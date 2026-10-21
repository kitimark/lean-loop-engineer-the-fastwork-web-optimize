import Fw.Ops.Wire
import Fw.Console.Review
import Fw.Console.ReviewStrips
/-!
# JSON for the review queue (`console.review`)

| op | request | reply |
|---|---|---|
| `console.review` | `looks`? [{flag, date, decision (kept, rejected, accepted), review (pending, done), material?}] (default `Fw.Preset.Gen.lookDecisions`), `steps` [{id, answer?, open}] (the board steps; `open` is waiting or started), `answer`? {flag, word}, `today`? (`YYYY-MM-DD`), `serve`? {flag, file} | `items` [{flag, step, date, words, material, state (open, keep, reject), post, title, body, audience}], `open`, `options`, `answer` (null, or {ok, reason?, step?, word?}) (`Fw.Console.Review`). With `today`, each item also has `strips` [{engine, state (ready, expired, missing), width?, push?, file?, run?, artifact?, expires?, note?, diff?, redo?}] and the reply has `serve` (null, or {ok, reason?, run?, artifact?, path?}: the allowlist, `Fw.Console.ReviewStrips.serve`) |
-/
namespace Fw.Wire.Review
open Lean Fw.Wire.Ops Fw.Console.Review
open Fw.Preset (Flag)

/-- The flag a key `part:variant` names. -/
def flagOf (k : String) : Except String Flag :=
  match k.splitOn ":" with
  | p :: v :: rest => if p.isEmpty then .error s!"bad flag {k}" else .ok ⟨p, ":".intercalate (v :: rest)⟩
  | _ => .error s!"bad flag {k}"

/-- A verdict word of a decision row. -/
def verdictOf : String → Except String Fw.Preset.Gen.LookVerdict
  | "kept" => .ok .kept | "rejected" => .ok .rejected | "accepted" => .ok .accepted
  | w => .error s!"unknown decision {w}"

/-- A review-state word of a decision row. -/
def reviewOf : String → Except String Fw.Preset.Gen.LookReview
  | "pending" => .ok .pending | "done" => .ok .done
  | w => .error s!"unknown review state {w}"

/-- The material of one engine. -/
def engineOf (j : Json) : Except String Fw.Preset.Gen.EngineMat := do
  let st ← (match ← str j "state" with
    | "ready" => pure Fw.Preset.Gen.Ready.ready
    | "pending" => pure Fw.Preset.Gen.Ready.pending
    | w => throw s!"unknown readiness {w}")
  let o (k : String) : Except String (Option String) :=
    match opt j k with | none => pure none | some v => some <$> asStr k v
  pure { state := st, run := ← o "run", artifact := ← o "artifact", expires := ← o "expires", task := ← o "task" }

/-- The material of a decision row. -/
def materialOf (j : Json) : Except String Fw.Preset.Gen.ReviewMaterial := do
  pure { chromium := ← engineOf (← field j "chromium"), webkit := ← engineOf (← field j "webkit") }

/-- The decision rows of a request. -/
def rows (req : Json) : Except String (List Fw.Console.Review.Row) :=
  match opt req "looks" with
  | none => pure Fw.Preset.Gen.lookDecisions
  | some _ => do
    (← arrD req "looks").mapM fun l => do
      pure { flag := ← flagOf (← str l "flag"), date := ← str l "date", decision := ← verdictOf (← str l "decision"),
             review := ← reviewOf (← str l "review"),
             material := ← (match opt l "material" with | none => pure none | some m => some <$> materialOf m) }

/-- The board steps of a request. -/
def recs (req : Json) : Except String (List Rec) := do
  (← arrD req "steps").mapM fun s => do
    pure ({ id := ← str s "id", answer := (match opt s "answer" with | some (.str a) => some a | _ => none),
            isOpen := ← asBool "open" (← field s "open") } : Rec)

/-- The state word of an item. -/
def stateWord : Option Verdict → String
  | none => "open"
  | some v => v.word

/-- An item as JSON. -/
def itemJson (rs : List Rec) (i : Item) : Json :=
  Json.mkObj [("flag", .str i.flag.key), ("step", .str i.step), ("date", .str i.date), ("words", .str i.words),
    ("state", .str (stateWord i.state)),
    ("material", match i.material with
      | some m => Json.mkObj [("chromium", m.chromium.json), ("webkit", m.webkit.json)]
      | none => .null),
    ("post", .bool (needsPost rs i.flag)), ("title", .str (title i.flag)),
    ("body", .str (body i)), ("audience", .str audience.name)]

/-- A strip as JSON. The run and expiry are those of the material (`Fw.Console.ReviewStrips.Strip`); a missing strip has none. -/
def stripJson (f : Fw.Preset.Flag) (o : Fw.Console.ReviewStrips.Out) : Json :=
  let base := [("engine", Json.str o.engine), ("state", .str o.state.word)]
  let redo := [("redo", Json.str (Fw.Console.ReviewStrips.redo f))]
  match o.row, o.strip with
  | none, _ => Json.mkObj (base ++ redo)
  | some r, none => Json.mkObj (base ++ [("width", toJson r.width), ("push", .str r.push.word), ("file", .str r.file)] ++ redo)
  | some r, some s => Json.mkObj (base ++ [("width", toJson r.width),
      ("push", .str r.push.word), ("file", .str r.file), ("run", .str s.run), ("artifact", .str r.artifact),
      ("expires", .str s.expires), ("note", .str r.note), ("diff", .str r.diff)] ++
      (if o.state == .expired then redo else []))

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
        | .ok v => Json.mkObj [("ok", .bool true), ("step", .str (((openStep rs f).map (·.id)).getD (stepId f))),
            ("word", .str v.word)]
        | .error e => Json.mkObj [("ok", .bool false), ("reason", .str e)]))
  let today? := (match opt req "today" with | some (.str t) => some t | _ => none)
  let its := items ds rs
  let withStrips (i : Item) : Json :=
    match itemJson rs i, today? with
    | .obj kvs, some t => .obj (kvs.insert "strips" (.arr ((Fw.Console.ReviewStrips.stripsOf t i.flag i.material).map (stripJson i.flag)).toArray))
    | j, _ => j
  let srv ← (match opt req "serve", today? with
    | some s, some t => do
      let fk ← str s "flag"
      let file ← str s "file"
      pure (match flagOf fk with
      | .error _ => Json.mkObj [("ok", .bool false), ("reason", .str "not a flag")]
      | .ok f => match its.find? (·.flag == f) with
        | none => Json.mkObj [("ok", .bool false), ("reason", .str "no pending review for this flag")]
        | some i => match Fw.Console.ReviewStrips.serve t f i.material file with
          | none => Json.mkObj [("ok", .bool false), ("reason", .str "not a servable strip of this review")]
          | some st => Json.mkObj [("ok", .bool true), ("run", .str st.run), ("artifact", .str st.row.artifact), ("path", .str st.row.path)])
    | _, _ => pure Json.null)
  pure ([("items", .arr (its.map withStrips).toArray),
    ("open", toJson (openItems ds rs).length),
    ("options", .arr #[.str Verdict.keep.word, .str Verdict.reject.word]),
    ("answer", ans)] ++ (if today?.isSome then [("serve", srv)] else []))

end Fw.Wire.Review
