import Lean
import Fw.Lint.InitCost
/-!
# Start-cost scan: the constants the C files of a program's modules evaluate at start, measured in the interpreter.
`run_cmd scan roots irDirs` in a file that imports `roots`; the verdict is `Fw.Lint.InitCost.report`.
-/
open Lean Elab Command Meta

namespace Fw.Lint.InitCostScan

/-- The imported modules `roots` reach, in import order. -/
def closure (env : Environment) (roots : List Name) : Array (Nat × Name) := Id.run do
  let mut seen : NameSet := roots.foldl NameSet.insert {}
  let mut todo := roots
  let mut fuel := env.header.moduleNames.size + 1
  while fuel > 0 && !todo.isEmpty do
    fuel := fuel - 1
    let mut next := []
    for m in todo do
      if let some i := env.getModuleIdx? m then
        for imp in (env.header.moduleData[i.toNat]?.map (·.imports)).getD #[] do
          unless seen.contains imp.module do
            seen := seen.insert imp.module
            next := imp.module :: next
    todo := next
  let mut out := #[]
  for i in [0:env.header.moduleNames.size] do
    if let some m := env.header.moduleNames[i]? then
      if seen.contains m then out := out.push (i, m)
  return out

/-- The C file of module `m` in the first of `dirs` that has one. -/
def cFile? (dirs : List System.FilePath) (m : Name) : IO (Option System.FilePath) := do
  let rel := System.mkFilePath (m.components.map (·.toString (escape := false))) |>.addExtension "c"
  for d in dirs do
    if ← (d / rel).pathExists then return some (d / rel)
  return none

/-- Start-time constants of `mods` in start order, unmapped symbols, non-toolchain modules with no C file, C count. -/
def startConsts (env : Environment) (mods : Array (Nat × Name)) (dirs : List System.FilePath) :
    IO (Array Name × Array String × Array String × Nat) := do
  let lib ← getLibDir (← findSysroot)
  let mut names := #[]
  let mut unmapped := #[]
  let mut noC := #[]
  let mut nmods := 0
  for (i, m) in mods do
    let some c ← cFile? dirs m | do
      unless Fw.Lint.InitCost.underDir lib (← findOLean m) do noC := noC.push m.toString
      continue
    nmods := nmods + 1
    let mut stems : Std.HashMap String Name := {}
    for d in IR.declMapExt.getModuleEntries env i do
      if let .fdecl f xs .. := d then
        if xs.isEmpty && env.contains f then stems := stems.insert (getSymbolStem env f) f
    for l in ← IO.FS.lines c do
      if let some s := Fw.Lint.InitCost.initStem? l then
        match stems[s]? with
        | some f => names := names.push f
        | none => unmapped := unmapped.push s
  return (names, unmapped, noC, nmods)

def chunks {α : Type} (f : Nat) (xs : List α) : List (List α) :=
  if _h : 0 < f ∧ xs ≠ [] then xs.take f :: chunks f (xs.drop f) else []
termination_by xs.length
decreasing_by
  have := List.length_pos_iff.mpr _h.2
  simp only [List.length_drop]
  omega

#guard chunks 2 [1, 2, 3, 4, 5] == [[1, 2], [3, 4], [5]]
#guard chunks 2 [1, 2, 3, 4] == [[1, 2], [3, 4]]
#guard chunks 3 ([] : List Nat) == []
#guard chunks 0 [1, 2] == []

theorem chunks_zero {α : Type} (xs : List α) : chunks 0 xs = [] := by
  rw [chunks]; simp

theorem chunks_nil {α : Type} (f : Nat) : chunks f ([] : List α) = [] := by
  rw [chunks]; simp

theorem flatten_chunks {α : Type} {f : Nat} (hf : 0 < f) (xs : List α) : (chunks f xs).flatten = xs := by
  fun_induction chunks f xs with
  | case1 xs h ih => simp [ih, List.take_append_drop]
  | case2 xs h => cases xs <;> simp_all

theorem length_le_of_mem_chunks {α : Type} {f : Nat} {xs : List α} {c : List α} (h : c ∈ chunks f xs) :
    c.length ≤ f := by
  fun_induction chunks f xs with
  | case1 xs _ ih =>
    rcases List.mem_cons.mp h with rfl | h
    · exact List.length_take_le _ _
    · exact ih h
  | case2 => simp at h

theorem two_mul_length_chunks_le {α : Type} {f : Nat} (hf : 1 < f) (xs : List α) :
    2 * (chunks f xs).length ≤ xs.length + 1 := by
  fun_induction chunks f xs with
  | case1 xs h ih =>
    have := List.length_pos_iff.mpr h.2
    by_cases hl : xs.length ≤ f
    · simp only [List.length_cons, List.drop_eq_nil_of_le hl, chunks_nil, List.length_nil]
      omega
    · simp only [List.length_cons, List.length_drop] at ih ⊢
      omega
  | case2 => simp

theorem length_chunks_lt {α : Type} {f : Nat} (hf : 1 < f) {xs : List α} (hx : 1 < xs.length) :
    (chunks f xs).length < xs.length := by
  have := two_mul_length_chunks_le hf xs
  omega

-- The compiler's `simp` pass recurses once per `let` of a definition (src/Lean/Compiler/LCNF/Simp/Main.lean:218,258
-- @eb6cafb) up to a depth of at least 8192 (src/Lean/Compiler/LCNF/Main.lean:122@eb6cafb), and a list literal of `n`
-- rows takes about 5 lets per row (measured boundary 1637/1638).
def fanOut : Nat := 256

def addListTree (base : Name) (ty : Expr) (xs : List Expr) : TermElabM Unit := do
  let listTy := mkApp (mkConst ``List [.zero]) ty
  let add (n : Name) (v : Expr) : TermElabM Expr := do
    addAndCompile (.defnDecl (mkDefinitionValEx n [] listTy v .opaque .safe [n]))
    return mkConst n
  let mut level ← (chunks fanOut xs).mapIdxM fun k c => do
    add (base ++ .mkSimple s!"leaf{k}") (← mkListLit ty c)
  let mut depth := 0
  while 1 < level.length do
    depth := depth + 1
    level ← (chunks fanOut level).mapIdxM fun k c => do
      add (base ++ .mkSimple s!"node{depth}_{k}") (mkApp2 (mkConst ``List.flatten [.zero]) ty (← mkListLit listTy c))
  discard <| add base (level.head?.getD (mkApp (mkConst ``List.nil [.zero]) ty))

def addProbe (i : Nat) (c : Name) : TermElabM Expr := do
  let get := Name.mkSimple s!"initCostGet{i}"
  let some ci := (← getEnv).find? c | throwError "init-cost: no constant {c}"
  let cv := Expr.const c (ci.levelParams.map fun _ => Level.zero)
  let ty ← inferType cv
  unless (← getLevel ty) == .succ .zero do throwError "init-cost: {c} is not in Type, so it cannot be measured"
  let u := Level.zero
  let natTy := mkConst ``Nat
  let pairTy := mkApp2 (.const ``Prod [u, .zero]) ty natTy
  let body := Expr.lam `n natTy (mkApp4 (.const ``Prod.mk [u, .zero]) ty natTy cv (.bvar 0)) .default
  addAndCompile (.defnDecl (mkDefinitionValEx get [] (← mkArrow natTy pairTy) body .opaque .safe [get]))
  return mkApp2 (mkConst ``Fw.Lint.InitCost.allocs) ty (mkConst get)

/-- Measures the start-time constants of the modules `roots` reach and reports; a project module with no C file is a
finding. -/
def scan (roots : List Name) (irDirs : List System.FilePath) : CommandElabM Unit := do
  let env ← getEnv
  let (names, unmapped, noC, nmods) ← (startConsts env (closure env roots) irDirs : IO _)
  if nmods == 0 then throwError "init-cost: no C file of {roots} in {irDirs}"
  liftTermElabM do
    let strTy := mkConst ``String
    let rowTy := mkApp2 (mkConst ``Prod [.zero, .zero]) strTy (mkApp (mkConst ``BaseIO) (mkConst ``Nat))
    let mut rows := #[]
    for h : i in [0:names.size] do
      let p ← addProbe i names[i]
      rows := rows.push (mkApp4 (mkConst ``Prod.mk [.zero, .zero]) strTy (mkApp (mkConst ``BaseIO) (mkConst ``Nat))
        (mkStrLit names[i].toString) p)
    addListTree `initCostRows rowTy rows.toList
    addListTree `initCostUnmapped strTy (unmapped.toList.map mkStrLit)
    addListTree `initCostNoC strTy (noC.toList.map mkStrLit)
  logInfo m!"init-cost: {names.size} constants in {nmods} modules with C files"
  elabCommand (← `(#eval Fw.Lint.InitCost.report $(mkIdent `initCostNoC) $(mkIdent `initCostUnmapped)
    $(mkIdent `initCostRows)))

end Fw.Lint.InitCostScan
