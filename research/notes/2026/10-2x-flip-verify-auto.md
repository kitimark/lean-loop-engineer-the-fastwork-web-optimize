# flip-verify-auto: automatic readings for the flip bugs A1, A3a, A3b, A3c, A4, A5

Date: 2026-10-27. Task `flip-verify-auto` (graph r539). Branch `worktree-wf_563f1ba9-714-1`, CI branch `ci/flip-verify-auto`.
Lean: `lean/Fw/Parts/MorphGeomVerify.lean` (readings, mutation list), golden lines `verify*` in `packages/contracts/golden/morph-geom-timed.jsonl` (from `MorphGeomTimedGen.lean`).
Code: `packages/gate-breakpoints/src/flip-verify.mjs`, `flip-cell.mjs`, `cli.mjs`; job `flip-cell` in `.github/workflows/breakpoint-gate.yml`.

## Answer

- Each of the six fixes has a graded reading, and each reading fails when its fix is reverted, on both engines. MEASURED: run 40544410328 (and 40537879823), job flip-cell, 2 bands (390x844, 1280x800) per mutation, table below.
- On main, five of the six readings pass on both engines in every band. MEASURED: Chromium 12 of 12 bands for A3a, A4, A5 (runs 40530697810, 40537879823, 40544410328) and the flip cell 48 of 48 readings. WebKit: A3a 12 of 12 and A4 12 of 12 in runs 40537879823 and 40544410328.
- A5 on WebKit is the open one. The CI-graded A5 reading failed in 1 band of 12 (run 40537879823) and 4 bands of 12 (run 40544410328). Run 40544410328: all 72 pushes were taken, the failures were my coverage rule (below), which I then corrected; the corrected rule has not run on CI (the cap is 4 pushes). Replayed offline on the saved logs of run 40544410328 it passes 12 of 12 bands and both in-job repeats. Run 40537879823 has one real untaken push (360x640, first open push, 2 frames in 680 ms); its logs carry no per-frame guard samples, so the new rule cannot be replayed on it. So the unit "passes on main on both engines" is MEASURED on Chromium and INFERRED for the corrected A5 rule on WebKit.
- The two WebKit geom-timed m=0 failures of run 40512085722 are harness faults, not the flip. Both are fixed: the timed cell passes m=0 in 12 of 12 bands on both engines in runs 40537879823 and 40544410328.

## The readings

| id | reading (Lean) | page-side input | pass |
|---|---|---|---|
| A4 | `quietOk`: for 800 ms after a leave, no running width or background transition that is visibly off its end value, and nav width = base within 1 px | each rAF frame: nav width, computed background, running CSSTransitions | `quiet_new_passes`; fails: `quiet_old_fails`, `quiet_fails_moving`, `quiet_fails_width`, `quiet_fails_narrow` |
| A3a | `keptAll`: across each re-parent the CSS animation currentTime moves by the frame time (within one frame), none restarts | each frame: currentTime of every CSS animation under the nav and panel, keyed by element, name | `kept_new`, `kept_passes`; fails: `kept_old_fails`, `kept_fails_lost`, `kept_fails_vacuous`, `kept_fails_one`, `kept_fails_ahead`, `kept_fails_behind` |
| A5 | `traceOk`: every push that had a chance is taken, in order; at least 3 of 4 pushes are covered | `window.__fwTakeTrace` events (push, take) from the driver, plus per-frame `is-on-dark` | `trace_ok_cycle`, `judged_*`, `trace_*` |
| A1, A3b, A3c | the flip-state cell (rects of column beside column, earn y, lang y) | rects at m in {0, .25, .5, 1} | existing cell, run with the fix reverted |

Definitions that differ from the task text (CONFIRMED in the data, they are why the first drafts failed on main):
- A4. "No transition runs" is false on the base page: the base nav ends a close with a sub-pixel width transition and a sub-percent background transition of its own (Chromium run 40525667335, local WebKit). A transition counts only while it is visibly off its end value (width more than 1 px from base, or colour distance above 0.02 to the final background, compared in sRGB).
- A3a. A re-parented CSS animation stalls exactly one frame (currentTime held while pending). The bound is `max(16.667 ms, that frame's rAF dt) + 0.01 ms`; a restart to 0 or a lost animation fails. Slow CI frames need the dt term (320x568 failed at 16.667 in run 40525667335).
- A5. Closes never consult `allowed()` once the flip is entered, so a mutation of `allowed` is not seen by closes. The A5 mutation makes `nav.classList.contains('is-on-dark')` false always: opens are never taken, which the reading catches. A push has a *chance* when the nav className showed `is-on-dark` in some frame that a later frame of the same 680 ms window followed (the retry runs on a tick; `take_never` in Lean says a guard that never opens never takes). The className string is read, not `classList.contains`, which the mutation overrides. Untaken pushes without a chance are excused (`pushJudged`). A taken push is covered without a chance, because a runner at one frame per 680 ms has no frame to show the guard open and the take proves it did. At most one push in four may be excused (`judgedEnough`). The first version of this rule counted only pushes with a chance; run 40544410328 failed on it (below).
- Why the guard can be late: `is-on-dark` is written by nav.hitTest (a hit-test driven class), the driver retries `startTimed()` only on a tick while the tween is pending (driver.ts 193, 226-236@HEAD). At 1 to 2 frames per 680 ms the tween can end before the class arrives. INFERRED from one untaken push (run 40537879823, WebKit 360x640, nav class at push `is-hero-chrome-ready` only, 2 frames in the window).

## The mutations

Runtime mutations on the page (CSSOM edits and prototype patches; no rebuild): A1 sets the Ub wrapper to display block; A3b removes the earn `transform:none`; A3c reverts the actions inset; A4 reverts the quiet-class rule; A3a makes the `CSSAnimation.currentTime` setter a no-op; A5 as above.

| fix reverted | reading that fails | Chromium | WebKit | run |
|---|---|---|---|---|
| A1 flex row | cell: column beside | 6 of 8 readings | 6 of 8 | 40544410328, 40537879823 |
| A3b earn transform | cell: earn y | 6 of 8 | 6 of 8 | same |
| A3c actions inset | cell: lang y | 3 of 8 | 3 of 8 | same |
| A4 quiet leave | verify A4 | 2 of 2 bands | 2 of 2 | same |
| A3a time kept | verify A3a | 2 of 2 | 2 of 2 | same |
| A5 retry | verify A5 | 2 of 2 | 2 of 2 | same |

Each own-reading failure is counted on its own reading; the other readings of verify do fail too under some mutations (A5: all three), which is expected because no push is taken, so no flip is entered. Chromium also caught all six in runs 40525667335 and 40530697810.

## Runs

| push | run | commit | result |
|---|---|---|---|
| 1 | 40525667335 | cd93b285f | Chromium verify failed 320x568 A3a (float edge); WebKit: no pushes at 1280x800, 1920x1080 (listeners arm late: no warm-up); Chromium mutations 6 of 6 |
| 2 | 40530697810 | 59fd94946 | Chromium 12/12 x 3 and 6 of 6 mutations; WebKit A5 failed (page not at the true end, dpr 3 at 1 to 4 Hz); timed m=0 1280x800 failed on the scroll position |
| 3 | 40537879823 | e56ef0507 | Chromium all green; WebKit A3a 12/12, A4 12/12, A5 11/12 (the untaken push), repeats green, mutations 6 of 6; timed m=0 12/12 both |
| 4 | 40544410328 | f08b8c1a0 | Chromium all green incl. repeats; WebKit A5 8/12 by coverage rule (72 of 72 pushes taken), repeats green, mutations 6 of 6; timed m=0 12/12 both |

In-job repeats (verify on 390x844, 1280x800, 1920x1080, two more passes) ran in the same job, not on separate jobs, so they do not meet the "3 runs on separate CI jobs" rule; they show repeatability inside one runner.

## The cause of the two WebKit geom-timed m=0 failures (run 40512085722)

- Both rows compare two pages side by side (base and flag). Two faults were in the harness, neither in the flip.
- Panel mount: the morph panel mounts and unmounts on timers and an IntersectionObserver, so two pages can differ in whether the columns exist (1920x1080: flag 0 of 5 columns). MEASURED run 40525667335 artifacts: panel attribute null on one page, hz 23 vs 59 to 63. Fix: `waitMountAgree` waits for 3 agreeing polls; a mismatch is `skipped`, not a failure.
- Scroll back: after scrolling to the top the base page stayed at scrollY 2236 (`is-scroll-hidden`, pill y -72) while the flag page was at 0 (`is-hero-pill`, y 16) (1280x800, run 40530697810). Fix: `stepScroll` asks again until both pages are at the target and have stayed 3 checks; otherwise the row is skipped with the positions.
- Result: m=0 passes 12 of 12 bands on both engines (runs 40537879823, 40544410328). The m=1 rows of the timed cell stay skipped ("flip not engaged"): the cell scrolls and does not wheel-push; the push is covered by the verify reading. Reported-only.

## How it runs elsewhere

- Entry point for the phone and Safari macOS lanes: `driveFlipProbe(page, {cycles})` in `packages/gate-breakpoints/src/flip-verify.mjs` with `installFlipProbe` as the page init script and `analyseFlipProbe(raw, {baseWidth, verify: loadVerify(), expectedPushes})`. CLI: `node src/cli.mjs verify --engine <e> [--bands 390x844,...] [--mutation A4|A3a|A5 --expect-fail] [--cycles n]`; the cell: `flip ... [--mutation A1|A3b|A3c --expect-fail] [--report-only]`. Not run on a phone or Safari macOS (accepted limit).
- Graded readings fail the job (no `|| true`); `--report-only` exits 0 and says so.

## TS stand-ins (replayed against the golden in `test/flip-verify.test.mjs`)

`judgeQuiet`, `keptWithin`/`judgeKept`, `takenFlags`/`judgeTrace`, `pushJudged`, `judgedEnough`; colour distance for the A4 visible-background rule has no Lean statement (the 0.02 threshold and the sRGB compare are TS only). The chance rule (which frames count) is TS only; Lean states what is done with it.

## Limits of this verification

- Verify runs at dpr 1: the push and take path does not depend on pixel density, and WebKit on the CI runner is at 2 to 4 Hz at dpr 3. A warm-up open and close before recording (listeners arm late). The page is scrolled to its true end first.
- CI WebKit is software-rendered and slow (hz 1 to 6 with the open panel); that is why A5 needs the chance rule. It is not a statement about phone frame rates.
- The corrected A5 rule (taken counts as covered) is MEASURED only offline on the saved logs of run 40544410328; no CI run executed it.
- The veil, the image model and the pixel report are other tasks (the pixel report stays reported). Class L stays the user's review.
