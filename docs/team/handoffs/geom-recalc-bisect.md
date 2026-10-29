# geom-recalc-bisect handoff (final, 3 of 3 CI pushes used)

- Branch: worktree-wf_02ef56dc-a11-1 (CI branch ci/geom-recalc-bisect)
- Worktree: .claude/worktrees/wf_02ef56dc-a11-1
- Last commit: the branch tip (finish: note stage order, e2167365b, then this handoff); main merged, not behind
- CI runs, all wktr success, 3 jobs, mode bisect-thr-off, pref OFF:
  - 40805577147 (5f37a54e, stage 1 hide descent): Lean overall named page-root, no single child dropped the rate. results/geom-recalc-bisect/r1
  - 40808745010 (5cc39310, stage 2 kill-feature and show-only): carrier named kill/smil 3 of 3, holder several/incomplete. r2
  - 40812007953 (da281b56, stage 3 pause SMIL per svg group): pauser named pause/dash 3 of 3 (dash 0/121 0/120 0/121, other 96-100). r3
- wktr.yml mode edit reverted (diff against main empty).

## Result (MEASURED)
The 93-100 recalcs per 100 frames with 0 elements updated come from the SMIL timeline (4 animate, x1/x2) of the 2 [data-fw-dash] svgs of the secure-network glint (platform part). WebKit path and fix proposal in research/notes/2026/10-2x-geom-recalc-bisect.md; ledger entry added.
Next task proposal: glint-hold-wktr, measure platform.glint:hold-freeze in this lane (Lean PlatformGlintHold hold_eq_faithful, ticking_hold, ticking_le) and add a Lean statement from ticking animations to recalcs, decided before data.

## Verified
- Lean lean/Fw/Device/RecalcBisect.lean (stage 1 level/descend, stage 2 carrier/holder, stage 3 pauser, overall2) and golden packages/contracts/golden/device/recalc-bisect.jsonl (71 lines) green in lean/scripts/check.sh; TS reader packages/measure-wktr/src/recalc-bisect.mjs replays it; measure-wktr tests 110 pass.
- finish: check.sh green, measure-wktr 110 pass, ci-paths 56 pass, apps/runner full suite 3679 pass (117 files, incl. run.test.ts, land-inputs, ledger tests) on the merged tree; the earlier run.test.ts vms=3 failure did not recur.

## Open
- fw review ready with run:40812007953 evidence and dry land (lead lands). Limits: WKTR is not iOS Safari, no phone run, hide arms change layout and the glint mounts from an observer, so part-level hide reads are weak; stage 1 and stage 3 (pauser) were decided in Lean before their data; stage 2 (kill/show-only) was added after stage 1's data (note, Runs section).

## Conventions
- Probe arms bs-* in packages/measure-wktr/src/mid-page.mjs (bsRead, kinds facts, full/hidden, l1/l2/deep, kill, hold, pause); results r1..r3 hold j<n>-accel-bisect-thr-off-1.json, tally.txt, verdict.txt.
- Read first: the note, then the RecalcBisect.lean header.
