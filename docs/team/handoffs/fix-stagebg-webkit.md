# fix-stagebg-webkit handoff

Branch: worktree-agent-a458614d290aab007 (CI branch ci/fix-stagebg-webkit). Files: apps/site/src/parts/platform/platform.module.css.

## Lean row for fix-proofs
| field | value |
|---|---|
| cell | platform.stageBg, WebKit (webkit-glib on CI), sweep desktop-1512-320-1512 stops <= 481 px (stage h, grain h, bg h); touch/hover not involved |
| property | stage `height` (grain, bg inherit it via inset 0) of the stage whose row sits in a stale grid |
| original value | `aspect-ratio: 361/288` (860 combo) / `640/512` (<=640), `height:auto`, `width:100%`; h = (W-40)*288/361 (351.8125 at W=481). Source: snapshot 2.gBuqKVzi.css:7814-7818, 11020-11030 |
| old port value | same CSS text; WebKit gave 319.625 (= h - 32.1875, one 28px/1.15 title line) |
| cause class | engine layout quirk (stale cache) exposed by a stretch default, not a CSS value difference; plus a smaller real bug: the section had no `font-family` (original inherits it from body, 0.ChGpbVhU.css:515-520) so the titles wrapped differently in a fresh load |
| formula | stage h = (W-40) * 288/361 for W <= 640 (independent of the row/copy height); copy track = padding 20 + title lines * 32.1875 |
| fix | `.stageSlot { align-self: start }` inside `@media (width<=640px)`; `font-family` (Google Sans stack) on `.section` |

## Why WebKit differs (INFERRED from a Linux WebKit repro, engine source not pinned-read yet)
Repro: docker `mcr.microsoft.com/playwright:v1.64.1-noble` (arm64, same webkit-glib as CI), load at 1512, resize 1512->481->400->320.
At 320 the port's second row reports tracks `191.19px 84.375px` (sum 275.56 = old stage 223.375 + old copy 52.19) while the original has `223.375px 84.375px`:
the grid container kept a stale content height from the 1-line title layout, the copy item grew to the 2-line height 84.375, and the
stretched stage (align-self normal = stretch) was shrunk by the difference (32.19) even though it has an aspect ratio.
With `align-self: start` the stage keeps its aspect-ratio height (223.375) in the same repro. text-wrap:pretty is not the cause (tested).
Spec: css-align-3 says `normal` behaves as `start` for items with a preferred aspect ratio; WebKit's grid stretch path still resizes them.
Engine source (Source/WebCore/rendering/RenderGrid.cpp@862f17d): :359-368 computeAspectRatioDependentAndBaselineItems marks block-size-dependent aspect-ratio items; :294 forces a second track-sizing pass for them; :1580-1589 updateGridAreaForAspectRatioItems re-applies stretch (applyStretchAlignmentToGridItemIfNeeded) to them against the track sizes of that pass. A stale copy-track size in that pass shrinks the stretched stage. (INFERRED link; the stale copy track itself is not located.)
Residual (not gated): the copy track stays stale (52.19 vs 84.4) after such a resize, so the row is 32 px short in WebKit-glib.

## State
Run 39072741571 (font-family only): webkit failures unchanged (stage/grain/bg h, 16 sweep stops), chromium 0.
Run 39073955561 (+ align-self:start): stage/grain/bg heights fixed in webkit; chromium and webkit each keep ONE failure:
platform.stageBg stage `align-self` (orig `auto`, port `start`, 120 samples) because the gate compares props declared by either arm.
Needs the lead/gate owner: add `align-self` to the stage role skipProps in packages/gate-breakpoints/src/anchors.json (declared engine workaround, cite this file).
Tried without effect (docker repro): removing text-wrap:pretty; `grid-template-rows: auto auto` on the row (stage still shrinks to 191.19 at 320 on the first descent).
No CSS-only fix leaves every compared property equal: any non-stretch placement shows in align-self/align-items.
Debug recipe: docker run --rm -v WORKTREE:/w -w /w/packages/gate-breakpoints mcr.microsoft.com/playwright:v1.64.1-noble node SCRIPT; build with `node apps/site/scripts/build.mjs --engine aot`.
