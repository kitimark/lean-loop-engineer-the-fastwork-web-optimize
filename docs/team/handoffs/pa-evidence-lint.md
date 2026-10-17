# pa-evidence-lint handoff

State: `plan.lint` (Lean) and `pnpm fw plan lint docs/team/work-graph.json` are done; commits on branch worktree-agent-a8455f9674aadf9c5 (code, then one back-fill commit).

## Use
`pnpm fw plan lint docs/team/work-graph.json` prints errors and warnings, counts info findings, exits 1 on errors. It reads main's first-parent history (`git log main`) and calls fwcore `plan.lint` (binary found like `fw watch`: this checkout, main, sibling worktrees; rebuild lean first).

## Lean (lean/Fw/Plan/Lint.lean, op in lean/Fw/Wire/Console.lean)
- error: unknownDep, evOther (not commit / run id / user / prose naming a commit), evLong (> 64), trailerNoEvidence, cycle (graph-wide, task `*`, via `acyclicB`).
- warn: evUser (kind=user), evProse (`abc1234: ...`), longTitle (> 200; sync clips it).
- info: evidenceNoTrailer (evidence on the row, no `Task:` trailer on main; normal for old tasks, only counted).
- Theorems: mem_codes, unknownDep_iff, evLong_iff, longTitle_iff, trailerNoEvidence_iff, evidenceNoTrailer_iff, ok_sound (ok => no unknown dep, Acyclic).
- Cycle detail text (`stuck`) lists tasks in or behind a cycle; no theorem for it, only `acyclicB_iff` backs the finding.

## Back-fill
44 tasks had a `Task:` trailer on main and no evidence; set to the 7-char sha of the oldest first-parent commit naming them. The eight named in the note (watch-fix, watch-slow, watch-proc-allow, plan-rev7, plan-rev7-1, ops-gate, store-cirun, math-r8-fix) were all among them, each matching a "merge <task>" subject.
After the lint: 0 errors, 34 warnings (prose/user evidence, 15 long titles), 57 info.

## Notes
- I also touched apps/runner/src/fw.ts (one registration branch) and lean/Fw.lean (import).
- Not done: no golden vectors for plan.lint (only #guard on evKind); no console-api route (CLI calls fwcore directly).
