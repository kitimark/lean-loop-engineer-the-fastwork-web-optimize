/-!
# Start-cost lint: the constants `fwcore` evaluates before `main`, each measured in small allocations against `bound`.
`scripts/InitCostLint.lean` runs it; `Fw.Lint.InitCostScan` finds and measures the constants.
-/
namespace Fw.Lint.InitCost

/-- Most small allocations one start-time constant may cost. -/
def bound : Nat := 10000

/-- `a` and the heartbeat count after `a` was evaluated (the caller evaluates the argument before the call). -/
@[noinline] def heartbeatsAfter {α : Type} (a : α) : BaseIO (α × Nat) := do
  return (a, ← IO.getNumHeartbeats)

/-- Small allocations made by `get h`, where `h` is the heartbeat count at the call. -/
@[noinline] def allocs {α : Type} (get : Nat → α × Nat) : BaseIO Nat := do
  let h0 ← IO.getNumHeartbeats
  let (_, h1) ← heartbeatsAfter (get h0)
  return h1 - h0

/-- The symbol `X` of a C line `X = _init_X();`, the form the C backend gives each constant it evaluates at start. -/
def initStem? (line : String) : Option String :=
  match line.splitOn " = _init_" with
  | [lhs, rhs] => if !lhs.isEmpty && !lhs.contains ' ' && rhs == lhs ++ "();" then some lhs else none
  | _ => none

#guard initStem? "lp_fwcore_Fw_A_b = _init_lp_fwcore_Fw_A_b();" == some "lp_fwcore_Fw_A_b"
#guard initStem? "l_Adv_big = _init_l_Adv_big();" == some "l_Adv_big"
#guard initStem? "lp_fwcore_Fw_A_b = _init_lp_fwcore_Fw_A_c();" == none
#guard initStem? "lean_mark_persistent(lp_fwcore_Fw_A_b);" == none
#guard initStem? " = _init_();" == none
#guard initStem? "res = initialize_Init(builtin);" == none

def boxedConstMark : String := "___boxed__const__"

/-- A start-time symbol with no constant of its own: the boxed copy of a scalar closed term. -/
def isBoxedConst (stem : String) : Bool := (stem.splitOn boxedConstMark).length > 1

#guard isBoxedConst "lp_fwcore_Fw_P_lines___closed__144___boxed__const__1"
#guard !isBoxedConst "lp_fwcore_Fw_P_lines"
#guard !isBoxedConst "lp_fwcore_Fw_P_lines___closed__144"

structure Row where
  name : String
  cost : Nat
deriving DecidableEq, Repr

inductive Finding where
  | over (name : String) (cost : Nat)
  | unmapped (stem : String)
deriving DecidableEq, Repr

def Finding.line : Finding → String
  | .over n c => s!"init-cost: over {n}: {c} allocations at start, bound {bound}"
  | .unmapped s => s!"init-cost: unmapped {s}: evaluated at start, no constant to measure"

def rowFinding (b : Nat) (r : Row) : Option Finding :=
  if r.cost ≤ b then none else some (.over r.name r.cost)

def stemFinding (s : String) : Option Finding :=
  if isBoxedConst s then none else some (.unmapped s)

/-- Each unmapped start-time symbol that is not a boxed scalar, then each constant over `b`, in start order. -/
def findings (b : Nat) (rows : List Row) (unmapped : List String) : List Finding :=
  unmapped.filterMap stemFinding ++ rows.filterMap (rowFinding b)

#guard findings 10 [⟨"a", 3⟩, ⟨"b", 10⟩] [] == []
#guard findings 10 [⟨"a", 3⟩, ⟨"b", 11⟩] [] == [.over "b" 11]
#guard findings 10 [] ["x___boxed__const__1"] == []
#guard findings 10 [⟨"a", 30⟩] ["x"] == [.unmapped "x", .over "a" 30]

theorem rowFinding_within {b : Nat} {r : Row} (h : r.cost ≤ b) : rowFinding b r = none := by
  simp [rowFinding, h]

theorem rowFinding_over {b : Nat} {r : Row} (h : b < r.cost) : rowFinding b r = some (.over r.name r.cost) := by
  simp [rowFinding, Nat.not_le.mpr h]

theorem stemFinding_boxed {s : String} (h : isBoxedConst s = true) : stemFinding s = none := by
  simp [stemFinding, h]

theorem stemFinding_unmapped {s : String} (h : isBoxedConst s = false) : stemFinding s = some (.unmapped s) := by
  simp [stemFinding, h]

theorem findings_nil_iff (b : Nat) (rows : List Row) (unmapped : List String) :
    findings b rows unmapped = [] ↔ (∀ s ∈ unmapped, isBoxedConst s = true) ∧ ∀ r ∈ rows, r.cost ≤ b := by
  simp only [findings, List.append_eq_nil_iff, List.filterMap_eq_nil_iff]
  constructor
  · rintro ⟨hu, hr⟩
    refine ⟨fun s hs => ?_, fun r hr' => ?_⟩
    · have := hu s hs
      cases hb : isBoxedConst s <;> simp_all [stemFinding]
    · have := hr r hr'
      by_cases hc : r.cost ≤ b <;> simp_all [rowFinding]
  · rintro ⟨hu, hr⟩
    exact ⟨fun s hs => stemFinding_boxed (hu s hs), fun r hr' => rowFinding_within (hr r hr')⟩

/-- `n` rows, their total, and the five dearest, as one summary line. -/
def summary (rows : List Row) (boxed : Nat) : String :=
  let top := (rows.mergeSort fun a b => a.cost ≥ b.cost).take 5
  s!"init-cost: {rows.length} start-time constants ({boxed} boxed scalars), {(rows.map (·.cost)).sum} allocations, " ++
    s!"dearest: {", ".intercalate (top.map fun r => s!"{r.name} {r.cost}")}"

#guard summary [⟨"a", 3⟩, ⟨"b", 7⟩] 1 == "init-cost: 2 start-time constants (1 boxed scalars), 10 allocations, dearest: b 7, a 3"

/-- Measures each constant in start order, prints the findings and the summary, and fails on any finding. -/
def report (unmapped : List String) (probes : List (String × BaseIO Nat)) : IO Unit := do
  let mut rows : Array Row := #[]
  for (n, p) in probes do
    rows := rows.push ⟨n, ← p⟩
  let fs := findings bound rows.toList unmapped
  for f in fs do IO.println f.line
  IO.println (summary rows.toList (unmapped.filter isBoxedConst).length)
  unless fs.isEmpty do
    throw (IO.userError s!"init-cost: FAILED: {fs.length} finding(s)")

end Fw.Lint.InitCost
