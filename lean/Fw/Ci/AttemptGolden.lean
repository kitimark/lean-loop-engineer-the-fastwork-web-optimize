import Lean.Data.Json
import Fw.Ci.Attempt

/-!
# Golden vectors of the in-flight freshness and `uncovered` exit rules (task `gh-budget-fresh-inflight`)

`packages/gh-budget/src/inflight.ts` is replayed against these lines; the rules are `Fw.Ci.Attempt.trusted` and
`Fw.Ci.Attempt.uncoveredExit`. Regenerate: `#eval Fw.Ci.AttemptGolden.gen []` run from `lean/`
(`lake env lean --stdin` after `import Fw.Ci.AttemptGolden`).
-/
namespace Fw.Ci.AttemptGolden

open Lean Fw.Ci.Attempt

/-- `(name, completed, read, now)`: a cached row read at `read`, asked at `now`. -/
def trustCases : List (String × Bool × Nat × Nat) := [
  ("finished row read 30 s ago is shared", true, 100, 130),
  ("finished row read 31 s ago is read again", true, 100, 131),
  ("queued row read at once is trusted", false, 100, 100),
  ("queued row read 300 s ago is trusted", false, 100, 400),
  ("queued row read 301 s ago is read again", false, 100, 401),
  ("in-progress row read hours ago is read again", false, 100, 100 + 4 * 3600)]

/-- `(name, incidents)`: `uncovered` incidents of one run since the wait began. -/
def uncoveredCases : List (String × Nat) := [
  ("no incident keeps waiting", 0), ("one incident keeps waiting", 1), ("a repeated incident ends the wait", 2),
  ("many incidents end the wait", 9)]

def goldenText (_ : Unit := ()) : String :=
  String.join (trustCases.map fun (n, c, r, t) =>
    (Json.mkObj [("kind", "trusted"), ("name", n), ("completed", c), ("read", r), ("now", t), ("trusted", trusted c r t)]).compress ++ "\n") ++
  String.join (uncoveredCases.map fun (n, k) =>
    (Json.mkObj [("kind", "uncovered"), ("name", n), ("incidents", k), ("exit", uncoveredExit k), ("code", uncoveredCode)]).compress ++ "\n")

/-- Write the golden file, or with `--check` fail when it differs. -/
def gen (args : List String) : IO Unit := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "attempt-inflight.jsonl"
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != goldenText () then
      throw (IO.userError s!"attempt-inflight golden: {p} is stale; regenerate with Fw.Ci.AttemptGolden.gen []")
    IO.println "attempt-inflight golden: up to date"
  else
    IO.FS.writeFile p (goldenText ())

end Fw.Ci.AttemptGolden
