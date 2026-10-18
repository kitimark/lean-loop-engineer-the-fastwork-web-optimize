# premise-ack handoff

State: branch `worktree-wf_3766c904-1ef-4` (CI branch `ci/premise-ack`), base 7fbb9ba (main merged) plus this note.
premise-tests run 39105133780 on `ci/premise-ack` is green: cv.auto-margin is acknowledged on chromium and webkit,
anim.list passed in that run, and its intermittent ack is not reported stale. `lean/scripts/check.sh` is green.

What exists
- `lean/Fw/Ops/Premise.lean`: section "Acknowledged findings". `errorClass` (first non-blank error line), `failClass`,
  `findings`, `Ack` (premise, engine, cls, finding, intermittent), `ackVerdict`, `AckVerdict.red`, `ackLint`, `acks`
  (3 acks), `ackFindingIds`. Theorems: `red_iff_unacked`, `mem_findings`, `changed_finding_red`, `ack_never_hides_new`,
  `stale_ack_reported`, `intermittent_not_stale`, `acks_lint_clean`. Plus golden rows `ack`, `ackcase`, `acklint`,
  `errorclass`.
- `apps/runner/src/premises.ts`: golden-checked TS stand-in. `fw premises` prints ACK lines in a separate block, plus
  FINDING (with "changed; acknowledged: ..."), STALE ack and LINT ack. Exit 3 on any of these.
- `research/findings/ledger.json`: entries `premise.cv.auto-margin` (n 26) and `premise.anim.list` (n 27, intermittent).
- `packages/premise-tests/src/tests.mjs`: anim.list now records `msToDuring` in the error's observation.
- Docs: `docs/team/tools/premises.md`, section "Acknowledge a finding".

Conventions
- The ack class must be exactly the first non-blank line of the assertion error, so a changed value is a new finding.
- `intermittent := true` only when CI shows both pass and fail (MEASURED: anim.list webkit failed in 1 of 5 runs).

Open items
- anim.list webkit cause is OPEN (INFERRED to be runner timing). Read `msToDuring` from the next failing run.
- `premise-tests.yml` paths omit `research/findings/ledger.json`. The ledger-id lint runs in vitest and in the verdict job only.
- No checker agent was available in this session, so the docstrings were self-checked against the 6-point list.

Read first: the "Acknowledged findings" section of Premise.lean, then `docs/team/tools/premises.md`.
