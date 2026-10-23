branch: worktree-wf_41867f2b-b5a-1 (CI branch ci/morph-real-wheel-followups)
worktree: .claude/worktrees/wf_41867f2b-b5a-1 (in the repo checkout)
last commit: bba5ad159 (pushed to ci/morph-real-wheel-followups, head tags [ci:smoothness] [webkit-cadence] [morph-wheel])
CI runs (smoothness.yml, jobs webkit-mac 1..3, macos-26):
- 39989441570 smoothness: running (checkpoint after the first push)

Verified so far
- Lean: WebKitLagPhase.lean (geometryIndex, acceptScrollIn, refusals noScroll / noOpen) and WebKitLag.lean (jobVerdicts, tally, pooling_hides) compile; golden webkit-lag.jsonl regenerated, 110 lines, `--check` green.
- `pnpm -s fw slot run --kind test --cache -- pnpm --filter @fw/measure-webkit test` green (468 tests) at 257e366cd.
- One local debug run (1 rep, not a result): the trusted scroll-in drive scrolled 4802 -> 4922 -> 5042 -> 5102 with three unprevented wheels, then a prevented push at the end, `--morph` 0 -> 1 -> 0.

Done in code
- (1) report.mjs analyzeMorphItems indexes geometry by `geometryIndex(r.ph[phase][0], i, n)`; test/lag-morph-followups.test.mjs uses a run off the 10/60/60 schedule.
- (2) macmorph.mjs drive `scrollin`: starts 300 px above the end, trusted `page.mouse.wheel` until within 8 px, then the push; accepted only when scrolled and `--morph` >= 0.9 (Lean acceptScrollIn).
- (4) macreport.mjs decides each job from its own runs (Lean jobVerdicts, golden kind jobVerdicts); no pooled verdict.
- (5) probe.mjs header: the `wk:down` / macmorph sentence cut.
- (3) Simulator leg: followUp, waits for sim-touch-reliable.

Open
- Wait for run 39989441570, download artifacts smoothness-webkit-mac-1..3, run `mac-cli.mjs report --files a,b,c`, write the results into research/notes/2026/10-2x-morph-real-wheel.md.
- Then: merge main, `sh lean/scripts/check.sh` via slot, ci-paths test, runner land-inputs test, plan lint, dry land, `fw review ready`.
- No change to .github/workflows/smoothness.yml was needed.

Read first: this file, research/notes/2026/10-2x-morph-real-wheel.md, lean/Fw/Measure/WebKitLagPhase.lean, packages/measure-webkit/src/lag/macmorph.mjs, macreport.mjs.
