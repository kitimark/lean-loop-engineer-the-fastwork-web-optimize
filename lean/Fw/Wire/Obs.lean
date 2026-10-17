import Lean.Data.Json
import Fw.Obs.Health
import Fw.Ops.Wire
import Fw.Wire.Sched
/-!
# JSON codecs and the op `obs.health` (team health of one observation snapshot)

Glue between `fwcore`'s JSON lines and `Fw.Obs.Health` (namespace `Fw.Wire.Obs`, so the math view treats it as
wire code). Total decoders only (`Except String`); no partial operations. Times are integer ms since the epoch; every
number is a non-negative integer (a fraction is refused, so the caller floors `diskFreeGB`).

| op | request | reply |
|---|---|---|
| `obs.health` | `now`, `params`?, `agents`? [Agent], `system` System | `agents` [{id, state, alerts:[code]}] (input order), `system` {alerts:[code]}, `counts` {active, idle, waiting, stalled, done}, `alerts` [{code, subject, detail}] (sorted by code, subject, detail; no duplicates) |

Shapes. Params (every field optional, defaults in brackets): `{idleMin [10], stallMin [20], toolHangMin [30]` (minutes),
`errStreak [3], ctxResumeMax [250000], ctxWarn [200000], diskMinGB [20], agentCap [10], simLockMaxMin [30]` (minutes),
`worktreesMax [20]}`. Agent: `{id, name?, task?, depth? [1], startedAt, lastAt, stoppedAt?, errTail? [0],
inflight? {tool, since}, waitingPermission? [false], ctxTokens?}` (`type`, `model`, `tools`, `errors`, `tokens`,
`inflight.verb` are accepted and ignored). System: `{diskFreeGB, memPressure? ["normal"|"warn"|"critical"],
simLock? {holder?, since?}, docker? [{id, name, startedAt}], worktrees? [0] (a count), ci? [{workflow, branch, status,
conclusion?, startedAt}]}` (`load1`, `consolePids` are accepted and ignored). `null` counts as absent.

Proved: the round trips `paramsOf_paramsJson`, `agentOf_agentJson`, `systemOf_systemJson`, `reqOf_reqJson`, and
`opHealth_reqJson` (the reply to an encoded request is the encoded `health` report). Guards at the end; golden vectors
in `packages/contracts/golden/obs/health.jsonl` (`Fw.Wire.Obs.Golden`, file `Fw/Obs/Golden.lean`).
-/
namespace Fw.Wire.Obs
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD ostr)
open Fw.Wire.Sched (optS ok_bind mapM_rt arrD_arr)
open Fw.Obs.Health

/-! ## Decoders and encoders -/

/-- An optional natural field (absent or `null` is `none`). -/
def optN (j : Json) (k : String) : Except String (Option Nat) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asNat k v

/-- An optional natural as a number or `null`. -/
def onat : Option Nat → Json
  | some n => toJson n
  | none => .null

/-- The thresholds as JSON (every field written). -/
def paramsJson (p : Params) : Json :=
  Json.mkObj [("idleMin", toJson p.idleMin), ("stallMin", toJson p.stallMin), ("toolHangMin", toJson p.toolHangMin),
    ("errStreak", toJson p.errStreak), ("ctxResumeMax", toJson p.ctxResumeMax), ("ctxWarn", toJson p.ctxWarn),
    ("diskMinGB", toJson p.diskMinGB), ("agentCap", toJson p.agentCap), ("simLockMaxMin", toJson p.simLockMaxMin),
    ("worktreesMax", toJson p.worktreesMax)]

/-- Decode the thresholds; a missing field takes its default. -/
def paramsOf (j : Json) : Except String Params := do
  let d : Params := {}
  pure { idleMin := ← natD j "idleMin" d.idleMin, stallMin := ← natD j "stallMin" d.stallMin,
         toolHangMin := ← natD j "toolHangMin" d.toolHangMin, errStreak := ← natD j "errStreak" d.errStreak,
         ctxResumeMax := ← natD j "ctxResumeMax" d.ctxResumeMax, ctxWarn := ← natD j "ctxWarn" d.ctxWarn,
         diskMinGB := ← natD j "diskMinGB" d.diskMinGB, agentCap := ← natD j "agentCap" d.agentCap,
         simLockMaxMin := ← natD j "simLockMaxMin" d.simLockMaxMin,
         worktreesMax := ← natD j "worktreesMax" d.worktreesMax }

/-- A tool call in flight as JSON. -/
def inflightJson (f : Inflight) : Json := Json.mkObj [("tool", .str f.tool), ("since", toJson f.since)]

/-- Decode a tool call in flight (`verb` ignored). -/
def inflightOf (j : Json) : Except String Inflight := do
  pure { tool := ← str j "tool", since := ← nat j "since" }

/-- An agent as JSON (every field written; absent options are `null`). -/
def agentJson (a : Agent) : Json :=
  Json.mkObj [("id", .str a.id), ("name", ostr a.name), ("task", ostr a.task), ("depth", toJson a.depth),
    ("startedAt", toJson a.startedAt), ("lastAt", toJson a.lastAt), ("stoppedAt", onat a.stoppedAt),
    ("errTail", toJson a.errTail), ("inflight", match a.inflight with | some f => inflightJson f | none => .null),
    ("waitingPermission", .bool a.waitingPermission), ("ctxTokens", onat a.ctxTokens)]

/-- An optional tool call in flight (absent or `null` is `none`). -/
def optInflight (j : Json) : Except String (Option Inflight) :=
  match opt j "inflight" with
  | none => .ok none
  | some v => some <$> inflightOf v

/-- Decode an agent; `id`, `startedAt` and `lastAt` are required. -/
def agentOf (j : Json) : Except String Agent := do
  pure { id := ← str j "id", name := ← optS j "name", task := ← optS j "task", depth := ← natD j "depth" 1,
         startedAt := ← nat j "startedAt", lastAt := ← nat j "lastAt", stoppedAt := ← optN j "stoppedAt",
         errTail := ← natD j "errTail" 0, inflight := ← optInflight j,
         waitingPermission := ← boolD j "waitingPermission" false, ctxTokens := ← optN j "ctxTokens" }

/-- Memory-pressure wire names. -/
def memName : Mem → String
  | .normal => "normal" | .warn => "warn" | .critical => "critical"

/-- A memory pressure from its wire name (an unknown name is refused). -/
def memOf : String → Except String Mem
  | "normal" => .ok .normal | "warn" => .ok .warn | "critical" => .ok .critical
  | s => .error s!"field memPressure: unknown value {s}"

/-- The simulator lock as JSON. -/
def simLockJson (l : SimLock) : Json := Json.mkObj [("holder", ostr l.holder), ("since", onat l.since)]

/-- Decode the simulator lock (both fields optional). -/
def simLockOf (j : Json) : Except String SimLock := do
  pure { holder := ← optS j "holder", since := ← optN j "since" }

/-- A container as JSON. -/
def containerJson (c : Container) : Json :=
  Json.mkObj [("id", .str c.id), ("name", .str c.name), ("startedAt", toJson c.startedAt)]

/-- Decode a container. -/
def containerOf (j : Json) : Except String Container := do
  pure { id := ← str j "id", name := ← str j "name", startedAt := ← nat j "startedAt" }

/-- A CI run as JSON. -/
def ciJson (r : CiRun) : Json :=
  Json.mkObj [("workflow", .str r.workflow), ("branch", .str r.branch), ("status", .str r.status),
    ("conclusion", ostr r.conclusion), ("startedAt", toJson r.startedAt)]

/-- Decode a CI run (`conclusion` optional). -/
def ciOf (j : Json) : Except String CiRun := do
  pure { workflow := ← str j "workflow", branch := ← str j "branch", status := ← str j "status",
         conclusion := ← optS j "conclusion", startedAt := ← nat j "startedAt" }

/-- The system facts as JSON (every field written). -/
def systemJson (s : System) : Json :=
  Json.mkObj [("diskFreeGB", toJson s.diskFreeGB), ("memPressure", .str (memName s.memPressure)),
    ("simLock", simLockJson s.simLock), ("docker", .arr (s.docker.toArray.map containerJson)),
    ("worktrees", toJson s.worktrees), ("ci", .arr (s.ci.toArray.map ciJson))]

/-- Decode the system facts; `diskFreeGB` is required. -/
def systemOf (j : Json) : Except String System := do
  let mem ← match opt j "memPressure" with
    | none => pure .normal
    | some v => memOf (← asStr "memPressure" v)
  let lock ← match opt j "simLock" with
    | none => pure {}
    | some v => simLockOf v
  pure { diskFreeGB := ← nat j "diskFreeGB", memPressure := mem, simLock := lock,
         docker := ← (← arrD j "docker").mapM containerOf, worktrees := ← natD j "worktrees" 0,
         ci := ← (← arrD j "ci").mapM ciOf }

/-- A request body as JSON: `now`, `params`, `agents`, `system`. -/
def reqJson (p : Params) (o : Obs) : Json :=
  Json.mkObj [("now", toJson o.now), ("params", paramsJson p), ("agents", .arr (o.agents.toArray.map agentJson)),
    ("system", systemJson o.system)]

/-- Decode a request body; `params` and `agents` are optional (defaults, no agents). -/
def reqOf (j : Json) : Except String (Params × Obs) := do
  let p ← match opt j "params" with
    | none => pure {}
    | some v => paramsOf v
  let agents ← (← arrD j "agents").mapM agentOf
  pure (p, { now := ← nat j "now", agents, system := ← systemOf (← field j "system") })

/-! ## Round trips -/

/-- Thresholds round-trip.

$$\forall p:\quad \operatorname{paramsOf}(\operatorname{paramsJson}(p)) = \mathrm{ok}(p)$$
-/
theorem paramsOf_paramsJson (p : Params) : paramsOf (paramsJson p) = .ok p := by
  cases p; rfl

set_option maxHeartbeats 4000000 in
/-- Agents round-trip.

$$\forall a:\quad \operatorname{agentOf}(\operatorname{agentJson}(a)) = \mathrm{ok}(a)$$
-/
theorem agentOf_agentJson (a : Agent) : agentOf (agentJson a) = .ok a := by
  obtain ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩ := a
  have hn : optS (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "name" = .ok name := by cases name <;> rfl
  have ht : optS (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "task" = .ok task := by cases task <;> rfl
  have hs : optN (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "stoppedAt" = .ok stoppedAt := by cases stoppedAt <;> rfl
  have hc : optN (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "ctxTokens" = .ok ctx := by cases ctx <;> rfl
  have hi : optInflight (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      = .ok inflight := by
    cases inflight with
    | none => rfl
    | some f => cases f; rfl
  have hd : natD (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "depth" 1 = .ok depth := rfl
  have hst : nat (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "startedAt" = .ok startedAt := rfl
  have hl : nat (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "lastAt" = .ok lastAt := rfl
  have he : natD (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "errTail" 0 = .ok errTail := rfl
  have hw : boolD (agentJson ⟨id, name, task, depth, startedAt, lastAt, stoppedAt, errTail, inflight, w, ctx⟩)
      "waitingPermission" false = .ok w := rfl
  simp only [agentOf, hn, ht, hd, hst, hl, hs, he, hi, hw, hc, ok_bind]
  rfl

/-- Containers round-trip.

$$\forall c:\quad \operatorname{containerOf}(\operatorname{containerJson}(c)) = \mathrm{ok}(c)$$
-/
theorem containerOf_containerJson (c : Container) : containerOf (containerJson c) = .ok c := by
  cases c; rfl

/-- CI runs round-trip.

$$\forall r:\quad \operatorname{ciOf}(\operatorname{ciJson}(r)) = \mathrm{ok}(r)$$
-/
theorem ciOf_ciJson (r : CiRun) : ciOf (ciJson r) = .ok r := by
  obtain ⟨w, b, s, c, t⟩ := r
  cases c <;> rfl

/-- System facts round-trip.

$$\forall s:\quad \operatorname{systemOf}(\operatorname{systemJson}(s)) = \mathrm{ok}(s)$$
-/
theorem systemOf_systemJson (s : System) : systemOf (systemJson s) = .ok s := by
  obtain ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci⟩ := s
  have hd := arrD_arr (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci⟩) "docker" _ rfl
  have hc := arrD_arr (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci⟩) "ci" _ rfl
  have hm : opt (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci⟩) "memPressure" =
      some (.str (memName mem)) := rfl
  have hl : opt (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci⟩) "simLock" =
      some (simLockJson ⟨holder, since⟩) := rfl
  have hml : memOf (memName mem) = .ok mem := by cases mem <;> rfl
  have hsl : simLockOf (simLockJson ⟨holder, since⟩) = .ok ⟨holder, since⟩ := by
    cases holder <;> cases since <;> rfl
  simp only [systemOf, hd, hc, hm, hl, Array.toList_map, ok_bind,
    mapM_rt containerJson containerOf containerOf_containerJson, mapM_rt ciJson ciOf ciOf_ciJson]
  simp only [asStr, ok_bind, hml, hsl]
  rfl

/-- Requests round-trip.

$$\forall p, o:\quad \operatorname{reqOf}(\operatorname{reqJson}(p, o)) = \mathrm{ok}(p, o)$$
-/
theorem reqOf_reqJson (p : Params) (o : Obs) : reqOf (reqJson p o) = .ok (p, o) := by
  obtain ⟨now, agents, sys⟩ := o
  have ha := arrD_arr (reqJson p ⟨now, agents, sys⟩) "agents" _ rfl
  have hp : opt (reqJson p ⟨now, agents, sys⟩) "params" = some (paramsJson p) := rfl
  have hs : field (reqJson p ⟨now, agents, sys⟩) "system" = .ok (systemJson sys) := rfl
  simp only [reqOf, ha, hp, hs, Array.toList_map, ok_bind, paramsOf_paramsJson,
    mapM_rt agentJson agentOf agentOf_agentJson, systemOf_systemJson]
  rfl

/-! ## The op -/

/-- State wire names. -/
def stateName : State → String
  | .active => "active" | .idle => "idle" | .waiting => "waiting" | .stalled => "stalled" | .done => "done"

/-- An alert as JSON. -/
def alertJson (x : Alert) : Json :=
  Json.mkObj [("code", .str x.code.name), ("subject", .str x.subject), ("detail", .str x.detail)]

/-- A list of codes as a JSON array of names. -/
def codesJson (cs : List Code) : Json := .arr (cs.toArray.map fun c => .str c.name)

/-- The reply fields of a report. -/
def reportFields (r : Report) : Reply :=
  [("agents", .arr (r.agents.toArray.map fun w =>
      Json.mkObj [("id", .str w.id), ("state", .str (stateName w.state)), ("alerts", codesJson w.alerts)])),
   ("system", Json.mkObj [("alerts", codesJson r.system)]),
   ("counts", Json.mkObj [("active", toJson r.counts.active), ("idle", toJson r.counts.idle),
      ("waiting", toJson r.counts.waiting), ("stalled", toJson r.counts.stalled), ("done", toJson r.counts.done)]),
   ("alerts", .arr (r.alerts.toArray.map alertJson))]

/-- `obs.health`: decode the snapshot, compute the report. -/
def opHealth (req : Json) : Except String Reply := do
  let (p, o) ← reqOf req
  pure (reportFields (health p o))

/-- The reply to an encoded request is the encoded report.

$$\forall p, o:\quad \operatorname{opHealth}(\operatorname{reqJson}(p, o)) = \mathrm{ok}(\operatorname{fields}(\operatorname{health}(p, o)))$$
-/
theorem opHealth_reqJson (p : Params) (o : Obs) :
    opHealth (reqJson p o) = .ok (reportFields (health p o)) := by
  simp only [opHealth, reqOf_reqJson, ok_bind]
  rfl

/-- The `Fw.Obs` ops. -/
def ops : List String := ["obs.health"]

/-- Dispatch an `Fw.Obs` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "obs.health" => some (opHealth req)
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

#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":50}}" ==
  "{\"agents\":[],\"alerts\":[],\"counts\":{\"active\":0,\"done\":0,\"idle\":0,\"stalled\":0,\"waiting\":0},\"system\":{\"alerts\":[]}}"
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5,\"memPressure\":\"critical\",\"load1\":3.25}}" |>.startsWith
  "{\"agents\":[],\"alerts\":[{\"code\":\"sys.diskLow\""
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5.5}}" == "error: field diskFreeGB: expected a non-negative integer"
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5,\"memPressure\":\"high\"}}" ==
  "error: field memPressure: unknown value high"
#guard run "obs.health" "{\"now\":1200000,\"agents\":[{\"id\":\"a\",\"startedAt\":0,\"lastAt\":0}],\"system\":{\"diskFreeGB\":50}}"
  |>.startsWith "{\"agents\":[{\"alerts\":[\"agent.stalled\"],\"id\":\"a\",\"state\":\"stalled\"}]"

end Fw.Wire.Obs
