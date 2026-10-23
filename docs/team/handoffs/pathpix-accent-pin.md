branch: worktree-wf_6d52745a-a7b-1 (CI branch ci/pathpix-accent-pin)
worktree: .claude/worktrees/wf_6d52745a-a7b-1
last commit: see git log (round 2: pin re-applied before every capture offset)
CI runs: 39943789128 (path-pix, 32d2316b3): complete. Round 2 run: pushed with the round 2 commit, id added in the next update.
verified: round 1 CI. Pin same:true in all arms of all 4 jobs. Chromium floor was the countdown seconds digit (chromium-1), not the accent. WebKit hero_copy A/A: 0 at y1/y213/y427 in w1; 48 px delta-1 in the button area at y0; w2 y427 invalid (A2 accent moved after the pin, cause unknown). Round 2 re-pins before every freeze and records the accent signature at shot start and end (rows[].accent).
open: round 2 CI result, package tests on a clean tree, lean check, ci-paths, land-inputs, land dry, note research/notes/2026/10-2x-pathpix-accent-pin.md

Task: pin the hero accent word identically in A, A2 and P before capture, without a site change.
- Pin: PIN_ACCENT_EXPR (packages/measure-webkit/src/pathpix-exit-page.mjs) replaces the live accent element by the
  element of the page as served (a synchronous request of the same URL), so every arm shows the server-rendered word in
  its idle state; the live chain keeps writing to the detached element. WebKit lane: after __wk.hold(), and again before each freeze;
  Chromium lane: end of loadArm in exit mode and before each freeze. Manifest handover.pin.<arm> = { before, ssr, after, same } (hashes).
- Lean: lean/Fw/Gate/PathPix.lean "Accent pin" (armPin_all, pinAt_same, pinAt_all, shown_ssr, shown_none, shown_arm_independent, region_pin);
  golden kinds accentPin (with perOffset) and pinRegion in packages/contracts/golden/gate/path-pix.jsonl (regenerate: lake build Fw.Gate.PathPix, then lake env lean --run scripts/PathPixGolden.lean > golden).
- TS twin: armPin, pinAt, shownAccent, pinMasks in pathpix-exit.mjs; armPin, pinAt in measure-chromium/src/pathpix-pure.mjs.
- Not pinned (follow-ups): countdown seconds digit (Chromium), 48 px button-area noise at y0 (WebKit), next-section avatar noise at y812/813.
