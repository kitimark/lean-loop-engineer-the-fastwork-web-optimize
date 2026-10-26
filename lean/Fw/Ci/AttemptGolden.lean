import Lean.Data.Json
import Fw.Ci.Attempt

/-!
# Golden vectors of the in-flight freshness and `uncovered` exit rules (task `gh-budget-fresh-inflight`)

`packages/gh-budget/test/inflight.test.ts` replays these lines against `trustedRow` and `uncoveredExit` in `packages/gh-budget/src/wait.ts`; the rules are `Fw.Ci.Attempt.trusted` and
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

/-- `(name, regAt, times)`: `uncovered` incident times of one run, for a wait that registered at `regAt`. -/
def uncoveredCases : List (String × Nat × List Nat) := [
  ("no incident keeps waiting", 5000, []), ("one incident keeps waiting", 5000, [5000]),
  ("two incidents 567 s apart end the wait", 5000, [4433, 5000]),
  ("incident of the previous slice, one in this one", 5000, [4460, 5001]),
  ("two incidents both before the wait keep waiting", 5000, [4900, 4990]),
  ("old incident beyond the lookback keeps waiting", 5000, [3799, 5000]),
  ("lookback edge counts", 5000, [3800, 5000]),
  ("many incidents end the wait", 5000, [4000, 4500, 5000, 5100])]

def goldenText (_ : Unit := ()) : String :=
  String.join (trustCases.map fun (n, c, r, t) =>
    (Json.mkObj [("kind", "trusted"), ("name", n), ("completed", c), ("read", r), ("now", t), ("trusted", trusted c r t)]).compress ++ "\n") ++
  String.join (uncoveredCases.map fun (n, r, ts) =>
    (Json.mkObj [("kind", "uncovered"), ("name", n), ("regAt", r), ("times", toJson ts), ("lookback", uncoveredLookbackS), ("exit", uncoveredExit r ts), ("code", uncoveredCode)]).compress ++ "\n")

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
