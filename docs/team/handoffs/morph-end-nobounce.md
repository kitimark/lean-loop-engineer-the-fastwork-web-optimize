branch: worktree-wf_2ef78aa3-7da-1 (CI branch ci/morph-end-nobounce)
worktree: .claude/worktrees/wf_2ef78aa3-7da-1
last commit: see `git log -1` (code at 3c5ac115f; note, ledger and merge of main after it; no more CI pushes)

CI runs at 3c5ac115f (push 2 of 2; first push failed in every site job: the build bans a prerendered style tag):
- breakpoint gate, both engines, fw=morph.end.nobounce:on: 40283431992 success
- chromium-counts swipe-touch-v1, flag 40283424333, same-commit default 40283428442: Lean reader offscreen-windows-cli.mjs, every window noGain, no metric differs (end frame 574, 3 runs per arm)
- toolbar-throttle 40283405286 (complete, report success): default 8 passes (5 usable), nobounce 7 (7 usable), jobs 1-8; reversals/re-opens/onsets overlap, Lean flagVerdict no-win; cost windows 2/3 of 3 needed, not read. sim (9) and sim (10) failed: "toolbar-plan has no entry for job 9/10" (plan has 8 entries); job 1 lost its nobounce pass (Runtime.evaluate timeout).
- failed push-1 runs: 40282634661, 40282669758, 40282673015, 40282681173

Verified: Lean MorphEndNobounce.lean + golden morph-end-nobounce.jsonl; note research/notes/2026/10-2x-morph-end-nobounce.md; ledger row morph.end.nobounce (look-change, class L) plus a notes entry; main merged (Trigger.lean and triggers.jsonl conflicts resolved, golden regenerated with fwcore fwtest -- --write-ci-trigger-golden).
Open: user's look verdict (class L); push-cycle replay (follow-up, needs push-cycle-separate); toolbar plan of 8 entries for 10 jobs (follow-up); no preset promotion.
Read first: the note, then lean/Fw/Parts/MorphEndNobounce.lean.
Dry land (main merged again): VERDICT scope morph-end-nobounce. Refused, 7 files outside the graph row's writes (lead edits the graph row): apps/site/src/App.tsx, apps/site/src/registry/index.ts, apps/site/src/styles/reset.css, lean/Fw/Parts/FootprintData.lean, packages/measure-webkit/src/throttle/toolbar-report.mjs, packages/measure-webkit/src/throttle/toolbar.mjs, packages/measure-webkit/test/throttle-toolbar.test.mjs. Tests green: check.sh, apps/runner (after the ledger note key fix), measure-webkit, site, ci-paths.
