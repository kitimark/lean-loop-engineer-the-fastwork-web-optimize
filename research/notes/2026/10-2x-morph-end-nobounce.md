# morph.end.nobounce:on: no bottom rubber band; Chromium reads no-gain in every window, the WebKit toolbar lane reads no-win (7 flag passes against 5 default passes), look class L

* Answer (MEASURED, CI only, no phone pass). `html { overscroll-behavior-y: none }` from first paint does not change what either engine counts at the end of the page in this harness. Chromium: every window noGain and no metric differs (3 runs per arm). WebKit Simulator toolbar lane: reversals, re-opens and fade onsets per gesture overlap the default passes, so the Lean verdict is no-win; the Layout and RecalculateStyles cost is not read because the lane has 2 default and 3 flag cost windows and the rule needs 3 per side.
* Look (class L, user's review): with no bounce the page cannot be pulled past the bottom, so the end feel changes. Not proved same-look; the ledger row `morph.end.nobounce` is `look-change`, `userDecision` pending, never a preset on this evidence.
* Lean (PROVED, `lean/Fw/Parts/MorphEndNobounce.lean`, golden `packages/contracts/golden/parts/morph-end-nobounce.jsonl`): `nb_target` (the write target equals the pin while the pin is at most the end), `push_at_end_no_write` (pin at the end, a forward push writes nothing), `pin_writes_below` (a write happens only when the page is below the pin and writes the pin), `no_write_above_end` (over a whole recording read without bounce no write asks for a position above the end), contrast `bounce_writes_back`. The flag changes no reducer code; it removes the positions above the end from what the reducer can read.

## What is delivered
One rule in `apps/site/src/styles/reset.css`: `html:has([data-fw-nobounce]) { overscroll-behavior-y: none }`, inside `@layer reset`. The flag `morph.end.nobounce:on` puts `data-fw-nobounce` on the page root in the server HTML; without the flag no element carries it. The first delivery as a prerendered style tag failed the build (the build bans them); the CSS file plus an attribute is the second.

## Runs (flag code at 3c5ac115f; base and flag on the same commit)
| lane | arm | run | n |
|---|---|---|---|
| breakpoint gate, both engines | morph.end.nobounce:on | 40283431992 success (Chromium j0-j2, WebKit j0-j3, merge) | all jobs |
| Chromium swipe-touch-v1 counts | default | 40283428442 | 3 runs |
| Chromium swipe-touch-v1 counts | morph.end.nobounce:on | 40283424333 | 3 runs |
| WebKit Simulator toolbar lane | default and nobounce, same jobs | 40283405286 | default 8 passes (5 usable), nobounce 7 passes (7 usable), jobs 1-8 |

Failed first-push runs (site build, no data): 40282634661, 40282669758, 40282673015, 40282681173.

## Chromium (MEASURED; Lean cmp/judge, slack 0; reader `packages/measure-chromium/src/offscreen-windows-cli.mjs`, Lean `Fw.Measure.OffscreenWindows`)
End frame 574 on all 6 runs, usable windows from the end frame.

| window | verdict | metrics that differ |
|---|---|---|
| approach | noGain | none |
| end 0-19 | noGain | none |
| end 20-59 | noGain | none |
| end 60-119 | noGain | none |
| end 120+ | noGain | none |
| finish | noGain | none |

Why noGain (mechanism): the compositor's elastic overscroll on the root scroller is off by default (`cc/trees/layer_tree_settings.h:114-115@f842f52`, `enable_elastic_overscroll_on_root = false`, CONFIRMED) and it is a platform setting, so the Linux Chromium of this lane has no rubber band for the rule to remove. The page never reads a position above the end in either arm, which is exactly the state the Lean theorems describe for the flag arm; the default arm already is in it. INFERRED for this harness (the setting was not read at run time); the identical counts are consistent with it.

## WebKit Simulator toolbar lane (MEASURED, run 40283405286, reducer `packages/measure-webkit/src/throttle/toolbar-report.mjs`, Lean `Fw.Measure.MorphEndCount.flagVerdict`)
Jobs 1-8 ran. Jobs sim (9) and sim (10) failed at once with `toolbar-plan has no entry for job 9 / 10` (the commit's plan lists 8 entries, the run started 10 jobs): no pass, not a Simulator loss. Job 1 lost its nobounce pass (Runtime.evaluate timed out after 120 s); default passes lost to touch-driver timeouts left 5 of 8 usable. A side below its minimum is undecided, never a win.

| arm | passes (usable) | gestures | reversals per gesture | closes per gesture | re-opens per gesture | fade onsets per gesture | pin writes per gesture | passes open at the end |
|---|---|---|---|---|---|---|---|---|
| default | 8 (5) | 60 | 1.33 | 0.33 | 0.25 | 0.33 | 1.15 | 0 |
| nobounce | 7 (7) | 84 | 1.11 | 0.33 | 0.25 | 0.33 | 0.98 | 0 |

| flag | usable | default beside them | reversals | re-opens | onsets | step cadence lifted | state-trace floor | Lean verdict |
|---|---|---|---|---|---|---|---|---|
| morph.end.nobounce:on | 7 | 5 (7 jobs) | overlap | overlap | overlap | no | holds | no-win |

Cost (idle rAF 36-37 Hz, fold 3x): cost windows default / flag 2 / 3, 3 needed per side, so Layout (2.225 against 1.819 per frame) and RecalcStyle (2.930 against 2.733) are shown for the record and not read. Reversals per gesture are lower (1.33 to 1.11) but the Lean rule asks every flag pass beyond every default pass, so the ranges overlap and the rate is not a win. Still runs and finish counts: every pass of both arms ends closed (passes open at the end 0).

Mechanism (CONFIRMED from source, WebKit@862f17d): the main frame's vertical overscroll behavior is copied onto the UIScrollView in the UI process, `WKWebViewIOS.mm:1084-1087` calls `updateScrollViewForOverscrollBehavior`, which sets `bouncesVertically = (behavior != None)` (`ScrollingTreeScrollingNodeDelegateIOS.mm:352-362`). So the rule turns off the iOS rubber band; scroll offsets above the end then do not occur, which is the premise of `no_write_above_end`. The lane's drag stays in the page (springboard target, 480 pt drag), so it rarely pushes against the end; the pin-write column drops 1.15 to 0.98 per gesture, inside the spread.

## Limits and follow-ups
* CI only, no phone pass; the felt end of page and Safari's toolbar reveal on a bottom push belong to the user's review (class L).
* The WebKit lane has 5 default and 7 flag usable passes in 7 jobs and no cost verdict; no new CI push was left to rerun it.
* Follow-up: the push-cycle replay (a forward push at the end, the case the Lean theorems are about) once `push-cycle-separate` has landed; the lane today has no flag arm there.
* Follow-up: the toolbar plan lists 8 entries for 10 started jobs; a plan of 10 or a job count of 8 would not waste two jobs.
