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

Source of every number above: the sampler logs (rows `t_s,rss_kb` below, `ps -o rss=` of the watch pid every 60 s; MB = rss_kb / 1024; sampler `sample.mjs`, scratch, spawns the stream with
`FW_CONSOLE_DIR=<copy>` `FW_WATCH_REAP=0`). The table drops the first and last row of each file (start-up and shutdown), leaving 20 points.
Slope = least squares of MB on minutes over those 20 points; max and mean are over the same points.

Raw sampler rows (`t_s,rss_kb`, all 22 rows per arm, first and last included):

```
before: 0,1152 60,638208 120,615792 180,861760 240,700448 300,827808 360,152032 420,707360 480,223696 540,736752 600,743808 660,797328 720,453136 780,436512 840,587680 900,577088 960,795616 1020,305568 1080,630992 1140,610896 1200,571440 1260,37600
after:  0,480 60,25600 120,199152 180,69952 240,216896 300,139072 360,212624 420,220816 480,179296 540,203408 600,223904 660,221888 720,255504 780,136896 840,126416 900,160544 960,242176 1020,225952 1080,227152 1140,229168 1200,226768 1260,207248
```

| minute | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| before MB | 623 | 601 | 842 | 684 | 808 | 148 | 691 | 218 | 719 | 726 | 779 | 443 | 426 | 574 | 564 | 777 | 298 | 616 | 597 | 558 |
| after MB | 25 | 194 | 68 | 212 | 136 | 208 | 216 | 175 | 199 | 219 | 217 | 250 | 134 | 123 | 157 | 237 | 221 | 222 | 224 | 221 |

Recomputed from the raw rows: before max 842, mean 585, slope -5.2 MB/min; after max 250, mean 183, slope +5.0 MB/min.

The tick line's own reading (taken inside the tick, at its peak) was at most 289 MB. `Fw.Ops.WatchMem.rssBoundKb` is 512 MB:
1.7 x the after-arm peak, below the before-arm mean. A first guess of 256 MB fired once in the after arm (289 MB), which is why
the bound was set from the measurement. Peak is 3.4 x lower than before; the lead's 663 MB incident would alert.

Alert output unchanged: `apps/runner/test/watch-mem.test.ts`, describe "recorded event window", replays the committed window
`apps/runner/test/fixtures/watch-mem/` (`timings.jsonl`: the newest 3400 rows of a recorded log reduced to tool, step, durMs, host, load,
startMs, exit; `spool/main.jsonl`: 400 recorded hook lines reduced to six fields; `events.jsonl` and `transcripts/agent-synth.jsonl`:
synthetic, shaped like the real ones, the transcript with a tool_use whose tool_result line is 700 kB, longer than one 512 KiB chunk). Each file
grows in three appends cut inside lines through the cursor readers; the test deep-equals the slow alert list (`slowAlerts`), the transcript
signal facts (`finishSignals`), `handbackAtOf`, `collectLead` and `collectFeedback` against the whole-file results. Window rows equal a sort
of everything on random logs (same file). The live OPEN lines of the two arms differ only where the world differs (load average, a CI run
that started between arms), plus `watch.rss fw-watch` once in the after arm (289 MB, against the 256 MB first guess).

Long lines: `readAppended` follows `Fw.Ops.WatchMem.nextCursor` (no newline: the cursor stays) by doubling its buffer until a newline or the file
end shows; golden row "a line longer than one chunk keeps the cursor at its start", theorem `next_none`, test "a line longer than one chunk".

## Accepted limits

- A last line without a newline is counted when its newline arrives (one tick later), not at once.
- Feedback events are all kept (26 in 48k events); the lead's notes cache and the fold caches on disk are unchanged.
- `health.jsonl` (195 MB) still grows by one snapshot per tick: disk, not memory (follow-up).
