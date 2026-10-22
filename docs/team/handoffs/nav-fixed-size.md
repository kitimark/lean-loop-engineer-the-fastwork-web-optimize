branch: worktree-wf_fab081fd-3ca-1 (CI branches ci/nav-fixed-size, ci/nav-fixed-size-bar, ci/nav-fixed-size-logo)
worktree: .claude/worktrees/wf_fab081fd-3ca-1 (repo-relative)
last commit: see `git log -1` (updated at each checkpoint)
CI runs: none pushed yet

## Verified (local, not results)
- Lean builds: Fw.Parts.NavClipBox, NavBarFixed, NavBarFixedWork, Fw.Engine.WebKitSimple (lake build, no sorry); goldens nav-clip-box.jsonl and nav-bar-fixed.jsonl (100 rows each, `#guard include_str`).
- Site: vitest src/parts/nav, nav.hitTest, morph.panel green (769); tsc --noEmit clean. The CSS is evaluated against the Lean rows (box.golden.test.ts).

## Open
- Pending: CI lean, breakpoint-gate (default config), trajectory-probe per arm; gate arms with fw= and layer census need a lead dispatch.
- Design: a part has one variant, so the arms are cumulative variants (bar-fixed includes clip-box, logo-3d includes bar-fixed); `requires` cannot name a flag of the same part. All three conflict with morph.panel:const-bounds (the panel is placed by the nav's insets).
- Read first: research/notes/2026/10-2x-nav-fixed-size.md (written at the end).
