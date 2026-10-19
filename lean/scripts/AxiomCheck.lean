import MathView
open Lean Elab Command

/-!
Fails when a constant of a module under `Fw/` depends on `sorryAx` or on an axiom outside `MathView.standardAxioms`.
Run from `lean/` by `scripts/axiom-check.sh`: it imports every module under `Fw/` and the probe, then runs `check`.
-/
namespace AxiomCheck

/-- The refusal reasons of one constant from its axioms, in their order. -/
def findings (axs : List String) : List String :=
  axs.filterMap fun a =>
    if a == "sorryAx" then some "depends on sorryAx"
    else if MathView.standardAxioms.contains a then none
    else some s!"non-standard axiom {a}"

theorem findings_nil_iff (axs : List String) :
    findings axs = [] ↔ ∀ a ∈ axs, a ∈ MathView.standardAxioms := by
  unfold findings
  rw [List.filterMap_eq_nil_iff]
  refine forall_congr' fun a => imp_congr_right fun _ => ?_
  by_cases hs : a = "sorryAx"
  · subst hs; simp [MathView.standardAxioms]
  · by_cases hc : MathView.standardAxioms.contains a = true
    · simp [hs, List.elem_iff.mp hc]
    · have : a ∉ MathView.standardAxioms := fun h => hc (List.elem_iff.mpr h)
      simp [hs, this]

theorem sorry_refuses (axs : List String) (h : "sorryAx" ∈ axs) : findings axs ≠ [] := by
  rw [Ne, findings_nil_iff]
  intro hall
  have := hall _ h
  simp [MathView.standardAxioms] at this

theorem nonstandard_refuses (axs : List String) (a : String) (h : a ∈ axs)
    (hn : a ∉ MathView.standardAxioms) : findings axs ≠ [] := by
  rw [Ne, findings_nil_iff]
  exact fun hall => hn (hall a h)

theorem standard_passes (axs : List String) (h : ∀ a ∈ axs, a ∈ MathView.standardAxioms) :
    findings axs = [] :=
  (findings_nil_iff axs).mpr h

#guard findings [] == []
#guard findings ["propext", "Classical.choice", "Quot.sound"] == []
#guard findings ["propext", "sorryAx"] == ["depends on sorryAx"]
#guard findings ["Lean.ofReduceBool"] == ["non-standard axiom Lean.ofReduceBool"]
#guard findings ["X.wish", "propext", "sorryAx"] == ["non-standard axiom X.wish", "depends on sorryAx"]

/-- The module of a source path under `lean/`. -/
def moduleOf (f : System.FilePath) : Name := (f.withExtension "").components.foldl Name.mkStr .anonymous

#guard moduleOf "Fw/Console/LandDry.lean" == `Fw.Console.LandDry

/-- Every module under `Fw/`, plus `Fw`. -/
def diskModules : IO (Array Name) := do
  let files ← System.FilePath.walkDir "Fw"
  return #[`Fw] ++ (files.filter (·.extension == some "lean")).map moduleOf

/-- One `<constant>: <reason>` line per finding over `cs`, sorted. -/
def lines (cs : Array Name) : CoreM (List String) := do
  let mut out := #[]
  for c in cs do
    for f in findings ((← collectAxioms c).toList.map toString) do
      out := out.push s!"{c}: {f}"
  return out.toList.mergeSort (· ≤ ·)

/-- The constants of the imported modules that `p` selects. -/
def constsOf (env : Environment) (p : Name → Bool) : Array Name :=
  (env.header.moduleNames.zip env.header.moduleData).foldl
    (fun acc (m, d) => if p m then acc ++ d.constNames else acc) #[]

/-- The findings `scripts/axiom-check-cases/AxProbe.lean` must produce. -/
def probeWant : List String :=
  ["AxProbe.usesWish: non-standard axiom wish", "AxProbe.viaDef: depends on sorryAx",
   "AxProbe.viaMacro: depends on sorryAx", "wish: non-standard axiom wish"]

/-- Logs an error per module not imported, per finding over the `Fw` constants and when the probe findings differ from
`probeWant`. -/
def check : CommandElabM Unit := do
  let env ← getEnv
  let missing := ((← diskModules).push `AxProbe).filter fun m => (env.getModuleIdx? m).isNone
  for m in missing do logError m!"axiom check: module {m} is not imported"
  let fw := constsOf env (`Fw).isPrefixOf
  let bad ← liftCoreM (lines fw)
  for l in bad.take 50 do logError m!"axiom check: {l}"
  let got ← liftCoreM (lines (constsOf env (· == `AxProbe)))
  unless got == probeWant do logError m!"axiom check: the probe findings are {got}, expected {probeWant}"
  IO.println s!"axiom check: {fw.size} constants, {bad.length} failing, {missing.size} modules not imported, probe {if got == probeWant then "ok" else "FAILED"}"

end AxiomCheck
