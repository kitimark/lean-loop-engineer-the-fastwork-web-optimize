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

Provenance. Measured at f3ee5ee0 (gate-gaps run 39527779967, branch `ci/image-arm-v2`, 3 reps on 3 separate jobs per engine,
22 probes in 3 shards); decided by `armdecide.mjs` at 0cb6552d (the commit that last changed it; `git diff --stat f3ee5ee0..HEAD`
over the measurement code, which is every file under `packages/gate-breakpoints/src` except `armdecide.mjs` and `trajectory/`,
`packages/visual-diff`, `apps/site`, `gate-gaps.yml` and `ImageArm.lean`, prints nothing). The tables at the end of this note
are the output of that CLI over the artifacts of that run, not edited; every section of them except Coverage is byte-identical
to the run's own `images-decide` artifact (job 118996415162). Every claim below holds at the 22 probe ids of
`arm-probes.json` only (22 of the 124 gate probes; 22 of 68 width x DPR pairs, see Coverage).

## Outcome

Verdict words below are copied from the decision tables (policy `exact` = a 1:1 copy of a plain `<img>` at its snapped device
size; policy `fit` = the control, the largest drawn device size at the file's aspect ratio, which may resample). "Both engines"
means that column; a verdict said of one engine is that engine's column. `lookChange`: some cell fails with the copies where the
original files passed. `shippedFails`: some cell fails with the copies and no failing cell passed with the original files. One
failing cell is enough for either; both are negative. `admissible` needs a cell and every cell passing.

- MEASURED, exact, both engines: **no part is admissible** at the 22 probe ids. `noCopy` in both engines (no file of the
  part has an exact copy at the 22 probe ids in arm-probes.json): hero, hero.deck, hero.exit, hero.orbit, morph.columns,
  morph.panel, people.deck, people.o. `shippedFails` in both engines: people.card (Chromium 46 of 66 cells have a copy, worst 4349 ppm;
  WebKit 35 of 66, 2649 ppm) and people.carousel (46 of 66, 33739 ppm; 35 of 66, 126609 ppm). No exact cell is in the
  "copy fails and the baseline passes" table, so exact has no `lookChange` at the 22 probe ids.
- MEASURED, fit, both engines column: `lookChange` for morph.columns, morph.panel, people.card, people.carousel and
  people.deck; `undecided` for hero.deck, hero.exit and hero.orbit (every cell of theirs is open, `open>open`: the baseline
  never settles); `noCopy` for hero and people.o. Per engine: people.card is `lookChange` in Chromium and `shippedFails` in
  WebKit; people.deck is `shippedFails` in Chromium and `lookChange` in WebKit; morph.columns, morph.panel and people.carousel are
  `lookChange` in both.
- Decoded saving (companion file, section "Decoded saving per part and probe"): exact, the two parts with a copy:
  median 1768 KiB (1.7 MiB) per probe, 864 to 1792 KiB; fit: 6.8 to 182.7 MiB per part and probe (6914.9 to 187105.3 KiB).
  No saving belongs to an admissible part, so each is a bound, not a result to ship.
- Per-part change against run 39520488340 (tip 4e4a44d6, copies JPEG q95 4:4:4, same 22 probes; its `images-decide`
  artifact): of 20 part x engine entries per policy, exact changes one part and fit changes one entry. Exact:
  people.carousel `lookChange` -> `shippedFails` in both engines (and in the both-engines column); people.card `shippedFails`
  unchanged; the other eight parts `noCopy` unchanged; cells with a copy 45 -> 46 (Chromium) and 33 -> 35 (WebKit). Fit:
  people.carousel in WebKit `shippedFails` -> `lookChange` (both-engines column `lookChange` unchanged); every other entry
  unchanged, so no part became admissible when the copies went from JPEG q95 to lossless PNG32. The lossless copy removed the
  encode stage; it moved the exact worst ppm of people.card in WebKit from 17187 to 2649 but the part still fails
  (`shippedFails`: the baseline fails in the same cells).

## How it is built

- Rules in Lean: `lean/Fw/Measure/ImageArm.lean` (snapping, reach, per-part decision `partDecision` and `partDecisionWithCopies`,
  decoded bytes `4*w*h`), 91 golden lines `packages/contracts/golden/gate/image-arm.jsonl`; the TS twins `armplan.mjs` and the
  decision in `armdecide.mjs` are checked against them (`test/images-armplan.test.mjs`, `test/images-armv2.test.mjs`).
- Per probe (width x DPR x input): audit with the probe's environment, group readings by file URL, assign each file to
  parts through the `data-fw` anchors, build copies with ImageMagick over the served URLs in a temporary copy of `dist`:
  lossless PNG32, one Lanczos stage (the decoded source resized to exactly w x h, no lossy encode), then run
  `visual-diff --parts` on the base and on each policy.
- Verdict per cell (part x engine x width x DPR x rep): pixel-lag tolerance ppm <= 2000, delta <= 64, antialiasing not
  excluded. `partDecision` order: lookChange > shippedFails > undecided (any other missing pass: unsettled, invalid, nc, error)
  > admissible (a cell, all cells pass); a part none of whose cells has a copy is `noCopy`. An error row is an error cell, and
  a cell whose copy differs between reps is `nc` per rep (the tables count it as `disputed`).
- The 22 probes (`arm-probes.json`): the upper side of each main width breakpoint at desktop (11, DPR 1) and touch (8, DPR 3 up
  to 481, DPR 2 from 601), two hover/pointer crosses at DPR 2 and the phone landscape (DPR 3).

## Why so few files are reachable (Why table, generated below)

Per probe and engine, files that get an exact copy (`ok`): 0 to 2 of 68 to 118. The rest: `cropped` (25 to 52 per probe),
`notImg` (11 to 41), `format:svg` (20 to 21), `scaled` (a transform scale at some stop, 0 to 8), `disputed` (the reps differ,
0 to 7), `format:avif` (3), `external` (1), `fractional` (0 to 1). A copy is exact only when the file is a plain `<img>`, drawn
at an integral device size, at scale 1, with a saving. All of this is at the 22 probe ids in arm-probes.json.

## The 1:1 question from engine source

Question: is a bitmap drawn at its own pixel size copied untouched, so a copy at the drawn device size is the same pixels?
The text of the answer is the module docstring of `lean/Fw/Measure/ImageArm.lean:12-29@f3ee5ee0`, Q1.

- A draw whose destination rectangle is a whole number of device pixels, at the copy's own pixel size, resamples nothing: the
  browser's second stage vanishes and the page differs from the original only by the copy tool's one stage (the exact copies
  are lossless PNG, so the stage is one Lanczos resize and no encode).
- CONFIRMED (source read): Skia turns a bilinear sample into a nearest one when the matrix is an integer translate
  (`tweak_sampling`, `src/shaders/SkImageShader.cpp:473-484`, called at `:522`, Skia 95ee33d7 = `skia_revision` at `DEPS:340` of
  chromium@f842f52; the CPU raster path). Chromium snaps the destination rectangle of an `<img>` to device pixels and draws it
  with that rectangle (`third_party/blink/renderer/core/paint/image_painter.cc:210,224-235@f842f52`). WebKit snaps with
  `snapRectToDevicePixels` (`Source/WebCore/rendering/RenderImage.cpp:569,693,774-808@862f17d`), and its Skia port, the Linux
  Playwright WebKit, draws with `kLinear` for Default quality
  (`Source/WebCore/platform/graphics/skia/GraphicsContextSkia.cpp:188-201,291,295@862f17d`) into the same shader rule.
  `ImageQualityController.cpp:172-176@862f17d` only picks the quality for an unscaled context at DPR 1 and plays no part for a
  copy at DPR 2 or 3.
- INFERRED (not read): that the float matrix of a WebKit draw at DPR 2 or 3 is an exact integer translate, the GPU raster path,
  and Apple's CoreGraphics (closed source). The CI cells are the evidence for those.
- The snapped size of a rectangle depends on where it sits (`snapSize_position_dependent`), except when its size is a whole
  number of device pixels (`snapSize_shift`): the only size a single copy can match wherever the image is.
  `exact_copy_is_snapped_size` proves the copy then equals the snapped size at every position. So a copy is reachable only for
  an `<img>` that fills its box, under no scale, of whole device-pixel size and smaller than the file; every other image has no
  1:1 copy, its drawn size moves with a transform or the position, and any copy is resampled twice.
- What the cells say, at the 22 probe ids: exact copies exist for 2 files of people.card and people.carousel; in those cells the
  original files fail too (`fail>fail` 25 and 12 in Chromium, 8 and 0 in WebKit; one Chromium people.card cell is `pass>pass`;
  the rest are open or disputed), so the cells do not settle that an exact copy draws like its source. The question of whether the second stage vanishes in
  WebKit at DPR 2 and 3 stays INFERRED for the 22 probe ids.

## Limits (accepted)

- 22 of 124 gate probes: 22 of 68 width x DPR pairs are probed (the 46 unprobed pairs are listed in Coverage), and 24 more
  probes at probed pairs (reduced motion, hover/pointer crosses other than the two, other heights, for example `desk-rm-*`,
  `touch-1200`) are not probed. Every verdict above is at the 22 probe ids.
- Decode memory only; no frame time (as set in the task).
- Linux Playwright WebKit is not CoreGraphics (Safari); no phone claim. GPU raster is not exercised.
- Many baseline cells are open (unsettled or invalid): the hero rows are `undecided` for that reason in the fit policy, not
  because the copies passed; people.deck is `noCopy` under exact (no file has an exact copy).
- `people.carousel` flips between runs (the baseline is noisy): its verdict word is one run's (run 39520488340: exact
  `lookChange`, this run: `shippedFails`).
- A file shared by two parts is copied once for both; the part rows therefore share cells (shared-URL caveat).
- The cells companion `10-21-image-arm-v2-cells.md` (about 1,300 lines) is generated and is not read as prose.
- TS stand-ins (not proved as TS): `imgOf` (reading -> Lean input), `whyFile` (report only), the aggregation in `armdecide.mjs`
  (grouping per policy, engine and part; its cell and part decisions are `armplan.mjs`, checked against the Lean golden).
- Old `pages.mjs`, `verify.mjs`, `arm.mjs` stay as legacy (tests import them).

## Generated tables

Written by `arm decide --splice` over the artifacts of run 39527779967; not edited by hand. One row per cell and rep: `10-21-image-arm-v2-cells.md`.

<!-- arm-tables:begin -->

### Runs (run 39527779967, commit f3ee5ee0)

- chromium r1-s1 (156.0.8078.4): 8 probes
- chromium r1-s2 (156.0.8078.4): 7 probes
- chromium r1-s3 (156.0.8078.4): 7 probes
- chromium r2-s1 (156.0.8078.4): 8 probes
- chromium r2-s2 (156.0.8078.4): 7 probes
- chromium r2-s3 (156.0.8078.4): 7 probes
- chromium r3-s1 (156.0.8078.4): 8 probes
- chromium r3-s2 (156.0.8078.4): 7 probes
- chromium r3-s3 (156.0.8078.4): 7 probes
- playwright-webkit r1-s1 (WebKit 27.2 (playwright-core 1.64.1)): 8 probes
- playwright-webkit r1-s2 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r1-s3 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r2-s1 (WebKit 27.2 (playwright-core 1.64.1)): 8 probes
- playwright-webkit r2-s2 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r2-s3 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r3-s1 (WebKit 27.2 (playwright-core 1.64.1)): 8 probes
- playwright-webkit r3-s2 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes
- playwright-webkit r3-s3 (WebKit 27.2 (playwright-core 1.64.1)): 7 probes

### Coverage (run 39527779967, commit f3ee5ee0)

Probed width x DPR pairs: 22 of 68 in the gate matrix (124 probes). Every verdict below holds at the 22 probe ids of arm-probes.json only; other gate probes at a probed pair (reduced motion, hover/pointer crosses, other heights) are not probed.

- probed: DPR 1: 320 401 481 601 721 861 1031 1101 1201 1280 1512; DPR 2: 601 861 1024 1031 1200 1201 1512; DPR 3: 320 401 481 932
- not probed: DPR 1: 319 400 461 462 480 600 640 641 720 860 960 961 1000 1001 1030 1100 1200 1279 1440 1511; DPR 2: 600 600.5 640 640.5 641 720 721 860 860.5 960 961 1000 1000.5 1001 1030 1100 1101 1279 1280 1511; DPR 3: 319 400 430 461 462 480

### Decision per part, policy exact (run 39527779967, commit f3ee5ee0)

| part | chromium (cells with a copy of all, worst ppm) | playwright-webkit (cells with a copy of all, worst ppm) | both engines |
|---|---|---|---|
| hero | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| hero.deck | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| hero.exit | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| hero.orbit | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| morph.columns | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| morph.panel | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| people.card | shippedFails (46 of 66, 4349) | shippedFails (35 of 66, 2649) | shippedFails |
| people.carousel | shippedFails (46 of 66, 33739) | shippedFails (35 of 66, 126609) | shippedFails |
| people.deck | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| people.o | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |

### Decision per part, policy fit (run 39527779967, commit f3ee5ee0)

| part | chromium (cells with a copy of all, worst ppm) | playwright-webkit (cells with a copy of all, worst ppm) | both engines |
|---|---|---|---|
| hero | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |
| hero.deck | undecided (18 of 66, 2722) | undecided (18 of 66, 18267) | undecided |
| hero.exit | undecided (66 of 66, 10185) | undecided (66 of 66, 38009) | undecided |
| hero.orbit | undecided (48 of 66, 12109) | undecided (48 of 66, 38382) | undecided |
| morph.columns | lookChange (66 of 66, 1239) | lookChange (66 of 66, 24684) | lookChange |
| morph.panel | lookChange (66 of 66, 1125) | lookChange (66 of 66, 22547) | lookChange |
| people.card | lookChange (66 of 66, 27870) | shippedFails (66 of 66, 32499) | lookChange |
| people.carousel | lookChange (66 of 66, 124036) | lookChange (66 of 66, 185489) | lookChange |
| people.deck | shippedFails (66 of 66, 65573) | lookChange (66 of 66, 168244) | lookChange |
| people.o | noCopy (0 of 66, -1) | noCopy (0 of 66, -1) | noCopy |

### What the cells did (run 39527779967, commit f3ee5ee0) (base verdict > drawn verdict; open = unsettled, invalid, nc or error; disputed = the reps did not agree on the file's copy, left out of the columns)

| policy | engine | part | cells with a copy | pass>pass | pass>fail | fail>pass | fail>fail | pass>open | fail>open | open>pass | open>fail | open>open | disputed | error | mean saving KiB per cell |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| exact | chromium | people.card | 46 | 1 | 0 | 0 | 25 | 0 | 0 | 0 | 0 | 0 | 20 | 0 | 1700.3 |
| exact | chromium | people.carousel | 46 | 0 | 0 | 0 | 12 | 1 | 0 | 0 | 0 | 13 | 20 | 0 | 1700.3 |
| exact | playwright-webkit | people.card | 35 | 0 | 0 | 0 | 8 | 0 | 0 | 0 | 0 | 0 | 27 | 0 | 1442.0 |
| exact | playwright-webkit | people.carousel | 35 | 0 | 0 | 0 | 0 | 0 | 1 | 0 | 1 | 6 | 27 | 0 | 1442.0 |
| fit | chromium | hero.deck | 18 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 18 | 0 | 0 | 15418.4 |
| fit | chromium | hero.exit | 66 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 66 | 0 | 0 | 36682.0 |
| fit | chromium | hero.orbit | 48 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 48 | 0 | 0 | 44655.9 |
| fit | chromium | morph.columns | 66 | 34 | 11 | 6 | 15 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 41169.2 |
| fit | chromium | morph.panel | 66 | 34 | 11 | 7 | 14 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 41169.2 |
| fit | chromium | people.card | 66 | 0 | 3 | 0 | 39 | 0 | 0 | 0 | 0 | 24 | 0 | 0 | 94859.9 |
| fit | chromium | people.carousel | 66 | 5 | 4 | 4 | 17 | 2 | 3 | 4 | 0 | 27 | 0 | 0 | 7101.8 |
| fit | chromium | people.deck | 66 | 0 | 0 | 0 | 3 | 0 | 0 | 0 | 0 | 63 | 0 | 0 | 91951.0 |
| fit | playwright-webkit | hero.deck | 18 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 18 | 0 | 0 | 15417.8 |
| fit | playwright-webkit | hero.exit | 66 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 66 | 0 | 0 | 34063.9 |
| fit | playwright-webkit | hero.orbit | 48 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 48 | 0 | 0 | 41056.2 |
| fit | playwright-webkit | morph.columns | 66 | 21 | 45 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 41169.5 |
| fit | playwright-webkit | morph.panel | 66 | 27 | 39 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 41169.5 |
| fit | playwright-webkit | people.card | 66 | 0 | 0 | 0 | 66 | 0 | 0 | 0 | 0 | 0 | 0 | 0 | 93937.4 |
| fit | playwright-webkit | people.carousel | 66 | 0 | 2 | 0 | 1 | 1 | 13 | 1 | 16 | 32 | 0 | 0 | 7108.7 |
| fit | playwright-webkit | people.deck | 66 | 3 | 3 | 0 | 33 | 0 | 0 | 0 | 0 | 27 | 0 | 0 | 90908.0 |

### Cells where the copy fails and the baseline passes (run 39527779967, commit f3ee5ee0) (reps with that / reps with a copy; per rep: base>drawn initials, drawn ppm / delta, ~ = disputed)

| policy | engine | probe | width@dpr | part | reps | per rep | files |
|---|---|---|---|---|---|---|---|
| fit | chromium | desk-1031 | 1031@1 | morph.columns | 1/3 | p>p 403/53, p>f 806/102, p>p 113/51 | 21 |
| fit | chromium | desk-1031 | 1031@1 | morph.panel | 1/3 | p>p 375/52, p>f 683/106, p>p 34/39 | 21 |
| fit | chromium | desk-1031 | 1031@1 | people.carousel | 2/3 | p>f 5750/200, p>f 5493/200, u>p 0/0 | 6 |
| fit | chromium | desk-1101 | 1101@1 | morph.columns | 1/3 | p>p 820/51, p>f 1013/103, f>f 997/103 | 21 |
| fit | chromium | desk-1101 | 1101@1 | morph.panel | 1/3 | p>p 461/52, p>f 751/104, f>f 700/104 | 21 |
| fit | chromium | desk-1201 | 1201@1 | morph.columns | 1/3 | p>f 1174/103, f>f 1142/103, p>p 96/59 | 21 |
| fit | chromium | desk-1201 | 1201@1 | morph.panel | 1/3 | p>f 819/104, f>f 939/104, p>p 0/0 | 21 |
| fit | chromium | desk-861 | 861@1 | morph.columns | 2/3 | p>f 1051/106, p>f 1109/106, p>p 272/51 | 21 |
| fit | chromium | desk-861 | 861@1 | morph.panel | 2/3 | p>f 640/101, p>f 702/101, p>p 103/51 | 21 |
| fit | chromium | desk-861 | 861@1 | people.carousel | 1/3 | f>p 0/0, f>p 0/0, p>f 8933/203 | 6 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | 1/3 | f>f 394/201, f>f 32/102, p>f 483/201 | 16 |
| fit | chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | 1/3 | f>f 234/203, f>f 21/92, p>f 324/203 | 16 |
| fit | chromium | touch-1031 | 1031@2 | morph.columns | 1/3 | p>f 117/84, f>f 185/183, f>f 60/101 | 17 |
| fit | chromium | touch-1031 | 1031@2 | morph.panel | 1/3 | p>f 90/84, f>f 218/183, f>f 51/101 | 17 |
| fit | chromium | touch-1201 | 1201@2 | morph.columns | 1/3 | f>f 362/201, p>p 165/44, p>f 257/84 | 16 |
| fit | chromium | touch-1201 | 1201@2 | morph.panel | 1/3 | f>f 205/203, p>p 4/31, p>f 55/84 | 16 |
| fit | chromium | touch-1512 | 1512@2 | morph.columns | 1/3 | f>p 366/58, p>f 543/185, f>f 306/201 | 16 |
| fit | chromium | touch-1512 | 1512@2 | morph.panel | 1/3 | f>p 21/33, p>f 68/147, f>f 209/210 | 16 |
| fit | chromium | touch-1512 | 1512@2 | people.carousel | 1/3 | f>f 12358/173, u>u 115/46, p>f 61725/244 | 6 |
| fit | chromium | touch-320 | 320@3 | people.card | 3/3 | p>f 9956/125, p>f 9954/125, p>f 9954/125 | 13 |
| fit | chromium | touch-481 | 481@3 | morph.columns | 1/3 | f>p 0/0, f>p 5/29, p>f 24/151 | 8 |
| fit | chromium | touch-481 | 481@3 | morph.panel | 1/3 | f>p 0/0, f>p 5/29, p>f 26/151 | 8 |
| fit | chromium | touch-601 | 601@2 | morph.columns | 1/3 | f>f 457/139, p>p 207/37, p>f 336/77 | 9 |
| fit | chromium | touch-601 | 601@2 | morph.panel | 1/3 | f>f 411/136, p>p 0/0, p>f 219/75 | 9 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.columns | 3/3 | p>f 23654/100, p>f 20012/103, p>f 20012/103 | 21 |
| fit | playwright-webkit | desk-1031 | 1031@1 | morph.panel | 3/3 | p>f 22547/89, p>f 17836/90, p>f 17836/90 | 21 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.columns | 3/3 | p>f 24684/104, p>f 24009/101, p>f 24459/116 | 21 |
| fit | playwright-webkit | desk-1101 | 1101@1 | morph.panel | 3/3 | p>f 20993/92, p>f 20157/95, p>f 20601/96 | 21 |
| fit | playwright-webkit | desk-1101 | 1101@1 | people.carousel | 1/3 | f>u 75922/255, u>f 67038/218, p>f 23921/255 | 6 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.columns | 3/3 | p>f 9600/82, p>f 9600/82, p>f 9600/82 | 21 |
| fit | playwright-webkit | desk-1201 | 1201@1 | morph.panel | 3/3 | p>f 7049/75, p>f 7049/75, p>f 7049/75 | 21 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.columns | 3/3 | p>f 22375/99, p>f 21570/105, p>f 22246/99 | 21 |
| fit | playwright-webkit | desk-1280 | 1280@1 | morph.panel | 3/3 | p>f 17902/92, p>f 17220/87, p>f 17936/92 | 21 |
| fit | playwright-webkit | desk-1512 | 1512@1 | morph.columns | 3/3 | p>f 4749/80, p>f 4749/80, p>f 4749/80 | 21 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.columns | 3/3 | p>f 23661/111, p>f 22625/107, p>f 23661/111 | 13 |
| fit | playwright-webkit | desk-601 | 601@1 | morph.panel | 3/3 | p>f 12724/101, p>f 12102/103, p>f 12724/101 | 13 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.columns | 3/3 | p>f 11114/76, p>f 20155/89, p>f 10407/77 | 21 |
| fit | playwright-webkit | desk-721 | 721@1 | morph.panel | 3/3 | p>f 7977/93, p>f 13362/99, p>f 7130/91 | 21 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.columns | 3/3 | p>f 22588/101, p>f 11985/84, p>f 21674/101 | 21 |
| fit | playwright-webkit | desk-861 | 861@1 | morph.panel | 3/3 | p>f 16336/90, p>f 9004/82, p>f 16377/90 | 21 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.columns | 3/3 | p>f 6146/126, p>f 6146/126, p>f 6146/126 | 17 |
| fit | playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | morph.panel | 3/3 | p>f 3018/99, p>f 3018/99, p>f 3018/99 | 17 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.columns | 3/3 | p>f 15139/112, p>f 15139/112, p>f 15139/112 | 16 |
| fit | playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | morph.panel | 3/3 | p>f 10835/97, p>f 10835/97, p>f 10835/97 | 16 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.columns | 3/3 | p>f 15646/110, p>f 15646/110, p>f 15646/110 | 17 |
| fit | playwright-webkit | touch-1031 | 1031@2 | morph.panel | 3/3 | p>f 12600/99, p>f 12600/99, p>f 12600/99 | 17 |
| fit | playwright-webkit | touch-1031 | 1031@2 | people.deck | 3/3 | p>f 5375/85, p>f 2194/70, p>f 2433/70 | 8 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.columns | 3/3 | p>f 15148/114, p>f 15148/114, p>f 15148/114 | 16 |
| fit | playwright-webkit | touch-1201 | 1201@2 | morph.panel | 3/3 | p>f 10744/97, p>f 10744/97, p>f 10744/97 | 16 |
| fit | playwright-webkit | touch-1512 | 1512@2 | morph.columns | 3/3 | p>f 5739/115, p>f 5739/115, p>f 5739/115 | 16 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.columns | 3/3 | p>f 15492/120, p>f 15492/120, p>f 15492/120 | 9 |
| fit | playwright-webkit | touch-601 | 601@2 | morph.panel | 3/3 | p>f 8492/118, p>f 8492/118, p>f 8492/118 | 9 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.columns | 3/3 | p>f 16859/120, p>f 16859/120, p>f 16859/120 | 21 |
| fit | playwright-webkit | touch-861 | 861@2 | morph.panel | 3/3 | p>f 11250/108, p>f 11250/108, p>f 11250/108 | 21 |
| fit | playwright-webkit | touch-861 | 861@2 | people.carousel | 1/3 | p>u 71868/227, u>f 78606/234, p>f 1224/72 | 6 |

### Why a file has no exact copy (run 39527779967, commit f3ee5ee0) (files per engine and probe; all reps together, `disputed` = the reps differ)

| engine | probe | width@dpr | ok | cropped | disputed | external | format:avif | format:svg | fractional | notImg | scaled |
|---|---|---|---|---|---|---|---|---|---|---|---|
| chromium | desk-1031 | 1031@1 | 0 | 49 | 1 | 1 | 3 | 21 | 0 | 41 | 2 |
| chromium | desk-1101 | 1101@1 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| chromium | desk-1201 | 1201@1 | 0 | 49 | 1 | 1 | 3 | 21 | 0 | 41 | 2 |
| chromium | desk-1280 | 1280@1 | 0 | 49 | 1 | 1 | 3 | 21 | 0 | 41 | 2 |
| chromium | desk-1512 | 1512@1 | 1 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 0 |
| chromium | desk-320 | 320@1 | 2 | 25 | 2 | 1 | 3 | 20 | 0 | 11 | 4 |
| chromium | desk-401 | 401@1 | 2 | 26 | 0 | 1 | 3 | 20 | 1 | 11 | 4 |
| chromium | desk-481 | 481@1 | 2 | 26 | 0 | 1 | 3 | 20 | 0 | 11 | 5 |
| chromium | desk-601 | 601@1 | 2 | 40 | 2 | 1 | 3 | 20 | 0 | 11 | 1 |
| chromium | desk-721 | 721@1 | 2 | 52 | 0 | 1 | 3 | 20 | 0 | 11 | 2 |
| chromium | desk-861 | 861@1 | 0 | 51 | 1 | 1 | 3 | 20 | 0 | 34 | 1 |
| chromium | hover-pointer-cross-1024x768-none-fine | 1024@2 | 0 | 49 | 1 | 1 | 3 | 20 | 0 | 34 | 1 |
| chromium | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| chromium | phone-landscape-no-preference | 932@3 | 0 | 48 | 3 | 1 | 3 | 20 | 0 | 12 | 3 |
| chromium | touch-1031 | 1031@2 | 1 | 50 | 1 | 1 | 3 | 20 | 0 | 11 | 2 |
| chromium | touch-1201 | 1201@2 | 0 | 50 | 0 | 1 | 3 | 21 | 0 | 41 | 2 |
| chromium | touch-1512 | 1512@2 | 1 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 0 |
| chromium | touch-320 | 320@3 | 2 | 25 | 2 | 1 | 3 | 20 | 0 | 11 | 4 |
| chromium | touch-401 | 401@3 | 2 | 26 | 0 | 1 | 3 | 20 | 0 | 11 | 5 |
| chromium | touch-481 | 481@3 | 2 | 26 | 2 | 1 | 3 | 20 | 0 | 11 | 3 |
| chromium | touch-601 | 601@2 | 2 | 40 | 1 | 1 | 3 | 20 | 0 | 11 | 2 |
| chromium | touch-861 | 861@2 | 2 | 50 | 0 | 1 | 3 | 20 | 0 | 11 | 2 |
| playwright-webkit | desk-1031 | 1031@1 | 0 | 50 | 1 | 1 | 3 | 21 | 0 | 41 | 1 |
| playwright-webkit | desk-1101 | 1101@1 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| playwright-webkit | desk-1201 | 1201@1 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| playwright-webkit | desk-1280 | 1280@1 | 0 | 49 | 2 | 1 | 3 | 21 | 0 | 41 | 1 |
| playwright-webkit | desk-1512 | 1512@1 | 1 | 43 | 1 | 1 | 3 | 21 | 0 | 41 | 7 |
| playwright-webkit | desk-320 | 320@1 | 0 | 25 | 4 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | desk-401 | 401@1 | 2 | 26 | 1 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | desk-481 | 481@1 | 0 | 25 | 3 | 1 | 3 | 20 | 0 | 12 | 5 |
| playwright-webkit | desk-601 | 601@1 | 1 | 40 | 3 | 1 | 3 | 20 | 0 | 12 | 1 |
| playwright-webkit | desk-721 | 721@1 | 0 | 48 | 7 | 1 | 3 | 20 | 0 | 12 | 1 |
| playwright-webkit | desk-861 | 861@1 | 0 | 51 | 1 | 1 | 3 | 20 | 0 | 34 | 1 |
| playwright-webkit | hover-pointer-cross-1024x768-none-fine | 1024@2 | 0 | 44 | 3 | 1 | 3 | 20 | 0 | 12 | 7 |
| playwright-webkit | hover-pointer-cross-1200x900-hover-coarse | 1200@2 | 0 | 43 | 2 | 1 | 3 | 21 | 0 | 41 | 7 |
| playwright-webkit | phone-landscape-no-preference | 932@3 | 1 | 44 | 2 | 1 | 3 | 20 | 0 | 13 | 7 |
| playwright-webkit | touch-1031 | 1031@2 | 0 | 43 | 4 | 1 | 3 | 20 | 0 | 12 | 7 |
| playwright-webkit | touch-1201 | 1201@2 | 0 | 43 | 2 | 1 | 3 | 21 | 0 | 41 | 7 |
| playwright-webkit | touch-1512 | 1512@2 | 1 | 43 | 0 | 1 | 3 | 21 | 0 | 41 | 8 |
| playwright-webkit | touch-320 | 320@3 | 1 | 25 | 3 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | touch-401 | 401@3 | 0 | 28 | 3 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | touch-481 | 481@3 | 0 | 25 | 4 | 1 | 3 | 20 | 0 | 12 | 4 |
| playwright-webkit | touch-601 | 601@2 | 2 | 34 | 3 | 1 | 3 | 20 | 0 | 12 | 6 |
| playwright-webkit | touch-861 | 861@2 | 0 | 43 | 4 | 1 | 3 | 20 | 0 | 12 | 7 |

<!-- arm-tables:end -->
