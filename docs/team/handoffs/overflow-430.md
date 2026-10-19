# overflow-430 handoff

State: branch `worktree-wf_beb0d3d6-b81-1`, CI branch `ci/overflow-430` (code commits 2b693e95 diagnostic, then the fix commit; tip 1d918800 plus this note).

Finding (MEASURED, CI): the 13 px is not a part added today. The wave-2 failures ran the stage page `?preset=v2-proved&only=g2&stage=vw:430,vh:932`
(profile swipe-v1; stage pages landed after wave 1, which is why wave-1 passed). Run 39226882980 (diagnostic) listed the one escaping element:
`div.morph-module_backdrop`, part `morph-panel`, absolute, left -12.89, right 442.89, width 455.78 (= `inset: 0 -3%` of 430). All 37 other
elements past 430 are inside clipping ancestors (platform track). The full page (push run 39225903429, swipe-v1, both targets) passes.
Cause (CONFIRMED by reading): in the page the nav hosts the panel (`.nav` position fixed, overflow hidden, nav.module.css); `PartStage` put it
in a plain div, so the bleed became scroll width.

Fix: `HOST_FRAME` in `apps/site/src/stage/hosts.ts` (fixed, inset 0, overflow hidden, pointer-events none) on the `panel` host div in `PartStage.tsx`.
TS stand-in, not in Lean (stage hosts are a TS port). Guard: `apps/site/src/stage/overflow.test.ts` (renders the g2 stage, checks the panel host frame),
plus the harness gate itself. Harness: `packages/measure-chromium/src/overflow.mjs` lists escaping elements when the viewport gate refuses
(test `test/overflow.test.mjs`).

Verified: run 39228072289 (workflow_dispatch, swipe-touch-v1, rewrite, preset v2-proved, only g2, 3 runs) passes; counts meta inner/client/scrollWidth 430/430/430.
Local: measure-chromium `pnpm test` 60 pass, ci-paths test 32 pass, runner land-inputs 40 pass, site typecheck clean, site vitest all pass
except `svg-extract.test.ts` "no tracked file ... 24 characters" which timed out at 5 s under load and passed alone.

Open: the page-less panel geometry in the stage is the viewport box, not the nav's `--panel-w` by `--panel-h` (accepted limit, stated in the HOST_FRAME doc).
Other stage targets that mount the panel host (morph.*) get the same frame. Other widths not checked.
Read first: `apps/site/src/stage/hosts.ts` (HOST_FRAME), `packages/measure-chromium/src/overflow.mjs`.
Writes outside the task: none (work graph untouched).
