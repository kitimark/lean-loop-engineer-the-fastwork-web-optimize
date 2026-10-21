import Fw.Ops.Wire
import Fw.Console.ReviewFeedback
/-!
# JSON for the feedback threads (`console.reviewFeedback`)

| op | request | reply |
|---|---|---|
| `console.reviewFeedback` | `events` [{type, flag, id (a `review.feedback`) or to (a `review.feedback.reply`), text, ts}] in log order (events of other types are ignored), `flag`? | `threads` [{flag, open, comments [{id, text, at, status (open, answered), reply (null or {text, at})}]}], one per flag in the order of its first comment; with `flag` only that flag's thread (an empty one when it has no comment) |

The thread is `Fw.Console.ReviewFeedback.thread`: the same refusal rules as the reducer, so an event the reducer would have refused
changes nothing here either.
-/
namespace Fw.Wire.ReviewFeedback
open Lean Fw.Wire.Ops Fw.Console.ReviewFeedback

/-- Read one event of the log (`none` for any other type). -/
def evOf (j : Json) : Except String (Option Ev) := do
  match ← str j "type" with
  | "review.feedback" => pure (some (.post (← str j "flag") (← str j "id") (← str j "text") (← nat j "ts")))
  | "review.feedback.reply" => pure (some (.reply (← str j "flag") (← str j "to") (← str j "text") (← nat j "ts")))
  | _ => pure none

/-- The flags of a thread list, each once, in the order of the first comment. -/
def flagsOf (fs : List Fb) : List String :=
  fs.foldl (fun acc f => if acc.contains f.flag then acc else acc ++ [f.flag]) []

/-- One comment as JSON. -/
def commentJson (f : Fb) : Json :=
  Json.mkObj [("id", .str f.id), ("text", .str f.text), ("at", toJson (f.postedAt)), ("status", .str f.status),
    ("reply", match f.reply with
      | none => Json.null
      | some (t, at_) => Json.mkObj [("text", .str t), ("at", toJson (at_))])]

/-- The thread of one flag as JSON. -/
def threadJson (fs : List Fb) (flag : String) : Json :=
  let cs := fs.filter (·.flag == flag)
  Json.mkObj [("flag", .str flag), ("open", toJson ((openOf fs flag).length)),
    ("comments", .arr (cs.map commentJson).toArray)]

/-- `console.reviewFeedback` (`Fw.Console.ReviewFeedback.thread`). -/
def opReviewFeedback (req : Json) : Except String Reply := do
  let evs := (← (← arrD req "events").mapM evOf).filterMap id
  let fs := thread evs
  let flags ← match opt req "flag" with
    | none => pure (flagsOf fs)
    | some _ => pure [← str req "flag"]
  pure [("threads", .arr (flags.map (threadJson fs)).toArray)]

end Fw.Wire.ReviewFeedback
