import Lean.Data.Json
import Fw.Oracle.Core
import Fw.Oracle.Calibrate
import Fw.Oracle.Redact
import Fw.Oracle.Send
import Fw.Oracle.Questions
import Fw.Oracle.Body
import Fw.Ops.Wire
/-! JSON codecs and the `oracle.*` ops over `fwcore` JSON lines. -/
namespace Fw.Wire.Oracle
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD ostr optN)
open Fw.Oracle

/-! ## Codecs -/

/-- A rational on the wire. -/
def ratJ (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

def ratOf (j : Json) : Except String Rat := do
  let n ← str j "num"
  let d ← str j "den"
  match n.toInt?, d.toNat? with
  | some n, some d => if d = 0 then throw "rational: den must be positive" else pure (mkRat n d)
  | _, _ => throw "rational: num and den must be decimal integer strings"

def numQ : Json → Option Rat
  | .num n => some (mkRat n.mantissa (10 ^ n.exponent))
  | _ => none

def specJ : Spec → Json
  | .choice os z => Json.mkObj [("type", "choice"), ("options", toJson os), ("noMatch", .str z)]
  | .noul => Json.mkObj [("type", "noul")]
  | .score ls => Json.mkObj [("type", "score"), ("levels", toJson ls)]

def answerJ : Answer → Json
  | .choice pk d => Json.mkObj [("type", "choice"), ("pick", .str pk), ("dist", .arr (d.map ratJ).toArray)]
  | .noul p => Json.mkObj [("type", "noul"), ("p", ratJ p)]
  | .score d => Json.mkObj [("type", "score"), ("dist", .arr (d.map ratJ).toArray)]

def failureJ : Failure → Json
  | .timeout => Json.mkObj [("kind", "timeout")]
  | .http s => Json.mkObj [("kind", "http"), ("status", toJson s)]
  | .malformed => Json.mkObj [("kind", "malformed")]
  | .schema d => Json.mkObj [("kind", "schema"), ("detail", .str d)]
  | .overBudget => Json.mkObj [("kind", "overBudget")]
  | .noKey => Json.mkObj [("kind", "noKey")]
  | .unredacted => Json.mkObj [("kind", "unredacted")]
  | .undeclared => Json.mkObj [("kind", "undeclared")]
  | .tooLarge => Json.mkObj [("kind", "tooLarge")]

def failureOf (j : Json) : Except String Failure := do
  match ← str j "kind" with
  | "timeout" => pure .timeout
  | "http" => pure (.http (← nat j "status"))
  | "malformed" => pure .malformed
  | "schema" => pure (.schema (← strD j "detail" ""))
  | "overBudget" => pure .overBudget
  | "noKey" => pure .noKey
  | "unredacted" => pure .unredacted
  | "undeclared" => pure .undeclared
  | "tooLarge" => pure .tooLarge
  | k => throw s!"failure: unknown kind {k}"
where strD (j : Json) (k d : String) : Except String String :=
  match opt j k with
  | none => .ok d
  | some v => asStr k v

def adviceJ : Advice → Json
  | .pick o => Json.mkObj [("kind", "pick"), ("value", .str o)]
  | .yes => Json.mkObj [("kind", "yes")]
  | .no => Json.mkObj [("kind", "no")]
  | .level i => Json.mkObj [("kind", "level"), ("value", toJson i)]

def adviceKey : Advice → String
  | .pick o => o
  | .yes => "yes"
  | .no => "no"
  | .level i => toString i

def adviceOfKey (s : Spec) (k : String) : Except String Advice :=
  match s.advisable.find? (adviceKey · == k) with
  | some v => .ok v
  | none => .error s!"thresholds: {k} is not an advisable option"

/-- A threshold table from the request. -/
def thresholdsOf (s : Spec) (req : Json) : Except String Thresholds := do
  match opt req "thresholds" with
  | none => pure []
  | some (.obj kvs) =>
    kvs.toList.filterMapM fun (k, v) => do
      let o ← adviceOfKey s k
      match v with
      | .null => pure none
      | j =>
        let τ ← ratOf j
        if 0 < τ ∧ τ ≤ 1 then pure (some (o, τ)) else throw s!"threshold {τ} of {k} is outside (0, 1]"
  | some _ => throw "thresholds: expected an object"

def thresholdsJ (s : Spec) (th : Thresholds) : Json :=
  Json.mkObj (s.advisable.map fun o => (adviceKey o, match th.lookup o with
    | some τ => ratJ τ
    | none => .null))

/-- A label from the wire, read against the answer space. -/
def labelOf (s : Spec) (j : Json) : Except String Advice :=
  match s, j with
  | .choice os _, .str o => if os.contains o then .ok (.pick o) else .error s!"label: {o} is not an option"
  | .noul, .str "yes" => .ok .yes
  | .noul, .str "no" => .ok .no
  | .score ls, v => do
    let i ← asNat "label" v
    if i < ls.length then pure (.level i) else throw "label: level out of range"
  | _, _ => .error "label: does not fit the question"

def reasonJ : Reason → Json
  | .failure f => Json.mkObj [("reason", "failure"), ("failure", failureJ f)]
  | .uncalibrated => Json.mkObj [("reason", "uncalibrated")]
  | .badThreshold t => Json.mkObj [("reason", "badThreshold"), ("threshold", ratJ t)]
  | .below g t => Json.mkObj [("reason", "below"), ("gate", ratJ g), ("threshold", ratJ t)]
  | .noMatch => Json.mkObj [("reason", "noMatch")]

def actionFields : Action → Reply
  | .advise v => [("action", "advise"), ("advice", adviceJ v)]
  | .escalate r => [("action", "escalate"), ("reason", reasonJ r)]

/-- A state from the wire: an object of field to a string or an array of strings. -/
def stateOf (j : Json) : Except String State := do
  match j with
  | .obj kvs =>
    kvs.toList.mapM fun (k, v) => match v with
      | .str s => pure (k, [s])
      | .arr a => do pure (k, ← a.toList.mapM (asStr k))
      | _ => throw s!"state: field {k} must be a string or an array of strings"
  | _ => throw "state: expected an object"

/-- The names to redact (optional, default none). -/
def namesOf (req : Json) : Except String (List String) := do
  (← arrD req "names").mapM (asStr "names")

def questionOf (req : Json) : Except String Question := do
  let n ← str req "name"
  match question n with
  | some q => pure q
  | none => throw s!"unknown question {n}"

def bodyJ (q : Question) (st : State) : Json :=
  Json.mkObj [("state", stateJ st), ("model", .str model),
    ("questions", Json.mkObj [(q.name, Json.mkObj [
      ("type", .str q.spec.wireType),
      ("instructions", .str q.instructions), ("criteria", criteriaJ q)])])]

#guard (Json.parse (bodyText ciTriage [("log", ["x"])])).toOption == some (bodyJ ciTriage [("log", ["x"])])
#guard (Json.parse (bodyText ciTriage [("job", ["j"]), ("log", ["x", "y"])])).toOption ==
  some (bodyJ ciTriage [("job", ["j"]), ("log", ["x", "y"])])

/-- Read the answer to question `q` out of a response body: the raw answer, or the reason it does not fit. -/
def rawOf (q : Question) (body : Json) : Except String Raw := do
  match body.getObjVal? "model" with
  | .ok (.str m) => if m != model then throw s!"reply model {m} is not the pinned {model}"
  | _ => throw "reply has no model"
  let a ← match body.getObjVal? "answers" >>= (·.getObjVal? q.name) with
    | .ok a => pure a
    | .error _ => throw s!"reply has no answer {q.name}"
  let ty ← str a "type"
  let pick := match a.getObjVal? "choice" with | .ok (.str s) => some s | _ => none
  let noul := match a.getObjVal? "noul" with | .ok v => numQ v | _ => none
  let probs ← match a.getObjVal? "probabilities" with
    | .ok (.obj kvs) => kvs.toList.mapM fun (k, v) => match numQ v with
      | some x => pure (k, x)
      | none => throw s!"probability {k} is not a number"
    | .ok _ => throw "probabilities is not an object"
    | .error _ => pure []
  pure { type := ty, pick, noul, probs }

/-- The outcome of a reply text. -/
def outcomeOf (q : Question) (text : String) : Outcome :=
  match Json.parse text with
  | .error _ => .failure .malformed
  | .ok body =>
    match rawOf q body >>= validate q.spec with
    | .ok a => .answer a
    | .error e => .failure (.schema e)

def requestOutcome (q : Question) (req : Json) : Except String Outcome := do
  match opt req "failure" with
  | some f => pure (.failure (← failureOf f))
  | none => pure (outcomeOf q (← str req "reply"))

/-! ## Ops -/

def opQuestion (req : Json) : Except String Reply := do
  let q ← questionOf req
  pure [("name", .str q.name), ("model", .str model), ("spec", specJ q.spec), ("target", ratJ q.target),
    ("perOption", toJson q.perOption), ("fields", toJson q.fields)]

def opRedact (req : Json) : Except String Reply := do
  pure [("text", .str (redactLine (← namesOf req) (← str req "text")))]

def opStore (req : Json) : Except String Reply := do
  pure [("text", .str (storedReply (← str req "text")))]

def rowId (j : Json) : Except String String :=
  match opt j "id", opt j "runId" with
  | some v, _ => asStr "id" v
  | none, some v => do pure s!"run-{← asNat "runId" v}"
  | none, none => .error "replay: a row needs id or runId"

def noSplit (j : Json) : Except String Unit :=
  match opt j "split" with
  | some _ => .error "replay: a row may not name a split (Lean splits by id)"
  | none => pure ()

def labeledRow (j : Json) : Bool :=
  match opt j "label" with
  | some .null | none => false
  | some _ => true

def replayOf (s : Spec) (j : Json) : Except String (String × Option Advice) := do
  noSplit j
  let label ← match opt j "label" with
    | some .null | none => pure none
    | some v => do pure (some (← labelOf s v))
  pure (← rowId j, label)

def answersOf (req : Json) : Except String (List (String × String)) := do
  (← arrD req "answers").mapM fun a => do pure (← str a "id", ← str a "reply")

/-- The labeled rows of the request's replay joined with its answers by id. -/
def joined (q : Question) (req : Json) : Except String (List IdRow × List String × Nat) := do
  let rs ← (← arrD req "replay").mapM (replayOf q.spec)
  let ans ← answersOf req
  let ids := labeledIds (rs.map fun (i, l) => (i, l.isSome))
  let labels := rs.filterMap fun (i, l) => l.map (i, ·)
  let got := ids.filterMap fun i => (ans.lookup i).map (i, ·)
  let rows := got.filterMap fun (i, t) => match outcomeOf q t, labels.lookup i with
    | .answer a, some l => some (i, ({ answer := a, label := l } : Row))
    | _, _ => none
  pure (rows, ids, got.length)

def statsJ (s : Spec) (th : Thresholds) (rows : List Row) : Reply :=
  let (cov, hit) := evalBy s th rows
  [("covered", toJson cov), ("hits", toJson hit), ("options", .arr (s.advisable.map fun o => Json.mkObj
    [("option", .str (adviceKey o)), ("advised", toJson (advisedBy s th rows o)),
     ("hits", toJson (hitsBy s th rows o))]).toArray)]

def opRequest (req : Json) : Except String Reply := do
  let q ← questionOf req
  let st := redactState (← namesOf req) (← stateOf (← field req "state"))
  pure [("bodyText", .str (bodyText q st)), ("state", stateJ st)]

def opPre (req : Json) : Except String Reply := do
  let q ← questionOf req
  let days ← (← arrD req "days").mapM (asStr "days")
  let p := pre defaultBudget q (← namesOf req) (← stateOf (← field req "state")) (← boolD req "logged" false)
    (← str req "today") days (← optN req "run")
  pure <| match p with
    | .replay => [("pre", "replay")]
    | .send body => [("pre", "send"), ("bodyText", .str body)]
    | .refuse f => [("pre", "refuse"), ("failure", failureJ f)]

/-- `oracle.plan`: the labeled ids of the replay rows. -/
def opPlan (req : Json) : Except String Reply := do
  let part ← match opt req "part" with
    | some v => do
      let p ← asStr "part" v
      if p == "holdout" || p == "choose" then pure (some (p == "holdout"))
      else throw s!"part: {p} is not holdout or choose"
    | none => pure none
  let es ← (← arrD req "rows").mapM fun j => do
    noSplit j
    let i ← rowId j
    pure (i, labeledRow j && part.all (heldOut i == ·))
  let cut : List Nat → List Nat := match ← optN req "limit" with
    | some n => (·.take n)
    | none => id
  let idx := cut (labeledIds ((List.range es.length).zip (es.map (·.2))))
  let ids := (labeledIds es).take idx.length
  let logged ← match opt req "logged" with
    | none => pure (List.replicate idx.length false)
    | some j => (← asArr "logged" j).toList.mapM (asBool "logged")
  if logged.length != idx.length then throw "logged: one flag per selected id"
  pure [("ids", toJson ids), ("indices", toJson idx), ("missing", toJson (missing logged)),
    ("runCap", toJson defaultBudget.runCap), ("resumable", toJson (resumable defaultBudget.runCap logged))]

def opValidate (req : Json) : Except String Reply := do
  let q ← questionOf req
  pure <| match outcomeOf q (← str req "reply") with
    | .answer a => [("ok", true), ("answer", answerJ a), ("gate", ratJ (gate a))]
    | .failure f => [("ok", false), ("failure", failureJ f)]

def opDecide (req : Json) : Except String Reply := do
  let q ← questionOf req
  let th ← thresholdsOf q.spec req
  let o ← requestOutcome q req
  let g := match o with
    | .answer a => [("gate", ratJ (gate a))]
    | .failure _ => []
  pure (actionFields (decideOpt q.spec th o) ++ g)

def opCalibrate (req : Json) : Except String Reply := do
  let q ← questionOf req
  let (rows, ids, answered) ← joined q req
  let th := certify q.spec q.target q.perOption rows
  let ans ← answersOf req
  let part (rs : List Row) (n : Nat) : Json := Json.mkObj ([("rows", toJson n)] ++ statsJ q.spec th rs)
  pure [("thresholds", thresholdsJ q.spec th),
    ("choose", part (choosePart rows) (ids.filter (!heldOut ·)).length),
    ("holdout", part (holdPart rows) (ids.filter heldOut).length),
    ("labeled", toJson ids.length), ("answered", toJson answered), ("used", toJson rows.length),
    ("dropped", toJson (answered - rows.length)), ("write", toJson (mayWrite ids (ans.map (·.1))))]

def opEval (req : Json) : Except String Reply := do
  let q ← questionOf req
  let th ← thresholdsOf q.spec req
  let (rows, ids, _) ← joined q req
  let ans ← answersOf req
  let held := ids.filter heldOut
  let answered := (held.filter fun i => (ans.lookup i).isSome).length
  let rows' := holdPart rows
  pure ([("rows", toJson held.length), ("answered", toJson answered), ("used", toJson rows'.length),
    ("dropped", toJson (answered - rows'.length))] ++ statsJ q.spec th rows')

def opBudget (_ : Json) : Except String Reply :=
  pure [("dailyCap", toJson defaultBudget.dailyCap), ("runCap", toJson defaultBudget.runCap)]

/-- The ops of this module. -/
def ops : List String :=
  ["oracle.question", "oracle.redact", "oracle.request", "oracle.pre", "oracle.validate", "oracle.decide",
   "oracle.calibrate", "oracle.eval", "oracle.store", "oracle.budget", "oracle.plan"]

/-- Dispatch an `oracle.*` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "oracle.question" => some (opQuestion req)
  | "oracle.redact" => some (opRedact req)
  | "oracle.request" => some (opRequest req)
  | "oracle.pre" => some (opPre req)
  | "oracle.validate" => some (opValidate req)
  | "oracle.decide" => some (opDecide req)
  | "oracle.calibrate" => some (opCalibrate req)
  | "oracle.eval" => some (opEval req)
  | "oracle.store" => some (opStore req)
  | "oracle.budget" => some (opBudget req)
  | "oracle.plan" => some (opPlan req)
  | _ => none

/-! ## Examples -/

/-- Run an op on a literal request (for the guards). -/
def run (op : String) (r : String) : String :=
  match Json.parse r with
  | .ok j => match handle op j with
    | some (.ok f) => (Json.mkObj f).compress
    | some (.error e) => s!"error: {e}"
    | none => "unknown op"
  | .error e => s!"parse: {e}"

/-- A CI-triage reply in the vendor's shape. -/
def sampleReply (pick : String) (pf pi pr pu : String) : String :=
  "{\"model\":\"jev-1.13.0\",\"answers\":{\"ci-triage\":{\"type\":\"choice\",\"choice\":\"" ++ pick ++
  "\",\"probabilities\":{\"flake\":" ++ pf ++ ",\"infra\":" ++ pi ++ ",\"real\":" ++ pr ++ ",\"unknown\":" ++ pu ++
  "},\"confidence\":0.5}},\"usage\":{\"input_tokens\":10,\"output_tokens\":1}}"

#guard run "oracle.decide" ("{\"name\":\"ci-triage\",\"reply\":" ++
  (Json.str (sampleReply "real" "0.01" "0.01" "0.97" "0.01")).compress ++ "}") ==
  "{\"action\":\"escalate\",\"gate\":{\"den\":\"25\",\"num\":\"24\"},\"reason\":{\"reason\":\"uncalibrated\"}}"
#guard run "oracle.decide" ("{\"name\":\"ci-triage\",\"thresholds\":{\"real\":{\"num\":\"1\",\"den\":\"2\"}},\"reply\":" ++
  (Json.str (sampleReply "real" "0.01" "0.01" "0.97" "0.01")).compress ++ "}") ==
  "{\"action\":\"advise\",\"advice\":{\"kind\":\"pick\",\"value\":\"real\"},\"gate\":{\"den\":\"25\",\"num\":\"24\"}}"
#guard run "oracle.decide" "{\"name\":\"ci-triage\",\"reply\":\"not json\"}" ==
  "{\"action\":\"escalate\",\"reason\":{\"failure\":{\"kind\":\"malformed\"},\"reason\":\"failure\"}}"
#guard run "oracle.decide" "{\"name\":\"ci-triage\",\"failure\":{\"kind\":\"noKey\"}}" ==
  "{\"action\":\"escalate\",\"reason\":{\"failure\":{\"kind\":\"noKey\"},\"reason\":\"failure\"}}"
#guard run "oracle.pre" "{\"name\":\"ci-triage\",\"state\":{\"log\":[\"/Users/x/y\"]},\"today\":\"d\"}" ==
  (Json.mkObj [("bodyText", .str (bodyText ciTriage [("log", ["~/y"])])), ("pre", "send")]).compress
#guard run "oracle.pre" "{\"name\":\"ci-triage\",\"state\":{\"note\":\"x\"},\"today\":\"d\"}" ==
  "{\"failure\":{\"kind\":\"undeclared\"},\"pre\":\"refuse\"}"
#guard run "oracle.pre" "{\"name\":\"ci-triage\",\"state\":{\"log\":\"x\"},\"today\":\"d\",\"logged\":true}" ==
  "{\"pre\":\"replay\"}"
#guard run "oracle.pre" "{\"name\":\"ci-triage\",\"state\":{},\"today\":\"d\",\"run\":60}" ==
  "{\"failure\":{\"kind\":\"overBudget\"},\"pre\":\"refuse\"}"
#guard run "oracle.plan" ("{\"rows\":[{\"id\":\"a\",\"label\":\"x\"},{\"id\":\"b\",\"label\":\"x\"}," ++
  "{\"runId\":7,\"label\":\"x\"},{\"id\":\"d\",\"label\":null}],\"logged\":[true,false,true]}") ==
  "{\"ids\":[\"a\",\"b\",\"run-7\"],\"indices\":[0,1,2],\"missing\":1,\"resumable\":true,\"runCap\":60}"
#guard (run "oracle.plan" "{\"rows\":[{\"id\":\"a\",\"split\":\"heldout\",\"label\":\"x\"}]}").startsWith "error: replay"
#guard run "oracle.plan" "{\"rows\":[{\"id\":\"a\",\"label\":\"x\"},{\"id\":\"b\",\"label\":\"x\"}],\"part\":\"holdout\"}" ==
  "{\"ids\":[\"a\"],\"indices\":[0],\"missing\":1,\"resumable\":true,\"runCap\":60}"
#guard run "oracle.plan" "{\"rows\":[{\"id\":\"a\",\"label\":\"x\"},{\"id\":\"b\",\"label\":\"x\"}],\"part\":\"choose\"}" ==
  "{\"ids\":[\"b\"],\"indices\":[1],\"missing\":1,\"resumable\":true,\"runCap\":60}"
#guard (run "oracle.plan" "{\"rows\":[],\"part\":\"heldout\"}").startsWith "error: part"
#guard run "oracle.plan" "{\"rows\":[{\"id\":\"a\",\"label\":\"x\"},{\"id\":\"b\",\"label\":\"x\"}],\"limit\":1}" ==
  "{\"ids\":[\"a\"],\"indices\":[0],\"missing\":1,\"resumable\":true,\"runCap\":60}"
#guard (run "oracle.plan" "{\"rows\":[{\"id\":\"a\",\"label\":\"x\"}],\"logged\":[]}").startsWith "error: logged"
#guard (run "oracle.calibrate" "{\"name\":\"ci-triage\",\"replay\":[],\"answers\":[]}").endsWith "\"write\":false}"
#guard (run "oracle.calibrate" ("{\"name\":\"ci-triage\",\"replay\":[{\"id\":\"a\",\"label\":\"real\"}," ++
  "{\"id\":\"b\",\"label\":\"real\"}],\"answers\":[{\"id\":\"a\",\"reply\":\"x\"}]}")) ==
  "{\"answered\":1,\"choose\":{\"covered\":0,\"hits\":0,\"options\":[{\"advised\":0,\"hits\":0,\"option\":\"flake\"}," ++
  "{\"advised\":0,\"hits\":0,\"option\":\"infra\"},{\"advised\":0,\"hits\":0,\"option\":\"real\"}],\"rows\":1}," ++
  "\"dropped\":1,\"holdout\":{\"covered\":0,\"hits\":0,\"options\":[{\"advised\":0,\"hits\":0,\"option\":\"flake\"}," ++
  "{\"advised\":0,\"hits\":0,\"option\":\"infra\"},{\"advised\":0,\"hits\":0,\"option\":\"real\"}],\"rows\":1}," ++
  "\"labeled\":2,\"thresholds\":{\"flake\":null,\"infra\":null,\"real\":null},\"used\":0,\"write\":false}"
#guard (run "oracle.calibrate" ("{\"name\":\"ci-triage\",\"replay\":[{\"id\":\"a\",\"split\":\"heldout\",\"label\":\"real\"}]," ++
  "\"answers\":[]}")).startsWith "error: replay"
#guard (run "oracle.calibrate" ("{\"name\":\"ci-triage\",\"replay\":[{\"id\":\"a\",\"label\":\"real\"}]," ++
  "\"answers\":[{\"id\":\"a\",\"reply\":\"x\"}]}")).endsWith "\"write\":true}"
#guard run "oracle.request" "{\"name\":\"ci-triage\",\"state\":{\"log\":[\"/Users/x/y\"]}}" ==
  run "oracle.request" "{\"name\":\"ci-triage\",\"state\":{\"log\":[\"~/y\"]}}"
#guard run "oracle.budget" "{}" == "{\"dailyCap\":200,\"runCap\":60}"
#guard run "oracle.validate" ("{\"name\":\"ci-triage\",\"reply\":" ++
  (Json.str (sampleReply "real" "0.97" "0.01" "0.01" "0.01")).compress ++ "}") ==
  "{\"failure\":{\"detail\":\"choice: the pick is not the highest-probability option\",\"kind\":\"schema\"},\"ok\":false}"
#guard run "oracle.validate" ("{\"name\":\"ci-triage\",\"reply\":" ++
  (Json.str (sampleReply "real" "0.01" "0.01" "0.01" "0.97")).compress ++ "}") ==
  "{\"failure\":{\"detail\":\"choice: the pick is not the highest-probability option\",\"kind\":\"schema\"},\"ok\":false}"
#guard run "oracle.decide" ("{\"name\":\"ci-triage\",\"thresholds\":{\"flake\":{\"num\":\"1\",\"den\":\"2\"}," ++
  "\"real\":null},\"reply\":" ++ (Json.str (sampleReply "real" "0.01" "0.01" "0.97" "0.01")).compress ++ "}") ==
  "{\"action\":\"escalate\",\"gate\":{\"den\":\"25\",\"num\":\"24\"},\"reason\":{\"reason\":\"uncalibrated\"}}"
#guard (run "oracle.decide" "{\"name\":\"ci-triage\",\"thresholds\":{\"real\":{\"num\":\"0\",\"den\":\"1\"}},\"reply\":\"x\"}").startsWith "error: threshold"
#guard (run "oracle.decide" "{\"name\":\"ci-triage\",\"thresholds\":{\"real\":{\"num\":\"3\",\"den\":\"2\"}},\"reply\":\"x\"}").startsWith "error: threshold"
#guard (run "oracle.decide" "{\"name\":\"ci-triage\",\"thresholds\":{\"unknown\":{\"num\":\"1\",\"den\":\"2\"}},\"reply\":\"x\"}").startsWith "error: thresholds"
#guard run "oracle.store" "{\"text\":\"short\"}" == "{\"text\":\"short\"}"
#guard (run "oracle.eval" "{\"name\":\"ci-triage\",\"replay\":[],\"answers\":[]}").startsWith
  "{\"answered\":0,\"covered\":0,\"dropped\":0,\"hits\":0,"

end Fw.Wire.Oracle
