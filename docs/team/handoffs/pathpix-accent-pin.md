branch: worktree-wf_6d52745a-a7b-1 (CI branch ci/pathpix-accent-pin)
worktree: .claude/worktrees/wf_6d52745a-a7b-1
last commit: see git log (round 2 work at 396892b0e, then the main merge and this handoff)
CI runs: 39943789128 (path-pix, 32d2316b3, pin once per arm): complete, success. 39947605395 (path-pix, 968f4a27b, re-pin before every freeze): complete, success. No new run in round 2.
status: CLOSED AS A FINDING (round 2). Pinning the accent does NOT bring the hero_copy A/A floor to 0. Remaining sources go to graph task hero-copy-floor-sources (r342).
verified: Lean check green; measure-webkit 427, measure-chromium 75, ci-paths 54, runner land-inputs 56 green.
open: fw land dry on the final tree; follow-ups in hero-copy-floor-sources: countdown digit, WebKit 48 px at y 0 (button area), avatar noise y 812/813, webkit-1 run 2 arm A at scrollY 0 on offset index 7, site-side accent hook (React re-creates the swapped node), 3-job repeat.
read first: research/notes/2026/10-2x-pathpix-accent-pin.md (all 9 hero_copy offsets per job, P-cell grade table, conclusion, remaining sources)

Round 2 delivered:
- Note: A/A table for all 9 offsets per job (both runs), P-cell grade table (inside/out, floor, grade, why, L from floor vs strips not accepted), plain conclusion, y 812/813 reworded (hero_copy cells with change).
- Per-row enforcement: Lean PathPix "The pin per measured row" (accentPinned served start stop n, rowsPinned, gradePinned, unpinnedWhy, floorPinned; gradePinned_valid_only_if etc.); golden kinds accentRow and accentGrade (regenerate: lake build Fw.Gate.PathPix, then lake env lean --run scripts/PathPixGolden.lean > packages/contracts/golden/gate/path-pix.jsonl); TS twin in packages/measure-webkit/src/pathpix-exit.mjs (analyzeExit marks accent-unpinned: grade invalid, invalidWhy, floor invalid); Chromium accentPinned in packages/measure-chromium/src/pathpix-pure.mjs.
- Dev check on run 39947605395 manifests: 12 of 232 cells marked accent-unpinned (webkit-1, offset 7, y 855). Run 39943789128 has no per-row records: all 208 cells would be unpinned.
conventions: served signature = handover.pin.A.ssr; a row without accent record is unpinned; accentRowOf is glue (TS stand-in).
