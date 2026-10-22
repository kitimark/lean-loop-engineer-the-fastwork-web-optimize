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
  cadence verdict, so there is no arm ranking from this lane.** Every row is a refusal by Lean `Fw.Sup.Measure.judge` (PROVED `judge_refuse_before`,
  `judge_accept_quiet`): the machine was not quiet before the pass. The rule was not weakened. MEASURED, `results/mac-safari/safari/` and `results/mac-safari/sim/`.
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

## Method

- **Machine.** Apple M1 Pro, 8 cores, 16 GB, macOS 27.0.1, Safari 27.0.1, xctrace 27.1, iPhone 15 Pro Max Simulator type on iOS 27.0. The Mac is shared: other agents and the user's apps run.
- **Zones and arms.** Hero exit and end of page (`hero`, `end`), five arms deduplicated by `dedupArms` (none dropped): the original snapshot `orig`, the rewrite default `base`,
  `hx` = `?fw=hero.exit:threaded`, `mp` = `?fw=morph.panel:const-bounds`, `pf` = `?fw=platform:fade-threaded`. Rounds interleave the arms (`orderFor` of `gate-breakpoints/src/smooth/schedule.mjs`).
- **Quiet rule (Lean, `lean/Fw/Sup/Measure.lean`).** A reading is quiet when load is at most 2.5, available memory at least 1024 MB, memory pressure level 1, no swap-out, no thrash, no
  high compression and no other slot holder (`quiet_iff`; each failing reason is a theorem, `not_quiet_load` ... `not_quiet_holders`). A pass is read before and after; `judge` accepts it
  only when both are quiet and in order within the span (`judge_accept`, `judge_stale_order`, `judge_stale_gap`); a refused or stale pass keeps no value (`kept_refused`, `kept_stale`).
  The readings come from the slot daemon's sampler (`fw slot status --json`). The lane holds a `sim` slot for its whole run; the slot daemon has no `measure` kind, so Lean's `holders` reason
  (`not_quiet_holders`) refuses a pass while another builder is live. 38 golden rows (`packages/contracts/golden/sup/measure.jsonl`) are replayed by the TS twin
  `safari-local-reduce.mjs` (7 tests).
- **Per cell reduction (Lean).** rAF intervals in tenths of ms: skipped slots (`skipped`, slot 8.3 ms or 16.7 ms from the median, `slotOf_cases`), count over 25 ms (`longCount`), p50, p95, max
  (`stat_p_order`, `max_ge`). A verdict against `base` needs at least 3 accepted passes on both sides; `better` or `worse` only when every pass of the arm beats (loses to) every pass of the base,
  otherwise `same` (`outcome_better`, `outcome_worse`, `outcome_same`; `outcome_self`: an arm never beats itself).
- **Engines.** (A) `safaridriver -p <free port>` (detached, its pid and the Safari pids it started are stopped at the end), one origin serving each arm's tree; (B) MobileSafari in an own
  device `fw-mac-safari-27` (same type and runtime as the CI device, created for the run and deleted after), reached through `ios_webkit_debug_proxy`; the sim-cadence flow and the `profileWindow` reducer are reused.
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
quiet while the user and other agents work on it, and with the Simulator booted it cannot be; a booked quiet window or a dedicated Mac would be needed. The proved rule (`judge`) did what it is for: it refused
every number that would have been taken next to other load.

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
the live clock on macOS Safari, the xctrace probe (process control and XML counting) and the markdown table printer hold no decision; the decisions are Lean (`quiet`, `judge`, `kept`, `outcome`, `stat`, `hitchesRecorded`).

## Accepted limits and open items

- No accepted pass: the unit "at least 3 quiet-checked passes with a verdict" is not met on either engine. It needs a quiet Mac (a booked window), and for the Simulator a quiet rule that accounts for the Simulator's own services
  (the CI note's finding, now MEASURED here too). Any change of the Lean thresholds is a separate task with Lean, goldens and twin together.
- The slot daemon has no `measure` kind; a follow-up should add one so the lease itself says "exclusive".
- `lean/scripts/check.sh` gained one stage line ("sup-measure golden check"), outside the task's file list.
- macOS Safari has no Timeline events through safaridriver; Paint and Composite exist only in the Simulator lane (Paint has a covered time, Composite is a count, Lean `isTimed`).
