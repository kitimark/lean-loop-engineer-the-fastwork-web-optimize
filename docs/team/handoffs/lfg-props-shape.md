# lfg-props-shape handoff

State: branch worktree-wf_49b2933e-3c9-1. Code is complete at b97b5cd (main merged in). The handoff commit sits on
top. check.sh is green, mathview lint reports 0 failing, and the key theorems use only the standard axioms.

What exists:
- `lean/Fw/Spec/Props.lean` has these parts:
  - `Property Impl := Impl → Prop`, plus `Rejects`, `Nonvacuous` and `Pointwise`;
  - `nonvacuous_of_rejects`, `ne_of_holds_of_rejects` and `rejects_of_counterexample`;
  - `PremiseKind` (engine shell fs ci platform dom), `Premise {kind, id}` and `Assume p c := c` (`assume_iff`,
    `.intro`, `.elim`);
  - `implName` and `killName`.
- `lean/Fw/Search.lean` has these parts:
  - `Enum` (enum, mono, complete) and `EnumAll` (all, complete);
  - `search` (`find?` of the first failing value), `searchUpTo`, `search_none_iff`, `search_some`,
    `search_some_first`, `forall_iff_searchUpTo` and `searchAll_none_iff`;
  - the links to a property: `refutes_of_search` (a counterexample gives `¬ P i`), `holds_of_searchAll`,
    `prop_iff_searchAll` and `prop_iff_searchUpTo`;
  - instances for Bool, Unit, Option, ×, `EnumAll.ofEquiv`, Nat and List (`listsUpTo`, `mem_listsUpTo`).
- `lean/Fw/Spec/Props/LandDryDemo.lean` is the worked example on `inc-land-dry-no-verdict`:
  - the properties `NoSilentExit` and `TruthfulVerdict` over `DryImpl := Outcome → String → Out`;
  - the bad implementations `emptyNoVerdict`, `exnNoVerdict` and `emptyDone`;
  - search guards over all 128 outcomes;
  - kill witnesses proved by the search (`decide +kernel`), and `NoSilentExit_blind_emptyDone`;
  - the proofs `*_impl`, and `stdout_one_verdict` under `Assume`.
- `docs/team/tools/lean-first.md` covers the seven steps, the worked example and the search API.

Conventions: a theorem is named `P_impl : P impl`, `P_rejects_<bad> : ¬ P bad` or `P_iff`, and a check is named
`Q_sound`. The gate decides by type, not by name. A task's Props modules go in `lean/Fw/Props/<TaskCamel>.lean`;
that directory is not created yet.

Open items:
- No checker helper was spawned, because this run had no agent-spawn tool. I reviewed the docstrings against the
  6-point checklist myself.
- `land.dryPrintsOutVerbatim` is an example premise id. `lfg-premise-registry` should register it, or the demo
  should switch to a registered id.
- No Plausible (`lfg-plausible-eval`), and no `Enum` for String. The demo fixes the task name in the search; the
  proof covers every task name.

Read first: the design note `research/notes/2026/10-18-lean-first-gate.md` (sections 1, 4 and 5), then the
LandDryDemo module.
