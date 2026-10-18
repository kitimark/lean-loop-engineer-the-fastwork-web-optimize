---
id: 2026-10-18-guidance-proofs
kind: note
title: "Chrome Modern Web Guidance rules under our engine models: 5 proved, 3 refuted, 25 conditional, 5 out of model (19 rules × 2 engines)"
status: review
created: 2026-10-18
topics: [lean, modern-web-guidance, chromium, webkit, engine-model]
---

# Modern Web Guidance rules under the Chromium and WebKit models

Source of the rules: GoogleChrome/modern-web-guidance@b31dc0a43ff5 (the 19 rules the `chrome-agent-docs` sweep marked
"yes" or "partly" in model). Proofs: `lean/Fw/Guidance/*.lean`, under the engine models as they are on main
(`Fw.Engine.Chromium`, `Fw.Engine.WebKit`, the shared `Fw.Engine.Core`). No model change and no CI measurement. Each
cell is one rule on one engine. Verdicts:

- **proved**: the theorem states the rule.
- **refuted**: a Lean counterexample where following the rule does not lower the work.
- **conditional**: proved under a named premise.
- **out-of-model**: the missing term is named.

## Answer first

| Rule | Chromium | WebKit | Theorem | Note |
|---|---|---|---|---|
| motion.compositor-props | conditional | conditional | `Motion.cr_guide_comp`, `cr_comp_free_realChrome`, `cr_lane_ride`, `cr_filter_thread`; `wk_guide_comp`, `wk_time_comp_free` | Cr: threaded animation on, valid target, not a non-user-scrollable scroll timeline; zero main work only in real Chrome (the CI lane pays one style and one props pass). WK: no disqualifier, time timeline or threaded scroll-driven on. |
| scroll-driven.native-over-js-listener | conditional | conditional | `Scroll.cr_native_scroll`, `cr_scroll_anim_thread`; `wk_native_scroll` | Premise: the engine threads the animation. Off `comp` no more work and no callback; `comp` work rises by design. |
| sticky.scroll-state-over-listener | conditional | conditional | `Scroll.listener_lt` | Premise: the query makes the same style change as the class toggle (no scroll-state term). |
| perf.inp.layout-thrashing | conditional | conditional | `Style.batched_clean_le_one`, `batched_dirty_two`, `interleaved_total` | "At most one pass" needs a clean frame start; from a dirty start batching costs 2. Shared Core flag model. |
| css.no-js-size-measurement | proved | proved | `Style.measure_ge_two`, `native_le_one` | Any write, read, write costs ≥ 2 passes; writes alone ≤ 1. Shared Core flag model. |
| css.box-size-animation-triggers-layout | proved | proved | `Motion.cr_size_anim`; `wk_size_anim` | Main thread, layout and paint pass, every mode and layer state. |
| transitions.transform-over-inset | proved | **refuted** | `Motion.cr_transform_lt_inset`; `wk_inset_lt_transform`, `wk_transform_lt_inset_own` | WK: without an own layer an absolute-inset write is less work than a transform write (the transform also repaints). |
| perf.will-change-overuse | out-of-model | conditional | `Motion.cr_own_moving`; `wk_willChange_memory`, `wk_own_moving`, `willChange_not_dominates` | Cr: no will-change compositing reason and no backing-store term. WK: a layer only under the normal policy; a backing store only when the layer draws content. |
| perf.inp.break-long-tasks | **refuted** | **refuted** | `Tasks.cr_split_total`, `wk_split_total`; `split_slices` | Each slice is ≤ the whole (proved), but the split run pays one more props (Cr) or commit (WK) pass: total is not the same. INP is out of model. |
| perf.inp.throttle-scroll-resize | conditional | conditional | `Scroll.throttle` | Premise: the handler runs more than once per frame. |
| scroll.defer-to-scrollend | conditional | conditional | `Scroll.defer_units`, `defer_forced`; `cr_defer_more_props`, `wk_defer_more_commit` | Units and forced passes drop from `|F|` to 1 handler share; the extra `scrollend` frame adds one props (Cr) or commit (WK) pass. |
| perf.inp.split-ui-from-heavy-compute | conditional | conditional | `Tasks.off_feedback_lt` | Premise: the moved work leaves the feedback frame (a worker reply landing in it is not covered). |
| perf.inp.no-heavy-interval-polling | conditional | conditional | `Tasks.poll_lt` | Premise: a timer callback counts as script in the frame it lands in (no timer or task-queue term). |
| perf.background.pause-offscreen-work | conditional | conditional | `Tasks.pause_loop_lt`, `cr_pause_comp_real`, `cr_pause_comp_lane`; `wk_pause_comp`, `wk_pause_scroll` | Premise: the paused work is script. Pausing a compositor animation saves no main work in real Chrome or for a time-based WK animation. |
| perf.css.contain-intrinsic-size | out-of-model | out-of-model | none | Missing: content-visibility skipping, intrinsic placeholder size, layout-shift score. |
| css.has-scope | conditional | conditional | `Style.scope_lt`, `cr_has_scope`; `wk_has_scope` | Premise: one invalidated element is one style-only change (no `:has()` invalidation term). |
| perf.cls.reserve-media-space | conditional | conditional | `Stability.cr_reserve_lt`; `wk_reserve_lt` | Work side only. Premise: the decode is a paint-only change and an unreserved box also changes size. No CLS term. |
| fonts.size-adjust-fallback | out-of-model | out-of-model | none | Missing: font metrics, font swap and line-box size, layout-shift score. |
| layout.scrollbar-gutter | conditional | conditional | `Stability.cr_gutter_lt`; `wk_gutter_lt` | Premise: a scrollbar appearing without a gutter is a width (Cr) or size (WK) change of the content. |

Counts over 38 cells: 5 proved, 3 refuted, 25 conditional, 5 out-of-model.

The 18 rules marked "no" have no term in either model and get no theorem: swipe.no-main-thread-gesture-interception,
perf.inp.scheduler-yield-front-of-queue, perf.css.content-visibility-offscreen, perf.css.no-content-visibility-above-fold,
perf.css.containment-isolates-reflow, perf.lcp.image-in-html, perf.lcp.fetchpriority, perf.lcp.lazy-loading,
perf.img.formats-srcset-sizes, fonts.preload-subset, perf.crp.render-blocking, perf.js.code-splitting,
perf.fetch-priority-scripts-fetches, perf.nav.speculation-rules, perf.cache.bfcache-sw, perf.render.hidden-until-found,
perf.html.ooo-streaming-fragmentation, perf.spa.view-cache-memory.

## What the guidance gets right

- Size animation (`width`, `height`) runs on the main thread and lays out and paints every frame on both engines, in
  every mode and layer state (`cr_size_anim`, `wk_size_anim`). Proved.
- JS size measurement: any write, then a read, then a write costs at least two passes, whatever comes before, between
  and after (`measure_ge_two`). Writes alone cost at most one (`native_le_one`). Proved in the Core flag machine,
  which both engine models use.
- On Chromium a transform or translate write is strictly less work than a top or left write on every layer state and
  in every mode (`cr_transform_lt_inset`).
- The guide's five compositor properties are accelerated on both engines (`cr_guide_comp`, `wk_guide_comp`), and a
  native scroll-driven animation removes the listener's callback with no more main-thread work off `comp`
  (`cr_native_scroll`, `wk_native_scroll`).
- Callback count, interval polling, moving compute off the feedback frame and pausing JS loops are strict wins by the
  same lemma: a frame with more script callbacks is strictly more work (`Basic.frame_lt_join_script`).

## Where it is wrong or engine-dependent

- **transform over inset on WebKit (refuted).** On a box with no layer, or with a layer it does not own, an
  absolute-inset write runs style, layout and props, while a transform write runs those plus paint
  (`wk_inset_lt_transform`). The guide's advice wins on WebKit only for a box with its own layer
  (`wk_transform_lt_inset_own`); a CSS transition of `transform` gets that layer because it is accelerated.
- **break-long-tasks (refuted on both).** "Total work stays the same" is false in both models. Each slice's frame runs
  its own update, so the split run pays one more props pass (Chromium) or commit pass (WebKit) and is not a `Shift`
  (`cr_split_total`, `wk_split_total`). The part that holds: no slice is more work than the whole (`split_slices`).
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
  or commit (WebKit) pass (`cr_defer_more_props`, `wk_defer_more_commit`). Neither run dominates on passes.
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
  - INP: input delay.

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

For a part on the WebKit side, `transform-over-inset` must be checked per box: on a box without its own layer the
inset write is the cheaper one.
