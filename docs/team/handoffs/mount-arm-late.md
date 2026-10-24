# mount-arm-late handoff

- Branch `worktree-wf_112a77b1-8ca-1`, worktree `.claude/worktrees/wf_112a77b1-8ca-1`, CI branch `ci/mount-arm-late`.
  Last commit: see `git log -1`. CI runs (branch `ci/mount-arm-late`):
  - `40092331051` trajectory-probe, success; inputs read back from the step name: `fw=morph.mount:arm-late widths=390,1280
    engines=both diagnostic` (commit-line, head ec89e3cac). Chromium: 0 new fails (1 both = baseline red, 1 undecided open@1
    coverage, 2 cleared); playwright-webkit: 2000 pass, 0 fail.
  - `40092331031` lean, failure by design: `check-imports` wants `lean/Fw.lean` to import the two new modules (lead wires).
  - gate push: pending (second and last push, head commit asks `[ci:breakpoint-gate]`).
- Verified: `lake env lean Fw/Parts/MorphMountArmLate.lean` and the golden module build clean; `armLate.test.ts` (62 golden
  rows + sweep counts) and `armLate.component.test.ts` green; `tsc --noEmit` green; `part-footprint.mjs --check` green.
- Read first: `lean/Fw/Parts/MorphMountArmLate.lean` header, then `prevent_needs`, `covers`, `stepW_inv`, `late_same`.
- Design: the flag `morph.mount:arm-late` (variant of morph.mount, own entry in `part.json`) keeps every listener the original
  has, but registers wheel/touchmove passive unless `near && inBand` or the morph is active. Band = `bottom <= vh + 8 + lead`,
  `lead = 5vh/4` (pan one viewport, checked by `MorphListen.panOk`, plus a quarter viewport of lag, INFERRED). The handler is the
  same in both modes, so only the honoring of `preventDefault` changes; `late_same` shows it is always honored when the
  original would call it, over any `Hooks` (every A/B/C combination, `prevent_needs_cfg`).
- WebKit premise (cited): `ScrollingTree.cpp:118-134@862f17d` (non-passive wheel region = synchronous + blocking dispatch;
  passive = async + non-blocking); touch gate `WebPageProxy.cpp:5049-5089,5228-5300@862f17d`.

## Lead wiring (shared files)

- `lean/Fw.lean`: `import Fw.Parts.MorphMountArmLate` and `import Fw.Parts.MorphMountArmLateGolden`.
- `lean/scripts/check.sh` has no new job needed: the golden is a `#guard` in the module. Optional: a driver
  `lean/scripts/MorphMountArmLateGolden.lean` (`Fw.Parts.MorphMountArmLateGolden.runGolden args`) and
  `job "morph-mount arm-late golden check" lake env lean --run scripts/MorphMountArmLateGolden.lean --check ../packages/contracts/golden/parts/morph-mount-arm-late.jsonl`.

## Open

- CI cannot drive the WebKit touch gate (INFERRED): touch-start to first scroll frame is a phone step.
- Listener-armed frames per zone on CI needs a harness read of `window.__fwArmLate.frames` (set by the flag per scroll frame);
  no lane reads it yet. The deterministic replay in `armLate.test.ts` gives the count per zone (approach 93 -> 0).
