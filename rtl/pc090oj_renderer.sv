//============================================================================
// pc090oj_renderer.sv
// PC090OJ sprite renderer for Rainbow Islands / Rastan-class boards.
//
// Dual line buffers; sprites processed during the line for the *next* display
// line. Uses burst GFX reads (4 words) when the arbiter supports it.
// COLBANK_W is 7 for Rainbow Islands, 9 for Volfied-style banking.
// Priority / opacity: first write to a pixel wins (MAME-style for this chip).
//============================================================================

module pc090oj_renderer #(
	parameter [9:0] H_LAST = 10'd423,
	parameter int COLBANK_W = 7,
	parameter [8:0] Y_OFFSET = 9'd16
)
(
	input         clk_sys,
	input         reset,
	input   [9:0] hc,
	input   [9:0] vc,
	input  [15:0] sprite_ctrl,
	input         ctrl_flip,
	output reg [12:0] sp_rd_addr,
	input      [15:0] sp_rd_dout,
	output reg        gfx_rd_req,
	output reg [23:1] gfx_rd_addr,
	input             gfx_rd_ready,
	input      [15:0] gfx_rd_dout,
	output            gfx_rd_burst,
	input      [63:0] gfx_rd_dout4,
	output            pixel_valid,
	output     [12:0] pixel_pal_addr
);

//------------------------------------------------------------------------
// Dual line buffers: {valid, palette[PAL_W-1:0]}
//------------------------------------------------------------------------
localparam H_VISIBLE = 320;
localparam int PAL_W = COLBANK_W + 4;
localparam int LB_W  = PAL_W + 1;
reg [LB_W-1:0] linebuf0 [0:319];
reg [LB_W-1:0] linebuf1 [0:319];
reg [LB_W-1:0] q0, q1;
reg        disp_buf;
reg        lb_we;
reg [8:0]  lb_addr;
reg [LB_W-1:0] lb_data;

always @(posedge clk_sys) begin
	if (lb_we &&  disp_buf) linebuf0[lb_addr] <= lb_data;
	q0 <= linebuf0[hc[8:0]];
end
always @(posedge clk_sys) begin
	if (lb_we && !disp_buf) linebuf1[lb_addr] <= lb_data;
	q1 <= linebuf1[hc[8:0]];
end

assign pixel_valid    = disp_buf ? q1[LB_W-1] : q0[LB_W-1];
assign pixel_pal_addr = disp_buf ? {{(13-PAL_W){1'b0}}, q1[PAL_W-1:0]}
                                 : {{(13-PAL_W){1'b0}}, q0[PAL_W-1:0]};

wire [COLBANK_W-1:0] sprite_colbank = (COLBANK_W == 9)
        ? {1'b1, sprite_ctrl[5:2], 4'd0}
        : {sprite_ctrl[7:5], 4'd0};

reg gfx_rd_ready_d;
always @(posedge clk_sys) gfx_rd_ready_d <= gfx_rd_ready;
wire gfx_rd_ready_re = gfx_rd_ready & ~gfx_rd_ready_d;
reg hc_was_last;
always @(posedge clk_sys) hc_was_last <= (hc == H_LAST);
wire swap_now = (hc == H_LAST) && !hc_was_last;
reg hc_was_zero;
always @(posedge clk_sys) hc_was_zero <= (hc == 10'd0);
wire line_start = (hc == 10'd0) && !hc_was_zero;
reg [8:0] sp_i;
reg [H_VISIBLE-1:0] written;
reg [9:0] clr_i;
reg [4:0] fstate;
reg       req_outstanding = 1'b0;
localparam FS_IDLE      = 5'd0;
localparam FS_DRAIN     = 5'd20;
localparam FS_CLEAR     = 5'd13;
localparam FS_Y_ADDR    = 5'd1;
localparam FS_Y_CAP     = 5'd2;
localparam FS_W0        = 5'd3;
localparam FS_W1        = 5'd4;
localparam FS_W2        = 5'd14;
localparam FS_W3        = 5'd15;
localparam FS_W0_W      = 5'd16;
localparam FS_W2_W      = 5'd17;
localparam FS_W3_W      = 5'd18;
localparam FS_DECIDE    = 5'd5;
localparam FS_GFX_START = 5'd6;
localparam FS_GFX_WAIT  = 5'd7;
localparam FS_WRITE     = 5'd11;
localparam FS_NEXT      = 5'd12;
assign gfx_rd_burst = 1'b1;
reg        fetching;
reg [8:0]  target_line;
reg [15:0] raw_w0, raw_w1, raw_w2, raw_w3;
reg signed [9:0] final_sx;
reg        final_xflip;
reg [3:0]  row_in_sprite;
reg [3:0]  px [0:15];
reg [4:0] wr_k;
reg [3:0] wr_px;
reg signed [9:0] dest_index;
reg signed [9:0] ry, rx, sy, sx;
reg yfl, xfl;
reg signed [9:0] line_off;
reg signed [9:0] ry_e, sy_e, loff_e;

function signed [9:0] unwrap9(input [8:0] v);
	unwrap9 = (v > 9'h140) ? ($signed({1'b0,v}) - $signed(11'sd512))
	                       : $signed({1'b0,v});
endfunction

always @(posedge clk_sys) begin
	if (reset) begin
		fstate      <= FS_IDLE;
		fetching    <= 1'b0;
		disp_buf    <= 1'b0;
		gfx_rd_req  <= 1'b0;
		req_outstanding <= 1'b0;
		sp_rd_addr  <= 13'd0;
		gfx_rd_addr <= 23'd0;
		wr_k        <= 5'd0;
		lb_we       <= 1'b0;
	end else begin
		lb_we <= 1'b0;
		if (swap_now) disp_buf <= ~disp_buf;
		if (gfx_rd_ready_re) req_outstanding <= 1'b0;
		if (line_start) begin

			target_line <= (vc[8:0] == 9'd223) ? Y_OFFSET
			                                   : (vc[8:0] + 9'd1 + Y_OFFSET);
			fetching    <= 1'b1;
			clr_i       <= 10'd0;
			wr_k        <= 5'd0;
			fstate      <= req_outstanding ? FS_DRAIN : FS_CLEAR;
		end else
		case (fstate)
			FS_IDLE: begin
			end

			FS_DRAIN: if (gfx_rd_ready_re) begin
				clr_i  <= 10'd0;
				fstate <= FS_CLEAR;
			end

			FS_CLEAR: begin

				lb_we   <= 1'b1;
				lb_addr <= clr_i[8:0];
				lb_data <= {LB_W{1'b0}};
				written[clr_i[8:0]] <= 1'b0;
				if (clr_i == 10'd319) begin

					sp_i       <= 9'd0;
					sp_rd_addr <= {9'd0, 2'd1};
					fstate     <= FS_Y_ADDR;
				end else begin
					clr_i <= clr_i + 10'd1;
				end
			end

			FS_Y_ADDR: fstate <= FS_Y_CAP;

			FS_Y_CAP: begin
				raw_w1 <= sp_rd_dout;
				sp_rd_addr <= {sp_i, 2'd0};
				fstate <= FS_W0_W;
			end

			FS_W0_W: begin

				ry_e = unwrap9(raw_w1[8:0]);
				sy_e = ctrl_flip ? ry_e : ($signed(10'sd256) - ry_e - 10'sd16);
				loff_e = $signed({1'b0,target_line}) - sy_e;
				if (loff_e >= 0 && loff_e < 10'sd16) begin
					fstate <= FS_W0;
				end else begin
					fstate <= FS_NEXT;
				end
			end

			FS_W0: begin
				raw_w0     <= sp_rd_dout;
				sp_rd_addr <= {sp_i, 2'd2};
				fstate     <= FS_W2_W;
			end
			FS_W2_W: fstate <= FS_W2;
			FS_W2: begin
				raw_w2     <= sp_rd_dout;
				sp_rd_addr <= {sp_i, 2'd3};
				fstate     <= FS_W3_W;
			end
			FS_W3_W: fstate <= FS_W3;
			FS_W3: begin
				raw_w3 <= sp_rd_dout;
				fstate <= FS_DECIDE;
			end

			FS_DECIDE: begin

				ry = unwrap9(raw_w1[8:0]);
				rx = unwrap9(raw_w3[8:0]);
				yfl = ctrl_flip ? raw_w0[15] : ~raw_w0[15];
				xfl = ctrl_flip ? raw_w0[14] : ~raw_w0[14];
				sy = ctrl_flip ? ry : ($signed(10'sd256) - ry - 10'sd16);
				sx = ctrl_flip ? rx : ($signed(10'sd320) - rx - 10'sd16);
				final_xflip <= xfl;
				final_sx    <= sx;
				line_off = $signed({1'b0,target_line}) - sy;
				if (line_off >= 0 && line_off < 10'sd16) begin
					row_in_sprite <= yfl ? (4'd15 - line_off[3:0]) : line_off[3:0];
					fstate <= FS_GFX_START;
				end else begin
					fstate <= FS_NEXT;
				end
			end

			FS_GFX_START: begin

				gfx_rd_addr <= {raw_w2[12:0], 6'd0} + {19'd0, row_in_sprite} * 24'd4;
				gfx_rd_req  <= ~gfx_rd_req; req_outstanding <= 1'b1;
				fstate      <= FS_GFX_WAIT;
			end

			FS_GFX_WAIT: if (gfx_rd_ready_re) begin
				px[0] =gfx_rd_dout4[63:60]; px[1] =gfx_rd_dout4[59:56];
				px[2] =gfx_rd_dout4[55:52]; px[3] =gfx_rd_dout4[51:48];
				px[4] =gfx_rd_dout4[47:44]; px[5] =gfx_rd_dout4[43:40];
				px[6] =gfx_rd_dout4[39:36]; px[7] =gfx_rd_dout4[35:32];
				px[8] =gfx_rd_dout4[31:28]; px[9] =gfx_rd_dout4[27:24];
				px[10]=gfx_rd_dout4[23:20]; px[11]=gfx_rd_dout4[19:16];
				px[12]=gfx_rd_dout4[15:12]; px[13]=gfx_rd_dout4[11:8];
				px[14]=gfx_rd_dout4[7:4];   px[15]=gfx_rd_dout4[3:0];
				fstate <= FS_WRITE;
			end

			FS_WRITE: begin
				wr_px = final_xflip ? px[4'd15 - wr_k[3:0]] : px[wr_k[3:0]];
				dest_index = final_sx + $signed({6'd0, wr_k[3:0]});
				if (dest_index >= 0 && dest_index < H_VISIBLE && wr_px != 4'd0
				    && !written[dest_index[8:0]]) begin
					lb_we   <= 1'b1;
					lb_addr <= dest_index[8:0];
					lb_data <= {1'b1,
					            sprite_colbank | {{(COLBANK_W-4){1'b0}}, raw_w0[3:0]},
					            wr_px};
					written[dest_index[8:0]] <= 1'b1;
				end
				if (wr_k != 5'd15) begin
					wr_k <= wr_k + 5'd1;
				end else begin
					wr_k   <= 5'd0;
					fstate <= FS_NEXT;
				end
			end

			FS_NEXT: begin
				if (sp_i == 9'd255) begin
					fetching <= 1'b0;
					fstate   <= FS_IDLE;
				end else begin
					sp_i       <= sp_i + 9'd1;
					sp_rd_addr <= {sp_i + 9'd1, 2'd1};
					fstate     <= FS_Y_ADDR;
				end
			end

			default: fstate <= FS_IDLE;
		endcase
	end
end

endmodule
