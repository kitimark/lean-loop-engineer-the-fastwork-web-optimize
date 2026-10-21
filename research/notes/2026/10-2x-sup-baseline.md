# Resource baseline of the dev Mac, first-day tables (task sup-baseline)

Status: MEASURED 2026-10-21 on the dev Mac (macOS, 16.0 GB RAM, 6.0 GB swap); 14 samples, 2026-10-21 13:02 UTC to 2026-10-21 13:07 UTC (a span of 4.3 min).
These are FIRST-DAY numbers. The 3-day collection continues in the running watch process; its full tables and the conclusions (which jobs to move, which limits to set) are follow-ups, not claimed here.
Every table below is generated from the local-only files `.fw-console/sup-samples.jsonl` and `.fw-console/locks.jsonl` by `apps/runner/src/sup-report.ts` (a TS stand-in; the verdict of each sample is Lean's); edit the generator, not this file.

## What is measured

- CONFIRMED (apps/runner/src/watch-collect.ts `sampleOnce`): every 20 s one `top -l 1 -stats pid,mem,cmprs`, `ps -A -o pid=,comm=`, `sysctl -n vm.swapusage` and `memory_pressure -Q` are read and reduced to one line: per kind the process count, the footprint and its compressed part, plus swap used, compressor size, free memory, 1-min load, the cost of the sample and the Lean verdict. No command line, path or user name is stored.
- CONFIRMED (lean/Fw/Obs/Health.lean, namespace `Res`): the kind of a process comes from the basename of its executable against a fixed allowlist (`kindTable`; every unlisted name is `other`); the verdict is `pressured` when swap use, the compressor or free memory trips its limit, else `busy` when a heavy kind (lean, chromium, simulator, webkit) runs or the 1-min load is at least 2.00, else `quiet`. Theorems: the verdict never lowers as pressure grows (`verdict_rank_mono`), and a quiet sample has no process of a heavy kind (`quiet_no_heavy`). The limits (swap 90 %, compressor 50 % of RAM, free 15 %, load 2.00) are first guesses, revisable after the 3 days.
- CONFIRMED (scripts/heavy-lock.mjs, scripts/lake-slot-lib.sh, scripts/sim-lock.sh): each lock appends an acquire and a release line (heavy-lock also a refuse line) with the time, kind, the holder's pid and start time, the wait or the hold in ms; no path, no argument, no owner name.

Footprint is the `top` MEM column per process. It counts the process's own compressed pages (CMPRS is the part of MEM that is compressed), so it does not under-report idle processes the way `ps` RSS does. It is per process: pages shared between processes (frameworks, the Lean runtime) are counted in each, so a sum over processes can exceed the machine's real use. Read the per-kind figures as upper bounds of that kind's share, and the rows as comparable between kinds, not as additive.

## Samples

| measure | value |
| --- | ---: |
| samples kept | 14 |
| dropped (another watcher sampled within 10 s) | 0 |
| samples with a missing reading (no verdict) | 0 |
| longest gap between samples (s) | 20.0 |
| gaps over 60 s | 0 |
| cost of one sample, p50 / p90 / max (s) | 0.7 / 1.2 / 1.4 |

## Verdict share

| verdict | samples | share |
| --- | ---: | ---: |
| quiet | 0 | 0.0 % |
| busy | 6 | 42.9 % |
| pressured | 8 | 57.1 % |
| unknown | 0 | 0.0 % |

`unknown` is a sample with a missing reading. `quiet` is the share of time a measurement on this Mac would not have been disturbed by our own heavy work; any other share is the machine as it was, including everything else the user runs.

## Footprint per kind

| kind | samples present | procs p50 | procs p90 | procs max | footprint MB p50 | p90 | max | of which compressed MB p50 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| lean | 14 (100.0 %) | 5 | 12 | 12 | 1299 | 1805 | 1808 | 1215 |
| fwcore | 14 (100.0 %) | 1 | 3 | 3 | 45 | 57 | 57 | 13 |
| node | 14 (100.0 %) | 21 | 27 | 29 | 1828 | 2237 | 2243 | 1030 |
| pnpm | 0 (0.0 %) | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| chromium | 0 (0.0 %) | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| simulator | 14 (100.0 %) | 1 | 1 | 1 | 15 | 15 | 15 | 12 |
| webkit | 14 (100.0 %) | 3 | 3 | 3 | 48 | 48 | 48 | 46 |
| other | 14 (100.0 %) | 577 | 584 | 589 | 18529 | 18785 | 18950 | 14436 |

All kinds together: footprint 21869 MB p50, 22231 MB p90, 22281 MB max (a sum of per-process figures; see the shared-page limit above). The largest sum (21.8 GB) exceeds the 16.0 GB of RAM, which shows the double counting: only the per-kind rows and their changes are meaningful, not their total.

## Machine

| measure | p50 | p90 | max |
| --- | ---: | ---: | ---: |
| swap used (MB) | 5531 | 5531 | 5563 |
| swap used (% of total) | 90.0 | 90.0 | 90.5 |
| compressor (MB) | 5105 | 5538 | 5814 |
| free memory (%) | 41 | 48 | 50 |
| load, 1 min | 26.2 | 92.0 | 118.3 |

Free memory is `memory_pressure`'s system-wide free percentage, so its p90 is the best and its p50 the typical case; the pressure limit trips at the low end.

## Simulator

| measure | value |
| --- | ---: |
| samples with a simulator-kind process | 14 |
| of which with no sim-lock held | 14 |
| simulator footprint, GB-hours | 0.001 |
| of which with no sim-lock held (idle), GB-hours | 0.001 |

The simulator kind includes `MobileSafari`, `SpringBoard` and the CoreSimulator service. The Simulator's WebKit helpers carry the same names as Safari's (`com.apple.WebKit.*`), so they count under `webkit`, and a Safari the user opens counts there too: `webkit` cannot tell the two apart. A booted Simulator is idle when the sim-lock is free.

## Locks

| lock | kind | acquires | refused | still open | waited >= 1 s | wait ms p50 | p90 | max | hold ms p50 | p90 | max | most at once |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| heavy | check | 1 | 0 | 0 | 0 | 12 | 12 | 12 | 47799 | 47799 | 47799 | 1 |
| lake-slot | build | 2 | 0 | 0 | 0 | 5 | 9 | 9 | 13472 | 28681 | 28681 | 1 |
| lake-slot | group | 1 | 0 | 0 | 0 | 7 | 7 | 7 | 17418 | 17418 | 17418 | 1 |

Lock events span 2026-10-21 13:02 UTC to 2026-10-21 13:07 UTC; 0 release(s) had no acquire in the window (the job began before logging).
`heavy` and `lake-slot` time stamps are in ms where the shell's `date` has `%N` (this Mac's does) and whole seconds otherwise; a `sim-lock` wait is counted in whole seconds (its poll loop sleeps 1 s). A release and an acquire at the same instant are counted as not overlapping, so "most at once" is a lower bound. The lake-slot pid is the calling shell's (`$$`), also inside a subshell, so two holders in one shell share a pid. With events on, `lake_slot` runs its command as a child instead of `exec`-ing it, so the shell stays alive for the build's duration; a wrapper killed by a signal logs no release (the hold shows as "still open") while its child keeps the slot.

## Limits

- First-day data only: one day of one person's use of one Mac. Do not generalize to other days or machines; the 3 days decide.
- The window is 4.3 min, under 6 h: every share above is dominated by whatever ran in it, which includes this task's own checks, tests and dry land. Read the numbers as a demonstration of the tables, not as a picture of a normal day.
- Local-only lane: this Mac's resources cannot be measured on CI; the raw files stay under `.fw-console/` (gitignored).
- The 20 s cadence misses anything shorter (a 5 s lake build can fall between two samples); `top` itself costs the time in the cost row, and a sample under heavy load may be late (see the gap rows).
- Kinds are by program name, so a `node` that is our watcher and a `node` that is someone's dev server both count as `node`.
