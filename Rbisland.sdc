# ============================================================================
# Rbisland.sdc - Timing constraints (skeleton)
# ============================================================================

# NOTE: there is deliberately NO create_clock on CLK_50M here.
#
# The top-level entity is sys_top (the MiSTer framework), not emu, so
# CLK_50M is an internal port of emu and NOT a top-level pin --
# `[get_ports {CLK_50M}]` therefore matches nothing. A create_clock whose
# collection is empty can abort SDC processing, and an SDC that fails to
# read leaves the design effectively unconstrained (Quartus then reports
# timing as met simply because nothing was analysed). meathax's Sega
# System 32 core documents hitting exactly this class of failure --
# constraints referencing objects that don't exist "silently disabled
# timing-driven synthesis".
#
# sys/ already constrains the real board clocks, and derive_pll_clocks
# picks up everything downstream of the PLL. Neither of the working
# reference cores checked (meathax/s32, meathax/mrdo) creates a clock
# here either.

derive_pll_clocks
derive_clock_uncertainty

# Cross-domain paths between the 8MHz/4MHz clock-enabled logic and clk_sys
# are handled via single clock-enables, not separate clocks, so no extra
# false-path/multicycle constraints are required for those. Add explicit
# set_false_path / set_multicycle_path constraints here once real CPU
# cores and the SDRAM controller are dropped in, based on their actual
# timing requirements.

# ---- FX68K recommended multicycle constraints (from rtl/fx68k/fx68k.txt) --
# Microcode/nanocode ROM access is one of FX68K's slowest paths but its
# output isn't needed the next cycle; wildcarded here since the exact
# hierarchical instance path depends on the synthesis tool's naming
# (emu > rbisland_top > cpu > fx68k_inst). Verify the resolved keeper
# names in Quartus's Timing Analyzer and tighten the wildcards if needed.
set_multicycle_path -start -setup -from [get_keepers {*fx68k_inst*Ir[*]}] -to [get_keepers {*fx68k_inst*microAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {*fx68k_inst*Ir[*]}] -to [get_keepers {*fx68k_inst*microAddr[*]}] 1
set_multicycle_path -start -setup -from [get_keepers {*fx68k_inst*Ir[*]}] -to [get_keepers {*fx68k_inst*nanoAddr[*]}] 2
set_multicycle_path -start -hold  -from [get_keepers {*fx68k_inst*Ir[*]}] -to [get_keepers {*fx68k_inst*nanoAddr[*]}] 1
