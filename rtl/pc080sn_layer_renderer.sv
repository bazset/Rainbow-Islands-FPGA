//============================================================================
// pc080sn_layer_renderer.sv
// One PC080SN tile layer (BG or FG) for Rainbow Islands / Rastan-class boards.
//
// Dual line buffers: fill the next scanline while displaying the current one.
// Reads tile attributes/code from VRAM, fetches 4bpp GFX, applies scroll and
// optional per-line rowscroll. TRANSPARENT=1 for FG (pen 0 clear).
//
// H_LAST / V_TOTAL follow the shared Taito video timing used by this core.
//============================================================================

module pc080sn_layer_renderer #(
	parameter [14:0] TILE_BASE   = 15'd0,
	parameter [14:0] ROWSCROLL_BASE = 15'h2000,
	parameter        TRANSPARENT = 1'b0,
	parameter [9:0]  H_LAST      = 10'd423,
	parameter [9:0]  V_TOTAL     = 10'd263,
	parameter [8:0]  X_OFFSET    = 9'd16,
	parameter [8:0]  Y_OFFSET    = 9'd16,
	parameter [8:0]  Y_PIC_ADJ   = 9'd0
)
(
	input         clk_sys,
	input         reset,
	input   [9:0] hc,
	input   [9:0] vc,
	input   [8:0] scrollx,
	input   [8:0] scrolly,
	input   [8:0] y_adjust,
	input         y_scroll_neg,
	output reg [14:0] tile_rd_addr,
	input      [15:0] tile_rd_dout,
	output reg        gfx_rd_req,
	output reg [23:1] gfx_rd_addr,
	input             gfx_rd_ready,
	input      [15:0] gfx_rd_dout,
	output            pixel_valid,
	output     [10:0] pixel_pal_addr,
	output            dbg_lb_we,
	output            dbg_lb_we_nz,
	output            dbg_px_nz,
	output            dbg_attr_nz,
	output            dbg_code_nz,
	output      [2:0] dbg_state
);

//------------------------------------------------------------------------
// Dual line buffers: {valid, palette index[10:0]}
//------------------------------------------------------------------------
localparam H_VISIBLE = 320;
reg [11:0] linebuf0 [0:319];
reg [11:0] linebuf1 [0:319];
reg [11:0] q0, q1;
reg        disp_buf;
reg        lb_we;
reg [8:0]  lb_addr;
reg [11:0] lb_data;

always @(posedge clk_sys) begin
	if (lb_we &&  disp_buf) linebuf0[lb_addr] <= lb_data;
	q0 <= linebuf0[hc[8:0]];
end
always @(posedge clk_sys) begin
	if (lb_we && !disp_buf) linebuf1[lb_addr] <= lb_data;
	q1 <= linebuf1[hc[8:0]];
end

assign pixel_pal_addr = disp_buf ? q1[10:0] : q0[10:0];
assign dbg_lb_we = lb_we;
assign dbg_lb_we_nz = lb_we && (lb_data[10:0] != 11'd0);
assign dbg_px_nz   = lb_we && (lb_data[3:0]  != 4'd0);
assign dbg_attr_nz = lb_we && (lb_data[10:4] != 7'd0);
assign pixel_valid    = TRANSPARENT ? (disp_buf ? q1[11] : q0[11]) : 1'b1;
reg [5:0] tile_i;
reg [3:0] fstate;
localparam FS_IDLE      = 4'd0;
localparam FS_ATTR      = 4'd1;
localparam FS_CODE      = 4'd3;
localparam FS_ATTR_W    = 4'd2;
localparam FS_CODE_W    = 4'd4;
localparam FS_GFX0_REQ  = 4'd5;
localparam FS_GFX0_WAIT = 4'd6;
localparam FS_GFX1_WAIT = 4'd7;
localparam FS_WRITE     = 4'd8;
localparam FS_RS        = 4'd9;
localparam FS_RS_W      = 4'd10;
assign dbg_code_nz = (fstate == FS_GFX0_REQ) && (tile_rd_dout[13:0] != 14'd0);
assign dbg_state   = fstate[2:0];
reg        fetching;
reg [8:0]  eff_x_base, eff_y;
wire [9:0] next_line = (vc == V_TOTAL - 10'd1) ? 10'd0 : (vc + 10'd1);
wire [8:0] rs_raster = next_line[8:0] + Y_OFFSET;
wire [7:0] rs_line   = rs_raster[7:0];
reg [8:0] y_total_off;
always @(posedge clk_sys) y_total_off <= Y_OFFSET + Y_PIC_ADJ + y_adjust;

reg [5:0]  tile_x_start, tile_y;
reg [2:0]  subpixel;
reg [8:0]  attr_r;
reg        xflip_r, yflip_r;
reg [13:0] code_r;
reg [15:0] gfx_w0;
reg [3:0]  row_r;
wire        first_tile = (tile_i == 6'd0);
wire [5:0]  cur_tile_x_start = first_tile ? eff_x_base[8:3] : tile_x_start;
wire [5:0]  cur_tile_y       = first_tile ? eff_y[8:3]      : tile_y;
wire [5:0]  tcol       = (cur_tile_x_start + tile_i) & 6'h3f;
wire [11:0] tile_index = {cur_tile_y, tcol};
reg hc_was_zero;
always @(posedge clk_sys) hc_was_zero <= (hc == 10'd0);
wire line_start = (hc == 10'd0) && !hc_was_zero;
reg hc_was_last;
always @(posedge clk_sys) hc_was_last <= (hc == H_LAST);
wire swap_now = (hc == H_LAST) && !hc_was_last;
reg gfx_rd_ready_d;
always @(posedge clk_sys) gfx_rd_ready_d <= gfx_rd_ready;
wire gfx_rd_ready_re = gfx_rd_ready & ~gfx_rd_ready_d;
reg [3:0] px [0:7];
reg [2:0] wr_k;
reg [3:0] wr_px;
reg signed [9:0] dest_index;

always @(posedge clk_sys) begin
	if (reset) begin
		fstate     <= FS_IDLE;
		fetching   <= 1'b0;
		disp_buf   <= 1'b0;
		gfx_rd_req <= 1'b0;
		tile_rd_addr <= 15'd0;
		tile_x_start <= 6'd0;
		tile_y       <= 6'd0;
		subpixel     <= 3'd0;
		row_r        <= 4'd0;
		attr_r       <= 9'd0;
		code_r       <= 14'd0;
		xflip_r      <= 1'b0;
		yflip_r      <= 1'b0;
		gfx_w0       <= 16'd0;
		gfx_rd_addr  <= 23'd0;
		wr_k         <= 3'd0;
		lb_we        <= 1'b0;
		eff_x_base   <= 9'd0;
		eff_y        <= 9'd0;
	end else begin
		lb_we <= 1'b0;
		if (swap_now) begin
			disp_buf <= ~disp_buf;
		end

		case (fstate)

			FS_IDLE: begin
				if (line_start && !fetching) begin

					tile_rd_addr <= ROWSCROLL_BASE + {7'd0, rs_line};

					eff_y    <= ({1'b0, next_line[8:0]}
					             + (y_scroll_neg ? -{1'b0, scrolly}
					                             :  {1'b0, scrolly})
					             + {1'b0, y_total_off}) & 10'h1ff;
					fetching <= 1'b1;
					tile_i   <= 6'd0;
					fstate   <= FS_RS_W;
				end
			end

			FS_RS_W: fstate <= FS_RS;

			FS_RS: begin
				eff_x_base <= (scrollx + tile_rd_dout[8:0] + X_OFFSET) & 9'h1ff;
				fstate     <= FS_ATTR;
			end

			FS_ATTR: begin
				tile_x_start <= eff_x_base[8:3];
				subpixel     <= eff_x_base[2:0];
				tile_y       <= eff_y[8:3];
				row_r        <= eff_y[2:0];

				tile_rd_addr <= {tile_index, 1'b0} + TILE_BASE;
				fstate       <= FS_ATTR_W;
			end

			FS_ATTR_W: fstate <= FS_CODE;

			FS_CODE: begin
				attr_r       <= tile_rd_dout[8:0];

				xflip_r      <= tile_rd_dout[14];
				yflip_r      <= tile_rd_dout[15];
				tile_rd_addr <= {tile_index, 1'b1} + TILE_BASE;
				fstate       <= FS_CODE_W;
			end

			FS_CODE_W: fstate <= FS_GFX0_REQ;

			FS_GFX0_REQ: begin
				code_r <= tile_rd_dout[13:0];

				gfx_rd_addr <= {tile_rd_dout[13:0], 4'd0} +
				               {20'd0, (yflip_r ? (4'd7 - row_r) : row_r)} * 24'd2;
				gfx_rd_req  <= ~gfx_rd_req;
				fstate      <= FS_GFX0_WAIT;
			end

			FS_GFX0_WAIT: begin
				if (gfx_rd_ready_re) begin
					gfx_w0      <= gfx_rd_dout;
					gfx_rd_addr <= gfx_rd_addr + 24'd1;
					gfx_rd_req  <= ~gfx_rd_req;
					fstate      <= FS_GFX1_WAIT;
				end
			end

			FS_GFX1_WAIT: begin
				if (gfx_rd_ready_re) begin
					px[0] = gfx_w0[15:12]; px[1] = gfx_w0[11:8];
					px[2] = gfx_w0[7:4];   px[3] = gfx_w0[3:0];
					px[4] = gfx_rd_dout[15:12]; px[5] = gfx_rd_dout[11:8];
					px[6] = gfx_rd_dout[7:4];   px[7] = gfx_rd_dout[3:0];
					fstate <= FS_WRITE;
				end
			end

			FS_WRITE: begin
				wr_px = xflip_r ? px[3'd7 - wr_k] : px[wr_k];
				dest_index = $signed({4'd0, tile_i, 3'd0}) + $signed({7'd0, wr_k}) - $signed({7'd0, subpixel});
				if (dest_index >= 0 && dest_index < H_VISIBLE) begin
					lb_we   <= 1'b1;
					lb_addr <= dest_index[8:0];
					lb_data <= {(TRANSPARENT ? (wr_px != 4'd0) : 1'b1), attr_r[6:0], wr_px};
				end
				if (wr_k != 3'd7) begin
					wr_k <= wr_k + 3'd1;
				end else begin
					wr_k <= 3'd0;
					if (tile_i == 6'd40) begin
						fetching <= 1'b0;
						fstate   <= FS_IDLE;
					end else begin
						tile_i <= tile_i + 6'd1;
						fstate <= FS_ATTR;
					end
				end
			end

			default: fstate <= FS_IDLE;
		endcase
	end
end

endmodule
