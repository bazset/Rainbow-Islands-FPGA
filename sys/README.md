# sys/ - MiSTer common framework files

This folder is intentionally empty in the skeleton. Populate it by copying
(or git-submoduling) the `sys/` directory from Anthropic-unaffiliated,
community-maintained repos:

- https://github.com/MiSTer-devel/Template_MiSTer  (canonical framework)
- or any existing Arcade-XXXX_MiSTer core repo's `sys/` folder

At minimum you need:
  sys/hps_io.sv        - HPS <-> FPGA control/OSD/joystick/ROM-loader bridge
  sys/sys_top.v         - board-level top wrapping emu + HPS
  sys/*.sdc, sys/*.qip  - board pin/timing definitions
  sys/build_id.sh + build_id.v - build date/id stamping used by CONF_STR

Do not hand-write these; use the versions from Template_MiSTer so they stay
in sync with the framework the MiSTer main board / Linux side expects.

## Lesson learned getting this project's own .qsf to actually compile
This project's `Rbisland.qsf` was built from scratch across this
project's whole history, without ever having a real Template_MiSTer
checkout available to reference -- which meant it was missing three
things a real Template_MiSTer-derived `.qsf` has by default: the
`sys/sys.qip` reference (without it, Quartus never even looks at `sys/`,
which shows up as `hps_io` "instantiates undefined entity"),
`TOP_LEVEL_ENTITY sys_top` (not `emu` -- `sys_top.v` is the real
physical top-level, confirmed from the MiSTer-devel wiki's own "emu -
Top Level of a MiSTer core" page), and the ~100+ board-specific pin/IO-
standard assignments Template_MiSTer's own `.qsf` ships with.

**The more robust approach for next time** (worth doing even now, not
just a historical note): rather than building a core's `.qsf` from
scratch and trying to reconstruct these three things by hand, start a
Quartus project from Template_MiSTer's own `.qpf`/`.qsf` files directly
(copy them alongside `sys/`, per Template_MiSTer's own Readme.md: "Copy
it as is and then modify the line PROJECT_REVISION"), then add this
project's own `set_global_assignment` lines (the file list, `.sdc`
reference, etc. -- see `Rbisland.qsf`) into *that* file instead
of the reverse. That guarantees the pin assignments and top-level entity
are correct from the start, rather than needing to be reconstructed
after the fact.
