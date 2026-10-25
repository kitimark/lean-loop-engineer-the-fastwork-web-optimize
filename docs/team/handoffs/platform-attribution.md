branch: worktree-wf_ffa8b2be-91c-1 (CI branch ci/platform-attribution, pushed once at 063b150fb, probe code only)
worktree: .claude/worktrees/wf_ffa8b2be-91c-1
last commit: see `git log -1` (Lean probe class + WebKit zone verdict committed; CI runs below are on 063b150, the site code)
state: waiting (9 dispatches, all `pnpm -s fw run --target rewrite --ref ci/platform-attribution`; 1 of 3 pushes used)

CI runs (state at 21:40 UTC 2026-10-25, fill in as they finish):
| id | lane | arm | state |
|---|---|---|---|
| 40236443781 | webkit-sim vms=3 | platform.sweep:probe-off | queued |
| 40236465002 | webkit-sim vms=3 | platform.glint:probe-off | running |
| 40236534457 | webkit-sim vms=3 | platform.entries:probe-off | running |
| 40236475717 | webkit-sim vms=3 | platform.marquee:probe-off | running |
| 40236531932 | webkit-sim vms=2 | base (VM r1 rerun, r2 extra) | running |
| 40236459376 | chromium-counts swipe-touch-v1 x3 | platform.sweep:probe-off | running |
| 40236516819 | chromium-counts | platform.glint:probe-off | queued |
| 40236472868 | chromium-counts | platform.entries:probe-off | running |
| 40236462082 | chromium-counts | platform.marquee:probe-off | running |
Chromium base is run 40203753344 (previous task, main 5c8cccc, same profile, code differs only by the added variants); WebKit base is
40203774734 (r2, r3) plus the rerun r1 above.

verified: probe class (Lean Kind.probe, probe_not_mem / probe_not_mem_lookCandidates / probe_not_isOpt, golden preset/probes.jsonl,
vitest registry/probes.test.ts); WebKit zone verdict (Lean OffscreenWebKit + golden offscreen-webkit.jsonl + node test).
open: read the 9 runs (recipe: note research/notes/2026/10-2x-platform-end-variants.md; `gh run download <id> -p 'webkit-sim-r*'` /
`-p 'chromium-counts-rewrite-r*'`), run Lean verdict on them (packages/measure-webkit/src/offscreen-webkit.mjs, passOf), write
research/notes/2026/10-2x-platform-attribution.md and the ledger rows, then check.sh, tests, merge main, lake build, plan lint, dry land.
conventions: waiters (`fw run`) die with the session; read runs directly with gh run view <id>. Scratch in scratchpad/pat/.
