# macos-vm-upload (measure-engineer)
Branch: worktree-wf_12081826-6bc-1
Worktree: .claude/worktrees/wf_12081826-6bc-1
Last code commit: a52762158 (empty [ci:webkit-sim] commit on top of merge 48684421e); CI branch ci/macos-vm-upload
CI runs: webkit-sim run 40259432097 on ci/macos-vm-upload at a52762158 (push 1 of 2), state complete (success). Artifacts: sim-tick-v1-1..4 (ticks: period@423s, pass@463s with pass-1.part, period@885s, done@1009s with pass-2.part; probes.jsonl 91/99/164/176 lines), webkit-sim-v1, telemetry-sim-v1.
State: complete. Merged main again after the run (HEAD eb54d16bd, no workflow change); check.sh, runner tests (3662) and tick tests green after it. Dry land VERDICT dry macos-vm-upload; review ready = review. Only the land remains (lead).

Verified (local, through fw slot): check.sh green before and after the merge of main; apps/runner test 116 files /
3662 tests green; node --test scripts/ci-paths.test.mjs + scripts/ci-telemetry/tick.test.mjs 68 pass; fw plan lint 0
errors, no writesClosure line for this task.
Verified on run 40259432097: per-pass artifacts plus >= 2 sim-tick-<vm>-<n> probe uploads, with probes.jsonl inside them.

In: Lean `Fw.Ci.Telemetry` cadence and wake rule (first_upload_before_cap, two_periodic_ticks), golden
`packages/contracts/golden/ci/telemetry.jsonl`, `scripts/ci-telemetry/tick.mjs` + test, 8 tick steps in
`.github/workflows/webkit-sim.yml`, exit 6 mapped in `apps/runner/src/land-remote.ts` + test, `docs/team/tools/ci-telemetry.md`.

Open: toolbar-throttle.yml needs the same edit after toolbar-sim-lane lands; with more than 1 session per VM the 8 tick
steps can run out before the measurement ends; cause of lost VMs stays UNKNOWN until a lost job leaves the new evidence;
at most 2 CI pushes on free macOS runners (1 used after this push).
Then: dry land (`pnpm -s fw slot run --kind land --cache -- pnpm -s fw land
worktree-wf_12081826-6bc-1 --task macos-vm-upload --dry`), `fw review ready`.
Read first: lean/Fw/Ci/Telemetry.lean, scripts/ci-telemetry/tick.mjs, .github/workflows/webkit-sim.yml.
