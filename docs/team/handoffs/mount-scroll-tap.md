# Handoff: mount-scroll-tap

State (round 3, final design round): branch worktree-wf_c156a96a-23d-2. Measured code is 52cd4856 (ci/mount-scroll-tap);
round 3 adds only the note, `results/mount-scroll-tap/branch-vs-base.json` and this file. Base: ci/mount-scroll-tap-base
at 8a82226a (merge-base with main).

Change: `apps/site/src/parts/morph.mount/index.tsx` removes `onScrollMotion` from window inside `mount()` after
`mounted = true` when `shift` (`shift` and `shift-dormant`).

Verified (round 2, unchanged): Lean section "The scroll stamp after mount" in `lean/Fw/Parts/MorphMountOpt.lean`
(`tickOf_tap`, `calls_shift`, `tap_no_stamp_after_mount`, ...), golden `morph-mount-tap.jsonl`, component test
`tap.component.test.ts` with 6 mutants.

Measured (round 3, lead-dispatched runs, note section "Round 2 runs"):
- FunctionCall delta per run: swipe-v1 -462/-463/-463, swipe-touch-v1 -459/-455/-459 (all in [-470, -400]).
  Per-frame `FunctionCall - FireAnimationFrame` sum equals minus the scroll-moved frames (463, 459) in 5 of 6 runs.
- Not a pass: swipe-v1 branch run 1 has FireAnimationFrame 1688 against 1687 (limit iii, lead decides).
- Gate: base not-ok set is only the webkit matchMedia phone-rotation cell for both flags. Branch adds the chromium
  commission `pain-1440-600-1440#0` margin-inline cell (orig arm 0px) in both flag runs 39357744868 and 39357747743.
  Limit (i): the lead reruns base and branch once per flag.
- webkit-sim 39357736128 (base) and 39357750346 (branch): success. WebKit saving stays source-only.

Open:
- Lead: rerun breakpoint-gate on both refs for fw=morph.mount:shift and morph.mount:shift-dormant, then decide the
  gate rows and the FireAnimationFrame row.

Conventions: the reduction script is not committed (no code in round 3); it is the prior script with arms swapped to
base/branch, and the json's `source` field states the reduction. Artifacts: `chromium-counts-rewrite-r{1,2,3}/counts.json`.
Read first: `research/notes/2026/10-20-mount-scroll-tap.md`, section "Round 2 runs".
