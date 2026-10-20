# Handoff: tween-platform-scope

**State.** Branch `worktree-wf_c156a96a-23d-1`. Lean commit 8e92404b, TS commit 50dbdd6e, and a final commit with the note,
results and this file. CI branch `ci/tween-platform-scope` is at 50dbdd6e.

**Verified.**
- Lean MT-R scoped arm in `lean/Fw/Parts/MorphTweenOpt.lean`:
  - theorems `registrationsScoped_rule`, `registrationsScoped_see`, `scoped_scope_le`, `platform_morph_local`, `fade_eq`,
    `waapi_section_finding`, `orig_below_le_waapi`, `scoped_below_nil`;
  - standard axioms only; `sh lean/scripts/check.sh` green.
- Regenerated goldens: morph-tween-waapi.jsonl (34 rows), ops/premise.jsonl, preset decisions, footprint.
- Chromium counts, 3 runs per arm: on touch, scoped is −113 elements per tween frame vs waapi, −3745 per run (MEASURED).
- Gate 39337856330: the platform row passes in both engines. The only Chromium fail is the commission flake.

**Open.**
- Gate re-run 39340504860: the platform row passes again; only commission margin-inline flake cells fail (2).
- webkit-sim 39337860689 failed on both attempts (inspector timeouts). Control waapi 39347940719 passed after 2
  timeouts. Re-dispatch with `-f target=rewrite -f fw=morph.tween:waapi-scoped`. The WebKit saving is INFERRED.
- Residual: in late frames scoped still recalcs 117-118 elements per frame above faithful. It is not the 24-element nav
  alone. Follow-up: morph-nav-scope.
- Preset inclusion is the lead's decision.
- `docs/plan/math-view.html` is frozen and was not regenerated. `apps/site/src/stage/inputs.ts` is unchanged: no
  contract reads `--platform-morph`.

**Conventions.**
- `waapi` is the frozen comparison arm. Scoped data lives in `registrationsScoped` and `readersScoped`.
- Golden rows carry `"arm":"waapi-scoped"`. The TS test splits rows by that key.
- After editing part.json, regenerate the preset decisions (Gen.lean). After editing index.tsx or the driver, run
  part-footprint.mjs --write, because the footprint records line numbers.

**Read first.**
- `research/notes/2026/10-20-tween-platform-scope.md`
- `results/tween-platform-scope/chromium-counts.json`
- MorphTweenOpt section "MT-R, the scoped arm"
