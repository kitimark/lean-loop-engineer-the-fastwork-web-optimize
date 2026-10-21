# earn-close-settle-rule (final design round of the earn close rule)

State: branch `earn-close-settle-rule`, last commit holds this file. `sh lean/scripts/check.sh` green.

Done:
- Lean `lean/Fw/Gate/Trajectory.lean` section `CloseStart`: close@0 = anchor at the first trigger + range
  `[s - tol, full + tol]` (`startCheck`); close-hold = `byM` and `settleAnd` over `settleCheck` (reading at or after
  `settleAt` = dur + delay + 80 ms past the last trigger lies within `tol` of `fullOf`). The round-2 chain rule
  (`chainCost`, `linkExcess`, `hull`, `target`, `settledOf`) is gone.
- Theorems: `byMSettle` (never more lenient than `byM`), `byMSettle_keep`, `startCheck_pass_iff`,
  `settleCheck_pass_iff`, every branch, mutations `byMStart_stale/_reversed/_collapsed/_target/_duration`, limits
  `byMStart_drift/_curve`, smallest refused changes `settle_{opacity,wide,phone}_{duration,delay}`.
- Golden `packages/contracts/golden/gate/trajectory.jsonl` (280 lines, ops `startCheck`, `settleCheck`, `byMStart`,
  `curve` with `full` and `bez`); TS twin `packages/gate-breakpoints/src/trajectory/reduce.mjs` (integers only).
- Doc `docs/team/tools/trajectory-probe.md` section "Earn close start": rule, proofs, limits (i)-(vi), wrong-cut
  limit, O/O numbers, re-reduce table.

Verified: gate-breakpoints `trajectory.test.mjs` 309/309; the package's other failures are missing `node_modules` in a
fresh worktree (`playwright-core`, `@fw/visual-diff`). `scripts/ci-paths.test.mjs` 54/54, runner `land-inputs` 55/55.
Re-reduce of runs 39466179818, 39472217441, 39508414669, 39508421419 against main 74fccd34: 9 earn close@0 units on
macOS WebKit go to pass, no close-hold unit changes (same 9 as round 2).

Open:
- The advice's "6140 close@0 samples" is half of 12280 (both arms of macOS WebKit); per arm the count is 6212 and 6068.
- The wrong-cut limit (darkCut 0.25) is INFERRED from a float simulation, not a Lean theorem.

Read first: the doc section, then `CloseStart` from `def startCheck` to `byMStart_curve`.
