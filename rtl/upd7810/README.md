# upd7810/ - NEC uPD78C11 CPU core

Pulled from **jlrh/taito-fpga** (cores/opwolf/hdl/upd7810.v and its
.vh dependency tables), GPLv3 (LICENSE kept verbatim in this folder).
Not a jotego/JTFRAME-affiliated project itself, but built on JTFRAME
conventions (jtframe_dual_ram/jtframe_ram/jtframe_sysz80 elsewhere in
that repo -- not needed here, since our wrapper doesn't use jtframe).

This is the CPU inside Taito's TC0030CMD "C-chip" -- a NEC uPD7810-
family microcontroller (uPD78C11 specifically) running a shared 4KB
internal "bootstrap" ROM common across Taito's C-chip games plus a
game-specific external EPROM. Validated by the original author against
MAME's own uPD7810 debugger trace, instruction-by-instruction, over
1.2M+ instructions (see the file's own header comment) -- this is a
serious, carefully-checked implementation, not a rough approximation.
See `rtl/taito_cchip.sv` for how this project wires it up for Rainbow
Islands specifically (different memory map base address than Operation
Wolf's, but the same TC0030CMD structure).
