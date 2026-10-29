# land-push-lane handoff

- Branch: worktree-wf_830b5115-3ee-1; worktree: .claude/worktrees/wf_830b5115-3ee-1; work commit ee7757da5.
- Verified: check.sh green, runner tests 3703/3703, ci-paths and ci-push node tests 62/62, dry land `VERDICT dry land-push-lane`, review ready `review`.
- CI runs: none (accepted limit: no CI push of our own; the next real land exercises the CircleCI path).

## State
- Lean: lean/Fw/Ci/Intent.lean section "The land intent": `landBranch`, `markerMessage`, `LandIntent`, `PushFacts`,
  `landCheck`, `landAdmits`, `pushRefused` (now takes the intent and facts); theorems `plain_no_measuring_refused`,
  `admitted_iff`, `land_admitted`, `landCheck_ok_iff`, one `other_*_refused`/`foreign_process_refused` per check,
  `land_runs_only_land`, `no_intent_unchanged`. `refuse_no_measuring` unchanged.
- Golden: packages/contracts/golden/ci/pushlane.jsonl gains rows `landBranch`, `marker`, `landCheck`
  (`cd lean && lake test -- --write-ci-trigger-golden`).
- TS: apps/runner/src/land-intent.ts (record I/O, `ancestors` via `ps`), ci-push.ts (`landCheck` twin, `landAdmission`,
  hook skips the lane rule only on `ok`), land-remote.ts `makePusher` writes the record around `git push`, land.ts wires
  `fileIntents` on the main checkout's git common dir.
- Tests: apps/runner/test/ci-push-lane-check.test.ts (golden replay + hook e2e: land push passes, hand push refused,
  foreign pid and other branch refused).
- Ledgers: research/mistakes/ledger.json m221, docs/team/incidents/ledger.json inc-land-push-lane; note
  research/notes/2026/10-2x-land-push-lane.md.

## Open
- The first real land with CircleCI legs confirms the path end to end.

## Read first
- research/notes/2026/10-2x-land-push-lane.md, then the Lean section.
