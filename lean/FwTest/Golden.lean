import Fw
/-!
# Golden JSON-lines round trips

* `golden/console-apply.jsonl`: the console-mvp conformance file (copied verbatim from
  `packages/contracts/golden/`); each case's `request` must give exactly its `response`.
* `golden/wire-requests.txt` → `golden/wire-replies.txt`: one reply line per request line,
  byte for byte (covers every op, the `Rat` wire form, a blank line, bad JSON and a non-object).
-/
namespace FwTest.Golden
open Lean

/-- The `lean/` directory: the test binary lives in `<root>/.lake/build/bin/`. -/
def root : IO System.FilePath := do
  let app ← IO.appPath
  match app.parent >>= (·.parent) >>= (·.parent) >>= (·.parent) with
  | some r => return r
  | none => throw (IO.userError "fwtest: cannot locate the package root")

/-- Lines of a file, without the trailing empty line. -/
def lines (p : System.FilePath) : IO (List String) := do
  let t ← IO.FS.readFile p
  let ls := t.splitOn "\n"
  return if ls.getLast? == some "" then ls.dropLast else ls

/-- Every console-apply golden case through `handleLine`; returns the number of failures. -/
def consoleApply : IO Nat := do
  let ls ← lines ((← root) / "golden" / "console-apply.jsonl")
  let mut bad := 0
  let mut i := 0
  for l in ls do
    i := i + 1
    let ok ← match Json.parse l with
      | .error e => do IO.println s!"console-apply line {i}: {e}"; pure false
      | .ok c =>
        let name := (c.getObjValAs? String "name").toOption.getD "?"
        let req := c.getObjValD "request"
        let want := c.getObjValD "response"
        let line := (Json.mkObj [("id", toJson i), ("op", "console.apply"),
          ("state", req.getObjValD "state"), ("event", req.getObjValD "event")]).compress
        match Json.parse (Fw.Wire.handleLine line) with
        | .error e => do IO.println s!"console-apply {name}: reply is not JSON: {e}"; pure false
        | .ok got =>
          let same := got.getObjValD "id" == toJson i &&
            got.getObjValD "state" == want.getObjValD "state" &&
            got.getObjValD "outcome" == want.getObjValD "outcome" &&
            (got.getObjValD "error") == Json.null
          unless same do
            IO.println s!"console-apply {name}: got {(got.getObjValD "outcome").compress}, want {(want.getObjValD "outcome").compress}"
          pure same
    unless ok do bad := bad + 1
  IO.println s!"console-apply golden: {ls.length - bad}/{ls.length} cases equal"
  return bad

/-- Request lines → reply lines, byte for byte; returns the number of failures. -/
def wire : IO Nat := do
  let r ← root
  let reqs ← lines (r / "golden" / "wire-requests.txt")
  let reps ← lines (r / "golden" / "wire-replies.txt")
  if reqs.length != reps.length then
    IO.println s!"wire golden: {reqs.length} requests but {reps.length} replies"
    return 1
  let mut bad := 0
  for (q, a) in reqs.zip reps do
    let got := Fw.Wire.handleLine q
    if got != a then
      IO.println s!"wire golden: {q}\n  got  {got}\n  want {a}"
      bad := bad + 1
  IO.println s!"wire golden: {reqs.length - bad}/{reqs.length} lines equal"
  return bad

/-- `Rat` wire form round trips (parse ∘ print = id) on a few values, and normalization. -/
def ratRoundTrip : IO Nat := do
  let qs : List Rat := [0, 1, -1, 1 / 70, -3 / 4, 1 / 252, 123456789 / 1000]
  let mut bad := 0
  for q in qs do
    match Fw.Wire.ratOfJson (Fw.Wire.ratToJson q) with
    | .ok q' => if q' != q then bad := bad + 1
    | .error _ => bad := bad + 1
  match Fw.Wire.ratOfJson (Json.mkObj [("num", "2"), ("den", "4")]) with
  | .ok q => if q != 1 / 2 then bad := bad + 1
  | .error _ => bad := bad + 1
  IO.println s!"rat wire form: {bad} failures"
  return bad

end FwTest.Golden
