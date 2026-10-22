# nav fixed size (render-cost C8u + C14 + translate3d logo): flags nav:clip-box, nav:bar-fixed, nav:logo-3d

Task `nav-fixed-size` (graph r279). Branch `worktree-wf_fab081fd-3ca-1`, CI branches `ci/nav-fixed-size` (lean, breakpoint gate on the
default config, trajectory fw=nav:clip-box), `ci/nav-fixed-size-bar` (trajectory fw=nav:bar-fixed), `ci/nav-fixed-size-logo`
(trajectory fw=nav:logo-3d). Context: `10-22-webkit-render-cost.md` (F3, F6, F9, F11, C8, C14).

## Verdict

Round 2 (original transition lists kept). Same-look breakpoint gate with the flag, both engines, all PASS; trajectory-probe verdict runs; lean runs green.

| flag | Lean | same-look gate (both engines) | trajectory-probe | layer census | verdict |
|---|---|---|---|---|---|
| clip-box | `box_eq`, `rest_same_*`, `visible_eq`, `probe_eq`, `union_const`, `layout_only_at_endpoints`, `usedW_eq_unionW`, `decl_eq_rest_zero`, `decl_close_rest`, `used_eq_rest_one`, golden 100 rows | run 39842609609 pass | 39842561544 | not run | partly-proved: same look and layout claim proved; cost not measured |
| bar-fixed | `barW_const`, `logoX_*`, `actionsX_*`, `bar_resizePaint_zero`, golden 100 rows | run 39846092556 pass | 39842569267 | not run | partly-proved |
| logo-3d | `translate_scale_order`, `logo3d_layout_*` | run 39848853982 pass | 39842581192 | not run | partly-proved |

Round 1 gates (39835303279, 39837964273) failed on `transition-property` losing `width`; fixed as described under Design. The nav clip trajectory cell stays
pending on gpu-trajectory-cells; layer census and cost lane are follow-ups.

## Design

A part carries one variant, so the three arms are cumulative variants: `bar-fixed` includes `clip-box`, `logo-3d` includes `bar-fixed`
(`Arm.has`, `requires_chain`). `requires` in `part.json` cannot name a flag of the same part (`registry/resolve.ts` checks it against the
selected set, which holds one variant per part), so the chain lives in the class names (`boxClip`, `boxBar`, `box3d`) and in Lean.
All three conflict with `morph.panel:const-bounds`: that variant places the panel from the nav box, here the panel is placed by the insets.

While the nav has `is-morphing` and not `is-locale-open` (`NavClipBox.active`):

| element | original | clip-box | bar-fixed adds | logo-3d adds |
|---|---|---|---|---|
| nav | `width`, `height`, `top` of the pill, `border-radius` | union box: width `panelW`, height `panelH + 4` (phone `panelH`), top 16 (phone 12), radius 0, `clip-path: inset(t x b x round r)` | | |
| bar | `left:0; right:0; top:0` | `left/right: x`, `top: t` (layout per frame) | `left/right: 0`, `translate: 0 t`, `will-change: transform` | |
| logo | `left: i + (50% - i) m`, `translate: -50% m` | same | `left: i`, `translate: X(m) - 50% m` | `transform: translate3d(X(m) - 50% m, 0, 0) scale(s)` |
| actions | `right: 8px` of the pill | same | `translate: A(m) -50%` | |
| panel | `inset: 0` | `inset: t x b x` | | |

`x = (panelW - pillW)(1 - m)/2`, `t = 4m` (phone `4(1 - m)`), `b = (panelH - pillH +- 4)(1 - m)`, `X(m)` the quadratic of `logoX_quad`, `A(m)` the affine
function of `actionsX_affine`. No element is added (the breakpoint gate counts direct children, incident of `morph-constant-bounds`): the
panel is a direct child selected by its `data-fw="morph-panel"` hook.

Phone logo: the original writes `translate` then `scale` as two properties, so the translation is outside the scale. `transform: translate3d() scale()`
keeps that order; the property `scale` plus a `transform` would scale the translation (`translate_scale_order`).

Width transition at rest: the original `transition` lists end with `width`. They stay as they are (the first CI version dropped `width` from them; the
breakpoint gate failed on the changed `transition-property` on both engines, runs 39835303279 and 39837964273, and the hero-pill to bar width change at the
hero exit lost its 0.68 s ease). Instead the rule declares `width: var(--pill-w)` and reaches the union through `min-width: var(--panel-w)`. The declared width
is constant in the morph, `min-width` is not in the lists, and at `m = 0` the declared width equals the rest width (`decl_eq_rest_zero`; for `0 < m <= cut`
within `cut * (panelW - pillW)`, `decl_close_rest`), so dropping `.is-morphing` starts no width transition. `usedW_eq_unionW`: used width = max(width, min-width)
= union width; `used_eq_rest_one` covers the end at 1 (the class stays on). `layout_only_at_endpoints`: boxes at two morph values differ only if one is at or below the cut.

## Lean

`lean/Fw/Parts/NavClipBox.lean`, `NavBarFixed.lean`, `NavBarFixedWork.lean`, `lean/Fw/Engine/WebKitSimple.lean`; goldens
`packages/contracts/golden/parts/nav-clip-box.jsonl`, `nav-bar-fixed.jsonl` (10 viewports on both sides of 640, 10 morph values around the cuts, 100 rows each,
tied by `#guard`). TS: `apps/site/src/parts/nav/box.ts`; `box.golden.test.ts` evaluates the CSS calc strings and the TS against the rows.

| theorem | statement |
|---|---|
| `box_eq` | the clip rect of the union box with the insets equals `navLeft/navTop/navWidth/navHeight` of the original, every viewport, every `m` |
| `insets_phone`, `insets_wide`, `insets_nonneg` | closed forms per band; non-negative for `0 <= m <= 1` when `pillH + 4 <= panelH` (why the union box) |
| `union_const` | above `morphingCut` with the menu closed the box is the same for every `m` |
| `rest_same_morph`, `rest_same_locale` | no rule at `m <= morphingCut`, and none with the menu open (one theorem per branch) |
| `visible_eq`, `probe_eq`, `probe_union_ne` | the shown region and its probe point are the original's; the union rect's point differs (390 x 844) |
| `barW_const`, `barWOrig_resizes`, `barW_ge_orig` | bar width constant; the original's grows |
| `logoX_eq`, `logoX_quad`, `actionsX_eq`, `actionsX_affine`, `barY_eq` | logo, actions and bar land where the original puts them |
| `translate_scale_order` | translate-then-scale differs from scale-then-translate for a scaled logo |
| `simpleContainer_backing`, `bar_premise_needed`, `navClip_simple`, `navOrig_draws`, `navClip_vs_orig` | no decoration + a composited bar + no other painting descendant: `drawsContent` false, 0 resident, 0 resize paint; rounded nav draws |
| `bar_normal_only`, `conservative_not_simple` | `will-change` composites the bar under Normal only; without the bar premise the nav draws |
| `wk_allocs_push` (`allocs_cold`, `allocs_growing`) | a push of n >= 3 frames at a steady size allocates 2 buffers; a size that changes every frame allocates n |
| `bar_resizePaint_zero`, `bar_orig_resizes` | the fixed bar causes no resize paint over a push; the original repaints once per size change |
| `logo3d_layout_normal`, `logo3d_layout_conservative`, `logo_translate_layout` | logo layout units per frame: 1 (original), 0 (logo-3d, Normal), 1 (Conservative, and the non-3d `translate` of bar-fixed) |
| `bar_layout_normal`, `bar_layout_conservative` | bar layout units per frame: 1 (clip-box) against 0 (bar-fixed, Normal) and 1 (Conservative) |
| `area_trade` | the union area is never below the pill area: a backing of the union is a trade unless the nav is a simple container |
| `layer_budget` | clip-box +1 layer, 0 kpx; bar-fixed +1 layer with the bar's kpx; logo-3d +1 layer with the logo's kpx |
| `requires_chain`, `writer_unchanged` | the arm order; every arm sees the faithful `--morph` sequence (CSS only), so `MorphTween.tween` proofs apply unchanged |

Premises named in the hypotheses: the bar is composited (`barComposited`), no other descendant paints into the nav, positions are exact reals
(a fractional edge may snap by 1/2 device px, INFERRED).

## Engine lines (WebKit@862f17d, `WC` = `Source/WebCore`)

| claim | status | source |
|---|---|---|
| Gap (a): the clip-path mask sits on the backdrop structural layer, so the backdrop is clipped to the pill | CONFIRMED in source; pixels not read | `GraphicsLayerCA.cpp:3353-3364` (`updateMaskLayer`: the structural layer for `StructuralLayerForBackdrop` takes the mask) |
| A composited layer's `clip-path` is a shape mask and a change is RecompositeLayer | CONFIRMED | `RenderLayer.cpp:779-791` (`willCompositeClipPath`), `RenderElement.cpp:321-326` |
| A rounded nav draws its decoration (`border-radius`), so it keeps a store; radius 0 plus a colour background is a simple container | CONFIRMED | `RenderLayerBacking.cpp:3235-3243` (`hasVisibleBoxDecorations` lists border, radius, outline, appearance, shadow, filter; not backdrop-filter, clip-path, overflow), `3426-3455`, `3509-3538` (`isSimpleContainerCompositingLayer`) |
| `clip-path` is not the `clip` property that blocks direct box decoration | CONFIRMED | `RenderElementStyleInlines.h:37-39` (`hasClip` = out-of-flow and `clip` not auto; `hasClipPath` separate) |
| `translate3d(x, 0, 0)` composites under Normal, not under Conservative | CONFIRMED | `RenderLayerCompositor.cpp:3878-3907` (`requiresCompositingForTransform`), `StyleTransformFunctionBase.h:92, 105-117` (`is3DOperation` reads the written type, so `translate3d` counts at z = 0), `StyleTranslateTransformFunction.h:55` |
| F11: a composited-bounds change sets the subsequent-layers traversal | CONFIRMED, with the condition: only when `updateCompositedBounds()` reports a change | `RenderLayerBacking.cpp:1145-1163`, `RenderLayerCompositor.cpp:1294, 1304-1309`; a fixed-size nav has constant bounds |
| F9: the view root lays out only out-of-flow boxes when only the nav resizes | CONFIRMED in part: the view relays out children only on a viewport size change | `RenderView.cpp:174-213`, `RenderBlock.cpp:765-831` |
| The unread rule of C14 (positioned child relayout): a direct absolute child is relaid out only when the parent passes `RelayoutChildren::Yes` or the child itself needs layout | CONFIRMED | `RenderBlock.cpp:894-912` (`needsLayout` lambda), `RenderBlockFlow.cpp:712-715` (Yes when the height changed) |

## CI

Runs (all MEASURED, GitHub Actions). The 2026-10-22 degradation dropped or delayed the first tips; runs of tips 3 appeared 37 min late and were superseded (stale,
skipped); the tips of checkpoint 4 (empty request commits, same code) produced the runs below.

| tip | lean | trajectory-probe (inputs read from the `trajectory inputs:` step) | breakpoint-gate (default config) |
|---|---|---|---|
| ci/nav-fixed-size cece43bf | 39831482607 success | 39831482797 `fw=nav:clip-box engines=both` verdict run, success | 39831482665 success |
| ci/nav-fixed-size-bar d6671674 | 39831504379 success | 39831504584 `fw=nav:bar-fixed`, success | not requested |
| ci/nav-fixed-size-logo 7de81c8d | 39831523626 success | 39831523593 `fw=nav:logo-3d`, success | not requested |

The probe workflow succeeds when it ran; the units are in its artifacts. Trajectory units against the faithful arm (new = fails here, not there):

| arm | chromium (hero+morph, 4 widths) | WebKit (hero path only) |
|---|---|---|
| clip-box | 291 new content units, 0 coverage; 77 cleared, 7 unmeasured | 4000 ok, 0 fail |
| bar-fixed | 391 new content units, 0 coverage | 4000 ok, 0 fail |
| logo-3d | 629 new (545 content, 84 coverage) | 4000 ok, 0 fail |

Reading (INFERRED): the new Chromium units are `nav.rect`, `nav.border-radius`, `nav.transform.shift`, `logo.rect-in-nav` (all arms) plus `logo.translate`
(bar-fixed) and `logo.scale`/`logo.transform.*` (logo-3d) during the morph. They differ by design: the nav element is the union box with `clip-path`, so its rect and
radius are not the pill's (`box_eq` proves the clipped region, not the element rect), and the logo moves by `translate`/`transform` from a different origin. The cell that compares
the clipped region instead is gpu-trajectory-cells, which is not on main: the trajectory verdict stays pending. The 84 coverage units of logo-3d at 390 are one
sample (1/62) of many properties (class and state props of a single step): a missing sample, not a value difference; rerun before reading more. WebKit's probe walks only
the hero path here, so its CLEAN says the flags are inert before the morph, nothing about the morph.

Dispatches for the lead (each is the same-look gate and the layer census for one flag, both engines, all breakpoints):
`pnpm -s fw run --gate --engines both --fw nav:clip-box --ref ci/nav-fixed-size` (also `nav:bar-fixed` with `--ref ci/nav-fixed-size-bar`, `nav:logo-3d` with `--ref ci/nav-fixed-size-logo`),
and the chromium-counts / webkit-sim layer census with `--target rewrite --fw nav:<flag>` against the faithful arm: the premise to read is `BarComposited` and nav `drawsContent=false`
(`navClip_simple`); if the census refutes it the arm is a negative finding by `area_trade` (union area >= pill area, so the backing is a trade unless the nav is a simple container).

## Follow-ups and limits

- Trajectory verdicts pending on gpu-trajectory-cells (accepted limit). Safari-on-Mac numbers belong to gpu-safari-lane.
- Same-look gate and census per flag: dispatches above. logo-3d at 430: goes to the user's look review if its pixel diff exceeds tolerance once the gate runs.
- Resize at rest no longer eases the nav width (accepted, see Design).
