branch: worktree-wf_df87b280-602-1 (CI branch ci/morph-real-wheel)
worktree: .claude/worktrees/wf_df87b280-602-1 (in the repo checkout)
measured sha: 9cdcefc41 (pushed to ci/morph-real-wheel; later commits only add notes and this file)
CI runs (smoothness.yml, jobs webkit-mac 1..3, macos-26, head commit tags [ci:smoothness] [webkit-cadence] [morph-wheel]):
- 39971123168 smoothness: success; webkit-mac 1..3 each 24 of 24 runs accepted by the phase rule, 0 refused (MEASURED)
- Result: trusted wheel reaches the page (isTrusted 72 of 72), morph 0 -> 1 -> 0; trusted vs synthetic per-frame counts overlap in 41 of 42 cells (only idle orig FireAnimationFrame, trusted higher; the trusted idle phase is ~3 frames longer)

Verified (MEASURED locally, not a result): one debug run on this Mac, 1 rep, 4 runs accepted by the phase rule; the trusted wheel
arrives with isTrusted true, the site calls preventDefault, `--morph` goes 0 -> 1 -> 0, the trusted push lands 1 to 3 frames after the schedule.
Verified (Lean): `sh lean/scripts/check.sh` green at 9cdcefc41 (phase rule + golden, init-cost lint needs the golden as a function).

What it is
- lean/Fw/Measure/WebKitLagPhase.lean: phase of a frame from the push times, refusal rule (idle >= 5, open >= 30, close >= 30), golden in webkit-lag.jsonl.
- packages/measure-webkit/src/lag/phase.mjs: TS twin, checked in test/lag-phase.test.mjs; probe.mjs marks wk:down / wk:up; report.mjs takes phases per run.
- src/lag/macmorph.mjs + macreport.mjs + mac-cli.mjs: Playwright WebKit mac leg, trusted (page.mouse.wheel) vs synthetic on the same page, per arm.
- .github/workflows/smoothness.yml: `[morph-wheel]` runs mac-cli in webkit-mac and skips webkit-sim (outside the graph writes).

Open
- Simulator leg not done: sim-touch-reliable (worktree-wf_b60a7b2e) is not on main. Follow-up: drive the same morph with the PushServer touch.
- Results table and note: research/notes/2026/10-2x-morph-real-wheel.md (done, from artifacts smoothness-webkit-mac-1..3).
- Writes outside the graph: packages/contracts/golden/measure/webkit-lag.jsonl (Lean generated), .github/workflows/smoothness.yml.
- TS stand-ins: macmorph.mjs / macreport.mjs aggregation (means, table layout); the verdict and classes call the Lean-checked reduce.mjs functions.

Read first: this file, the note, lean/Fw/Measure/WebKitLagPhase.lean, packages/measure-webkit/src/lag/macmorph.mjs.
Conventions: push only ci/morph-real-wheel (branch -f, plain push); poll CI with fw ci wait; heavy checks through `pnpm -s fw slot run`.
