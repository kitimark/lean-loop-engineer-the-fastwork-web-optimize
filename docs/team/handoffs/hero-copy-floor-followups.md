branch: worktree-wf_2d420399-b29-1 (CI branch ci/hero-copy-floor-followups)
worktree: .claude/worktrees/wf_2d420399-b29-1
last commit sha: ee7bd519a (main merged; CI run pushed at ee7bd519a)
CI runs: path-pix 40007968162 (in_progress, 3 sim + 3 chromium jobs); the only run allowed for this task
state: Lean lemmas + golden + TS twin + report + probes done and tested (measure-webkit pathpix tests 42 pass); note and final checks pending the run.

Verified so far
- Lean `lean/Fw/Gate/PathPix.lean`: `RowLayer`, `countedBy`, `receiver_counts`, `hero_yields_to_receiver`, `yielded_counted_by_receiver`, `inside_some_mask_counted` (no pixel lost); `foreignReason` now generic; golden kind `yield` (8 rows) regenerated, --check green.
- TS twin: `splitUnion` returns `receivers`, cells carry `sharedTo` (receiving layer keys per yielded pixel set), `where.outProbes`; WebKit page expr records `probes` (nav, nav-lang button, nav-earn, logo boxes); report prints receiver cell grade beside each yielded row and a probe table.
- Item 3 (pre-run): the P-only 2-1 at device 873,118..134 (webkit-1, offset 5) is the right-edge arc of the language switch pill (`nav.langMenu` `.switch`, nav_bar layer: fixed, backdrop-filter); evidence = FRAME_P_5 thumb pixels (218,29),(218,33) symmetric about the pill centre. The run's probe table confirms the box.
- Item 4: sourced negative (WebKit GraphicsLayerCA contentsScale constant, census and boxes identical in the varying job, settled-frame already enforced).

Open: read run 40007968162 with the report script, write the note (every number from the report), check.sh, package tests, ci-paths, land-inputs, plan lint, dry land, review ready.
