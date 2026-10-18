# mistake-record-4 handoff

**State:** done on branch worktree-wf_d5cb4940-f30-1 (base f0e5cec). See the commit "mistake-record-4: ..." on that branch.
- `docs/team/incidents/ledger.json`: 15 new rows. `inc-watch-bg-ampersand` gets a 5th occurrence and a new title.
- `pnpm fw incidents lint`: 64 incidents, 0 errors, 12 warnings. The warnings are local-only refs (`event`, `proc`).
- `research/notes/2026/10-18-mistake-retro.md`: new section "Batch 4" (class table, one lesson per row, 6 proposed
  ids) and a batch-4 bullet in "What this changes in the plan".

**Count:** the task said 13 items, but the lead's list had 16 bullets: 15 new rows plus 1 repeat.

**Conventions followed (same as mistake-record-3 at e934534):**
- JSON is written with indent 1 and ensure_ascii off, plus a trailing newline.
- Each cause starts with a status prefix and cites file:line@commit. Evidence uses only commits on main, run ids,
  existing files and event seqs.
- A proposed hardening id stays in the regression text. `hardening`/`fix` name the existing task that hosts it.
- `at` comes from the evidence time where there is one; otherwise it is the recording time.

**Verification:**
- Review counts come from the workflow run journals (`ready_to_land: false`): lfg-props-shape 3, console-stale 4,
  wait-guard-enforce 3.
- CI facts come from `gh run list` and `gh run view`: 39102129920, 39102129956, 39102911529, 39102129921 and 39105133805.
- Events 780-788 come from `.fw-console/events.jsonl`.

**Open items (for the lead):**
- Add the proposed work-graph ids: review-loop-alert, spawn-role-reach, theorem-reach-lint, land-cancel-runs,
  workflow-one-task and gate-expected-red. Then repoint the matching rows' `fix.task`.
- Class `c-silent-drop`: not added (that file is outside this task's writes). Add it on a 3rd occurrence; the note
  gives the reason.

**Read first:** the retro note's "Batch 4" section, then the 15 rows at the end of the ledger.
