# trajectory-probe-speed handoff

State: branch `worktree-wf_fe20256e-e16-1`, ci branch `ci/trajectory-probe-speed`. Read first: `docs/team/tools/trajectory-probe.md`
("Legs and paths", "Measured").

Done
- Lean decides the jobs of a dispatch (`lean/Fw/Gate/Trajectory.lean`: `walks`, `legs`, `enginesOf`, `plan`, theorems incl.
  `plan_mac_morph`); golden rows `op: plan` in `packages/contracts/golden/gate/trajectory.jsonl`; node twin
  `packages/gate-breakpoints/src/trajectory/plan.mjs` checked against it.
- Workflow `.github/workflows/trajectory-probe.yml`: width legs (matrix), `merge` / `merge-apple` jobs rebuild the unchanged
  artifacts, probe-apple runs for every dispatch with playwright-webkit (hero + morph), reps 5, `timeout-minutes: 15`.
- Runs 39453181962 and 39455284967 (8 candidates as preset `v2-proved`) recorded with `Fw.Preset.Gen.record`; `v2-proved`
  regenerated with `Gen.run []`: 0 members.
- Cap: `Fw.Ci.Pool.Caps` row `trajectory-probe` / `probe-apple`, n 4, p90 11.2 min, cap 15 (thin); excluded list now only
  `webkit-sim.yml`; golden `pool-caps.jsonl` regenerated; `ci-paths --check` green.

Verified: gate-breakpoints tests 285 pass, ci-paths test 45 pass, runner land-inputs 55 pass, site v2-proved test 3 pass,
`lean/scripts/check.sh` green at the final commit.

Result per flag (all 8 equal): chromium hero/morph pass, webkit hero pass (linux + mac), mac-webkit morph FAIL in both runs
-> shared run so the cell stays pending -> `pending: trajectory`, nothing admitted.

Open
- Mac morph fail = `nav.background-color` at 641 and 1280 on approach steps a*, a colour transition sampled mid-flight (the
  original shows the same values). Fix is a Lean `judge`/`outcome` change (approach windows), outside this task's writes.
- A single-flag `--fw` run per flag would settle the cells (a failing run of the flag alone falsifies, a passing one passes);
  cost 8 macOS dispatches, over the 6 allowed.
- Cap is `thin` (4 successes); re-derive at 10. `mergeRaws` is a TS stand-in (glue, no Lean spec).

Conventions: Bash hook refuses compound commands; use script files in the scratchpad. Rebuild with `lake build <module>` before running a golden script (it reads the compiled olean).
