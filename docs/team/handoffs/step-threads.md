# Handoff: step-threads (console-builder)

State: branch `worktree-wf_46707736-00d-1`; Lean, contracts, console-api, runner and console-web are built and tested (see the report).
Read first: `docs/team/tools/console-steps.md`, then `lean/Fw/Console/Steps.lean`.

## What exists
- Lean: `Fw.Console.Steps` (topic refusals, `define`/`topics`, grouping `view`/`order` with cover and sorted-permutation proofs,
  `questionAlerts`/`reviewAlerts`, post-opens and reply-closes theorems). `Step.topic`, `Body.stepPost ... topic`,
  `Body.stepTopic`, `EvType.stepTopic` ("step.topic", lead and script) in `Fw/Console.lean`; wire in `Fw/Wire.lean`, `Fw/Serve.lean`.
- Op `console.stepTopics` (`lean/Fw/Wire/Steps.lean`), golden `packages/contracts/golden/console/steps-topics.jsonl` (from `Fw/Ops/Golden.lean`).
- Alert `step.question` (`Fw/Obs/Health.lean`, rank 15; later ranks shifted by 1), goldens `golden/obs/health.jsonl`.
- Threads reuse `review.feedback`/`.reply`; the subject is `step:<id>` or `topic:<id>` in `flag`. `review.feedback` alerts exclude those subjects.
- `stepJson` and the `step.post` event JSON write `topic` only when set (keeps the old goldens byte-equal).
- console-api `src/steps/threads.ts` (`GET /api/steps/topics`, `POST /api/steps/:kind/:id/question`), runner `src/step-threads.ts`,
  web `StepThreads.tsx` plus `ReviewFeedback` `words` prop.

## Open / follow-ups
- Phone notifications; threads on other card kinds.
- No topics are seeded: the lead posts them (`fw step topic --id --title --summary`, then `fw step post --topic`).
- A subject's existence is not validated (documented limit).
- Files outside the task's graph writes that this task touched: `lean/Fw/Console.lean`, `Fw/Serve.lean`, `Fw/Wire.lean`, `Fw/Wire/Console.lean`,
  `Fw/Wire/Steps.lean`, `Fw/Obs/Health.lean`, `Fw/Obs/Golden.lean`, `Fw/Ops/Golden.lean`, `Fw.lean`, `lean/FwTest/Mutants/Console.lean`,
  `lean/golden/*` (none changed in the end except the obs golden), `packages/contracts/src/index.ts`, `schema/*`, `fixtures`, `test`,
  `apps/console-web/test/step-threads.test.tsx`.

## Conventions
Never hand-edit generated files: `lake env lean --run scripts/OpsGolden.lean` / `ObsGolden.lean` / `BoardGolden.lean`, `pnpm gen` in `packages/contracts`.
