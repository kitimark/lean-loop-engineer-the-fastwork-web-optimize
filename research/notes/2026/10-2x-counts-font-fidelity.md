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
- Ledger (`research/findings/ledger.json`): 37 of its 53 entries cite a CI run older than the first fonts run (39900399252), so their Chromium
  counts figures come from the font-less image unless they are WebKit, gate or pixel results. Entries: 2, 4, 6, 8, 9, 11, 12, 14, 21,
  26 to 53 (26 to 53 all). INFERRED: I did not read each entry's run to tell Chromium counts from other lanes; read an entry's
  `evidence` run ids before relying on its Chromium number, and prefer its WebKit verdict.

## Re-measure on the pick image

- Pick image = the lane image of counts-lane-fonts (`fonts-liberation 1:1.07.4-11`), unchanged by this task.
- NOT DELIVERED here: the refreeze of `classes.frozen.json` and the zone baselines. Lean's freeze needs >= 3 workflow runs that used one image
  id (`Fw.Measure.Freeze.freezeTables`, `minRuns` 3, "mixed image digests" refuses). The workflow pins one image across runs through the
  dispatch input `image_run`; `fw run` does not send it (`Fw.Store.Layout.dispatchInputs`: "`image_run` keeps its default") and
  `gh workflow run` is refused in the agent sandbox, so a push or `fw run` would build a new image per run. The lead dispatches:
  for each profile (`swipe-v1`, `swipe-touch-v1`) one run with target both (first run builds the image), then two with `image_run=<first run>`, then
  `gh run download <id> --dir runs/<id> --pattern 'chromium-c*'`, `node packages/measure-chromium/src/freeze.mjs runs/<three ids> --built-by <first run> --out packages/measure-chromium/classes.frozen.json`,
  and `node packages/measure-chromium/src/zone-baseline.mjs baseline --out results/baselines/chromium`
  (`pnpm --filter @fw/measure-chromium test` fails until both are regenerated).

## Accepted limits

- The phone was not measured; the Simulator stands in for the phone's fonts and viewport rules (Mac process, Mac fonts: its 6042 equals the phone's 6042).
- Playwright WebKit and the Chromium container disagree with the phone by the hero's viewport-unit height (80 px), not by fonts; the
  fidelity pick is about text, so it does not see that gap.
- Rows are re-measured only where the lane can; the table above names the rest.
