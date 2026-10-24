branch: worktree-wf_2035e8c8-453-1 (CI branch ci/invisible-paint)
worktree: .claude/worktrees/wf_2035e8c8-453-1 (run `sh scripts/wt-prep.sh` and `pnpm install --offline --frozen-lockfile` first)
last commit: f9f8a3f92 (pushed to ci/invisible-paint; head message carries [ci:wktr] [repaint])
CI runs: wktr 40076565001 = in_progress (push 1 of 3). Other workflows on the push (lean, visual-diff, wktr-fixtures) are not mine.

What exists
- lean/Fw/Engine/PaintVisible.lean (class rule, one theorem per class, builds), lean/scripts/PaintVisibleGolden.lean, packages/contracts/golden/engine/paint-visible.jsonl.
- TS twin packages/measure-webkit/src/paintclip.mjs (replays the golden; TS stand-in for per100/classify glue).
- WKTR lane packages/measure-wktr/src/repaint*.mjs (page script, parser, reduction, driver, serve, summary); wktr.yml has input `repaint` / commit token `[repaint]`, site job, repaint-summary job.
- Tests: 22 pass (paintclip 7, repaint 12, repaint-summary 3).

Verified: unit tests only. The page script has never run (no local WKTR archive); first CI run is its first real run. Read `sample`/`probe` lines in run.log, failures.json, raw gz.

Open
- Lean/Fw.lean import line: `import Fw.Engine.PaintVisible`; check.sh job line: `job "paint-visible golden check" lake env lean --run scripts/PaintVisibleGolden.lean --check ../packages/contracts/golden/engine/paint-visible.jsonl` (lead adds at land).
- Inspector Paint `data.clip` lane (measure-webkit) not built: needs an xcode job in webkit-sim.yml/smoothness.yml (outside writes) -> followUp.
- Named limits: new-tile paints during scroll are invisible to WKTR repaint rects; WKTR is not the phone; covered/clipped/noop classes need pixel diff.
- Note to write: research/notes/2026/10-2x-invisible-paint.md; results/invisible-paint/ summaries.

Read first: the note (once written), packages/measure-wktr/src/repaint.mjs header, wktr.yml repaint steps.
