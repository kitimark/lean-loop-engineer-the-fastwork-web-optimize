# evidence-twins handoff

Branch `worktree-wf_9bb74026-560-1`, worktree `.claude/worktrees/wf_9bb74026-560-1`, no CI push (accepted limit: existing artifacts only), so no run ids.
Work commit eec2d8508 (code, tests, Lean, golden); note `research/notes/2026/10-2x-evidence-twins.md`.

**Done:** TS `cmpKnown`, `lookKnown`, `known`, `MIN_SAMPLES` in `packages/measure-webkit/src/touchlock.mjs` replay golden ops
`cmpKnown`/`lookKnown` (`touchlock.test.mjs`); `summarize` uses them. `morph-end-report.mjs` prints `cmpKnown`; `toolbar.mjs` adds
`cmpByKnown`/`columnsKnown`, `toolbar-report.mjs` prints them. Lean `TouchLock.minSamples` 1 to 3; `known_iff` restated,
`known_ne_nil`, `cmpKnown_one_*`, `lookKnown_one_*`; complete-evidence equality theorems kept; golden regenerated (constants gain
`minSamples`; own `cmpKnownCases`/`lookKnownCases` with 3-value complete rows and short rows).
**Floor 3 reason:** every decision cell in the toolbar, morph-end and pooled touch-lock artifacts holds 3 or more per side; only
per-job touch-lock cells fall below (they printed overlap). The table of changed printed cells is in the note.
**Verified:** `lake build Fw.Measure.TouchLock` green; package tests `touchlock`, `throttle-toolbar`, `throttle-morph-end` pass.
**Stand-ins / open:** `columns`/`columnsKnown` split stays until `MorphEndCount.cmpBy` moves to `cmpKnown` (needs MorphEndCount.lean
and `morph-end-count.jsonl`, outside the writes). Faithful empty zones: task `faithful-empty-guard`.
**Writes outside the original graph writes:** packages/measure-webkit/test/throttle-morph-end.test.mjs (test of morph-end-report.mjs; the lead added it in graph r514).
**Read first:** the note, then `TouchLock.lean` section on `minSamples`.
