# Taito C-Chip Arcade Core for MiSTer FPGA

An open-source, cycle-accurate MiSTer FPGA core targeting Taito C-Chip hardware. This core features native Z80 hardware sound synthesis, low-latency sprite rendering, dynamic pause overlays, and core-side CRT geometry controls.

---

## 🎮 Supported Games

Thanks to shared underlying Taito C-Chip hardware architecture (Motorola 68000 main CPU, Zilog Z80 sound CPU, YM2151 FM audio, and C-Chip protection MCU), this core runs the following titles via `.mra` files:

| Game | Release | Board Architecture | MRA File Name |
| :--- | :---: | :---: | :--- |
| **Rainbow Islands: The Story of Bubble Bobble 2** | 1987 | Taito C-Chip | ` Rainbow Islands.mra` |
| **Rainbow Islands Extra** | 1988 | Taito C-Chip | ` Rainbow Islands Extra.mra` |

> ⚠️ **Note on MRA Filenames:** To prevent automated update scripts or third-party core updates from accidentally overwriting your local custom configuration files, custom MRA files are formatted with a **leading space** in the filename (e.g., ` Rainbow Islands.mra`).

---

## ⚠️ Important Setup Instructions for Rainbow Islands Extra

To get **Rainbow Islands Extra** running properly, you must manually extract the C-Chip MCU file from the Extra ROM zip and place it into the `cchip` folder:

1. Locate `rbislande.zip` in your MAME ROM directory.
2. Extract the C-Chip MCU file: **`c27-04.30`** (or `c27-04.bin`).
3. Copy **`c27-04.30`** into your **`/games/mame/cchip/`** directory on your SD card.

> **Why this is required:** *Rainbow Islands Extra* uses the base *Rainbow Islands* C-Chip MCU data. Placing this file in `/games/mame/cchip/` ensures the core properly initializes the protection hardware and avoids boot loops or game-over triggers.

---

## ✨ Features & Hardware Improvements

* **Native Hardware Audio:** Native Z80 (`T80s`) + PC060HA CIU + YM2151 (`jt51`) execution path. Bus-level side-effects (mode pointers and status flags) are strobed strictly on the falling edge of chip select to prevent Z80 bus sample corruption.
* **Optimized Line-Buffer Sprite Engine:** Burst SDRAM tile-row reads prevent scanline fetch starvation during high sprite density (e.g., multiple rainbows and enemy sprites on screen).
* **Pause & Patreon Overlay:** Features system-wide clock enable gating (`ce_6m`, `ce_3m`) on pause. Active pause renders an OSD text window powered by an embedded $8 \times 8$ BRAM font ROM without disrupting video raster sync.
* **Lagless CRT Geometry Control:** Core-side integration of `crt_adjust.sv` supports sub-pixel horizontal stretch/squeeze, horizontal content shift, and vertical line positioning without dropping sync or shifting the MiSTer main OSD menu.
* **NVRAM & High Score Support:** Automatic saving of scores to `/media/fat/config/NVRAM/<game_id>.hi`.

---

## 🛠️ Installation & Setup

1. Copy the core binary (`RainbowIslands_*.rbf`) to your MiSTer's `/_Arcade/cores/` directory.
2. Place your MRA launch files in the `/_Arcade/` folder on your SD card.
3. Place the required MAME ROM ZIP files (`rbisland.zip`, `rbislande.zip`) into your `/games/mame/` directory.
4. Follow the **Rainbow Islands Extra** C-Chip file setup steps detailed above.

---

## 📜 Credits & Acknowledgments

This core incorporates open-source modules and technical contributions from the arcade preservation community:

* **Jorge Cwik (fx68k):** Cycle-accurate Motorola 68000 CPU core.
* **Jose Tejada / JTFrame (jt51):** Cycle-accurate YM2151 FM Synthesis audio core.
* **Daniel Wallner / MikeJ (T80):** Zilog Z80 CPU implementation.
* **rmonic79:** [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust) module (`crt_adjust.sv`) for lagless CRT alignment controls.
* **Raki (IKA87AD):** Hardware schematics, logic analysis, and timing documentation.
* **Sorgelig:** MiSTer framework & SDRAM infrastructure.

---

## 🤝 Support & Community

If you'd like to follow along with ongoing development, report issues, or support hardware research for future arcade cores, check out the project links below:

* **Patreon:** [https://www.patreon.com/c/bazset](https://www.patreon.com/c/bazset)
* **Issues & Bug Reports:** Please use the GitHub Issues tracker for cycle-timing discrepancies, sound issues, or graphic regressions.
