# hero.countdown `one-chain`: the per-digit rAF chains in one shared-loop callback (discovery R7, hero half)

Flag `hero.countdown:one-chain`, commit 75b08603 on ci/countdown-one-chain. Lean `Fw.Parts.HeroCountdownOneChain`,
golden `packages/contracts/golden/parts/hero.countdown.onechain.jsonl`, TS `oneChainClock` in
`apps/site/src/parts/hero.countdown/driver.ts`, counts table `results/countdown-one-chain/counts.md`.

## Answer

- **Win on script work, MEASURED.** FireAnimationFrame and FunctionCall both drop by 243 on swipe-v1 (2058 → 1815,
  -11.8 %) and by 252 on swipe-touch-v1 (2112 → 1860, -11.9 %), 3 of 3 shards each. Every scrolled zone gains, from
  -13 to -41 per zone; the mount zone `rest` halves (20 → 9).
- Style, layout and paint are unchanged on swipe-v1 (UpdateLayoutTree 1849, Layout 358, RecalcStyleCount 1832 on both arms).
  On swipe-touch-v1 one frame (499, the first `settle` frame) gains one forced style recalc: UpdateLayoutTree and
  RecalcStyleCount +1, elementCount +10. This is a small new cost, explained below.
- The visual is unchanged by construction: the 10 faces, the `setInterval(1000)` and every transform write stay the
  same (Lean `oneChain_writes_eq`). The breakpoint gate passes the hero.countdown row in every reachable column
  on both engines (run 39313815482): all 14 on Chromium, 12 on WebKit plus 2 UNREACHABLE by the Lean reach rule. The
  run fails on 4 unrelated commission items, explained below.

## Mechanism

`faithful` runs the original's scheduling. A 1 s interval refreshes the clock reading. Each digit whose target changes
gets its own rAF chain (`stop(i)` and then a new registration), and the chain ends when its spring settles. Each chain
costs one rAF callback per frame. Engines call the callbacks of a frame one by one, and each call is one
FireAnimationFrame plus one FunctionCall (CONFIRMED):
- Chromium `frame_request_callback_collection.cc`@f842f52: callbacks are swapped into a snapshot at :86, then each one
  is traced and invoked with the same `high_res_now_ms` at :99-125 (FireAnimationFrame at :114, Invoke at :123).
- WebKit `ScriptedAnimationController.cpp`@862f17d: the timestamp is taken at :156, the list is copied at :162, and
  :178-200 run `willFireAnimationFrame`, invoke and `didFireAnimationFrame` once per callback (198-200).

`one-chain` gives `startFaithful` a clock adapter. The adapter keeps each `{ own: true }` chain in a set and runs the
set, in registration order, from one subscriber of the shared loop. That subscriber exists only while the set is
non-empty. The calls, their order and their timestamps are the same as in `faithful`, so each frame pays one callback
instead of one per rolling digit. When another part already keeps the shared loop alive, the digits add no callback at
all.

## Lean (all theorems use only propext and Quot.sound)

- `oneChain_frame_eq`: one frame of `oneChainCbs` equals one frame of `faithfulCbs`.
- `oneChain_writes_eq`: over any run of refreshes and frames, both variants step the same digits per event, in the
  same order, with the same writes and the same states. `order_perm` adds that any permutation of the active digits
  gives the same states and the same writes up to order, so the result does not hang on the iteration order.
- `faithful_rafs` and `oneChain_rafs`: per frame, `faithful` pays one callback per stepped digit and `one-chain` pays
  min 1 of that.
- `oneChain_raf` (two or more rolling digits mean fewer callbacks) and `oneChain_raf_eq` (one digit or none means
  equal callbacks).
- Page level (`pageFaithful`, `pageOneChain`): `page_le` holds always. `page_lt_shared` gives a strict saving with one
  digit rolling while the shared loop has other subscribers. `page_eq_alone` and `page_eq_still` give no saving
  otherwise.
- The golden has 6 scenarios: mount, ones, tens, minute, restart mid-roll and still. The vitest replays each one
  through the real `startFaithful` and fake rAF and timer queues, for both clocks. It checks the steps and the
  callback counts per frame.

The measured drop fits `page_lt_shared`. During a swipe the scroll engine and other parts keep the shared loop running,
so every frame in which the ones digit rolls saves its callback, not only the frames where two or more digits roll.

## The forced recalc on swipe-touch-v1, INFERRED

In frame 499, all 3 shards, faithful has 1 UpdateLayoutTree of 320 elements and one-chain has 2, together covering
330 elements. The FireAnimationFrame count is 4 on both arms. The 10 extra elements equal one digit's 10 faces.

Reading: the digits now step inside the shared loop at the position of their subscriber in the clock's subscriber
set. In `faithful` they step in their own callbacks after the shared loop's callback. In this frame a shared
subscriber that reads layout runs after the countdown wrote a face transform, so the read forces a style update.
`window.scrollY` is one such read: it calls `UpdateStyleAndLayout` (Chromium
`local_dom_window.cc:1877`@f842f52). I have not identified which subscriber read in frame 499; the artifacts hold
counts only, no trace stacks.

What the existing counts add (MEASURED, runs 39313842964 one-chain / 39313910496 faithful, `counts.json` frames
496-502, all 3 shards):
- Frame 499 also has ScheduleStyleRecalculation 2 against 1. So style went dirty, clean, then dirty again inside the
  frame: one more invalidate-and-update cycle, not a larger single one.
- Layout, LayoutCount, FireAnimationFrame, RequestAnimationFrame and FunctionCall are equal in frame 499. The extra
  update is style only, which fits a face-transform write followed by a read: a transform dirties style and not layout.
- Frames 496-498 show the expected saving (FireAnimationFrame 3 against 4, 4 against 5), and frames 500-502 differ only
  in EventDispatch and FunctionCall noise that changes from shard to shard.

Narrowing, INFERRED. `createRafClock` iterates its `Set` of subscribers with `for...of`, and a `Set` iterator also
visits entries added during the walk (ECMA-262 CreateSetIterator walks the entry list by index). The one-chain
subscriber is added when a chain starts, so any shared subscriber added after it, for example one that a part adds when
the swipe settles, runs after the face writes in the same frame. The footprint lists the shared-clock (`ctx: clock`)
layout reads that could be it: `rect` in commission (`driver.ts` 128, 129, 155; `index.tsx` 89), pain.notes
(`index.tsx` 75-81), people.card (`index.tsx` 49-53) and hero.orbit (`driver.ts` 80, `clientWidth`). Telling them
apart needs a trace with stacks. The chromium-counts lane uploads `counts.json` and zones only and has no input for
a raw trace, so this stays open.

Lean gap: `oneChain_writes_eq` covers the countdown's own writes and their order. It does not model other parts'
reads in the same frame. Lesson: moving work into a shared callback keeps the work but changes its position relative
to other parts' reads. A scheduling proof is page-exact only when it fixes that position. One option is a clock API
that runs the group last in the shared frame; whether it is worth it is an open item.

## The strip claim, retired

`strip_claim` (`HeroCountdownOpt.lean`) says that with no rolling digit the strip run equals the faithful run, so the
claim is `noClaim`. That holds for render work only. `strip` schedules through `createCountdownDriver.tick` on an
always-on shared subscriber (index.tsx `stripSubscribe`). `strip_schedule_still_gt` proves that in a still frame with
no other shared subscriber, this costs 1 callback where the original costs 0 (`pageFaithful false own 0 <
pageAlwaysOn false own 0`). `oneChain_le_alwaysOn` proves that `one-chain` never costs more than the always-on
scheduling. So the strip's script cost is not "equal when still". A strip DOM with `one-chain` scheduling would keep
both savings; that is a follow-up, not part of this flag.

## Gate

Run 39313815482 (engines both, `?fw=hero.countdown:one-chain`):
- WebKit passes every row.
- Chromium passes every row except `commission`, which fails 1 of 5 probes in sweep `pain-1440-600-1440` step 0:
  `inner` and `rows` `margin-inline-*` read orig "0px" against rewrite "96px"/"8px".
- The same 4 items fail with the same values on ci/exit-scoped-var (run 39314391342, flag `hero.exit:scoped`). That
  flag shares no code with this one. This is the known content-visibility reading of fix-commission-margin, not this
  variant.

Run 39318057726, scoped with `parts=hero.countdown`, has 301 passing readings, 0 failing and 3 excused on each engine.
Its merged verdict is still "refused": the narrowed run counts the 28 out-of-scope cells per engine as `not-run`, so a
narrowed gate never reaches pass. Both runs are in `results/countdown-one-chain/gate.md`.

## Limits

- Chromium counts only. WebKit has the same per-callback loop (cited above) but no measured count here.
- The morph.countdown half waits for morph-layers.
- Footprint rows for the new TS lines wait for the FootprintData regeneration (owned by morph-layers).
