# 🌈 MiSTer Core Release: Rainbow Islands (Taito, 1987)

> **Hardware Implementation**  
> This is a full hardware-level implementation of the original arcade board—**not** an emulator or high-level simulation. Every physical chip on the original PCB is implemented as its own dedicated HDL module, wired together precisely as the physical trace routing dictates.

---

## 🛠️ Installation

> [!IMPORTANT]
> The core requires genuine **C-chip ROMs** to function. Currently, only the `rbisland` (**World, rev 2, set 1**) release is supported.

### SD Card Directory Mapping

| File | File Name | SD Card Destination |
| :--- | :--- | :--- |
| **MRA File** | `bazset.mra` | `/media/fat/_Arcade/` |
| **Core File** | `Rbisland.rbf` | `/media/fat/_Arcade/cores/` |
| **ROM Zip** | `rbisland.zip` | `/media/fat/games/mame/` |
| **C-Chip Zip** | `cchip.zip` | `/media/fat/games/mame/` |

### Required Zip Contents

Both zip files below are **strictly required**:

* **`rbisland.zip`** — Must contain the game-specific C-chip EPROM (`cchip_b22-15.53`).
* **`cchip.zip`** — Provides `cchip_upd78c11.bin` *(the internal mask ROM shared across all C-chip titles)*.
