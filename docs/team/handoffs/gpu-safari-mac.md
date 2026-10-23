# gpu-safari-mac handoff

Branch `worktree-wf_57bd0747-50d-1`, worktree `.claude/worktrees/wf_57bd0747-50d-1`. Last commit: `git log -1` (branch tip). Based on main f3248e954.
CI runs: none pushed. The Mac rows are lane exception (c) (the real Apple GPU runs only here); CI rows they pair with are in `results/gpu-safari/lane/ci-pairs.mjs`.

Verified (MEASURED, macOS Safari 27.0.1 through safaridriver, measure slot, Mac unlocked all session):
- nav (3 arms), morph alone and bundled, pain, hero.exit:threaded, people.o:preview-translate vs faithful in one session: `results/gpu-safari/mac-<arm>.json`;
  pairing with Simulator rows: `results/gpu-safari/mac-vs-sim.json` (`node results/gpu-safari/lane/pairs.mjs --write`).
- Nav above the later-load floor at every state (4x to 326x); pain 0 px at all five states; people-o 0 px at f10/f20/f40; morph inconclusive on the Mac
  (noise as large as the arm); hero above the floor at x0.25 and x0.5 in two sessions (size at x0.5 not repeated), identical at x0.75.
- Item 2: `probe-fade.mjs` / `mac-bundled-vs-threaded.json`: the bundled arm's computed opacity and blur equal the CSS path (platform 47.5% in frame), style equal at all three states; pixel-identical in the Simulator at m0.25 only.
- Item 3: Lean `Fw.Measure.GpuElapsed` (both-side proofs), golden `results/gpu-safari/lane/elapsed.golden.jsonl`, checked in `lean/scripts/check.sh` and `lane.test.mjs` (14 tests pass).
- Quiet rule refuses timing on macOS too (`mac-quiet-refusal.json`, 12 of 12 refused, load 2.8 to 3.7).

Open: people.carousel:crop (timer-driven swap, needs parked timers); a third hero session plus a CI Simulator hero row; the phone is not measured;
moving the lane to `packages/measure-webkit`; the TS stand-ins listed in the note. Files outside the task writes: `lean/Fw/Measure/GpuElapsed.lean`,
`lean/scripts/GpuElapsedGolden.lean`, `lean/Fw.lean`, `lean/scripts/check.sh`.

Conventions: Mac shots stay in `$TMPDIR/fw-gpu-safari-shots`, never committed. The Mac pages do not freeze fully, so read the nearest-later-load count against the floor, not the grade.
Start with `research/notes/2026/10-2x-gpu-safari-lane.md` (section "macOS Safari arms"). Re-run: `pnpm -s fw slot acquire --kind measure --lease 3000`, then
`node results/gpu-safari/lane/run.mjs mac <nav|morph|pain|hero|people|all>` in its own process group; release the slot after.
