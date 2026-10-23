branch: worktree-wf_9e4882e0-ebf-1 (CI branch ci/counts-font-fidelity)
worktree: .claude/worktrees/wf_9e4882e0-ebf-1
last commit: 6dbd68b6b
CI runs: 39906869467 font-fidelity (in progress; pushed at 6dbd68b6b)
verified: Lean pick rule (Profile.lean "Font fidelity", golden + TS twins, 12 profile tests); ci-paths tests 54 pass; measure-chromium tests 73 pass
open: first CI result unread; set not chosen; no re-measure yet; Dockerfile/fonts.conf/Lean font constants unchanged

State
- Lean: lean/Fw/Measure/Profile.lean fontSets (6 candidate sets), fontDist, fontPick, notdefCount; twins in packages/measure-chromium/src/profile.mjs.
- Measurement code (packages/measure-chromium/src/fidelity*.mjs): page function (fidelity-page.mjs), views m430/p430/d1280, container driver, host orchestrator (fetches each set's Debian packages inside the lane image), Playwright WebKit driver, comparison (fidelity-compare.mjs, writes fidelity-summary.md and fidelity-choice.json).
- Workflow .github/workflows/font-fidelity.yml (chromium, webkit-mac, report); Lean rows added in Trigger.lean, Overflow.lean (width 2), Pool/Caps.lean (excluded), Intent.lean (macosFiles); goldens under packages/contracts/golden/ci regenerated; scripts/ci-paths.test.mjs excluded list.

Next
1. pnpm -s fw ci wait --branch ci/counts-font-fidelity --workflow font-fidelity; fetch artifacts; read fidelity-summary.md.
2. Apply the chosen set (Dockerfile, docker/apt-manifest.txt, docker/fonts.conf = Lean fontsConf, Lean font constants + golden), re-measure swipe-v1 / swipe-touch-v1, refreeze classes.frozen.json, zone baselines, path-pix and premise baselines, people-o-hover tallies.
3. Note research/notes/2026/10-2x-counts-font-fidelity.md; merge main; dry land.

Conventions: only ci/counts-font-fidelity* pushes; commit message line [ci:font-fidelity] starts this lane; at most 8 dispatches; counts-lane-fonts branch (worktree-wf_c886ec11-19e-1) merged locally, not on main at last check.
