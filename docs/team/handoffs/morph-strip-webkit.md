# Handoff: morph-strip-webkit

Branch `worktree-wf_446b6a96-5b3-1` (CI copy `ci/morph-strip-webkit`), worktree
`.claude/worktrees/wf_446b6a96-5b3-1`. Last commit: `git log -1` (Lean + CSS at b0085401).

CI runs (webkit-sim, `gh workflow run webkit-sim.yml --ref ci/morph-strip-webkit -f lag=true -f target=rewrite -f vms=3
-f cost=on [-f fw=hero.countdown:strip,morph.countdown:strip] -f nonce=<n>`):
- base 39775174615 (mswbase1, 3a452e64), in progress; flag 39775198022 (mswflag1, 3a452e64, before the entry
  alignment fix), in progress.
- base 39776549128 (mswbase2, b0085401), queued; flag 39776554155 (mswflag2, b0085401), queued.

Verified:
- TS strip runs `startFaithful` (no shared-loop subscriber); `scheduling.test.ts` pins equal rAF registrations per
  frame; hero.countdown + morph.countdown vitest 282 pass. Lean `strip_still_eq` (k = 0 still frame = original's).
- Pixel E under any panel opacity: `strip_px_eq` (opacity-1 layers never change a pixel, `stackPx_filter`).
- Strip entries were centred in a cell rounded to whole px, 0.09-0.2 px above the faces at font 24/28 (local layout
  probe, not a result); `.entry { align-items: flex-start }` fixes it (`entry_center_iff`, `entry_start`).

Open:
- Reduce the cost tables (`node packages/measure-webkit/src/lag/cli.mjs cost-report`), morph-open new layers base vs
  flag; ledger notes rows n 7 / n 13; preset decision in `lean/Fw/Preset/Gen.lean` `curated`.

Read first: `research/notes/2026/10-2x-webkit-cost-counters.md` (lane, counters, limits).
