branch: worktree-wf_95345f2e-b29-1
worktree: .claude/worktrees/wf_95345f2e-b29-1 (under the repo root)
last commit: see git log (handoff written after dispatch)
task: platform-end-variants, STEP 1 only (measure; no step-2 builds).

CI runs (all dispatched with `pnpm -s fw run --target rewrite --ref main`, sha 5c8cccc, 2026-10-25; unchanged code, so no ci/ push):
| id | lane | arm | state |
|---|---|---|---|
| 40203774734 | webkit-sim vms=3 | base | running |
| 40203759230 | webkit-sim vms=3 | platform.sweep:offscreen-pause | running |
| 40203790654 | webkit-sim vms=3 | platform.glint:offscreen-pause | running |
| 40203753344 | chromium-counts swipe-touch-v1 x3 | base | running |
| 40203778407 | chromium-counts swipe-touch-v1 x3 | platform.sweep:offscreen-pause | queued |
| 40203771621 | chromium-counts swipe-touch-v1 x3 | platform.glint:offscreen-pause | queued |
| 40203756095 | chromium-counts swipe-touch-v1 x3 | platform:fade-threaded | queued |
Not dispatched: webkit fade-threaded (already a WebKit no-win, ledger platform:fade-threaded).

verified: nothing yet. open: read counts, Lean verdict rule, write research/notes/2026/10-2x-platform-end-variants.md and ledger notes.
