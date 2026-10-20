# drain-wake-flake handoff

State: the tip commit of this worktree's branch. Task: journal-cache.test 'a journal append and a new session dir wake the drain'
timed out (3 s `until`) on the Linux land lane (runs 39432902864 and the ac3a92a land).

Mechanism:
- CONFIRMED by source: on Linux Node's `fs.watch({recursive:true})` is the JS watcher `lib/internal/fs/recursive_watch.js`
  (nodejs/node v24.14.0; `lib/fs.js:2531` picks it when not macOS/Windows): one inotify watch per file/dir. `kFSWatchStart` runs
  `#watchFile`/`#watchFolder` before `fs.watch` attaches the listener (`lib/fs.js:2533-2545`), so files that exist when a watch
  opens give no event; only a sweep that starts after `sync()` sees them. `drain-watch.ts` pokes after `sync()` on a discover
  event, but the safety interval's own `sync()` did not (fixed: it requests a sweep when it opened a watch).
- The old test took `p1` (passes started) 100 ms BEFORE the write, so a pass that started in between answered nothing, its safety
  tick was 60 s, and its 3 s deadline was a guess.
- MEASURED on the Linux land lane (runs 39436234168, 39436911272, probe of the same scenario, 20 + 12 rounds): 0 misses, longest
  pass 47 ms. The flake did not reproduce in isolation, only inside the full suite (30 files in parallel on 2 vCPU). A lost kernel
  event was not found; the root cause beyond "full-suite load" is NOT established. Accepted limit: a proved fallback tick bound.

Fix: Lean `Fw.Console.ReconcileSched`: `answerStart`, `wakeStartBound`, `wakeDoneBound`, theorems `poke_wake_le`, `poke_done_le`,
`tick_wake_le` (a file event, a new dir after sync, and a dropped event each start the answering pass within settle-or-period plus
the longest pass). Golden `packages/contracts/golden/console/wake-bound.jsonl`, written by
`lake env lean --run scripts/ReconcileSchedGolden.lean` (its --check covers both golden files). TS stand-in `wakeStartBound` /
`wakeDoneBound` in `src/spool/drain-watch.ts`, checked on the golden. The test takes `p1` at the write, uses a 1 s tick, waits for
`wakeStartBound(tick, longest pass)` + 500 ms margin + its own event-loop stall, prints a trail on a miss, and runs 10 times.

Verified: land lane run 39438056251 (Linux, commit 31ff21ac) green with the wake test at 10 runs (vitest `repeats: 9` = 10 runs);
`sh lean/scripts/check.sh` green; console-api, ci-paths and land-inputs tests green locally.

Open: the CI miss's root cause stays unproven; if it returns, the error trail says whether a pass was long, the loop stalled, or
no pass started. Read first: end of `ReconcileSched.lean`, `drain-watch.ts`, the test in `journal-cache.test.ts`.
