# phone-end-counts: counts and frame intervals per zone on the real iPhone

## Answer

- **6 of 16 planned visits ran, so the result is partial (MEASURED, one phone, one session).** The phone dropped off USB during visit 6
  (morph.countdown:strip): "connection closed by the proxy (code 1006)", then "paired but not on USB" for 4 more minutes. The rules allow
  one retry; the retry could not start. Eight arms have no phone data (strip, shift-dormant, logo-3d, bar-fixed, clip-box, const-bounds,
  engine.events:quiet, hit-skip) and the base was visited once, not three times (the middle and end visits did not run).
- **Every verdict below is provisional.** The "base spread" is the spread of 3 counts passes and 5 frame reps inside one base visit, not
  across visits. The rule (Lean `Fw.Device.PhoneArms`, golden `packages/contracts/golden/device/phone-arms.jsonl`) is applied as written;
  the A/B/A repeat that would show visit-to-visit drift is the missing part.
- **The original page is slow on the phone over the whole page (MEASURED):** 100 of 100 moving frames in the hero zone take over 34 ms
  and over 50 ms, against 0 for the rewrite; in the rest zone 79 per 100 against 0.5. Its EventDispatch is lower (30 vs 262 hero).
- **hero.exit:threaded lowers Layout and FireAnimationFrame in every zone** (hero Layout 165 vs 195, rAF 163 vs 192; finish Layout 33 vs 52;
  rest Layout 321 vs 375), with frames the same, and raises Paint (hero 665 vs 539) and EventDispatch (338 vs 262). Counts label: mixed.
- **morph.columns:idle-none changes no count and no frame cell (same, same).** Its CI win is memory, which this lane does not read.
- **hero:scene-pause and morph.countdown:hidden-pause look worse on the phone** (hero over34 1.8 per 100 vs 0; FunctionCall and EventDispatch
  up; finish Layout 80 and 86 vs 52). Single visit each; confirm with the base repeats before using it (INFERRED: the base repeats would show
  whether visit-to-visit drift explains it; idle-none matching the base within 2 on every cell argues against a session-wide drift).

## Method (CONFIRMED from the code)

- `node src/device-cli.mjs arms-run` (packages/measure-webkit): one `withPhone` session per visit, frames lane (800 px/s, 5 reps + 1
  warm-up) then counts lane (Timeline on, 50 px steps, pinned clock, 3 passes + 1 warm-up). The Timeline adds its own cost equally to every arm.
- Lean plan: 14 arms, none dropped (all prerender hashes distinct, flag sets distinct; the strip arm loads `hero.countdown:strip,morph.countdown:strip`
  because the part requires the hero flag). 16 visits: base, original and the first flag half, base, the second half reversed, base; blocks of at
  most 15 min with 5 min cool (Lean `mayStart`, `coolOk`). Run: base 237 s, original 312 s, threaded 368 s, scene-pause 266 s, idle-none 237 s,
  hidden-pause 265 s.
- Zones from Lean `Session.zoneOf`: hero = first two viewports, finish = last viewport, rest = otherwise; viewport 775, maxY 5267. Counts are
  summed over 500 px bins per zone. Verdict per cell: beats if arm high + base spread < base low, worse if the reverse, else same; a label per
  zone and family (counts, frames) is never pooled across families.
- Battery temperature stayed 33 C on every visit (the only heat proxy); the phone was charging. No visit was lost before visit 6.
- Summaries: `results/phone/2026-10-25-end-counts/summary.json` and `tables.md` (raw passes in `.local/phone/2026-10-25/`, gitignored).

## Per zone, arm median (base median), verdict (MEASURED, 1 visit per arm)

| arm | zone | Layout | RecalcStyles | Paint | Composite | rAF | FunctionCall | EventDispatch | over34 /100 | over50 /100 |
|---|---|---|---|---|---|---|---|---|---|---|
| base | hero | 195 | 175 | 539 | 59 | 192 | 424 | 262 | 0.00 | 0.00 |
| original | hero | 213 W | 197 W | 457 B | 59 = | 194 W | 301 B | 30 B | 100.0 W | 100.0 W |
| hero.exit:threaded | hero | 165 B | 159 B | 665 W | 59 = | 163 B | 460 W | 338 W | 0.90 = | 0.00 = |
| hero:scene-pause | hero | 195 = | 187 W | 483 = | 59 = | 192 = | 712 W | 562 W | 1.81 W | 0.00 = |
| morph.columns:idle-none | hero | 191 = | 175 = | 506 = | 59 = | 192 = | 422 = | 260 = | 0.00 = | 0.00 = |
| morph.countdown:hidden-pause | hero | 195 = | 177 = | 487 = | 59 = | 192 = | 481 W | 325 W | 1.83 W | 0.00 = |
| base | finish | 52 | 76 | 163 | 34 | 89 | 201 | 130 | 0.00 | 0.00 |
| original | finish | 72 W | 86 W | 185 = | 34 = | 85 B | 125 = | 17 B | 1.78 = | 1.78 W |
| hero.exit:threaded | finish | 33 B | 76 = | 158 = | 34 = | 72 B | 172 = | 118 = | 1.72 = | 0.00 = |
| hero:scene-pause | finish | 80 W | 90 W | 214 = | 34 = | 84 B | 228 = | 160 = | 0.00 = | 0.00 = |
| morph.columns:idle-none | finish | 53 = | 77 = | 170 = | 34 = | 89 = | 285 = | 214 = | 0.00 = | 0.00 = |
| morph.countdown:hidden-pause | finish | 86 W | 89 W | 207 = | 34 = | 85 = | 246 = | 178 = | 5.55 = | 1.85 W |
| base | rest | 375 | 395 | 899 | 120 | 400 | 831 | 532 | 0.46 | 0.46 |
| original | rest | 358 = | 415 W | 705 B | 120 = | 444 W | 601 B | 60 B | 79.5 W | 79.5 W |
| hero.exit:threaded | rest | 321 B | 396 = | 981 W | 120 = | 340 B | 861 = | 625 W | 0.46 = | 0.46 = |
| hero:scene-pause | rest | 350 B | 407 W | 595 B | 120 = | 418 = | 1003 W | 700 W | 1.43 W | 0.47 = |
| morph.columns:idle-none | rest | 381 = | 395 = | 876 = | 120 = | 400 = | 831 = | 532 = | 0.45 = | 0.45 = |
| morph.countdown:hidden-pause | rest | 356 B | 408 W | 637 B | 120 = | 400 = | 1006 W | 720 W | 3.06 W | 1.02 = |

B = beats the base beyond the base spread, W = worse, = same. Per-arm labels (counts, frames): original mixed, worse; hero.exit:threaded mixed, same;
hero:scene-pause mixed, worse; morph.columns:idle-none same, same; morph.countdown:hidden-pause mixed, worse; the eight other arms unresolved (no visit).

## Phone against the CI Simulator verdicts

Scenarios differ: the Simulator lanes read other zones (hero-exit scroll, census layers, memory), the phone reads end-of-page scripted-scroll counts.
A match in direction is therefore weak evidence; a difference is a different quantity, not a contradiction.

| flag | CI Simulator verdict (run ids) | phone (this note) | reading |
|---|---|---|---|
| hero.exit:threaded | trade: rAF 6.88 to 5.88 per step, Layout 7.80 to 6.51 (flag 39731192687, base 39739724461) | Layout and rAF lower in all 3 zones (-15% hero), Paint and EventDispatch higher | same direction on Layout and rAF (MEASURED both) |
| hero:scene-pause | win: layers 58 vs 136 at y3000, 65 vs 145 at y4500 (39548856639 vs 39309416016) | counts mixed, frames worse; layers not read by this lane | not comparable; the phone shows no count win |
| morph.columns:idle-none | win: backing 106 to 90 MB (Simulator census 39897807511 vs base 39897814980) | same on every cell | consistent: memory win, no count change |
| morph.countdown:hidden-pause | win: no element drop (39312082945) | counts mixed, frames worse | phone disagrees in sign on the finish zone; one visit |
| morph.countdown:strip | trade: finish layers 128 to 56 (39775198022 vs 39775174615; 39776554155 vs 39776549128; webkit-sim 40081936555) | not run | open |
| nav.hitTest:hit-skip | no Simulator run (Chromium prediction) | not run | open |
| engine.events:quiet | win: EventDispatch -53%, FunctionCall -36% (40134234199 vs 40134016822) | not run | open; the phone has the EventDispatch cell to test it |
| morph.panel:const-bounds | unknown: open-push Composite 100-148 vs 176-181 ms (39760667274 vs 39744614747) | not run | open |
| nav:clip-box, nav:bar-fixed, nav:logo-3d | unknown (39872562267, 39872566438, 39872570182; logo-3d moved no count) | not run | open |
| morph.mount:shift-dormant | -3 layouts (39325721909), Simulator unknown | not run | open |

## Limits and open items

- One phone, one session; the phone locked or left USB at visit 6 (named failure: connection closed by the proxy, code 1006, then paired but not on
  USB). Resume: `node src/device-cli.mjs arms-run --all --site ../../apps/site/dist/aot --dir ../../.local/phone/2026-10-25 --blocked ../../scratchpad/pec/blocked.txt`
  (state in `.local/phone/2026-10-25/state.json`; visit 6 has one failed attempt, one retry remains).
- The three base visits needed for the A/B/A spread did not all run (INFERRED consequence: verdicts of arms that differ by a small amount are not
  trustworthy; hero:scene-pause and hidden-pause increases are the first to re-check).
- ci/phone-end-counts push (ab773fe95): all 20 workflows concluded skipped (e.g. lean-math 40173828875, webkit-sim 40173828789); no CI measurement.
