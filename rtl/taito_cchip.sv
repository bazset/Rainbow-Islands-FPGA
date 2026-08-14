module taito_cchip
(
	input        clk_sys,
	input        reset,
	input        mem_cs,
	input        asic_cs,
	input        wr,
	input  [9:0] addr,
	input  [7:0] din,
	output [7:0] dout,
	input        ext_irq,
	output [13:0] rom_addr,
	input   [7:0] rom_data,
	input  [7:0] pa_in,
	input  [7:0] pb_in,
	input  [7:0] pc_in,
	input  [7:0] ad_in,
	output [7:0] pb_out
);

reg [1:0] div_cnt;
always @(posedge clk_sys) begin
	if (reset) div_cnt <= 2'd0;
	else       div_cnt <= div_cnt + 2'd1;
end
wire cen12 = (div_cnt == 2'd0);
wire [15:0] cpu_addr;
wire  [7:0] cpu_dout;
wire        cpu_we;
reg   [7:0] cpu_din;
wire  [7:0] pb_out_i;

upd7810 u_cpu
(
	.rst   (reset),
	.clk   (clk_sys),
	.cen   (cen12),
	.addr  (cpu_addr),
	.dout  (cpu_dout),
	.we    (cpu_we),
	.din   (cpu_din),
	.pa_in (pa_in),
	.pb_in (pb_in),
	.pc_in (pc_in),
	.pa_out(),
	.pb_out(pb_out_i),
	.pc_out(),
	.intf1 (ext_irq),
	.trace_stb (),
	.trace_pc  (),
	.undef     ()
);

assign pb_out = pb_out_i;
wire cpu_rom  = cpu_addr <  16'h1000 || (cpu_addr >= 16'h2000 && cpu_addr < 16'h4000);
wire cpu_sram = cpu_addr >= 16'h1000 && cpu_addr < 16'h1400;
wire cpu_asic = cpu_addr >= 16'h1400 && cpu_addr < 16'h1800;
wire cpu_iram = cpu_addr >= 16'hff00;
wire [9:0] asic_off = cpu_addr[9:0];
wire       cpu_bank_we = cpu_asic & cpu_we & (asic_off == 10'h200);
assign rom_addr = cpu_addr[13:0];
wire [7:0] sram_cpu, sram_68k, iram_dout;
reg [7:0] asic_ram [0:3];

always @* begin
	cpu_din = 8'hff;
	if (cpu_rom)  cpu_din = rom_data;
	if (cpu_sram) cpu_din = sram_cpu;
	if (cpu_iram) cpu_din = iram_dout;
	if (cpu_asic) cpu_din = (asic_off < 10'h200) ? asic_ram[cpu_addr[1:0]] : 8'h00;
end

reg [2:0] bank, bank68;

always @(posedge clk_sys) begin
	if (reset) begin
		bank   <= 3'd0;
		bank68 <= 3'd0;
		asic_ram[0] <= 8'd0; asic_ram[1] <= 8'd0;
		asic_ram[2] <= 8'd0; asic_ram[3] <= 8'd0;
	end else begin
		if (cpu_asic && cpu_we) begin
			if (asic_off == 10'h200) bank <= cpu_dout[2:0];
			else                     asic_ram[cpu_addr[1:0]] <= cpu_dout;
		end
		if (asic_cs && wr) begin
			if (addr == 10'h200) bank68 <= din[2:0];
			else                 asic_ram[addr[1:0]] <= din;
		end
	end
end

assign dout = asic_cs ? ((addr < 10'h200) ? asic_ram[addr[1:0]] : 8'h00)
                       : sram_68k;

reg [7:0] sram [0:8191];

always @(posedge clk_sys) begin
	if (cpu_sram && cpu_we) sram[{bank, cpu_addr[9:0]}] <= cpu_dout;
end
assign sram_cpu = sram[{bank, cpu_addr[9:0]}];

always @(posedge clk_sys) begin
	if (mem_cs && wr) sram[{bank68, addr}] <= din;
end
assign sram_68k = sram[{bank68, addr}];
reg [7:0] iram [0:255];

always @(posedge clk_sys) begin
	if (cpu_iram && cpu_we) iram[cpu_addr[7:0]] <= cpu_dout;
end
assign iram_dout = iram[cpu_addr[7:0]];

endmodule
