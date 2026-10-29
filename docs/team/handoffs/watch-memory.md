branch: worktree-wf_49266267-829-1
worktree: .claude/worktrees/wf_49266267-829-1 (under the main checkout)
last commit: e64ac7211 (this file added in the next commit)
run ids: none (local task, no CI)
verified: Lean WatchMem compiles; goldens replay in check.sh; runner tests; local RSS before/after, before max 842 MB / after max 250 MB (local, 21 min, 60 s samples, slope -5 / +5 MB/min)
open: next.ts outside writes (dry land may need --allow); follow-ups below

round 2 (review refused r1): long-line cursor fix (grow buffer), recorded-window fixture + replay test, raw RSS rows in the note, read_grown docstring. No CI runs. Samples: the note's raw rows (sampler scratch was kept).

## State
- Cause: fw watch re-read whole logs each tick (timings 64 MB, transcripts 110 MB, fwcore binary hash 83 MB, events, spool).
  Now cursor reads in 512 KiB chunks (`apps/runner/src/watch-mem.ts`), windowed timing samples (newest 3000), per-transcript
  fold state, chunked binary hash.
- Lean: `lean/Fw/Ops/WatchMem.lean` (window, readFrom, nextCursor, rssBoundKb, tick line); ops `ops.watchWindow`,
  `ops.watchCursor`, `ops.watchRss` are routed through `Fw.Wire.WatchDiff.handle` (Wire.lean untouched).
- Goldens: `packages/contracts/golden/ops/ops.watch{Window,Cursor,Rss}.jsonl`, generated from Lean; regenerate them if
  `rssBoundKb` changes (test strings in `apps/runner/test/watch-mem.test.ts` name the bound).
- `fw watch --stream --tick` prints `TICK rss=.. heap=.. bound=..`; health.jsonl rows carry `mem`; alert `watch.rss fw-watch`.
- Numbers and method: `research/notes/2026/10-2x-watch-memory.md`. Sampler scripts were scratch (not committed): spawn the
  watch with `FW_CONSOLE_DIR=<copy>` and `FW_WATCH_REAP=0`, `ps -o rss` every 60 s.

## Conventions
- TS stand-ins (temporary): `windowRows`, `readFrom`, `nextCursor` in watch-mem.ts, checked against the goldens.
- `apps/runner/src/next.ts` is outside the task's writes (transcript tail); the dry land may need `--allow`.

## Follow-ups
- docs/team/tools/fw-watch.md does not mention `--tick`.
- health.jsonl (195 MB) grows one snapshot per tick: disk only; needs a retention rule.
- The Lean monitorShapes allowlist is exact: adding `--tick` to the Monitor command drops its proc.long exemption.
- An unterminated final line is counted one tick late.

Read first: the research note, then `lean/Fw/Ops/WatchMem.lean`, then `watch-mem.ts`.
