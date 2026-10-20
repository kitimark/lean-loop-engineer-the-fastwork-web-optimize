# Handoff: mount-scroll-tap

State (lead-decision step after round 3): branch worktree-wf_c156a96a-23d-2. Measured code is 52cd4856
(ci/mount-scroll-tap); later commits add only the note, `results/mount-scroll-tap/branch-vs-base.json` and this file.
Base: ci/mount-scroll-tap-base at 8a82226a (merge-base with main).

Change: `apps/site/src/parts/morph.mount/index.tsx` removes `onScrollMotion` from window inside `mount()` after
`mounted = true` when `shift` (`shift` and `shift-dormant`).

Verified (round 2, unchanged): Lean section "The scroll stamp after mount" in `lean/Fw/Parts/MorphMountOpt.lean`,
golden `morph-mount-tap.jsonl`, component test `tap.component.test.ts` with 6 mutants.

Measured, note sections "Round 3 runs (lead-dispatched)" and "Lead reruns", json keys `rows` and `rerun`:
- swipe-v1 FunctionCall delta: round 3 -462/-463/-463, rerun -463/-463/-464, all in [-470, -400].
- FireAnimationFrame equal in 4 of 6 swipe-v1 runs. Round 3 run 1: branch +1 (frame 0). Rerun run 3 (39363612059 vs
  39363621551): base +1 (frame 0 at 2 on the base, 0 on the branch).
- Gate, commission `pain-1440-600-1440#0` not ok: base 1 of 4 runs (39363615245, shift), branch 3 of 4 (39357744868,
  39357747743, 39363627657). In the rerun it comes with `desktop-1512-320-1512#0` each time. Webkit: the same
  phone-rotation cell on both refs in all 8 runs.

Open:
- Lead: decide the FireAnimationFrame row and the gate rows from the "Facts per row for the lead" list in the note.

Conventions: the reduction scripts are not committed (no code in this task); the json `source` and `rerun.source`
fields state the reduction. Artifacts: `chromium-counts-rewrite-r{1,2,3}/counts.json`; gate stale arm from
`gate-merged-chromium/chromium.json`.
Read first: `research/notes/2026/10-20-mount-scroll-tap.md`, section "Lead reruns".
