module z80_sound_wrapper
(
	input        clk_sys,
	input        reset,
	output [15:0] cpu_a,
	input   [7:0] cpu_din,
	output  [7:0] cpu_dout,
	output        cpu_mreq_n,
	output        cpu_iorq_n,
	output        cpu_rd_n,
	output        cpu_wr_n,
	input        int_req,
	input        nmi_req,
	input        cpu_reset_req,
	input        pause,
	output       cpu_ce

);

reg [3:0] div_cnt = 4'd0;

always @(posedge clk_sys) begin
	div_cnt <= (div_cnt == 4'd11) ? 4'd0 : div_cnt + 4'd1;
end
wire cen = (div_cnt == 4'd0) & ~pause;
assign cpu_ce = cen;
wire reset_n = ~(reset | cpu_reset_req);
wire m1_n, iorq_n_i, rd_n_i;
wire int_ack_cycle = ~m1_n & ~iorq_n_i;
wire [7:0] di_to_core = int_ack_cycle ? 8'hFF : cpu_din;
assign cpu_iorq_n = iorq_n_i;
assign cpu_rd_n   = rd_n_i;

T80s t80_inst
(
	.RESET_n (reset_n),
	.CLK     (clk_sys),
	.CEN     (cen),
	.WAIT_n  (1'b1),
	.INT_n   (~int_req),
	.NMI_n   (~nmi_req),
	.BUSRQ_n (1'b1),
	.M1_n    (m1_n),
	.MREQ_n  (cpu_mreq_n),
	.IORQ_n  (iorq_n_i),
	.RD_n    (rd_n_i),
	.WR_n    (cpu_wr_n),
	.RFSH_n  (),
	.HALT_n  (),
	.BUSAK_n (),
	.OUT0    (1'b0),
	.A       (cpu_a),
	.DI      (di_to_core),
	.DO      (cpu_dout)
);

endmodule
