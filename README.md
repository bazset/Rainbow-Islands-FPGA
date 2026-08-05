MiSTer Core Release: Rainbow Islands (Taito, 1987)

Hardware Implementation
This is a hardware implementation of the arcade board, not a simulation of its behavior. Each chip on the original PCB is its own HDL module, wired together as the real board wires them.

Installation

The core needs the genuine C-chip ROMs to run. Currently, only the rbisland (World, rev 2, set 1) set is supported.

File Destination on the SD Card:

Rainbow Islands (World, rev 2, set 1) bazset.mra /media/fat/_Arcade/
Rbisland.rbf /media/fat/_Arcade/cores/
rbisland.zip /media/fat/games/mame/
cchip.zip /media/fat/games/mame/

Both zips are required:

rbisland.zip must contain the game-specific C-chip EPROM (cchip_b22-15.53)
cchip.zip supplies cchip_upd78c11.bin (the internal mask ROM shared by every C-chip game)
