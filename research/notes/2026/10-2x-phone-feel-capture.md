# Phone feel capture: what the page did while the person scrolled, next to the rating

Task `phone-feel-capture`, branch `worktree-wf_3521dc2c-a1c-1`. Claims are marked CONFIRMED (Lean theorem, golden or unit
test), MEASURED (a device run) or INFERRED.

## Why

The 2026-10-29 ratings-only session stopped after 6 of 10 visits: base 1,1 (hero cards lag and blink, end of page laggy);
v2-proved 3,3; v2-proved+glint-hold 3,3. The end of the page was laggy on every arm and A and B felt the same. A rating
alone cannot say whether the page got lighter and did not feel it, or felt lighter and was not. So each visit now records
what the page did, and a Lean rule puts the two side by side.

## What a visit records

| Field | Source | Unit in Lean |
|---|---|---|
| Frame times, long frames (> 16.7 ms, > 33 ms) | page `requestAnimationFrame` loop | hundredths of a ms |
| Scroll trace | `scrollY` per frame; touch events (`s m e c`, x, y, finger count) | tenths of a px |
| Style, layout, paint records per 500 px zone | Timeline on for the visit; `performance.mark('cap:<frame>')` joins records to frames; `reduceSteps` + `zones(500)` as the counts lane | records |
| Pin fights | every page call of `window.scrollTo` (the nav tween pins with `scrollTo({top, behavior:'instant'})`), against the scroll move of the frame before it | tenths of a px |
| Tween re-targets | `window.__fwTakeTrace` `push` events with the tween progress at the start (only the geom-timed variant emits them) | per mille |
| Hero-card blinks | computed opacity of every `hero.orbit_card` per frame | per mille |

The raw file `visits/<NN>-<label>.json` under the session directory is a `fw.phone.record/1` (frames, parts, touches,
viewport) with a `feel` block (active flags, card opacity, pins, starts), so the existing device and CI replay lanes can
replay the finger path (`normalize` accepts it; unit test "the saved raw record normalizes for the replay lanes").

Definitions, all in `lean/Fw/Device/FeelCapture.lean` and golden-checked by `device-feel-cap.mjs`:

- A gap is moving when the scroll moved across it or across the gap before it; `long17` and `long33` count moving gaps over
  1670 and 3300 hundredths of a ms. Still frames never count (`longCount_still`), `long33 <= long17 <= moving`
  (`long33_le_long17`, `longCount_le_moving`).
- A pin fights when it goes against the scroll move at the pin (`fightAt`; `fightAt_noop`, `fightAt_still`,
  `fightAt_same_way`), so a pin with the finger is never a fight.
- A re-target is a tween start whose progress is strictly between 0 and 1000 (`retarget_mid`, `retarget_rest`, `retarget_end`).
- Blink: a card's opacity falls by at least 150 per mille below a frame before and a frame after, those two frames at most 8
  frames apart; a run of dipping frames counts once. `blink_dip`, `blink_wide_dip`, `blink_two` count; `blink_small_dip`,
  `blink_step_down`, `blink_slow_return`, `blink_fade_out`, `blink_constant` do not.
- Idle: after 1500 ms with no finger and no scroll move a frame is idle; its Timeline records are kept out of the zones.

## Joint reducer (Feel.lean)

Per arm: the rating verdict (as before), the capture summary over the arm's visits (median long33, long17, pin fights,
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

NOT RUN. The probe at the start and again at the end of the task found the phone paired and reachable over the network but
not on USB (`device-cli.mjs ping`: "the iPhone ... is paired but not on USB"; `idevice_id -l`, `system_profiler SPUSBDataType`
and `ioreg -p IOUSB` list no iPhone). The Web Inspector proxy and the thermal condition need the cable, so no session could
start. No session, owner or proxy of mine was started; nothing is left on the phone.

What was checked without the phone (harness checks, not results):

- The page recorder `CAP_START_JS` ran in desktop Chrome against the built site: it found 10 `hero.orbit_card` elements, recorded
  frames, opacity, active flags and every `window.scrollTo` pin, and `inputsOf` + `captureOf` turned them into a capture
  (Timeline rows absent there, so zones empty: stated by `zoneNote`). Not a phone time and not a count.
- Unit tests: `test/device-feel-capture.test.mjs` (unit conversion, idle steps out of the zones, overscroll offset, a raw
  record that `normalize` accepts, a failing start leaves the session alive), `test/device-feel-cap.test.mjs`.

To deliver the dry run: plug the phone in and unlock it, then
`node src/device-feel-dry.mjs --site ../../apps/site/dist/aot --dir .local/phone/<date>-feel-capture --driver .local/phone/2026-10-28-flip-driver --seed 1`
(about 8 min: pin to Serious, 2 arms, 3 scripted swipes each, rate 3, stop). It prints one line per saved visit file and which
capture fields hold a value. Fields that can stay 0 on a scripted swipe: pins and fights (no nav tween in the first arms),
re-targets (only the geom-timed variant traces), blinks (only if a card dips).

## Commands

As in `10-2x-phone-feel-kit.md`, with `--seed <n>` now required. Dry run drive script: `node src/device-feel-dry.mjs --site
<dist/aot> --dir .local/phone/<date>-feel-capture --driver .local/phone/2026-10-28-flip-driver --seed <n>`.
