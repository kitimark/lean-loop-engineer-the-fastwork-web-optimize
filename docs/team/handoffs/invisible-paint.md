branch: worktree-wf_2035e8c8-453-1 (CI branch ci/invisible-paint)
worktree: .claude/worktrees/wf_2035e8c8-453-1 (run `sh scripts/wt-prep.sh` and `pnpm install --offline --frozen-lockfile` first)
last commit: see `git log -1` (push 2 of 3 carries [ci:wktr] [repaint] in its head message)
CI runs: wktr 40076565001 (sha f9f8a3f92, push 1) = j1/j2/j3 success, repaint-summary FAILED (non-integer reRasterArea, fixed in e063d20f4). Run 2: wktr 40078541948 (sha 31c373675, push 2 of 3) = in_progress at 08:34Z.

What exists
- lean/Fw/Engine/PaintVisible.lean (class rule + `dirty` rule, one theorem per class, builds), lean/scripts/PaintVisibleGolden.lean, packages/contracts/golden/engine/paint-visible.jsonl (37 lines).
- TS twin packages/measure-webkit/src/paintclip.mjs (replays the golden).
- WKTR lane packages/measure-wktr/src/repaint*.mjs; wktr.yml has input `repaint` / token `[repaint]`, `site` job, `repaint-summary` job (timeout 16 min on the macOS job).
- Tests: paintclip 7, repaint 15, repaint-summary 3 pass.

Verified: run 1 page script works (567 frames per arm, 3 zones, layers ~207, probe names 12 of ~105). Tracked repaint rects are counted before the engine's dedupe (GraphicsLayerCA.cpp:1031 vs 1033-1043); the reducer applies the Lean `dirty` rule. Run 1 numbers are superseded (no citations).
Unnamed carousel layers (360x310, 374x796, 434x784 at x=416) now get a size-match guess ("1 of N same size") in run 2.

Open
- Lean/Fw.lean import `import Fw.Engine.PaintVisible`; check.sh job: `job "paint-visible golden check" lake env lean --run scripts/PaintVisibleGolden.lean --check ../packages/contracts/golden/engine/paint-visible.jsonl` (lead adds at land).
- lean/Fw/Ops/LakeJobsGen.lean needs row ("wktr.yml", "site", false, ["breakgen"]) (`node scripts/ci-paths.mjs --write`, outside my writes); only remaining ci-paths test failure.
- Inspector Paint `data.clip` lane not built (needs xcode job in webkit-sim.yml/smoothness.yml, outside writes) -> followUp.
- Limits: new-tile paints during scroll invisible to WKTR repaint rects; WKTR is not the phone; covered/noop classes need pixel diff.
- Note to write: research/notes/2026/10-2x-invisible-paint.md; results/invisible-paint/ summaries.

Read first: the note (once written), packages/measure-wktr/src/repaint.mjs header, wktr.yml repaint steps.
