branch: worktree-wf_fd853f1b-e98-1
worktree: .claude/worktrees/wf_fd853f1b-e98-1
last commit: branch tip (`git log -1`); first work commit cd6eae4c3
CI runs: none pushed (Mac rows are lane exception (c), the real Apple GPU runs only on this Mac); paired CI rows in `results/gpu-safari/lane/ci-pairs.mjs`.
state: DONE except the follow-ups below.

Verified (MEASURED on this Mac, macOS Safari 27.0.1 via safaridriver, measure lease held, IOConsoleLocked false before each session):
- carousel (people.carousel:crop mid-swap, timers parked): 2 sessions, 7.2k to 8.7k px above floor 0 at t55/t110/t165; cause = leaver width/margin kept (class L).
- hero.exit:threaded: 3 sessions; x0.25 and x0.5 above floor in all three, size varies 5k to 21k.
- morph: 6-load floor session; floor spans 8k to 87k px, inside platform and nav boxes; Mac morph stays INCONCLUSIVE.
- quiet rule with `--mine <own token>`: 8/8 quiet x5 (`mac-quiet-s1..s5.json`); the old "holders" refusal counted our own lease. No timing instrument exists: Instruments is the follow-up.
- Lean `elapsed_largest` (`lean/Fw/Measure/GpuElapsed.lean`); per-arm run-kind table and new tests in `lane/lane.test.mjs` (18 pass).
- bundled vs threaded pixel difference explained (note, item 9).
Reductions side by side: `results/gpu-safari/mac-sessions.json` (`node results/gpu-safari/lane/sessions.mjs --write`).

Open / follow-ups: Simulator hero row (needs CI); Composite/render-server timing by Instruments; move lane to `packages/measure-webkit`; phone not measured; morph needs an instrument not drowned by platform/nav blur drift.
Conventions: shots stay in `$TMPDIR/fw-gpu-safari-shots`, never committed; run `node results/gpu-safari/lane/run.mjs mac <zone> [--suffix .sN] [--loads N]` in its own process group under a measure lease.
Read first: `research/notes/2026/10-2x-gpu-safari-lane.md` (section "macOS Safari arms").
