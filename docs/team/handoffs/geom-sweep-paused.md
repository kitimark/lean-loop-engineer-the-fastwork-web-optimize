branch: worktree-wf_6cf1ce10-b7b-1 (CI branch ci/geom-sweep-paused); worktree .claude/worktrees/wf_6cf1ce10-b7b-1
last commit: (set at each commit; see git log)
CI runs: none yet (push 1 pending)
state: Lean verdict + golden + probe arms written, package tests pass (94), no CI evidence yet. 0 of 3 pushes used.

# what exists
- Lean `lean/Fw/Device/SweepPause.lean`: per job `Job.why` (no-frames, idle-not-on, idle-not-off, explains, not-sweep, mixed), `overall` (explains / mixed / notSweep / inconclusive, minValid 2), `Verdict.next`; one theorem per branch; golden `packages/contracts/golden/device/sweep-pause.jsonl`.
- TS stand-in `packages/measure-wktr/src/sweep-pause.mjs` replays the golden (`test/sweep-pause.test.mjs`); the report-to-Job reducer `jobOf` is glue.
- Probe arms `sw-<warm|flip|idle>[-p][-t]` in `mid-page.mjs`; mode `sweep-thr-off` in `accel-cli.mjs` (pref OFF header). Identity: CSSAnimation named `sweep-module_sweepDoc_<hash>` whose target is inside section[data-fw=platform] (4 found in a desktop smoke).
- ci branch only: `.github/workflows/wktr.yml` ACCEL_MODES from the head-commit token `[accel-sweep]` (revert in the final commit).

# open
- push 1 (debug of the flip path: the desktop smoke could not engage geom tracks, the local dist lacks the geom pair).
