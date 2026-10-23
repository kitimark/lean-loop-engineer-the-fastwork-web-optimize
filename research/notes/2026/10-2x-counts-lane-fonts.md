---
id: counts-lane-fonts
kind: note
title: "The Chromium counts container gets one system font package; the page loads at 1280 without the text-wrap workaround, and the swipe page becomes 720 px taller"
status: draft
created: 2026-10-23
topics: [chromium, measurement, fonts, counts, profiles, crash]
---

# Counts lane fonts

Task `counts-lane-fonts`, branch `ci/counts-lane-fonts` (candidate) and `ci/counts-lane-fonts-base` (old image, same tip
otherwise). Claims carry CONFIRMED / MEASURED / INFERRED. Free GitHub runners only; Chrome for Testing 156.0.8078.4 stands in for
branded Chrome.

## Answer

- MEASURED: with the lane's image holding the one font package `fonts-liberation`, the original page and the rewrite both load
  and run at 1280 x 800 with no `text-wrap` workaround and no renderer crash, 3 of 3 counts jobs each: rewrite run 39900925552,
  original run 39900932545. Before, the same two targets crashed in every job (runs 39865150834, 39865162582).
- DECISION: the lane gets exactly the fonts a desktop Chrome user on Debian or Ubuntu gets with the browser's own `.deb`:
  `fonts-liberation` 1:1.07.4-11 (bookworm snapshot, pinned), in one fontconfig directory, no aliases. The text of the config is
  `Fw.Measure.Profile.fontsConf` (Lean); `docker/fonts.conf` is that text, and a test compares the two.
- MEASURED, comparability: the fonts move counts. On `swipe-v1` the same tip with the old image (run 39901082850) and with the new
  image (run 39900399252) differ in 61 of 75 count types, because the swipe page is 720 px taller (max scroll 5346 px vs 4626 px)
  and the swipe lasts 575 frames instead of 503. Counts from before this task, taken without fonts, are therefore not comparable
  with counts from after it. Layout counts of the desktop rows did not move (below).

## Why this option

The crash needs a layout pass with no font at all: the container's `fonts.conf` had no `<dir>`, and the page's web font is not yet
ready at the first layout, so the first line has no font (`10-2x-chrome-balance-repro.md`, MEASURED, run 39878812594; the people
title, `text-wrap: balance` over a paragraph holding an inline-grid atomic inline, `10-2x-chromium-desktop-crash.md`).

Options:

| option | verdict | why |
|---|---|---|
| fonts of the Chrome `.deb` dependency list (`fonts-liberation`) | chosen | what a desktop user has; the image stays deterministic: pinned package version, dated snapshot mirror, manifest diff, one `<dir>`, a Lean `fontsOk` check at run start |
| the page's own web font ready before the first layout | rejected | it cannot be forced on the original page without editing it, and the order of the font and the first layout is exactly what the page does on a user's machine |
| keep no fonts, keep `text-wrap: wrap` on every element | rejected | the counts then describe a page without balancing (a look change), and a site-side fix would turn the breakpoint gate red (it reads `text-wrap-style`; branch note `10-2x-people-title-crash-fix.md`: the block `o` does not stop the crash, only `text-wrap: wrap` on the title does) |
| a larger font set (DejaVu, Noto, emoji) | rejected | more fallback faces change line breaks and the count of font loads without a user-visible reason; one family set is enough to avoid the empty-font state |

INFERRED: that `fonts-liberation` is in Chrome's own dependency list comes from the old Dockerfile comment, not from a read of
the `.deb` control file (the fetch was blocked).

## Lean

`lean/Fw/Measure/Profile.lean` pins `fontPkg`, `fontVersion`, `fontDir`, `fontFamilies`, `fontsConf` and `fontsOk` (every pinned
family is among the families `fc-list` reports). Theorems: `fontsOk_iff`, `fontsOk_missing`, `fontsOk_nil` (a container with no
font fails), `fontsConf_one_dir` (exactly one `<dir>`), `fontDir_system` (the dir is a system path) and `fontDir_not_snapshot`
(not the mounted snapshot). The golden `packages/contracts/golden/measure/profile.jsonl` carries the config text and the `fontsOk`
cases; `packages/measure-chromium/src/profile.mjs` (`fontsOk`) and `test/profile.test.mjs` check against it. `run.mjs` runs
`fc-list : family`, exits 2 with `FW_NO_SYSTEM_FONTS` if `fontsOk` fails, and writes `meta.systemFonts` to `counts.json`. MEASURED:
`meta.systemFonts` is Liberation Mono, Sans, Sans Narrow and Serif in every job of the runs below.

## No crash at 1280 (MEASURED)

| target | run | jobs | text-wrap workaround |
|---|---|---|---|
| rewrite | 39900925552 | r1, r2, r3 and classify green | none (profile `desktop-1280` has no `css`) |
| original | 39900932545 | r1, r2, r3 and classify green | none |

`people-o-hover` (rewrite) also ran without the workaround: base run 39900922311, with `--fw people.o:preview-translate` run
39900929308, 3 jobs each, green. Both profiles now have no `css`; a test asserts it.

## Re-measured desktop rows (MEASURED, 3 jobs each)

Old rows: `desktop-1280` rewrite run 39868985767, `people-o-hover` base 39881189724 and flag 39881193403, all taken with the
workaround and no fonts. New rows: no workaround, with fonts.

| row | old | new |
|---|---|---|
| desktop-1280 rewrite, `trace.Layout` (rest / scroll / tail) | 17 / 97 / 6 (120) | 17 / 97 / 6 (120) |
| desktop-1280 rewrite, `Layout.totalObjects` | 103782 | 103782 |
| people-o-hover base, `trace.Layout` in the scroll phase | 67 | 67 |
| people-o-hover flag `people.o:preview-translate`, scroll phase | 28 | 28 |
| people-o-hover base / flag, `trace.Layout` whole run | 232 / 193 | 232 / 193 |
| people-o-hover base / flag, `Layout.totalObjects` | 269582 / 220507 | 269582 / 220507 |

So the people-o-followups result (Layout 67 to 28 in the scroll phase, with the flag) does not move: the layout counts of the
three rows are equal to the unit, in all three jobs. What moves is paint and raster:

| type (sum of 3-job run 1) | desktop rewrite old / new | hover base old / new |
|---|---|---|
| `trace.Paint` | 440 / 506 | 863 / 989 |
| `trace.RasterTask` | 302 / 521 | 778 / 958 |
| `trace.Layout.dirtyObjects` | 3170 / 1300 | 7706 / 2910 |
| `trace.UpdateLayoutTree` | 437 / 431 | 398 / 407 |

Classes over 3 runs (deterministic / stable / quarantined), desktop rewrite: old 52 / 11 / 5, new 53 / 6 / 9; 10 of 68 types
change class: 7 go to quarantined (JSEventListeners, LayoutObjects, Nodes, invalidationAreaPx, invalidationRects, Layer.deleted,
MajorGC) and 3 go from quarantined to deterministic (FireAnimationFrame, RequestAnimationFrame, HitTest.overlayAdDetector). Desktop original: new 47 / 16 / 5 (run 39900932545), old 52 / 13 / 2 (run 39869000429, whose
files were not fetched, so no type-level comparison). The class tallies move by a few types; the layout types stay deterministic.

Attribution: the new rows change two things at once (fonts and no workaround), and the budget of runs was spent, so no run
isolates them. INFERRED: the paint, raster and tile changes come from the fonts (the swipe A/B below changes only the image and
shows the same direction); the layout counts did not change with either, so the workaround never changed the layout counts of
these profiles.

## Swipe A/B: do the fonts move counts? (MEASURED)

Same tip, same `run.mjs` except the font check, `swipe-v1` at 430 px, both targets, 3 jobs each.

| target | new image run | old image run | deterministic types (new / old) | stable (new / old) | quarantined (new / old) | types that change class |
|---|---|---|---|---|---|---|
| original | 39900399252 | 39901082850 | 34 / 36 | 26 / 25 | 10 / 9 | 9 of 70 |
| rewrite | 39900399252 | 39901082850 | 26 / 27 | 30 / 27 | 14 / 16 | 13 of 70 |

| | frames | max scroll |
|---|---|---|
| new image | 575 (535 swipe frames) | 5346 px |
| old image | 503 (463 swipe frames) | 4626 px |

The old-image arm reproduces the 499 snapshots (`census.snapshots`) of the frozen classes (`classes.frozen.json`, image 8f0e17f5,
run 39184638066) exactly, so the lane is stable across weeks; the new image (570 snapshots) is what changes it. In 61 of 75 types
the 3-job ranges of the two images do not overlap. Of the deterministic types of the new arm, only 10 (original) and 8
(rewrite) of 34 and 23 have an equal sum in the old arm; the rest scale with the 72 extra frames (Commit, Layerize, EvaluateScript,
cc.Draw, ScrollLayer and others), and Layer.created and Animation counts also move.

INFERRED: the page is taller with fonts because text that had no installed face in the old lane (glyphs not covered by the
page's web fonts, and the interval before the web font is ready) was laid out with empty advances; with a face it takes real
width and wraps. The phone has system fonts, so the new lane is closer to it.

## Follow-ups (not fixed here)

- The frozen classes (`classes.frozen.json`) and every earlier lane result that lacks `meta.systemFonts` came from the font-less
  image and may need re-measuring on the new image. That is a finding, not a fix item.
- Branded Chrome could differ from Chrome for Testing; the Chromium bug filing for the crash is a user step.
