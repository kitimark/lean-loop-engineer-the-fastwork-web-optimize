# hero:scene-pause: the kCopy bound, open@1 against the original, membership (task scene-pause-kcopy)

## Answer

- After the splash a paused hero box is off-screen within kCopy (170 px at 932x430): PROVED,
  `Fw.Parts.HeroScenePause.hero_paused_hidden_copy` and `hero_paused_same_after_splash`. Not covered:
  `hero.exit:threaded`, which runs card animations after the splash (`threaded_card_after_splash`).
- open@1 is judged against the original's first frame (`Fw.Gate.Trajectory.byMFirst`, since commit 046ff5f5a). The three
  recorded flag runs replay clean under it (`Open.recorded_clean`). The new run 40139690556 is Chromium UNDECIDED only
  through leave-one-out and playwright-webkit CLEAN. No unit is new.
- y 5267 census: still n=1 (39548856639). A push cannot set `fw`, so runs 2 and 3 are dispatches for the lead.
- Gen.run: hero:scene-pause is linked now (`Gen.linkTable`). It is not a member: ledger status partly-proved, and the
  WebKit morph cell is pending (macOS WebKit).

| cell | state | run |
|---|---|---|
| chromium hero | pass | 40139690556 |
| chromium morph | pass | 40139690556 |
| webkit hero | pass | 40139690556 (Linux playwright-webkit) |
| webkit morph | pending | needs probe-apple (dispatch) |

## kCopy (PROVED)

- Premise, read from the CSS (CONFIRMED, `apps/site/src/parts`): the splash end turns off the hero copy
  (`hero/hero.module.css:38-41`, `[data-splash='done'] .copy`), the cards (`hero.orbit/card.module.css:160-168`,
  `[data-orbit][data-done] .card`) and the cue copyFromRing above 600 px (`hero.cue/cue.module.css:84-94`). The cue
  copyIn at 600 px or less has no splash-end rule.
- Lean table `heroAnims`: 20 keyframes rules, each with its selectors and splash-end rule. The site test
  (`apps/site/src/parts/hero/scene.golden.test.ts`) replays each row from the CSS, and checks that the table names every
  `@keyframes` of the hero subtree and nothing else. So a new animation fails the test until the table lists it.
- `after_splash_copy`: outside `hero.exit/threaded.module.css`, every animation still running after the splash belongs to
  the copy column. `card_stops`: every card animation stops at the splash end.
- `hero_paused_hidden_copy`: when the stale shift is at most kCopy = vh - copyOutset and the copy column is inside the
  stage, a paused box is hidden. `kMax_le_kCopy`: on every matrix probe, kCopy is at least kMax.
- At 60 Hz, one frame of lag stays inside kCopy up to 10200 px/s of scroll (`copySpeed`, INFERRED: the one-frame lag
  is INFERRED).

## Why the attribute lags (engine source, CONFIRMED)

- WebKit `Page::updateRendering` (`page/Page.cpp:2231@862f17d`) runs animations (2307) and rAF callbacks (2329), then
  intersection observations (2366-2367, `Document::updateIntersectionObservers`, `dom/Document.cpp:10464-10492`). It
  notifies the observers in the same update (`page/IntersectionObserver.cpp:860`). The stale shift comes from UI-process
  scrolling running ahead of the web-process commit (INFERRED).
- Chromium `LocalFrameView::RunPostLifecycleSteps` (`frame/local_frame_view.cc:1073-1078@f842f52`) runs the observer
  steps after paint. It delivers them in a posted task (`intersection_observer_controller.cc:90-105`), so the attribute
  applies one frame later at the earliest.
- A paused animation does not tick: WebKit `WebAnimation::needsTick` (`animation/WebAnimation.cpp:1553-1556`), Chromium
  `Animation::TimeToEffectChange` (`core/animation/animation.cc:3376-3380`).

## open@1 against the original (MEASURED, PROVED replay)

- Recorded runs 39548822269, 39553952680, 39556935431: open@1 in 0/5 original, 2, 1 or 0/5 faithful, 0/5 candidate.
  Under `firstCover` the candidate's missing sample is late (`firstCover 5 0 5 = late`), a skip and never new
  (`Open.recorded_open_late`, `Fw.Gate.Trajectory.rel_first_skip_not_new`). A missing sample is red only when the
  original has one in at least 4 of 5 reps (`Open.red_needs_original`).
- Run 40139690556 (sha 4e24712, all four widths, `fw=hero:scene-pause`, inputs from artifact trajectory-inputs):
  Chromium 14416 units, 0 fail, 43 undecided. Of these, 42 are open@1 at 640 morph, skip firstLate in the candidate and
  in the faithful arm. Their leave-one-out family has 2 late and 4 undecided verdicts, which is what one original hit in
  5 reps gives (`Open.run_640_family`; that the original had 1 hit is INFERRED from that family). The 43rd unit is the
  nav background-color close@0 at 1280: pass in all reps, fail:apart in 2 of 5 leave-one-out sets. The same unit
  failed once in 39548822269. playwright-webkit: 4000 units, CLEAN.

## Membership

- `Fw.Preset.Gen.run` (written, then `--check` up to date): one member, engine.scroll:unthrottle. For hero:scene-pause
  the verdict is `not-proved` (ledger status partly-proved), with trajectory `pending`. The preset was not edited by hand.
- To become a member it needs the census at n=3 and a passing macOS WebKit morph cell, and then the status `proved` in
  the ledger.

## Open

- Census runs 2 and 3, and the macOS trajectory: dispatches (see the task report).
- Safari frame time: a follow-up, since no lane exists.
