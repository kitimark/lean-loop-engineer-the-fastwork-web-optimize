# timing-work-dims handoff

- Branch `worktree-wf_cdc2f175-f40-1`, worktree `.claude/worktrees/wf_cdc2f175-f40-1`, last code sha f535f8f36 (merge of main 0c14dc9).
- CI runs: none (no ci/* push; all checks ran locally via fw slot).
- Verified: check.sh green (axioms ok, timing golden up to date), runner suite 101 files / 3050 tests, ci-paths 54/54,
  `fw land --dry` gives `VERDICT dry timing-work-dims`, `fw review ready` gives `review`.
- Open: land dry lake 43470 stays slow (no work field; module count is the driver); polish commit 38160 is still slow
  with 21 spans of history (golden polishRun, n 9); both are follow-ups. Wire/Obs.lean and watch-collect.ts were edited
  outside the main write list but inside the land scope. Goldens changed: packages/contracts/golden/obs/timing.jsonl,
  timing-work.jsonl, new timing-slow.jsonl; lean/scripts/TimingGolden.lean now checks and writes
  Fw.Wire.Obs.TimingSlow too.

## What changed
- `lean/Fw/Obs/Timing.lean`: `checksWork`/`spanWork` give the work class `checks` (heavy kinds joined by `+`, or
  `light`); `judgeQ` marks fw slot-run overflow buckets (`slot run <kind>[ dry][ cached]`) `mixed`, never slow
  (`judgeQ_mixed_not_slow`, `no_slow_bucket`). The old body is `judgeW`.
- `lean/Fw/Obs/Next.lean`: `subject` adds ` [k=v,…]`; `sameKey` compares work; golden namespace `Fw.Wire.Obs.TimingSlow`
  writes `packages/contracts/golden/obs/timing-slow.jsonl` (via `lean/scripts/TimingGolden.lean`).
- `lean/Fw/Wire/Obs.lean`: `workOf` keeps string members only.
- TS: `polish.ts` `stagedChecks` asks `ops.checkMap` for the staged files after `git add`; `timing.ts` `noteSpan`
  adds the `checks` member to the `fw`/`polish commit` line that `begin` writes (fw-main.ts unchanged);
  `watch-collect.ts` parseSamples uses `spanWork`.

## Conventions
- Spans written before this change have no `checks` member and keep the old key (accepted limit).
- Re-judge method: cut `.fw-console/timings.jsonl` at the alert span, add the reconstructed `checks` to polish spans,
  call `obs.timing`/`obs.slow` on `parseSamples` of the cut (3000-sample cap, as the watcher reads it).

## Read first
`lean/Fw/Obs/Timing.lean` (checksWork, judgeQ, polishRun, bucketRun), `lean/Fw/Obs/Next.lean` (subject, sameKey),
`apps/runner/test/timing-slow.test.ts`.
