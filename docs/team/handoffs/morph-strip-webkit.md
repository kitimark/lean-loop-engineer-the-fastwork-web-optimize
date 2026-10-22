# Handoff

Branch `worktree-wf_446b6a96-5b3-1` (CI copy `ci/morph-strip-webkit`), worktree
`.claude/worktrees/wf_446b6a96-5b3-1`. Last commit: `git log -1`.

CI runs (webkit-sim, `gh workflow run webkit-sim.yml --ref ci/morph-strip-webkit -f lag=true -f target=rewrite -f vms=3
-f cost=on [-f fw=hero.countdown:strip,morph.countdown:strip] -f nonce=<n>`):
- base 39775174615 (mswbase1): success, r1-r3 reduced. base 39776549128 (mswbase2): r1 reduced, r2 failed (Simulator
  shut down), r3 running at handback.
- flag 39775198022 (mswflag1, before the entry alignment fix): r1, r2 reduced, r3 running. flag 39776554155 (mswflag2):
  r2 reduced, r1/r3 running at handback.

Verified:
- Morph-open new layers per pass 81-83 (base, 8 passes) -> 9-11 (flag, 6 passes); resident 128 -> 52-56; paint
  records after open 95-110 -> 28-51; cadence and Composite overlap (`lag/cli.mjs cost-report`, base as original).
- Lean: `strip_px_eq` (pixel E under any panel opacity), `entry_center_iff` / `entry_start` (top-aligned entries),
  `strip_still_eq` (no subscriber); check.sh green, standard axioms.
- Ledger n 13 strip row proved, webkit win; notes rows for n 7 / n 13; both strips leave `curated` in Gen.lean
  (decisions: verdict proved, membership pending trajectory like every flag).

Open:
- Chromium C3 (elementCount 11264 -> 22445) not re-judged; `research/notes/2026/10-19-c3-decision.md` still says
  excluded (outside this task's writes).
- `lean/Fw/Parts/FootprintData.lean`, `packages/contracts/golden/parts/footprint.gen.json` regenerated (outside writes).

Read first: `research/notes/2026/10-2x-webkit-cost-counters.md` (lane, counters, limits).
