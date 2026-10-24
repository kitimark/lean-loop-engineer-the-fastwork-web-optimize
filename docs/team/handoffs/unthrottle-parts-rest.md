Branch: worktree-wf_b72af43c-e06-1
Worktree: .claude/worktrees/wf_b72af43c-e06-1 (under the repo root)
Last commit: 87a4e4b3c (work); this handoff is the next commit
CI runs: none dispatched (task reads run 40101702393 from its downloaded artifacts; no new CI dispatch allowed)
Verified: ThrottleParts.lean builds; golden regenerated (794 lines) and --check up to date; test/throttle-parts.test.mjs 35 pass. Slot check/test, ci-paths, land-inputs, plan lint and dry land: see the report.
Open: independent commission measurement under the snap class (the fit is post-hoc, INFERRED); platform anchor not found; why the original arm ran at about 60 ms in round 1.

## State
- Lean: `judge` pools passes with K at least `minK` (3); `judgeCounts` is the old count form (240 vectors). New: shape `snap` (commission), `commission_snaps_up`, `enterFollow_rising`, `throttleK_band_iff` (converse of `throttleK_mem_band`), `minK_iff`, `bandFor_rest`, `drop_in_band_low`, `drop_out_of_band`, `hit_throttled_cadence`.
- Golden: 468 pass-list `judge`, 240 `judgeCounts`, 40 `partVerdict`, 13 `bandFor` (with `inDomain`, `fixed`). Regenerate with `lake env lean --run scripts/ThrottlePartsGolden.lean`; never by hand.
- parts.mjs: `poolOf`, `inDomain`, `judge`, `judgeCounts`, `bandFor` are twins replayed from the golden; `armSeries` emits per-pass detail, `medianGapMs` over exercised passes (midMoving above 0); `judgeArm`, `partOf`, `noDataReason`, `captureRow` are TS reporting.
- Results: `results/unthrottle-parts/rest-40101702393.{json,md}` re-reduced (people.card agree (partial), commission agree). drags and finish summaries keep the old schema.

## Conventions
- minK 3 is a modelling choice (INFERRED), not an engine fact. K is per pass, from that pass's median frame gap.
- The commission class change is a post-hoc fit; do not call it confirmed.
- Shell here refuses compound commands and heredocs; use plain commands and the Write/Edit tools.

## Read first
research/notes/2026/10-2x-unthrottle-parts-rest.md, then lean/Fw/Device/ThrottleParts.lean (sections Snap, domain, golden).
