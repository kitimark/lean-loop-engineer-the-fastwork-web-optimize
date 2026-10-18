import Lean.Data.Json
import Fw.Ci.Budget
import Fw.Ci.Verdict
import Fw.Ci.Intent
import Fw.Ops.Wire
/-!
# JSON codecs and the ops `ci.budget.*` (the GitHub request budget of the CI poller)

Glue between `fwcore`'s JSON lines and `Fw.Ci.Budget` (namespace `Fw.Wire.Ci`, so the math view treats it as wire
code). The limits are always `Fw.Ci.Budget.defaults`; the caller never restates them (`ci.budget.limits` returns
them, and `packages/contracts/golden/ci-budget/limits.json` holds them). Times are integer seconds since the epoch.
Every request carries `now`; `state` is optional (absent or `null`: `init now`); the clock event `now` is applied to
it first (the clock never goes back, entries older than an hour are pruned). The caller stores the returned `state`
and passes it to the next call.

| op | request | reply |
|---|---|---|
| `ci.budget.reserve` | `now`, `state`?, `cost` | Decision |
| `ci.budget.next` | `now`, `state`? | Decision, and on `issue` also `createdSince` (n or null) |
| `ci.budget.observe` | `now`, `state`?, `lines` [string], `actual`? | `state`, `headers` Headers, `actual` |
| `ci.budget.step` | `now`, `state`?, `event` Event | `state` |
| `ci.budget.status` | `now`, `state`? | `limits`, `shares`, `used`, `interval`, `headroom`, `retryUntil`, `fails`, `watched`, `createdSince`, `state` |
| `ci.budget.limits` | (nothing) | `limits` |
| `ci.verdict` | `runs` [Facts] | `runs` [{`verdict`, `code`, `reason`}], `verdict`, `code` (`Fw.Ci.Verdict.combine`) |
| `ci.verdict` | `msg` (null: unknown), `lanes` {name: Facts or null} | `lanes` [{`name`, `verdict`, `code`, `reason`}], `verdict`, `code` (`Fw.Ci.Verdict.waitVerdict`) |
| `ci.required` | `msg` (null: unknown) | `lanes` [name] (`Fw.Ci.Intent.wanted`, table order); unknown: `lanes` null, `verdict`, `code`, `reason` |

Facts: `{guard, steps:[{name, conclusion}], jobs:[conclusion], heavySteps:[{name, conclusion}]}` (`heavySteps`: the
steps of every non-guard job, read for the tip re-check's `stale:` step).

Shapes. Decision: `{decision:"issue", kind:"tick"|"oneoff", cost, state}` (the state with the charge booked; on a
tick every watched run is covered), `{decision:"wait", until, reason, state}` or `{decision:"stop", reason, state}`;
reason ∈ `failures idle tooBig retryAfter floor hour minute interval`. State: `{now, ledger:[{time, cost,
kind, charged}], remaining, reset, retryUntil, fails, etag, watched:[{runId, createdAt, lastCovered}], lastTick,
pending:{kind, cost}|null, pages}` (`remaining reset etag lastTick lastCovered` may be null; every field but `now` is
optional on input). Headers: `{status, remaining, reset, retryAfter, etag}` (null when absent). `lines` are the
response header lines of `gh api --include` (or `curl -i`), one per element, `< ` prefixes allowed; `actual` (default:
the number of status lines, i.e. responses) is the number of requests the call really made. Event: `{register:{runId,
createdAt}}`, `{unregister:runId}`, `{pages:n}` or `{resume:true}`.
-/
namespace Fw.Wire.Ci
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD ostr optN)
open Fw.Ci.Budget

/-- A natural number as JSON. -/
def jn (n : Nat) : Json := toJson n

/-- An optional natural number as JSON (`null` when absent). -/
def ojn : Option Nat → Json
  | some n => jn n
  | none => .null

/-- An optional string field (absent or `null`: `none`). -/
def optStr (j : Json) (k : String) : Except String (Option String) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asStr k v

/-! ## Names -/

/-- The name of a kind. -/
def kindName : Kind → String
  | .tick => "tick"
  | .oneoff => "oneoff"

/-- A kind from its name. -/
def kindOf (k : String) : String → Except String Kind
  | "tick" => .ok .tick
  | "oneoff" => .ok .oneoff
  | v => .error s!"field {k}: unknown value {v}"

/-- The name of a reason. -/
def reasonName : Reason → String
  | .failures => "failures"
  | .idle => "idle"
  | .tooBig => "tooBig"
  | .retryAfter => "retryAfter"
  | .floor => "floor"
  | .hour => "hour"
  | .minute => "minute"
  | .interval => "interval"

/-! ## Codecs -/

/-- A ledger entry as JSON. -/
def entryJson (e : Entry) : Json :=
  Json.mkObj [("time", jn e.time), ("cost", jn e.cost), ("kind", .str (kindName e.kind)), ("charged", .bool e.charged)]

/-- A ledger entry from JSON. -/
def entryOf (j : Json) : Except String Entry := do
  pure { time := ← nat j "time", cost := ← nat j "cost", kind := ← kindOf "kind" (← str j "kind"),
         charged := ← asBool "charged" (← field j "charged") }

/-- A watched run as JSON. -/
def watchJson (w : Watch) : Json :=
  Json.mkObj [("runId", jn w.runId), ("createdAt", jn w.createdAt), ("lastCovered", ojn w.lastCovered)]

/-- A watched run from JSON. -/
def watchOf (j : Json) : Except String Watch := do
  pure { runId := ← nat j "runId", createdAt := ← nat j "createdAt", lastCovered := ← optN j "lastCovered" }

/-- The call in flight as JSON. -/
def pendingJson : Option (Kind × Nat) → Json
  | some (k, c) => Json.mkObj [("kind", .str (kindName k)), ("cost", jn c)]
  | none => .null

/-- The call in flight from JSON. -/
def pendingOf (j : Json) : Except String (Option (Kind × Nat)) :=
  match opt j "pending" with
  | none => .ok none
  | some p => do pure (some (← kindOf "kind" (← str p "kind"), ← nat p "cost"))

/-- The state as JSON. -/
def stateJson (s : State) : Json :=
  Json.mkObj [("now", jn s.now), ("ledger", .arr (s.ledger.map entryJson).toArray), ("remaining", ojn s.remaining),
    ("reset", ojn s.reset), ("retryUntil", jn s.retryUntil), ("fails", jn s.fails), ("etag", ostr s.etag),
    ("watched", .arr (s.watched.map watchJson).toArray), ("lastTick", ojn s.lastTick),
    ("pending", pendingJson s.pending), ("pages", jn s.pages)]

/-- The state from JSON (every field but `now` optional, with the `init` defaults). -/
def stateOf (j : Json) : Except String State := do
  pure { now := ← nat j "now", ledger := ← (← arrD j "ledger").mapM entryOf, remaining := ← optN j "remaining",
         reset := ← optN j "reset", retryUntil := ← natD j "retryUntil" 0, fails := ← natD j "fails" 0,
         etag := ← optStr j "etag", watched := ← (← arrD j "watched").mapM watchOf, lastTick := ← optN j "lastTick",
         pending := ← pendingOf j, pages := ← natD j "pages" 1 }

/-- Headers as JSON. -/
def headersJson (h : Headers) : Json :=
  Json.mkObj [("status", jn h.status), ("remaining", ojn h.remaining), ("reset", ojn h.reset),
    ("retryAfter", ojn h.retryAfter), ("etag", ostr h.etag)]

/-- The limits as JSON, with the two shares of each window. -/
def limitsJson (L : Limits) : Json :=
  Json.mkObj [("W", jn L.W), ("B", jn L.B), ("R", jn L.R), ("W1", jn L.W1), ("B1", jn L.B1), ("R1", jn L.R1),
    ("F", jn L.F), ("Pmin", jn L.Pmin), ("back0", jn L.back0), ("backMax", jn L.backMax),
    ("maxFails", jn L.maxFails), ("listCost", jn L.listCost),
    ("shares", Json.mkObj [("tick", Json.mkObj [("hour", jn (share L .tick)), ("minute", jn (share1 L .tick))]),
                           ("oneoff", Json.mkObj [("hour", jn (share L .oneoff)), ("minute", jn (share1 L .oneoff))])])]

/-- An event from JSON (exactly one of `register`, `unregister`, `pages`, `resume`). -/
def eventOf (j : Json) : Except String Event :=
  match opt j "register", opt j "unregister", opt j "pages", opt j "resume" with
  | some r, none, none, none => do pure (.register (← nat r "runId") (← nat r "createdAt"))
  | none, some r, none, none => do pure (.unregister (← asNat "unregister" r))
  | none, none, some n, none => do pure (.pages (← asNat "pages" n))
  | none, none, none, some b => do
    if ← asBool "resume" b then pure .resume else .error "field resume: expected true"
  | _, _, _, _ => .error "field event: expected exactly one of register, unregister, pages, resume"

/-! ## Ops -/

/-- The request's state with its clock applied (absent state: `init now`). -/
def clocked (req : Json) : Except String State := do
  let now ← nat req "now"
  let s ← match opt req "state" with
    | none => pure (init now)
    | some j => stateOf j
  pure (step defaults s (.clock now))

/-- A decision as reply fields; `s` is the state a `wait` or `stop` returns. -/
def decisionReply (s : State) : Decision → Reply
  | .issue k c s' => [("decision", .str "issue"), ("kind", .str (kindName k)), ("cost", jn c), ("state", stateJson s')]
  | .wait u r => [("decision", .str "wait"), ("until", jn u), ("reason", .str (reasonName r)), ("state", stateJson s)]
  | .stop r => [("decision", .str "stop"), ("reason", .str (reasonName r)), ("state", stateJson s)]

/-- `ci.budget.reserve`: may a one-off call of `cost` requests go now? -/
def opReserve (req : Json) : Except String Reply := do
  let s ← clocked req
  let c ← nat req "cost"
  pure (decisionReply s (reserve defaults s c))

/-- `ci.budget.next`: the shared poller's decision; a tick lists the runs created since `createdSince`. -/
def opNext (req : Json) : Except String Reply := do
  let s ← clocked req
  match next defaults s with
  | d@(.issue _ _ s') => pure (decisionReply s d ++ [("createdSince", ojn (since s'))])
  | d => pure (decisionReply s d)

/-- `ci.budget.observe`: fold the response headers of the call in flight into the state. -/
def opObserve (req : Json) : Except String Reply := do
  let s ← clocked req
  let ls ← (← arr req "lines").toList.mapM (asStr "lines")
  let (h, n) := parse ls
  let a ← natD req "actual" n
  pure [("state", stateJson (step defaults s (.response h a))), ("headers", headersJson h), ("actual", jn a)]

/-- `ci.budget.step`: register or unregister a run, set the pages of a tick, or resume after a stop. -/
def opStep (req : Json) : Except String Reply := do
  let s ← clocked req
  let e ← eventOf (← field req "event")
  pure [("state", stateJson (step defaults s e))]

/-- The window sums of one kind: charged and corrections, per hour and per minute. -/
def usedJson (s : State) (k : Kind) : Json :=
  let L := defaults
  Json.mkObj [("hour", jn (wsum L.W s.now (chargedOf k) s.ledger)), ("minute", jn (wsum L.W1 s.now (chargedOf k) s.ledger)),
    ("hourCorrections", jn (wsum L.W s.now (corrOf k) s.ledger)),
    ("minuteCorrections", jn (wsum L.W1 s.now (corrOf k) s.ledger))]

/-- `ci.budget.status`: the limits, the window sums, the interval and the guards. -/
def opStatus (req : Json) : Except String Reply := do
  let s ← clocked req
  let L := defaults
  pure [("limits", limitsJson L), ("used", Json.mkObj [("tick", usedJson s .tick), ("oneoff", usedJson s .oneoff)]),
    ("interval", jn (interval L s)), ("headroom", .bool (headroom L s)), ("retryUntil", jn s.retryUntil),
    ("fails", jn s.fails), ("watched", jn s.watched.length), ("createdSince", ojn (since s)), ("state", stateJson s)]

/-- `ci.budget.limits`: the limits (`Fw.Ci.Budget.defaults`). -/
def opLimits (_req : Json) : Except String Reply := pure [("limits", limitsJson defaults)]

/-! ## `ci.verdict` (`Fw.Ci.Verdict`) -/

/-- A conclusion field: the conclusion its text names; absent or `null` (e.g. still running) reads as `""`, which
folds to failure.
$$\forall j, k:\ \operatorname{concl}(j, k) = \operatorname{conclOf}(j[k]\ \text{if a string, else } \texttt{""})$$ -/
def conclField (j : Json) (k : String) : Except String Fw.Ci.Verdict.Concl := do
  pure (Fw.Ci.Verdict.conclOf ((← optStr j k).getD ""))

/-- A guard step `{name, conclusion}`.
$$\forall j:\ \operatorname{step}(j) = (j.\mathit{name},\ \operatorname{concl}(j, \texttt{conclusion}))$$ -/
def stepOf (j : Json) : Except String (String × Fw.Ci.Verdict.Concl) := do
  pure (← str j "name", ← conclField j "conclusion")

/-- One run's verdict as JSON: `{verdict, code, reason}`. Below $T$, $J$, $H$ are the run's `steps`, `jobs` and
`heavySteps` (absent: empty), and a `guard` key that is absent reads as success.
$$\forall j:\ \operatorname{runV}(j) = \operatorname{verdict}(g,\ \operatorname{decOf}(T),\ J,\ \operatorname{staleOf}(H)),\ g = \begin{cases} \mathrm{success} & \texttt{guard} \notin j \\ \operatorname{concl}(j, \texttt{guard}) & \text{otherwise} \end{cases}$$ -/
def runVerdict (j : Json) : Except String (Fw.Ci.Verdict.Verdict × Json) := do
  -- no `guard` key: the run's workflow has no guard job (a branch based before task ci-trigger-lean), so nothing was
  -- decided away and the guard counts as `success`; a present key (also `null`) is read as a conclusion
  let g ← match j.getObjVal? "guard" with
    | .error _ => pure Fw.Ci.Verdict.Concl.success
    | .ok _ => conclField j "guard"
  let steps ← (← arrD j "steps").mapM stepOf
  let jobs ← (← arrD j "jobs").mapM fun v => do pure (Fw.Ci.Verdict.conclOf (← asStr "jobs" v))
  let stale := Fw.Ci.Verdict.staleOf (← (← arrD j "heavySteps").mapM stepOf)
  let v := Fw.Ci.Verdict.verdict ⟨g, Fw.Ci.Verdict.decisionOf steps, jobs, stale⟩
  let reason := if v == .notRun then Fw.Ci.Verdict.reasonOf g stale steps else ""
  pure (v, Json.mkObj [("verdict", .str (Fw.Ci.Verdict.name v)), ("code", jn (Fw.Ci.Verdict.code v)),
    ("reason", .str reason)])

/-- One lane of a branch wait: `{name, verdict, code, reason}`; a lane without a run (`null` or absent) is `missing`
(code 4, verdict `none`). The skip kind is the one its reason names.
$$\forall F, \ell:\ \operatorname{laneV}(F, \ell) = \begin{cases} (\mathrm{none},\ \mathrm{none}) & F[\ell.n] \in \{\text{absent}, \texttt{null}\} \\ (\mathrm{some}(v),\ \operatorname{skipOf}(s)) & \text{otherwise, with } (v, s) \text{ the verdict and reason of } \operatorname{runV}(F[\ell.n]) \end{cases}$$ -/
def laneVerdict (lanes : Json) (l : Fw.Ci.Intent.Lane) : Except String (Fw.Ci.Verdict.LaneRun × Json) := do
  match lanes.getObjVal? l.name with
  | .error _ | .ok .null =>
    pure (⟨none, none⟩, Json.mkObj [("name", .str l.name), ("verdict", "missing"), ("code", jn 4),
      ("reason", "no run of this lane for the commit")])
  | .ok f =>
    let (v, j) ← runVerdict f
    let reason := (j.getObjValAs? String "reason").toOption.getD ""
    pure (⟨some v, Fw.Ci.Verdict.skipOf reason⟩, j.setObjVal! "name" (.str l.name))

/-- The reply fields of a wait whose request is unknown, after `pre`: the verdict $\operatorname{wait}(\mathrm{none})$
(not run), its code and a reason.
$$\forall P:\ \operatorname{unknown}(P) = P \mathbin{+\!\!+} [\texttt{verdict}: \operatorname{wait}(\mathrm{none}),\ \texttt{code}: \operatorname{code}(\operatorname{wait}(\mathrm{none})),\ \texttt{reason}]$$ -/
def unknownReply (pre : Reply) : Reply :=
  pre ++ [("verdict", .str (Fw.Ci.Verdict.name (Fw.Ci.Verdict.waitVerdict none))),
    ("code", jn (Fw.Ci.Verdict.code (Fw.Ci.Verdict.waitVerdict none))),
    ("reason", "unknown request: the head commit's message could not be read (fetch the commit)")]

/-- `ci.verdict`. Runs mode: request `{runs:[Facts]}` (`guard`: the guard job's conclusion, the key absent when the
workflow has no guard job, `null` while it runs; `steps`: its steps; `jobs`: every other job's conclusion;
`heavySteps`: their steps); reply `{runs:[{verdict, code, reason}], verdict, code}` with the combined verdict
(`Fw.Ci.Verdict.combine`). Lanes mode (a `lanes` key): request `{msg, lanes:{name: Facts or null}}` with the newest run
of each lane for one commit; reply `{lanes:[{name, verdict, code, reason}], verdict, code}` over `waitLanes msg` (the
requested lanes and lean), combined by `Fw.Ci.Verdict.waitVerdict` (`Fw.Ci.Intent.wait_needs_default_pass`); `msg`
absent or `null` (the message could not be read) gives `lanes` `[]`, verdict not run and `reason`
(`unknown_request_never_pass`).
$$\forall m, F:\ \operatorname{verdict}_{\mathrm{lanes}}(m, F) = \begin{cases} \operatorname{wait}(\mathrm{none}) & m \in \{\text{absent}, \texttt{null}\} \\ \operatorname{wait}\bigl(\mathrm{some}([\, \operatorname{laneV}(F, \ell) : \ell \in \operatorname{waitLanes}(m) \,])\bigr) & \text{otherwise} \end{cases} \qquad \forall \vec{\jmath}:\ \operatorname{verdict}_{\mathrm{runs}}(\vec{\jmath}) = \operatorname{combine}([\, \operatorname{runV}(j) : j \in \vec{\jmath} \,])$$ -/
def opVerdict (req : Json) : Except String Reply := do
  match req.getObjVal? "lanes" with
  | .ok lanes =>
    match ← optStr req "msg" with
    | none => pure (unknownReply [("lanes", .arr #[])])
    | some msg =>
      let rs ← (Fw.Ci.Intent.waitLanes msg).mapM (laneVerdict lanes)
      let v := Fw.Ci.Verdict.waitVerdict (some (rs.map (·.1)))
      pure [("lanes", .arr (rs.map (·.2)).toArray), ("verdict", .str (Fw.Ci.Verdict.name v)),
        ("code", jn (Fw.Ci.Verdict.code v))]
  | .error _ =>
    let rs ← (← arrD req "runs").mapM runVerdict
    let v := Fw.Ci.Verdict.combine (rs.map (·.1))
    pure [("runs", .arr (rs.map (·.2)).toArray), ("verdict", .str (Fw.Ci.Verdict.name v)),
      ("code", jn (Fw.Ci.Verdict.code v))]

/-- `ci.required`: request `{msg}`; reply `{lanes:[name]}`, the names of `waitLanes msg` in table order. `msg` absent
or `null` (the message could not be read): reply `{lanes:null, verdict, code, reason}` with the verdict of an unknown
request (not run), so the caller stops without waiting.
$$\forall m:\ \operatorname{required}(m) = \begin{cases} \mathrm{null} & m \in \{\text{absent}, \texttt{null}\} \\ [\, \ell.n : \ell \in \operatorname{waitLanes}(m) \,] & \text{otherwise} \end{cases}$$ -/
def opRequired (req : Json) : Except String Reply := do
  match ← optStr req "msg" with
  | none => pure (unknownReply [("lanes", .null)])
  | some msg => pure [("lanes", .arr ((Fw.Ci.Intent.waitLanes msg).map fun l => Json.str l.name).toArray)]

/-- The ops of this module. -/
def ops : List String :=
  ["ci.budget.reserve", "ci.budget.next", "ci.budget.observe", "ci.budget.step", "ci.budget.status", "ci.budget.limits",
    "ci.verdict", "ci.required"]

/-- Dispatch a `ci.budget.*` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ci.budget.reserve" => some (opReserve req)
  | "ci.budget.next" => some (opNext req)
  | "ci.budget.observe" => some (opObserve req)
  | "ci.budget.step" => some (opStep req)
  | "ci.budget.status" => some (opStatus req)
  | "ci.budget.limits" => some (opLimits req)
  | "ci.verdict" => some (opVerdict req)
  | "ci.required" => some (opRequired req)
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

/-- One field of a reply as compact JSON (for the guards). -/
def runField (op r k : String) : String :=
  match Json.parse (run op r) with
  | .ok j => match j.getObjVal? k with
    | .ok v => v.compress
    | .error _ => "absent"
  | .error _ => run op r

/-- A sample state with every field set (for the guards). -/
def sample : State where
  now := 7
  ledger := [⟨1, 2, .tick, true⟩, ⟨3, 1, .oneoff, false⟩]
  remaining := some 4000
  reset := some 3600
  retryUntil := 9
  fails := 1
  etag := some "W/x"
  watched := [⟨5, 2, some 7⟩, ⟨6, 3, none⟩]
  lastTick := some 7
  pending := some (.oneoff, 2)
  pages := 2

-- the state round-trips through JSON
#guard (stateOf (stateJson sample)).toOption == some sample
#guard (stateOf (stateJson (init 0))).toOption == some (init 0)
-- a fresh one-off goes and is booked
#guard runField "ci.budget.reserve" "{\"now\":100,\"cost\":1}" "decision" == "\"issue\""
#guard runField "ci.budget.reserve" "{\"now\":100,\"cost\":1}" "state" ==
  "{\"etag\":null,\"fails\":0,\"lastTick\":null,\"ledger\":[{\"charged\":true,\"cost\":1,\"kind\":\"oneoff\",\"time\":100}],\"now\":100,\"pages\":1,\"pending\":{\"cost\":1,\"kind\":\"oneoff\"},\"remaining\":null,\"reset\":null,\"retryUntil\":0,\"watched\":[]}"
-- nothing watched: the poller stops idle
#guard run "ci.budget.next" "{\"now\":100}" ==
  "{\"decision\":\"stop\",\"reason\":\"idle\",\"state\":{\"etag\":null,\"fails\":0,\"lastTick\":null,\"ledger\":[],\"now\":100,\"pages\":1,\"pending\":null,\"remaining\":null,\"reset\":null,\"retryUntil\":0,\"watched\":[]}}"
-- one watched run: tick, list since its creation
#guard runField "ci.budget.next" "{\"now\":100,\"state\":{\"now\":90,\"watched\":[{\"runId\":5,\"createdAt\":80}]}}" "createdSince" == "80"
#guard runField "ci.budget.next" "{\"now\":100,\"state\":{\"now\":90,\"watched\":[{\"runId\":5,\"createdAt\":80}],\"lastTick\":90}}" "until" == "120"
-- a retry-after holds every call
#guard runField "ci.budget.reserve" "{\"now\":100,\"state\":{\"now\":90,\"retryUntil\":160},\"cost\":1}" "reason" == "\"retryAfter\""
-- observe a refusal with retry-after
#guard runField "ci.budget.observe" "{\"now\":100,\"lines\":[\"HTTP/2.0 403 Forbidden\",\"Retry-After: 60\"]}" "headers" ==
  "{\"etag\":null,\"remaining\":null,\"reset\":null,\"retryAfter\":60,\"status\":403}"
#guard runField "ci.budget.observe" "{\"now\":100,\"lines\":[\"HTTP/2.0 403 Forbidden\",\"Retry-After: 60\"]}" "state" |>.startsWith
  "{\"etag\":null,\"fails\":1,"
-- events
#guard runField "ci.budget.step" "{\"now\":100,\"event\":{\"register\":{\"runId\":5,\"createdAt\":80}}}" "state" |>.endsWith
  "\"watched\":[{\"createdAt\":80,\"lastCovered\":null,\"runId\":5}]}"
#guard run "ci.budget.step" "{\"now\":100,\"event\":{\"pages\":2,\"resume\":true}}" ==
  "error: field event: expected exactly one of register, unregister, pages, resume"
#guard run "ci.budget.reserve" "{\"now\":100,\"cost\":1.5}" == "error: field cost: expected a non-negative integer"
#guard runField "ci.budget.limits" "{}" "limits" ==
  "{\"B\":3000,\"B1\":60,\"F\":500,\"Pmin\":30,\"R\":1200,\"R1\":40,\"W\":3600,\"W1\":60,\"back0\":60,\"backMax\":3600,\"listCost\":2,\"maxFails\":6,\"shares\":{\"oneoff\":{\"hour\":1200,\"minute\":40},\"tick\":{\"hour\":1800,\"minute\":20}}}"
#guard runField "ci.budget.status" "{\"now\":100}" "interval" == "30"
-- a run whose guard was skipped at its if: is not run (code 4), with the reason
#guard run "ci.verdict" "{\"runs\":[{\"guard\":\"skipped\",\"jobs\":[\"skipped\"]}]}" ==
  "{\"code\":4,\"runs\":[{\"code\":4,\"reason\":\"unwanted: guard if: the head commit does not ask for this lane\",\"verdict\":\"not-run\"}],\"verdict\":\"not-run\"}"
#guard runField "ci.verdict" "{\"runs\":[{\"guard\":\"success\",\"steps\":[{\"name\":\"decision: run\",\"conclusion\":\"success\"}],\"jobs\":[\"success\",\"skipped\"]}]}" "verdict" == "\"pass\""
#guard runField "ci.verdict" "{\"runs\":[{\"guard\":\"success\",\"steps\":[{\"name\":\"decision: skip: no input changed\",\"conclusion\":\"success\"}],\"jobs\":[\"skipped\"]}]}" "runs" ==
  "[{\"code\":4,\"reason\":\"no input changed\",\"verdict\":\"not-run\"}]"
#guard runField "ci.verdict" "{\"runs\":[{\"guard\":\"success\",\"jobs\":[\"success\",\"failure\"]},{\"guard\":\"skipped\"}]}" "code" == "1"
#guard runField "ci.verdict" "{\"runs\":[]}" "code" == "4"
-- no guard key (a workflow without a guard job): pass iff a job ran and all that ran succeeded; a null guard (still
-- running) is not a pass
#guard runField "ci.verdict" "{\"runs\":[{\"jobs\":[\"success\",\"success\"]}]}" "code" == "0"
#guard runField "ci.verdict" "{\"runs\":[{\"jobs\":[\"skipped\"]}]}" "code" == "4"
#guard runField "ci.verdict" "{\"runs\":[{\"guard\":null,\"jobs\":[\"success\"]}]}" "code" == "1"
-- round 3: a job that stopped at its tip re-check makes the run not-run (stale), never fail or pass
#guard runField "ci.verdict" "{\"runs\":[{\"guard\":\"success\",\"steps\":[{\"name\":\"decision: run\",\"conclusion\":\"success\"}],\"jobs\":[\"failure\"],\"heavySteps\":[{\"name\":\"tip re-check\",\"conclusion\":\"success\"},{\"name\":\"stale: a newer push is the branch tip\",\"conclusion\":\"failure\"}]}]}" "code" == "4"
-- the lanes mode: [ci:wktr] wants lean and wktr; wktr has no run, so no pass even though lean passed
#guard runField "ci.verdict" "{\"msg\":\"x [ci:wktr]\",\"lanes\":{\"lean\":{\"jobs\":[\"success\"]}}}" "code" == "4"
#guard runField "ci.verdict" "{\"msg\":\"x [ci:wktr]\",\"lanes\":{\"lean\":{\"jobs\":[\"success\"]},\"wktr\":null}}" "lanes" ==
  "[{\"code\":0,\"name\":\"lean\",\"reason\":\"\",\"verdict\":\"pass\"},{\"code\":4,\"name\":\"wktr\",\"reason\":\"no run of this lane for the commit\",\"verdict\":\"missing\"}]"
#guard runField "ci.verdict" "{\"msg\":\"x [ci:wktr]\",\"lanes\":{\"lean\":{\"jobs\":[\"success\"]},\"wktr\":{\"jobs\":[\"success\"]}}}" "code" == "0"
-- the round-4 probe: lean skipped as unchanged and the requested lane passed: not a pass (round 5)
#guard runField "ci.verdict" "{\"msg\":\"[ci:wktr]\",\"lanes\":{\"lean\":{\"guard\":\"success\",\"steps\":[{\"name\":\"decision: skip: unchanged: none\",\"conclusion\":\"success\"}],\"jobs\":[\"skipped\"]},\"wktr\":{\"jobs\":[\"success\"]}}}" "code" == "4"
-- a requested lane skipped as unchanged is not a pass
#guard runField "ci.verdict" "{\"msg\":\"[ci:wktr]\",\"lanes\":{\"lean\":{\"jobs\":[\"success\"]},\"wktr\":{\"guard\":\"success\",\"steps\":[{\"name\":\"decision: skip: unchanged: none\",\"conclusion\":\"success\"}],\"jobs\":[\"skipped\"]}}}" "code" == "4"
#guard runField "ci.required" "{\"msg\":\"fix [ci:wktr] [ci:difftest]\"}" "lanes" == "[\"difftest\",\"lean\",\"wktr\"]"
#guard runField "ci.required" "{\"msg\":\"fix\"}" "lanes" == "[\"lean\"]"
-- round 4: an unknown message (null or absent) never passes and requires no lane list
#guard runField "ci.required" "{\"msg\":null}" "lanes" == "null"
#guard runField "ci.required" "{}" "code" == "4"
#guard runField "ci.verdict" "{\"msg\":null,\"lanes\":{\"lean\":{\"jobs\":[\"success\"]}}}" "code" == "4"
#guard runField "ci.verdict" "{\"lanes\":{\"lean\":{\"jobs\":[\"success\"]}}}" "verdict" == "\"not-run\""

end Fw.Wire.Ci
