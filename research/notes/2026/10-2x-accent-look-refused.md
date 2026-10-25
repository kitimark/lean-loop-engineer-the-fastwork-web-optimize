# hero.accent: the user refused draw-nolayout-full; draw-nolayout is a look change too

## Answer
- `hero.accent:draw-nolayout` (glide kept) does not render the accent text the same as the faithful page. It is a look
  change, and it needs its own user look decision before it could ship. The user never saw it on its own.
- The accent text of `draw-nolayout` is drawn by the same CSS rules as the refused `draw-nolayout-full` (CONFIRMED,
  source below). The user's reason, "it changes how the accent text renders", therefore applies to it (INFERRED). The only difference between the two arms is the headline glide, and `draw-nolayout` keeps the
  faithful glide.
- Recorded in `Gen.lookDecisions`; ledger row `accent.drawin-width-nolayout` has status `refuted`. `Gen.run` fails
  when a refused flag is in v2-proved.

## Decision recorded (CONFIRMED: the user, in chat, 2026-10-25)
- `lean/Fw/Preset/Gen.lean:247-252`: flag `hero.accent:draw-nolayout-full`, date 2026-10-25, decision `rejected`,
  review `done`. WebKit material: runs 40030735082 and 40035116432 (webkit-sim, task accent-nolayout-measure),
  artifacts `webkit-sim-r1`, `webkit-sim-r2`, `webkit-sim-r3`, kept 30 days (`.github/workflows/webkit-sim.yml:491`),
  expire 2026-11-22. Chromium material: `pending`, because no Chromium run exists.
- "Refused" is written as `rejected`: the look verdict words are `kept`, `rejected` and `accepted`
  (`Gen.LookVerdict`, `lean/Fw/Preset/Gen.lean:193`; parsed by `Fw.Wire.Review.verdictOf`, `lean/Fw/Wire/Review.lean:21-23`). No new word was added.
- Ledger `research/findings/ledger.json`, row `accent.drawin-width-nolayout`: status `refuted`, `userDecision` with
  date, reason, source (chat) and the material above. `Fw.Console.Compose.classBy` puts any row with status `refuted`
  in the class whose text reads "refused".
- The registry (`apps/site/src/parts/hero.accent/part.json`, outside this task's writes) still lists both wipe arms as
  `kind: optimized` without `visClass: L`. `Gen.lookCandidates` reads only class L, so the decision cannot rest on it.
  `Gen.decisionKept` (`lean/Fw/Preset/Gen.lean:302`) keeps a decision when its flag is a look candidate or when it is a
  refusal of a registered flag; `staleDecisions` names every other decision. Theorems: `decisionKept_of_candidate`,
  `decisionKept_of_rejected`, `rejected_of_decisionKept` (a kept decision outside the look candidates is a refusal) and
  `not_decisionKept_of_unregistered` (a decision on an unregistered flag is stale).
- `Gen.refusedMembers` (:335) lists refused flags inside the preset, and `Gen.run` throws when the list is not empty
  (:481-482). Today the list is empty: the flag has no link and its row is not `proved`.
- Goldens from `Gen.run` (never by hand): every row of `v2-proved.decisions.jsonl` gains `userDecision`
  (`Gen.decisionOf`), which is the refusal on `hero.accent:draw-nolayout-full` and `null` on rows without a decision;
  that row's `flagRows` status is `refuted`. `look-change.candidates.jsonl` is unchanged, because the flag is not
  class L. `Gen.run --check` and the ledger agreement check (`ledgerDisagreements`) pass.

## Why draw-nolayout is a look change (Lean `Fw.Engine.StyleDiffAccent`, lines @0a03ebb)
| statement | where | what it says |
|---|---|---|
| `faithfulFrame`, `armFrame` | :54-60 | faithful draw frames change `stroke-dashoffset` on three copies; the arm frames change `clip-path inset()` instead |
| `slotChanges` | :109-116 | `draw-nolayout` uses `armFrame` in every slot; `draw-nolayout-full` differs only in the later draw-in frames, which drop `width` |
| `arm_drawIn_layout_only_width` | :89 | the `draw-nolayout` draw-in frame still carries the `width` change, the faithful glide |
| `clip_endpoints` | :315 | the hidden end of the clip shows nothing and the shown end covers the box, so start and end frames agree |
| `clip_coverage_differs` | :246 | for 0 < c < 1, c·c ≠ c, and 1·1 ≠ 0: a final stroke under a clip never gives the coverage of a traced stroke |
| `#guard verdict .clipFinal == .look` | :228 | the same-look search rates "final stroke clipped to the swept region" as a look change |
| `jump_differs` | :271 | applies only to `draw-nolayout-full`: the text after the word moves when the width jumps |

The accent strokes are therefore revealed by a left-to-right clip in both arms, and by a stroke trace on the faithful
page. The two pictures agree at the ends of each 0.9 s draw and differ inside it. Lean has no statement that the
headline glide of `draw-nolayout` is pixel-equal to the faithful glide. It keeps the same change: the `.drawingIn` width
transition, 0.9 s, the same easing.

Source (CONFIRMED, `apps/site/src/parts/hero.accent/accent.module.css`): the stroke rules at :65, :70 and :73 select
`:is([data-fw-draw='nolayout'], [data-fw-draw='nolayout-full'])`, so both arms draw the accent text the same way. Only
:76-78 (`transition: none`) is specific to `draw-nolayout-full`.

## Measured material (MEASURED, webkit-sim, 430x775; no pixel data)
| run | arm | width transitions started (6 captures) | Layout rows per hero-exit scroll frame |
|---|---|---:|---:|
| 40035116432 | faithful | 10 | 2.443 |
| 40035116432 | draw-nolayout | 9 | 1.771 |
| 40035116432 | draw-nolayout-full | 0 | 1.781 |

- `draw-nolayout` starts the width transition like faithful, so the glide is kept. `draw-nolayout-full` starts none.
  Report: `results/accent-draw-nolayout/accent-report-40035116432.md`.
- Pixels: none exist for the draw window. Path-pix has no draw-window mode, and the real-iPhone session
  (`results/phone/2026-10-24/summary.md`) showed only `draw-nolayout-full`. The look verdict rests on the Lean
  statements, the CSS source and the user's words, not on a pixel diff.

## Limits
- The user's verdict is recorded, not measured. No CI was dispatched.
- `ledgerDisagreements` compares only the Chromium material with the ledger's review text. This decision has no
  Chromium material, so its WebKit runs and artifacts are written in the ledger text without a check.
- Ledger row `accent.draw-nolayout` still holds the 2026-10-24 `userDecision` carried over from `draw-nolayout-full`.
  `Gen.lookDecisions` has no entry for it, because the user has not decided on that flag.
- Follow-up outside this task's writes: register `draw-nolayout` and `draw-nolayout-full` as `kind: proposal`,
  `visClass: L` in `part.json` (and the assertions in `drawNoLayout.test.ts`), so the look-change golden lists both.
