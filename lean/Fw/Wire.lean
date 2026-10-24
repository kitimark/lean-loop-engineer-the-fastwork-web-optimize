import Lean.Data.Json
import Fw.Spec.Frames
import Fw.Spec.Verdict
import Fw.Spec.Null
import Fw.Spec.Lease
import Fw.Spec.Flags
import Fw.Spec.Cost
import Fw.Spec.Screen
import Fw.Console
import Fw.Console.Alert
import Fw.Board
import Fw.Site.BreakpointGen
import Fw.Measure.Wire
import Fw.Ops.Wire
import Fw.Wire.Sched
import Fw.Wire.Gate
import Fw.Wire.Obs
import Fw.Wire.Console
import Fw.Wire.Store
import Fw.Ci.Wire
import Fw.Ci.Telemetry
import Fw.Obs.MacTelemetryWire
import Fw.Faithful.Wire
import Fw.Gate.PathPixWire
import Fw.Ops.CheckMap
import Fw.Oracle.Wire
import Fw.Oracle.ReplayWire
import Fw.Oracle.ExpandWire
import Fw.Oracle.RetrieveWire
import Fw.Ops.WatchDiff
import Fw.Lint.Context
import Fw.Ops.LakeGc
import Fw.Ops.DiskGc
import Fw.Ops.Reap
/-!
# JSON-lines protocol (the only boundary the TypeScript shell sees)

One request object per line on stdin, exactly one reply per line on stdout, in order.
Every reply echoes the request's `id` (any JSON value; `null` when absent or unreadable).
Success: `{"id":…, <result fields>}`; failure: `{"id":…, "error":"<reason>"}`.

Numbers (PLAN §3.2): counts are `Nat`, times are integer ns (or the unit named in the field),
exact fractions are `{"num":"<int>","den":"<positive int>"}`. A non-integer number is refused.
This module and `Main.lean` use no partial operations (no bang-suffixed accessors, index access or panics);
`scripts/check-partial.sh` enforces it.
-/
namespace Fw.Wire
open Lean

/-! ## Small decoders (all total, all `Except String`) -/

/-- Read a required field of an object. -/
def field (j : Json) (k : String) : Except String Json :=
  match j.getObjVal? k with
  | .ok v => .ok v
  | .error _ => .error s!"missing field {k}"

/-- Read a required string field. -/
def str (j : Json) (k : String) : Except String String := do
  match ← field j k with
  | .str s => pure s
  | _ => throw s!"field {k}: expected a string"

/-- Read a required natural-number field (integers only). -/
def nat (j : Json) (k : String) : Except String Nat := do
  match (← field j k).getNat? with
  | .ok n => pure n
  | .error _ => throw s!"field {k}: expected a non-negative integer"

/-- Read a required Boolean field. -/
def bool (j : Json) (k : String) : Except String Bool := do
  match ← field j k with
  | .bool b => pure b
  | _ => throw s!"field {k}: expected a boolean"

/-- Read an array field. -/
def arr (j : Json) (k : String) : Except String (Array Json) := do
  match ← field j k with
  | .arr a => pure a
  | _ => throw s!"field {k}: expected an array"

/-- Read an optional field: missing or `null` is `none`. -/
def opt (j : Json) (k : String) : Option Json :=
  match j.getObjVal? k with
  | .ok .null => none
  | .ok v => some v
  | .error _ => none

/-- A JSON value as a string. -/
def asStr (k : String) : Json → Except String String
  | .str s => .ok s
  | _ => .error s!"field {k}: expected a string"

/-- A JSON value as a natural number. -/
def asNat (k : String) (j : Json) : Except String Nat :=
  match j.getNat? with
  | .ok n => .ok n
  | .error _ => .error s!"field {k}: expected a non-negative integer"

/-- A JSON value as an integer. -/
def asInt (k : String) (j : Json) : Except String Int :=
  match j.getInt? with
  | .ok n => .ok n
  | .error _ => .error s!"field {k}: expected an integer"

/-- A JSON value as an array. -/
def asArr (k : String) : Json → Except String (Array Json)
  | .arr a => .ok a
  | _ => .error s!"field {k}: expected an array"

/-- An optional nullable string field. -/
def optStr (j : Json) (k : String) : Except String (Option String) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asStr k v

/-- A list of strings field. -/
def strs (j : Json) (k : String) : Except String (List String) := do
  (← arr j k).toList.mapM (asStr k)

/-- A list of naturals field. -/
def nats (j : Json) (k : String) : Except String (List Nat) := do
  (← arr j k).toList.mapM (asNat k)

/-- A list of integers field. -/
def ints (j : Json) (k : String) : Except String (List Int) := do
  (← arr j k).toList.mapM (asInt k)

/-- Encode an optional string as a string or `null`. -/
def ostr : Option String → Json
  | some s => .str s
  | none => .null

/-! ## Exact fractions -/

/-- The wire form of a rational: `{"num":"<int>","den":"<positive int>"}`, always reduced. -/
def ratToJson (q : Rat) : Json :=
  Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- Parse the wire form of a rational; the denominator must be a positive integer string. The
value is normalized (so `{"num":"2","den":"4"}` reads as 1/2). -/
def ratOfJson (j : Json) : Except String Rat := do
  let n ← str j "num"
  let d ← str j "den"
  match n.toInt?, d.toNat? with
  | some n, some d => if d = 0 then throw "rational: den must be positive" else pure (mkRat n d)
  | _, _ => throw "rational: num and den must be decimal integer strings"

/-! ## Console codecs (the `packages/contracts` shapes) -/

open Fw.Console

/-- Actor from its wire name. -/
def actorOf : String → Except String Actor
  | "user" => .ok .user | "lead" => .ok .lead | "owner" => .ok .owner
  | "reviewer" => .ok .reviewer | "script" => .ok .script | "git" => .ok .git | "hook" => .ok .hook
  | a => .error s!"unknown actor {a}"

/-- Step kind wire names. -/
def stepKindName : StepKind → String
  | .action => "action" | .yes_no => "yes_no" | .choice => "choice" | .text => "text"

/-- Step kind from its wire name. -/
def stepKindOf : String → Except String StepKind
  | "action" => .ok .action | "yes_no" => .ok .yes_no | "choice" => .ok .choice | "text" => .ok .text
  | k => .error s!"unknown step kind {k}"

/-- Run kind wire names. -/
def runKindName : RunKind → String
  | .screen => "screen" | .gate => "gate" | .run => "run" | .device => "device"

/-- Run kind from its wire name. -/
def runKindOf : String → Except String RunKind
  | "screen" => .ok .screen | "gate" => .ok .gate | "run" => .ok .run | "device" => .ok .device
  | k => .error s!"unknown run kind {k}"

/-- Step status from its wire name. -/
def stepStatusOf : String → Except String StepStatus
  | "waiting" => .ok .waiting | "started" => .ok .started | "answered" => .ok .answered
  | "done" => .ok .done | "cancelled" => .ok .cancelled
  | k => .error s!"unknown step status {k}"

/-- Run status wire names. -/
def runStatusName : RunStatus → String
  | .running => "running" | .passed => "passed" | .failed => "failed"

/-- Run status from its wire name. -/
def runStatusOf : String → Except String RunStatus
  | "running" => .ok .running | "passed" => .ok .passed | "failed" => .ok .failed
  | k => .error s!"unknown run status {k}"

/-- Stage wire names. -/
def stageName : Stage → String
  | .question => "question" | .build => "build" | .screen => "screen" | .review => "review"
  | .device => "device" | .land_ready => "land_ready" | .land => "land"

/-- Encode a card (every field present, `null` for absent values). -/
def cardJson (c : Card) : Json := Json.mkObj [
  ("id", .str c.id), ("owner", .str c.owner), ("needsDevice", .bool c.needsDevice),
  ("approved", .bool c.approved), ("head", ostr c.head),
  ("builders", .arr (c.builders.toArray.map .str)), ("screenAt", ostr c.screenAt),
  ("reviewAt", ostr c.reviewAt), ("reviewedBy", ostr c.reviewedBy), ("deviceAt", ostr c.deviceAt),
  ("landReq", ostr c.landReq), ("landed", .bool c.landed), ("violation", .bool c.violation),
  ("lastAt", toJson c.lastAt)]

/-- Decode a card. -/
def cardOfJson (j : Json) : Except String Card := do
  pure { id := ← str j "id", owner := ← str j "owner", needsDevice := ← bool j "needsDevice",
         approved := ← bool j "approved", head := ← optStr j "head", builders := ← strs j "builders",
         screenAt := ← optStr j "screenAt", reviewAt := ← optStr j "reviewAt",
         reviewedBy := ← optStr j "reviewedBy", deviceAt := ← optStr j "deviceAt",
         landReq := ← optStr j "landReq", landed := ← bool j "landed",
         violation := ← bool j "violation", lastAt := ← nat j "lastAt" }

/-- Encode an optional list of strings. -/
def optStrs : Option (List String) → Json
  | some xs => .arr (xs.toArray.map .str)
  | none => .null

/-- Decode an optional nullable list of strings. -/
def optStrsOf (j : Json) (k : String) : Except String (Option (List String)) :=
  match opt j k with
  | none => .ok none
  | some v => do some <$> ((← asArr k v).toList.mapM (asStr k))

/-- Decode the optional `audience` field (missing or null = `Alert.legacyAudience` of the step id). -/
def audienceField (j : Json) (id : String) : Except String Audience :=
  match opt j "audience" with
  | none => .ok (Fw.Console.Alert.legacyAudience id)
  | some v => do
    match ← asStr "audience" v with
    | "user" => pure .user
    | "lead" => pure .lead
    | w => throw s!"field audience: unknown audience {w}"

/-- Decode the optional `body` field (missing or null = empty). -/
def bodyField (j : Json) : Except String String := do
  pure ((← optStr j "body").getD "")

def topicField (j : Json) : Except String (Option String) := do
  match ← optStr j "topic" with
  | some "" => throw "field topic: empty topic id"
  | t => pure t

/-- Encode a step; the `topic` key is present only when the step has one. -/
def stepJson (s : Step) : Json := Json.mkObj ([
  ("id", .str s.id), ("card", ostr s.card), ("title", .str s.title), ("kind", .str (stepKindName s.kind)),
  ("options", optStrs s.options), ("status", .str s.status.name), ("answer", ostr s.answer),
  ("postedAt", toJson s.postedAt), ("lastAt", toJson s.lastAt), ("audience", .str s.audience.name),
  ("body", .str s.body)] ++ (match s.topic with | some t => [("topic", Json.str t)] | none => []))

/-- Decode a step. -/
def stepOfJson (j : Json) : Except String Step := do
  pure { id := ← str j "id", card := ← optStr j "card", title := ← str j "title",
         kind := ← stepKindOf (← str j "kind"), options := ← optStrsOf j "options",
         status := ← stepStatusOf (← str j "status"), answer := ← optStr j "answer",
         postedAt := ← nat j "postedAt", lastAt := ← nat j "lastAt",
         audience := ← audienceField j (← str j "id"), body := ← bodyField j, topic := ← topicField j }

/-- Encode a run. -/
def runJson (r : Run) : Json := Json.mkObj [
  ("id", .str r.id), ("card", .str r.card), ("kind", .str (runKindName r.kind)),
  ("status", .str (runStatusName r.status)), ("startedAt", toJson r.startedAt)]

/-- Decode a run. -/
def runOfJson (j : Json) : Except String Run := do
  pure { id := ← str j "id", card := ← str j "card", kind := ← runKindOf (← str j "kind"),
         status := ← runStatusOf (← str j "status"), startedAt := ← nat j "startedAt" }

/-- Encode the console state. -/
def stateJson (s : State) : Json := Json.mkObj [
  ("seen", .arr (s.seen.toArray.map .str)), ("cards", .arr (s.cards.toArray.map cardJson)),
  ("steps", .arr (s.steps.toArray.map stepJson)), ("runs", .arr (s.runs.toArray.map runJson))]

/-- Decode the console state. -/
def stateOfJson (j : Json) : Except String State := do
  pure { seen := ← strs j "seen",
         cards := ← (← arr j "cards").toList.mapM cardOfJson,
         steps := ← (← arr j "steps").toList.mapM stepOfJson,
         runs := ← (← arr j "runs").toList.mapM runOfJson }

/-- Decode an event body from the flat command object (by its `type`). -/
def bodyOfJson (j : Json) : Except String Body := do
  match ← str j "type" with
  | "card.open" => pure (.cardOpen (← str j "card") (← str j "owner") (← bool j "needsDevice"))
  | "card.approve" => pure (.cardApprove (← str j "card"))
  | "card.build" => pure (.cardBuild (← str j "card") (← str j "sha") (← str j "agent"))
  | "card.screen" => pure (.cardScreen (← str j "card") (← str j "sha") (← bool j "pass"))
  | "card.review" =>
    pure (.cardReview (← str j "card") (← str j "sha") (← str j "signedBy") (← bool j "accept"))
  | "card.swipe" => pure (.cardSwipe (← str j "card") (← str j "sha") (← bool j "better"))
  | "card.land_request" => pure (.cardLandRequest (← str j "card") (← str j "sha"))
  | "card.landed" => pure (.cardLanded (← str j "card") (← str j "sha"))
  | "step.post" =>
    pure (.stepPost (← str j "step") (← optStr j "card") (← str j "title")
      (← stepKindOf (← str j "kind")) (← optStrsOf j "options") (← audienceField j (← str j "step")) (← bodyField j) (← topicField j))
  | "step.start" => pure (.stepStart (← str j "step"))
  | "step.answer" => pure (.stepAnswer (← str j "step") (← str j "answer"))
  | "step.done" => pure (.stepDone (← str j "step") (← optStr j "note"))
  | "step.cancel" => pure (.stepCancel (← str j "step"))
  | "run.start" => pure (.runStart (← str j "run") (← str j "card") (← runKindOf (← str j "kind")))
  | "run.finish" => pure (.runFinish (← str j "run") (← bool j "ok"))
  | "review.previewed" => pure (.reviewPreviewed (← str j "flag") (← str j "device"))
  | "review.feedback" => pure (.reviewFeedback (← str j "flag") (← str j "id") (← str j "text"))
  | "review.feedback.reply" => pure (.reviewFeedbackReply (← str j "flag") (← str j "to") (← str j "text"))
  | "step.topic" => pure (.stepTopic (← str j "topic") (← str j "title") (← str j "summary"))
  | t => throw s!"unknown event type {t}"

/-- Decode an event (`seq` and unknown fields are ignored). -/
def eventOfJson (j : Json) : Except String Event := do
  pure { key := ← str j "key", ts := ← nat j "ts", actor := ← actorOf (← str j "actor"),
         body := ← bodyOfJson j }

/-- Encode an outcome. -/
def outcomeJson : Outcome → Json
  | .accepted d => Json.mkObj [("accepted", .bool true), ("duplicate", .bool d)]
  | .refused w => Json.mkObj [("accepted", .bool false), ("reason", .str w)]

/-- Encode a needs-you entry. -/
def needsJson (n : NeedsYou) : Json :=
  Json.mkObj [("step", .str n.step), ("title", .str n.title), ("action", .str n.action)]

/-- Encode a board row. -/
def boardCardJson (b : BoardCard) : Json := Json.mkObj [
  ("id", .str b.id), ("owner", .str b.owner), ("stage", .str (stageName b.stage)),
  ("next", Json.mkObj [("who", .str b.next.1), ("command", .str b.next.2)]),
  ("lastAt", toJson b.lastAt), ("needsYou", (b.needsYou.map needsJson).getD .null),
  ("runningRuns", toJson b.runningRuns), ("head", ostr b.head), ("landed", .bool b.landed),
  ("violation", .bool b.violation), ("stale", .bool b.stale)]

/-- Encode the board. -/
def boardJson (b : Board) : Json := Json.mkObj [
  ("seq", toJson b.seq), ("now", toJson b.now), ("cards", .arr (b.cards.toArray.map boardCardJson)),
  ("steps", .arr (b.steps.toArray.map stepJson)), ("needsYou", .arr (b.needsYou.toArray.map needsJson))]

/-! ## Spec codecs -/

/-- Verdict wire names. -/
def verdictName : Fw.Verdict.Verdict → String
  | .better => "better" | .worse => "worse" | .noise => "noise" | .tooFew => "tooFew"

/-- Direction from its wire name. -/
def dirOf : String → Except String Fw.Verdict.Dir
  | "lower" => .ok .lower | "higher" => .ok .higher
  | d => .error s!"unknown dir {d}"

/-- Screen result wire names. -/
def screenName : Fw.Screen.Result → String
  | .dominates => "dominates" | .equal => "equal" | .worse => "worse" | .mixed => "mixed"

/-- Part from its wire name. -/
def partOf : String → Except String Fw.Flags.Part
  | "nav" => .ok .nav | "hero" => .ok .hero | "categories" => .ok .categories
  | "carousel" => .ok .carousel | "countdown" => .ok .countdown | "footer" => .ok .footer
  | p => .error s!"unknown part {p}"

/-- Part wire names. -/
def partName : Fw.Flags.Part → String
  | .nav => "nav" | .hero => "hero" | .categories => "categories" | .carousel => "carousel"
  | .countdown => "countdown" | .footer => "footer"

/-- Decode a registry rule `{"kind":"requires"|"conflicts","p","v","q","w"}`. -/
def ruleOfJson (j : Json) : Except String Fw.Flags.Rule := do
  let p ← partOf (← str j "p")
  let q ← partOf (← str j "q")
  let v ← str j "v"
  let w ← str j "w"
  match ← str j "kind" with
  | "requires" => pure (.requires p v q w)
  | "conflicts" => pure (.conflicts p v q w)
  | k => throw s!"unknown rule kind {k}"

/-- Decode a registry `{"variants":{part:[variant,…]},"rules":[…]}`; a part not listed has no
variants. -/
def registryOfJson (j : Json) : Except String Fw.Flags.Registry := do
  let vs ← field j "variants"
  let mut table : List (Fw.Flags.Part × List String) := []
  for p in Fw.Flags.Part.all do
    match opt vs (partName p) with
    | none => table := (p, []) :: table
    | some a => table := (p, ← (← asArr (partName p) a).toList.mapM (asStr (partName p))) :: table
  let rules ← (← arr j "rules").toList.mapM ruleOfJson
  let t := table
  pure { variants := fun p => ((t.find? (·.1 == p)).map (·.2)).getD [], rules }

/-! ## Operations -/

/-- The result of one request: the fields to send next to the echoed id. -/
abbrev Reply := List (String × Json)

/-- `console.apply`: `{state, event}` → `{state, outcome}`. -/
def opConsoleApply (req : Json) : Except String Reply := do
  let s ← stateOfJson (← field req "state")
  let e ← eventOfJson (← field req "event")
  let (s', o) := Fw.Console.step s e
  pure [("state", stateJson s'), ("outcome", outcomeJson o)]

/-- `console.board`: `{state, now, seq}` → `{board}`. -/
def opConsoleBoard (req : Json) : Except String Reply := do
  let s ← stateOfJson (← field req "state")
  pure [("board", boardJson (Fw.Console.board s (← nat req "now") (← nat req "seq")))]

/-- `verdict`: `{dir, ctl:[int], var:[int]}` → `{verdict, pNull}`. `pNull` is proved for every
m, n (`Fw.Null.pAt_le_pNull`, `pAt_distinct`, `falseBetterProb_eq_pNull`): it bounds the
false-"better" probability under the uniform-labeling premise, with equality for distinct values. -/
def opVerdict (req : Json) : Except String Reply := do
  let d ← dirOf (← str req "dir")
  let ctl ← ints req "ctl"
  let var ← ints req "var"
  pure [("verdict", .str (verdictName (Fw.Verdict.verdict d ctl var))),
        ("pNull", ratToJson (Fw.Null.pNull ctl.length var.length))]

/-- `multiplicity`: `{k, m, n}` or `{k, p}` → `{p, ok}` (ok iff k·p ≤ 1/20). With `m, n` the `p`
is `pNull m n`, a proved bound for every m, n (`Fw.Null.pAt_le_pNull`); a caller-supplied `p` is
taken as given. -/
def opMultiplicity (req : Json) : Except String Reply := do
  let k ← nat req "k"
  let p ← match opt req "p" with
    | some pj => ratOfJson pj
    | none => do pure (Fw.Null.pNull (← nat req "m") (← nat req "n"))
  pure [("p", ratToJson p), ("ok", .bool (Fw.Null.multOk k p))]

/-- `ticks`: `{hz, dtNs:[nat], thresholdsNs?:[nat]}` → `{ticks:[nat], above:[nat]}`. -/
def opTicks (req : Json) : Except String Reply := do
  let hz ← nat req "hz"
  let dts ← nats req "dtNs"
  let ths ← match opt req "thresholdsNs" with
    | none => pure []
    | some v => (← asArr "thresholdsNs" v).toList.mapM (asNat "thresholdsNs")
  pure [("ticks", toJson (dts.map (Fw.Frames.tickAt hz))),
        ("above", toJson (ths.map (fun t => Fw.Frames.countAbove t dts)))]

/-- Decode a run of per-frame count vectors. -/
def runOf (req : Json) (k : String) : Except String Fw.Screen.Run := do
  (← arr req k).toList.mapM fun f => do (← asArr k f).toList.mapM (asNat k)

/-- `screen`: `{base:[[nat]], var:[[nat]]}` → `{screen}`. -/
def opScreen (req : Json) : Except String Reply := do
  match Fw.Screen.screen (← runOf req "base") (← runOf req "var") with
  | .ok r => pure [("screen", .str (screenName r))]
  | .error e => throw e

/-- Decode a work vector. -/
def workOf (j : Json) : Except String Fw.Cost.Work := do
  pure { scriptUs := ← nat j "scriptUs", styleElems := ← nat j "styleElems",
         layoutObjs := ← nat j "layoutObjs", paintKpx := ← nat j "paintKpx" }

/-- `cost`: `{unit:{style,layout,paint}, budgetUs, work}` → `{mainUs, onTime}`. -/
def opCost (req : Json) : Except String Reply := do
  let u ← field req "unit"
  let unit : Fw.Cost.UnitCost := { style := ← nat u "style", layout := ← nat u "layout", paint := ← nat u "paint" }
  let w ← workOf (← field req "work")
  let b ← nat req "budgetUs"
  pure [("mainUs", toJson (Fw.Cost.mainUs unit w)), ("onTime", .bool (Fw.Cost.onTime unit b w))]

/-- `flags.resolve`: `{registry, req:[{part, variant}]}` → `{config:{part: variant}}`. -/
def opFlagsResolve (req : Json) : Except String Reply := do
  let r ← registryOfJson (← field req "registry")
  let overrides ← (← arr req "req").toList.mapM fun o => do
    pure ((← partOf (← str o "part")), (← str o "variant"))
  match Fw.Flags.resolve r overrides with
  | .ok c => pure [("config", Json.mkObj (Fw.Flags.Part.all.map fun p => (partName p, .str (c p))))]
  | .error e => throw e

/-- `lease.step`: `{state, cmd}` → `{state, reply}` (derived codecs of `Fw.Lease`). -/
def opLeaseStep (req : Json) : Except String Reply := do
  let s ← fromJson? (α := Fw.Lease.State) (← field req "state")
  let c ← fromJson? (α := Fw.Lease.Cmd) (← field req "cmd")
  let (s', r) := Fw.Lease.step s c
  pure [("state", toJson s'), ("reply", toJson r)]

/-- The id to echo: the request's `id`, or `null`. -/
def idOf (req : Json) : Json := (opt req "id").getD .null

/-- Build a reply line: the id first, then the fields. -/
def render (id : Json) (fields : Reply) : String := (Json.mkObj (("id", id) :: fields)).compress

/-- Build an error reply line. -/
def renderError (id : Json) (e : String) : String := render id [("error", .str e)]

/-- The ops this binary answers. -/
def ops : List String :=
  ["console.apply", "console.board", "verdict", "multiplicity", "ticks", "screen", "cost",
   "flags.resolve", "lease.step", "breakpoints.gen", "samples"] ++ Fw.Wire.Measure.ops ++ Fw.Wire.Ops.ops
  ++ Fw.Wire.Sched.ops
  ++ Fw.Wire.Gate.ops
  ++ Fw.Wire.Obs.ops -- watch-lean: obs.health
  ++ Fw.Wire.Console.ops -- lean-console-gaps: console.landReadiness, console.actor, plan.trailers
  ++ Fw.Wire.Store.ops -- store-and-run: store.plan, store.manifest, store.objectPath, store.reduce
  ++ Fw.Wire.Ci.ops -- ghb-lean: ci.budget.*
  ++ Fw.Wire.Ci.Telemetry.ops -- ci-telemetry: ci.telemetry
  ++ Fw.Wire.Obs.MacTelemetry.ops -- macos-telemetry: obs.macSample, obs.macReduce, obs.macMatched, obs.macIs
  ++ Fw.Wire.CheckMap.ops -- check-map-lean: ops.checkMap, ops.checkVerdict
  ++ Fw.Wire.Oracle.ops
  ++ Fw.Wire.OracleReplay.ops
  ++ Fw.Wire.OracleExpand.ops
  ++ Fw.Wire.OracleRetrieve.ops
  ++ Fw.Wire.Lint.ops -- context-slop: lint.context
  ++ Fw.Wire.LakeGc.ops -- lean-bin-slim: ops.lakeGc
  ++ Fw.Wire.DiskGc.ops -- disk-auto-gc: ops.diskGc, ops.diskGcPath
  ++ Fw.Wire.Reap.ops
  ++ Fw.Wire.WatchDiff.ops
  ++ Fw.Wire.Faithful.ops
  ++ Fw.Wire.PathPix.ops
  ++ ["console.replay", "console.query", "console.reset"] -- stateful ops: Fw/Serve.lean (fwcore serve)

/-- Dispatch one parsed request object (every op but `samples`). -/
def handleCore (req : Json) : Except String Reply := do
  match ← str req "op" with
  | "console.apply" => opConsoleApply req
  | "console.board" => opConsoleBoard req
  | "verdict" => opVerdict req
  | "multiplicity" => opMultiplicity req
  | "ticks" => opTicks req
  | "screen" => opScreen req
  | "cost" => opCost req
  | "flags.resolve" => opFlagsResolve req
  | "lease.step" => opLeaseStep req
  | "breakpoints.gen" => Fw.Site.BreakpointGen.opBreakpointsGen req
  | other =>
    match Fw.Wire.Measure.handle other req with
    | some r => r
    | none =>
    match Fw.Wire.Ops.handle other req with  -- lean-ops
    | some r => r
    | none =>
    match Fw.Wire.Sched.handle other req with  -- lean-wire-sched: ops.admit, metrics.*
    | some r => r
    | none =>
    match Fw.Wire.Gate.handle other req with  -- verdict-to-lean: gate.*
    | some r => r
    | none =>
    match Fw.Wire.Obs.handle other req with  -- watch-lean: obs.health
    | some r => r
    | none =>
    match Fw.Wire.Console.handle other req with  -- lean-console-gaps
    | some r => r
    | none =>
    match Fw.Wire.Store.handle other req with  -- store-and-run
    | some r => r
    | none =>
    match Fw.Wire.Ci.handle other req with  -- ghb-lean: ci.budget.*
    | some r => r
    | none =>
    match Fw.Wire.Ci.Telemetry.handle other req with  -- ci-telemetry
    | some r => r
    | none =>
    match Fw.Wire.Obs.MacTelemetry.handle other req with  -- macos-telemetry
    | some r => r
    | none =>
    match Fw.Wire.CheckMap.handle other req with  -- check-map-lean
    | some r => r
    | none =>
    match Fw.Wire.Oracle.handle other req with
    | some r => r
    | none =>
    match Fw.Wire.OracleReplay.handle other req with  -- jev-replay: oracle.replay, oracle.preRun, oracle.score
    | some r => r
    | none =>
    match Fw.Wire.OracleExpand.handle other req with
    | some r => r
    | none =>
    match Fw.Wire.OracleRetrieve.handle other req with
    | some r => r
    | none =>
    match Fw.Wire.Lint.handle other req with  -- context-slop: lint.context
    | some r => r
    | none =>
    match Fw.Wire.LakeGc.handle other req with  -- lean-bin-slim: ops.lakeGc
    | some r => r
    | none =>
    match Fw.Wire.DiskGc.handle other req with  -- disk-auto-gc: ops.diskGc, ops.diskGcPath
    | some r => r
    | none =>
    match Fw.Wire.Reap.handle other req with  -- orphan-guard: ops.lspReap
    | some r => r
    | none =>
    match Fw.Wire.WatchDiff.handle other req with  -- watch-stream
    | some r => r
    | none =>
    match Fw.Wire.Faithful.handle other req with
    | some r => r
    | none =>
    match Fw.Wire.PathPix.handle other req with
    | some r => r
    | none => throw s!"unknown op {other}"

/-- The sample requests. -/
def sampleRequests : List (String × String) := [
  ("verdict", "{\"op\":\"verdict\",\"dir\":\"lower\",\"ctl\":[21,19,23,20],\"var\":[4,3,5,2]}"),
  ("multiplicity", "{\"op\":\"multiplicity\",\"k\":3,\"m\":4,\"n\":4}"),
  ("ticks", "{\"op\":\"ticks\",\"hz\":120,\"dtNs\":[8333333,37500000,54167000],\"thresholdsNs\":[34000000]}"),
  ("screen", "{\"op\":\"screen\",\"base\":[[3,10],[2,10]],\"var\":[[1,10],[2,10]]}"),
  ("cost", "{\"op\":\"cost\",\"unit\":{\"style\":1,\"layout\":1,\"paint\":1},\"budgetUs\":10,\"work\":{\"scriptUs\":4,\"styleElems\":2,\"layoutObjs\":2,\"paintKpx\":2}}"),
  ("flags.resolve", "{\"op\":\"flags.resolve\",\"registry\":{\"variants\":{\"nav\":[\"orig\"],\"hero\":[\"orig\",\"v2\"],\"categories\":[\"orig\"],\"carousel\":[\"orig\"],\"countdown\":[\"orig\"],\"footer\":[\"orig\"]},\"rules\":[]},\"req\":[{\"part\":\"hero\",\"variant\":\"v2\"}]}"),
  ("console.apply", "{\"op\":\"console.apply\",\"state\":{\"seen\":[],\"cards\":[],\"steps\":[],\"runs\":[]},\"event\":{\"key\":\"k1\",\"ts\":1001,\"type\":\"card.open\",\"actor\":\"owner\",\"card\":\"A\",\"owner\":\"o\",\"needsDevice\":false}}"),
  ("console.board", "{\"op\":\"console.board\",\"now\":5000,\"seq\":1,\"state\":{\"seen\":[\"k1\"],\"cards\":[{\"id\":\"A\",\"owner\":\"o\",\"needsDevice\":false,\"approved\":false,\"head\":null,\"builders\":[],\"screenAt\":null,\"reviewAt\":null,\"reviewedBy\":null,\"deviceAt\":null,\"landReq\":null,\"landed\":false,\"violation\":false,\"lastAt\":1001}],\"steps\":[],\"runs\":[]}}"),
  ("lease.step", "{\"op\":\"lease.step\",\"state\":{\"queue\":[]},\"cmd\":{\"acquire\":{\"o\":\"a\",\"now\":0,\"ttl\":900}}}")]
/-- Golden samples: one request per op and the reply this binary gives (for zod to parse). -/
def samples : Json :=
  .arr (sampleRequests.toArray.map fun (name, r) =>
    match Json.parse r with
    | .ok j =>
      let resp := match handleCore j with
        | .ok f => Json.mkObj f
        | .error e => Json.mkObj [("error", .str e)]
      Json.mkObj [("name", .str name), ("request", j), ("response", resp)]
    | .error e => Json.mkObj [("name", .str name), ("error", .str e)])

/-- Dispatch one parsed request object. -/
def handle (req : Json) : Except String Reply := do
  if (← str req "op") == "samples" then pure [("samples", samples)] else handleCore req

/-- Answer one input line. Every line gets exactly one reply line: a blank line, unreadable JSON
or a non-object is an error reply with `"id":null`. -/
def handleLine (line : String) : String :=
  let t := line.trimAscii.toString
  if t.isEmpty then renderError .null "empty request" else
  match Json.parse t with
  | .error e => renderError .null s!"invalid JSON: {e}"
  | .ok req =>
    match req with
    | .obj _ =>
      match handle req with
      | .ok fields => render (idOf req) fields
      | .error e => renderError (idOf req) e
    | _ => renderError .null "request must be a JSON object"

end Fw.Wire
