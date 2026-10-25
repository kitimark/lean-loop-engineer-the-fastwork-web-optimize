# phone-end-counts: counts, painted area, layers and frame intervals per zone on the real iPhone

## Answer

- **15 of 16 planned visits ran (MEASURED, one phone, one session); morph.countdown:strip is the named lost arm.** The base ran three times
  (visits 0, 7, 15), so every verdict below is against a real A/B/A base spread (9 counts passes, 15 frame reps per cell). Strip failed in three
  tries: (1) usbReset (code 1006); (2) staleTab;
  after a hand reset, (3) Runtime.evaluate timed out mid-scroll with no USB cycle (other, which points at the arm). Lean `mayAttempt
  [usbReset, staleTab, other]` is false, so the visit is lost in this session and not retryable here. Its re-measure in phone-thermal-check is a
  new visit in a new session with a fixed harness (the wip.mjs provisional-target fix), not a fourth attempt.
- **engine.events:quiet is the one clean count win and it matches the CI Simulator.** FunctionCall and EventDispatch drop beyond the base spread
  in hero and rest (hero 276 vs 424 and 114 vs 262; rest 587 vs 831 and 288 vs 532), nothing else moves, frames the same. Simulator: EventDispatch
  -53%, FunctionCall -36% (runs 40134234199 vs 40134016822); phone: -56% and -35% in the hero zone.
- **hero.exit:threaded trades Layout and rAF for Paint and EventDispatch**, as on the Simulator (flag 39731192687, base 39739724461): hero Layout
  165 vs 195, rAF 163 vs 192, finish Layout 33 vs 52, rest Layout 321 vs 376; Paint (hero 665 vs 534, rest 981 vs 899) and EventDispatch (338 vs
  262, 625 vs 532) rise; frames the same; 4 to 5 more layers from y 3000 on.
- **morph.columns:idle-none and hero:scene-pause cut layers on the phone as on the Simulator** (census lane): idle-none
  124 vs 136 layers at y 3000, backing store 93.9 vs 111.0 MB (Simulator 106 to 90 MB); scene-pause 51 vs 136 layers at y 3000 (Simulator 58 vs
  136). idle-none changes no count and no frame cell. scene-pause raises FunctionCall and EventDispatch (hero 712 vs 424 and 562 vs 262), frames the same.
- **Four arms trade on the phone (Lean label mixed)**: rest Paint falls beyond the base spread (base 899 down to 595-711) while FunctionCall and
  EventDispatch rise; hidden-pause and logo-3d also have frames worse. morph.countdown:hidden-pause (finish Layout 86 vs 52, finish over50 1.85 per
  100 vs 0), nav:logo-3d (rest over50 4.89 per 100 vs 0.46, rAF 418 vs 400), and, in counts only, hero:scene-pause and morph.panel:const-bounds. INFERRED
  that work moves between steps (coalesced paints) rather than shrinking, not tested.
- **No count, area, layer or frame cell moves beyond the base spread for nav.hitTest:hit-skip, nav:clip-box, nav:bar-fixed and
  morph.mount:shift-dormant.** For hit-skip that is expected (INFERRED): the scripted scroll sends no pointer path, which is what the flag skips.
- **The original page is slow on the phone over the whole page (MEASURED):** hero 100 of 100 moving frames over 34 ms (rewrite 0.9), rest 79 of
  100 (rewrite 0.5); it has 30 to 47 layers at y 3000 and later against 124 to 141. Its EventDispatch is lower (hero 30 vs 262).
- **paintArea (Timeline Paint clip areas, CSS px squared) moves in no arm beyond the base spread** in any zone (base hero 33.1, finish 3.1,
  rest 44.7 Mpx squared).
- **The base is steady between visits:** hero Layout 192-196 over the three visits, rest Layout 368-385, layers within 4 between base visits at
  every stop (110-112 at y 0, 112-116 at y 1500, 136 at y 3000, 141-142 at y 4500, 124 at the end), hero
  frames over 34 ms 0 to 1.8 per 100. Its largest wobble is finish FunctionCall (183 to 371) and EventDispatch (112 to 300), a one-step spike that
  appears in one or two passes of every base visit; it is the widest base spread and so the hardest cell to beat.

## Per arm verdicts (Lean `Fw.Device.PhoneArms`, golden `packages/contracts/golden/device/phone-arms.jsonl`)

Label per zone as counts / frames; "all" pools the zones of one family. A cell beats the base only if the arm's highest value plus the base
spread stays below the base's lowest (worse the other way round). Counts cover Layout, RecalculateStyles, Paint, Composite, FireAnimationFrame,
FunctionCall, EventDispatch and paintArea.

| arm | visits | hero | finish | rest | counts all | frames all |
|---|---|---|---|---|---|---|
| original | 1 | mixed / worse | mixed / worse | mixed / worse | mixed | worse |
| hero.exit:threaded | 1 | mixed / same | better / same | mixed / same | mixed | same |
| hero:scene-pause | 1 | worse / same | mixed / same | mixed / same | mixed | same |
| morph.columns:idle-none | 1 | same / same | same / same | same / same | same | same |
| morph.countdown:hidden-pause | 1 | same / same | worse / worse | mixed / same | mixed | worse |
| morph.countdown:strip | 0 (lost) | unresolved | unresolved | unresolved | unresolved | unresolved |
| nav.hitTest:hit-skip | 1 | same / same | same / same | same / same | same | same |
| engine.events:quiet | 1 | better / same | same / same | better / same | better | same |
| morph.panel:const-bounds | 1 | same / same | same / same | mixed / same | mixed | same |
| nav:clip-box | 1 | same / same | same / same | same / same | same | same |
| nav:bar-fixed | 1 | same / same | same / same | same / same | same | same |
| nav:logo-3d | 1 | mixed / same | mixed / same | mixed / worse | mixed | worse |
| morph.mount:shift-dormant | 1 | same / same | same / same | same / same | same | same |

Each cell with its base median and range is in `results/phone/2026-10-25-end-counts/tables.md` (one table per zone with counts, paintArea in Mpx
squared and frame intervals per 100 moving frames, then the layer and backing-store tables per scroll stop). The census verdict uses the same Lean cell
rule over the census values of all passes. Backing-store bytes come in tile steps of about 7 MB, so a one-step cell is noise-level (nav:bar-fixed
at y 3000 reads "beats" with 103.9 vs 111.0 MB, base spread 0 there; hit-skip and logo-3d show the same 103.9 and read "same").

## Method (CONFIRMED from the code)

- `node src/device-cli.mjs arms-run` (packages/measure-webkit): one `withPhone` session per visit, frames lane (800 px/s, 5 reps + 1
  warm-up) then counts lane (Timeline on, 50 px steps, pinned clock, 3 passes + 1 warm-up, layer census at y 0, 1500, 3000, 4500 and the end).
  The Timeline adds its own cost equally to every arm.
- Lean plan: 14 arms, none dropped (all prerender hashes distinct, flag sets distinct; the strip arm loads `hero.countdown:strip,morph.countdown:strip`
  because the part requires the hero flag). 16 visits: base, original and the first flag half, base, the second half reversed, base; blocks of at
  most 15 min with 5 min cool (Lean `mayStart`, `coolOk`). Visits took 234 to 368 s. The session ran under the first plan (`visitMin` 5, three
  visits per block, held within 15 min by the runtime `mayStart` guard); Lean now has `visitMin` 7 (above the longest visit), two per block.
- Zones from Lean `Session.zoneOf`: hero = first two viewports, finish = last viewport, rest = otherwise; viewport 775, maxY 5267. Counts are
  summed over 500 px bins per zone. A label per zone and family (counts, frames) is never pooled across families.
- Heat: battery temperature stayed 33 C on all 15 visits (the only heat proxy this round; thermal state comes with phone-thermal-check); the
  phone charged from 64 to 80 percent over the first visits and then held 80 (charge limit).
- Raw passes stay in `.local/phone/2026-10-25/` (gitignored); the reduction (`arms-reduce`) wrote `summary.json` and `tables.md`.

## What went wrong, and the rule that follows (Lean `PhoneArms.mayAttempt`, `tabPlan`)

- Visit 6 (morph.countdown:strip) took three tries, in this order (lead-resume.log). Try 1: proxy closed (code 1006) together with a USB
  re-enumeration on the Mac; after the user restarted usbmuxd the run resumed (usbReset). Try 2: the stalled run could not return our tab to
  about:blank (the cleanup also needs the USB link), so the next start found no blank tab: found 0 of 1 tabs (staleTab). The lead reset the tab by
  hand. Try 3: Runtime.evaluate timed out after 15 s on frames rep 2 with no USB cycle (other). No WebContent crash or jetsam log on the phone. The
  mid-scroll stall after a clean reset points at the arm, not the harness. Lean `mayAttempt [usbReset, staleTab, other]` is false (theorem
  `strip_visit_lost`): the visit is lost, `retryable` false; visits 7 to 15 then ran with `arms-run --all`.
- Fix 1 (`packages/measure-webkit/src/device.mjs`): Lean `tabPlan` drives the one blank tab; with none it returns the one tab on our own
  host, at any port, to about:blank first (theorems: drive, reset, refuse on two blanks, refuse otherwise, reset only without a blank tab, and
  `ownTab_any_port`). Every visit serves on a new port, so a tab left by the previous visit sits on the old port; round 2 matched the new port
  only and never fired. The reset runs before the blank-tab check; it touches only a tab whose URL is the host, or the host followed by `:` or `/`.
- Fix 2 (`device-phone-run.mjs`): Lean `Fault` names each failed attempt (`usbReset`, `staleTab`, `other`); `mayAttempt` gives two attempts and
  a third only when every failed attempt was a harness fault (four theorems, one per branch). A visit lost to an arm-side fault (`other`) is
  not retried. Older state entries without names count as `other`.
- Fix 3 (round 3): faults are append-only. Lean `recordFault`, `handReset` (leaves the faults as they are, so no new attempts) and `appendOnly`
  with theorems `handReset_mayAttempt`, `handReset_append_only`, `handReset_fourth`; `saveState` refuses a write that drops earlier faults and
  `markHandReset` notes a reset without touching them. The lead's hand reset in try 2 therefore cannot give strip a fresh start.
- The lost arm leaves the strip verdict open here; its Simulator result (a trade: finish layers 128 to 56) stands unchecked on the phone. Strip is
  re-measured as a new visit in phone-thermal-check.

## Phone against the CI Simulator verdicts

Scenarios differ: the Simulator lanes read other zones (hero-exit scroll, census layers, memory), the phone reads end-of-page scripted-scroll
counts. A match in direction is weak evidence; a difference is a different quantity, not a contradiction.

| flag | CI Simulator verdict (run ids) | phone verdict (this note) | reading |
|---|---|---|---|
| engine.events:quiet | win: EventDispatch -53%, FunctionCall -36% (40134234199 vs 40134016822) | counts better: hero EventDispatch -56%, FunctionCall -35%; rest -46%, -29%; frames same | agrees (MEASURED both) |
| hero.exit:threaded | trade: rAF 6.88 to 5.88 per step, Layout 7.80 to 6.51 (flag 39731192687, base 39739724461) | Layout and rAF lower in all 3 zones (hero -15%), Paint and EventDispatch higher, frames same | agrees in direction on Layout and rAF |
| morph.columns:idle-none | win: backing 106 to 90 MB (Simulator census 39897807511 vs base 39897814980) | layers 124 vs 136, backing 93.9 vs 111.0 MB at y 3000 (beats), 87.0 vs 104.2 at the end; counts, frames same | agrees (MEASURED both) |
| hero:scene-pause | win: layers 58 vs 136 at y3000, 65 vs 145 at y4500 (39548856639 vs 39309416016) | layers 51 vs 136 and 56 vs 141 (beats); counts mixed (FunctionCall, EventDispatch up), frames same | layers agree; the phone adds a count cost |
| morph.countdown:hidden-pause | win: no element drop (39312082945) | counts mixed, frames worse (finish Layout 86 vs 52, finish over50 1.85 vs 0) | phone disagrees; one visit |
| morph.countdown:strip | trade: finish layers 128 to 56 (39775198022 vs 39775174615; 39776554155 vs 39776549128; webkit-sim 40081936555) | lost (named; three tries, retryable false) | open until a new visit in phone-thermal-check |
| nav.hitTest:hit-skip | no Simulator run (Chromium prediction) | same, same | not exercised by scripted scroll (INFERRED) |
| morph.panel:const-bounds | unknown: open-push Composite 100-148 vs 176-181 ms (39760667274 vs 39744614747) | counts mixed (rest Paint 711 vs 899 beats, rest FunctionCall 931 vs 831 worse), frames same | different quantity |
| nav:clip-box | unknown (39872562267) | same, same | no phone effect |
| nav:bar-fixed | unknown (39872566438) | same, same (one tile step at y 3000) | no phone effect |
| nav:logo-3d | unknown, moved no count (39872570182) | counts mixed, frames worse (rest over50 4.89 vs 0.46) | phone cost; one visit |
| morph.mount:shift-dormant | -3 layouts (39325721909), Simulator unknown | same, same | no phone effect |

## Limits and open items

- One phone, one session; scripted scrolling does not move the Safari toolbar, so toolbar-throttle and touch-path flags (engine.scroll:unthrottle,
  morph.mount:arm-late, morph.mount:band, morph.end.*) are out of scope. Each arm except the base has one visit; the verdict is against the
  3-visit base spread only, so arm-side visit-to-visit drift is untested.
- Repeat the four arms that trade on the phone (hidden-pause, logo-3d, scene-pause, const-bounds) before any flag decision.
- ci/phone-end-counts push (ab773fe95): all 20 workflows concluded skipped (e.g. lean-math 40173828875, webkit-sim 40173828789); no CI measurement.
  
