import Fw.Ops.Meter

/-! # Mutant killers for `Fw.Ops.Meter` (task m0-mutants)

`Obs.le` only appears as a hypothesis of the monotonicity theorems, so making it stricter (`≤` to
`<`) left every theorem true; reflexivity pins it. `Verdict.rank` was only used through its order,
so the exact ranks of the spec are pinned here. -/

namespace FwTest.Mutants.Meter
open Fw.Ops.Meter

/-- The observation order is reflexive.

$$\forall o:\quad o \preceq o$$

Every observation is below itself, which fails as soon as one of the `≤` of the order is strict. -/
theorem obs_le_refl (o : Obs) : o.le o :=
  ⟨rfl, Nat.le_refl _, Nat.le_refl _, Nat.le_refl _, Nat.le_refl _⟩

/-- The ranks of the three verdicts are the specified ones.

$$\mathrm{rank}(\mathrm{resumeOk}) = 0 \land \mathrm{rank}(\mathrm{resumeCheap}) = 1 \land \mathrm{rank}(\mathrm{respawn}) = 2$$

The three ranks are exactly 0, 1 and 2. -/
theorem rank_values : Verdict.rank .resumeOk = 0 ∧ Verdict.rank .resumeCheap = 1 ∧ Verdict.rank .respawn = 2 :=
  ⟨rfl, rfl, rfl⟩

end FwTest.Mutants.Meter
