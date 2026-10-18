# model-checks: F3/F4 engine-check per landed flag arm (Chromium)

Task model-checks, branch `worktree-wf_df082d5f-ac9-2`, CI branch `ci/model-checks`, base commit 698b7755. Status words: MEASURED (a CI run id is cited), INFERRED.

## What changed

- `variantKeys` (apps/runner/src/engine-check.ts:69-74) answered both `target+search` and `target` for a run with a query, so a flag run filled the
  `rewrite` base series of every row. `lean/Fw/Engine/Keys.lean` fixes the rule: one faithful key per run, `runKey`
  (`rewrite` for the default run, `rewrite+?fw=...` for a flag run), proved injective (`runKey_inj`); `answers_base_iff`: only the default rewrite run
  answers `rewrite`. One alias, `hidden-pause`, is answered by a rewrite run whose flags are a nonempty subset of the three hidden-pause arms (INFERRED:
  each arm keeps the `=o` and `<=o` rows). 72 Lean-generated vectors in `packages/engine-check/golden/keys.jsonl`; `src/keys.mjs` equals all of them.
- `packages/engine-check` stages each run under the one variant its key answers and calls the unmodified apps/runner `engine-check`.

## Result (swipe-v1, base run 39130874266: rewrite, no query, 3 runs; every flag run has 3 runs, same image as the frozen classes)

| flag | chromium run | pass / model-bug / unusable | model-bug rows |
|---|---|---|---|
| morph.tween:waapi | 39131146372 | 3 / 1 / 2 | trace.FireAnimationFrame `<o`: 1748 = 1748 |
| engine.scene:hidden-pause | 39131168588 | 2 / 1 / 1 | trace.UpdateLayoutTree `<=o`: 1851 > 1850 |
| morph.columns:hidden-pause | 39131207849 | 3 / 0 / 1 | none |
| morph.countdown:hidden-pause | 39131217951 | 3 / 0 / 1 | none |
| all three hidden-pause arms | 39131249517 | 2 / 1 / 1 | trace.UpdateLayoutTree `<=o`: 1851 > 1850 |
| morph.mount:shift | 39131302530 | 5 / 1 / 2 | metric.LayoutCount `=o`: r2 has one layout one frame later (524/525) |
| hero.countdown:strip,morph.countdown:strip | 39131314391 | 1 / 0 / 0 | none |
| nav.hitTest:hit-skip | 39131343835 | 7 / 1 / 1 | trace.FunctionCall `=o`: sums 2552 = 2552, frames differ |
| nav.hitTest:elements-skip | 39131395370 | 7 / 1 / 1 | trace.FunctionCall `=o`: sums 2552 = 2552, frames differ |
| people.card:shrink | not-run | not on main (registry has only `shell`; goldens name people.card:mq) | |
| pain.notes:arm | not-run | not on main (goldens name pain.notes:visible) | |

The unusable rows are the quarantined types (trace.Layout, trace.Layout.dirtyObjects, trace.Animation.compositeFailedBits): never used.

## Findings (none patched in the model)

- waapi: the model predicts fewer FireAnimationFrame; the arm made none fewer. INFERRED cause: swipe-v1 scrolls with scrollTo and never pushes the
  morph, so the tween never runs. The touch profile pushes the morph, but see below.
- hidden-pause scene arm: one extra style recalc (1851 against 1850 in all 3 runs); the golden claims `<=o`. MEASURED. Columns and countdown arms alone pass.
- hit-skip and elements-skip: the base itself is not frame-exact for trace.FunctionCall (base runs r2 and r3 differ from r1 in 6 frames each), while
  `classes.frozen.json` calls it deterministic. The `=o` verdict is therefore class staleness of the frozen class on this base, not an arm effect (INFERRED).
  Worth a refreeze of the rewrite arm on the current base before the next engine-check.
- morph.mount:shift LayoutCount: the base is frame-exact (3 runs identical); one of the 3 variant runs moves one layout by one frame. The class has no slack for that.

## Not run, with the reason

- swipe-touch-v1 rows (mount 8, strip 1): the touch lane fails on the current base with no flag set: runs 39131406685 (3 jobs) and 39135255809, "touch swipe did
  not finish within maxFrames" (packages/measure-chromium/src/run.mjs:276). Cause not investigated (outside this task); the touch runs of mount (39131436435) and strip (39131489452) failed the same way.
- WebKit: no lane in engine-check (`laneRes_webkit`, lean/Fw/Measure/EngineCheck.lean:605), so a WebKit row is unusable whatever is measured. No WebKit run.
- F1/F2 fixtures: not run (accepted limit).
- Class counts per type are the frozen classes (3 runs per arm, kMax 4, tMax 24); this task adds no new class freeze.

## Deviations

- The golden keys file is `packages/engine-check/golden/keys.jsonl`, not `packages/contracts/golden/engine/keys.jsonl`: the engine-goldens registry
  (scripts/EngineGoldens.lean) and the cite lint (`Fw.Ops.Premise` engineCites) would read a file in that directory as an engine row file; both are outside the write scope.
- The staging copies each counts.json with `meta.variant` set, so apps/runner `variantKeys` is used unchanged.
