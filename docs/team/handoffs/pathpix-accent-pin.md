branch: worktree-wf_6d52745a-a7b-1 (CI branch ci/pathpix-accent-pin)
worktree: .claude/worktrees/wf_6d52745a-a7b-1
last commit: see git log (code at 968f4a27b; later commits only note, handoff, merges)
CI runs: 39943789128 (path-pix, 32d2316b3, pin once per arm): complete, success. 39947605395 (path-pix, 968f4a27b, re-pin before every freeze): complete, success.
verified: run 2, Chromium hero_copy A/A floor 0 at every cell in both jobs; WebKit 0 at y 1, 213, 427 in both jobs, 48 px at delta 1 inside the mask at y 0 (not the accent); no invalid cells (run 1 had the y 427 ones in webkit-2); A2 and P accent signatures equal the served one at shot start and end in all rows. Lean check, measure-webkit 426, measure-chromium 75, ci-paths 54 green.
open: runner test and fw land dry on the final tree; follow-ups: countdown seconds digit, 48 px button-area noise at y 0 (WebKit), avatar noise y 812/813, webkit-1 arm A accent re-created at y 855/856 (cells there not usable), repeat the workflow with 3 or more jobs.
read first: research/notes/2026/10-2x-pathpix-accent-pin.md

Task: pin the hero accent word identically in A, A2 and P before capture, without a site change.
- Pin: PIN_ACCENT_EXPR (packages/measure-webkit/src/pathpix-exit-page.mjs) replaces the live accent element by the
  element of the page as served (a synchronous request of the same URL), so every arm shows the server-rendered word in
  its idle state; the live chain keeps writing to the detached element. WebKit lane: after __wk.hold(), and again before each freeze;
  Chromium lane: end of loadArm in exit mode and before each freeze. Manifest handover.pin.<arm> = { before, ssr, after, same } (hashes);
  rows[].accent = { drift, shotStart, shotEnd }.
- Lean: lean/Fw/Gate/PathPix.lean "Accent pin" (armPin_all, pinAt_same, pinAt_all, shown_ssr, shown_none, shown_arm_independent, region_pin);
  golden kinds accentPin (with perOffset) and pinRegion in packages/contracts/golden/gate/path-pix.jsonl (regenerate: lake build Fw.Gate.PathPix, then lake env lean --run scripts/PathPixGolden.lean > golden).
- TS twin: armPin, pinAt, shownAccent, pinMasks in pathpix-exit.mjs; armPin, pinAt in measure-chromium/src/pathpix-pure.mjs.
