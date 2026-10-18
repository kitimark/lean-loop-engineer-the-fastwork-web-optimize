# Handoff: lfg-mathview-facts

**State:** round 2 on branch `worktree-wf_cde75b6e-1eb-1` (round 1 `ca517c5` and main `f25c908` merged; see `git log -3`).
Not landed. The CI mathview-differential job has not run (needs a `ci/*` push, lead decides).

**What round 2 changed** (round-1 reviews: math-reviewer and adversarial, both refused):
- Wire reach $W$ = `closure([Fw.Wire.handle] ++ fwIdents(scripts/*Golden.lean))`. `wireRoot` and the module-name roots
  are gone. `#guard !(wire% Fw.Wire.Sched.taskAdmitted)`.
- Subjects (`subjectsOf`): `opsOf` drops sort-valued constants (types, aliases, predicates). If none remain, `ctorOps`
  takes the ops named in the ctor types of the statement's project inductive predicates (Prop-valued only, followed
  transitively, defs not unfolded).
- `reachFromWire : Option Bool`: null when there are no subjects.
- `reach` keeps `MathView.hasEntry` names. `hasEntry` = `candidate` (the old `skip` + name filters) ∧ `shown` (the
  `entryOf` test), so `entries` and the facts share one test.
- The defEq environment limit is stated in `sidesDefEq` and in the note (section 6), guarded via `defEqAt%`.
- The math-review minors are fixed in the docstrings.

**Counts (MEASURED locally, export of 2792 theorems):** round 1 (`ca517c5`): true 2062, false 722, null 0.
Round 2: true 1681, false 949, null 162. 11 went false → true, all from the inductive-predicate fallback
(Sched.Admit, Ci.Budget, Console.Preview). Base fields differ from round 1 only in modules changed since then.

**Read first:** `lean/Fw/Spec/MathFacts.lean` (`subjectsOf`, `wireReach`, the elaborators `facts%`, `wire%`,
`wireOf%`, `defEqAt%`), `lean/Fw/Spec/MathFactsGuards.lean`, `MathView.lean` (`candidate`, `shown`, `hasEntry`).

**Open items:**
- `wire%` reads `scripts/` relative to the working directory, and Lake does not track those files. A changed golden
  script does not rebuild the guards.
- An inductive-predicate subject can be a small helper (for example `Vec.get` in `eq_of_seq`). True then means
  "some op in the invariant is wired".
- No spawn tool was available, so the 6-point docstring checklist was self-applied.
