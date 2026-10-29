---
id: 2026-10-29-faded-pause-entry
kind: note
title: "platform:faded-pause entry: resume, scene-writer and escape items proved and linked; every gate cell passes, so Gen.run enters it and v2-proved has 3 flags"
status: draft
created: 2026-10-29
topics: [platform, faded-pause, v2-proved, trajectory-probe, ledger, lean]
---

# faded-pause-entry

Task `faded-pause-entry`, branch `ci/faded-pause-entry` (worktree branch `worktree-wf_debe029b-131-1`). Pinned unit: the
gate cells of platform:faded-pause recorded through Gen.record, each missingWhy item of its ledger row closed by a linked
Lean theorem or left open with a reason, and the v2-proved decision Gen.run computes.

## Answer
Gen.run decides enter with no blockers, so v2-proved now has 3 flags: engine.scroll:unthrottle, hero.exit:threaded
and platform:faded-pause. Source: packages/contracts/golden/preset/v2-proved.decisions.jsonl, the `entry` of row
`platform:faded-pause`. No other flag's decision changed.
`Gen.run []` regenerated these four files, and `Gen.run ["--check"]` reports "up to date, 3 flags":
- v2-proved.json
- apps/site/src/registry/presets/v2-proved.json
- v2-proved.decisions.jsonl
- v2-proved.trajectory.jsonl

## Entry requirements (Gen.entryReqs)
| requirement | state | evidence |
|---|---|---|
| proofs | met | `why` = proved: the linkTable key is the row's candidate, and the row is `proved` and not model-bug. `fadedLinkGaps` is empty |
| gate chromium | met | run 40900090514: chromium hero pass, morph pass (v2-proved.trajectory.jsonl) |
| gate webkit | met | run 40900090514: mac-webkit hero pass, morph pass; linux-webkit hero pass |
| look | met | visClass E (platform/part.json) |
| q6 | met | always met |

## Gates
- No recordable run existed before this task. Breakpoint-gate run 40287895072 has only gate artifacts, no trajectory
  artifacts.
- Push 1 of 2: commit 80d9c0b3cbe77ee77bfac8e7891f590f81c497fc on ci/faded-pause-entry, with
  `[trajectory fw=platform:faded-pause engines=both debug=nav-transition]`. The `debug=` key makes the apple leg run
  (`Fw.Ci.Trigger.appleRuns`). Inputs: results/faded-pause-entry/r1/inputs.json, copied from the trajectory-inputs
  artifact.
- Run 40900090514 passed (`fw ci wait` returned success, so pass). It was recorded with
  `Gen.record ["40900090514", <sha>, "-", trajectory-chromium, trajectory-playwright-webkit, trajectory-apple]`.
  All five cells pass:

| engine | walk | outcome | groups (content / coverage) | widths per content / coverage list |
|---|---|---|---|---|
| chromium | hero | pass | 0 | - |
| chromium | morph | pass | 3 (3 / 0) | 1 |
| linux-webkit | hero | pass | 0 | - |
| mac-webkit | hero | pass | 0 | - |
| mac-webkit | morph | pass | 42 (4 / 42) | 1 |

Source: the v2-proved.trajectory.jsonl rows whose `run` is 40900090514.
- `Fw.Gate.Trajectory.outcome` tests content and coverage repeats separately (lean/Fw/Gate/Trajectory.lean:2985-2986):
  a content list at 2 or more widths fails the cell, a coverage list at 2 or more widths leaves it unjudged. In every
  group the content units sit at one width and the coverage units sit at one width. In the mac-webkit morph row
  (v2-proved.trajectory.jsonl:89), logo.color has content [390] and coverage [1280]; earn.opacity, earn.max-width and
  nav.background-color have content [640] and coverage [1280].
- Chromium: nav.rect, nav.background-color and nav.transform.shift at 1280 (steps close@0 and close-hold@0).
- mac-webkit: 4 content groups at 390 or 640, and coverage groups from one open@2 step at 1280.
- The run summaries count these units as "new" against the faithful arm (summary-*.md in trajectory-chromium and
  trajectory-apple):
  - chromium: 4 of 14416
  - apple: 48 of 14416
- These units are on the nav morph at the top of the page. The flag acts only after the platform fade reaches 0, at the
  page end. INFERRED: the units are morph-walk noise, not caused by the flag. Gen's rule passes these cells whatever the cause.

## Lean (lean/Fw/Parts/PlatformFadedPause.lean)
The earlier theorems (zero_iff, faded_same_pixels, frame_same, visible_phase, faded_no_tick, faded_run, glint_phase,
scene_offscreen, scene_faded, scene_neither) are in research/notes/2026/10-2x-platform-faded-pause.md. New here:
- Escape: `escape_shows` (an element that escapes the opacity group shows its own colour) and `invisible_iff` (at fade 0
  the result is the backdrop for every subtree colour exactly when nothing escapes, or the escape paints the backdrop
  colour). This turns the earlier "no descendant escapes" premise into an iff; the census test stays the check.
- Resume: a two-clock model, `OrigClk` (the page without the flag) and `FlagClk` (current time, phase, observer state,
  fade, saved start). `resume_phase`: from the same start, after any event list that `Allowed` admits, every unfaded state
  shows the same phase `min cur dur` on both clocks. `settled_skipped`: an animation at or past its duration saves no
  start; `restore_skips`: with no saved start the restore changes nothing.
- Writer: `writer_or` (the one data-fw-scene writer pauses exactly when offscreen or faded), `writer_order_free` (the
  observer and fade updates in either order give the same attribute), `setFaded_idem`, `setActive_idem`,
  `setFaded_writes` (one write per fade edge, none when the fade state repeats).
- WebKit work cut: `Fw.Device.EndWktr.cuts_spec` (the judge used for the WKTR flip arm).

Linked: ledger row leanFor holds the 17 PlatformFadedPause names and `Fw.Device.EndWktr.cuts_spec`; Gen's linkTable maps
platform:faded-pause to the row's candidate key, and `Gen.fadedLinkGaps` (checked in `Gen.run`, which throws when it is
not empty) requires 16 of them by name.

## Open items (left on the row with reasons)
- The one extra RecalcStyle and Layout at the Chromium resume edge (window `finish`: RecalcStyleCount 320 to 321,
  LayoutCount 52 to 53; base run 40287924353, flag run 40287928566, Lean `Fw.Measure.OffscreenWindows`, table in
  research/notes/2026/10-2x-platform-faded-pause.md):
  INFERRED to be the edge's scene write and the `getAnimations` flush. `setFaded_writes` proves one scene write per edge;
  which engine pass the counter adds is not isolated by a run.
- iOS Safari not measured: WKTR stands in for WebKit (accepted limit); the phone check comes with a user capture session.
- Premise faded implies active (`Allowed`): INFERRED from the tween taking every push while the section is active
  (MorphTween, snapshot 13065-13072). The third `#guard` after `setFaded_writes` is the counterexample: a scroll that skips
  the push handler and leaves the section off screen while the fade is 0 resumes 5 ahead of the original.
- Status: the row is `proved` with these two items open, the same form as the engine.scroll:unthrottle row (proved, three
  measurement items open). Both items are measurement attributions, not correctness of the flag; every correctness item
  is closed by a linked theorem.

## Composition with members
- Members engine.scroll:unthrottle and hero.exit:threaded: no part.json declares a conflict or requirement between them and
  platform:faded-pause. resolve.ts:140-141 checks `conflicts` over the selected set and accepts the 3-flag preset.
- data-fw-scene writer vs platform.sweep:offscreen-pause: the flag owns the single writer, which ORs the observer with the
  fade (`writer_or`, `writer_order_free`, `scene_offscreen`). platform/part.json still declares the two flags in
  conflict, and sweep offscreen-pause is not a member.
- Glint hold-freeze and the compositor glint clocks are not members, so nothing composes with them yet.
  - The faded-pause glint pause shares the dash svgs' SMIL clock with hold-freeze (10-26-end-of-page-variants.md
    'Conflicts').
  - platform.glint/part.json declares no conflict between them.
  - Follow-up: declare that conflict, or prove the two compose, before hold-freeze can enter.
- The preset carries platform:faded-pause. part.json declares it in conflict with:
  - morph.tween:waapi
  - morph.tween:waapi-scoped
  - platform.sweep:offscreen-pause
  - platform.glint:offscreen-pause

  So resolve.ts:140-141 refuses a search like `?preset=v2-proved&fw=morph.tween:waapi` unless the search also selects
  another platform variant. No other flag changed membership.

## Numbers and sources
- WKTR recalcs per 100 frames: base 244/242/237, faded-pause 87/89/91, all-paused floor 83/70/81; bands 11/10/9; cuts in
  3 of 3 (run 40869911524, results/end-wktr-flip/r1/verdict.txt 'fp/recalc' lines, judged by `Fw.Device.EndWktr.judge`).
- WKTR layouts per 100 frames: 186/176/104 to 22/75/64, cuts in 3 of 3 (same file, 'fp/layout' lines).
- Trajectory: run 40900090514 at 80d9c0b. Cell outcomes come from v2-proved.trajectory.jsonl. Unit counts (14416 units; 4 new in
  trajectory-chromium, 48 new in trajectory-apple) come from the summary files in the artifacts.
