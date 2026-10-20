# waapi-threshold-attr handoff

State: branch `worktree-wf_be3f7e90-9a2-2`, pushed as `ci/waapi-threshold-attr`. `sh lean/scripts/check.sh` is green.

Verified:
- Lean (`lean/Fw/Parts/MorphTweenOpt.lean`):
  - `attrReaders` lists the 9 strict threshold readers of `data-fw-morph`. `AttrScene`/`attrScene` is the reader scene.
  - `ASt`, `stepAttr` and `runAttr` model the attribute as a function of the writer's write times. The old writer is `oldW`; the fixed one is `fixW dl` (finish or marker poll).
  - Proved: `fixW_ok`, `attr_band` (attribute in the original's band every frame), `dlLo_sound`, and `waapi_vis` restated over `AttrScene`.
  - The old driver's counterexample is `old_attr_stale`, plus a `#guard` on both replay cases.
- Golden: `packages/contracts/golden/parts/morph-tween-waapi.attr.jsonl`, generated from `attrJsonl ()` and pinned by `include_str`.
- Driver (`apps/site/src/parts/morph.tween/waapi.driver.ts`):
  - One target-less marker animation per threshold ahead (`hasMarker`), each finishing 1 ms before its crossing.
  - `onMarker` writes; while the value is not yet strictly past, it writes each frame until it is.
  - The driver writes on push and at finish, and dedupes writes.
  - Fake replay cost: 7 script frames of 42 (open), 13 of 64 (reverse at 300 ms).
- Tests: apps/site test and typecheck, contracts test, runner land-inputs/ledger-merge/premises, ci-paths.

Not delivered / open:
- The CI trajectory probe needs a lead dispatch:
  - `pnpm -s fw run --trajectory --ref ci/waapi-threshold-attr --fw morph.tween:waapi --reps 2`
  - the same with `--fw morph.tween:waapi-scoped`
  - an A/A run without `--fw`
- probe-apple (macos-26) runs the hero path only, so the macOS WebKit morph path needs a workflow change.
- The ledger rows keep status `refuted`; re-admission belongs to trajectory-admission.

Conventions:
- To regenerate the attr golden, comment out the `include_str` guard, then `lake env lean --run` a script that writes `attrJsonl ()`, then restore the guard.
- The footprint goldens (FootprintData, FootprintRows, footprint*.gen.json) are regenerated (outside task writes), and they now carry an `unresolved-target` finding at index.tsx:103 (`startTime` of the target-less marker).

Read first: MorphTweenOpt.lean, from `attrReaders` to `waapi_vis`; then waapi.golden.test.ts.
