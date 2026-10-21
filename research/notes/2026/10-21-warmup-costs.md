---
id: 2026-10-21-warmup-costs
kind: note
title: "Warm-up costs: what each kind of process costs to start cold on this Mac, and the idle grace Fw.Sup can derive from it"
status: final
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [fw-sup, daemon, resources, cold-start, idle-grace]
---

# Warm-up costs (2026-10-21)

Task `sup-warmup`, stage 0 of the fw-sup plan (`daemon-design` section 5: "the grace per kind needs warm-up costs that
are not recorded today"). Question: what does it cost to start each kind of process cold, so that the idle grace of a
warm one can be priced by it?

**Unit of decision.** One cold-start cost per kind (lake serve, Simulator boot and shutdown, fwcore start, longest lake
build p99), each MEASURED with its command, repeats and machine load; the proposed idle-grace rule per kind as an
input to `Fw.Sup`. The Lean encoding of the rule is a follow-up (sup-model, sup-route).

**Accepted limits.** Local measurements on a shared, busy Mac (8 cores, 16 GB): every sample carries the load average
and the free memory beside it, and none is a CI result. The Simulator runtime available here is the pinned iOS 27.0
build 24A434 on an iPhone 15 Pro Max device type, the platform `.github/scripts/check-simulator.sh:11-13` pins for CI; CI's host is a
different machine, so its boot time differs.

## How it was measured

- **Lane: local.** These are this Mac's own process costs; CI runners cannot show them (work-graph `sup-warmup`,
  `devices: local`). Nothing here is phone time.
- **No land running.** Before every sample `measure.mjs` runs `pnpm -s fw land --queue-status` and checks the land lock
  (`fw-land.lock` in the git common directory). A queued land or a held lock makes it wait 30 s and ask again; it
  never stops anything. The Mac was still loaded by other agents' work (columns `load1`, `free MB`, `avail MB`):
  free = free + speculative pages, avail = free + inactive + purgeable pages (`vm_stat`), swap used in
  `results.json`.
- **Processes.** Every `lake serve` is spawned in its own process group and TERMed after its sample; the Simulator is a
  device the script creates (`fw-warmup-<pid>-<n>`) under `scripts/sim-lock.sh` and deletes; devices that were there
  before (including a booted one) were not touched. The device list is read back after the run (`leftover` column in
  the Simulator line of the table).
- **Footprint.** Memory is `footprint -j` (the physical footprint Activity Monitor shows) of the process and its
  descendants; RSS counts shared mappings once per process, so a Simulator tree (about 180 processes) sums to several
  times its footprint in a debug run. fwcore additionally reports `time -l` max RSS.
- **Cold cache.** The OS file cache cannot be dropped without a privileged `purge`; so "cold" here means a new process,
  not a cold disk. The first sample of a series is the closest to cold and is listed first.

Reproduce (needs `lean/.lake` built; Node 24.22.0):

```
node research/notes/2026/warmup-costs/measure.mjs lakehist --until 2026-10-21T12:55:33.147Z
node research/notes/2026/warmup-costs/measure.mjs fwcore --n 5
node research/notes/2026/warmup-costs/measure.mjs fwcore --rss-only   # the second fwcore series alone, spawn series kept
node research/notes/2026/warmup-costs/measure.mjs lsp --n 5
node research/notes/2026/warmup-costs/measure.mjs vitest --n 3
node research/notes/2026/warmup-costs/measure.mjs sim --n 3
node research/notes/2026/warmup-costs/render.mjs [--check]
```

`measure.mjs` merges one kind per call into `results.json`; `render.mjs` replaces the block between the generated
markers below with tables built from it (`--check` exits 1 when the note and `results.json` disagree). Nothing in the
block is typed by hand.

Commands, one per kind (also the first line of each table section):

| kind | command | repeats |
|---|---|---|
| lake serve | `lake serve` in `lean/`, LSP `initialize`, `didOpen` of `Fw/Store/Ci.lean` (about 450 lines, one import), time to the first `publishDiagnostics` and to `$/lean/fileProgress` with nothing left to process | 5 fresh servers |
| Simulator | `simctl create`, `boot` + `bootstatus`, `shutdown`, `boot` + `bootstatus` again, `shutdown`, `delete` | 3 fresh devices |
| fwcore | `spawnSync(fwcore)` with one `console.landTier` request line, as `fwcoreCall` does; `/usr/bin/time -l` for memory | 5 + 5 |
| fwcore in a test run | `pnpm exec vitest run test/checks.test.ts` in `apps/runner` (every case calls `fwcoreCall` once) | 3, plus one counted run |
| longest lake build | nearest-rank quantiles of the local `lean/check` `lake build` spans in `.fw-console/timings.jsonl` (`fw timings`'s own method) | 1 pass over the history |

<!-- GENERATED:tables -->
## Tables (generated from results.json by render.mjs; do not edit)

### Headline numbers

- **lake serve** (5 fresh servers): first diagnostics median 540 ms, file done median 2584 ms, max 4790 ms; tree footprint 234 MB.
- **Simulator** (3 fresh devices): first boot to ready median 46.1 s, reboot to ready median 13.3 s, shutdown median 4.34 s (pooled: 3 first and 3 second shutdowns; first alone 4.88 s, second alone 4.26 s); tree footprint 1448 MB at most.
- **fwcore start**: spawn to reply median 72.2 ms (5 runs), `time -l` real median 40 ms, peak footprint 11 MB, binary 78 MB.
- **fwcore in a test run**: median 52 ms per start inside a vitest worker; `checks.test.ts` starts it 74 times.
- **lake build** (local history, 2026-10-17 to 2026-10-21): rebuild p50 13.9 s, p90 45.1 s, p99 190.9 s, max 303.3 s (n 384); p99 below load1 10: 116.3 s (n 66, equals its max), at or above: 190.9 s (n 318).

### Cold-start cost per kind

| kind | typical cold cost s | worst cold cost s | basis | footprint MB |
| --- | --- | --- | --- | --- |
| lake serve (spawn to file done) | 2.58 | 195.7 | median of 5 ok runs (max 4.79 s); worst = max plus the rebuild p99 (stale oleans) | 234 |
| Simulator (reboot to ready) | 13.3 | 48.6 | median reboot-to-ready of 3 runs (max 14.8 s); worst = max first boot of a new device; stop (shutdown) max 8.49 s | 1448 |
| fwcore start (one request) | 0.07 | 0.14 | median of 5 runs (max 143 ms); worst = max incl. in-test starts | 11 |

Longest lake build (no idle process, so no grace; it bounds the worst case above): p99 of 384 rebuilds of 2 s or more, 190.9 s.

### Proposed idle grace per kind (rule: grace = clamp(10 x typical cold cost, gMin, 1800 s), typical = median of n runs, gMin = 2 x tick)

The supervisor tick is not fixed (daemon-design S4 names `tickMax` with no number), so gMin is shown for two ticks: 20 s (the stage 0 sampler of check.json section 5, INFERRED to be the tick) and 300 s (`fw watch --interval 300`, docs/team/tools/fw-watch.md:7, the only loop today).

| kind | typical (median) cold cost s | k x cold s | grace s at tick 20 s (gMin 40 s) | grace s at tick 300 s (gMin 600 s) |
| --- | --- | --- | --- | --- |
| lake serve (spawn to file done) | 2.58 | 10 x 2.58 = 26 | 40 | 600 |
| Simulator (reboot to ready) | 13.3 | 10 x 13.3 = 133 | 133 | 600 |
| fwcore start (one request) | 0.07 | 10 x 0.07 = 1 | 40 | 600 |


### lake serve to first diagnostics

Command: `cd lean && lake serve  (LSP client: initialize, initialized, didOpen Fw/Store/Ci.lean, 454 lines; a fresh server per sample, process group TERMed after)`. Measured 2026-10-21, 5 fresh servers, `Fw/Store/Ci.lean` (454 lines).

| run | initialize ms | first diagnostics ms | file done ms | server tree footprint MB | load1 / free MB / avail MB |
| --- | --- | --- | --- | --- | --- |
| 1 | 268 | 572 | 3013 | 224 | 65.28 / 378 / 3479 |
| 2 | 190 | 540 | 4790 | 225 | 58.75 / 397 / 3570 |
| 3 | 228 | 534 | 2349 | 230 | 56.29 / 663 / 3631 |
| 4 | 206 | 581 | 2584 | 230 | 51.56 / 346 / 3531 |
| 5 | 186 | 473 | 1881 | 234 | 49.43 / 283 / 3537 |

### Simulator boot and shutdown

Command: `xcrun simctl create <fresh name> "iPhone 15 Pro Max" <iOS 27.0 24A434>; simctl boot <udid>; simctl bootstatus <udid>; simctl shutdown <udid>; boot+bootstatus again; shutdown; delete  (scripts/sim-lock.sh held; own device only)`. Measured 2026-10-21, 3 devices created and deleted by the run (0 left over), iOS 27.0 (24A434), iPhone 15 Pro Max.

| run | create ms | first boot ready ms | shutdown ms | reboot ready ms | shutdown ms (2nd) | delete ms | sim tree footprint MB (1st / 2nd boot) | load1 / free MB / avail MB |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 501 | 48598 | 4879 | 14775 | 4233 | 260 | 1168 / 806 | 39.02 / 521 / 3981 |
| 2 | 310 | 42213 | 4338 | 13345 | 4492 | 324 | 1448 / 734 | 214.58 / 948 / 4341 |
| 3 | 459 | 46116 | 8486 | 12894 | 4265 | 211 | 1147 / 732 | 183.58 / 675 / 4223 |

### fwcore start

Command: `node: spawnSync(lean/.lake/build/bin/fwcore, [], {input: one console.landTier request line, env LEAN_ABORT_ON_PANIC=1}) as fwcoreCall in apps/runner/src/run.ts; rss series: /usr/bin/time -l fwcore < the same line`. Measured 2026-10-21, binary 78 MB.

| run | spawn to reply ms | exit | load1 / free MB / avail MB |
| --- | --- | --- | --- |
| 1 | 71.7 | 0 | 69.48 / 407 / 3420 |
| 2 | 142.9 | 0 | 69.48 / 379 / 3394 |
| 3 | 70.2 | 0 | 69.48 / 313 / 3383 |
| 4 | 83.2 | 0 | 65.28 / 484 / 3499 |
| 5 | 72.2 | 0 | 65.28 / 470 / 3468 |

| run | real ms (time -l) | max RSS MB | peak footprint MB | load1 / free MB / avail MB |
| --- | --- | --- | --- | --- |
| 1 | 190 | 46 | 11 | 10.44 / 288 / 3781 |
| 2 | 40 | 46 | 11 | 10.44 / 328 / 3735 |
| 3 | 40 | 46 | 11 | 10.44 / 332 / 3749 |
| 4 | 40 | 46 | 11 | 10.44 / 412 / 3810 |
| 5 | 40 | 46 | 11 | 10.44 / 988 / 4106 |

### fwcore starts inside a test run

Command: `cd apps/runner && pnpm exec vitest run test/checks.test.ts  (wall of the process; one extra run with FW_CORE_BIN set to a counting wrapper gives the number of fwcore starts)`. Measured 2026-10-21. The file runs 55 tests and starts fwcore 74 times (counting wrapper, separate untimed run).

| run | process wall ms | vitest duration ms | exit | load1 / free MB / avail MB |
| --- | --- | --- | --- | --- |
| 1 | 4741 | 3960 | 0 | 21.7 / 241 / 3326 |
| 2 | 5786 | 4770 | 0 | 22.53 / 296 / 3285 |
| 3 | 5103 | 4410 | 0 | 21.76 / 458 / 3116 |

Starts seen from inside a vitest worker (`a temporary apps/runner/test/zz-warmup-probe.test.ts (removed after the run) calls fwcoreCall 12 times in a row and times each call with performance.now, run as pnpm exec vitest run test/zz-warmup-probe.test.ts`):

| run | first start ms | median of 12 ms | max ms | load1 / free MB / avail MB |
| --- | --- | --- | --- | --- |
| 1 | 75.4 | 52.2 | 75.4 | 21.06 / 539 / 3549 |
| 2 | 49.1 | 52.3 | 74.6 | 22.18 / 458 / 3704 |
| 3 | 47.9 | 49.7 | 80.2 | 22.18 / 285 / 3659 |

Starts x in-test median (52 ms) = 3848 ms of the 74 starts, against a process wall of 5103 ms (median of 3).

### longest lake build (history)

Source: `node measure.mjs lakehist: nearest-rank quantiles of .fw-console/timings.jsonl rows tool=lean/check host=local step='lake build' (scripts/fwcore-build.sh: lake build + strip + build record, one per lean/check.sh); bench rows tool=lake-slot/bench`. Window 2026-10-17 to 2026-10-21 (read 2026-10-21). Nearest-rank quantiles, seconds.

| series | n | p50 s | p90 s | p99 s | max s |
| --- | --- | --- | --- | --- | --- |
| all `lake build` stages | 1185 | 0.79 | 21.2 | 92.7 | 303.3 |
| exit 0 | 1170 | 0.78 | 20.6 | 90.2 | 303.3 |
| exit 0, load1 < 10 | 300 | 0.57 | 12.6 | 45.0 | 116.3 |
| exit 0, load1 >= 10 | 870 | 0.89 | 24.3 | 108.7 | 303.3 |
| exit 0, under 2 s (no module rebuilt) | 786 | 0.58 | 1.04 | 1.65 | 1.95 |
| exit 0, 2 s or more (a rebuild) | 384 | 13.9 | 45.1 | 190.9 | 303.3 |
| a rebuild, load1 < 10 (p99 equals max at this n) | 66 | 11.7 | 26.2 | 116.3 | 116.3 |
| a rebuild, load1 >= 10 | 318 | 14.3 | 45.9 | 190.9 | 303.3 |
| bench: solo build, plain | 6 | 5.20 | 10.3 | 10.3 | 10.3 |
| bench: clean fwcore-build, plain | 5 | 144.6 | 178.0 | 178.0 | 178.0 |
<!-- /GENERATED:tables -->

## Reading the numbers

Status of each claim: CONFIRMED (a source or a table above), MEASURED (a number in the tables), INFERRED (my reading).

- **The kinds sit on very different scales (MEASURED).** A fwcore start is tens of milliseconds, a lake serve is
  seconds, a Simulator boot is tens of seconds, a rebuild is up to minutes (headline numbers above). A grace priced
  by cold cost therefore differs by that ratio between kinds, which is what the design asks for (Simulator long, lake
  serve medium, warm core short; `daemon-design` section 3).
- **fwcore start is a time cost, not a memory cost (MEASURED: 11 MB footprint).** Keeping it warm saves wall time
  only. In `checks.test.ts` the starts are most of the file's wall time (INFERRED: the probe request
  `console.landTier` is assumed to cost what the requests of `checks.test.ts` cost; the 74 starts x in-test median
  and the process wall are in the generated line under the test-run table). That is the case for one warm core in the
  daemon (stage 2); it is not a case for a long idle grace.
- **The Simulator needs the device kept, the process stopped (MEASURED: first boot 46.1 s median against 13.3 s for a
  reboot, about 3.5 times).** So an idle teardown must `simctl shutdown` the repo's device and keep it, never delete
  it. Shutdown by the repo's UDID only, with a simctl timeout, is what the check of `daemon-design` asks for its
  section 5 (CONFIRMED: check.json corrections, stage 4: "`simctl shutdown` only for the repo's device UDID").
- **Footprint of a fresh Simulator is below the idle 3 GB of the baseline (INFERRED).** A device booted here had no
  app opened in it; the baseline's idle device had loaded content. What a stop frees depends on what ran in the
  device, so the supervisor should read the footprint when it decides, not assume one.
- **Load (MEASURED, 5 and 3 samples; the lake build split is n 66 and n 318).** Samples were taken between the load1
  values listed beside each. The 3 Simulator samples show no ordering by load. Across the 5 lake serve samples load
  falls from run 1 to run 5 (65 to 49), yet file-done time rises at run 2 and again at run 4: two exceptions, so
  there is no clear ordering with 5 samples (INFERRED). The lake build does follow load, on the rebuild series the
  grace uses (exit 0, 2 s or more): p99 116.3 s below load1 10 (n 66, so p99 equals the max) and 190.9 s at or above
  (n 318), tables above. Read the build number as a load-dependent upper bound (INFERRED).
  The 5 fwcore `time -l` samples were re-measured in round 2 at load1 10.4 (the first series ran at 65): real time
  40 ms for four runs and 190 ms for the first, while the spawn series (72 ms median) stayed from the load-65 session
  (MEASURED, tables above); peak footprint and RSS did not change with the load.
- **Interpretation of "longest lake build of a single module" (INFERRED).** `timings.jsonl` records the `lake build`
  stage of a `check.sh` run (modules rebuilt after a change, then strip and the build record), not one module. The
  stage's p99 over rebuilds of 2 s or more is the closest recorded number and an upper bound for one module.

## Idle grace as an input for Fw.Sup

The design (`daemon-design` section 3, `stop_only_idle`) stops a ready, unleased resource when
`now - lastUse >= grace kind` or under memory pressure, and says the grace is "priced by cold-start cost". This is the
rule that fits the measurements, stated as an input; whether it is the right one is a Lean question (sup-model).

- **Rule (INFERRED).** `grace kind = clamp (K * typical cold cost kind) gMin gMax`, with `K = 10`, `gMin = 2 x tick`,
  `gMax = 1800 s`, and `typical cold cost` the median of the n runs of the kind (nearest rank; the worst is the max).
  - `K * cold` is the ski-rental argument. Keeping a process warm for exactly its cold cost `B` is 2-competitive
    against an offline choice when waiting time and idle time weigh the same (`K = 1`). An agent waiting on a cold
    start costs more than an idle process costs while memory is free, so `K > 1`; 10 is a starting value, not a
    measurement, and the first week of stage 0's reuse-gap log should replace it.
  - `gMin = 2 x tick` keeps the stop decision off the tick: a grace under two ticks would race it. The tick is not
    known: `daemon-design/design.md` axiom S4 names `tickMax` without a number, and the `~20 s` of check.json section 5
    is the stage 0 sampler period, not a declared tick (INFERRED that the tick is no longer than the sampler). The only
    supervisor loop that exists today is `fw watch --interval 300` (CONFIRMED, docs/team/tools/fw-watch.md:7). So
    `gMin` is a function of the tick and the grace table above shows two: tick 20 s gives `gMin` 40 s, tick 300 s gives
    600 s. At tick 300 s `gMin` (600 s)
    exceeds every `K x cold` (largest 133 s, MEASURED) and all three kinds get 600 s; at tick 20 s only the
    Simulator's 133 s exceeds `gMin` 40 s. sup-model fixes `tickMax`; this note does not. `gMax` is the 30-minute re-arm period of the watch stream: a
    resource unused for that long is not in a work loop.
  - Under pressure the grace does not apply (`shedding s`), so `K` only decides the idle-and-comfortable case.
- **Typical, not worst.** The rule uses the typical restart: the median of the n runs of an existing device rebooted on fresh oleans (the max of the runs is the worst column). The worst
  case (a first boot of a new device, `lake serve` on stale oleans that need the longest rebuild) belongs to the
  start timeout (`startMax`, theorem `start_bounded`), not to the grace.
- **Per kind.** The long cold start (Simulator) gets the longest grace and is the only kind whose stop is ours to
  decide: it is the biggest idle process and nobody else restarts it. lake serve is owned by an MCP server (count and
  alert only until its restart behaviour is verified, check.json section 5), so its grace is a reporting threshold,
  not a stop. fwcore has no idle process today; the grace applies to the warm core of stage 2, and at `gMin` it is
  effectively "stop when quiet".
- **The lake build** has no idle process (a job under a ticket); its p99 bounds the worst-case cold start of
  lake serve (stale oleans) and is the natural `holdMax` input for a build ticket.

## Open items and follow-ups

- Lean encoding of the rule, the clamp bounds and `K` (sup-model, sup-route); golden vectors from `results.json`.
- Replace `K = 10` with a value fitted to measured reuse gaps once stage 0's acquire/release logs exist (sup-baseline).
- A per-module lake build time is not recorded anywhere (`timings.jsonl` has the whole `lake build` stage). The p99
  above is the stage, not one module; a per-module span would need `lake build` output parsing.
- Cold file cache: not measured (needs `purge`, which is privileged).
