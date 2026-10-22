# hero-exit-threaded-measure handoff

Branch `worktree-wf_34794772-0e5-1` (CI copy `ci/hero-exit-threaded-measure`), worktree
`.claude/worktrees/wf_34794772-0e5-1`. Last commit: `git log -1`. Round 2 applied (findings 1-4, 6; 5 recorded in the note).

CI runs (webkit-sim, `gh workflow run webkit-sim.yml --ref ci/hero-exit-threaded-measure -f lag=true -f target=rewrite -f vms=3 -f cost=on [-f fw=hero.exit:threaded] -f nonce=<n>`), finished (flag run success; both base runs concluded failure: VM r2 lost its target, the passes used are from VMs that succeeded):
- flag arm: run 39731192687, success, r1 r2 r3, 6 passes.
- base arm: run 39739724461 (r1, r3 ok, 4 passes; r2 failed exit 4); first base run 39731185714 (r3 ok; r2 failed, r1 hit the job limit, no artifact).
Dispatches used: 3 of 4.

Result (MEASURED, note `research/notes/2026/10-2x-hero-exit-threaded-measure.md`): per scroll step in the hero exit zone rAF
callbacks, Layout, Recalculate styles, InvalidateLayout, ScheduleStyleRecalculation and FireAnimationFrame events are lower (separated). Absolute per-step times,
skipped slots, new layers overlap. Relative to each arm's calm baseline (rerun of `lag/cli.mjs report`, same artifacts) Recalculate styles us is 1.89 (1.78-2.02)
base against 1.27 (1.15-1.54) flag and FunctionCall us 1.55 against 1.13, separated (flag lower); calm baselines equal. Backing store +2.9 MB. maxY 5231 vs 5267
(36 px longer page with the flag, open for the phone replay). Runner images differ between arms; flag r3 alone (same image) gives the same verdicts.
Recommendation hold (phone replay), reason text only changed. Ledger note updated (finding n 6, task hero-exit-threaded-measure).
Reduction: `lag/cli.mjs cost-report` and `report` with base r1+r3 of run 39739724461 as --original and flag r1-r3 as --rewrite/--faithful.

Files: results/hero-exit-threaded-measure/report.json, research/findings/ledger.json (notes row), the note, this handoff.
Gate: `VERDICT review-ready hero-exit-threaded-measure review`; dry: `VERDICT dry hero-exit-threaded-measure`; Lean console.report accepts the report (invalid empty). Follow-ups: phone replay of the hero exit, base VM 2 fails twice.
