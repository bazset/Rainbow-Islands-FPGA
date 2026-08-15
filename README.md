
# Rainbow Islands (MiSTer FPGA) by bazset

Support my work and follow development updates on [Patreon](https://www.patreon.com/cw/bazset)!

Hardware implementation of Taito’s **Rainbow Islands** (1987) for [MiSTer FPGA](https://mister-devel.github.io/MkDocs_MiSTer/).

This is a chip-level reconstruction of the arcade board — not a high-level simulation of game behaviour. Each major custom on the PCB is its own HDL module, wired as on the original hardware.


### Currently Supported Sets

- **Rainbow Islands** (*World, rev 2, set 1*)
- **Rainbow Islands - Extra Version**

## Hardware

| Block | Implementation |
|-------|----------------|
| Main CPU | MC68000 @ 8 MHz (FX68K) |
| Sound CPU | Z80 @ 4 MHz (T80) |
| FM audio | YM2151 @ 4 MHz |
| Sound mailbox | Taito PC060HA (CIU) |
| Tile maps (BG + FG) | Taito PC080SN |
| Sprites | Taito PC090OJ |
| Protection / inputs | Taito C-chip (TC0030CMD / µPD78C11) |

Video timing follows the measured Taito PC080SN path used on this board family (same family as Rastan): pixel clock ≈ 6.6715 MHz, frame rate ≈ 59.83 Hz. Suitable for HDMI scalers and CRTs.

### C-chip

Rainbow Islands uses a sealed NEC µPD78C11 microcontroller (the **C-chip**) for copy protection and player input handling. It runs a program; it is not a static lookup table.

This core executes the genuine C-chip firmware on an HDL model of the µPD78C11 (`jttc0030cmd`, jotego, GPL-3.0). Both ROMs are required:

- **4 KB internal mask ROM** (`cchip_upd78c11.bin` in `cchip.zip`)
- **8 KB game-specific EPROM** (e.g. `cchip_b22-15.53` inside `rbisland.zip`)

PA / PB / PC bit packing follows MAME’s `rbisland.cpp` ioport map (cross-checked against jotego’s `jtrastan_cchip.v`).

---

## Installation (MiSTer)

| File | Destination |
|------|-------------|
| `Rainbow Islands (World, rev 2, set 1) bazset.mra` | `/media/fat/_Arcade/` |
| `Rbisland.rbf` | `/media/fat/_Arcade/cores/` |
| `rbisland.zip` | `/media/fat/games/mame/` |
| `cchip.zip` | `/media/fat/games/mame/` |

* **`cchip.zip`**: Must contain `cchip_mcu.bin` (the shared C-chip mask ROM used across all C-chip games)
* **`rbisland.zip`** (or **`rbislande.zip`** for the *Extra* version): Must contain the game-specific C-chip EPROM (`cchip_eeprom.bin`)

---

## Project layout

```
Rbisland/
├── rtl/              Core SystemVerilog (bus, video, sound glue, top)
├── sys/              MiSTer framework / platform
├── sound/            Sound-related helpers / scripts
├── cfg/              Build / board config
├── Rbisland.qpf/.qsf/.sdc/.sv
├── build.bat  clean.bat  compare.bat
└── LICENSE  README.md
```

Main RTL modules of interest:

- `rbisland_top.sv` — top-level integration  
- `rbisland_bus_decoder.sv` — 68000 map (`game_config.svh`)  
- `pc080sn_layer_renderer.sv` — tile layers  
- `pc090oj_renderer.sv` — sprites  
- `pc060ha_ciu.sv` — 68000 ↔ Z80 mailbox  
- `rbisland_cchip.sv` — C-chip glue around `jttc0030cmd`

---
## Credits and acknowledgements

- **Jorge Cwik (ijor)** for the cycle-accurate **FX68K** 68000 CPU core.
- **Daniel Wallner** for the foundational **T80** Z80 CPU core.
- **Jose Tejada Gómez (jotego)** for the **JT51** (YM2151 FM synth) core, the `jttc0030cmd` C-chip wrapper, and the **CRT adjust core** (`jtframe_resync`) for video positioning.
- **ika-musume** for the **IKA87AD** microcontroller core used inside the C-chip implementation.
- **Alexey Melnikov (Sorgelig)** for the MiSTer **SDRAM controller** (`sdram.sv`).
- **MAME Dev Team** for the reference driver implementation (`rbisland.cpp` / `taito.cpp`) that made memory mapping, custom chip behavior, and bus logic analysis possible.
- **rmonic79** — Creator of [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust)
- Arcade PCB measurements and public schematics for the Taito B-system / related boards.
---

## License

See `LICENSE` in this repository. Third-party modules retain their own licenses (e.g. GPL for jotego’s C-chip model).

ROM files are copyrighted by their respective owners and are **not** distributed with this project.

---


