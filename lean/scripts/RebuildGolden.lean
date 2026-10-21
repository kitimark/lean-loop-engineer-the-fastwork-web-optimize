import Fw.Ops.Rebuild
import Std.Data.HashMap
import Lean.Data.Json

/-! Write (or with `--check`, verify) `packages/contracts/golden/ops/rebuild.jsonl` from the CI and `lake query` facts in
`rebuild-facts.jsonl`; `--check` also fails when a computed rebuild set differs from the modules CI built. -/

open Lean Fw.Ops.Rebuild

/-- A string array field (missing is empty). -/
def strs (j : Json) (k : String) : List String :=
  match j.getObjValAs? (Array String) k with
  | .ok a => a.toList
  | .error _ => []

/-- An array-of-objects field (missing is empty). -/
def objs (j : Json) (k : String) : List Json :=
  match j.getObjValAs? (Array Json) k with
  | .ok a => a.toList
  | .error _ => []

/-- A natural-number field (missing is 0). -/
def natF (j : Json) (k : String) : Nat := (j.getObjValAs? Nat k).toOption.getD 0

/-- `{m, imports}` rows as a module map. -/
def graphOf (rows : List Json) : Std.HashMap String (List String) :=
  rows.foldl (fun g r => g.insert ((r.getObjValAs? String "m").toOption.getD "") (strs r "imports")) {}

/-- The importers map of a module map. -/
def reverseOf (g : Std.HashMap String (List String)) : Std.HashMap String (List String) :=
  g.fold (fun r m is => is.foldl (fun r x => r.insert x (m :: r.getD x [])) r) {}

/-- The graph after the `Fw.Wire.SchedJson` split: `Fw.Wire.Obs` and `Fw.Wire.Sched` import the helper module instead
of `Fw.Wire.Obs` importing `Fw.Wire.Sched`. -/
def split (g : Std.HashMap String (List String)) : Std.HashMap String (List String) :=
  let obs := (g.getD "Fw.Wire.Obs" []).filter (· != "Fw.Wire.Sched")
  ((g.insert "Fw.Wire.Obs" (obs ++ ["Fw.Wire.SchedJson"])).insert "Fw.Wire.Sched"
    (g.getD "Fw.Wire.Sched" [] ++ ["Fw.Wire.SchedJson"])).insert "Fw.Wire.SchedJson" ["Fw.Ops.Wire"]

/-- Sorted strings. -/
def sorted (l : List String) : List String := (l.toArray.qsort (· < ·)).toList

/-- The rebuild set, critical path and `Fw.Wire.Obs` membership of one graph, `none` when a cone does not close. -/
def model (g : Std.HashMap String (List String)) (changed : List String) (t : String → Nat) :
    Option (List String × Nat) := do
  let d := fun m => g.getD m []
  let r := reverseOf g
  let R ← rebuildSet? d (fun x => r.getD x []) (g.size + 1) ["Main"] changed
  pure (sorted R, critical d R t)

/-- The output line of one land, and whether its computed rebuild set equals the modules CI built. -/
def landLine (base : Std.HashMap String (List String)) (j : Json) : Json × Bool :=
  let g0 := (objs j "set").foldl (fun g r => g.insert ((r.getObjValAs? String "m").toOption.getD "") (strs r "imports"))
    base
  let g := (strs j "drop").foldl (fun g m => g.erase m) g0
  let built := (objs j "built").map fun r => ((r.getObjValAs? String "m").toOption.getD "", natF r "ms")
  let t : String → Nat := fun m => (built.lookup m).getD 0
  let ci := sorted (built.map (·.1))
  let legs := (objs j "fwcoreStepS").map (natF · "s")
  let changed := strs j "changed"
  let field (k : String) : Json := (j.getObjVal? k).toOption.getD .null
  match model g changed t, model (split g) changed t with
  | some (R, cp), some (R', cp') =>
    let ok := R == ci
    (Json.mkObj [("run", field "run"), ("land", field "land"), ("changed", toJson changed.length),
      ("rebuilt", toJson R), ("ciBuilt", toJson ci.length), ("match", toJson ok),
      ("criticalMs", toJson cp), ("sumMs", toJson (built.foldl (· + ·.2) 0)),
      ("fwcoreStepS", Json.mkObj [("min", toJson (legs.foldl min (legs.headD 0))), ("max", toJson (maxOf legs))]),
      ("obs", toJson (R.contains "Fw.Wire.Obs")),
      ("split", Json.mkObj [("rebuilt", toJson R'.length), ("obs", toJson (R'.contains "Fw.Wire.Obs")),
        ("criticalMs", toJson cp')])], ok)
  | _, _ => (Json.mkObj [("run", field "run"), ("error", .str "a cone did not close")], false)

/-- Write the golden file, or with `--check` exit 1 when it is stale or a rebuild set differs from CI. -/
def main (args : List String) : IO UInt32 := do
  let dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops"
  let lines := ((← IO.FS.readFile (dir / "rebuild-facts.jsonl")).splitOn "\n").filter (· != "")
  let js := lines.filterMap fun l => (Json.parse l).toOption
  let some hd := js.head? | IO.println "rebuild golden: no facts"; return 1
  let base := graphOf (objs hd "graph")
  let outs := (js.drop 1).map (landLine base)
  let text := String.join (outs.map fun (o, _) => o.compress ++ "\n")
  let bad := outs.filter (!·.2)
  let p := dir / "rebuild.jsonl"
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"rebuild golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/RebuildGolden.lean)"
      return 1
    if !bad.isEmpty then
      IO.println s!"rebuild golden: {bad.length} lands where the Lake-graph rebuild set differs from CI"
      return 1
    IO.println s!"rebuild golden: {outs.length} lands, each rebuild set equals CI, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"rebuild golden: {outs.length} lands written, {bad.length} differ from CI"
  return 0
