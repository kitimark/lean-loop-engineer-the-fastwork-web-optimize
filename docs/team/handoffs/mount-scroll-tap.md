# Handoff: mount-scroll-tap

State (round 2): branch worktree-wf_c156a96a-23d-2, pushed as ci/mount-scroll-tap. Base for every comparison:
ci/mount-scroll-tap-base at the merge-base with main (8a82226a). `sh lean/scripts/check.sh` is green at the final commit.

Change: `apps/site/src/parts/morph.mount/index.tsx` removes `onScrollMotion` from window inside `mount()` after
`mounted = true` when `shift` (`shift` and `shift-dormant`). The cleanup keeps its removal (a no-op after mount).

Verified:
- Lean `lean/Fw/Parts/MorphMountOpt.lean`, section "The scroll stamp after mount": `mountV_tail_irrelevant`,
  `tickOf_tap`, `armV_tap`, `calls_shift`, `tap_no_stamp_after_mount`, `visSame_tail`, `E_after_mount_tail`. `Ev` has
  an `input` field (wheel/touchmove, taken or not), stamped as `take()` does.
- Golden `packages/contracts/golden/parts/morph-mount-tap.jsonl` (17 lines), replayed by `tap.golden.test.ts`.
- Component test `apps/site/src/parts/morph.mount/tap.component.test.ts` (jsdom, new dev dep `jsdom` 30.1.3 in
  apps/site): fails on 6 mutants of the removal line (table in the note).
- Site test and typecheck, runner test (land-inputs included), ci-paths test: green.

Open: measurements. Every run needs workflow inputs and a ci/* push only runs the defaults, so the lead dispatches:
- `gh workflow run chromium-counts.yml --ref <ref> -f target=rewrite -f preset=v2-proved -f runs=3 -f image_run=39049264131 -f profile=<p>`
  for ref in ci/mount-scroll-tap-base, ci/mount-scroll-tap and p in swipe-v1, swipe-touch-v1 (4 runs)
- `gh workflow run breakpoint-gate.yml --ref <ref> -f fw=<f>` for both refs and f in morph.mount:shift,
  morph.mount:shift-dormant (4 runs; the base runs give main's not-ok set)
- `gh workflow run webkit-sim.yml --ref <ref> -f target=rewrite -f preset=v2-proved` for both refs
- Then fill the note's "Round 2 runs" table: run ids, verdicts, and the per-frame diff (per frame
  `trace.FunctionCall - trace.FireAnimationFrame`, branch minus base). Predicted range: -417 to -463 (swipe-v1),
  -413 to -459 (swipe-touch-v1).

Registry writes (lead resolves at land): lean/scripts/check.sh, lean/Fw/Ci/Trigger.lean (lean.yml paths),
packages/contracts/golden/ci/triggers.jsonl, lean/Fw/Parts/FootprintData.lean, footprint.gen.json, pnpm-lock.yaml.
Read first: `research/notes/2026/10-20-mount-scroll-tap.md`.
