branch: worktree-wf_67501544-66c-1 (CI branch ci/earn-bound-arm)
worktree: .claude/worktrees/wf_67501544-66c-1 (under the main checkout)
last commit: d8c3fa26 (request commit; code in ac8932ee)

# earn-bound-arm checkpoint 1 (after the first CI push)

CI runs (smoothness.yml, head commit asks for [ci:smoothness] [webkit-cadence] [earn-bound]):
- 39729682403 smoothness: running (3 mac jobs, 3 sim jobs, arms base/aa/bound, holdMs 1400)
Dispatches used: 0 of 6 (a push is the run).

Verified: gate-breakpoints smooth-bound test and measure-webkit profile-report test pass locally; scripts/ci-paths.test.mjs passes.
One local debug run of the mac leg (3 arms, 1 event rep + 1 cadence rep, hold 1400): the bound arm's earn button reported
transition-duration 0s, all windows kept, end windows have finish-zone frames. Not a result.

What was built:
- packages/gate-breakpoints/src/smooth/bound.mjs: BOUND_CSS/BOUND_JS (probe-only, injected after load, same config hash as base), parseArms, endPushFor.
- --arms and --hold-ms on `smooth/cli.mjs webkit` and `measure-webkit/src/profile/cli.mjs sim`; webkit-cadence.mjs, sim-cadence.mjs take `only`, `holdMs`.
- report.mjs: pair base|bound (first = base does less, so bound beats A/A = verdict `second`), ratio column "bound / base" only when the arm ran.
- smoothness.yml: token [earn-bound] sets ARMS=base,aa,bound, HOLD_MS=1400, REPS 8 (mac) / 7 (sim).
- Outside the graph writes: packages/measure-webkit/src/profile/** and test, apps/runner/src/land.ts (one declared read).

Open: wait for the run, download the 6 artifacts (smoothness-webkit-mac-N, smoothness-webkit-sim-N), run
`node packages/measure-webkit/src/profile/cli.mjs report --runs <dir> --out <dir>`, then results/earn-bound/report.json, the note
research/notes/2026/10-2x-earn-gpu.md, package tests, dry land, `pnpm -s fw review ready`.
No checker corrections for the earn-gpu note existed in the scratch folder (earn-r1-findings.md is the older earn drift task); the note is checked by the builder against the cited sources.
