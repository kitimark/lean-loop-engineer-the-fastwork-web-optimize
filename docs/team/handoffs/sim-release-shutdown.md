branch: worktree-wf_27491bc9-f1d-1
worktree: .claude/worktrees/wf_27491bc9-f1d-1
last commit: `git log -1` (main merged)
CI runs: none (accepted limit: local tests only)

State
- Lean `lean/Fw/Sup/SimRelease.lean`: `simOurs`, `simHandover`, `simSettle`, `simRecord`; theorems `simSettle_release_clean`
  (no handover: nothing lease-booted stays booted), `simHandover_keeps_for_live_holder`, `simSettle_preexisting_kept`,
  `simSettle_shut_booted`, `simSettle_handover`, `simRecord_inherits`. `lake build Fw.Sup.SimRelease` green.
- Golden: `simReleaseLines` in AdaptGolden.lean (ops adapt.simSettle, adapt.simHandover, adapt.simRecord), adapt.jsonl regenerated.
- slot.ts: `simReleaseShutdown` (in `tick` and `releaseToken`) shuts down only the udids `simSettle` names; `simBefore` is kept
  across a handover (`simRecord`). Tests: apps/runner/test/slot-sim-release.test.ts (fake simctl), golden replay in slot.test.ts.
- Lead adds at land: `import Fw.Sup.SimRelease` in lean/Fw.lean (after `import Fw.Sup.Adapt`); no check.sh line (the sup-adapt golden
  check imports AdaptGolden, which imports SimRelease).
Open: a lease that names its device (`--udid`) is not built (limit: attribution by booted-list diff only); a legacy
`.local/locks/sim` holder is not a handover target.
TS stand-ins: none beyond the twins checked against the golden rows.
Read first: lean/Fw/Sup/SimRelease.lean, docs/team/tools/slot.md "Simulator release".
