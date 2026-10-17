# Handoff: plan-rev7-1

**State:** PLAN revision 7.1 committed on this worktree branch (the commit that adds this note; trailer `Task: plan-rev7-1`).
Files: docs/plan/PLAN.md, docs/plan/loop-plan.html (non-math sections only; the math view between the
`mathview-review:begin` and `mathview:end` markers is untouched).

**Done**
- All 15 findings of research/notes/2026/10-17-plan-rev7-review.md applied, each checked against its cited file first.
  Log: PLAN Appendix D, "Revision 7.1 delta", rows 1-15.
- Added freeze-lean (bc2e28a), rewrite-ci-lane (fee88b2), math review round 8 (7d564e2); marked touch-ci-verify,
  class-freeze, store-and-run, gate-unreachable, freeze-lean, rewrite-ci-lane (and alert-steps, watch-fix) done in
  §0, §5.1, §6.6, §10.1, §10.2. Rows 16-19 of the same log.
- WKTR route moved from §12.0 (user decisions) to the §12.2 default Q10 as the lead's reading (finding 6).

**Conventions followed**
- No new label prefixes. "R" is the risk prefix, so the plan writes "original" and "rewrite", never A/R.
- §4.2 findings table has a "Status, source" column; local runs are tagged "MEASURED locally (debug)".
- Lean size from the math view: 1,947 declarations, 910 theorems, 51 modules at 7d564e2. The brief's "68 modules"
  is the file count (67 under lean/Fw plus Fw.lean); the plan uses the math view's 51 and says why in App D.

**Open**
- Length about 1,700 lines vs the ~1,300 target (this task said do not cut). Next cut: move §4.2 findings and §6.6
  details into their notes.
- The rewrite has no frozen class table yet (the frozen table is original-only).
- Lean `workflowInputs` for chromium lacks preset/fw (in math-r8-fix); `fw run` reports them BLOCKED until then.
- The macOS budget (56fe6c9) is not yet a `max-parallel` in the workflow files.

**Read first:** PLAN Appendix D "Revision 7.1 delta", then the §4.2 findings table.
