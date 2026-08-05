# 🌈 Rainbow Islands (Taito, 1987) — MiSTer FPGA Core

![MiSTer FPGA](https://img.shields.io/badge/Platform-MiSTer_FPGA-blue?style=flat-square)
![Status](https://img.shields.io/badge/Status-Beta-yellow?style=flat-square)
![License](https://img.shields.io/badge/License-GPL--3.0-orange?style=flat-square)

A cycle-accurate hardware implementation of the original Taito **Rainbow Islands** arcade hardware for the MiSTer FPGA platform.

> [!WARNING]
> **Beta Release**  
> This core is currently in active development. You may encounter bugs, incomplete features, or timing inaccuracies. Feedback and issue reports are welcome!

> [!NOTE]
> **Hardware Implementation, Not Emulation**  
> This is a full hardware-level implementation of the original PCB—**not** software emulation or a high-level abstraction. Every physical chip on the board is instantiated as a dedicated HDL module, routed precisely as designed on the physical PCB trace routes.

---

## 🔬 Hardware Specifications

| Component | Hardware Unit | Clock Speed |
| :--- | :--- | :--- |
| **Main CPU** | Motorola MC68000 | 8.0 MHz |
| **Sound CPU** | Zilog Z80 | 4.0 MHz |
| **FM Synth** | Yamaha YM2151 | 4.0 MHz |
| **Sound Mailbox** | Taito PC060HA | — |
| **Tilemaps (BG/FG)** | Taito PC080SN | — |
| **Sprites** | Taito PC090OJ | — |
| **Protection & Inputs** | Taito C-chip (NEC µPD78C11) | — |

---

## 🛠️ Installation & Setup

> [!IMPORTANT]
> This core requires genuine **C-chip ROMs** to function properly. Currently, only the **`rbisland`** (*World, rev 2, set 1*) ROM set is supported.

### 📁 SD Card File Directory

Place the required files into their respective directories on your MiSTer SD card:

| File Type | File Name | Destination Path |
| :--- | :--- | :--- |
| **MRA File** | `bazset.mra` | `/media/fat/_Arcade/` |
| **Core Binary** | `Rbisland.rbf` | `/media/fat/_Arcade/cores/` |
| **ROM Archive** | `rbisland.zip` | `/media/fat/games/mame/` |
| **C-Chip Archive** | `cchip.zip` | `/media/fat/games/mame/` |

### 📦 Required Archives

Both ZIP files below are **mandatory**:

* **`rbisland.zip`** — Contains game-specific data, including the C-chip EPROM (`cchip_b22-15.53`).
* **`cchip.zip`** — Contains `cchip_upd78c11.bin` (*the internal microcontroller mask ROM shared across Taito C-chip titles*).

---

## 📜 Credits & Licensing

* Hardware reverse-engineering and FPGA core implementation by [Your Name/Handle].
* Original arcade hardware designed by **Taito Corporation** (1987).
* Distributed under the **GNU General Public License v3.0**.
