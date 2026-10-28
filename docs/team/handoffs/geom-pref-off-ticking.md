branch: worktree-wf_e077f1dc-fb5-1 (CI branch ci/geom-pref-off-ticking)
worktree: .claude/worktrees/wf_e077f1dc-fb5-1 (under the main checkout)
last commit: see git log (push 2 of max 3 about to go out)
CI runs: wktr 40653612323 (push 1 d79a4bab5, complete, success, 3 jobs, modes mid + mid-thr-off, arms all,all-again,all-3,all-4); push 2 wktr run: see below when pushed.

# state
- Contradiction RESOLVED from data (MEASURED, re-tally of run 40648228102 pref OFF j1, j3): the parked prewarm note's "25 accelerated / 30 ticking" is the RAW property-name match
  (`a` flag, no class fold) = 18 transform + 1 backdrop-filter + 4 opacity + 2 filter; the 30 = 20 translate + 2 scale + 8 hidden. The class-folded read (Lean readsAccelCls) is 47 and the engine oracle ticks 0 (rawAcc 25, clsAcc 47, oracleTick 0). Probe diff main vs parked branch: mid-page.mjs adds a trace and carries held tracks only; accel-cli.mjs, midflip.mjs unchanged.
- Main code, run 40653612323 pref OFF (j1, j2): flips 2 to 4 (and the later ones) 47 accelerated / 0 ticking at p30/p50/p80 in every sample; first flip: a fixed set S1 of 21 tracks ticks until about p50
  (j1 p30+p50, j2 p30) = 13 rendered img[data-mg=image] transform, logo translate, earn button opacity+filter+translate, earnClip translate, earnLabel translate, footerGrad scale, footerEnd translate; all commit by p80. Lean branch of S1 = unaccelerated (running, active, rendered, no accelerated entry).
  Pref ON samples in that run are thin (flush at 48 to 95 % of the tween, slow frame clock): only j2 flips 3, 4 at p80 (47 / 0).
- Source (WebKit 862f17d): KeyframeEffect.cpp:2402-2411 applyPendingAcceleratedActions returns while the renderer is not composited; ticksContinuouslyWhileActive (2724-2746) is true until isCompletelyAccelerated && isRunningAccelerated; isRunningAccelerated (1680-1689) with the pref OFF is m_runningAccelerated == Yes, set only by renderer->startAnimation after that. INFERRED: S1 elements get their layer late (RenderLayerCompositor::requiresCompositingForAnimation, RenderLayerCompositor.cpp:3842). Push 2 adds a per-sample layer flag (`l`) and a pre-push layer map (`layBefore`) to test it.
- Lean (check.sh green via fw slot at d79a4bab5): raw_misses_folded, Reason/reasonOf, ticksMain_eq_reason, reasonOf_* theorems, golden "reason" and "raw" lines. TS stand-in: reasonOf, keySummary in packages/measure-wktr/src/midflip.mjs.
- wktr.yml carries the ACCEL_MODES env (ci branch only); revert it (git checkout main -- .github/workflows/wktr.yml) in the last commit before the dry land.
- scratchpad tools (not committed): scratchpad/geom-pref-off/tools/keys.mjs, sets.mjs (read artifacts downloaded with gh run download <id> -p 'wktr-j*').

# open
- push 2 readout, note research/notes/2026/10-2x-geom-pref-off-ticking.md, ledger note, package tests, merge main, dry land, review ready.
