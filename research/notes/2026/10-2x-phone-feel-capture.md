# Phone feel capture: what the page did while the person scrolled, next to the rating

Task `phone-feel-capture`, branch `worktree-wf_3521dc2c-a1c-1`. Claims are marked CONFIRMED (Lean theorem, golden or unit
test), MEASURED (a device run) or INFERRED.

## Why

The 2026-10-29 ratings-only session stopped after 6 of 10 visits: base 1,1 (hero cards lag and blink, end of page laggy);
v2-proved 3,3; v2-proved+glint-hold 3,3. The end of the page was laggy on every arm and A and B felt the same. A rating
alone cannot say whether the page got lighter and did not feel it, or felt lighter and was not. Each visit now records
what the page did, and a Lean rule sets it beside the rating.

## What a visit records

| Field | Source | Unit in Lean |
|---|---|---|
| Frame times, long frames (> 17 ms, > 34 ms) | page `requestAnimationFrame` loop | hundredths of a ms |
| Scroll trace | `scrollY` per frame; touch events (`s m e c`, x, y, finger count) | tenths of a px |
| Style, layout, paint records per 500 px zone | Timeline on for the visit; `performance.mark('cap:<frame>')` joins records to frames; `reduceSteps` + `zones(500)` as the counts lane; the saved visit keeps, per zone, the `zones()` counts in `feel.zones`: one count per `COUNT_TYPES` entry (`reduce.mjs`), in that order (style, layout, paint first) | records |
| Pin fights | every page call of `window.scrollTo` (the nav tween pins with `scrollTo({top, behavior:'instant'})`), against the scroll move of the frame before it | tenths of a px |
| Tween re-targets | `window.__fwTakeTrace` `push` events with the tween progress at the start (only the geom-timed variant emits them) | per mille |
| Hero-card blinks | computed opacity of every `hero.orbit_card` per frame | per mille |

The raw file `visits/<NN>-<label>.json` under the session directory is a `fw.phone.record/1` (frames, parts, touches,
viewport) with a `feel` block (active flags, card opacity, pins, starts), so the existing device and CI replay lanes can
replay the finger path (`normalize` accepts it; unit test "the saved raw record normalizes for the replay lanes").

Definitions, all in `lean/Fw/Device/FeelCapture.lean` and golden-checked by `device-feel-cap.mjs`:

- A gap is moving when the scroll moved across it or across the gap before it; `long17` and `long33` count moving gaps over
  1700 and 3400 hundredths of a ms (see the 2026-10-30 defects: Safari stamps whole milliseconds). Still frames never count (`longCount_still`), `long33 <= long17 <= moving`
  (`long33_le_long17`, `longCount_le_moving`).
- A pin fights when it goes against the scroll move at the pin (`fightAt`; `fightAt_noop`, `fightAt_still`,
  `fightAt_same_way`), so a pin with the finger is never a fight.
- A re-target is a tween start whose progress is strictly between 0 and 1000 (`retarget_mid`, `retarget_rest`, `retarget_end`).
- Blink: a card's opacity falls by at least 150 per mille below a frame before and a frame after, those two frames at most 8
  frames apart; a run of dipping frames counts once. `blink_dip`, `blink_wide_dip`, `blink_two` count; `blink_small_dip`,
  `blink_step_down`, `blink_slow_return`, `blink_fade_out`, `blink_constant` do not.
- Idle: after 1500 ms with no finger and no scroll move a frame is idle; its Timeline records are kept out of the zones.

## Joint reducer (Feel.lean)

Per arm: the rating verdict, the capture summary over the arm's visits (median long33, long17, pin fights,
blinks; top zone = the first zone with the most work, none when no zone has any) and a flag. The summary score is
`long33 + fights + blinks`; an arm is measured heavier or lighter than base when its score differs by at least 2
(`capMargin`; `measured_swap`, `measured_self`). Flags (`flagOf`): "felt worse, measured lighter" and "felt better,
measured heavier"; nothing else flags (`flagOf_quiet`, `flagOf_unmeasured`), base never flags itself
(`jointSame_base_quiet`). The TS twin `device-feel-cap.mjs` follows the golden `feel.jsonl` (kinds `capconsts`, `capture`,
`blinks`, `closeCause`, `joint`). `feel start` prints the rating table and the joint table at the end, on a stop command
and on a signal.

## Defects of 2026-10-29, fixed

| Defect | Fix | Proof |
|---|---|---|
| USB unplug showed as "connection closed by the proxy" | on a close this tool did not make, probe `idevice_id -l` once and say "the phone is not on USB" | Lean `closeCause`, golden, `test/wip-target-swap.test.mjs` |
| `ConditionOwner.recover()` SIGTERMed the owner before it acknowledged the set, leaving the condition on the phone | `termGate`: wait for the "fw-pin held" line, then signal, then wait for "fw-pin cleared" | `termGate_no_early_term`, `termGate_go_iff`, `termGate_late`, golden `term` |
| After a USB drop no clear is acknowledged | `droppedClear`: only after a USB drop, a phone that reads its pre-pin state, when that state is below the target, counts as cleared (end `clearedDrop`) | `endVerdictDrop_iff`, golden `enddrop` |
| `feel stop` without a server killed nothing useful | `fallbackAct`: SIGTERM the recorded session once (pid and start time must match, `mayKill`), wait up to 330 s, then recover | golden `fallback`, `test/device-feel-run.test.mjs` |
| Ctrl-C ended without a table | the CLI prints `summaryText` and the joint table on every end, also after an error | |
| Repeat rounds showed the same letters | a visit's label is its position, so no letter repeats (A to F) | `labels_fresh`, `test/device-feel.test.mjs` |
| `--seed` defaulted to 0 | `feel start` refuses without `--seed` | CLI check |
| Dry run 2026-10-30: 57% of steady 60 Hz moving frames counted as "long > 16.7 ms" (long17 475 of 739 moving gaps): Safari stamps frames to whole milliseconds, so a 16.7 ms frame reads 16 or 17 | limits 1670/3300 become 1700/3400 (`long17Cs`, `long33Cs`); the same visit files recount to 51 and 46 | golden `capconsts`, `longCount_stall`, `longCount_two_limits` |
| Dry run 2026-10-30: `feel start` found "0 of 0 tabs" when Safari was not running | `tabsOfLaunching`: with no tab listed, launch Safari with `devicectl device process launch` once and list again; the tab choice stays `tabPlan` | MEASURED on the phone (Safari terminated, then launched by the helper, one `about:blank` tab); glue, no unit test |
| Dry run 2026-10-30: `state.json` pin read `usbDropped` true after a normal clear | `dropWindow`: only log text before the owner's `fw-pin cleared pid=<pid>` line (or before our SIGTERM) can show a drop; the rule that uses the flag (`droppedClear`, `endVerdictDrop`) is unchanged | unit cases: normal clear then tunnel-closed line gives false; a mid-run drop gives true. TS stand-in for the log-window slice |

## Probe effect and limits (stated)

- The Timeline instrument is on during the visit and costs page time, as in the counts lane. The frame times of a
  captured visit are therefore not the frame times of an uncaptured one; compare captured visits with captured visits only.
- `getComputedStyle(card).opacity` once per card per frame forces a style flush; blink detection sees computed opacity only
  (not a layer swap or `visibility`).
- Re-targets are visible only on a variant that emits trace events. Pins are all `window.scrollTo` calls of the page,
  including ones that are not the nav tween.
- Scripted swipe is a stand-in for the person; Serious is induced; USB-drop handling is unit-tested only; n stays 2 per
  same-look arm; no CI run.

## Dry run

RUN 2026-10-30, iPhone 15 Pro Max on USB, unlocked, scripted swipe (no user input). Harness check, not a result.
`node src/device-feel-dry.mjs --site ../../apps/site/dist/aot --dir .local/phone/2026-10-30-feel-capture --driver .local/phone/2026-10-28-flip-driver --seed 1`
(about 5 min: pin Serious, 2 visits, 3 scripted swipe requests each (`--swipes 3`), rate 3, stop). Raw files stay under `.local/`.

First attempt ended at start with "found 0 of 0 tabs": Safari was not running (probe: launching it with `devicectl` made the proxy list one `about:blank`
tab). That is our harness gap, fixed (table above); no user-side setting was involved. Second attempt completed; the pin cleared (end `heatRemains`: the
phone was still warm after the clear, as for any run; the condition owner exited and its clear was confirmed); `state.json` pin records `acked` true and `usbDropped` true: the owner prints
"userspace tunnel transport closed (device disconnected?); tearing down" on every normal exit, after its `fw-pin cleared` line, and the
drop detector matched that line, so the flag was a false positive (no drop happened; `acked` true keeps the end verdict). Fixed after the run (table above).

| Visit (arm) | frames | touch events | active frames | Timeline rows | card series | pins | re-targets |
|---|---|---|---|---|---|---|---|
| 1 (v2-proved) | 1542 | 319 | 1487 | 36894 | 10 cards x 1542 | 0 | 0 |
| 2 (v2-proved+glint-hold) | 1528 | 313 | 1483 | 36556 | 10 cards x 1528 | 0 | 0 |

Counts from Lean's `captureOf` (TS twin, golden-checked) over the saved visits (frames, pins, starts, opacity; recomputed from the visit files: moving gaps, long frames, reversals, pins, fights and blinks match
this table), with the final limits 17 and 34 ms. The zone column is not recomputable from this run's visit files: they predate the fix that keeps the per-zone
per-zone `COUNT_TYPES` counts in `feel.zones`, so its figures come from this run's `feel.json` `captures[].zoneWork` (style + layout + paint summed per zone). Visits
saved from now on keep the per-zone counts per kind, and the zone column recomputes from them:

| Visit | moving gaps | long > 17 ms | long > 34 ms | pins | fights | reversals | blinks | zones with work |
|---|---|---|---|---|---|---|---|---|
| 1 | 739 | 51 | 0 | 0 | 0 | 5 | 0 | 1 (zone 0, 6285 records) |
| 2 | 742 | 46 | 0 | 0 | 0 | 5 | 0 | 1 (zone 0, 6328 records) |

(With the first limits, 16.7 and 33 ms, the same visits read long17 475 and 472.)

Well-formedness (all hold): schema `fw.phone.record/1`; frames `t`, `y`, `vh`, `vt` and the three part series have equal length; times
rise; the finger trace starts with `s` and ends with `e`, 6 start and 6 end events per visit; card opacity is 0 to 1000 for every frame and every card; Timeline rows are
present and joined to frames by `cap:<frame>` marks (`zoneNote` null); the joint table printed, next to the ratings, per arm. Fields that
stayed 0 and why: pins and fights (no nav tween in these arms), re-targets (only the geom-timed variant traces), blinks (opacity stayed 1000
on every card), long > 34 ms (no two-frame stall). Only zone 0 has work: the scripted swipes moved the page at most 473 px (visit 1) and 483 px (visit 2) by `frames.y`, with 5 reversals in each.
Printed joint lines: v2-proved "long>16.7ms 475, long>33ms 0, pin fights 0, blinks 0, most work in zone 0 (1 visit)" under the old limits.

Not covered: a real finger path to the end of the page (pin fights, end-zone work), the blink detector on a real dip (unit tests and goldens
only), a USB drop.

## Commands

As in `10-2x-phone-feel-kit.md`, with `--seed <n>` now required. Dry run drive script: `node src/device-feel-dry.mjs --site
<dist/aot> --dir .local/phone/<date>-feel-capture --driver .local/phone/2026-10-28-flip-driver --seed <n>`.
