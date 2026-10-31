branch: worktree-wf_5d322fb6-6d3-1 (CI branch ci/sweep-pause-all)
worktree: .claude/worktrees/wf_5d322fb6-6d3-1
round 2 (refused r1: Scene premise false after a script pause). Fix: scene-frozen spans tracked while held (pause.ts setScene/close/resumeTime/startShift; MutationObserver reads data-fw-scene). Lean: PlatformSweepPause "Held loops" (fold_core, events_core, resume_same, start_same by induction; Override = CSSAnimation.cpp:278-287@862f17d). Golden platform-sweep-pause.jsonl 17 lines. Footprint: platform.sweep now reads platform's scene attribute -> Bridge codeAdj row 28 gains 33.
CI runs: webkit-sim 41196494063 at ce9eb255b: pass, hidden sweep loops running 0 of 2 at end and back in 3 of 3 jobs (results/sweep-pause-all/r3/sweep-loops.txt); breakpoint gate: run id added by the lead (single-flag gate is a lead dispatch)
Verified locally: check.sh green, vitest platform.sweep, @fw/site typecheck, part-footprint --check, ContractsGolden --check.
Open: lead dispatches the single-flag gate; platform:faded-pause composition (finding only); hero.accent/hero.cue watchers may have the same scene shape.

--- round 1 handoff below (older) ---
branch: worktree-wf_5d322fb6-6d3-1 (CI branch ci/sweep-pause-all)
worktree: .claude/worktrees/wf_5d322fb6-6d3-1
last commit: aa0a30d0d (merge main + Lean theorems + goldens); ci/sweep-pause-all is at c74f1111e, not pushed again (shipped code differs by the extracted holdNew helper, same branch condition)
CI runs: webkit-sim end-floor (arm set sweep, the fix) 41189420040 at c74f1111e: pass, hidden sweep loops running 0 of 2 at end and back in 3 of 3 jobs; breakpoint gate both engines, flag alone: pass, run 41190009074 at c74f1111e (flip-cell playwright-webkit passed on re-run; first attempt failed A4 1 of 3 passes, a flake also seen on runs 41181634194, 41186783098, 41189419989 of this branch, control on main pending); earlier runs 41182219539 and 41186783133 are pre-fix evidence

Verified locally: vitest platform.sweep (3 files), @fw/site typecheck, part-footprint --check after --write.
Open: platform:faded-pause composition (finding only); hero.accent/hero.cue watchers may have the same scene-restart shape; the 2 in-view sweep loops still run at the end of the page (by design, same look).

State: cause found (platform scene CSS rule restarts hidden loops when the section comes near; no IO report follows). `watchSweepPause(els, IO, now, host)` re-holds on a scene attribute change; pauses every running loop; no-start-time loops resume at currentTime + paused. Local Playwright repro passes.
Harness: SWEEP_LOOPS_JS and arm `sweepPause` in packages/measure-webkit/src/sim-end-floor.mjs (own function, rows line "sweep loops <arm>").
Finding only: platform:faded-pause conflict (two owners of pause/startTime; could compose with a reason set; new Lean case, follow-up).
Read first: research/notes/2026/10-31-sweep-pause-all.md.

Lean theorems (PlatformSweepPause: fold_core, events_core, resume_same, start_same, untracked_differs, resume_pending_phase, hold_* , rehold_keeps/idem; OffscreenPause.look_same_pending), golden platform-sweep-pause.jsonl 14 lines, TS replays resumeTime/holdNew. Main merged, footprint goldens regenerated. Open: census of run 41189420040 (still in_progress), check.sh, tests, plan lint, dry land.

Done: run 41189420040 census hidden loops running 0 of 2 at end/back in 3 of 3 jobs (results/sweep-pause-all/r2). check.sh green, site/measure-webkit/ci-paths/land-inputs tests green, plan lint 0 errors. Open: dry land result in the report; gate dispatch by the lead.
