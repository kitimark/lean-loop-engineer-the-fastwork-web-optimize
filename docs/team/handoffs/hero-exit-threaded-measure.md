# hero-exit-threaded-measure handoff

Branch `worktree-wf_34794772-0e5-1` (CI copy `ci/hero-exit-threaded-measure`), worktree
`.claude/worktrees/wf_34794772-0e5-1`. Last commit: `git log -1`.

CI runs (webkit-sim, `gh workflow run webkit-sim.yml --ref ci/hero-exit-threaded-measure -f lag=true -f target=rewrite -f vms=3 -f cost=on [-f fw=hero.exit:threaded] -f nonce=<n>`), all complete:
- flag arm: run 39731192687, success, r1 r2 r3, 6 passes.
- base arm: run 39739724461 (r1, r3 ok, 4 passes; r2 failed exit 4); first base run 39731185714 (r3 ok; r2 failed, r1 hit the job limit, no artifact).
Dispatches used: 3 of 4.

Result (MEASURED, note `research/notes/2026/10-2x-hero-exit-threaded-measure.md`): per scroll step in the hero exit zone rAF
callbacks, Layout events and Recalculate styles events are lower (ranges separated); times, skipped slots, new layers overlap;
backing store +2.9 MB. Recommendation hold (phone replay). Ledger note appended (finding n 6, task hero-exit-threaded-measure).
Reduction: `lag/cli.mjs cost-report` and `report` with base r1+r3 of run 39739724461 as --original and flag r1-r3 as --rewrite/--faithful.

Files: results/hero-exit-threaded-measure/report.json, research/findings/ledger.json (notes row), the note, this handoff.
Open: `fw review ready` gate and `fw land --dry` (see the report), follow-ups: phone replay of the hero exit, base VM 2 fails twice.
