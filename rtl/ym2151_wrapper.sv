module ym2151_wrapper
(
	input        clk_sys,
	input        reset,
	input        ym_reg_cs,
	input        ym_data_cs,
	input        cpu_wr_n,
	input  [7:0] din,
	output [7:0] dout,
	output       irq_req,
	output [1:0] rom_bank,
	input        snd_test,
	input        pause,
	input        scr_en,
	input        scr_cs_n,
	input        scr_wr_n,
	input        scr_a0,
	input  [7:0] scr_din,
	output       cen_o,
	output signed [15:0] audio_l,
	output signed [15:0] audio_r
);

reg [3:0] div_cnt = 4'd0;

always @(posedge clk_sys) begin
	div_cnt <= (div_cnt == 4'd11) ? 4'd0 : div_cnt + 4'd1;
end
wire cen = (div_cnt == 4'd0);
reg cen_p1_toggle = 1'b0;
always @(posedge clk_sys) begin
	if (reset) cen_p1_toggle <= 1'b0;
	else if (cen) cen_p1_toggle <= ~cen_p1_toggle;
end
wire cen_p1 = cen & cen_p1_toggle;
localparam [1:0] YM_HOLD = 2'd3;
wire ym_sel    = ym_reg_cs | ym_data_cs;
wire z80_ym_wr = ym_sel & ~cpu_wr_n;
wire z80_ym_rd = ym_sel & cpu_wr_n;
reg [1:0] wr_hold = 2'd0;
reg       lat_a0  = 1'b0;
reg [7:0] lat_din = 8'd0;

always @(posedge clk_sys) begin
	if (reset) begin
		wr_hold <= 2'd0;
	end else if (z80_ym_wr) begin

		lat_a0  <= ym_data_cs;
		lat_din <= din;
		wr_hold <= YM_HOLD;
	end else if (z80_ym_rd) begin

		wr_hold <= 2'd0;
	end else if (cen && wr_hold != 2'd0) begin
		wr_hold <= wr_hold - 2'd1;
	end
end

wire wr_active = (wr_hold != 2'd0) & ~z80_ym_rd;
wire cs_n_z80 = ~(ym_sel | wr_active);
wire wr_n_z80 = ~wr_active;
wire a0_z80   = wr_active ? lat_a0 : ym_data_cs;
reg        tst_cs_n = 1'b1, tst_wr_n = 1'b1, tst_a0 = 1'b0;
reg  [7:0] tst_din  = 8'd0;
wire       cs_n_i = snd_test ? tst_cs_n : scr_en ? scr_cs_n : cs_n_z80;
wire       wr_n_i = snd_test ? tst_wr_n : scr_en ? scr_wr_n : wr_n_z80;
wire       a0_i   = snd_test ? tst_a0   : scr_en ? scr_a0   : a0_z80;
wire [7:0] din_i  = snd_test ? tst_din  : scr_en ? scr_din  : lat_din;
assign cen_o = cen;
wire ct1, ct2, irq_n;

jt51 jt51_inst
(
	.rst     (reset),
	.clk     (clk_sys),
	.cen     (cen    & ~pause),
	.cen_p1  (cen_p1 & ~pause),
	.cs_n    (cs_n_i),
	.wr_n    (wr_n_i),
	.a0      (a0_i),
	.din     (din_i),
	.dout    (dout),
	.ct1     (ct1),
	.ct2     (ct2),
	.irq_n   (irq_n),
	.sample  (),
	.left    (audio_l),
	.right   (audio_r),
	.xleft   (),
	.xright  ()
);

assign irq_req  = ~irq_n;
assign rom_bank = {ct2, ct1};
localparam int TST_N = 25;
reg [15:0] tst_rom [0:TST_N-1];
initial begin
	tst_rom[ 0] = 16'h0800; tst_rom[ 1] = 16'h20C7;
	tst_rom[ 2] = 16'h4001; tst_rom[ 3] = 16'h4801;
	tst_rom[ 4] = 16'h5001; tst_rom[ 5] = 16'h5801;
	tst_rom[ 6] = 16'h6000; tst_rom[ 7] = 16'h6800;
	tst_rom[ 8] = 16'h7000; tst_rom[ 9] = 16'h7800;
	tst_rom[10] = 16'h801F; tst_rom[11] = 16'h881F;
	tst_rom[12] = 16'h901F; tst_rom[13] = 16'h981F;
	tst_rom[14] = 16'hA000; tst_rom[15] = 16'hA800;
	tst_rom[16] = 16'hB000; tst_rom[17] = 16'hB800;
	tst_rom[18] = 16'hE00F; tst_rom[19] = 16'hE80F;
	tst_rom[20] = 16'hF00F; tst_rom[21] = 16'hF80F;
	tst_rom[22] = 16'h284A; tst_rom[23] = 16'h3000;
	tst_rom[24] = 16'h0878;
end

reg  [4:0] tst_idx  = 5'd0;
reg  [6:0] tst_wait = 7'd0;
reg  [1:0] tst_ph   = 2'd0;
reg        tst_done = 1'b0;
reg        snd_test_d = 1'b0;

always @(posedge clk_sys) begin
	snd_test_d <= snd_test;

	if (snd_test && !snd_test_d) begin
		tst_idx <= 5'd0; tst_ph <= 2'd0; tst_wait <= 7'd0; tst_done <= 1'b0;
	end else if (!snd_test && snd_test_d) begin

		tst_idx  <= 5'd0;
		tst_ph   <= 2'd0;
		tst_wait <= 7'd0;
		tst_done <= 1'b0;
	end else if (cen && !tst_done) begin
		if (tst_wait != 7'd0) begin
			tst_wait <= tst_wait - 7'd1;
			tst_cs_n <= 1'b1;
			tst_wr_n <= 1'b1;
		end else begin
			case (tst_ph)
				2'd0: begin
					tst_a0   <= 1'b0;
					tst_din  <= tst_rom[tst_idx][15:8];
					tst_cs_n <= 1'b0;
					tst_wr_n <= 1'b0;
					tst_ph   <= 2'd1;
				end
				2'd1: begin
					tst_cs_n <= 1'b1; tst_wr_n <= 1'b1;
					tst_wait <= 7'd64;
					tst_ph   <= 2'd2;
				end
				2'd2: begin
					tst_a0   <= 1'b1;
					tst_din  <= tst_rom[tst_idx][7:0];
					tst_cs_n <= 1'b0;
					tst_wr_n <= 1'b0;
					tst_ph   <= 2'd3;
				end
				2'd3: begin
					tst_cs_n <= 1'b1; tst_wr_n <= 1'b1;
					tst_wait <= 7'd64;
					tst_ph   <= 2'd0;

					if (tst_idx == TST_N-1 || !snd_test) tst_done <= 1'b1;
					else                                 tst_idx  <= tst_idx + 5'd1;
				end
			endcase
		end
	end
end

endmodule
