# traj-dispatch-scope handoff

Unit: one dispatch. A trajectory dispatch is marked verdict (default; stored, judged) or diagnostic (`--diagnostic`).
Verdict walks all four widths; diagnostic walks any nonempty subset of {390,640,641,1280}; legs are the existing
`legs`/`legTable` of the chosen widths.

## State
- Lean: `lean/Fw/Gate/Trajectory/Dispatch.lean` (imported in `lean/Fw.lean`). `dispatch`, `dispatchIn`, `dispatchLegs`.
  Theorems: `dispatch_accepted_iff`, `verdict_all_widths`, `verdict_in_all_widths`, `verdict_outcome_judged` (links to
  `outcome`), `diagnostic_nonempty`, `diagnostic_unjudged`, `one_leg_iff` (macOS legs), refusal branches
  `dispatch_empty`, `dispatch_bad`, `dispatch_verdict_scoped`, `dispatch_diagnostic`, `dispatch_verdict_all`,
  `dispatchIn_default`, `legs_length_le`, `dispatch_legs_mem`.
- Golden: `packages/contracts/golden/gate/trajectory-dispatch.jsonl` from `lean/scripts/TrajectoryDispatchGolden.lean`
  (`--check` wired in `lean/scripts/check.sh`).
- TS: `apps/runner/src/run-pick.ts` holds the twin (`pickWidths`, `dispatch`, `dispatchIn`, `legsOf`, `enginesOf`,
  `refusalText`; a TS stand-in checked against the golden). `apps/runner/src/run.ts`: `--diagnostic` flag; `runGate`
  refuses a scoped verdict dispatch (exit 2, message names `--diagnostic`) before any fwcore call, also under `--dry`.
- Tests: `apps/runner/test/run-dispatch.test.ts` (new); `run.test.ts` got `--diagnostic` on its scoped-width cases and
  the width-800 case now matches the new refusal text.

## Verified
See the report for the check.sh exit code, runner test result and the `fw land --dry` VERDICT line.

## Not done / accepted limits
- No CI dispatch, no measured saving. Saving bound is INFERRED from the macos-minutes check: up to ~115 job-min/day on
  diagnostic series, 0 on verdict runs. Existing stored runs are unchanged.
- The push-message lane (`[trajectory ... widths=...]`, Lean `pushProbe`, `.github/scripts/trajectory-line.mjs`) and the
  workflow `widths` input still accept a subset; only `fw run --trajectory` enforces the mark. Follow-up if wanted.
- `docs/team/tools/trajectory-probe.md` line 15 does not yet mention `--diagnostic` (outside this task's writes).
- Leg-count TS stand-in: the engine table `LEG_TABLE` is checked through golden `legs`, `enginesOf` through `engines` lines.

## Read first
`lean/Fw/Gate/Trajectory/Dispatch.lean`, then `apps/runner/test/run-dispatch.test.ts`.
