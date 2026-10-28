# geom-track-style handoff (graph r552, round 2)

Branch worktree-wf_ee9ffcfe-af8-1 (worktree .claude/worktrees/wf_ee9ffcfe-af8-1 under the main checkout), CI branch ci/geom-track-style. Both pushes used; none left, round 2 pushes nothing.
State: investigation finished, note research/notes/2026/10-2x-geom-track-style.md (read it first). Ledger note in research/findings/ledger.json (rewritten in round 2).
CI runs: push 1 (7a177f5f4) breakpoint-gate 40611977476, wktr 40611977559 (cancelled, j3 lost); push 2 (1b00b7447) lean 40616651280 success, breakpoint-gate 40616651357 (track-accel r1..r3 success), wktr 40616651419 (j1, j2, j3 success).
flip-cell playwright-webkit (morph.geom:on) failed on both pushes: 40611977476 at 360x640 and 640x1000 (7 of 48), 40616651357 at 640x1000 m=0..0.5 (3 of 48; columns 0 of 3, images 0 of 13). Cause unknown; it is not the geom-style-cut A4 failure; this branch changes no site or flip-cell code. Follow-up: rerun on main to tell a flake from a pattern.

Round 2 (review round 1 refused): per-frame figures divided elements by main frames, which differ about 4x between arms. Re-derived per flip window from the run 40616651357 artifacts:
at 1440 all tracks 7-8 frames, 585-702 elements, 13.7-15.6 ms; transform paused 30-31 frames, 1353-1546, 27.3-33.4 ms; translate paused 28-31, 1515-1678, 24.9-33.9 ms. Verdict: no Chromium style-work reason to fold the image transforms; the proposed geom-image-column-scale is withdrawn.
Lean `MorphTrackAccel`: per-flip window rule (`counted`, `flipTotal`), `foldReason` (elements and time each their own theorem), measured reps, `no_fold_reason_any_band`, `all_lowest_wide`. TS stand-in: `windowsOf`/`armSummary` (track-accel.mjs) apply the rule without a golden.

Verified:
- Lean MorphTrackAccel (play-state, property, constant gates, per-flip rule), golden unchanged, TS golden test, gate-breakpoints test, check.sh (see the final commit).
- Chromium timed: filter tracks and column:0 translate stay on main; all else gets cc starts; judge ok in 9 of 9 timed cells. Scrubbed: nothing on the compositor.
- WebKit: scrubbed 55/55 paused; timed per-element readout, 5 of 6 after the settle cancel, j3 all-again with all 55 running (translate 20/20, transform 18/26).
- WebKit source (862f17d): a running, completely accelerated effect schedules no tick (AnimationEffect.cpp:385-396, KeyframeEffect.cpp:2724-2744).
Open: WebKit question (which rendered tracks are not running accelerated mid-flip; what else writes style per frame on the phone) and the proposed next task geom-webkit-midflip (WKTR, settle cancel after the readout); flip-cell rerun on main; pooled per-property judge.
Conventions: scratch in the session scratchpad; compound shell commands are refused, use Edit/Write; commit trailers per CLAUDE.md; heavy runs through `pnpm -s fw slot run`.
