# Handoff: alert-steps-plain

State: branch worktree-wf_4b8d04ef-923-1. Lean, wire, contracts, drain and console-web are done; see the last commit.

What changed
- Lean decides the audience (`Fw.Console.Alert.audienceOf`, `legacyAudience`) and writes the plain text (`Alert.plain`,
  `Fw.Ops.Obs.spoolPlain`). `Step` has `audience` and `body`; `step.done` has an optional `note`.
- Auto-close: `Fw.Ops.Obs.resolveSpool` via `ops.obs` `resolve`; the drain's `resolveSweep` submits `step.done` (actor script).
  Reducer: a script `step.done` on a waiting step is accepted only for audience lead (`script_done_waiting_is_lead`).
- Console web: "Your steps" counts only audience user; lead steps sit in a read-only details block; body rendered per line.
- Docs: docs/team/tools/console.md (last section), fw-watch.md (last section).

Verified (MEASURED here): `sh lean/scripts/check.sh` green; console-api 519 tests, console-web 19, contracts 7, runner 1437,
`node --test scripts/ci-paths.test.mjs` 41, all with typecheck. The old step `alert-spool-1792389046068` closes in
`apps/console-api/test/spool.test.ts` (title only, body "", window of 0 lines).

Open items
- No main-CI alert poster exists in the repo; the task text assumed one. Nothing was added for it.
- Key parsing from Details or an old title is checked by #guards only, not by a round-trip theorem.
- A Details list cut with "..." never closes by itself. A window with no line closes only unknown-field keys.
- Agent alerts for the user keep the evidence-based `step.cancel` close.
- After landing: restart console-api so the live drain runs the new sweep; the stale spool step then closes on the next sweep.

Read first: lean/Fw/Ops/Obs.lean (resolve section), lean/Fw/Console/Alert.lean (plain), apps/console-api/src/spool/drain.ts.
Never hand-edit goldens: lean/golden/console-apply.jsonl was edited by script (state fields + 3 new cases from fwcore) and copied to packages/contracts/golden.
