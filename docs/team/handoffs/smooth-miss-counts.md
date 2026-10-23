# smooth-miss-counts handoff

Branch: `worktree-wf_052bd076-8ce-1`. Worktree: `.claude/worktrees/wf_052bd076-8ce-1`. Last commit: d4dd26410 (push server); code commits 93dc4c514, b7e1e6c2c, 1b6f69d86, d4dd26410.
CI branches (push form `git branch -f ci/<x> HEAD`, `git push origin ci/<x>`): ci/smooth-miss-counts (1b6f69d86), ci/smooth-miss-counts-wk (2231f63a6), ci/smooth-miss-counts-wk2 (d4dd26410). Dispatches used: 3 of 6.

CI runs (workflow smoothness)
- 39897279523 Chromium cadence, 6 jobs (390/1280 x 3 sets): complete, success. Counts and histograms read from it.
- 39897310152 WebKit mac x3 success; sim job 1 INCOMPLETE (touch push: one xcodebuild per window took 90 s, Timeline.stop timed out, then driver exit 64); sim jobs 2, 3 pending/failing the same way.
- wk2 run (id not yet seen): sim end window through one long XCUITest `PushServer` (go-n/done-n files); mac again.

Verified (local, debug only)
- Lean `Fw.Gate.Smooth` builds (over25/34/50, skips, longGaps, Counts, ordering theorems); golden `smooth.jsonl` `--check` up to date.
- gate-breakpoints 652, measure-webkit 406+, ci-paths 54 pass; Swift files typecheck with swiftc against the iOS Simulator SDK.

Results so far
- Chromium: counts per window and arm in cadence.table.md (3 jobs per width). Histograms: `Browser.getHistograms` answers, but ScrollJank/Smoothness/Checkerboarding hold no sample in the headless shell (all windows empty).
- skipped slots == over 25 ms in every Chromium cell (frames on exact vsync); on mac WebKit they differ (hero base 291 vs 263).

Open
- Read the wk2 sim jobs: did the touch push reach the page (`push`, `touched` in sim.json rows), how many kept end windows.
- Research note `research/notes/2026/10-23-smooth-miss-counts.md`, merge main, dry land, `fw review ready`.
- `lag/probe.mjs` morphRun still uses the synthetic WheelEvent (its report assumes fixed idle/open/close frame counts): follow-up.
- Files outside the task writes: gate-breakpoints `src/smooth/*`, `test/smooth.test.mjs`; measure-webkit `src/profile/*`, `src/touch-push.mjs`, `src/throttle/driver.mjs`, `src/throttle/driver/UITests/PushServer.swift`, `test/*`; `.github/workflows/smoothness.yml`.
