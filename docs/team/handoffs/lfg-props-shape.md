# lfg-props-shape handoff

State: round 2 on branch worktree-wf_7237e934-b3b-1 (round-1 head 7bef9d7 and main merged in). Code commit 516652f;
the handoff commit sits on top. check.sh is green (~41 s), and the key theorems use only the standard
axioms.

What exists:
- `lean/Fw/Spec/Props.lean`:
  - `Property Impl := Impl → Prop`, `Rejects`, `Nonvacuous`, `Pointwise` (`{α : Type v}`), `nonvacuous_of_rejects`,
    `rejects_of_counterexample` (`ne_of_holds_of_rejects` dropped in round 2: trivially true);
  - round 2: `AgreesOff impl bad incident`, `ReadsAt Q pt`, `failures_on_incident` (every failure of `bad` is an
    incident input), `fails_on_incident` (and at least one is);
  - `PremiseKind`, `Premise {kind, id}`, `Assume` is now a structure (`Assume.intro`, `.elim`, `assume_iff`) with a
    `fail_if_success exact h` example; module doc names `lfg-premise-registry` / `lfg-mathview-facts` as the only
    enforcement for unmarked hypotheses and unregistered ids;
  - `implName` and `killName`.
- `lean/Fw/Search.lean`: `Enum` / `EnumAll`, `search`, `searchUpTo` and the property links; round 2 reworded "size"
  (the class has no size function).
- `lean/Fw/Spec/Props/LandDryDemo.lean`: as round 1, plus `emptyIncident`, `threwIncident`, `<bad>_agrees_off` for
  all three bad runs, step 6b (`qOneVerdictAt`, `qTruthfulAt`, `*_iff_pointwise`, `*_readsAt`, three
  `*_on_incident`), and `emptyNoVerdict_search` / `exnNoVerdict_search` (first counterexample for every task name).
- `docs/team/tools/lean-first.md`: steps 3, 6, 7 require `<bad>_agrees_off` and the `_on_incident` theorem, and state
  what Lean does not catch.

Conventions: `P_impl`, `P_rejects_<bad>`, `<bad>_agrees_off`, `P_rejects_<bad>_on_incident`, `P_iff`, `Q_sound`. The
gate decides by type, not by name. Task Props modules go in `lean/Fw/Props/<TaskCamel>.lean` (not created yet).

Open items:
- No checker helper was spawned (no agent-spawn tool in this run); docstrings self-reviewed against the checklist.
- `land.dryPrintsOutVerbatim` is an example premise id until `lfg-premise-registry` registers it.
- No `Enum` for String; `emptyDone`'s first counterexample is still a task-"x" guard (the `_on_incident` theorem
  covers every task).

Read first: the design note `research/notes/2026/10-18-lean-first-gate.md` (sections 1, 4, 5), then LandDryDemo.
