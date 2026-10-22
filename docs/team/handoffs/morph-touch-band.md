# Handoff: morph-touch-band

Branch `worktree-wf_75b957a6-e11-1`, worktree `.claude/worktrees/wf_75b957a6-e11-1`, CI branch `ci/morph-touch-band`.
Last measured shas: 6fa2cec5 (`ci/morph-touch-band`), 7fd7c482 (`ci/morph-touch-band-tween`), empty probe commits.

CI runs:
- trajectory-probe 39778906252 (c42b1e17, fw both flags): failed at smoke, `?fw=a,b` is not prerendered (the build
  prerenders single-variant pages and presets only), so each flag is probed alone
- trajectory-probe 39779755536 (6fa2cec5, fw=morph.mount:band): in progress
- trajectory-probe 39779781978 (7fd7c482, fw=morph.tween:band): queued

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
- Both flags together (the touch win) cannot be gated or probed yet: the gate and probe builds prerender no
  multi-flag search (`apps/site/scripts/build.mjs --config` is not passed by the workflows).
- Generated files outside the task globs: `lean/Fw/Parts/FootprintData.lean`, `footprint.gen.json`,
  `packages/contracts/golden/preset/v2-proved.decisions.jsonl`; import of MorphListen sits in MorphTweenOpt.lean
  (MorphMountOpt is in the fwcore cone, which may not include_str files outside lean/).
- The pan premise reads `morph-listen.profiles.jsonl` (stroke ys extracted from the replay profiles, kept equal by
  `listen.golden.test.ts`), since check.sh may read only `CHECK_SH_READS`.

Read first: MorphListen.lean sections "The window" and "Band", then listen.ts.
