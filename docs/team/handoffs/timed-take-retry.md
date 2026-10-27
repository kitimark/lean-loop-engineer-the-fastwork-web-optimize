branch: worktree-wf_008d44e4-abb-1 (CI copy ci/timed-take-retry)
worktree: .claude/worktrees/wf_008d44e4-abb-1
last commit: 1781540dc (code), handoff commit follows
CI runs (round 2, dispatched by builder from ci/timed-take-retry at 8e667f5ab): gate run 40503716001 success; chromium-counts swipe-touch-v1 x3 base 40503734787 and flag 40503729708 both success; windows read: all noGain (results/timed-take-retry/chromium-windows.md). Round 2 done, awaiting review.
CI runs (round 1): push of ci/timed-take-retry: 'lean' running (check on push); every other push workflow skipped by its guard. The flagged gate
  and counts are not started (they need dispatch inputs).
verified: Lean check.sh green; @fw/site test 8449 pass; ci-paths 56 pass; runner land-inputs 73 pass; ledger tests pass; local Chromium
  push log (results/timed-take-retry/): every push takes the timed path at 390, 430, 1280.
open: dispatch (lead), after the push of ci/timed-take-retry is green:
  breakpoint gate (see docs/team/tools/fw-run.md for the gate form): --fw morph.geom:on,morph.tween:geom-timed --ref ci/timed-take-retry
  pnpm -s fw run --engines chromium --profile swipe-touch-v1 --runs 3 --target rewrite --fw morph.geom:on,morph.tween:geom-timed --ref ci/timed-take-retry
  then base vs flag x3 with Lean OffscreenWindows reader (packages/measure-chromium/src/offscreen-windows-cli.mjs).
  Class L look stays the user's review. Why the hit test reads light at 390 in Chromium but dark in WebKit stays open.

Read first: research/notes/2026/10-2x-timed-take-retry.md, then lean/Fw/Parts/MorphGeomTimed.lean (end of file, "Take rule with retry").
Conventions: take rule is direction-free (takeOk); frame 0 = the push, frame k = k-th tick; golden rows fn=take in
packages/contracts/golden/morph-geom-timed.jsonl; TweenEnv.trace is an opt-in probe hook (window.__fwTakeTrace), geom-timed only.
Probe: REPO=<worktree> node results/timed-take-retry/pushlog.mjs (needs apps/site build --engine aot, desktop Chrome).
TS stand-ins: none for the rule (replayed against the golden); the 17 ms tick grid in the golden is a model of rAF.
