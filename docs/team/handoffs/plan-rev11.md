# Handoff: plan-rev11 (plan-editor)

**State.** PLAN rev 11.2 (final design round) committed on branch `worktree-wf_9847872a-d87-4` (round 1 ce0df27d,
round 2 45c46c37; main merged at 6493cd83); see `git log -1` there. Files: `docs/plan/PLAN.md` (1,387 lines),
`docs/plan/loop-plan.html` (one parenthetical).

**Final design round (Fable brief, five sentences only).** Rule per sentence: every theorem mention carries If/Then
from the Lean statement; CONFIRMED only when every If holds for the site, else INFERRED naming the open premise.
- S1 §10.7, S2 §0 (+ html bullet): units-type combined run INFERRED under the open bridge; `frameWork_append_units`
  gives the page sum within one run; per-flag attribution needs `lego_swap_units` (abstract `Indep`).
- S3 §4.8 `passes_not_compositional`: equal passes CONFIRMED; "never an increase" INFERRED (from `passes_append`).
- S4 §4.8 Visual row split into three; `_Q` (909) added; box ½ px composes (`boxQ`/`tolBox`), band-height ½ px not.
- S5 §10.7 visual cut clause matches S4.

**Verified.** Lean lines Compose.lean:108, 137, 217, 371, 411 and Visual.lean:232, 866, 873, 888, 909 read at merge.

**Open (accepted limits).**
- Length 1,387 lines (~85 over); rev 12 cuts §8.2, §12.0, §4.2. The round forbade other edits.
- Bridge task `Independent → Indep` not in work-graph.json yet (lead's edit).
- C3 facts, per-flag passes runs, F6 go in rev 12.
- Follow-ups for lean-prover: `passes_append_le` (makes S3 CONFIRMED), the bridge proof (flips S1/S2 and §10.7 cuts).
- Pre-commit checkmap not run here; the lead's land checks run it.
- A third refusal splits S1+S2 from S3-S5 into two tasks.

**Conventions.** Edit PLAN by scratch python scripts with exact-match asserts; no new label prefix without a glossary
row; contradictions go to App A with "which way and why"; theorem sentences restate hypotheses and conclusion.

**Read first.** PLAN §4.8, §10.7, App D rev 11.2; `lean/Fw/Engine/Compose.lean`.
