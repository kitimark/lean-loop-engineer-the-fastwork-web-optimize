branch: worktree-wf_5d322fb6-6d3-1 (CI branch ci/sweep-pause-all)
worktree: .claude/worktrees/wf_5d322fb6-6d3-1
last commit: 43cbd8aa0 (merge main + Lean theorems + goldens, local only; ci/sweep-pause-all is at c74f1111e)
CI runs: webkit-sim end-floor (arm set sweep, the fix) 41189420040 at c74f1111e running; breakpoint-gate on push 41189420xxx at c74f1111e (tip tag; read id with gh run list); earlier runs 41182219539 and 41186783133 are pre-fix evidence; gate: run id added by the lead

Verified locally: vitest platform.sweep (3 files), @fw/site typecheck, part-footprint --check after --write.
Open: CI Simulator census of the fix (arm set sweep, tag [end-sweep]): hidden loops running 0 at end in 3 of 3 jobs; merge main, regenerate footprint, dry land; gate: run id added by the lead.

State: cause found (platform scene CSS rule restarts hidden loops when the section comes near; no IO report follows). `watchSweepPause(els, IO, now, host)` re-holds on a scene attribute change; pauses every running loop; no-start-time loops resume at currentTime + paused. Local Playwright repro passes (dbg script in session scratchpad only).
Harness: SWEEP_LOOPS_JS and arm `sweepPause` in packages/measure-webkit/src/sim-end-floor.mjs (own function, rows line "sweep loops <arm>").
Finding only: platform:faded-pause conflict (two owners of pause/startTime; could compose with a reason set; new Lean case, follow-up).
Read first: research/notes/2026/10-31-sweep-pause-all.md.

Finisher: Lean theorems added (PlatformSweepPause: resume_pending_same/phase/span, hold_* , rehold_keeps/idem; OffscreenPause.look_same_pending), golden platform-sweep-pause.jsonl 14 lines, TS replays resumeTime/holdNew. Main merged, footprint goldens regenerated. Open: census of run 41189420040 (still in_progress), check.sh, tests, plan lint, dry land.
