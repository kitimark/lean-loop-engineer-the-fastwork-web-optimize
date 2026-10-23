branch: worktree-wf_9e4882e0-ebf-1 (CI branch ci/counts-font-fidelity)
worktree: .claude/worktrees/wf_9e4882e0-ebf-1
last commit: see git log (main merged 586d04705, then this handoff)
CI runs (ci/counts-font-fidelity unless noted): font-fidelity 39906869467 failed (rows dir, fixed), 39907447564 success; path-pix 39909931032 success; engine-premises 39909930901 success, 39912692117 success (ci/counts-font-fidelity-nofont); chromium-counts swipe-v1 39914488176 success (builds image), 39916914389 success, 39916917890 success (image_run=39914488176); swipe-touch-v1 39914492010 failed (maxFrames); lean 39917882274 (push run)
verified: pick = liberation; swipe-v1 on font image 3 runs, 575 frames, docHeight 6278, same image digest (original det/stable/quar 30/16/24, rewrite 23/22/25 of 70); swipe-touch-v1 maxFrames 2378 from Lean (Swipe section, golden touchPage/touchBudget); lean check, measure-chromium 74, runner 2914, ci-paths 54 pass; dry land with --allow for the 7 out-of-scope files = VERDICT dry
open: (1) dry without --allow = VERDICT scope: font-fidelity.yml, land.ts, lean/Fw/Ci/{Intent,Overflow,Pool/Caps,Trigger}.lean, scripts/ci-paths.test.mjs are outside the task writes (lead widens writes or lands with --allow); (2) refreeze not committed: classes.frozen.json and zone baselines stay as before because freeze.mjs rewrites both profiles; (3) swipe-touch-v1 dispatches below

Touch dispatches (lead; each reuses the swipe-v1 image):
  3x gh workflow run chromium-counts.yml --ref ci/counts-font-fidelity -f profile=swipe-touch-v1 -f target=both -f image_run=39914488176
Then download chromium-c* of the six runs (swipe-v1 three + touch three) and run
  node packages/measure-chromium/src/freeze.mjs <six run dirs> --built-by 39914488176 --out packages/measure-chromium/classes.frozen.json
  zone stores: pnpm -s fw ci <run> --branch ci/counts-font-fidelity, zone-baseline.mjs --store <store> --target original|rewrite --profile <p> --run <id> --out results/baselines/chromium per profile and arm, then zone-baseline.mjs baseline --out results/baselines/chromium
Warning: the touch failure may be a stall (target at stroke start takes the vertical pan), not a frame shortage; the new error message in run.mjs names scrollY, range, moves, events.

Findings: path-pix Chromium A/A no longer reproducible between jobs on the font image (22-28 E of 28); engine-premises differs from font-less in one row (Chromium paint/raster main set, 129/130, margin@own set); WebKit rows hold. Ledger: 37 entries stay INFERRED per entry (table in the note); entries 19 and 54 also cite older runs, not on the list.
Read first: research/notes/2026/10-2x-counts-font-fidelity.md
