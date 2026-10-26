# macos-vm-upload (measure-engineer)
Branch: worktree-wf_12081826-6bc-1
Worktree: .claude/worktrees/wf_12081826-6bc-1 (under the repo root)
Last code commit: 48684421e (merge of main into 4bdb08a56); CI branch ci/macos-vm-upload
CI runs: none yet (push 1 of 2 about to be made; run id added below once listed). State: waiting for push 1.

Verified (local, through fw slot): check.sh green before and after the merge of main; apps/runner test 116 files /
3662 tests green; node --test scripts/ci-paths.test.mjs + scripts/ci-telemetry/tick.test.mjs 68 pass; fw plan lint 0
errors, no writesClosure line for this task.
Not verified: that one CI run shows per-pass artifacts plus >= 2 sim-tick-<vm>-<n> probe uploads. Check on the run:
artifact names, sim-tick-* count >= 2, probes.jsonl inside them.

In: Lean `Fw.Ci.Telemetry` cadence and wake rule (first_upload_before_cap, two_periodic_ticks), golden
`packages/contracts/golden/ci/telemetry.jsonl`, `scripts/ci-telemetry/tick.mjs` + test, 8 tick steps in
`.github/workflows/webkit-sim.yml`, exit 6 mapped in `apps/runner/src/land-remote.ts` + test, `docs/team/tools/ci-telemetry.md`.

Open: toolbar-throttle.yml needs the same edit after toolbar-sim-lane lands; with more than 1 session per VM the 8 tick
steps can run out before the measurement ends; cause of lost VMs stays UNKNOWN until a lost job leaves the new evidence;
at most 2 CI pushes on free macOS runners (1 used after this push).
Then: when the run completes, verify artifacts, dry land (`pnpm -s fw slot run --kind land --cache -- pnpm -s fw land
worktree-wf_12081826-6bc-1 --task macos-vm-upload --dry`), `fw review ready`.
Read first: lean/Fw/Ci/Telemetry.lean, scripts/ci-telemetry/tick.mjs, .github/workflows/webkit-sim.yml.
