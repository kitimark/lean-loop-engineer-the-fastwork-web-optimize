# Handoff: tween-platform-scope

**State.** Branch `worktree-wf_c156a96a-23d-1`: Lean 8e92404b, TS 50dbdd6e, then the note, results and this file.
CI branch `ci/tween-platform-scope` is at 50dbdd6e.

**Verified.**
- `lean/Fw/Parts/MorphTweenOpt.lean`, "MT-R, the scoped arm": `registrationsScoped_rule`, `registrationsScoped_see`,
  `scoped_scope_le`, `platform_morph_local`, `fade_eq`, `waapi_section_finding`, `orig_below_le_waapi`,
  `scoped_below_nil`. Standard axioms only; `sh lean/scripts/check.sh` green.
- Regenerated: morph-tween-waapi.jsonl (34 rows), ops/premise.jsonl, preset decisions, footprint.
- Chromium, touch, 3 runs per arm: scoped is −113 elements per tween frame vs waapi, −3745 per run (MEASURED).
- Gates 39337856330 and 39340504860: the platform row passes in both engines. The only fails are commission
  margin-inline flake cells.

**Open.**
- webkit-sim 39337860689 failed on both attempts with inspector timeouts. The control waapi run 39347940719 passed
  after 2 timeouts. Re-dispatch with `-f target=rewrite -f fw=morph.tween:waapi-scoped`. The WebKit saving is INFERRED.
- Residual: late frames still recalc 117-118 elements per frame above faithful, more than the 24-element nav alone.
  This is the morph-nav-scope follow-up.
- Preset inclusion is the lead's decision. math-view.html is frozen and was not regenerated. inputs.ts is unchanged,
  because no contract reads `--platform-morph`.

**Conventions.**
- `waapi` is the frozen comparison arm. The scoped data is `registrationsScoped` and `readersScoped`. Its golden rows
  carry `"arm":"waapi-scoped"`.
- After editing part.json, regenerate the preset decisions. After editing index.tsx or the driver, run
  part-footprint.mjs --write.

**Read first.** `research/notes/2026/10-20-tween-platform-scope.md`,
`results/tween-platform-scope/chromium-counts.json`.
