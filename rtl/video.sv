module video #(

	parameter int V_VISIBLE_P = 224,
	parameter int V_FRONT_P   = 7,
	parameter int V_SYNC_P    = 3,
	parameter int V_BACK_P    = 29,
	parameter int H_FRONT_P   = 44,
	parameter int H_SYNC_P    = 27,
	parameter int H_BACK_P    = 33
)
(
	input        clk_sys,
	input        ce_pix,
	input        reset,
	output       HBlank,
	output       VBlank,
	output       HSync,
	output       VSync,
	output [8:0] hpos,
	output [8:0] vpos
);

localparam H_VISIBLE = 320;
localparam H_FRONT   = H_FRONT_P;
localparam H_SYNC    = H_SYNC_P;
localparam H_BACK    = H_BACK_P;
localparam H_TOTAL   = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
localparam V_VISIBLE = V_VISIBLE_P;
localparam V_FRONT   = V_FRONT_P;
localparam V_SYNC    = V_SYNC_P;
localparam V_BACK    = V_BACK_P;
localparam V_TOTAL   = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;
reg [9:0] hc;
reg [9:0] vc;

always @(posedge clk_sys) begin
	if (reset) begin
		hc <= 0;
		vc <= 0;
	end else if (ce_pix) begin
		if (hc == H_TOTAL - 1) begin
			hc <= 0;
			vc <= (vc == V_TOTAL - 1) ? 10'd0 : vc + 1'd1;
		end else begin
			hc <= hc + 1'd1;
		end
	end
end

localparam [9:0] HS_START = H_VISIBLE + H_FRONT;
localparam [9:0] VS_START = V_VISIBLE + V_FRONT;
wire hblank_w = (hc >= H_VISIBLE);
wire vblank_w = (vc >= V_VISIBLE);
wire hsync_w  = (hc >= HS_START) && (hc < HS_START + H_SYNC);
wire vsync_w  = (vc >= VS_START) && (vc < VS_START + V_SYNC);
assign HBlank = hblank_w;
assign VBlank = vblank_w;
assign HSync  = hsync_w;
assign VSync  = vsync_w;
assign hpos = hc[8:0];
assign vpos = vc[8:0];

endmodule
