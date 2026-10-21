import Lean.Data.Json
import Fw.Oracle.Replay
import Fw.Oracle.Wire
/-!
# The ops `oracle.replay`, `oracle.preRun`, `oracle.score` (namespace `Fw.Wire.OracleReplay`)
Request and reply fields: docs/team/tools/oracle.md, section Replay ops.
-/
namespace Fw.Wire.OracleReplay
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat str natD arrD optN boolD)
open Fw.Wire.Oracle (ratJ numQ failureJ failureOf questionOf namesOf stateOf replayOf thresholdsJ statsJ outcomeOf)
open Fw.Oracle

/-- The registered set named by the request's `set`. -/
def setOf (req : Json) : Except String ReplaySet := do
  let n ← str req "set"
  match replaySet n with
  | some r => pure r
  | none => throw s!"set: {n} is not a registered replay set"

/-- The string fields of a dataset row. -/
def textsOf : Json → List (String × String)
  | .obj kvs => kvs.toList.filterMap fun (k, v) => match v with
    | .str s => some (k, s)
    | _ => none
  | _ => []

/-- The part named by the request (`holdout`: held out, `calibrate`: not; absent: both). -/
def partOf (req : Json) : Except String (Option Bool) :=
  match opt req "part" with
  | none => pure none
  | some v => do
    let p ← asStr "part" v
    if p == "holdout" || p == "calibrate" then pure (some (p == "holdout"))
    else throw s!"part: {p} is not holdout or calibrate"

/-- `oracle.replay`: the rows of a set to send, in send order, each with its state (`pick`, `rowState`). -/
def opReplay (req : Json) : Except String Reply := do
  let r ← setOf req
  let opts := r.question.spec.keys
  let parsed ← (← arrD req "rows").mapM fun j => do
    let i ← str j "id"
    let l := match opt j "label" with
      | some (.str l) => some l
      | _ => none
    pure (i, l, textsOf j)
  let labeled := parsed.filterMap fun (i, l, t) => l.bind fun l => if opts.contains l then some (i, l, t) else none
  let unknown := (parsed.filter (·.2.1.isSome)).length - labeled.length
  let flagged := labeled.map fun (i, l, t) => (i, l, leaks t)
  let part ← partOf req
  let cut : List (String × String) → List (String × String) := match ← optN req "limit" with
    | some n => (·.take n)
    | none => id
  let sel := cut ((pick r flagged).filter fun (i, _) => part.all (heldOut i == ·))
  let rowJ (i l : String) : Option Json := (labeled.find? (·.1 == i)).map fun (_, _, t) => Json.mkObj
    [("id", .str i), ("label", .str l), ("part", .str (if heldOut i then "holdout" else "calibrate")),
     ("state", stateJ (rowState r t))]
  pure [("set", .str r.name), ("question", .str r.question.name), ("file", .str r.file),
    ("sampled", toJson r.sampled), ("labeled", toJson labeled.length), ("unknownLabel", toJson unknown),
    ("leaking", toJson (if r.sampled then (flagged.filter (·.2.2)).length else 0)),
    ("selected", toJson sel.length), ("rows", .arr (sel.filterMap fun (i, l) => rowJ i l).toArray)]

/-- `oracle.preRun`: replay, refuse, or send with the body and its estimated tokens. -/
def opPreRun (req : Json) : Except String Reply := do
  let q ← questionOf req
  let days ← (← arrD req "days").mapM (asStr "days")
  let p := preRun defaultBudget defaultRunBudget q (← namesOf req) (← stateOf (← field req "state"))
    (← boolD req "logged" false) (← str req "today") days (← natD req "sent" 0) (← natD req "spent" 0)
  pure <| match p with
    | .replay => [("pre", "replay")]
    | .send body => [("pre", "send"), ("bodyText", .str body), ("tokens", toJson (estTokens body))]
    | .refuse f => [("pre", "refuse"), ("failure", failureJ f)]

/-- An arm answer's outcome: its failure, its Jev reply, or its validated choice. -/
def armOutcome (q : Question) (a : Json) : Except String Outcome := do
  match opt a "failure", opt a "reply", opt a "choice" with
  | some f, _, _ => pure (.failure (← failureOf f))
  | none, some t, _ => pure (outcomeOf q (← asStr "reply" t))
  | none, none, some c => do
    let pk ← asStr "choice" c
    let probs ← match opt a "probabilities" with
      | some (.obj kvs) => kvs.toList.mapM fun (k, v) => match numQ v with
        | some x => pure (k, x)
        | none => throw s!"probability {k} is not a number"
      | some _ => throw "probabilities is not an object"
      | none => pure []
    pure <| match validate q.spec { type := "choice", pick := some pk, noul := none, probs } with
      | .ok ans => .answer ans
      | .error e => .failure (.schema e)
  | none, none, none => throw "answer: needs failure, reply or choice"

/-- A named choice, kept only if it is an option of the question. -/
def choiceIn (q : Question) : Option Json → Option String
  | some (.str c) => if q.spec.keys.contains c then some c else none
  | _ => none

/-- The `choice` inside a Jev reply's answer to the question. -/
def replyChoice (q : Question) (a : Json) : Option Json :=
  match opt a "reply" with
  | some (.str t) =>
    (Json.parse t >>= (·.getObjVal? "answers") >>= (·.getObjVal? q.name) >>= (·.getObjVal? "choice")).toOption
  | _ => none

/-- The option an arm answer names: the validated pick, else the `choice` of the answer or of its Jev reply,
the same rule for every arm. -/
def pickOf (q : Question) (a : Json) (o : Outcome) : Option String :=
  match o with
  | .answer (.choice pk _) => some pk
  | _ => choiceIn q (opt a "choice" <|> replyChoice q a)

theorem choiceIn_option {q : Question} {j : Option Json} {c : String} (h : choiceIn q j = some c) :
    q.spec.keys.contains c := by
  unfold choiceIn at h
  split at h
  · split at h <;> simp_all
  · simp at h

theorem pickOf_validated (q : Question) (a : Json) (pk : String) (p) :
    pickOf q a (.answer (.choice pk p)) = some pk := rfl

theorem pickOf_fallback_option {q : Question} {a : Json} {o : Outcome} {c : String}
    (ho : ∀ pk p, o ≠ .answer (.choice pk p)) (h : pickOf q a o = some c) : q.spec.keys.contains c := by
  unfold pickOf at h
  split at h
  · exact absurd rfl (ho _ _)
  · exact choiceIn_option h

theorem pickOf_arm_eq_jev {q : Question} {a b : Json} {c : String} {f g : Failure}
    (ha : opt a "choice" = some (.str c)) (hb : opt b "choice" = none) (hr : replyChoice q b = some (.str c)) :
    pickOf q a (.failure f) = pickOf q b (.failure g) := by
  simp [pickOf, ha, hb, hr]

/-- A token count of an arm answer: its own field, else (for a Jev reply) the reply's `usage` entry, else 0. -/
def tokensOf (a : Json) (k usage : String) : Nat :=
  match opt a k with
  | some v => (v.getNat?).toOption.getD 0
  | none => match opt a "reply" with
    | some (.str t) => ((Json.parse t >>= (·.getObjVal? "usage") >>= (·.getObjVal? usage) >>= (·.getNat?)).toOption).getD 0
    | _ => 0

/-- An optional rational on the wire (null for none). -/
def optRat : Option Rat → Json
  | some x => ratJ x
  | none => .null

/-- The score of rows: right, accuracy over the rows, and per option labeled, chosen, right, precision, recall. -/
def scoreJ (opts : List String) (rs : List Scored) : Json :=
  Json.mkObj [("rows", toJson rs.length), ("answered", toJson (answeredN rs)), ("right", toJson (rightAll rs)),
    ("accuracy", optRat (ratio (rightAll rs) rs.length)),
    ("options", .arr (opts.map fun o => Json.mkObj [("option", .str o), ("labeled", toJson (labeledN rs o)),
      ("chosen", toJson (chosenN rs o)), ("right", toJson (rightN rs o)),
      ("precision", optRat (ratio (rightN rs o) (chosenN rs o))),
      ("recall", optRat (ratio (rightN rs o) (labeledN rs o)))]).toArray)]

/-- `oracle.score`: the numbers of one arm; fields in docs/team/tools/oracle.md. -/
def opScore (req : Json) : Except String Reply := do
  let q ← questionOf req
  let arm ← str req "arm"
  let price ← match armPrice arm with
    | some p => pure p
    | none => throw s!"arm: {arm} has no price"
  let labels := (← (← arrD req "replay").mapM (replayOf q.spec)).filterMap fun (i, l) => l.map (i, ·)
  let ans ← (← arrD req "answers").mapM fun a => do
    let o ← armOutcome q a
    pure (← str a "id", o, pickOf q a o, tokensOf a "inputTokens" "input_tokens",
      tokensOf a "outputTokens" "output_tokens", ← optN a "ms")
  let joined := labels.filterMap fun (i, l) => (ans.find? (·.1 == i)).map fun x => (i, l, x)
  let scored (sel : String → Bool) : List Scored :=
    (joined.filter fun (i, _) => sel i).map fun (_, l, (_, _, p, _)) => (optionName l, p)
  let rows : List IdRow := joined.filterMap fun (i, l, (_, o, _)) => match o with
    | .answer a => some (i, { answer := a, label := l })
    | .failure _ => none
  let th := certify q.spec q.target q.perOption rows
  let opts := q.spec.keys
  let all := scored fun _ => true
  let inTok := (joined.map fun (_, _, (_, _, _, t, _)) => t).sum
  let outTok := (joined.map fun (_, _, (_, _, _, _, t, _)) => t).sum
  let ms := joined.filterMap fun (_, _, (_, _, _, _, _, m)) => m
  pure [("arm", .str arm), ("question", .str q.name), ("labeled", toJson labels.length),
    ("missing", toJson (labels.length - joined.length)),
    ("all", scoreJ opts all), ("holdout", scoreJ opts (scored heldOut)),
    ("confusion", Json.mkObj [("columns", toJson (opts ++ ["failed"])),
      ("rows", .arr (opts.map fun l => Json.mkObj [("label", .str l),
        ("counts", toJson (confusionRow all opts l))]).toArray)]),
    ("thresholds", thresholdsJ q.spec th),
    ("choose", Json.mkObj (statsJ q.spec th (choosePart rows))),
    ("holdoutCert", Json.mkObj (statsJ q.spec th (holdPart rows))),
    ("minHoldout", toJson (minHoldout q.target q.perOption)),
    ("inputTokens", toJson inTok), ("outputTokens", toJson outTok), ("dollars", ratJ (dollars price inTok outTok)),
    ("msMean", optRat (meanQ ms)), ("msMedian", toJson (medianN ms)), ("msMax", toJson ms.max?)]

/-- The ops of this module. -/
def ops : List String := ["oracle.replay", "oracle.preRun", "oracle.score"]

/-- Dispatch an op of this module (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "oracle.replay" => some (opReplay req)
  | "oracle.preRun" => some (opPreRun req)
  | "oracle.score" => some (opScore req)
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

#guard run "oracle.replay" ("{\"set\":\"d1\",\"rows\":[{\"id\":\"a\",\"label\":\"c-quota\",\"title\":\"t wf_1a\"," ++
  "\"symptom\":\"s\",\"cause\":\"c\",\"split\":\"x\"},{\"id\":\"b\",\"label\":\"c-zzz\"},{\"id\":\"c\",\"label\":null}]}") ==
  "{\"file\":\"d1.jsonl\",\"labeled\":1,\"leaking\":0,\"question\":\"incident-class\",\"rows\":[{\"id\":\"a\"," ++
  "\"label\":\"c-quota\",\"part\":\"holdout\",\"state\":{\"cause\":\"c\",\"symptom\":\"s\",\"title\":\"t wf_<id>\"}}]," ++
  "\"sampled\":false,\"selected\":1,\"set\":\"d1\",\"unknownLabel\":1}"
#guard (run "oracle.replay" "{\"set\":\"d1\",\"rows\":[{\"id\":\"a\",\"label\":\"c-quota\"},{\"id\":\"b\",\"label\":\"c-quota\"}],\"part\":\"calibrate\"}").endsWith
  "\"selected\":1,\"set\":\"d1\",\"unknownLabel\":0}"
#guard (run "oracle.replay" ("{\"set\":\"d2\",\"rows\":[{\"id\":\"a\",\"label\":\"blocker\",\"what\":\"Blocker: x\"}," ++
  "{\"id\":\"e\",\"label\":\"blocker\",\"what\":\"x\"}]}")).endsWith "\"selected\":1,\"set\":\"d2\",\"unknownLabel\":0}"
#guard (run "oracle.replay" "{\"set\":\"d9\",\"rows\":[]}").startsWith "error: set"
#guard run "oracle.preRun" "{\"name\":\"incident-class\",\"state\":{\"title\":\"t\"},\"today\":\"d\",\"sent\":60}" ==
  "{\"failure\":{\"kind\":\"overBudget\"},\"pre\":\"refuse\"}"
#guard (run "oracle.preRun" "{\"name\":\"incident-class\",\"state\":{\"title\":\"t\"},\"today\":\"d\"}").startsWith
  "{\"bodyText\":"
#guard run "oracle.preRun" "{\"name\":\"incident-class\",\"state\":{\"title\":\"t\"},\"today\":\"d\",\"logged\":true}" ==
  "{\"pre\":\"replay\"}"
#guard run "oracle.score" ("{\"name\":\"finding-severity\",\"arm\":\"haiku\",\"replay\":[{\"id\":\"a\",\"label\":\"blocker\"}," ++
  "{\"id\":\"b\",\"label\":\"blocker\"},{\"id\":\"c\",\"label\":\"follow-up\"},{\"id\":\"d\",\"label\":\"follow-up\"}]," ++
  "\"answers\":[{\"id\":\"a\",\"choice\":\"blocker\",\"inputTokens\":1000,\"outputTokens\":100,\"ms\":10}," ++
  "{\"id\":\"b\",\"choice\":\"follow-up\",\"ms\":30},{\"id\":\"c\",\"failure\":{\"kind\":\"timeout\"},\"ms\":20}]}") ==
  "{\"all\":{\"accuracy\":{\"den\":\"3\",\"num\":\"1\"},\"answered\":2,\"options\":[{\"chosen\":1,\"labeled\":2," ++
  "\"option\":\"blocker\",\"precision\":{\"den\":\"1\",\"num\":\"1\"},\"recall\":{\"den\":\"2\",\"num\":\"1\"},\"right\":1}," ++
  "{\"chosen\":0,\"labeled\":0,\"option\":\"fix-before-land\",\"precision\":null,\"recall\":null,\"right\":0}," ++
  "{\"chosen\":1,\"labeled\":1,\"option\":\"follow-up\",\"precision\":{\"den\":\"1\",\"num\":\"0\"}," ++
  "\"recall\":{\"den\":\"1\",\"num\":\"0\"},\"right\":0},{\"chosen\":0,\"labeled\":0,\"option\":\"unclear\"," ++
  "\"precision\":null,\"recall\":null,\"right\":0}],\"right\":1,\"rows\":3},\"arm\":\"haiku\"," ++
  "\"choose\":{\"covered\":0,\"hits\":0,\"options\":[{\"advised\":0,\"hits\":0,\"option\":\"blocker\"}," ++
  "{\"advised\":0,\"hits\":0,\"option\":\"fix-before-land\"},{\"advised\":0,\"hits\":0,\"option\":\"follow-up\"}]}," ++
  "\"confusion\":{\"columns\":[\"blocker\",\"fix-before-land\",\"follow-up\",\"unclear\",\"failed\"],\"rows\":[" ++
  "{\"counts\":[1,0,1,0,0],\"label\":\"blocker\"},{\"counts\":[0,0,0,0,0],\"label\":\"fix-before-land\"}," ++
  "{\"counts\":[0,0,0,0,1],\"label\":\"follow-up\"},{\"counts\":[0,0,0,0,0],\"label\":\"unclear\"}]}," ++
  "\"dollars\":{\"den\":\"20000\",\"num\":\"3\"},\"holdout\":{\"accuracy\":{\"den\":\"1\",\"num\":\"1\"},\"answered\":1," ++
  "\"options\":[{\"chosen\":1,\"labeled\":1,\"option\":\"blocker\",\"precision\":{\"den\":\"1\",\"num\":\"1\"}," ++
  "\"recall\":{\"den\":\"1\",\"num\":\"1\"},\"right\":1},{\"chosen\":0,\"labeled\":0,\"option\":\"fix-before-land\"," ++
  "\"precision\":null,\"recall\":null,\"right\":0},{\"chosen\":0,\"labeled\":0,\"option\":\"follow-up\"," ++
  "\"precision\":null,\"recall\":null,\"right\":0},{\"chosen\":0,\"labeled\":0,\"option\":\"unclear\"," ++
  "\"precision\":null,\"recall\":null,\"right\":0}],\"right\":1,\"rows\":1},\"holdoutCert\":{\"covered\":0,\"hits\":0," ++
  "\"options\":[{\"advised\":0,\"hits\":0,\"option\":\"blocker\"},{\"advised\":0,\"hits\":0,\"option\":\"fix-before-land\"}," ++
  "{\"advised\":0,\"hits\":0,\"option\":\"follow-up\"}]},\"inputTokens\":1000,\"labeled\":4,\"minHoldout\":25," ++
  "\"missing\":1,\"msMax\":30,\"msMean\":{\"den\":\"1\",\"num\":\"20\"},\"msMedian\":20,\"outputTokens\":100," ++
  "\"question\":\"finding-severity\",\"thresholds\":{\"blocker\":null,\"fix-before-land\":null,\"follow-up\":null}}"
#guard
  let probs := Json.mkObj [("blocker", .num ⟨60, 2⟩), ("fix-before-land", .num ⟨20, 2⟩),
    ("follow-up", .num ⟨10, 2⟩), ("unclear", .num ⟨9, 2⟩)]
  let jevAns := Json.mkObj [("type", .str "choice"), ("choice", .str "blocker"), ("probabilities", probs),
    ("confidence", .num ⟨5, 1⟩)]
  let reply := Json.mkObj [("model", .str model), ("answers", Json.mkObj [("finding-severity", jevAns)])]
  let req (arm : String) (a : Json) := Json.mkObj [("name", .str "finding-severity"), ("arm", .str arm),
    ("replay", .arr #[Json.mkObj [("id", .str "a"), ("label", .str "blocker")]]), ("answers", .arr #[a])]
  let part (arm : String) (a : Json) (k : String) :=
    (Json.parse (run "oracle.score" (req arm a).compress) >>= (·.getObjVal? k)).toOption
  let jev := Json.mkObj [("id", .str "a"), ("reply", .str reply.compress)]
  let haiku := Json.mkObj [("id", .str "a"), ("choice", .str "blocker"), ("probabilities", probs)]
  let rejected := match questionOf (req "jev" jev) >>= fun q => armOutcome q jev with
    | .ok (.failure (.schema _)) => true
    | _ => false
  rejected && ["all", "holdout", "confusion"].all (fun k => part "jev" jev k == part "haiku" haiku k) &&
    ((part "jev" jev "all").bind fun j => (j.getObjVal? "right").toOption) == some (toJson 1)
#guard (run "oracle.score" "{\"name\":\"finding-severity\",\"arm\":\"gpt\",\"replay\":[],\"answers\":[]}").startsWith
  "error: arm"

end Fw.Wire.OracleReplay
