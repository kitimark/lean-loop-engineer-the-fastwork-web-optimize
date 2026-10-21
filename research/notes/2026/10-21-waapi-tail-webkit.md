# waapi-tail-webkit: why the waapi arm starts no nav width transition on WebKit (phase 1: source and instrument; phase 2: the rows and the verdict)

Follow-up of `10-21-waapi-nav-width-tail.md`. On macOS WebKit 1280 the waapi arm starts no `width` transition at the
flip of `is-morphing`, where the original does. Phase 1 reads the WebKit source, names the candidate mechanisms with the
observation each one predicts, and adds a recorder that tells them apart. Phase 1 made no measurement claim. Phase 2
(`waapi-tail-webkit-p2`, last section) classifies the rows of three macOS WebKit runs and decides the base window.

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
four paths; the rows each produces (records are delivered in the order queued; the class record queued by the nav's observer
comes after the records already waiting for the recorder):

| Path | Code | Rows (one `t` = one recorder callback) |
|---|---|---|
| A: poll, a rAF callback of `everyFrame` | `poll`: `write(v)`, then `if (baseOn) writeBase(v)` (waapi.driver.ts:137-146) | `data`, `base`, `cls` at one `t`; no flush between them |
| M: marker finish, an animation finish event ("update animations and send events") | `onMarker`: `write(v)` only, then starts the poll (:147-153) | `data`, `cls` at one `t`; the `base` row, if any, comes later from `onBase` or a `poll` |
| P: the push (wheel task) | `push_` (:177-221): `write(st.from)` at :205, and `writeBase(st.to)` at :216 inside `if (baseWindow(...))` (:215-220) | `data` (if the value changed), `base`; the flip, if the data write is what crosses, follows as `cls` |
| S: the settle, `first.onfinish` (:206-208) calls `settleFlight` (:167-175) | `write(st.value)`, then `writeBase(st.value)` if `baseOn` was on (:172-173), in the finish event of the first animation | `data`, `base`, `cls` at one `t`, from an animation finish event, not from a rAF callback |

`baseWindow` is true only for a closing push (`to < from`, waapi.logic.ts:173), so `base` rows are expected in the close phase
only; path P writes the final base `st.to` at the push, `onBase` and `poll` then follow the animation from `baseDelay` on.

Which path carried a flip is read from the rows at its `cls`: `[data, base, cls]` at one `t` is A or S (the rows do not separate them;
they differ in the event that ran the callback); `[data, cls]` with `base` only later is M. On M the base is
written in a different callback than the flip, by construction of the driver; on A and S they share one.

Reading rows (corrected in phase 2): a `raf` row whose frame timestamp `ts` is at or before the flip's own `t` (within 2 ms)
is the flip's own frame, not a boundary. Only a `size` row, a `read` row, or a `raf` row with a later `ts` proves another
style update or rendering update between two writes. Phase 1's rule "a raf row between means C1 or C2" was wrong for that case.

## Candidate mechanisms and what each predicts (INFERRED, to be told apart by the rows)

A style update ends at a forced flush (a `read` row: the probe's sampler reads before each sample, in a timer task) or at the
rendering update (a `raf` or `size` row of the next frame). Rows with one `t` come from one callback and share one update.
`tr` rows: the nav's own `transitionrun/start/end/cancel`.

| Id | Mechanism | Predicts in the rows |
|---|---|---|
| C1 | Flip and base write fall in different style updates through a frame boundary; at the flip's update before == after width | `cls`, then `base` at a later `t`, a `size` row or a `raf` row of a later frame between, NO `read` row between; no `tr` at the flip. Path M produces this by construction |
| C2 | The base is already applied at the flip's update (written, and rendered, earlier) | `base`, then `cls` at a later `t` with a `size` row or a `raf` row of a later frame between and no `read` row between; no `tr` |
| C-probe | The probe's own sampler read forces a style flush between the two writes and splits the update | a `read` row between `base` and `cls` (either order); no `tr`. The same candidate without a `read` row between is C1 or C2. Read the corrected rule above for what "between" needs |
| C3 | A transition starts and is cancelled in the same or next update, by nothing the page wrote | `transitionrun`/`transitionstart`, then a width `transitioncancel` with no write one frame before it |
| C4 | A per-frame base write cancels and restarts the running transition (step 4) | two or more width `transitioncancel` rows, each one frame after a write (WebKit dispatches transition events in the frame after the style update) |
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

The mac leg does not run on a push by default. Whether it runs is decided in Lean (phase 2): `Fw.Ci.Trigger.appleRuns`
(`ProbeEv`, `hasFrames`, `recorderOf`; theorems `apple_no_leg`, `apple_dispatch`, `apple_push_frames`, `apple_push_debug`,
`apple_push_plain`, `apple_push_asked`; 40 `kind:"apple"` rows in `triggers.jsonl`; node twin `appleRuns` in
`.github/scripts/trajectory-line.mjs`, mode `apple`). `trajectory-probe.yml` runs the twin in the plan step and reads its
`apple_run` output in `probe-apple.if`; the YAML holds no rule. Runs 2 and 3 below ran the mac leg through that output.

## Hit threshold

Phase 2 takes the window length from the golden `baseWindow.delay` (`morph-tween-waapi.tail.jsonl`, the row with
`window: true`, `delay` 454556045/1048576, about 433.5; the driver reads it in `waapi.logic.ts`), not from a number
chosen here. Which reps are hits stays the earlier note's rule (`hit_iff_mP` in `Fw.Parts.MorphTweenOpt`, WidthTail).

## Phase 2: the rows of three runs, the class of each rep, the verdict (MEASURED)

**Runs** (push-triggered, commit lines `[ci:trajectory-probe]` and `[trajectory fw=morph.tween:waapi widths=1280
engines=playwright-webkit debug=nav-transition]`, mac leg `probe apple (playwright-webkit, macos-26) 1280`, separate jobs;
the inputs artifact of each shows engines, fw, widths and debug as pushed):

| Run | Commit | Note |
|---|---|---|
| 39571243779 | 8ae4a8f9 | run 1 |
| 39572308204 | b9afdb74 | run 2; first run with the mac leg decided by `apple_run` |
| 39573516482 | 6529fbb4 | run 3 |
| 39527354981 | 47ec2d5a | phase 1 run, an extra data point (same recorder, before the Lean rule) |

Each run has 5 reps of the role `base` (inline writes, no animation; the control) and 5 of the role `cand` (the waapi arm with
the window); the original has no recorder. The unit is the first close flip
(`cls` with `on: false`) of a rep. The classifier is `Fw.Parts.MorphTweenWebkit` (Lean; `splitRep`, `transRep`, `classRep`,
`holdRep`, `verdict`); its node twin `classifyRep`, `holdRep`, `windowVerdict` in `debug.mjs` equals the Lean golden
`morph-tween-webkit-rows.jsonl` (14 rep cases: 4 real excerpts and 10 synthetic, one per class and edge; 8 verdict cases) in
`test/webkit-rows.test.mjs`, and gives the same class and hold on the full raw files as the Lean run on them.

**Rule fix.** A `raf` row at or before the flip's own time is the flip's frame, not a boundary (see the paths section).

### Classes per rep (class / hold; reps 0..4)

| Run | Arm | Reps |
|---|---|---|
| 39571243779 | base | c0/held c0/held c0/held c4/held c4/held |
| 39571243779 | cand | c4/jumped c0/jumped c4/jumped c0/jumped c0/jumped |
| 39572308204 | base | c4/held c0/held c4/held c0/held c4/held |
| 39572308204 | cand | c0/jumped c4/jumped c0/jumped c0/jumped c0/jumped |
| 39573516482 | base | c0/held c4/held c0/held c0/held c0/held |
| 39573516482 | cand | c0/jumped c0/jumped c0/jumped c0/jumped c0/jumped |
| 39527354981 | base | c4/held c0/held c0/held c4/held c4/held |
| 39527354981 | cand | c0/jumped c4/jumped c4/jumped c0/jumped c0/jumped |

Counts over the three runs (15 reps per arm): split class **c0 in 30 of 30**; no c1, c2, c3, C-probe, noFlip or noBase. Cand: c0 12,
c4 3, jumped 15. Base: c0 9, c4 6, held 15. The phase 1 run agrees (c0 in 10 of 10, cand jumped 5, base held 5).

**Reading of one rep.** In every cand rep the rows at the flip are `data` and `cls` at one `t` (path M: the marker finish
writes the data only), then a `raf` row of the same frame (it may also come after the next row) and the `base` row with the identical value 0 to 1 ms
later (the poll's rAF callback of that frame). No `read` and no `size` row lies between them. In the base arm `base`, `data` and `cls`
sit at one `t`. A width `transitionrun`/`transitionstart` appears 21 to 135 ms after the flip in both arms. The difference is
the first `size` row after the flip: the base arm keeps its width (15 of 15, next == prev), the cand arm drops to within 0.21 px of
rest (0.00 to 0.21 px above rest) from 0.33 to 2.4 px above rest.

### What the classes decide

| Candidate | Decision | Why |
|---|---|---|
| C1, C2 (writes in different style updates) | refuted for these reps (0 of 30) | no `size`, `read` or later-frame `raf` row lies between `data`, `cls` and `base`: one style update |
| **C-probe** | **ruled out** | the probe's reads occur only between frames, never between the writes (no `read` row between in 30 of 30); the probe does not split the update, so no run without reads is needed |
| C3 (a transition cancelled by nothing) | 0 of 30 | no width cancel without a write one frame before it |
| C4 (a train of cancels by writes) | present in 9 of 30 reps, in both arms | two or more width cancels, each a frame after a write; it does not separate the arms (cand: 3 of 15 c4 and 15 of 15 jumped; base: 6 of 15 and 15 of 15 held), so it does not explain the jump |
| C0 (no split) | class of 21 of 30 reps; the split is c0 in all 30 | the split theory is refuted: `data`, `cls` and `base` reach one style update. The cause of the missing tail is elsewhere |

Mechanism left (INFERRED, to be tested in a follow-up, not decided here): the before-change style of the transition comes from
the rendered style, and the width in it already follows the animated `--morph`, so before is close to after at the flip's update;
Styleable.cpp:606-618 and StyleTreeResolver.cpp:825 are the lines.

### Verdict on the base window (decided in Lean)

`Fw.Parts.MorphTweenWebkit.verdict runs holds`: no claim under 3 runs; keep iff some hit rep held; drop iff some rep jumped and
none held (theorems `verdict_needMore`, `verdict_keep`, `verdict_drop`, `verdict_unseen`, `drop_no_held`). The hold of a rep is
`holdRep`: unseen when the width before is within 0.08 px of rest, held when the first width after keeps at least half of the
excess over rest, else jumped (`holdOf_flat`, `holdOf_held`, `holdOf_jumped`). Evidence: runs 39571243779, 39572308204 and
39573516482 hold 15 jumped cand reps and no held rep, so `drop_on_measured : verdict 3 (replicate 15 jumped) = .drop`.

**Decision: drop the base-write window on macOS WebKit at 1280.** With the window on, no rep restores the old width (0 of 15; 0 of
20 with the phase 1 run), so the window gives no width on WebKit and costs about 9 script frames per close at 60 Hz
(`closeCost`, earlier note). Limits: one engine (Playwright WebKit on macos-26) and one width (1280); a run with the window
off was not made, so "drop" means the window does nothing visible, not that the transition then starts. The code change (gate the
window on the engine, or remove it) is not in this task; it is the follow-up `waapi-tail-drop`. Chromium keeps its own verdict
from the earlier note.

### TS stand-ins

The node twin of the classifier is checked against the Lean golden (not a stand-in). Stand-ins: the recorder itself and the
probe plumbing (`apps/site/src/debug/nav-transition.ts`, `debug.mjs` `debugFor`, `readDebug`), the page-side row capture, and
the JSON-to-row normaliser `normalizeRow` (its rounding is the Lean `scaled`, tested on a sample, not proved).

### Follow-ups

- `waapi-tail-drop`: gate or remove the window on WebKit, then a Chromium and WebKit class count of the result.
- Why the cand width at the first size row after the flip is W(m(R)): read the before-change style source (Styleable.cpp:606-618)
  against the rows; a run with the window off would show whether the transition then starts.
- Frames: WebKit logs `size` rows in frames that have no `raf` row, so a `raf` row is not a complete frame list.
