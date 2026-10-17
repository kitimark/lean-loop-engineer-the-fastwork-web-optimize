# why-core-lessons (lean-prover)

State: branch of this worktree, commit "why-core-lessons: ..." on top of main 53d0262 (main merged after, see git log).
`sh lean/scripts/check.sh` green; key theorems use only propext, Quot.sound, Classical.choice.

Done
- Overcount CONFIRMED (Chromium document.cc:2757-2762@f842f52, WebKit Document.cpp:3042-3043@862f17d):
  `Fw.Engine.frameWork_overcount`. Faithful count `frameWorkE E f endDirty` = forced + [touched and endDirty]
  added beside `frameWork` (non-breaking, a parameter, not a FrameIn field, because Parts were frozen).
- Core end-dirty algebra over `FlagOp` (check/dirty/neutral): flagForced/flagEnd/flagTotal, append laws,
  `flagTotal_closed` (total = [d and first non-neutral is not dirty] + dirtyRuns), `flagTotal_remove_check`,
  `frameE_le_of_cover`.
- `lean/Fw/Engine/Lessons.lean`: L1-L6 (comp move, shift, resident-only, absorption, pause, reader removal).
- `lean/Fw/Engine/Visual.lean` end: roundQ, toy rasters refuting raster_path (C4 fracAlpha, C5 fracXf),
  `PathPremises5`/`shown_eq5`, double rounding, alpha999, over=lerp, crossfade within 1 LSB, alpha_one_iff
  (<= 1/510, corrects the ledger's <), occlusion, rounded-rect rigidity (axis-aligned only).
- research/findings/ledger.json updated by script (indent 1, no trailing newline): 12 missingWhy closed,
  4 narrowed/retargeted (n=10 x2, 14, 25), n=22 union lemma corrected (needs `updates`).

Open (lead sequences)
- Migrate Parts from `frameWork` to `frameWorkE` (or make endDirty a FrameIn field): NavHitTestOpt (move `fin`
  into Core via a bridge forced_rho d as = flagForced d (as.map (toFlag . rho))), EngineScroll, PeopleCard
  gate_lt_forced (saving 2 -> 1, verdict unchanged), PainNotes, MorphMountOpt, Golden forcedCountsBatched rows
  (forced-only; as totals pilot batched style is 2/1 not 1/0).
- Deferred missingWhy: n=2 observers, n=19 mount kind, n=20 relayout propagation, n=10 WebKit tick clause and
  general-affine rigidity, n=14 area x ops cost, n=25 error bound for eps > 1/510.

Read first: Core.lean section "End-dirty", Lessons.lean module doc, ledger finding n=1 mechanism.
