branch: worktree-wf_f4682884-067-1 (CI branch ci/people-carousel-crop, code tip ee8ff9c58)
worktree: .claude/worktrees/wf_f4682884-067-1 (repo-relative)
last commit: see git log (main merged at a085f6e; dry land VERDICT dry people-carousel-crop; review ready VERDICT review-ready people-carousel-crop review)
CI runs (dispatches used 4 of 6), all finished: trajectory-probe 39896845339 success; breakpoint-gate 39898995879 success (both engines); webkit-sim base 39899015125 (r1 r2 lag json, r3 cancelled), flag 39899018175 failed no data (Safari lost), flag retry 39906731945 success.
Results: results/people-carousel-crop/ (trajectory summaries, carousel cell L at 390 and 640, WebKit lag and cost reports base vs crop). WebKit end-of-page: no separated difference (lane does not sample inside the 220 ms swap); layer census +4 layers, reason animation 5 to 8 as the Lean budget says.
Verified (local): check.sh green, @fw/site test and typecheck, @fw/runner test, scripts/ci-paths.test.mjs.
Open (follow-ups): a lane that samples inside the swap windows; the felt-lag check on the phone; no WebKit people-zone trajectory on Linux (cells walk pain only).
Files outside the task writes: lean/Fw.lean, lean/Fw/Parts/FootprintData.lean, packages/contracts/golden/parts/footprint.gen.json, packages/contracts/golden/preset/look-change.candidates.jsonl, research/findings/ledger.json.
Read first: research/notes/2026/10-2x-people-carousel-crop.md.
