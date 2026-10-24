# build-review workflow

`.claude/workflows/build-review.js`: one task per run. Stages: Build, Review (Lean gate `fw review ready`, then the reviewer), Polish.
Args: `{ task: { id, role, prompt, lean?, worktree?, unit?, limits?, findings?, report? }, voice? }`.

## Lead resume path
`task.report` (path of a builder report JSON) together with `task.worktree` skips the build stage. One `runner` agent
(label `resume-dry:<id>`) reads the report, runs `pnpm -s fw slot run --kind land --cache -- pnpm -s fw land <branch> --task <id> --dry`
in the worktree (no `--allow`) and returns the last `VERDICT dry` line verbatim. The script puts that line in the report's `dry`
field; the gate and review then run as usual. Use it when only the dry line was refused (for example the lead added the
missing writes to the graph task). The gate rule is unchanged: `dryOk` takes the exact line `VERDICT dry <id>`.
`report` without `worktree` is ignored and the build runs.
`report` may be the report object itself instead of a path; the script then uses it as is and the runner only runs the dry
land (a runner echoing a 14-item report returned `items: []`, wf_8aa275ef). The resume path never builds: a round that must
change code (review findings) uses `worktree` with `findings`, not `report` (wf_362ba514 re-reviewed an unchanged commit).

## No-result record
A builder that ends without StructuredOutput makes `agent({schema})` throw. The script catches it and returns
`[{ task, worktree, branch, handoff, state: 'no-result' }]`, the same record as a null result; no later stage runs.
Restart from the handoff file (checkpoint rule).

## Builder preamble
Report `dry` exactly as the last VERDICT line the dry land printed without `--allow`; list files outside the task's writes in `open`.

Tests: `node --test scripts/build-review.test.mjs` (stub agents for each part).
