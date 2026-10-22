# Handoff: morph-touch-band

Branch `worktree-wf_75b957a6-e11-1`, CI branches `ci/morph-touch-band` (de61db3a), `ci/morph-touch-band-tween` (7fd7c482).
Ledger row `morph.touch-band` (n 46, partly-proved, both flags) in `research/findings/ledger.json`.

CI runs (trajectory-probe):
- 39778906252 (both flags): failed at smoke; `?fw=a,b` is not prerendered, so each flag is probed alone
- 39779755536 (morph.mount:band): webkit CLEAN 4000/4000; chromium RED, 42 rows `w=390 ... NEW open@1=coverage`
- 39781320030 (morph.mount:band, rerun): webkit CLEAN; chromium RED with the same 42-row miss at w=641, while the
  faithful arm missed it at w=640 (both=42), so a sampling miss of the first open push, not the flag (INFERRED)
- 39779781978 (morph.tween:band): CLEAN on both engines

Verified:
- `lean/Fw/Parts/MorphListen.lean`: `hub_eq_base`, `hub_prevented`, `listeners_merged_le`, `band_same`, `seq_quiet`,
  `armed_in_band`; pan premise on the replay profiles; golden `morph-listen.jsonl` by `#guard`.
- TS hub in `apps/site/src/parts/morph.mount/listen.ts`, tests in `listen.golden.test.ts`; `band` in both part.json.
- check.sh green; site tests green; ci-paths and land-inputs green.

Open:
- Gate per flag (lead): `pnpm -s fw run --gate --ref ci/morph-touch-band --fw morph.mount:band --engines both`, same
  with `--fw morph.tween:band`.
- WebKit touch-to-first-scroll (>= 3 runs) has no lane: needs a probe mode in packages/measure-webkit.
- Both flags together cannot be gated or probed: the workflows build no multi-flag search.
- Outside the globs: ledger row, FootprintData.lean, FootprintRows.lean, footprint.gen.json, footprint-diff.gen.json,
  v2-proved.decisions.jsonl (all generated except the ledger).
- MorphListen is imported from MorphTweenOpt.lean, because MorphMountOpt is in the fwcore cone, which may not include_str files outside lean/.
- The pan premise reads `morph-listen.profiles.jsonl`, since check.sh may read only `CHECK_SH_READS`.

Read first: MorphListen.lean sections "The window" and "Band", then listen.ts.
