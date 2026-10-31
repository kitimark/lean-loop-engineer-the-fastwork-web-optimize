branch: worktree-wf_5d322fb6-6d3-1 (CI branch ci/sweep-pause-all)
worktree: .claude/worktrees/wf_5d322fb6-6d3-1
last commit: f195bd44b (pushed to ci/sweep-pause-all; later commits are handoff only)
CI runs: webkit-sim end-floor (arm set sweep) 41186783133 at f195bd44b running; breakpoint-gate on push 41186783098 running (tip tag; old push gate 41182219607 at cb16967d6 passed, dispatch gate 41181634194 stale); older webkit-sim 41182219539 complete (premise finding); gate: run id added by the lead

Verified locally: vitest platform.sweep (3 files), @fw/site typecheck, part-footprint --check after --write.
Open: CI Simulator census of the fix (arm set sweep, tag [end-sweep]): hidden loops running 0 at end in 3 of 3 jobs; merge main, regenerate footprint, dry land; gate: run id added by the lead.

State: cause found (platform scene CSS rule restarts hidden loops when the section comes near; no IO report follows). `watchSweepPause(els, IO, now, host)` re-holds on a scene attribute change; pauses every running loop; no-start-time loops resume at currentTime + paused. Local Playwright repro passes (dbg script in session scratchpad only).
Harness: SWEEP_LOOPS_JS and arm `sweepPause` in packages/measure-webkit/src/sim-end-floor.mjs (own function, rows line "sweep loops <arm>").
Finding only: platform:faded-pause conflict (two owners of pause/startTime; could compose with a reason set; new Lean case, follow-up).
Read first: research/notes/2026/10-31-sweep-pause-all.md.
