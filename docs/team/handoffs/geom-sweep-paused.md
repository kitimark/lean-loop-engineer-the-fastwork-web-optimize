branch: worktree-wf_6cf1ce10-b7b-1 (CI branch ci/geom-sweep-paused); worktree .claude/worktrees/wf_6cf1ce10-b7b-1
last commit: see git log (final commit holds note, ledger, results, wktr.yml reverted)
CI runs: wktr 40665823632 (push 1, complete, success) and 40670621458 (push 2, complete, success). 2 of 3 pushes used, none left needed.
state: investigation finished; note research/notes/2026/10-2x-geom-sweep-paused.md; ledger note added; Lean verdict inconclusive (idle-not-off, 6 of 6 jobs).

# result (MEASURED unless tagged)
- 4 sweepDoc animations found and paused in every job; flip engaged. Pausing them: flip recalcs/frame 1.67-2.17 vs 2.0-2.17 (0-17 percent drop; explains needs 75).
- Idle: sweep = 1 of 2 recalcs/frame (2.0 -> 1.0); all animations paused still 1.0 -> residual is not an animation (source INFERRED, probably page script after rAF).
- geom-sweep-compositor not justified for flips; maybe for idle. Next: geom-recalc-source (MutationObserver, rAF counter, per-recalc element count at frame end).
- Style ms is a timed-flush proxy at 1 ms; flip style drop sign flips in 2 of 6 jobs (INFERRED nothing).

# what exists
- Lean `lean/Fw/Device/SweepPause.lean` + golden `packages/contracts/golden/device/sweep-pause.jsonl`; TS stand-in `packages/measure-wktr/src/sweep-pause.mjs` (replays golden; `jobOf` is glue).
- Probe arms `sw-<warm|flip|idle>[-p|-a|-o][-t]` in `mid-page.mjs`; -a/-o are diagnostic (not in the Lean decision); mode `sweep-thr-off` in `accel-cli.mjs`.
- Results `results/geom-sweep-paused/{run1,run2,jobs.txt}`.
- `.github/workflows/wktr.yml` ACCEL_MODES edit is reverted (main keeps default modes); to rerun the sweep lane re-add `[accel-sweep]` token handling on a ci branch.

# open
- Lead decides geom-recalc-source. Trigger.lean/triggers.jsonl/check.sh edits are the golden wiring row for sweep-pause.
- Read first: the note, then `results/geom-sweep-paused/jobs.txt`.
