# incident-lean-fields handoff

State: committed on this worktree branch (see `git log -1`); not landed.

What exists
- `lean/Fw/Plan/Incident.lean`: `Incident` gains `leanVerdict`, `leanReason`, `hardening`, `empiricalCheck`, `mistakeClass`
  (optional strings); `Facts` gains `classes`. 7 new error codes: missingLeanVerdict, badLeanVerdict, missingLeanReason,
  missingHardening, unknownHardening, missingEmpiricalCheck, unknownMistakeClass; each detail names the field.
- Rule: provable/partly need `hardening` (a work graph id); `no` needs `empiricalCheck` (a hardening on a `no` is optional,
  but must exist if named). `mistakeClass` optional, must be a class id of research/mistakes/ledger.json.
- Theorems: `lint_ok_iff` (ok iff every entry `Complete`), `okOne_iff`, `verdict_codes_iff`, `verdictOf_not_blank`,
  `no_without_empiricalCheck_refused`, `ok_hardening_exists`; `holds_mono_facts` now also takes classes ⊆.
  Old status theorems unchanged and green.
- `lean/Fw/Wire/Plan.lean` (outside the listed writes, needed): decodes the 5 fields and the `classes` fact.
- Glue `apps/runner/src/incidents.ts`: `mistakeClasses(root)` reads `classes[].id`, passed as `classes`.
- Golden `packages/contracts/golden/plan/incident-lint.jsonl`: 38 cases (10 new lean-field cases + 1 refusal); old
  requests changed (the `good` record now carries the fields), regenerated with FW_WRITE_INCIDENT_GOLDEN=1.

Backfill (docs/team/incidents/ledger.json, 16 incidents, all matched; no "unmatched in retro")
- incident -> retro row: orphan-wait-loop m090, unlanded-handback m133, claim-order m128, plan-sync-on-land-only m130,
  land-post-commit-throw m139, commit-during-land m065, land-scope-registrations m141, agent-on-ci-branch m140,
  fw-lean-import-conflict m066, gh-rate-limit m100, next-false-positives m134, retention-hides-unlanded m133,
  variant-gate-flags-off m043, silent-stdin-bg m092, worktree-role-as-teammate m116, workflow-unbound m144.
- Verdicts: 15 provable, 1 partly (silent-stdin-bg, empiricalCheck from m092), 0 no. Verdict/reason copied verbatim.
- `hardening` choice (judgement, review it): the task the retro's leanReason credits (often the incident's fix task);
  orphan-wait-loop -> wait-guard and variant-gate-flags-off -> gate-exit-verdict (class NEW tasks, open).
- Extra informational field `mistake` (retro row id), not linted.

Open items
- Parallel incidents (inc-watch-unlanded-after-land, inc-watch-alert-during-land, inc-slow-land) need the fields at land.
- wt-prep.sh treats a long-lived `lean --server` in main/lean as a running build and skips the clone (cloned by hand).

Read first: the module header of `lean/Fw/Plan/Incident.lean`, then `docs/team/incidents/README.md`.
