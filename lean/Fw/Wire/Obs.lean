import Lean.Data.Json
import Std.Data.TreeMap.Raw.Lemmas
import Fw.Obs.Backoff
import Fw.Obs.Health
import Fw.Obs.Next
import Fw.Obs.Push
import Fw.Obs.Timing
import Fw.Sup.Adapt
import Fw.Ops.Wire
import Fw.Wire.SchedJson
/-!
# JSON codecs and the op `obs.health` (team health of one observation snapshot)

Glue between `fwcore`'s JSON lines and `Fw.Obs.Health` (namespace `Fw.Wire.Obs`, so the math view treats it as
wire code). Total decoders only (`Except String`); no partial operations. Times are integer ms since the epoch; every
number is a non-negative integer (a fraction is refused, so the caller floors `diskFreeGB`).

| op | request | reply |
|---|---|---|
| `obs.health` | `now`, `params`?, `agents`? [Agent], `lead`? Lead, `system` System (`gh`? {actions, pages, webhooks (githubstatus state names), prevDegraded, incidents [{name, status, impact, createdAt, updatedAt, body, actions}], ciAgeMs? (age in ms of the run list in `ci`; 0 = read this pass; above `Fw.Obs.ciFreshMs` ci.slow details end with the age)}), `prevAt`?, `critical`? [string] | `agents` [{id, state, alerts:[code]}] (input order), `system` {alerts:[code]} (code order), `counts` {active, idle, parked, stalled, gone, done}, `alerts` [{code, subject, detail, critical}] (critical first, then by code, subject, detail; no duplicates) |
| `obs.next` | `now`, `params`?, `agents`? [AgentFacts] | `agents` [{id, actions:[{action, …args}]}] (input order; `Fw.Obs.Next.next`) |

Shapes. Params (every field optional, defaults in brackets): `{idleMin [10], stallMin [20], toolHangMin [30]` (minutes),
`errStreak [3], ctxResumeMax [250000], ctxWarn [200000], diskMinGB [20], agentCap [10], simLockMaxMin [30]` (minutes),
`worktreesMax [20], wfQuietMin [30], goneAfterMin [120], ciSlowMin [20], toolSlowMin [15], procMaxMin [20], ciSlowBy [[{workflow: "breakpoint-gate", min: 40}]]`
(minutes), `loadMax [150]}`. Agent: `{id, name?, task?, kind? ["lead"|"teammate"|"subagent"|"workflow";
"subagent"], parent?, startedAt, lastAt, stoppedAt?, errTail? [0], inflight? {tool, since}, lastTool?, lastToolAt?,
idleAt?, workflowDone? [false], transcriptOnly? [false], ctxTokens?}` (any other field, e.g. `type`, `model`, `tools`,
`errors`, `tokens`, `inflight.verb`, is ignored). Lead: `{lastToolAt?, noteAt?}` (absent: no events). System:
`{diskFreeGB, memPressure? ["normal"|"warn"|"critical"], simLock? {holder?, since?}, docker? [{id, name, startedAt}],
worktrees? [0] (a count), ci? [{workflow, branch, status, conclusion?, startedAt, endedAt?, headSha? [""]}], loadFloor? [0] (the floor
of the 1-min load average; above `Fw.Obs.Timing.contendedLoad` it raises sys.contended), load? {builders? [0], heavyJobs? [0], prevContended? [false]} (the local check.sh/lake builders and heavy jobs that run, in the sys.contended detail, and whether the previous check raised it: the hysteresis bit), feedback? [{kind: "post"|"reply", flag, ref (the comment id, or the one answered), text, ts}] (the accepted review.feedback events of the log, oldest first: an open comment raises review.feedback), procs? [{pid, name, startedAt, pids? [[]], agent?}] (`agent`: the
id of the agent whose Bash call started the tree), services? [[]] (pids), keep? [[]] (pids the lead declared), svcs? [{name, inputs? [{path, changed? false}], unknown? (why the code that runs cannot be identified: raises svc.unknown), sweepErrors? 0 (fwcore throws its drain caught since start: raises svc.sweepError)}] (services and, for each input group, whether
`main` changed it since the service's base commit)}` (any other field,
e.g. `load1`, `consolePids`, `stale`, is ignored). `prevAt` is the time of the previous check (absent: first check);
`critical` lists the task ids on the critical path. `null` counts as absent.

`obs.next` shapes. Params: the Health params plus `loopCapMin [30], fileStaleMin [10]` (minutes). AgentFacts:
`{id, task, state ["active"|"idle"|"parked"|"stalled"|"gone"|"done"], session, handbackAt?, branch? {name, ahead,
landed, queued? [false], mergesClean? [true], deps? [[]]}, handoff? [false], worktree? {lockPid?, lockAlive? [false]}, ctxTokens? [0], children? [{pid, chain? [[]],
kind ["sleepLoop"|"ciWait"|"build"|"other"|"stdinWait"], run and timeoutMin (ciWait only), startedAt, watchedAt?,
producerExited? [false], watch? {kind ["task"|"agent"], id}}], ci? {id, workflow, branch, status, conclusion?,
startedAt, endedAt?}, board? {id, done, agent?}, signals? SigFacts}`. Action: `{action}` plus `run` (waitCi), `branch`,
`task` (land), `branch` (routeIntegrator), `pid` (killOrphan), `reason`
["heldByChild"|"ciWaitOverdue"|"foreignLoop"|"lockDead"|"conflict"] (investigate), `task`, `agent` (claimTask), `dep`
(waitDeps). The reply runs `next` on the facts resolved against all agents (`Fw.Obs.Next.resolve`); an agent with
`signals` also gets `signal {state, ids}`, `handbackAt` and `keep`. Golden vectors in
`packages/contracts/golden/obs/next.jsonl` (`Fw.Wire.Obs.NextGolden`, this file).

`obs.signals` shapes. Request: `{now, params? (the obs.next params; hung after loopCapMin minutes), agents? [SigFacts]}`.
SigFacts: `{agent, launched? [{id, time}], ends? [{id, time, how? ["notified"|"killed"|"exited"] ["notified"], code
(exited only, an integer)}], bounds? [{time, start}], handbacks? [[]], notices? [{time, finished}], procs? [{id, pid,
kind ["stdin"|"sleepLoop"|"other"]}], metaFinished? [[]] (recorded, never read)}` (lists default to empty). Reply:
per agent `{agent, state ["working"|"waitingOwnBg"|"handedBackHeld"|"handedBackDone"|"finished"|"idle"|"hung"], ids,
handbackAt}`. Golden vectors in `packages/contracts/golden/obs/signals.jsonl` (`Fw.Wire.Obs.SignalsGolden`, this
file): the 8 real timelines of `Fw.Obs.Signals.golden`, seconds there, milliseconds on the wire.

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
open Fw.Obs (Svc SvcInput)

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

/-- A per-workflow `ci.slow` limit as JSON: `{workflow, min}`. -/
def slowByJson (e : String × Nat) : Json := Json.mkObj [("workflow", .str e.1), ("min", toJson e.2)]

/-- Decode a per-workflow `ci.slow` limit. -/
def slowByOf (j : Json) : Except String (String × Nat) := do
  pure (← Fw.Wire.Ops.str j "workflow", ← nat j "min")

/-- Per-workflow limits round-trip. -/
theorem slowByOf_slowByJson (e : String × Nat) : slowByOf (slowByJson e) = .ok e := by
  obtain ⟨w, m⟩ := e
  rfl

/-- The thresholds' JSON fields (every field written). -/
def paramsFields (p : Params) : List (String × Json) :=
  [("idleMin", toJson p.idleMin), ("stallMin", toJson p.stallMin), ("toolHangMin", toJson p.toolHangMin),
    ("errStreak", toJson p.errStreak), ("ctxResumeMax", toJson p.ctxResumeMax), ("ctxWarn", toJson p.ctxWarn),
    ("diskMinGB", toJson p.diskMinGB), ("agentCap", toJson p.agentCap), ("simLockMaxMin", toJson p.simLockMaxMin),
    ("worktreesMax", toJson p.worktreesMax), ("wfQuietMin", toJson p.wfQuietMin),
    ("goneAfterMin", toJson p.goneAfterMin), ("ciSlowMin", toJson p.ciSlowMin), ("toolSlowMin", toJson p.toolSlowMin),
    ("procMaxMin", toJson p.procMaxMin), ("loadMax", toJson p.loadMax),
    ("ciSlowBy", .arr (p.ciSlowBy.toArray.map slowByJson))]

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
         loadMax := ← natD j "loadMax" d.loadMax,
         ciSlowBy := ← (match opt j "ciSlowBy" with
           | none => pure d.ciSlowBy
           | some _ => do (← arrD j "ciSlowBy").mapM slowByOf) }

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
    ("workflowDone", .bool a.workflowDone), ("transcriptOnly", .bool a.transcriptOnly), ("ctxTokens", onat a.ctxTokens),
    ("sessionPid", onat a.sessionPid)]

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
         ctxTokens := ← optN j "ctxTokens", sessionPid := ← optN j "sessionPid" }

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
    ("conclusion", ostr r.conclusion), ("startedAt", toJson r.startedAt), ("endedAt", onat r.endedAt),
    ("headSha", .str r.headSha)]

/-- Decode a CI run (`conclusion` and `endedAt` optional). -/
def ciOf (j : Json) : Except String CiRun := do
  pure { workflow := ← str j "workflow", branch := ← str j "branch", status := ← str j "status",
         conclusion := ← optS j "conclusion", startedAt := ← nat j "startedAt", endedAt := ← optN j "endedAt",
         headSha := ← Fw.Wire.Ops.strD j "headSha" "" }

def unknownStart : Nat := 2 ^ 64

def startOf (j : Json) (k : String) : Except String Nat := do
  let v ← field j k
  match v.getNat? with
  | .ok n => .ok n
  | .error _ =>
    match v.getInt? with
    | .ok i => if i < 0 then .ok unknownStart else asNat k v
    | .error _ => asNat k v

def procJson (q : Proc) : Json :=
  Json.mkObj [("pid", toJson q.pid), ("name", .str q.name), ("startedAt", toJson q.startedAt),
    ("pids", .arr (q.pids.toArray.map toJson)), ("agent", ostr q.agent)]

def procOf (j : Json) : Except String Proc := do
  pure { pid := ← nat j "pid", name := ← str j "name", startedAt := ← startOf j "startedAt",
         pids := ← (← arrD j "pids").mapM (asNat "pids"), agent := ← optS j "agent" }

/-- A feedback event as JSON: `kind` `post` (`ref` the comment id) or `reply` (`ref` the comment answered). -/
def fbEvJson : Fw.Console.ReviewFeedback.Ev → Json
  | .post flag id text ts => Json.mkObj [("kind", .str "post"), ("flag", .str flag), ("ref", .str id), ("text", .str text), ("ts", toJson ts)]
  | .reply flag to text ts => Json.mkObj [("kind", .str "reply"), ("flag", .str flag), ("ref", .str to), ("text", .str text), ("ts", toJson ts)]

/-- Decode a feedback event; a `kind` other than `post` and `reply` is an error. -/
def fbEvOf (j : Json) : Except String Fw.Console.ReviewFeedback.Ev := do
  let k ← str j "kind"
  if k = "post" then pure (.post (← str j "flag") (← str j "ref") (← str j "text") (← nat j "ts"))
  else if k = "reply" then pure (.reply (← str j "flag") (← str j "ref") (← str j "text") (← nat j "ts"))
  else throw s!"kind: unknown feedback event {k}"

/-- A service input group as JSON. -/
def svcInputJson (i : SvcInput) : Json := Json.mkObj [("path", .str i.path), ("changed", .bool i.changed)]

/-- Decode a service input group. -/
def svcInputOf (j : Json) : Except String SvcInput := do
  pure { path := ← str j "path", changed := ← boolD j "changed" false }

/-- A service as JSON. -/
def svcJson (v : Svc) : Json :=
  Json.mkObj [("name", .str v.name),
    ("inputs", .arr (v.inputs.toArray.map svcInputJson)), ("unknown", ostr v.unknown),
    ("sweepErrors", toJson v.sweepErrors)]

/-- Decode a service (`inputs` optional, default empty; `sweepErrors` optional, default 0). -/
def svcOf (j : Json) : Except String Svc := do
  pure { name := ← str j "name", inputs := ← (← arrD j "inputs").mapM svcInputOf,
         unknown := ← optS j "unknown", sweepErrors := ← natD j "sweepErrors" 0 }

/-- A GitHub incident as JSON. -/
def ghIncidentJson (i : Fw.Obs.GhIncident) : Json :=
  Json.mkObj [("name", .str i.name), ("status", .str i.status), ("impact", .str i.impact),
    ("createdAt", toJson i.createdAt), ("updatedAt", toJson i.updatedAt), ("body", .str i.body),
    ("actions", .bool i.actions)]

/-- Decode a GitHub incident (every field but `name` optional). -/
def ghIncidentOf (j : Json) : Except String Fw.Obs.GhIncident := do
  pure { name := ← str j "name", status := ← Fw.Wire.Ops.strD j "status" "", impact := ← Fw.Wire.Ops.strD j "impact" "",
         createdAt := ← natD j "createdAt" 0, updatedAt := ← natD j "updatedAt" 0,
         body := ← Fw.Wire.Ops.strD j "body" "", actions := ← boolD j "actions" false }

/-- The GitHub reading as JSON. -/
def ghJson (g : Fw.Obs.Gh) : Json :=
  Json.mkObj [("actions", .str g.actions.name), ("pages", .str g.pages.name), ("webhooks", .str g.webhooks.name),
    ("prevDegraded", .bool g.prevDegraded), ("incidents", .arr (g.incidents.toArray.map ghIncidentJson)),
    ("ciAgeMs", toJson g.ciAgeMs)]

/-- Decode the GitHub reading (every field optional; an unreadable state is `unknown`). -/
def ghOf (j : Json) : Except String Fw.Obs.Gh := do
  pure { actions := .ofName (← Fw.Wire.Ops.strD j "actions" "unknown"), pages := .ofName (← Fw.Wire.Ops.strD j "pages" "unknown"),
         webhooks := .ofName (← Fw.Wire.Ops.strD j "webhooks" "unknown"), prevDegraded := ← boolD j "prevDegraded" false,
         incidents := ← (← arrD j "incidents").mapM ghIncidentOf, ciAgeMs := ← natD j "ciAgeMs" 0 }

/-- The load facts as JSON (every field written). -/
def loadJson (l : Fw.Obs.Health.LoadInfo) : Json :=
  Json.mkObj [("builders", toJson l.builders), ("heavyJobs", toJson l.heavyJobs), ("prevContended", .bool l.prevContended)]

/-- Decode the load facts (every field optional). -/
def loadOf (j : Json) : Except String Fw.Obs.Health.LoadInfo := do
  pure { builders := ← natD j "builders" 0, heavyJobs := ← natD j "heavyJobs" 0, prevContended := ← boolD j "prevContended" false }

/-- The load facts round-trip. -/
theorem loadOf_loadJson (l : Fw.Obs.Health.LoadInfo) : loadOf (loadJson l) = .ok l := by
  obtain ⟨b, h, p⟩ := l
  rfl

/-- The system facts' JSON fields (every field written). -/
def systemFields (s : System) : List (String × Json) :=
  [("diskFreeGB", toJson s.diskFreeGB), ("memPressure", .str (memName s.memPressure)),
    ("simLock", simLockJson s.simLock), ("docker", .arr (s.docker.toArray.map containerJson)),
    ("worktrees", toJson s.worktrees), ("ci", .arr (s.ci.toArray.map ciJson)), ("loadFloor", toJson s.loadFloor),
    ("procs", .arr (s.procs.toArray.map procJson)), ("services", .arr (s.services.toArray.map toJson)),
    ("keep", .arr (s.keep.toArray.map toJson)), ("svcs", .arr (s.svcs.toArray.map svcJson)),
    ("alivePids", match s.alivePids with | some l => .arr (l.toArray.map toJson) | none => .null),
    ("gh", ghJson s.gh), ("load", loadJson s.load), ("feedback", .arr (s.feedback.toArray.map fbEvJson))]

/-- The system facts as JSON (every field written). -/
def systemJson (s : System) : Json := Json.mkObj (systemFields s)

/-- The optional listed pids (absent or `null`: the process table was not read). -/
def alivePidsOf (j : Json) : Except String (Option (List Nat)) :=
  match opt j "alivePids" with
  | none => pure none
  | some _ => do pure (some (← (← arrD j "alivePids").mapM (asNat "alivePids")))

/-- Decode the system facts; `diskFreeGB` is required. -/
def systemOf (j : Json) : Except String System := do
  let mem ← match opt j "memPressure" with
    | none => pure .normal
    | some v => memOf (← asStr "memPressure" v)
  let lock ← match opt j "simLock" with
    | none => pure {}
    | some v => simLockOf v
  let gh ← match opt j "gh" with
    | none => pure {}
    | some v => ghOf v
  let load ← match opt j "load" with
    | none => pure {}
    | some v => loadOf v
  pure { diskFreeGB := ← nat j "diskFreeGB", memPressure := mem, simLock := lock, gh,
         docker := ← (← arrD j "docker").mapM containerOf, worktrees := ← natD j "worktrees" 0,
         ci := ← (← arrD j "ci").mapM ciOf, loadFloor := ← natD j "loadFloor" 0,
         procs := ← (← arrD j "procs").mapM procOf, services := ← (← arrD j "services").mapM (asNat "services"),
         keep := ← (← arrD j "keep").mapM (asNat "keep"), svcs := ← (← arrD j "svcs").mapM svcOf,
         alivePids := ← alivePidsOf j, load, feedback := ← (← arrD j "feedback").mapM fbEvOf }

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

No two threshold fields share a key.
-/
theorem paramsFields_keys (p : Params) : ((paramsFields p).map Prod.fst).Pairwise (· ≠ ·) := by
  simp only [paramsFields, List.map_cons, List.map_nil]
  decide +kernel

/-- Thresholds round-trip.

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
    g "loadMax" _ (by unfold paramsFields; mem_lit), g "ciSlowBy" _ (by unfold paramsFields; mem_lit),
    arrD_arr (paramsJson p) "ciSlowBy" _ (g "ciSlowBy" _ (by unfold paramsFields; mem_lit)), Array.toList_map,
    ok_bind, mapM_rt slowByJson slowByOf slowByOf_slowByJson]
  rfl

/-- An agent's keys are pairwise distinct.

No two agent fields share a key.
-/
theorem agentFields_keys (a : Agent) : ((agentFields a).map Prod.fst).Pairwise (· ≠ ·) := by
  simp only [agentFields, List.map_cons, List.map_nil]
  decide +kernel

/-- Agents round-trip.

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
  have hsp : optN (agentJson a) "sessionPid" = .ok a.sessionPid := by
    unfold optN opt; rw [g "sessionPid" _ (by unfold agentFields; mem_lit)]; cases a.sessionPid <;> rfl
  simp only [agentOf, hid, hn, ht, hk, hp, hst, hl, hs, he, hi, hlt, hla, hia, hw, hr, hc, hsp, ok_bind]
  rfl

/-- The lead session's facts round-trip.

Decoding the JSON written for the lead's facts gives the same facts back.
-/
theorem leadOf_leadJson (l : Lead) : leadOf (leadJson l) = .ok l := by
  obtain ⟨t, n⟩ := l
  cases t <;> cases n <;> rfl

/-- Feedback events round-trip. -/
theorem fbEvOf_fbEvJson (e : Fw.Console.ReviewFeedback.Ev) : fbEvOf (fbEvJson e) = .ok e := by
  cases e <;> rfl

/-- Containers round-trip. -/
theorem containerOf_containerJson (c : Container) : containerOf (containerJson c) = .ok c := by
  cases c; rfl

/-- CI runs round-trip. -/
theorem ciOf_ciJson (r : CiRun) : ciOf (ciJson r) = .ok r := by
  obtain ⟨w, b, s, c, t, e, h⟩ := r
  cases c <;> cases e <;> rfl

/-- Process trees round-trip.

Decoding the JSON written for a process tree gives the same tree back.
-/
theorem procOf_procJson (q : Proc) : procOf (procJson q) = .ok q := by
  obtain ⟨pid, name, st, pids, ag⟩ := q
  have hp := arrD_arr (procJson ⟨pid, name, st, pids, ag⟩) "pids" _ rfl
  have ha : optS (procJson ⟨pid, name, st, pids, ag⟩) "agent" = .ok ag := by cases ag <;> rfl
  simp only [procOf, hp, ha, Array.toList_map, ok_bind, mapM_rt toJson (asNat "pids") (fun _ => rfl)]
  rfl

/-- Service input groups round-trip. -/
theorem svcInputOf_svcInputJson (i : SvcInput) : svcInputOf (svcInputJson i) = .ok i := by
  cases i; rfl

/-- Services round-trip. -/
theorem svcOf_svcJson (v : Svc) : svcOf (svcJson v) = .ok v := by
  obtain ⟨name, ins, un, se⟩ := v
  have hi := arrD_arr (svcJson ⟨name, ins, un, se⟩) "inputs" _ rfl
  have hu : optS (svcJson ⟨name, ins, un, se⟩) "unknown" = .ok un := by cases un <;> rfl
  have he : natD (svcJson ⟨name, ins, un, se⟩) "sweepErrors" 0 = .ok se := by cases un <;> rfl
  simp only [svcOf, hi, hu, he, Array.toList_map, ok_bind, mapM_rt svcInputJson svcInputOf svcInputOf_svcInputJson]
  rfl

/-- GitHub incidents round-trip. -/
theorem ghIncidentOf_ghIncidentJson (i : Fw.Obs.GhIncident) : ghIncidentOf (ghIncidentJson i) = .ok i := by
  cases i; rfl

/-- The GitHub reading round-trips. -/
theorem ghOf_ghJson (g : Fw.Obs.Gh) : ghOf (ghJson g) = .ok g := by
  obtain ⟨a, pg, w, pv, inc, ca⟩ := g
  have hi := arrD_arr (ghJson ⟨a, pg, w, pv, inc, ca⟩) "incidents" _ rfl
  have hc : natD (ghJson ⟨a, pg, w, pv, inc, ca⟩) "ciAgeMs" 0 = .ok ca := rfl
  have ha : Fw.Wire.Ops.strD (ghJson ⟨a, pg, w, pv, inc, ca⟩) "actions" "unknown" = .ok a.name := rfl
  have hp : Fw.Wire.Ops.strD (ghJson ⟨a, pg, w, pv, inc, ca⟩) "pages" "unknown" = .ok pg.name := rfl
  have hw : Fw.Wire.Ops.strD (ghJson ⟨a, pg, w, pv, inc, ca⟩) "webhooks" "unknown" = .ok w.name := rfl
  have hv : boolD (ghJson ⟨a, pg, w, pv, inc, ca⟩) "prevDegraded" false = .ok pv := rfl
  simp only [ghOf, ha, hp, hw, hv, hc, hi, Array.toList_map, ok_bind, Fw.Obs.GhComp.ofName_name,
    mapM_rt ghIncidentJson ghIncidentOf ghIncidentOf_ghIncidentJson]
  rfl

/-- The system facts' keys are pairwise distinct. -/
theorem systemFields_keys (s : System) : ((systemFields s).map Prod.fst).Pairwise (· ≠ ·) := by
  simp only [systemFields, List.map_cons, List.map_nil]
  decide +kernel

private theorem systemJson_get {s : System} {k : String} {v : Json} (hm : (k, v) ∈ systemFields s) :
    (systemJson s).getObjVal? k = .ok v :=
  getObjVal_mkObj (systemFields_keys s) hm

private theorem systemJson_arrD {s : System} {k : String} {α : Type} {l : List α} {f : α → Json}
    (hm : (k, .arr (l.toArray.map f)) ∈ systemFields s) : arrD (systemJson s) k = .ok (l.map f) := by
  rw [arrD_arr _ _ _ (systemJson_get hm), Array.toList_map]

private theorem systemOf_diskFreeGB (s : System) : nat (systemJson s) "diskFreeGB" = .ok s.diskFreeGB := by
  unfold nat field; rw [systemJson_get (by unfold systemFields; mem_lit)]; rfl

private theorem systemOf_worktrees (s : System) : natD (systemJson s) "worktrees" 0 = .ok s.worktrees := by
  unfold natD opt; rw [systemJson_get (by unfold systemFields; mem_lit)]; rfl

private theorem systemOf_loadFloor (s : System) : natD (systemJson s) "loadFloor" 0 = .ok s.loadFloor := by
  unfold natD opt; rw [systemJson_get (by unfold systemFields; mem_lit)]; rfl

private theorem systemOf_memPressure (s : System) :
    opt (systemJson s) "memPressure" = some (.str (memName s.memPressure)) := by
  unfold opt; rw [systemJson_get (by unfold systemFields; mem_lit)]

private theorem systemOf_simLock (s : System) : opt (systemJson s) "simLock" = some (simLockJson s.simLock) := by
  unfold opt; rw [systemJson_get (by unfold systemFields; mem_lit)]; rfl

private theorem systemOf_gh (s : System) : opt (systemJson s) "gh" = some (ghJson s.gh) := by
  unfold opt; rw [systemJson_get (by unfold systemFields; mem_lit)]; rfl

private theorem systemOf_load (s : System) : opt (systemJson s) "load" = some (loadJson s.load) := by
  unfold opt; rw [systemJson_get (by unfold systemFields; mem_lit)]; rfl

private theorem systemOf_docker (s : System) : arrD (systemJson s) "docker" = .ok (s.docker.map containerJson) :=
  systemJson_arrD (by unfold systemFields; mem_lit)

private theorem systemOf_ci (s : System) : arrD (systemJson s) "ci" = .ok (s.ci.map ciJson) :=
  systemJson_arrD (by unfold systemFields; mem_lit)

private theorem systemOf_procs (s : System) : arrD (systemJson s) "procs" = .ok (s.procs.map procJson) :=
  systemJson_arrD (by unfold systemFields; mem_lit)

private theorem systemOf_services (s : System) : arrD (systemJson s) "services" = .ok (s.services.map toJson) :=
  systemJson_arrD (by unfold systemFields; mem_lit)

private theorem systemOf_keep (s : System) : arrD (systemJson s) "keep" = .ok (s.keep.map toJson) :=
  systemJson_arrD (by unfold systemFields; mem_lit)

private theorem systemOf_svcs (s : System) : arrD (systemJson s) "svcs" = .ok (s.svcs.map svcJson) :=
  systemJson_arrD (by unfold systemFields; mem_lit)

private theorem systemOf_feedback (s : System) : arrD (systemJson s) "feedback" = .ok (s.feedback.map fbEvJson) :=
  systemJson_arrD (by unfold systemFields; mem_lit)

private theorem systemOf_alivePids (s : System) : alivePidsOf (systemJson s) = .ok s.alivePids := by
  have h : (systemJson s).getObjVal? "alivePids" =
      .ok (match s.alivePids with | some l => .arr (l.toArray.map toJson) | none => .null) :=
    systemJson_get (by unfold systemFields; mem_lit)
  cases ha : s.alivePids with
  | none => rw [ha] at h; simp only [alivePidsOf, opt, h]; rfl
  | some l =>
    rw [ha] at h
    simp only [alivePidsOf, opt, h, arrD_arr _ _ _ h, Array.toList_map, ok_bind,
      mapM_rt toJson (asNat "alivePids") (fun _ => rfl)]
    rfl

private theorem memOf_memName (m : Mem) : memOf (memName m) = .ok m := by
  cases m <;> rfl

private theorem simLockOf_simLockJson (l : SimLock) : simLockOf (simLockJson l) = .ok l := by
  obtain ⟨h, t⟩ := l
  cases h <;> cases t <;> rfl

/-- System facts round-trip. -/
theorem systemOf_systemJson (s : System) : systemOf (systemJson s) = .ok s := by
  simp only [systemOf, systemOf_diskFreeGB, systemOf_worktrees, systemOf_loadFloor, systemOf_memPressure,
    systemOf_simLock, systemOf_gh, systemOf_load, systemOf_docker, systemOf_ci, systemOf_procs, systemOf_services,
    systemOf_keep, systemOf_svcs, systemOf_feedback, systemOf_alivePids, asStr, ok_bind, memOf_memName,
    simLockOf_simLockJson, ghOf_ghJson, loadOf_loadJson, mapM_rt containerJson containerOf containerOf_containerJson,
    mapM_rt ciJson ciOf ciOf_ciJson, mapM_rt procJson procOf procOf_procJson,
    mapM_rt toJson (asNat "services") (fun _ => rfl), mapM_rt toJson (asNat "keep") (fun _ => rfl),
    mapM_rt svcJson svcOf svcOf_svcJson, mapM_rt fbEvJson fbEvOf fbEvOf_fbEvJson]
  rfl

/-- Requests round-trip. -/
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
  pure (reportFields (health p (settle o)))

/-- The reply to an encoded request is the encoded report. -/
theorem opHealth_reqJson (p : Params) (o : Obs) :
    opHealth (reqJson p o) = .ok (reportFields (health p (settle o))) := by
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

/-- A watch as JSON: `{kind ["task"|"agent"], id}`. -/
def watchJson : Fw.Obs.Next.Watch → Json
  | .task b => Json.mkObj [("kind", .str "task"), ("id", .str b)]
  | .agent a => Json.mkObj [("kind", .str "agent"), ("id", .str a)]

/-- Decode a watch (an unknown kind is refused). -/
def watchOf (j : Json) : Except String Fw.Obs.Next.Watch := do
  match ← str j "kind" with
  | "task" => pure (.task (← str j "id"))
  | "agent" => pure (.agent (← str j "id"))
  | s => throw s!"field kind: unknown value {s}"

/-- A child process as JSON (`run` and `timeoutMin` only for a `ciWait`; `watch` only when known). -/
def childJson (c : Child) : Json :=
  let k : List (String × Json) := match c.kind with
    | .sleepLoop => [("kind", .str "sleepLoop")]
    | .ciWait r m => [("kind", .str "ciWait"), ("run", toJson r), ("timeoutMin", toJson m)]
    | .build => [("kind", .str "build")]
    | .other => [("kind", .str "other")]
    | .stdinWait => [("kind", .str "stdinWait")]
  Json.mkObj ([("pid", toJson c.pid), ("chain", natsJson c.chain)] ++ k ++
    [("startedAt", toJson c.startedAt), ("watchedAt", onat c.watchedAt), ("producerExited", .bool c.producerExited)] ++
    match c.watch with
    | some v => [("watch", watchJson v)]
    | none => [])

/-- A child kind (`ciWait` needs `run` and `timeoutMin`; an unknown kind is refused). -/
def childKindOf (j : Json) : Except String ChildKind := do
  match ← str j "kind" with
  | "sleepLoop" => pure .sleepLoop
  | "ciWait" => pure (.ciWait (← nat j "run") (← nat j "timeoutMin"))
  | "build" => pure .build
  | "other" => pure .other
  | "stdinWait" => pure .stdinWait
  | s => throw s!"field kind: unknown value {s}"

/-- Decode a child process (`chain` optional, default empty; `watchedAt` optional; `producerExited` default false;
`watch` optional). -/
def childOf (j : Json) : Except String Child := do
  pure { pid := ← nat j "pid", chain := ← (← arrD j "chain").mapM (asNat "chain"), kind := ← childKindOf j,
         startedAt := ← startOf j "startedAt", watchedAt := ← optN j "watchedAt",
         producerExited := ← boolD j "producerExited" false,
         watch := ← match opt j "watch" with
           | none => pure none
           | some v => some <$> watchOf v }

theorem startOf_nat (k : String) (n : Nat) : startOf (Json.mkObj [(k, toJson n)]) k = .ok n := by
  have g : (Json.mkObj [(k, toJson n)]).getObjVal? k = .ok (toJson n) :=
    getObjVal_mkObj (l := [(k, toJson n)]) (by simp) (by simp)
  unfold startOf field
  rw [g]
  rfl

theorem startOf_neg (k : String) (n : Nat) :
    startOf (Json.mkObj [(k, toJson (-(n + 1 : Int)))]) k = .ok unknownStart := by
  have g : (Json.mkObj [(k, toJson (-(n + 1 : Int)))]).getObjVal? k = .ok (toJson (-(n + 1 : Int))) :=
    getObjVal_mkObj (l := [(k, toJson (-(n + 1 : Int)))]) (by simp) (by simp)
  unfold startOf field
  rw [g]
  rw [← Int.negSucc_eq]
  have hn : Int.negSucc n < 0 := Int.negSucc_lt_zero n
  simp [Json.getNat?, Json.getInt?, toJson, JsonNumber.fromInt, hn, bind, Except.bind, pure, Except.pure]
  rfl

theorem unknownStart_age (now : Nat) (h : now < unknownStart) : now - unknownStart = 0 := by omega

theorem oldB_unknown (p : Fw.Obs.Next.Params) (now : Nat) (c : Fw.Obs.Next.Child) (h : now < unknownStart)
    (hs : c.startedAt = unknownStart) : Fw.Obs.Next.oldB p now c = false := by
  simp [Fw.Obs.Next.oldB, hs, unknownStart_age now h]

theorem overdueB_unknown (now : Nat) (c : Fw.Obs.Next.Child) (h : now < unknownStart)
    (hs : c.startedAt = unknownStart) : Fw.Obs.Next.overdueB now c = false := by
  unfold Fw.Obs.Next.overdueB
  split <;> simp [hs, unknownStart_age now h]

theorem procLongB_unknown (p : Params) (o : Obs) (q : Proc) (h : o.now < unknownStart)
    (hs : q.startedAt = unknownStart) : procLongB p o q = false := by
  simp [procLongB, hs, unknownStart_age o.now h]

def branchJson (b : Branch) : Json :=
  Json.mkObj [("name", .str b.name), ("ahead", toJson b.ahead), ("landed", .bool b.landed), ("queued", .bool b.queued),
    ("mergesClean", .bool b.mergesClean), ("deps", .arr (b.deps.toArray.map .str)),
    ("onMain", .bool b.onMain), ("landLock", ostr b.landLock), ("landQueued", .bool b.inLandQueue)]

/-- Decode a branch (`name`, `ahead`, `landed` required; `queued` default false). -/
def branchOf (j : Json) : Except String Branch := do
  pure { name := ← str j "name", ahead := ← nat j "ahead", landed := ← asBool "landed" (← field j "landed"),
         queued := ← boolD j "queued" false, mergesClean := ← boolD j "mergesClean" true,
         deps := ← (← arrD j "deps").mapM (fun v => match v with | .str x => pure x | _ => throw "deps: string expected"),
         onMain := ← boolD j "onMain" false, inLandQueue := ← boolD j "landQueued" false,
         landLock := ← match opt j "landLock" with
           | none => pure none
           | some v => some <$> asStr "landLock" v }

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

/-! ### Signals (`Fw.Obs.Signals`) -/

open Fw.Obs.Signals (How ProcKind) in
/-- An end's `how` as fields: `how` plus `code` for an exit. -/
def howFields : How → List (String × Json)
  | .notified => [("how", .str "notified")]
  | .killed => [("how", .str "killed")]
  | .exited c => [("how", .str "exited"), ("code", toJson c)]

open Fw.Obs.Signals (How) in
/-- Decode an end's `how` (absent: `notified`; `exited` needs an integer `code`; an unknown value is refused). -/
def howOf (j : Json) : Except String How :=
  match opt j "how" with
  | none => .ok .notified
  | some (.str "notified") => .ok .notified
  | some (.str "killed") => .ok .killed
  | some (.str "exited") => match j.getObjValAs? Int "code" with
    | .ok c => .ok (.exited c)
    | .error _ => .error "field code: expected an integer"
  | some v => .error s!"field how: unknown value {v.compress}"

open Fw.Obs.Signals (ProcKind) in
/-- A process kind's wire name. -/
def procKindName : ProcKind → String
  | .stdin => "stdin" | .sleepLoop => "sleepLoop" | .other => "other"

open Fw.Obs.Signals (ProcKind) in
/-- A process kind from its wire name (an unknown name is refused). -/
def procKindOf : String → Except String ProcKind
  | "stdin" => .ok .stdin | "sleepLoop" => .ok .sleepLoop | "other" => .ok .other
  | s => .error s!"field kind: unknown value {s}"

/-- An agent's signal facts as JSON (every list written). -/
def sigFactsJson (g : Fw.Obs.Signals.Facts) : Json :=
  Json.mkObj [("agent", .str g.agent),
    ("launched", .arr (g.launched.toArray.map fun l => Json.mkObj [("id", .str l.id), ("time", toJson l.time)])),
    ("ends", .arr (g.ends.toArray.map fun e =>
      Json.mkObj ([("id", .str e.id), ("time", toJson e.time)] ++ howFields e.how))),
    ("bounds", .arr (g.bounds.toArray.map fun b => Json.mkObj [("time", toJson b.time), ("start", .bool b.start)])),
    ("handbacks", natsJson g.handbacks),
    ("notices", .arr (g.notices.toArray.map fun n =>
      Json.mkObj [("time", toJson n.time), ("finished", .bool n.finished)])),
    ("procs", .arr (g.procs.toArray.map fun q =>
      Json.mkObj [("id", .str q.id), ("pid", toJson q.pid), ("kind", .str (procKindName q.kind))])),
    ("metaFinished", natsJson g.metaFinished)]

/-- Decode an agent's signal facts; `agent` is required, every list defaults to empty. -/
def sigFactsOf (j : Json) : Except String Fw.Obs.Signals.Facts := do
  pure { agent := ← str j "agent",
         launched := ← (← arrD j "launched").mapM fun v => do pure { id := ← str v "id", time := ← nat v "time" },
         ends := ← (← arrD j "ends").mapM fun v => do
           pure { id := ← str v "id", time := ← nat v "time", how := ← howOf v },
         bounds := ← (← arrD j "bounds").mapM fun v => do
           pure { time := ← nat v "time", start := ← asBool "start" (← field v "start") },
         handbacks := ← (← arrD j "handbacks").mapM (asNat "handbacks"),
         notices := ← (← arrD j "notices").mapM fun v => do
           pure { time := ← nat v "time", finished := ← asBool "finished" (← field v "finished") },
         procs := ← (← arrD j "procs").mapM fun v => do
           pure { id := ← str v "id", pid := ← nat v "pid", kind := ← procKindOf (← str v "kind") },
         metaFinished := ← (← arrD j "metaFinished").mapM (asNat "metaFinished") }

/-- A signal state as JSON: `{state, ids}`. -/
def sigStateJson (s : Fw.Obs.Signals.State) : Json :=
  Json.mkObj [("state", .str s.name), ("ids", .arr (s.ids.toArray.map .str))]

/-- An agent's facts as JSON (every field written, absent options are `null`; `signals` only when present). -/
def factsJson (f : AgentFacts) : Json :=
  Json.mkObj ([("id", .str f.id), ("task", .str f.task), ("state", .str (stateName f.state)),
    ("handbackAt", onat f.handbackAt), ("session", toJson f.session),
    ("branch", match f.branch with | some b => branchJson b | none => .null),
    ("worktree", match f.worktree with | some w => worktreeJson w | none => .null),
    ("ctxTokens", toJson f.ctxTokens), ("children", .arr (f.children.toArray.map childJson)),
    ("ci", match f.ci with | some c => ciNextJson c | none => .null),
    ("board", match f.board with | some r => taskRowJson r | none => .null), ("handoff", .bool f.handoff)] ++
    match f.signals with
    | some g => [("signals", sigFactsJson g)]
    | none => [])

/-- Decode an agent's facts; `id`, `task`, `state` and `session` are required. -/
def factsOf (j : Json) : Except String AgentFacts := do
  pure { id := ← str j "id", task := ← str j "task", state := ← stateOf (← str j "state"),
         handbackAt := ← optN j "handbackAt", session := ← nat j "session",
         branch := ← optObj j "branch" branchOf, worktree := ← optObj j "worktree" worktreeOf,
         ctxTokens := ← natD j "ctxTokens" 0, children := ← (← arrD j "children").mapM childOf,
         ci := ← optObj j "ci" ciNextOf, board := ← optObj j "board" taskRowOf,
         handoff := ← boolD j "handoff" false, signals := ← optObj j "signals" sigFactsOf }

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

/-- The reply fields of `obs.next`: per agent (input order) its id and the actions on its resolved facts (`resolve`
against all agents of the request); an agent with signals also gets its signal state, its resolved handback and
whether retention keeps it. -/
def nextReply (p : Fw.Obs.Next.Params) (now : Nat) (fs : List AgentFacts) : Reply :=
  [("agents", .arr (fs.toArray.map fun f =>
    let g := Fw.Obs.Next.resolve p now fs f
    Json.mkObj ([("id", .str f.id), ("actions", .arr ((Fw.Obs.Next.next p now g).toArray.map actionJson))] ++
      match Fw.Obs.Next.sigState p now g with
      | some s => [("signal", sigStateJson s), ("handbackAt", onat g.handbackAt),
                   ("keep", .bool (Fw.Obs.Next.keepB p now g))]
      | none => [])))]

/-- `obs.next`: decode the facts, compute each agent's next actions. -/
def opNext (req : Json) : Except String Reply := do
  let (p, now, fs) ← nextReqOf req
  pure (nextReply p now fs)

/-- Decode an `obs.signals` request body: `now`, `params` (the `obs.next` params; the hung threshold is `loopCapMin`
minutes), `agents` (signal facts); `params` and `agents` are optional (defaults, no agents). -/
def sigReqOf (j : Json) : Except String (Fw.Obs.Next.Params × Nat × List Fw.Obs.Signals.Facts) := do
  let p ← match opt j "params" with
    | none => pure {}
    | some v => nextParamsOf v
  pure (p, ← nat j "now", ← (← arrD j "agents").mapM sigFactsOf)

/-- The reply fields of `obs.signals`: per agent (input order) its id, state, the ids the state names, and its latest
handback at or before `now`. -/
def signalsReply (p : Fw.Obs.Next.Params) (now : Nat) (gs : List Fw.Obs.Signals.Facts) : Reply :=
  [("agents", .arr (gs.toArray.map fun g =>
    let s := Fw.Obs.Signals.classify (Fw.Obs.Next.sigParams p) now g
    Json.mkObj [("agent", .str g.agent), ("state", .str s.name), ("ids", .arr (s.ids.toArray.map .str)),
      ("handbackAt", onat (Fw.Obs.Signals.lastHandback now g))]))]

/-- `obs.signals`: decode the signal facts, classify each agent at `now`. -/
def opSignals (req : Json) : Except String Reply := do
  let (p, now, gs) ← sigReqOf req
  pure (signalsReply p now gs)

/-! ## `obs.timing` and `obs.slow`: the verdicts of `Fw.Obs.Timing` and the slow steps that are alerts -/

namespace Timing

/-- Decode a host (`"local"` or `"ci"`). -/
def hostOf (k : String) (j : Json) : Except String Fw.Obs.Timing.Host := do
  match ← asStr k j with
  | "local" => pure .«local»
  | "ci" => pure .ci
  | h => throw s!"field {k}: unknown host {h}"

/-- The work dimensions of a sample or key: the string members of its `work` object, in key order; a member of another
type is dropped (as `slotWork` drops a width that is not an integer).
-/
def workOf (j : Json) : Except String (List (String × String)) :=
  match opt j "work" with
  | none => .ok []
  | some (.obj kvs) => .ok (kvs.toList.filterMap fun (k, v) => match v with | .str t => some (k, t) | _ => none)
  | some _ => .error "field work: expected an object"

#guard (workOf (Json.mkObj [("work", Json.mkObj [("width", "2"), ("n", (3 : Nat)), ("x", Json.null)])])).toOption ==
  some [("width", "2")]
#guard (workOf (Json.mkObj [("work", Json.mkObj [("width", "1"), ("checks", "light")])])).toOption ==
  some [("checks", "light"), ("width", "1")]
#guard (workOf (Json.mkObj [])).toOption == some [] && (workOf (Json.mkObj [("work", "x")])).toOption == none

/-- Decode a history key. -/
def keyOf (j : Json) : Except String Fw.Obs.Timing.Key := do
  pure { tool := ← str j "tool", step := ← str j "step", host := ← hostOf "host" (← field j "host"),
         kind := ← Fw.Wire.Ops.strD j "runKind" "", work := ← workOf j }

def optI (j : Json) (k : String) : Except String (Option Int) :=
  match opt j k with
  | none => .ok none
  | some v => match v.getInt? with
    | .ok n => .ok (some n)
    | .error _ => .error s!"field {k}: expected an integer"

def waitsOf (j : Json) : Except String (List (Fw.Sup.Adapt.WhyTag × Nat)) := do
  let es ← (← arrD j "waits").mapM (fun e => do pure (← str e "why", ← nat e "ms"))
  pure (es.filterMap (fun (n, ms) => (Fw.Sup.Adapt.WhyTag.ofName? n).map (·, ms)))

/-- Decode a sample (`load` default 0). -/
def sampleOf (j : Json) : Except String Fw.Obs.Timing.Sample := do
  pure { tool := ← str j "tool", step := ← str j "step", durMs := ← nat j "durMs",
         host := ← hostOf "host" (← field j "host"), load := ← natD j "load" 0,
         kind := ← Fw.Wire.Ops.strD j "runKind" "", exit := ← optI j "exit", skipped := ← boolD j "skipped" false,
         waitMs := ← natD j "waitMs" 0, waits := ← waitsOf j, work := ← workOf j,
         ownMs := (opt j "ownMs").bind fun v => (v.getNat?).toOption }

def groupOf (j : Json) : Except String Fw.Obs.Timing.Group := do
  pure { name := ← str j "name", keys := ← (← arrD j "keys").mapM keyOf }

/-- Decode a stage. -/
def stageOf (j : Json) : Except String Fw.Obs.Timing.Stage := do
  pure { id := ← str j "id", groups := ← (← arrD j "groups").mapM groupOf }

/-- Decode the parameters (each field optional, the defaults of `Fw.Obs.Timing.Params`). -/
def paramsOf (j : Json) : Except String Fw.Obs.Timing.Params := do
  let d : Fw.Obs.Timing.Params := {}
  pure { nMin := ← natD j "nMin" d.nMin, window := ← natD j "window" d.window, kNum := ← natD j "kNum" d.kNum,
         kDen := ← natD j "kDen" d.kDen, budgetMs := ← natD j "budgetMs" d.budgetMs,
         budgets := ← (← arrD j "budgets").mapM (fun b => do pure (← str b "tool", ← nat b "ms")),
         ceilings := ← (← arrD j "ceilings").mapM (fun c => do pure (← str c "tool", ← str c "step", ← nat c "ms")),
         loadMax := ← natD j "loadMax" d.loadMax, stages := ← (← arrD j "stages").mapM stageOf }

/-- Decode a request body: `params` (optional) and `samples` (time order). -/
def reqOf (j : Json) : Except String (Fw.Obs.Timing.Params × List Fw.Obs.Timing.Sample) := do
  let p ← match opt j "params" with
    | none => pure {}
    | some v => paramsOf v
  pure (p, ← (← arrD j "samples").mapM sampleOf)

/-- `obs.timing`: one verdict per full sample (`Fw.Obs.Timing.fullRun`), then the structural verdicts (`Fw.Obs.Timing.timingVerdicts`). -/
def opTiming (req : Json) : Except String Reply := do
  let (p, ss) ← reqOf req
  pure [("verdicts", .arr ((Fw.Obs.Timing.verdictsOf p ss).map Fw.Wire.Obs.Timing.verdictJson).toArray)]

def detailOf (vs : List Fw.Obs.Timing.Verdict) (s : String) : String :=
  match (vs.filterMap fun
      | .sample v => if v.code == .slow && Fw.Obs.Next.stepName v == s then some v.detail else none
      | .structural _ => none).getLast? with
  | some d => d
  | none => ""

def opSlow (req : Json) : Except String Reply := do
  let (p, ss) ← reqOf req
  let vs := Fw.Obs.Timing.verdictsOf p ss
  let slow := Fw.Obs.Next.slowSteps vs
  let base := [("slow", Json.arr (slow.toArray.map .str))]
  match req.getObjVal? "detail" with
  | .ok (.bool true) => pure (base ++ [("details", Json.arr (slow.toArray.map fun s => .str (detailOf vs s)))])
  | _ => pure base

end Timing

namespace Backoff

/-- Decode the parameters (each field optional, the defaults of `Fw.Obs.Backoff.Params`). -/
def paramsOf (j : Json) : Except String Fw.Obs.Backoff.Params := do
  let d : Fw.Obs.Backoff.Params := {}
  pure { extra := ← natD j "extra" d.extra }

/-- The reply fields of a decision: `action` (`"restart"` or `"wait"`) and `waitMs` (0 for restart). -/
def decisionJson : Fw.Obs.Backoff.Decision → Reply
  | .restart => [("action", .str "restart"), ("waitMs", toJson (0 : Nat))]
  | .wait ms => [("action", .str "wait"), ("waitMs", toJson ms)]

/-- `obs.backoff`: what to do when an fwcore call missed its deadline (`Fw.Obs.Backoff.onTimeout`). Request:
`{params?, cores, load, baseMs, waitedMs}`; reply `{action, waitMs}`. -/
def opBackoff (req : Json) : Except String Reply := do
  let p ← match opt req "params" with
    | none => pure {}
    | some v => paramsOf v
  pure (decisionJson (Fw.Obs.Backoff.onTimeout p (← nat req "cores") (← nat req "load") (← nat req "baseMs") (← nat req "waitedMs")))

end Backoff

/-- The `Fw.Obs` ops. -/
def ops : List String := ["obs.health", "obs.next", "obs.signals", "obs.timing", "obs.slow", "obs.backoff", "obs.push"]

/-- Dispatch an `Fw.Obs` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "obs.health" => some (opHealth req)
  | "obs.next" => some (opNext req)
  | "obs.signals" => some (opSignals req)
  | "obs.timing" => some (Timing.opTiming req)
  | "obs.slow" => some (Timing.opSlow req)
  | "obs.backoff" => some (Backoff.opBackoff req)
  | "obs.push" => some (Fw.Wire.Obs.Push.opPush req)
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
-- obs.signals: no agents; an open turn; handed back with `b` pending; the same past the 30-min cap with a stdin proc.
#guard run "obs.signals" "{\"now\":0}" == "{\"agents\":[]}"
#guard run "obs.signals" "{\"now\":5,\"agents\":[{\"agent\":\"a\",\"bounds\":[{\"time\":0,\"start\":true}]}]}" ==
  "{\"agents\":[{\"agent\":\"a\",\"handbackAt\":null,\"ids\":[],\"state\":\"working\"}]}"
#guard run "obs.signals" "{\"now\":5,\"agents\":[{\"agent\":\"a\",\"launched\":[{\"id\":\"b\",\"time\":1}],\"bounds\":[{\"time\":0,\"start\":true},{\"time\":2,\"start\":false}],\"handbacks\":[2]}]}" ==
  "{\"agents\":[{\"agent\":\"a\",\"handbackAt\":2,\"ids\":[\"b\"],\"state\":\"handedBackHeld\"}]}"
#guard run "obs.signals" "{\"now\":1800005,\"agents\":[{\"agent\":\"a\",\"launched\":[{\"id\":\"b\",\"time\":1}],\"bounds\":[{\"time\":0,\"start\":true},{\"time\":2,\"start\":false}],\"handbacks\":[2],\"procs\":[{\"id\":\"b\",\"pid\":9,\"kind\":\"stdin\"}]}]}" ==
  "{\"agents\":[{\"agent\":\"a\",\"handbackAt\":2,\"ids\":[\"b\"],\"state\":\"hung\"}]}"
-- An exit with a negative code ends `b`; `exited` without a code and an unknown proc kind are refused.
#guard run "obs.signals" "{\"now\":5,\"agents\":[{\"agent\":\"a\",\"launched\":[{\"id\":\"b\",\"time\":1}],\"ends\":[{\"id\":\"b\",\"time\":3,\"how\":\"exited\",\"code\":-1}],\"bounds\":[{\"time\":0,\"start\":true},{\"time\":2,\"start\":false}],\"handbacks\":[2]}]}" ==
  "{\"agents\":[{\"agent\":\"a\",\"handbackAt\":2,\"ids\":[],\"state\":\"handedBackDone\"}]}"
#guard run "obs.signals" "{\"now\":5,\"agents\":[{\"agent\":\"a\",\"ends\":[{\"id\":\"b\",\"time\":3,\"how\":\"exited\"}]}]}" ==
  "error: field code: expected an integer"
#guard run "obs.signals" "{\"now\":5,\"agents\":[{\"agent\":\"a\",\"procs\":[{\"id\":\"b\",\"pid\":9,\"kind\":\"tty\"}]}]}" ==
  "error: field kind: unknown value tty"
-- obs.slow: a slow latest sample is an alert subject `<tool>/<step>`; a newer ok sample clears it; bad host refused
#guard run "obs.slow" "{\"params\":{\"nMin\":1,\"budgetMs\":1000},\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":100,\"host\":\"local\"},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":5000,\"host\":\"local\"}]}" ==
  "{\"slow\":[\"t/s\"]}"
#guard run "obs.slow" "{\"params\":{\"nMin\":1,\"budgetMs\":1000},\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":100,\"host\":\"local\"},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":5000,\"host\":\"local\"},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":100,\"host\":\"local\"}]}" ==
  "{\"slow\":[]}"
#guard run "obs.slow" "{\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":1,\"host\":\"mars\"}]}" == "error: field host: unknown host mars"
#guard run "obs.slow" "{\"params\":{\"nMin\":1,\"budgetMs\":1000},\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":2000,\"host\":\"local\",\"work\":{\"width\":2}},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":5000,\"host\":\"local\",\"work\":{\"width\":\"1\"}}]}" == "{\"slow\":[]}"
#guard run "obs.slow" "{\"params\":{\"nMin\":1,\"budgetMs\":1000},\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":2000,\"host\":\"local\",\"work\":{\"width\":2}},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":5000,\"host\":\"local\",\"work\":{\"width\":\"2\"}}]}" ==
  "{\"slow\":[]}"
#guard run "obs.slow" "{\"params\":{\"nMin\":1,\"budgetMs\":1000},\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":2000,\"host\":\"local\",\"work\":{\"width\":\"2\"}},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":5000,\"host\":\"local\",\"work\":{\"width\":\"2\"}}]}" ==
  "{\"slow\":[\"t/s [width=2]\"]}"
#guard run "obs.slow" "{\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":1,\"host\":\"ci\",\"work\":3}]}" == "error: field work: expected an object"
#guard run "obs.slow" "{}" == "{\"slow\":[]}"
#eval run "obs.slow" "{\"detail\":true,\"params\":{\"nMin\":1,\"budgetMs\":1000},\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":100,\"host\":\"local\"},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":5000,\"host\":\"local\"}]}"
#eval 0
#guard run "obs.slow" "{\"params\":{\"nMin\":1,\"budgetMs\":1000},\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":100,\"host\":\"local\",\"exit\":0},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":5000,\"host\":\"local\",\"exit\":null},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":100,\"host\":\"local\",\"exit\":16},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":0,\"host\":\"ci\",\"exit\":0,\"skipped\":true}]}" ==
  "{\"slow\":[\"t/s\"]}"
#guard run "obs.slow" "{\"params\":{\"nMin\":1,\"budgetMs\":1000},\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":2000,\"host\":\"ci\",\"exit\":0},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":0,\"host\":\"ci\",\"exit\":0,\"skipped\":true},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":0,\"host\":\"ci\",\"exit\":0,\"skipped\":true},{\"tool\":\"t\",\"step\":\"s\",\"durMs\":2500,\"host\":\"ci\",\"exit\":0}]}" ==
  "{\"slow\":[]}"
#guard run "obs.slow" "{\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":1,\"host\":\"ci\",\"exit\":\"0\"}]}" == "error: field exit: expected an integer"
#guard run "obs.slow" "{\"samples\":[{\"tool\":\"t\",\"step\":\"s\",\"durMs\":1,\"host\":\"ci\",\"exit\":-1}]}" == "{\"slow\":[]}"
-- obs.backoff: not loaded restarts at the first deadline; loaded (load >= cores) waits the rest of the stretched total; then restarts
#guard run "obs.backoff" "{\"cores\":8,\"load\":3,\"baseMs\":10000,\"waitedMs\":10000}" == "{\"action\":\"restart\",\"waitMs\":0}"
#guard run "obs.backoff" "{\"cores\":8,\"load\":115,\"baseMs\":10000,\"waitedMs\":10000}" == "{\"action\":\"wait\",\"waitMs\":20000}"
#guard run "obs.backoff" "{\"cores\":8,\"load\":115,\"baseMs\":10000,\"waitedMs\":30000}" == "{\"action\":\"restart\",\"waitMs\":0}"
#guard run "obs.timing" "{}" == "{\"verdicts\":[]}"
-- obs.next: a branch whose land commit is on main, or that the live land lock names, gets no land action
#guard ((run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"done\",\"session\":1,\"handbackAt\":5,\"branch\":{\"name\":\"w\",\"ahead\":3,\"landed\":false}}]}").splitOn "\"land\"").length == 2
#guard ((run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"done\",\"session\":1,\"handbackAt\":5,\"branch\":{\"name\":\"w\",\"ahead\":3,\"landed\":false,\"onMain\":true}}]}").splitOn "\"land\"").length == 1
#guard ((run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"done\",\"session\":1,\"handbackAt\":5,\"branch\":{\"name\":\"w\",\"ahead\":3,\"landed\":false,\"landLock\":\"w\"}}]}").splitOn "\"land\"").length == 1
#guard ((run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"done\",\"session\":1,\"handbackAt\":5,\"branch\":{\"name\":\"w\",\"ahead\":3,\"landed\":false,\"landLock\":\"x\"}}]}").splitOn "\"land\"").length == 2
#guard ((run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"done\",\"session\":1,\"handbackAt\":5,\"branch\":{\"name\":\"w\",\"ahead\":3,\"landed\":false,\"landQueued\":true}}]}").splitOn "\"land\"").length == 1
-- obs.next with signals: the hung stdin child of an idle, handed-back agent is killed and the agent kept; a loop
-- watching task `b` sees its producer exited once another agent's signals end `b` (`killed`).
#guard run "obs.next" "{\"now\":1800005,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":9,\"chain\":[1],\"kind\":\"stdinWait\",\"startedAt\":1}],\"signals\":{\"agent\":\"a\",\"launched\":[{\"id\":\"b\",\"time\":1}],\"bounds\":[{\"time\":0,\"start\":true},{\"time\":2,\"start\":false}],\"handbacks\":[2],\"procs\":[{\"id\":\"b\",\"pid\":9,\"kind\":\"stdin\"}]}}]}" ==
  "{\"agents\":[{\"actions\":[{\"action\":\"killOrphan\",\"pid\":9}],\"handbackAt\":2,\"id\":\"a\",\"keep\":true,\"signal\":{\"ids\":[\"b\"],\"state\":\"hung\"}}]}"
#guard run "obs.next" "{\"now\":10,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":7,\"chain\":[1],\"kind\":\"sleepLoop\",\"startedAt\":0,\"watchedAt\":5,\"watch\":{\"kind\":\"task\",\"id\":\"b\"}}]},{\"id\":\"x\",\"task\":\"x\",\"state\":\"active\",\"session\":1,\"signals\":{\"agent\":\"x\",\"launched\":[{\"id\":\"b\",\"time\":1}],\"ends\":[{\"id\":\"b\",\"time\":3,\"how\":\"killed\"}]}}]}" ==
  "{\"agents\":[{\"actions\":[{\"action\":\"killOrphan\",\"pid\":7}],\"id\":\"a\"},{\"actions\":[{\"action\":\"none\"}],\"handbackAt\":null,\"id\":\"x\",\"keep\":false,\"signal\":{\"ids\":[],\"state\":\"idle\"}}]}"

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
  { name := "inc-watch-unlanded-after-land: branch 3 ahead, not an ancestor of main, but a land commit for its task is on main -> none"
    fs := [{ ex "z" .done with handbackAt := some (ago 5), branch := some { name := "wt-z", ahead := 3, landed := false, queued := false, onMain := true } }] },
  { name := "inc-watch-alert-during-land: branch 3 ahead and unlanded, the live land lock names this branch -> none"
    fs := [{ ex "z" .done with handbackAt := some (ago 5), branch := some { name := "wt-z", ahead := 3, landed := false, queued := false, landLock := some "wt-z" } }] },
  { name := "a land lock held for another branch does not suppress: branch 3 ahead and unlanded -> land"
    fs := [{ ex "z" .done with handbackAt := some (ago 5), branch := some { name := "wt-z", ahead := 3, landed := false, queued := false, landLock := some "wt-other" } }] },
  { name := "land-queue: branch 3 ahead and unlanded, but a pending entry of the land queue -> none"
    fs := [{ ex "z" .done with handbackAt := some (ago 5), branch := some { name := "wt-z", ahead := 3, landed := false, queued := false, inLandQueue := true } }] },
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
  ("child start 0 (older than the loop cap): killOrphan", lit "{\"now\":1760000000000,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":2,\"chain\":[1],\"kind\":\"sleepLoop\",\"startedAt\":0}]}]}"),
  ("child start negative (a ps age longer than the clock) is unknown: not old, no killOrphan", lit "{\"now\":1760000000000,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":2,\"chain\":[1],\"kind\":\"sleepLoop\",\"startedAt\":-1760000000001}]}]}"),
  ("refused: a fractional child start", lit "{\"now\":1760000000000,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":2,\"chain\":[1],\"kind\":\"sleepLoop\",\"startedAt\":1.5}]}]}"),
  ("refused: unknown state", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"busy\",\"session\":1}]}"),
  ("refused: unknown child kind", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":2,\"kind\":\"robot\",\"startedAt\":0}]}]}"),
  ("refused: ciWait without run", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":2,\"kind\":\"ciWait\",\"timeoutMin\":10,\"startedAt\":0}]}]}"),
  ("refused: negative pid", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"children\":[{\"pid\":-2,\"kind\":\"build\",\"startedAt\":0}]}]}"),
  ("refused: board row without done", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"board\":{\"id\":\"a\"}}]}"),
  ("refused: agent without session", lit "{\"now\":0,\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\"}]}"),
  ("params: loopCapMin and a Health field given, the rest default",
   lit "{\"now\":1760000000000,\"params\":{\"loopCapMin\":1,\"ctxWarn\":10},\"agents\":[{\"id\":\"a\",\"task\":\"a\",\"state\":\"idle\",\"session\":1,\"ctxTokens\":11,\"children\":[{\"pid\":2,\"chain\":[1],\"kind\":\"sleepLoop\",\"startedAt\":1759999000000}]}]}")]

/-- Every case as (name, request body). -/
def cases (_ : Unit := ()) : List (String × Json) := typed.map (fun c => (c.name, nextReqJson c.p c.now c.fs)) ++ literal

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
def fileText (_ : Unit := ()) : String :=
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

/-! ## Golden vectors of `obs.signals`

`packages/contracts/golden/obs/signals.jsonl`: one line per checkpoint of the 8 real timelines of
`Fw.Obs.Signals.golden`, `{"name", "request", "response", "expect"}`. The timelines count seconds since 23:00 (+07:00)
on 2026-10-17; on the wire every time is milliseconds since the Unix epoch, `ms t = base + 1000 t`, so the default
loop cap (30 min) is the golden's 1800 s. `expect` holds the note's rule state and the expected state; `run` checks
that the file is current and that every response equals `expect.state`. -/
namespace SignalsGolden
open Fw.Obs.Signals

/-- 2026-10-17 23:00 +07:00 in milliseconds since the Unix epoch. -/
def base : Nat := 1792252800000

/-- A golden time (seconds after `base`) in wire milliseconds. -/
def ms (t : Nat) : Nat := base + 1000 * t

/-- An agent's signal facts with every time mapped to wire milliseconds. -/
def scale (f : Facts) : Facts :=
  { f with
    launched := f.launched.map fun l => { l with time := ms l.time }
    ends := f.ends.map fun e => { e with time := ms e.time }
    bounds := f.bounds.map fun b => { b with time := ms b.time }
    handbacks := f.handbacks.map ms
    notices := f.notices.map fun n => { n with time := ms n.time }
    metaFinished := f.metaFinished.map ms }

/-- `h:mm:ss` of a golden time (hours after 23:00 wrap at 24). -/
def clock (t : Nat) : String :=
  let h := (t / 3600 + 23) % 24
  let two (n : Nat) := if n < 10 then s!"0{n}" else s!"{n}"
  s!"{two h}:{two (t / 60 % 60)}:{two (t % 60)}"

/-- One golden line: name, request body (without `op`), rule state and expected state. -/
structure Case where
  name : String
  req : Json
  rule : Fw.Obs.Signals.State
  state : Fw.Obs.Signals.State

/-- Every checkpoint of every timeline as a case. -/
def cases (_ : Unit := ()) : List Case :=
  golden.flatMap fun τ => τ.checks.map fun c =>
    { name := s!"{τ.name} @ {clock c.t}",
      req := Json.mkObj [("now", toJson (ms c.t)), ("agents", .arr #[sigFactsJson (scale τ.facts)])],
      rule := c.rule, state := c.state }

/-- The reply to a request (without id): the reply fields, or `{error}`. -/
def respond (req : Json) : Json :=
  match opSignals req with
  | .ok f => Json.mkObj f
  | .error e => Json.mkObj [("error", .str e)]

/-- The state of the first agent of a response (`none` for an error or a malformed reply). -/
def stateOf (r : Json) : Option (String × List Json) := do
  let a ← (r.getObjValD "agents").getArrVal? 0 |>.toOption
  let s ← (a.getObjValAs? String "state").toOption
  let ids ← (a.getObjValD "ids").getArr? |>.toOption
  pure (s, ids.toList)

/-- The cases whose response state differs from the expected state (empty when the golden reproduces). -/
def mismatches (_ : Unit := ()) : List String :=
  cases.filterMap fun c =>
    if stateOf (respond c.req) == some (c.state.name, c.state.ids.map Json.str) then none else some c.name

#guard cases.length == 39
#guard mismatches == []
-- The signal-facts codec round-trips every golden timeline (with wire times).
#guard golden.all fun τ => match sigFactsOf (sigFactsJson (scale τ.facts)) with
  | .ok g => g == scale τ.facts
  | .error _ => false
-- Scaling to milliseconds keeps every checkpoint's state under the default 30-min loop cap.
#guard golden.all fun τ => τ.checks.all fun c =>
  classify (Fw.Obs.Next.sigParams {}) (ms c.t) (scale τ.facts) == classify goldenParams c.t τ.facts

/-- The text of the golden file. -/
def fileText (_ : Unit := ()) : String :=
  String.join (cases.map fun c =>
    let opReq := match c.req with
      | .obj kvs => Json.obj (kvs.insert "op" (.str "obs.signals"))
      | j => j
    (Json.mkObj [("name", .str c.name), ("request", opReq), ("response", respond c.req),
      ("expect", Json.mkObj [("rule", sigStateJson c.rule), ("state", sigStateJson c.state)])]).compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def path : System.FilePath := ".." / "packages" / "contracts" / "golden" / "obs" / "signals.jsonl"

/-- Compare (or write) the golden file; returns the number of failures (stale file or mismatched states). -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / path
  let mut bad := 0
  if write then
    IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / "obs")
    IO.FS.writeFile p fileText
  else
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != fileText then
      IO.println s!"obs.signals golden: {p} is stale (regenerate with Fw.Wire.Obs.SignalsGolden.run \".\" true)"
      bad := bad + 1
  for m in mismatches do
    IO.println s!"obs.signals golden: {m} does not give the expected state"
    bad := bad + 1
  IO.println s!"obs.signals golden: {cases.length} checkpoints of {golden.length} timelines, {
    if write then "written" else s!"{bad} failures"}"
  return bad

end SignalsGolden

end Fw.Wire.Obs
