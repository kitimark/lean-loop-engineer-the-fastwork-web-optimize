import Lean.Data.Json
/-!
# Which literal millisecond numbers in land-selected tests the lint refuses

Task `land-wallclock-off-gate` (automate-me candidate 6). A test the land runs must not fail because the machine is
loaded, so an absolute wall-clock bound in it is a land refusal waiting for load. The lint `scripts/lint-wallclock.mjs`
finds literal numbers in a test file, classifies each by the syntactic site it sits in (the lexing is glue), and asks
this module whether the number is a bound and whether it is refused.

* A **bound** is a literal `n > 0` at a site that limits how long something may take: an assertion upper bound, a
  `timeout` option, a hard-coded call deadline, a comparison of an elapsed time against a literal.
* A **loop cap** (a counted `for` loop around a sleep, as in `for (i < 100) { await wait(100) }`) limits the poll to
  `count × sleep` milliseconds, so it is a bound too.
* A **sleep** (`setTimeout(r, 50)`, `wait(300)`) waits and limits nothing; it is never refused.
* A bound is allowed only with a non-empty written reason (the allowlist `scripts/wallclock-allow.json`).

Golden vectors: `packages/contracts/golden/console/wallclock.jsonl` (`goldenText`, op `wallclock.verdict`). The lint's
test replays them. TS side: `scripts/lint-wallclock.mjs` is glue plus this decision, checked against the golden.

**Listed TS stand-in (follow-up task `wallclock-lint-lean`):** which site a literal sits in (the line regexes), how an
allow entry matches a line, and the stale-entry rule are TS only and not yet specified here. Only the decision on a
classified literal (`isBound`, `reasonOk`, `refuse`) is Lean.
-/
namespace Fw.Console.WallClock
open Lean

/-- The syntactic site of a literal: an assertion upper bound, a timeout option, a hard-coded deadline argument, an
elapsed-time comparison, a loop cap, a sleep delay, or anything else. -/
inductive Site | assertLt | timeoutOpt | deadlineArg | elapsedCmp | loopCap | sleep | other
  deriving DecidableEq, Repr

/-- The site's name in the golden and in the lint. -/
def Site.name : Site → String
  | .assertLt => "assertLt" | .timeoutOpt => "timeoutOpt" | .deadlineArg => "deadlineArg"
  | .elapsedCmp => "elapsedCmp" | .loopCap => "loopCap" | .sleep => "sleep" | .other => "other"

/-- Does the site limit how long something may take? -/
def Site.limits : Site → Bool
  | .assertLt | .timeoutOpt | .deadlineArg | .elapsedCmp | .loopCap => true
  | .sleep | .other => false

/-- A literal is a wall-clock bound. -/
def isBound (s : Site) (n : Nat) : Bool := s.limits && decide (0 < n)

/-- A reason counts when it has a character outside the Lean whitespace set, which is exactly the four characters space
(U+0020), tab (U+0009), carriage return (U+000D) and line feed (U+000A); a vertical tab or a no-break space is not
whitespace. -/
def reasonOk (r : String) : Bool := r.toList.any fun c => !c.isWhitespace

/-- The lint refuses a literal that is a bound and carries no reason. -/
def refuse (s : Site) (n : Nat) (r : String) : Bool := isBound s n && !reasonOk r

/-- Sleeps and other numbers are never refused. -/
theorem refuse_not_limits (s : Site) (n : Nat) (r : String) (h : s.limits = false) : refuse s n r = false := by
  simp [refuse, isBound, h]

/-- Zero is never a bound (no limit is set). -/
theorem refuse_zero (s : Site) (r : String) : refuse s 0 r = false := by
  simp [refuse, isBound]

/-- A written reason allows any literal. -/
theorem refuse_reason (s : Site) (n : Nat) (r : String) (h : reasonOk r = true) : refuse s n r = false := by
  simp [refuse, h]

/-- Refusal is exactly "bound without reason" (so a refused literal is a bound). -/
theorem refuse_iff (s : Site) (n : Nat) (r : String) :
    refuse s n r = true ↔ isBound s n = true ∧ reasonOk r = false := by
  simp [refuse]

/-! ## Golden vectors -/

/-- One golden case. -/
def case (name : String) (s : Site) (n : Nat) (r : String) : Json :=
  Json.mkObj [("name", .str name),
    ("request", Json.mkObj [("op", "wallclock.verdict"), ("site", s.name), ("ms", toJson n), ("reason", .str r)]),
    ("response", Json.mkObj [("refuse", .bool (refuse s n r)), ("bound", .bool (isBound s n))])]

/-- The cases: the 20 fixed tuples listed below. -/
def cases : List Json :=
  [case "assert bound, no reason" .assertLt 5000 "", case "assert bound, blank reason" .assertLt 5000 "  ",
   case "assert bound, reason" .assertLt 5000 "ratio of two timed runs",
   case "timeout option, no reason" .timeoutOpt 120000 "", case "timeout option, reason" .timeoutOpt 120000 "generous cap",
   case "deadline arg, no reason" .deadlineArg 150 "", case "deadline arg, reason" .deadlineArg 150 "frozen child never answers",
   case "elapsed comparison, no reason" .elapsedCmp 3000 "", case "elapsed comparison, reason" .elapsedCmp 3000 "x",
   case "sleep, no reason" .sleep 300 "", case "other number" .other 5000 "",
   case "zero assert" .assertLt 0 "", case "zero timeout" .timeoutOpt 0 "", case "one ms assert" .assertLt 1 "",
   case "loop cap, no reason" .loopCap 100 "", case "loop cap, reason" .loopCap 100 "poll count",
   case "reason is a space" .assertLt 5000 " ", case "reason is tab, cr, lf" .assertLt 5000 "\t\r\n",
   case "reason is a vertical tab" .assertLt 5000 "\x0b", case "reason is a no-break space" .assertLt 5000 "\u00a0"]

/-- The golden text. -/
def goldenText : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/wallclock.jsonl"

/-- Write the golden file (IO). -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output? (IO) -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.WallClock
