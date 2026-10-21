import Fw.Ops.Wire
import Fw.Wire.Review
import Fw.Console.ReviewPreview
/-!
# JSON for the review preview (`console.reviewPreview`)

| op | request | reply |
|---|---|---|
| `console.reviewPreview` | the rows and steps of `console.review` (`looks`?, `steps`), `events` [{flag, device, key?}] (the accepted `review.previewed` events, any order), `ask`? {flag, view (flag, faithful, compare), width}, `names`? {search, flag} | `items` [{flag, open, desktop, phone, missing [device words], asks [lines]}], `plan` (null without `ask`; else {ok, view, search, arm (r, compare), slot, device, key, event, carries} or {ok false, reason}), `names` (null without `names`; else whether the search names the flag by a whole entry) |

An item counts only the events of its round: those whose `key` names the round tag of the item's step (`Fw.Console.ReviewPreview.roundEventsOf`,
`roundOfKey`). An event without `key` is untagged and counts for the first round only. A `posts` field of an older caller is ignored.

The plan is made only for an open look-change review. `event` is the typed command the console records when the preview opens
(`review.previewed`), with `key` as its idempotency key.
-/
namespace Fw.Wire.ReviewPreview
open Lean Fw.Wire.Ops Fw.Console.ReviewPreview
open Fw.Preset (Flag)

/-- The accepted preview events of a request, each with its key (`""` when absent: untagged). -/
def seenOf (req : Json) : Except String (List Fw.Console.ReviewPreview.KSeen) := do
  (← arrD req "events").mapM fun e => do
    let key ← (match opt e "key" with
      | none => pure ""
      | some _ => str e "key")
    pure ((← str e "flag", ← str e "device"), key)

/-- The events that count for an item: those whose key names the round tag of the item's step. -/
def roundEvents (evs : List Fw.Console.ReviewPreview.KSeen) (i : Fw.Console.Review.Item) : List Seen :=
  Fw.Console.ReviewPreview.roundEventsOf (Fw.Console.ReviewPreview.roundTag i.flag i.step) evs

/-- The wire word of an arm: the rewrite arm is `r`. -/
def armWord : Fw.Console.BuildsOpen.Arm → String
  | .rewrite => "r"
  | .compare => "compare"

/-- One item of the reply. -/
def itemJson (evs : List Seen) (i : Fw.Console.Review.Item) : Json :=
  let ms := missing evs i.flag
  Json.mkObj [("flag", .str i.flag.key), ("open", .bool i.state.isNone),
    ("desktop", .bool (seenOn evs i.flag .desktop)), ("phone", .bool (seenOn evs i.flag .phone)),
    ("missing", .arr (ms.map (fun d => Json.str d.word)).toArray), ("asks", .arr ((asks evs i.flag).map Json.str).toArray)]

/-- `console.reviewPreview` (`Fw.Console.ReviewPreview.plan`, `missing`, `asks`). -/
def opReviewPreview (req : Json) : Except String Reply := do
  let ds ← Fw.Wire.Review.rows req
  let rs ← Fw.Wire.Review.recs req
  let evs ← seenOf req
  let names ← (match opt req "names" with
    | none => pure Json.null
    | some n => do pure (Json.bool (searchHasFlag (← str n "search") (← Fw.Wire.Review.flagOf (← str n "flag")))))
  let ask ← (match opt req "ask" with
    | none => pure Json.null
    | some a => do
      let f ← Fw.Wire.Review.flagOf (← str a "flag")
      let w ← str a "view"
      let width ← nat a "width"
      match View.ofWord w with
      | none => pure (Json.mkObj [("ok", .bool false), ("reason", .str "view must be flag, faithful or compare")])
      | some v => pure (match plan ds rs f v width, record ds rs f width with
        | some p, .ok (k, d) => Json.mkObj [("ok", .bool true), ("view", .str p.view.word), ("search", .str p.search),
            ("arm", .str (armWord p.arm)), ("slot", .str p.slot), ("device", .str d.word), ("key", .str k),
            ("event", Json.mkObj [("type", .str "review.previewed"), ("flag", .str f.key), ("device", .str d.word)]),
            ("carries", .bool (carries f v p.search))]
        | _, _ => Json.mkObj [("ok", .bool false), ("reason", .str "no open look-change review for this flag")]))
  pure [("items", .arr ((Fw.Console.Review.items ds rs).map fun i => itemJson (roundEvents evs i) i).toArray), ("plan", ask), ("names", names)]

end Fw.Wire.ReviewPreview
