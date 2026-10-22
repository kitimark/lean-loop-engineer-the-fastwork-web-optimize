branch: worktree-wf_67501544-66c-1 (CI branch ci/earn-bound-arm)
worktree: .claude/worktrees/wf_67501544-66c-1 (under the main checkout)
last commit: d8c3fa26 (request commit; code in ac8932ee)

# earn-bound-arm checkpoint 2 (mac leg done, sim leg running)

CI runs (smoothness.yml, head commit asks for [ci:smoothness] [webkit-cadence] [earn-bound]):
- 39729682403 smoothness: mac jobs 1-3 complete (48 windows each, none refused); sim job 1 INCOMPLETE (Simulator shut down after
  31 windows, 5 reps of base and aa, 5 or 6 of bound); sim jobs 2 and 3 still running (about 36 min each, one after another).
Dispatches used: 0 of 6 (a push is the run). Do not push a newer commit to ci/earn-bound-arm while the run is going (stale check).

Mac preview (3 jobs, finish zone, render work ms per window): base 725.77, aa 714.48, bound 733.64. Lean across verdict
base|bound: `same` in hero, finish and rest. So no mac headroom: bound is not below A/A. Not final until the sim legs are in.

What was built:
- packages/gate-breakpoints/src/smooth/bound.mjs: BOUND_CSS/BOUND_JS (probe-only, injected after load, same config hash as base), parseArms, endPushFor.
- --arms and --hold-ms on `smooth/cli.mjs webkit` and `measure-webkit/src/profile/cli.mjs sim`; webkit-cadence.mjs, sim-cadence.mjs take `only`, `holdMs`.
- report.mjs: pair base|bound (first = base does less, so bound beats A/A = verdict `second`), ratio column "bound / base" only when the arm ran.
- smoothness.yml: token [earn-bound] sets ARMS=base,aa,bound, HOLD_MS=1400, REPS 8 (mac) / 7 (sim).
- Outside the graph writes: packages/measure-webkit/src/profile/** and test, apps/runner/src/land.ts (one declared read).

Open: wait for sim jobs 2-3, download the artifacts (smoothness-webkit-mac-N, smoothness-webkit-sim-N) into an empty dir, run
`node packages/measure-webkit/src/profile/cli.mjs report --runs <dir> --out <dir>`, then results/earn-bound/report.json, the note
research/notes/2026/10-2x-earn-gpu.md, package tests, merge main, dry land, `pnpm -s fw review ready`.
No checker corrections for the earn-gpu note existed in the scratch folder (earn-r1-findings.md is the older earn drift task); the note is checked by the builder against the cited sources.
