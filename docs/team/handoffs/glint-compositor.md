# glint-compositor handoff

Branch `worktree-wf_f7fe370b-113-1`, worktree `.claude/worktrees/wf_f7fe370b-113-1`, CI branch `ci/glint-compositor` tip 79077612d, pushes used 4 of 4 (last).
CI runs: wktr 40845872049 success (valid, glintLive 2), premise-tests 40845872174 success, premise-tests 40837548139 success (look numbers);
older: wktr 40833327416 and 40837547847 success but invalid for the variant; premise-tests 40833327444 and 40837035170 failed (older premise definitions); 40837035176 stopped (stale tip).

Verified
- Lean `Fw.Parts.PlatformGlintCompositor` (stops_eq, shiftAt_eq, variant_no_smil, variant_no_writes), golden-generated keyframes `compositor.gen.ts`, site tests, runner tests,
  check.sh green at the final commit of this branch.
- Look (MEASURED, run 40837548139, Chromium 156 and WebKit 27.2, dpr 1 and 2): dash interior differs by at most 3 of 255 (bound 12 fixed before the data), edge pixels
  (round-cap columns, partly covered top/bottom rows) by up to 94, so class L (user look review). Flag is not in a preset.
- WKTR valid reading run 40845872049 (glintLive 2), results/glint-compositor/r4: idle within the floor band in 3 of 3 jobs, flip cuts partly in 3 of 3; premise-tests 40845872174 success.

Open: user look review (class L), edge-exact variant, flip residual (80-88 vs floor 68-75, split by rs.kt/rs.internals), Chromium counts lane, move the glint-compositor.mjs reduction into fwcore (JS reduction is a temporary stand-in).
Read first: research/notes/2026/10-2x-glint-compositor.md.
