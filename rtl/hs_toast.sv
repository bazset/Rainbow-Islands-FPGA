module hs_toast #(
	parameter [9:0] H_VISIBLE = 10'd320,
	parameter [9:0] V_VISIBLE = 10'd224,
	parameter integer HOLD_CLKS = 48000000
)
(
	input             clk_sys,
	input       [8:0] hpos,
	input       [8:0] vpos,
	input             busy_load,
	input             busy_save,
	output            overlay_on,
	output     [23:0] overlay_rgb
);

localparam integer HOLD_W = $clog2(HOLD_CLKS + 1);
reg [HOLD_W-1:0] hold;
reg              is_save;
wire busy = busy_load | busy_save;

always @(posedge clk_sys) begin
	if (busy) begin
		hold    <= HOLD_CLKS[HOLD_W-1:0];

		is_save <= busy_save;
	end
	else if (hold != 0) hold <= hold - 1'b1;
end

wire showing = (hold != 0);
localparam integer COLS   = 20;
localparam integer TEXT_W = COLS * 8;
localparam integer TEXT_H = 8;
localparam integer PAD    = 4;
localparam integer BORDER = 2;
localparam integer BOX_X0 = 8;
localparam integer BOX_X1 = BOX_X0 + TEXT_W + 2*PAD - 1;
localparam integer BOX_Y1 = V_VISIBLE - 8 - 1;
localparam integer BOX_Y0 = BOX_Y1 - (TEXT_H + 2*PAD) + 1;
localparam integer TEXT_X = BOX_X0 + PAD;
localparam integer TEXT_Y = BOX_Y0 + PAD;
localparam [159:0] MSG_LOAD = "  LOADING SCORES... ";
localparam [159:0] MSG_SAVE = "  SAVING SCORES...  ";

(* ramstyle = "M10K" *) reg [7:0] font_rom [0:767];
initial $readmemh("rtl/font8x8.hex", font_rom);

wire [9:0] hx = {1'b0, hpos};
wire [9:0] vy = {1'b0, vpos};
wire in_box    = showing &&
                 (hx >= BOX_X0[9:0]) && (hx <= BOX_X1[9:0]) &&
                 (vy >= BOX_Y0[9:0]) && (vy <= BOX_Y1[9:0]);

wire in_border = in_box &&
                 ((hx <  BOX_X0[9:0] + BORDER) || (hx > BOX_X1[9:0] - BORDER) ||
                  (vy <  BOX_Y0[9:0] + BORDER) || (vy > BOX_Y1[9:0] - BORDER));

wire in_text   = in_box &&
                 (hx >= TEXT_X[9:0]) && (hx < TEXT_X[9:0] + TEXT_W) &&
                 (vy >= TEXT_Y[9:0]) && (vy < TEXT_Y[9:0] + TEXT_H);

wire [9:0] tx = hx - TEXT_X[9:0];
wire [9:0] ty = vy - TEXT_Y[9:0];
wire [4:0] col = tx[7:3];
wire [2:0] cx  = tx[2:0];
wire [2:0] cy  = ty[2:0];
wire [7:0] ch = is_save ? MSG_SAVE[159 - {col, 3'b000} -: 8]
                        : MSG_LOAD[159 - {col, 3'b000} -: 8];

wire       ch_valid = (ch >= 8'h20) && (ch <= 8'h7F);
wire [6:0] ch_idx   = ch_valid ? (ch[6:0] - 7'h20) : 7'd0;
wire [9:0] font_a   = {ch_idx, cy};
reg [7:0] font_row;
reg [2:0] cx_q;
reg       in_box_q, in_border_q, in_text_q;

always @(posedge clk_sys) begin
	font_row    <= font_rom[font_a];
	cx_q        <= cx;
	in_box_q    <= in_box;
	in_border_q <= in_border;
	in_text_q   <= in_text;
end

wire pixel_on = in_text_q && font_row[3'd7 - cx_q];
assign overlay_on  = in_box_q;
assign overlay_rgb = pixel_on      ? 24'hFFFFFF :
                     in_border_q   ? 24'h4080FF :
                                     24'h000030;

endmodule
