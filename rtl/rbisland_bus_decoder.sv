//============================================================================
// rbisland_bus_decoder.sv
// 68000 address decode for Rainbow Islands / related Taito boards.
//
// Region bases are compile-time constants from game_config.svh (GAME_ID).
// Decode widths follow MAME rbisland.cpp / rastan.cpp memory maps and the
// real board's partial address compares (including intentional A1 mirrors).
//============================================================================

`include "game_config.svh"

module rbisland_bus_decoder #(
	parameter int GAME_ID = `GAME_RAINBOW
)
(
	input             clk,
	input             reset,

	// 68000 bus
	input      [23:1] cpu_a,
	input             cpu_as_n,
	input             cpu_rw,          // 1=read, 0=write
	input             cpu_uds_n,
	input             cpu_lds_n,
	output reg        cpu_dtack_n,
	output reg        dbg_unmapped,
	output reg  [7:0] dbg_unmapped_addr,
	input      [15:0] cpu_dout,        // from CPU (writes)
	output reg [15:0] cpu_din,         // to CPU (reads)

	// Program ROM
	output            rom_cs,
	input      [15:0] rom_dout,
	input             rom_ready,

	// Work RAM / extra RAM / palette
	output            work_ram_cs,
	output            work_ram_we,
	input      [15:0] work_ram_dout,
	output            ext_ram_cs,
	output            ext_ram_we,
	input      [15:0] ext_ram_dout,
	output            palette_cs,
	output            palette_we,
	input      [15:0] palette_dout,

	// PC080SN tilemap + scroll/ctrl
	output            tilemap_cs,
	output            tilemap_we,
	input      [15:0] tilemap_dout,
	output            yscroll_cs,
	output            xscroll_cs,
	output            vcu_ctrl_cs,

	// PC090OJ sprite RAM + control
	output            sprite_ram_cs,
	output            sprite_ram_we,
	input      [15:0] sprite_ram_dout,
	output            sprite_ctrl_cs,

	// DIPs / watchdog
	output            dswa_cs,
	input      [15:0] dswa_din,
	output            dswb_cs,
	input      [15:0] dswb_din,
	output            watchdog_cs,

	// PC060HA CIU (68000 side, low byte only)
	output            ciu_port_cs,
	output            ciu_comm_cs,
	output            ciu_wr,
	output            ciu_rd,
	input       [7:0] ciu_comm_din,

	// C-chip (low byte only)
	output            cchip_mem_cs,
	output            cchip_asic_cs,
	output            cchip_wr,
	input       [7:0] cchip_din
);

wire bus_active = ~cpu_as_n;

//------------------------------------------------------------------------
// Per-game base addresses (compile-time constants from game_config.svh)
//------------------------------------------------------------------------
localparam [23:0] ROM_BASE        = `CFG_ROM_BASE(GAME_ID);
localparam [23:0] WORK_RAM_BASE   = `CFG_WORK_RAM_BASE(GAME_ID);
localparam [23:0] PALETTE_BASE    = `CFG_PALETTE_BASE(GAME_ID);
localparam [23:0] EXT_RAM_BASE    = `CFG_EXT_RAM_BASE(GAME_ID);
localparam [23:0] EXT_RAM_TOP     = `CFG_EXT_RAM_TOP(GAME_ID);
localparam [23:0] DSWA_BASE       = `CFG_DSWA_BASE(GAME_ID);
localparam [23:0] SPRCTRL_BASE    = `CFG_SPRCTRL_BASE(GAME_ID);
localparam [23:0] DSWB_BASE       = `CFG_DSWB_BASE(GAME_ID);
localparam [23:0] WATCHDOG_BASE   = `CFG_WATCHDOG_BASE(GAME_ID);
localparam [23:0] CIU_BASE        = `CFG_CIU_BASE(GAME_ID);
localparam [23:0] CCHIP_MEM_BASE  = `CFG_CCHIP_MEM_BASE(GAME_ID);
localparam [23:0] CCHIP_ASIC_BASE = `CFG_CCHIP_ASIC_BASE(GAME_ID);
localparam [23:0] TILEMAP_BASE    = `CFG_TILEMAP_BASE(GAME_ID);
localparam [23:0] YSCROLL_BASE    = `CFG_YSCROLL_BASE(GAME_ID);
localparam [23:0] XSCROLL_BASE    = `CFG_XSCROLL_BASE(GAME_ID);
localparam [23:0] VCUCTRL_BASE    = `CFG_VCUCTRL_BASE(GAME_ID);
localparam [23:0] SPRITERAM_BASE  = `CFG_SPRITERAM_BASE(GAME_ID);

//------------------------------------------------------------------------
// Address selects
// Compare widths match the real board decode (and intentional A1 mirrors).
//------------------------------------------------------------------------
wire sel_rom      = bus_active && (cpu_a[23:19] == ROM_BASE[23:19]);
wire sel_work_ram = bus_active && (cpu_a[23:14] == WORK_RAM_BASE[23:14]);
wire sel_palette  = bus_active && (cpu_a[23:12] == PALETTE_BASE[23:12]);
wire sel_ext_ram  = bus_active && (cpu_a[23:1]  >= EXT_RAM_BASE[23:1]) &&
                                   (cpu_a[23:1]  <= (EXT_RAM_TOP[23:1] - 23'd0));
wire sel_dswa     = bus_active && (cpu_a[23:2]  == DSWA_BASE[23:2]);
wire sel_sprctrl  = bus_active && (cpu_a[23:1]  == SPRCTRL_BASE[23:1]);
wire sel_dswb     = bus_active && (cpu_a[23:2]  == DSWB_BASE[23:2]);
wire sel_watchdog = bus_active && (cpu_a[23:2]  == WATCHDOG_BASE[23:2]);
wire sel_ciu_grp  = bus_active && (cpu_a[23:2]  == CIU_BASE[23:2]);
wire sel_cchip_mem  = bus_active && (cpu_a[23:11] == CCHIP_MEM_BASE[23:11]);
wire sel_cchip_asic = bus_active && (cpu_a[23:11] == CCHIP_ASIC_BASE[23:11]);
wire sel_tilemap  = bus_active && (cpu_a[23:16] == TILEMAP_BASE[23:16]);
wire sel_yscroll  = bus_active && (cpu_a[23:2]  == YSCROLL_BASE[23:2]);
wire sel_xscroll  = bus_active && (cpu_a[23:2]  == XSCROLL_BASE[23:2]);
wire sel_vcuctrl  = bus_active && (cpu_a[23:2]  == VCUCTRL_BASE[23:2]);
wire sel_spriteram= bus_active && (cpu_a[23:14] == SPRITERAM_BASE[23:14]);

// CIU 4-byte window: A1 selects port vs comm; both are low-byte only
wire sel_ciu_port = sel_ciu_grp && (cpu_a[1] == 1'b0);
wire sel_ciu_comm = sel_ciu_grp && (cpu_a[1] == 1'b1);

assign rom_cs        = sel_rom;
assign work_ram_cs   = sel_work_ram;
assign palette_cs    = sel_palette;
assign ext_ram_cs    = sel_ext_ram;
assign tilemap_cs    = sel_tilemap;
assign sprite_ram_cs = sel_spriteram;
assign sprite_ctrl_cs= sel_sprctrl;
assign dswa_cs        = sel_dswa;
assign dswb_cs        = sel_dswb;
assign watchdog_cs    = sel_watchdog;
assign yscroll_cs     = sel_yscroll;
assign xscroll_cs     = sel_xscroll;
assign vcu_ctrl_cs    = sel_vcuctrl;
assign ciu_port_cs    = sel_ciu_port;
assign ciu_comm_cs    = sel_ciu_comm;
assign cchip_mem_cs   = sel_cchip_mem;
assign cchip_asic_cs  = sel_cchip_asic;

//------------------------------------------------------------------------
// Write enables (byte lanes applied at the RAMs in rbisland_top)
//------------------------------------------------------------------------
wire wr_cycle = bus_active && !cpu_rw;
assign work_ram_we = wr_cycle && sel_work_ram;
assign ext_ram_we  = wr_cycle && sel_ext_ram;
assign palette_we  = wr_cycle && sel_palette;
assign tilemap_we  = wr_cycle && sel_tilemap;
assign sprite_ram_we = wr_cycle && sel_spriteram;
assign cchip_wr = wr_cycle && !cpu_lds_n && (sel_cchip_mem || sel_cchip_asic);
assign ciu_wr   = wr_cycle && !cpu_lds_n && (sel_ciu_port  || sel_ciu_comm);
assign ciu_rd   = bus_active && cpu_rw && !cpu_lds_n && sel_ciu_comm;

//------------------------------------------------------------------------
// Read data mux (8-bit peripherals present on D7:0 only)
//------------------------------------------------------------------------
always_comb begin
	cpu_din = 16'h0000;
	if (sel_rom)          cpu_din = rom_dout;
	else if (sel_work_ram) cpu_din = work_ram_dout;
	else if (sel_palette)  cpu_din = palette_dout;
	else if (sel_ext_ram)  cpu_din = ext_ram_dout;
	else if (sel_dswa)     cpu_din = dswa_din;
	else if (sel_dswb)     cpu_din = dswb_din;
	else if (sel_tilemap)  cpu_din = tilemap_dout;
	else if (sel_spriteram) cpu_din = sprite_ram_dout;
	else if (sel_ciu_comm) cpu_din = {8'h00, ciu_comm_din};
	else if (sel_cchip_mem || sel_cchip_asic) cpu_din = {8'h00, cchip_din};
end

//------------------------------------------------------------------------
// DTACK: ROM waits on rom_ready; everything else one wait state.
// Unmapped accesses are also acked (no BERR) so the CPU never hangs.
//------------------------------------------------------------------------
reg as_n_d;
always @(posedge clk) as_n_d <= cpu_as_n;

wire any_internal_sel = sel_work_ram | sel_palette | sel_ext_ram | sel_dswa | sel_sprctrl |
                         sel_dswb | sel_watchdog | sel_ciu_port | sel_ciu_comm |
                         sel_cchip_mem | sel_cchip_asic | sel_tilemap | sel_yscroll |
                         sel_xscroll | sel_vcuctrl | sel_spriteram;

always @(posedge clk) begin
	if (reset) begin
		cpu_dtack_n <= 1'b1;
	end else begin
		if (cpu_as_n) begin
			cpu_dtack_n <= 1'b1;
		end else if (sel_rom) begin
			cpu_dtack_n <= ~rom_ready;
		end else begin
			cpu_dtack_n <= as_n_d;
		end
	end
end

//------------------------------------------------------------------------
// Sticky unmapped-access diagnostic
//------------------------------------------------------------------------
wire unmapped_sel = bus_active && !sel_rom && !any_internal_sel;

always @(posedge clk) begin
	if (reset) begin
		dbg_unmapped      <= 1'b0;
		dbg_unmapped_addr <= 8'd0;
	end else if (unmapped_sel && !dbg_unmapped) begin
		dbg_unmapped      <= 1'b1;
		dbg_unmapped_addr <= cpu_a[23:16];
	end
end

endmodule
