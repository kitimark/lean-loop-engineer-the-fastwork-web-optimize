# hero-exit-threaded-measure handoff

Branch `worktree-wf_34794772-0e5-1` (CI copy `ci/hero-exit-threaded-measure`), worktree
`.claude/worktrees/wf_34794772-0e5-1`. Last commit: see `git log -1` (graph commit 34fcb69a + this file).

CI runs (webkit-sim, dispatched with `gh workflow run webkit-sim.yml --ref ci/hero-exit-threaded-measure -f lag=true -f target=rewrite -f vms=3 -f cost=on [-f fw=hero.exit:threaded] -f nonce=<n>`):
- base arm, nonce hetmbase1: run 39731185714, running
- flag arm `fw=hero.exit:threaded`, nonce hetmflag1: run 39731192687, running

Verified: nothing yet. Open: wait for both, download into new dirs under the scratchpad, `lag/cli.mjs cost-report`
(--original base JSONs? see note: both arms are rewrite builds, so pass base as --original and flag as --rewrite for the
report layout and say so), write ledger row update, results/hero-exit-threaded-measure/report.json, the note.
Budget: at most 4 dispatches (2 used). Read first: research/notes/2026/10-2x-webkit-cost-counters.md section 4.
