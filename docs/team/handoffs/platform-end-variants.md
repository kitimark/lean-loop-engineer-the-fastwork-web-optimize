branch: worktree-wf_95345f2e-b29-1
worktree: .claude/worktrees/wf_95345f2e-b29-1 (under the repo root)
last commit: see git log (handoff written after dispatch)
task: platform-end-variants, STEP 1 only (measure; no step-2 builds).

CI runs (all dispatched with `pnpm -s fw run --target rewrite --ref main`, sha 5c8cccc, 2026-10-25; unchanged code, so no ci/ push):
| id | lane | arm | state |
|---|---|---|---|
| 40203774734 | webkit-sim vms=3 | base | queued (macOS) |
| 40203759230 | webkit-sim vms=3 | platform.sweep:offscreen-pause | queued (macOS) |
| 40203790654 | webkit-sim vms=3 | platform.glint:offscreen-pause | queued (macOS) |
| 40203753344 | chromium-counts swipe-touch-v1 x3 | base | complete (success) |
| 40203778407 | chromium-counts swipe-touch-v1 x3 | platform.sweep:offscreen-pause | complete (success) |
| 40203771621 | chromium-counts swipe-touch-v1 x3 | platform.glint:offscreen-pause | complete (success) |
| 40203756095 | chromium-counts swipe-touch-v1 x3 | platform:fade-threaded | complete (success) |
Not dispatched: webkit fade-threaded (already a WebKit no-win, ledger platform:fade-threaded).

verified: Chromium 4 runs done and read (script scratchpad/pev/ch.mjs, gitignored; recreate: frames of counts.json, phases by first scrollY==5342 frame 574, cmp/judge from packages/measure-chromium/src/offscreen.mjs). Finish zone all three arms noGain (sweep +1 recalc, raster -59 in approach only; glint same; fade-threaded raster area 2.1x). WebKit runs: macOS jobs queued 2 h; base r1 started 16:37Z, the rest still queued at 16:50Z. The three `fw run` waiters for webkit died (poller: nonce matches several runs, same id twice, exit 1) but the GitHub runs live; wait with `pnpm -s fw ci wait <id>` and download with `gh run download <id> -p "webkit-sim-r*"`, no refile needed. open: read counts, Lean verdict rule, write research/notes/2026/10-2x-platform-end-variants.md and ledger notes.
