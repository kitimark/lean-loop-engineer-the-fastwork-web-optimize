import Fw.Measure.WktrVariance
import Lean.Data.Json
/-!
# Golden vectors of the WKTR variance verdict (task `wktr-serial-baseline`)

`packages/contracts/golden/measure/wktr.variance.jsonl`, one JSON object per line, `kind` says which:

* `diffCase`: two class-kind tables and the keys `Fw.Measure.WktrVariance.differs` returns (sorted, once each).
* `findingsCase`: serial runs (id and table), a baseline and a candidate run, the `rivals` ids (the runs of the set with the id of neither side), their
  distinct count `nBaselines`, the `varying` keys among the rivals, the `findings` and the `claim` verdict.
* `typeOfCase`: a key and `typeOf` of it (a descriptive label; no verdict uses it).
* `pairCase`: runs and `pairDiffs`.
* `overlapCase`, `rangeCase`: the timing-range rules.

`packages/measure-wktr/fixtures/variance.mjs` is tested against them (`test/variance.test.mjs`).

```
cd lean && lake env lean --run scripts/WktrVarianceGolden.lean           # write the file
cd lean && lake env lean --run scripts/WktrVarianceGolden.lean --check   # fail if it is stale
```
-/
namespace Fw.Wire.WktrVariance.Golden
open Lean Fw.Measure.WktrLayout Fw.Measure.WktrVariance

def kindName : Kind → String
  | .det => "deterministic"
  | .stable => "stable"
  | .quar => "quarantined"

def tableJson (t : Table) : Json := Json.mkObj (t.map fun (k, v) => (k, Json.str (kindName v)))

def sortUniq (l : List String) : List String := (l.eraseDups.toArray.qsort (· < ·)).toList

def strs (l : List String) : Json := Json.arr (l.map Json.str).toArray

def verdictName : Verdict → String
  | .measured => "measured"
  | .unexplained => "unexplained"
  | .noBaseline => "noBaseline"

private def t1 : Table := [("a", .det), ("b", .stable), ("c", .quar)]
private def t2 : Table := [("a", .det), ("b", .quar), ("c", .quar), ("d", .det)]
private def t3 : Table := [("a", .det), ("b", .quar), ("c", .stable)]
private def t4 : Table := [("a", .stable), ("b", .stable), ("c", .quar), ("e", .det)]

def tables : List (String × Table) := [("t1", t1), ("t2", t2), ("t3", t3), ("t4", t4), ("empty", [])]

def diffCases : List Json :=
  (tables.flatMap fun (n, a) => tables.map fun (m, b) => (n, a, m, b)).map fun (n, a, m, b) =>
    Json.mkObj [("kind", Json.str "diffCase"), ("name", Json.str s!"{n}-{m}"), ("a", tableJson a), ("b", tableJson b),
      ("differs", strs (sortUniq (differs a b)))]

def runJson (r : Run) : Json := Json.mkObj [("id", (r.1 : Json)), ("table", tableJson r.2)]

def findingsCases : List Json :=
  let sets : List (String × List Run) :=
    [("none", []), ("one", [(1, t1)]), ("t1t2", [(1, t1), (2, t2)]), ("t1t2t3", [(1, t1), (2, t2), (3, t3)]),
     ("dup", [(1, t1), (1, t1)]), ("twin", [(1, t1), (9, t1)]), ("selfIn", [(10, t1), (11, t2), (12, t3)])]
  let pairs : List (String × Run × Run) :=
    [("a", (10, t1), (11, t2)), ("b", (10, t1), (12, t3)), ("c", (10, t1), (13, t4)), ("d", (20, t2), (13, t4))]
  (sets.flatMap fun (sn, rs) => pairs.map fun (pn, b, c) => (sn, rs, pn, b, c)).map fun (sn, rs, pn, b, c) =>
    let rv := rivals b c rs
    Json.mkObj [("kind", Json.str "findingsCase"), ("name", Json.str s!"{sn}-{pn}"), ("runs", Json.arr (rs.map runJson).toArray),
      ("base", runJson b), ("cand", runJson c), ("rivals", Json.arr (rv.map fun r => (r.1 : Json)).toArray),
      ("nBaselines", (nBaselines rv : Json)), ("varying", strs (sortUniq (varying (rv.map Prod.snd)))),
      ("findings", strs (sortUniq (findings b.2 c.2 (rv.map Prod.snd)))), ("claim", Json.str (verdictName (claim b c rs)))]

def typeOfCases : List Json :=
  ["control-f1/live/layoutUpdates", "a/live-trace/renderingUpdates", "x", "a/b"].map fun k =>
    Json.mkObj [("kind", Json.str "typeOfCase"), ("key", Json.str k), ("type", Json.str (typeOf k))]

def pairCases : List Json :=
  [[], [t1], [t1, t2], [t1, t2, t3], [t1, t2, t3, t4]].map fun rs =>
    Json.mkObj [("kind", Json.str "pairCase"), ("runs", Json.arr (rs.map tableJson).toArray),
      ("pairDiffs", Json.arr ((pairDiffs rs).map fun (n : Nat) => (n : Json)).toArray)]

def overlapCases : List Json :=
  ([((687, 874), (572, 976)), ((1, 2), (3, 4)), ((3, 4), (1, 2)), ((1, 3), (3, 5)), ((5, 5), (5, 5)), ((0, 0), (1, 1)), ((2, 1), (1, 2))] :
      List ((Nat × Nat) × (Nat × Nat))).map fun (a, b) =>
    Json.mkObj [("kind", Json.str "overlapCase"), ("a", Json.arr #[(a.1 : Json), (a.2 : Json)]),
      ("b", Json.arr #[(b.1 : Json), (b.2 : Json)]), ("overlap", Json.bool (overlap a b))]

def rangeCases : List Json :=
  ([[], [7], [3, 1, 2], [976, 735, 572]] : List (List Nat)).map fun xs =>
    Json.mkObj [("kind", Json.str "rangeCase"), ("xs", Json.arr (xs.map fun (n : Nat) => (n : Json)).toArray),
      ("range", match rangeOf xs with
        | some (l, h) => Json.arr #[(l : Json), (h : Json)]
        | none => Json.null)]

/-- The lines of the file. -/
def cases : List Json := diffCases ++ findingsCases ++ typeOfCases ++ pairCases ++ overlapCases ++ rangeCases

def text : String := String.join (cases.map fun j => j.compress ++ "\n")

def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "measure"

/-- Compare (or write) the file; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / dir
  let p := d / "wktr.variance.jsonl"
  if write then
    IO.FS.createDirAll d
    IO.FS.writeFile p text
    IO.println s!"wktr-variance golden: {cases.length} lines written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != text then
    IO.println s!"wktr-variance golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/WktrVarianceGolden.lean)"
    return 1
  IO.println s!"wktr-variance golden: {cases.length} lines, 0 stale"
  return 0

end Fw.Wire.WktrVariance.Golden
