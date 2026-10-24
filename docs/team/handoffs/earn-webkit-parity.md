# earn-webkit-parity handoff
Branch: worktree-wf_f45ca365-4a6-1 (CI branch ci/earn-webkit-parity). Worktree: .claude/worktrees/wf_f45ca365-4a6-1.
Last sha: see `git log -1` (the commit that adds this note). All 3 CI dispatches used.
CI runs (workflow trajectory-probe, all success): 40082730706 (86dde9fc4, Safari invalid: reduced motion on),
40083514606 (2245a5009, Safari valid), 40084115382 (840426931, adds fix-candidate arms). Download with
`gh run download <id> -n transitions-apple-1280` (`pnpm fw ci <id>` only reads chromium-counts runs).

## Result
Read first: research/notes/2026/10-2x-earn-webkit-parity.md. Cause CONFIRMED by source: WebKit@862f17d Styleable.cpp:553-566 sets the
`padding-inline` shorthand's logical longhands in the transition list, they have no animation wrapper
(process-css-properties.py:~5956), so no transition starts on padding-left/right; Chromium css_animations.cc:2993-3007 uses ToPhysical.
MEASURED on 3 CI jobs: WebKit and Safari padding 24 (16 narrow) -> 0 in the flip frame, Chromium eases ~570-600 ms; opacity fade is
not slower on WebKit. Best fix: `padding-inline-start, padding-inline-end` in the transition list (candidates measured in 1 job only).
Summaries: results/earn-webkit-parity/<run>/<width>/summary, across-runs.{json,txt} (transitions-combine.mjs).

## Verified
Lean Fw.Engine.TransitionStart builds, golden transition-start.jsonl (588 rows) --check ok, engine-goldens 13 files equal,
gate-breakpoints tests, ci-paths 56 pass, actionlint clean. Final gate results are in the task report.

## Open / for the lead (not edited by me)
- Wiring done: `import Fw.Engine.TransitionStart` in lean/Fw.lean. No separate check.sh job: the
  `engine goldens check` job already compares transition-start.jsonl, and a job that reads
  ../packages/contracts/golden/engine/transition-start.jsonl fails ci-paths --check and adds 5 writesClosure errors to plan lint
  (needs a Trigger.lean lean.yml row entry `packages/contracts/golden/engine/transition-start.jsonl`, lead only).
- goldenLines/goldenJsonl take `Unit`: as constants they cost 30398 start allocations (init cost lint bound 10000).
- Outside writes made: lean/scripts/EngineGoldens.lean (row + import), lean/Fw/Ops/Premise.lean (engineFiles entry), lean/Fw.lean, lean/scripts/check.sh (unchanged vs main).
- TS stand-ins: reduction in transitions.mjs, transitions-combine.mjs.
- Limits: candidates 1 job; no iPhone; morph sequences not in CI (15 min cap, `--morph 0`); Chromium 20-30 fps on runner; Safari 1280 only.

## Conventions
Workflow gate: commit message needs `[ci:trajectory-probe] [frames:...] [transitions:earn]`. Runner has Reduce Motion on; the Safari
step writes it off first. Next task earn-webkit-smooth: apply the CSS swap in nav.module.css (both earn rules), repeat candidates on 3 jobs.

Continue round: main merged cleanly (no conflicts), trigger golden regenerated with no diff, dry land and review ready verdicts green.
