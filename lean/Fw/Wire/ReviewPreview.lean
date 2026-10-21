import Fw.Ops.Wire
import Fw.Wire.Review
import Fw.Console.ReviewPreview
/-!
# JSON for the review preview (`console.reviewPreview`)

| op | request | reply |
|---|---|---|
| `console.reviewPreview` | the rows and steps of `console.review` (`looks`?, `steps`), `events` [{flag, device, seq?}] (the accepted `review.previewed` events, any order), `posts`? [{step, seq}] (the log positions of the `step.post` events), `ask`? {flag, view (flag, faithful, compare), width}, `names`? {search, flag} | `items` [{flag, open, desktop, phone, missing [device words], asks [lines]}], `plan` (null without `ask`; else {ok, view, search, arm (r, compare), slot, device, key, event, carries} or {ok false, reason}), `names` (null without `names`; else whether the search names the flag by a whole entry) |

With `posts`, an item counts only the events after the posting of its review step (`Fw.Console.Review.inRound`): a new round starts with
no previews. Without `posts` every event counts. An event without `seq` is at position 0.

The plan is made only for an open look-change review. `event` is the typed command the console records when the preview opens
(`review.previewed`), with `key` as its idempotency key.
-/
namespace Fw.Wire.ReviewPreview
open Lean Fw.Wire.Ops Fw.Console.ReviewPreview
open Fw.Preset (Flag)

/-- The accepted preview events of a request. -/
def seenOf (req : Json) : Except String (List (Seen × Nat)) := do
  (← arrD req "events").mapM fun e => do pure ((← str e "flag", ← str e "device"), ← natD e "seq" 0)

/-- The postings of review steps, when the request gives them. -/
def postsOf (req : Json) : Except String (Option (List Fw.Console.Review.Post)) :=
  match opt req "posts" with
  | none => pure none
  | some _ => do
    pure (some (← (← arrD req "posts").mapM fun p => do pure ({ step := ← str p "step", seq := ← nat p "seq" } : Fw.Console.Review.Post)))

/-- The events that count for an item: those of its round (all of them without `posts`). -/
def roundEvents (posts : Option (List Fw.Console.Review.Post)) (evs : List (Seen × Nat)) (i : Fw.Console.Review.Item) : List Seen :=
  match posts with
  | none => evs.map (·.1)
  | some ps => Fw.Console.Review.inRound (Fw.Console.Review.roundStart ps i.flag i.step) evs

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
  let posts ← postsOf req
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
  pure [("items", .arr ((Fw.Console.Review.items ds rs).map fun i => itemJson (roundEvents posts evs i) i).toArray), ("plan", ask), ("names", names)]

end Fw.Wire.ReviewPreview
