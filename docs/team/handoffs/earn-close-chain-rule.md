# Handoff: earn-close-chain-rule

State: branch `worktree-wf_27d7c8bb-7e0-1` on main 0e426af3. Lean section `CloseStart` of
`lean/Fw/Gate/Trajectory.lean`, TS twin in `packages/gate-breakpoints/src/trajectory/reduce.mjs`, golden
`packages/contracts/golden/gate/trajectory.jsonl` (273 lines), doc `docs/team/tools/trajectory-probe.md` section
"Earn close start".

Rule: close@0 bucket 0 of earn opacity and max-width. `chainCost` = |first rewrite trigger reading - original first
trigger reading| + sum over chain links of `linkExcess` (reading outside `hull` of the curve from the previous chain
point towards both morph targets, tau +- 80 ms). Pass when the cost is at most `tol`.

Verified:
- `sh lean/scripts/check.sh` green (axiom check 0 failing); `lake env lean Fw/Gate/Trajectory.lean` clean.
- Theorems: `startCheck_budget` (cumulative bound), `judgeStart_sound`, `linkExcess_on`, `hull_mem`, every
  `linkExcess_*`, `linksExcess_*`, `chainCost_*` branch; mutations `byMStart_stale`, `_reversed`, `_linear`,
  `_duration`, drift `drift_links`, `drift_second`, `byMStart_drift`.
- Golden ops `hull` and `chainCost` added; gate-breakpoints tests 524/524; ci-paths 52/52; runner land-inputs 55/55.
- Re-reduce of runs 39466179818, 39472217441, 39508414669, 39508421419 (macOS new 172, 128, 253, 44; Chromium 0, 0, 84,
  0; Linux WebKit 0): all 64 earn close@0 cells (macOS, Chromium) pass/pass/ok; 9 cells change against main,
  all earn close@0 on macOS.

Open:
- Admission of the scoped arm: task close-start-identity-rule.
- nav.background-color close@0 failures are outside this rule.
- Ledger note for the lead: hero.exit:scoped inline `next` (from round 2) still open.

Read first: the doc section, then `chainCost` and `startCheck_budget` in Trajectory.lean.
Scratch tools (not committed): rered.mjs and celldiff.mjs re-reduce artifacts with several reducer copies.
