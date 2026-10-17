import Lean.Data.Json
import Std.Data.TreeMap.Raw.Lemmas
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
| `obs.health` | `now`, `params`?, `agents`? [Agent], `lead`? Lead, `system` System | `agents` [{id, state, alerts:[code]}] (input order), `system` {alerts:[code]}, `counts` {active, idle, parked, stalled, done}, `alerts` [{code, subject, detail}] (sorted by code, subject, detail; no duplicates) |

Shapes. Params (every field optional, defaults in brackets): `{idleMin [10], stallMin [20], toolHangMin [30]` (minutes),
`errStreak [3], ctxResumeMax [250000], ctxWarn [200000], diskMinGB [20], agentCap [10], simLockMaxMin [30]` (minutes),
`worktreesMax [20], wfQuietMin [30]}`. Agent: `{id, name?, task?, kind? ["lead"|"teammate"|"subagent"|"workflow";
"subagent"], parent?, startedAt, lastAt, stoppedAt?, errTail? [0], inflight? {tool, since}, lastTool?, lastToolAt?,
idleAt?, workflowDone? [false], transcriptOnly? [false], ctxTokens?}` (any other field, e.g. `type`, `model`, `tools`,
`errors`, `tokens`, `inflight.verb`, is ignored). Lead: `{lastToolAt?, noteAt?}` (absent: no events). System:
`{diskFreeGB, memPressure? ["normal"|"warn"|"critical"], simLock? {holder?, since?}, docker? [{id, name, startedAt}],
worktrees? [0] (a count), ci? [{workflow, branch, status, conclusion?, startedAt}]}` (any other field, e.g. `load1`,
`consolePids`, `stale`, is ignored). `null` counts as absent.

Proved: the round trips `paramsOf_paramsJson`, `agentOf_agentJson`, `leadOf_leadJson`, `systemOf_systemJson`,
`reqOf_reqJson`, and
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

/-- The thresholds' JSON fields (every field written). -/
def paramsFields (p : Params) : List (String × Json) :=
  [("idleMin", toJson p.idleMin), ("stallMin", toJson p.stallMin), ("toolHangMin", toJson p.toolHangMin),
    ("errStreak", toJson p.errStreak), ("ctxResumeMax", toJson p.ctxResumeMax), ("ctxWarn", toJson p.ctxWarn),
    ("diskMinGB", toJson p.diskMinGB), ("agentCap", toJson p.agentCap), ("simLockMaxMin", toJson p.simLockMaxMin),
    ("worktreesMax", toJson p.worktreesMax), ("wfQuietMin", toJson p.wfQuietMin)]

/-- The thresholds as JSON (every field written). -/
def paramsJson (p : Params) : Json := Json.mkObj (paramsFields p)

/-- Decode the thresholds; a missing field takes its default. -/
def paramsOf (j : Json) : Except String Params := do
  let d : Params := {}
  pure { idleMin := ← natD j "idleMin" d.idleMin, stallMin := ← natD j "stallMin" d.stallMin,
         toolHangMin := ← natD j "toolHangMin" d.toolHangMin, errStreak := ← natD j "errStreak" d.errStreak,
         ctxResumeMax := ← natD j "ctxResumeMax" d.ctxResumeMax, ctxWarn := ← natD j "ctxWarn" d.ctxWarn,
         diskMinGB := ← natD j "diskMinGB" d.diskMinGB, agentCap := ← natD j "agentCap" d.agentCap,
         simLockMaxMin := ← natD j "simLockMaxMin" d.simLockMaxMin,
         worktreesMax := ← natD j "worktreesMax" d.worktreesMax, wfQuietMin := ← natD j "wfQuietMin" d.wfQuietMin }

/-- A tool call in flight as JSON. -/
def inflightJson (f : Inflight) : Json := Json.mkObj [("tool", .str f.tool), ("since", toJson f.since)]

/-- Decode a tool call in flight (`verb` ignored). -/
def inflightOf (j : Json) : Except String Inflight := do
  pure { tool := ← str j "tool", since := ← nat j "since" }

/-- Agent-kind wire names. -/
def kindName : Kind → String
  | .lead => "lead" | .teammate => "teammate" | .subagent => "subagent" | .workflow => "workflow"

/-- An agent kind from its wire name (an unknown name is refused). -/
def kindOf : String → Except String Kind
  | "lead" => .ok .lead | "teammate" => .ok .teammate | "subagent" => .ok .subagent | "workflow" => .ok .workflow
  | s => .error s!"field kind: unknown value {s}"

/-- The optional `kind` field: absent or `null` is `subagent`; a non-string value or an unknown name is refused. -/
def kindD (j : Json) : Except String Kind :=
  match opt j "kind" with
  | none => .ok .subagent
  | some v => do kindOf (← asStr "kind" v)

/-- An agent's JSON fields (every field written; absent options are `null`). -/
def agentFields (a : Agent) : List (String × Json) :=
  [("id", .str a.id), ("name", ostr a.name), ("task", ostr a.task), ("kind", .str (kindName a.kind)),
    ("parent", ostr a.parent), ("startedAt", toJson a.startedAt), ("lastAt", toJson a.lastAt),
    ("stoppedAt", onat a.stoppedAt), ("errTail", toJson a.errTail),
    ("inflight", match a.inflight with | some f => inflightJson f | none => .null),
    ("lastTool", ostr a.lastTool), ("lastToolAt", onat a.lastToolAt), ("idleAt", onat a.idleAt),
    ("workflowDone", .bool a.workflowDone), ("transcriptOnly", .bool a.transcriptOnly), ("ctxTokens", onat a.ctxTokens)]

/-- An agent as JSON (every field written; absent options are `null`). -/
def agentJson (a : Agent) : Json := Json.mkObj (agentFields a)

/-- An optional tool call in flight (absent or `null` is `none`). -/
def optInflight (j : Json) : Except String (Option Inflight) :=
  match opt j "inflight" with
  | none => .ok none
  | some v => some <$> inflightOf v

/-- Decode an agent; `id`, `startedAt` and `lastAt` are required. -/
def agentOf (j : Json) : Except String Agent := do
  pure { id := ← str j "id", name := ← optS j "name", task := ← optS j "task", kind := ← kindD j,
         parent := ← optS j "parent", startedAt := ← nat j "startedAt", lastAt := ← nat j "lastAt",
         stoppedAt := ← optN j "stoppedAt", errTail := ← natD j "errTail" 0, inflight := ← optInflight j,
         lastTool := ← optS j "lastTool", lastToolAt := ← optN j "lastToolAt", idleAt := ← optN j "idleAt",
         workflowDone := ← boolD j "workflowDone" false, transcriptOnly := ← boolD j "transcriptOnly" false,
         ctxTokens := ← optN j "ctxTokens" }

/-- The lead session's facts as JSON. -/
def leadJson (l : Lead) : Json := Json.mkObj [("lastToolAt", onat l.lastToolAt), ("noteAt", onat l.noteAt)]

/-- Decode the lead session's facts (both fields optional). -/
def leadOf (j : Json) : Except String Lead := do
  pure { lastToolAt := ← optN j "lastToolAt", noteAt := ← optN j "noteAt" }

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

/-- A request body as JSON: `now`, `params`, `agents`, `lead`, `system`. -/
def reqJson (p : Params) (o : Obs) : Json :=
  Json.mkObj [("now", toJson o.now), ("params", paramsJson p), ("agents", .arr (o.agents.toArray.map agentJson)),
    ("lead", leadJson o.lead), ("system", systemJson o.system)]

/-- Decode a request body; `params`, `agents` and `lead` are optional (defaults, no agents, no lead events). -/
def reqOf (j : Json) : Except String (Params × Obs) := do
  let p ← match opt j "params" with
    | none => pure {}
    | some v => paramsOf v
  let agents ← (← arrD j "agents").mapM agentOf
  let lead ← match opt j "lead" with
    | none => pure {}
    | some v => leadOf v
  pure (p, { now := ← nat j "now", agents, lead, system := ← systemOf (← field j "system") })

/-! ## Round trips -/

/-- Looking a key up in an object built from a list with pairwise distinct keys gives that key's value.

$$\forall \ell, k, v:\quad \bigl(\operatorname{keys}(\ell)\ \text{pairwise distinct} \land (k, v) \in \ell\bigr)
  \implies \operatorname{getObjVal?}(\operatorname{mkObj}(\ell), k) = \mathrm{ok}(v)$$

Every field of an object written with distinct keys reads back as the value written.
-/
theorem getObjVal_mkObj {l : List (String × Json)} {k : String} {v : Json}
    (hd : (l.map Prod.fst).Pairwise (· ≠ ·)) (hm : (k, v) ∈ l) : (Json.mkObj l).getObjVal? k = .ok v := by
  have hd' : l.Pairwise (fun a b => ¬ compare a.1 b.1 = .eq) :=
    (List.pairwise_map.mp hd).imp fun h he => h (Std.LawfulEqCmp.eq_of_compare he)
  have h := Std.TreeMap.Raw.getElem?_ofList_of_mem (cmp := compare) (k := k) (k' := k)
    Std.ReflCmp.compare_self hd' hm
  simp only [Json.mkObj, Json.getObjVal?, Std.TreeMap.Raw.get?_eq_getElem?, h]
  rfl

/-- Close `(k, ?v) ∈ [literal list]` by trying each position (the first key match assigns `?v`). -/
local macro "mem_lit" : tactic => `(tactic| repeat first | exact List.Mem.head _ | apply List.Mem.tail)

/-- The thresholds' keys are pairwise distinct.

$$\forall p:\quad \operatorname{keys}(\operatorname{paramsFields}(p))\ \text{pairwise distinct}$$

No two threshold fields share a key.
-/
theorem paramsFields_keys (p : Params) : ((paramsFields p).map Prod.fst).Pairwise (· ≠ ·) := by
  simp only [paramsFields, List.map_cons, List.map_nil]
  decide +kernel

/-- Thresholds round-trip.

$$\forall p:\quad \operatorname{paramsOf}(\operatorname{paramsJson}(p)) = \mathrm{ok}(p)$$

Decoding the JSON written for the thresholds gives the same thresholds back.
-/
theorem paramsOf_paramsJson (p : Params) : paramsOf (paramsJson p) = .ok p := by
  have g : ∀ k v, (k, v) ∈ paramsFields p → (paramsJson p).getObjVal? k = .ok v :=
    fun _ _ hm => getObjVal_mkObj (paramsFields_keys p) hm
  simp only [paramsOf, natD, opt, g "idleMin" _ (by unfold paramsFields; mem_lit),
    g "stallMin" _ (by unfold paramsFields; mem_lit), g "toolHangMin" _ (by unfold paramsFields; mem_lit),
    g "errStreak" _ (by unfold paramsFields; mem_lit), g "ctxResumeMax" _ (by unfold paramsFields; mem_lit),
    g "ctxWarn" _ (by unfold paramsFields; mem_lit), g "diskMinGB" _ (by unfold paramsFields; mem_lit),
    g "agentCap" _ (by unfold paramsFields; mem_lit), g "simLockMaxMin" _ (by unfold paramsFields; mem_lit),
    g "worktreesMax" _ (by unfold paramsFields; mem_lit), g "wfQuietMin" _ (by unfold paramsFields; mem_lit)]
  rfl

/-- An agent's keys are pairwise distinct.

$$\forall a:\quad \operatorname{keys}(\operatorname{agentFields}(a))\ \text{pairwise distinct}$$

No two agent fields share a key.
-/
theorem agentFields_keys (a : Agent) : ((agentFields a).map Prod.fst).Pairwise (· ≠ ·) := by
  simp only [agentFields, List.map_cons, List.map_nil]
  decide +kernel

/-- Agents round-trip.

$$\forall a:\quad \operatorname{agentOf}(\operatorname{agentJson}(a)) = \mathrm{ok}(a)$$

Decoding the JSON written for an agent gives the same agent back.
-/
theorem agentOf_agentJson (a : Agent) : agentOf (agentJson a) = .ok a := by
  have g : ∀ k v, (k, v) ∈ agentFields a → (agentJson a).getObjVal? k = .ok v :=
    fun _ _ hm => getObjVal_mkObj (agentFields_keys a) hm
  have hid : str (agentJson a) "id" = .ok a.id := by
    unfold str field; rw [g "id" _ (by unfold agentFields; mem_lit)]; rfl
  have hn : optS (agentJson a) "name" = .ok a.name := by
    unfold optS opt; rw [g "name" _ (by unfold agentFields; mem_lit)]; cases a.name <;> rfl
  have ht : optS (agentJson a) "task" = .ok a.task := by
    unfold optS opt; rw [g "task" _ (by unfold agentFields; mem_lit)]; cases a.task <;> rfl
  have hk : kindD (agentJson a) = .ok a.kind := by
    unfold kindD opt; rw [g "kind" _ (by unfold agentFields; mem_lit)]; cases a.kind <;> rfl
  have hp : optS (agentJson a) "parent" = .ok a.parent := by
    unfold optS opt; rw [g "parent" _ (by unfold agentFields; mem_lit)]; cases a.parent <;> rfl
  have hst : nat (agentJson a) "startedAt" = .ok a.startedAt := by
    unfold nat field; rw [g "startedAt" _ (by unfold agentFields; mem_lit)]; rfl
  have hl : nat (agentJson a) "lastAt" = .ok a.lastAt := by
    unfold nat field; rw [g "lastAt" _ (by unfold agentFields; mem_lit)]; rfl
  have hs : optN (agentJson a) "stoppedAt" = .ok a.stoppedAt := by
    unfold optN opt; rw [g "stoppedAt" _ (by unfold agentFields; mem_lit)]; cases a.stoppedAt <;> rfl
  have he : natD (agentJson a) "errTail" 0 = .ok a.errTail := by
    unfold natD opt; rw [g "errTail" _ (by unfold agentFields; mem_lit)]; rfl
  have hi : optInflight (agentJson a) = .ok a.inflight := by
    unfold optInflight opt; rw [g "inflight" _ (by unfold agentFields; mem_lit)]
    cases a.inflight with
    | none => rfl
    | some f => cases f; rfl
  have hlt : optS (agentJson a) "lastTool" = .ok a.lastTool := by
    unfold optS opt; rw [g "lastTool" _ (by unfold agentFields; mem_lit)]; cases a.lastTool <;> rfl
  have hla : optN (agentJson a) "lastToolAt" = .ok a.lastToolAt := by
    unfold optN opt; rw [g "lastToolAt" _ (by unfold agentFields; mem_lit)]; cases a.lastToolAt <;> rfl
  have hia : optN (agentJson a) "idleAt" = .ok a.idleAt := by
    unfold optN opt; rw [g "idleAt" _ (by unfold agentFields; mem_lit)]; cases a.idleAt <;> rfl
  have hw : boolD (agentJson a) "workflowDone" false = .ok a.workflowDone := by
    unfold boolD opt; rw [g "workflowDone" _ (by unfold agentFields; mem_lit)]; cases a.workflowDone <;> rfl
  have hr : boolD (agentJson a) "transcriptOnly" false = .ok a.transcriptOnly := by
    unfold boolD opt; rw [g "transcriptOnly" _ (by unfold agentFields; mem_lit)]; cases a.transcriptOnly <;> rfl
  have hc : optN (agentJson a) "ctxTokens" = .ok a.ctxTokens := by
    unfold optN opt; rw [g "ctxTokens" _ (by unfold agentFields; mem_lit)]; cases a.ctxTokens <;> rfl
  simp only [agentOf, hid, hn, ht, hk, hp, hst, hl, hs, he, hi, hlt, hla, hia, hw, hr, hc, ok_bind]
  rfl

/-- The lead session's facts round-trip.

$$\forall \ell:\quad \operatorname{leadOf}(\operatorname{leadJson}(\ell)) = \mathrm{ok}(\ell)$$

Decoding the JSON written for the lead's facts gives the same facts back.
-/
theorem leadOf_leadJson (l : Lead) : leadOf (leadJson l) = .ok l := by
  obtain ⟨t, n⟩ := l
  cases t <;> cases n <;> rfl

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
  obtain ⟨now, agents, lead, sys⟩ := o
  have ha := arrD_arr (reqJson p ⟨now, agents, lead, sys⟩) "agents" _ rfl
  have hp : opt (reqJson p ⟨now, agents, lead, sys⟩) "params" = some (paramsJson p) := rfl
  have hl : opt (reqJson p ⟨now, agents, lead, sys⟩) "lead" = some (leadJson lead) := rfl
  have hs : field (reqJson p ⟨now, agents, lead, sys⟩) "system" = .ok (systemJson sys) := rfl
  simp only [reqOf, ha, hp, hl, hs, Array.toList_map, ok_bind, paramsOf_paramsJson, leadOf_leadJson,
    mapM_rt agentJson agentOf agentOf_agentJson, systemOf_systemJson]
  rfl

/-! ## The op -/

/-- State wire names. -/
def stateName : State → String
  | .active => "active" | .idle => "idle" | .parked => "parked" | .stalled => "stalled" | .done => "done"

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
      ("parked", toJson r.counts.parked), ("stalled", toJson r.counts.stalled), ("done", toJson r.counts.done)]),
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
  "{\"agents\":[],\"alerts\":[],\"counts\":{\"active\":0,\"done\":0,\"idle\":0,\"parked\":0,\"stalled\":0},\"system\":{\"alerts\":[]}}"
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5,\"memPressure\":\"critical\",\"load1\":3.25}}" |>.startsWith
  "{\"agents\":[],\"alerts\":[{\"code\":\"sys.diskLow\""
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5.5}}" == "error: field diskFreeGB: expected a non-negative integer"
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5,\"memPressure\":\"high\"}}" ==
  "error: field memPressure: unknown value high"
#guard run "obs.health" "{\"now\":1200000,\"agents\":[{\"id\":\"a\",\"startedAt\":0,\"lastAt\":0}],\"system\":{\"diskFreeGB\":50}}"
  |>.startsWith "{\"agents\":[{\"alerts\":[\"agent.stalled\"],\"id\":\"a\",\"state\":\"stalled\"}]"

end Fw.Wire.Obs
