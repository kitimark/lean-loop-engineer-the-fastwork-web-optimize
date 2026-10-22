# Handoff: morph-touch-band

Branch `worktree-wf_75b957a6-e11-1`, worktree `.claude/worktrees/wf_75b957a6-e11-1`, CI branch `ci/morph-touch-band`.
Last measured sha: c42b1e17 (empty probe commit on fba3b699).

CI runs (push of c42b1e17):
- trajectory-probe 39778906252: in progress (fw=morph.mount:band,morph.tween:band, engines both)
- lean 39778906504: in progress
- wktr-fixtures 39778906223: in progress

Verified:
- `lean/Fw/Parts/MorphListen.lean`: `hub_eq_base` (merged listener = per-part listeners on every event sequence),
  `hub_prevented`, `band_same`, `seq_quiet`, `armed_in_band` (band premise as hypotheses), replay pan check on
  `user-fixture.json` and `swipe-touch-v1.json`; golden `packages/contracts/golden/parts/morph-listen.jsonl` by `#guard`.
- TS: `apps/site/src/parts/morph.mount/listen.logic.ts` and `listen.ts` (hub), golden + hub tests in
  `listen.golden.test.ts`; variants `band` in both part.json; site tsc clean, morph vitest green.

Open:
- Breakpoint gate with the flags needs a dispatch (lead): `pnpm -s fw run --gate --ref ci/morph-touch-band
  --fw morph.mount:band,morph.tween:band --engines both`.
- WebKit touch-to-first-scroll (base vs flag, >= 3 runs) has no lane: needs a probe mode in packages/measure-webkit
  (passive touchstart timeStamp to the first rAF with a scrollY change), outside this task's writes.
- Generated files outside the task globs: `lean/Fw/Parts/FootprintData.lean`, `footprint.gen.json`,
  `packages/contracts/golden/preset/v2-proved.decisions.jsonl`; import of MorphListen sits in MorphTweenOpt.lean
  (MorphMountOpt is in the fwcore cone, which may not include_str files outside lean/).

Read first: MorphListen.lean sections "The window" and "Band", then listen.ts.
