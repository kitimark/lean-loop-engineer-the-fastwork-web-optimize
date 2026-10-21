# console-push handoff

State: `fw watch --stream` now also prints one `USER <type> <flag|step> <text>` line per new lead-facing user event of
`.fw-console/events.jsonl` within about 2 s of the append. Tick lines (OPEN/CLOSE/REAP/DISKGC/STREAM END) unchanged.
The interim `tail -F | grep '"actor":"user"'` Monitor is no longer needed (lead to retire it after landing and re-arming the stream).

What was built
- Lean: `lean/Fw/Obs/Push.lean` (`leadFacing type actor`: actor user and type in review.feedback, step.answer, step.done,
  step.cancel; one theorem per branch, `leadFacing_iff`, `not_user`, `other_type`), op `obs.push` (`{events:[{type,actor}]}` to
  `{push:[bool]}`), golden `packages/contracts/golden/obs/push.jsonl` (11 rows, hooked into `Obs/Golden.lean`).
- TS: `apps/runner/src/watch-push.ts` (LineTail: offset read, partial line waits, shrink or new inode restarts at 0; startPush:
  fs.watch on the directory plus 1 s safety poll; classification is fwcore's), wired in `streamMain` (`watch.ts`).
- Tests: `apps/runner/test/watch-push.test.ts` (user question prints, hook/script/lead/user step.start print nothing, partial
  line waits, rotation, golden against fwcore), `watch-push-latency.test.ts`.

Measured (this Mac, under current load, 20 appends, fwcore spawn per batch): p50 82 ms, p95 170 ms, max 1101 ms (the first
append, cold fwcore start). `PUSH_LATENCY=1 pnpm -C apps/runner exec vitest run test/watch-push-latency.test.ts --silent=false`.

Verified: `sh lean/scripts/check.sh` green; tsc; vitest watch-push*.test.ts; full runner suite green after the wallclock-allow entries. Reviewer re-run of the latency test: p50 68 ms, p95 214 ms, max 1065 ms.

Writes outside the graph list: `lean/Fw/Wire/Obs.lean` (import and dispatch line for obs.push), `lean/Fw/Obs/Golden.lean`
(golden hook), `apps/runner/test/watch-push-latency.test.ts` (matches watch-push*).

Open / limits: starts at the end of the log (no replay of earlier events); local Mac only; no phone notification; line text
cut at 160 characters is TS rendering. Read first: `watch-push.ts`, `lean/Fw/Obs/Push.lean`, docs/team/tools/watch.md (Console push).
