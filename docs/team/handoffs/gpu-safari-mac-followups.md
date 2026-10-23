branch: worktree-wf_fd853f1b-e98-1
worktree: .claude/worktrees/wf_fd853f1b-e98-1
last commit: see `git log -1` (branch tip); first work commit cd6eae4c3
CI runs: none pushed (the Mac rows are lane exception (c): the real Apple GPU runs only on this Mac); CI rows they pair with: `results/gpu-safari/lane/ci-pairs.mjs`.
state: IN PROGRESS (checkpoint written during the Mac sessions)

Done so far (MEASURED on this Mac, macOS Safari 27.0.1 through safaridriver, measure lease held, screen unlocked, IOConsoleLocked false before each session):
- carousel session 1 (people.carousel:crop mid-swap, timers parked): `results/gpu-safari/mac-people-carousel-crop.json`.
- quiet rule with `--mine <own token>`: 8 of 8 quiet in two attempts (`results/gpu-safari/mac-quiet-s1.json`, `-s2.json`).
- Lean `elapsed_largest` proved in `lean/Fw/Measure/GpuElapsed.lean`.

Open: hero sessions s2 and s3, morph floor session (6 loads), carousel repeat, per-arm run-kind table (done in lane.test.mjs), note, final checks, dry land.
Conventions: shots stay in `$TMPDIR/fw-gpu-safari-shots`, never committed; re-run `node results/gpu-safari/lane/run.mjs mac <zone> [--suffix .sN] [--loads N]` in its own process group under `pnpm -s fw slot acquire --kind measure --lease 3000`.
Read first: `research/notes/2026/10-2x-gpu-safari-lane.md` (section "macOS Safari arms").
