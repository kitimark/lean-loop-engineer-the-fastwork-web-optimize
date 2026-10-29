# glint-compositor handoff

Branch `worktree-wf_f7fe370b-113-1`, worktree `.claude/worktrees/wf_f7fe370b-113-1`, CI branch `ci/glint-compositor`.
Last pushed commit 090b513b4 (push 1 of 3, tokens `[ci:wktr] [accel] [ci:premise-tests]`).
CI runs: wktr 40833327416 (running), premise-tests 40833327444 (running), wktr-fixtures 40833327497 (side effect, ignore).

Built (all committed except the note and results)
- Lean: `lean/Fw/Parts/PlatformGlintCompositor.lean` (stops_eq, shiftAt_eq, variant_no_smil, variant_no_writes), `PlatformGlintCompositorGolden.lean`
  (writes `packages/contracts/golden/parts/platform-glint-compositor.jsonl` and `apps/site/src/parts/platform.glint/compositor.gen.ts`),
  `lean/Fw/Device/GlintHoldCompositor.lean` (WKTR verdict judgeC decided before data; golden `device/glint-compositor.jsonl`), premise
  `glint.compositor-pixels` in `Fw/Ops/Premise.lean`, check.sh jobs, Trigger rows, triggers.jsonl regenerated.
- Site: flag `platform.glint:compositor` (part.json, class L), `CompDash` in `platform/Visuals.tsx`, CSS in `visuals.module.css`, `compositor.ts`.
- Look premise page and test: `packages/premise-tests/pages/glint.compositor-pixels.html`, `src/tests.mjs` (bound COMPOSITOR_BOUND = 12 of 255, fixed before the data).
- WKTR: mode `glint-comp-thr-off` in `packages/measure-wktr/src/accel-cli.mjs`, stand-in `src/glint-compositor.mjs` + `glint-compositor-cli.mjs`, test.
- Ledger row n=95 `platform.glint:compositor`; `scripts` helper not committed.

Temporary: `.github/workflows/wktr.yml` builds with the compositor config and runs `--modes glint-base-thr-off,glint-comp-thr-off`; REVERT before landing.

Local debug (not results): WebKit premise run showed the leftmost cap column differing by up to 41/255 (dpr 1), 93 (dpr 2) with clip-path inset; with clip-path path() 3 px per dash end.

Open: read CI results (`pnpm -s fw ci wait`), results/glint-compositor, note research/notes/2026/10-2x-glint-compositor.md, ledger note, check.sh via slot, site and package tests, dry land.
