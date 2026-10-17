# Handoff: lean-site (breakpoint layer, Lean first)

State at ee04fc4 plus the breakgen follow-up. Read `lean/Fw/Site/README.md` first.

- **Modules** (`lean/Fw/Site/`, Mathlib-free, in `Fw.lean`, 72 theorems, mathview lint clean, standard axioms only):
  - `Breakpoints`: `Px` is an exact rational CSS px. `Env` holds width, height, device width and height, DPR,
    hover, pointer, motion, scheme, media type and forced colors. `MQ` is OR-of-AND syntax with an evaluator and CSS
    and legacy printers. It defines the 30 conditions (`catalogue`). Edge sufficiency: `MQ.eval_congr`,
    `eval_ofNat_congr` and `eval_const_on_band`.
  - `BreakpointFacts`: `*_iff` for every condition. Byte-exact CSS (`catalogue_css`), edges (`catalogue_edges`),
    overlaps as iff, the JS desktop-deck gate, and the fractional gaps.
  - `BreakpointMatrix`: the 124-load matrix. `matrix_observes_every_edge` shows that for every condition and every
    edge it lists, there is a pair at N and N+1 that flips it. Also the edge pairs per profile and the MUI neutral set
    (`matrix_neutral_inert`, `matrix_neutral_hover_both_sides`).
  - `BreakpointGen`: `genJson`, `checkInventory`, `run`, `opBreakpointsGen`.
- **Commands** (from `lean/`):
  - `lake exe breakgen > Fw/Site/breakpoints.gen.json` regenerates the file.
  - `lake exe breakgen --inventory ../research/kickoff/11-breakpoints/breakpoints.json --check Fw/Site/breakpoints.gen.json`
    exits 1 on a byte diff or on an inventory mismatch.
  - fwcore op `breakpoints.gen` returns `{gen, mismatches}`.
- **Consumers:** the site and the breakpoint gate read only `lean/Fw/Site/breakpoints.gen.json`. It holds:
  - CSS strings and TS ids;
  - the edges;
  - the gaps;
  - `neutral` with a reason per entry, for `scripts/media-check.mjs`;
  - per-probe `expect` / `expectNeutral` golden vectors for `matchMedia`.
- **Inventory corrections:** three claims were wrong. They are fixed in the 11-breakpoints README, the JSON and
  `gen-breakpoints.py`.
  - Phone landscape is in the C860 overlap only (`matrix_landscape_overlaps`).
  - At 1024, `c1030` matches by width (`matrix_cross_no_touch_arm`).
  - At 1001, the device-width arm does not flip `c1030` (`matrix_dw_arm`).
- **Modelling choices (INFERRED)** are listed in the Site README:
  - device width equals the viewport width in profile loads;
  - the inputs and DPR for the dark and height probes;
  - the fractional probes use DPR 1.25.
- **mathview fix (at 4d179c3):** `--lint` crashed because one heartbeat budget was shared by the whole export.
  The total was about 204k (thousand heartbeats) against a limit of 200k. The costliest single declaration
  (`BreakpointGen.run`) cost about 3.3k, so no single declaration was the cause.
  - Each declaration now gets a fresh budget (`declBudget`, 200k), and `autoTex` its own (`texBudget`, 50k; past it
    the output is `"?"`).
  - Any exception, including a timeout, becomes the lint failure `export failed` with the declaration's name.
  - The export now records a `heartbeats` count per entry.
  - `lake exe partsgolden` runs `Fw.Parts.Golden`, and its output equals `packages/contracts/golden/parts`.
- **Gaps:**
  - `scripts/check.sh` does not run the `breakgen --check` line yet.
  - The 1100 container edge and the visible overlap outcomes are not modelled. They are still to be MEASURED.
  - Live-resize sequences are not generated yet.
