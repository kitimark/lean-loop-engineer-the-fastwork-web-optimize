# Handoff: local-mem-budget (console-builder), rounds 1 and 2

State: branch `worktree-wf_a08b7aa9-761-1`, commit named in the report. Read first: `lean/Fw/Obs/Stale.lean` (`recordTree`,
`chooseBaseTree`), `lean/Fw/Obs/Health.lean` (`contendedNow`, `LoadInfo`), `lean/Fw/Sched/Heavy.lean` (`maxWaitS`, `Verdict.timeout`),
`scripts/heavy-lock.mjs`, `scripts/fwcore-build.sh`.

Round 1: contended samples never raise timing.slow (`contendedLoad` 8); `sys.contended` alert; heavy lock (Lean verdict, TS stand-in
`scripts/heavy-lock.mjs`, golden sched/heavy.jsonl); propslint exe; one fwcore builder.
Round 2:
- svc.unknown trace: 6 records, all `fwcore` "no build record", next to `lean/check | lake build` or `fw land | fwcore rebuild`
  spans (attribution INFERRED, spans carry no cwd). Causes: old script removed the record at build start; no record on dirty or
  mid-merge trees. Fix: record is `tree <write-tree id before build> <sha256>`, written only when files equal the index before and
  after (Lean `recordTree`); readers resolve it to the commit of main with that tree (`build-base.ts`, land.ts `parseBuildRecord`).
- `systemOf_systemJson` back at 4M heartbeats (wire `system.load {builders, heavyJobs, prevContended}`); builds in ~4 min.
- Cap relabelled INFERRED (no 1/2/4 run: load 13, swap 93%). Max wait `maxWaitS` 1800: heavy-lock exits 75, job not run.
- Hysteresis: open above 8, close at 4 or below (`calmLoad`); opens/day 5,32,25,25,12 -> 1,11,6,14,2 (replay, local timings).
- Lows: atomic ticket, rank<0 re-enqueue, own-start failure throws, countHeavy checks pid+start, lakefile 0.2 GB.
Accepted limits: no concurrency measurement; MCP servers not stopped; CI timing out of scope; 60-96% of local lean/check samples
per day still contended; relink window shows unknown until the new record is written; dirty builds stay unknown; a tree not yet on
main (land in progress) stays unknown.
Open: sys.swapHigh; proc.leftover; proc.heavy; proc.long missed lake-serve trees; trend view; `fwcore-build.sh`/check-fast outside the lock.
Conventions: Lean writes goldens (`lake env lean --run scripts/<X>Golden.lean`, `--check`); never hand-edit *.gen / golden.
Writes outside the graph list: Trigger.lean, LandSpeed.lean, land.ts, Stale.lean, Wire/Obs.lean, Health.lean, Timing.lean, Golden.lean,
Heavy.lean, lean.yml, build-base.ts, watch-*.ts, fwcore-build.sh, fwcore-record-rule.sh, their tests, docs/team/tools/{console-stale,land,watch-rules}.md.
