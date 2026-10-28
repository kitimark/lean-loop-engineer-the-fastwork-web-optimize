# geom-track-style handoff (graph r552)

Branch worktree-wf_ee9ffcfe-af8-1 (worktree .claude/worktrees/wf_ee9ffcfe-af8-1 under the main checkout), CI branch ci/geom-track-style. Both pushes used; none left.
State: investigation finished, note written: research/notes/2026/10-2x-geom-track-style.md (read it first). Ledger note appended in research/findings/ledger.json.
CI runs: push 1 (7a177f5f4) breakpoint-gate 40611977476, wktr 40611977559 (cancelled, j3 lost); push 2 (1b00b7447) lean 40616651280 success,
breakpoint-gate 40616651357 (track-accel r1..r3 success; only flip-cell playwright-webkit fails, the geom-style-cut flake), wktr 40616651419 (j1, j2, j3 success; j3 all-again caught all 55 running, accel translate 20/20, transform 18/26).

Verified:
- Lean MorphTrackAccel (play-state, property, constant gates), golden regenerated and checked, TS golden test, gate-breakpoints test (4), check.sh green at c0c08b81b, package tests green.
- Chromium timed: filter tracks and column:0 translate stay on main; all else gets cc starts; judge ok in 9 of 9 timed cells. Scrubbed: nothing on the compositor.
- Per-frame style (Chromium): every track target gets `StyleRecalc:Animation` per frame even when composited; pausing transform or translate drops 84-92 to 45-54 elements per frame at 1440.
- WebKit: scrubbed 55/55 paused; timed readout only per element, taken after the driver cancelled the tracks.
Open: run ids in `fw review ready`; dry land; the proposed fix task (fold image transform tracks into a column scale) is a follow-up, not started.
Conventions: scratch in the session scratchpad; compound shell commands are refused, use Edit/Write; commit trailers per CLAUDE.md; heavy runs through `pnpm -s fw slot run`.
