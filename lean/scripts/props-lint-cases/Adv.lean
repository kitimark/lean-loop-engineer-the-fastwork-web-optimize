import Fw.Spec.Props.LandDryDemo
/-!
# Props-lint test cases (round-4 review probe; check.sh stage `props lint`)

Each attack below on the convention gate must be a finding of `scripts/PropsLint.lean`; the expected findings
(`<rule> <declaration>`, sorted) are `Adv.expected.txt`. check.sh compiles this file outside the source tree
(`lake env lean -R <d> -o <d>/Adv.olean <d>/Adv.lean`) and lints it together with every `lean_lib`, so the diff also
fails on any finding in the project itself. Not part of any `lean_lib`.
-/
open Fw.Console.LandVerdict Fw.Console.LandDry Fw.Spec.Props Fw.Spec.Props.LandDryDemo Fw.Spec.LandDrySig
  Fw.Spec.Incidents Fw.Spec.Incidents.LandDry

namespace Adv

theorem dryOut_ne_replay : emptyNoVerdict ≠ dryOut := fun h =>
  NoSilentExit_rejects_inc_land_dry_no_verdict (by
    show NoSilentExit emptyNoVerdict
    rw [h]; exact NoSilentExit_impl)

/-! Attack 1: pin the impl through a theorem (closure follows only definitions). -/
theorem hideImpl : ∃ g : DryImpl, g = dryOut := ⟨dryOut, rfl⟩
def PinViaThm (run : DryImpl) : Prop := run = Classical.choose hideImpl

theorem PinViaThm_convention : Convention .landDry dryOut PinViaThm where
  holds := (Classical.choose_spec hideImpl).symm
  kills := ⟨incLandDryNoVerdict, incLandDryNoVerdict_mem, fun h => by
    have := Classical.choose_spec hideImpl
    exact dryOut_ne_replay (h.trans this)⟩
  faithful := landDryRegistry_faithful

/-! Attack 2: name the impl directly, but wrap the convention in a Prop definition. -/
def PinImpl (run : DryImpl) : Prop := run = dryOut
def Wrapped : Prop := Convention .landDry dryOut PinImpl
theorem wrapped : Wrapped where
  holds := rfl
  kills := ⟨incLandDryNoVerdict, incLandDryNoVerdict_mem, dryOut_ne_replay⟩
  faithful := landDryRegistry_faithful


/-! Attack 3: pin the impl through an inductive predicate (closure follows only `defnInfo`, never constructors). -/
inductive IsImpl (run : DryImpl) : Prop
  | mk : run = dryOut → IsImpl run

theorem IsImpl_convention : Convention .landDry dryOut IsImpl where
  holds := ⟨rfl⟩
  kills := ⟨incLandDryNoVerdict, incLandDryNoVerdict_mem, fun ⟨h⟩ => dryOut_ne_replay h⟩
  faithful := landDryRegistry_faithful

/-! Attack 4: same with a structure. -/
structure IsImplS (run : DryImpl) : Prop where
  eq : run = dryOut

theorem IsImplS_convention : Convention .landDry dryOut IsImplS where
  holds := ⟨rfl⟩
  kills := ⟨incLandDryNoVerdict, incLandDryNoVerdict_mem, fun ⟨h⟩ => dryOut_ne_replay h⟩
  faithful := landDryRegistry_faithful
end Adv
