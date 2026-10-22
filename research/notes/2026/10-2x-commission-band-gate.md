# commission:band-gate (ledger row 48)

Status: CONFIRMED for the Lean statements and the CSS premise, MEASURED for the counts, INFERRED where marked.
Code: `lean/Fw/Parts/CommissionOpt.lean`, `apps/site/src/parts/commission/` (driver, logic, `bandgate.test.ts`), goldens
`packages/contracts/golden/parts/commission-gate.jsonl`. Not a GPU route: a style-only saving, no animated property changes.

## Question

In the c1000 band (`commission.module.css` 436-452) the section pins `--commission-shrink-scale: 1` and
`--commission-shrink-radius: 0px`, and the card sets `border-radius: 0` and `transform: none`. The driver still writes
`--commission-enter-shrink` and `--commission-shrink` on every body (two `setProperty` calls). Both properties inherit, so a
changed value restyles the section's descendants (INFERRED from the element counts below). Can the writes be skipped
without any visible change?

## Premises

- CONFIRMED (`bandgate.test.ts`, CSS premise tests): the two properties are read only at lines 9 (scale) and 48 (radius);
  the band rule at 438-446 removes both effects; no other file of the part reads them.
- CONFIRMED: commission is not the last section (platform follows), so the follower runs for a whole scroll-in.
- The faithful body (`driver.ts`, JS 3092-3123) writes both properties on every body, also when the value did not change.

## Lean (class E)

`Fw.Parts.CommissionOpt`; the gate is `c1000` from the generated media conditions.

| statement | meaning |
|---|---|
| `look_gated` | `c1000` holds: look = (scale 1, radius 0) for every pair |
| `look_const_iff` | the look is independent of the pair exactly in the band |
| `fol_cls_agree` | follower pair and class bits equal the original's after every event |
| `inl_written`, `inl_ungated`, `inl_settled` | an event that is not (gated and moving) leaves the original's pair on the section |
| `exit_catchup` | the first event with the gate off holds `(n, max n r)` of its frame |
| `media_catchup`, `media_look_agree` | a band change without a body writes the follower's pair; the look agrees |
| `commission_visSame` | visible scenes equal (E) for every environment trajectory, with P1 as hypothesis |
| `writes_orig`, `writes_le` | original: 2 writes per event; variant never more |
| `moving_run`, `moving_run_lt` | gated and moving every event: 0 writes, strictly fewer than the original |
| `stepV_writes`, `stepC_writes` | the TS decisions `planWrite`, `planCatchup` are the model's events |

Goldens (`commission-gate.jsonl`, 70 lines): `planWrite`, `planCatchup`, `catchupPair`, `cardLook` per environment, and
`trace` lines that `bandgate.test.ts` replays through the real driver (writes and section pair per event, both arms).

## Design history (finding)

| design | gate | cause |
|---|---|---|
| v1: skip every write in the band, catch-up body on a media change (9997b62) | FAIL, run 39836996121 | the gate compares computed custom properties at rest: original `"0"`, rewrite `"1"` (83 chromium probes); the media-change body ran a body the original does not run (runway height, title display, section height rows) |
| v2: skip only while the follower moves; write at settle; on a media change write the follower's pair without a body (2a74101) | pass, run 39843552595 | the pair at rest equals the original's (`inl_settled`); no extra body |

Lesson: a skip fails the gate when it leaves a computed value different from the original, even when nothing shows. The base gate (no flag, run 39840038549) passes.

## Measurements

CI only. Chromium: `fw run --target rewrite --engines chromium --profile swipe-v1 --runs 3`, viewport 430x932 dpr 3
touch (the c1000 band). Base run 39837044649 (9997b62, faithful path unchanged by v2), flag run 39843560957 (2a74101).
Window: scrollY 3070-3530, 46 frames per run. The window is the commission bottom from 0.85h to 0.35h; its position is
INFERRED from the class-toggle spike (element count spike at scrollY 3090 in both arms: `shrinking` on at bottom 0.83h).

| per frame, window | base r1 r2 r3 | flag r1 r2 r3 |
|---|---|---|
| RecalcStyleCount | 5.02 5.02 5.02 | 3.07 3.07 3.07 |
| UpdateLayoutTree elementCount | 127.3 127.3 127.3 | 60.1 60.1 60.1 |
| ScheduleStyleRecalculation | 5.02 5.02 5.02 | 3.07 3.07 3.07 |
| FunctionCall | 9.50 9.50 9.50 | 9.50 9.50 9.50 |
| Layout | 0.57 0.57 0.57 | 0.57 0.57 0.57 |
| Paint | 3.87 3.89 3.89 | 3.89 3.89 3.89 |
| census layers | 66.35 66.37 66.37 | 66.37 66.37 66.37 |
| census tiles | 121.09 121.09 121.09 | 121.09 121.09 121.09 |
| Commit | 1.00 1.00 1.00 | 1.00 1.00 1.00 |

Layer budget 0 (layers, tiles equal). Outside scrollY 2650-3580 the 250 px bins of RecalcStyleCount and elementCount are
equal within 1 (the saving is exactly where the follower runs). The flag's FunctionCall is unchanged because the follower
and the class toggles still run.

WebKit: `fw run --target rewrite --engines webkit`, iOS Simulator 430x775, 50 px steps, 2 passes per run. Base run
39837001915 (9997b62), flag run 39843567401 (2a74101). The v1 flag run 39837008165 failed with no artifact.

| window (sum of 2 passes: pass 1 / pass 2) | base | flag |
|---|---|---|
| y 2500-3500 RecalculateStyles | 124 / 127 | 99 / 92 |
| y 2500-3500 Layout | 108 / 101 | 114 / 88 |
| y 2500-3500 Paint | 137 / 139 | 142 / 133 |
| y 2500-3500 Composite | 40 / 40 | 40 / 40 |
| y 2500-3500 FunctionCall | 282 / 299 | 379 / 294 |
| y 3500-4500 RecalculateStyles | 152 / 154 | 106 / 101 |

The y 2500-3500 window is the Chromium window scaled to this page and INFERRED. RecalculateStyles falls by 20-28 %; the
base's own gap between passes in that window is 3. Layout, Paint and FunctionCall overlap or are noisy (FunctionCall
pass 1 of the flag arm is high, pass 2 equals the base). The y 3500-4500 saving is not explained by the model
(INFERRED: the exit follower still moving, unverified). Frame times are not recorded by either count lane.

Gate: breakpoint-gate `--fw commission:band-gate` both engines, run 39843552595 success; lean run 39843527891 success.

## Verdict

Win on style recalculation in both engines (Chromium 5.02 to 3.07 recalcs and 127 to 60 elements per frame in the
scroll-in window; WebKit RecalculateStyles minus 20-28 %), same look by proof and by the gate, layer budget 0. Not
measured: frame times, the phone. Ledger row 48 is `partly-proved`; promotion to the v2-proved preset is the lead's call.
