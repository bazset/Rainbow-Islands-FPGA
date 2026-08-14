`ifndef BUILD_DATE
`include "build_id.v"
`endif

module pause_overlay #(
	parameter [9:0] H_VISIBLE = 10'd320,
	parameter [9:0] V_VISIBLE = 10'd224,
	parameter [9:0] V_FIRST   = 10'd0,
	parameter bit   ROTATE    = 1'b0,
	parameter [3:0] CELL_W    = 4'd6
)
(
	input             clk_sys,
	input       [8:0] hpos,
	input       [8:0] vpos,
	input             pause,
	output            overlay_on,
	output     [23:0] overlay_rgb
);

wire [9:0] vv = {1'b0, vpos} - V_FIRST;
wire [9:0] u  = ROTATE ? vv : {1'b0, hpos};
wire [9:0] v  = ROTATE ? ((H_VISIBLE - 10'd1) - {1'b0, hpos}) : vv;
localparam [9:0] U_SIZE = ROTATE ? V_VISIBLE : H_VISIBLE;
localparam [9:0] V_SIZE = ROTATE ? H_VISIBLE : V_VISIBLE;
localparam integer COLS   = 32;
localparam integer ROWS   = 8;
localparam integer TEXT_W = COLS * CELL_W;
localparam integer TEXT_H = ROWS * 8;
localparam integer TEXT_X = (U_SIZE - TEXT_W) / 2;
localparam integer TEXT_Y = (V_SIZE - TEXT_H) / 2;
localparam integer PAD    = 8;
localparam integer BOX_X0 = TEXT_X - PAD;
localparam integer BOX_X1 = TEXT_X + TEXT_W + PAD - 1;
localparam integer BOX_Y0 = TEXT_Y - PAD;
localparam integer BOX_Y1 = TEXT_Y + TEXT_H + PAD - 1;
localparam integer BORDER = 2;
localparam [255:0] L0 = "             PAUSED             ";
localparam [255:0] L1 = "                                ";
localparam [255:0] L2 = "        RAINBOW ISLANDS         ";
localparam [255:0] L3 = "       MiSTer FPGA CORE         ";
localparam [255:0] L4 = {"      VERSION RI-", `BUILD_DATE, "      "};
localparam [255:0] L5 = "                                ";
localparam [255:0] L6 = "https://www.patreon.com/c/bazset";
localparam [255:0] L7 = "                                ";

(* ramstyle = "M10K" *) reg [7:0] font_rom [0:767];
initial $readmemh("rtl/font8x8.hex", font_rom);

wire in_box    = pause &&
                 (u >= BOX_X0) && (u <= BOX_X1) &&
                 (v >= BOX_Y0) && (v <= BOX_Y1);

wire in_border = in_box &&
                 ((u <  BOX_X0 + BORDER) || (u > BOX_X1 - BORDER) ||
                  (v <  BOX_Y0 + BORDER) || (v > BOX_Y1 - BORDER));

wire in_text   = in_box &&
                 (u >= TEXT_X) && (u < TEXT_X + TEXT_W) &&
                 (v >= TEXT_Y) && (v < TEXT_Y + TEXT_H);

wire [9:0] tx = u - TEXT_X[9:0];
wire [9:0] ty = v - TEXT_Y[9:0];
reg [9:0] tx1, ty1;
reg       in_box1, in_border1, in_text1;

always @(posedge clk_sys) begin
	tx1       <= tx;
	ty1       <= ty;
	in_box1   <= in_box;
	in_border1<= in_border;
	in_text1  <= in_text;
end

localparam integer CW = CELL_W;

(* ramstyle = "M10K" *) reg [7:0] cell_lut [0:255];
integer ci;
initial begin
	for (ci = 0; ci < 256; ci = ci + 1)
		cell_lut[ci] = { 5'((ci / CW) > 31 ? 31 : (ci / CW)), 3'(ci % CW) };
end

wire [7:0] cell_idx = in_text1 ? tx1[7:0] : 8'd0;
reg [7:0] cell_q;
wire [4:0] col_q = cell_q[7:3];
wire [2:0] cx_r  = cell_q[2:0];
reg [2:0] row_r, cy_r;
reg       in_box2, in_border2, in_text2;

always @(posedge clk_sys) begin
	cell_q    <= cell_lut[cell_idx];
	row_r     <= ty1[5:3];
	cy_r      <= ty1[2:0];
	in_box2   <= in_box1;
	in_border2<= in_border1;
	in_text2  <= in_text1;
end

reg [7:0] ch;
always @(*) begin
	case (row_r)
		3'd0:    ch = L0[255 - {col_q, 3'b000} -: 8];
		3'd1:    ch = L1[255 - {col_q, 3'b000} -: 8];
		3'd2:    ch = L2[255 - {col_q, 3'b000} -: 8];
		3'd3:    ch = L3[255 - {col_q, 3'b000} -: 8];
		3'd4:    ch = L4[255 - {col_q, 3'b000} -: 8];
		3'd5:    ch = L5[255 - {col_q, 3'b000} -: 8];
		3'd6:    ch = L6[255 - {col_q, 3'b000} -: 8];
		default: ch = L7[255 - {col_q, 3'b000} -: 8];
	endcase
end

wire        ch_valid = (ch >= 8'h20) && (ch <= 8'h7F);
wire  [6:0] ch_idx   = ch_valid ? (ch[6:0] - 7'h20) : 7'd0;
wire  [9:0] font_a   = {ch_idx, cy_r};
reg [7:0] font_row;
reg [2:0] cx_q;
reg       in_box_q, in_border_q, in_text_q;
reg [2:0] row_q;

always @(posedge clk_sys) begin
	font_row    <= font_rom[font_a];
	cx_q        <= cx_r;
	in_box_q    <= in_box2;
	in_border_q <= in_border2;
	in_text_q   <= in_text2;
	row_q       <= row_r;
end

wire pixel_on = in_text_q && font_row[3'd7 - cx_q];
localparam [23:0] C_FILL   = 24'h101028;
localparam [23:0] C_BORDER = 24'hF0F0F0;
localparam [23:0] C_TITLE  = 24'hFFE060;
localparam [23:0] C_TEXT   = 24'hFFFFFF;
localparam [23:0] C_LINK   = 24'h80D0FF;
assign overlay_on  = in_box_q;
assign overlay_rgb = in_border_q ? C_BORDER :
                     !pixel_on   ? C_FILL   :
                     (row_q == 3'd0) ? C_TITLE :
                     (row_q == 3'd6) ? C_LINK  :
                                       C_TEXT;

endmodule
