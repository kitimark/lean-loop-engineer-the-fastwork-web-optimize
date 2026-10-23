branch: worktree-wf_f4682884-067-1 (CI branch ci/people-carousel-crop)
worktree: .claude/worktrees/wf_f4682884-067-1 (repo-relative)
last commit: ee8ff9c58 is the CI tip (code unchanged since); later commits are handoff/note/results only
CI runs (dispatches used 3 of 6):
- trajectory-probe 39896845339 success (push, inputs read back: engines=both fw=people.carousel:crop widths= diagnostic=false commit-line). Chromium units RED = baseline (42 fail in both arms) plus 1 new nav.background-color 1280 close@0 (not our part); WebKit Linux CLEAN (hero path only). Carousel cell (people zone avatar rects, artifact cells-gpu-chromium): L at 390 and 640, swaps 4/4, holds equal-ish: the look change shows as L as designed.
- breakpoint-gate 39898995879 (dispatch nonce=pcc1gate, fw=people.carousel:crop) queued
- webkit-sim lag+cost: base 39899015125 (pccbase1), flag 39899018175 (pccflag1: fw=people.carousel:crop), both queued
Verified (local): check.sh green; @fw/site test (123 files) and typecheck green.
Open: read gate and webkit-sim results into the note/ledger (placeholders PENDING in the ledger row: chromium/webkit text), run ci-paths and runner land-inputs tests, review ready, dry land.
Files outside the task writes: lean/Fw.lean, lean/Fw/Parts/FootprintData.lean, packages/contracts/golden/parts/footprint.gen.json, packages/contracts/golden/preset/look-change.candidates.jsonl, research/findings/ledger.json.
Read first: research/notes/2026/10-2x-people-carousel-crop.md.
