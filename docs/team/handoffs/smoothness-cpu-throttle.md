Branch: worktree-wf_92f26323-31b-1 (CI branches ci/smoothness-cpu-throttle-1x, ci/smoothness-cpu-throttle-6x)
Worktree: .claude/worktrees/wf_92f26323-31b-1 (under the repo root)
Last commit: 7ec80d5dc (empty commit carrying the round-b 6x CI lines; code commits dcc222721, 000fa5781; round-a results 1517d1697)

CI runs (workflow smoothness, 3 jobs per width, widths 390 and 1280)
- 39924675073 ci/smoothness-cpu-throttle-1x, round a, 1x: complete. cand = a copy of base (the `[trajectory ...]` text sat on the title line, not its own line, so no flags were parsed). Results: results/smoothness-throttle/a-empty-cand/.
- 39924693045 ci/smoothness-cpu-throttle-6x, round a, 6x: complete, same flaw.
- 39927164863 ci/smoothness-cpu-throttle-1x, round b, 1x, cand = look flags `morph.tween:scroll-lock,nav:earn-no-transition`: running
- 39927184622 ci/smoothness-cpu-throttle-6x, round b, 6x, same cand: running
This is the 4th run: no more runs.

State
- Built: `Emulation.setCPUThrottlingRate` in `launch.mjs` (`setCpuThrottle`), applied in `cadence.mjs` after the page is ready and before the recorder starts; `throttle.mjs` allowlist 1 or 6;
  `--cpu-throttle` in `cli.mjs`; `cadence-table.mjs` carries `cpuThrottle` per cell and refuses to mix throttles in one table; `smoothness.yml`: `workflow_dispatch` inputs `cpu_throttle` (1|6, default 1), `fw`, `widths`; a push says `[cpu-throttle=6]`; no traced reps under a throttle; the site build prerenders the candidate query when a throttle is asked for.
- Verified: package test 651 pass, ci-paths test 54 pass, actionlint clean; local CDP sanity (busy loop 32 ms at 1x, 181 ms at 6x; not a result).
- Open: round-b tables to `results/smoothness-throttle/{1x,6x}`, the note `research/notes/2026/10-2x-smoothness-throttle.md`, ranking against WebKit run 39634194664 and the phone session results/phone/2026-10-21.
Read first: research/notes/2026/10-2x-smoothness-probe.md, 10-2x-smoothness-webkit.md, docs/team/tools/smoothness-probe.md.
Tables: `gh run download <id> -D <dir>/<id> -p 'smoothness-*'` then `node packages/gate-breakpoints/src/smooth/cli.mjs cadence --runs <dir> --out <out>` (one dir per throttle).
Lesson: the `[trajectory ...]` text must start its own commit-message line.
