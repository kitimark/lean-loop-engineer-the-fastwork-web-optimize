branch: worktree-wf_6d52745a-a7b-1 (CI branch ci/pathpix-accent-pin)
worktree: .claude/worktrees/wf_6d52745a-a7b-1
last commit: 32d2316b3
CI runs: 39943789128 (path-pix, ci/pathpix-accent-pin, 32d2316b3): chromium (1) (2) done, sim (1) (2) still running (about 35 min)
chromium result so far: pin applied in all 3 arms of both jobs (handover.pin same:true). hero_copy A/A floor 0 in chromium-2; chromium-1 still 490/377/142 px at y 0/1/233: the diff is the countdown seconds digit (spring mid-roll in one arm, strip AA_hero_copy_0.png), not the accent word. The Chromium floor of earlier runs was countdown noise, not accent (refutes the INFERRED cause in the hero-exit-threaded-pix note for Chromium).
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
