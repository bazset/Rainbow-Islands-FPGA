//============================================================================
// pll.sv - Clock generator wrapper
//
// Wraps a Quartus "Altera PLL" (fPLL) megafunction IP. This project's
// sandbox has no licensed Quartus install to actually run IP Catalog in,
// so the exact integer divider values needed are computed and verified
// here instead -- regenerating the real IP with these parameters should
// reproduce this exactly:
//
//   Reference : 50.000 MHz (CLK_50M)
//   VCO       : 1200.000 MHz  (M=24, N=1 -- 50MHz * 24/1, within Cyclone
//               V's typical fPLL VCO range of ~600-1300MHz)
//   outclk_0  : 1200MHz / C0=25  = 48.000 MHz exact -- system clock
//   outclk_1  : 1200MHz / C1=200 =  6.000 MHz exact -- pixel clock
//
// Both output frequencies divide the 1200MHz VCO with ZERO remainder
// (verified: 1200e6 % 48e6 == 0 and 1200e6 % 6e6 == 0), so both are
// exact, not approximated -- there's no rounding error to inherit here,
// unlike some other MiSTer cores' clock ratios.
//
// ⚠⚠ DO NOT ADD THIS FILE TO Rbisland.qsf. ⚠⚠
// It is deliberately excluded from the Quartus project. Two reasons,
// the second of which is absolute:
//   1. A real generated PLL IP (rtl/pll.v + rtl/pll/pll_0002.v) already
//      defines module "pll" -- including both is a duplicate definition.
//   2. MiSTer's sys_top feeds CLK_VIDEO into clock-select blocks that
//      REQUIRE a genuine PLL hard-IP output. Anything built from
//      ordinary fabric logic -- including this file's flip-flop divider
//      below -- is rejected with "Error (15836): ... must be driven by
//      a PLL's output clock". No arrangement of frequencies fixes that;
//      it's about the physical clock source, not the rate.
// This file survives purely for the two uses noted below (parameter
// documentation + a simulation model gated behind `define SIMULATION).
//
// ⚠ REPLACE THIS FILE'S BODY with a real Quartus IP Catalog-generated
// "Altera PLL" using the M/N/C parameters above before using this on
// real hardware. 48MHz from a 50MHz reference has no exact integer
// relationship, so no amount of ordinary fabric logic (dividers,
// counters) can synthesize it correctly -- only the real PLL hard IP
// block can. The default body below is a same-caveat placeholder that
// is at least safely SYNTHESIZABLE (a real flip-flop divider, no
// latches, no combinational timing loops) so the project still builds
// and something clocks the design while you regenerate the real IP --
// it is NOT frequency-accurate (its outputs are 50MHz/2=25MHz and
// 50MHz/8=6.25MHz, not 48MHz/6MHz) and should not be trusted for
// anything beyond "does the design at least come out of reset".
//
// A behaviorally-accurate (real-time-period-based, non-synthesizable)
// simulation model is available separately, gated behind an explicit
// `define SIMULATION` -- see sim/tb_pll.sv for how to enable it. It is
// NOT the default, and NOT guarded with `ifndef SYNTHESIS` -- Quartus does
// not predefine that macro, so such a block is actually synthesised. Its
// real-number `#` delays do not map to hardware at all and Quartus infers
// latches from them (a genuinely bad result: latches on a clock
// generator would have been a serious problem on real hardware, not
// just a style warning). Fixed by making the safe path the default and
// requiring explicit opt-in for the simulation-accurate one, rather than
// trying to auto-detect synthesis-vs-simulation via an assumed macro.
//============================================================================

module pll
(
	input        refclk,   // 50 MHz
	input        rst,
	output       outclk_0, // 48 MHz sys clock (target; see caveats above)
	output       outclk_1, // 6 MHz pixel clock (target; see caveats above)
	output       locked
);

`ifdef SIMULATION
// Behaviorally-accurate, NON-synthesizable: real-time periods matching
// 48.000MHz/6.000MHz exactly, for testbenches that opt in explicitly
// (e.g. `iverilog -g2012 -DSIMULATION ...`, or `` `define SIMULATION ``
// before including/compiling this file). See sim/tb_pll.sv.
reg out0 = 1'b0;
reg out1 = 1'b0;
always #(1_000.0/48.0/2.0) if (!rst) out0 = ~out0;
always #(1_000.0/6.0/2.0)  if (!rst) out1 = ~out1;

reg [3:0] lock_cnt = 0;
reg       locked_r = 0;
always @(posedge refclk) begin
	if (rst) begin
		lock_cnt <= 0;
		locked_r <= 0;
	end else if (lock_cnt != 4'hF) begin
		lock_cnt <= lock_cnt + 1'd1;
	end else begin
		locked_r <= 1'b1;
	end
end

assign outclk_0 = out0;
assign outclk_1 = out1;
assign locked   = locked_r;

`else
// Default: safely synthesizable, NOT frequency-accurate (see header).
// Plain flip-flop dividers -- no latches, no inferred combinational
// feedback, nothing Quartus should object to structurally.
reg [1:0] div0 = 2'd0;
reg [2:0] div1 = 3'd0;
reg       out0 = 1'b0;
reg       out1 = 1'b0;

always @(posedge refclk) begin
	if (rst) begin
		div0 <= 2'd0;
		out0 <= 1'b0;
	end else if (div0 == 2'd0) begin
		div0 <= 2'd1;
		out0 <= ~out0;
	end else begin
		div0 <= 2'd0;
	end
end

always @(posedge refclk) begin
	if (rst) begin
		div1 <= 3'd0;
		out1 <= 1'b0;
	end else if (div1 == 3'd3) begin
		div1 <= 3'd0;
		out1 <= ~out1;
	end else begin
		div1 <= div1 + 3'd1;
	end
end

reg [3:0] lock_cnt = 0;
reg       locked_r = 0;
always @(posedge refclk) begin
	if (rst) begin
		lock_cnt <= 0;
		locked_r <= 0;
	end else if (lock_cnt != 4'hF) begin
		lock_cnt <= lock_cnt + 1'd1;
	end else begin
		locked_r <= 1'b1;
	end
end

assign outclk_0 = out0;
assign outclk_1 = out1;
assign locked   = locked_r;
`endif

endmodule
