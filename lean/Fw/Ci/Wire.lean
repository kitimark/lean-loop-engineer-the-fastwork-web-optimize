import Lean.Data.Json
import Fw.Ci.Budget
import Fw.Ci.Verdict
import Fw.Ci.Attempt
import Fw.Ci.Intent
import Fw.Ci.Overflow
import Fw.Ci.Pool.FallbackWire
import Fw.Ci.PoolTierWire
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
| `ci.budget.next` | `now`, `state`?, `markers`? [Marker] | Decision (the state swept of watches without a live waiter when `markers` is present), and on `issue` also `createdSince` (n or null) and `pages` |
| `ci.budget.observe` | `now`, `state`?, `lines` [string], `actual`? | `state`, `headers` Headers, `actual` |
| `ci.budget.step` | `now`, `state`?, `event` Event | `state` |
| `ci.budget.status` | `now`, `state`? | `limits`, `shares`, `used`, `interval`, `headroom`, `retryUntil`, `fails`, `watched`, `createdSince`, `state` |
| `ci.budget.limits` | (nothing) | `limits` |
| `ci.verdict` | `runs` [Facts] | `runs` [{`verdict`, `code`, `reason`}], `verdict`, `code` (`Fw.Ci.Verdict.combine`) |
| `ci.verdict` | `msg` (null: unknown), `lanes` {name: Facts or null} | `lanes` [{`name`, `verdict`, `code`, `reason`}], `verdict`, `code` (`Fw.Ci.Verdict.waitVerdict`) |
| `ci.attempt` | `recorded`?, `live`? (a cached fact against the live run) or `row`?, `view` (jobs view against a listed row) or `floor`, `row`? (row against the newest attempt seen) or `read`, `now` (a finished row's age) or `open`, `ago` (jobs without a conclusion, seconds since the finish) | `reuse` / `settled` / `current` / `fresh` / `jobsSettled` (bool; `Fw.Ci.Attempt`) |
| `ci.required` | `msg` (null: unknown) | `lanes` [name] (`Fw.Ci.Intent.wanted`, table order); unknown: `lanes` null, `verdict`, `code`, `reason` |
| `ci.overflow` | `legs` [name], `ghActive` [workflow name] or null, `ghActions`, `ghPrev`?, `ccArm`, `ccReadAt` (ms or null), `now` (ms), `spent`, `storage`, `keys` (n or null), `checkout` (bool or null), `forceFull`? | `gh` [leg], `cc` [leg], `reason`, `ghFree`, `ghDegraded`, `ccReady` (`Fw.Ci.Overflow`) |
| `ci.overflowCombine` | `kinds` [verdict kind] | `kind` (the deciding kind, null for none; `Fw.Ci.Overflow.pickKind`) |
| `ci.overflowSettle` | `gh` [leg], `cc` [leg], `ccStarted` (bool) | `gh`, `cc`, `again` [leg]: a CircleCI group that could not start hands its legs to a second GitHub run (`again`; `Fw.Ci.Overflow.settle`) |
| `ci.poolRoute`, `ci.poolConsts` | see `Fw.Wire.CiPool` | the macOS fallback route (`Fw.Ci.Pool.Fallback`) |
| `ci.poolTier`, `ci.poolTierConsts` | see `Fw.Wire.CiPoolTier` | the three-tier macOS pool (`Fw.Ci.PoolTier`) |

Facts: `{guard, steps:[{name, conclusion}], jobs:[conclusion], heavySteps:[{name, conclusion}]}` (`heavySteps`: the
steps of every non-guard job, read for the tip re-check's `stale:` step).

Shapes. Decision: `{decision:"issue", kind:"tick"|"oneoff", cost, state}` (the state with the charge booked; on a
tick every watched run is covered), `{decision:"wait", until, reason, state}` or `{decision:"stop", reason, state}`;
reason ∈ `failures idle tooBig retryAfter floor hour minute interval`. State: `{now, ledger:[{time, cost,
kind, charged}], remaining, reset, retryUntil, fails, etag, watched:[{runId, createdAt, lastCovered, misses}], lastTick,
pending:{kind, cost}|null, pages}` (`remaining reset etag lastTick lastCovered` may be null; every field but `now` is
optional on input). Marker: `{runId, killOk, recorded?, now?}` (`killOk`: `kill(pid, 0)` found the process; `recorded`/`now`: the process start time
the marker holds and the pid's now, opaque strings; absent or null: unknown). Headers: `{status, remaining, reset, retryAfter, etag, resource}` (null when absent). `lines` are the
response header lines of `gh api --include` (or `curl -i`), one per element, `< ` prefixes allowed; `actual` (default:
the number of status lines, i.e. responses) is the number of requests the call really made. Event: `{register:{runId,
createdAt}}`, `{unregister:runId}`, `{pages:n}`, `{resume:true}`, `{sweep:[runId]}` (drop every watch not in the list, with an `orphan` incident) or `{listed:{rows, count, pagesRead, createdSince}}` (Lean decides whether
the list was cut: `pagesRead * 100 <= count`). A stored watch may carry an old `registeredAt`; it is ignored.
-/
namespace Fw.Wire.Ci
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD ostr optN optB)
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
  Json.mkObj [("runId", jn w.runId), ("createdAt", jn w.createdAt), ("lastCovered", ojn w.lastCovered), ("misses", jn w.misses)]

/-- A watched run from JSON. -/
def watchOf (j : Json) : Except String Watch := do
  pure { runId := ← nat j "runId", createdAt := ← nat j "createdAt", lastCovered := ← optN j "lastCovered", misses := ← natD j "misses" 0 }

/-- The call in flight as JSON. -/
def pendingJson : Option (Kind × Nat) → Json
  | some (k, c) => Json.mkObj [("kind", .str (kindName k)), ("cost", jn c)]
  | none => .null

/-- The call in flight from JSON. -/
def pendingOf (j : Json) : Except String (Option (Kind × Nat)) :=
  match opt j "pending" with
  | none => .ok none
  | some p => do pure (some (← kindOf "kind" (← str p "kind"), ← nat p "cost"))

/-- The name of a drop reason. -/
def dropName : Drop → String
  | .unseen => "unseen"
  | .uncovered => "uncovered"
  | .orphan => "orphan"

/-- A drop reason from its name. -/
def dropOf (k : String) : String → Except String Drop
  | "unseen" => .ok .unseen
  | "uncovered" => .ok .uncovered
  | "orphan" => .ok .orphan
  | v => .error s!"field {k}: unknown value {v}"

/-- An incident as JSON. -/
def incidentJson (i : Incident) : Json :=
  Json.mkObj [("runId", jn i.runId), ("time", jn i.time), ("why", .str (dropName i.why))]

/-- An incident from JSON. -/
def incidentOf (j : Json) : Except String Incident := do
  pure { runId := ← nat j "runId", time := ← nat j "time", why := ← dropOf "why" (← str j "why") }

/-- The state as JSON. -/
def stateJson (s : State) : Json :=
  Json.mkObj [("now", jn s.now), ("ledger", .arr (s.ledger.map entryJson).toArray), ("remaining", ojn s.remaining),
    ("reset", ojn s.reset), ("retryUntil", jn s.retryUntil), ("fails", jn s.fails), ("etag", ostr s.etag),
    ("watched", .arr (s.watched.map watchJson).toArray), ("lastTick", ojn s.lastTick),
    ("pending", pendingJson s.pending), ("pages", jn s.pages), ("incidents", .arr (s.incidents.map incidentJson).toArray)]

/-- The state from JSON (every field but `now` optional, with the `init` defaults). -/
def stateOf (j : Json) : Except String State := do
  pure { now := ← nat j "now", ledger := ← (← arrD j "ledger").mapM entryOf, remaining := ← optN j "remaining",
         reset := ← optN j "reset", retryUntil := ← natD j "retryUntil" 0, fails := ← natD j "fails" 0,
         etag := ← optStr j "etag", watched := ← (← arrD j "watched").mapM watchOf, lastTick := ← optN j "lastTick",
         pending := ← pendingOf j, pages := ← natD j "pages" 1,
         incidents := ← (← arrD j "incidents").mapM incidentOf }

/-- Headers as JSON. -/
def headersJson (h : Headers) : Json :=
  Json.mkObj [("status", jn h.status), ("remaining", ojn h.remaining), ("reset", ojn h.reset),
    ("retryAfter", ojn h.retryAfter), ("etag", ostr h.etag), ("resource", ostr h.resource)]

/-- The limits as JSON, with the two shares of each window and the waiter's re-read period `slice`. -/
def limitsJson (L : Limits) : Json :=
  Json.mkObj [("W", jn L.W), ("B", jn L.B), ("R", jn L.R), ("W1", jn L.W1), ("B1", jn L.B1), ("R1", jn L.R1),
    ("F", jn L.F), ("Pmin", jn L.Pmin), ("back0", jn L.back0), ("backMax", jn L.backMax),
    ("maxFails", jn L.maxFails), ("listCost", jn L.listCost), ("slice", jn slice), ("missMax", jn L.missMax),
    ("maxRun", jn L.maxRun), ("sentinelBase", jn sentinelBase), ("sentinelSpan", jn sentinelSpan), ("pageCap", jn (pageCap L)),
    ("shares", Json.mkObj [("tick", Json.mkObj [("hour", jn (share L .tick)), ("minute", jn (share1 L .tick))]),
                           ("oneoff", Json.mkObj [("hour", jn (share L .oneoff)), ("minute", jn (share1 L .oneoff))])])]

/-- One row of a tick's list, `(runId, createdAt)`, from JSON. -/
def rowOf (j : Json) : Except String (Nat × Nat) := do
  pure (← nat j "runId", ← nat j "createdAt")

/-- A waiter marker as the glue read it, from JSON: `{runId, killOk, recorded?, now?}`. -/
def markerOf (j : Json) : Except String Marker := do
  pure { runId := ← nat j "runId", killOk := ← asBool "killOk" (← field j "killOk"),
         recorded := ← optStr j "recorded", now := ← optStr j "now" }

/-- An event from JSON (exactly one of `register`, `unregister`, `pages`, `resume`, `listed`, `ack`, `sweep`). -/
def eventOf (j : Json) : Except String Event := do
  let keys := ["register", "unregister", "pages", "resume", "listed", "ack", "sweep"].filter fun k => (opt j k).isSome
  match keys with
  | ["register"] => let r ← field j "register"; pure (.register (← nat r "runId") (← nat r "createdAt"))
  | ["unregister"] => pure (.unregister (← asNat "unregister" (← field j "unregister")))
  | ["pages"] => pure (.pages (← asNat "pages" (← field j "pages")))
  | ["resume"] => if ← asBool "resume" (← field j "resume") then pure .resume else .error "field resume: expected true"
  | ["listed"] =>
    let l ← field j "listed"
    pure (.listed (← (← arr l "rows").toList.mapM rowOf) (← nat l "count") (← natD l "pagesRead" 1) (← natD l "createdSince" 0))
  | ["ack"] => pure (.ack (← asNat "ack" (← field j "ack")))
  | ["sweep"] => pure (.sweep (← (← asArr "sweep" (← field j "sweep")).toList.mapM (asNat "sweep")))
  | _ => .error "field event: expected exactly one of register, unregister, pages, resume, listed, ack, sweep"

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

/-- `ci.budget.next`: the shared poller's decision; a tick lists the runs created since `createdSince`. With
`markers` (the waiter markers the glue read under the state lock) the watches without a live waiter are swept first
(`sweep`, `aliveIds`), so `createdSince` and the reply's `state` come from live watches only
(`next_window_from_live`); without `markers` nothing is swept. -/
def opNext (req : Json) : Except String Reply := do
  let s0 ← clocked req
  let s ← match opt req "markers" with
    | none => pure s0
    | some ms => do
      let alive := aliveIds (← (← asArr "markers" ms).toList.mapM markerOf)
      pure (step defaults s0 (.sweep alive))
  match next defaults s with
  | d@(.issue _ _ s') => pure (decisionReply s d ++ [("createdSince", ojn (since s')), ("pages", jn (pagesOf defaults s'))])
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
  match e with
  | .register r _ =>
    if validWatch defaults r then pure [("state", stateJson (step defaults s e))]
    else .error s!"field register: runId {r} is neither a GitHub run id nor a branch sentinel"
  | _ => pure [("state", stateJson (step defaults s e))]

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
folds to failure; any other value is an error. -/
def conclField (j : Json) (k : String) : Except String Fw.Ci.Verdict.Concl := do
  pure (Fw.Ci.Verdict.conclOf ((← optStr j k).getD ""))

/-- A guard step `{name, conclusion}`. -/
def stepOf (j : Json) : Except String (String × Fw.Ci.Verdict.Concl) := do
  pure (← str j "name", ← conclField j "conclusion")

/-- One run's verdict as JSON: `{verdict, code, reason}`. Below `T`, `J`, `H` are the run's `steps`, `jobs` and
`heavySteps` (absent: empty), and a `guard` key that is absent reads as success. -/
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
(code 4, verdict `none`). Below `laneV` is its `LaneRun`, whose skip kind is the one the reason names;
an error of `runVerdict` is the result. -/
def laneVerdict (lanes : Json) (l : Fw.Ci.Intent.Lane) : Except String (Fw.Ci.Verdict.LaneRun × Json) := do
  match lanes.getObjVal? l.name with
  | .error _ | .ok .null =>
    pure (⟨none, none⟩, Json.mkObj [("name", .str l.name), ("verdict", "missing"), ("code", jn 4),
      ("reason", "no run of this lane for the commit")])
  | .ok f =>
    let (v, j) ← runVerdict f
    let reason := (j.getObjValAs? String "reason").toOption.getD ""
    pure (⟨some v, Fw.Ci.Verdict.skipOf reason⟩, j.setObjVal! "name" (.str l.name))

/-- The reply fields of a wait whose request is unknown, after `pre`: the verdict `wait(none)`
(not run), its code and a reason. -/
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
(`unknown_request_never_pass`). A field of the wrong type is an error; `runs` absent is `[]`. -/
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
request (not run), so the caller stops without waiting. A `msg` that is not a string is an error. -/
def opRequired (req : Json) : Except String Reply := do
  match ← optStr req "msg" with
  | none => pure (unknownReply [("lanes", .null)])
  | some msg => pure [("lanes", .arr ((Fw.Ci.Intent.waitLanes msg).map fun l => Json.str l.name).toArray)]

/-- `ci.attempt`: which attempt of a run a recorded fact answers for (`Fw.Ci.Attempt`). Request `{recorded?, live?}`:
reply `{reuse}`; request `{view, row?}`: reply `{settled}`; request `{floor, row?}`: reply `{current}`; request `{read, now}` (seconds): reply `{fresh}`. An attempt is a
natural number, absent or `null` when unknown. The cases are tried in this order: `open` (open jobs, with `ago` seconds since the finish) gives jobsSettled, `view` gives settled, `read` gives
fresh, `floor` gives current, otherwise reuse. -/
def opAttempt (req : Json) : Except String Reply := do
  let n? (k : String) : Except String (Option Nat) := do
    match opt req k with
    | none | some .null => pure none
    | some _ => pure (some (← nat req k))
  if (opt req "open").isSome then
    pure [("jobsSettled", .bool (Fw.Ci.Attempt.jobsSettled (← nat req "open") (← nat req "ago")))]
  else if (opt req "view").isSome then
    pure [("settled", .bool (Fw.Ci.Attempt.settled (← n? "row") (← nat req "view")))]
  else if (opt req "read").isSome then
    pure [("fresh", .bool (Fw.Ci.Attempt.fresh (← nat req "read") (← nat req "now")))]
  else if (opt req "floor").isSome then
    pure [("current", .bool (Fw.Ci.Attempt.current (← nat req "floor") (← n? "row")))]
  else
    pure [("reuse", .bool (Fw.Ci.Attempt.reuse (← n? "recorded") (← n? "live")))]

/-- A leg by its name. -/
def legOf (k : String) : Except String Fw.Console.LandLegs.Leg :=
  match Fw.Console.LandLegs.Leg.ofName? k with
  | some l => pure l
  | none => throw s!"field legs: unknown leg {k}"

/-- The facts of `ci.overflow` (a missing `ghActive`, `ccReadAt`, `keys`, `checkout` is unknown). -/
def overflowFacts (req : Json) : Except String Fw.Ci.Overflow.Facts := do
  let names (j : Json) (k : String) : Except String (List String) := do
    let a ← asArr k j
    a.toList.mapM (asStr k)
  let legs ← (← names (← field req "legs") "legs").mapM legOf
  let active ← match opt req "ghActive" with
    | none => pure none
    | some j => pure (some (← names j "ghActive"))
  pure { legs, ghActive := active, ghActions := ← str req "ghActions", ghPrev := ← boolD req "ghPrev" false,
         ccArm := ← str req "ccArm", ccReadAt := ← optN req "ccReadAt", now := ← nat req "now", spent := ← nat req "spent",
         storage := ← nat req "storage", keys := ← optN req "keys", checkout := ← optB req "checkout",
         forceFull := ← boolD req "forceFull" false }

/-- `ci.overflow`: which land legs run on GitHub and which on CircleCI (`Fw.Ci.Overflow`). -/
def opOverflow (req : Json) : Except String Reply := do
  let f ← overflowFacts req
  let nm (l : List Fw.Console.LandLegs.Leg) : Json := .arr (l.map fun x => Json.str x.name).toArray
  pure [("gh", nm (Fw.Ci.Overflow.ghLegs f)), ("cc", nm (Fw.Ci.Overflow.ccLegs f)),
    ("reason", .str (Fw.Ci.Overflow.reason f)), ("ghFree", jn (Fw.Ci.Overflow.ghFree f)),
    ("ghDegraded", .bool (Fw.Ci.Overflow.ghDegraded f)),
    ("ccReady", .bool (Fw.Ci.Overflow.ccReady f (Fw.Ci.Overflow.overflowSet f).length))]

/-- `ci.overflowCombine`: the verdict kind that decides when each provider's legs have a verdict. -/
def opOverflowCombine (req : Json) : Except String Reply := do
  let ks ← (← arr req "kinds").toList.mapM (asStr "kinds")
  pure [("kind", match Fw.Ci.Overflow.pickKind ks with | some k => .str k | none => .null)]

/-- `ci.overflowSettle`: where the legs run after the CircleCI group tried to start (`Fw.Ci.Overflow.settle`). -/
def opOverflowSettle (req : Json) : Except String Reply := do
  let legsOf (k : String) : Except String (List Fw.Console.LandLegs.Leg) := do
    (← (← arr req k).toList.mapM (asStr k)).mapM legOf
  let st := Fw.Ci.Overflow.settle (← legsOf "gh") (← legsOf "cc") (← boolD req "ccStarted" true)
  let nm (l : List Fw.Console.LandLegs.Leg) : Json := .arr (l.map fun x => Json.str x.name).toArray
  pure [("gh", nm st.gh), ("cc", nm st.cc), ("again", nm st.again)]

/-- The ops of this module. -/
def ops : List String :=
  ["ci.budget.reserve", "ci.budget.next", "ci.budget.observe", "ci.budget.step", "ci.budget.status", "ci.budget.limits",
    "ci.verdict", "ci.required", "ci.attempt", "ci.overflow", "ci.overflowCombine", "ci.overflowSettle"] ++
    Fw.Wire.CiPool.ops ++ Fw.Wire.CiPoolTier.ops

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
  | "ci.attempt" => some (opAttempt req)
  | "ci.overflow" => some (opOverflow req)
  | "ci.overflowCombine" => some (opOverflowCombine req)
  | "ci.overflowSettle" => some (opOverflowSettle req)
  | _ => (Fw.Wire.CiPool.handle op req).orElse fun _ => Fw.Wire.CiPoolTier.handle op req

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
  watched := [⟨5, 2, some 7, 0⟩, ⟨6, 3, none, 1⟩]
  lastTick := some 7
  pending := some (.oneoff, 2)
  pages := 2

-- the state round-trips through JSON
#guard (stateOf (stateJson sample)).toOption == some sample
#guard (stateOf (stateJson (init 0))).toOption == some (init 0)
-- a fresh one-off goes and is booked
#guard runField "ci.budget.reserve" "{\"now\":100,\"cost\":1}" "decision" == "\"issue\""
#guard runField "ci.budget.reserve" "{\"now\":100,\"cost\":1}" "state" ==
  "{\"etag\":null,\"fails\":0,\"incidents\":[],\"lastTick\":null,\"ledger\":[{\"charged\":true,\"cost\":1,\"kind\":\"oneoff\",\"time\":100}],\"now\":100,\"pages\":1,\"pending\":{\"cost\":1,\"kind\":\"oneoff\"},\"remaining\":null,\"reset\":null,\"retryUntil\":0,\"watched\":[]}"
-- nothing watched: the poller stops idle
#guard run "ci.budget.next" "{\"now\":100}" ==
  "{\"decision\":\"stop\",\"reason\":\"idle\",\"state\":{\"etag\":null,\"fails\":0,\"incidents\":[],\"lastTick\":null,\"ledger\":[],\"now\":100,\"pages\":1,\"pending\":null,\"remaining\":null,\"reset\":null,\"retryUntil\":0,\"watched\":[]}}"
-- one watched run: tick, list since its creation
#guard runField "ci.budget.next" "{\"now\":100,\"state\":{\"now\":90,\"watched\":[{\"runId\":5,\"createdAt\":80}]}}" "createdSince" == "80"
#guard runField "ci.budget.next" "{\"now\":95,\"state\":{\"now\":90,\"watched\":[{\"runId\":5,\"createdAt\":80}],\"lastTick\":90}}" "until" == "100"
-- a retry-after holds every call
#guard runField "ci.budget.reserve" "{\"now\":100,\"state\":{\"now\":90,\"retryUntil\":160},\"cost\":1}" "reason" == "\"retryAfter\""
-- observe a refusal with retry-after
#guard runField "ci.budget.observe" "{\"now\":100,\"lines\":[\"HTTP/2.0 403 Forbidden\",\"Retry-After: 60\"]}" "headers" ==
  "{\"etag\":null,\"remaining\":null,\"reset\":null,\"resource\":null,\"retryAfter\":60,\"status\":403}"
#guard runField "ci.budget.observe" "{\"now\":100,\"lines\":[\"HTTP/2.0 403 Forbidden\",\"Retry-After: 60\"]}" "state" |>.startsWith
  "{\"etag\":null,\"fails\":1,\"incidents\":[],"
-- only the core bucket sets the remaining count
#guard runField "ci.budget.observe" "{\"now\":100,\"lines\":[\"HTTP/2.0 200 OK\",\"X-Ratelimit-Remaining: 4000\",\"X-Ratelimit-Reset: 3600\",\"X-Ratelimit-Resource: graphql\"]}" "state" |>.endsWith
  "\"remaining\":null,\"reset\":null,\"retryUntil\":0,\"watched\":[]}"
#guard runField "ci.budget.observe" "{\"now\":100,\"lines\":[\"HTTP/2.0 200 OK\",\"X-Ratelimit-Remaining: 4000\",\"X-Ratelimit-Reset: 3600\",\"X-Ratelimit-Resource: core\"]}" "state" |>.endsWith
  "\"remaining\":4000,\"reset\":3600,\"retryUntil\":0,\"watched\":[]}"
-- events
#guard runField "ci.budget.step" "{\"now\":100,\"event\":{\"register\":{\"runId\":5,\"createdAt\":80}}}" "state" |>.endsWith
  "\"watched\":[{\"createdAt\":80,\"lastCovered\":null,\"misses\":0,\"runId\":5}]}"
#guard run "ci.budget.step" "{\"now\":100,\"event\":{\"pages\":2,\"resume\":true}}" ==
  "error: field event: expected exactly one of register, unregister, pages, resume, listed, ack, sweep"
#guard run "ci.budget.reserve" "{\"now\":100,\"cost\":1.5}" == "error: field cost: expected a non-negative integer"
#guard runField "ci.budget.limits" "{}" "limits" ==
  "{\"B\":3000,\"B1\":60,\"F\":500,\"Pmin\":10,\"R\":1200,\"R1\":40,\"W\":3600,\"W1\":60,\"back0\":60,\"backMax\":3600,\"listCost\":2,\"maxFails\":6,\"maxRun\":10000000000000,\"missMax\":3,\"pageCap\":10,\"sentinelBase\":1000000000000000,\"sentinelSpan\":4294967296,\"shares\":{\"oneoff\":{\"hour\":1200,\"minute\":40},\"tick\":{\"hour\":1800,\"minute\":20}},\"slice\":2}"
#guard runField "ci.budget.status" "{\"now\":100}" "interval" == "10"
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
