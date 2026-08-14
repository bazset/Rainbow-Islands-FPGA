module ym2203_wrapper
(
	input        clk_sys,
	input        reset,
	input        ym_reg_cs,
	input        ym_data_cs,
	input        cpu_wr_n,
	input  [7:0] din,
	output [7:0] dout,
	output       irq_req,
	input  [7:0] dswa,
	input  [7:0] dswb,
	input        pause,
	output       cen_o,
	output signed [15:0] audio_l,
	output signed [15:0] audio_r
);

reg [3:0] div_cnt = 4'd0;

always @(posedge clk_sys) begin
	div_cnt <= (div_cnt == 4'd11) ? 4'd0 : div_cnt + 4'd1;
end
wire cen = (div_cnt == 4'd0);
assign cen_o = cen;
wire ym_sel = ym_reg_cs | ym_data_cs;
wire cs_n_i = ~ym_sel;
wire wr_n_i = cpu_wr_n;
wire addr_i = ym_data_cs;
wire irq_n;
wire signed [15:0] snd;

jt03 jt03_inst
(
	.rst     (reset),
	.clk     (clk_sys),
	.cen     (cen & ~pause),
	.din     (din),
	.addr    (addr_i),
	.cs_n    (cs_n_i),
	.wr_n    (wr_n_i),
	.dout    (dout),
	.irq_n   (irq_n),
	.IOA_in  (dswa),
	.IOB_in  (dswb),
	.IOA_out (),
	.IOB_out (),
	.IOA_oe  (),
	.IOB_oe  (),
	.psg_A   (),
	.psg_B   (),
	.psg_C   (),
	.fm_snd  (),
	.psg_snd (),
	.snd        (snd),
	.snd_sample (),
	.debug_view ()
);

assign irq_req = ~irq_n;
assign audio_l = snd;
assign audio_r = snd;

endmodule
