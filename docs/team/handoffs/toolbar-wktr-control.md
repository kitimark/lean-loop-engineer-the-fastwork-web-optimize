branch: worktree-wf_6c371da2-432-1 (CI branch ci/toolbar-wktr-control, pushed tip ca231bbba)
worktree: .claude/worktrees/wf_6c371da2-432-1
last commit: ca231bbba (see `git log -1` for later local commits)
CI runs: wktr 40231779387 in_progress: j1 success (compositable wait 82.0 ms both passes, VERDICT toolbar-gate pass), j2 queued, j3 pending (push 1 of 2); lean 40231779472 success.
verified locally: lean build green, check.sh green at ca231bbba+handoff commits (main merge: already up to date), @fw/measure-wktr test 73 pass, ci-paths test 56 pass.
open: wait for the wktr run (3 jobs serial, about 40 min incl. macos queue); fold run id, waits and the control paragraph into the note; merge main; check.sh; ci-paths test; runner land-inputs test; dry land; review ready.

State
- Lean: Flag gets .compositable (not a production flag; Flag.all unchanged, Flag.arms = all ++ [compositable]); controlPage = one time-based accelerated animation; theorems control_page_not_lifted, compositable_throttled, compositable_down/up, compositable_same_takes; exempt_only_unthrottle now covers all five arms.
- Golden packages/contracts/golden/parts/morph-mount-toolbar.gate.jsonl regenerated (270 rows) from MorphMountToolbarGolden.gateText; gateExempt compositable = false.
- Fixture: packages/measure-wktr/src/toolbar-page.mjs injects CONTROL_CSS (translateX keyframes, 400 ms linear infinite alternate) and reports lift {animations, timelines, states, transform}; gate.mjs check control-anim (one running DocumentTimeline animation) plus the existing exempt check (wait >= 50 ms).
- Note research/notes/2026/10-2x-toolbar-wktr-gate.md: WKTR observes arms and wait; takes come from Node running gesture.ts.
- writesClosure: fw plan lint prints no warning for toolbar-wktr-control; wktr.yml is not edited (toolbar-cli runs every FLAGS entry), so Intent.lean, Overflow.lean and Trigger.lean need no edit.
