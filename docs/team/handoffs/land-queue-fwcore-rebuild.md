# land-queue-fwcore-rebuild handoff

State: the queue rebuilds fwcore after a `done` land whose merged diff touches `lean/**` or `scripts/fwcore-build.sh`, before the next dequeue.

Delivered
- Lean `Fw.Console.LandVerdict`: new refusal kind `rebuild` (exit 18). `Fw.Console.LandQueue`: `coreSource`, `touchesCore`, `needsRebuild`, `afterLand`, `stopKind`, `rebuildReason`, theorems one per branch, golden op `landQueue.afterLand` (9 cases). Goldens `land-queue.jsonl` and `land-dry.jsonl` regenerated.
- TS: `apps/runner/src/land-verdict.ts` (`afterLand` etc., golden-checked), `land-queue.ts` `runQueue` options `head`/`diff`/`rebuild`, glue in `fw.ts` (span `fwcore rebuild (queue)`).
- Tests: `apps/runner/test/land-queue.test.ts` (golden op; two items where the first touches lean/ -> the second is not refused stale; failed rebuild -> `rebuild`, queue stops).
- Doc: last section of `docs/team/tools/land.md`.

Verified: apps/runner `pnpm test` (tsc + 1434 tests) green; `lake build` green; goldens written.
Open: the rebuild is local; its time is a span only, not optimized. The TS `afterLand` is a golden-checked stand-in, not an fwcore op.
Read first: section "The queue rebuilds fwcore" in `lean/Fw/Console/LandQueue.lean`.
