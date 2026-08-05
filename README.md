# 🌈 Rainbow Islands (Taito, 1987) — MiSTer FPGA Core

![MiSTer FPGA](https://img.shields.io/badge/Platform-MiSTer_FPGA-blue?style=flat-square)
![Status](https://img.shields.io/badge/Status-Beta-yellow?style=flat-square)
![License](https://img.shields.io/badge/License-GPL--3.0-orange?style=flat-square)
[![Patreon](https://img.shields.io/badge/Support-Patreon-orange?style=flat-square&logo=patreon)](https://www.patreon.com/c/bazset)

A cycle-accurate hardware implementation of the original Taito **Rainbow Islands** arcade hardware for the MiSTer FPGA platform.

> [!WARNING]
> **Beta Release**  
> This core is currently in active development. You may encounter bugs, incomplete features, or timing inaccuracies. Feedback and issue reports are welcome!

> [!NOTE]
> **Hardware Implementation, Not Emulation**  
> This is a full hardware-level implementation of the original PCB—**not** software emulation or a high-level abstraction. Every physical chip on the board is instantiated as a dedicated HDL module, routed precisely as designed on the physical PCB trace routes.

---

## 🐛 Known Issues

The core is in active development. The following issues are currently being worked on:

* **No Sound** — YM2151 / audio path implementation is currently under active development.
* **Direct Video** — Results in a black screen on boot.
* **Screen Wobble** — Observed on some consumer CRTs.
* **Map Screen** — Positioned slightly too low on the display output.
* **Sprite Flicker** — Occurs when a high density of sprites shares scanlines (most visible when the end-of-level treasure chest opens).

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

## ❤️ Support the Project

If you'd like to follow along with ongoing core development, get early updates, or support arcade core preservation efforts, check out my Patreon:

👉 **[patreon.com/c/bazset](https://www.patreon.com/c/bazset)**

---

## 📜 Credits & Licensing

* FPGA core implementation by **bazset**.
* Original arcade hardware designed by **Taito Corporation** (1987).
* Distributed under the **GNU General Public License v3.0**.
