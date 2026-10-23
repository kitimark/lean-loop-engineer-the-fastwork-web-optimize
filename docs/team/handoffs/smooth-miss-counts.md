# smooth-miss-counts handoff

Branch: `worktree-wf_052bd076-8ce-1`. Worktree: `.claude/worktrees/wf_052bd076-8ce-1`. Last commit: 2231f63a6 (empty, carries `[webkit-cadence]`); code commit 1b6f69d86.
CI branches: `ci/smooth-miss-counts` (head 1b6f69d86, Chromium cadence), `ci/smooth-miss-counts-wk` (head 2231f63a6, WebKit mac + sim).

CI runs (workflow smoothness)
- 39897279523 Chromium cadence, ci/smooth-miss-counts: in_progress
- 39897310152 WebKit mac + sim, ci/smooth-miss-counts-wk: queued

Verified (local, debug only)
- Lean `Fw.Gate.Smooth` builds with over25/34/50, skips, longGaps, `Counts` and the ordering theorems; golden `smooth.jsonl` regenerated, `--check` up to date.
- gate-breakpoints and measure-webkit unit tests pass (measure-webkit 406 at 1b6f69d86); `scripts/ci-paths.test.mjs` 54 pass.

Done in code (not yet seen in CI)
- Chromium cadence rows carry `th` and `hist` (browser CDP `Browser.getHistograms`, ScrollJank, Smoothness, Checkerboarding; null when the browser refuses); table prints counts per window and arm.
- WebKit rows carry `th`; `profile/report.mjs` cadence table has over 25/34/50, skipped slots, frames.
- Simulator end window pushes by real touches (`measure-webkit/src/touch-push.mjs`, `profile/recorder.mjs` `endTouchJs`, XCUITest driver of the toolbar-throttle probe, built in the `webkit-sim` job). It falls back to the synthetic wheel and says why (`push` in sim.json, `end push` column in the run table).

Open
- Results and run ids go in `research/notes/2026/10-23-smooth-miss-counts.md` once the runs finish.
- `lag/probe.mjs` morphRun still uses the synthetic WheelEvent: its report assumes fixed idle/open/close frame counts; follow-up.
- Files outside the task writes: gate-breakpoints `src/smooth/*`, `test/smooth.test.mjs`; measure-webkit `src/profile/*`, `src/touch-push.mjs`, `test/*`; `.github/workflows/smoothness.yml`.
