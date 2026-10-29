# glint-compositor handoff

PUSH 4 done and valid: wktr run 40845872049 success (glintLive 2), premise-tests run 40845872174 success, tip 79077612d. Idle: base 100 / floor 0 / compositor 0 per 100 frames (within band, 3 of 3); flip 171-176 / 68-75 / 80-88 (cuts partly). wktr.yml edit reverted. Note updated (results/glint-compositor/r4). Remaining: check.sh, tests, dry land, review ready.

Branch `worktree-wf_f7fe370b-113-1`, worktree `.claude/worktrees/wf_f7fe370b-113-1`, CI branch `ci/glint-compositor` (tip ced74ee8c). Pushes used 3 of 3.
CI runs: premise-tests 40837548139 success (final premise, both engines), 40833327444 and 40837035170 failed (older premise definitions, recorded the look numbers);
wktr 40833327416 (r1) and 40837547847 (r3, "r2" in results/) success but INVALID for the variant; 40837035176 stopped (stale tip).

Verified
- Lean `Fw.Parts.PlatformGlintCompositor` (stops_eq, shiftAt_eq, variant_no_smil, variant_no_writes), golden-generated keyframes `compositor.gen.ts`, site tests, runner tests,
  check.sh green at the final commit of this branch.
- Look (MEASURED, run 40837548139, Chromium 156 and WebKit 27.2, dpr 1 and 2): dash interior differs by at most 3 of 255 (bound 12 fixed before the data), edge pixels
  (round-cap columns, partly covered top/bottom rows) by up to 94, so class L (user look review). Flag is not in a preset.

NOT verified: the WKTR recalc comparison. The probe (`packages/measure-wktr/src/mid-page.mjs` rsArm) paused the variant's own Web Animations, so the compositor arm's 0
idle recalcs are not a reading (glintLive 0). Fixed in the last commits (option `gk`, `rs.glintLive`; Lean `judgeLive`, golden, stand-in), NOT re-run. To measure: a 4th push of
`ci/glint-compositor` with `[ci:wktr] [accel]` and the temporary wktr.yml edit (build `--config "?fw=morph.geom:on,morph.tween:geom-timed,platform.glint:compositor"`,
accel `--modes glint-base-thr-off,glint-comp-thr-off`; commit 5eaad3bb4 has the exact edit), then `node packages/measure-wktr/src/glint-compositor-cli.mjs <job dirs>`.

Open: the corrected WKTR run (above); Chromium counts lane not run (no on-screen glint profile); user's look review (class L).
Files outside the graph writes: lean/Fw/Ops/Premise.lean, packages/contracts/golden/ops/premise.jsonl, packages/contracts/golden/preset/look-change.candidates.jsonl,
packages/premise-tests/pages/glint.compositor-pixels.html, packages/contracts/golden/parts/footprint-diff.gen.json.
Read first: research/notes/2026/10-2x-glint-compositor.md.
