module cpu68k_wrapper
(
	input             clk_sys,
	input             reset,
	output     [23:1] cpu_a,
	input      [15:0] cpu_din,
	output     [15:0] cpu_dout,
	output            cpu_as_n,
	output            cpu_rw,
	output            cpu_uds_n,
	output            cpu_lds_n,
	input             cpu_dtack_n,
	input             vblank_irq,
	input             pause,
	output            cpu_ce_r,
	output            cpu_ce_f
);

reg [2:0] phase_cnt = 3'd0;

always @(posedge clk_sys) begin
	phase_cnt <= (phase_cnt == 3'd5) ? 3'd0 : phase_cnt + 3'd1;
end

wire enPhi1 = (phase_cnt == 3'd5) & ~pause;
wire enPhi2 = (phase_cnt == 3'd2) & ~pause;
assign cpu_ce_r = enPhi1;
assign cpu_ce_f = enPhi2;
wire fc0, fc1, fc2;
wire bg_n, oresetn, ohaltedn;
reg irq4_pending;
wire fc_is_iack = (fc2 & fc1 & fc0);
wire int_ack_cycle = fc_is_iack & ~cpu_as_n;

always @(posedge clk_sys) begin
	if (reset) begin
		irq4_pending <= 1'b0;
	end else begin
		if (vblank_irq)          irq4_pending <= 1'b1;
		else if (int_ack_cycle)  irq4_pending <= 1'b0;
	end
end

wire [2:0] ipl_n = irq4_pending ? 3'b011 : 3'b111;
wire vpa_n_i = ~int_ack_cycle;
wire dtack_n_to_core = int_ack_cycle ? 1'b1 : cpu_dtack_n;

fx68k fx68k_inst
(
	.clk       (clk_sys),
	.HALTn     (1'b1),
	.extReset  (reset),
	.pwrUp     (reset),
	.enPhi1    (enPhi1),
	.enPhi2    (enPhi2),
	.eRWn      (cpu_rw),
	.ASn       (cpu_as_n),
	.LDSn      (cpu_lds_n),
	.UDSn      (cpu_uds_n),
	.E         (),
	.VMAn      (),
	.FC0       (fc0),
	.FC1       (fc1),
	.FC2       (fc2),
	.BGn       (bg_n),
	.oRESETn   (oresetn),
	.oHALTEDn  (ohaltedn),
	.DTACKn    (dtack_n_to_core),
	.VPAn      (vpa_n_i),
	.BERRn     (1'b1),
	.BRn       (1'b1),
	.BGACKn    (1'b1),
	.IPL0n     (ipl_n[0]),
	.IPL1n     (ipl_n[1]),
	.IPL2n     (ipl_n[2]),
	.iEdb      (cpu_din),
	.oEdb      (cpu_dout),
	.eab       (cpu_a)
);

endmodule
