import Fw.Ops.Wire
import Fw.Console.Review
/-!
# JSON for the review queue (`console.review`)

| op | request | reply |
|---|---|---|
| `console.review` | `looks`? [{flag, date, words}] (default `Fw.Preset.Gen.lookDecisions`), `steps` [{id, answer?}] (the board steps), `answer`? {flag, word} | `items` [{flag, step, date, words, state (open, keep, reject), post, title, body, audience}], `open`, `options`, `answer` (null, or {ok, reason?, step?, word?}) (`Fw.Console.Review`) |
-/
namespace Fw.Wire.Review
open Lean Fw.Wire.Ops Fw.Console.Review
open Fw.Preset (Flag)

/-- The flag a key `part:variant` names. -/
def flagOf (k : String) : Except String Flag :=
  match k.splitOn ":" with
  | p :: v :: rest => if p.isEmpty then .error s!"bad flag {k}" else .ok ⟨p, ":".intercalate (v :: rest)⟩
  | _ => .error s!"bad flag {k}"

/-- The decision rows of a request. -/
def rows (req : Json) : Except String (List Fw.Console.Review.Row) :=
  match opt req "looks" with
  | none => pure Fw.Preset.Gen.lookDecisions
  | some _ => do
    (← arrD req "looks").mapM fun l => do
      pure (← flagOf (← str l "flag"), ← str l "date", ← str l "words")

/-- The board steps of a request. -/
def recs (req : Json) : Except String (List Rec) := do
  (← arrD req "steps").mapM fun s => do
    pure ({ id := ← str s "id", answer := (match opt s "answer" with | some (.str a) => some a | _ => none) } : Rec)

/-- The state word of an item. -/
def stateWord : Option Verdict → String
  | none => "open"
  | some v => v.word

/-- An item as JSON. -/
def itemJson (rs : List Rec) (i : Item) : Json :=
  Json.mkObj [("flag", .str i.flag.key), ("step", .str i.step), ("date", .str i.date), ("words", .str i.words),
    ("state", .str (stateWord i.state)), ("post", .bool (needsPost rs i.flag)), ("title", .str (title i.flag)),
    ("body", .str (body i)), ("audience", .str audience.name)]

/-- `console.review` (`Fw.Console.Review.items`, `accept`). -/
def opReview (req : Json) : Except String Reply := do
  let ds ← rows req
  let rs ← recs req
  let ans ← (match opt req "answer" with
    | none => pure Json.null
    | some a => do
      let f ← flagOf (← str a "flag")
      let w ← str a "word"
      pure (match accept ds rs f w with
        | .ok v => Json.mkObj [("ok", .bool true), ("step", .str (stepId f)), ("word", .str v.word)]
        | .error e => Json.mkObj [("ok", .bool false), ("reason", .str e)]))
  pure [("items", .arr ((items ds rs).map (itemJson rs)).toArray),
    ("open", toJson (openItems ds rs).length),
    ("options", .arr #[.str Verdict.keep.word, .str Verdict.reject.word]),
    ("answer", ans)]

end Fw.Wire.Review
