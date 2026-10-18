# Lean first: write the properties before the code

How an agent states what must never happen, shows the statement can fail, searches for bugs, and only then proves.
Design and rules R1-R5: `research/notes/2026/10-18-lean-first-gate.md`. Foundation (task `lfg-props-shape`):

| module | what it gives |
|---|---|
| `lean/Fw/Spec/Props.lean` | `Property Impl := Impl → Prop`, `Rejects`, `Nonvacuous`, `Pointwise`, `AgreesOff`, `ReadsAt`, `failures_on_incident`, `fails_on_incident`, the incident registry (`Incident`, `Strict`, `Registry`, `Registry.Faithful`, `Kills`, `Convention`), the premise marker `Assume` (a structure), `PremiseKind`, `Premise` (non-empty id), the names `implName` / `killName` |
| `lean/Fw/Search.lean` | `Enum` (a list of values per bound; no size function), `EnumAll` (finite types), `search` (first counterexample), `searchUpTo`, the links `refutes_of_search`, `holds_of_searchAll`, `prop_iff_searchAll`, `prop_iff_searchUpTo` |
| `lean/Fw/Spec/Props/LandDryDemo.lean` | the worked example below, all seven steps |

Stages: C0 and C1 (the cutover commits on main, design note section 8) are not set yet. Until the gate lands
(`lfg-land-wire`), these rules are a convention, not a land refusal.

## The steps

1. **Signature.** Name the type of the implementation: inputs (the facts) to output (what the process prints and its
   exit code). Exceptions and early returns are *inputs* (a `threw` fact), so every path has an output.
2. **Properties over the signature.** One `Prop`-valued def per never-happen property, `def P (impl : Impl) : Prop`.
   It does not mention the implementation, so it exists before the code. Docstring: one English sentence plus `$$`
   math, as for every theorem. New task modules go in `lean/Fw/Props/<TaskCamel>.lean`.
3. **Registered incidents, not bad implementations of your choice.** The kill target is an `Incident` row of the
   signature's `Registry`, written once per incident of `docs/team/incidents/ledger.json` and reviewed with that
   incident, never per property: `id` (the ledger id), `pred` (the incident inputs) and `replay` (the implementation
   that reproduces the real bug, named after it, for example `emptyNoVerdict`). The `Registry` proves every id
   non-empty, the ids distinct and every `pred` strict (`Strict pred`: some input is not an incident input). Why:
   when the author of a property also picks the bad implementation and the incident inputs, an unrelated property
   ("the exit code is at most 100") rejects a made-up bad that differs only on the incident inputs, and still
   passes the real bug. Once the real implementation exists, prove `Registry.Faithful impl R`: every replay equals
   `impl` off its incident inputs (`AgreesOff`). That checks the replay, not a property. Extra mutants (`emptyDone`,
   `exnNoVerdict`) are welcome as `¬ P bad` theorems, for example to show a blind property, but they never count
   as a kill.
4. **Search before proof.** Write a pointwise `Bool` check `Q impl x` and prove `P_iff` (`P impl ↔ ∀ x, Q impl x =
   true`), or at least the sound direction. Give the input type an `Enum` / `EnumAll` instance. Add guards:
   `#guard (search EnumAll.all (Q impl)).isNone` and, for each replay and mutant `m`,
   `#guard (search EnumAll.all (Q m)).isSome`. The second guard shows the search can see the bug at all. A search
   must exhaust a finite type or cover at least 10^3 points, and take at most 5 s of elaboration.
5. **Kill witnesses.** Each property names at least one registered incident `i` it rejects:
   `theorem P_rejects_<i> : ¬ P i.replay` (the id's `-` become `_`, `killName`). Prove each one by running the
   search: `refutes_of_search _ _ _ EnumAll.all (Q_sound i.replay t) (by decide +kernel)`. Then
   `theorem P_kills : Kills R P` by `kills_of_rejects`. A property that passes every replay kills nothing
   (`not_kills_of_passes`), however many made-up bads it rejects.
6. **Proof.** `theorem P_impl : P impl`. Commit it only after the guards of step 4: rule 5 checks that order in git.
   Then `theorem P_convention : Convention R impl P` (`P impl`, `Kills R P`, `Registry.Faithful impl R`). With a
   check that reads one point (`ReadsAt Q pt`), `failures_on_incident` gives that the replay fails only on incident
   inputs and `fails_on_incident` that it fails on at least one (`P_rejects_<i>_on_incident`).
7. **Premises.** Anything Lean cannot see (engine behaviour, shell semantics, the file system, CI, the process
   printing what Lean computed) enters as a hypothesis
   `(h : Assume { kind := k, id := "registry.id" } claim)`, never inside a def. Kinds: `engine`, `shell`, `fs`,
   `ci`, `platform`, `dom`. An empty id does not elaborate (`Premise.id_ne`, proved by `decide`); the id must also
   be in the premise registry (`lfg-premise-registry`). `Assume` is a structure, so the marked claim is built only
   by `Assume.intro` and read by `Assume.elim`; a bare proof does not fit where the marker is expected. The marker
   only labels the premise and enforces nothing about its content: a marked premise of `False` proves anything
   (`assume_false_elim`), so premise contents are reviewed with the registry. Lean does *not* catch: a theorem that
   takes an outside fact as a bare, unmarked hypothesis; a non-empty premise id that is not in the registry; an
   `Incident.id` that is not in the ledger. Only `lfg-premise-registry` (premise ids), `lfg-mathview-facts`
   (hypotheses listed in review) and, for incident ids, an open item of `lfg-land-wire` enforce those.

Names: `P_impl`, `P_rejects_<i>`, `P_kills`, `P_convention`, `P_rejects_<i>_on_incident`, `P_iff`, `Q_sound`,
`<replay>_agrees_off`, `<registry>_faithful` (`implName`, `killName` in `Fw.Spec.Props`). The gate reads the types
(`P impl`, `¬ P i.replay` for a row `i` of the registry, `Convention R impl P`), not the names.

## Worked example: `fw land --dry` on an empty branch (`inc-land-dry-no-verdict`)

Incident: in fix-orbit, `fw land --dry` on a branch with no commits of its own printed a path and no `VERDICT` line.
A script reading the verdict found none.

1. Signature: `DryImpl := Outcome → String → Out`, where `Outcome` holds the seven stage results of
   `Fw.Console.LandDry` (`threw fresh own scope merges reads lints`), the `String` is the task, and `Out` is
   `{lines, exit}`.
2. Properties:
   - `NoSilentExit run := ∀ o t, verdictCount (run o t).lines = 1`
     $$\forall O\, t,\ |[\ell \in r(O,t).\mathrm{lines} : \ell \text{ starts with } \texttt{VERDICT }]| = 1$$
   - `TruthfulVerdict run`: the last line is `verdictLine o.kind t`, and the exit code is `o.kind.exitCode`.
3. The registry has one row, because the ledger has one incident for this decision: `landDryRegistry =
   [incLandDryNoVerdict]` with id `inc-land-dry-no-verdict`, incident inputs `emptyIncident` (an empty branch;
   `emptyIncident_strict`) and replay `emptyNoVerdict`; `landDryRegistry_faithful` checks the replay against
   `dryOut`. Two mutants are not rows:

   | implementation | role and what it does | which property rejects it |
   |---|---|---|
   | `emptyNoVerdict` | replay: the empty branch returns after the log, exit 0 | both (kills) |
   | `exnNoVerdict` | mutant: top-level catch prints `Error: land failed`, exit 1 | both (not kills) |
   | `emptyDone` | mutant: the empty branch prints `VERDICT done`, exit 0 | only `TruthfulVerdict` (not a kill) |

4. The search, before any proof. There are 128 outcomes ($\mathbb B^7$, `EnumAll.ofEquiv`), and the task is fixed to
   `"x"`:

   ```lean
   #guard (search EnumAll.all (qOneVerdict dryOut "x")).isNone          -- the real run: clean
   #guard ((search EnumAll.all (qOneVerdict emptyNoVerdict "x")).map
            fun o => (o.threw, o.fresh, o.own)) == some (false, true, false)   -- found: the empty branch
   #guard ((search EnumAll.all (qOneVerdict exnNoVerdict "x")).map (·.threw)) == some true
   #guard (search EnumAll.all (qOneVerdict emptyDone "x")).isNone       -- NoSilentExit is blind here
   #guard (search EnumAll.all (qTruthful emptyDone "x")).isSome         -- TruthfulVerdict is not
   ```

   The search found the incident's input, an empty branch (`threw = false, fresh = true, own = false`), with no proof
   written. The `emptyDone` guard showed that one property was not enough. `NoSilentExit_blind_emptyDone` proves
   that blindness.
5. Kill witnesses against the registered replay: `NoSilentExit_rejects_inc_land_dry_no_verdict` and
   `TruthfulVerdict_rejects_inc_land_dry_no_verdict` (`¬ P incLandDryNoVerdict.replay`), each by
   `refutes_of_search … (by decide +kernel)`, then `NoSilentExit_kills` and `TruthfulVerdict_kills`. The mutants
   get `NoSilentExit_rejects_exnNoVerdict` and `TruthfulVerdict_rejects_emptyDone`, which are not kills.
6. Proofs: `NoSilentExit_impl` and `TruthfulVerdict_impl`, from `Fw.Console.LandDry.dryRun_one_verdict`, then
   `NoSilentExit_convention` and `TruthfulVerdict_convention`. The two `*_on_incident` theorems: the replay fails
   each check only on empty-branch inputs and on at least one, for every task. The `#guard`s search task `"x"`;
   `emptyNoVerdict_search` and `exnNoVerdict_search` prove the same first counterexample for every task name.
   The negative case: `Silly run := ∀ o t, (run o t).exit ≤ 100` holds of `dryOut` (`Silly_impl`) and rejects a
   made-up `sillyBad` (exit 200 on the empty branch), which met every round-2 rule. It passes the registered replay
   (`Silly_passes_replay : ¬ ¬ Silly incLandDryNoVerdict.replay`), so `Silly_not_kill : ¬ Kills landDryRegistry
   Silly` and `Silly_not_convention`.
7. Premise: `stdout_one_verdict` concludes one verdict line for the *real stdout*, but only under
   `Assume { kind := .shell, id := "land.dryPrintsOutVerbatim" } (∀ o t, stdout o t = (dryOut o t).lines)`. That is the step from
   Lean to `land.ts`. The id is an example until `lfg-premise-registry` registers it.

## Search API (`Fw.Search`)

- `search xs q`: the first `x ∈ xs` with `q x = false`. `search_none_iff`: `search xs q = none ↔ ∀ x ∈ xs, q x = true`
  (the property on that bound). `search_some` and `search_some_first`: what it returns is a real counterexample, and it
  is the first one.
- `searchUpTo n q` searches `Enum.enum n`. `forall_iff_searchUpTo`: clean at every bound iff the check holds everywhere.
- Instances: finite (`Bool`, `Unit`, `Option`, `×`, `EnumAll.ofEquiv`) and bounded (`Nat` ≤ n, `List` of length
  ≤ n, `Option`, `×`). For a structure, map it from a tuple with `EnumAll.ofEquiv`.
- For text inputs (shell lines, transcripts), write a small grammar type with an `Enum` instance and render it to
  text. Add a corpus of real logs as well (design note, rule 5).
