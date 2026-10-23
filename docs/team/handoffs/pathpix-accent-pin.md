branch: worktree-wf_6d52745a-a7b-1 (CI branch ci/pathpix-accent-pin)
worktree: .claude/worktrees/wf_6d52745a-a7b-1
last commit: see git log (WIP before the first CI push)
CI runs: none yet
verified: measure-webkit pathpix tests (24) green locally; Lean PathPix builds, golden regenerated and --check green
open: CI run (floor of hero_copy A/A at 0?), package tests, lean check, ci-paths, land-inputs, land dry

Task: pin the hero accent word identically in A, A2 and P before capture, without a site change.
- Pin: PIN_ACCENT_EXPR (packages/measure-webkit/src/pathpix-exit-page.mjs) replaces the live accent element by the
  element of the page as served (a synchronous request of the same URL), so every arm shows the server-rendered word in
  its idle state; the live chain keeps writing to the detached element. WebKit lane: after __wk.hold(), before freeze;
  Chromium lane: end of loadArm in exit mode. Manifest handover.pin.<arm> = { before, ssr, after, same } (hashes).
- Lean: lean/Fw/Gate/PathPix.lean "Accent pin" (armPin_all, shown_ssr, shown_none, shown_arm_independent, region_pin);
  golden kinds accentPin and pinRegion in packages/contracts/golden/gate/path-pix.jsonl.
- TS twin: armPin, shownAccent, pinMasks in pathpix-exit.mjs; armPin in measure-chromium/src/pathpix-pure.mjs.
