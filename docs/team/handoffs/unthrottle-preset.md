# unthrottle-preset handoff

Branch: worktree-wf_582d1cc2-be7-1 (CI branch ci/unthrottle-preset). Worktree: .claude/worktrees/wf_582d1cc2-be7-1 (under the repo root)
Last pushed commit: c113d5eca (code d8b937498 + empty request commit).

CI runs (ci/unthrottle-preset):
- 40078755889 trajectory-probe push (fw=engine.scroll:unthrottle, both engines): running
- 40078755847 toolbar-throttle push (arms rewrite, unthrottle, original): running
- 40078755885 lean push: running
- 40078781031 chromium-counts dispatch fw=engine.scroll:unthrottle swipe-v1 x3 (dispatch 1 of 3; layers with position absolute + guard): running

Verified: Lean EngineScrollUnthrottle.lean (position field, `(pointer: coarse)` guard theorems guard_keeps_ios, guard_lifts_ios, guard_fine_noop,
guard_fine_cost; relevantAnimations named on `Anim`); check.sh green at d8b937498; vitest src/parts/engine.scroll pass; measure-webkit throttle tests pass.
Open: read the four runs; decide absolute vs fixed from the layers; record trajectory (Gen.record), set ledger row proved, Gen.run, gate dispatch on v2-proved; note + v2-report section.
Writes outside the task: .github/workflows/toolbar-throttle.yml, packages/measure-webkit/src/throttle/{cli,report}.mjs, packages/measure-webkit/test/throttle-report.test.mjs, apps/site/src/registry/presets/v2-proved.json (generated).
