# ika87ad/ - real TC0030CMD "C-chip" (uPD78C11 LLE)

Pulled from **jotego/jtcores** (`modules/jttc0030cmd/`), used by jotego's
own shipped, working `rastan` core (which also supports Rainbow Islands
-- `cores/rastan/hdl/jtrastan_cchip.v` in that repo instantiates this
same module for both games). Investigated per the user's request to
learn from a more mature reference implementation before building our
own from scratch a second time -- see doc/rainbow_islands_notes.md for
the full comparison against this project's own first attempt (which
this replaces).

## !! LICENCE: READ BEFORE PUBLISHING THE RAINBOW ISLANDS CORE !!

Checked against upstream 2026-08-07. **Upstream's LICENCE now carries a
clause 3 that our vendored copy does not have:**

> 3. This clause adds one more restriction to the BSD2 license. All files,
>    and even a snippet of code comprising IKA87AD may not be used to
>    implement Taito's game "Rainbow Islands". This clause will be removed
>    after I implement an FPGA compatible core for that game.

That is what "Temporary" in the title means. Timeline from upstream's commit
history on `LICENSE`:

- 2023-12-12 `45d30fb` initial commit -- clauses 1 and 2 only.
- 2024-01-16 `ed3539d` "update license" -- clause 3 added.
- 2024-02-19 `75588f6` -- current, stronger wording ("even a snippet").

Our copy came via jotego, and jotego's `modules/jttc0030cmd/LICENSE.IKA87AD`
still ships the pre-2024 two-clause text -- so our files predate the
restriction and our `LICENSE` matches what we were given. But **`Rbisland.qsf`
lines 165-171 compile these files into the Rainbow Islands core**, which is
exactly the use Raki has reserved. Volfied is not named by the clause and is
unaffected.

Consequences for this folder:
- **Do NOT re-vendor from upstream for the Rainbow build.** Pulling the
  current upstream tree imports clause 3 along with it. The only upstream
  delta in the RTL is three `verilator lint_off` pragmas jotego prepended to
  `IKA87AD.sv`; the other four files are byte-identical, so there is nothing
  to gain and a licence term to lose.
- Talk to Raki before publishing Rainbow Islands publicly.

(Also note: jotego's own `jttc0030cmd/README.md` lists Superman, the Taito-X
family and Operation Wolf -- it does **not** mention Rainbow Islands, contrary
to what the paragraph below claims. Treat that claim as unverified.)

---

Two licenses in this folder, kept separate on purpose:
- `IKA87AD*.sv` (the actual uPD78C11 CPU core, from
  https://github.com/ika-musume/IKA87AD by Raki) -- permissive BSD-2-
  style ("Taito C-Chip Temporary License"), kept verbatim in `LICENSE`.
  **See the licence warning above before relying on this line.**
  Validated upstream against datasheet-derived golden values for every
  instruction/addressing mode (Verilator + C++), not re-validated here.
- `jttc0030cmd.v` (the generic C-chip wrapper: memory map, banked SRAM,
  ASIC mailbox, DTACK, INT1 conditioning) -- **GPLv3** (JTCORES,
  Andrea Bogazzi). Same copyleft consideration as FX68K/JT51/sdram.sv/
  upd7810 elsewhere in this project.

`jttc0030cmd.v` is used essentially as-is (a complete, generic, already-
tested C-chip implementation -- it has its own `ver/hostmem`/`ver/int1`/
`ver/boot` test suite upstream covering the bank-separation, ASIC
mailbox, and INT1-conditioning logic). This project's own glue is just
`rtl/rbisland_cchip.sv`, which wires rbisland's specific bus signals,
ROM storage, and the player-input PA/PB/PC mapping (adapted from
`jtrastan_cchip.v`'s own rbisland-specific branch in the same upstream
repo, not re-derived independently) into it.
