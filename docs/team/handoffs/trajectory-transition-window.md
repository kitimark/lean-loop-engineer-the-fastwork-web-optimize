# trajectory-transition-window handoff

State: branch `worktree-wf_473f9c96-555-1`, final commit in the report. No CI dispatch: the stored runs were enough.
Read first: `docs/team/tools/trajectory-probe.md`, section "Transitions in flight".

Done
- Lean `lean/Fw/Gate/Trajectory.lean` adds `settleTable` (from `nav.module.css`), `settleOf`, `startLag` (200 ms),
  `inFlight`, `crossedPass`, `crossed` and `judgeFlight`. `judgeIn`, `bucketVerdict`, `byM` and `byStep` take `d` and `seg`;
  with `d = none` they behave as before.
- Theorems (a): `judgeFlight_self`, `bucketVerdict_self`, `byStep_self`. (b): `judgeFlight_settled`,
  `byStep_settled_differs`. (c): `judgeFlight_outside`. The OR-branches: `judgeFlight_rewrite`, `judgeFlight_window`.
- Golden `casesFlight` (settle, flight, byM and byStep with settle) in `trajectory.jsonl`. `reduce.mjs` is checked against it
  in `trajectory.test.mjs`, including a check that `SETTLE` equals the golden table.
- Runs 39442517769, 39453181962 and 39455284967 were re-reduced from their raw files with the new `cli.mjs summary` and
  re-recorded. `Gen.run []` then admits all 8 candidates to `v2-proved`.

Verified: gate-breakpoints tests 314 pass, ci-paths 47 pass, runner land-inputs 55 pass, site v2-proved 3 pass, site
typecheck ok. `lean/scripts/check.sh` result is in the report.

Open
- The kit reads a WebKit mid-transition colour as oklab `[1000,0,0,α]` (owner: `kit.mjs`). Recording
  `document.getAnimations()` would replace the `since` bound.
- `since` sees only nav class changes. `startLag` is MEASURED (overrun 140 ms), not proved.
- Coverage `new` groups are a separate issue. In 39455284967 they make mac morph unjudged.
- A stored pass is not re-checked when a flag's part changes (`Stored.sha` is unread).

Conventions: the Bash hook refuses compound commands, so use script files in the scratchpad. Run
`lake build Fw.Gate.Trajectory` before the golden script.
