branch: worktree-wf_a3ba2392-7af-1
worktree: .claude/worktrees/wf_a3ba2392-7af-1
last commit: see `git log -1` (round 2 commit 86a2cd6d, then handoff)
CI runs: none (runner code and tests only)

State: round 2 built. Runner test, ci-paths, slot-self tests and the dry land: see the report (verdict line in `dry`).

Round 2 changes
- Verb lists exported by the dispatching modules: POLISH_VERBS (polish.ts), ORACLE_SUBS incl. score, arm-input (oracle.ts), CONSOLE_SUBS,
  INCIDENTS_SUBS, PREVIEW_SUBS, CARD_VERBS, STEP_VERBS/TASK_VERBS (lib.ts), STEP_THREAD_VERBS (step-threads.ts), REVIEW_VERBS (review.ts),
  READY_VERBS (review-ready.ts), PLAN_SUBS (plan.ts), CI_SUBS (ci.ts), SLOT_SUBS (slot-span.ts). polish, oracle, console, incidents, preview,
  card, step, task, slot use their list in their own guard; plan and ci dispatch in fw-main.ts (list is tested against the usage text).
- fw-groups.ts SUBCOMMANDS is built from those imports only; spanStep names a sub only if it is in the list.
- Tests (span-names.test.ts): usage-text parse, every key non-empty and imported (no string literals), oracle holds score/arm-input.
  Mutation checks done: removing `polish:` -> 3 tests fail; dropping score/arm-input from ORACLE_SUBS -> 1 fails.
- slot-span.ts: `slot run <kind> dry` (wrapped argv has --dry), `... cached` on a replay (slotStepEnd, flag on globalThis; timing.ts begin's
  end(extra.step) overrides the step).
- run.ts runCli opens the run span before parseRunArgs (new optional `begin` arg for tests).
Open: follow-up 5 (check real timings.jsonl for `run wait`, `slot run test`, `slot run land dry`, `dry total`) is the lead's. Plan/ci lists are not used by a module-own guard (dispatch is the if-chain in fw-main.ts).
Writes outside the graph list: card.ts, ci.ts, console.ts, incidents.ts, lib.ts, oracle.ts, plan.ts, polish.ts, preview.ts, review.ts, review-ready.ts, step-threads.ts, slot.ts, timing.ts, fw.ts, fw-groups.ts, run-phases.ts, slot-span.ts, scripts/slot-self.mjs, tests.
Read first: apps/runner/src/fw-groups.ts, apps/runner/test/span-names.test.ts.

Round 3 (merged main r231): dry land VERDICT dry run-span-split (exit 0). Mutation evidence: removing `polish:` fails span-names.test.ts:22,32,48; dropping score/arm-input fails span-names.test.ts:41.
Startup cost measured (docs/team/tools/timings.md): +0.01 s wall, RSS unchanged; slot path import closure excludes fw-groups.ts. No fix needed.
