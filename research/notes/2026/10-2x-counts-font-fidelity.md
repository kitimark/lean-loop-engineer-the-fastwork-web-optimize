# Counts lane fonts: which font set lays the page out like WebKit

Question: the Chromium lane image had no system fonts until task counts-lane-fonts added `fonts-liberation`. Which set of
Debian font packages makes the lane's Chromium lay the original page out like WebKit (the phone's engine), and which figures
taken on the font-less image are suspect? Tags: MEASURED (a CI run id named), INFERRED (reasoned, not seen), CONFIRMED (source read).

## Answer

- MEASURED: **fonts-liberation alone is enough; the lane image stays as it is.** Five font-bearing sets give the same document
  height (6278 px at 430x932, 5964 px at 430x775, 8594 px at 1280x800) and the same part boxes, 1 px from Playwright WebKit on macOS
  (6277, 5963, 8594). Lean's pick rule (`Fw.Measure.Profile.fontPick`, fewest distance, then fewest .notdef, then fewest packages)
  returns `liberation`. No Dockerfile, `fonts.conf` or Lean font constant changes.
- MEASURED: the **font-less image did not draw the page's text**: the three web faces (Google Sans normal x2, Playpen Sans Start
  Selling) end in FontFace status `error`, the text lays out with 0 lines, the mobile page is 720 px short (5558 vs 6278) and
  desktop 1280 crashes. The hypothesis that fallback fonts (JetBrains Mono, Momo Signature, star glyphs) explain the gap is refuted.
- MEASURED: the **Simulator (iOS 27, iPhone 15 Pro Max, Safari) reads 6042 px at 430x775, the number the phone gave** (results/phone/2026-10-17-s1: 6042).
  Playwright WebKit and Chromium read 5963/5964. The gap is the hero (1550 vs 1630 px) and the platform sweep (35 vs 37 px) and no
  other part (INFERRED cause: the hero uses viewport units, `100svh`/`100dvh` are in the snapshot css, and Safari on iOS sizes them
  from its own toolbar state, which the desktop WebKit viewport does not copy). It is not a font effect: all five sets are
  one length at 430, and the Simulator, which has the phone's fonts, agrees with the phone.

## Document height (CSS px), original page

| engine / set | 430x932 | 430x775 | 1280x800 |
|---|---|---|---|
| Playwright WebKit 27.2, macOS 26.6.2 (reference) | 6277 | 5963 | 8594 |
| Simulator Safari, iOS 27.0 (2 sessions, identical) | n/a | 6042 | n/a |
| phone iPhone 15 Pro Max Safari (results/phone/2026-10-17-s1) | n/a | 6042 | n/a |
| none (old image) | 5558 | 5244 | crash |
| liberation, +dejavu, +tlwg, +noto, +noto+emoji (all) | 6278 | 5964 | 8594 |

Runs: font-fidelity 39906869467 (chromium job failed on a missing output directory, webkit-mac ok) and 39907447564 (chromium,
webkit-mac, sim, report all success; the two runs agree on every WebKit number). Two repeats per Chromium set in one job: all identical
(document height and every part box). Distance to WebKit (Lean `fontDist`): 3 for every font-bearing set at both mobile views, 0 at
1280; .notdef occurrences 0; 457 of 462 leaves have the same line count, 0 differ, 5 missing (4 at 430x775); the only part gaps are
`people.card` and `people.carousel`, +1.34 px each. The `none` set: distance 1494 at both mobile views, 4194 .notdef occurrences, 205 leaves
with another line count, 165 missing. Thai (`tlwg`), Noto and emoji packages add nothing: with `liberation` alone every code point of the page is drawn by a web face or a system
font (4354 of 4354 occurrences covered at 430, 3776 at 1280; .notdef 0), so a bigger set costs image bytes and changes no layout.

## What the font-less image measured (ledger and baselines)

- Figures taken on the old image: mobile page 720 px short and desktop 1280 crashing (the earlier `text-wrap: balance` workaround).
  Runs: swipe-v1 old image 39901082850 (503 frames, classes original 36/25/9 det/stable/quar) vs new image 39900399252 (575 frames, 34/26/10);
  rewrite 27/27/16 old vs 26/30/14 new (same two runs). Old frozen snapshot 499, new 570.
- people-o-hover (hover scroll, 3 runs each): base 36/24/9 on the old image (39881189724) becomes 26/27/16 on the new (39900922311);
  flag `people.o:preview-translate` 26/31/12 old (39881193403) becomes 36/18/15 new (39900929308). The base-minus-flag deltas
  inside one run set still hold; their absolute classes do not carry over.
- `classes.frozen.json` (image `sha256:8f0e17f5...`, built by run 39049264131; runs 39184638066, 39186469962, 39186477379 for the swipe-v1
  original) and `results/baselines/chromium/*` (earlier image `ebefaf34`) were measured on a page whose text did not render. Every
  absolute Chromium count, frame count and class taken from them is of that page. Differences inside one run (base arm against flag
  arm, A against P) are comparable because both arms ran on one image.
- Ledger (`research/findings/ledger.json`): 37 of its 53 numbered entries (n = 2, 4, 6, 8, 9, 11, 12, 14, 21, 26 to 53) cite only CI runs older than
  the first fonts run (39900399252), so their Chromium counts figures come from the font-less image unless they are WebKit, gate or pixel results.
  INFERRED per entry: the table lists, per entry, the runs its text cites (a regex over the entry's JSON, MEASURED as a list of ids); that an entry's
  Chromium figure comes from a counts job rather than a gate, WebKit or pixel job is INFERRED from the date alone, because no entry's run was opened.
  Read an entry's `evidence` run ids before relying on its Chromium number, and prefer its WebKit verdict. Entries 19 (4 of its 5 cited runs older)
  and 54 (5 of 7) also cite older runs and are not on the list as written; checking them is a follow-up.

| entry n | part | rows | runs cited | newest run cited (all older than 39900399252, the first fonts run) | status |
|---|---|---|---|---|---|
| 2 | engine.scroll | 1 | 1 | 39048702153 | INFERRED |
| 4 | nav.hitTest | 1 | 1 | 39048702153 | INFERRED |
| 6 | hero.exit | 4 | 26 | 39516092834 | INFERRED |
| 8 | hero.countdown | 4 | 6 | 39367037943 | INFERRED |
| 9 | morph.tween | 6 | 20 | 39505203727 | INFERRED |
| 11 | morph.panel | 5 | 2 | 39106547260 | INFERRED |
| 12 | morph.mount | 3 | 8 | 39325741608 | INFERRED |
| 14 | morph.columns | 2 | 3 | 39527779967 | INFERRED |
| 21 | pain.notes | 3 | 7 | 39343967737 | INFERRED |
| 26 | premise | 1 | 5 | 39102911529 | INFERRED |
| 27 | premise | 1 | 5 | 39102911529 | INFERRED |
| 28 | gate.page-root | 1 | 1 | 39130842058 | INFERRED |
| 29 | nav.morph | 1 | 1 | 39292323514 | INFERRED |
| 30 | premise | 1 | 8 | 39340222228 | INFERRED |
| 31 | premise | 1 | 3 | 39354644363 | INFERRED |
| 32 | gate.margin | 1 | 4 | 39362804966 | INFERRED |
| 33 | premise | 1 | 4 | 39370632229 | INFERRED |
| 34 | load.bundle | 1 | 2 | 39352403687 | INFERRED |
| 35 | tooling.land | 1 | 3 | 39370530353 | INFERRED |
| 36 | tooling.land | 1 | 4 | 39345070296 | INFERRED |
| 37 | tooling.fwcore | 1 | 2 | 39324877968 | INFERRED |
| 38 | tooling.ci | 1 | 1 | 39332408753 | INFERRED |
| 39 | nav | 1 | 6 | 39530106935 | INFERRED |
| 40 | hero | 1 | 7 | 39557718020 | INFERRED |
| 41 | engine.scroll | 1 | 3 | 39667548341 | INFERRED |
| 42 | platform | 1 | 4 | 39685930205 | INFERRED |
| 43 | hero.accent | 1 | 5 | 39699740380 | INFERRED |
| 44 | platform | 1 | 3 | 39731104953 | INFERRED |
| 45 | morph.panel | 1 | 6 | 39760667274 | INFERRED |
| 46 | morph.mount | 1 | 4 | 39781320030 | INFERRED |
| 47 | pain | 1 | 15 | 39856789295 | INFERRED |
| 48 | commission | 1 | 7 | 39843567401 | INFERRED |
| 49 | nav | 1 | 13 | 39887331854 | INFERRED |
| 50 | nav | 1 | 13 | 39887335005 | INFERRED |
| 51 | morph.panel | 1 | 8 | 39855506403 | INFERRED |
| 52 | nav | 1 | 13 | 39887328839 | INFERRED |
| 53 | people.o | 1 | 22 | 39881193403 | INFERRED |

## Re-measure on the pick image

- Pick image = the lane image of counts-lane-fonts (`fonts-liberation 1:1.07.4-11`), unchanged by this task.
- MEASURED, swipe-v1 on the pick image, three workflow runs of one image: 39914488176 (built the image), 39916914389 and 39916917890 (both
  `image_run=39914488176`), all branch ci/counts-font-fidelity, sha 3783b391d, image `sha256:47b1dcbe...` in all 18 jobs, 575 frames and document
  height 6278 px in every job. Frozen classes over the three runs (kMax 4, tMax 24; `freeze.mjs`, Lean `Fw.Measure.Freeze`), deterministic/stable/quarantined
  of 70 types: original 30/16/24, rewrite 23/22/25. The font-less image gave original 36/25/9 (503 frames, frozen snapshot 499).
  The quarantined share is the cross-run worst class: one run alone gave 34/26/10 (39900399252).
- Superseded by the refreeze below. `classes.frozen.json` and the zone baselines were not committed then. `freeze.mjs --out` writes the whole file from the runs it is given, and the
  file holds one image id for all profiles and arms ("image digest across profiles and arms" refuses a mix). A file from the three swipe-v1 runs alone
  loses the swipe-touch-v1 table and fails 7 tests of `pnpm --filter @fw/measure-chromium test` (the four baseline checks and three faithful comparisons);
  with the old file all 76 pass. So the refreeze is one step over both profiles, after the touch runs below exist.
- swipe-touch-v1 run 39914492010 failed in every counts job: `touch swipe did not finish within maxFrames` after 2000 swipe frames (827 s per job).
  Lean now derives the allowance: `Fw.Measure.Profile.Swipe.budget` = (4 x strokes + 1) x frames per stroke, strokes = ceil(scroll range / finger path),
  for the font page's scroll range 6278 - 932 = 5346 px, 7 strokes of 82 frames: 2378 (the old page, 4626 px, gives 2050). Theorems: the budget is at least
  the ideal swipe, monotone in the scroll range, and covers a swipe whose strokes carry only a quarter of their path. Golden rows `touchPage` and
  `touchBudget` in `packages/contracts/golden/measure/profile.jsonl`; the twin `swipeBudget` in `profile.mjs`; the profile holds 2378 and its test
  checks the number against the golden. **INFERRED, and doubtful as a cure:** a swipe over 5346 px needs about 7 x 82 = 574 frames (the old page needed
  531 frames for 4626 px), a quarter of the 2000 that ran out, so a shortage of frames is not the arithmetic reason for the failure; a stall (the
  swipe stops advancing, for example a touch target at the stroke's start point that takes the vertical pan) fits 2000 frames at 0.41 s each. The
  error now names scrollY, the page's scroll range, the highest scrollY and the touch events sent.
- MEASURED, swipe-touch-v1 run 39920521620 (image_run=39914488176, maxFrames 2378) failed in all six jobs alike: scrollY highest 5342 of 5346, 2263 moves
  (29 strokes, though 7 strokes of 780 px cover the page), 2322 touch events. So it is a stall 4 px short of the limit, not a frame shortage. INFERRED
  cause: the compositor's scroll bound for a touch gesture is a few px below the main-thread bound (`scrollTo` reaches 5346). The old end condition
  `yNow >= docHeight - realInnerHeight - 0.5` never held. swipe-v1 passed because it is `scrollTo` mode: its plan is fixed by frame count and the
  engine clamps, so it never waits for a scroll position (575 frames, highest scrollY 5346 in run 39916914389). The error's `scrollY null` was the last
  recorded frame, whose scrollY is filled one frame later; the message now prints the current reading.
- Fix (Lean `Swipe.ended`, `Swipe.band` = dy, `Swipe.idleFrames` = 2 strokes; theorems `swipe_ended_limit`, `swipe_ended_stall`, `swipe_not_ended_far`,
  `swipe_not_ended_moving`, `swipe_budget_idle`; golden rows `touchEnd`; twin `swipeEnded` in `profile.mjs`): the limit is the scroller's own
  `scrollHeight - clientHeight` read once on the settled page; a touch or wheel swipe ends when scrollY reaches it, or when scrollY is within one move
  of it and 164 frames (two strokes) gained nothing. A stall farther than one move from the limit is never accepted (it still fails at maxFrames).
  The result records `input.scrollLimitPx`, `input.endReason` (limit or stalled) and `input.endGapPx`. The wheel
  profile maps to a one-move stroke (Swipe dy 0 dy 0 0). Not proved: the cause of the 4 px gap (a stall beyond one move would still fail).
- Dispatch for the lead (the three swipe-touch-v1 runs must use image_run=39914488176, the image of the swipe-v1 runs, because the freeze refuses two image ids):
  `gh workflow run chromium-counts.yml --ref ci/counts-font-fidelity -f profile=swipe-touch-v1 -f target=both -f image_run=39914488176` three times; then
  `gh run download <id> --dir runs/<id> --pattern 'chromium-c*'` for the six runs and
  `node packages/measure-chromium/src/freeze.mjs runs/39914488176 runs/39916914389 runs/39916917890 runs/<t1> runs/<t2> runs/<t3> --built-by 39914488176 --out packages/measure-chromium/classes.frozen.json`,
  the zone stores (`pnpm -s fw ci <run> --branch ci/counts-font-fidelity`, then `zone-baseline.mjs --store <store> --target original|rewrite --profile <p> --run <id> --out results/baselines/chromium` per profile and arm),
  `node packages/measure-chromium/src/zone-baseline.mjs baseline --out results/baselines/chromium`.
- MEASURED, swipe-touch-v1 on the pick image, three workflow runs of one image: 39924634896, 39924639452, 39924643106 (branch ci/counts-font-fidelity, sha c3c94a0b5, `image_run=39914488176`,
  image `sha256:47b1dcbe...` in all 18 jobs). All 18 jobs ended `input.endReason = stalled` with `endGapPx = 4` and `scrollLimitPx = 5346` (limit minus highest scrollY): within one
  move (780 px) of the limit as Lean `Swipe.ended` requires, so the end rule held in every job; none ended at the limit. The 4 px gap is the same in every job, so it is a property of the
  touch scroller, not noise (INFERRED cause stays: compositor bound a few px below the main-thread bound). Every job has 771 frames.
- MEASURED, frozen classes of the font image against the font-less table (kMax 4, tMax 24; types det/stable/quarantined of 70, per arm; `freeze.mjs`, `classes.frozen.json` now image `47b1dcbe...`, built by run 39914488176):

| profile, arm | font-less (image 8f0e17f5, run set 39184638066...) | font image (runs above) |
|---|---|---|
| swipe-v1 original | 33/27/10 | 30/16/24 (runs 39914488176, 39916914389, 39916917890) |
| swipe-v1 rewrite | 30/22/18 | 23/22/25 (same runs) |
| swipe-touch-v1 original | 24/35/11 | 33/18/19 (runs 39924634896, 39924639452, 39924643106) |
| swipe-touch-v1 rewrite | 27/26/17 | 20/19/31 (same runs) |

  Frames: swipe-v1 575 in every job of both arms (font-less baseline 503 original, 385 rewrite); swipe-touch-v1 771 in every job of both arms (font-less 531 original, 409 rewrite).
  Zones: swipe-v1 13 (was 12), touch 14 (was 13). Zone baselines (`results/baselines/chromium`, `detDrift` 0 in all four) are of runs 39916914389 (swipe-v1) and 39924634896 (touch).
  The quarantined share grows because the page now lays out text, which varies run to run; INFERRED, not tested per type.
- Faithful check on one image (MEASURED, Lean-decided): every arm now sits on the font image `47b1dcbe...`. A = the frozen original baseline (runs 39916914389 swipe-v1, 39924634896 touch);
  R (rewrite) and the control A' (a second original) = the three shards of one other run of the same profile and image, 39916917890 (swipe-v1) and 39924639452 (touch), both `target=both`,
  rebuilt with `zone-baseline.mjs` (store entry, then `baseline --profile --target`) into `results/faithful/runs`; `faithful.mjs verdict` and `faithful.mjs lean` regenerated
  `results/faithful/*.verdict.json` and `lean/Fw/Faithful/Measured.lean`. The control A'/A passes on both profiles (swipe-v1 and touch, all three zones), so run-to-run variance of the original on the font image is inside its own bands.
  The rewrite R fails y04000, y04500 and tail on both profiles (as on the font-less image). The earlier mixed-image control FAIL was the image change, as inferred.
  Store note: runs 39916914389 and 39916917890 map to one store key, so A' was pulled into a scratch store (`FW_CONSOLE_DIR=<dir> pnpm -s fw ci <run> --branch ci/counts-font-fidelity`).
- MEASURED, engine-premises (A/B on the font and font-less images): font image run 39909930901 (sha 3783b391d) against the font-less tree run 39912692117
  (branch ci/counts-font-fidelity-nofont). Every row reads the same except Chromium `paint` and `raster` of the main step set: font-less 130 of 130 agree
  (both rows hold), font image 129 of 130 (both rows fail) at step 118, case `margin@own`, act `set`: the model says Paint and RasterTask are absent, all
  three passes observed them. The extra set (paint 13 of 14, raster 12 of 14) fails the same on both images, and WebKit rows all hold. INFERRED cause: with text
  drawn, a moved box repaints its glyphs, which the font-less page did not have; the premise rows were written on the font-less page.
- MEASURED, path-pix on the font image (run 39909931032): Chromium begin-frame, A/A (two loads of one page, must be equal) 28 of 28 E in job 1 and 22 E
  plus 6 L in job 2; P cells 19 E, 9 L (job 1) and 21 E, 7 L (job 2). The font-less lane gave 29 of 29 E and P 28 E, 1 L in all 8 jobs
  (research/notes/2026/10-2x-path-pix.md). The Chromium lane is therefore no longer reproducible between jobs on the font image. Simulator: A/A 0 E,
  19 to 20 L, 6 invalid of 27 in both jobs, P 1 E; same as before (0 E, 21 L, 6 invalid). INFERRED: the 6 L A/A cells of job 2 are text anti-aliasing or a
  timing difference between loads; no repeat was run, so whether job 1 or job 2 is the typical one is open.

## Accepted limits

- The phone was not measured; the Simulator stands in for the phone's fonts and viewport rules (Mac process, Mac fonts: its 6042 equals the phone's 6042).
- Playwright WebKit and the Chromium container disagree with the phone by the hero's viewport-unit height (80 px), not by fonts; the
  fidelity pick is about text, so it does not see that gap.
- Rows are re-measured only where the lane can; the table above names the rest.
