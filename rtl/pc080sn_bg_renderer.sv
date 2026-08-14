module pc080sn_bg_renderer
(
	input         clk_sys,
	input         reset,
	input   [9:0] hc,
	input   [9:0] vc,
	input   [8:0] scrollx,
	input   [8:0] scrolly,
	output reg [14:0] tile_rd_addr,
	input      [15:0] tile_rd_dout,
	output reg        gfx_rd_req,
	output reg [23:1] gfx_rd_addr,
	input             gfx_rd_ready,
	input      [15:0] gfx_rd_dout,
	output     [10:0] pixel_pal_addr
);

localparam H_VISIBLE = 320;
reg [10:0] linebuf0 [0:319];
reg [10:0] linebuf1 [0:319];
reg        disp_buf;
assign pixel_pal_addr = disp_buf ? linebuf1[hc[8:0]] : linebuf0[hc[8:0]];
reg [5:0] tile_i;
reg [2:0] fstate;
localparam FS_IDLE      = 3'd0;
localparam FS_ATTR      = 3'd1;
localparam FS_CODE      = 3'd2;
localparam FS_GFX0_REQ  = 3'd3;
localparam FS_GFX0_WAIT = 3'd4;
localparam FS_GFX1_WAIT = 3'd5;
localparam FS_WRITE     = 3'd6;
reg        fetching;
reg [8:0]  eff_x_base, eff_y;
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
reg hc_was_405;
always @(posedge clk_sys) hc_was_405 <= (hc == 10'd405);
wire swap_now = (hc == 10'd405) && !hc_was_405;
reg gfx_rd_ready_d;
always @(posedge clk_sys) gfx_rd_ready_d <= gfx_rd_ready;
wire gfx_rd_ready_re = gfx_rd_ready & ~gfx_rd_ready_d;

integer k;
reg [3:0] px [0:7];
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
		eff_x_base   <= 9'd0;
		eff_y        <= 9'd0;
	end else begin
		if (swap_now) begin
			disp_buf <= ~disp_buf;
		end

		case (fstate)
			FS_IDLE: begin
				if (line_start && !fetching) begin
					eff_x_base <= scrollx & 9'h1ff;

					eff_y    <= ({1'b0,vc[8:0]} + 10'd1 + {1'b0,scrolly}) & 10'h1ff;
					fetching <= 1'b1;
					tile_i   <= 6'd0;
					fstate   <= FS_ATTR;
				end
			end

			FS_ATTR: begin
				tile_x_start <= eff_x_base[8:3];
				subpixel     <= eff_x_base[2:0];
				tile_y       <= eff_y[8:3];
				row_r        <= eff_y[2:0];
				tile_rd_addr <= {tile_y, tcol, 1'b0};
				fstate       <= FS_CODE;
			end

			FS_CODE: begin
				attr_r       <= tile_rd_dout[8:0];
				xflip_r      <= tile_rd_dout[14];
				yflip_r      <= tile_rd_dout[15];
				tile_rd_addr <= {tile_y, tcol, 1'b1};
				fstate       <= FS_GFX0_REQ;
			end

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
				for (k = 0; k < 8; k = k + 1) begin
					dest_index = $signed({4'd0, tile_i, 3'd0}) + k - {7'd0, subpixel};
					if (dest_index >= 0 && dest_index < H_VISIBLE) begin
						if (disp_buf)
							linebuf0[dest_index[8:0]] <= {attr_r[6:0], xflip_r ? px[7-k] : px[k]};
						else
							linebuf1[dest_index[8:0]] <= {attr_r[6:0], xflip_r ? px[7-k] : px[k]};
					end
				end
				if (tile_i == 6'd40) begin
					fetching <= 1'b0;
					fstate   <= FS_IDLE;
				end else begin
					tile_i <= tile_i + 6'd1;
					fstate <= FS_ATTR;
				end
			end

			default: fstate <= FS_IDLE;
		endcase
	end
end

endmodule
