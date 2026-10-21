# traj-dispatch-push-lane handoff

Unit: the verdict/diagnostic mark rule (Lean `Fw.Gate.Trajectory.Dispatch`) now gates all three entry points: `fw run --trajectory`
(already), the push line `[trajectory ... diagnostic]`, and the workflow `widths` input with a boolean `diagnostic` input.

## State
- Lean `Dispatch.lean`: `dispatch` refuses a repeated width (`ws.Nodup`); `dispatch_accepted_iff` restated with `Nodup`; new
  `dispatch_repeat`, `accepted_nodup`, `Why.text` (shared refusal words); `dispatch_bad`/`dispatch_verdict_scoped`/`dispatch_diagnostic` adjusted.
- Lean `Ci/Trigger.lean` (where `pushProbe` lives, not Trajectory.lean): `ProbeIn.diagnostic`, bare word `diagnostic` in `addTok`, `build` asks
  `ProbeIn.walksOk`/`walkWhy` (= `dispatchIn`). Theorems `walk_verdict_all`, `walk_diagnostic_some`, `parseLine_walks`,
  `push_verdict_all_widths` (a push without the word walks all four), `push_diagnostic_widths`; `example`s for each refusal text.
  `Lane.inputs .trajectory` (Store/Layout.lean) gained `diagnostic` (LaneInputs check), trajectory-probe row reads `trajectory-dispatch.jsonl`.
- Goldens regenerated from Lean: `golden/ci/triggers.jsonl` (`lake test -- --write-ci-trigger-golden`), `golden/gate/trajectory-dispatch.jsonl`.
- JS `.github/scripts/trajectory-line.mjs`: `dispatch`, `dispatchIn`, `whyText`, `walkRefusal`; push parse and the dispatch path (env `DIAGNOSTIC`, `WIDTHS`)
  both refuse a subset with the Dispatch text. Test checks `dispatchIn`/`dispatch` against `trajectory-dispatch.jsonl` and `pushProbe` against `triggers.jsonl`.
- Workflow `trajectory-probe.yml`: input `diagnostic` (boolean), `DIAGNOSTIC` env in step `Read the inputs` (the first step that reads the inputs, before the build),
  `diagnostic` in the step name and `inputs.json`.
- Round 2: Lean `Trigger.lean` `ProbeLane` (trajectory | smoothness | frames): `pushProbe wf lane m` reads the line in `effLane wf m` (trajectory + `[frames:` = frames);
  `build lane` applies `ProbeIn.widthsOk` (mark rule only when `lane.marked`, i.e. trajectory); `diagnostic` word only where `lane.word`. Smoothness = frozen pre-task reader
  (`addTokPre`..`parseLinePre`), theorems `parseLine_smoothness`, `push_smoothness_pre`, `push_smoothness_widths`; frames: `push_frames_exempt`, `effLane_*`, `marked_iff`.
  Goldens `probe` rows now carry `wf` (3 lanes x 2). `trajectory-line.mjs` takes `LANE=trajectory|smoothness|frames` (default trajectory); both workflows set it; `scripts/ci-push.mjs` passes 'trajectory'.
  Examples in `build-review.js` preamble and the Trigger.lean module doc carry `diagnostic` + the clause.
- Runner: `run-pick.ts` `dispatch` has the Nodup twin; `run.ts` sends `-f diagnostic=true` for `--diagnostic` only when the ref's workflow declares the
  input (`declaresInput`; an older ref is sent none, logged). `scripts/ci-push.test.mjs` line got the word + a scoped-refusal case.
- Docs: `trajectory-probe.md` usage line (`--diagnostic` + one sentence), push-line key, step name; new `docs/team/tools/ts-stand-ins.md` (register).

## Verified
`sh lean/scripts/check.sh` green; runner `pnpm test` green; `node --test` on ci-paths, changed-inputs, ci-push, circleci, lake-slot, trajectory-line green.

## Outside the graph writes (list for review)
`lean/Fw/Ci/Trigger.lean`, `lean/Fw/Store/Layout.lean`, `packages/contracts/golden/ci/triggers.jsonl`, `apps/runner/src/run.ts`, `run-pick.ts`,
`apps/runner/test/run.test.ts`, `run-dispatch.test.ts`, `scripts/ci-push.test.mjs`, `scripts/ci-push.mjs` (round 2: lane argument): the task text names `Trajectory.lean pushProbe`, but it is in Trigger.lean.

## Accepted limits
Old stored runs unchanged; `fw run` on a ref older than the input dispatches without the mark (the old workflow has no rule); the workflow-input path is
proved by the node spawn test, not by a dispatch (agents cannot dispatch); one CI push run proves the push-line step (see report).

## CI proof (one run, GitHub)
Run 39606077971 (push, `ci/traj-dispatch-push-lane`, line `[trajectory widths=390,641 engines=chromium]` without the word): job `site`, step
"Read the inputs" ran `trajectory-line.test.mjs` (9 pass, 0 fail) then failed with `trajectory-line: refused: widths 390,641 is a subset ... add the word diagnostic ...`
before any build. The accept path and the dispatch input were not run on CI (a diagnostic run is a full probe; dispatch is lead-only): node spawn tests cover both.
