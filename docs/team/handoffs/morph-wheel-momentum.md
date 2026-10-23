branch: worktree-wf_6ccadb14-8f5-1 (CI branch ci/morph-wheel-momentum, mac leg only)
worktree: .claude/worktrees/wf_6ccadb14-8f5-1
last commit: CI pushed at 8687ac51a (merge of main over 384d299e7-era code commit); later commits are note and handoff only
CI runs: round 1: mac 40018133445 success, sim 40018153769 failure (INCONCLUSIVE, no more). Round 2 (3rd dispatch, mac only): smoothness run for 8687ac51a PENDING (lean run 40032804374 in progress); wait with `fw ci wait --branch ci/morph-wheel-momentum --workflow smoothness`.
Verified: Lean WebKitLagPhase.lean (pull section: offFrames, pullFrames, acceptPull, atEnd/stalled refusals, 14 theorems; golden 162 lines regenerated, never hand-edited); lean/scripts/check.sh green; measure-webkit tests 538/538; ci-paths 56/56; runner land-inputs 56/56 (an earlier failure was my own edits during the run).
Findings (a): a Playwright WebKit trusted wheel has no momentum phase (WebWheelEvent 6-arg ctor, phase None; Playwright 1.64.1 coreBundle.js Input.dispatchWheelEvent without phase; WebKit 56453fd). (b): the site holds the scroll (wheel prevented while the morph is open, L restores the lock), so scrollY cannot strictly change; the push only opens the morph at scrollY >= maxY-7.
Design: drive `pull` (macmorph.mjs): settle at maxY-4, trusted push, then scrollBy instant -2 each frame until the up push; ys[k] = position read after the pull; Lean acceptPull refuses atEnd (push y >= maxY) and stalled (an open frame with no off-lock record within 2 frames).
Open: run results into the note (follow-up 3), report with mac-cli report --files a,b,c --jobs 1,2,3, dry land, review ready.
Files outside the task writes: WebKitLagPhase.lean, golden webkit-lag.jsonl, mac-cli.mjs, probe.mjs.
Read first: research/notes/2026/10-2x-morph-real-wheel.md, end of lean/Fw/Measure/WebKitLagPhase.lean, packages/measure-webkit/src/lag/macmorph.mjs, macreport.mjs.
