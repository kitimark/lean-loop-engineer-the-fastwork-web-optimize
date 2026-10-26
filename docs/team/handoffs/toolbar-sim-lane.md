# toolbar-sim-lane handoff
Branch worktree-wf_bf9846c7-37b-1, worktree .claude/worktrees/wf_bf9846c7-37b-1; CI branch ci/toolbar-sim-lane at 02d957418 (3 of 3 pushes used).
CI runs (toolbar-throttle.yml): 40236328441 (push 1, jobs 1-5 ok, rest cancelled by me), 40250249829 (push 2, jobs 1-3 ok, rest cancelled), 40257287239 (push 3, jobs 1-3 and 5-10 ok, job 4 lost VM, complete).
Verified: package tests 906 pass, ci-paths 56, land-inputs 73; check.sh green; dry land VERDICT dry toolbar-sim-lane; Lean MorphEndCount builds, golden 119 lines --check ok; main merged (3ef749b06).
Open: `fw review ready` result; follow-ups: ledger row, part.json promotion of unthrottle, cost windows < 3 per arm (needs a new push budget).
Result note: research/notes/2026/10-2x-toolbar-sim-lane.md (pooled report of the three runs; labels r1jN/r2jN/r3jN).

## State
- Lean: lean/Fw/Measure/MorphEndCount.lean Tb block; golden kinds tb-steps, tb-gestures, tb-onsets, tb-pass, tb-verdict, tb-hz, tb-win, tb-cost (regenerate: `lake build Fw.Measure.MorphEndCount`, then `lake env lean --run scripts/MorphEndCountGolden.lean`).
- TS twin: packages/measure-webkit/src/throttle/toolbar.mjs; glue toolbar-page.mjs, toolbar-probe.mjs, toolbar-plan.mjs, toolbar-cli.mjs (`report --in label=file,...`), toolbar-report.mjs; test/throttle-toolbar.test.mjs replays the golden.
- Workflow: `[throttle:toolbar]` mode in toolbar-throttle.yml.

## Conventions and limits
- Cost window: opens at gesture 2, closed once gesture 5 began; Lean windowCost counts only between page stamps of gestures 4 and 5 (protocol round trips take 7-50 s under touch).
- Look-change arms never enter a preset; part.json untouched.
- Same look is judged on the morph state trace, not pixels.
- Lost VMs are named failures (run 40257287239 job 4).
