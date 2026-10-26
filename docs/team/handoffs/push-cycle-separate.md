branch: worktree-wf_99fed9ac-b8f-1 (CI branch ci/push-cycle-separate)
worktree: .claude/worktrees/wf_99fed9ac-b8f-1 (under the repo root)
last commit: see `git log -1` (updated after each run)
runs: 40284577163 (push 1 of 3, at fec40a04c, per-cycle xcodebuild design, sims 2 and 3 failed, 1 cancelled stale: evidence only); 40297879483 (push 2, at 61697a111, FinishServer design, vms 1-3 done, 4-6 running); 40315679172 (push 3 of 3, at ae47dfd3c, bundle-removal fix, running)
verified: Lean rule + golden (check.sh green), TS twin and report tests (measure-webkit 914 pass), ci-paths 56 pass, actionlint clean for the lane edit
open: verdict per arm, H4 reading, note, ledger row, dry land, review gate

What was built
- lean/Fw/Measure/PushCycle.lean: sepVerdict (cycle-vs-clock, theorem per branch), across/readCensus, restMs, golden packages/contracts/golden/measure/push-cycle.jsonl.
- packages/measure-webkit/src/throttle/push-cycle.mjs: twin + glue (periodMs, activeQuiet/activeCycles, sepArm, censusSeries are TS stand-ins with no Lean golden).
- push-cycle-pass.mjs: profile full (12 cycles, one touch run) and dwell (6 one-cycle runs, census + rest between). push-cycle-cli.mjs --separate. push-cycle-report.mjs: verdict and census tables.
- .github/workflows/toolbar-throttle.yml: background measuring step with tick uploads (own commit) and the [throttle:push-cycle-separate] lane (6 jobs, rewrite,user).

Conventions
- Metric: slow50 frames per cycle, cycles 3..5 by index versus clock-matched index; a side under 3 passes is undecided.
- Counted window per cycle = open stretch + 8 s; everything else is masked in both profiles.
- Run: commit message with `[ci:toolbar-throttle] [throttle:push-cycle-separate]`, `git branch -f ci/push-cycle-separate HEAD`, `git push origin ci/push-cycle-separate`; wait `pnpm -s fw ci wait --branch ci/push-cycle-separate`.
- Artifacts: `gh run download <id> -n toolbar-throttle-<vm> -D <dir>`; apply sepArm via `node packages/measure-webkit/src/throttle/push-cycle-cli.mjs report --in a.json,b.json`.

Read first: this file, then research/notes/2026/10-2x-push-cycle-separate.md (when written), then lean/Fw/Measure/PushCycle.lean from `sepVerdict`.
Pre-existing, not ours: scripts/ci-steps-lint.test.mjs fails on `path-pix.yml: uncovered:sim-draw` (path-pix.yml and Steps.lean unchanged by this branch).
