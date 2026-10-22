branch: worktree-wf_6367bf83-6b7-1
worktree: .claude/worktrees/wf_6367bf83-6b7-1
last commit: see `git log -1` on the branch (Lean change at 052fbca27)
CI runs: none (no dispatch; the re-reduction reads the artifacts of 39729682403 and 39754568950)

# across-insufficient: done

`across` (lean/Fw/Gate/Smooth.lean) now counts `decisive vs` (first + second + same samples) and returns `insufficient`
when that count is below `minSamples`, so a list of only `insufficient` samples never reads `same`.

Verified:
- Theorems: `across_insufficient` (new), `across_few` (kept, via `decisive_le`), `across_first`, `across_second`,
  `across_split`, `across_same` (hypothesis now `minSamples ≤ decisive vs`), `across_swap`.
- Golden `packages/contracts/golden/gate/smooth.jsonl`: four new across cases (all insufficient; 2 decisive of 5;
  3 decisive of 5 giving first; 3 decisive of 5 giving same). The old case `(2, [first, first, insufficient])` moved
  from `first` to `insufficient`.
- JS twin `across` in packages/gate-breakpoints/src/smooth/reduce.mjs follows; `smooth.test.mjs` checks it against the
  golden. packages/measure-webkit/src/profile/report.mjs imports that twin, so it needed no edit.
- Re-reduction (`node packages/measure-webkit/src/profile/cli.mjs report --runs <dir> --out <dir2>`, artifacts
  smoothness-webkit-mac-1..3 of 39729682403 and smoothness-webkit-sim-1..3 of 39754568950), pair base|bound:
  only the Simulator hero and rest zones change, from `same` to `insufficient` (0/0/0/3 jobs). macOS hero, finish and
  rest, the Simulator finish zone and every cadence row stay `same`. The note's table (finish zone only) does not change,
  so research/notes/2026/10-2x-earn-gpu.md is not edited.

Open (outside the writes):
- research/notes/2026/10-2x-earn-gpu.md:307 cites `across_same` at `:735`; it is now at `:752`.
- `k` stays `agreeNeeded` of all jobs, insufficient ones included; whether it should be two thirds of the decisive jobs is
  not decided here.
