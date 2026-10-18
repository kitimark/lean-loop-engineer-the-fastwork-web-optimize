# lfg-props-shape handoff

State: round 3 on branch worktree-wf_d4784429-e5d-1 (round-2 head a114e56 and main merged in). Code commit d5a9f07
(the handoff-only commit sits on top). check.sh is green, `fw land --dry` gives `VERDICT dry`, and the key theorems
use only the standard axioms.

Round 3 (review: the author picked both the bad and the incident predicate, so `Silly := exit ≤ 100` met every rule):
- `lean/Fw/Spec/Props.lean`: incident registry `Incident α β {id, pred, replay}`, `Strict`, `Registry {rows, ids_ne,
  ids_nodup, strict}`, `Registry.Faithful impl R` (AgreesOff per row: a check on the replay only), `Kills R P :=
  ∃ i ∈ R.rows, ¬ P i.replay`, `Convention R impl P {holds, kills, faithful}`, `kills_of_rejects`,
  `not_kills_of_passes`, `nonvacuous_of_kills`. `Premise.id_ne : id ≠ "" := by decide` (anonymous `⟨k, id⟩` no
  longer elaborates; use `{ kind := k, id := "…" }`), `assume_false_elim` states that a marked `False` proves
  anything. `killName P incidentId` maps `-` to `_`.
- `lean/Fw/Spec/Props/LandDryDemo.lean`: one row `incLandDryNoVerdict` (ledger has one incident; exn and emptyDone are
  mutants, not rows), `landDryRegistry`, `emptyIncident_strict`, `landDryRegistry_faithful`,
  `*_rejects_inc_land_dry_no_verdict`, `*_kills`, `*_convention`, two `*_on_incident` for the replay; step 6c
  `Silly`, `sillyBad`, `Silly_passes_replay : ¬¬ Silly incLandDryNoVerdict.replay`, `Silly_not_kill`,
  `Silly_not_convention`. Removed `threwIncident` and the mutants' `agrees_off` / `on_incident`.
- `lean/Fw/Search.lean`: `refutes_of_search` math now says isSome(search) = true.
- `docs/team/tools/lean-first.md`: steps 3, 4, 5, 6, 7, names and worked example match.
- Reviewer probe re-run (copy in scratchpad/lfg3/Probe.lean): the `Silly` kill needs `sorry`, `¬ Kills landDryRegistry
  Silly` proves, and the empty-id `Assume` lines fail to elaborate.

Conventions: `P_impl`, `P_rejects_<incident id with _>`, `P_kills`, `P_convention`, `P_rejects_<i>_on_incident`,
`P_iff`, `Q_sound`. The gate decides by type (`Convention R impl P`), not by name. Task Props modules go in
`lean/Fw/Props/<TaskCamel>.lean` (not created yet).

Open items:
- `Incident.id` is not checked against docs/team/incidents/ledger.json in Lean (lint belongs with `lfg-land-wire`).
- Premise ids are only non-empty; registry membership is `lfg-premise-registry`.
- No checker helper was spawned (no agent-spawn tool in this run); docstrings self-reviewed against the checklist.

Read first: the design note `research/notes/2026/10-18-lean-first-gate.md` (sections 1, 4, 5), then LandDryDemo.
