# waapi-tail-webkit: why the waapi arm starts no nav width transition on WebKit (phase 1: source and instrument)

Follow-up of `10-21-waapi-nav-width-tail.md`. On macOS WebKit 1280 the waapi arm starts no `width` transition at the
flip of `is-morphing`, where the original does. Phase 1 reads the WebKit source, names the candidate mechanisms with the
observation each one predicts, and adds a recorder that tells them apart. **It makes no measurement claim.** Phase 2 is
one CI run of the recorder and the verdict from its rows.

## What is already measured (from the earlier note, MEASURED)

At the flip frame R the cand width equals W(m(R)) within 0.014 px, and the next sample is the pill width in 4 of 5
reps. A transition that started at R would show W(m(P)) at R, where P is the previous base. So there is no transition
at R. The earlier note's reading, "different style change events", is one candidate here (C1), not a fact.

## WebKit source (INFERRED mechanism, file:line@862f17d, Source/WebCore/)

| Step | Where |
|---|---|
| `updateCSSTransitionsForStyleableAndProperty`: before-change style is a clone of `lastStyleChangeEventStyle` with only the effects that animate the property applied; after-change style is a clone of the pre-animation resolved style | style/Styleable.cpp:556-770 (before: 604-616) |
| A transition starts only if no transition runs for the property, the matching duration is > 0 and before != after (`Interpolation::equals`) | style/Styleable.cpp:556-770 |
| A running transition is retargeted (cancel, restart) in step 4 | style/Styleable.cpp:705-756 |
| `oldStyle` of the transition update is `beforeResolutionStyle`, the rendered animated style; `updateCSSTransitions` runs before `applyAnimations` | style/StyleTreeResolver.cpp:814-1000 (`createAnimatedElementUpdate`) |
| With keyframe effects: `setLastStyleChangeEventStyle(clone(resolvedStyle))` records the pre-animation style, then `applyKeyframeEffects` | style/StyleTreeResolver.cpp:882-918 |
| An animation-only update takes the style from `lastStyleChangeEventStyle` when nothing is overridden after the animation | style/StyleTreeResolver.cpp:182 |
| A property in the animation layer is re-applied after animation only if important and not transition-sourced; `width` is in the running-transition map, so it is not re-resolved | style/PropertyCascade.cpp:354-390 |

Reading: the transition is decided from two styles of one style update. If the class flip and the base `--morph` write
reach the engine in different updates, or the base is the same at the flip's update, before equals after and no
transition starts.

## Candidate mechanisms and what each predicts (INFERRED, to be told apart by the rows)

| Id | Mechanism | Predicts in the rows |
|---|---|---|
| C1 | Flip and base write fall in different style updates; at the flip's update before == after width | `cls` row, then `base` row, with a `size` or `raf` row between; no `transitionrun` at the flip |
| C2 | The base is unchanged at the flip's update (the write comes in a later update or was already applied) | `base` row before the `cls` row for the same value; no `transitionrun` |
| C3 | A transition starts and is cancelled in the same or next update | `transitionrun`/`transitionstart`, then `transitioncancel` within a frame |
| C4 | A per-frame base write cancels and restarts the running transition (spec step 4) | a train of cancel/run pairs, one per frame; width not exactly the pill width at the next sample (contradicted by the measured 984.000, unless no transition runs) |
| C-probe | The probe's own per-frame `getComputedStyle` reads force a style flush between the flip and the base write, splitting the update | the same rows as C1, and the rows differ when the recorder runs without the probe's reads (the recorder never reads style, so it cannot cause this) |

In the driver, `write(hint)` and `writeBase` run in the same rAF `poll` callback, and the class flip comes in the
MutationObserver microtask of the hint write. They are normally one style update unless something forces a flush
between them. So C-probe and C2 are the likelier ones, but that is not measured.

## The recorder (apps/site/src/debug/nav-transition.ts)

Off unless the URL has `fw-debug=nav-transition`. That param is not a flag: `resolve` reads only `fw` and `preset`, so the
config hash does not change. When off, `installNavTransitionDebug` returns `null` and touches nothing (test: a mounted
`Nav` on the default URL defines no `window.__fwDebug` and adds no transition listener). When on it sets
`window.__fwDebug.navTransition = { rows, dropped }` (cap `MAX_ROWS` 6000) and records, never reading layout or computed
style:

| Row kind | Source |
|---|---|
| `data` | `data-fw-morph` attribute write (MutationObserver) |
| `cls` | `is-morphing` class flip (same observer, so the order of `data`, `cls`, `base` is the order the engine saw them) |
| `base` | inline `--morph` write (same observer) |
| `tr` | `transitionrun`, `transitionstart`, `transitionend`, `transitioncancel` of the nav itself (`target === nav`) |
| `size` | ResizeObserver border-box size, only while hot (`HOT_MS` 1500 after the last nav row) |
| `raf` | frame timestamps, only while hot |

The module sits outside `src/parts/` on purpose: the footprint generator scans every file of a part, and a debug file
inside `nav/` added clock reads to the part's footprint. `nav/index.tsx` imports it, so the line numbers of the nav
footprint shifted; `node apps/site/scripts/part-footprint.mjs --write` regenerated `footprint.gen.json` and
`FootprintData.lean` (78 lines each, line numbers only; `--check` is green).

## The probe saves the rows (packages/gate-breakpoints/src/trajectory/)

`debug.mjs` loads the rewrite arms (base and cand, never the original) with `&fw-debug=<name>` when a recorder is
requested, and `morphPass` reads `window.__fwDebug.<field>` after each rep. The rows land in
`runs[].morph.debugReps` of `raw-<engine>.json`, in the leg artifact `out/trajectory`. `null` rows mean the page did not
install the recorder (a stale build). The config lookup (`rewriteFor`, `armCheck`) uses the search without the debug
param, and `mergeRaws` refuses legs that disagree on `debug`. Tests: `test/debug.test.mjs` (table of requests, the
URL, the page reader, the merge) and `apps/site/src/debug/nav-transition.test.ts` (21 tests).

## Plumbing gap (CONFIRMED)

`trajectory-probe.yml` and Lean `store.trajectory` (the dispatch behind `fw run --trajectory`) have no debug input, and
adding one is a Lean, runner, workflow and golden change outside this task. The request therefore rides in a committed
row of `debug.requests.json` keyed on the exact search `?fw=morph.tween:waapi` (or the env var `FW_DEBUG` for a local
run). **The row must be removed with the phase 2 report**: while it exists, every dispatched run of that search records
the rows. `fw run` checks that the run's head SHA equals the worktree HEAD, so the request commit stays at HEAD.

## Hit threshold

Phase 2 takes the window length from the golden `baseWindow.delay` (`morph-tween-waapi.tail.jsonl`, the row with
`window: true`, `delay` 454556045/1048576, about 433.5; the driver reads it in `waapi.logic.ts`), not from a number
chosen here. Which reps are hits stays the earlier note's rule (`hit_iff_mP` in `Fw.Parts.MorphTweenOpt`, WidthTail).

## Phase 2 (one run, then the verdict)

`pnpm -s fw run --trajectory --engines playwright-webkit --fw morph.tween:waapi --widths 1280 --ref ci/waapi-tail-webkit`.
Read, per hit rep, the rows around the `cls` row: the order of `data`/`cls`/`base`, any `tr` rows, and the `size` and
`raf` rows between. Match them to C1 to C4 and C-probe; the table above is the key. Count classes over at least 3 runs on
separate jobs before any claim.
