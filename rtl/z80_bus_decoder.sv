`include "game_config.svh"

module z80_bus_decoder #(parameter int GAME_ID = `GAME_RAINBOW)
(
	input             clk,
	input             reset,
	input      [15:0] cpu_a,
	input             cpu_mreq_n,
	input             cpu_iorq_n,
	input             cpu_rd_n,
	input             cpu_wr_n,
	input       [7:0] cpu_dout,
	output reg  [7:0] cpu_din,
	output            rom_cs,
	output     [16:0] rom_addr,
	input       [7:0] rom_dout,
	output            ram_cs,
	output            ram_we,
	input       [7:0] ram_dout,
	output            ym_reg_cs,
	output            ym_data_cs,
	input       [7:0] ym_dout,
	output            ciu_port_cs,
	output            ciu_comm_cs,
	output            ciu_wr,
	output            ciu_rd,
	input       [7:0] ciu_comm_din,
	input       [1:0] rom_bank
);

wire mem_active = ~cpu_mreq_n;
wire io_active  = ~cpu_iorq_n;
wire rd_active  = ~cpu_rd_n;
wire wr_active  = ~cpu_wr_n;
localparam bit VOLFIED = (GAME_ID == `GAME_VOLFIED);
wire sel_rom_fixed  = mem_active && (VOLFIED ? (cpu_a[15]    == 1'b0)
                                             : (cpu_a[15:14] == 2'b00));
wire sel_rom_banked = mem_active && !VOLFIED && (cpu_a[15:14] == 2'b01);
wire sel_ram        = mem_active && (VOLFIED ? (cpu_a[15:11] == 5'b10000)
                                             : (cpu_a[15:12] == 4'b1000));

wire sel_ym_reg     = mem_active && (cpu_a == 16'h9000);
wire sel_ym_data    = mem_active && (cpu_a == 16'h9001);
wire sel_ciu_port   = mem_active && (cpu_a == (VOLFIED ? 16'h8800 : 16'hA000));
wire sel_ciu_comm   = mem_active && (cpu_a == (VOLFIED ? 16'h8801 : 16'hA001));
assign rom_cs  = sel_rom_fixed | sel_rom_banked;
assign rom_addr = VOLFIED       ? {2'b00, cpu_a[14:0]}
                : sel_rom_fixed ? {3'b000, cpu_a[13:0]}
                                : (17'h0C000 + {3'b000, rom_bank, cpu_a[13:0]});

assign ram_cs = sel_ram;
assign ram_we = sel_ram & wr_active;
assign ym_reg_cs  = sel_ym_reg;
assign ym_data_cs = sel_ym_data;
assign ciu_port_cs = sel_ciu_port;
assign ciu_comm_cs = sel_ciu_comm;
assign ciu_wr      = (sel_ciu_port | sel_ciu_comm) & wr_active;
assign ciu_rd      = sel_ciu_comm & rd_active;
always_comb begin
	cpu_din = 8'hFF;
	if (sel_rom_fixed || sel_rom_banked) cpu_din = rom_dout;
	else if (sel_ram)      cpu_din = ram_dout;
	else if (sel_ym_reg || sel_ym_data) cpu_din = ym_dout;
	else if (sel_ciu_comm) cpu_din = ciu_comm_din;

end

endmodule
