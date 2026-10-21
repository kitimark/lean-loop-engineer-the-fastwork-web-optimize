# waapi-tail-webkit: why the waapi arm starts no nav width transition on WebKit (phase 1: source and instrument)

Follow-up of `10-21-waapi-nav-width-tail.md`. On macOS WebKit 1280 the waapi arm starts no `width` transition at the
flip of `is-morphing`, where the original does. Phase 1 reads the WebKit source, names the candidate mechanisms with the
observation each one predicts, and adds a recorder that tells them apart. **It makes no measurement claim.** Phase 2 is
one CI run of the recorder and the verdict from its rows.

## What is already measured (from the earlier note, MEASURED)

At the flip frame R the cand width equals W(m(R)) within 0.014 px, and the next sample is the pill width in 4 of 5
reps. A transition that started at R would show W(m(P)) at R, where P is the previous base. So there is no transition
at R. The earlier note's reading, "different style change events", is one candidate here (C1), not a fact.

## WebKit source (INFERRED mechanism, file:line@862f17d, Source/WebCore/style/; every line below read at that commit)

| Step | Where |
|---|---|
| `updateCSSTransitionsForStyleableAndProperty` (the whole decision for one property) | Styleable.cpp:570-759 |
| Before-change style: a clone of `lastStyleChangeEventStyle`, with only the effects that animate the property applied | Styleable.cpp:606-618 |
| After-change style: a clone of the new (pre-animation) resolved style | Styleable.cpp:625-633 |
| A transition starts only if no transition runs for the property, a matching property has duration > 0 and before != after (`Interpolation::equals` at :649) | Styleable.cpp:646-651 |
| A running transition is retargeted (cancel, restart) | Styleable.cpp:694-756 |
| The transition update gets `oldStyle` = `beforeResolutionStyle` (the rendered style) and the unanimated resolved style; `updateCSSTransitions` runs there, before keyframe effects are applied | StyleTreeResolver.cpp:825 (oldStyle), :855-856 (call), :811 (`createAnimatedElementUpdate`) |
| An element with keyframe effects: the pre-animation resolved style is stored as `lastStyleChangeEventStyle`, then `applyKeyframeEffects` runs; an element without them stores its after-change style | StyleTreeResolver.cpp:887-891 (no effects), :894-896 (store), :902 (apply) |
| After the effects, the cascade is applied again for what depends on animated properties (`applyCascadeAfterAnimation`; the function is at :1076-1094) | StyleTreeResolver.cpp:907-913 (call at :910) |
| An animation-only update takes its style from `lastStyleChangeEventStyle` when nothing is overridden after the animation | StyleTreeResolver.cpp:182-183 |

Reading: the transition is decided from two styles of one style update (before: stored at the previous update; after: this
update's pre-animation style). The nav's `width` follows `var(--morph)`. The WAAPI animation animates `--morph` on the nav, so
the stored styles hold the BASE `--morph` (the inline value), while `applyCascadeAfterAnimation` (:907-913) re-resolves the
`var(--morph)`-dependent `width` from the animated `--morph`. That is why the rendered width follows the animation while the
transition decision sees only the base `--morph` and the class. If the class flip and the base write reach the engine in
different style updates, or the base is the same at the flip's update, before may equal after and no transition starts
(INFERRED; the line numbers are CONFIRMED, the consequence for this page is not measured).

## Which task writes what (INFERRED from `waapi.driver.ts` and `morph.tween/index.tsx:109-113`)

`write(v)` publishes `data-fw-morph` (the hint); `writeBase(v)` sets the inline `--morph` on the nav; the nav's own
MutationObserver (`nav/index.tsx`, on `data-fw-morph`) flips `is-morphing` in a microtask after the write. The class flip is
therefore never in the task of its cause as a script statement, but it IS before any rendering update. The flip can come from
three paths; the rows each produces (records are delivered in the order queued; the class record queued by the nav's observer
comes after the records already waiting for the recorder):

| Path | Code | Rows (one `t` = one recorder callback) |
|---|---|---|
| A: poll, a rAF callback of `everyFrame` | `poll`: `write(v)`, then `if (baseOn) writeBase(v)` (waapi.driver.ts:139-147) | `data`, `base`, `cls` at one `t`; no flush between them |
| M: marker finish, an animation finish event ("update animations and send events") | `onMarker`: `write(v)` only (:148-153) | `data`, `cls` at one `t`; the `base` row, if any, comes later at another `t` from `onBase` or a `poll` |
| P: the push (wheel task) | `push_`: `write(st.from)`, and `writeBase(st.to)` when `baseWindow` (:206-217) | `data` (if the value changed), `base`; the flip, if the data write is what crosses, follows as `cls` |

`baseWindow` is true only for a closing push (`to < from`, waapi.logic.ts:173), so `base` rows are expected in the close phase
only; path P writes the final base `st.to` at the push, `onBase` and `poll` then follow the animation from `baseDelay` on.

Which path carried a flip is read from the rows at its `cls`: `[data, base, cls]` at one `t` is A (or P with the flip in the
same task); `[data, cls]` with `base` only later is M. On M the base is written in a different callback than the flip, by
construction of the driver; on A they share a callback.

## Candidate mechanisms and what each predicts (INFERRED, to be told apart by the rows)

A style update ends at a forced flush (a `read` row: the probe's sampler reads before each sample, in a timer task) or at the
rendering update (a `raf` or `size` row of the next frame). Rows with one `t` come from one callback and share one update.
`tr` rows: the nav's own `transitionrun/start/end/cancel`.

| Id | Mechanism | Predicts in the rows |
|---|---|---|
| C1 | Flip and base write fall in different style updates through a frame boundary; at the flip's update before == after width | `cls`, then `base` at a later `t`, a `raf` or `size` row between, NO `read` row between; no `tr` at the flip. Path M produces this by construction |
| C2 | The base is already applied at the flip's update (written, and rendered, earlier) | `base`, then `cls` at a later `t` with a `raf` or `size` row between and no `read` row between; no `tr` |
| C-probe | The probe's own sampler read forces a style flush between the two writes and splits the update | a `read` row between `base` and `cls` (either order); no `tr`. The same candidate without a `read` row between is C1 or C2 |
| C3 | A transition starts and is cancelled in the same or next update | `transitionrun`/`transitionstart`, then `transitioncancel` within a frame |
| C4 | A per-frame base write cancels and restarts the running transition (step 4) | a train of cancel/run pairs, one per frame; width not exactly the pill width at the next sample (contradicted by the measured 984.000 unless no transition runs) |
| C0 | No split: `data`, `base`, `cls` at one `t` (path A) with no `read` row among them, and no `tr` | the split theory is refuted for that rep; the cause is elsewhere (for example before == after for another reason) |

C-probe is now decidable in the run itself: a `read` row between the two writes shows the probe's flush there, and its
absence rules it out for that rep. A run without the probe's reads is not needed to decide it for a rep (it would still be
the clean test of whether the probe changes the outcome overall; the workflow hardcodes `READS: full` and phase 2 plans no
such run).

## The recorder (apps/site/src/debug/nav-transition.ts)

Off unless the URL has `fw-debug=nav-transition`. That param is not a flag: `resolve` reads only `fw` and `preset`, so the
config hash does not change. When off, `installNavTransitionDebug` returns `null` and touches nothing (test: a mounted
`Nav` on the default URL defines no `window.__fwDebug` and adds no transition listener, and a cold recorder registers no
rAF). When on it sets `window.__fwDebug.navTransition = { rows, dropped }` (cap `MAX_ROWS` 6000) and
`window.__fwDebug.navTransitionRead`, and records, never reading layout or computed style:

| Row kind | Source |
|---|---|
| `data` | `data-fw-morph` attribute write (MutationObserver) |
| `cls` | `is-morphing` class flip (same observer) |
| `base` | inline `--morph` write (same observer) |
| `tr` | `transitionrun`, `transitionstart`, `transitionend`, `transitioncancel` of the nav itself (`target === nav`) |
| `size` | ResizeObserver border-box size, only while hot (`HOT_MS` 1500 after the last nav row) |
| `raf` | frame timestamps, only while hot; the loop starts at the first nav row and ends at the first frame at or past `hotUntil` |
| `read` | the probe's sampler is about to read (kit.mjs `snap` calls `navTransitionRead()`), only while hot |

`data`, `cls` and `base` come from ONE MutationObserver with `attributeOldValue`: one row per MutationRecord, in the order
of the records array, keyed on `attributeName`. The value after a record is the old value of the next record of the same
attribute, or the attribute now for the last one; a record gives a row only if that value differs from the last one logged.
(Round 1 emitted `data`, `cls`, `base` in a fixed order with one timestamp whatever the engine's order; its order test wrote
in that order and could not tell.) Tests: one task writing `--morph`, the class, then `data-fw-morph` expects `base`, `cls`,
`data`; the reverse write order expects the reverse; interleaved records of one attribute keep their own values.
`navTransitionRead` first drains the observer (`takeRecords`) so a write before the read in the same task is logged before the
`read` row.

Cost to the page, listed rather than denied: a rAF callback each frame while hot and none while cold (test); a
ResizeObserver on the nav for the whole page (INFERRED not to schedule a frame by itself; not checked in WebKit source); the
observers. In the probe the sampler's own rAF loop already runs during every phase of both rewrite arms and the original, so
the hot-only recorder loop adds no frame schedule beyond it while a phase is sampled.

The module sits outside `src/parts/` on purpose: the footprint generator scans every file of a part, and a debug file
inside `nav/` added clock reads to the part's footprint. `nav/index.tsx` imports it, so the line numbers of the nav
footprint shifted; `node apps/site/scripts/part-footprint.mjs --write` regenerated `footprint.gen.json` and
`FootprintData.lean` (78 lines each, line numbers only; `--check` is green).

## The probe saves the rows (packages/gate-breakpoints/src/trajectory/)

`debug.mjs` loads the rewrite arms (base and cand, never the original) with `&fw-debug=<name>` when `FW_DEBUG` names a
recorder, and `morphPass` reads `window.__fwDebug.<field>` after each rep. The kit stamps each sampler read into the
recorder's log. The rows land in `runs[].morph.debugReps` of `raw-<engine>.json`, in the leg artifact `out/trajectory`. `null`
rows mean the page did not install the recorder (a stale build). The config lookup (`rewriteFor`, `armCheck`) uses the search
without the debug param, and `mergeRaws` refuses legs that disagree on `debug`.

## The request: a key on the push commit line (CONFIRMED, replaces round 1's committed file)

Round 1 committed `debug.requests.json`, so a branch that landed would have turned the recorder on for every run of that
search. Round 2 removes the file. The request is a key of the push commit line,
`[trajectory fw=morph.tween:waapi widths=1280 engines=playwright-webkit debug=nav-transition]`, decided in Lean
(`Fw.Ci.Trigger`: key `debug`, allowlist `probeDebugs`, theorems `build_ok`, `build_debug_none`, `build_debug_some`,
`build_debug_unknown`; golden rows of `triggers.jsonl`; node twin `.github/scripts/trajectory-line.mjs`; unknown values are
refused). `trajectory-probe.yml` takes it as the site job output `debug` and sets `FW_DEBUG` for the probe steps. Nothing
that lands on `main` can ask for a recorder; a dispatch has no `debug` input.

The mac leg does not run on a push by default: `probe-apple` was `workflow_dispatch` only. It now also runs on a push whose
commit line carries a `debug=` key (and `apple_n != 0`); a push without the key is unchanged. That gate is YAML, not Lean,
and is listed as a stand-in in the handoff.

## Hit threshold

Phase 2 takes the window length from the golden `baseWindow.delay` (`morph-tween-waapi.tail.jsonl`, the row with
`window: true`, `delay` 454556045/1048576, about 433.5; the driver reads it in `waapi.logic.ts`), not from a number
chosen here. Which reps are hits stays the earlier note's rule (`hit_iff_mP` in `Fw.Parts.MorphTweenOpt`, WidthTail).

## Phase 2 (one run, then the verdict)

Phase 2 reads the artifact of the phase 1 run (or a re-run): per hit rep, the rows around the `cls` row: the order of
`data`/`base`/`cls`, the `t` they share, any `tr` rows, and the `read`, `size` and `raf` rows between. It classifies them
against C1 to C4, C-probe and C0 (the table above is the key) and counts classes over at least 3 runs on separate jobs
before any claim. Phase 1 shows only that rows exist for each rep.
