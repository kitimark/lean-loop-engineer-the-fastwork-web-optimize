- Branch worktree-wf_ec961771-f21-1, worktree .claude/worktrees/wf_ec961771-f21-1, last commit see `git log -1`.
- CI runs: none. No ci/flip-accel-webkit push was made (the variant is the identity; see below). No run ids exist for this task.
- Result (CONFIRMED, Lean + WebKit@862f17d source): the end-of-page flip animates translate, scale, transform, opacity, filter, backdrop-filter; all six are
  `animation-wrapper-acceleration: "always"` (CSSProperties.json). `FlipAccel.forcing_tracks_zero`: 0 recalc-forcing tracks at 12 band viewports (43/51/52 tracks).
  `accelOnly_id` + `same_look`: the accelerated-only variant equals the original in every frame, so no flag, no class-L variant, no WKTR arm.
- Premise refuted: the floor is not a property class. Runtime state decides ticking (ticksContinuouslyWhileActive, KeyframeEffect.cpp:2724-2746); earlier runs
  (geom-pref-off-ticking) read steady state 47 accelerated / 0 ticking, plus a start-up transient S1 of 21 tracks. INFERRED: the 3-frame end-floor reps sit in that transient.
- Files: lean/Fw/Parts/FlipAccel.lean, FlipAccelGen.lean, lean/scripts/FlipAccelGolden.lean, check.sh job, Trigger.lean rows + triggers.jsonl, golden
  packages/contracts/golden/parts/flip-accel.jsonl, apps/site/src/parts/morph.geom/flip-accel.golden.test.ts, research/notes/2026/10-30-flip-accel-webkit.md, ledger (1 entry).
- Verified: lake build FlipAccelGen; golden regenerated and check job added; vitest flip-accel.golden.test.ts 3 pass; @fw/site test via fw slot green.
- Open: the pinned-unit WKTR measurement is not delivered (reason above). Next test: frame-pinned window (end-floor-window) + per-frame ticking probe; any start-up
  change (promote layers before push, create tracks before commit) needs its own same-look proof and is class L until proved (geom-prewarm was parked for moving layout).
- Read first: research/notes/2026/10-30-flip-accel-webkit.md, then 10-2x-geom-pref-off-ticking.md and 10-2x-end-floor-writes.md.
