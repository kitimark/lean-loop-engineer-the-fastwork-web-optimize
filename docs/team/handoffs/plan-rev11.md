# Handoff: plan-rev11 (plan-editor)

**State.** PLAN rev 11.1 (round 2) committed on branch `worktree-wf_9847872a-d87-4` (round 1 was ce0df27d; main merged
at c1385a3b); see `git log -1` there. Files: `docs/plan/PLAN.md` (1,365 lines), `docs/plan/loop-plan.html` (one bullet).

**Round 2 (lead decisions in the after-contract-r2 file, P1/P2/P3).**
- §4.8 table is If / Then from the Lean signatures (Compose.lean, Visual.lean:866, 873, 888); usage CONFIRMED only
  where every hypothesis is discharged, else INFERRED with the open premise.
- Bridge `Independent → Indep`: the lead adds the work-graph task (owner lean-prover, after contract-rows-from-code).
- §10.7: sibling gate re-runs and visual re-checks of untouched parts are "dropped under premise"; whole-page gates
  are the evidence. Passes-type savings model-only; per-flag runs before C3 tonight if CI minutes allow.
- §4.7 hidden-pause 1,851 > 1,850: model or harness bug, not `passes_not_compositional` (equal passes, not more).

**Verified.** Every §4.8 row read against `lean/Fw/Engine/Compose.lean` (137, 194, 217-293, 326, 371, 411, 449) and
`Visual.lean`. `scope_sound` (Scope.lean:710) needs `u ∈ pilotParts`, which has 33 part uses (319-470), not 4 as the
round-1 review said; the plan states 33.

**Open.**
- Length 1,365 lines, about 65 over ~1,300 (accepted limit for this round); rev 12 cuts: §8.2 roster, §12.0, §4.2.
- The bridge task is not in work-graph.json yet (the lead's edit).
- C3 facts (wave results, gates, `v2-proved` set, which per-flag passes runs landed) go in rev 12.
- Pre-commit checkmap not run here (fwcore not built in the worktree); the lead's land checks run it.

**Conventions.** Edit PLAN by scratch python scripts with exact-match asserts; no new label prefix without a glossary
row; contradictions go to App A with "which way and why"; theorem sentences restate hypotheses and conclusion.

**Read first.** PLAN §4.8, §10.7, App D rev 11.1; `lean/Fw/Engine/Compose.lean`.
