branch: worktree-wf_94944339-2ae-1 (CI branch ci/hero-accent-draw-nolayout)
worktree: .claude/worktrees/wf_94944339-2ae-1
last commit: 08e6bcdf0 (empty token commit on top of main merge f4d177efe and work 3449c6efd)
CI runs: webkit-sim 39999057900 (push, [swap-lane] [swap-fw:accent-nolayout], arm hero.accent:draw-nolayout): running. 1 of 2 dispatches used.
verified: Lean StyleDiffAccent builds (all theorems by decide), golden regenerated, site hero.accent tests + tsc green, ci-paths 56 green, lake test green.
open: run result (Layout per swap window and hero-exit frame, arm vs faithful); note + ledger row; check.sh; dry land; pixel sameness not measurable in path-pix (accent pinned, PP_FLAG is a hero.exit flag).
design: arm = clip-path inset() wipe on the visible copy (frame0), path dash static; look change (wipe is not the stroke trace). Draw-out frames need no layout (Lean arm_drawOut_nolayout), draw-in keeps the original's width transition (layout, arm_drawIn_layout_only_width). Chromium faithful draw-out already has no layout (faithful_drawOut).
writes outside graph: .github/workflows/webkit-sim.yml (FW token [swap-fw:accent-nolayout]), lean/Fw/Ci/Trigger.lean + golden/ci/triggers.jsonl, packages/contracts/golden/preset/v2-proved.decisions.jsonl.
read first: lean/Fw/Engine/StyleDiffAccent.lean
