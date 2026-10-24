branch: worktree-wf_2035e8c8-453-1 (CI branch ci/invisible-paint)
worktree: .claude/worktrees/wf_2035e8c8-453-1
state: data run done and written up. Note research/notes/2026/10-2x-invisible-paint.md, summaries results/invisible-paint/, LakeJobsGen row added (ci-paths --write, tests 56 pass).
CI runs: 40076565001 (push 1, summary job failed, harness bug fixed), 40078541948 (push 2, green, superseded), 40082809394 (push 3, sha 1d99c57a8, wktr success, final data, cited). No further dispatch.
Lead adds at land: lean/Fw.lean `import Fw.Engine.PaintVisible`; lean/scripts/check.sh `job "paint-visible golden check" lake env lean --run scripts/PaintVisibleGolden.lean --check ../packages/contracts/golden/measure/paint-visible.jsonl`.
Open: Inspector Paint data.clip lane (needs xcode job in webkit-sim.yml, outside writes); name the unnamed "other" layers (fix candidate 1 depends on it); covered/noop pixel-diff sample.
Read first: the note.

Round 3 changes outside the graph writes (add to writes before land, dry land needs --allow for the first two): apps/runner/src/land.ts (measure-wktr reads paintclip.mjs), lean/Fw/Ci/Overflow.lean (wktr width 2 to 3 for the 3-job repaint lane), golden moved to packages/contracts/golden/measure/paint-visible.jsonl (golden/engine is cite-linted by check.sh and needs a generator row; the check.sh job path must use golden/measure).
Verified at the final commit: check.sh green, runner/measure-wktr/measure-webkit tests pass, ci-paths test 56 pass, dry land `VERDICT dry invisible-paint` with --allow of the two files.

---- earlier state (rounds 1-2) ----
branch: worktree-wf_2035e8c8-453-1 (CI branch ci/invisible-paint)
worktree: .claude/worktrees/wf_2035e8c8-453-1 (run `sh scripts/wt-prep.sh` and `pnpm install --offline --frozen-lockfile` first)
last commit: see `git log -1` (push 2 of 3 carries [ci:wktr] [repaint] in its head message)
CI runs: wktr 40076565001 (sha f9f8a3f92, push 1) = j1/j2/j3 success, repaint-summary FAILED (non-integer reRasterArea, fixed in e063d20f4). Run 2: wktr 40078541948 (sha 31c373675, push 2 of 3) = success, j1 j2 j3 + repaint-summary all green (artifacts in scratchpad/ivp/run2). Run 3 (push 3 of 3, last): same lane with fixed guess attribution, wktr 40082809394 (sha 1d99c57a8) queued 09:39Z.

What exists
- lean/Fw/Engine/PaintVisible.lean (class rule + `dirty` rule, one theorem per class, builds), lean/scripts/PaintVisibleGolden.lean, packages/contracts/golden/measure/paint-visible.jsonl (37 lines).
- TS twin packages/measure-webkit/src/paintclip.mjs (replays the golden).
- WKTR lane packages/measure-wktr/src/repaint*.mjs; wktr.yml has input `repaint` / token `[repaint]`, `site` job, `repaint-summary` job (timeout 16 min on the macOS job).
- Tests: paintclip 7, repaint 15, repaint-summary 3 pass.

Verified: run 1 page script works (567 frames per arm, 3 zones, layers ~207, probe names 12 of ~105). Tracked repaint rects are counted before the engine's dedupe (GraphicsLayerCA.cpp:1031 vs 1033-1043); the reducer applies the Lean `dirty` rule. Run 1 numbers are superseded (no citations).
Unnamed carousel layers (360x310, 374x796, 434x784 at x=416) now get a size-match guess ("1 of N same size") in run 2.

Open
- Lean/Fw.lean import `import Fw.Engine.PaintVisible`; check.sh job: `job "paint-visible golden check" lake env lean --run scripts/PaintVisibleGolden.lean --check ../packages/contracts/golden/measure/paint-visible.jsonl` (lead adds at land).
- lean/Fw/Ops/LakeJobsGen.lean needs row ("wktr.yml", "site", false, ["breakgen"]) (`node scripts/ci-paths.mjs --write`, outside my writes); only remaining ci-paths test failure.
- Inspector Paint `data.clip` lane not built (needs xcode job in webkit-sim.yml/smoothness.yml, outside writes) -> followUp.
- Limits: new-tile paints during scroll invisible to WKTR repaint rects; WKTR is not the phone; covered/noop classes need pixel diff.
- Note to write: research/notes/2026/10-2x-invisible-paint.md; results/invisible-paint/ summaries.

Read first: the note (once written), packages/measure-wktr/src/repaint.mjs header, wktr.yml repaint steps.
