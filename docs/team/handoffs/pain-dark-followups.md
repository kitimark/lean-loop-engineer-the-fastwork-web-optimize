# pain-dark-followups (part-builder) handoff, final

- Branch worktree-wf_27e8c82d-469-1, worktree .claude/worktrees/wf_27e8c82d-469-1, CI branch ci/pain-dark-followups at 9597ea656 (the measured code; later commits change Lean theorems, part.json kind, docs, golden, merge of main). Last commit: `git log -1`.
- CI runs, all complete:
  - 39852164349 trajectory-probe push, fw=pain:dark-scroll, verdict run: pain-dark cell E (both directions) on Chromium 156 and Linux WebKit 27.2 at 390 and 640, layer engaged, same flip step in both arms. Artifacts cells-gpu-chromium, cells-gpu-playwright-webkit-390/-640.
  - 39852250962 breakpoint-gate, both engines, fw=pain:dark-static: pass.
  - 39852245766 chromium-counts swipe-v1 x3, pain:dark-static: toggle frame 3,413,963 to 3,013,203 px, raster 26 to 20, recalcs 4 to 3, +0 layers; whole swipe -0.4 percent.
  - 39852256714 webkit-sim pain:dark-static; 39856782689 base and 39856789295 pain:dark-scroll at the same ref.
- Verdicts: (1) post-flip look E on both engines (Linux WebKit, not Safari). (2) toggle_free and ride_exceeds relabelled model assumptions (ToggleUi, RideEveryFrame) in Lean, part.json and the ledger; Chromium toggle frame tied in Lean (chromium_style_gt, chromium_paint_lt, chromium_paint_drop). (3) no-win: pain:dark-static (no animated layer) has +0 MB backing but no WebKit paint saving (band 26.5/25.2 vs base 26.9/24.8 vs HOLD 10.1/9.9 M px2) and changes the look (Hidden fails at 390 and 640), so it is a look-change proposal (visClass L). Flag pain:dark-scroll stays HOLD.
- Mechanism (INFERRED beyond the layer list): HOLD overlap-promotes the notes canvas and .inner above the animated .sticky::before (RenderLayerCompositor.cpp:1332-1335@862f17d); the paint saving and the 12 MB appear together. Not identified: why the base repaints the whole stage every 50 px step. Next: a paint attribution by layer before another arrangement.
- Verified at the final commit: lean/scripts/check.sh green, @fw/site test and typecheck, @fw/gate-breakpoints test, @fw/runner test, ci-paths test.
- Files outside the task writes: lean/Fw/Parts/FootprintData.lean, packages/contracts/golden/parts/footprint.gen.json, packages/contracts/golden/preset/look-change.candidates.jsonl, research/findings/ledger.json (row n=47), .github/workflows/trajectory-probe.yml, packages/gate-breakpoints/src/trajectory/cells-gpu-run.mjs and cells-gpu-cli.mjs.
- Read first: the note section "Follow-ups (task pain-dark-followups)", then Lean `PainDarkScroll.lean` from `Span` on.
