---
id: 2026-10-21-image-arm-v2
kind: note
title: "Image arm v2: copies at the drawn device size, per-part verdicts decided in Lean, the decoded memory they save, and the 1:1 question from engine source"
status: draft
created: 2026-10-21
authors: [agent:measure-engineer]
topics: [images, webkit, chromium, measurement, lag]
---

# Image arm v2 (2026-10-21)

Question: can a part's images be served at the size they are drawn (device pixels) with no visible change, and how much
decoded memory does that save? Scope limit (accepted): decode memory only, no frame time.

## Outcome

- MEASURED: with the exact policy (a 1:1 copy of a plain `<img>` at its snapped device size) **no part is admissible**.
  Only `people.card` and `people.carousel` have a file that qualifies; `people.card` fails its own baseline in most
  cells (shippedFails), `people.carousel` shows copy failures where the baseline passes (lookChange).
  The other eight parts have no file that a 1:1 copy can reach (noCopy).
- MEASURED: the control policy (fit: the largest drawn device size at the file's aspect ratio, which may resample) changes the
  look in `morph.columns`, `morph.panel` (both engines), `people.card` (Chromium), `people.carousel`, `people.deck`; the hero
  parts stay undecided (their baseline never settles, 18 to 66 cells each, all open).
- The decoded saving per cell is large (exact: median 1.7 MiB per probe; fit: 7 to 183 MiB per part and probe) but belongs
  to no admissible part, so it is a bound, not a result to ship.

Runs (gate-gaps, branch `ci/image-arm-v2`, 3 reps on 3 separate jobs per engine, 22 probes in 3 shards):
final tip 4e4a44d6 = run 39520488340 (success); the previous tip's run 39506658971 (success) agrees on every part except
`people.carousel`, exact: shippedFails there, lookChange in the final run (a noisy baseline: some cells pass in one run and
fail in the other). A run on 39513157760 lost one runner job and was cancelled.

## How it is built

- Rules in Lean: `lean/Fw/Measure/ImageArm.lean` (snapping, reach, policies, per-part decision, decoded bytes `4*w*h`),
  75 golden lines `packages/contracts/golden/gate/image-arm.jsonl`; the TS twin `armplan.mjs` is checked against them
  (`packages/gate-breakpoints/test/images-armplan.test.mjs`).
- Per probe (width x DPR x input): audit with the probe's environment, group readings by file URL, assign each file to
  parts through the `data-fw` anchors, build copies with ImageMagick (Lanczos, JPEG q95 4:4:4) over the served URLs in a
  temporary copy of `dist`, run `visual-diff --parts` on the base and on each policy.
- Verdict per cell (part x engine x width x DPR x rep): pixel-lag tolerance ppm <= 2000, delta <= 64, antialiasing not
  excluded. `partDecision` order: lookChange (a copy fails where the baseline passes) > shippedFails (the baseline itself fails)
  > undecided (any cell open) > admissible (all cells pass, with a copy in every cell).
- Probes: the upper side of each main width breakpoint at desktop and touch, two hover/pointer crosses, phone landscape.

## Why so few files are reachable (why-table, CI artifact `images-decide`)

Per probe, files that get an exact copy: 0 to 4 of about 100. The rest: `cropped` (object-fit or an overflow clip, 25 to 52
per probe), `notImg` (backgrounds, 11 to 41), `format:svg` (20), `scaled` (a transform scale at some stop, 0 to 8),
`format:avif`/`external` (3/1), `fractional` (0 to 1). A copy is exact only when the file is a plain `<img>`, drawn at an
integral device size, at scale 1.

## The 1:1 question from engine source

Question: is a bitmap drawn at its own pixel size copied untouched, so a copy at the drawn device size is the same pixels?

- Chromium (chromium@f842f52): `ImagePainter` snaps the destination rect to whole pixels,
  `third_party/blink/renderer/core/paint/image_painter.cc:210` (`ToPixelSnappedRect(dest_rect)`), and sets the image rendering
  quality from style only (`:250-252`). There is no 1:1 branch in the paint step. CONFIRMED (source read). The Skia sampling step
  below it is not in our sparse clone; that integer-translation draws sample like nearest is INFERRED from Skia and is not read.
- WebKit (WebKit@862f17d): `RenderImage.cpp:693` and `:569` snap the content rect with `snapRectToDevicePixels`;
  `ImageQualityController::chooseInterpolationQuality` has an explicit branch for the 1:1 case,
  `Source/WebCore/rendering/ImageQualityController.cpp:176` (`size == imageSize && !contextIsScaled` -> `Default`). It returns
  the default quality, not "no filter", so the shortcut is a choice of quality, not a copy. CONFIRMED (source).
- Answer: the engines place the image on a snapped rectangle. A copy made at the snapped size matches the original only when
  the original is drawn without scaling, which is what the reach rule requires. The CI result agrees: where both exist, the
  baseline and the exact copy differ only in a few cells (`people.carousel`), and `people.card` fails its own baseline in 32 of 45 Chromium cells and 33 of 33 WebKit cells.
  The engine step (CoreGraphics in Safari) is not exercised: Playwright WebKit on Linux is a different graphics build.
  The Lean twin gives the snapped sizes (`snapSize_shift`, `exact_copy_is_snapped_size`).

## Accepted limits and stand-ins

- Decode memory only; no frame time (as set in the task).
- Linux Playwright WebKit is not Safari's CoreGraphics build; no phone claim.
- Many baseline cells are open (unsettled or invalid): the hero and `people.deck` rows are undecided for that reason, not
  because the copies passed.
- A file shared by two parts is copied once for both; the part rows therefore share cells (shared-URL caveat).
- TS stand-ins (not proved): `imgOf` (reading -> Lean input), `whyFile` (report only), the aggregation in `armdecide.mjs`
  (grouping per policy/engine/part; the decision itself is `armplan.partDecision`, twin of Lean).
- Old `pages.mjs`, `verify.mjs`, `arm.mjs` stay as legacy (tests import them).
