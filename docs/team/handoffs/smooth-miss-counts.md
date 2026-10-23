# smooth-miss-counts handoff

Branch: `worktree-wf_052bd076-8ce-1`. Worktree: `.claude/worktrees/wf_052bd076-8ce-1`. Code commits 93dc4c514, b7e1e6c2c, 1b6f69d86, d4dd26410, 5406286ac, c2229af20; note d06fe1ce7; main merged after. Read first: `research/notes/2026/10-23-smooth-miss-counts.md`.
CI branches: ci/smooth-miss-counts (1b6f69d86), -wk (2231f63a6), -wk2 (d4dd26410), -wk3 (5406286ac). Dispatches used 4 of 6.

CI runs (workflow smoothness)
- 39897279523 Chromium cadence 6 jobs: complete, success (counts in the note).
- 39897310152 WebKit mac x3 success; sim one xcodebuild per window: INCOMPLETE (superseded).
- 39901005729 (PushServer) complete, success: mac x3 fine; sim x3, first touch end window worked in each job (orig 251-353 frames), later ones hit the Timeline.stop 60 s timeout.
- 39909042070 (Timeline.stop 240 s) complete, cancelled: mac x3 success (same verdicts); sim 1 and 3 cancelled at the 50 min step limit, sim 2 success with 0 touch end windows of 15.

Verified
- Lean `Fw.Gate.Smooth` counts and theorems, golden `--check`, `sh lean/scripts/check.sh` green after the first main merge.
- Tests: gate-breakpoints 652, measure-webkit 407, ci-paths 54, runner land-inputs 56 pass.
- Dry land passes with `--allow` for the files outside the task writes (listed in the report `open`).

Findings
- Chromium: skipped slots equal over 25 in every cell; headless shell histograms (ScrollJank, Smoothness, Checkerboarding) are empty.
- Mac WebKit (real wheel): hero orig vs base "second" and end "same" in 6 of 6 jobs over 2 runs.
- Simulator real touch is not reliable on CI: XCUITest idle waits make a push take 50 to 130 s and the Timeline stops time out. Do not dispatch for it again without a new idea.

Open
- `lag/probe.mjs` `morphRun` still uses the synthetic WheelEvent: its report assumes fixed idle/open/close frame counts (follow-up).
- Simulator orig hero keeps 1 to 7 frames per window (pre-existing starvation).
