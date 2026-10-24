# hittest-elements-proof handoff

- Branch: worktree-wf_19bb37f8-8d7-1; worktree .claude/worktrees/wf_19bb37f8-8d7-1; CI branch ci/hittest-elements-proof.
- Last commit: see `git log -1` (this file is committed with each checkpoint).
- CI runs (both complete, success, sha d7b257a, chromium-counts swipe-v1, 3 runs): faithful rewrite 40081984397;
  rewrite `?fw=nav.hitTest:elements-skip` 40081975943. Dispatch budget (2) used.
- Verified: `lean/Fw/Parts/NavHitTestElements.lean` builds clean, axioms standard (same_class, same_onDark_run,
  elements_frame_no_style_dirt, faithful_frame_style_dirt). Golden `nav.hitTest.elements.jsonl` (555 lines) passes
  `gen ["--check"]`; site test `apps/site/src/parts/nav.hitTest/elements.golden.test.ts` passes. Chromium:
  UpdateLayoutTree 2192 -> 1122 (-2 per swipe frame, every zone), Layout 418 -> 418.
- Written: note `research/notes/2026/10-2x-hittest-elements-proof.md`, ledger note row (entry n=4, task
  hittest-elements-proof, field chromium).
- Open: WKTR per zone not reachable (wktr.yml:190-191 runs snapshot/site only); site test path is outside the graph
  writes; lead adds `import Fw.Parts.NavHitTestElements` to lean/Fw.lean and the check.sh golden line.
- Read first: the note, then the Lean module.
