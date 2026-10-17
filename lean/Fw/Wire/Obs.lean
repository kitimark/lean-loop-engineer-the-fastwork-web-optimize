import Lean.Data.Json
import Std.Data.TreeMap.Raw.Lemmas
import Fw.Obs.Health
import Fw.Obs.Next
import Fw.Ops.Wire
import Fw.Wire.Sched
/-!
# JSON codecs and the op `obs.health` (team health of one observation snapshot)

Glue between `fwcore`'s JSON lines and `Fw.Obs.Health` (namespace `Fw.Wire.Obs`, so the math view treats it as
wire code). Total decoders only (`Except String`); no partial operations. Times are integer ms since the epoch; every
number is a non-negative integer (a fraction is refused, so the caller floors `diskFreeGB`).

| op | request | reply |
|---|---|---|
| `obs.health` | `now`, `params`?, `agents`? [Agent], `lead`? Lead, `system` System, `prevAt`?, `critical`? [string] | `agents` [{id, state, alerts:[code]}] (input order), `system` {alerts:[code]} (code order), `counts` {active, idle, parked, stalled, gone, done}, `alerts` [{code, subject, detail, critical}] (critical first, then by code, subject, detail; no duplicates) |
| `obs.next` | `now`, `params`?, `agents`? [AgentFacts] | `agents` [{id, actions:[{action, …args}]}] (input order; `Fw.Obs.Next.next`) |

Shapes. Params (every field optional, defaults in brackets): `{idleMin [10], stallMin [20], toolHangMin [30]` (minutes),
`errStreak [3], ctxResumeMax [250000], ctxWarn [200000], diskMinGB [20], agentCap [10], simLockMaxMin [30]` (minutes),
`worktreesMax [20], wfQuietMin [30], goneAfterMin [120], ciSlowMin [20], toolSlowMin [15], procMaxMin [20]`
(minutes), `loadMax [150]}`. Agent: `{id, name?, task?, kind? ["lead"|"teammate"|"subagent"|"workflow";
"subagent"], parent?, startedAt, lastAt, stoppedAt?, errTail? [0], inflight? {tool, since}, lastTool?, lastToolAt?,
idleAt?, workflowDone? [false], transcriptOnly? [false], ctxTokens?}` (any other field, e.g. `type`, `model`, `tools`,
`errors`, `tokens`, `inflight.verb`, is ignored). Lead: `{lastToolAt?, noteAt?}` (absent: no events). System:
`{diskFreeGB, memPressure? ["normal"|"warn"|"critical"], simLock? {holder?, since?}, docker? [{id, name, startedAt}],
worktrees? [0] (a count), ci? [{workflow, branch, status, conclusion?, startedAt, endedAt?}], loadFloor? [0] (the floor
of the 1-min load average), procs? [{pid, name, startedAt, pids? [[]], agent?}] (`agent`: the
id of the agent whose Bash call started the tree), services? [[]] (pids), keep? [[]] (pids the lead declared)}` (any other field,
e.g. `load1`, `consolePids`, `stale`, is ignored). `prevAt` is the time of the previous check (absent: first check);
`critical` lists the task ids on the critical path. `null` counts as absent.

`obs.next` shapes. Params: the Health params plus `loopCapMin [30], fileStaleMin [10]` (minutes). AgentFacts:
`{id, task, state ["active"|"idle"|"parked"|"stalled"|"gone"|"done"], session, handbackAt?, branch? {name, ahead,
landed, queued? [false], mergesClean? [true], deps? [[]]}, handoff? [false], worktree? {lockPid?, lockAlive? [false]}, ctxTokens? [0], children? [{pid, chain? [[]],
kind ["sleepLoop"|"ciWait"|"build"|"other"], run and timeoutMin (ciWait only), startedAt, watchedAt?,
producerExited? [false]}], ci? {id, workflow, branch, status, conclusion?, startedAt, endedAt?}, board? {id, done,
agent?}}`. Action: `{action}` plus `run` (waitCi), `branch`, `task` (land), `branch` (routeIntegrator), `pid`
(killOrphan), `reason` ["heldByChild"|"ciWaitOverdue"|"foreignLoop"|"lockDead"|"conflict"] (investigate), `task`, `agent`
(claimTask), `dep` (waitDeps). Golden vectors in `packages/contracts/golden/obs/next.jsonl` (`Fw.Wire.Obs.NextGolden`, this file).

Proved: the round trips `paramsOf_paramsJson`, `agentOf_agentJson`, `leadOf_leadJson`, `systemOf_systemJson`,
`procOf_procJson`, `reqOf_reqJson`, and
`opHealth_reqJson` (the reply to an encoded request is the encoded `health` report). Guards at the end; golden vectors
in `packages/contracts/golden/obs/health.jsonl` (`Fw.Wire.Obs.Golden`, file `Fw/Obs/Golden.lean`).
-/
namespace Fw.Wire.Obs
open Lean
open Fw.Wire.Ops (Reply field opt asStr asNat asBool asArr str nat arr natD boolD arrD ostr)
open Fw.Wire.Sched (optS ok_bind mapM_rt arrD_arr strsD strsD_rt)
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
    ("worktreesMax", toJson p.worktreesMax), ("wfQuietMin", toJson p.wfQuietMin),
    ("goneAfterMin", toJson p.goneAfterMin), ("ciSlowMin", toJson p.ciSlowMin), ("toolSlowMin", toJson p.toolSlowMin),
    ("procMaxMin", toJson p.procMaxMin), ("loadMax", toJson p.loadMax)]

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
         worktreesMax := ← natD j "worktreesMax" d.worktreesMax, wfQuietMin := ← natD j "wfQuietMin" d.wfQuietMin,
         goneAfterMin := ← natD j "goneAfterMin" d.goneAfterMin, ciSlowMin := ← natD j "ciSlowMin" d.ciSlowMin,
         toolSlowMin := ← natD j "toolSlowMin" d.toolSlowMin, procMaxMin := ← natD j "procMaxMin" d.procMaxMin,
         loadMax := ← natD j "loadMax" d.loadMax }

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
    ("conclusion", ostr r.conclusion), ("startedAt", toJson r.startedAt), ("endedAt", onat r.endedAt)]

/-- Decode a CI run (`conclusion` and `endedAt` optional). -/
def ciOf (j : Json) : Except String CiRun := do
  pure { workflow := ← str j "workflow", branch := ← str j "branch", status := ← str j "status",
         conclusion := ← optS j "conclusion", startedAt := ← nat j "startedAt", endedAt := ← optN j "endedAt" }

/-- A process tree as JSON. -/
def procJson (q : Proc) : Json :=
  Json.mkObj [("pid", toJson q.pid), ("name", .str q.name), ("startedAt", toJson q.startedAt),
    ("pids", .arr (q.pids.toArray.map toJson)), ("agent", ostr q.agent)]

/-- Decode a process tree (`pids` optional, default empty; `agent` optional). -/
def procOf (j : Json) : Except String Proc := do
  pure { pid := ← nat j "pid", name := ← str j "name", startedAt := ← nat j "startedAt",
         pids := ← (← arrD j "pids").mapM (asNat "pids"), agent := ← optS j "agent" }

/-- The system facts as JSON (every field written). -/
def systemJson (s : System) : Json :=
  Json.mkObj [("diskFreeGB", toJson s.diskFreeGB), ("memPressure", .str (memName s.memPressure)),
    ("simLock", simLockJson s.simLock), ("docker", .arr (s.docker.toArray.map containerJson)),
    ("worktrees", toJson s.worktrees), ("ci", .arr (s.ci.toArray.map ciJson)), ("loadFloor", toJson s.loadFloor),
    ("procs", .arr (s.procs.toArray.map procJson)), ("services", .arr (s.services.toArray.map toJson)),
    ("keep", .arr (s.keep.toArray.map toJson))]

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
         ci := ← (← arrD j "ci").mapM ciOf, loadFloor := ← natD j "loadFloor" 0,
         procs := ← (← arrD j "procs").mapM procOf, services := ← (← arrD j "services").mapM (asNat "services"),
         keep := ← (← arrD j "keep").mapM (asNat "keep") }

/-- A request body as JSON: `now`, `params`, `agents`, `lead`, `system`, `prevAt`, `critical`. -/
def reqJson (p : Params) (o : Obs) : Json :=
  Json.mkObj [("now", toJson o.now), ("params", paramsJson p), ("agents", .arr (o.agents.toArray.map agentJson)),
    ("lead", leadJson o.lead), ("system", systemJson o.system), ("prevAt", onat o.prevAt),
    ("critical", .arr (o.critical.toArray.map .str))]

/-- Decode a request body; `params`, `agents`, `lead`, `prevAt` and `critical` are optional (defaults, no agents, no
lead events, first check, no critical task). -/
def reqOf (j : Json) : Except String (Params × Obs) := do
  let p ← match opt j "params" with
    | none => pure {}
    | some v => paramsOf v
  let agents ← (← arrD j "agents").mapM agentOf
  let lead ← match opt j "lead" with
    | none => pure {}
    | some v => leadOf v
  pure (p, { now := ← nat j "now", agents, lead, system := ← systemOf (← field j "system"),
             prevAt := ← optN j "prevAt", critical := ← strsD j "critical" })

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
    g "worktreesMax" _ (by unfold paramsFields; mem_lit), g "wfQuietMin" _ (by unfold paramsFields; mem_lit),
    g "goneAfterMin" _ (by unfold paramsFields; mem_lit), g "ciSlowMin" _ (by unfold paramsFields; mem_lit),
    g "toolSlowMin" _ (by unfold paramsFields; mem_lit), g "procMaxMin" _ (by unfold paramsFields; mem_lit),
    g "loadMax" _ (by unfold paramsFields; mem_lit)]
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
  obtain ⟨w, b, s, c, t, e⟩ := r
  cases c <;> cases e <;> rfl

/-- Process trees round-trip.

$$\forall q:\quad \operatorname{procOf}(\operatorname{procJson}(q)) = \mathrm{ok}(q)$$

Decoding the JSON written for a process tree gives the same tree back.
-/
theorem procOf_procJson (q : Proc) : procOf (procJson q) = .ok q := by
  obtain ⟨pid, name, st, pids, ag⟩ := q
  have hp := arrD_arr (procJson ⟨pid, name, st, pids, ag⟩) "pids" _ rfl
  have ha : optS (procJson ⟨pid, name, st, pids, ag⟩) "agent" = .ok ag := by cases ag <;> rfl
  simp only [procOf, hp, ha, Array.toList_map, ok_bind, mapM_rt toJson (asNat "pids") (fun _ => rfl)]
  rfl

/-- System facts round-trip.

$$\forall s:\quad \operatorname{systemOf}(\operatorname{systemJson}(s)) = \mathrm{ok}(s)$$
-/
theorem systemOf_systemJson (s : System) : systemOf (systemJson s) = .ok s := by
  obtain ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci, lf, procs, svc, kp⟩ := s
  have hd := arrD_arr (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci, lf, procs, svc, kp⟩) "docker" _ rfl
  have hc := arrD_arr (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci, lf, procs, svc, kp⟩) "ci" _ rfl
  have hq := arrD_arr (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci, lf, procs, svc, kp⟩) "procs" _ rfl
  have hv := arrD_arr (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci, lf, procs, svc, kp⟩) "services" _ rfl
  have hk := arrD_arr (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci, lf, procs, svc, kp⟩) "keep" _ rfl
  have hm : opt (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci, lf, procs, svc, kp⟩) "memPressure" =
      some (.str (memName mem)) := rfl
  have hl : opt (systemJson ⟨disk, mem, ⟨holder, since⟩, docker, wt, ci, lf, procs, svc, kp⟩) "simLock" =
      some (simLockJson ⟨holder, since⟩) := rfl
  have hml : memOf (memName mem) = .ok mem := by cases mem <;> rfl
  have hsl : simLockOf (simLockJson ⟨holder, since⟩) = .ok ⟨holder, since⟩ := by
    cases holder <;> cases since <;> rfl
  simp only [systemOf, hd, hc, hq, hv, hk, hm, hl, Array.toList_map, ok_bind,
    mapM_rt containerJson containerOf containerOf_containerJson, mapM_rt ciJson ciOf ciOf_ciJson,
    mapM_rt procJson procOf procOf_procJson, mapM_rt toJson (asNat "services") (fun _ => rfl),
    mapM_rt toJson (asNat "keep") (fun _ => rfl)]
  simp only [asStr, ok_bind, hml, hsl]
  rfl

/-- Requests round-trip.

$$\forall p, o:\quad \operatorname{reqOf}(\operatorname{reqJson}(p, o)) = \mathrm{ok}(p, o)$$
-/
theorem reqOf_reqJson (p : Params) (o : Obs) : reqOf (reqJson p o) = .ok (p, o) := by
  obtain ⟨now, agents, lead, sys, prev, crit⟩ := o
  have ha := arrD_arr (reqJson p ⟨now, agents, lead, sys, prev, crit⟩) "agents" _ rfl
  have hp : opt (reqJson p ⟨now, agents, lead, sys, prev, crit⟩) "params" = some (paramsJson p) := rfl
  have hl : opt (reqJson p ⟨now, agents, lead, sys, prev, crit⟩) "lead" = some (leadJson lead) := rfl
  have hs : field (reqJson p ⟨now, agents, lead, sys, prev, crit⟩) "system" = .ok (systemJson sys) := rfl
  have hv : optN (reqJson p ⟨now, agents, lead, sys, prev, crit⟩) "prevAt" = .ok prev := by
    cases prev <;> rfl
  have hk := strsD_rt (reqJson p ⟨now, agents, lead, sys, prev, crit⟩) "critical" crit rfl
  simp only [reqOf, ha, hp, hl, hs, hv, hk, Array.toList_map, ok_bind, paramsOf_paramsJson, leadOf_leadJson,
    mapM_rt agentJson agentOf agentOf_agentJson, systemOf_systemJson]
  rfl

/-! ## The op -/

/-- State wire names. -/
def stateName : State → String
  | .active => "active" | .idle => "idle" | .parked => "parked" | .stalled => "stalled" | .gone => "gone"
  | .done => "done"

/-- An alert as JSON (`critical`: tied to a critical-path task). -/
def alertJson (x : Alert) : Json :=
  Json.mkObj [("code", .str x.code.name), ("subject", .str x.subject), ("detail", .str x.detail),
    ("critical", .bool x.crit)]

/-- A list of codes as a JSON array of names. -/
def codesJson (cs : List Code) : Json := .arr (cs.toArray.map fun c => .str c.name)

/-- The reply fields of a report. -/
def reportFields (r : Report) : Reply :=
  [("agents", .arr (r.agents.toArray.map fun w =>
      Json.mkObj [("id", .str w.id), ("state", .str (stateName w.state)), ("alerts", codesJson w.alerts)])),
   ("system", Json.mkObj [("alerts", codesJson r.system)]),
   ("counts", Json.mkObj [("active", toJson r.counts.active), ("idle", toJson r.counts.idle),
      ("parked", toJson r.counts.parked), ("stalled", toJson r.counts.stalled), ("gone", toJson r.counts.gone),
      ("done", toJson r.counts.done)]),
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

/-! ## The op `obs.next` (`Fw.Obs.Next`) -/

open Fw.Obs.Next (AgentFacts Child ChildKind Branch Worktree Ci TaskRow Reason Action)

/-- The `obs.next` thresholds as one flat object: every Health field plus `loopCapMin` and `fileStaleMin`. -/
def nextParamsJson (p : Fw.Obs.Next.Params) : Json :=
  Json.mkObj (paramsFields p.health ++
    [("loopCapMin", toJson p.loopCapMin), ("fileStaleMin", toJson p.fileStaleMin)])

/-- Decode the `obs.next` thresholds; a missing field takes its default (`loopCapMin` 30, `fileStaleMin` 10). -/
def nextParamsOf (j : Json) : Except String Fw.Obs.Next.Params := do
  let d : Fw.Obs.Next.Params := {}
  pure { health := ← paramsOf j, loopCapMin := ← natD j "loopCapMin" d.loopCapMin,
         fileStaleMin := ← natD j "fileStaleMin" d.fileStaleMin }

/-- A state from its wire name (an unknown name is refused). -/
def stateOf : String → Except String State
  | "active" => .ok .active | "idle" => .ok .idle | "parked" => .ok .parked | "stalled" => .ok .stalled
  | "gone" => .ok .gone | "done" => .ok .done
  | s => .error s!"field state: unknown value {s}"

/-- A list of naturals as a JSON array. -/
def natsJson (l : List Nat) : Json := .arr (l.toArray.map toJson)

/-- A child process as JSON (`run` and `timeoutMin` only for a `ciWait`). -/
def childJson (c : Child) : Json :=
  let k : List (String × Json) := match c.kind with
    | .sleepLoop => [("kind", .str "sleepLoop")]
    | .ciWait r m => [("kind", .str "ciWait"), ("run", toJson r), ("timeoutMin", toJson m)]
    | .build => [("kind", .str "build")]
    | .other => [("kind", .str "other")]
  Json.mkObj ([("pid", toJson c.pid), ("chain", natsJson c.chain)] ++ k ++
    [("startedAt", toJson c.startedAt), ("watchedAt", onat c.watchedAt), ("producerExited", .bool c.producerExited)])

/-- A child kind (`ciWait` needs `run` and `timeoutMin`; an unknown kind is refused). -/
def childKindOf (j : Json) : Except String ChildKind := do
  match ← str j "kind" with
  | "sleepLoop" => pure .sleepLoop
  | "ciWait" => pure (.ciWait (← nat j "run") (← nat j "timeoutMin"))
  | "build" => pure .build
  | "other" => pure .other
  | s => throw s!"field kind: unknown value {s}"

/-- Decode a child process (`chain` optional, default empty; `watchedAt` optional; `producerExited` default false). -/
def childOf (j : Json) : Except String Child := do
  pure { pid := ← nat j "pid", chain := ← (← arrD j "chain").mapM (asNat "chain"), kind := ← childKindOf j,
         startedAt := ← nat j "startedAt", watchedAt := ← optN j "watchedAt",
         producerExited := ← boolD j "producerExited" false }

/-- A branch as JSON. -/
def branchJson (b : Branch) : Json :=
  Json.mkObj [("name", .str b.name), ("ahead", toJson b.ahead), ("landed", .bool b.landed), ("queued", .bool b.queued),
    ("mergesClean", .bool b.mergesClean), ("deps", .arr (b.deps.toArray.map .str))]

/-- Decode a branch (`name`, `ahead`, `landed` required; `queued` default false). -/
def branchOf (j : Json) : Except String Branch := do
  pure { name := ← str j "name", ahead := ← nat j "ahead", landed := ← asBool "landed" (← field j "landed"),
         queued := ← boolD j "queued" false, mergesClean := ← boolD j "mergesClean" true,
         deps := ← (← arrD j "deps").mapM (fun v => match v with | .str x => pure x | _ => throw "deps: string expected") }

/-- A worktree as JSON. -/
def worktreeJson (w : Worktree) : Json := Json.mkObj [("lockPid", onat w.lockPid), ("lockAlive", .bool w.lockAlive)]

/-- Decode a worktree (both fields optional: not locked, not alive). -/
def worktreeOf (j : Json) : Except String Worktree := do
  pure { lockPid := ← optN j "lockPid", lockAlive := ← boolD j "lockAlive" false }

/-- An agent's CI run as JSON: its id plus the `CiRun` fields. -/
def ciNextJson (c : Ci) : Json :=
  Json.mkObj [("id", toJson c.id), ("workflow", .str c.run.workflow), ("branch", .str c.run.branch),
    ("status", .str c.run.status), ("conclusion", ostr c.run.conclusion), ("startedAt", toJson c.run.startedAt),
    ("endedAt", onat c.run.endedAt)]

/-- Decode an agent's CI run (`id` plus the `CiRun` fields). -/
def ciNextOf (j : Json) : Except String Ci := do
  pure { id := ← nat j "id", run := ← ciOf j }

/-- A board row as JSON. -/
def taskRowJson (r : TaskRow) : Json :=
  Json.mkObj [("id", .str r.id), ("done", .bool r.done), ("agent", ostr r.agent)]

/-- Decode a board row (`id`, `done` required; `agent` optional: unbound). -/
def taskRowOf (j : Json) : Except String TaskRow := do
  pure { id := ← str j "id", done := ← asBool "done" (← field j "done"), agent := ← optS j "agent" }

/-- An optional object field decoded with `f` (absent or `null` is `none`). -/
def optObj {α : Type} (j : Json) (k : String) (f : Json → Except String α) : Except String (Option α) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> f v

/-- An agent's facts as JSON (every field written; absent options are `null`). -/
def factsJson (f : AgentFacts) : Json :=
  Json.mkObj [("id", .str f.id), ("task", .str f.task), ("state", .str (stateName f.state)),
    ("handbackAt", onat f.handbackAt), ("session", toJson f.session),
    ("branch", match f.branch with | some b => branchJson b | none => .null),
    ("worktree", match f.worktree with | some w => worktreeJson w | none => .null),
    ("ctxTokens", toJson f.ctxTokens), ("children", .arr (f.children.toArray.map childJson)),
    ("ci", match f.ci with | some c => ciNextJson c | none => .null),
    ("board", match f.board with | some r => taskRowJson r | none => .null), ("handoff", .bool f.handoff)]

/-- Decode an agent's facts; `id`, `task`, `state` and `session` are required. -/
def factsOf (j : Json) : Except String AgentFacts := do
  pure { id := ← str j "id", task := ← str j "task", state := ← stateOf (← str j "state"),
         handbackAt := ← optN j "handbackAt", session := ← nat j "session",
         branch := ← optObj j "branch" branchOf, worktree := ← optObj j "worktree" worktreeOf,
         ctxTokens := ← natD j "ctxTokens" 0, children := ← (← arrD j "children").mapM childOf,
         ci := ← optObj j "ci" ciNextOf, board := ← optObj j "board" taskRowOf,
         handoff := ← boolD j "handoff" false }

/-- An `obs.next` request body as JSON: `now`, `params`, `agents`. -/
def nextReqJson (p : Fw.Obs.Next.Params) (now : Nat) (fs : List AgentFacts) : Json :=
  Json.mkObj [("now", toJson now), ("params", nextParamsJson p), ("agents", .arr (fs.toArray.map factsJson))]

/-- Decode an `obs.next` request body; `params` and `agents` are optional (defaults, no agents). -/
def nextReqOf (j : Json) : Except String (Fw.Obs.Next.Params × Nat × List AgentFacts) := do
  let p ← match opt j "params" with
    | none => pure {}
    | some v => nextParamsOf v
  pure (p, ← nat j "now", ← (← arrD j "agents").mapM factsOf)

/-- Reason wire names. -/
def reasonName : Reason → String
  | .heldByChild => "heldByChild" | .ciWaitOverdue => "ciWaitOverdue" | .foreignLoop => "foreignLoop"
  | .lockDead => "lockDead" | .conflict => "conflict"

/-- An action as JSON: `{action}` plus its arguments (`run`, `branch`, `task`, `pid`, `reason`). -/
def actionJson : Action → Json
  | .none => Json.mkObj [("action", .str "none")]
  | .waitCi r => Json.mkObj [("action", .str "waitCi"), ("run", toJson r)]
  | .land b k => Json.mkObj [("action", .str "land"), ("branch", .str b), ("task", .str k)]
  | .routeIntegrator b => Json.mkObj [("action", .str "routeIntegrator"), ("branch", .str b)]
  | .killOrphan q => Json.mkObj [("action", .str "killOrphan"), ("pid", toJson q)]
  | .cleanupWorktree => Json.mkObj [("action", .str "cleanupWorktree")]
  | .respawnFromHandoff => Json.mkObj [("action", .str "respawnFromHandoff")]
  | .nudgeHandoff => Json.mkObj [("action", .str "nudgeHandoff")]
  | .investigate r => Json.mkObj [("action", .str "investigate"), ("reason", .str (reasonName r))]
  | .claimTask k a => Json.mkObj [("action", .str "claimTask"), ("task", .str k), ("agent", .str a)]
  | .waitDeps d => Json.mkObj [("action", .str "waitDeps"), ("dep", .str d)]

/-- The reply fields of `obs.next`: per agent (input order) its id and actions. -/
def nextReply (p : Fw.Obs.Next.Params) (now : Nat) (fs : List AgentFacts) : Reply :=
  [("agents", .arr (fs.toArray.map fun f =>
    Json.mkObj [("id", .str f.id), ("actions", .arr ((Fw.Obs.Next.next p now f).toArray.map actionJson))]))]

/-- `obs.next`: decode the facts, compute each agent's next actions. -/
def opNext (req : Json) : Except String Reply := do
  let (p, now, fs) ← nextReqOf req
  pure (nextReply p now fs)

/-- The `Fw.Obs` ops. -/
def ops : List String := ["obs.health", "obs.next"]

/-- Dispatch an `Fw.Obs` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "obs.health" => some (opHealth req)
  | "obs.next" => some (opNext req)
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
  "{\"agents\":[],\"alerts\":[],\"counts\":{\"active\":0,\"done\":0,\"gone\":0,\"idle\":0,\"parked\":0,\"stalled\":0},\"system\":{\"alerts\":[]}}"
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5,\"memPressure\":\"critical\",\"load1\":3.25}}" |>.startsWith
  "{\"agents\":[],\"alerts\":[{\"code\":\"sys.diskLow\""
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5.5}}" == "error: field diskFreeGB: expected a non-negative integer"
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":5,\"memPressure\":\"high\"}}" ==
  "error: field memPressure: unknown value high"
#guard run "obs.health" "{\"now\":1200000,\"agents\":[{\"id\":\"a\",\"startedAt\":0,\"lastAt\":0}],\"system\":{\"diskFreeGB\":50}}"
  |>.startsWith "{\"agents\":[{\"alerts\":[\"agent.stalled\"],\"id\":\"a\",\"state\":\"stalled\"}]"

#guard run "obs.health" "{\"now\":7260000,\"prevAt\":7000000,\"agents\":[{\"id\":\"a\",\"startedAt\":0,\"lastAt\":0}],\"system\":{\"diskFreeGB\":50}}"
  |>.startsWith "{\"agents\":[{\"alerts\":[\"agent.gone\"],\"id\":\"a\",\"state\":\"gone\"}]"
#guard run "obs.health" "{\"now\":0,\"critical\":[\"x\"],\"system\":{\"diskFreeGB\":50,\"loadFloor\":150,\"ci\":[{\"workflow\":\"w\",\"branch\":\"ci/x\",\"status\":\"completed\",\"conclusion\":\"failure\",\"startedAt\":0}]}}"
  |>.startsWith "{\"agents\":[],\"alerts\":[{\"code\":\"ci.failed\",\"critical\":true,"
#guard run "obs.health" "{\"now\":0,\"system\":{\"diskFreeGB\":50,\"procs\":[{\"pid\":1,\"name\":\"n\",\"startedAt\":0,\"pids\":[2.5]}]}}"
  == "error: field pids: expected a non-negative integer"

#guard run "obs.next" "{\"now\":0}" == "{\"agents\":[]}"
#guard run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1}]}" ==
  "{\"agents\":[{\"actions\":[{\"action\":\"none\"}],\"id\":\"a\"}]}"
#guard run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"busy\",\"session\":1}]}" ==
  "error: field state: unknown value busy"
#guard run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"active\",\"session\":1,\"board\":{\"id\":\"a\",\"done\":false}}]}" ==
  "{\"agents\":[{\"actions\":[{\"action\":\"claimTask\",\"agent\":\"a\",\"task\":\"a\"}],\"id\":\"a\"}]}"
#guard run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"active\",\"session\":1,\"children\":[{\"pid\":7,\"chain\":[1],\"kind\":\"sleepLoop\",\"startedAt\":0,\"watchedAt\":5,\"producerExited\":true}]}]}" ==
  "{\"agents\":[{\"actions\":[{\"action\":\"killOrphan\",\"pid\":7},{\"action\":\"nudgeHandoff\"}],\"id\":\"a\"}]}"
#guard run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":7,\"kind\":\"ciWait\",\"startedAt\":0}]}]}" ==
  "error: missing field run"

/-! ## Golden vectors of `obs.next`

`packages/contracts/golden/obs/next.jsonl`: one line per case, `{"name", "request", "response"}` as for `obs.health`
(`request` carries its `op`; `response` is the reply without the id). Generated from Lean, never by hand: `run "."
true` writes it, `run "." false` checks it (from `lean/`, e.g. `lake env lean --run` on a two-line script calling
`Fw.Wire.Obs.NextGolden.run`). The typed cases repeat the observed failures (cases 1 to 7 of the obs-next task) and
both sides of every threshold edge; `gaps` checks that every action and every reason is produced. -/
namespace NextGolden
open Fw.Obs.Next (t0 ago ex)

/-- A sleep loop under session 100 started at `s`, watching a file last changed at `w`. -/
def lp (pid s : Nat) (w : Option Nat := none) (x : Bool := false) : Child :=
  { pid, chain := [100, 1], kind := .sleepLoop, startedAt := s, watchedAt := w, producerExited := x }

/-- A child of kind `k` under session 100 started at `s`. -/
def ch (pid : Nat) (k : ChildKind) (s : Nat) : Child := { pid, chain := [100, 1], kind := k, startedAt := s }

/-- A running CI run of `ci/<t>` with id `r`. -/
def ciRun (r : Nat) (t : String) : Ci :=
  ⟨r, { workflow := "ci", branch := s!"ci/{t}", status := "in_progress", startedAt := ago 5 }⟩

/-- One typed case: name, params, time, agents. -/
structure Typed where
  name : String
  p    : Fw.Obs.Next.Params := {}
  now  : Nat := t0
  fs   : List AgentFacts

/-- The typed cases. -/
def typed : List Typed := [
  { name := "case 1 port-nav: handed back, branch 3 ahead and unlanded, on the integrator's list -> routeIntegrator"
    fs := [{ ex "port-nav" .done with
      handbackAt := some (ago 90), branch := some { name := "wt-port-nav", ahead := 3, landed := false, queued := true }, worktree := some {} }] },
  { name := "case 1b port-nav not on the integrator's list -> land with its task"
    fs := [{ ex "port-nav" .done with
      handbackAt := some (ago 90), branch := some { name := "wt-port-nav", ahead := 3, landed := false, queued := false }, worktree := some {} }] },
  { name := "case 1c port-nav with a live build child: no land; held by a child that gets no kill"
    fs := [{ ex "port-nav" .done with
      handbackAt := some (ago 90), branch := some { name := "wt-port-nav", ahead := 3, landed := false, queued := false }, worktree := some {},
      children := [ch 810 .build (ago 5)] }] },
  { name := "case 2 ghb-runner: handed back and landed, an until-grep sleep loop under the session on a stale log -> killOrphan (cleanup waits for no live child)"
    fs := [{ ex "ghb-runner" .done with
      handbackAt := some (ago 25), branch := some { name := "wt-ghb-runner", ahead := 0, landed := true, queued := false }, worktree := some {},
      children := [lp 555 (ago 22) (some (ago 20))] }] },
  { name := "case 2b ghb-runner after the kill: landed, no live child -> cleanupWorktree"
    fs := [{ ex "ghb-runner" .done with
      handbackAt := some (ago 25), branch := some { name := "wt-ghb-runner", ahead := 0, landed := true, queued := false }, worktree := some {} }] },
  { name := "case 2c a sleep loop outside the session's tree is never killed: investigate heldByChild and foreignLoop"
    fs := [{ ex "ghb-runner" .done with
      handbackAt := some (ago 25), branch := some { name := "wt-ghb-runner", ahead := 0, landed := true, queued := false }, worktree := some {},
      children := [{ lp 556 (ago 22) (some (ago 20)) with chain := [1] }] }] },
  { name := "case 3 wktr-ci-lane: idle, until-grep loop for 2h54m on a file others keep rewriting (fresh) -> killOrphan by the loop cap"
    fs := [{ ex "wktr-ci-lane" .idle with children := [lp 900 (ago 174) (some (ago 1))] }] },
  { name := "case 3b loop cap edge: a loop exactly loopCapMin (30 min) old is kept"
    fs := [{ ex "wktr-ci-lane" .idle with children := [lp 901 (ago 30) (some (ago 1))] }] },
  { name := "case 3c loop cap edge: 1 ms past loopCapMin -> killOrphan"
    fs := [{ ex "wktr-ci-lane" .idle with children := [lp 902 (ago 30 - 1) (some (ago 1))] }] },
  { name := "case 4 port-platform: idle in waitrun.sh (timeout 10 min) on its running CI run -> waitCi"
    fs := [{ ex "port-platform" .idle with
      children := [ch 600 (.ciWait 42 10) (ago 4)], ci := some (ciRun 42 "port-platform") }] },
  { name := "case 4b port-platform active while its CI run runs -> waitCi"
    fs := [{ ex "port-platform" .active with
      children := [ch 600 (.ciWait 42 10) (ago 4)], ci := some (ciRun 42 "port-platform") }] },
  { name := "case 4c a CI wait past its own timeout (11 min > 10) -> waitCi and investigate ciWaitOverdue; never killed"
    fs := [{ ex "port-platform" .idle with
      children := [ch 601 (.ciWait 42 10) (ago 11)], ci := some (ciRun 42 "port-platform") }] },
  { name := "case 5 integrate-ports: active, context 260000 > ctxWarn, an old loop on a fresh file -> nudgeHandoff only (never killed)"
    fs := [{ ex "integrate-ports" .active with ctxTokens := 260000, children := [lp 700 (ago 99) (some (ago 1))] }] },
  { name := "case 5b context exactly ctxWarn (200000) -> none"
    fs := [{ ex "integrate-ports" .active with ctxTokens := 200000 }] },
  { name := "case 6 integrate-ports at 03:15: active, an until-grep loop on a background task's output whose producer exited -> killOrphan and nudgeHandoff"
    fs := [{ ex "integrate-ports" .active with children := [lp 701 (ago 35) (some (ago 3)) true] }] },
  { name := "case 6b active, producerExited without a watched file: not a dead watch -> none"
    fs := [{ ex "integrate-ports" .active with children := [lp 702 (ago 35) none true] }] },
  { name := "case 6c active, a loop on a file unchanged for 11 min (> fileStaleMin) -> killOrphan and nudgeHandoff"
    fs := [{ ex "integrate-ports" .active with children := [lp 703 (ago 12) (some (ago 11))] }] },
  { name := "case 7 obs-next-lean at 03:05: live, its task reached the board after the spawn-time claim, unbound and not done -> claimTask"
    fs := [{ ex "obs-next-lean" .active with board := some { id := "obs-next-lean", done := false } }] },
  { name := "case 7b task already bound to an agent -> none"
    fs := [{ ex "obs-next-lean" .active with
      board := some { id := "obs-next-lean", done := false, agent := some "obs-next-lean" } }] },
  { name := "case 7c task done -> none"
    fs := [{ ex "obs-next-lean" .idle with board := some { id := "obs-next-lean", done := true } }] },
  { name := "case 7d agent gone: no claim; stuck without a child -> respawnFromHandoff"
    fs := [{ ex "obs-next-lean" .gone with board := some { id := "obs-next-lean", done := false }, handoff := true }] },
  { name := "case 10 explainer-rev6: long finished, gone, task done on the board, handoff exists -> none (no respawn)"
    fs := [{ ex "explainer-rev6" .gone with board := some { id := "explainer-rev6", done := true }, handoff := true }] },
  { name := "case 10b gone with no board row for its task -> none"
    fs := [{ ex "env-elan" .gone with handoff := true }] },
  { name := "case 10c gone, task open, no handoff note -> none"
    fs := [{ ex "lean-math" .gone with board := some { id := "lean-math", done := false } }] },
  { name := "case 7e board row of another task id -> none"
    fs := [{ ex "obs-next-lean" .idle with board := some { id := "other", done := false } }] },
  { name := "stalled, no handback, no child -> respawnFromHandoff"
    fs := [{ ex "s" .stalled with worktree := some {}, board := some { id := "s", done := false }, handoff := true }] },
  { name := "case 8 port-nav ended 2 h ago, branch 3 ahead and unlanded, on the integrator's list: retained (keep) -> routeIntegrator"
    fs := [{ ex "port-nav" .done with handbackAt := some (ago 120), branch := some { name := "wt-port-nav", ahead := 3, landed := false, queued := true }, worktree := some {} }] },
  { name := "case 8b port-nav ended 2 h ago, not queued, clean, no unlanded dependency -> land"
    fs := [{ ex "port-nav" .done with handbackAt := some (ago 120), branch := some { name := "wt-port-nav", ahead := 3, landed := false, queued := false }, worktree := some {} }] },
  { name := "case 9 variant-morph-panel-rest: handed back, branch contains the unlanded port-morph-panel branch -> waitDeps"
    fs := [{ ex "variant-morph-panel-rest" .done with handbackAt := some (ago 30), branch := some { name := "wt-variant-morph-panel-rest", ahead := 4, landed := false, queued := false, deps := ["wt-port-morph-panel"] }, worktree := some {} }] },
  { name := "case 9b clean but conflicting with main (merge-tree exits non-zero) -> investigate conflict"
    fs := [{ ex "variant-morph-panel-rest" .done with handbackAt := some (ago 30), branch := some { name := "wt-variant-morph-panel-rest", ahead := 4, landed := false, queued := false, mergesClean := false }, worktree := some {} }] },
  { name := "gone with a live build child -> investigate heldByChild (no respawn while it runs)"
    fs := [{ ex "g" .gone with children := [ch 820 .build (ago 40)] }] },
  { name := "done without handback, branch landed, no child -> cleanupWorktree"
    fs := [{ ex "d" .done with branch := some { name := "wt-d", ahead := 0, landed := true, queued := false }, worktree := some {} }] },
  { name := "idle with a dead worktree-lock pid -> investigate lockDead"
    fs := [{ ex "l" .idle with worktree := some { lockPid := some 4242, lockAlive := false } }] },
  { name := "idle with a live worktree-lock pid -> none"
    fs := [{ ex "l" .idle with worktree := some { lockPid := some 4242, lockAlive := true } }] },
  { name := "a loop pid shared with a build child is ambiguous: no kill"
    fs := [{ ex "a" .done with handbackAt := some (ago 5), children := [lp 950 (ago 60), ch 950 .build (ago 60)] }] },
  { name := "a loop whose pid is the session pid is not killed"
    fs := [{ ex "a" .done with handbackAt := some (ago 5), children := [lp 100 (ago 60)] }] },
  { name := "handed back, branch 0 ahead and unlanded -> none"
    fs := [{ ex "z" .done with handbackAt := some (ago 5), branch := some { name := "wt-z", ahead := 0, landed := false, queued := false } }] },
  { name := "handed back, no branch, worktree present -> none"
    fs := [{ ex "z" .done with handbackAt := some (ago 5), worktree := some {} }] },
  { name := "parked with context 210000 -> nudgeHandoff"
    fs := [{ ex "q" .parked with ctxTokens := 210000 }] },
  { name := "file-stale edge: watched file unchanged exactly fileStaleMin (10 min) -> none"
    fs := [{ ex "w" .idle with children := [lp 960 (ago 15) (some (ago 10))] }] },
  { name := "file-stale edge: 1 ms past fileStaleMin -> killOrphan"
    fs := [{ ex "w" .idle with children := [lp 961 (ago 15) (some (ago 10 - 1))] }] },
  { name := "params override: loopCapMin 5, a 6 min old loop -> killOrphan"
    p := { loopCapMin := 5 }
    fs := [{ ex "o" .idle with children := [lp 970 (ago 6) (some (ago 1))] }] },
  { name := "three agents: replies in input order, each decided alone"
    fs := [{ ex "x1" .stalled with ctxTokens := 0 }, ex "x2" .idle,
      { ex "x3" .active with board := some { id := "x3", done := false } }] }]

/-- A literal request (an unparsable literal becomes an object that names it, so the case fails visibly). -/
def lit (s : String) : Json := (Json.parse s).toOption.getD (Json.mkObj [("unparsable", .str s)])

/-- Literal cases: optional fields, nulls, and refused requests. -/
def literal : List (String × Json) := [
  ("minimal: only now", lit "{\"now\":0}"),
  ("nulls count as absent: handbackAt, branch, worktree, ci, board, watchedAt",
   lit "{\"now\":1760000000000,\"agents\":[{\"id\":\"n\",\"task\":\"n\",\"state\":\"idle\",\"session\":1,\"handbackAt\":null,\"branch\":null,\"worktree\":null,\"ci\":null,\"board\":null,\"children\":[{\"pid\":2,\"chain\":[1],\"kind\":\"build\",\"startedAt\":0,\"watchedAt\":null}]}]}"),
  ("refused: unknown state", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"busy\",\"session\":1}]}"),
  ("refused: unknown child kind", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":2,\"kind\":\"robot\",\"startedAt\":0}]}]}"),
  ("refused: ciWait without run", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":2,\"kind\":\"ciWait\",\"timeoutMin\":10,\"startedAt\":0}]}]}"),
  ("refused: negative pid", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":-2,\"kind\":\"build\",\"startedAt\":0}]}]}"),
  ("refused: board row without done", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"board\":{\"id\":\"a\"}}]}"),
  ("refused: agent without session", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\"}]}"),
  ("params: loopCapMin and a Health field given, the rest default",
   lit "{\"now\":1760000000000,\"params\":{\"loopCapMin\":1,\"ctxWarn\":10},\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"ctxTokens\":11,\"children\":[{\"pid\":2,\"chain\":[1],\"kind\":\"sleepLoop\",\"startedAt\":1759999000000}]}]}")]

/-- Every case as (name, request body). -/
def cases : List (String × Json) := typed.map (fun c => (c.name, nextReqJson c.p c.now c.fs)) ++ literal

/-- The request with its `op` field. -/
def withOp (j : Json) : Json :=
  match j with
  | .obj kvs => .obj (kvs.insert "op" (.str "obs.next"))
  | j => j

/-- The reply to a request (without id): the reply fields, or `{error}`. -/
def respond (req : Json) : Json :=
  match opNext req with
  | .ok f => Json.mkObj f
  | .error e => Json.mkObj [("error", .str e)]

/-- An action's tag (its constructor, with the reason for `investigate`). -/
def tag : Action → String
  | .none => "none" | .waitCi _ => "waitCi" | .land .. => "land" | .routeIntegrator _ => "routeIntegrator"
  | .killOrphan _ => "killOrphan" | .cleanupWorktree => "cleanupWorktree"
  | .respawnFromHandoff => "respawnFromHandoff" | .nudgeHandoff => "nudgeHandoff"
  | .investigate r => s!"investigate {reasonName r}" | .claimTask .. => "claimTask"
  | .waitDeps _ => "waitDeps"

/-- Coverage gaps of the typed cases: action tags no case produces (empty when complete). -/
def gaps : List String :=
  let got := typed.flatMap fun c => c.fs.flatMap fun f => (Fw.Obs.Next.next c.p c.now f).map tag
  (["none", "waitCi", "land", "routeIntegrator", "killOrphan", "cleanupWorktree", "respawnFromHandoff",
    "nudgeHandoff", "claimTask", "investigate heldByChild", "investigate ciWaitOverdue", "investigate foreignLoop",
    "investigate lockDead", "investigate conflict", "waitDeps"].filter (!got.contains ·))

#guard gaps == []
#guard (typed.map (·.name)).eraseDups.length == typed.length

/-- The text of the golden file. -/
def fileText : String :=
  String.join (cases.map fun (name, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp req), ("response", respond req)]).compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def path : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "next.jsonl"

/-- Compare (or write) the golden file; returns the number of failures (stale file or coverage gaps). -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / path
  let mut bad := 0
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "obs")
    IO.FS.writeFile p fileText
  else
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != fileText then
      IO.println s!"obs.next golden: {p} is stale (regenerate with Fw.Wire.Obs.NextGolden.run \".\" true)"
      bad := bad + 1
  for g in gaps do
    IO.println s!"obs.next golden: no case covers {g}"
    bad := bad + 1
  IO.println s!"obs.next golden: {cases.length} cases, {if write then "written" else s!"{bad} failures"}"
  return bad

end NextGolden

end Fw.Wire.Obs
