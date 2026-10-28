branch: worktree-wf_ff911e21-2e3-1 (CI branch ci/geom-webkit-midflip)
worktree: .claude/worktrees/wf_ff911e21-2e3-1 (run `sh scripts/wt-prep.sh`, `pnpm install --offline --frozen-lockfile`)
last commit: e471963f2 (code), see git log for the later ones
CI runs: none yet (push 1 of 3 not sent)

Task: geom-webkit-midflip (graph r554). Which geom-timed tracks run accelerated mid-flip on WebKit, is any effect pending or ticking
continuously, what is ThreadedTimeBasedAnimationsEnabled in WKTR vs iOS Safari, recalcs per frame during the flip vs idle.

Built and verified locally (not measured):
- Lean `Fw.Parts.MorphTrackAccel`: Eff, ticksContinuously, ticksMain, tickOf, binOf, normName, theorems per OR-branch, 256 tick golden lines
  (lean/Fw/Parts/MorphTrackAccelGen.lean -> packages/contracts/golden/parts/morph-track-accel.jsonl, `--check` up to date). check.sh green.
- packages/gate-breakpoints/src/track-accel-page.mjs: `P.mid` samples every track at 30/50/80 % of the 680 ms tween (state, pending, accelerated,
  threaded flag, timeToNextAnimationTick), per-frame recalc counts, idle arm, getAnimations listing bracketed by recalc counts.
- packages/measure-wktr: modes `mid` (WKTR default pref, threaded ON) and `mid-thr-off` (header ThreadedTimeBasedAnimationsEnabled=false, the
  phone default); src/midflip.mjs (TS mirror of the Lean rule + summaries); test/midflip.test.mjs replays the golden. wktr.yml accel step runs
  `--modes mid,mid-thr-off`.
- Tests: measure-wktr 83, gate-breakpoints 822, ci-paths 56 pass.

Open: push 1 (message must carry [ci:wktr] [accel]), fetch the 3 jobs, midSummary/frameSummary, the note
research/notes/2026/10-2x-geom-webkit-midflip.md, ledger note, dry land, fw review ready.

Conventions: the WKTR frame clock is slow (4-21 frames per 565 ms), so samples are taken by animation phase, not frame count. Nothing here is
phone time. iOS Safari pref default (false) is from source (UnifiedWebPreferences.yaml:8557-8570@862f17d), not measured.
Read first: lean/Fw/Parts/MorphTrackAccel.lean (end), packages/measure-wktr/src/midflip.mjs, research/notes/2026/10-2x-phone-flip-p95.md.
