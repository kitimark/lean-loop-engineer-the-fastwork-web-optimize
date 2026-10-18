---
id: 2026-10-18-guidance-proofs
kind: note
title: "Chrome Modern Web Guidance rules under our engine models: 0 proved, 0 refuted, 29 conditional, 9 out of model (19 rules × 2 engines)"
status: review
created: 2026-10-18
topics: [lean, modern-web-guidance, chromium, webkit, engine-model]
---

# Modern Web Guidance rules under the Chromium and WebKit models

Source of the rules: GoogleChrome/modern-web-guidance@b31dc0a43ff5 (the 19 rules the `chrome-agent-docs` sweep marked
"yes" or "partly" in model). Proofs: `lean/Fw/Guidance/*.lean`, under the engine models as they are on main
(`Fw.Engine.Chromium`, `Fw.Engine.WebKit`, the shared `Fw.Engine.Core`). No model change and no CI measurement. Each
cell is one rule on one engine. The label is decided by the theorem as stated, never by the rule text:

- **proved**: the theorem states the guide's claim for every case the quote covers.
- **conditional**: the theorem covers a named special case or needs a named premise; the Note column names it. Where
  the premise is an encoding (it lies in the choice of frames, not in a Lean hypothesis) the note says "encoding".
- **refuted**: a Lean counterexample to the claim the guide actually makes (quoted).
- **out-of-model**: the model has no term for the guide's claim; the missing term is named.

Final design round (round 2): no new theorem, model term or mechanism; a missing theorem makes a cell conditional or
out-of-model. Counterexamples to claims the guide does not make are side findings, not refutations.

## Answer first

| Rule | Chromium | WebKit | Theorem | Note |
|---|---|---|---|---|
| motion.compositor-props | conditional | conditional | `Motion.cr_guide_comp`, `cr_comp_free_realChrome`, `cr_lane_ride`, `cr_filter_thread`; `wk_guide_comp`, `wk_time_comp_free` | Cr: threaded animation on, valid target, not a non-user-scrollable scroll timeline; zero main work only in real Chrome (the CI lane pays one style and one props pass). WK: no disqualifier, time timeline or threaded scroll-driven on. |
| scroll-driven.native-over-js-listener | conditional | conditional | `Scroll.cr_native_scroll`, `cr_scroll_anim_thread`; `wk_native_scroll` | Premise: the engine threads the animation. Off `comp` no more work and no callback; `comp` work rises by design. |
| sticky.scroll-state-over-listener | out-of-model | out-of-model | none (`Scroll.listener_lt` is a side note) | Missing: a scroll-state container query term. `listener_lt` only shows that extra script callbacks on top of the same frame are more work. |
| perf.inp.layout-thrashing | conditional | conditional | `Style.batched_clean_le_one`, `batched_dirty_two`, `interleaved_total` | "At most one pass" needs a clean frame start; from a dirty start batching costs 2. Shared Core flag model. |
| css.no-js-size-measurement | conditional | conditional | `Style.measure_ge_two`, `native_le_one` | Only write-read-write sequences: a size write precedes the measuring read in the same frame and another write follows (≥ 2 passes; writes alone ≤ 1). A plain measure-then-write from a clean frame is not covered. Shared Core flag model. |
| css.box-size-animation-triggers-layout | conditional | conditional | `Motion.cr_size_anim`; `wk_size_anim` | Main thread, layout and paint pass, every mode and layer state. Chromium: only width and height; margin and padding are in the model but not stated. WebKit: encoding, the animation's frame carries a size change (hc); WkProp.size stands for width/height. |
| transitions.transform-over-inset | conditional | conditional | `Motion.cr_transform_lt_inset`; `wk_transform_lt_inset_own` | Only per-frame JS style writes, not the guide's `@keyframes` animation (for an animation the model gives thread placement only: `cr_guide_comp`, `cr_noneligible_main`, `wk_guide_comp`, `wk_unaccel_main`). WK: only a box with its own layer. Side finding: for a script write on a WK box without its own layer the absolute-inset write is less work (`wk_inset_lt_transform`). |
| perf.will-change-overuse | out-of-model | conditional | `Motion.cr_own_moving`; `wk_willChange_memory`, `wk_own_moving`, `willChange_not_dominates` | Cr: no will-change compositing reason and no backing-store term. WK: a layer only under the normal policy; a backing store only when the layer draws content. |
| perf.inp.break-long-tasks | out-of-model | out-of-model | none (`Tasks.split_slices`, `cr_split_total`, `wk_split_total` are side notes) | Guide: "Any JavaScript execution exceeding 50ms should be split. Yield to the main thread frequently so the browser can process pending user inputs." Missing: task duration in ms, pending input and input delay. Side notes: each slice is ≤ the whole (`split_slices`, ≤ only); the split run pays one more props (Cr) or commit (WK) pass. |
| perf.inp.throttle-scroll-resize | conditional | conditional | `Scroll.throttle` | Premise: the handler runs more than once per frame. |
| scroll.defer-to-scrollend | conditional | conditional | `Scroll.defer_units`, `defer_forced`; `cr_defer_more_props`, `wk_defer_more_commit` | Units and forced passes drop from `|F|` to 1 handler share. Side note: the extra `scrollend` frame adds one props (Cr) or commit (WK) pass, shown only for a handler with no forced layout. |
| perf.inp.split-ui-from-heavy-compute | conditional | conditional | `Tasks.off_feedback_lt` | Premise: the moved work leaves the feedback frame (a worker reply landing in it is not covered). |
| perf.inp.no-heavy-interval-polling | conditional | conditional | `Tasks.poll_lt` | Premise: a timer callback counts as script in the frame it lands in (no timer or task-queue term). |
| perf.background.pause-offscreen-work | conditional | conditional | `Tasks.pause_loop_lt`, `cr_pause_comp_real`, `cr_pause_comp_lane`; `wk_pause_comp`, `wk_pause_scroll` | Premise: the paused work is script. Pausing a compositor animation saves no main work in real Chrome or for a time-based WK animation. |
| perf.css.contain-intrinsic-size | out-of-model | out-of-model | none | Missing: content-visibility skipping, intrinsic placeholder size, layout-shift score. |
| css.has-scope | conditional | conditional | `Style.scope_lt`, `cr_has_scope`; `wk_has_scope` | Encoding: one invalidated element is one style-only change (no `:has()` invalidation term). |
| perf.cls.reserve-media-space | conditional | conditional | `Stability.cr_reserve_lt`; `wk_reserve_lt` | Work side only. Encoding: the reserved arm is a paint-only change (`bgImage` Cr, `background` WK), the unreserved arm a height (Cr) or size (WK) change alone, not decode plus size change. No CLS term. |
| fonts.size-adjust-fallback | out-of-model | out-of-model | none | Missing: font metrics, font swap and line-box size, layout-shift score. |
| layout.scrollbar-gutter | conditional | conditional | `Stability.cr_gutter_lt`; `wk_gutter_lt` | Encoding: a scrollbar appearing without a gutter is a width (Cr) or size (WK) change of the content. |

Counts over 38 cells: 0 proved, 0 refuted, 29 conditional, 9 out-of-model.

The 18 rules marked "no" have no term in either model and get no theorem: swipe.no-main-thread-gesture-interception,
perf.inp.scheduler-yield-front-of-queue, perf.css.content-visibility-offscreen, perf.css.no-content-visibility-above-fold,
perf.css.containment-isolates-reflow, perf.lcp.image-in-html, perf.lcp.fetchpriority, perf.lcp.lazy-loading,
perf.img.formats-srcset-sizes, fonts.preload-subset, perf.crp.render-blocking, perf.js.code-splitting,
perf.fetch-priority-scripts-fetches, perf.nav.speculation-rules, perf.cache.bfcache-sw, perf.render.hidden-until-found,
perf.html.ooo-streaming-fragmentation, perf.spa.view-cache-memory.

## What the guidance gets right

- Size animation (`width`, `height`) runs on the main thread and lays out and paints every frame on both engines, in
  every mode and layer state (`cr_size_anim`, `wk_size_anim`). Conditional: Chromium only for width and height, WebKit under the encoding premise that the frame carries the size change.
- JS size measurement, write-read-write case only (conditional): a write, then a read, then a write costs at least
  two passes, whatever comes before, between and after (`measure_ge_two`). Writes alone cost at most one
  (`native_le_one`). A read then a write from a clean frame is not covered. Core flag machine, used by both engines.
- On Chromium a transform or translate script write is strictly less work than a top or left script write on every
  layer state and in every mode (`cr_transform_lt_inset`). Conditional: per-frame JS writes, not `@keyframes`.
- The guide's five compositor properties are accelerated on both engines (`cr_guide_comp`, `wk_guide_comp`), and a
  native scroll-driven animation removes the listener's callback with no more main-thread work off `comp`
  (`cr_native_scroll`, `wk_native_scroll`).
- Callback count, interval polling, moving compute off the feedback frame and pausing JS loops are strict wins by the
  same lemma: a frame with more script callbacks is strictly more work (`Basic.frame_lt_join_script`).

## Where it is wrong or engine-dependent

- **transform over inset (conditional on both).** The guide's claim is about `@keyframes` animations; every work
  theorem here compares per-frame JS style writes. For script writes on WebKit the transform write wins only on a box
  with its own layer (`wk_transform_lt_inset_own`). Side finding, scoped to script writes: on a box with no layer, or
  with a layer it does not own, an absolute-inset script write runs style, layout and props, while a transform script
  write runs those plus paint (`wk_inset_lt_transform`). This is not a counterexample to the `@keyframes` claim; for
  an animation the model only places `transform` on the compositor and an unaccelerated inset on the main thread
  (`wk_guide_comp`, `wk_unaccel_main`; Cr `cr_guide_comp`, `cr_noneligible_main`).
- **break-long-tasks (out of model on both).** The guide says "Any JavaScript execution exceeding 50ms should be
  split. Yield to the main thread frequently so the browser can process pending user inputs." The models have no task
  duration, pending input or input delay. Side notes: no slice is more work than the whole (`split_slices`, ≤ only).
  Each slice's frame runs its own update, so the split run pays one more props pass (Chromium) or commit pass (WebKit)
  and is not a `Shift` (`cr_split_total`, `wk_split_total`): a finding about total work, a claim the guide does not
  make.
- **Compositor properties are engine-dependent.**
  - Chromium also composites a non-blur `filter` and `backdrop-filter`, which the guide omits, and never a blur
    (`cr_filter_thread`).
  - The "no main-thread work" claim holds in shipping Chrome (`cr_comp_free_realChrome`) but not in the CI lane, which
    pays one style and one props pass per frame (`cr_lane_ride`).
  - On WebKit a scroll-timeline animation restyles its target whenever the frame updates (`wk_pause_scroll`).
- **Layout thrashing.** "At most one lifecycle pass" holds only when the frame starts clean (`batched_clean_le_one`).
  If something dirtied style before the batch, the first read forces a pass and the writes need another
  (`batched_dirty_two`).
- **defer to scrollend.** Units and forced passes go from one handler share per scrolled frame to one share in total
  (`defer_units`, `defer_forced`). The deferred handler runs in a frame of its own, which pays one more props (Chromium)
  or commit (WebKit) pass (`cr_defer_more_props`, `wk_defer_more_commit`). Neither run dominates on passes. Scope:
  those two theorems use a handler with no forced layout (a transform write), outside the rule's layout-dependent
  case; no theorem covers the extra pass for a layout-dependent handler.
- **Pausing offscreen work.** For a compositor animation the saving is empty on the main thread in real Chrome and for
  a time-based WebKit animation (`cr_pause_comp_real`, `wk_pause_comp`). It is one style unit in the CI lane
  (`cr_pause_comp_lane`) and for a WebKit scroll-driven animation (`wk_pause_scroll`). JS loops are always a win.
- **will-change.**
  - WebKit makes a layer for it only under the normal compositing policy, not the conservative one.
  - A layer holds a backing store only when it draws content or delegates display (`wk_willChange_memory`), so memory
    does not grow with every element.
  - Extra layers are never a dominating claim (`willChange_not_dominates`); on a moving box they lower per-frame work
    on both engines (`cr_own_moving`, `wk_own_moving`).
  - Chromium has no will-change term, so the memory side is out of model there.
- **Throttling scroll and resize handlers** only helps when the handler runs more than once per frame (`throttle`, case
  `k = n`). The HTML event loop already dispatches `scroll` and `resize` at most once per frame in "update the
  rendering". INFERRED: the step was not re-read for this note.
- **Out of model, follow-ups.** Missing terms by rule:
  - contain-intrinsic-size: content-visibility skip and intrinsic placeholder size;
  - size-adjust fallback: font metrics, font swap and line-box size;
  - both, and reserve-media-space: a layout-shift score;
  - Chromium will-change: a compositing reason and a backing-store term;
  - sticky headers: a scroll-state container query;
  - INP and long tasks: task duration, pending input, input delay.

## Which of our parts each rule touches

| Rule | Parts (from the sweep, INFERRED where the sweep says so) |
|---|---|
| motion.compositor-props | hero.exit, hero.countdown, morph.columns, morph.tween |
| scroll-driven.native-over-js-listener | hero.exit (per-scroll-frame `--exit-opacity`; view-timeline variant in `Fw/Parts/HeroExitOpt.lean`) |
| sticky.scroll-state-over-listener | hero.exit (sticky hero in a 200vh track), nav.hitTest |
| perf.inp.layout-thrashing | nav.hitTest, hero.exit, hero.countdown, morph.tween, morph.mount, platform |
| css.no-js-size-measurement | morph.tween, hero.exit |
| css.box-size-animation-triggers-layout | hero.exit, platform |
| transitions.transform-over-inset | hero.countdown, hero.exit, platform |
| perf.will-change-overuse | hero.exit, hero.countdown, morph.columns, morph.countdown, platform |
| perf.inp.break-long-tasks | engine.scroll, morph.tween, hero.exit, hero.countdown |
| perf.inp.throttle-scroll-resize | engine.scroll, morph.mount |
| scroll.defer-to-scrollend | morph.mount, morph.tween, hero.exit, nav.hitTest |
| perf.inp.split-ui-from-heavy-compute | none |
| perf.inp.no-heavy-interval-polling | hero.countdown, morph.countdown, platform |
| perf.background.pause-offscreen-work | engine.scene, morph.columns, morph.tween, platform, platform.entries |
| perf.css.contain-intrinsic-size | none |
| css.has-scope | platform (`:has` in platform.module.css) |
| perf.cls.reserve-media-space | platform, morph.columns |
| fonts.size-adjust-fallback | none (site-wide text) |
| layout.scrollbar-gutter | engine.scroll |

For a part on the WebKit side that moves a box by script writes, `transform-over-inset` must be checked per box: on a
box without its own layer the absolute-inset script write is the cheaper one.
