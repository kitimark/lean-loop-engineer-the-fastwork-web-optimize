# checkmap-preset-inputs handoff

State: branch worktree-wf_e007c264-660-5 (commit named in the report). Lean build green; `node scripts/test-checkmap.mjs` all passed (no skips).

Done
- `presetInputKey` (lean/Fw/Ops/CheckMap.lean) has 7 branches: + `lean/Fw/Preset/V2Proved.lean`, `lean/Fw/Gate/Trajectory.lean`
  (the whole import closure of Fw.Preset.Gen; test (4) walks the imports and asks fwcore, so a new import fails the test).
- `planStaged paths deleted`: the plan whose preset check also takes the staged deletions that are inputs (a deleted file gets no other check).
  Theorems: `presetInput_planned` (staged add/change of an input -> the plan has a presetCheck command over it),
  `presetInput_deleted_planned` (deletion), `planStaged_not_input` (other deletions change nothing), `presetInput_v2proved`,
  `presetInput_trajectory`; `presetInput_not` got a look-alike.
- Wire: `ops.checkMap` takes optional `deleted`. scripts/checkmap.mjs `--staged` sends `git diff --cached --diff-filter=D`.
- Golden: checkmap.jsonl 19 cases (2 new for deletions, inputs case extended). Regenerate: `cd lean && lake env lean --run scripts/CheckMapGolden.lean`.
- Tests: deleting the ledger, a golden file, a part.json or the site preset each runs the check; deleting a non-input does not.

Round 2
- `--staged` lists with `--no-renames` (rename = D old + A new); staged paths missing from the working tree go to `deleted` (index judged). Tests: rename of ledger and of a golden file, staged ledger change then `rm`.
- Theorem `presetInput_planStaged` (input in paths + any deleted list -> presetCheck command containing it).
- Timing, real hook mode `checkmap.mjs --staged` with the ledger staged, warm, 2 runs each: main's script 1.26 s, 1.75 s; this branch 1.14 s, 2.31 s (noise dominates; the preset check is the cost, one extra git diff is a few ms).

Limits: non-json modes read the working tree; a staged Gen-side Lean module triggers the check but the built (working tree) code runs.
Writes outside the task list: none.
Read first: CheckMap.lean `presetInputKey`, `planStaged`; scripts/test-checkmap.mjs sections 3-4.
