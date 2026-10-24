# mount-arm-late handoff

- Branch `worktree-wf_112a77b1-8ca-1`, worktree `.claude/worktrees/wf_112a77b1-8ca-1`, CI branch `ci/mount-arm-late`; last commit = `git log -1`.
- CI runs: `40092331051` trajectory-probe success (inputs read back: `fw=morph.mount:arm-late widths=390,1280 engines=both
  diagnostic`; Chromium 0 new fails, 1 baseline-red, 1 undecided open@1 coverage; playwright-webkit 2000 pass 0 fail).
  `40093577005` breakpoint-gate success (default config, no flag). `40092331031`, `40093577014` lean: fail by design, the
  import check wants `lean/Fw.lean` wired (lead).
- Verified: `lean/scripts/check.sh` green with the two imports added locally (axiom check included); site test and
  typecheck green; `part-footprint.mjs --check` green; `fw plan lint` has no writesClosure error for this task.
- Read first: `lean/Fw/Parts/MorphMountArmLate.lean`: `prevent_needs`, `covers`, `stepW_inv`, `late_same`, `ops_reach`.
- Design: variant `arm-late` of `morph.mount` keeps every listener the original has but registers wheel and touchmove
  passive unless `near && inBand` or the morph is active. Band: platform `bottom <= vh + 8 + lead`, `lead = 5vh/4`
  (a viewport of pan, `MorphListen.panOk`, plus a quarter viewport of lag, INFERRED). The handler is the same in both modes,
  so only the honoring of `preventDefault` changes; `late_same` holds for any `Hooks`. WebKit: `ScrollingTree.cpp:118-134@862f17d`.
- Count (replay in `armLate.test.ts`, not a browser): non-passive frames on one sweep, original 93 approach + 62 band + 151
  past, arm-late 0 + 62 + 151.

## Lead wiring and dispatches

- `lean/Fw.lean`: add `import Fw.Parts.MorphMountArmLate` and `import Fw.Parts.MorphMountArmLateGolden`; no check.sh job needed
  (golden is a `#guard`). Optional driver for `--check`: `Fw.Parts.MorphMountArmLateGolden.runGolden`.
- Writes outside the task row: `apps/site/src/parts/morph.mount/index.tsx` (the flag wiring), `armLate.component.test.ts`,
  `lean/Fw/Parts/FootprintData.lean` (from `part-footprint --write`); the dry land refuses on these three.
- Gate with the flag: `gh workflow run breakpoint-gate --ref ci/mount-arm-late -f fw=morph.mount:arm-late`.

## Open

- CI cannot drive the WebKit touch gate (INFERRED): touch-start to first scroll frame is a phone step.
- Listener-armed frames per zone in a browser: the flag counts scroll frames per mode in `window.__fwArmLate.frames`; no lane reads it.
