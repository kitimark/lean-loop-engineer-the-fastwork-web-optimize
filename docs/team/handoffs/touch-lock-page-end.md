branch: worktree-wf_9543f835-e44-1 (CI branch ci/touch-lock-page-end)
worktree: .claude/worktrees/wf_9543f835-e44-1
last commit: 0a6af7f0e (work); the handoff commit after it carries the CI tags
CI runs: none finished yet (first push in flight; the run id is added after `fw ci` lists it)
verified: Lean module and golden check, measure-webkit test (590 pass), ci-paths test (56), runner land-inputs test (56)
open: reversal counts per arm (needs the run), note, dry land, review gate

# touch-lock-page-end

- Read first: `lean/Fw/Measure/TouchLock.lean` (model, theorems, golden), `packages/measure-webkit/src/touchlock*.mjs` (twin, page scripts, walk, CLI).
- Lane: push `ci/touch-lock-page-end` with the commit-message tags `[ci:smoothness] [webkit-cadence] [sim-only] [touch-lock]`; one webkit-sim job runs `touchlock-cli.mjs run`; artifact `smoothness-webkit-sim-1` holds `touch-lock.json` and `touch-lock.md`.
- Arms: orig (snapshot), base (rewrite), lock (rewrite plus CSS lock shim while the morph is open, one frame late).
- Gesture: flick `{dragPt:500, velocity:1800, holdMs:0}` from `START_GAP_PX = 250` above the end (one XCUITest press cannot start more than 2 viewports away).
- Verdict: a run is jitter iff the open phase has a direction reversal ending at the lock position (`frameFights > 0`).
- Follow-ups: Q2 touchmove deferral analysis, drawn-offset video reversal count, across-job cadence verdict (`sim-touch-verdict-jobs`).
- At most 2 dispatches; free runners only; never push main.
