# review-feedback handoff (console-builder)

Branch `worktree-wf_21068a14-405-1`. Read `docs/team/tools/review-feedback.md` first (who decides what).

## State
- Done and tested: Lean thread (`lean/Fw/Console/ReviewFeedback.lean`, laws in `ReviewFeedbackLaws.lean`), reducer events
  `review.feedback` (user) and `review.feedback.reply` (lead) in `lean/Fw/Console.lean` and `Serve.lean`, wire op
  `console.reviewFeedback` + golden, mutant guards, console-api route + test, runner `fw review reply|feedback` + test,
  web Feedback section + test, contracts commands, schemas (`pnpm gen`), fixtures.
- Alert decision proved in `lean/Fw/Obs/FeedbackAlert.lean` (pairs flag/detail; theorems: alert iff open comment, one per
  flag, count, post opens, reply closes, detail = open count + first 120 characters).

## Open
- Health glue not done: `local-mem-budget` edits `Fw/Obs/Health.lean`, `golden/obs/**`, `watch-collect.ts`, and had not landed
  when I stopped. After it lands: merge main, add `Code.reviewFeedback` (name `review.feedback`, rank after `procLong` so
  `names_sorted` holds), an `Obs.system` input of feedback events, a `sFeedback` piece mapping `FeedbackAlert.alerts`, regenerate
  `golden/obs`, read the events in `watch-collect.ts`, add a watch test (post opens, reply closes).

## Conventions
- Generated files: `lake env lean --run scripts/OpsGolden.lean` (in `lean/`), `pnpm gen` in `packages/contracts`.
- `fb` is not in `stateJson`/`stateOfJson` (like `plan`).
- Lean has no Mathlib here: no `tauto`, `by_contra`; use `Classical.byContradiction`.
