---
id: 2026-10-20-image-audit
kind: note
title: "Image audit: natural against drawn size in the hero, morph and people regions, what WebKit does with them, and a drawn-size arm"
status: draft
created: 2026-10-20
authors: [agent:measure-engineer]
topics: [images, webkit, measurement, lag]
---

# Image audit (2026-10-20)

User question: do unoptimized images cause the Safari lag (hero cards leaving, end of the page)? This note answers with
a measured table, the WebKit source on decoding and repainting, a Lean cost term, and an arm that serves images at drawn size.
It claims no frame time: nothing here was timed.

**Outcome.** (1) The ranked tables for both lag regions are MEASURED (run 39481653302). (2) The WebKit decode and resample facts are
cited, each premise with its status: two premises are INFERRED, P-resample and P-repaint, and a frame cost needs both. (3) The
premise that a drawn-size arm renders **visually identical** is **refuted** (MEASURED negative finding, "The drawn-size arm" below);
the arm is closed in this note and in `research/findings/ledger.json`, and its re-plan is **task image-arm-v2**, not this task.
No image file outside `snapshot/` is in this branch: the 102 resized copies of the first rounds are not in its history.

**Units.** Sizes in the tables and the arm section are binary: MiB = 2^20 bytes, KiB = 2^10 bytes (the generator, `reduce.mjs`
`mb` and `kb`, divides by 1048576 and 1024). The landed lag-source note's decimal MB are converted where they are compared.

## Results

**Run ids.** Tables and totals: run `39481653302` (workflow gate-gaps, branch `ci/image-audit`, head 93a0cada: audit, pages and
verify jobs, 3 reps each, both engines); the same tables came out of run `39476108407` (3 reps; the ranks and every waste ratio agree
to 0.1). Every row below is the union of 3 WebKit reps (playwright-webkit 27.2 on a Linux runner, so not Safari's CoreGraphics build;
D1-D6 and R1-R4 are read from source, not measured here). The audit loads the page at 39 cells (13 widths x DPR 1, 2, 3), scrolls the
page, sets `--morph` to 1 for the end-of-page state (the tween is driven only by wheel and touch, so the audit writes it itself), and
reads every `img` and `background-image` with its natural size, drawn box, DPR and the effects on its ancestors. **Waste** = natural
pixels / drawn device pixels (1.0 = exact; below 1 the image is drawn upscaled). **Decoded MiB** = natural w*h*4 (what the file costs once
decoded in full; D4 says an asynchronous decode of a large image can be smaller). **Effects:** B backdrop-filter, F filter, O opacity
below 1, T transform, Ta an animated transform, M mask; the column holds those seen on an ancestor at 1512@2 or 430@3.

**Region A, hero cards leaving (playwright-webkit, site as shipped, run 39481653302)**: 21 files (21 drawn in some cell), 1.78 MiB on disk, 46.63 MiB decoded (natural pixels x 4)

| # | file | natural | fmt | KiB | decoded MiB | drawn px at 1512@2 | drawn px at 430@3 | waste x at 1512@1 / @2 / @3 | at 430@1 / @3 | waste x range over all cells (cells drawn) | effects above it |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | hero/peter-cover.jpg | 1200x2133 | jpeg | 343 | 9.76 | 382x679 | - | 39.4 / 9.9 / 4.4 | - / - | 4.4 (w1512@3) to 39.4 (w1512@1) (26) | O T |
| 2 | hero/nam-cover.jpg | 1200x1866 | jpeg | 379 | 8.54 | 456x709 | - | 27.7 / 6.9 / 3.1 | - / - | 3.1 (w1512@3) to 27.7 (w1512@1) (26) | O T |
| 3 | hero/leobeer-cover.jpg | 1200x1148 | jpeg | 207 | 5.26 | 382x365 | 354x339 | 39.4 / 9.9 / 4.4 | 103.3 / 11.5 | 4.4 (w1512@3) to 103.3 (w430@1) (39) | O T |
| 4 | hero/weng-cover.jpg | 1090x994 | jpeg | 56 | 4.13 | 529x482 | 365x333 | 16.9 / 4.2 / 1.9 | 80.0 / 8.9 | 1.9 (w1512@3) to 80.0 (w430@1) (39) | O T |
| 5 | hero/pakincht-cover.jpg | 956x1194 | jpeg | 311 | 4.35 | 424x530 | - | 20.3 / 5.1 / 2.3 | - / - | 2.3 (w1512@3) to 20.3 (w1512@1) (26) | O T |
| 6 | hero/mod-cover.jpg | 741x1047 | jpeg | 75 | 2.96 | 376x531 | 477x674 | 15.5 / 3.9 / 1.7 | 21.7 / 2.4 | 1.7 (w1512@3) to 21.7 (w430@1) (39) | O T |
| 7 | sellers/ux-ui-designer/avatar.jpg | 640x640 | jpeg | 66 | 1.56 | 88x88 | 90x90 | 202.3 / 52.9 / 23.5 | 455.1 / 50.6 | 23.5 (w1512@3) to 455.1 (w430@1) (39) | O T |
| 8 | hero/buttercup-cover.jpg | 656x656 | jpeg | 46 | 1.64 | 382x382 | - | 11.8 / 2.9 / 1.3 | - / - | 1.3 (w1512@3) to 11.8 (w1512@1) (26) | O T |
| 9 | hero/chapavich-cover.jpg | 656x656 | jpeg | 44 | 1.64 | 386x386 | - | 11.6 / 2.9 / 1.3 | - / - | 1.3 (w1512@3) to 11.6 (w1512@1) (26) | O T |
| 10 | hero/slayalldeep-cover.jpg | 656x656 | jpeg | 76 | 1.64 | 402x402 | - | 10.7 / 2.7 / 1.2 | - / - | 1.2 (w1512@3) to 10.7 (w1512@1) (26) | O T |
| 11 | sellers/ai-video-editor/avatar.jpg | 480x480 | jpeg | 28 | 0.88 | 72x72 | 66x66 | 177.8 / 44.4 / 20.9 | 522.4 / 52.9 | 20.9 (w1512@3) to 522.4 (w430@1) (39) | O T |
| 12 | hero/bold-cover.jpg | 656x656 | jpeg | 75 | 1.64 | 472x472 | 477x477 | 7.7 / 1.9 / 0.9 | 17.0 / 1.9 | 0.9 (w1512@3) to 17.0 (w430@1) (39) | O T |
| 13 | hero/peter-avatar.jpg | 320x480 | jpeg | 31 | 0.59 | 72x108 | - | 79.0 / 19.8 / 9.3 | - / - | 9.3 (w1512@3) to 79.0 (w1512@1) (26) | O T |
| 14 | hero/nam-avatar.jpg | 320x427 | jpeg | 18 | 0.52 | 84x112 | - | 55.7 / 14.5 / 6.5 | - / - | 6.5 (w1512@3) to 55.7 (w1512@1) (26) | O T |
| 15 | hero/weng-avatar.jpg | 320x322 | jpeg | 19 | 0.39 | 96x97 | 66x66 | 42.9 / 11.1 / 4.9 | 233.7 / 23.7 | 4.9 (w1512@3) to 233.7 (w430@1) (39) | O T |
| 16 | hero/slayalldeep-avatar.jpg | 320x322 | jpeg | 16 | 0.39 | 74x74 | - | 71.4 / 18.8 / 8.3 | - / - | 8.3 (w1512@3) to 71.4 (w1512@1) (26) | O T |
| 17 | hero/mod-avatar.jpg | 300x300 | jpeg | 11 | 0.34 | 70x70 | 90x90 | 73.5 / 18.4 / 8.2 | 100.0 / 11.1 | 8.2 (w1512@3) to 100.0 (w430@1) (39) | O T |
| 18 | hero/buttercup-avatar.jpg | 250x250 | jpeg | 8 | 0.24 | 72x72 | - | 48.2 / 12.1 / 5.7 | - / - | 5.7 (w1512@3) to 48.2 (w1512@1) (26) | O T |
| 19 | hero/pakincht-avatar.jpg | 150x150 | jpeg | 4 | 0.09 | 78x78 | - | 14.1 / 3.7 / 1.6 | - / - | 1.6 (w1512@3) to 14.1 (w1512@1) (26) | O T |
| 20 | hero/chapavich-avatar.jpg | 113x113 | jpeg | 4 | 0.05 | 72x72 | - | 9.9 / 2.5 / 1.1 | - / - | 1.1 (w1512@3) to 9.9 (w1512@1) (26) | O T |
| 21 | profile/online.svg | 15x15 | svg | 0 | 0.00 | 26x26 | 24x24 | 1.3 / 0.3 / 0.1 | 3.5 / 0.4 | 0.1 (w1512@3) to 3.5 (w430@1) (39) | O T |

**Region B, end-of-page morph (end state, run 39481653302)**: 21 files (21 drawn in some cell), 5.44 MiB on disk, 58.80 MiB decoded (natural pixels x 4)

| # | file | natural | fmt | KiB | decoded MiB | drawn px at 1512@2 | drawn px at 430@3 | waste x at 1512@1 / @2 / @3 | at 430@1 / @3 | waste x range over all cells (cells drawn) | effects above it |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | roles/architect.png | 1282x1282 | png | 317 | 6.27 | 574x574 | 672x672 | 20.0 / 5.0 / 2.2 | 32.8 / 3.6 | 2.2 (w1512@3) to 32.8 (w430@1) (39) | B F O T Ta |
| 2 | roles/graphic-designer.png | 1282x1282 | png | 429 | 6.27 | 698x698 | 1047x1047 | 13.5 / 3.4 / 1.5 | 13.5 / 1.5 | 1.5 (w1512@3) to 13.5 (w1512@1) (39) | B F O T Ta |
| 3 | roles/software-engineer.png | 1282x1282 | png | 396 | 6.27 | 720x720 | - | 12.7 / 3.2 / 1.4 | - / - | 1.4 (w1512@3) to 12.7 (w1512@1) (24) | B F O T Ta |
| 4 | roles/project-manager.png | 1282x1281 | png | 328 | 6.26 | 721x720 | - | 12.7 / 3.2 / 1.4 | - / - | 1.4 (w1512@3) to 12.7 (w1512@1) (24) | B F O T Ta |
| 5 | roles/web-developer.png | 1282x1281 | png | 357 | 6.26 | 721x720 | - | 12.7 / 3.2 / 1.4 | - / - | 1.4 (w1512@3) to 12.7 (w1512@1) (24) | B F O T Ta |
| 6 | media/post-4.jpg | 819x1024 | jpeg | 145 | 3.20 | 576x720 | 864x1080 | 8.1 / 2.0 / 0.9 | 8.1 / 0.9 | 0.9 (w1512@3) to 8.1 (w1512@1) (39) | B F O T Ta |
| 7 | work/work-a.jpg | 736x920 | jpeg | 126 | 2.58 | 574x718 | 509x636 | 6.6 / 1.6 / 0.7 | 18.8 / 2.1 | 0.7 (w1512@3) to 18.8 (w430@1) (39) | B F O T Ta |
| 8 | work/work-e.jpg | 736x1042 | jpeg | 134 | 2.93 | 574x813 | - | 6.6 / 1.6 / 0.7 | - / - | 0.7 (w1512@3) to 6.6 (w1512@1) (24) | B F O T Ta |
| 9 | media/cover-cafe.jpg | 960x539 | jpeg | 392 | 1.97 | 755x424 | 1133x636 | 6.5 / 1.6 / 0.7 | 6.5 / 0.7 | 0.7 (w1512@3) to 6.5 (w1512@1) (39) | B F O T Ta |
| 10 | work/work-c.jpg | 735x893 | jpeg | 84 | 2.50 | 649x788 | 973x1182 | 5.1 / 1.3 / 0.6 | 5.1 / 0.6 | 0.6 (w1512@3) to 5.1 (w1512@1) (39) | B F O T Ta |
| 11 | work/work-f.jpg | 600x848 | jpeg | 90 | 1.94 | 590x834 | - | 4.1 / 1.0 / 0.5 | - / - | 0.5 (w1512@3) to 4.1 (w1512@1) (24) | B F O T Ta |
| 12 | media/post-5.jpg | 735x893 | jpeg | 84 | 2.50 | 729x886 | - | 4.1 / 1.0 / 0.5 | - / - | 0.5 (w1512@3) to 4.1 (w1512@1) (24) | B F O T Ta |
| 13 | profile/portfolio-1.jpg | 960x540 | jpeg | 275 | 1.98 | 1280x720 | 1920x1080 | 2.3 / 0.6 / 0.3 | 2.3 / 0.3 | 0.3 (w1512@3) to 2.3 (w1512@1) (39) | B F O T Ta |
| 14 | profile/portfolio-2.jpg | 960x540 | jpeg | 351 | 1.98 | 1867x1050 | - | 1.1 / 0.3 / 0.1 | - / - | 0.1 (w1512@3) to 1.1 (w1512@1) (24) | B F O T Ta |
| 15 | profile/portfolio-3.jpg | 960x540 | jpeg | 369 | 1.98 | 1280x720 | - | 2.3 / 0.6 / 0.3 | - / - | 0.3 (w1512@3) to 2.3 (w1512@1) (24) | B F O T Ta |
| 16 | media/service-kitchen.png | 410x512 | png | 366 | 0.80 | 574x717 | 414x517 | 2.0 / 0.5 / 0.2 | 8.8 / 1.0 | 0.2 (w1512@3) to 8.8 (w430@1) (39) | B F O T Ta |
| 17 | media/avatar-cat.png | 341x512 | png | 290 | 0.67 | 574x862 | 589x885 | 1.4 / 0.4 / 0.2 | 3.0 / 0.3 | 0.2 (w1512@3) to 3.0 (w430@1) (39) | B F O T Ta |
| 18 | media/post-3.png | 341x512 | png | 266 | 0.67 | 702x1054 | 1053x1581 | 0.9 / 0.2 / 0.1 | 0.9 / 0.1 | 0.1 (w1512@3) to 0.9 (w1512@1) (39) | B F O T Ta |
| 19 | media/post-2.png | 368x460 | png | 222 | 0.65 | 576x720 | 864x1080 | 1.6 / 0.4 / 0.2 | 1.6 / 0.2 | 0.2 (w1512@3) to 1.6 (w1512@1) (39) | B F O T Ta |
| 20 | media/post-1.png | 368x447 | png | 253 | 0.63 | 593x720 | 889x1080 | 1.5 / 0.4 / 0.2 | 1.5 / 0.2 | 0.2 (w1512@3) to 1.5 (w1512@1) (39) | B F O T Ta |
| 21 | media/service-cafe.png | 480x270 | png | 290 | 0.49 | 1280x720 | 1920x1080 | 0.6 / 0.1 / 0.1 | 0.6 / 0.1 | 0.1 (w1512@3) to 0.6 (w1512@1) (39) | B F O T Ta |

**People section (extra, top 12 of 50 by wasted bytes, run 39481653302)**: 50 files (48 drawn in some cell), 7.71 MiB on disk, 191.11 MiB decoded (natural pixels x 4)

| # | file | natural | fmt | KiB | decoded MiB | drawn px at 1512@2 | drawn px at 430@3 | waste x at 1512@1 / @2 / @3 | at 430@1 / @3 | waste x range over all cells (cells drawn) | effects above it |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | a/post-strawberry.jpg (background-image) | 1320x1752 | jpeg | 293 | 8.82 | 264x350 | - | 100.1 / 25.0 / 11.1 | - / - | 11.1 (w1512@3) to 100.1 (w1512@1) (12) | M T |
| 2 | a/service-strawberry.jpg (background-image) | 1320x1747 | jpeg | 415 | 8.80 | 390x516 | 555x735 | 45.8 / 11.5 / 5.1 | 50.9 / 5.7 | 2.6 (w860@2) to 50.9 (w430@1) (39) | M T |
| 3 | a/service-dd-transport.jpg (background-image) | 1400x1400 | jpeg | 226 | 7.48 | 264x264 | - | 112.5 / 28.1 / 12.5 | - / - | 12.5 (w1512@3) to 112.5 (w1512@1) (12) | M T Ta |
| 4 | a/post-greengo.jpg (background-image) | 1400x1400 | jpeg | 168 | 7.48 | 370x370 | - | 57.3 / 14.3 / 6.4 | - / - | 6.1 (w1030@2) to 57.3 (w1512@1) (20) | M T Ta |
| 5 | a/post-orchestra.jpg (background-image) | 1600x1067 | jpeg | 316 | 6.51 | 370x247 | 526x351 | 75.0 / 18.7 / 8.3 | 83.4 / 9.2 | 4.2 (w860@2) to 83.4 (w430@1) (39) | M T |
| 6 | a/service-feature.jpg (background-image) | 1272x1272 | jpeg | 534 | 6.17 | 264x264 | - | 92.9 / 23.2 / 10.3 | - / - | 10.3 (w1512@3) to 92.9 (w1512@1) (12) | M T |
| 7 | a/service-chatbot.jpg (background-image) | 1448x1086 | jpeg | 129 | 6.00 | 264x198 | - | 120.3 / 30.1 / 13.4 | - / - | 13.4 (w1512@3) to 120.3 (w1512@1) (12) | M T |
| 8 | a/service-eye.jpg (background-image) | 1400x1099 | jpeg | 172 | 5.87 | 264x207 | - | 112.1 / 28.2 / 12.5 | - / - | 12.5 (w1512@3) to 112.1 (w1512@1) (12) | M T |
| 9 | a/post-spark.jpg (background-image) | 1448x1086 | jpeg | 234 | 6.00 | 370x278 | - | 61.2 / 15.3 / 6.8 | - / - | 6.5 (w1030@2) to 61.2 (w1512@1) (20) | M T |
| 10 | a/post-marketing.jpg (background-image) | 1207x1303 | jpeg | 251 | 6.00 | 371x400 | - | 42.5 / 10.6 / 4.7 | - / - | 4.5 (w1030@2) to 44.1 (w1031@2) (20) | M T |
| 11 | a/post-haus-clinic.jpg (background-image) | 1120x1400 | jpeg | 191 | 5.98 | 370x463 | - | 36.7 / 9.2 / 4.1 | - / - | 3.9 (w1030@2) to 38.3 (w1031@2) (20) | M T Ta |
| 12 | a/post-symposium.jpg (background-image) | 1087x1447 | jpeg | 222 | 6.00 | 370x493 | - | 34.6 / 8.6 / 3.8 | - / - | 3.6 (w1030@2) to 36.4 (w1031@2) (20) | M T |

Chromium gives the same natural sizes, formats, bytes and decoded totals (hero 46.63 MiB, morph 58.80 MiB, people 191.11 MiB); only the
hero's drawn sizes differ (cards sampled at another animation phase: leobeer-cover 498x476 against 382x365 at 1512@2). The Chromium
tables are in the run's `images-summary` artifact. The tables are MiB (2^20 bytes): peter-cover is 1200 x 2133 x 4 = 9.76 MiB, which is
10.24 MB in decimal. The landed lag-source note's 61.66 MB and 30.07 MB for the morph are the same bytes as 58.80 MiB and 28.68 MiB.

**What the table says.**

- The morph is mostly not oversized at DPR 2. The waste at 1512@2 is 5.0x for architect.png and 3.2 to 3.4x for the other four role
  PNGs (1282 px square, drawn 574 to 721 device px), 2.0x for media/post-4 and 1.6x or less for the rest; 9 of the 21 are drawn above their
  natural size at 1512@2 (waste below 1: the portfolio, service, avatar and post PNGs and JPEGs), and most are at 1512@3 (see the cross-check).
- The hero is the clearest case at a phone's DPR 1 to 3: a 640 px avatar is drawn at 88 px (53x at 1512@2) and the 1200 px covers at
  4 to 10x at 1512@2. It is 46.63 MiB decoded but only 1.78 MiB on disk.
- The people section is the largest by far (191.11 MiB decoded, 50 files, background-image JPEGs of 1100 to 1750 px, the top twelve
  drawn at 9x to 30x their pixels at 1512@2), but it is a mask-and-transform region, not part of region A or B.
- No file is in more than one region.

**Effects above the images** (the other half of the question). Region A images sit under opacity and transform (O T). Region B images
sit under B F O T Ta: a backdrop-filter, a filter, an opacity, a transform and an animated transform. By R3 and R4 a composited filter
and backdrop-filter are layer properties, so an image in such a layer is not repainted by their animation; the images' natural size
enters a frame only through a repaint (see "What the facts give").

**Cross-check against `10-20-webkit-lag-source.md`.** That note's morph numbers come from the pre-morph box (track 199 px at 1512,
124.0 px at 430) or from the end-state formula (286.8 px at 1512). The audit here measures the end state with `--morph` = 1: the track
at 1512 is 287 px (the note's 286.8: same). On a phone, the audit's track is 132.5 px against the note's 124.0 px (the note's formula
`(366 * 1.06 - 2 * 8) / 3`; the audit reads the real box). Consequences: desktop ratios 0.38 to 2.23 with 9 upscaled (note: 0.38 to
2.24, 9: agree); phone ratios 0.25 to 1.91 with 10 upscaled (note: 0.25 to 1.91, 9 of 13: the extra upscaled image is
service-kitchen, at 0.99 in the audit, just under 1). Bytes agree (above). The note's claim that a later paint of a visible `decoding="async"` image decodes
synchronously is D3's default-mode branch, not a contradiction. The one difference that matters: the earlier audit sized the drawn arm
from the pre-morph box, which is why the first drawn-size arm (runs 39463201200 and 39470558091) failed the morph.

### The drawn-size arm (premise refuted: MEASURED negative finding)

**What was built.** `apps/site/src/flags/images/drawn.json` (schema `fw.images.drawn/1`) lists, per image, DPR and width class, the
resized copy to serve; it holds paths, pixel sizes, byte counts and sha256 only, no image data. It names 102 copies of the 48 images
the audit sees drawn. `node packages/gate-breakpoints/src/images/cli.mjs arm build` generates it (never by hand) and writes the
copies with `sips` (and `pngquant` for PNG) into the gitignored `apps/site/dist/aot/images-drawn`. **The copies are not in git:**
Fastwork material enters git only as the unmodified snapshot, so the resized copies of earlier rounds (derived from it) are not in
this branch's history. `sips` exists on a Mac only, so no Linux CI job builds them yet; the `[images-arm]` steps of
`gate-gaps.yml` run only when the copies are in the served dist, which no commit provides. The numbers below are those of run
`39481653302`, which served the committed copies of head 93a0cada (since removed from the history); a re-run needs the builder
of task image-arm-v2. Each copy holds twice the pixels its image needs at the widest width where it is chosen (`OVERSAMPLE = 2`), the
ladder steps by 1.5x, and `drawnFile(manifest, url, width, dpr)` returns the smallest listed DPR at least the requested one, then the
last row with `from <= width`.

**The switch is an API only.** `packages/measure-webkit/src/images/switch.mjs` exports `armFromEnv(env)` (`FW_IMAGES_ARM` unset, empty
or `default` is the site as shipped, `drawn` is the arm, anything else throws) and `drawnRewrite({ arm, width, dpr, base, manifest })`
(a `serveTree` rewrite). **No code calls either yet**: webkit-lag-probe is not wired to it, and with the copies gone from git it has
nothing to serve until image-arm-v2. `packages/measure-webkit/src/images/arm.mjs` is a byte copy of the gate-breakpoints one (a test
keeps them equal); three tests cover the switch.

**Was it visually identical within the PL tolerance? No.** PL tolerance = `packages/visual-diff/src/verdict.mjs` DEFAULT_TOL: ppm
<= 2000, maxDelta <= 64, countAA false. Run `39481653302`, `images-pages-*` jobs (70 cells per rep: 7 probes x 10 parts; `pages.mjs`
compares the original snapshot against our rewrite once with the site build as shipped, `baseline`, and once with the copies, `drawn`;
`unsettled` = the original against itself already differs, so no verdict is possible), 3 reps, both engines.

| part | WebKit baseline against arm (3 reps x 7 probes) | Chromium |
|---|---|---|
| morph.panel, morph.columns (region B) | pass 0 ppm in all 21 cells of each, both arms; but the arm replaces **1 of 21 morph images** (`architect.png`), in **4 of 7 probes** (desk-1100, desk-861, touch-1031, touch-601), so the 0 ppm pass covers only `architect-1096.png`. The other 20 morph images are never served from a copy, and desk-1512, touch-401 and touch-320 replace no morph image at all (MEASURED: `drawnFile` over the 7 probes of `breakpoints.gen.json`) | the shipped site already fails 8 to 9 of 21 cells of each part against the original (at most 953 ppm, so the delta rule, above 64, decides); the arm changes the verdict in 6 of 21 cells of each part, 4 fail to pass and 2 pass to fail: no direction, so within the run-to-run noise, not an arm effect (INFERRED from the two directions) |
| hero, hero.orbit, hero.exit, hero.deck (region A) | unsettled in both arms in every cell (21+15+21+6): the hero cards animate, so no verdict can be claimed | the same |
| people.card | fail in both arms, 21 of 21 | pass to fail in 3 of 21 |
| people.o, people.carousel, people.deck | verdict changes in 6, 10 and 3 of 21 cells; the arm is not shown identical | changes in 3, 5 and 0 of 21 (0 for deck, which is unsettled in all 21) |

So the identity is shown for **one image**, `architect-1096.png`, on WebKit (a pass of 0 ppm in the 4 probes that serve it), and **not
shown** for any other morph image, for region A (nothing settles) or for the people section, where it changes verdict. `images-verify-*` (each
copy against its source at the two sizes it is drawn at, a white page, WebKit r1-r3 identical): at DPR 2, 29 of 86 copies pass at 1/2
scale and 37 of 86 at 1/3; at DPR 3, 21 of 48 and 23 of 48. Chromium passes 40/86, 33/86, 20/48 and 21/48. **158 of 268 fail on
WebKit and 154 of 268 on Chromium**, with a median 1600 to 5200 ppm and a 90th percentile of 9000 to 35000 ppm. The old arm (1x
copies, from pre-morph audits; run 39470558091) failed 338 and 266 of 480 per-copy tests (one number per engine), and its morph on
touch-1031 and touch-601 on WebKit gave 14239, 17519, 9506 and 16891 ppm with delta 114 to 139; desktop gave at most 331 ppm.

**Negative finding (MEASURED), closing the premise.** A resized copy is not pixel-identical in WebKit or Chromium, and no
oversample fixes it: the browser's downscale of a large source in one stage differs from two stages (the sips kernel, then the
browser's). A copy drawn at 72 px from a 144 px copy is visibly blurrier than a 480 px source drawn at 72 px. The difference grows
with the source/drawn ratio; at oversample 2 the verify was worse than at 1x (the copy is drawn down by a factor 2 or 3 instead of 1).
The per-copy verify therefore cannot pass for a copy that is far smaller than its source, whatever the page does; the page-level
check passes only where the browser draws the copy at or near its device size (`architect-1096.png`). Mechanism: INFERRED from the
pixel diffs, since the resampling filters are in WebKit's closed CoreGraphics and Skia's source was not diffed here.
- **Numbers:** per-copy verify 158/268 fail (WebKit), 154/268 (Chromium); people parts change verdict in 3 to 10 of 21 WebKit cells;
  the hero is unsettled in every cell; the morph pass covers only `architect-1096.png`; run 39481653302.
- **Lesson:** an image arm is a rendering change that has to be judged by a page-level screenshot per part at the probe DPR, not by a
  byte comparison of pixels, and "identical" is a claim per replaced image, not per part.
- **Next:** task **image-arm-v2** (not this task): either accept a look-change class for the arm (the user reviews it) or judge per part
  at the probe DPR, with a Linux copy builder so that CI can serve the copies without committing them.

**What the arm would save.** Decoded MiB (natural w*h*4 of the files drawn), run `39481653302`, WebKit, mean of 3 reps,
hero + morph + people. The run summary gave these in decimal MB; they are converted here (divided by 1.048576). Each row names the
page-check probe that covers it. The page-check probes (7) are desk-1512@1, desk-1100@1, desk-861@1, touch-1031@2, touch-601@2,
touch-401@3 and touch-320@3; a cell at another width or DPR was **not page-checked**.

| cell | site as shipped | arm | change | page-check probe |
|---|---|---|---|---|
| 1512@1 | 295.1 MiB | 232.3 MiB | -21% | desk-1512@1 (hero unsettled, people changes verdict; no morph image replaced) |
| 1512@2 | 295.1 MiB | 232.3 MiB | -21% | not page-checked (no probe at 1512@2) |
| 1512@3 | 295.1 MiB | 276.0 MiB | -6% | not page-checked |
| 430@1 | 97.7 MiB | 66.3 MiB | -32% | not page-checked |
| 430@3 | 97.7 MiB | 86.0 MiB | -12% | not page-checked (touch-401@3 is the nearest probe, at another width) |

(At 1512@2: hero 46.6, morph 58.8, people 189.6 MiB as shipped; arm 43.3, 58.8, 130.2.) 1512@1 and 1512@2 are the same row because a DPR 1
page is served the DPR 2 copies (`drawnFile` takes the smallest listed DPR at least the requested one). **The morph's decoded bytes do not
change at 1512 because the manifest holds no copy of any morph image at a width of 1280 or more** (`architect.png`, the only morph image in
the table, has a `null` row from 1280; the other 20 are not in the table), and no morph image has a DPR 3 entry; the morph changes at
430@1 only through `architect.png`. It is not because the images are drawn near their natural size: `architect.png` is 5.0x oversized and
the other role PNGs 3.2 to 3.4x at 1512@2 (table above). The arm would save most on the people section and on the hero at phone DPR 1.
Chromium gives the same figures to 0.1 MiB apart from people at 430 (46.3 MiB as shipped against WebKit's 51.8 MiB: the two engines load a
different set of images there). Disk bytes of the drawn files fall from 14.9 MiB to 13.7 MiB at 1512@2 (converted from 15.6 and 14.4 MB).

**Writes outside the task's graph writes** are listed in the handoff (`docs/team/handoffs/image-audit.md`).


## WebKit: what happens to a large image (source @862f17d)

`WC` = `Source/WebCore`, read in `.cache/upstream/WebKit@862f17d`. Files outside the sparse pin were read with `curl` at the
same sha (`ImageFrame.cpp`, `BitmapImageDescriptor.cpp`, `WebKit/Shared/CacheModel.cpp`,
`WTF/Scripts/Preferences/UnifiedWebPreferences.yaml`). The Lean statement of each fact is `lean/Fw/Engine/WebKitImage.lean`.

| # | Claim | Status | Source |
|---|---|---|---|
| D1 | A still image is "large" when its decoded size (w*h*4) is over 500 KB; animated over 100 KB | CONFIRMED | `WC/platform/graphics/BitmapImageSource.cpp:349-353` |
| D2 | Large-image async decoding is on by default (WebKit, WebCore, legacy) | CONFIRMED | `WTF/Scripts/Preferences/UnifiedWebPreferences.yaml:4565-4574`; history: bug 165177 (2016-11-30) split the setting, bug 174451 (2017-07) turned async off after the first tile paint |
| D3 | The decode mode of a draw depends on the `decoding` attribute first. `decoding="sync"` is synchronous (:290-292). `decoding="async"` takes the default mode at any size (:295-302). With `auto`, a small image is synchronous (:316-317) and a large one takes the default mode (:318-319). The default mode is asynchronous on the first paint of an element that never painted an image (:271-286); otherwise synchronous when the renderer is in the viewport and asynchronous when it is not. Both lag regions' images carry `decoding="async"` (hero.orbit/card.tsx:29,36; morph.columns/index.tsx:75), so size does not enter their mode; only first paint and visibility do (`modeFor` in Lean, `attr_async_ignores_size`) | CONFIRMED | `WC/rendering/RenderBoxModelObject.cpp:256-320` (default mode at 271-286, attribute cases at 290-302, auto at 315-319), `WC/rendering/RenderElement.cpp:1799-1804` (visible = inside the window clip rect) |
| D4 | A synchronous decode builds the whole image at its native size (subsampled only by D6); an asynchronous decode builds a thumbnail at min(native area, drawn area) | CONFIRMED | `WC/platform/graphics/cg/ImageDecoderCG.cpp:676-698` (`CGImageSourceCreateImageAtIndex` against `CGImageSourceCreateThumbnailAtIndex`); drawn size from `WC/platform/graphics/BitmapImage.cpp:94-106` |
| D5 | A decoded frame is kept and reused by every later draw whose options it is compatible with: a full-size frame serves any request, a sized one serves requests up to its largest side; asking for a finer subsampling level than the cached one decodes again | CONFIRMED | `WC/platform/graphics/DecodingOptions.h:67-88`, `WC/platform/graphics/ImageFrame.cpp:113-124`, `BitmapImageSource.cpp:563-620` |
| D6 | iOS and macOS subsample only images of 5 Mpx or more: the maximum level is the first whose area is under 5*1024*1024, and it is 0 for anything smaller. Every image of the lag regions is under that, so none is subsampled | CONFIRMED | `WC/platform/graphics/BitmapImageDescriptor.cpp:229-280` |
| R1 | A draw hands the whole decoded frame to CoreGraphics (`CGContextDrawImage` with the destination rectangle); WebCore keeps no scaled copy. That CoreGraphics resamples the frame on each such draw is INFERRED (closed source), and the iOS source points the other way. On iOS WebKit calls `CGImageSetCachingFlags(image, kCGImageCachingTemporary)` because under CoreGraphics' transient caching default "the images had to be resampled/recreated every time we called CGContextDrawImage"; "we now tell CG to cache the drawn images". That comment points toward CG caching the drawn image on iOS Safari (the target), so toward `resamples = false` or a cached resample, while the platform-neutral hand-over points toward a per-draw resample. What CG caches after the flag is not visible in WebKit. **P-resample stays INFERRED in both directions**; this note does not assume `resamples = true` | CONFIRMED (hand-over, the iOS flag and comment) / INFERRED (per-draw resample, either way) | `WC/platform/graphics/cg/GraphicsContextCG.cpp:283-433`, `ImageDecoderCG.cpp:702-709` (the comment at :703-706) |
| R2 | Interpolation quality: images whose layout size changes between paints are drawn at low quality for 500 ms; a transform leaves the layout size alone and draws at default quality | CONFIRMED | `WC/rendering/ImageQualityController.cpp:45-46,136-205` |
| R3 | A layer whose filters the compositor can run (no reference filter) paints without them: a change of `filter` is a layer property update (`FiltersChanged`), not a repaint of the content. A filter that cannot be composited paints the layer through the software filter | CONFIRMED | `WC/rendering/RenderLayer.cpp:1055-1070`, `WC/rendering/RenderLayerBacking.cpp:868-871`, `WC/platform/graphics/ca/GraphicsLayerCA.cpp:925-945` |
| R4 | `backdrop-filter` composites its layer | CONFIRMED | `WC/rendering/RenderLayerCompositor.cpp:3981-3984` |
| M1 | Decoded size counts against the memory cache. The primary-browser cache model has 128 MiB in total on a device with at least 2 GB (Safari's model is INFERRED) | CONFIRMED (table) / INFERRED (model) | `WebKit/Shared/CacheModel.cpp:88-119` |
| M2 | Over the live capacity, the cache destroys the decoded data of live images, least recently used first, but not an image used less than 1 s ago; a destroyed image decodes again at its next draw | CONFIRMED | `WC/loader/cache/MemoryCache.cpp:53,209-233,275-328`, `WC/loader/cache/CachedImage.cpp:651-660` |

What the facts give, and what they do not:

- **Where a large photo costs.** At first paint in the viewport (D3) the whole image is decoded on the main thread at its native
  size (D4); a photo drawn small pays decode time in proportion to its natural pixels, once (D5). Below the fold the same photo
  decodes at the drawn size on a worker (D4), so the cost moves to the scroll that brings it into view only if a full-size frame is
  needed again. CONFIRMED for the branches, INFERRED for their cost.
- **Per frame.** An image in a layer that only has its opacity, transform or composited filter animated is not repainted (R3
  covers the composited filter; the opacity, transform, backdrop and no-effect rows are **P-repaint, INFERRED** here, not cited to a
  source line), so its natural size does not enter a frame's cost; the layer's backing store
  has the drawn size. A repaint (a layout change, a software filter, a style change with a repaint difference) draws the
  frame again and, if CoreGraphics resamples (R1, INFERRED, and on iOS the source comment points toward CG caching the drawn image),
  reads natural pixels. The cost term is natural pixels times the number of repaints **only under `resamples = true`**; under `false`
  it is the one-off decode. Whether any of the lag's frames repaint an image is the question this note does not answer.
- **Memory.** Decoded bytes are w*h*4 whatever the file size (M1), so a small JPEG can be a large frame; the audit's decoded column is that
  number.

Lean (`lean/Fw/Engine/WebKitImage.lean`, `lake build` green via `lean/scripts/check.sh`). **Statement:** for an image of `natPx` natural and
`drawnPx` drawn pixels, repainted `reps` times, `cost m resamples natPx drawnPx reps = decodedPx m natPx drawnPx * (1 + (if resamples then reps else 0))`,
where `decodedPx` is the whole image for a synchronous decode and `min natPx drawnPx` for an asynchronous one.
The file has **40 theorems** (`grep -c '^theorem'`). Those of the decode and cost terms, one per branch: `isLarge_true`, `isLarge_false` (D1); `maxLevel_one`, `maxLevel_two`, `maxLevel_three`, `level_zero` to
`level_three`, `no_subsampling_under_limit` (D6); `auto_small_sync`, `auto_large_firstPaint_async`, `auto_large_visible_sync`,
`auto_large_hidden_async`, `attr_sync_always_sync`, `attr_async_small_firstPaint_async`, `attr_async_small_visible_sync`,
`attr_async_small_hidden_async`, `attr_async_ignores_size` (D3, with the `decoding` attribute); `async_decodes_drawn` (D4); the cost
theorems `cost_sync_resample`, `cost_async_resample`, `cost_mono_nat`, `cost_mono_reps`, `sync_saving` (the saving of a copy is exactly
the pixel difference times (1 + repaints)), `drawn_copy_le`, `drawn_copy_modes_equal` and `async_source_equals_copy` (an image
already decoded asynchronously gains nothing from a copy). The repaint rows have `composited_filter_no_repaint`,
`opacity_anim_no_repaint`, `transform_anim_no_repaint`, `backdrop_no_repaint`, `nothing_no_repaint` and
`software_filter_repaints_each_frame`. **Premises:** D1-D6 and R3 are source facts (CONFIRMED). **Two premises are INFERRED, and a
frame cost depends on both.** **P-resample** (R1) is the `resamples` flag; it is INFERRED in both directions (the iOS
`kCGImageCachingTemporary` comment points toward CG caching the drawn image, the platform-neutral hand-over toward a per-draw
resample). **P-repaint** is the compositor rows of `repaints` (`opacityAnim`, `transformAnim`, `backdrop`, `nothing` map to 0
repaints); only the composited-filter row has a source citation (R3). The cost is `decodedPx * (1 + reps)` under `resamples = true`
and `reps = repaints u frames`; with `resamples = false` it is the one-off decode alone (`cost_no_resample`).
