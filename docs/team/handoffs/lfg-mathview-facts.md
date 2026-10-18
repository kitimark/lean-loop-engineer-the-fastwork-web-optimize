# Handoff: lfg-mathview-facts

**State:** round 2 on branch `worktree-wf_cde75b6e-1eb-1`, with round 1 (`ca517c5`) and main merged (see `git log -3`).
Not landed. The CI mathview-differential job has not run; it needs a `ci/*` push, which the lead decides.

**What round 2 changed** (both round-1 reviews refused: math-reviewer and adversarial):
- Wire reach $W$ = `closure([Fw.Wire.handle] ++ fwIdents(scripts/*Golden.lean))`. `wireRoot` and module-name roots
  are gone. `#guard !(wire% Fw.Wire.Sched.taskAdmitted)`.
- Subjects (`subjectsOf`): `opsOf` drops sort-valued constants (types, aliases, predicates). If none remain, `ctorOps`
  takes the ops named in the constructor types of the statement's project inductive predicates. Only Prop-valued
  inductives count; they are followed transitively, and definitions are not unfolded.
- `reachFromWire : Option Bool` is null when a theorem has no subjects.
- `reach` keeps names that pass `MathFacts.hasEntry`, which applies `MathView.skip` plus the `entries`/`entryOf`
  filters. `entryJson` also intersects with the set of exported entry names, so the export output is exact.
- The defEq environment limit is stated in `sidesDefEq` and in the module doc. `defEqAt%` guards the budget edge.
- The math-review minors are fixed in the docstrings.

**Counts (MEASURED locally, export):**

| export | theorems | true | false | null |
|---|---|---|---|---|
| round 1 (`ca517c5`) | 2784 | 2062 | 722 | 0 |
| round 2 | 2796 | 1685 | 949 | 162 |

11 theorems moved false → true. All come from the inductive-predicate fallback (Sched.Admit, Ci.Budget,
Console.Preview).

**Read first:** `lean/Fw/Spec/MathFacts.lean` (`hasEntry`, `subjectsOf`, `wireReach`, and the elaborators `facts%`,
`wire%`, `wireOf%`, `defEqAt%`), then `lean/Fw/Spec/MathFactsGuards.lean`.

**Open items:**
- Out of scope (writes = MathViewMain, Fw/Spec/**, scripts/**): the as-built text for note section 6 (W, subjects,
  three values, defEq limit) is in the MathFacts module doc. `hasEntry` copies the `MathView` filters; moving it
  into `MathView.lean` needs that path in scope.
- `wire%` reads `scripts/` relative to the working directory, and Lake does not track those files. The guards also
  hold with no sources at all (checked).
- An inductive-predicate subject can be a small helper, for example `Vec.get` in `eq_of_seq`.
- No spawn tool was available, so the 6-point docstring checklist was self-applied.
