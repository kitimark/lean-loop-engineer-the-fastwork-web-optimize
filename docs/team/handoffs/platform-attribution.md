branch: worktree-wf_ffa8b2be-91c-1 (CI branch ci/platform-attribution, pushed twice: 063b150fb, 86b876ba4; one push left)
worktree: .claude/worktrees/wf_ffa8b2be-91c-1
last commit: see `git log -1`
state: waiting on the 5 WebKit Simulator runs (queued for a macOS runner since 21:40 UTC 2026-10-25); Chromium is finished

CI runs (`pnpm -s fw run --target rewrite --ref ci/platform-attribution`):
| id | lane | arm | commit | state |
|---|---|---|---|---|
| 40236459376 | chromium-counts swipe-touch-v1 x3 | sweep v1 (class removed; superseded, Paint artifact) | 063b150 | success |
| 40237508223 | chromium-counts | platform.sweep:probe-off (animation: none) | 86b876b | success |
| 40236516819 | chromium-counts | platform.glint:probe-off | 063b150 | success |
| 40236472868 | chromium-counts | platform.entries:probe-off | 063b150 | success |
| 40236462082 | chromium-counts | platform.marquee:probe-off | 063b150 | success |
| 40237513521 | webkit-sim vms=3 | platform.sweep:probe-off | 86b876b | queued |
| 40236465002 | webkit-sim vms=3 | platform.glint:probe-off | 063b150 | queued |
| 40236534457 | webkit-sim vms=3 | platform.entries:probe-off | 063b150 | queued |
| 40236475717 | webkit-sim vms=3 | platform.marquee:probe-off | 063b150 | queued |
| 40236531932 | webkit-sim vms=2 | base (VM r1 rerun, r2 extra) | 063b150 | queued |
| 40236443781 | webkit-sim | sweep v1 | 063b150 | cancelled by me (replaced by 40237513521) |
Bases: Chromium 40203753344; WebKit 40203774734 (r2, r3) plus the rerun r1 above (1 VM of 3 needed).

verified: probe class (Lean Kind.probe, probe_not_mem, probe_not_mem_lookCandidates, probe_not_isOpt, golden preset/probes.jsonl, vitest
registry/probes.test.ts); WebKit zone verdict (Lean OffscreenWebKit + golden offscreen-webkit.jsonl + node test + CLI). Chromium table
and verdicts in scratchpad/pat/log/ch-final.md (scratch script scratchpad/pat/ch.mjs, uses the Lean twin cmp/judge).
Chromium result: sweep off = 215 fewer raster tasks (1207 > 992 in the finish window), 792 fewer PaintImage (4 per frame to the end of the
run), Paint +1 per frame (counter artifact, Lean verdict reads `more`); glint off = 38 fewer raster, 9 fewer recalc, all before the end +20;
entries off = 5 of 6 approach layouts gone (252 of 69851 layout objects), nothing after the end; marquee = no effect.
open: read the 5 WebKit runs (`gh run download <id> -p 'webkit-sim-r*'`, then `node packages/measure-webkit/src/offscreen-webkit-cli.mjs
--arm base=<dirs> --arm name=<dirs>`), write research/notes/2026/10-2x-platform-attribution.md and ledger notes (+ apps/runner ledger-merge
test), check.sh, tests, merge main, lake build, plan lint, review ready, dry land. If WebKit is still queued: report waiting.
conventions: waiters die with the session; read runs with gh run view/list. Scratch in scratchpad/pat/.
