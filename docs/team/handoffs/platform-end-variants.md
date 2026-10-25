branch: worktree-wf_95345f2e-b29-1
worktree: .claude/worktrees/wf_95345f2e-b29-1 (under the repo root)
last commit: see git log; step 1 complete (measure only; no step-2 build)

CI runs (dispatched with `pnpm -s fw run --target rewrite --ref main`, main 5c8cccc, unchanged code, no ci/ push):
| id | lane | arm | state |
|---|---|---|---|
| 40203774734 | webkit-sim vms=3 | base | r2, r3 success, r1 cancelled (runner), run cancelled |
| 40203759230 | webkit-sim vms=3 | platform.sweep:offscreen-pause | success |
| 40203790654 | webkit-sim vms=3 | platform.glint:offscreen-pause | success |
| 40203753344 | chromium-counts swipe-touch-v1 x3 | base | success |
| 40203778407 | chromium-counts | platform.sweep:offscreen-pause | success |
| 40203771621 | chromium-counts | platform.glint:offscreen-pause | success |
| 40203756095 | chromium-counts | platform:fade-threaded | success |

verified: all 7 runs read; note research/notes/2026/10-2x-platform-end-variants.md (answer first); ledger notes appended (3 rows).
Result: no existing variant wins at the page end on either engine (Lean cmp/judge twin); fade-threaded Chromium no-win (area 2.1x);
premises for step-2 (a) sweep, (b) glint, (c) entries are NOT measured (pause arms are no-ops while visible); next = attribution arm per part.
open: attribution arms (follow-up round); WebKit open/close push split needs the lag/cost lane (no fw run input); fw run webkit waiter bug
(nonce matches the same run id twice, exit 1; runs fine). Scratch scripts scratchpad/pev/{ch,wk}.mjs are not committed (rebuild from run ids; recipe in the note).
read first: the note.
