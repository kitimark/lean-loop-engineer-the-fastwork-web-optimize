# Handoff: trajectory-close-start

State: branch `worktree-wf_a71b0089-ac6-1`, final commit after 6be54a90 (see `git log`). Absorbs trajectory-settled-sample.

Verified:
- Lean `Fw.Gate.Trajectory`: `envelope`, `isCoreIn`, `judgeWith`, `judgeUnit` (envelope), `judgeOwn` (one pass), `headOf`,
  `windowPass`, `windowAt`; `bucketVerdict` uses `windowAt`. Theorems: `judgeUnit_agree`, `windowAt_old`,
  `judgeUnit_other_start`, `judgeUnit_red_two_passes`, `byM_reversed_two_passes`, `byM_settled_push_end`,
  `byM_sampled_push_end`, `byM_in_flight_push_end`, one theorem per `windowPass` branch, outside theorems over every pass,
  `bucketVerdict_self` kept. Standard axioms only.
- Golden `packages/contracts/golden/gate/trajectory.jsonl` (217 lines, `casesClose` holds the new cases, split out of
  `casesFlight` for the init-cost bound); `reduce.mjs` replays it; gate-breakpoints tests 397/397.
- `sh lean/scripts/check.sh` green; `scripts/ci-paths.test.mjs` and runner `land-inputs` green.
- Six stored runs re-reduced, before/after table and Lean outcome lines in `docs/team/tools/trajectory-probe.md`
  (section "Transition start and settled push end").

Findings:
- `hero.exit:scoped` (39466179818) still fails on mac morph: `nav.background-color` new at 390, 640, 641; the candidate
  starts the close at 226.5 against 249.3 to 252.3 in every original pass. The 1280 failures cleared.
- A/A 39472217441 mac morph went fail to `no verdict: coverage`.
- A pass with no core sample now uses the other passes' cores (stricter on some Linux WebKit close-hold@0 units).

Open: Linux WebKit morph stays unjudged (coverage); the close-start colour gap needs a flag-alone run (INFERRED timing).

Conventions: the TS twin names match Lean (`windowAt(ph, d, seg, orig, r)`); the head branch needs a settled sample.
Read first: the Limits list under "Transitions in flight" in trajectory-probe.md, then `windowPass` in Trajectory.lean.
Scratch re-reduce tools were local only (rr.mjs: v1 colour conversion via `colourFromV1`, then `reduceRaw`).
