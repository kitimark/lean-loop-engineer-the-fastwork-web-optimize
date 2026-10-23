Branch: worktree-wf_92f26323-31b-1 (CI branches ci/smoothness-cpu-throttle-1x, ci/smoothness-cpu-throttle-6x)
Worktree: .claude/worktrees/wf_92f26323-31b-1 (under the repo root)
CI tips 7ec80d5dc (6x) and b65f29dc5 (1x)

CI runs (workflow smoothness, 3 jobs per width, widths 390 and 1280), all complete, 4 of 4 runs used
- 39927164863 ci/smoothness-cpu-throttle-1x, round b, 1x, cand = look flags `morph.tween:scroll-lock,nav:earn-no-transition` (main result)
- 39927184622 ci/smoothness-cpu-throttle-6x, round b, 6x, same cand (main result)
- 39924675073 and 39924693045, round a (1x, 6x): cand = a copy of base (the `[trajectory ...]` text sat on the title line, not its own line); supplement for orig/base/aa only

Verified
- Package test (@fw/gate-breakpoints) green, ci-paths test 54 pass, actionlint clean; local CDP sanity (busy loop 32 ms at 1x, 181 ms at 6x; not a result).
- Finding (note research/notes/2026/10-2x-smoothness-throttle.md): 6x lags every window and every arm alike; every Lean pair verdict "not told apart" (A/A spread 6.6 to 14.8 points); the WebKit hero gap (orig worst) is not reproduced. PROXY only.
Built: `setCpuThrottle` (launch.mjs), applied in cadence.mjs before the recorder; `throttle.mjs` (allowlist 1|6); `throttle-table.mjs` + `cli.mjs throttle` (1x beside 6x); `cadence-table.mjs` carries `cpuThrottle` and refuses mixed tables;
`smoothness.yml`: dispatch inputs `cpu_throttle`, `fw`, `widths`, push token `[cpu-throttle=N]`, no traced reps under a throttle, site build prerenders the candidate query for a throttle run.
Open
- Dispatch not made (none needed: both throttles ran by push). A dispatch with `cpu_throttle=6` also works once the workflow is on main.
- TS stand-ins: throttle.mjs, throttle-table.mjs, the shell allowlist in the workflow. A Lean rule for a 6x-tuned spread is not written (needs more than 3 samples); lead to sequence.
- docs/team/tools/smoothness-probe.md not updated (outside the task writes): add the `cpu_throttle` input, `[cpu-throttle=N]` and the own-line rule for `[trajectory ...]`.
Conventions: the `[trajectory ...]` text must start its own commit-message line; one table directory per throttle.
Tables: `gh run download <id> -D <dir>/<id> -p 'smoothness-*'`, `node packages/gate-breakpoints/src/smooth/cli.mjs cadence --runs <dir> --out <out>`, `... throttle --a <1x out> --b <6x out> --out compare.md`.
