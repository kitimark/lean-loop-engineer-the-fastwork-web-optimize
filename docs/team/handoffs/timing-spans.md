# timing-spans handoff

State: branch worktree-agent-ace47202b9a8055c5 (see git log). Read first: docs/team/tools/timings.md.

Done
- apps/runner/src/timing.ts (span writer, CI span mapping, summary view), timing-ci.ts (charged `gh run view`, dedupe, backfill).
- scripts/span.sh + lean/scripts/check.sh: 8 stages timed (shell chosen: node wrapper costs ~40 ms per stage).
- fw.ts: one `fw` span per invocation (exit handler), `fw timings`, `fw ci wait` ingests finished runs.
- land.ts: spans for merge, merge commit, each check (argv), reconcile, verify, plan sync, worktree cleanup.
- watch.ts: one `watch pass` span around collect+check+log (not in watch-collect/next).
- test/timing.test.ts; runner tests 267 green; lean/scripts/check.sh green.
- Backfill done once into the main checkout's .fw-console/timings.jsonl: run 39067656223 + 3 per workflow.

Open for timing-alert / timing-lean
- Poller-only completions (no `fw ci wait` waiter) write no CI spans.
- Shell span cost ~8 ms/step (2 `date` spawns), above the 5 ms goal; node spans 0.05 ms.
- Slow verdict is not decided here: Lean (timing-lean) must define it; `fw timings` quantiles are display only.
- lean/scripts/check.sh is shared; stage names are the `step` keys: renaming one breaks history.
