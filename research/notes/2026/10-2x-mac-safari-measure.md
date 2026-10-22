---
id: 2026-10-2x-mac-safari-measure
kind: note
title: "Safari on this Mac and in the iOS Simulator: a local lane with a quiet rule, and what xctrace records (mac-safari-measure)"
status: draft
created: 2026-10-22
topics: [webkit, safari, simulator, macos, xctrace, measurement, host-load]
---

Task `mac-safari-measure`, branch `worktree-wf_f4a6ed0e-0c6-1`, no CI run (local lane, named exception (c) of "Measure on CI": a real Apple GPU and display).
User request: "let's try to measure on safari of iOS simulator and macOS". Tags: MEASURED (a file under `results/mac-safari/` named here),
PROVED (Lean theorem named here), INFERRED (reading of MEASURED data). Nothing here is phone time and nothing is a CI result.

## Answer

- **The lane exists and is proved, but this shared Mac never gave it a quiet pass: 0 accepted passes of 30 attempted (macOS Safari 20, Simulator 10). There is no
  cadence verdict, so there is no arm ranking from this lane.** Every row is a refusal by Lean `Fw.Sup.Measure.judge` (29 before the pass, 1 after; PROVED `judge_refuse_before`, `judge_refuse_after`). **Cause (MEASURED, per-pass files): two terms.** The fixed ceiling `loadMax 2.5` sat below this Mac's usual idle load (2.75-14.47 in 15 of 20 macOS readings, 12 of them 3.1-7.0; 1-minute load 3.2-4.3 with no builder running), and when the load did drop under 2.5, available memory was under the 1024 MB floor (5 macOS refusals were for memory only, at load 1.57-2.46; memory is a reason in 16 of 30 rows). Round 2 replaces only the load ceiling, by a measured floor (next section); the memory floor is unchanged, so a memory-starved Mac still gives no pass; the Simulator then added load 300-500 on top. The rule was not weakened to get a pass. MEASURED, `results/mac-safari/safari/` and `results/mac-safari/sim/`.
- **macOS Safari (safaridriver): drivable with no admin step, cadence only.** `safaridriver` opens a 430 x 932 window and runs the same recorder, hero burst and end push
  as the Simulator lane; it exposes no Inspector protocol, so there are no Timeline events (no Paint, no Composite). MEASURED (harness debug run, below).
- **iOS Simulator: the Simulator itself makes the Mac not quiet.** A freshly created device booted with Safari launched and no page raised the 1-minute load
  from 64 to 308, 381, 435, 479, 515 within 90 s (the quiet ceiling is 2.5), took available memory to 167-562 MB (floor 1024), memory pressure to level 2 and
  the compressor to 2-25 GB per minute. Sixty seconds after shutdown it was still 143. So with the rule as proved, no Simulator pass can be accepted on this
  Mac while the Simulator runs. MEASURED, idle-boot probe. This matches the CI runner finding of `10-18-webkit-quiet.md` (load 400-950 from the Simulator's own services).
- **xctrace (local, Xcode 27.1): Animation Hitches does not record the Simulator; it does record macOS Safari when attached to its process.**
  Simulator: "Hitches is not supported on this platform" (the same refusal as CI, `10-2x-xctrace-ci.md`); Metal System Trace records and finalizes (81 tables) but has
  no hitch table. macOS: `--all-processes` records hitch rows in 1 of 3 tries; `--attach <Safari pid>` gives hitch rows in 8 of 21 recordings (table below). MEASURED, `results/mac-safari/xctrace*.json`.
  Per-zone hitch counts are obtainable but were not added to the lane: no pass was accepted to carry them, the recordings cover the whole 16 s and not the zone, and the counts are not stable (below).

## Round 2 fixes (review of the first round)

- **Quiet ceiling = measured idle floor + margin (PROVED).** `ceilCenti q fl = fl + loadMarginCenti` (margin 1.00). The floor `fl` is `baselineFloor`: the median load of 8 readings taken 10 s apart, defined only when
  every reading is calm in all non-load terms (memory, pressure, swap, thrash, compression, no other slot holder), the spread (max - min) is at most 1.50 and the median at most 8.00; otherwise there is no floor and no pass starts
  (`baselineFloor_none_few|loud|spread|high`, `baselineFloor_some`, `baselineFloor_between`). `quiet_load_le`: a quiet reading is at most floor + margin; `accepted_load_le_cap`: any accepted pass is at most 8.00 + 1.00 whatever the baseline.
  `judge` takes the floor; goldens `measure.floor`, `measure.judge` (with `floorCenti`) are replayed by the twin (`baselineFloor`, `judge(b, a, fl)`), and a sweep test checks that `quiet` never accepts a load above floor + margin.
- **Simulator settle.** `simFloor q p boot rs` uses only readings at least `settleS` (120 s) after boot, so the heavy first seconds of a boot are not read as the floor (`simFloor_none_unsettled`, `simFloor_some_settled`).
  The sliding window of `takeBaseline` waits until the last 8 readings are steady, up to `--base-wait-s` (600 s), and gives no floor otherwise.
- **Debug run on this Mac (read-only, no Simulator, no slot, 156 s, not a result).** 8 readings, 10 s apart: load 4.27, 4.31, 4.18, 4.30, 3.79, 3.52, 3.35, 3.22 with one other slot holder live. The rule refused ("no steady idle floor"):
  every reading had a live holder (`holdersMax` 0); the load spread (1.09) alone was within 1.50. This confirms both causes of the first round: the old ceiling 2.5 sat under every one of these readings, and the new rule still refuses a Mac that is not idle.
- **Simulator device reuse.** `ensureDevice` finds `fw-mac-safari-27` by name and creates it only when none exists (it throws on several of that name or a missing template); the lane only boots and shuts down. `removeDevice` is gone, and
  `meta.device.createdThisRun` records the one creation. Per-run creation had caused the first-boot load of 93-551 and a MobileCal 0x8BADF00D crash. Tests: reuse, create once over four runs, duplicates refused.
- **xctrace safety (incident `inc-tmp-trace-leak`: about 27 kernel traces of 5-8 GB, about 140 GB, in the user temp folder; an orphan ran 41 minutes).** The probe now: records with `--time-limit` (Lean `ProbeLimits`, `probeAct`:
  wait, SIGINT at the limit + 60 s, SIGKILL at +120 s, the same for an orphan or a trace over 12 GB; PROVED `probeAct_orphan|oversize|late|interrupt|wait|bounded`); runs each child in its own process group with `TMPDIR` inside
  `<out dir>/.xctrace/work-<pid>` and refuses a work dir inside the temp folder (`assertOwnDir`); starts a recording only with 30 GB free (`mayRecord_low|room`); deletes the trace files after the export in a `finally` (`attempt`);
  holds the sim slot from before the first recording to the cleanup (`attempt` throws without a lease token); dies with its parent (`watchParent` and the per-child orphan check); sweeps stale `work-<pid>` dirs of dead probes.
  **Round 2 closes the user-temp leak path:** on Darwin Foundation resolves the temp dir from `confstr(_CS_DARWIN_USER_TEMP_DIR)` first and reads TMPDIR only when that fails (swift-foundation `Sources/FoundationEssentials/String/String+Path.swift:491-510@9539423`, CONFIRMED), so `TMPDIR` alone does not hold the recorder's `instruments*.ktrace`. `guard.mjs` reads `getconf DARWIN_USER_TEMP_DIR`, snapshots its `instruments*.ktrace` names when the guard is made and after every wipe, adds the size of new ones born after the snapshot to `traceMB` at every look (Lean `probeAct` takes that sum), and `wipe()` deletes only those. One real record, `xctrace record --template "Animation Hitches" --all-processes --time-limit 5s` under a held `measure` slot (MEASURED, 88 s with the exports, one run, 2026-10-23): trace in the work dir 908 MB at the largest look, and afterwards no `instruments*.ktrace` in the user temp folder or in `$TMPDIR` (on this shell both are the same folder), the work dir holds only its empty `tmp`. This run does not show which folder the recorder wrote to; it shows that none is left behind. The group kill after a child exits now happens at its `exit` event, while the group id is still the leader's.
  Tests (`safari-local-guard.test.mjs`, 15): own group and TMPDIR, a fake child that writes into the confstr dir instead of `$TMPDIR` (counted, only new traces wiped, older ones and other names kept), user-folder traces toward the cap, `getconf` read, no file outside the work dir, temp-folder refusal, deadline kill of a child that ignores SIGINT with its group, size cap, parent loss, `killAll`, `dirMB`, `sweepStale`, no record without a slot,
  wipe on error, no record without disk room, `--time-limit` always present. One real 5 s recording was taken in round 2 (above).

## Method

- **Machine.** Apple M1 Pro, 8 cores, 16 GB, macOS 27.0.1, Safari 27.0.1, xctrace 27.1, iPhone 15 Pro Max Simulator type on iOS 27.0. The Mac is shared: other agents and the user's apps run.
- **Zones and arms.** Hero exit and end of page (`hero`, `end`), five arms deduplicated by `dedupArms` (none dropped): the original snapshot `orig`, the rewrite default `base`,
  `hx` = `?fw=hero.exit:threaded`, `mp` = `?fw=morph.panel:const-bounds`, `pf` = `?fw=platform:fade-threaded`. Rounds interleave the arms (`orderFor` of `gate-breakpoints/src/smooth/schedule.mjs`).
- **Quiet rule (Lean, `lean/Fw/Sup/Measure.lean`).** A reading is quiet when load is at most the floor plus 1.00 (see Round 2), available memory at least 1024 MB, memory pressure level 1, no swap-out, no thrash, no
  high compression and no other slot holder (`quiet_iff`; each failing reason is a theorem, `not_quiet_load` ... `not_quiet_holders`). A pass is read before and after; `judge` accepts it
  only when both are quiet and in order within the span (`judge_accept`, `judge_stale_order`, `judge_stale_gap`); a refused or stale pass keeps no value (`kept_refused`, `kept_stale`).
  The readings come from the slot daemon's sampler (`fw slot status --json`). macOS Safari (and the macOS xctrace probe) hold a `measure` slot and take an exclusive `fw slot pass start|stop` around each measured window (task `slot-measure-exclusive`, on main); the Simulator lane keeps a `sim` slot,
  because the daemon shuts a booted device down 600 s after its last `sim` holder (`simAction`) and a `measure` slot does not count as one. Lean's `holders` reason
  (`not_quiet_holders`) still refuses a pass while another holder is live. The golden rows (`packages/contracts/golden/sup/measure.jsonl`, 69) are replayed by the TS twin `safari-local-reduce.mjs`.
- **Per cell reduction (Lean).** rAF intervals in tenths of ms: skipped slots (`skipped`, slot 8.3 ms or 16.7 ms from the median, `slotOf_cases`), count over 25 ms (`longCount`), p50, p95, max
  (`stat_p_order`, `max_ge`). A verdict against `base` needs at least 3 accepted passes on both sides; `better` or `worse` only when every pass of the arm beats (loses to) every pass of the base,
  otherwise `same` (`outcome_better`, `outcome_worse`, `outcome_same`; `outcome_self`: an arm never beats itself).
- **Engines.** (A) `safaridriver -p <free port>` (detached, its pid and the Safari pids it started are stopped at the end), one origin serving each arm's tree; (B) MobileSafari in an own
  device `fw-mac-safari-27` (same type and runtime as the CI device, created once and reused), reached through `ios_webkit_debug_proxy`; the sim-cadence flow and the `profileWindow` reducer are reused.
- **Limits of the lane.** There is no A/A arm. The page clock is live on macOS Safari (not pinned). The Simulator is not iPhone hardware: its numbers would rank arms, not predict the phone.

## Quiet-checked passes (the pinned unit: zone x arm x engine, at least 3 accepted passes)

Result: none. Tables below are `node packages/measure-webkit/src/sim-local-summary.mjs <dir>` over the per-pass files. The 20 macOS rows come from one run of 40 minutes
(2 rounds, `--wait-s 120` per pass: a pass waited up to 120 s for a quiet reading); the 10 Simulator rows from one run of 10 minutes (1 round, `--wait-s 45`).

macOS Safari (safaridriver), 20 attempts:

| engine | window | arm | passes | refused (before/after/stale) | errors | long>25ms | skipped | p50 ms | p95 ms | max ms | Paint ms | Composite n | vs base (long) | vs base (skipped) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| safari | end | base | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | - | - |
| safari | end | hx | 0 | 1/1/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| safari | end | mp | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| safari | end | orig | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| safari | end | pf | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| safari | hero | base | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | - | - |
| safari | hero | hx | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| safari | hero | mp | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| safari | hero | orig | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| safari | hero | pf | 0 | 2/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |

iOS Simulator (MobileSafari), 10 attempts:

| engine | window | arm | passes | refused (before/after/stale) | errors | long>25ms | skipped | p50 ms | p95 ms | max ms | Paint ms | Composite n | vs base (long) | vs base (skipped) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sim | end | base | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | - | - |
| sim | end | hx | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| sim | end | mp | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| sim | end | orig | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| sim | end | pf | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| sim | hero | base | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | - | - |
| sim | hero | hx | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| sim | hero | mp | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| sim | hero | orig | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |
| sim | hero | pf | 0 | 1/0/0 | 0 | - | - | - | - | - | - | - | insufficient | insufficient |

Why the passes were refused (MEASURED, last reading of each wait; a row keeps one reason per failing term):

| engine | attempts | refused before | refused after | reason load | reason avail | reason holders | reason compress | reason pressure | load of the recorded reading (min / median / max) | accepted |
|---|---|---|---|---|---|---|---|---|---|---|
| safari | 20 | 19 | 1 | 15 | 8 | 2 | 0 | 0 | 1.57 / 3.64 / 14.47 | 0 |
| sim | 10 | 10 | 0 | 10 | 8 | 0 | 1 | 0 | 4 / 32.49 / 354.15 | 0 |

Reading: on macOS Safari the lowest recorded load was 1.57 and the median 3.64 against the ceiling 2.5; 15 of 20 attempts failed the load term, 8 the memory floor, 2 had another slot holder; and one pass ran
(`safari end hx`: before accepted, after refused, its value dropped by `kept_refused`). On the Simulator all 10 attempts failed the load term (median 32.5, max 354) and 8 the memory floor. INFERRED: the Mac is not
quiet while the user and other agents work on it, and with the Simulator booted it cannot be; a booked quiet window or a dedicated Mac would be needed.

## Harness debug run (not a result)

With `--debug-ignore-quiet` (rows marked `debug: true`, refused as an `--out` under `results/`, files kept in the scratch area only) one pass per cell ran on macOS Safari to prove the harness works end to
end: windows took 4-7 s each, the Safari window was 430 px wide, the driver and Safari were stopped afterwards. Those numbers were taken while the Mac was loaded (load 6-11, memory under the floor); they are
neither reported nor ranked here, by the rule the lane enforces.

## xctrace on this Mac (the yes/no)

Probe `packages/measure-webkit/src/xctrace/probe.mjs`: records a template while a window runs, exports the table of contents and the hitch tables, and counts rows; Lean `hitchesRecorded`
(PROVED `hitches_not_finalized`, `hitches_no_rows`, `hitches_recorded`) says a trace "records hitches" only if it finalized and holds a hitch row.

| file | target | template | zone / arm | exit | trace finalized | hitch rows (all 6 tables) | `hitches` table rows | refusal |
|---|---|---|---|---|---|---|---|---|
| `xctrace.json` | sim | Animation Hitches | idle page | 2 | false | 0 | - | * [Error] Hitches is not supported on this platform. ; Recording failed with errors. Saving output file... ; Export failed: Trace is malformed - run data is missing. |
| `xctrace.json` | sim | Metal System Trace | idle page | 0 | true | 0 | - | * [Warning] Recovery Suggestion: This could be due to a missing package, or an error in a package under development. |
| `xctrace.json` | mac | Animation Hitches | hero / base, all processes | 0 | true | 0 | - | - |
| `xctrace.json` | mac | Metal System Trace | hero / base, all processes | 0 | true | 0 | - | - |
| `xctrace-mac.json` | mac | Animation Hitches | hero / base, all processes | timeout | true | 0 | - | - |
| `xctrace-mac.json` | mac | Metal System Trace | hero / base, all processes | timeout | true | 0 | - | - |
| `xctrace-mac.json` | mac-attach | Animation Hitches | hero / base, attach Safari | 0 | true | 3446 | - | - |
| `xctrace-zones.json` | mac | Animation Hitches | hero / base, all processes | 0 | true | 3700 | 3 | - |
| `xctrace-zones.json` | mac | Metal System Trace | hero / base, all processes | 0 | true | 0 | - | - |
| `xctrace-zones.json` | mac-attach | Animation Hitches | hero / orig | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones.json` | mac-attach | Animation Hitches | end / orig | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones.json` | mac-attach | Animation Hitches | hero / base | 0 | true | 8818 | 13 | - |
| `xctrace-zones.json` | mac-attach | Animation Hitches | end / base | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones.json` | mac-attach | Animation Hitches | hero / hx | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones.json` | mac-attach | Animation Hitches | end / hx | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones.json` | mac-attach | Animation Hitches | hero / mp | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones.json` | mac-attach | Animation Hitches | end / mp | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones.json` | mac-attach | Animation Hitches | hero / pf | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones.json` | mac-attach | Animation Hitches | end / pf | timeout | false | 0 | - | Export failed: Document Missing Template Error |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | hero / orig | 0 | true | 9048 | 10 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | end / orig | 0 | true | 8519 | 61 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | hero / base | 0 | true | 9228 | 1 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | end / base | 0 | true | 8660 | 46 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | hero / hx | 0 | true | 24 | 3 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | end / hx | 0 | true | 8511 | 34 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | hero / mp | 0 | true | 0 | 0 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | end / mp | 0 | true | 0 | 0 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | hero / pf | 0 | true | 0 | 0 | - |
| `xctrace-zones2.json` | mac-attach | Animation Hitches | end / pf | timeout | false | 0 | - | Export failed: Document Missing Template Error |

Reading (MEASURED unless marked):

- **Simulator.** Animation Hitches refuses: "Hitches is not supported on this platform." and the trace is malformed, as on the CI runner (`10-2x-xctrace-ci.md`). Metal System Trace records and finalizes (81 tables) but
  holds no hitch table, so no hitch count. Answer for the Simulator: no.
- **macOS Safari, `--all-processes`.** Three tries of Animation Hitches: 0 rows (finalized), 0 rows (stop timed out, finalized), 3700 rows with 3 hitches (hero, base). Three tries of Metal System Trace: no hitch table. Unreliable.
- **macOS Safari, `--attach <pid of the Safari the driver started>`.** 21 recordings of 16 s (zone x arm, one window inside): 8 with hitch rows, 3 finalized and empty (`mp`, `pf` cells), 10 not finalized (the stop did not
  finish and `Export failed: Document Missing Template Error`). In the first 10-recording run 9 stops timed out; after the probe sent SIGINT at limit + 60 s instead of killing at limit + 90 s, 9 of 10 finalized.
  Answer for macOS: yes, with attach, as a table of 6 hitch schemas (`hitches`, `hitches-updates`, `hitches-renders`, `hitches-framewait`, `hitches-gpu`, `hitches-frame-lifetimes`); about 2000 renders in 16 s means the display
  presented at about 125 Hz while rAF ran at 60 Hz (INFERRED: a ProMotion display).
- **Per-zone counts are not stable.** `hero / base` shows 13 hitches in one recording and 1 in another (`xctrace-zones.json`, `xctrace-zones2.json`), `hero / hx` shows 24 rows in all (almost no frames: the page was idle
  in the recording), and the `hitches` table counts the whole recording, not the zone (no row filter by the window's time range was written). So no per-zone count is reported as a result and none was added to the
  pass files; a lane that wanted them would filter rows by the zone's start and end and require the same quiet-checked passes. Follow-up, not delivered.
- **Why attach.** `--all-processes` also records the window server and every app; the hitch tables were empty in 2 of 3 tries. INFERRED: the hitch instrument needs the app process as its target; not checked in Apple documentation here.

## Against the CI numbers (ci-device-accuracy terms)

| source | engine | what it gives | what this lane adds |
|---|---|---|---|
| `10-2x-smoothness-webkit.md` (run 39634194664) | macOS Playwright WebKit and CI Simulator | frames over 60 ms per rep, render work per window, `Layout` records | a real GPU and display and a window size of 430 px; no accepted passes, so no comparison |
| earn-bound-arm run 39754568950 (commit 6a8482da, note `10-2x-earn-gpu.md` on that branch) | CI Simulator, 3 sim jobs of 36 windows | class counts per type for the earn bound arm (no-go for that candidate) | nothing comparable: the bound arm is not among this lane's five |
| `10-2x-morph-constant-bounds.md` (runs 39744614747, 39760667274) | CI Simulator | only Composite per frame on the open push is lower with const-bounds; the other cells overlap | `mp` is in this lane; no accepted pass, so no cell |

CONFIRMED statement: the CI notes' cadence on macOS (43 frames over 60 ms for the original against 4 for the rewrite in the hero zone) is a different engine build (Playwright WebKit 27.2) and a different
clock; a local number from this lane could not be put next to it without the same quiet stamp the CI runner lacks (`10-18-webkit-quiet.md`).

## TS stand-ins (glue, no decision)

The sampler reading (`readMachine`, `readingOf`), the wait loop (`waitQuiet`), the window scripts (the recorder, hero burst, end push), the W3C WebDriver client, the pgrep-based cleanup of the Safari the lane started,
the live clock on macOS Safari, the xctrace probe (process control and XML counting) and the markdown table printer hold no decision; the decisions are Lean (`quiet`, `baselineFloor`, `simFloor`, `judge`, `kept`, `outcome`, `stat`, `hitchesRecorded`, `probeAct`, `mayRecord`).

## Accepted limits and open items

- No accepted pass: the unit "at least 3 quiet-checked passes with a verdict" is not met on either engine, and this round took none. It needs a Mac whose baseline is steady (a booked window), measured by the new floor rule.
  The first real Simulator run creates `fw-mac-safari-27` once; its first boot is heavy and the settle period and sliding baseline wait it out.
- `safari-local-lease.mjs` now holds `measure` + `pass start|stop` for macOS Safari and the macOS probe (`holdMeasureSlot`); the Simulator keeps `sim`. A Simulator pass inside a measure window would need the daemon to treat `measure` as a booted-device holder: a follow-up for `slot-measure-exclusive`.
- `lean/scripts/check.sh` gained one stage line ("sup-measure golden check"), outside the task's file list.
- macOS Safari has no Timeline events through safaridriver; Paint and Composite exist only in the Simulator lane (Paint has a covered time, Composite is a count, Lean `isTimed`).
