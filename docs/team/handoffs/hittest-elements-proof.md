# hittest-elements-proof handoff

- Branch: worktree-wf_19bb37f8-8d7-1; worktree .claude/worktrees/wf_19bb37f8-8d7-1; CI branch ci/hittest-elements-proof.
- Last commit: see `git log -1` (this file is committed with each checkpoint).
- CI runs (both complete, success, sha d7b257a, chromium-counts swipe-v1, 3 runs): faithful rewrite 40081984397;
  rewrite `?fw=nav.hitTest:elements-skip` 40081975943. Lean run 40085221652 (merged head a372d1c) failed only at the
  import check; the continue round fixes that. No new CI dispatch in the continue round.
- Continue round (graph r423): merged main; `import Fw.Parts.NavHitTestElements` added to lean/Fw.lean; check.sh job
  "hittest elements golden check" runs `Fw.Parts.NavHitTestElements.gen ["--check"]`. lint-check-sh clean;
  ci-paths --check clean (no Trigger.lean row change needed).
- Verified: module builds, axioms standard (same_class, same_onDark_run, elements_frame_no_style_dirt,
  faithful_frame_style_dirt). Golden `nav.hitTest.elements.jsonl` (555 lines) equals the Lean output; site test
  `apps/site/src/parts/nav.hitTest/elements.golden.test.ts` replays it. Chromium: UpdateLayoutTree 2192 to 1122,
  Layout 418 to 418. Ledger row: research/findings/ledger.json (task hittest-elements-proof).
- Open (follow-ups): WKTR count per zone (wktr.yml runs the snapshot only, no flag input); iPhone not measured.
- Read first: research/notes/2026/10-2x-hittest-elements-proof.md, then lean/Fw/Parts/NavHitTestElements.lean.
