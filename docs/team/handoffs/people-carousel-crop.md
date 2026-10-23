branch: worktree-wf_f4682884-067-1 (CI branch ci/people-carousel-crop)
worktree: .claude/worktrees/wf_f4682884-067-1 (repo-relative)
last commit: ee8ff9c58 is the CI tip (code unchanged since); later commits are handoff/note/results only
CI runs (dispatches used 4 of 6):
- trajectory-probe 39896845339 success (push, inputs read back: engines=both fw=people.carousel:crop widths= diagnostic=false commit-line). Chromium units RED = baseline (42 fail in both arms) plus 1 new nav.background-color 1280 close@0 (not our part); WebKit Linux CLEAN (hero path only; the Linux WebKit cells walk pain only, so no WebKit people-zone trajectory). Carousel cell (people zone avatar rects, artifact cells-gpu-chromium): L at 390 and 640, swaps 4/4: the look change shows as L as designed.
- breakpoint-gate 39898995879 (nonce pcc1gate, fw=people.carousel:crop) success, both engines (chromium j0-j2, playwright-webkit j0-j3, merge).
- webkit-sim lag+cost (target=rewrite vms=3 cost=on): base 39899015125 (r1 ok, r2 lag json written, r3 cancelled; lag-report job skipped because target is not both); flag 39899018175 FAILED (no lag json: Safari lost in every VM, simctl code 405); flag retry 39906731945 (nonce pccflag2) queued.
- Reduce offline: node packages/measure-webkit/src/lag/cli.mjs report --original <base lag jsons> --faithful <flag lag jsons> (and cost-report), artifacts webkit-sim-r* of each run.
Verified (local): check.sh green; @fw/site test (123 files) and typecheck green; @fw/runner test green; scripts/ci-paths.test.mjs green.
Open: read the flag retry, write the numbers into note/ledger (ledger row has chromium/webkit text without WebKit cost numbers yet), review ready, dry land.
Files outside the task writes: lean/Fw.lean, lean/Fw/Parts/FootprintData.lean, packages/contracts/golden/parts/footprint.gen.json, packages/contracts/golden/preset/look-change.candidates.jsonl, research/findings/ledger.json.
Read first: research/notes/2026/10-2x-people-carousel-crop.md.
