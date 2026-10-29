# fw watch memory (task watch-memory, 2026-10-29)

Trigger: the Mac ran at 113 MB free with 604k pages in the compressor; `node apps/runner/src/fw.ts watch --interval 300 --stream`
held 663 MB resident five minutes after it started. All numbers below are MEASURED local harness numbers of our own tool
(not a site result), copies of `.fw-console/` read through `FW_CONSOLE_DIR`, `FW_WATCH_REAP=0`, `--interval 60`
(stricter than the 300 s of the Monitor: more ticks per hour).

## Cause (MEASURED, one pass at a time, `process.memoryUsage()` and a wrapper on `readFileSync`)

Every tick re-read whole files and kept the text alive until the next collection:

| read per tick | size | where | RSS it added |
|---|---|---|---|
| `timings.jsonl`, parsed fully, then cut to 3000 rows | 64 MB, 382k lines | `readSamples` (watch-collect.ts) | +380 MB |
| agent transcripts, whole text for `signalsOf` + `handbackAtOf` | 7 files, 110 MB | `collectRaw` (next.ts) | +240 MB heap |
| the fwcore binary, for its sha256 | 83 MB | `coreBase` -> `buildBase` -> `sha256File` | +180 MB external |
| `events.jsonl` for feedback events | 10 MB | `collectFeedback` | +30 MB |
| `spool/main.jsonl` for the lead's last times | 7 MB | `collectLead` | +10 MB |

RSS never fell back after a tick (V8 and malloc keep the pages), so the high-water mark of one tick became the resident size.

## Fix

- Each growing log is read by cursor (`watch-mem.ts`): from where the last tick stopped, in 512 KiB pieces, whole lines only;
  a truncated or replaced file (inode, size) is read again from its start. Rule and proofs: `Fw.Ops.WatchMem.readFrom`,
  `nextCursor` (theorems `read_grown`, `read_truncated`, `read_replaced`, `readFrom_le`, `nextCursor_le`).
- Timing samples keep a window of the newest 3000 by start time, equal starts in file order (`push`, `window`; theorems
  `window_length_le`, `window_sorted`, `push_suffix`). TS `windowRows` is a stand-in checked against
  `golden/ops/ops.watchWindow.jsonl` and against a sort of everything on random logs.
- Transcripts: the signal fold and the handback time are kept per transcript in memory and fed only the appended lines; a pass
  forgets the transcripts it did not ask for.
- The binary's sha256 is read in 1 MiB pieces and kept while inode, size and mtime stay.
- Self-check: every tick asks fwcore `ops.watchRss` with the process's own RSS and heap; the reply is the tick line
  (`TICK rss=..MB heap=..MB bound=..MB`, printed with `--stream --tick`, always logged as `mem` in `health.jsonl`) and,
  above `Fw.Ops.WatchMem.rssBoundKb`, the alert `watch.rss fw-watch`.

## Measurement

Local, this Mac under load average 9 to 14 (other agents running), 21-minute streams, sampled with `ps` every 60 s, first and
last sample dropped, 20 samples each. Same console copy, same filter (`fw watch --interval 60 --stream`; the after arm adds `--tick`).

| arm | max RSS | mean RSS | slope |
|---|---|---|---|
| before (whole-file reads) | 842 MB | 585 MB | -5 MB/min (sawtooth 150 to 860 MB, no trend) |
| after (cursors, window, chunked hash) | 250 MB | 183 MB | +5 MB/min (cold-start fill, flat from minute 3: 126 to 256 MB) |

The tick line's own reading (taken inside the tick, at its peak) was at most 289 MB. `Fw.Ops.WatchMem.rssBoundKb` is 512 MB:
1.7 x the after-arm peak, below the before-arm mean. A first guess of 256 MB fired once in the after arm (289 MB), which is why
the bound was set from the measurement. Peak is 3.4 x lower than before; the lead's 663 MB incident would alert.

Alert output unchanged: the golden replay (`watch-mem.test.ts`: slow verdicts over the windowed samples equal those over a
whole-file read, on append, torn line, truncation, replacement; window equals a sort of everything on random logs) is the proof.
The live OPEN lines of the two arms differ only where the world differs (load average, a CI run that started between arms),
plus `watch.rss fw-watch` once in the after arm (at 289 MB, against the 256 MB first guess).

## Accepted limits

- A last line without a newline is counted when its newline arrives (one tick later), not at once.
- Feedback events are all kept (26 in 48k events); the lead's notes cache and the fold caches on disk are unchanged.
- `health.jsonl` (195 MB) still grows by one snapshot per tick: disk, not memory (follow-up).
