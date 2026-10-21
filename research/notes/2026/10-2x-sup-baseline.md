# Resource baseline of the dev Mac, smoke sample (task sup-baseline)

Status: MEASURED 2026-10-21 on the dev Mac (macOS, 16.0 GB RAM, 6.0 GB swap); 12 samples, 2026-10-21 13:33 UTC to 2026-10-21 13:37 UTC (a span of 3.8 min).
This is a SMOKE SAMPLE, not first-day data: the span is 3.8 min, under 6 h. It was taken by running the sampler (`sampleOnce`) by hand for a few minutes, to show that the sampler, the verdict and this generator work end to end. Its shares describe those minutes, which include this task's own checks and tests. The first-day tables are a follow-up.
Collection starts when the watch process restarts on the landed code (the post-land routine): the watch that ran before the land has no sampler, so no sample before that restart exists.
Every table below is generated from the local-only files `.fw-console/sup-samples.jsonl` and `.fw-console/locks.jsonl` by `apps/runner/src/sup-report.ts` (a TS stand-in; the verdict of each sample is the TS mirror of Lean's verdict (`resVerdict`), golden-checked); edit the generator, not this file.

## What is measured

- CONFIRMED (apps/runner/src/watch-collect.ts `sampleOnce`): every 20 s one `top -l 1 -stats pid,mem,cmprs`, `ps -A -o pid=,ppid=,comm=`, `sysctl -n vm.swapusage` and `memory_pressure -Q` are read and reduced to one line: per kind the process count and the footprint (MEM plus CMPRS) with its compressed part, plus swap used, compressor size, free memory, 1-min load, the cost of the sample and the verdict. The command line (`ps -o command`) is read only for the `lake`, `lean` and `launchd_sim` processes, to tell a build from a server and to find the Simulator device; it is not stored. No path or user name is stored.
- CONFIRMED (lean/Fw/Obs/Health.lean, namespace `Res`): the kind of a process is decided by identity, not by name alone: the program name from a fixed table (`kindTable`), the first argument for `lake` (a `serve` is `leanServe`, anything else is `leanBuild`), the ancestry (a process under a booted `launchd_sim` of one of our `fw-*` Simulator devices is `simulator`; a Safari under a `safaridriver` we started is `webkit`, and its WebKit helpers follow it) and the Simulator device name from its `device.plist`. Everything else is `other`, and `CoreSimulatorService`, system WebKit helpers and a Safari the user opened are `system` or `other`, not heavy. Heavy kinds are `leanBuild`, `chromium`, `simulator` and `webkit`. The verdict is `pressured` when swap use, the compressor or free memory trips its limit, else `busy` when a heavy kind runs or the 1-min load is at least 2.00, else `quiet`. Theorems: the verdict never lowers as pressure grows (`verdict_rank_mono`), `quiet` implies no heavy kind and a low load (`quiet_no_heavy`, `quiet_low_load`), and the background processes alone give `quiet` (`quiet_with_background`). The limits (swap 90 %, compressor 50 % of RAM, free 15 %, load 2.00) are first guesses, revised after the first day.
- CONFIRMED (scripts/heavy-lock.mjs, scripts/lake-slot-lib.sh, scripts/sim-lock.sh): each lock appends an acquire line and a release line (heavy-lock also a refuse line) with the time, kind, the holder's pid and start time, the wait or the hold in ms; no path, no argument, no owner name. The exec form of `lake_slot` replaces the shell with its command and so can log the acquire only; its row has no hold (see Locks).

Footprint is the `top` MEM column plus the CMPRS column per process (MEASURED: CMPRS is not a part of MEM; 6 of 620 rows of one `top` run had CMPRS above MEM, e.g. MEM 13 MB with CMPRS 73 MB). It is per process, so pages shared between processes (frameworks, the Lean runtime) can be counted in each. For that reason the tables give per-kind rows only and no total over kinds; read the rows as upper bounds of each kind's share and as comparable between kinds, not as additive.

## Samples

| measure | value |
| --- | ---: |
| samples kept | 12 |
| dropped (another watcher sampled within 10 s) | 0 |
| samples with a missing reading (no verdict) | 0 |
| longest gap between samples (s) | 20.7 |
| gaps over 60 s | 0 |
| cost of one sample, p50 / p90 / max (s) | 0.6 / 0.6 / 0.7 |

## Verdict share

| verdict | samples | share |
| --- | ---: | ---: |
| quiet | 0 | 0.0 % |
| busy | 12 | 100.0 % |
| pressured | 0 | 0.0 % |
| unknown | 0 | 0.0 % |

`unknown` is a sample with a missing reading. `quiet` is the share of time a measurement on this Mac would not have been disturbed by our own heavy work; any other share is the machine as it was, including everything else the user runs.

### Which condition tripped `pressured`

| condition | limit now | samples tripped | share of 12 samples with every reading |
| --- | ---: | ---: | ---: |
| swap used / swap total | at least 90 % | 0 | 0.0 % |
| compressor / RAM | at least 50 % | 0 | 0.0 % |
| free memory (`memory_pressure`) | at most 15 % | 0 | 0.0 % |
| pressured by swap alone | - | 0 | 0.0 % |
| pressured by the compressor or free memory | - | 0 | 0.0 % |

The swap ratio is of DYNAMIC swap: macOS adds swap files on demand, so used over total tends to sit near a fixed high ratio whatever the pressure, and `swapPct` is flagged for revision after the first day. `memory_pressure`'s system-wide free percentage is the pressure input to prefer; a row "by swap alone" above zero shows how much of `pressured` rests on the swap ratio only. The limits are the current `RES_PARAMS` (first guesses).

## Footprint per kind

| kind | samples present | procs p50 | procs p90 | procs max | footprint MB p50 | p90 | max | of which compressed MB p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| leanBuild | 0 (0.0 %) | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| leanServe | 12 (100.0 %) | 5 | 5 | 5 | 2512 | 2512 | 2512 | 1214 |
| fwcore | 12 (100.0 %) | 1 | 1 | 1 | 58 | 59 | 59 | 15 |
| node | 12 (100.0 %) | 17 | 26 | 27 | 2840 | 3265 | 3427 | 943 |
| pnpm | 0 (0.0 %) | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| chromium | 0 (0.0 %) | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| simulator | 0 (0.0 %) | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| webkit | 0 (0.0 %) | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| system | 12 (100.0 %) | 4 | 4 | 4 | 119 | 121 | 122 | 56 |
| other | 12 (100.0 %) | 538 | 542 | 551 | 31291 | 31668 | 32095 | 13311 |

Footprint is MEM plus CMPRS; the last column is the CMPRS part. There is no total over kinds (shared pages can be counted twice).

## Machine

| measure | p50 | p90 | max |
| --- | ---: | ---: | ---: |
| swap used (MB) | 5363 | 5363 | 5363 |
| swap used (% of total, dynamic swap) | 87.3 | 87.3 | 87.3 |
| compressor (MB) | 4996 | 5341 | 5539 |
| free memory (%) | 51 | 52 | 52 |
| load, 1 min | 6.2 | 7.5 | 8.1 |

Free memory is `memory_pressure`'s system-wide free percentage, so its p90 is the best and its p50 the typical case; the pressure limit trips at the low end.

## Simulator

| measure | value |
| --- | ---: |
| samples with a simulator-kind process | 0 |
| of which with no sim-lock held | 0 |
| simulator footprint, GB-hours | 0.000 |
| of which with no sim-lock held (idle), GB-hours | 0.000 |

The simulator kind is the whole `launchd_sim` subtree of a booted Simulator device of ours (named `fw-*`): the device's daemons, SpringBoard, MobileSafari and its WebKit helpers all count there. `CoreSimulatorService` and the system WebKit helpers that run for any app are `system`, not heavy, and a Safari the user opened is `other`. A booted Simulator is idle when the sim-lock is free.

## Heavy-lock holds

No sample fell inside a heavy-lock hold in this window.

## Locks

| lock | kind | acquires | of which exec (no release logged) | refused | still open | waited >= 1 s | wait ms p50 | p90 | max | hold ms p50 | p90 | max | most at once |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heavy | check | 1 | 0 | 0 | 0 | 0 | 9 | 9 | 9 | 15195 | 15195 | 15195 | 1 |
| lake-slot | build | 1 | 1 | 0 | 0 | 0 | 5 | 5 | 5 | not logged | - | - | - |
| lake-slot | group | 1 | 0 | 0 | 0 | 0 | 5 | 5 | 5 | 13599 | 13599 | 13599 | 1 |

Lock events span 2026-10-21 13:33 UTC to 2026-10-21 13:34 UTC; 0 release(s) had no acquire in the window (the job began before logging).
`heavy` and `lake-slot` time stamps are in ms where the shell's `date` has `%N` (this Mac's does) and whole seconds otherwise; a `sim-lock` wait is counted in whole seconds (its poll loop sleeps 1 s). A release and an acquire at the same instant are counted as not overlapping, so "most at once" is a lower bound. The lake-slot pid is the calling shell's (`$$`), also inside a subshell, so two holders in one shell share a pid. `lake_slot` keeps `exec`: the shell becomes the command, so there is no point at which a release could be written. With events on it logs the acquire only (marked `exec`), and the row has no hold, no "still open" and no "most at once": the hold is not derived from the next acquire, because that gap includes idle time. The group form (`lake_slot_hold` and `lake_slot_release`) logs both lines.

## Design section 5 mapping

One row per metric of the design's section 5 (stage 0 measurements): the value this window gives, or why it gives none.

| stage | design section 5 metric | source | value in this window | note |
| --- | ---: | ---: | ---: | ---: |
| 0 | Predicted peak charge, idle MB-hours reclaimable, requests that would be refused, replayed on the logs | not collected | - | needs the replay of 3.5 days of logs; a follow-up of this task |
| 1a | fwcore starts per day | not collected | fwcore processes present in 12 samples (100.0 %), p50 1 | a snapshot count, not a start count; starts need the spawn log |
| 1a | `op` p50 latency against the 40 ms spawn | not collected | - | needs the daemon (stage 1a) to time its calls |
| 1b | Peak summed footprint of lean children | sampler | leanBuild 0 MB max, 0 processes max | per kind only, the leanServe servers are a separate row |
| 1b | Lake builds outside a lease | lake-slot events | 2 lake-slot acquire(s); leanBuild present in 0 samples (0.0 %) | the exec form logs no hold interval, so a build outside a lease is not separated here |
| 1b | Lake serve MB-hours idle | sampler | leanServe 172.2 MB-hours in total | the idle split is not collected |
| 2 | Long-lived Node processes | sampler | node processes p50 17, p90 26, max 27 | no process age is read, so "long-lived" is not separated |
| 2 | Hook start footprint | not collected | - | needs a per-hook sample |
| 2 | Watch re-arm cold passes | not collected | - | needs the watch log |
| 3 | Peak footprint during lands | sampler and heavy-lock events | no sample under a heavy-lock hold in this window | 1 heavy-lock acquire(s) |
| 3 | Load p90 | sampler | 7.5 (p50 6.2, max 8.1) | 1-minute load |
| 3 | `inc-land-load-flake` recurrences | not collected | - | an incident count, not a machine reading |
| 4 | Idle Simulator GB-hours | sampler and sim-lock events | 0.000 idle of 0.000 in total | the simulator kind is the launchd_sim subtree of a booted fw-* device; idle means no sim-lock held |
| 4 | Boots per day times boot time | sim-lock events | 0 sim-lock acquire(s) in 0.04 day(s) | boot time is not measured |
| 4 | Serena/MCP processes counted, idle alert | not collected | - | these processes fall into `other`; no separate count |

## Limits

- Smoke sample: 3.8 min on one Mac, mostly this task's own work. Read it as a demonstration of the tables, not as a picture of a normal day or of the 3-day collection.
- Local-only lane: this Mac's resources cannot be measured on CI; the raw files stay under `.fw-console/` (gitignored).
- The 20 s cadence misses anything shorter (a 5 s lake build can fall between two samples); `top` itself costs the time in the cost row, and a sample under heavy load may be late (see the gap rows).
- Footprint per process can count shared pages twice, so only per-kind rows are given.
- The pressure limits are first guesses and `swapPct` is on dynamic swap; both are revised after the first day.
- A Safari counts only under a `safaridriver` we started; the WebKit helpers of a Safari the user opened are excluded by ancestry.
- `node` processes are all `node`: a watcher of ours and someone's dev server both count there.
