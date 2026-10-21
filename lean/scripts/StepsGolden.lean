import Lean.Data.Json
import Fw.Ci.Steps

/-! Write (or with `--check`, verify) `packages/contracts/golden/ci/steps.jsonl` (Fw.Ci.Steps): the allowlist rows, the
step labels, the lint cases and the flagged jobs. Consumer: `scripts/ci-steps-lint.mjs`, replayed by
`scripts/ci-steps-lint.test.mjs`. Run from `lean/`: `lake env lean --run scripts/StepsGolden.lean [--check]`. -/

open Lean Fw.Ci.Steps

def strs (l : List String) : Json := .arr (l.map Json.str).toArray

def opt (o : Option String) : Json := match o with | some s => .str s | none => .null

def kindName : Kind → String
  | .collect => "collect" | .hostState => "hostState" | .teardown => "teardown" | .upload => "upload"
  | .telemetry => "telemetry"

def condName : Cond → String
  | .notCancelled => "notCancelled" | .always => "always" | .failure => "failure"

def obsJson (o : Obs) : Json :=
  Json.mkObj [("label", .str o.label), ("ifText", opt o.ifText), ("timeout", opt o.timeout)]

def postJson (p : Post) : Json :=
  Json.mkObj [("label", .str p.label), ("kind", .str (kindName p.kind)), ("cond", .str (condName p.cond)),
    ("ifText", .str p.cond.text)]

def rowJson (r : Row) : Json :=
  Json.mkObj [("kind", "row"), ("file", .str r.file), ("job", .str r.job), ("measure", .str r.measure),
    ("post", .arr (r.post.map postJson).toArray), ("teardown", .bool r.hasTeardown)]

def condJson (c : Cond) : Json :=
  Json.mkObj [("kind", "cond"), ("cond", .str (condName c)), ("ifText", .str c.text),
    ("runsOnSuccess", .bool (c.runs .success)), ("runsOnFailure", .bool (c.runs .failure)),
    ("runsOnCancel", .bool (c.runs .cancelled))]

def labelCases : List (String × Option String × Option String) := [
  ("a named step", some "Boot the Simulator (kept booted for the whole job)", none),
  ("a named step that also uses an action", some "The rewrite build (site job)", some "actions/download-artifact@9000827ccba6bdab643e8b6fd33ac0654aef8333"),
  ("an action pinned by sha", none, some "actions/upload-artifact@cf430e030ddbb5b0abf93d22962f4752f3646cd9"),
  ("a local action", none, some "./.github/actions/telemetry"),
  ("a step with neither", none, none)]

def pre : List Obs := [⟨"tip re-check", none, none⟩, ⟨"actions/checkout", none, none⟩]

def steps (r : Row) (post : List Obs) : List Obs := pre ++ [⟨r.measure, none, none⟩] ++ post

def exact (r : Row) : List Obs := r.post.map Post.expected

def sim : Row := (rows.head?.getD ⟨"", "", "", []⟩)
def wktr : Row := ((rows.drop 1).head?.getD ⟨"", "", "", []⟩)

def ob (l : String) (c : Option Cond) (t : Option String := none) : Obs := ⟨l, c.map Cond.text, t⟩

/-- Lint cases: (name, row, observed steps). -/
def cases : List (String × Row × List Obs) :=
  let hostOk := ob "Host state on failure" (some .failure)
  let keepOk := ob "Keep logs" (some .notCancelled)
  let upOk := ob uploadLabel (some .notCancelled)
  let telOk := ob "./.github/actions/telemetry" (some .always)
  [("webkit-sim: the allowed steps, nothing else", sim, steps sim (exact sim)),
   ("webkit-sim: the old Simulator shutdown step comes back", sim,
     steps sim [keepOk, hostOk, ob "Shut down and delete the Simulator" (some .notCancelled) (some "3"), upOk, telOk]),
   ("webkit-sim: the host state step runs on success too", sim,
     steps sim [keepOk, ob "Host state on failure" (some .notCancelled), upOk, telOk]),
   ("webkit-sim: the old Keep-logs timeout of 3 minutes", sim,
     steps sim [ob "Keep logs" (some .notCancelled) (some "3"), hostOk, upOk, telOk]),
   ("webkit-sim: the host state step has a timeout", sim,
     steps sim [keepOk, ob "Host state on failure" (some .failure) (some "3"), upOk, telOk]),
   ("webkit-sim: the upload only runs on success()", sim, steps sim [keepOk, hostOk, ⟨uploadLabel, none, none⟩, telOk]),
   ("webkit-sim: the upload is missing", sim, steps sim [keepOk, hostOk, telOk]),
   ("webkit-sim: the copy step is missing", sim, steps sim [hostOk, upOk, telOk]),
   ("webkit-sim: the upload runs before the copy", sim, steps sim [upOk, keepOk, hostOk, telOk]),
   ("webkit-sim: a step is added after the telemetry", sim, steps sim (exact sim ++ [ob "Clean up" (some .always)])),
   ("webkit-sim: no steps after the measurement step", sim, steps sim []),
   ("webkit-sim: the measurement step is gone", sim, pre),
   ("webkit-sim: the measurement step occurs twice", sim, steps sim (exact sim) ++ [⟨sim.measure, none, none⟩]),
   ("wktr: the allowed steps, nothing else", wktr, steps wktr (exact wktr)),
   ("wktr: the upload runs only when not cancelled", wktr,
     steps wktr [ob "Delete the Simulator device" (some .always), ob uploadLabel (some .notCancelled)])]

def covCases : List (String × String × List String) := [
  ("webkit-sim: its one macOS job", "webkit-sim.yml", ["sim"]),
  ("webkit-sim: a second macOS job without a row", "webkit-sim.yml", ["sim", "probe"]),
  ("webkit-sim: the macOS job is gone", "webkit-sim.yml", []),
  ("a file with no row has no macOS job", "lean.yml", []),
  ("a file with no row gains a macOS job", "lean.yml", ["build"]),
  ("gate-gaps: its one macOS job", "gate-gaps.yml", ["collect-macos"])]

def line (j : Json) : String := j.compress ++ "\n"

def text : String :=
  String.join (rows.map (line ∘ rowJson))
    ++ String.join ([Cond.notCancelled, .always, .failure].map (line ∘ condJson))
    ++ String.join (labelCases.map fun (n, nm, us) =>
      line (Json.mkObj [("kind", "label"), ("name", .str n), ("stepName", opt nm), ("uses", opt us),
        ("label", .str (labelOf nm us))]))
    ++ String.join (cases.map fun (n, r, os) =>
      line (Json.mkObj [("kind", "case"), ("name", .str n), ("file", .str r.file), ("job", .str r.job),
        ("steps", .arr (os.map obsJson).toArray), ("problems", strs (checkJob r os))]))
    ++ String.join (covCases.map fun (n, f, found) =>
      line (Json.mkObj [("kind", "coverage"), ("name", .str n), ("file", .str f), ("found", strs found),
        ("problems", strs (coverage f found))]))
    ++ line (Json.mkObj [("kind", "flagged"), ("jobs", strs flagged)])

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "steps.jsonl"
  let n := (text.splitOn "\n").length - 1
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"steps golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/StepsGolden.lean)"
      return 1
    IO.println s!"steps golden: {n} lines, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"steps golden: {n} lines written"
  return 0
