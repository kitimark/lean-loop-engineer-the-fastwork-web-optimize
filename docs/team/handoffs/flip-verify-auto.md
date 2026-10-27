branch: worktree-wf_563f1ba9-714-1 (CI branch ci/flip-verify-auto)
worktree: .claude/worktrees/wf_563f1ba9-714-1
last commit: see `git log -1` (WIP commits carry "flip-verify-auto")
CI runs: push 1 40525667335 failure; push 2 40530697810 failure; push 3 40537879823 (e56ef0507): Chromium all green (verify 12/12 x3 reads, 2 repeats, 6 of 6 mutations caught), WebKit verify 11/12 on A5 (360x640 first open push untaken, guard-late on a 1.5 fps runner), repeats green, 6 of 6 mutations caught, timed cell m=0 12/12 on both engines. Push 4 40544410328 (f08b8c1a0, A5 judges pushes the guard had a chance for, Lean traceOk) in progress; wait with `pnpm -s fw ci wait 40544410328`. Push 4 is the last.

## State
- Lean: lean/Fw/Parts/MorphGeomVerify.lean (quiet leave A4, time kept A3a, take trace A5, Mutation list; one theorem per branch).
  Golden lines verify, verifyQuiet, verifyKept, verifyTrace come from MorphGeomTimedGen.lean into packages/contracts/golden/morph-geom-timed.jsonl.
- TS: packages/gate-breakpoints/src/flip-verify.mjs. Entry point for other lanes (phone, Safari macOS):
  `installFlipProbe` (page side, init script), `driveFlipProbe(page)`, `analyseFlipProbe(raw, {baseWidth, verify})`.
  CLI: `node src/cli.mjs verify --engine ... [--mutation A4|A3a|A5 --expect-fail]`; `flip ... [--mutation A1|A3b|A3c --expect-fail] [--report-only]`.
- TS stand-ins (replayed against the golden in test/flip-verify.test.mjs): judgeQuiet, judgeKept, judgeTrace, colour distance for A4's visible-background rule.
- Workflow: .github/workflows/breakpoint-gate.yml job flip-cell: graded cell, reported geom-timed cell, graded verify, graded mutation runs.

## Verified
- Local debug runs (not results): Chromium and WebKit, pass on main, each of A4, A3a, A5 and A1, A3b, A3c caught when reverted.
- Unit tests: 13 pass (packages/gate-breakpoints).

## Findings to carry
- A4 literal wording ("no transition runs") is false even on the base page: the base nav ends a close with a sub-pixel width and sub-percent background transition of its own.
  The reading counts a transition only while it is visibly off its end value (width beyond 1 px of base, colour beyond 0.02 in sRGB/alpha).
- A3a: a re-parented animation stalls one frame (currentTime held); the bound is the length of the frame it happens in (max of 16.67 ms and that frame).
- A5 mutation: classList.contains('is-on-dark') reads light always (closes do not consult the guard once the flip is entered).

## Open
- CI results, 3 runs, note research/notes/2026/10-2x-flip-verify-auto.md, ledger notes, gap 5 cause (WebKit m=0 failures; diagnostics `live`/`recheck` in the timed cell).
- Do not edit apps/site/src/parts/morph.columns/** (phone-cols-probe).
