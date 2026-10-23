import Fw.Obs.Stale
import Fw.Obs.FeedbackAlert
import Fw.Console.Steps
import Fw.Obs.GhStatus
import Fw.Obs.Timing
/-!
# Team health: per-agent state and alert rules over one observation snapshot

`fw watch` (task `watch-cli`) collects one snapshot per interval: every agent's kind, timing and tool facts, the lead
session's last tool event and last notification, plus system, simulator-lock, Docker, worktree, CI, load and local
process facts, the time of the previous check and the task ids on the console's critical path. This module is the pure
part: from the snapshot and the thresholds it derives each agent's state (`active`, `idle`, `parked`, `stalled`,
`gone`, `done`) and a sorted, duplicate-free list of alerts. The wire op `obs.health` (`Fw.Wire.Obs`) is its JSON face.

Units: times are ms since the epoch (`Nat`); the `…Min` thresholds are minutes (`μ = 60000` ms each); an age is the
truncated difference `now ∸ t` (a timestamp after `now` has age 0). Context sizes are tokens,
disk is whole GB, the load average is its floor (an integer threshold `L` is reached by the load exactly when it is
reached by the floor).

Why no per-agent "waiting for permission" state: every `Notification` hook event arrives without an agent id, so a
permission prompt cannot be attributed to an agent. It is a team-level alert instead (`team.permissionWait`: a
notification newer than the lead session's last tool event; the user answers it in the terminal).

Gone agents (`goneAfterMin`): an agent stopped by hand (TaskStop) emits no stop hook. An agent with no event for more
than `goneAfterMin` minutes counts as ended (state `gone`): it no longer counts as live (`nLive`, `team.overCap`, child,
lock and container tests), raises no other `agent.*` alert, and raises `agent.gone` once, at the first check that sees
it gone (the previous check, `prevAt`, did not).

Slow work (the lead's monitor): `ci.slow` (a run queued or in progress for more than `ciSlowMin`), `ci.finished` (a
run that the previous check flagged as slow has finished: its duration and conclusion, once), `agent.toolSlow` (a tool
call in flight for more than `toolSlowMin`, waits excepted), `proc.long` (a process tree started by the session alive
for more than `procMaxMin`, see below), `sys.loadHigh` (1-min load average at or above `loadMax`), `sys.contended` (1-min load above
`Fw.Obs.Timing.contendedLoad`, the CPUs of the local Mac: the one signal that stands for the per-step `timing.slow` the load causes).

Long-running processes (`proc.long`): a tree is exempt when it is an intended long-runner (`declaredB`: its program is
on the checked-in allowlist `keepProgs`, or one of its pids is a service pid or a pid the lead declared with
`fw watch --keep`), and when the agent whose Bash call started it is live (`ownerLiveB`: an agent's poll loop is its own
business while it works). A tree of the lead session, or of an agent that has stopped, is gone, or is no longer listed
(an orphan), raises `proc.long` once it is older than `procMaxMin`; when an agent started it, the alert names that ended agent.

Critical path: the observation carries `critical`, the task ids on the console's critical path (`/api/plan`
`criticalPath`, read by `fw watch`; empty when the console is down). An agent alert whose agent is tied to such a task
(id, name or task equals the task id, or is it plus a `-<digits>` suffix) and a CI alert whose branch is `ci/<task>`
(same suffix rule) is marked `crit`; the output order puts every `crit` alert first.

Rules (proved below):
* `state_done`, `state_gone`, `state_parked`, `state_stalled`, `state_idle`, `state_active`: the state is exactly the
  one the rules name; `state_cases`: exactly one holds; `counts_total`: the counts add up.
* `agentAlerts_quiet`, `agent_alert_live`, `gone_alerts`, `goneAlert_iff`: a done or parked agent raises no `agent.*`
  alert, a gone agent only `agent.gone`, and that exactly when the previous check did not see it gone.
* `nLive_gone`: a gone agent does not count as live (so not toward `team.overCap`).
* `wait_not_hang`: an `Agent` or `SendMessage` call in flight while a child of the agent is live is a wait: no
  `agent.toolHang`, no `agent.toolSlow`, never stalled.
* `stalled_facts`: a stalled agent is not parked and its age is at least the stall threshold.
* `health_mono`: loosening the thresholds (raising any upper threshold, lowering `diskMinGB`, same `wfQuietMin` and
  `goneAfterMin`) never adds an alert.
* `lockOrphan_iff`, `permissionWait_iff`, `loadHigh_iff`: when `sim.lockOrphan`, `team.permissionWait` and
  `sys.loadHigh` fire; `sysContended_iff`, `sysContended_iff_sample`: when `sys.contended` fires, and that it is the test that makes a local timing sample `contended`.
* `procLong_iff`, `ownerLive_quiet`, `declared_quiet`, `procLong_sound`, `orphan_raised`: a live agent's process tree
  and a declared long-runner never raise `proc.long`; every `proc.long` alert is an undeclared tree older than
  `procMaxMin` whose owner is not live; an orphan of an ended agent does raise it.
* `svcStale_iff`, `staleAlert_fields`, `sStale_restart` (rule and proofs in `Fw.Obs.Stale`): `svc.stale` fires for a
  service exactly when an input changed on `main` since its base commit (start or build); a service judged at the
  head raises none.
* `svcSweepError_iff`, `sweep_error_alerts`: `svc.sweepError` fires, with the count, for every service whose drain
  caught an fwcore throw since it started (task task-state-truth: no swallowed throw).
* `svcUnknown_iff`, `unknown_service_alerts`: `svc.unknown` fires for every service whose running code cannot be
  identified (never silence).
* `alerts_sorted`, `crit_first`, `mem_alerts`, `health_perm`: the alert list is strictly sorted (critical first, then
  code, subject, detail), holds exactly the raised alerts, and does not depend on the order of the agents.
-/
namespace Fw.Obs.Health

/-- Milliseconds per minute, the unit of every `…Min` threshold. -/
def msPerMin : Nat := 60000

/-- The thresholds. Upper thresholds reached at or above (a value equal to the threshold alerts): `idleMin`,
`stallMin`, `toolHangMin` (minutes), `errStreak` (failed calls), `simLockMaxMin` (minutes), `loadMax` (1-min load
average); upper thresholds passed only strictly above (a value equal to the threshold does not alert): `ctxResumeMax`,
`ctxWarn` (tokens), `agentCap` (live non-lead agents), `worktreesMax`, `ciSlowMin` (per workflow `ciSlowBy`, strict too), `toolSlowMin`, `procMaxMin`
(minutes); the lower threshold `diskMinGB` (free GB strictly below it alerts); and two thresholds that decide which
agents have ended (they are not alert thresholds): `wfQuietMin`, the minutes without an event after which a workflow
agent seen only in its transcript counts as done, and `goneAfterMin`, the minutes strictly above which any agent
without an event counts as gone.
-/
structure Params where
  idleMin       : Nat := 10
  stallMin      : Nat := 20
  toolHangMin   : Nat := 30
  errStreak     : Nat := 3
  ctxResumeMax  : Nat := 250000
  ctxWarn       : Nat := 200000
  diskMinGB     : Nat := 20
  agentCap      : Nat := 10
  simLockMaxMin : Nat := 30
  worktreesMax  : Nat := 20
  wfQuietMin    : Nat := 30
  goneAfterMin  : Nat := 120
  ciSlowMin     : Nat := 20
  toolSlowMin   : Nat := 15
  procMaxMin    : Nat := 20
  loadMax       : Nat := 150
  ciSlowBy      : List (String × Nat) := [("breakpoint-gate", 40)]
deriving DecidableEq, Repr

/-- **The `ci.slow` limit of a workflow**: the entry of the per-workflow map `ciSlowBy` when the workflow has one,
otherwise the global `ciSlowMin`.

`breakpoint-gate` runs 20 to 25 minutes (p50 of 2026-10-19), so its default limit is 40 minutes, not the global 20.
-/
def ciSlowFor (p : Params) (w : String) : Nat :=
  (p.ciSlowBy.lookup w).getD p.ciSlowMin

/-- **The global value is the default** (`ciSlowFor_default`): a workflow with no entry in the map is judged by `ciSlowMin`. -/
theorem ciSlowFor_default (p : Params) (w : String) (h : p.ciSlowBy.lookup w = none) :
    ciSlowFor p w = p.ciSlowMin := by
  simp [ciSlowFor, h]

/-- **With an empty map every workflow uses the global value** (`ciSlowFor_nil`). -/
theorem ciSlowFor_nil (p : Params) (w : String) (h : p.ciSlowBy = []) : ciSlowFor p w = p.ciSlowMin := by
  simp [ciSlowFor, h, List.lookup]

/-- **An entry overrides the global value** (`ciSlowFor_entry`): when the first entry for `w` is `m`, the limit of `w` is `m`. -/
theorem ciSlowFor_entry (p : Params) (w : String) (m : Nat) (h : p.ciSlowBy.lookup w = some m) :
    ciSlowFor p w = m := by
  simp [ciSlowFor, h]

/-- A tool call still running: the tool's name and its start time (ms). -/
structure Inflight where
  tool  : String
  since : Nat
deriving DecidableEq, Repr

/-- How an agent was started: the lead session itself, a teammate (idles between messages on purpose), a subagent
(spawned by the `Agent` tool), or a workflow agent (spawned by a workflow run).
-/
inductive Kind where
  | lead | teammate | subagent | workflow
deriving DecidableEq, Repr

/-- One agent as observed: id, optional name and task (a lock holder may name either), kind, the id of the agent
that spawned it (`none` when the lead did, or unknown), start, last event and stop times (ms; `stoppedAt` is `none`
while it runs), the number of failed tool calls at the end of its log, the tool call in flight, the name and time of
its last finished tool call, the time of its last `TeammateIdle` event, whether its workflow run has finished, whether
it is seen only in its transcript (no hook event), its context size, and the pid of the Claude session whose hooks
wrote its spool (`none` when the spool has none).
-/
structure Agent where
  id             : String
  name           : Option String := none
  task           : Option String := none
  kind           : Kind := .subagent
  parent         : Option String := none
  startedAt      : Nat := 0
  lastAt         : Nat := 0
  stoppedAt      : Option Nat := none
  errTail        : Nat := 0
  inflight       : Option Inflight := none
  lastTool       : Option String := none
  lastToolAt     : Option Nat := none
  idleAt         : Option Nat := none
  workflowDone   : Bool := false
  transcriptOnly : Bool := false
  ctxTokens      : Option Nat := none
  sessionPid     : Option Nat := none
deriving DecidableEq, Repr

/-- The lead session's facts: the time of its last finished tool call and of the last `Notification` hook event
(which carries no agent id), each `none` when there was none.
-/
structure Lead where
  lastToolAt : Option Nat := none
  noteAt     : Option Nat := none
deriving DecidableEq, Repr

/-- Memory pressure as macOS reports it. -/
inductive Mem where
  | normal | warn | critical
deriving DecidableEq, Repr

/-- The simulator lock: its holder (a free-form owner string) and since when it is held. -/
structure SimLock where
  holder : Option String := none
  since  : Option Nat := none
deriving DecidableEq, Repr

/-- A running Docker container: id, name, start time (ms). -/
structure Container where
  id        : String
  name      : String
  startedAt : Nat
deriving DecidableEq, Repr

/-- A CI run: workflow, branch, status, conclusion (`none` while running), start time and end time (ms; `endedAt` is
the run's last update, `none` when unknown).

`headSha` is the commit the run was triggered for (`""` when unknown); runs of one workflow, branch and sha form a set.
-/
structure CiRun where
  workflow   : String
  branch     : String
  status     : String
  conclusion : Option String := none
  startedAt  : Nat
  endedAt    : Option Nat := none
  headSha    : String := ""
deriving DecidableEq, Repr

/-- A local process tree started by the observed session (one Bash tool call): the pid of its root, the program name
of its first command (never the command line), its start time (ms), every other pid in the tree, and the id of the
agent whose Bash call started it (`none`: the lead session, or not known).
-/
structure Proc where
  pid       : Nat
  name      : String
  startedAt : Nat
  pids      : List Nat := []
  agent     : Option String := none
deriving DecidableEq, Repr

/-- What the local machine runs when it is loaded (task `local-mem-budget`): the `lake` builders and the live heavy-lock
holders (for the detail of `sys.contended`), and whether the previous check already raised `sys.contended`
(`prevContended`: the one bit of memory of the hysteresis). One field of `System`, so its wire round trip is its own lemma.
-/
structure LoadInfo where
  builders      : Nat := 0
  heavyJobs     : Nat := 0
  prevContended : Bool := false
deriving DecidableEq, Repr

/-- The machine-level facts the rules read: free disk (GB), memory pressure, the simulator lock, running containers,
the number of git worktrees, recent CI runs, the floor of the 1-min load average, the session's process trees, the
service pids (long-running on purpose: the console server, the watcher itself), and the pids the lead declared as
intended long-runners (`fw watch --keep`).

`V` the services' facts. `alivePids` is the set of pids the process table listed at the observation (`none`: the table was not read, so no agent
is judged by it).
-/
structure System where
  diskFreeGB  : Nat := 0
  memPressure : Mem := .normal
  simLock     : SimLock := {}
  docker      : List Container := []
  worktrees   : Nat := 0
  ci          : List CiRun := []
  loadFloor   : Nat := 0
  procs       : List Proc := []
  services    : List Nat := []
  keep        : List Nat := []
  svcs        : List Svc := []
  alivePids   : Option (List Nat) := none
  gh          : Gh := {}
  load        : LoadInfo := {}
  feedback    : List Fw.Console.ReviewFeedback.Ev := []
deriving DecidableEq, Repr

/-- One observation: the time it was taken (ms), the agents, the lead session's facts, the system facts, the time of
the previous check (`none` for the first), and the task ids on the console's critical path.
-/
structure Obs where
  now      : Nat
  agents   : List Agent := []
  lead     : Lead := {}
  system   : System := {}
  prevAt   : Option Nat := none
  critical : List String := []
deriving DecidableEq, Repr

/-! ## Agent state -/

/-- The six agent states. -/
inductive State where
  | active | idle | parked | stalled | gone | done
deriving DecidableEq, Repr

/-- Whether an agent has stopped: it stopped, or it is a workflow agent whose workflow run finished, or a workflow
agent seen only in its transcript with no event for `wfQuietMin` minutes.
-/
def stopped (p : Params) (now : Nat) (a : Agent) : Bool :=
  a.stoppedAt.isSome ||
    (a.kind == .workflow && (a.workflowDone || (a.transcriptOnly && decide (p.wfQuietMin * msPerMin ≤ now - a.lastAt))))

/-- Whether an agent is gone: no event for strictly more than `goneAfterMin` minutes (stopped by hand, no stop hook). -/
def goneB (p : Params) (now : Nat) (a : Agent) : Bool := decide (p.goneAfterMin * msPerMin < now - a.lastAt)

/-- Whether an agent has ended: it stopped or it is gone. -/
def ended (p : Params) (now : Nat) (a : Agent) : Bool := stopped p now a || goneB p now a

/-- Whether an agent is live (has not ended). -/
def live (p : Params) (now : Nat) (a : Agent) : Bool := !ended p now a

/-- Whether a `TeammateIdle` event is newer than the last finished tool call (any such event counts when no tool call
has finished).
-/
def idleNewer (a : Agent) : Bool :=
  match a.idleAt with
  | none => false
  | some i => match a.lastToolAt with
    | none => true
    | some s => decide (s < i)

/-- Whether an agent is parked: a teammate with no tool in flight whose last finished tool call was `SendMessage`, or
whose last `TeammateIdle` is newer than its last finished tool call (it waits for a message on purpose).
-/
def parkedB (a : Agent) : Bool :=
  a.kind == .teammate && a.inflight.isNone && (a.lastTool == some "SendMessage" || idleNewer a)

/-- The tools whose call waits for another agent. -/
def waitTool (s : String) : Bool := s == "Agent" || s == "SendMessage"

/-- Whether some live agent of the list names `a` as its parent. -/
def hasLiveChild (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Bool :=
  agents.any fun b => live p now b && b.parent == some a.id

/-- Whether the tool call in flight has hung: it has run for `toolHangMin` minutes and it is not a wait (an `Agent` or
`SendMessage` call while a child of the agent is live).
-/
def hungB (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Bool :=
  match a.inflight with
  | none => false
  | some f => !(waitTool f.tool && hasLiveChild p now agents a) && decide (p.toolHangMin * msPerMin ≤ now - f.since)

/-- The stall test as a Boolean: no event for `stallMin` minutes, and no tool in flight or the one in flight has hung. -/
def stallB (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Bool :=
  decide (p.stallMin * msPerMin ≤ now - a.lastAt) && (a.inflight.isNone || hungB p now agents a)

/-- The stall condition as a proposition. -/
def Stall (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Prop :=
  p.stallMin * msPerMin ≤ now - a.lastAt ∧
    ∀ f, a.inflight = some f →
      ¬ (waitTool f.tool = true ∧ hasLiveChild p now agents a = true) ∧ p.toolHangMin * msPerMin ≤ now - f.since

/-- The Boolean stall test decides `Stall`. -/
theorem stallB_iff (p : Params) (t : Nat) (A : List Agent) (a : Agent) : stallB p t A a = true ↔ Stall p t A a := by
  unfold stallB Stall hungB
  cases h : a.inflight with
  | none => simp
  | some f => cases waitTool f.tool <;> cases hasLiveChild p t A a <;> simp

/-- An agent's state: done once stopped; else gone when silent for more than `goneAfterMin`; else parked (a teammate
waiting for a message on purpose); else stalled when the stall test holds; else idle after `idleMin` minutes without an
event; else active.
-/
def state (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : State :=
  if stopped p now a then .done
  else if goneB p now a then .gone
  else if parkedB a then .parked
  else if stallB p now agents a then .stalled
  else if p.idleMin * msPerMin ≤ now - a.lastAt then .idle
  else .active

/-- Done exactly when stopped. -/
theorem state_done (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .done ↔ stopped p t a = true := by
  unfold state
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Gone exactly when not stopped and gone. -/
theorem state_gone (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .gone ↔ stopped p t a = false ∧ goneB p t a = true := by
  unfold state
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Parked exactly when not ended and parked. -/
theorem state_parked (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .parked ↔ ended p t a = false ∧ parkedB a = true := by
  unfold state ended
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Stalled exactly when not ended, not parked and the stall condition holds. -/
theorem state_stalled (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .stalled ↔ ended p t a = false ∧ parkedB a = false ∧ Stall p t A a := by
  rw [← stallB_iff]
  unfold state ended
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Idle exactly when not ended, not parked, not stalled and without an event for `idleMin` minutes. -/
theorem state_idle (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .idle ↔ ended p t a = false ∧ parkedB a = false ∧ ¬ Stall p t A a ∧
      p.idleMin * msPerMin ≤ t - a.lastAt := by
  rw [← stallB_iff]
  unfold state ended
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp_all

/-- Active exactly when not ended, not parked, not stalled and with an event within `idleMin` minutes. -/
theorem state_active (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .active ↔ ended p t a = false ∧ parkedB a = false ∧ ¬ Stall p t A a ∧
      t - a.lastAt < p.idleMin * msPerMin := by
  rw [← stallB_iff]
  unfold state ended
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp_all <;> omega

/-- Every agent has exactly one state: the state is one of the six, and two different states never hold together
(with `state_done` … `state_active`, the six rule conditions partition all agents).
-/
theorem state_cases (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    (state p t A a = .active ∨ state p t A a = .idle ∨ state p t A a = .parked ∨ state p t A a = .stalled ∨
      state p t A a = .gone ∨ state p t A a = .done) ∧
    ∀ s s' : State, state p t A a = s → state p t A a = s' → s = s' := by
  refine ⟨?_, fun s s' h h' => h ▸ h'⟩
  cases state p t A a <;> simp

/-- A stalled agent is not parked, and it has had no event for at least `stallMin` minutes. -/
theorem stalled_facts (p : Params) (t : Nat) (A : List Agent) (a : Agent) (h : state p t A a = .stalled) :
    parkedB a = false ∧ p.stallMin * msPerMin ≤ t - a.lastAt := by
  obtain ⟨_, hw, hs, _⟩ := (state_stalled p t A a).1 h
  exact ⟨hw, hs⟩

/-! ## Alerts -/

/-- The alert codes, listed in the order of their wire names. -/
inductive Code where
  | ctxHigh | ctxWarn | errStreak | gone | stalled | toolHang | toolSlow
  | ciFailed | ciFinished | ciSlow | dockerOrphan | procLong | reviewFeedback | simLockLong | simLockOrphan | stepQuestion | svcStale | svcSweepError | svcUnknown | sysContended | diskLow | ghDegraded | loadHigh
  | memCritical | overCap | permissionWait | worktreesMany
deriving DecidableEq, Repr

/-- Every code, in rank order. -/
def Code.all : List Code :=
  [.ctxHigh, .ctxWarn, .errStreak, .gone, .stalled, .toolHang, .toolSlow,
   .ciFailed, .ciFinished, .ciSlow, .dockerOrphan, .procLong, .reviewFeedback, .simLockLong, .simLockOrphan, .stepQuestion, .svcStale, .svcSweepError, .svcUnknown, .sysContended, .diskLow, .ghDegraded, .loadHigh,
   .memCritical, .overCap, .permissionWait, .worktreesMany]

/-- The wire name of a code. -/
def Code.name : Code → String
  | .ctxHigh => "agent.ctxHigh" | .ctxWarn => "agent.ctxWarn" | .errStreak => "agent.errStreak"
  | .gone => "agent.gone" | .stalled => "agent.stalled" | .toolHang => "agent.toolHang"
  | .toolSlow => "agent.toolSlow" | .ciFailed => "ci.failed" | .ciFinished => "ci.finished" | .ciSlow => "ci.slow"
  | .dockerOrphan => "docker.orphan" | .procLong => "proc.long" | .reviewFeedback => "review.feedback" | .simLockLong => "sim.lockLong"
  | .simLockOrphan => "sim.lockOrphan" | .stepQuestion => "step.question" | .svcStale => "svc.stale" | .svcSweepError => "svc.sweepError" | .svcUnknown => "svc.unknown" | .sysContended => "sys.contended" | .diskLow => "sys.diskLow" | .ghDegraded => "sys.ghDegraded" | .loadHigh => "sys.loadHigh"
  | .memCritical => "sys.memCritical" | .overCap => "team.overCap" | .permissionWait => "team.permissionWait"
  | .worktreesMany => "worktrees.many"

/-- The rank of a code (its position in `Code.all`). -/
def Code.rank : Code → Nat
  | .ctxHigh => 0 | .ctxWarn => 1 | .errStreak => 2 | .gone => 3 | .stalled => 4 | .toolHang => 5 | .toolSlow => 6
  | .ciFailed => 7 | .ciFinished => 8 | .ciSlow => 9 | .dockerOrphan => 10 | .procLong => 11 | .reviewFeedback => 12
  | .simLockLong => 13 | .simLockOrphan => 14 | .stepQuestion => 15 | .svcStale => 16 | .svcSweepError => 17 | .svcUnknown => 18
  | .sysContended => 19 | .diskLow => 20 | .ghDegraded => 21 | .loadHigh => 22
  | .memCritical => 23 | .overCap => 24 | .permissionWait => 25 | .worktreesMany => 26

/-- Whether a code is about one agent (`agent.*`). -/
def Code.isAgent (c : Code) : Bool := c.rank < 7

/-- The rank determines the code. -/
theorem Code.rank_inj (c c' : Code) (h : c.rank = c'.rank) : c = c' := by
  cases c <;> cases c' <;> simp_all [Code.rank]

/-- Rank order is the order of the wire names: the names in rank order are strictly increasing strings. -/
theorem Code.names_sorted : (Code.all.map Code.name).Pairwise (· < ·) := by decide

/-- An alert: its code, its subject (an agent id, `team`, `lead`, `disk`, `memory`, `load`, `sim`, `workflow@branch`,
a container name, `name#pid` of a process or `worktrees`), a detail text built from measured values only (never from a
threshold), and whether it is tied to the critical path.
-/
structure Alert where
  code    : Code
  subject : String
  detail  : String
  crit    : Bool := false
deriving DecidableEq, Repr

/-- The order within one criticality: by code rank, then subject, then detail (strings lexicographic). -/
def Alert.Lt0 (x y : Alert) : Prop :=
  x.code.rank < y.code.rank ∨
    (x.code.rank = y.code.rank ∧ (x.subject < y.subject ∨ (x.subject = y.subject ∧ x.detail < y.detail)))

/-- The output order: critical alerts first, then by code rank, subject and detail. -/
def Alert.Lt (x y : Alert) : Prop :=
  (x.crit = true ∧ y.crit = false) ∨ (x.crit = y.crit ∧ Alert.Lt0 x y)

instance (x y : Alert) : Decidable (Alert.Lt0 x y) := by unfold Alert.Lt0; infer_instance
instance (x y : Alert) : Decidable (Alert.Lt x y) := by unfold Alert.Lt; infer_instance

/-- The order is irreflexive. -/
theorem Alert.lt_irrefl (x : Alert) : ¬ Alert.Lt x x := by
  unfold Alert.Lt Alert.Lt0
  have := String.lt_irrefl x.subject
  have := String.lt_irrefl x.detail
  cases x.crit <;> simp_all

/-- The order within one criticality is transitive. -/
theorem Alert.lt0_trans {x y z : Alert} (h₁ : Alert.Lt0 x y) (h₂ : Alert.Lt0 y z) : Alert.Lt0 x z := by
  unfold Alert.Lt0 at *
  rcases h₁ with h₁ | ⟨r₁, h₁ | ⟨s₁, d₁⟩⟩ <;> rcases h₂ with h₂ | ⟨r₂, h₂ | ⟨s₂, d₂⟩⟩
  · exact .inl (Nat.lt_trans h₁ h₂)
  · exact .inl (r₂ ▸ h₁)
  · exact .inl (r₂ ▸ h₁)
  · exact .inl (r₁ ▸ h₂)
  · exact .inr ⟨r₁.trans r₂, .inl (String.lt_trans h₁ h₂)⟩
  · exact .inr ⟨r₁.trans r₂, .inl (s₂ ▸ h₁)⟩
  · exact .inl (r₁ ▸ h₂)
  · exact .inr ⟨r₁.trans r₂, .inl (s₁ ▸ h₂)⟩
  · exact .inr ⟨r₁.trans r₂, .inr ⟨s₁.trans s₂, String.lt_trans d₁ d₂⟩⟩

/-- The order is transitive. -/
theorem Alert.lt_trans {x y z : Alert} (h₁ : Alert.Lt x y) (h₂ : Alert.Lt y z) : Alert.Lt x z := by
  unfold Alert.Lt at *
  rcases h₁ with ⟨a₁, b₁⟩ | ⟨e₁, l₁⟩ <;> rcases h₂ with ⟨a₂, b₂⟩ | ⟨e₂, l₂⟩
  · rw [b₁] at a₂; cases a₂
  · exact .inl ⟨a₁, e₂ ▸ b₁⟩
  · exact .inl ⟨e₁ ▸ a₂, b₂⟩
  · exact .inr ⟨e₁.trans e₂, Alert.lt0_trans l₁ l₂⟩

/-- Two different strings are ordered one way or the other. -/
theorem str_trich {a b : String} (h : a ≠ b) : a < b ∨ b < a := by
  by_cases h₁ : a < b
  · exact .inl h₁
  · by_cases h₂ : b < a
    · exact .inr h₂
    · exact absurd (String.le_antisymm (String.not_lt.1 h₂) (String.not_lt.1 h₁)) h

/-- The order is total on different alerts. -/
theorem Alert.lt_trich {x y : Alert} (h : x ≠ y) : Alert.Lt x y ∨ Alert.Lt y x := by
  obtain ⟨c, s, d, k⟩ := x
  obtain ⟨c', s', d', k'⟩ := y
  unfold Alert.Lt Alert.Lt0
  simp only
  by_cases hk : k = k'
  · subst hk
    by_cases hr : c.rank = c'.rank
    · have hc := Code.rank_inj c c' hr
      subst hc
      by_cases hs : s = s'
      · subst hs
        have hd : d ≠ d' := fun e => h (e ▸ rfl)
        rcases str_trich hd with l | l
        · exact .inl (.inr ⟨rfl, .inr ⟨rfl, .inr ⟨rfl, l⟩⟩⟩)
        · exact .inr (.inr ⟨rfl, .inr ⟨rfl, .inr ⟨rfl, l⟩⟩⟩)
      · rcases str_trich hs with l | l
        · exact .inl (.inr ⟨rfl, .inr ⟨rfl, .inl l⟩⟩)
        · exact .inr (.inr ⟨rfl, .inr ⟨rfl, .inl l⟩⟩)
    · rcases Nat.lt_or_gt_of_ne hr with l | l
      · exact .inl (.inr ⟨rfl, .inl l⟩)
      · exact .inr (.inr ⟨rfl, .inl l⟩)
  · cases k <;> cases k' <;> simp_all

/-- Insert into a strictly sorted list, dropping an exact duplicate. -/
def ins (x : Alert) : List Alert → List Alert
  | [] => [x]
  | y :: ys => if Alert.Lt x y then x :: y :: ys else if x = y then y :: ys else y :: ins x ys

/-- Sort and deduplicate: insert every element into the empty list. -/
def sortU (l : List Alert) : List Alert := l.foldr ins []

/-- Insertion adds exactly its element. -/
theorem mem_ins (x z : Alert) (l : List Alert) : z ∈ ins x l ↔ z = x ∨ z ∈ l := by
  induction l with
  | nil => simp [ins]
  | cons y ys ih =>
    unfold ins
    split
    · simp
    · split
      · rename_i h; subst h; simp
      · simp only [List.mem_cons, ih]; constructor <;> intro h <;> rcases h with h | h | h <;> simp [h]

/-- Insertion keeps a list strictly sorted. -/
theorem sorted_ins (x : Alert) (l : List Alert) (h : l.Pairwise Alert.Lt) : (ins x l).Pairwise Alert.Lt := by
  induction l with
  | nil => simp [ins]
  | cons y ys ih =>
    rw [List.pairwise_cons] at h
    unfold ins
    split
    · rename_i hxy
      refine List.pairwise_cons.2 ⟨?_, List.pairwise_cons.2 h⟩
      intro z hz
      rcases List.mem_cons.1 hz with e | hz
      · exact e ▸ hxy
      · exact Alert.lt_trans hxy (h.1 z hz)
    · split
      · exact List.pairwise_cons.2 h
      · rename_i hlt hne
        have hyx : Alert.Lt y x := (Alert.lt_trich hne).resolve_left hlt
        refine List.pairwise_cons.2 ⟨?_, ih h.2⟩
        intro z hz
        rcases (mem_ins x z ys).1 hz with e | hz
        · exact e ▸ hyx
        · exact h.1 z hz

/-- `sortU` keeps exactly the members. -/
theorem mem_sortU (z : Alert) (l : List Alert) : z ∈ sortU l ↔ z ∈ l := by
  induction l with
  | nil => simp [sortU]
  | cons y ys ih => simp only [sortU, List.foldr_cons] at *; rw [mem_ins, ih]; simp

/-- `sortU` is strictly sorted. -/
theorem sorted_sortU (l : List Alert) : (sortU l).Pairwise Alert.Lt := by
  induction l with
  | nil => simp [sortU]
  | cons y ys ih => exact sorted_ins y _ ih

/-- Two strictly sorted lists with the same members are equal. -/
theorem eq_of_sorted (l l' : List Alert) (h : l.Pairwise Alert.Lt) (h' : l'.Pairwise Alert.Lt)
    (hm : ∀ z, z ∈ l ↔ z ∈ l') : l = l' := by
  induction l generalizing l' with
  | nil =>
    cases l' with
    | nil => rfl
    | cons b bs => exact absurd ((hm b).2 (List.mem_cons_self ..)) (by simp)
  | cons a as ih =>
    cases l' with
    | nil => exact absurd ((hm a).1 (List.mem_cons_self ..)) (by simp)
    | cons b bs =>
      rw [List.pairwise_cons] at h h'
      have hab : a = b := by
        rcases List.mem_cons.1 ((hm a).1 (List.mem_cons_self ..)) with e | ha
        · exact e
        · rcases List.mem_cons.1 ((hm b).2 (List.mem_cons_self ..)) with e | hb
          · exact e.symm
          · exact absurd (Alert.lt_trans (h.1 b hb) (h'.1 a ha)) (Alert.lt_irrefl a)
      subst hab
      have hrest : ∀ z, z ∈ as ↔ z ∈ bs := by
        intro z
        constructor
        · intro hz
          rcases List.mem_cons.1 ((hm z).1 (List.mem_cons_of_mem _ hz)) with e | hz'
          · exact absurd (e ▸ h.1 z hz) (Alert.lt_irrefl a)
          · exact hz'
        · intro hz
          rcases List.mem_cons.1 ((hm z).2 (List.mem_cons_of_mem _ hz)) with e | hz'
          · exact absurd (e ▸ h'.1 z hz) (Alert.lt_irrefl a)
          · exact hz'
      rw [ih bs h.2 h'.2 hrest]

/-- An alert if the condition holds, else nothing. -/
def when (b : Bool) (x : Alert) : List Alert := if b then [x] else []

/-- Membership in `when`. -/
theorem mem_when (b : Bool) (x z : Alert) : z ∈ when b x ↔ b = true ∧ z = x := by
  cases b <;> simp [when]

/-- Whole minutes in a duration (for alert details). -/
def mins (d : Nat) : Nat := d / msPerMin

/-- Whether the tool call in flight is slow: it has run for strictly more than `toolSlowMin` minutes and it is not a
wait (an `Agent` or `SendMessage` call while a child of the agent is live).
-/
def slowB (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Bool :=
  match a.inflight with
  | none => false
  | some f => !(waitTool f.tool && hasLiveChild p now agents a) && decide (p.toolSlowMin * msPerMin < now - f.since)

/-- The detail text of a tool call in flight: its tool and whole minutes running (empty when none is in flight). -/
def toolDetail (now : Nat) (a : Agent) : String :=
  match a.inflight with
  | some f => s!"{f.tool} running for {mins (now - f.since)} min"
  | none => ""

/-- The `agent.*` alerts of one live agent (none once it has ended, i.e. stopped or gone, or is parked), in code
order: context over `ctxResumeMax` (do not resume it), context over `ctxWarn`, at least `errStreak` (and at least one)
failed calls in a row, stalled, a tool hung, a tool slow. An unknown context size counts as 0. Every alert has
`crit = false` here (`agentAll` marks it).
-/
def agentAlerts (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : List Alert :=
  if ended p now a || parkedB a then [] else
  let ctx := a.ctxTokens.getD 0
  when (decide (p.ctxResumeMax < ctx)) ⟨.ctxHigh, a.id, s!"{ctx} context tokens", false⟩ ++
  when (decide (p.ctxWarn < ctx)) ⟨.ctxWarn, a.id, s!"{ctx} context tokens", false⟩ ++
  when (decide (0 < a.errTail ∧ p.errStreak ≤ a.errTail))
    ⟨.errStreak, a.id, s!"{a.errTail} failed tool calls in a row", false⟩ ++
  when (stallB p now agents a) ⟨.stalled, a.id, s!"no event for {mins (now - a.lastAt)} min", false⟩ ++
  when (hungB p now agents a) ⟨.toolHang, a.id, toolDetail now a, false⟩ ++
  when (slowB p now agents a) ⟨.toolSlow, a.id, toolDetail now a, false⟩

/-- Whether an agent became gone since the previous check: always on the first check (no previous check), else when
it was not gone at the previous check's time.
-/
def newGone (p : Params) (prev : Option Nat) (a : Agent) : Bool :=
  match prev with
  | none => true
  | some q => !goneB p q a

/-- The `agent.gone` alert of an agent: raised once, at the first check where the agent is gone (state `gone`) and the
previous check did not see it gone.
-/
def goneAlert (p : Params) (o : Obs) (a : Agent) : List Alert :=
  when (!stopped p o.now a && goneB p o.now a && newGone p o.prevAt a)
    ⟨.gone, a.id, s!"no event for {mins (o.now - a.lastAt)} min", false⟩

/-- Whether a string is tied to a task id: it equals the id, or the id followed by `-` and one or more decimal digits
(a respawned agent `task-2`).
-/
def tiedTo (c s : String) : Bool :=
  s == c ||
    (let pre := (c ++ "-").toList
     let l := s.toList
     l.take pre.length == pre && !(l.drop pre.length).isEmpty && (l.drop pre.length).all Char.isDigit)

/-- Whether an agent works on a critical-path task: its id, name or task is tied to a task id of `K`. -/
def critAgent (K : List String) (a : Agent) : Bool :=
  K.any fun c => tiedTo c a.id || a.name.any (tiedTo c) || a.task.any (tiedTo c)

/-- Whether a CI run belongs to a critical-path task: its branch is tied to `ci/` followed by a task id of `K`. -/
def critCi (K : List String) (r : CiRun) : Bool := K.any fun c => tiedTo ("ci/" ++ c) r.branch

/-- Set an alert's critical flag. -/
def mark (k : Bool) (x : Alert) : Alert := { x with crit := k }

/-- Every `agent.*` alert of one agent: its `agent.gone` alert and its live-agent alerts, each marked critical when
the agent works on a critical-path task.
-/
def agentAll (p : Params) (o : Obs) (a : Agent) : List Alert :=
  (goneAlert p o a ++ agentAlerts p o.now o.agents a).map (mark (critAgent o.critical a))

/-- A done, gone or parked agent raises no live-agent alert. -/
theorem agentAlerts_quiet (p : Params) (t : Nat) (A : List Agent) (a : Agent)
    (h : state p t A a = .done ∨ state p t A a = .gone ∨ state p t A a = .parked) : agentAlerts p t A a = [] := by
  unfold agentAlerts
  rcases h with h | h | h
  · simp [ended, (state_done p t A a).1 h]
  · simp [ended, ((state_gone p t A a).1 h).2]
  · simp [((state_parked p t A a).1 h).2]

/-- A live-agent alert of an agent is an `agent.*` alert about that agent, not critical. -/
theorem agentAlerts_subject (p : Params) (t : Nat) (A : List Agent) (a : Agent) (x : Alert)
    (h : x ∈ agentAlerts p t A a) : x.code.isAgent = true ∧ x.subject = a.id ∧ x.crit = false := by
  unfold agentAlerts at h
  split at h
  · simp at h
  · simp only [List.mem_append, mem_when] at h
    rcases h with ((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩ <;> subst e <;>
      simp [Code.isAgent, Code.rank]

/-- A live-agent alert is never `agent.gone`. -/
theorem agentAlerts_not_gone (p : Params) (t : Nat) (A : List Agent) (a : Agent) (x : Alert)
    (h : x ∈ agentAlerts p t A a) : x.code ≠ .gone := by
  unfold agentAlerts at h
  split at h
  · simp at h
  · simp only [List.mem_append, mem_when] at h
    rcases h with ((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩ <;> subst e <;> simp

/-- Every alert of an agent (`agentAll`) is an `agent.*` alert about that agent. -/
theorem agentAll_subject (p : Params) (o : Obs) (a : Agent) (x : Alert) (h : x ∈ agentAll p o a) :
    x.code.isAgent = true ∧ x.subject = a.id := by
  unfold agentAll at h
  obtain ⟨y, hy, e⟩ := List.mem_map.1 h
  subst e
  rcases List.mem_append.1 hy with hy | hy
  · unfold goneAlert at hy
    obtain ⟨_, e⟩ := (mem_when _ _ _).1 hy
    subst e
    simp [mark, Code.isAgent, Code.rank]
  · have := agentAlerts_subject p o.now o.agents a y hy
    exact ⟨this.1, this.2.1⟩

/-- A gone agent raises only `agent.gone`: every alert of a gone agent has that code. -/
theorem gone_alerts (p : Params) (o : Obs) (a : Agent) (h : state p o.now o.agents a = .gone) (x : Alert)
    (hx : x ∈ agentAll p o a) : x.code = .gone := by
  unfold agentAll at hx
  rw [agentAlerts_quiet p o.now o.agents a (.inr (.inl h)), List.append_nil] at hx
  obtain ⟨y, hy, e⟩ := List.mem_map.1 hx
  subst e
  unfold goneAlert at hy
  obtain ⟨_, e⟩ := (mem_when _ _ _).1 hy
  subst e
  rfl

/-- `agent.gone` is raised for an agent exactly when its state is gone and it was not gone at the previous check (or
there was none).
-/
theorem goneAlert_iff (p : Params) (o : Obs) (a : Agent) :
    (∃ x ∈ agentAll p o a, x.code = .gone) ↔ state p o.now o.agents a = .gone ∧ newGone p o.prevAt a = true := by
  rw [state_gone]
  constructor
  · rintro ⟨x, hx, hc⟩
    unfold agentAll at hx
    obtain ⟨y, hy, e⟩ := List.mem_map.1 hx
    subst e
    rcases List.mem_append.1 hy with hy | hy
    · unfold goneAlert at hy
      obtain ⟨b, _⟩ := (mem_when _ _ _).1 hy
      simp only [Bool.and_eq_true, Bool.not_eq_true'] at b
      exact ⟨⟨b.1.1, b.1.2⟩, b.2⟩
    · simp only [mark] at hc
      exact absurd hc (agentAlerts_not_gone p o.now o.agents a y hy)
  · rintro ⟨⟨hs, hg⟩, hn⟩
    refine ⟨mark (critAgent o.critical a) ⟨.gone, a.id, s!"no event for {mins (o.now - a.lastAt)} min", false⟩, ?_, rfl⟩
    unfold agentAll goneAlert
    simp [hs, hg, hn, when]

/-- An `Agent` or `SendMessage` call in flight while a child of the agent is live is a wait, not a hang: the tool
has not hung and is not slow, the agent is not stalled, and it raises neither `agent.toolHang` nor `agent.toolSlow`.
-/
theorem wait_not_hang (p : Params) (t : Nat) (A : List Agent) (a : Agent) (f : Inflight)
    (hf : a.inflight = some f) (hw : waitTool f.tool = true) (hc : hasLiveChild p t A a = true) :
    hungB p t A a = false ∧ slowB p t A a = false ∧ state p t A a ≠ .stalled ∧
      ∀ x ∈ agentAlerts p t A a, x.code ≠ .toolHang ∧ x.code ≠ .toolSlow := by
  have hh : hungB p t A a = false := by unfold hungB; simp [hf, hw, hc]
  have hs : slowB p t A a = false := by unfold slowB; simp [hf, hw, hc]
  refine ⟨hh, hs, ?_, ?_⟩
  · intro hst
    obtain ⟨_, _, _, h⟩ := (state_stalled p t A a).1 hst
    exact (h f hf).1 ⟨hw, hc⟩
  · intro x hx
    unfold agentAlerts at hx
    split at hx
    · simp at hx
    · simp only [List.mem_append, mem_when, hh, hs] at hx
      rcases hx with ((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨b, _⟩) | ⟨b, _⟩ <;>
        first | (subst e; simp) | simp at b

/-- Whether a lock owner string names an agent: its id, name or task. -/
def names (h : String) (a : Agent) : Bool := a.id == h || a.name == some h || a.task == some h

/-- Whether the simulator lock is orphaned: it has a holder and no live agent is named by it. -/
def orphanB (p : Params) (now : Nat) (agents : List Agent) (l : SimLock) : Bool :=
  match l.holder with
  | none => false
  | some h => !agents.any fun a => live p now a && names h a

/-- A CI conclusion that counts as a failure. -/
def ciFailing (r : CiRun) : Bool :=
  r.conclusion == some "failure" || r.conclusion == some "timed_out" || r.conclusion == some "startup_failure"

/-- Whether a run is the latest of its workflow and branch (no run of the same pair started later). -/
def ciLatest (runs : List CiRun) (r : CiRun) : Bool :=
  runs.all fun r' => !(r'.workflow == r.workflow && r'.branch == r.branch) || decide (r'.startedAt ≤ r.startedAt)

/-- Whether a run is waiting or running (status queued, in_progress, waiting, requested or pending). -/
def ciRunning (r : CiRun) : Bool :=
  r.status == "queued" || r.status == "in_progress" || r.status == "waiting" || r.status == "requested" ||
    r.status == "pending"

/-- Whether a run is slow: waiting or running for strictly more than the workflow's limit `s_p(wf(r))` minutes since it started. -/
def ciSlowB (p : Params) (now : Nat) (r : CiRun) : Bool :=
  ciRunning r && decide (ciSlowFor p r.workflow * msPerMin < now - r.startedAt)

/-- Whether a run that the previous check flagged as slow has finished since: it is completed, it ended after the
previous check's time `q`, and at `q` it had run for strictly more than the workflow's limit `s_p(wf(r))` minutes (so it was still running
at `q` and `ci.slow` was raised). False on the first check or without an end time.
-/
def ciFinishedB (p : Params) (prev : Option Nat) (r : CiRun) : Bool :=
  match prev, r.endedAt with
  | some q, some e => r.status == "completed" && decide (q < e) && decide (ciSlowFor p r.workflow * msPerMin < q - r.startedAt)
  | _, _ => false

/-- Whether a container is orphaned: no live agent started at or before it (so none could have started it). -/
def dockerOrphanB (p : Params) (now : Nat) (agents : List Agent) (c : Container) : Bool :=
  !agents.any fun a => live p now a && decide (a.startedAt ≤ c.startedAt)

/-- The checked-in allowlist of programs that run for the whole session on purpose: `caffeinate` (keeps the Mac awake).
A change to it is a reviewed edit of this file.
-/
def keepProgs : List String := ["caffeinate"]

/-- Whether a process tree is an intended long-runner: its name is on the allowlist `keepProgs`, or one of its pids
(root included) is a service pid or a pid the lead declared (`fw watch --keep`).
-/
def declaredB (services keep : List Nat) (q : Proc) : Bool :=
  keepProgs.contains q.name || (q.pid :: q.pids).any fun x => services.contains x || keep.contains x

/-- Whether the agent whose Bash call started a process tree is live (false when the tree has no owner, i.e. the lead
started it or the owner is not known, and when the owner is not in the agent list).
-/
def ownerLiveB (p : Params) (now : Nat) (agents : List Agent) (q : Proc) : Bool :=
  match q.agent with
  | none => false
  | some g => agents.any fun a => a.id == g && live p now a

/-- Whether a process tree runs too long: it is not an intended long-runner, the agent that started it is not live
(the lead's own trees, and orphans of ended or gone agents), and it has been alive for strictly more than `procMaxMin`
minutes.
-/
def procLongB (p : Params) (o : Obs) (q : Proc) : Bool :=
  !declaredB o.system.services o.system.keep q && !ownerLiveB p o.now o.agents q &&
    decide (p.procMaxMin * msPerMin < o.now - q.startedAt)

/-- The number of live agents other than the lead session. -/
def nLive (p : Params) (now : Nat) (agents : List Agent) : Nat :=
  (agents.filter fun a => live p now a && a.kind != .lead).length

/-- A gone agent does not count as live: adding it to the list leaves `nLive` (and so `team.overCap`) unchanged. -/
theorem nLive_gone (p : Params) (t : Nat) (A : List Agent) (a : Agent) (h : goneB p t a = true) :
    live p t a = false ∧ nLive p t (a :: A) = nLive p t A := by
  have hl : live p t a = false := by simp [live, ended, h]
  exact ⟨hl, by simp [nLive, hl]⟩

/-- The number of live agents of one kind. -/
def nKind (p : Params) (now : Nat) (agents : List Agent) (k : Kind) : Nat :=
  (agents.filter fun a => live p now a && a.kind == k).length

/-- The number of live non-lead agents spawned by another agent (helpers: they have a parent id). -/
def nHelpers (p : Params) (now : Nat) (agents : List Agent) : Nat :=
  (agents.filter fun a => live p now a && a.kind != .lead && a.parent.isSome).length

/-- Whether a permission prompt may be open in the lead's terminal: a notification exists and it is newer than the
lead session's last finished tool call (any notification counts when no tool call has finished).
-/
def permB (l : Lead) : Bool :=
  match l.noteAt with
  | none => false
  | some n => match l.lastToolAt with
    | none => true
    | some s => decide (s < n)

/-! ### Team and system alerts, one piece per code -/

/-- `team.overCap`: more live non-lead agents than `agentCap` (the detail counts them by kind and counts the helpers). -/
def sOver (p : Params) (o : Obs) : List Alert :=
  when (decide (p.agentCap < nLive p o.now o.agents)) ⟨.overCap, "team",
    s!"{nLive p o.now o.agents} live agents: {nKind p o.now o.agents .teammate} teammate, {nKind p o.now o.agents .subagent} subagent, {nKind p o.now o.agents .workflow} workflow; {nHelpers p o.now o.agents} with a parent agent", false⟩

/-- `sys.diskLow`: free disk strictly below `diskMinGB`. -/
def sDisk (p : Params) (o : Obs) : List Alert :=
  when (decide (o.system.diskFreeGB < p.diskMinGB)) ⟨.diskLow, "disk", s!"{o.system.diskFreeGB} GB free", false⟩

/-- `sys.memCritical`: memory pressure critical. -/
def sMem (o : Obs) : List Alert :=
  when (o.system.memPressure == .critical) ⟨.memCritical, "memory", "memory pressure critical", false⟩

/-- `sys.loadHigh`: the floor of the 1-min load average at or above `loadMax`. -/
def sLoad (p : Params) (o : Obs) : List Alert :=
  when (decide (p.loadMax ≤ o.system.loadFloor))
    ⟨.loadHigh, "load", s!"load average {o.system.loadFloor} (1 min, floor)", false⟩

/-- Is the machine contended now: above `contendedLoad`, or open since the previous check and still above `calmLoad`. -/
def contendedNow (o : Obs) : Bool :=
  decide (Fw.Obs.Timing.contendedLoad < o.system.loadFloor) ||
    (o.system.load.prevContended && decide (Fw.Obs.Timing.calmLoad < o.system.loadFloor))

/-- `sys.contended` (task `local-mem-budget`), with hysteresis: it opens when the floor of the 1-min load average is strictly
above `Fw.Obs.Timing.contendedLoad` (the test that makes a local timing sample `contended`) and, once open (the previous
check raised it), stays open until the floor is at or below `Fw.Obs.Timing.calmLoad`. A load that wobbles around 8 is one
open alert, not a new OPEN line at every crossing (alert key `code|subject`). One signal for the whole machine, with the
builders and heavy jobs that run, in place of one `timing.slow` per step the load slowed.
-/
def sContended (o : Obs) : List Alert :=
  when (contendedNow o)
    ⟨.sysContended, "load",
      s!"load average {o.system.loadFloor} (1 min, floor) over {Fw.Obs.Timing.contendedLoad} CPUs; {o.system.load.builders} builders, {o.system.load.heavyJobs} heavy jobs", false⟩

/-- `sim.lockLong`: the simulator lock has a holder and a start time and has been held for `simLockMaxMin` minutes. -/
def sLockLong (p : Params) (o : Obs) : List Alert :=
  when (o.system.simLock.holder.isSome &&
      o.system.simLock.since.any fun s => decide (p.simLockMaxMin * msPerMin ≤ o.now - s))
    ⟨.simLockLong, "sim",
      s!"held by {o.system.simLock.holder.getD ""} for {mins (o.now - o.system.simLock.since.getD 0)} min", false⟩

/-- `sim.lockOrphan`: the simulator lock is orphaned. -/
def sOrphan (p : Params) (o : Obs) : List Alert :=
  when (orphanB p o.now o.agents o.system.simLock)
    ⟨.simLockOrphan, "sim", s!"held by {o.system.simLock.holder.getD ""}", false⟩

/-- The list without repeats with `n` steps of fuel, each element kept at its first position. -/
def dedupN {α : Type} [DecidableEq α] : Nat → List α → List α
  | 0, _ => []
  | _ + 1, [] => []
  | n + 1, x :: xs => x :: dedupN n (xs.filter fun y => decide (y ≠ x))

/-- The list without repeats, each element kept at its first position (fuel: the length). -/
def dedupFirst {α : Type} [DecidableEq α] (l : List α) : List α := dedupN l.length l

/-- With enough fuel membership is unchanged. -/
theorem mem_dedupN {α : Type} [DecidableEq α] : ∀ (n : Nat) (l : List α), l.length ≤ n → ∀ y, y ∈ dedupN n l ↔ y ∈ l
  | 0, [], _, y => by simp [dedupN]
  | 0, _ :: _, h, _ => by simp at h
  | _ + 1, [], _, y => by simp [dedupN]
  | n + 1, x :: xs, h, y => by
    have hf : (xs.filter fun y => decide (y ≠ x)).length ≤ n := by
      have := List.length_filter_le (fun y => decide (y ≠ x)) xs
      simp only [List.length_cons] at h; omega
    simp only [dedupN, List.mem_cons, mem_dedupN n _ hf y, List.mem_filter, decide_eq_true_eq]
    by_cases hy : y = x <;> simp [hy]

/-- With enough fuel there is no repeated element. -/
theorem nodup_dedupN {α : Type} [DecidableEq α] : ∀ (n : Nat) (l : List α), l.length ≤ n → (dedupN n l).Nodup
  | 0, [], _ => by simp [dedupN]
  | 0, _ :: _, h => by simp at h
  | _ + 1, [], _ => by simp [dedupN]
  | n + 1, x :: xs, h => by
    have hf : (xs.filter fun y => decide (y ≠ x)).length ≤ n := by
      have := List.length_filter_le (fun y => decide (y ≠ x)) xs
      simp only [List.length_cons] at h; omega
    simp only [dedupN, List.nodup_cons]
    refine ⟨fun hm => ?_, nodup_dedupN n _ hf⟩
    have := (mem_dedupN n _ hf x).1 hm
    simp at this

/-- `dedupFirst` keeps membership. -/
theorem mem_dedupFirst {α : Type} [DecidableEq α] (l : List α) (y : α) : y ∈ dedupFirst l ↔ y ∈ l :=
  mem_dedupN _ _ (Nat.le_refl _) y

/-- `dedupFirst` has no repeated element. -/
theorem nodup_dedupFirst {α : Type} [DecidableEq α] (l : List α) : (dedupFirst l).Nodup :=
  nodup_dedupN _ _ (Nat.le_refl _)

/-- **The set of a run**: the workflow, branch and commit it ran for. A push and the dispatches that follow it share one set
(`fw ci` dispatches `breakpoint-gate` once per engine, 3 to 7 s apart).
-/
def ciKey (r : CiRun) : String × String × String := (r.workflow, r.branch, r.headSha)

/-- The runs of a set. -/
def ciSet (runs : List CiRun) (k : String × String × String) : List CiRun :=
  runs.filter fun r => ciKey r == k

/-- **A set failed** (`ci.failed` per set): every run of the set is completed and one of them failed. A set with a run still
running (or queued) is pending, not failed.
-/
def ciSetFailed (runs : List CiRun) (k : String × String × String) : Bool :=
  (ciSet runs k).all (fun r => r.status == "completed") && (ciSet runs k).any ciFailing

/-- A set is the latest of its workflow and branch when it holds a latest run of that pair. -/
def ciSetLatest (runs : List CiRun) (k : String × String × String) : Bool :=
  (ciSet runs k).any (ciLatest runs)

/-- The sets that raise `ci.failed`: each distinct set once, in order of first appearance, when it failed and is the latest. -/
def ciFailedKeys (runs : List CiRun) : List (String × String × String) :=
  (dedupFirst (runs.map ciKey)).filter fun k => ciSetFailed runs k && ciSetLatest runs k

/-- `ci.failed`: the latest set of a workflow and branch failed (critical when the branch is a critical task's), once per set. -/
def sCiFailed (o : Obs) : List Alert :=
  (ciFailedKeys o.system.ci).map fun k =>
    let r := (ciSet o.system.ci k).find? ciFailing
    ⟨.ciFailed, s!"{k.1}@{k.2.1}", s!"latest run {(r.bind (·.conclusion)).getD ""}",
      critCi o.critical (r.getD { workflow := k.1, branch := k.2.1, status := "completed", startedAt := 0 })⟩

/-- **A set with a running run is pending** (`ciSetFailed_of_running`): while a run of the set is waiting or running, the
set has not failed, whatever its siblings concluded.
-/
theorem ciSetFailed_of_running (runs : List CiRun) (r : CiRun) (hr : r ∈ runs) (h : ciRunning r = true) :
    ciSetFailed runs (ciKey r) = false := by
  have hmem : r ∈ ciSet runs (ciKey r) := List.mem_filter.2 ⟨hr, by simp⟩
  have hs : (r.status == "completed") = false := by
    simp only [ciRunning, Bool.or_eq_true, beq_iff_eq] at h
    rcases h with ((((h | h) | h) | h) | h) <;> simp [h]
  have hall : (ciSet runs (ciKey r)).all (fun r => r.status == "completed") = false := by
    rw [Bool.eq_false_iff]
    intro hall
    have := List.all_eq_true.1 hall r hmem
    simp [hs] at this
  simp [ciSetFailed, hall]

/-- **A completed set fails iff one run failed** (`ciSetFailed_iff`): when every run of a set is completed, the set failed
exactly when some run of it failed.
-/
theorem ciSetFailed_iff (runs : List CiRun) (k : String × String × String)
    (h : ∀ r ∈ ciSet runs k, r.status = "completed") :
    ciSetFailed runs k = true ↔ ∃ r ∈ ciSet runs k, ciFailing r = true := by
  have ha : (ciSet runs k).all (fun r => r.status == "completed") = true := by
    simp only [List.all_eq_true, beq_iff_eq]; exact h
  simp [ciSetFailed, ha]

/-- **Once per set** (`ciFailedKeys_nodup`): no set is reported twice, however many of its runs failed. -/
theorem ciFailedKeys_nodup (runs : List CiRun) : (ciFailedKeys runs).Nodup :=
  (nodup_dedupFirst _).sublist List.filter_sublist

/-- One `ci.failed` alert per failed latest set (`sCiFailed_length`). -/
theorem sCiFailed_length (o : Obs) : (sCiFailed o).length = (ciFailedKeys o.system.ci).length := by
  simp [sCiFailed]

/-- **A failed latest set raises** (`ciSetFailed_raised`): the set of any run `r` that failed (all runs completed, one
failing) and is the latest of its pair has an alert with subject `workflow@branch`.
-/
theorem ciSetFailed_raised (o : Obs) (r : CiRun) (hr : r ∈ o.system.ci)
    (hf : ciSetFailed o.system.ci (ciKey r) = true) (hl : ciSetLatest o.system.ci (ciKey r) = true) :
    ∃ x ∈ sCiFailed o, x.code = .ciFailed ∧ x.subject = s!"{r.workflow}@{r.branch}" := by
  have hk : ciKey r ∈ ciFailedKeys o.system.ci :=
    List.mem_filter.2 ⟨(mem_dedupFirst _ _).2 (List.mem_map.2 ⟨r, hr, rfl⟩), by simp [hf, hl]⟩
  exact ⟨_, List.mem_map.2 ⟨ciKey r, hk, rfl⟩, rfl, rfl⟩

/-- A `ci.slow` alert while an Actions incident is open names it; outside one it is the plain detail. -/
def ciSlowAlert (o : Obs) (r : CiRun) : Alert :=
  ⟨.ciSlow, s!"{r.workflow}@{r.branch}",
    s!"{r.status} for {mins (o.now - r.startedAt)} min" ++ o.system.gh.suffix ++ o.system.gh.ciNote, critCi o.critical r⟩

/-- `ci.slow`: a run waiting or running for more than the workflow's limit `s_p(wf(r))` minutes. -/
def sCiSlow (p : Params) (o : Obs) : List Alert :=
  (o.system.ci.filter (ciSlowB p o.now)).map (ciSlowAlert o)

/-- `sys.ghDegraded`: Actions is flagged (not operational, or unknown after a flagged pass). -/
def sGh (o : Obs) : List Alert :=
  when o.system.gh.degradedB ⟨.ghDegraded, "github", o.system.gh.detail, false⟩

/-- The alert flag opens while Actions is not operational. -/
theorem sGh_opens (o : Obs) (h1 : o.system.gh.actions ≠ .operational) (h2 : o.system.gh.actions ≠ .unknown) :
    sGh o = [⟨.ghDegraded, "github", o.system.gh.detail, false⟩] := by
  have : o.system.gh.degradedB = true := ghOpenB_degraded _ _ h1 h2
  simp [sGh, when, this]

/-- The alert closes when Actions is operational again, whatever the previous pass said. -/
theorem sGh_closes (o : Obs) (h : o.system.gh.actions = .operational) : sGh o = [] := by
  have : o.system.gh.degradedB = false := by simp [Gh.degradedB, h, ghOpenB]
  simp [sGh, when, this]

/-- A failed fetch keeps the alert as the previous pass left it. -/
theorem sGh_unknown (o : Obs) (h : o.system.gh.actions = .unknown) :
    sGh o ≠ [] ↔ o.system.gh.prevDegraded = true := by
  have : o.system.gh.degradedB = o.system.gh.prevDegraded := by simp [Gh.degradedB, h, ghOpenB]
  cases hp : o.system.gh.prevDegraded <;> simp [sGh, when, this, hp]

/-- Outside an open Actions incident, with a fresh run list, a `ci.slow` alert is unchanged. -/
theorem ciSlowAlert_plain (o : Obs) (r : CiRun) (h : o.system.gh.incident = none)
    (hf : o.system.gh.ciAgeMs ≤ ciFreshMs) :
    (ciSlowAlert o r).detail = s!"{r.status} for {mins (o.now - r.startedAt)} min" := by
  simp [ciSlowAlert, Gh.suffix_none _ h, Gh.ciNote, ciAgeNote_fresh _ hf]

/-- **A stale run list is named** (`ciSlowAlert_ages`): when the list is older than `ciFreshMs`, the `ci.slow` detail
ends with its age in minutes. This is the fix for a finished run that still reads as running.
-/
theorem ciSlowAlert_ages (o : Obs) (r : CiRun) (h : ciFreshMs < o.system.gh.ciAgeMs) :
    ∃ a, (ciSlowAlert o r).detail = a ++ " (CI data " ++ toString (o.system.gh.ciAgeMs / 60000) ++ " min old)" := by
  refine ⟨s!"{r.status} for {mins (o.now - r.startedAt)} min" ++ o.system.gh.suffix, ?_⟩
  simp [ciSlowAlert, Gh.ciNote, ciAgeNote_old _ h, String.append_assoc]

/-- During an open Actions incident a `ci.slow` alert names it. -/
theorem ciSlowAlert_names (o : Obs) (r : CiRun) (i : GhIncident) (h : o.system.gh.incident = some i) :
    ∃ a b, (ciSlowAlert o r).detail = a ++ i.name ++ b := by
  obtain ⟨a, b, hs⟩ := Gh.suffix_names _ i h
  exact ⟨s!"{r.status} for {mins (o.now - r.startedAt)} min" ++ a, b ++ o.system.gh.ciNote, by
    simp [ciSlowAlert, hs, String.append_assoc]⟩

/-- `ci.finished`: a run flagged slow by the previous check has finished (once): its conclusion and duration. -/
def sCiFin (p : Params) (o : Obs) : List Alert :=
  (o.system.ci.filter (ciFinishedB p o.prevAt)).map fun r =>
    ⟨.ciFinished, s!"{r.workflow}@{r.branch}",
      s!"{r.conclusion.getD ""} after {mins (r.endedAt.getD 0 - r.startedAt)} min", critCi o.critical r⟩

/-- `docker.orphan`: an orphaned container. -/
def sDocker (p : Params) (o : Obs) : List Alert :=
  (o.system.docker.filter (dockerOrphanB p o.now o.agents)).map fun c =>
    ⟨.dockerOrphan, c.name, s!"container {c.id}", false⟩

/-- The `proc.long` alert of a process tree: subject `name#pid`, detail its age in whole minutes, plus the owner's
id when an agent started it (that agent is not live, so the tree is an orphan).
-/
def procAlert (o : Obs) (q : Proc) : Alert :=
  match q.agent with
  | none => ⟨.procLong, s!"{q.name}#{q.pid}", s!"alive {mins (o.now - q.startedAt)} min", false⟩
  | some g => ⟨.procLong, s!"{q.name}#{q.pid}", s!"alive {mins (o.now - q.startedAt)} min, agent {g} ended", false⟩

/-- Every `proc.long` alert has code `proc.long`. -/
theorem procAlert_code (o : Obs) (q : Proc) : (procAlert o q).code = .procLong := by
  unfold procAlert; cases q.agent <;> rfl

/-- `proc.long`: a process tree of the session alive too long, not declared, and not owned by a live agent. -/
def sProc (p : Params) (o : Obs) : List Alert :=
  (o.system.procs.filter (procLongB p o)).map (procAlert o)

def sFeedback (o : Obs) : List Alert :=
  (Fw.Console.Steps.reviewAlerts o.system.feedback).map fun fd => ⟨.reviewFeedback, fd.1, fd.2, false⟩

def sQuestion (o : Obs) : List Alert :=
  (Fw.Console.Steps.questionAlerts o.system.feedback).map fun fd => ⟨.stepQuestion, fd.1, fd.2, false⟩

/-- The `svc.stale` alert of a stale service: subject its name, detail the changed input paths (measured values). -/
def staleAlert (s : Svc) : Alert :=
  ⟨.svcStale, s.name, "changed on main since its commit: " ++ ", ".intercalate s.changed, false⟩

/-- `svc.stale`: one alert for each service with an input changed on `main` since its base commit. -/
def sStale (o : Obs) : List Alert :=
  (o.system.svcs.filter Svc.staleB).map staleAlert

/-- The `svc.sweepError` alert of a service whose drain caught fwcore throws: subject its name, detail the count.

(`e(s)`: the service's count of caught throws; `dec`: its decimal digits.)
-/
def sweepAlert (s : Svc) : Alert :=
  ⟨.svcSweepError, s.name, s!"{s.sweepErrors} fwcore throws caught in the drain since start", false⟩

/-- `svc.sweepError`: one alert for each service that counted at least one caught fwcore throw since it started. A
caught throw is never silence.
-/
def sSweep (o : Obs) : List Alert :=
  (o.system.svcs.filter fun s => decide (0 < s.sweepErrors)).map sweepAlert

/-- The `svc.unknown` alert of a service whose running code cannot be identified: subject its name, detail the reason. -/
def unknownAlert (s : Svc) (r : String) : Alert :=
  ⟨.svcUnknown, s.name, "cannot identify the code that runs: " ++ r, false⟩

/-- `svc.unknown`: one alert for each service whose running code cannot be identified. Unidentifiable code is never
silence.
-/
def sUnknown (o : Obs) : List Alert :=
  o.system.svcs.filterMap fun s => s.unknown.map (unknownAlert s)

/-- `worktrees.many`: more worktrees than `worktreesMax`. -/
def sWt (p : Params) (o : Obs) : List Alert :=
  when (decide (p.worktreesMax < o.system.worktrees)) ⟨.worktreesMany, "worktrees", s!"{o.system.worktrees} worktrees", false⟩

/-- `team.permissionWait`: a notification newer than the lead's last tool call. -/
def sPerm (o : Obs) : List Alert :=
  when (permB o.lead)
    ⟨.permissionWait, "lead", s!"notification {mins (o.now - o.lead.noteAt.getD 0)} min ago, no lead tool call since", false⟩

/-- The team and system alerts: the pieces in code order. -/
def sysAlerts (p : Params) (o : Obs) : List Alert :=
  sCiFailed o ++ sCiFin p o ++ sCiSlow p o ++ sDocker p o ++ sProc p o ++ sFeedback o ++ sLockLong p o ++ sOrphan p o ++
    sQuestion o ++ sStale o ++ sSweep o ++ sUnknown o ++ sContended o ++ sDisk p o ++ sGh o ++ sLoad p o ++ sMem o ++ sOver p o ++ sPerm o ++ sWt p o

/-- Every raised alert, unsorted: each agent's alerts, then the team and system alerts. -/
def raw (p : Params) (o : Obs) : List Alert := o.agents.flatMap (agentAll p o) ++ sysAlerts p o

/-- The state counts. -/
structure Counts where
  active  : Nat
  idle    : Nat
  parked  : Nat
  stalled : Nat
  gone    : Nat
  done    : Nat
deriving DecidableEq, Repr

/-- One output row per agent: id, state, the codes of its alerts. -/
structure Row where
  id     : String
  state  : State
  alerts : List Code
deriving DecidableEq, Repr

/-- The health report: a row per agent (input order), the codes of the team and system alerts (each once, in code
order), the state counts, and every alert, sorted and deduplicated.
-/
structure Report where
  agents : List Row
  system : List Code
  counts : Counts
  alerts : List Alert
deriving DecidableEq, Repr

/-- How many agents are in a state. -/
def countState (p : Params) (now : Nat) (agents : List Agent) (s : State) : Nat :=
  (agents.filter fun a => state p now agents a == s).length

/-! ### A dead session ends its agents (task `alert-rules-fix`)

After a session restart the old session's agents never write a `SubagentStop`. Each agent carries the pid of the session
whose hooks wrote its spool; when the process table was read and does not list that pid, the agent is dead.
-/

/-- Whether an agent's session is dead: it carries a session pid, the process table was read, and the pid is not in it. -/
def deadSession (alive : Option (List Nat)) (a : Agent) : Bool :=
  match a.sessionPid, alive with
  | some q, some l => !l.contains q
  | _, _ => false

/-- The agent as the rules see it: a dead one is stopped (at its last event if no stop was seen), any other unchanged. -/
def settleAgent (alive : Option (List Nat)) (a : Agent) : Agent :=
  if deadSession alive a then { a with stoppedAt := some (a.stoppedAt.getD a.lastAt) } else a

/-- The observation with its dead agents stopped. -/
def settle (o : Obs) : Obs := { o with agents := o.agents.map (settleAgent o.system.alivePids) }

/-- **An agent of a dead session is done and quiet** (`dead_session_done`): it is stopped, its state is `done`, it is not
live, and it raises no `agent.*` alert (no stall, no tool hang, no slow tool) and does not count toward the agent cap.
-/
theorem dead_session_done (alive : Option (List Nat)) (p : Params) (t : Nat) (A : List Agent) (a : Agent)
    (h : deadSession alive a = true) :
    state p t A (settleAgent alive a) = .done ∧ live p t (settleAgent alive a) = false ∧
      agentAlerts p t A (settleAgent alive a) = [] := by
  have hs : stopped p t (settleAgent alive a) = true := by simp [settleAgent, h, stopped]
  have hd : state p t A (settleAgent alive a) = .done := (state_done p t A _).2 hs
  refine ⟨hd, ?_, agentAlerts_quiet p t A _ (.inl hd)⟩
  simp [live, ended, hs]

/-- **A live session leaves its agents alone** (`alive_session_same`): an agent without a session pid, one whose pid is
listed, or any agent when the process table was not read, is unchanged.
-/
theorem alive_session_same (alive : Option (List Nat)) (a : Agent) (h : deadSession alive a = false) :
    settleAgent alive a = a := by
  simp [settleAgent, h]

/-- **An unread process table judges nobody** (`unread_table_alive`). -/
theorem unread_table_alive (a : Agent) : deadSession none a = false := by
  simp [deadSession]

/-- **A listed pid is alive** (`listed_pid_alive`). -/
theorem listed_pid_alive (l : List Nat) (a : Agent) (q : Nat) (hq : a.sessionPid = some q) (hm : q ∈ l) :
    deadSession (some l) a = false := by
  simp [deadSession, hq, hm]

/-- The health report of one observation. -/
def health (p : Params) (o : Obs) : Report :=
  { agents := o.agents.map fun a => ⟨a.id, state p o.now o.agents a, (agentAll p o a).map (·.code)⟩
    system := Code.all.filter fun c => (sysAlerts p o).any (·.code == c)
    counts := { active := countState p o.now o.agents .active, idle := countState p o.now o.agents .idle,
                parked := countState p o.now o.agents .parked, stalled := countState p o.now o.agents .stalled,
                gone := countState p o.now o.agents .gone, done := countState p o.now o.agents .done }
    alerts := sortU (raw p o) }

/-! ## Report theorems -/

/-- The alert list holds exactly the raised alerts. -/
theorem mem_alerts (p : Params) (o : Obs) (x : Alert) : x ∈ (health p o).alerts ↔ x ∈ raw p o :=
  mem_sortU x _

/-- The alert list is strictly sorted (critical first, then by code, subject and detail), so it has no duplicates. -/
theorem alerts_sorted (p : Params) (o : Obs) : (health p o).alerts.Pairwise Alert.Lt := sorted_sortU _

/-- Critical alerts come first: no critical alert follows a non-critical one. -/
theorem crit_first (p : Params) (o : Obs) :
    (health p o).alerts.Pairwise (fun x y => y.crit = true → x.crit = true) := by
  refine (alerts_sorted p o).imp ?_
  intro x y h hy
  rcases h with ⟨hx, _⟩ | ⟨e, _⟩
  · exact hx
  · rw [e]; exact hy

/-- The team and system alerts of one code: the piece of `sysAlerts` for that code (none for an `agent.*` code). -/
def sysPiece (p : Params) (o : Obs) : Code → List Alert
  | .ciFailed => sCiFailed o
  | .ciFinished => sCiFin p o
  | .ciSlow => sCiSlow p o
  | .dockerOrphan => sDocker p o
  | .procLong => sProc p o
  | .reviewFeedback => sFeedback o
  | .simLockLong => sLockLong p o
  | .simLockOrphan => sOrphan p o
  | .stepQuestion => sQuestion o
  | .svcStale => sStale o
  | .svcSweepError => sSweep o
  | .svcUnknown => sUnknown o
  | .diskLow => sDisk p o
  | .ghDegraded => sGh o
  | .loadHigh => sLoad p o
  | .memCritical => sMem o
  | .overCap => sOver p o
  | .permissionWait => sPerm o
  | .worktreesMany => sWt p o
  | .sysContended => sContended o
  | .ctxHigh | .ctxWarn | .errStreak | .gone | .stalled | .toolHang | .toolSlow => []

/-- `sysAlerts` is the concatenation of the pieces in rank order. -/
theorem sysAlerts_eq (p : Params) (o : Obs) : sysAlerts p o = Code.all.flatMap (sysPiece p o) := by
  simp [sysAlerts, Code.all, sysPiece, List.flatMap_cons, List.append_assoc]

/-- Every alert of a piece carries the piece's code. -/
theorem piece_code (p : Params) (o : Obs) (c : Code) (x : Alert) (h : x ∈ sysPiece p o c) : x.code = c := by
  cases c <;> simp only [sysPiece, sCiFailed, sCiFin, sCiSlow, sDocker, sProc, sFeedback, sLockLong, sOrphan, sQuestion, sStale, sSweep, sUnknown, sDisk, sGh, sLoad,
    sMem, sOver, sPerm, sWt, sContended, List.not_mem_nil] at h
  all_goals first
    | (obtain ⟨s, _, e⟩ := List.mem_filterMap.1 h
       cases hu : s.unknown <;> simp only [hu, Option.map_none, Option.map_some, reduceCtorEq, Option.some.injEq] at e
       subst e; rfl)
    | (obtain ⟨_, e⟩ := (mem_when _ _ _).1 h; subst e; rfl)
    | (obtain ⟨_, _, e⟩ := List.mem_map.1 h; subst e; rfl)
    | (obtain ⟨_, _, e⟩ := List.mem_map.1 h; subst e; exact procAlert_code _ _)

/-- A team or system alert lies in the piece of its own code. -/
theorem mem_sys (p : Params) (o : Obs) (x : Alert) : x ∈ sysAlerts p o ↔ x ∈ sysPiece p o x.code := by
  rw [sysAlerts_eq, List.mem_flatMap]
  constructor
  · rintro ⟨c, _, h⟩
    rw [piece_code p o c x h]; exact h
  · intro h
    exact ⟨x.code, by cases x.code <;> decide, h⟩

/-- A team or system alert carries one of the team and system codes, never an `agent.*` code. -/
theorem sysAlerts_notAgent (p : Params) (o : Obs) (x : Alert) (h : x ∈ sysAlerts p o) :
    x.code.isAgent = false := by
  rw [mem_sys] at h
  revert h
  cases x.code <;> simp [sysPiece, Code.isAgent, Code.rank]

/-- Every `agent.*` alert in the report names an agent of the observation that is neither done nor parked; a gone
agent raises only `agent.gone`.
-/
theorem agent_alert_live (p : Params) (o : Obs) (x : Alert) (hx : x ∈ (health p o).alerts)
    (ha : x.code.isAgent = true) :
    ∃ a ∈ o.agents, state p o.now o.agents a ≠ .done ∧ state p o.now o.agents a ≠ .parked ∧
      (state p o.now o.agents a = .gone → x.code = .gone) ∧ a.id = x.subject := by
  rw [mem_alerts] at hx
  unfold raw at hx
  rcases List.mem_append.1 hx with h | h
  · obtain ⟨a, ha', hxa⟩ := List.mem_flatMap.1 h
    refine ⟨a, ha', ?_, ?_, fun hg => gone_alerts p o a hg x hxa, (agentAll_subject p o a x hxa).2.symm⟩
    all_goals
      intro hs
      unfold agentAll at hxa
      obtain ⟨y, hy, _⟩ := List.mem_map.1 hxa
      rcases List.mem_append.1 hy with hy | hy
    · unfold goneAlert at hy
      obtain ⟨b, _⟩ := (mem_when _ _ _).1 hy
      rw [(state_done p o.now o.agents a).1 hs] at b
      simp at b
    · rw [agentAlerts_quiet p o.now o.agents a (.inl hs)] at hy; simp at hy
    · unfold goneAlert at hy
      obtain ⟨b, _⟩ := (mem_when _ _ _).1 hy
      have := ((state_parked p o.now o.agents a).1 hs).1
      unfold ended at this
      simp only [Bool.or_eq_false_iff] at this
      rw [this.1, this.2] at b
      simp at b
    · rw [agentAlerts_quiet p o.now o.agents a (.inr (.inr hs))] at hy; simp at hy
  · rw [sysAlerts_notAgent p o x h] at ha; cases ha

/-- An alert with a team or system code comes from `sysAlerts`. -/
theorem mem_sys_of_notAgent (p : Params) (o : Obs) (x : Alert) (hx : x ∈ (health p o).alerts)
    (hc : x.code.isAgent = false) : x ∈ sysAlerts p o := by
  rw [mem_alerts] at hx
  unfold raw at hx
  rcases List.mem_append.1 hx with h | h
  · obtain ⟨a, _, hxa⟩ := List.mem_flatMap.1 h
    rw [(agentAll_subject p o a x hxa).1] at hc; cases hc
  · exact h

/-- The report has an alert of a team or system code exactly when that code's piece is not empty. -/
theorem sys_code_iff (p : Params) (o : Obs) (c : Code) (hc : c.isAgent = false) :
    (∃ x ∈ (health p o).alerts, x.code = c) ↔ sysPiece p o c ≠ [] := by
  constructor
  · rintro ⟨x, hx, e⟩
    have h := (mem_sys p o x).1 (mem_sys_of_notAgent p o x hx (by rw [e]; exact hc))
    rw [e] at h
    exact List.ne_nil_of_mem h
  · intro h
    obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil _ h
    have e := piece_code p o c y hy
    refine ⟨y, (mem_alerts p o y).2 (List.mem_append.2 (.inr ((mem_sys p o y).2 (by rw [e]; exact hy)))), e⟩

theorem feedback_iff (p : Params) (o : Obs) (f : String) :
    (∃ x ∈ (health p o).alerts, x.code = .reviewFeedback ∧ x.subject = f) ↔
      Fw.Console.Steps.isStepSubject f = false ∧
        Fw.Console.ReviewFeedback.openOf (Fw.Console.ReviewFeedback.thread o.system.feedback) f ≠ [] := by
  rw [← Fw.Console.Steps.mem_reviewFlags]
  constructor
  · rintro ⟨x, hx, hc, hs⟩
    have h := (mem_sys p o x).1 (mem_sys_of_notAgent p o x hx (by rw [hc]; rfl))
    rw [hc] at h
    simp only [sysPiece, sFeedback, List.mem_map] at h
    obtain ⟨fd, hfd, e⟩ := h
    rw [← e] at hs
    simp only at hs
    rw [← hs]
    exact List.mem_map.2 ⟨fd, hfd, rfl⟩
  · intro h
    obtain ⟨fd, hfd, e⟩ := List.mem_map.1 h
    have hy : (⟨.reviewFeedback, fd.1, fd.2, false⟩ : Alert) ∈ sysPiece p o .reviewFeedback := by
      simp only [sysPiece, sFeedback]
      exact List.mem_map.2 ⟨fd, hfd, rfl⟩
    exact ⟨_, (mem_alerts p o _).2 (List.mem_append.2 (.inr ((mem_sys p o _).2 hy))), rfl, e⟩

theorem question_iff (p : Params) (o : Obs) (f : String) :
    (∃ x ∈ (health p o).alerts, x.code = .stepQuestion ∧ x.subject = f) ↔
      Fw.Console.Steps.isStepSubject f = true ∧
        Fw.Console.ReviewFeedback.openOf (Fw.Console.ReviewFeedback.thread o.system.feedback) f ≠ [] := by
  rw [← Fw.Console.Steps.mem_questionSubjects]
  constructor
  · rintro ⟨x, hx, hc, hs⟩
    have h := (mem_sys p o x).1 (mem_sys_of_notAgent p o x hx (by rw [hc]; rfl))
    rw [hc] at h
    simp only [sysPiece, sQuestion, List.mem_map] at h
    obtain ⟨fd, hfd, e⟩ := h
    rw [← e] at hs
    simp only at hs
    rw [← hs]
    exact List.mem_map.2 ⟨fd, hfd, rfl⟩
  · intro h
    obtain ⟨fd, hfd, e⟩ := List.mem_map.1 h
    have hy : (⟨.stepQuestion, fd.1, fd.2, false⟩ : Alert) ∈ sysPiece p o .stepQuestion := by
      simp only [sysPiece, sQuestion]
      exact List.mem_map.2 ⟨fd, hfd, rfl⟩
    exact ⟨_, (mem_alerts p o _).2 (List.mem_append.2 (.inr ((mem_sys p o _).2 hy))), rfl, e⟩

theorem feedback_post_opens (p : Params) (o : Obs) (f i t : String) (ts : Nat)
    (hf : Fw.Console.Steps.isStepSubject f = false)
    (h : Fw.Console.ReviewFeedback.postRefusal (Fw.Console.ReviewFeedback.thread o.system.feedback) f i t = none) :
    ∃ x ∈ (health p { o with system := { o.system with feedback := o.system.feedback ++ [.post f i t ts] } }).alerts,
      x.code = .reviewFeedback ∧ x.subject = f := by
  rw [feedback_iff]
  exact ⟨hf, (Fw.Obs.FeedbackAlert.mem_flags _ f).mp (Fw.Obs.FeedbackAlert.post_opens _ f i t ts h)⟩

theorem feedback_reply_closes (p : Params) (o : Obs) (f to t : String) (ts : Nat)
    (h : Fw.Console.ReviewFeedback.replyRefusal (Fw.Console.ReviewFeedback.thread o.system.feedback) f to t = none)
    (honly : ∀ y ∈ Fw.Console.ReviewFeedback.thread o.system.feedback, y.flag = f → y.isOpen = true → y.id = to) :
    ¬ ∃ x ∈ (health p { o with system := { o.system with feedback := o.system.feedback ++ [.reply f to t ts] } }).alerts,
      x.code = .reviewFeedback ∧ x.subject = f := by
  rw [feedback_iff]
  rintro ⟨_, hne⟩
  exact Fw.Obs.FeedbackAlert.reply_closes _ f to t ts h honly ((Fw.Obs.FeedbackAlert.mem_flags _ f).mpr hne)

theorem question_post_opens (p : Params) (o : Obs) (f i t : String) (ts : Nat)
    (hf : Fw.Console.Steps.isStepSubject f = true)
    (h : Fw.Console.ReviewFeedback.postRefusal (Fw.Console.ReviewFeedback.thread o.system.feedback) f i t = none) :
    ∃ x ∈ (health p { o with system := { o.system with feedback := o.system.feedback ++ [.post f i t ts] } }).alerts,
      x.code = .stepQuestion ∧ x.subject = f := by
  rw [question_iff]
  exact ⟨hf, (Fw.Obs.FeedbackAlert.mem_flags _ f).mp (Fw.Obs.FeedbackAlert.post_opens _ f i t ts h)⟩

theorem question_reply_closes (p : Params) (o : Obs) (f to t : String) (ts : Nat)
    (h : Fw.Console.ReviewFeedback.replyRefusal (Fw.Console.ReviewFeedback.thread o.system.feedback) f to t = none)
    (honly : ∀ y ∈ Fw.Console.ReviewFeedback.thread o.system.feedback, y.flag = f → y.isOpen = true → y.id = to) :
    ¬ ∃ x ∈ (health p { o with system := { o.system with feedback := o.system.feedback ++ [.reply f to t ts] } }).alerts,
      x.code = .stepQuestion ∧ x.subject = f := by
  rw [question_iff]
  rintro ⟨_, hne⟩
  exact Fw.Obs.FeedbackAlert.reply_closes _ f to t ts h honly ((Fw.Obs.FeedbackAlert.mem_flags _ f).mpr hne)

/-- `when` is not empty exactly when its condition holds. -/
theorem when_ne_nil (b : Bool) (x : Alert) : when b x ≠ [] ↔ b = true := by
  cases b <;> simp [when]

/-- The simulator lock raises `sim.lockOrphan` exactly when it has a holder that names no live agent (by id, name or
task).
-/
theorem lockOrphan_iff (p : Params) (o : Obs) :
    (∃ x ∈ (health p o).alerts, x.code = .simLockOrphan) ↔
      ∃ h, o.system.simLock.holder = some h ∧ ¬ ∃ a ∈ o.agents, live p o.now a = true ∧ names h a = true := by
  rw [sys_code_iff p o _ rfl]
  simp only [sysPiece, sOrphan, when_ne_nil]
  unfold orphanB
  cases o.system.simLock.holder with
  | none => simp
  | some h => simp

/-- `team.permissionWait` fires exactly when a notification exists that is newer than the lead's last finished tool
call (or the lead has finished none).
-/
theorem permissionWait_iff (p : Params) (o : Obs) :
    (∃ x ∈ (health p o).alerts, x.code = .permissionWait) ↔
      ∃ ν, o.lead.noteAt = some ν ∧ ∀ s, o.lead.lastToolAt = some s → s < ν := by
  rw [sys_code_iff p o _ rfl]
  simp only [sysPiece, sPerm, when_ne_nil]
  unfold permB
  cases o.lead.noteAt with
  | none => simp
  | some n => cases o.lead.lastToolAt <;> simp

/-- `sys.loadHigh` fires exactly when the floor of the 1-min load average is at or above `loadMax`. -/
theorem loadHigh_iff (p : Params) (o : Obs) :
    (∃ x ∈ (health p o).alerts, x.code = .loadHigh) ↔ p.loadMax ≤ o.system.loadFloor := by
  rw [sys_code_iff p o _ rfl]
  simp only [sysPiece, sLoad, when_ne_nil, decide_eq_true_eq]

/-- `sys.contended` fires exactly when the floor of the 1-min load average is above `contendedLoad`, or the previous
check raised it and the floor is still above `calmLoad` (hysteresis). -/
theorem sysContended_iff (p : Params) (o : Obs) :
    (∃ x ∈ (health p o).alerts, x.code = .sysContended) ↔
      Fw.Obs.Timing.contendedLoad < o.system.loadFloor ∨
        (o.system.load.prevContended = true ∧ Fw.Obs.Timing.calmLoad < o.system.loadFloor) := by
  rw [sys_code_iff p o _ rfl]
  simp only [sysPiece, sContended, contendedNow, when_ne_nil, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq]

/-- Opens above `contendedLoad`, whatever the previous check said. -/
theorem sysContended_opens (p : Params) (o : Obs) (h : Fw.Obs.Timing.contendedLoad < o.system.loadFloor) :
    ∃ x ∈ (health p o).alerts, x.code = .sysContended :=
  (sysContended_iff p o).2 (Or.inl h)

/-- Closes at or below `calmLoad`, whatever the previous check said. -/
theorem sysContended_closes (p : Params) (o : Obs) (h : o.system.loadFloor ≤ Fw.Obs.Timing.calmLoad) :
    ¬ ∃ x ∈ (health p o).alerts, x.code = .sysContended := by
  rw [sysContended_iff]
  have := Fw.Obs.Timing.calmLoad_lt
  omega

/-- Between the two limits the alert keeps the state of the previous check: open stays open, closed stays closed. -/
theorem sysContended_between (p : Params) (o : Obs) (h1 : Fw.Obs.Timing.calmLoad < o.system.loadFloor)
    (h2 : o.system.loadFloor ≤ Fw.Obs.Timing.contendedLoad) :
    (∃ x ∈ (health p o).alerts, x.code = .sysContended) ↔ o.system.load.prevContended = true := by
  rw [sysContended_iff]
  cases hp : o.system.load.prevContended <;> simp <;> omega

/-- **The signal and the timing verdict are one test.** `sys.contended` fires exactly when a local timing sample taken
at the observation's load (with the default limit, `contendedLoad`) is `contended`: while the machine is contended
every step's timing is judged `contended` and the one `sys.contended` carries it; at normal load neither does.
-/
theorem sysContended_iff_sample (p : Params) (o : Obs) (s : Fw.Obs.Timing.Sample)
    (hh : s.host = .«local») (hl : s.load = o.system.loadFloor) (hp : o.system.load.prevContended = false) :
    (∃ x ∈ (health p o).alerts, x.code = .sysContended) ↔ Fw.Obs.Timing.contended {} s = true := by
  rw [sysContended_iff]
  simp [Fw.Obs.Timing.contended, hh, hl, hp]

/-- A run waiting or running for more than the workflow's limit `s_p(wf(r))` minutes raises `ci.slow` with subject `workflow@branch`. -/
theorem ciSlow_raised (p : Params) (o : Obs) (r : CiRun) (hr : r ∈ o.system.ci) (h : ciSlowB p o.now r = true) :
    ∃ x ∈ (health p o).alerts, x.code = .ciSlow ∧ x.subject = s!"{r.workflow}@{r.branch}" := by
  have hy : ciSlowAlert o r ∈ sCiSlow p o :=
    List.mem_map.2 ⟨r, List.mem_filter.2 ⟨hr, h⟩, rfl⟩
  exact ⟨_, (mem_alerts p o _).2 (List.mem_append.2 (.inr ((mem_sys p o _).2 hy))), rfl, rfl⟩

/-! ## Long-running processes -/

/-- The report holds a `proc.long` alert exactly when it is the alert of a process tree that runs too long. -/
theorem procLong_iff (p : Params) (o : Obs) (x : Alert) :
    (x ∈ (health p o).alerts ∧ x.code = .procLong) ↔
      ∃ q ∈ o.system.procs, procLongB p o q = true ∧ x = procAlert o q := by
  constructor
  · rintro ⟨hx, e⟩
    have h := (mem_sys p o x).1 (mem_sys_of_notAgent p o x hx (by rw [e]; rfl))
    rw [e] at h
    simp only [sysPiece, sProc] at h
    obtain ⟨q, hq, e'⟩ := List.mem_map.1 h
    rw [List.mem_filter] at hq
    exact ⟨q, hq.1, hq.2, e'.symm⟩
  · rintro ⟨q, hq, hl, rfl⟩
    have hy : procAlert o q ∈ sysPiece p o (procAlert o q).code := by
      rw [procAlert_code]
      exact List.mem_map.2 ⟨q, List.mem_filter.2 ⟨hq, hl⟩, rfl⟩
    exact ⟨(mem_alerts p o _).2 (List.mem_append.2 (.inr ((mem_sys p o _).2 hy))), procAlert_code o q⟩

/-- A process tree started by a live agent's Bash call never runs too long, whatever its age. -/
theorem ownerLive_quiet (p : Params) (o : Obs) (q : Proc) (a : Agent) (ha : a ∈ o.agents)
    (hg : q.agent = some a.id) (hl : live p o.now a = true) : procLongB p o q = false := by
  have hw : ownerLiveB p o.now o.agents q = true := by
    unfold ownerLiveB; rw [hg]; exact List.any_eq_true.2 ⟨a, ha, by simp [hl]⟩
  simp [procLongB, hw]

/-- An intended long-runner (allowlisted program, service pid, or declared pid in its tree) never runs too long. -/
theorem declared_quiet (p : Params) (o : Obs) (q : Proc) (h : declaredB o.system.services o.system.keep q = true) :
    procLongB p o q = false := by
  simp [procLongB, h]

/-! ## Stale services -/

/-- The report holds a `svc.stale` alert exactly when it is the alert of a service with a changed input. -/
theorem svcStale_iff (p : Params) (o : Obs) (x : Alert) :
    (x ∈ (health p o).alerts ∧ x.code = .svcStale) ↔
      ∃ s ∈ o.system.svcs, (∃ i ∈ s.inputs, i.changed = true) ∧ x = staleAlert s := by
  constructor
  · rintro ⟨hx, e⟩
    have h := (mem_sys p o x).1 (mem_sys_of_notAgent p o x hx (by rw [e]; rfl))
    rw [e] at h
    simp only [sysPiece, sStale] at h
    obtain ⟨s, hs, e'⟩ := List.mem_map.1 h
    rw [List.mem_filter] at hs
    exact ⟨s, hs.1, s.stale_iff.1 hs.2, e'.symm⟩
  · rintro ⟨s, hs, hl, rfl⟩
    have hy : staleAlert s ∈ sysPiece p o (staleAlert s).code :=
      List.mem_map.2 ⟨s, List.mem_filter.2 ⟨hs, s.stale_iff.2 hl⟩, rfl⟩
    exact ⟨(mem_alerts p o _).2 (List.mem_append.2 (.inr ((mem_sys p o _).2 hy))), rfl⟩

/-- A stale service's alert names the service and lists exactly its changed paths. -/
theorem staleAlert_fields (s : Svc) :
    (staleAlert s).subject = s.name ∧
      (staleAlert s).detail = "changed on main since its commit: " ++ ", ".intercalate s.changed := ⟨rfl, rfl⟩

/-- A service judged at the head of `main` (just restarted or rebuilt) raises no `svc.stale` alert. -/
theorem sStale_restart (o : Obs) (hist : List (List String)) (n : String) (X : List String) :
    sStale { o with system := { o.system with svcs := [Svc.judge hist hist.length n X] } } = [] := by
  simp [sStale, List.filter, Svc.judge_head_not_stale hist n X]

/-- The report holds a `svc.unknown` alert exactly when it is the alert of a service whose code cannot be identified. -/
theorem svcUnknown_iff (p : Params) (o : Obs) (x : Alert) :
    (x ∈ (health p o).alerts ∧ x.code = .svcUnknown) ↔
      ∃ s ∈ o.system.svcs, ∃ r, s.unknown = some r ∧ x = unknownAlert s r := by
  constructor
  · rintro ⟨hx, e⟩
    have h := (mem_sys p o x).1 (mem_sys_of_notAgent p o x hx (by rw [e]; rfl))
    rw [e] at h
    simp only [sysPiece, sUnknown, List.mem_filterMap] at h
    obtain ⟨s, hs, hr⟩ := h
    cases hu : s.unknown with
    | none => simp [hu] at hr
    | some r => simp only [hu, Option.map_some, Option.some.injEq] at hr; exact ⟨s, hs, r, hu, hr.symm⟩
  · rintro ⟨s, hs, r, hu, rfl⟩
    have hy : unknownAlert s r ∈ sysPiece p o (unknownAlert s r).code := by
      show unknownAlert s r ∈ sUnknown o
      exact List.mem_filterMap.2 ⟨s, hs, by simp [hu]⟩
    exact ⟨(mem_alerts p o _).2 (List.mem_append.2 (.inr ((mem_sys p o _).2 hy))), rfl⟩

/-- Never silence: a service whose running code cannot be identified always has an alert in the report, named after it. -/
theorem unknown_service_alerts (p : Params) (o : Obs) (s : Svc) (hs : s ∈ o.system.svcs) (r : String)
    (hu : s.unknown = some r) :
    ∃ x ∈ (health p o).alerts, x.code = .svcUnknown ∧ x.subject = s.name :=
  ⟨unknownAlert s r, ((svcUnknown_iff p o _).2 ⟨s, hs, r, hu, rfl⟩).1, rfl, rfl⟩

/-- The report holds a `svc.sweepError` alert exactly when it is the alert of a service with a caught fwcore throw. -/
theorem svcSweepError_iff (p : Params) (o : Obs) (x : Alert) :
    (x ∈ (health p o).alerts ∧ x.code = .svcSweepError) ↔
      ∃ s ∈ o.system.svcs, 0 < s.sweepErrors ∧ x = sweepAlert s := by
  constructor
  · rintro ⟨hx, e⟩
    have h := (mem_sys p o x).1 (mem_sys_of_notAgent p o x hx (by rw [e]; rfl))
    rw [e] at h
    simp only [sysPiece, sSweep] at h
    obtain ⟨s, hs, e'⟩ := List.mem_map.1 h
    rw [List.mem_filter, decide_eq_true_eq] at hs
    exact ⟨s, hs.1, hs.2, e'.symm⟩
  · rintro ⟨s, hs, hl, rfl⟩
    have hy : sweepAlert s ∈ sysPiece p o (sweepAlert s).code :=
      List.mem_map.2 ⟨s, List.mem_filter.2 ⟨hs, decide_eq_true hl⟩, rfl⟩
    exact ⟨(mem_alerts p o _).2 (List.mem_append.2 (.inr ((mem_sys p o _).2 hy))), rfl⟩

/-- Never a swallowed throw: a service that counted a caught fwcore throw always has an alert in the report, named after
it, whose detail carries the count.
-/
theorem sweep_error_alerts (p : Params) (o : Obs) (s : Svc) (hs : s ∈ o.system.svcs) (he : 0 < s.sweepErrors) :
    ∃ x ∈ (health p o).alerts, x.code = .svcSweepError ∧ x.subject = s.name ∧
      x.detail = s!"{s.sweepErrors} fwcore throws caught in the drain since start" :=
  ⟨sweepAlert s, ((svcSweepError_iff p o _).2 ⟨s, hs, he, rfl⟩).1, rfl, rfl, rfl⟩

/-- A binary the build record does not name (no record, or a record of another binary) always raises `svc.unknown`:
the core is never judged on a guessed commit.
-/
theorem unidentified_core_alerts (p : Params) (o : Obs) (binHash : String) (rec : Option (String × String))
    (name : String) (h : ∀ s, rec ≠ some (s, binHash))
    (hs : Base.svc name (chooseBase binHash rec) ∈ o.system.svcs) :
    ∃ x ∈ (health p o).alerts, x.code = .svcUnknown ∧ x.subject = name := by
  have hu := chooseBase_unknown_alerts binHash rec name h
  cases hr : (Base.svc name (chooseBase binHash rec)).unknown with
  | none => simp [Svc.unknownB, hr] at hu
  | some r => exact unknown_service_alerts p o _ hs r hr

/-- Every `proc.long` alert comes from a process tree of the session that is not declared, whose owner is not a live
agent, and that is alive for strictly more than `procMaxMin` minutes.
-/
theorem procLong_sound (p : Params) (o : Obs) (x : Alert) (hx : x ∈ (health p o).alerts)
    (hc : x.code = .procLong) :
    ∃ q ∈ o.system.procs, x = procAlert o q ∧ declaredB o.system.services o.system.keep q = false ∧
      ¬ (∃ a ∈ o.agents, q.agent = some a.id ∧ live p o.now a = true) ∧
      p.procMaxMin * msPerMin < o.now - q.startedAt := by
  obtain ⟨q, hq, hl, e⟩ := (procLong_iff p o x).1 ⟨hx, hc⟩
  refine ⟨q, hq, e, ?_, fun ⟨a, ha, hg, hv⟩ => ?_, ?_⟩
  · cases hd : declaredB o.system.services o.system.keep q
    · rfl
    · rw [declared_quiet p o q hd] at hl; cases hl
  · rw [ownerLive_quiet p o q a ha hg hv] at hl; cases hl
  · simp only [procLongB, Bool.and_eq_true, decide_eq_true_eq] at hl
    exact hl.2

/-- An orphan raises `proc.long`: a process tree of the session that is not declared, whose owner is an agent id
that no live agent of the list carries (the agent ended, is gone, or dropped out), and that is alive for strictly
more than `procMaxMin` minutes, has its alert in the report.
-/
theorem orphan_raised (p : Params) (o : Obs) (q : Proc) (g : String) (hq : q ∈ o.system.procs)
    (hd : declaredB o.system.services o.system.keep q = false) (hg : q.agent = some g)
    (hn : ∀ a ∈ o.agents, a.id = g → live p o.now a = false)
    (ht : p.procMaxMin * msPerMin < o.now - q.startedAt) : procAlert o q ∈ (health p o).alerts := by
  have hw : ownerLiveB p o.now o.agents q = false := by
    unfold ownerLiveB; rw [hg]
    refine List.any_eq_false.2 fun a ha => ?_
    by_cases e : a.id = g
    · simp [e, hn a ha e]
    · simp [e]
  have hl : procLongB p o q = true := by simp [procLongB, hd, hw, ht]
  exact ((procLong_iff p o _).2 ⟨q, hq, hl, rfl⟩).1

/-! ## Monotonicity -/

/-- `q` is looser than `p`: every upper threshold of `q` is at least `p`'s, the disk floor of `q` is at most `p`'s,
and both use the same `wfQuietMin` and `goneAfterMin` (they decide which agents have ended, so they are not loosening
knobs).
-/
structure Looser (p q : Params) : Prop where
  idle : p.idleMin ≤ q.idleMin
  stall : p.stallMin ≤ q.stallMin
  hang : p.toolHangMin ≤ q.toolHangMin
  err : p.errStreak ≤ q.errStreak
  ctxMax : p.ctxResumeMax ≤ q.ctxResumeMax
  ctxWarn : p.ctxWarn ≤ q.ctxWarn
  disk : q.diskMinGB ≤ p.diskMinGB
  cap : p.agentCap ≤ q.agentCap
  sim : p.simLockMaxMin ≤ q.simLockMaxMin
  wt : p.worktreesMax ≤ q.worktreesMax
  wf : p.wfQuietMin = q.wfQuietMin
  gone : p.goneAfterMin = q.goneAfterMin
  toolSlow : p.toolSlowMin ≤ q.toolSlowMin
  ciSlow : ∀ w, ciSlowFor p w ≤ ciSlowFor q w
  procMax : p.procMaxMin ≤ q.procMaxMin
  load : p.loadMax ≤ q.loadMax

/-- Whether an agent has ended depends on the thresholds only through `wfQuietMin` and `goneAfterMin`. -/
theorem ended_congr (p q : Params) (t : Nat) (a : Agent) (h : p.wfQuietMin = q.wfQuietMin)
    (hg : p.goneAfterMin = q.goneAfterMin) : ended p t a = ended q t a := by
  simp [ended, stopped, goneB, h, hg]

/-- So does whether an agent has a live child. -/
theorem hasLiveChild_congr (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (h : p.wfQuietMin = q.wfQuietMin)
    (hg : p.goneAfterMin = q.goneAfterMin) : hasLiveChild p t A a = hasLiveChild q t A a := by
  simp only [hasLiveChild, live, ended_congr p q t _ h hg]

/-- A tool hung under looser thresholds has also hung under tighter ones. -/
theorem hungB_mono (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (hpq : Looser p q)
    (h : hungB q t A a = true) : hungB p t A a = true := by
  unfold hungB at *
  rw [hasLiveChild_congr p q t A a hpq.wf hpq.gone]
  cases hf : a.inflight with
  | none => simp [hf] at h
  | some f =>
    simp only [hf, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    exact ⟨h.1, Nat.le_trans (Nat.mul_le_mul_right _ hpq.hang) h.2⟩

/-- A tool slow under looser thresholds is also slow under tighter ones. -/
theorem slowB_mono (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (hpq : Looser p q)
    (h : slowB q t A a = true) : slowB p t A a = true := by
  unfold slowB at *
  rw [hasLiveChild_congr p q t A a hpq.wf hpq.gone]
  cases hf : a.inflight with
  | none => simp [hf] at h
  | some f =>
    simp only [hf, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    exact ⟨h.1, Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ hpq.toolSlow) h.2⟩

/-- Stalling under looser thresholds implies stalling under tighter ones. -/
theorem stalled_mono (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (hpq : Looser p q)
    (h : state q t A a = .stalled) : state p t A a = .stalled := by
  have hs : stallB q t A a = true → stallB p t A a = true := by
    intro e
    unfold stallB at *
    simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at e ⊢
    exact ⟨Nat.le_trans (Nat.mul_le_mul_right _ hpq.stall) e.1, e.2.imp id (hungB_mono p q t A a hpq)⟩
  have he := ended_congr p q t a hpq.wf hpq.gone
  rw [state_stalled] at h ⊢
  obtain ⟨h1, h2, h3⟩ := h
  exact ⟨by rw [he]; exact h1, h2, (stallB_iff p t A a).1 (hs ((stallB_iff q t A a).2 h3))⟩

/-- A live-agent alert under looser thresholds is also raised under tighter ones. -/
theorem agentAlerts_mono (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (hpq : Looser p q) (x : Alert)
    (h : x ∈ agentAlerts q t A a) : x ∈ agentAlerts p t A a := by
  have hs : stallB q t A a = true → stallB p t A a = true := by
    intro e
    have hn : (ended q t a || parkedB a) = false := by
      cases hg : (ended q t a || parkedB a)
      · rfl
      · unfold agentAlerts at h; simp [hg] at h
    simp only [Bool.or_eq_false_iff] at hn
    have hst : state q t A a = .stalled := by
      rw [state_stalled, ← stallB_iff]; exact ⟨hn.1, hn.2, e⟩
    have := (state_stalled p t A a).1 (stalled_mono p q t A a hpq hst)
    exact (stallB_iff p t A a).2 this.2.2
  have hh := hungB_mono p q t A a hpq
  have hsl := slowB_mono p q t A a hpq
  have he := ended_congr p q t a hpq.wf hpq.gone
  have hle := hpq.err
  have hc := hpq.ctxMax
  have hwn := hpq.ctxWarn
  unfold agentAlerts at h ⊢
  rw [he]
  split at h
  · simp at h
  · rename_i hg
    simp only [hg, Bool.false_eq_true, ↓reduceIte, List.mem_append, mem_when] at h ⊢
    rcases h with ((((⟨b, e⟩ | ⟨b, e⟩) | ⟨b, e⟩) | ⟨b, e⟩) | ⟨b, e⟩) | ⟨b, e⟩
    · exact .inl (.inl (.inl (.inl (.inl ⟨by simp at b ⊢; omega, e⟩))))
    · exact .inl (.inl (.inl (.inl (.inr ⟨by simp at b ⊢; omega, e⟩))))
    · exact .inl (.inl (.inl (.inr ⟨by simp at b ⊢; omega, e⟩)))
    · exact .inl (.inl (.inr ⟨hs b, e⟩))
    · exact .inl (.inr ⟨hh b, e⟩)
    · exact .inr ⟨hsl b, e⟩

/-- Every alert of an agent under looser thresholds is also raised under tighter ones (`agent.gone` does not depend on
the loosening knobs).
-/
theorem agentAll_mono (p q : Params) (o : Obs) (a : Agent) (hpq : Looser p q) (x : Alert)
    (h : x ∈ agentAll q o a) : x ∈ agentAll p o a := by
  have hg : goneAlert q o a = goneAlert p o a := by
    unfold goneAlert newGone stopped goneB; rw [hpq.wf, hpq.gone]
  unfold agentAll at *
  rw [hg] at h
  obtain ⟨y, hy, e⟩ := List.mem_map.1 h
  subst e
  refine List.mem_map.2 ⟨y, ?_, rfl⟩
  rcases List.mem_append.1 hy with hy | hy
  · exact List.mem_append.2 (.inl hy)
  · exact List.mem_append.2 (.inr (agentAlerts_mono p q o.now o.agents a hpq y hy))

/-- A `when` with a weaker condition and the same alert holds more. -/
theorem when_sub {b b' : Bool} (y : Alert) (hb : b = true → b' = true) (x : Alert) (h : x ∈ when b y) :
    x ∈ when b' y := by
  rw [mem_when] at h ⊢
  exact ⟨hb h.1, h.2⟩

/-- Filtering with a weaker test and the same alert map keeps more. -/
theorem fm_sub {α : Type} (l : List α) (f g : α → Bool) (m : α → Alert) (hfg : ∀ r ∈ l, f r = true → g r = true)
    (x : Alert) (h : x ∈ (l.filter f).map m) : x ∈ (l.filter g).map m := by
  obtain ⟨r, hr, e⟩ := List.mem_map.1 h
  rw [List.mem_filter] at hr
  exact List.mem_map.2 ⟨r, List.mem_filter.2 ⟨hr.1, hfg r hr.1 hr.2⟩, e⟩

/-- A team or system alert of one code under looser thresholds is also raised under tighter ones. -/
theorem sysPiece_mono (p q : Params) (o : Obs) (hpq : Looser p q) (c : Code) (x : Alert)
    (h : x ∈ sysPiece q o c) : x ∈ sysPiece p o c := by
  have hl : live q = live p := by funext t a; simp [live, ended_congr p q t a hpq.wf hpq.gone]
  have hn : nLive q o.now o.agents = nLive p o.now o.agents := by simp only [nLive, hl]
  have hk : nKind q o.now o.agents = nKind p o.now o.agents := by funext k; simp only [nKind, hl]
  have hhp : nHelpers q o.now o.agents = nHelpers p o.now o.agents := by simp only [nHelpers, hl]
  have ho : orphanB q o.now o.agents = orphanB p o.now o.agents := by funext l; simp only [orphanB, hl]
  have hdo : dockerOrphanB q o.now o.agents = dockerOrphanB p o.now o.agents := by
    funext c; simp only [dockerOrphanB, hl]
  have hd := hpq.disk
  have hcap := hpq.cap
  have hwt := hpq.wt
  have hld := hpq.load
  cases c
  all_goals try (simp only [sysPiece, List.not_mem_nil] at h; done)
  · exact h
  · refine fm_sub _ _ _ _ (fun r _ hr => ?_) x h
    unfold ciFinishedB at *
    cases hp : o.prevAt with
    | none => simp [hp] at hr
    | some t =>
      cases he : r.endedAt with
      | none => simp [hp, he] at hr
      | some e =>
        simp only [hp, he, Bool.and_eq_true, decide_eq_true_eq] at hr ⊢
        exact ⟨hr.1, Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ (hpq.ciSlow r.workflow)) hr.2⟩
  · refine fm_sub _ _ _ _ (fun r _ hr => ?_) x h
    unfold ciSlowB at *
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hr ⊢
    exact ⟨hr.1, Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ (hpq.ciSlow r.workflow)) hr.2⟩
  · simp only [sysPiece, sDocker] at h ⊢; rw [← hdo]; exact h
  · refine fm_sub _ _ _ _ (fun r _ hr => ?_) x h
    have hw : ownerLiveB q o.now o.agents r = ownerLiveB p o.now o.agents r := by simp only [ownerLiveB, hl]
    unfold procLongB at *
    rw [hw] at hr
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hr ⊢
    exact ⟨hr.1, Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ hpq.procMax) hr.2⟩
  · exact h
  · refine when_sub _ (fun hb => ?_) x h
    cases hs : o.system.simLock.since with
    | none => simp [hs] at hb
    | some s =>
      simp only [hs, Option.any_some, Bool.and_eq_true, decide_eq_true_eq] at hb ⊢
      exact ⟨hb.1, Nat.le_trans (Nat.mul_le_mul_right _ hpq.sim) hb.2⟩
  · simp only [sysPiece, sOrphan] at h ⊢; rw [← ho]; exact h
  · exact h
  · exact h
  · exact h
  · exact h
  · exact h
  · exact when_sub _ (fun hb => by simp only [decide_eq_true_eq] at hb ⊢; omega) x h
  · exact h
  · exact when_sub _ (fun hb => by simp only [decide_eq_true_eq] at hb ⊢; omega) x h
  · exact h
  · simp only [sysPiece, sOver] at h ⊢
    rw [hn, hk, hhp] at h
    exact when_sub _ (fun hb => by simp only [decide_eq_true_eq] at hb ⊢; omega) x h
  · exact h
  · exact when_sub _ (fun hb => by simp only [decide_eq_true_eq] at hb ⊢; omega) x h

/-- A team or system alert under looser thresholds is also raised under tighter ones. -/
theorem sysAlerts_mono (p q : Params) (o : Obs) (hpq : Looser p q) (x : Alert) (h : x ∈ sysAlerts q o) :
    x ∈ sysAlerts p o := by
  rw [mem_sys] at *
  exact sysPiece_mono p q o hpq x.code x h

/-- Loosening the thresholds never adds an alert: every alert of the report under `q` is in the report under `p`.
(Raising any upper threshold, or lowering `diskMinGB`, with `wfQuietMin` and `goneAfterMin` unchanged, is a
loosening.)
-/
theorem health_mono (p q : Params) (o : Obs) (hpq : Looser p q) (x : Alert) (h : x ∈ (health q o).alerts) :
    x ∈ (health p o).alerts := by
  rw [mem_alerts] at *
  unfold raw at *
  rcases List.mem_append.1 h with h | h
  · obtain ⟨a, ha, hx⟩ := List.mem_flatMap.1 h
    exact List.mem_append.2 (.inl (List.mem_flatMap.2 ⟨a, ha, agentAll_mono p q o a hpq x hx⟩))
  · exact List.mem_append.2 (.inr (sysAlerts_mono p q o hpq x h))

/-! ## Agent order does not matter -/

/-- An agent's state and live-agent alerts do not depend on the order of the agent list. -/
theorem agent_perm (p : Params) (t : Nat) (A l : List Agent) (a : Agent) (hl : l.Perm A) :
    state p t l a = state p t A a ∧ agentAlerts p t l a = agentAlerts p t A a := by
  have hc : hasLiveChild p t l a = hasLiveChild p t A a := by unfold hasLiveChild; rw [hl.any_eq]
  have hh : hungB p t l a = hungB p t A a := by unfold hungB; rw [hc]
  have hsl : slowB p t l a = slowB p t A a := by unfold slowB; rw [hc]
  have hs : stallB p t l a = stallB p t A a := by unfold stallB; rw [hh]
  exact ⟨by unfold state; rw [hs], by unfold agentAlerts; rw [hs, hh, hsl]⟩

/-- The team and system alerts do not depend on the order of the agents. -/
theorem sysAlerts_perm (p : Params) (o : Obs) (l : List Agent) (hl : l.Perm o.agents) :
    sysAlerts p { o with agents := l } = sysAlerts p o := by
  have hn : nLive p o.now l = nLive p o.now o.agents := (hl.filter _).length_eq
  have hk : nKind p o.now l = nKind p o.now o.agents := by funext k; exact (hl.filter _).length_eq
  have hh : nHelpers p o.now l = nHelpers p o.now o.agents := (hl.filter _).length_eq
  have ho : orphanB p o.now l o.system.simLock = orphanB p o.now o.agents o.system.simLock := by
    unfold orphanB; split <;> simp [hl.any_eq]
  have hd : dockerOrphanB p o.now l = dockerOrphanB p o.now o.agents := by
    funext c; unfold dockerOrphanB; rw [hl.any_eq]
  have hq : procLongB p { o with agents := l } = procLongB p o := by
    funext r
    have hw : ownerLiveB p o.now l r = ownerLiveB p o.now o.agents r := by
      unfold ownerLiveB; cases r.agent <;> simp only [hl.any_eq]
    simp only [procLongB, hw]
  have ha : procAlert { o with agents := l } = procAlert o := rfl
  have hc : ciSlowAlert { o with agents := l } = ciSlowAlert o := rfl
  simp only [sysAlerts, sCiFailed, sCiFin, sCiSlow, sDocker, sProc, sFeedback, sLockLong, sOrphan, sQuestion, sStale, sSweep, sUnknown, sDisk, sGh, sLoad, sMem, sOver,
    sPerm, sWt, sContended, contendedNow, hn, hk, hh, ho, hd, hq, ha, hc]

/-- The report's alerts, system codes and counts do not depend on the order of the agents (the rows follow it). -/
theorem health_perm (p : Params) (o : Obs) (l : List Agent) (hl : l.Perm o.agents) :
    (health p { o with agents := l }).alerts = (health p o).alerts ∧
    (health p { o with agents := l }).system = (health p o).system ∧
    (health p { o with agents := l }).counts = (health p o).counts := by
  have hs := sysAlerts_perm p o l hl
  have ha : agentAll p { o with agents := l } = agentAll p o := by
    funext a; simp only [agentAll, goneAlert, (agent_perm p o.now o.agents l a hl).2]
  have hst : state p o.now l = state p o.now o.agents := by
    funext a; exact (agent_perm p o.now o.agents l a hl).1
  refine ⟨?_, ?_, ?_⟩
  · apply eq_of_sorted _ _ (alerts_sorted _ _) (alerts_sorted _ _)
    intro z
    rw [mem_alerts, mem_alerts]
    unfold raw
    simp only [List.mem_append, hs, ha]
    rw [(hl.flatMap_right (agentAll p o)).mem_iff]
  · simp only [health, hs]
  · simp only [health, countState, hst, (hl.filter _).length_eq]

/-- The counts add up to the number of agents. -/
theorem counts_total (p : Params) (o : Obs) :
    let c := (health p o).counts
    c.active + c.idle + c.parked + c.stalled + c.gone + c.done = o.agents.length := by
  simp only [health, countState]
  generalize hf : state p o.now o.agents = f
  induction o.agents with
  | nil => rfl
  | cons a as ih =>
    simp only [List.filter_cons, List.length_cons]
    cases f a <;> simp <;> omega

/-! ## Examples -/

/-- A sample agent (a subagent) started at 0 with its last event at minute 0 (for the guards). -/
def a0 : Agent := { id := "a" }

/-- A sample teammate whose last finished tool call was at minute 0 (for the guards). -/
def tm0 : Agent := { a0 with kind := .teammate, lastTool := some "Bash", lastToolAt := some 0 }

/-- A sample CI run of workflow `ci` on branch `main`, completed at an unknown time, started at 0 (for the guards). -/
def ci0 : CiRun := { workflow := "ci", branch := "main", status := "completed", startedAt := 0 }

#guard state {} (5 * msPerMin) [] a0 == .active
#guard state {} (10 * msPerMin - 1) [] a0 == .active
#guard state {} (10 * msPerMin) [] a0 == .idle
#guard state {} (20 * msPerMin) [] a0 == .stalled
#guard state {} (20 * msPerMin) [] { a0 with inflight := some ⟨"Bash", 0⟩ } == .idle
#guard state {} (30 * msPerMin) [] { a0 with inflight := some ⟨"Bash", 0⟩ } == .stalled
#guard state {} (99 * msPerMin) [] { a0 with stoppedAt := some 1 } == .done
#guard state {} 0 [] { a0 with lastAt := 5 } == .active
-- gone: strictly more than goneAfterMin (120) minutes without an event; stopped wins over gone
#guard state {} (120 * msPerMin) [] a0 == .stalled
#guard state {} (120 * msPerMin + 1) [] a0 == .gone
#guard state {} (120 * msPerMin + 1) [] tm0 == .gone
#guard state {} (999 * msPerMin) [] { a0 with stoppedAt := some 1 } == .done
#guard live {} (120 * msPerMin + 1) a0 == false
#guard nLive {} (121 * msPerMin) [a0, { a0 with lastAt := 100 * msPerMin }] == 1
-- teammates: parked after SendMessage or a newer TeammateIdle; a tool in flight or an older TeammateIdle is not parked
#guard state {} (99 * msPerMin) [] tm0 == .stalled
#guard state {} (99 * msPerMin) [] { tm0 with lastTool := some "SendMessage" } == .parked
#guard state {} (99 * msPerMin) [] { tm0 with lastTool := some "SendMessage", inflight := some ⟨"Bash", 0⟩ } == .stalled
#guard state {} (99 * msPerMin) [] { tm0 with idleAt := some 1 } == .parked
#guard state {} (99 * msPerMin) [] { tm0 with idleAt := some 0 } == .stalled
#guard state {} (99 * msPerMin) [] { tm0 with lastToolAt := none, idleAt := some 0 } == .parked
#guard state {} (99 * msPerMin) [] { a0 with lastTool := some "SendMessage" } == .stalled
-- workflow agents: done when the run finished, or transcript-only and quiet for wfQuietMin
#guard state {} (99 * msPerMin) [] { a0 with kind := .workflow, workflowDone := true } == .done
#guard state {} (30 * msPerMin) [] { a0 with kind := .workflow, transcriptOnly := true } == .done
#guard state {} (30 * msPerMin - 1) [] { a0 with kind := .workflow, transcriptOnly := true } == .stalled
#guard state {} (99 * msPerMin) [] { a0 with kind := .workflow } == .stalled
#guard state {} (99 * msPerMin) [] { a0 with transcriptOnly := true } == .stalled
-- an Agent call in flight with a live child is a wait; with a done child it hangs
#guard state {} (99 * msPerMin) [{ a0 with id := "c", parent := some "a", lastAt := 99 * msPerMin }]
  { a0 with inflight := some ⟨"Agent", 0⟩ } == .idle
#guard state {} (99 * msPerMin) [{ a0 with id := "c", parent := some "a", stoppedAt := some 1 }]
  { a0 with inflight := some ⟨"Agent", 0⟩ } == .stalled
#guard (agentAlerts {} (99 * msPerMin) [{ a0 with id := "c", parent := some "a" }]
  { a0 with lastAt := 99 * msPerMin, inflight := some ⟨"SendMessage", 0⟩ }).map (·.code) == []
#guard (agentAlerts {} (99 * msPerMin) [] { a0 with lastAt := 99 * msPerMin, inflight := some ⟨"Agent", 0⟩ }).map (·.code)
  == [.toolHang, .toolSlow]
#guard agentAlerts {} (99 * msPerMin) [] { a0 with stoppedAt := some 1, errTail := 9, ctxTokens := some 300000 } == []
#guard agentAlerts {} (99 * msPerMin) [] { tm0 with idleAt := some 1, errTail := 9, ctxTokens := some 300000 } == []
#guard agentAlerts {} (121 * msPerMin) [] { a0 with errTail := 9, ctxTokens := some 300000 } == []
#guard (agentAlerts {} 0 [] { a0 with ctxTokens := some 250001 }).map (·.code) == [.ctxHigh, .ctxWarn]
#guard (agentAlerts {} 0 [] { a0 with ctxTokens := some 250000 }).map (·.code) == [.ctxWarn]
#guard (agentAlerts {} 0 [] { a0 with errTail := 3 }).map (·.code) == [.errStreak]
#guard (agentAlerts {} 0 [] { a0 with errTail := 2 }).map (·.code) == []
#guard (agentAlerts { errStreak := 0 } 0 [] { a0 with errTail := 0 }).map (·.code) == []
#guard (agentAlerts {} (30 * msPerMin) [] { a0 with inflight := some ⟨"Bash", 0⟩ }).map (·.code)
  == [.stalled, .toolHang, .toolSlow]
-- toolSlow: strictly more than toolSlowMin (15) minutes in one call
#guard slowB {} (15 * msPerMin) [] { a0 with inflight := some ⟨"Bash", 0⟩ } == false
#guard slowB {} (15 * msPerMin + 1) [] { a0 with inflight := some ⟨"Bash", 0⟩ } == true
#guard slowB {} (99 * msPerMin) [] a0 == false
#guard (agentAlerts {} (15 * msPerMin + 1) [] { a0 with lastAt := 15 * msPerMin, inflight := some ⟨"Bash", 0⟩ })
  == [⟨.toolSlow, "a", "Bash running for 15 min", false⟩]
#guard toolDetail (16 * msPerMin) { a0 with inflight := some ⟨"Bash", msPerMin⟩ } == "Bash running for 15 min"
#guard toolDetail 0 a0 == ""
-- agent.gone: once, at the first check that sees the agent gone
#guard newGone {} none a0 == true
#guard newGone {} (some (120 * msPerMin)) a0 == true
#guard newGone {} (some (120 * msPerMin + 1)) a0 == false
#guard goneAlert {} { now := 121 * msPerMin, prevAt := some (100 * msPerMin) } a0
  == [⟨.gone, "a", "no event for 121 min", false⟩]
#guard goneAlert {} { now := 130 * msPerMin, prevAt := some (121 * msPerMin) } a0 == []
#guard goneAlert {} { now := 130 * msPerMin } a0 == [⟨.gone, "a", "no event for 130 min", false⟩]
#guard goneAlert {} { now := 130 * msPerMin } { a0 with stoppedAt := some 1 } == []
#guard goneAlert {} { now := 120 * msPerMin } a0 == []
-- critical path: an id, name or task tied to a task id (exact, or `-` and digits); CI branches `ci/<task>`
#guard tiedTo "watch-slow" "watch-slow" == true
#guard tiedTo "watch-slow" "watch-slow-2" == true
#guard tiedTo "watch-slow" "watch-slow-" == false
#guard tiedTo "watch-slow" "watch-slow-x" == false
#guard tiedTo "watch" "watch-slow" == false
#guard critAgent ["watch-slow"] { a0 with name := some "watch-slow" } == true
#guard critAgent ["watch-slow"] { a0 with task := some "watch-slow-3" } == true
#guard critAgent ["watch-slow"] a0 == false
#guard critAgent [] { a0 with name := some "watch-slow" } == false
#guard critCi ["hittest"] { ci0 with branch := "ci/hittest" } == true
#guard critCi ["hittest"] { ci0 with branch := "ci/hittest-swipe" } == false
#guard critCi ["hittest"] { ci0 with branch := "hittest" } == false
#guard agentAll {} { now := 0, critical := ["t"] } { a0 with task := some "t", errTail := 3 }
  == [⟨.errStreak, "a", "3 failed tool calls in a row", true⟩]
#guard permB {} == false
#guard permB { noteAt := some 5 } == true
#guard permB { noteAt := some 5, lastToolAt := some 4 } == true
#guard permB { noteAt := some 5, lastToolAt := some 5 } == false
#guard permB { lastToolAt := some 5 } == false
#guard orphanB {} 0 [{ a0 with task := some "wktr" }] { holder := some "wktr" } == false
#guard orphanB {} 0 [{ a0 with task := some "wktr", stoppedAt := some 1 }] { holder := some "wktr" } == true
#guard orphanB {} (121 * msPerMin) [{ a0 with task := some "wktr" }] { holder := some "wktr" } == true
#guard orphanB {} 0 [] {} == false
#guard ciFailing { ci0 with conclusion := some "timed_out" } == true
#guard ciFailing { ci0 with conclusion := some "success" } == false
#guard ciFailing ci0 == false
#guard ciLatest [{ ci0 with conclusion := some "failure", startedAt := 1 }, { ci0 with conclusion := some "success", startedAt := 2 }]
  { ci0 with conclusion := some "failure", startedAt := 1 } == false
#guard ciLatest [{ ci0 with startedAt := 1 }, { ci0 with branch := "x", startedAt := 2 }] { ci0 with startedAt := 1 } == true
-- ci.failed per (workflow, branch, sha) set (alert-rules-fix): the push (skipped) and two dispatches of ci/morph-tween-inherit
#guard (sCiFailed { now := 0, system := { ci := [
  { ci0 with workflow := "gate", branch := "ci/m", conclusion := some "failure", startedAt := 8, headSha := "a" },
  { ci0 with workflow := "gate", branch := "ci/m", status := "in_progress", startedAt := 5, headSha := "a" },
  { ci0 with workflow := "gate", branch := "ci/m", conclusion := some "skipped", startedAt := 3, headSha := "a" }] } }).length == 0
#guard (sCiFailed { now := 0, system := { ci := [
  { ci0 with workflow := "gate", branch := "ci/m", conclusion := some "failure", startedAt := 8, headSha := "a" },
  { ci0 with workflow := "gate", branch := "ci/m", conclusion := some "failure", startedAt := 5, headSha := "a" },
  { ci0 with workflow := "gate", branch := "ci/m", conclusion := some "skipped", startedAt := 3, headSha := "a" }] } }).map (·.subject)
  == ["gate@ci/m"]
-- an older failed sha is not the latest set; a newer pending sha hides it
#guard (sCiFailed { now := 0, system := { ci := [
  { ci0 with workflow := "gate", branch := "ci/m", status := "queued", startedAt := 9, headSha := "b" },
  { ci0 with workflow := "gate", branch := "ci/m", conclusion := some "failure", startedAt := 5, headSha := "a" }] } }).length == 0
-- a run without a sha is its own set per workflow and branch (the old behaviour)
#guard (sCiFailed { now := 0, system := { ci := [{ ci0 with conclusion := some "failure", startedAt := 1 }] } }).length == 1
#guard ciSlowFor {} "ci" == 20
#guard ciSlowFor {} "breakpoint-gate" == 40
#guard ciSlowFor { ciSlowBy := [] } "breakpoint-gate" == 20
#guard ciSlowB {} (30 * msPerMin) { ci0 with workflow := "breakpoint-gate", status := "in_progress" } == false
#guard ciSlowB {} (41 * msPerMin) { ci0 with workflow := "breakpoint-gate", status := "in_progress" } == true
-- ci.slow: waiting or running for strictly more than ciSlowMin (20) minutes
#guard ciRunning { ci0 with status := "queued" } == true
#guard ciRunning { ci0 with status := "in_progress" } == true
#guard ciRunning ci0 == false
#guard ciSlowB {} (20 * msPerMin) { ci0 with status := "in_progress" } == false
#guard ciSlowB {} (20 * msPerMin + 1) { ci0 with status := "in_progress" } == true
#guard ciSlowB {} (99 * msPerMin) ci0 == false
-- ci.finished: slow at the previous check, completed after it
#guard ciFinishedB {} (some (21 * msPerMin)) { ci0 with endedAt := some (25 * msPerMin) } == true
#guard ciFinishedB {} (some (20 * msPerMin)) { ci0 with endedAt := some (25 * msPerMin) } == false
#guard ciFinishedB {} (some (21 * msPerMin)) { ci0 with endedAt := some (21 * msPerMin) } == false
#guard ciFinishedB {} none { ci0 with endedAt := some (25 * msPerMin) } == false
#guard ciFinishedB {} (some (21 * msPerMin)) ci0 == false
#guard ciFinishedB {} (some (21 * msPerMin)) { ci0 with status := "in_progress", endedAt := some (25 * msPerMin) } == false
#guard sCiFin {} { now := 30 * msPerMin, prevAt := some (21 * msPerMin), critical := ["x"],
                   system := { ci := [{ ci0 with branch := "ci/x", conclusion := some "success", endedAt := some (25 * msPerMin) }] } }
  == [⟨.ciFinished, "ci@ci/x", "success after 25 min", true⟩]
#guard dockerOrphanB {} 0 [{ a0 with startedAt := 5 }] ⟨"c1", "pg", 4⟩ == true
#guard dockerOrphanB {} 0 [{ a0 with startedAt := 5 }] ⟨"c1", "pg", 5⟩ == false
-- proc.long: strictly more than procMaxMin (20) minutes, and no pid of the tree is a service
#guard procLongB {} { now := 20 * msPerMin + 1 } ⟨7, "node", 0, [], none⟩ == true
#guard procLongB {} { now := 20 * msPerMin } ⟨7, "node", 0, [], none⟩ == false
#guard procLongB {} { now := 99 * msPerMin, system := { services := [7] } } ⟨7, "node", 0, [], none⟩ == false
#guard procLongB {} { now := 99 * msPerMin, system := { services := [9] } } ⟨7, "node", 0, [8, 9], none⟩ == false
#guard procLongB {} { now := 99 * msPerMin, system := { services := [10] } } ⟨7, "node", 0, [8, 9], none⟩ == true
-- declared: allowlisted program name, or a pid the lead declared (`keep`) anywhere in the tree
#guard procLongB {} { now := 99 * msPerMin } ⟨7, "caffeinate", 0, [8], none⟩ == false
#guard procLongB {} { now := 99 * msPerMin } ⟨7, "Python", 0, [8], none⟩ == true
#guard procLongB {} { now := 99 * msPerMin, system := { keep := [8] } } ⟨7, "Python", 0, [8], none⟩ == false
#guard procLongB {} { now := 99 * msPerMin, system := { keep := [9] } } ⟨7, "Python", 0, [8], none⟩ == true
-- owner: a live agent's tree never; an ended, gone or unknown agent's tree (orphan) after procMaxMin
#guard procLongB {} { now := 99 * msPerMin, agents := [{ id := "a", lastAt := 98 * msPerMin }] }
  ⟨7, "sleep", 0, [8], some "a"⟩ == false
#guard procLongB {} { now := 99 * msPerMin, agents := [{ id := "a", lastAt := 98 * msPerMin, stoppedAt := some 1 }] }
  ⟨7, "sleep", 0, [8], some "a"⟩ == true
#guard procLongB {} { now := 200 * msPerMin, agents := [{ id := "a", lastAt := 79 * msPerMin }] }
  ⟨7, "sleep", 0, [8], some "a"⟩ == true
#guard procLongB {} { now := 99 * msPerMin, agents := [{ id := "b", lastAt := 98 * msPerMin }] }
  ⟨7, "sleep", 0, [8], some "a"⟩ == true
#guard procLongB {} { now := 99 * msPerMin, agents := [{ id := "a", lastAt := 98 * msPerMin }] }
  ⟨7, "sleep", 0, [8], none⟩ == true
#guard procAlert { now := 99 * msPerMin } ⟨7, "sleep", 0, [8], some "a"⟩
  == ⟨.procLong, "sleep#7", "alive 99 min, agent a ended", false⟩
#guard procAlert { now := 99 * msPerMin } ⟨7, "sleep", 0, [8], none⟩ == ⟨.procLong, "sleep#7", "alive 99 min", false⟩
#guard nLive {} 0 [a0, { a0 with kind := .lead }, { a0 with kind := .workflow, workflowDone := true }] == 1
#guard ((health {} { now := 0, system := { diskFreeGB := 19, memPressure := .critical } }).alerts.map (·.code))
  == [.diskLow, .memCritical]
#guard (health {} { now := 0, system := { diskFreeGB := 20 } }).alerts == []
#guard ((health {} { now := 0, lead := { noteAt := some 0 }, system := { diskFreeGB := 20 } }).alerts.map (·.code))
  == [.permissionWait]
-- sys.loadHigh: at or above loadMax (150)
#guard sLoad {} { now := 0, system := { loadFloor := 150 } } == [⟨.loadHigh, "load", "load average 150 (1 min, floor)", false⟩]
#guard sLoad {} { now := 0, system := { loadFloor := 149 } } == []
-- critical alerts sort first; system codes are listed in code order
#guard (health {} { now := 0, critical := ["t"], agents := [{ a0 with task := some "t", errTail := 3 }],
                    system := { diskFreeGB := 19, ci := [{ ci0 with conclusion := some "failure" }] } }).alerts.map (·.code)
  == [.errStreak, .ciFailed, .diskLow]
#guard (health {} { now := 0, critical := ["t"], agents := [{ a0 with errTail := 3 }],
                    system := { diskFreeGB := 19, ci := [{ ci0 with branch := "ci/t", conclusion := some "failure" }] } }).alerts.map (·.code)
  == [.ciFailed, .errStreak, .diskLow]
#guard (health {} { now := 0, system := { diskFreeGB := 19, loadFloor := 200 } }).system == [.sysContended, .diskLow, .loadHigh]
-- sys.contended: strictly above contendedLoad (8), with the builders and heavy jobs in the detail
#guard sContended { now := 0, system := { loadFloor := 8 } } == []
#guard sContended { now := 0, system := { loadFloor := 9, load := { builders := 4, heavyJobs := 2 } } } ==
  [⟨.sysContended, "load", "load average 9 (1 min, floor) over 8 CPUs; 4 builders, 2 heavy jobs", false⟩]
-- hysteresis: open above 8; once open, stays open down to calmLoad + 1 = 5 and closes at 4 or below
#guard (sContended { now := 0, system := { loadFloor := 8 } }).isEmpty
#guard (sContended { now := 0, system := { loadFloor := 6, load := { prevContended := true } } }).length == 1
#guard (sContended { now := 0, system := { loadFloor := 6 } }).isEmpty
#guard (sContended { now := 0, system := { loadFloor := 5, load := { prevContended := true } } }).length == 1
#guard (sContended { now := 0, system := { loadFloor := 4, load := { prevContended := true } } }).isEmpty
#guard sortU [⟨.diskLow, "disk", "1", false⟩, ⟨.ctxHigh, "b", "x", false⟩, ⟨.ctxHigh, "a", "x", false⟩,
    ⟨.diskLow, "disk", "1", false⟩, ⟨.worktreesMany, "worktrees", "1", true⟩]
  == [⟨.worktreesMany, "worktrees", "1", true⟩, ⟨.ctxHigh, "a", "x", false⟩, ⟨.ctxHigh, "b", "x", false⟩,
    ⟨.diskLow, "disk", "1", false⟩]

/-! The resource baseline (task sup-baseline): the kind of each running process and the verdict `quiet`, `busy` or `pressured` of one sample. A process counts as heavy only when it is our work, decided by its program name, first argument and ancestry, never by its name alone. -/
namespace Res

/-- The process kinds the 20 s sampler counts. `leanBuild` is a `lake` or `lean` build, `leanServe` the `lake serve` language server and its workers,
`system` a background service no work of ours owns (`CoreSimulatorService`, a WebKit XPC service outside our Safari or Simulator). -/
inductive ProcKind where
  | leanBuild | leanServe | fwcore | node | pnpm | chromium | simulator | webkit | system | other
deriving DecidableEq, Repr

/-- Every kind, in the order the sampler lists them. -/
def ProcKind.all : List ProcKind :=
  [.leanBuild, .leanServe, .fwcore, .node, .pnpm, .chromium, .simulator, .webkit, .system, .other]

theorem ProcKind.mem_all (k : ProcKind) : k ∈ ProcKind.all := by cases k <;> decide

/-- The wire name of a kind. -/
def ProcKind.name : ProcKind → String
  | .leanBuild => "leanBuild" | .leanServe => "leanServe" | .fwcore => "fwcore" | .node => "node" | .pnpm => "pnpm"
  | .chromium => "chromium" | .simulator => "simulator" | .webkit => "webkit" | .system => "system" | .other => "other"

/-- A kind whose presence rules out a quiet machine: our builds, our browsers, our Simulator device and our Safari. -/
def ProcKind.heavy : ProcKind → Bool
  | .leanBuild | .chromium | .simulator | .webkit => true
  | .leanServe | .fwcore | .node | .pnpm | .system | .other => false

theorem ProcKind.heavy_iff (k : ProcKind) : k.heavy = true ↔ k = .leanBuild ∨ k = .chromium ∨ k = .simulator ∨ k = .webkit := by
  cases k <;> simp [ProcKind.heavy]

/-- The always-on background kinds: the language server, the background services and the light tools are never heavy. -/
theorem background_not_heavy (k : ProcKind) (h : k ∈ [ProcKind.leanServe, .fwcore, .node, .pnpm, .system, .other]) :
    k.heavy = false := by
  simp only [List.mem_cons, List.not_mem_nil, or_false] at h
  rcases h with rfl | rfl | rfl | rfl | rfl | rfl <;> rfl

/-- What a program name says about a process before its ancestry and arguments are read. -/
inductive Role where
  | kind (k : ProcKind) | leanTool | simRoot | safari | safariDriver | webkitHelper
deriving DecidableEq, Repr

/-- The wire name of a role. -/
def Role.name : Role → String
  | .kind k => k.name | .leanTool => "leanTool" | .simRoot => "simRoot" | .safari => "safari"
  | .safariDriver => "safariDriver" | .webkitHelper => "webkitHelper"

/-- The allowlist: executable basename to role. Every unlisted name has no role. -/
def kindTable : List (String × Role) := [
  ("lean", .leanTool), ("lake", .leanTool),
  ("fwcore", .kind .fwcore), ("fwtest", .kind .fwcore),
  ("node", .kind .node), ("pnpm", .kind .pnpm),
  ("Chromium", .kind .chromium), ("Chromium Helper", .kind .chromium), ("Chromium Helper (Renderer)", .kind .chromium),
  ("Chromium Helper (GPU)", .kind .chromium), ("chrome-headless-shell", .kind .chromium), ("headless_shell", .kind .chromium),
  ("chrome_crashpad_handler", .kind .chromium),
  ("launchd_sim", .simRoot),
  ("com.apple.CoreSimulator.CoreSimulatorService", .kind .system),
  ("Safari", .safari), ("safaridriver", .safariDriver),
  ("com.apple.WebKit.WebContent", .webkitHelper), ("com.apple.WebKit.Networking", .webkitHelper),
  ("com.apple.WebKit.GPU", .webkitHelper)]

/-- One running process: its pid, parent pid, executable path (`ps comm`) and command line (read only for `lake`, `lean` and `launchd_sim`). -/
structure Proc where
  pid : Nat
  ppid : Nat
  comm : String
  args : String := ""
deriving Repr

/-- A Simulator device by its id and name. -/
structure Device where
  udid : String
  name : String
deriving Repr

/-- The program name of a `ps` command: the part after the last `/`, else the first word of a retitled process. -/
def argv0Base (comm : String) : String :=
  if comm.contains '/' then (comm.splitOn "/").getLastD comm else (comm.splitOn " ").headD comm

/-- The role of a process by its program name only. -/
def roleOf (p : Proc) : Option Role := kindTable.lookup (argv0Base p.comm)

/-- A non-empty `sub` occurs in `s`. -/
def hasSub (s sub : String) : Bool := !sub.isEmpty && 1 < (s.splitOn sub).length

/-- The first argument of a command line: its second word. -/
def firstArg (args : String) : String := ((args.splitOn " ").drop 1).headD ""

/-- The language-server verbs: `lake serve`, `lean --server`, `lean --worker`. -/
def serveVerb (args : String) : Bool :=
  firstArg args == "serve" || firstArg args == "--server" || firstArg args == "--worker"

/-- The Simulator devices of ours are the ones named `fw-…`. -/
def ourDevice (d : Device) : Bool := d.name.startsWith "fw-"

/-- The `launchd_sim` of a booted device of ours: its command line holds the device id. -/
def isOurSimRoot (devs : List Device) (p : Proc) : Bool :=
  roleOf p == some .simRoot && devs.any fun d => ourDevice d && hasSub p.args d.udid

/-- A `lake serve`, `lean --server` or `lean --worker` process. -/
def isServeRoot (p : Proc) : Bool := roleOf p == some .leanTool && serveVerb p.args

/-- A `safaridriver` process. -/
def isDriver (p : Proc) : Bool := roleOf p == some .safariDriver

/-- A Safari process. -/
def isSafari (p : Proc) : Bool := roleOf p == some .safari

/-- A process whose ancestors include a Safari that a `safaridriver` started. -/
def underOurSafari (anc : List Proc) : Bool := anc.any isSafari && anc.any isDriver

/-- **The kind of a process** from its own program name and arguments and the list of its ancestors (parent first).
A process inside the `launchd_sim` of a booted device of ours is `simulator`. `lake` and `lean` are `leanServe` when they or an ancestor run the
language server, else `leanBuild`. Safari is `webkit` when a `safaridriver` started it, else `other`. A WebKit service is `webkit` under such a Safari,
else `system`. A `launchd_sim` of another device is `other`. -/
def kindAt (devs : List Device) (p : Proc) (anc : List Proc) : ProcKind :=
  if (p :: anc).any (isOurSimRoot devs) then .simulator
  else match roleOf p with
    | some (.kind k) => k
    | some .leanTool => if (p :: anc).any isServeRoot then .leanServe else .leanBuild
    | some .safari => if anc.any isDriver then .webkit else .other
    | some .webkitHelper => if underOurSafari anc then .webkit else .system
    | some .simRoot => .other
    | some .safariDriver => .other
    | none => .other

/-- The ancestors of `p`, parent first, by at most `n` steps (a parent loop stops). -/
def ancestors (ps : List Proc) : Nat → Proc → List Proc
  | 0, _ => []
  | n + 1, p =>
    match ps.find? (fun q => q.pid == p.ppid && q.pid != p.pid) with
    | none => []
    | some q => q :: ancestors ps n q

/-- The kind of a process among all running ones. -/
def kindOf (devs : List Device) (ps : List Proc) (p : Proc) : ProcKind := kindAt devs p (ancestors ps ps.length p)

/-- The kind of each running process, in order. -/
def kindsOf (devs : List Device) (ps : List Proc) : List ProcKind := ps.map (kindOf devs ps)

/-- The listed names are distinct, so each has one role. -/
theorem kindTable_nodup : (kindTable.map Prod.fst).Nodup := by decide

theorem lookup_of_mem : ∀ (l : List (String × Role)), (l.map Prod.fst).Nodup →
    ∀ a k, (a, k) ∈ l → l.lookup a = some k
  | [], _, _, _, h => by simp at h
  | (b, v) :: t, hn, a, k, h => by
    rw [List.map_cons, List.nodup_cons] at hn
    rcases List.mem_cons.mp h with h | h
    · obtain ⟨rfl, rfl⟩ := Prod.mk.inj h
      simp [List.lookup]
    · have hne : a ≠ b := fun e => hn.1 (List.mem_map.mpr ⟨(a, k), h, e⟩)
      simp only [List.lookup, beq_false_of_ne hne]
      exact lookup_of_mem t hn.2 a k h

theorem mem_of_lookup : ∀ (l : List (String × Role)) (a : String) (k : Role), l.lookup a = some k → (a, k) ∈ l
  | [], _, _, h => by simp [List.lookup] at h
  | (b, v) :: t, a, k, h => by
    by_cases e : a = b
    · subst e
      simp [List.lookup] at h
      simp [h]
    · simp only [List.lookup, beq_false_of_ne e] at h
      exact List.mem_cons_of_mem _ (mem_of_lookup t a k h)

/-- The kinds a bare program name may give: none of them is an owned or heavy-by-identity kind. -/
def plainKinds : List ProcKind := [.fwcore, .node, .pnpm, .chromium, .system]

/-- Only `plainKinds` come from the name table alone, so `simulator`, `webkit`, `leanBuild` and `leanServe` need identity. -/
theorem kindTable_plain : ∀ e ∈ kindTable, ∀ k ∈ ProcKind.all, e.2 = Role.kind k → k ∈ plainKinds := by decide

theorem plain_of_role (p : Proc) (k : ProcKind) (h : roleOf p = some (.kind k)) : k ∈ plainKinds :=
  kindTable_plain _ (mem_of_lookup _ _ _ h) k k.mem_all rfl

/-- A name on the allowlist as a plain kind gets that kind, outside a Simulator of ours. -/
theorem kindAt_plain (devs : List Device) (p : Proc) (anc : List Proc) (k : ProcKind) (h : roleOf p = some (.kind k))
    (hs : (p :: anc).any (isOurSimRoot devs) = false) : kindAt devs p anc = k := by
  simp [kindAt, hs, h]

/-- A name off the allowlist is `other`, outside a Simulator of ours. -/
theorem kindAt_unlisted (devs : List Device) (p : Proc) (anc : List Proc) (h : roleOf p = none)
    (hs : (p :: anc).any (isOurSimRoot devs) = false) : kindAt devs p anc = .other := by
  simp [kindAt, hs, h]

/-- A process inside the `launchd_sim` of a booted device of ours is `simulator`. -/
theorem simulator_of_sim_root (devs : List Device) (p : Proc) (anc : List Proc) (h : (p :: anc).any (isOurSimRoot devs) = true) :
    kindAt devs p anc = .simulator := by
  simp [kindAt, h]

/-- Only a process inside the `launchd_sim` of a booted device of ours is `simulator`. -/
theorem sim_root_of_simulator (devs : List Device) (p : Proc) (anc : List Proc) (h : kindAt devs p anc = .simulator) :
    (p :: anc).any (isOurSimRoot devs) = true := by
  by_cases hs0 : (p :: anc).any (isOurSimRoot devs) = true
  · exact hs0
  have hs : (p :: anc).any (isOurSimRoot devs) = false := by simpa using hs0
  cases hr : roleOf p with
  | none => simp [kindAt, hs, hr] at h
  | some r =>
    cases r with
    | kind k =>
      have := plain_of_role p k hr
      simp only [kindAt, hs, hr] at h
      subst h
      simp [plainKinds] at this
    | leanTool => by_cases c : (p :: anc).any isServeRoot = true <;> simp [kindAt, hs, hr, c] at h
    | safari => by_cases c : anc.any isDriver = true <;> simp [kindAt, hs, hr, c] at h
    | webkitHelper => by_cases c : underOurSafari anc = true <;> simp [kindAt, hs, hr, c] at h
    | simRoot => simp [kindAt, hs, hr] at h
    | safariDriver => simp [kindAt, hs, hr] at h

/-- Only a Safari that a `safaridriver` started, or a WebKit service under one, is `webkit`: a `webkit` process has a `safaridriver` ancestor. -/
theorem driver_of_webkit (devs : List Device) (p : Proc) (anc : List Proc) (h : kindAt devs p anc = .webkit) :
    anc.any isDriver = true := by
  by_cases hs : (p :: anc).any (isOurSimRoot devs) = true
  · simp [kindAt, hs] at h
  · have hs' : (p :: anc).any (isOurSimRoot devs) = false := by simpa using hs
    cases hr : roleOf p with
    | none => simp [kindAt, hs', hr] at h
    | some r =>
      cases r with
      | kind k =>
        have := plain_of_role p k hr
        simp only [kindAt, hs', hr] at h
        subst h
        simp [plainKinds] at this
      | leanTool => by_cases c : (p :: anc).any isServeRoot = true <;> simp [kindAt, hs', hr, c] at h
      | safari => by_cases c : anc.any isDriver = true
                  · exact c
                  · simp [kindAt, hs', hr, c] at h
      | webkitHelper => by_cases c : underOurSafari anc = true
                        · simp only [underOurSafari, Bool.and_eq_true] at c
                          exact c.2
                        · simp [kindAt, hs', hr, c] at h
      | simRoot => simp [kindAt, hs', hr] at h
      | safariDriver => simp [kindAt, hs', hr] at h

/-- A `lake` or `lean` that no language server owns is a build: `leanBuild` implies a lean tool and no server among it and its ancestors. -/
theorem leanBuild_not_serving (devs : List Device) (p : Proc) (anc : List Proc) (h : kindAt devs p anc = .leanBuild) :
    roleOf p = some .leanTool ∧ (p :: anc).any isServeRoot = false := by
  by_cases hs : (p :: anc).any (isOurSimRoot devs) = true
  · simp [kindAt, hs] at h
  · have hs' : (p :: anc).any (isOurSimRoot devs) = false := by simpa using hs
    cases hr : roleOf p with
    | none => simp [kindAt, hs', hr] at h
    | some r =>
      cases r with
      | kind k =>
        have := plain_of_role p k hr
        simp only [kindAt, hs', hr] at h
        subst h
        simp [plainKinds] at this
      | leanTool =>
        refine ⟨rfl, ?_⟩
        by_cases c : (p :: anc).any isServeRoot = true
        · simp [kindAt, hs', hr, c] at h
        · simpa using c
      | safari => by_cases c : anc.any isDriver = true <;> simp [kindAt, hs', hr, c] at h
      | webkitHelper => by_cases c : underOurSafari anc = true <;> simp [kindAt, hs', hr, c] at h
      | simRoot => simp [kindAt, hs', hr] at h
      | safariDriver => simp [kindAt, hs', hr] at h

/-- A `lake` or `lean` under a language-server process (or being one), outside our Simulator, is `leanServe`. -/
theorem leanServe_of_serve (devs : List Device) (p : Proc) (anc : List Proc) (hr : roleOf p = some .leanTool)
    (hs : (p :: anc).any (isOurSimRoot devs) = false) (hv : (p :: anc).any isServeRoot = true) : kindAt devs p anc = .leanServe := by
  simp [kindAt, hs, hr, hv]

/-- A WebKit service with no Safari of ours above it is `system`, whatever its parent is. -/
theorem system_of_unowned_helper (devs : List Device) (p : Proc) (anc : List Proc) (hr : roleOf p = some .webkitHelper)
    (hs : (p :: anc).any (isOurSimRoot devs) = false) (hu : underOurSafari anc = false) : kindAt devs p anc = .system := by
  simp [kindAt, hs, hr, hu]

/-- A Safari with no `safaridriver` above it is `other`. -/
theorem other_of_unowned_safari (devs : List Device) (p : Proc) (anc : List Proc) (hr : roleOf p = some .safari)
    (hs : (p :: anc).any (isOurSimRoot devs) = false) (hd : anc.any isDriver = false) : kindAt devs p anc = .other := by
  simp [kindAt, hs, hr, hd]

/-- The thresholds: pressured at swap use, compressor size or free memory (percent); busy at load (hundredths).
All four are first guesses, revised after the first day of data. `swapPct` is the one flagged for revision: macOS adds swap files on demand, so swap
used over swap total sits near a fixed high ratio and need not follow memory pressure; the free percentage is `memory_pressure`'s system-wide figure. -/
structure Params where
  swapPct : Nat := 90
  cmprsPct : Nat := 50
  freePct : Nat := 15
  quietCenti : Nat := 200

/-- One sample: the kind of each running process, 1-min load times 100, swap, compressor and RAM in MB, free memory in percent. -/
structure Obs where
  procs : List ProcKind := []
  loadCenti : Nat := 0
  swapUsedMB : Nat := 0
  swapTotalMB : Nat := 0
  compressorMB : Nat := 0
  ramMB : Nat := 0
  freePct : Nat := 100

/-- The three verdicts, in order of pressure. -/
inductive Verdict where
  | quiet | busy | pressured
deriving DecidableEq, Repr

/-- The pressure rank of a verdict. -/
def Verdict.rank : Verdict → Nat
  | .quiet => 0 | .busy => 1 | .pressured => 2

/-- Swap use at or above `swapPct` percent of the swap total (as `Fw.Sched.Heavy.swapHigh`); the swap total grows on demand, so this ratio is a dynamic-swap reading. -/
def swapHigh (p : Params) (o : Obs) : Bool := decide (0 < o.swapTotalMB ∧ p.swapPct * o.swapTotalMB ≤ 100 * o.swapUsedMB)

/-- Compressor at or above `cmprsPct` percent of RAM. -/
def cmprsHigh (p : Params) (o : Obs) : Bool := decide (0 < o.ramMB ∧ p.cmprsPct * o.ramMB ≤ 100 * o.compressorMB)

/-- Free memory at or below `freePct` percent. -/
def freeLow (p : Params) (o : Obs) : Bool := decide (o.freePct ≤ p.freePct)

/-- Some process of a heavy kind runs. -/
def heavyRunning (o : Obs) : Bool := o.procs.any ProcKind.heavy

/-- The 1-min load is at or above `quietCenti` hundredths. -/
def loadBusy (p : Params) (o : Obs) : Bool := decide (p.quietCenti ≤ o.loadCenti)

/-- Memory pressure: swap, compressor or free memory. -/
def pressuredB (p : Params) (o : Obs) : Bool := swapHigh p o || cmprsHigh p o || freeLow p o

/-- **The verdict of a sample**: `pressured` on memory, else `busy` on a heavy process or load, else `quiet`. -/
def verdict (p : Params) (o : Obs) : Verdict :=
  if pressuredB p o then .pressured else if heavyRunning o || loadBusy p o then .busy else .quiet

/-- Pressured exactly when swap, compressor or free memory trips. -/
theorem pressured_iff (p : Params) (o : Obs) :
    verdict p o = .pressured ↔ swapHigh p o = true ∨ cmprsHigh p o = true ∨ freeLow p o = true := by
  cases hh : heavyRunning o <;> cases hl : loadBusy p o <;> cases hs : swapHigh p o <;> cases hc : cmprsHigh p o <;>
    cases hf : freeLow p o <;> simp [verdict, pressuredB, hh, hl, hs, hc, hf]

theorem pressured_of_swap (p : Params) (o : Obs) (h : swapHigh p o = true) : verdict p o = .pressured :=
  (pressured_iff p o).2 (Or.inl h)

theorem pressured_of_cmprs (p : Params) (o : Obs) (h : cmprsHigh p o = true) : verdict p o = .pressured :=
  (pressured_iff p o).2 (Or.inr (Or.inl h))

theorem pressured_of_free (p : Params) (o : Obs) (h : freeLow p o = true) : verdict p o = .pressured :=
  (pressured_iff p o).2 (Or.inr (Or.inr h))

/-- Busy exactly when memory is fine and a heavy process runs or the load is high. -/
theorem busy_iff (p : Params) (o : Obs) :
    verdict p o = .busy ↔ pressuredB p o = false ∧ (heavyRunning o = true ∨ loadBusy p o = true) := by
  cases hh : heavyRunning o <;> cases hl : loadBusy p o <;> cases hp : pressuredB p o <;> simp [verdict, hh, hl, hp]

theorem busy_of_heavy (p : Params) (o : Obs) (hp : pressuredB p o = false) (h : heavyRunning o = true) :
    verdict p o = .busy :=
  (busy_iff p o).2 ⟨hp, Or.inl h⟩

theorem busy_of_load (p : Params) (o : Obs) (hp : pressuredB p o = false) (h : loadBusy p o = true) :
    verdict p o = .busy :=
  (busy_iff p o).2 ⟨hp, Or.inr h⟩

/-- Quiet exactly when memory is fine, no heavy process runs and the load is low. -/
theorem quiet_iff (p : Params) (o : Obs) :
    verdict p o = .quiet ↔ pressuredB p o = false ∧ heavyRunning o = false ∧ loadBusy p o = false := by
  cases hh : heavyRunning o <;> cases hl : loadBusy p o <;> cases hp : pressuredB p o <;> simp [verdict, hh, hl, hp]

/-- **A quiet sample has no process of a heavy kind.** -/
theorem quiet_no_heavy (p : Params) (o : Obs) (h : verdict p o = .quiet) : ∀ k ∈ o.procs, k.heavy = false := by
  intro k hk
  have := ((quiet_iff p o).1 h).2.1
  simp only [heavyRunning, List.any_eq_false] at this
  simpa using this k hk

/-- A quiet sample has a load below `quietCenti`. -/
theorem quiet_low_load (p : Params) (o : Obs) (h : verdict p o = .quiet) : o.loadCenti < p.quietCenti := by
  have := ((quiet_iff p o).1 h).2.2
  simp only [loadBusy, decide_eq_false_iff_not, Nat.not_le] at this
  exact this

/-- `o'` is at least as pressed as `o`: more processes, load, swap and compressor, less free memory, same totals. -/
structure Obs.Le (o o' : Obs) : Prop where
  procs : ∀ k ∈ o.procs, k ∈ o'.procs
  load : o.loadCenti ≤ o'.loadCenti
  swap : o.swapUsedMB ≤ o'.swapUsedMB
  swapTotal : o.swapTotalMB = o'.swapTotalMB
  cmprs : o.compressorMB ≤ o'.compressorMB
  ram : o.ramMB = o'.ramMB
  free : o'.freePct ≤ o.freePct

/-- The verdict never lowers as pressure grows. -/
theorem verdict_rank_mono (p : Params) (o o' : Obs) (h : Obs.Le o o') : (verdict p o).rank ≤ (verdict p o').rank := by
  have hs : swapHigh p o = true → swapHigh p o' = true := by
    simp only [swapHigh, decide_eq_true_eq]
    rw [← h.swapTotal]
    intro ⟨a, b⟩
    exact ⟨a, Nat.le_trans b (Nat.mul_le_mul_left 100 h.swap)⟩
  have hc : cmprsHigh p o = true → cmprsHigh p o' = true := by
    simp only [cmprsHigh, decide_eq_true_eq]
    rw [← h.ram]
    intro ⟨a, b⟩
    exact ⟨a, Nat.le_trans b (Nat.mul_le_mul_left 100 h.cmprs)⟩
  have hf : freeLow p o = true → freeLow p o' = true := by
    simp only [freeLow, decide_eq_true_eq]
    exact fun a => Nat.le_trans h.free a
  have hh : heavyRunning o = true → heavyRunning o' = true := by
    simp only [heavyRunning, List.any_eq_true]
    exact fun ⟨k, hk, hv⟩ => ⟨k, h.procs k hk, hv⟩
  have hl : loadBusy p o = true → loadBusy p o' = true := by
    simp only [loadBusy, decide_eq_true_eq]
    exact fun a => Nat.le_trans a h.load
  have hP : pressuredB p o = true → pressuredB p o' = true := by
    simp only [pressuredB, Bool.or_eq_true]
    rintro ((a | a) | a)
    · exact Or.inl (Or.inl (hs a))
    · exact Or.inl (Or.inr (hc a))
    · exact Or.inr (hf a)
  have hB : (heavyRunning o || loadBusy p o) = true → (heavyRunning o' || loadBusy p o') = true := by
    simp only [Bool.or_eq_true]
    exact fun b => b.elim (fun x => Or.inl (hh x)) (fun x => Or.inr (hl x))
  unfold verdict
  cases e1 : pressuredB p o <;> cases e2 : pressuredB p o' <;> cases e3 : (heavyRunning o || loadBusy p o) <;>
    cases e4 : (heavyRunning o' || loadBusy p o') <;> simp_all [Verdict.rank]

/-- A quiet machine with only background processes: the language server, a Simulator service, a system WebContent and light tools. -/
theorem quiet_with_background :
    verdict {} { procs := [.leanServe, .leanServe, .system, .system, .node, .pnpm, .fwcore, .other], loadCenti := 50, freePct := 50 } = .quiet := by
  decide

/-- A quiet sample is reachable with every background kind present, and one heavy kind alone makes it busy. -/
theorem busy_with_one_heavy (k : ProcKind) (hk : k.heavy = true) :
    verdict {} { procs := [.leanServe, .system, k], loadCenti := 50, freePct := 50 } = .busy := by
  rcases (ProcKind.heavy_iff k).1 hk with rfl | rfl | rfl | rfl <;> decide

/-- The always-on background processes are not heavy, outside a Simulator of ours: a `CoreSimulatorService`, a WebKit service with no Safari of
ours above it, and a `lake`/`lean` under a language server. -/
theorem background_procs_not_heavy (devs : List Device) (p : Proc) (anc : List Proc) (hs : (p :: anc).any (isOurSimRoot devs) = false)
    (h : roleOf p = some (.kind .system) ∨ (roleOf p = some .webkitHelper ∧ underOurSafari anc = false) ∨
      (roleOf p = some .leanTool ∧ (p :: anc).any isServeRoot = true)) : (kindAt devs p anc).heavy = false := by
  rcases h with h | ⟨h, hu⟩ | ⟨h, hv⟩
  · rw [kindAt_plain devs p anc _ h hs]; rfl
  · rw [system_of_unowned_helper devs p anc h hs hu]; rfl
  · rw [leanServe_of_serve devs p anc h hs hv]; rfl

private def pr (pid ppid : Nat) (comm : String) (args : String := "") : Proc := ⟨pid, ppid, comm, args⟩

#guard argv0Base "/Users/x/.nvm/versions/node/v24.22.0/bin/node" == "node"
#guard argv0Base "node server.js" == "node"
#guard argv0Base "/Applications/Chromium.app/Contents/Frameworks/Chromium Helper (Renderer).app/Contents/MacOS/Chromium Helper (Renderer)" == "Chromium Helper (Renderer)"
#guard argv0Base "/Users/x/node/not-node" == "not-node"
#guard argv0Base "" == ""
-- background processes with no owner of ours
#guard kindsOf [] [pr 1 0 "/sbin/launchd", pr 10 1 "/L/CoreSimulator.framework/XPCServices/com.apple.CoreSimulator.CoreSimulatorService.xpc/Contents/MacOS/com.apple.CoreSimulator.CoreSimulatorService",
    pr 11 1 "/S/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
    pr 12 20 "/e/bin/lean" "/e/bin/lean --server", pr 20 30 "/e/bin/lake" "/e/bin/lake serve -- -D"]
  == [.other, .system, .system, .leanServe, .leanServe]
-- a build is heavy, its children too
#guard kindsOf [] [pr 20 1 "/e/bin/lake" "/e/bin/lake build", pr 21 20 "/e/bin/lean" "/e/bin/lean -R x"] == [.leanBuild, .leanBuild]
-- a booted device of ours: the whole subtree is simulator; another device and another process of the same name are not
#guard kindsOf [⟨"AAAA", "fw-sim 15"⟩] [pr 5 1 "/R/sbin/launchd_sim" "/R/sbin/launchd_sim /D/AAAA/data/var/run/launchd_bootstrap.plist",
    pr 6 5 "/R/usr/libexec/backboardd", pr 7 6 "/R/usr/libexec/some-daemon", pr 8 1 "/R/usr/libexec/some-daemon"] == [.simulator, .simulator, .simulator, .other]
#guard kindsOf [⟨"BBBB", "iPhone 17"⟩] [pr 5 1 "/R/sbin/launchd_sim" "/R/sbin/launchd_sim /D/BBBB/data", pr 6 5 "/R/usr/libexec/backboardd"] == [.other, .other]
#guard verdict {} { procs := kindsOf [] [pr 10 1 "/x/com.apple.CoreSimulator.CoreSimulatorService", pr 11 1 "/x/com.apple.WebKit.WebContent",
    pr 12 1 "/e/bin/lake" "/e/bin/lake serve"], loadCenti := 50, freePct := 50 } == .quiet
private def simTree : List Proc := [pr 5 1 "/R/sbin/launchd_sim" "/R/sbin/launchd_sim /D/AAAA/data", pr 6 5 "/R/backboardd"]
#guard verdict {} { procs := kindsOf [⟨"AAAA", "fw-sim"⟩] simTree, loadCenti := 50, freePct := 50 } == .busy
#guard verdict {} {} == .quiet
#guard verdict {} { procs := [.node, .other] } == .quiet
#guard verdict {} { procs := [.leanServe, .system] } == .quiet
#guard verdict {} { procs := [.leanBuild] } == .busy
#guard verdict {} { loadCenti := 200 } == .busy
#guard verdict {} { loadCenti := 199 } == .quiet
#guard verdict {} { swapUsedMB := 900, swapTotalMB := 1000 } == .pressured
#guard verdict {} { swapUsedMB := 899, swapTotalMB := 1000 } == .quiet
#guard verdict {} { swapUsedMB := 900 } == .quiet
#guard verdict {} { compressorMB := 50, ramMB := 100 } == .pressured
#guard verdict {} { compressorMB := 49, ramMB := 100 } == .quiet
#guard verdict {} { freePct := 15 } == .pressured
#guard verdict {} { freePct := 16 } == .quiet
#guard verdict {} { procs := [.leanBuild], freePct := 10 } == .pressured

end Res

end Fw.Obs.Health
