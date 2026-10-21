# traj-dispatch-push-lane handoff (round 2)

Unit: the verdict/diagnostic mark rule (Lean `Fw.Gate.Trajectory.Dispatch`) gates `fw run --trajectory`, the trajectory push line
`[trajectory ... diagnostic]` and the workflow `widths` input (boolean `diagnostic`). Round 2: the rule binds the trajectory lane only.

## State
- `lean/Fw/Gate/Trajectory/Dispatch.lean`: `dispatch` refuses a repeated width; `dispatch_accepted_iff` restated with `Nodup`; `Why.text` shared.
- `lean/Fw/Ci/Trigger.lean` (pushProbe lives here, not Trajectory.lean): `ProbeLane` (trajectory | smoothness | frames), `effLane wf m` (trajectory +
  `[frames:` = frames), `pushProbe wf lane m`, `build lane` with `ProbeIn.widthsOk` (mark rule only when `lane.marked`), the word `diagnostic` only where `lane.word`.
- Smoothness = the frozen pre-task reader (`addTokPre`..`parseLinePre`): `parseLine_smoothness`, `push_smoothness_pre`, `push_smoothness_widths`.
  Frames: `push_frames_exempt`, `marked_iff`. Trajectory: `push_verdict_all_widths`, `push_diagnostic_widths` (need `effLane wf m = .trajectory`).
- Goldens (`golden/ci/triggers.jsonl`, `lake exe fwcore fwtest --write-ci-trigger-golden`): `probe` rows carry `wf`, every message in all 3 lanes.
- `.github/scripts/trajectory-line.mjs`: `LANE=trajectory|smoothness|frames` (default trajectory; both workflows set it); `pushProbeIn(wf, lane, msg)` (`pushProbe(lane, msg)`/`parseLine(msg)` stay the trajectory lane, so `scripts/ci-push.mjs` is untouched); test parses the
  line documented in `docs/team/tools/trajectory-frames.md` and the smoothness 390,1280 line.
- `trajectory-probe.yml`: input `diagnostic`, `DIAGNOSTIC`/`LANE` env in "Read the inputs" (the first step that reads the inputs, before the build).
- Runner: `run-pick.ts` Nodup twin; `run.ts` sends `-f diagnostic=true` only when the ref's workflow declares the input.
- Preamble example (`.claude/workflows/build-review.js:17`) and the Trigger.lean module doc carry `diagnostic` plus "a widths subset needs the bare word diagnostic".

## Verified
`sh lean/scripts/check.sh` green; runner `pnpm test` (1911); `node --test .github/scripts/*.test.mjs scripts/*.test.mjs` (278) green.
CI run 39606077971 (round 1, trajectory push without the word) failed in the site job as designed; the accept path is a follow-up (node spawn tests cover it).

## Outside the graph writes
`Trigger.lean`, `Store/Layout.lean`, `golden/ci/triggers.jsonl`, `run.ts`, `run-pick.ts`, `run.test.ts`, `run-dispatch.test.ts`, `scripts/ci-push.test.mjs`.

## Accepted limits
Old stored runs unchanged; `fw run` on a ref older than the input dispatches without the mark; dispatch-input paths proved by spawn tests; GitHub only.
TS stand-ins: `docs/team/tools/ts-stand-ins.md`.
