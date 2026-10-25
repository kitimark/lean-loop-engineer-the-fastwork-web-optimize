# hero:scene-pause: the kCopy bound, open@1 against the original, membership (task scene-pause-kcopy)

## Answer

- After the splash a paused hero box is off-screen within kCopy (170 px at 932x430): PROVED,
  `Fw.Parts.HeroScenePause.hero_paused_hidden_copy` and `hero_paused_same_after_splash`. Not covered:
  `hero.exit:threaded`, which runs card animations after the splash (`threaded_card_after_splash`).
- open@1 is judged against the original's first frame (`Fw.Gate.Trajectory.byMFirst`, since commit 046ff5f5a). The three
  recorded flag runs replay clean under it (`Open.recorded_clean`). The new run 40139690556 is Chromium UNDECIDED only
  through leave-one-out and playwright-webkit CLEAN. No unit is new.
- y 5267 census (MEASURED, flag run 40151792642 n=3 VMs, base run 40151813906 n=2 VMs): at the page end the flag arm has
  39 to 47 layers and 5 will-change layers in every pass, the plain rewrite 124 to 128 and 90. The drop of 85 will-change
  layers equals the Lean prediction (`hero_paused_drop`). The census holds.
- Gen.run: hero:scene-pause is not a member. The ledger status is still partly-proved, and the macOS WebKit morph cell
  fails (run 40143377510, `falsified: trajectory`). The failing unit, nav background-color, also fails at 2 widths in
  the macOS A/A run 39472217441. So the fail is not attributed to the flag (INFERRED).

| cell | state | run |
|---|---|---|
| chromium hero | pass | 40139690556 |
| chromium morph | pass | 40139690556 |
| webkit hero | pass | 40139690556 (Linux playwright-webkit), 40143377510 (macOS and Linux) |
| webkit morph | fail | 40143377510 (macOS WebKit; nav background-color content new at 390 and 641) |

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

## y 5267 census (MEASURED)

webkit-sim, sha 4d752f0, iOS Simulator 430x775 DPR 3, 2 fresh-load passes per VM. Flag arm: run 40151792642,
`?fw=hero:scene-pause`, configHash a4cb3c200e1a2b2a, VMs r1 to r3 (n=3). Base arm: run 40151813906, no search (the plain
rewrite), configHash d2aa6b60965189a0, VMs r2 and r3 (n=2; r1 was cancelled, the run ended cancelled). Artifacts
webkit-sim-r*, field `passes[].census`.

| VM | arm | max y | layers at max y (pass 1 / 2) | will-change at max y | layers at 3000 | layers at 4500 |
|---|---|---|---|---|---|---|
| r1 | flag | 5231 | 39 / 46 | 5 / 5 | 51 / 58 | 56 / 63 |
| r2 | flag | 5267 | 39 / 47 | 5 / 5 | 51 / 59 | 56 / 64 |
| r3 | flag | 5267 | 46 / 39 | 5 / 5 | 58 / 51 | 69 / 56 |
| r2 | base | 5231 | 124 / 128 | 90 / 90 | 136 / 140 | 141 / 145 |
| r3 | base | 5267 | 128 / 128 | 90 / 90 | 140 / 140 | 145 / 145 |

- Page end: flag 39 to 47 layers (spread 8, 6 passes), base 124 to 128 (spread 4, 4 passes). The ranges do not overlap;
  the smallest drop is 77 layers. The will-change count is the same in every pass: 90 to 5 at the page end, 91 to 6 at
  3000 and 4500, a drop of 85 (`hero_paused_drop`).
- The max y is the census state `max`, fixed from pass 1. In flag r1 and base r2, pass 1 read a 6006 px document (max y
  5231), the others 6042 px (max y 5267), as in run 39548856639. At y 5267 exactly: flag n=2 VMs (39 to 47), base n=1
  VM (128). At 5231 the counts fall in the same ranges (flag 39 / 46, base 124 / 128).
- The base arm is the plain rewrite, so the drop is attributed by both total and reason (the earlier baseline was the
  `morph.mount:shift` arm).
- Superseded: census 40143379767 (1 VM, setTypeOfService EINVAL after a hang).

## Membership

- Run 40143377510 (dispatch, sha 4d752f0, `fw=hero:scene-pause`, engines playwright-webkit, all widths) recorded with
  `Gen.record`: mac-webkit hero pass, mac-webkit morph fail, linux-webkit hero pass. The morph summary is RED: 52 new
  units (10 content, 42 coverage). The content units are nav background-color close@0 at 390 and 641 (and close-hold@0
  at 641), and earn opacity and max-width open@6 to open@10 at 1280. The coverage units are open@3 at 1280. Content
  new units of one node property at 2 widths make the run fail (`outcome`, `lean/Fw/Gate/Trajectory.lean`).
- `Fw.Preset.Gen.run` (written): one member, engine.scroll:unthrottle. hero:scene-pause: `member` false, `why`
  not-proved (status partly-proved), trajectory `falsified: trajectory` (webkit morph cell fail). The preset was not
  edited by hand.
- Attribution (INFERRED): among the stored macOS morph runs, nav background-color has content new units at 2 or more
  widths in 39466179818 (hero.exit:scoped), 39472217441 (hero.exit:faithful, an A/A arm) and 39453181962 (a preset).
  So the same unit fails without the flag. The ledger status stays partly-proved until a rule or a rerun separates the
  two.

## Open

- macOS WebKit morph: the nav background-color close@0 samples need the in-flight rule named in
  `docs/team/tools/trajectory-probe.md` (transition from `bgRed m(q)`), or an A/A rate for this unit. Follow-up.
- Safari frame time: a follow-up, since no lane exists.
