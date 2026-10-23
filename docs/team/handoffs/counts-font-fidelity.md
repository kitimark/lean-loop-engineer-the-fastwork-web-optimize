branch: worktree-wf_9e4882e0-ebf-1 (CI branch ci/counts-font-fidelity)
worktree: .claude/worktrees/wf_9e4882e0-ebf-1
last commit: see git log (swipe-touch-v1 maxFrames from Lean, after merging main)
CI runs: 39906869467 font-fidelity failed (rows dir, fixed); 39907447564 font-fidelity success; path-pix 39909931032 success, engine-premises 39909930901 success (push 3783b391d, pick image); chromium-counts swipe-v1 image run 39914488176 success; swipe-touch-v1 39914492010 failed (every counts job: maxFrames); reuse runs swipe-v1 39916914389 and 39916917890 (image_run=39914488176) queued at 07:18Z
verified: pick = liberation (fontPick over 5 font sets; Playwright WebKit macOS reference); Simulator doc height 6042 at 430x775 equals the phone (results/phone/2026-10-17-s1); Lean golden + TS twins; ci-paths tests 54 pass; measure-chromium tests 73 pass
open: refreeze of classes.frozen.json and zone baselines needs 3 workflow runs of one image id per profile (image_run); fw run does not send image_run and gh workflow run is refused in the sandbox, so the lead dispatches them (see note); path-pix / engine-premises re-run on the image; research note; merge main after counts-lane-fonts lands

State
- Lean: lean/Fw/Measure/Profile.lean fontSets (6 candidate sets), fontDist, fontPick, notdefCount; twins in packages/measure-chromium/src/profile.mjs; golden profile.jsonl.
- Measurement code packages/measure-chromium/src/fidelity*.mjs (page function, views m430/p430/d1280, container driver, host orchestrator, Playwright WebKit driver, Simulator driver, comparison writing fidelity-summary.md and fidelity-choice.json).
- Workflow .github/workflows/font-fidelity.yml (guard, chromium, webkit-mac, sim, report); Lean rows in Trigger.lean, Overflow.lean, Pool/Caps.lean, Intent.lean; goldens under packages/contracts/golden/ci; scripts/ci-paths.test.mjs; apps/runner/src/land.ts reads.
- Result: every font-bearing set lays out like WebKit (dist 3 of 6277 px); the font-less image drew 0 lines for web-face text (page 720 px short on mobile, crash at 1280). Lane image keeps fonts-liberation only; no Dockerfile or Lean font constant change.

Next
1. Read path-pix / engine-premises results on the image; write research/notes/2026/10-2x-counts-font-fidelity.md.
2. Lead: refreeze (3 dispatches per profile with image_run, then freeze.mjs and zone-baseline.mjs) as the note lists.
3. Merge main, dry land (VERDICT dry counts-font-fidelity), fw review ready.

Conventions: only ci/counts-font-fidelity* pushes; commit message token starts a lane; at most 8 dispatches (0 used); counts-lane-fonts branch (worktree-wf_c886ec11-19e-1) merged locally, not on main at last check.
