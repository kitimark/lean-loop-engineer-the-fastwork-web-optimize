# morph-constant-bounds (part-builder) checkpoint

- Branch `worktree-wf_966da1fd-1d2-1`, worktree `.claude/worktrees/wf_966da1fd-1d2-1`, CI branch `ci/morph-constant-bounds`.
- Code commit 03afae6b (Lean, goldens, flag, footprint, preset); results commit follows.
- Runs (dispatches used 3 of 4): breakpoint-gate engines both 39744563175 running; webkit-sim base (lag=true cost=on, target rewrite)
  39744614747 running; webkit-sim flag (`fw=morph.panel:const-bounds`) 39744653093 running.

## Verified
- Lean `lean/Fw/Parts/MorphConstBounds.lean`: `paint_eq`, `visible_iff`, `frame_on_nav`, `pivot_same`, `newBox_const`,
  `frame_eq_orig`, `orig_resizes_h/w`, `frame_inside`, `tail_invisible`, `colW_mono`, `pitch_scaled_ne`; golden
  `packages/contracts/golden/parts/morph-const-bounds.jsonl` (144 rows, `#guard` against the file).
- Site: `morph.panel` variant `const-bounds` (index.tsx frame wrapper, morph.module.css `.cb` / `.frame`), test
  `const-bounds.golden.test.ts` evaluates the CSS calc strings against the Lean rows; site test and typecheck green.
- Footprint and preset regenerated at 03afae6b.

## Open
- Read the three runs; cost-report; ledger row, note, report.json; check.sh at the end; dry land.
- PathPix has no lane code (its handoff), so same-look pixels are Lean-only here.

## Conventions
- Golden regen: copy MorphConstBounds.lean without the `include_str` line into the scratchpad, add
  `def main := IO.print boundsJsonl`, `lake env lean --run`.
- Tracks (columns) are not made constant: `pitch_scaled_ne` shows scaling the final layout changes the gap pitch.
