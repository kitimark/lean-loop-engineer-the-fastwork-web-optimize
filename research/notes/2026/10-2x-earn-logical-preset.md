# nav:earn-logical and the v2-proved preset (task earn-logical-preset)

Answer: the 390 px earn-frame cell passes on macOS WebKit (worst frame 60 changed pixels against 78 allowed, exit and entry). Gen.run still says "not yet" for `nav:earn-logical`: blocker `gate webkit` (the macOS WebKit morph walk fails), and the flag cannot be a member in any case (kind proposal, class L). Preset membership is unchanged: `engine.scroll:unthrottle`, `hero.exit:threaded`.

## 1. The 390 cell (MEASURED, run 40876250109)

Pinned unit: the 390 px cell for `nav:earn-logical`, macOS Playwright WebKit against macOS Playwright Chromium, against the Lean `frameBound` row (`packages/contracts/golden/parts/nav.earn.webkit.jsonl`; threshold 40, 2 permille, band 100 px: allowed 78 at 390, 256 at 1280).

Rule fixed before the data (handoff, commit 81b3af044): the cell passes when every one of the 17 frames of the logical arm, exit and entry, is within the bound. The measure is `maxChanged`, the frames with the label hidden, the same as the verdict of `nav-cta-webkit-match`.

| width | scenario | arm | worst frame | allowed | frames over | settled |
|---|---|---|---|---|---|---|
| 390 | exit | logical | 60 | 78 | 0 | 3 |
| 390 | entry | logical | 60 | 78 | 0 | 10 |
| 390 | exit | faithful | 245 | 78 | 6 | 3 |
| 390 | entry | faithful | 1332 | 78 | 4 | 10 |
| 1280 | exit | logical | 53 | 256 | 0 | 53 |
| 1280 | entry | logical | 60 | 256 | 0 | 45 |

Both apple legs (`apple-390_641`, `apple-640_1280`) ran the harness at 390 and 1280 and gave identical numbers. The faithful arm exceeds the bound; the logical arm passes; in Chromium the two arms differ by 0 changed pixels. Recorded in `packages/contracts/golden/parts/nav.earn.frames.jsonl` by `Fw.Parts.NavEarnFrames` (`Cell.ok = frameOk width worst`; the check job `nav-earn-frames golden check` replays it). Result files: `results/earn-logical-preset/summary.json`.

Limits (accepted): macOS WebKit stands in for iOS Safari; the rect differences that remain are 2 px at 390 and 4 px at 1280.

## 2. Gen.run for nav:earn-logical (CONFIRMED, run 40872462216)

The flag was not linked, so Gen.run did not decide it. `Fw.Preset.Gen.linkTable` now links the candidate string of ledger row n=73 (`nav.earn.logicalPadding`, status proved) to `nav:earn-logical`; `#guard`s in `lean/Fw/Preset/Gen.lean` pin that the link exists, that the proofs requirement is met, and that the entry is "enter" only with both gates.

Walk of push 1 (trajectory-probe, fw=nav:earn-logical, debug=nav-transition), recorded by `Gen.record` into `v2-proved.trajectory.jsonl`:

| engine | hero | morph |
|---|---|---|
| chromium | pass | pass |
| linux-webkit | pass | not run |
| mac-webkit | pass | fail |

The mac-webkit morph cell fails with 42 groups, most of them `coverage` at 390, 640 and 1280. Content groups: nav `background-color` (390, 640, 1280), nav `cls.is-on-dark` (1280), logo `color` (1280), earn `opacity` (640, 1280), earn `max-width` (640). The nav and logo groups are not the earn button.

Decision row (`packages/contracts/golden/preset/v2-proved.decisions.jsonl`): `entry: not yet, blockers [gate webkit]`, `member: false`, `registered: false`. Look is met (accepted look 2026-10-25), proofs are met, Chromium gates pass.

## 3. Structural blocker (CONFIRMED, lean/Fw/Preset/V2Proved.lean)

`V2Proved.ok = isOpt && why == proved && trajWhy == pass && !isLook`, and `look_not_mem` proves an L-class flag is never in the preset. `nav:earn-logical` is kind proposal and class L, so even with a passing webkit gate Gen.run could not make it a member. Not patched here (the review-loop rules: a premise problem is a finding, not a sideways fix). Follow-up: decide whether look-accepted L flags get their own preset or the kind changes to optimized once the user's look verdict is the accepted gate.

## 4. Preset composes (step 3)

It did not enter, so there is nothing new to compose. The site registry/preset tests (`apps/site`, 165 files, 8460 tests) pass on the unchanged preset.

## Pushes and runs

| push | sha | run | result |
|---|---|---|---|
| 1 | c3512b93f | 40872462216 | walk complete; apple jobs hit the 18 min cap; earn-frames step cancelled |
| 2 | 0bcadecfe | 40876250109 | earn-frames-only on the apple legs (message `[earn-frames]`, frames steps guarded); 390 cell decided. The workflow change is outside the task writes and is not landed; it stays on the ci ref |
