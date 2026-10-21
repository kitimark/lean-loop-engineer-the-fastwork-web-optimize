# macos-teardown-trim (measure-engineer), branch worktree-wf_d205ef06-ea2-1, CI branch ci/macos-teardown-trim

State: webkit-sim.yml trimmed; Lean allowlist, golden and lint cover all five macOS workflows. Two GitHub runs measured.

Read first: `lean/Fw/Ci/Steps.lean` (rows, `checkJob`, `upload_survives`), `scripts/ci-steps-lint.mjs`, the sim job tail of
`.github/workflows/webkit-sim.yml`, `research/notes/2026/10-21-macos-minutes.md` (rank 4).

What changed
- `Fw.Ci.Steps`: allowlist of the steps after the measurement step (five macOS jobs), lint decision `checkJob`,
  theorems `upload_runs_on_success`, `only_telemetry_after_upload`, `webkit_sim_no_teardown`, `upload_survives`.
- Golden `packages/contracts/golden/ci/steps.jsonl` (generator `lean/scripts/StepsGolden.lean`, `--check` in check.sh).
- `scripts/ci-steps-lint.mjs` (TS stand-in of `go`/`tailAfter`/`checkJob`, replayed against the golden by
  `scripts/ci-steps-lint.test.mjs`); wired into the root `lint` script.
- webkit-sim sim job: no Simulator shutdown/delete step, "Keep logs" is only the `cp` (no timeout), "Host state on
  failure" runs on `failure()` only (continue-on-error, no timeout), `ios_webkit_debug_proxy` kegs cached per image build.
- Writes outside the task's graph writes: `lean/Fw/Ci/Trigger.lean` (cache writer `iwdp`, `macosCaches`, excluded from the
  seeders), `packages/contracts/golden/ci/triggers.jsonl` (regenerated), `lean/scripts/check.sh`, `lean/Fw.lean`, root `package.json`.

Measured (GitHub, webkit-sim, cell original/430/1; basis for the figures in the report)
- run 39624847034 (iwdp cache MISS): iwdp step 17 s, boot 198 s, measure 23.4 min, Keep logs 20 s, upload 52 s, telemetry 75 s.
- run 39631161575 (iwdp cache HIT): iwdp step 2 s, boot 181 s, measure 20.5 min, Keep logs 11 s, upload 80 s, telemetry 21 s.
- Removed by absence: "Shut down and delete the Simulator" (16 s in the note). Host-state step skipped on success in both.
- Per run on a hit about 38 s (16 + about 10 + 12); per day about 17 job-min at 27 jobs/day. INFERRED, n=1 per state.

Open items
- Follow-up: trim the Simulator teardown in wktr, wktr-fixtures, engine-premises, gate-gaps (the lint prints them as
  "follow-up"; change the Lean rows, regenerate the golden, then the workflow).
- Larger teardown costs seen: upload-artifact 52-80 s and the telemetry finish 21-75 s; "Complete job" takes about 3 min.
- Measure step moved 20.5-23.4 min vs the note's 16.1 min median: different cells, not comparable; it is not part of this task.
- The Keep-logs timeout class (3 failed cells, 42 job-min) is counted in rank 2 (webkit-sim-target-lost), not here.
