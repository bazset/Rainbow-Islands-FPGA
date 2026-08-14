//============================================================================
// rbisland_cchip.sv
// Glue for the TC0030CMD C-chip on Rainbow Islands-class boards.
//
// Instantiates jotego's jttc0030cmd (µPD78C11 C-chip model), GPL-3.0.
// See: https://github.com/jotego/jtcores  (and related JT C-chip sources)
//
// PA / PB / PC bit packing follows MAME's rbisland.cpp ioport layout
// (player inputs presented to the C-chip as on the original PCB).
// The same packing appears in jotego's jtrastan_cchip.v; that file was
// used as a cross-check only — the source of truth is MAME / the board.
//============================================================================

module rbisland_cchip
(
	input        clk_sys,       // 48 MHz system clock
	input        reset,

	// 68000 side (chip selects from bus decoder)
	input        mem_cs,        // 0x800000-0x8007FF  (shared RAM window)
	input        asic_cs,       // 0x800800-0x800FFF  (ASIC / bank regs)
	input        wr,            // LDS-qualified write
	input  [9:0] addr,
	input  [7:0] din,
	output [7:0] dout,
	input        ext_irq,       // VBlank pulse into C-chip INTF1

	// ROM download (mask ROM + game EPROM in one stream)
	input        ioctl_download,
	input        ioctl_wr,
	input [24:0] ioctl_addr,
	input  [7:0] ioctl_dout,
	input  [7:0] ioctl_index,
	input        dl_en,
	input [24:0] dl_addr,       // region-relative address

	// Controls — bit order matches MAME rbisland ioport map
	input        service,
	input  [1:0] cab_1p,        // start1, start2
	input  [1:0] coin,
	input        tilt,
	input  [5:0] joystick1,
	input        pause
);

//------------------------------------------------------------------------
// 12 MHz clock enable (48 MHz / 4). Divider free-runs; pause gates cen.
//------------------------------------------------------------------------
reg [1:0] div_cnt = 2'd0;
always @(posedge clk_sys) begin
	div_cnt <= div_cnt + 2'd1;
end
wire cen12 = (div_cnt == 2'd0) & ~pause;

wire        cs   = mem_cs | asic_cs;
wire [10:0] addr11 = {asic_cs, addr};   // bit 10 selects ASIC vs mem inside core

wire [11:0] mrom_addr;
wire [7:0]  mrom_data;
wire [12:0] eprom_addr;
wire [7:0]  eprom_data;

//------------------------------------------------------------------------
// 4 KB internal mask ROM + 8 KB game EPROM (loaded from ioctl)
//------------------------------------------------------------------------
reg [7:0] mask_rom [0:4095];
reg [7:0] eprom     [0:8191];

always @(posedge clk_sys) begin
	if (dl_en && ioctl_wr) begin
		if (dl_addr < 25'h1000)
			mask_rom[dl_addr[11:0]] <= ioctl_dout;
		else if (dl_addr < 25'h3000)
			eprom[dl_addr[24:0] - 25'h1000] <= ioctl_dout;
	end
end

// Registered ROM reads (1-cycle latency expected by jttc0030cmd)
reg [7:0] mrom_data_r, eprom_data_r;
always @(posedge clk_sys) begin
	mrom_data_r  <= mask_rom[mrom_addr];
	eprom_data_r <= eprom[eprom_addr];
end
assign mrom_data  = mrom_data_r;
assign eprom_data = eprom_data_r;

//------------------------------------------------------------------------
// PA / PB / PC — MAME rbisland.cpp ioport bit order
// Cross-checked against jotego jtrastan_cchip.v (same packing for rbisland).
// jttc0030cmd is jotego's µPD78C11 model (GPL-3.0).
//------------------------------------------------------------------------
reg [7:0] cc_pa, cc_pb, cc_pc;
always @(posedge clk_sys) begin
	cc_pa <= {service, cab_1p[0], cab_1p[1], 5'h1f};
	cc_pb <= {6'h3f, ~coin[1:0]};
	cc_pc <= {joystick1[5], joystick1[4], joystick1[0], joystick1[1], 3'b111, tilt};
end

jttc0030cmd u_cchip
(
	.rst (reset),
	.clk (clk_sys),
	.cen (cen12),
	.cs   (cs),
	.addr (addr11),
	.din  (din),
	.dout (dout),
	.rnw  (~wr),
	.dtack_n (),
	.int1  (ext_irq),
	.nmi_n (1'b1),
	.pa_in (cc_pa), .pb_in (cc_pb), .pc_in (cc_pc),
	.pa_out (), .pb_out (), .pc_out (),
	.an (8'hff),
	.mrom_addr  (mrom_addr),
	.mrom_data  (mrom_data),
	.eprom_addr (eprom_addr),
	.eprom_data (eprom_data),
	.dbg_pc    (),
	.dbg_fetch ()
);

endmodule
