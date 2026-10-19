# model-bug-fixes handoff

State: branch `worktree-wf_c8c1d265-fc1-1`. Commits: dc68f310 (B), 259876ef (C), 3b2c6f43 (A, Lean), 821693ef (A, ledger), then a merge of main. Full `lake build` is green (514 jobs, 25 s after the merge).

Verified:
- B: wave-1 refreeze adopted in `packages/measure-chromium/classes.frozen.json`. Regenerated `results/baselines/chromium/**`, `results/faithful/**` and `lean/Fw/Faithful/Measured.lean`. Faithful verdicts:
  - rewrite fails in all six zones: swipe-v1 y04000/y04500/tail with 27/14/14 fails; swipe-touch-v1 with 28/14/10.
  - control passes everywhere.
- C: the Exit fail exemptions are dropped (run 39184687325: all 57 pass). Exit golden is 92 lines.
- A: section `Refuted` at the end of `lean/Fw/Engine/Chromium.lean`. It holds 9 theorems (`crossFrame_total`, `eqO_totals_pass`, `eqO_det_bug`, `det_stale`, `judge_quarantined`, `navHit_functionCall_rejudged`, `mount_layoutCount_rejudged`, `sceneReturn_style`, `waapi_raf_eq_iff`), all on standard axioms.
- Re-judged with engine-check on the adopted classes, using the model-checks CI counts:
  - nav.hitTest FunctionCall: unusable (quarantined), a class finding.
  - mount LayoutCount: pass (stable(4,0), totals 94).
  - scene UpdateLayoutTree ≤o: still a model bug (1851 vs 1850, a forced style pass from getAnimations after removeAttribute).
  - waapi FireAnimationFrame: correct prediction on swipe-v1 is `=o` (no push). The same cause makes compositeFailedBits <o a model bug.
- Ledger notes are in `research/findings/ledger.json` with task `model-bug-fixes` (5 entries).
- Tests pass: engine-check 6, gate-breakpoints 138, measure-chromium 47, runner 1034 (includes typecheck and land-inputs), ci-paths 32. check.sh ran once.

Open (outside this task's write set):
- `lean/Fw/Parts/HiddenPause.lean`: golden rows must add the forced seek pass, or the site must seek before `removeAttribute` in `apps/site/src/parts/engine.scene/index.tsx` (INFERRED fix).
- `lean/Fw/Parts/MorphTweenOpt.lean`: golden row FireAnimationFrame `=o` on swipe-v1, and compositeFailedBits on the reverse row. `<o` needs a push profile.
- Why rAF/FunctionCall/EventDispatch vary across runs is still undiagnosed. Per-part attribution waits for driver-stage-mode.
- The docstring checker was self-run (no helper tool in this session). A fresh `checker` pass is advised.

Read first: the `Refuted` section of Chromium.lean, `research/notes/2026/10-19-model-checks.md`, and the engine-check outputs (regenerate them with `node packages/engine-check/src/cli.mjs --rows <golden> --runs <base>,<run>`).
