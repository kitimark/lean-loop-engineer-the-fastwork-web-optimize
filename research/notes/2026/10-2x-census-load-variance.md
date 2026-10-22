# Census load variance: why two loads of the same page list different layers

Task census-load-variance (follow-up of layer-census-check). Status words: MEASURED, INFERRED, CONFIRMED.

## Question

`checkPair` refused a base-vs-base pair on the iOS Simulator lane: pass 1 and pass 2 of one session, same page, same build,
listed different undeclared layers. Which boxes differ, and why?

## Cause (MEASURED on runs 39760288475 original, 39763719675 rewrite; mechanism INFERRED until the fix run below)

Three separate causes (the third found by the fix run 39775866606). Sample sizes: one session (2 passes) per arm, 6 y positions each.

| # | cause | boxes (rewrite / original) | where |
|---|---|---|---|
| 1 | pass 1 loads deep, pass 2 loads at the top | nav bar `div.nav-module_bar` / `div.start-selling-top-nav-bar`; morph `div.morph-module_backdrop`, 3 x `div.morph-module_col`, 3 x `div.morph-module_track` (2.5 MB each), `div.morph-module_veil`, `div.morph-module_center`, `footer.morph-module_footer` / the `start-selling-*` set plus `div.start-selling-morph-panel` | pass 1 has them at y=0 and 1500, pass 2 only from y=3000 |
| 2a | timer-run animations of the page (INFERRED) | `span.accent-module_frame_*`, `svg.accent-module_svg_*...idleFrame` (bounds 60, 85 or 101 wide by word), `div.typing-module_visual_*`, `div.typing-module_beat_*` / `span.frame.svelte-*`, `svg.accent-svg.is-idle-frame`, `button.scroll-cue.svelte-*` | any y; present, absent or resized between passes |
| 2b | listed after a refusal, mechanism not found (cause 3 mechanism: not found; co-occurs with the commission section layer in 39795650433, whose state is scroll-driven and rAF-eased, not timer-run) | `span.typing-module_avatar_*`, `section.commission.*`, `div.fee-visual*`, `div.body.svelte-ty4hd7` | runs 39794304091, 39795650433, 39807770579 |

| 3 | page height of one load: `max` resolves to 5231 in pass 1 and 5267 in pass 2 (docH 6006 vs 6042), so the sample offsets differ (`samples` refusal); the `#document` root layer is 430x6006 vs 430x6042 at y=0 | root layer `#document`, last offset | run 39775866606 |

Also: layers whose reasons read `["(gone)"]` (including nodes named `?`) are torn down between the layer list and the
reasons read. The declared nav box `header.nav-module_nav` carried `is-hero-chrome-read` in pass 1 and `is-hero-pill` in
pass 2 at y=0: pass 1 had been scrolled when it loaded.

Cause 1 mechanism. The morph panel mounts from an IntersectionObserver with `rootMargin: 200% 0px` and stays mounted
(`apps/site/src/parts/morph.mount/logic.ts`, `IO_ROOT_MARGIN`; original `nodes/2.DyWL8TcE.js:13076-13086`). Pass 1 follows
the warm-up, whose scroll run ends at maxY, so `Page.reload` restores the bottom scroll position and the panel mounts at
load. Pass 2 follows `navigateTab` (a fresh navigation at scroll 0), so the panel mounts only when the census reaches
y=3000. The morph tween is wheel-driven, not scroll-driven (`morph.tween/logic.ts`), so it is not a cause.

Cause 2 mechanism. The accent word rotation and typing line run on timers, not on scroll; which layers exist at a read
depends on the phase of those animations. WebKit reports integer CSS px layer bounds
(`InspectorLayerTreeAgent.cpp:189-191@862f17d`), so a one-pixel change of an animated width is a new box.

The runner was loaded (load1 482 to 313), which widens the phase spread but is not a cause.

## Fix

1. `onePass` scrolls to 0 (`atTop`, `determinism.mjs`) before `loadFresh`, so both passes start at scroll 0, and logs
   `scroll position after the load`. TS glue, not Lean-checked (listed as a stand-in).
2. `pinStates` (`determinism.mjs`, `cli.mjs`): passes after the first read the offsets pass 1 resolved, so `max` is
   resolved once per session. TS glue, not Lean-checked (stand-in); the `samples` refusal stays and still refuses
   two arms with different offsets.
3. The census rule in Lean (`Fw.Measure.Census`): the undeclared comparison reads `stable`, the layers that are not
   declared, not `(gone)`, and not on the allowlist `runnerStems`:
   `#document` (the root layer, whose height is the page height of one load), `span.accent-module_frame_`, `svg.accent-module_svg_`, `div.typing-module_visual_`, `div.typing-module_beat_`,
   `span.typing-module_avatar_`, `span.frame.`, `svg.accent-svg.`, `button.scroll-cue.`, `section.commission.`, `div.fee-visual`,
   `div.body.svelte-ty4hd7` (12 stems, as in `census-check.mjs` and `Census.lean`). A name is free-running iff it starts with a stem
   (`varying`). Theorems: `stable_perm`, `stable_cons_gone`, `stable_cons_varying`, `stable_cons_declared`,
   `stable_cons_kept`, `stable_replicate_varying`, `stable_replicate_gone` (any count of such layers is ignored, no
   tolerance), `stable_mem_free`, `varying_of_stem`, `undeclaredAt_cons_gone`, `undeclaredAt_cons_varying`,
   `undeclaredAt_cons_kept` (a kept layer without its twin is refused), `undeclaredRefusals_eq_nil_iff`,
   `refusals_ok_iff`, `refusals_self`. Goldens (`census.jsonl`): `varying` lines and the checks `loadVarianceBase`,
   `varyingCountNotTolerated`, `goneAndVaryingBeside` (accepted), `unlistedBesideVarying`, `nearStemRefused`,
   `nearStemRefused2` (refused), `goneDeclaredNotUndeclared` (accepted), `rootHeightDiffers` (accepted). The JS twin (`census-check.mjs`) reads the same
   goldens.
4. The census of declared layers and the declared table counts are unchanged (`undeclared` is kept for them).

Cost of the allowlist. A real regression that adds a layer named like a stem is hidden; a stem is a prefix of a
hashed CSS-module or Svelte class, so a rename of the part changes the stem and the box is refused until it is added.
A box that is declared (has an `fw` or `layer` id) is never on the list. Follow-up: give the accent and typing boxes
`data-fw` ids so they are declared and counted instead of listed.

## S1 amendment (design text section 2.4)

The design file is lead scratch and not in the repo; the amendment is stated here.

S1 of path-pix-core names the node origin read by `getBoundingClientRect` as micro CSS px. WebKit's layer tree reports
integer CSS px bounds (`InspectorLayerTreeAgent.cpp:189-191@862f17d`), so the grid check reads the in-page node origin,
never the layer bounds. A layer-bounds origin carries up to one CSS px of rounding and must not be tested against the
micro grid.

## Results

Each run is one VM, one session, two fresh-load passes, six y positions (5 after pinning). Lane: webkit-sim, iOS Simulator.
Rule column: which version of the rule the stored artifact is judged by. "CI" is the verdict the run itself printed;
"re-eval" is `checkPair` (the JS twin the golden pins) applied offline to the downloaded passes.

| run | arm | commit | pass 2 vs pass 1 | note |
|---|---|---|---|---|
| 39760288475 | original | before fix | CI refused, re-eval refused | morph/nav layers only in pass 1 (start-selling nav bar) |
| 39763719675 | rewrite | before fix | CI refused, re-eval refused | same, `nav-module_bar`, morph set |
| 39775833487 | original | 5db37d95 | failed | seek stalled 741 s on the Simulator; scroll after load 0 |
| 39775866606 | rewrite | 5db37d95 | CI refused (`samples`) | both loads at scroll 0; maxY 5231 vs 5267 |
| 39785816004 | original | 2107815b | CI accepted | |
| 39791097329 | original | 2107815b + empty | CI accepted | |
| 39785868145 | rewrite | 2107815b | CI accepted | |
| 39794304091 | rewrite | 2107815b | CI refused on `span.typing-module_avatar_*`; re-eval accepted with the avatar stem | |
| 39795650433 | original | d8ae1db5 | CI refused on `section.commission.compact`, `div.fee-visual`; re-eval accepted with those stems | doc height 6042 vs 6006 |
| 39807770579 | original | 6fe61cb5 | CI refused on `div.body.svelte-ty4hd7` (hero feed, masked); re-eval accepted with that stem | |
| 39812409397 | original | 1a8f396e (final list) | CI accepted | scroll after load 0, docH 6042 both |

Net (MEASURED): after the scroll-to-top fix the morph and nav layers no longer differ in any of the eight post-fix runs.
What remains are the page's own animation phases. Of the 8 post-fix runs that finished, 4 were accepted by the rule of
their own commit (39785816004, 39791097329, 39785868145, 39812409397) and 4 were refused: 1 on the sample offsets (fixed by `pinStates`) and 3 on one more animated box each
(typing avatar, commission section and fee visual, hero feed body); each of those box lists was then added. A stem
added after a refusal is judged on the run that caused it only by re-evaluation (the same `checkPair` the golden pins),
which is not independent evidence. The one run after the last stem change (39812409397) is: accepted. The allowlist is
therefore not shown closed; the rate of one new box per refused run is the number to watch.

## Accepted limits

- The Simulator has no real GPU; a layer list here is WebKit's layer tree, not a GPU capture.
- The allowlist is by prefix of a hashed name; a rename of a part is refused until its stem is listed.
- At most 3 dispatches: the rewrite arm has 2 post-fix runs plus 1 that found the pin; the original arm runs from pushes.
