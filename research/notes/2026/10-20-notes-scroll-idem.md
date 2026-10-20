---
id: notes-scroll-idem
kind: note
title: "pain.notes:visible-idem: skip the covered-frame commit that writes nothing"
status: MEASURED
created: 2026-10-20
topics: [pain.notes, react, commit, scroll, lean, optimization]
---

# pain.notes:visible-idem: skip the covered-frame commit that writes nothing

- `pain.notes:visible-idem` cuts `trace.FunctionCall` by 733 on swipe-v1 (4412-4413 to 3679-3680, -16.6 %) and by
  720-724 on swipe-touch-v1 (6329 to 5605-5609, -11.4 %), 3 runs per arm against main's `v2-proved` preset (MEASURED).
- Each covered scroll frame loses 3 calls (217 of 503 frames on swipe-v1, 221 of 531 on swipe-touch-v1). Paint,
  Layout, RasterTask and UpdateLayoutTree stay within run noise: the skipped commit wrote nothing.
- The visual is unchanged: Lean proves every element holds the same value in both arms after every event prefix
  (`scroll_dom_eq`, class E). The breakpoint gate passes
  `pain.notes` in every column on Chromium and WebKit; its only red cells are the known commission margin-inline
  flake.
- The brief's version (skip when there are no extra notes) is not E. A note moved by key and then a layout back to
  the old value shows the old place in the original and the moved place in that version (`naive_not_E`). The shipped
  variant also requires "no move since the last commit".

## Change

- `onScroll` in `apps/site/src/parts/pain.notes/driver.ts` clears the extra notes and commits the view on every scroll
  frame in which the commission card's top is above `0.995·innerHeight`. Variant `visible` does this too.
- Variant `visible-idem` (built on `visible`) skips that clear when Lean `Idem.skips` holds: no extra notes, and no
  note move since the last commit. `setPos` sets a `dirty` flag; every `view()` clears it.
- The brief's version, `if (extras.length) { extras = []; view(); }`, is not E (`naive_not_E`, below). It ignores
  moves, and React compares new props with its last committed props, not with the element.

## Why the commit is redundant (sources)

- `view()` hands React a fresh `{base, extras, dragging}` object, so `useState`'s eager bail-out (`Object.is`,
  `ReactFiberHooks.js:3677-3699`@61aa00d) never fires and every covered frame renders (CONFIRMED).
- On commit, React writes a style key only when the new value differs from the old prop
  (`CSSPropertyOperations.js:151-157`@61aa00d). The old props are the fiber's last committed `memoizedProps`
  (`ReactFiberCommitWork.js:2244-2248`@61aa00d), and other props follow the same rule
  (`ReactDOMComponent.js:2012-2020`@61aa00d) (CONFIRMED). So a commit of an unchanged view writes nothing.
- The render runs in a Scheduler task posted on a `MessageChannel` (`Scheduler.js:498, 549-551`@61aa00d). Its
  `onmessage` call is one depth-0 `FunctionCall` trace event (`v8_script_runner.cc:879-894`@f842f52). One React
  render per covered frame is therefore at most one `FunctionCall` (INFERRED: several updates in one frame batch).
- At width 860 px or less, the tick never adds an extra note, so every covered-frame commit there is redundant
  (INFERRED from `tick` in `logic.ts`, Lean `narrow_tick_id`).

## Proofs

`lean/Fw/Parts/PainNotesOpt.lean`, namespace `Fw.Parts.PainNotesOpt.Idem`. The model keeps the driver's view, React's
last committed props (`last`), the element values (`dom`) and the move flag (`dirty`). A commit writes exactly the
keys whose rendered value differs from `last` (the React rule above). A move updates the view and writes the element
without a commit (`writeNote`). Render, move and write are arbitrary.

| theorem | statement |
|---|---|
| `inv_step`, `inv_mount` | with no move since the last commit, `last` is the render of the view; every event keeps this |
| `scroll_idem` | when `skips` holds, the original's clear-and-commit leaves view, `last` and `dom` unchanged |
| `step_eq`, `run_eq` | the variant's step and whole run equal the original's (view, `last`, `dom`, flag) |
| `scroll_dom_eq` | every element holds the same value in both arms after every prefix of every event list (class E) |
| `commits_le` | the variant never commits more |
| `commits_lt` | strictly fewer commits when some covered frame meets `skips` |
| `naive_not_E` | the brief's version: move to 1, one covered frame, layout back to 0; the original shows 0, it shows 1 |
| `move_layout_stale` | the original port alone: move to 1, layout back to 0 without a commit between; the note stays at 1 |

Golden commit counts: `goldenCommits` over 7 traces (`PainNotesGolden.scrollTraces`), rows `scrollCommits` in
`packages/contracts/golden/parts/pain.notes.jsonl`. `logic.test.ts` replays each trace through the real driver
(`visible` and `visible-idem`) and counts `env.commit` calls. All rows match.

The DOM write trace is the same in both arms: the variant skips only commits that write no key. The brief expected
the trace to differ after key moves; that holds for its version only, and there the difference is visible.

## Measurements

Chromium counts, image run 39292317241, target `rewrite`, 3 runs per arm. Base `?preset=v2-proved`; arm
`?preset=v2-proved&fw=pain.notes:visible-idem` (read from each `counts.json` `meta.search`). Ranges are min-max over
the 3 runs. Run ids in `results/notes-scroll-idem/runs.json`.

| profile | counter | base | arm | delta |
|---|---|---|---|---|
| swipe-v1 | `trace.FunctionCall` | 4412-4413 | 3679-3680 | -733 (-16.6 %) |
| swipe-v1 | non-rAF calls (FunctionCall - FireAnimationFrame) | 2725 | 1992 | -733 (-26.9 %) |
| swipe-v1 | frames at exactly -3 calls | | | 217 of 503 |
| swipe-v1 | `trace.MinorGC` | 2-3 | 0-1 | -2 |
| swipe-touch-v1 | `trace.FunctionCall` | 6329 | 5605-5609 | -720 to -724 (-11.4 %) |
| swipe-touch-v1 | non-rAF calls | 4607 | 3883-3887 | -720 to -724 (-15.7 %) |
| swipe-touch-v1 | frames at exactly -3 calls | | | 221 of 531 |
| swipe-touch-v1 | `trace.MinorGC` | 2-3 | 0-1 | -2 |

- `FireAnimationFrame`, `Paint`, `Layout`, `UpdateLayoutTree` and `RasterTask` totals overlap between arms on both
  profiles (for example swipe-v1 Paint 2219-2222 vs 2218-2220; swipe-touch-v1 UpdateLayoutTree 873-874 in both).
- The per-frame drop starts at frame 61 (scrollY 520 on swipe-v1, 485 on swipe-touch-v1), where the commission card
  first rises past `0.995·innerHeight` (INFERRED), and holds to the last frame.
- 3 calls per skipped commit, not the 1 the brief expected (MEASURED). Which three callbacks they are (Scheduler
  message task, passive-effect flush or others) is not traced here (open).

WebKit Simulator (`webkit-sim`, 2 passes per arm, base run 39343967737, arm run 39343964250; both green). The reduced
scroll `FunctionCall` totals overlap (base 1691 and 1959, arm 1736 and 1626), and the harness classes the metric
quarantined. No WebKit delta is claimed.

Breakpoint gate with `fw=pain.notes:visible-idem`, run 39343960834:

| attempt | how | result |
|---|---|---|
| 1 | dispatch | red: Chromium `commission` margin-inline-start/end at sweep `pain-1440-600-1440` stop 0 (0px vs 96px) |
| 2 | re-run of failed jobs | only `merge` re-ran on the same readings; same result |
| 3 | full re-run | red: the same keys at stop 0 of `desktop-1512-320-1512` and `pain-1440-600-1440` (0px vs 132px) |

Every other cell passes on both engines. `pain.notes` passes in all 14 columns on Chromium. On WebKit it passes in 12
and two are UNREACHABLE (the reach rule). The red cell is the commission margin-inline flake named in the brief. It
moves between sweeps across attempts and is not in the part this variant changes.

## What this changes in the plan

- `visible-idem` is a candidate for the `v2-proved` preset in place of `visible`; inclusion is the lead's decision.
- General lesson: React diffs new props against its last committed props, not against the element. Once code writes
  the DOM directly (here `writeNote` on a key or drag move), a re-commit of the same view is no longer a no-op, and a
  skip must track "written since the last commit" (the `dirty` flag), not only "the view looks unchanged".
- Follow-up: `move_layout_stale` shows the port (and every variant) keeps a moved note when a later layout repeats the
  committed value. Check whether the original Svelte behaves the same (INFERRED that it does not).
- Follow-up: identify the 3 calls per React commit with a trace of one covered frame; other parts that commit on
  scroll may carry the same cost.
