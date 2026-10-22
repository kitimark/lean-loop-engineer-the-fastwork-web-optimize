# Handoff: morph-strip-webkit

Branch `worktree-wf_446b6a96-5b3-1` (CI copy `ci/morph-strip-webkit`), worktree
`.claude/worktrees/wf_446b6a96-5b3-1`. Last commit: `git log -1` (first push at 3a452e64).

CI runs (webkit-sim, `gh workflow run webkit-sim.yml --ref ci/morph-strip-webkit -f lag=true -f target=rewrite -f vms=3
-f cost=on [-f fw=hero.countdown:strip,morph.countdown:strip] -f nonce=<n>`):
- base arm (default rewrite, faithful clocks): run 39775174615, nonce mswbase1, in progress.
- flag arm (`hero.countdown:strip,morph.countdown:strip`): run 39775198022, nonce mswflag1, in progress.

Verified:
- TS strip runs `startFaithful` (no shared-loop subscriber); `scheduling.test.ts` pins equal rAF registrations per
  frame against the original model; hero.countdown + morph.countdown vitest 282 pass.

Open:
- Lean: pixel bound under fractional panel opacity; scheduling theorem for the removed subscriber.
- Reduce the cost tables (`lag/cli.mjs cost-report`), morph-open new layers base vs flag; ledger row; preset decision.

Read first: `research/notes/2026/10-2x-webkit-cost-counters.md` (lane, counters, limits).
