import Lean.Data.Json
import Fw.Ops.Wire
/-!
# `Fw.Obs.Push`: which console events `fw watch --stream` pushes to the lead

An event the user causes in the console (a question or comment, an answer to a step, done, cancel) is printed as one line
the moment it is appended. Everything else (hook and script events, the user's `step.start` and `review.previewed`) is not.
The stream asks `obs.push` with the type and actor of each new event; the golden file `golden/obs/push.jsonl` pins the rows.
-/
namespace Fw.Obs.Push

/-- The event types a user causes that the lead must see. -/
def types : List String := ["review.feedback", "step.answer", "step.done", "step.cancel"]

/-- **Lead-facing**: the actor is `user` and the type is one of `types`. -/
def leadFacing (type actor : String) : Bool := actor == "user" && types.contains type

/-- A hook or script event is never lead-facing. -/
theorem not_user (type actor : String) (h : actor ≠ "user") : leadFacing type actor = false := by
  simp [leadFacing, h]

/-- A question or comment (`review.feedback`) by the user is lead-facing. -/
theorem feedback : leadFacing "review.feedback" "user" = true := by decide

/-- A step answer by the user is lead-facing. -/
theorem answer : leadFacing "step.answer" "user" = true := by decide

/-- A step done by the user is lead-facing. -/
theorem done : leadFacing "step.done" "user" = true := by decide

/-- A step cancel by the user is lead-facing. -/
theorem cancel : leadFacing "step.cancel" "user" = true := by decide

/-- A user event of any other type (`step.start`, `review.previewed`, ...) is not lead-facing. -/
theorem other_type (type : String) (h : type ∉ types) : leadFacing type "user" = false := by
  simp [leadFacing, h]

/-- Lead-facing exactly when the actor is `user` and the type is listed. -/
theorem leadFacing_iff (type actor : String) : leadFacing type actor = true ↔ actor = "user" ∧ type ∈ types := by
  simp [leadFacing]

/-! ## Golden rows -/

/-- Golden cases: name, type, actor. -/
def cases : List (String × String × String) := [
  ("user question or comment", "review.feedback", "user"),
  ("user step answer", "step.answer", "user"),
  ("user step done", "step.done", "user"),
  ("user step cancel", "step.cancel", "user"),
  ("user step start is not pushed", "step.start", "user"),
  ("user preview is not pushed", "review.previewed", "user"),
  ("lead reply is not pushed", "review.feedback.reply", "lead"),
  ("lead feedback event is not pushed", "review.feedback", "lead"),
  ("hook spawn is not pushed", "agent.spawn", "hook"),
  ("script step done is not pushed", "step.done", "script"),
  ("hook step answer is not pushed", "step.answer", "hook")]

end Fw.Obs.Push

namespace Fw.Wire.Obs.Push
open Lean
open Fw.Wire.Ops (Reply str arr)

/-- `obs.push`: request `{events: [{type, actor}]}`, reply `{push: [bool]}` in input order. -/
def opPush (req : Json) : Except String Reply := do
  let evs ← arr req "events"
  let bs ← evs.toList.mapM fun e => do
    pure (Fw.Obs.Push.leadFacing (← str e "type") (← str e "actor"))
  pure [("push", .arr (bs.toArray.map .bool))]

/-- The text of the golden file `golden/obs/push.jsonl`. -/
def goldenText : String :=
  String.join (Fw.Obs.Push.cases.map fun (n, t, a) =>
    (Json.mkObj [("name", .str n),
      ("request", Json.mkObj [("op", .str "obs.push"), ("events", .arr #[Json.mkObj [("type", .str t), ("actor", .str a)]])]),
      ("response", Json.mkObj [("push", .arr #[.bool (Fw.Obs.Push.leadFacing t a)])])]).compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "push.jsonl"

end Fw.Wire.Obs.Push
