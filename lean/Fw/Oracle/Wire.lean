import Lean.Data.Json
import Fw.Oracle.Core
import Fw.Oracle.Calibrate
import Fw.Oracle.Redact
import Fw.Oracle.Send
import Fw.Oracle.Triage
import Fw.Ops.Wire
/-!
# JSON codecs and the ops `oracle.*` (typed answers from an outside model, and what we do with them)

Glue between `fwcore`'s JSON lines and `Fw.Oracle` (namespace `Fw.Wire.Oracle`, so the math view treats it as wire
code). The TypeScript client (`packages/oracle`) holds no decision: it asks `oracle.request` for the exact body
(the state redacted here), hashes that text, asks `oracle.pre` whether to replay, refuse or send, reads the key and
sends only on `send`, and passes the reply text (or the failure) to `oracle.decide`.

| op | request | reply |
|---|---|---|
| `oracle.question` | `name` | `name`, `model`, `spec`, `target`, `minRows` |
| `oracle.redact` | `names`?, `text` | `text` |
| `oracle.triage.state` | `workflow`, `lines` [string] | `state` (not yet redacted) |
| `oracle.request` | `name`, `names`?, `state` | `bodyText` (send these bytes), `state` (redacted) |
| `oracle.pre` | `names`?, `state`, `logged`, `today`, `days` [string], `run`? | `pre` replay/refuse/send, `failure`? |
| `oracle.validate` | `name`, `reply` (the response body text) | `ok`, then `answer` and `gate`, or `failure` |
| `oracle.decide` | `name`, `threshold` (rational or null), `reply` or `failure` | `action`, `advice`? `reason`? `gate`? |
| `oracle.calibrate` | `name`, `rows` [{`reply`, `label`}], `target`?, `minRows`? | `threshold`, `covered`, `hits`, `used`, `dropped` |
| `oracle.budget` | (nothing) | `dailyCap`, `runCap` |

Shapes. Rational: `{"num":"<int>","den":"<positive int>"}`. State: an object of field to string or array of strings
(a one-line field is written as a string). Failure: `{kind: timeout|http|malformed|schema|overBudget|noKey|
unredacted, status?, detail?}`. Answer: `{type, pick?, p?, dist?}`. Advice: `{kind: pick|yes|no|level, value?}`.
Reason: `{reason: failure|uncalibrated|below|noMatch, failure?, gate?, threshold?}`. A reply's numbers are decimal
fractions converted exactly (mantissa / 10^exponent). A reply that is not JSON is `malformed`; one that is JSON but
has no answer of the right shape (or a model other than the pinned one) is a `schema` failure.
-/
namespace Fw.Wire.Oracle
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD ostr optN)
open Fw.Oracle

/-! ## Codecs -/

/-- A rational on the wire. -/
def ratJ (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

/-- A rational from the wire. -/
def ratOf (j : Json) : Except String Rat := do
  let n ← str j "num"
  let d ← str j "den"
  match n.toInt?, d.toNat? with
  | some n, some d => if d = 0 then throw "rational: den must be positive" else pure (mkRat n d)
  | _, _ => throw "rational: num and den must be decimal integer strings"

/-- A JSON number as an exact rational (`none` for anything else). -/
def numQ : Json → Option Rat
  | .num n => some (mkRat n.mantissa (10 ^ n.exponent))
  | _ => none

/-- An answer space on the wire. -/
def specJ : Spec → Json
  | .choice os z => Json.mkObj [("type", "choice"), ("options", toJson os), ("noMatch", .str z)]
  | .noul => Json.mkObj [("type", "noul")]
  | .score ls => Json.mkObj [("type", "score"), ("levels", toJson ls)]

/-- An answer on the wire. -/
def answerJ : Answer → Json
  | .choice pk d => Json.mkObj [("type", "choice"), ("pick", .str pk), ("dist", .arr (d.map ratJ).toArray)]
  | .noul p => Json.mkObj [("type", "noul"), ("p", ratJ p)]
  | .score d => Json.mkObj [("type", "score"), ("dist", .arr (d.map ratJ).toArray)]

/-- A failure on the wire. -/
def failureJ : Failure → Json
  | .timeout => Json.mkObj [("kind", "timeout")]
  | .http s => Json.mkObj [("kind", "http"), ("status", toJson s)]
  | .malformed => Json.mkObj [("kind", "malformed")]
  | .schema d => Json.mkObj [("kind", "schema"), ("detail", .str d)]
  | .overBudget => Json.mkObj [("kind", "overBudget")]
  | .noKey => Json.mkObj [("kind", "noKey")]
  | .unredacted => Json.mkObj [("kind", "unredacted")]

/-- A failure from the wire. -/
def failureOf (j : Json) : Except String Failure := do
  match ← str j "kind" with
  | "timeout" => pure .timeout
  | "http" => pure (.http (← nat j "status"))
  | "malformed" => pure .malformed
  | "schema" => pure (.schema (← strD j "detail" ""))
  | "overBudget" => pure .overBudget
  | "noKey" => pure .noKey
  | "unredacted" => pure .unredacted
  | k => throw s!"failure: unknown kind {k}"
where strD (j : Json) (k d : String) : Except String String :=
  match opt j k with
  | none => .ok d
  | some v => asStr k v

/-- An advice on the wire. -/
def adviceJ : Advice → Json
  | .pick o => Json.mkObj [("kind", "pick"), ("value", .str o)]
  | .yes => Json.mkObj [("kind", "yes")]
  | .no => Json.mkObj [("kind", "no")]
  | .level i => Json.mkObj [("kind", "level"), ("value", toJson i)]

/-- A label from the wire, read against the answer space: an option name (choice), `yes`/`no` (noul), or a level
index (score). -/
def labelOf (s : Spec) (j : Json) : Except String Advice :=
  match s, j with
  | .choice os _, .str o => if os.contains o then .ok (.pick o) else .error s!"label: {o} is not an option"
  | .noul, .str "yes" => .ok .yes
  | .noul, .str "no" => .ok .no
  | .score ls, v => do
    let i ← asNat "label" v
    if i < ls.length then pure (.level i) else throw "label: level out of range"
  | _, _ => .error "label: does not fit the question"

/-- A reason on the wire. -/
def reasonJ : Reason → Json
  | .failure f => Json.mkObj [("reason", "failure"), ("failure", failureJ f)]
  | .uncalibrated => Json.mkObj [("reason", "uncalibrated")]
  | .below g t => Json.mkObj [("reason", "below"), ("gate", ratJ g), ("threshold", ratJ t)]
  | .noMatch => Json.mkObj [("reason", "noMatch")]

/-- An action as reply fields. -/
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

/-- A state on the wire (a one-line field as a string). -/
def stateJ (st : State) : Json :=
  Json.mkObj (st.map fun (k, ls) => (k, match ls with
    | [s] => .str s
    | _ => .arr (ls.map Json.str).toArray))

/-- The names to redact (optional, default none). -/
def namesOf (req : Json) : Except String (List String) := do
  (← arrD req "names").mapM (asStr "names")

/-- The registered question named in the request. -/
def questionOf (req : Json) : Except String Question := do
  let n ← str req "name"
  match question n with
  | some q => pure q
  | none => throw s!"unknown question {n}"

/-- The criteria of a question as the API wants them: an option map (choice), `true`/`false` meanings (noul), the
level list (score). -/
def criteriaJ (q : Question) : Json :=
  match q.spec with
  | .score ls => toJson ls
  | _ => Json.mkObj (q.criteria.map fun (k, v) => (k, Json.str v))

/-- The request body for a question and a (redacted) state. -/
def bodyJ (q : Question) (st : State) : Json :=
  Json.mkObj [("state", stateJ st), ("model", .str model),
    ("questions", Json.mkObj [(q.name, Json.mkObj [
      ("type", .str (match q.spec with | .choice .. => "choice" | .noul => "noul" | .score _ => "score")),
      ("instructions", .str q.instructions), ("criteria", criteriaJ q)])])]

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

/-- The outcome of a reply text: `malformed` when it is not JSON, `schema` when it has no fitting answer, else the
validated answer. -/
def outcomeOf (q : Question) (text : String) : Outcome :=
  match Json.parse text with
  | .error _ => .failure .malformed
  | .ok body =>
    match rawOf q body >>= validate q.spec with
    | .ok a => .answer a
    | .error e => .failure (.schema e)

/-- The outcome named by a request: its `failure`, else its `reply` text. -/
def requestOutcome (q : Question) (req : Json) : Except String Outcome := do
  match opt req "failure" with
  | some f => pure (.failure (← failureOf f))
  | none => pure (outcomeOf q (← str req "reply"))

/-! ## Ops -/

/-- `oracle.question`: a registered question. -/
def opQuestion (req : Json) : Except String Reply := do
  let q ← questionOf req
  pure [("name", .str q.name), ("model", .str model), ("spec", specJ q.spec), ("target", ratJ q.target),
    ("minRows", toJson q.minRows)]

/-- `oracle.redact`: one text redacted. -/
def opRedact (req : Json) : Except String Reply := do
  pure [("text", .str (redact (← namesOf req) (← str req "text")))]

/-- `oracle.triage.state`: the CI-triage state of a failed run (not yet redacted). -/
def opTriageState (req : Json) : Except String Reply := do
  let lines ← (← arr req "lines").toList.mapM (asStr "lines")
  pure [("state", stateJ (triageState (← str req "workflow") lines))]

/-- `oracle.request`: the exact body to send, with the state redacted. -/
def opRequest (req : Json) : Except String Reply := do
  let q ← questionOf req
  let st := redactState (← namesOf req) (← stateOf (← field req "state"))
  pure [("bodyText", .str (bodyJ q st).compress), ("state", stateJ st)]

/-- `oracle.pre`: replay, refuse or send. -/
def opPre (req : Json) : Except String Reply := do
  let days ← (← arrD req "days").mapM (asStr "days")
  let p := pre defaultBudget (← namesOf req) (← stateOf (← field req "state")) (← boolD req "logged" false)
    (← str req "today") days (← optN req "run")
  pure <| match p with
    | .replay => [("pre", "replay")]
    | .send => [("pre", "send")]
    | .refuse f => [("pre", "refuse"), ("failure", failureJ f)]

/-- `oracle.validate`: the validated answer and its gate value, or the failure. -/
def opValidate (req : Json) : Except String Reply := do
  let q ← questionOf req
  pure <| match outcomeOf q (← str req "reply") with
    | .answer a => [("ok", true), ("answer", answerJ a), ("gate", ratJ (gate a))]
    | .failure f => [("ok", false), ("failure", failureJ f)]

/-- `oracle.decide`: the policy's action. -/
def opDecide (req : Json) : Except String Reply := do
  let q ← questionOf req
  let t ← match opt req "threshold" with
    | none => pure none
    | some j => some <$> ratOf j
  let o ← requestOutcome q req
  let g := match o with
    | .answer a => [("gate", ratJ (gate a))]
    | .failure _ => []
  pure (actionFields (policy q.spec t o) ++ g)

/-- `oracle.calibrate`: the threshold from labeled replies (rows whose reply fails validation are left out and
counted as `dropped`). -/
def opCalibrate (req : Json) : Except String Reply := do
  let q ← questionOf req
  let target ← match opt req "target" with
    | none => pure q.target
    | some j => ratOf j
  let n ← natD req "minRows" q.minRows
  let rows ← (← arrD req "rows").mapM fun r => do
    let label ← labelOf q.spec (← field r "label")
    pure (match outcomeOf q (← str r "reply") with
      | .answer a => some ({ answer := a, label } : Row)
      | .failure _ => none)
  let used := rows.filterMap id
  let th := calibrate q.spec target n used
  let (cov, hit) := match th with
    | some τ => (covered q.spec τ used, hits q.spec τ used)
    | none => (0, 0)
  pure [("threshold", match th with | some τ => ratJ τ | none => .null), ("covered", toJson cov),
    ("hits", toJson hit), ("used", toJson used.length), ("dropped", toJson (rows.length - used.length))]

/-- `oracle.budget`: the spend guard. -/
def opBudget (_ : Json) : Except String Reply :=
  pure [("dailyCap", toJson defaultBudget.dailyCap), ("runCap", toJson defaultBudget.runCap)]

/-- The ops of this module. -/
def ops : List String :=
  ["oracle.question", "oracle.redact", "oracle.triage.state", "oracle.request", "oracle.pre", "oracle.validate",
   "oracle.decide", "oracle.calibrate", "oracle.budget"]

/-- Dispatch an `oracle.*` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "oracle.question" => some (opQuestion req)
  | "oracle.redact" => some (opRedact req)
  | "oracle.triage.state" => some (opTriageState req)
  | "oracle.request" => some (opRequest req)
  | "oracle.pre" => some (opPre req)
  | "oracle.validate" => some (opValidate req)
  | "oracle.decide" => some (opDecide req)
  | "oracle.calibrate" => some (opCalibrate req)
  | "oracle.budget" => some (opBudget req)
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

#guard run "oracle.decide" ("{\"name\":\"ci-triage\",\"threshold\":null,\"reply\":" ++
  (Json.str (sampleReply "real" "0.01" "0.01" "0.97" "0.01")).compress ++ "}") ==
  "{\"action\":\"escalate\",\"gate\":{\"den\":\"25\",\"num\":\"24\"},\"reason\":{\"reason\":\"uncalibrated\"}}"
#guard run "oracle.decide" ("{\"name\":\"ci-triage\",\"threshold\":{\"num\":\"1\",\"den\":\"2\"},\"reply\":" ++
  (Json.str (sampleReply "real" "0.01" "0.01" "0.97" "0.01")).compress ++ "}") ==
  "{\"action\":\"advise\",\"advice\":{\"kind\":\"pick\",\"value\":\"real\"},\"gate\":{\"den\":\"25\",\"num\":\"24\"}}"
#guard run "oracle.decide" "{\"name\":\"ci-triage\",\"threshold\":null,\"reply\":\"not json\"}" ==
  "{\"action\":\"escalate\",\"reason\":{\"failure\":{\"kind\":\"malformed\"},\"reason\":\"failure\"}}"
#guard run "oracle.decide" "{\"name\":\"ci-triage\",\"failure\":{\"kind\":\"noKey\"}}" ==
  "{\"action\":\"escalate\",\"reason\":{\"failure\":{\"kind\":\"noKey\"},\"reason\":\"failure\"}}"
#guard run "oracle.pre" "{\"state\":{\"log\":[\"/Users/x/y\"]},\"today\":\"d\"}" ==
  "{\"failure\":{\"kind\":\"unredacted\"},\"pre\":\"refuse\"}"
#guard run "oracle.request" "{\"name\":\"ci-triage\",\"state\":{\"log\":[\"/Users/x/y\"]}}" ==
  run "oracle.request" "{\"name\":\"ci-triage\",\"state\":{\"log\":[\"~/y\"]}}"
#guard run "oracle.budget" "{}" == "{\"dailyCap\":200,\"runCap\":60}"

end Fw.Wire.Oracle
