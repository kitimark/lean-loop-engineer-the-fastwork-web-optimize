# gate-shard-balance handoff

State: branch of this worktree, merged from the previous builder (088315d settle frame budget, 0549eaa LPT shard plan,
f47e8c9 math, 255c914 WIP) and main. `sh lean/scripts/check.sh` is green ("all lean/ gates green").

## Result (MEASURED, CI run 39110348835, dispatched on ci/gate-shard-balance, all 33 parts, arm lanes)
- 6 gate jobs (chromium 2, playwright-webkit 4), 65.1 job-minutes (baseline 39106417480: 65.5); gate wall 12.2 min
  (baseline 18.9, original 39101532038 about 50). Per-job minutes and queue time: research/notes/2026/10-18-gate-shard-balance.md.
- Per-cell verdicts vs 39101532038 and 39106417480: WebKit 0 differ; Chromium 502/504 equal, 2 differ in failing count
  only (commission x desk-rm, hero.orbit x desk-rm: fail in all runs, 1 -> 2 of 30 probes). INFERRED intermittent probes
  (see note). The run concludes `failure` as the baselines do (same failing cells).

## Merge notes (read before touching Lean Parts)
- The builder branch carried the port work with the old proof files; main moved the same proofs. Resolution: `PeopleCard.lean`
  and `PainNotes.lean` are the builder's (port specs); main's PrePaint changes to the old proofs were applied to
  `PeopleCardOpt.lean` and `PainNotesOpt.lean`. `Premise.lean`, `premise.jsonl` are main's. `check.sh` has both new stages.
- Added `$$` math to `Fw.Gate.PageOffset` docstrings and `PainNotes.Render` (mathview lint).
- My push to ci/gate-shard-balance started every workflow; I cancelled all but `lean` so the pool stayed free.

## Open
- The WebKit desktop sweep (about 11.6 min) is the floor; lowering it needs a smaller frame budget or concurrency 1 plus a
  new verdict comparison (note, "Open"). Regenerate `ShardObs.lean` with `scripts/shard-obs.mjs` after harness changes.
- One run only (the task asked for one); a 3-run class table was not made, the claim is timing, not counts.
- Worktree needs `pnpm install --offline --frozen-lockfile` before `pnpm fw` works.
