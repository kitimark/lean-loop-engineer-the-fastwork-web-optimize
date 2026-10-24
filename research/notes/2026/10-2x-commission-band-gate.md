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
| `commission_visSame` | visible scenes equal (E) after every body (bodies only; the merged rows below add media events) |
| `tick_fol_cls`, `m_fol_cls` | a tick is an optional media event, then an optional body; follower and class bits agree after every tick |
| `tick_inl_body`, `tick_inl_media_off`, `tick_inl_keep` | per tick: a body that does not skip, or a media event with the gate off, leaves the original's pair; any other tick without a body changes neither pair |
| `inl_agree_p1` | `Reads` and `MediaOnFlip`: whenever the painted gate is off, the pairs agree |
| `inl_agree_p2` | `BodyAfterSkip`: after every tick that does not skip, the pairs agree (no media event needed) |
| `skip_gated` | `Reads`: a tick that skips paints with the gate on |
| `look_agree_p1`, `look_agree_p2`, `look_agree_merged` | the look agrees after every tick under `MediaOnFlip` or under `BodyAfterSkip` |
| `commission_visSame_merged` | visible scenes equal (E) over the merged trajectory, per environment trajectory under either premise |
| `writes_orig`, `writes_le` | original: 2 writes per event; variant never more |
| `moving_run`, `moving_run_lt` | gated and moving every event: 0 writes, strictly fewer than the original |
| `stepV_writes`, `stepC_writes` | the TS decisions `planWrite`, `planCatchup` are the model's events |

Limit: the theorems cover the look (scale, radius). While the follower moves in the band, the custom properties' own computed values differ from the original's (getComputedStyle would show it); they are equal again at rest and on band exit, which is what the breakpoint gate compares.

Goldens (`commission-gate.jsonl`, 75 lines): `planWrite`, `planCatchup`, `catchupPair`, `cardLook` per environment,
`trace` lines that `bandgate.test.ts` replays through the real driver (writes and section pair per event, both arms),
and 5 `mergedTrace` lines that it replays as ticks (media handler, then body) with the card look per tick. The last
`mergedTrace` line breaks both premises (the gate turns off after a skip with no event and no body) and its looks
differ; the Lean `#guard` on `exRun` shows the same.

The merged model takes three premises per tick k, painted with environment k:

- `Reads`: the media event and the body read the gate the tick paints with.
- `MediaOnFlip` (P1): a tick whose gate differs from the previous tick's has a media event.
- `BodyAfterSkip`: a tick after a skipping body has a body.

## Premise P1 (source)

P1 says the media-query change event fires in the same rendering update as the rAF body, before both the body and
paint.

- HTML, CONFIRMED (whatwg/html `source` @b342939): "update the rendering" evaluates media queries and reports changes
  (123812-123813), then runs the animation frame callbacks (123860), then updates the rendering of each document
  (123972-123973). CSSOM View (w3c/csswg-drafts `cssom-view-1/Overview.bs` @a1dd397, 870-886) fires `change` in that
  step when the matches state changed since the last run, and the matches state is the live result (865-866).
- WebKit, CONFIRMED (@862f17d): `Page::updateRendering` runs `MediaQueryEvaluation` (`page/Page.cpp:2298-2300`) before
  `AnimationFrameCallbacks` (2329-2331) and before the layer flush in `doAfterUpdateRendering` (2400, 2551). The step
  calls `evaluateAll(DispatchNow)` (`dom/Document.cpp:5861-5867`), which starts a new evaluation round
  (`css/MediaQueryMatcher.cpp:99`) and dispatches `change` synchronously (`css/MediaQueryList.cpp:93-109`). `matches()`
  returns the value of the last round (`css/MediaQueryList.cpp:124-142`, outside iframes), so the body reads the gate
  of the same step. P1 and `Reads` hold, given that no viewport change lands inside one rendering update (INFERRED).
- Chromium, P1 does not hold (CONFIRMED, @f842f52, `third_party/blink/renderer/core/`). A viewport resize calls
  `MediaQueryAffectingValueChanged` (`dom/document.cc:5729-5733`). The style engine marks every sheet with a size
  media query dirty first (`css/style_engine.cc:525-532`, 440-445, 823-826, 4767-4769; our `commission.module.css:436`
  is one), so `NeedsLayoutTreeUpdate()` holds (`dom/document.cc:2488-2489`) and the evaluation waits for the next
  style recalc (`dom/document.cc:1203-1209`, run at 2827 via 5717-5722). That recalc follows the rAF callbacks, so
  `MediaFeaturesChanged` queues the event (`css/media_query_matcher.cc:146-153`, `dom/document.cc:6622-6624`) for
  the next frame's step 10 (`page/page_animator.cc:276-288`), after this frame's paint. A `matches` read in between
  flips the stored value (`css/media_query_list.cc:101-122`), and then `MediaFeaturesChanged` returns false
  (89-94): no event fires at all.
- Chromium still keeps the look, through `BodyAfterSkip` (`look_agree_p2`). `matches` re-evaluates live
  (`css/media_query_list.cc:110-122`), so a body reads the gate it paints with. A skipping body has `f.more`, and the
  driver then requests its own rAF (`driver.ts:125`, 92; `clock.ts:31`), so the next frame runs a body before paint.
  That the clock runs the requested rAF in the next painted frame is INFERRED (no source read for throttled frames).

In Chromium the variant's look rests on the body after a skip, not on the media event. A late media handler reads the live gate, so `Reads` still holds.

## Design history (finding)

| design | gate | cause |
|---|---|---|
| v1: skip every write in the band, catch-up body on a media change (9997b62) | FAIL, run 39836996121 | the gate compares computed custom properties at rest: original `"0"`, rewrite `"1"` (83 chromium probes); the media-change body ran a body the original does not run (runway height, title display, section height rows) |
| v2: skip only while the follower moves; write at settle; on a media change write the follower's pair without a body (2a74101) | pass, run 39843552595 | the pair at rest equals the original's (`inl_settled`); no extra body |

Lesson: a skip fails the gate when it leaves a computed value different from the original, even when nothing shows. The base gate (no flag, run 39840038549) passes.

## Measurements

CI only. Chromium: `fw run --target rewrite --engines chromium --profile swipe-v1 --runs 3`, viewport 430x932 dpr 3
touch (the c1000 band). Base run 39837044649 (9997b62, faithful path unchanged by v2), flag run 39843560957 (2a74101).
Window: the `swipe` frames with 3070 <= scrollY < 3530 (half-open; the profile steps 10 px, so 46 frames per run).
The window is the commission bottom from 0.85h to 0.35h; its position is INFERRED from the class-toggle spike (element
count spike at scrollY 3090 in both arms: `shrinking` on at bottom 0.83h). Every mean below is the sum of a count over
those frames of `counts.json` in the run's `chromium-counts-rewrite-r<n>` artifact, divided by 46.

| per frame, window | base r1 r2 r3 | flag r1 r2 r3 |
|---|---|---|
| RecalcStyleCount | 5.02 5.02 5.02 | 3.09 3.09 3.09 |
| UpdateLayoutTree elementCount | 127.3 127.3 127.3 | 60.9 60.9 60.9 |
| ScheduleStyleRecalculation | 5.02 5.02 5.02 | 3.09 3.09 3.09 |
| FunctionCall | 9.50 9.50 9.50 | 9.50 9.50 9.50 |
| Layout | 0.57 0.57 0.57 | 0.57 0.57 0.57 |
| Paint | 3.87 3.89 3.89 | 3.89 3.89 3.89 |
| census layers | 66.35 66.37 66.37 | 66.37 66.37 66.37 |
| census tiles | 121.09 121.09 121.09 | 121.09 121.09 121.09 |
| Commit | 1.00 1.00 1.00 | 1.00 1.00 1.00 |

Layer budget 0 (layers, tiles equal). In 250 px bins of scrollY starting at 0 (run r1 of each arm), RecalcStyleCount
and elementCount differ only in the bins from 2500 to 3750 and are equal within 1 in every other bin (the saving is where
the follower runs). The flag's FunctionCall is unchanged because the follower and the class toggles still run.

Bound convention: the flag figures 3.07 and 60.1 are the means of
the v1 flag run 39837049981 in the same half-open window (3.065, 60.11), not of the v2 run 39843560957 (3.087,
60.87). With the inclusive window 3070 <= scrollY <= 3530 (47 frames) the means are base 5.02 and 127.1, flag 3.09 and
60.6. The base and the other rows in the table match the half-open window.

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

Win on style recalculation in both engines (Chromium 5.02 to 3.09 recalcs and 127.3 to 60.9 elements per frame in the
scroll-in window; WebKit RecalculateStyles minus 20-28 %), layer budget 0. Same look by the gate and by proof: P1 in WebKit (CONFIRMED from source), `BodyAfterSkip` in Chromium, where P1 does not hold. Not
measured: frame times, the phone. Ledger row 48 is `partly-proved`; promotion to the v2-proved preset is the lead's call.
