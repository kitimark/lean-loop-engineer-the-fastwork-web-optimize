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

/-- Adds `initCostGet{i} := fun n => (c, n)` and returns the probe `allocs initCostGet{i}`, which evaluates `c`. -/
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
    addAndCompile (.defnDecl (mkDefinitionValEx `initCostRows [] (mkApp (mkConst ``List [.zero]) rowTy)
      (← mkListLit rowTy rows.toList) .opaque .safe [`initCostRows]))
    addAndCompile (.defnDecl (mkDefinitionValEx `initCostUnmapped [] (mkApp (mkConst ``List [.zero]) strTy)
      (← mkListLit strTy (unmapped.toList.map mkStrLit)) .opaque .safe [`initCostUnmapped]))
    addAndCompile (.defnDecl (mkDefinitionValEx `initCostNoC [] (mkApp (mkConst ``List [.zero]) strTy)
      (← mkListLit strTy (noC.toList.map mkStrLit)) .opaque .safe [`initCostNoC]))
  logInfo m!"init-cost: {names.size} constants in {nmods} modules with C files"
  elabCommand (← `(#eval Fw.Lint.InitCost.report $(mkIdent `initCostNoC) $(mkIdent `initCostUnmapped)
    $(mkIdent `initCostRows)))

end Fw.Lint.InitCostScan
