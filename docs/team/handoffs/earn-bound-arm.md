branch: worktree-wf_67501544-66c-1 (CI branch ci/earn-bound-arm)
worktree: .claude/worktrees/wf_67501544-66c-1
last commit: see `git log -1` on the branch (main merged at d75ce5b8f; land.ts conflict resolved as the union of both read lists)

# earn-bound-arm: done, verdict NO-GO for candidate B

Verdict (MEASURED, Lean `across` pair base|bound, finish zone): `same` in every decisive job of both WebKit legs; no job says
`second`. So bound does not beat A/A, B is not built, the faithful earn animation stays. Neither VM has a real GPU.

CI runs (all on ci/earn-bound-arm, smoothness.yml; 3 of 6 dispatches used):
- 39729682403: mac jobs 1-3 complete (8 reps, 48 windows each) = the macOS evidence. Sim jobs 1-2 died at 31/38 windows, sim job 3 hit
  the 45 min limit (no artifact). GitHub conclusion cancelled (sim job 3 hit the limit; mac jobs 1-3 succeeded); fw ci state prints unknown for all three runs, GitHub gives 39744983394 and 39754568950 success.
- 39744983394: [sim-only], 4 reps: too few finish windows (MIN_REPS 5), verdict insufficient.
- 39754568950: [sim-only], 6 reps: 3 sim jobs, 36 windows each, all decisive = the iOS Simulator evidence.

Files: research/notes/2026/10-2x-earn-gpu.md (note, result section), results/earn-bound/report.json (fwcore `console.report`: `invalid:[]` = accepted,
item unposted; not posted), packages/gate-breakpoints/src/smooth/bound.mjs (+ webkit-cadence.mjs, cli.mjs),
packages/measure-webkit/src/profile/{sim-cadence,cli,report}.mjs, smoothness.yml tokens [earn-bound] and [sim-only].
Writes outside the graph: measure-webkit profile files and test, gate-breakpoints test/smooth-bound.test.mjs, apps/runner/src/land.ts
(one declared read of bound.mjs for packages/measure-webkit).
How to read the numbers again: download smoothness-webkit-mac-N / -sim-N into <dir>/<runId>/<artifact>/ and run
`node packages/measure-webkit/src/profile/cli.mjs report --runs <dir> --out <dir2>`.

Open / follow-ups:
- Phone replay of base vs bound (plan step 4) is the only check for GPU/UI-process time; the VMs cannot show it.
- iOS Simulator leg: most hero windows read insufficient (frames land in the wrong zone in some windows); only the finish zone decides.
  Cause not investigated. The Simulator dies after about 30-40 windows; keep sim reps at 6 or fewer per job.
- TS stand-ins: PAIRS entry base|bound (reuses Lean-twin verdict fns); the go/no-go rule was applied by hand from the across table.
- report.json was never invalid (`"invalid":[]` is the accepted answer); negative result written into the note
  (section "Why the bound arm reads same") ; the ledger notes row for nav.earn.noTransition is outside the writes, the lead adds it (text in the note, Report paragraph).
