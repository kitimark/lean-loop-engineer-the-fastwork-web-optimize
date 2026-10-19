# Handoff: mount-scroll-tap

State: branch worktree-wf_c156a96a-23d-2, pushed as ci/mount-scroll-tap. Base for counts: ci/mount-scroll-tap-base
(main fefd858d). `sh lean/scripts/check.sh` is green at the final commit.

Change: `apps/site/src/parts/morph.mount/index.tsx` removes `onScrollMotion` from window inside `mount()` after
`mounted = true` when `shift`. The cleanup keeps its removal (a no-op after mount).

Verified:
- Lean `lean/Fw/Parts/MorphMountOpt.lean`, section "The scroll stamp after mount": `mountV_tail_irrelevant`,
  `tickOf_tap`, `armV_tap`, `calls_shift`, `tap_no_stamp_after_mount`, `visSame_tail`, `E_after_mount_tail`.
- Golden `packages/contracts/golden/parts/morph-mount-tap.jsonl` (generator `lean/scripts/MorphTapGolden.lean`,
  job in check.sh), replayed by `apps/site/src/parts/morph.mount/tap.golden.test.ts`.
- Site test and typecheck, ci-paths test, runner land-inputs test: green.
- Prior counts (faithful against shift-dormant): `results/mount-scroll-tap/prior-faithful-vs-shift-dormant.json`.

Open (the dispatch was refused in the agent sandbox; the lead runs these):
- `gh workflow run chromium-counts.yml --ref ci/mount-scroll-tap-base -f profile=swipe-v1 -f runs=3 -f target=rewrite -f preset=v2-proved -f image_run=39049264131`
- the same with `-f profile=swipe-touch-v1`, then both again with `--ref ci/mount-scroll-tap`
- `gh workflow run breakpoint-gate.yml --ref ci/mount-scroll-tap -f fw=morph.mount:shift`
- `gh workflow run webkit-sim.yml --ref ci/mount-scroll-tap -f target=rewrite -f preset=v2-proved` and the same on
  `--ref ci/mount-scroll-tap-base`
- Then fill the note's Measurements with the per-frame diff (scripts in the note's method: per frame,
  FunctionCall minus FireAnimationFrame, branch minus base). Expect about -463 (swipe-v1) and -459 (swipe-touch-v1).

Registry writes (lead resolves at land): lean/scripts/check.sh, lean/Fw/Ci/Trigger.lean (lean.yml paths),
packages/contracts/golden/ci/triggers.jsonl, lean/Fw/Parts/FootprintData.lean, footprint.gen.json.

Read first: `research/notes/2026/10-20-mount-scroll-tap.md`.
