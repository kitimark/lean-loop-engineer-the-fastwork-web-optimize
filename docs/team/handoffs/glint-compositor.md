# glint-compositor handoff

Branch `worktree-wf_f7fe370b-113-1`, worktree `.claude/worktrees/wf_f7fe370b-113-1`, CI branch `ci/glint-compositor`.
Pushes used: 2 of 3 (090b513b4 push 1, 182cf1ae6 push 2). Last pushed commit 182cf1ae6.
CI runs: wktr 40833327416 success (r1, results/glint-compositor/r1), premise-tests 40833327444 failure (old premise, recorded the look numbers),
wktr 40837035176 (r2, running), premise-tests 40837035170 (new premise, running).

Verified (MEASURED, run 40833327416, WKTR pref OFF, 3 jobs): idle recalcs per 100 frames base 100-102, floor 0, compositor 0 in 3 of 3 jobs (within the floor band);
flip base 185-232, floor 74-92, compositor 85-94 (within, within, cuts partly; overall mixed). Look: class L, dash end caps differ by 35 to 94 of 255 in both
engines (run 40833327444), inside the dash within the bound 12. Lean stops_eq, golden and site tests, check.sh green except the footprint-diff golden fixed in 5eaad3bb4.

Built: Lean `Fw.Parts.PlatformGlintCompositor(+Golden)`, `Fw.Device.GlintHoldCompositor`, premise `glint.compositor-pixels`, flag `platform.glint:compositor` (class L, part.json,
Visuals.tsx CompDash, visuals.module.css, compositor.ts, compositor.gen.ts), WKTR mode `glint-comp-thr-off` + stand-in `glint-compositor*.mjs`, ledger row n=95 and note, note
`research/notes/2026/10-2x-glint-compositor.md`.

Open: (1) `.github/workflows/wktr.yml` carries the TEMPORARY compositor build/mode edit again for push 2: revert (`git checkout b70d3b3a8 -- .github/workflows/wktr.yml`)
before landing; (2) read r2 and the new premise run (`fw ci wait <id>`), add r2 to results and the note; (3) check.sh through fw slot at the final commit, tests, dry land,
`fw review ready`. Chromium counts lane not run (no on-screen glint profile). Files outside the graph writes: lean/Fw/Ops/Premise.lean,
packages/contracts/golden/ops/premise.jsonl, packages/contracts/golden/preset/look-change.candidates.jsonl, packages/premise-tests/pages/glint.compositor-pixels.html,
packages/contracts/golden/parts/footprint-diff.gen.json.
