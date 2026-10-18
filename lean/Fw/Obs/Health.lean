import Fw.Obs.Stale
/-!
# Team health: per-agent state and alert rules over one observation snapshot

`fw watch` (task `watch-cli`) collects one snapshot per interval: every agent's kind, timing and tool facts, the lead
session's last tool event and last notification, plus system, simulator-lock, Docker, worktree, CI, load and local
process facts, the time of the previous check and the task ids on the console's critical path. This module is the pure
part: from the snapshot and the thresholds it derives each agent's state (`active`, `idle`, `parked`, `stalled`,
`gone`, `done`) and a sorted, duplicate-free list of alerts. The wire op `obs.health` (`Fw.Wire.Obs`) is its JSON face.

Units: times are ms since the epoch (`Nat`); the `…Min` thresholds are minutes ($\mu = 60000$ ms each); an age is the
truncated difference $\mathit{now} \mathbin{\dot-} t$ (a timestamp after `now` has age 0). Context sizes are tokens,
disk is whole GB, the load average is its floor (an integer threshold $L$ is reached by the load exactly when it is
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
for more than `procMaxMin`, see below), `sys.loadHigh` (1-min load average at or above `loadMax`).

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
  `sys.loadHigh` fire.
* `procLong_iff`, `ownerLive_quiet`, `declared_quiet`, `procLong_sound`, `orphan_raised`: a live agent's process tree
  and a declared long-runner never raise `proc.long`; every `proc.long` alert is an undeclared tree older than
  `procMaxMin` whose owner is not live; an orphan of an ended agent does raise it.
* `svcStale_iff`, `staleAlert_fields`, `sStale_restart` (rule and proofs in `Fw.Obs.Stale`): `svc.stale` fires for a
  service exactly when an input changed on `main` since its base commit (start or build); a restart clears it.
* `alerts_sorted`, `crit_first`, `mem_alerts`, `health_perm`: the alert list is strictly sorted (critical first, then
  code, subject, detail), holds exactly the raised alerts, and does not depend on the order of the agents.
-/
namespace Fw.Obs.Health

/-- Milliseconds per minute, the unit of every `…Min` threshold.

$$\mu = 60000$$
-/
def msPerMin : Nat := 60000

/-- The thresholds. Upper thresholds reached at or above (a value equal to the threshold alerts): `idleMin`,
`stallMin`, `toolHangMin` (minutes), `errStreak` (failed calls), `simLockMaxMin` (minutes), `loadMax` (1-min load
average); upper thresholds passed only strictly above (a value equal to the threshold does not alert): `ctxResumeMax`,
`ctxWarn` (tokens), `agentCap` (live non-lead agents), `worktreesMax`, `ciSlowMin`, `toolSlowMin`, `procMaxMin`
(minutes); the lower threshold `diskMinGB` (free GB strictly below it alerts); and two thresholds that decide which
agents have ended (they are not alert thresholds): `wfQuietMin`, the minutes without an event after which a workflow
agent seen only in its transcript counts as done, and `goneAfterMin`, the minutes strictly above which any agent
without an event counts as gone.

$$p = (\mathit{idle}, \mathit{stall}, \mathit{hang}, \mathit{err}, \mathit{ctxMax}, \mathit{ctxWarn}, \mathit{diskMin}, \mathit{cap}, \mathit{simMax}, \mathit{wtMax}, \mathit{wfQuiet}, \mathit{goneAfter}, \mathit{ciSlowMin}, \mathit{toolSlow}, \mathit{procMax}, \mathit{loadMax}) \in \mathbb N^{16}$$
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
deriving DecidableEq, Repr

/-- A tool call still running: the tool's name and its start time (ms).

$$f = (\mathit{tool}, \mathit{since}) \in \mathrm{String} \times \mathbb N$$
-/
structure Inflight where
  tool  : String
  since : Nat
deriving DecidableEq, Repr

/-- How an agent was started: the lead session itself, a teammate (idles between messages on purpose), a subagent
(spawned by the `Agent` tool), or a workflow agent (spawned by a workflow run).

$$\mathcal K = \{\mathrm{lead}, \mathrm{teammate}, \mathrm{subagent}, \mathrm{workflow}\}$$
-/
inductive Kind where
  | lead | teammate | subagent | workflow
deriving DecidableEq, Repr

/-- One agent as observed: id, optional name and task (a lock holder may name either), kind, the id of the agent
that spawned it (`none` when the lead did, or unknown), start, last event and stop times (ms; `stoppedAt` is `none`
while it runs), the number of failed tool calls at the end of its log, the tool call in flight, the name and time of
its last finished tool call, the time of its last `TeammateIdle` event, whether its workflow run has finished, whether
it is seen only in its transcript (no hook event), and its context size.

$$a = (\mathit{id}, \mathit{name}_\bot, \mathit{task}_\bot, k, \mathit{parent}_\bot, \mathit{start}, \mathit{last}, \mathit{stop}_\bot, \mathit{errTail}, f_\bot, \mathit{lastTool}_\bot, \mathit{lastToolAt}_\bot, \mathit{idleAt}_\bot, \mathit{wfDone}, \mathit{trOnly}, \mathit{ctx}_\bot)$$
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
deriving DecidableEq, Repr

/-- The lead session's facts: the time of its last finished tool call and of the last `Notification` hook event
(which carries no agent id), each `none` when there was none.

$$\ell = (\mathit{lastToolAt}_\bot, \mathit{noteAt}_\bot)$$
-/
structure Lead where
  lastToolAt : Option Nat := none
  noteAt     : Option Nat := none
deriving DecidableEq, Repr

/-- Memory pressure as macOS reports it.

$$\mathcal M = \{\mathrm{normal}, \mathrm{warn}, \mathrm{critical}\}$$
-/
inductive Mem where
  | normal | warn | critical
deriving DecidableEq, Repr

/-- The simulator lock: its holder (a free-form owner string) and since when it is held.

$$L = (\mathit{holder}_\bot, \mathit{since}_\bot)$$
-/
structure SimLock where
  holder : Option String := none
  since  : Option Nat := none
deriving DecidableEq, Repr

/-- A running Docker container: id, name, start time (ms).

$$c = (\mathit{id}, \mathit{name}, \mathit{start}) \in \mathrm{String}^2 \times \mathbb N$$
-/
structure Container where
  id        : String
  name      : String
  startedAt : Nat
deriving DecidableEq, Repr

/-- A CI run: workflow, branch, status, conclusion (`none` while running), start time and end time (ms; `endedAt` is
the run's last update, `none` when unknown).

$$r = (\mathit{wf}, \mathit{br}, \mathit{status}, \mathit{concl}_\bot, \mathit{start}, \mathit{end}_\bot)$$
-/
structure CiRun where
  workflow   : String
  branch     : String
  status     : String
  conclusion : Option String := none
  startedAt  : Nat
  endedAt    : Option Nat := none
deriving DecidableEq, Repr

/-- A local process tree started by the observed session (one Bash tool call): the pid of its root, the program name
of its first command (never the command line), its start time (ms), every other pid in the tree, and the id of the
agent whose Bash call started it (`none`: the lead session, or not known).

$$q = (\mathit{pid}, \mathit{name}, \mathit{start}, P, \mathit{owner}_\bot) \in \mathbb N \times \mathrm{String} \times \mathbb N \times \mathbb N^* \times \mathrm{String}_\bot,\quad \mathit{owner}(q) = \mathit{owner}_\bot \ \text{(the last component)}$$
-/
structure Proc where
  pid       : Nat
  name      : String
  startedAt : Nat
  pids      : List Nat := []
  agent     : Option String := none
deriving DecidableEq, Repr

/-- The machine-level facts the rules read: free disk (GB), memory pressure, the simulator lock, running containers,
the number of git worktrees, recent CI runs, the floor of the 1-min load average, the session's process trees, the
service pids (long-running on purpose: the console server, the watcher itself), and the pids the lead declared as
intended long-runners (`fw watch --keep`).

$$\Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
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
deriving DecidableEq, Repr

/-- One observation: the time it was taken (ms), the agents, the lead session's facts, the system facts, the time of
the previous check (`none` for the first), and the task ids on the console's critical path.

$$o = (\mathit{now}, A, \ell, \Sigma, \mathit{prev}_\bot, K)$$
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

/-- The six agent states.

$$\mathcal S = \{\mathrm{active}, \mathrm{idle}, \mathrm{parked}, \mathrm{stalled}, \mathrm{gone}, \mathrm{done}\}$$
-/
inductive State where
  | active | idle | parked | stalled | gone | done
deriving DecidableEq, Repr

/-- Whether an agent has stopped: it stopped, or it is a workflow agent whose workflow run finished, or a workflow
agent seen only in its transcript with no event for `wfQuietMin` minutes.

$$\operatorname{stopped}(p, t, a) \iff \mathit{stop}(a) \ne \bot \vee \bigl(k(a) = \mathrm{workflow} \wedge (\mathit{wfDone}(a) \vee (\mathit{trOnly}(a) \wedge \mu\,\mathit{wfQuiet} \le t \mathbin{\dot-} \mathit{last}(a)))\bigr)$$
-/
def stopped (p : Params) (now : Nat) (a : Agent) : Bool :=
  a.stoppedAt.isSome ||
    (a.kind == .workflow && (a.workflowDone || (a.transcriptOnly && decide (p.wfQuietMin * msPerMin ≤ now - a.lastAt))))

/-- Whether an agent is gone: no event for strictly more than `goneAfterMin` minutes (stopped by hand, no stop hook).

$$\operatorname{gone}(p, t, a) \iff \mu\,\mathit{goneAfter} < t \mathbin{\dot-} \mathit{last}(a)$$
-/
def goneB (p : Params) (now : Nat) (a : Agent) : Bool := decide (p.goneAfterMin * msPerMin < now - a.lastAt)

/-- Whether an agent has ended: it stopped or it is gone.

$$\operatorname{ended}(p, t, a) \iff \operatorname{stopped}(p, t, a) \vee \operatorname{gone}(p, t, a)$$
-/
def ended (p : Params) (now : Nat) (a : Agent) : Bool := stopped p now a || goneB p now a

/-- Whether an agent is live (has not ended).

$$\operatorname{live}(p, t, a) \iff \neg \operatorname{ended}(p, t, a)$$
-/
def live (p : Params) (now : Nat) (a : Agent) : Bool := !ended p now a

/-- Whether a `TeammateIdle` event is newer than the last finished tool call (any such event counts when no tool call
has finished).

$$\operatorname{idleNewer}(a) \iff \exists i.\ \mathit{idleAt}(a) = i \wedge \forall s.\ \mathit{lastToolAt}(a) = s \Rightarrow s < i$$
-/
def idleNewer (a : Agent) : Bool :=
  match a.idleAt with
  | none => false
  | some i => match a.lastToolAt with
    | none => true
    | some s => decide (s < i)

/-- Whether an agent is parked: a teammate with no tool in flight whose last finished tool call was `SendMessage`, or
whose last `TeammateIdle` is newer than its last finished tool call (it waits for a message on purpose).

$$\operatorname{parked}(a) \iff k(a) = \mathrm{teammate} \wedge f(a) = \bot \wedge (\mathit{lastTool}(a) = \texttt{SendMessage} \vee \operatorname{idleNewer}(a))$$
-/
def parkedB (a : Agent) : Bool :=
  a.kind == .teammate && a.inflight.isNone && (a.lastTool == some "SendMessage" || idleNewer a)

/-- The tools whose call waits for another agent.

$$\operatorname{waitTool}(s) \iff s \in \{\texttt{Agent}, \texttt{SendMessage}\}$$
-/
def waitTool (s : String) : Bool := s == "Agent" || s == "SendMessage"

/-- Whether some live agent of the list names `a` as its parent.

$$\operatorname{child}(p, t, A, a) \iff \exists b \in A.\ \operatorname{live}(p, t, b) \wedge \mathit{parent}(b) = \mathit{id}(a)$$
-/
def hasLiveChild (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Bool :=
  agents.any fun b => live p now b && b.parent == some a.id

/-- Whether the tool call in flight has hung: it has run for `toolHangMin` minutes and it is not a wait (an `Agent` or
`SendMessage` call while a child of the agent is live).

$$\operatorname{hung}(p, t, A, a) \iff \exists \varphi.\ f(a) = \varphi \wedge \neg(\operatorname{waitTool}(\mathit{tool}(\varphi)) \wedge \operatorname{child}(p, t, A, a)) \wedge \mu\,\mathit{hang} \le t \mathbin{\dot-} \mathit{since}(\varphi)$$
-/
def hungB (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Bool :=
  match a.inflight with
  | none => false
  | some f => !(waitTool f.tool && hasLiveChild p now agents a) && decide (p.toolHangMin * msPerMin ≤ now - f.since)

/-- The stall test as a Boolean: no event for `stallMin` minutes, and no tool in flight or the one in flight has hung.

$$\operatorname{stallB}(p, t, A, a) \iff \mu\,\mathit{stall} \le t \mathbin{\dot-} \mathit{last}(a) \wedge (f(a) = \bot \vee \operatorname{hung}(p, t, A, a))$$
-/
def stallB (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Bool :=
  decide (p.stallMin * msPerMin ≤ now - a.lastAt) && (a.inflight.isNone || hungB p now agents a)

/-- The stall condition as a proposition.

$$\operatorname{Stall}(p, t, A, a) \iff \mu\,\mathit{stall} \le t \mathbin{\dot-} \mathit{last}(a) \wedge \forall \varphi.\ f(a) = \varphi \Rightarrow \big(\neg(\operatorname{waitTool}(\mathit{tool}(\varphi)) \wedge \operatorname{child}(p, t, A, a)) \wedge \mu\,\mathit{hang} \le t \mathbin{\dot-} \mathit{since}(\varphi)\big)$$
-/
def Stall (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Prop :=
  p.stallMin * msPerMin ≤ now - a.lastAt ∧
    ∀ f, a.inflight = some f →
      ¬ (waitTool f.tool = true ∧ hasLiveChild p now agents a = true) ∧ p.toolHangMin * msPerMin ≤ now - f.since

/-- The Boolean stall test decides `Stall`.

$$\forall p, t, A, a:\quad \operatorname{stallB}(p, t, A, a) = \mathrm{true} \iff \operatorname{Stall}(p, t, A, a)$$
-/
theorem stallB_iff (p : Params) (t : Nat) (A : List Agent) (a : Agent) : stallB p t A a = true ↔ Stall p t A a := by
  unfold stallB Stall hungB
  cases h : a.inflight with
  | none => simp
  | some f => cases waitTool f.tool <;> cases hasLiveChild p t A a <;> simp

/-- An agent's state: done once stopped; else gone when silent for more than `goneAfterMin`; else parked (a teammate
waiting for a message on purpose); else stalled when the stall test holds; else idle after `idleMin` minutes without an
event; else active.

$$\operatorname{state}(p, t, A, a) = \begin{cases} \mathrm{done} & \operatorname{stopped}(p, t, a) \\ \mathrm{gone} & \text{else if } \operatorname{gone}(p, t, a) \\ \mathrm{parked} & \text{else if } \operatorname{parked}(a) \\ \mathrm{stalled} & \text{else if } \operatorname{Stall}(p, t, A, a) \\ \mathrm{idle} & \text{else if } \mu\,\mathit{idle} \le t \mathbin{\dot-} \mathit{last}(a) \\ \mathrm{active} & \text{otherwise} \end{cases}$$
-/
def state (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : State :=
  if stopped p now a then .done
  else if goneB p now a then .gone
  else if parkedB a then .parked
  else if stallB p now agents a then .stalled
  else if p.idleMin * msPerMin ≤ now - a.lastAt then .idle
  else .active

/-- Done exactly when stopped.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{done} \iff \operatorname{stopped}(p, t, a)$$
-/
theorem state_done (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .done ↔ stopped p t a = true := by
  unfold state
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Gone exactly when not stopped and gone.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{gone} \iff \neg\operatorname{stopped}(p, t, a) \wedge \operatorname{gone}(p, t, a)$$
-/
theorem state_gone (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .gone ↔ stopped p t a = false ∧ goneB p t a = true := by
  unfold state
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Parked exactly when not ended and parked.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{parked} \iff \neg\operatorname{ended}(p, t, a) \wedge \operatorname{parked}(a)$$
-/
theorem state_parked (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .parked ↔ ended p t a = false ∧ parkedB a = true := by
  unfold state ended
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Stalled exactly when not ended, not parked and the stall condition holds.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{stalled} \iff \neg\operatorname{ended}(p, t, a) \wedge \neg\operatorname{parked}(a) \wedge \operatorname{Stall}(p, t, A, a)$$
-/
theorem state_stalled (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .stalled ↔ ended p t a = false ∧ parkedB a = false ∧ Stall p t A a := by
  rw [← stallB_iff]
  unfold state ended
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Idle exactly when not ended, not parked, not stalled and without an event for `idleMin` minutes.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{idle} \iff \neg\operatorname{ended}(p, t, a) \wedge \neg\operatorname{parked}(a) \wedge \neg\operatorname{Stall}(p, t, A, a) \wedge \mu\,\mathit{idle} \le t \mathbin{\dot-} \mathit{last}(a)$$
-/
theorem state_idle (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .idle ↔ ended p t a = false ∧ parkedB a = false ∧ ¬ Stall p t A a ∧
      p.idleMin * msPerMin ≤ t - a.lastAt := by
  rw [← stallB_iff]
  unfold state ended
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp_all

/-- Active exactly when not ended, not parked, not stalled and with an event within `idleMin` minutes.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{active} \iff \neg\operatorname{ended}(p, t, a) \wedge \neg\operatorname{parked}(a) \wedge \neg\operatorname{Stall}(p, t, A, a) \wedge t \mathbin{\dot-} \mathit{last}(a) < \mu\,\mathit{idle}$$
-/
theorem state_active (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .active ↔ ended p t a = false ∧ parkedB a = false ∧ ¬ Stall p t A a ∧
      t - a.lastAt < p.idleMin * msPerMin := by
  rw [← stallB_iff]
  unfold state ended
  cases stopped p t a <;> cases goneB p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp_all <;> omega

/-- Every agent has exactly one state: the state is one of the six, and two different states never hold together
(with `state_done` … `state_active`, the six rule conditions partition all agents).

$$\forall p, t, A, a:\quad \operatorname{state}(p,t,A,a) \in \mathcal S \quad\text{and}\quad \forall s, s' \in \mathcal S:\ \operatorname{state}(p,t,A,a) = s \wedge \operatorname{state}(p,t,A,a) = s' \Rightarrow s = s'$$
-/
theorem state_cases (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    (state p t A a = .active ∨ state p t A a = .idle ∨ state p t A a = .parked ∨ state p t A a = .stalled ∨
      state p t A a = .gone ∨ state p t A a = .done) ∧
    ∀ s s' : State, state p t A a = s → state p t A a = s' → s = s' := by
  refine ⟨?_, fun s s' h h' => h ▸ h'⟩
  cases state p t A a <;> simp

/-- A stalled agent is not parked, and it has had no event for at least `stallMin` minutes.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{stalled} \Rightarrow \neg\operatorname{parked}(a) \wedge \mu\,\mathit{stall} \le t \mathbin{\dot-} \mathit{last}(a)$$
-/
theorem stalled_facts (p : Params) (t : Nat) (A : List Agent) (a : Agent) (h : state p t A a = .stalled) :
    parkedB a = false ∧ p.stallMin * msPerMin ≤ t - a.lastAt := by
  obtain ⟨_, hw, hs, _⟩ := (state_stalled p t A a).1 h
  exact ⟨hw, hs⟩

/-! ## Alerts -/

/-- The alert codes, listed in the order of their wire names.

$$\mathcal C = \{\texttt{agent.ctxHigh}, \texttt{agent.ctxWarn}, \texttt{agent.errStreak}, \texttt{agent.gone}, \texttt{agent.stalled}, \texttt{agent.toolHang}, \texttt{agent.toolSlow}, \texttt{ci.failed}, \texttt{ci.finished}, \texttt{ci.slow}, \texttt{docker.orphan}, \texttt{proc.long}, \texttt{sim.lockLong}, \texttt{sim.lockOrphan}, \texttt{svc.stale}, \texttt{sys.diskLow}, \texttt{sys.loadHigh}, \texttt{sys.memCritical}, \texttt{team.overCap}, \texttt{team.permissionWait}, \texttt{worktrees.many}\}$$
-/
inductive Code where
  | ctxHigh | ctxWarn | errStreak | gone | stalled | toolHang | toolSlow
  | ciFailed | ciFinished | ciSlow | dockerOrphan | procLong | simLockLong | simLockOrphan | svcStale | diskLow | loadHigh
  | memCritical | overCap | permissionWait | worktreesMany
deriving DecidableEq, Repr

/-- Every code, in rank order.

$$\mathcal C = (c_0, \ldots, c_{20})$$
-/
def Code.all : List Code :=
  [.ctxHigh, .ctxWarn, .errStreak, .gone, .stalled, .toolHang, .toolSlow,
   .ciFailed, .ciFinished, .ciSlow, .dockerOrphan, .procLong, .simLockLong, .simLockOrphan, .svcStale, .diskLow, .loadHigh,
   .memCritical, .overCap, .permissionWait, .worktreesMany]

/-- The wire name of a code.

$$\operatorname{name}(c_i) = \text{the } i\text{-th string of } \mathcal C$$
-/
def Code.name : Code → String
  | .ctxHigh => "agent.ctxHigh" | .ctxWarn => "agent.ctxWarn" | .errStreak => "agent.errStreak"
  | .gone => "agent.gone" | .stalled => "agent.stalled" | .toolHang => "agent.toolHang"
  | .toolSlow => "agent.toolSlow" | .ciFailed => "ci.failed" | .ciFinished => "ci.finished" | .ciSlow => "ci.slow"
  | .dockerOrphan => "docker.orphan" | .procLong => "proc.long" | .simLockLong => "sim.lockLong"
  | .simLockOrphan => "sim.lockOrphan" | .svcStale => "svc.stale" | .diskLow => "sys.diskLow" | .loadHigh => "sys.loadHigh"
  | .memCritical => "sys.memCritical" | .overCap => "team.overCap" | .permissionWait => "team.permissionWait"
  | .worktreesMany => "worktrees.many"

/-- The rank of a code (its position in `Code.all`).

$$\operatorname{rank}(c_i) = i$$
-/
def Code.rank : Code → Nat
  | .ctxHigh => 0 | .ctxWarn => 1 | .errStreak => 2 | .gone => 3 | .stalled => 4 | .toolHang => 5 | .toolSlow => 6
  | .ciFailed => 7 | .ciFinished => 8 | .ciSlow => 9 | .dockerOrphan => 10 | .procLong => 11 | .simLockLong => 12
  | .simLockOrphan => 13 | .svcStale => 14 | .diskLow => 15 | .loadHigh => 16 | .memCritical => 17 | .overCap => 18
  | .permissionWait => 19 | .worktreesMany => 20

/-- Whether a code is about one agent (`agent.*`).

$$\operatorname{isAgent}(c) \iff \operatorname{rank}(c) < 7$$
-/
def Code.isAgent (c : Code) : Bool := c.rank < 7

/-- The rank determines the code.

$$\forall c, c' \in \mathcal C:\quad \operatorname{rank}(c) = \operatorname{rank}(c') \Rightarrow c = c'$$
-/
theorem Code.rank_inj (c c' : Code) (h : c.rank = c'.rank) : c = c' := by
  cases c <;> cases c' <;> simp_all [Code.rank]

/-- Rank order is the order of the wire names: the names in rank order are strictly increasing strings.

$$\operatorname{name}(c_0) < \operatorname{name}(c_1) < \cdots < \operatorname{name}(c_{20}) \quad\text{(lexicographic)}$$
-/
theorem Code.names_sorted : (Code.all.map Code.name).Pairwise (· < ·) := by decide

/-- An alert: its code, its subject (an agent id, `team`, `lead`, `disk`, `memory`, `load`, `sim`, `workflow@branch`,
a container name, `name#pid` of a process or `worktrees`), a detail text built from measured values only (never from a
threshold), and whether it is tied to the critical path.

$$x = (\mathit{code}, \mathit{subject}, \mathit{detail}, \mathit{crit}) \in \mathcal C \times \mathrm{String}^2 \times \mathbb B$$
-/
structure Alert where
  code    : Code
  subject : String
  detail  : String
  crit    : Bool := false
deriving DecidableEq, Repr

/-- The order within one criticality: by code rank, then subject, then detail (strings lexicographic).

$$x \prec_0 y \iff \operatorname{rank}(x) < \operatorname{rank}(y) \vee (\operatorname{rank}(x) = \operatorname{rank}(y) \wedge (\mathit{subj}(x) < \mathit{subj}(y) \vee (\mathit{subj}(x) = \mathit{subj}(y) \wedge \mathit{det}(x) < \mathit{det}(y))))$$
-/
def Alert.Lt0 (x y : Alert) : Prop :=
  x.code.rank < y.code.rank ∨
    (x.code.rank = y.code.rank ∧ (x.subject < y.subject ∨ (x.subject = y.subject ∧ x.detail < y.detail)))

/-- The output order: critical alerts first, then by code rank, subject and detail.

$$x \prec y \iff (\mathit{crit}(x) \wedge \neg\mathit{crit}(y)) \vee (\mathit{crit}(x) = \mathit{crit}(y) \wedge x \prec_0 y)$$
-/
def Alert.Lt (x y : Alert) : Prop :=
  (x.crit = true ∧ y.crit = false) ∨ (x.crit = y.crit ∧ Alert.Lt0 x y)

instance (x y : Alert) : Decidable (Alert.Lt0 x y) := by unfold Alert.Lt0; infer_instance
instance (x y : Alert) : Decidable (Alert.Lt x y) := by unfold Alert.Lt; infer_instance

/-- The order is irreflexive.

$$\forall x:\quad \neg (x \prec x)$$
-/
theorem Alert.lt_irrefl (x : Alert) : ¬ Alert.Lt x x := by
  unfold Alert.Lt Alert.Lt0
  have := String.lt_irrefl x.subject
  have := String.lt_irrefl x.detail
  cases x.crit <;> simp_all

/-- The order within one criticality is transitive.

$$\forall x, y, z:\quad x \prec_0 y \wedge y \prec_0 z \Rightarrow x \prec_0 z$$
-/
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

/-- The order is transitive.

$$\forall x, y, z:\quad x \prec y \wedge y \prec z \Rightarrow x \prec z$$
-/
theorem Alert.lt_trans {x y z : Alert} (h₁ : Alert.Lt x y) (h₂ : Alert.Lt y z) : Alert.Lt x z := by
  unfold Alert.Lt at *
  rcases h₁ with ⟨a₁, b₁⟩ | ⟨e₁, l₁⟩ <;> rcases h₂ with ⟨a₂, b₂⟩ | ⟨e₂, l₂⟩
  · rw [b₁] at a₂; cases a₂
  · exact .inl ⟨a₁, e₂ ▸ b₁⟩
  · exact .inl ⟨e₁ ▸ a₂, b₂⟩
  · exact .inr ⟨e₁.trans e₂, Alert.lt0_trans l₁ l₂⟩

/-- Two different strings are ordered one way or the other.

$$\forall a, b \in \mathrm{String}:\quad a \ne b \Rightarrow a < b \vee b < a$$
-/
theorem str_trich {a b : String} (h : a ≠ b) : a < b ∨ b < a := by
  by_cases h₁ : a < b
  · exact .inl h₁
  · by_cases h₂ : b < a
    · exact .inr h₂
    · exact absurd (String.le_antisymm (String.not_lt.1 h₂) (String.not_lt.1 h₁)) h

/-- The order is total on different alerts.

$$\forall x, y:\quad x \ne y \Rightarrow x \prec y \vee y \prec x$$
-/
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

/-- Insert into a strictly sorted list, dropping an exact duplicate.

$$\operatorname{ins}(x, []) = [x], \quad \operatorname{ins}(x, y{:}ys) = \begin{cases} x{:}y{:}ys & x \prec y \\ y{:}ys & x = y \\ y{:}\operatorname{ins}(x, ys) & \text{otherwise} \end{cases}$$
-/
def ins (x : Alert) : List Alert → List Alert
  | [] => [x]
  | y :: ys => if Alert.Lt x y then x :: y :: ys else if x = y then y :: ys else y :: ins x ys

/-- Sort and deduplicate: insert every element into the empty list.

$$\operatorname{sortU}(l) = \operatorname{foldr}(\operatorname{ins}, [], l)$$
-/
def sortU (l : List Alert) : List Alert := l.foldr ins []

/-- Insertion adds exactly its element.

$$\forall x, z, l:\quad z \in \operatorname{ins}(x, l) \iff z = x \vee z \in l$$
-/
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

/-- Insertion keeps a list strictly sorted.

$$\forall x, l:\quad \operatorname{sorted}_\prec(l) \Rightarrow \operatorname{sorted}_\prec(\operatorname{ins}(x, l))$$
-/
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

/-- `sortU` keeps exactly the members.

$$\forall z, l:\quad z \in \operatorname{sortU}(l) \iff z \in l$$
-/
theorem mem_sortU (z : Alert) (l : List Alert) : z ∈ sortU l ↔ z ∈ l := by
  induction l with
  | nil => simp [sortU]
  | cons y ys ih => simp only [sortU, List.foldr_cons] at *; rw [mem_ins, ih]; simp

/-- `sortU` is strictly sorted.

$$\forall l:\quad \operatorname{sorted}_\prec(\operatorname{sortU}(l))$$
-/
theorem sorted_sortU (l : List Alert) : (sortU l).Pairwise Alert.Lt := by
  induction l with
  | nil => simp [sortU]
  | cons y ys ih => exact sorted_ins y _ ih

/-- Two strictly sorted lists with the same members are equal.

$$\forall l, l':\quad \operatorname{sorted}_\prec(l) \wedge \operatorname{sorted}_\prec(l') \wedge (\forall z:\ z \in l \iff z \in l') \Rightarrow l = l'$$
-/
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

/-- An alert if the condition holds, else nothing.

$$\operatorname{when}(b, x) = \begin{cases} [x] & b \\ [] & \neg b \end{cases}$$
-/
def when (b : Bool) (x : Alert) : List Alert := if b then [x] else []

/-- Membership in `when`.

$$\forall b, x, z:\quad z \in \operatorname{when}(b, x) \iff b \wedge z = x$$
-/
theorem mem_when (b : Bool) (x z : Alert) : z ∈ when b x ↔ b = true ∧ z = x := by
  cases b <;> simp [when]

/-- Whole minutes in a duration (for alert details).

$$\operatorname{mins}(d) = \lfloor d / \mu \rfloor$$
-/
def mins (d : Nat) : Nat := d / msPerMin

/-- Whether the tool call in flight is slow: it has run for strictly more than `toolSlowMin` minutes and it is not a
wait (an `Agent` or `SendMessage` call while a child of the agent is live).

$$\operatorname{slow}(p, t, A, a) \iff \exists \varphi.\ f(a) = \varphi \wedge \neg(\operatorname{waitTool}(\mathit{tool}(\varphi)) \wedge \operatorname{child}(p, t, A, a)) \wedge \mu\,\mathit{toolSlow} < t \mathbin{\dot-} \mathit{since}(\varphi)$$
-/
def slowB (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : Bool :=
  match a.inflight with
  | none => false
  | some f => !(waitTool f.tool && hasLiveChild p now agents a) && decide (p.toolSlowMin * msPerMin < now - f.since)

/-- The detail text of a tool call in flight: its tool and whole minutes running (empty when none is in flight).

$$\delta(t, a) = \begin{cases} \text{“}\mathit{tool}(\varphi)\text{ running for }\operatorname{mins}(t \mathbin{\dot-} \mathit{since}(\varphi))\text{ min”} & f(a) = \varphi \\ \varepsilon & f(a) = \bot \end{cases}$$
-/
def toolDetail (now : Nat) (a : Agent) : String :=
  match a.inflight with
  | some f => s!"{f.tool} running for {mins (now - f.since)} min"
  | none => ""

/-- The `agent.*` alerts of one live agent (none once it has ended, i.e. stopped or gone, or is parked), in code
order: context over `ctxResumeMax` (do not resume it), context over `ctxWarn`, at least `errStreak` (and at least one)
failed calls in a row, stalled, a tool hung, a tool slow. An unknown context size counts as 0. Every alert has
$\mathit{crit} = \mathrm{false}$ here (`agentAll` marks it).

$$\operatorname{agentAlerts}(p, t, A, a) = \begin{cases} [] & \operatorname{ended}(p, t, a) \vee \operatorname{parked}(a) \\ \operatorname{when}(\kappa > \mathit{ctxMax}, (\texttt{ctxHigh}, \mathit{id}(a), \text{“}\kappa\text{ context tokens”})) \mathbin{+\!\!+} \operatorname{when}(\kappa > \mathit{ctxWarn}, (\texttt{ctxWarn}, \mathit{id}(a), \text{“}\kappa\text{ context tokens”})) \\ \quad \mathbin{+\!\!+} \operatorname{when}(\mathit{errTail}(a) \ge \max(\mathit{err}, 1), (\texttt{errStreak}, \mathit{id}(a), \text{“}\mathit{errTail}(a)\text{ failed tool calls in a row”})) \\ \quad \mathbin{+\!\!+} \operatorname{when}(\operatorname{stallB}(p, t, A, a), (\texttt{stalled}, \mathit{id}(a), \text{“no event for }\operatorname{mins}(t \mathbin{\dot-} \mathit{last}(a))\text{ min”})) \\ \quad \mathbin{+\!\!+} \operatorname{when}(\operatorname{hung}(p, t, A, a), (\texttt{toolHang}, \mathit{id}(a), \delta(t, a))) \mathbin{+\!\!+} \operatorname{when}(\operatorname{slow}(p, t, A, a), (\texttt{toolSlow}, \mathit{id}(a), \delta(t, a))) & \text{otherwise} \end{cases},\quad \text{where } \kappa = \begin{cases} \mathit{ctx}(a) & \mathit{ctx}(a) \ne \bot \\ 0 & \mathit{ctx}(a) = \bot \end{cases}\ \text{(numbers in decimal)}$$
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

$$\operatorname{newGone}(p, q_\bot, a) \iff q_\bot = \bot \vee \exists q.\ q_\bot = q \wedge \neg\operatorname{gone}(p, q, a)$$
-/
def newGone (p : Params) (prev : Option Nat) (a : Agent) : Bool :=
  match prev with
  | none => true
  | some q => !goneB p q a

/-- The `agent.gone` alert of an agent: raised once, at the first check where the agent is gone (state `gone`) and the
previous check did not see it gone.

$$\operatorname{goneAlert}(p, o, a) = \operatorname{when}\bigl(\neg\operatorname{stopped}(p, t, a) \wedge \operatorname{gone}(p, t, a) \wedge \operatorname{newGone}(p, \mathit{prev}, a),\ (\texttt{agent.gone}, \mathit{id}(a), \text{“no event for }\operatorname{mins}(t \mathbin{\dot-} \mathit{last}(a))\text{ min”}, \mathrm{false})\bigr),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
-/
def goneAlert (p : Params) (o : Obs) (a : Agent) : List Alert :=
  when (!stopped p o.now a && goneB p o.now a && newGone p o.prevAt a)
    ⟨.gone, a.id, s!"no event for {mins (o.now - a.lastAt)} min", false⟩

/-- Whether a string is tied to a task id: it equals the id, or the id followed by `-` and one or more decimal digits
(a respawned agent `task-2`).

$$\operatorname{tied}(c, s) \iff s = c \vee \exists d \in \{0,\ldots,9\}^+.\ s = c \mathbin{+\!\!+} \texttt{-} \mathbin{+\!\!+} d$$
-/
def tiedTo (c s : String) : Bool :=
  s == c ||
    (let pre := (c ++ "-").toList
     let l := s.toList
     l.take pre.length == pre && !(l.drop pre.length).isEmpty && (l.drop pre.length).all Char.isDigit)

/-- Whether an agent works on a critical-path task: its id, name or task is tied to a task id of $K$.

$$\operatorname{critA}(K, a) \iff \exists c \in K.\ \operatorname{tied}(c, \mathit{id}(a)) \vee (\exists s.\ \mathit{name}(a) = s \wedge \operatorname{tied}(c, s)) \vee (\exists s.\ \mathit{task}(a) = s \wedge \operatorname{tied}(c, s))$$
-/
def critAgent (K : List String) (a : Agent) : Bool :=
  K.any fun c => tiedTo c a.id || a.name.any (tiedTo c) || a.task.any (tiedTo c)

/-- Whether a CI run belongs to a critical-path task: its branch is tied to `ci/` followed by a task id of $K$.

$$\operatorname{critR}(K, r) \iff \exists c \in K.\ \operatorname{tied}(\texttt{ci/} \mathbin{+\!\!+} c, \mathit{br}(r))$$
-/
def critCi (K : List String) (r : CiRun) : Bool := K.any fun c => tiedTo ("ci/" ++ c) r.branch

/-- Set an alert's critical flag.

$$\operatorname{mark}(k, (c, s, d, k')) = (c, s, d, k)$$
-/
def mark (k : Bool) (x : Alert) : Alert := { x with crit := k }

/-- Every `agent.*` alert of one agent: its `agent.gone` alert and its live-agent alerts, each marked critical when
the agent works on a critical-path task.

$$\operatorname{agentAll}(p, o, a) = \operatorname{map}\bigl(\operatorname{mark}(\operatorname{critA}(K, a)),\ \operatorname{goneAlert}(p, o, a) \mathbin{+\!\!+} \operatorname{agentAlerts}(p, t, A, a)\bigr),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
-/
def agentAll (p : Params) (o : Obs) (a : Agent) : List Alert :=
  (goneAlert p o a ++ agentAlerts p o.now o.agents a).map (mark (critAgent o.critical a))

/-- A done, gone or parked agent raises no live-agent alert.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) \in \{\mathrm{done}, \mathrm{gone}, \mathrm{parked}\} \Rightarrow \operatorname{agentAlerts}(p, t, A, a) = []$$
-/
theorem agentAlerts_quiet (p : Params) (t : Nat) (A : List Agent) (a : Agent)
    (h : state p t A a = .done ∨ state p t A a = .gone ∨ state p t A a = .parked) : agentAlerts p t A a = [] := by
  unfold agentAlerts
  rcases h with h | h | h
  · simp [ended, (state_done p t A a).1 h]
  · simp [ended, ((state_gone p t A a).1 h).2]
  · simp [((state_parked p t A a).1 h).2]

/-- A live-agent alert of an agent is an `agent.*` alert about that agent, not critical.

$$\forall p, t, A, a, x:\quad x \in \operatorname{agentAlerts}(p, t, A, a) \Rightarrow \operatorname{isAgent}(\mathit{code}(x)) \wedge \mathit{subj}(x) = \mathit{id}(a) \wedge \neg\mathit{crit}(x)$$
-/
theorem agentAlerts_subject (p : Params) (t : Nat) (A : List Agent) (a : Agent) (x : Alert)
    (h : x ∈ agentAlerts p t A a) : x.code.isAgent = true ∧ x.subject = a.id ∧ x.crit = false := by
  unfold agentAlerts at h
  split at h
  · simp at h
  · simp only [List.mem_append, mem_when] at h
    rcases h with ((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩ <;> subst e <;>
      simp [Code.isAgent, Code.rank]

/-- A live-agent alert is never `agent.gone`.

$$\forall p, t, A, a, x:\quad x \in \operatorname{agentAlerts}(p, t, A, a) \Rightarrow \mathit{code}(x) \ne \texttt{agent.gone}$$
-/
theorem agentAlerts_not_gone (p : Params) (t : Nat) (A : List Agent) (a : Agent) (x : Alert)
    (h : x ∈ agentAlerts p t A a) : x.code ≠ .gone := by
  unfold agentAlerts at h
  split at h
  · simp at h
  · simp only [List.mem_append, mem_when] at h
    rcases h with ((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩ <;> subst e <;> simp

/-- Every alert of an agent (`agentAll`) is an `agent.*` alert about that agent.

$$\forall p, o, a, x:\quad x \in \operatorname{agentAll}(p, o, a) \Rightarrow \operatorname{isAgent}(\mathit{code}(x)) \wedge \mathit{subj}(x) = \mathit{id}(a)$$
-/
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

/-- A gone agent raises only `agent.gone`: every alert of a gone agent has that code.

$$\forall p, o, a, x:\quad \operatorname{state}(p, t, A, a) = \mathrm{gone} \wedge x \in \operatorname{agentAll}(p, o, a) \Rightarrow \mathit{code}(x) = \texttt{agent.gone},\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
-/
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

$$\forall p, o, a:\quad (\exists x \in \operatorname{agentAll}(p, o, a).\ \mathit{code}(x) = \texttt{agent.gone}) \iff \operatorname{state}(p, t, A, a) = \mathrm{gone} \wedge \operatorname{newGone}(p, \mathit{prev}, a),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
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

$$\forall p, t, A, a, \varphi:\quad f(a) = \varphi \wedge \operatorname{waitTool}(\mathit{tool}(\varphi)) \wedge \operatorname{child}(p, t, A, a) \Rightarrow \neg\operatorname{hung}(p, t, A, a) \wedge \neg\operatorname{slow}(p, t, A, a) \wedge \operatorname{state}(p, t, A, a) \ne \mathrm{stalled} \wedge \forall x \in \operatorname{agentAlerts}(p, t, A, a).\ \mathit{code}(x) \notin \{\texttt{agent.toolHang}, \texttt{agent.toolSlow}\}$$
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

/-- Whether a lock owner string names an agent: its id, name or task.

$$\operatorname{names}(h, a) \iff h = \mathit{id}(a) \vee \mathit{name}(a) = h \vee \mathit{task}(a) = h$$
-/
def names (h : String) (a : Agent) : Bool := a.id == h || a.name == some h || a.task == some h

/-- Whether the simulator lock is orphaned: it has a holder and no live agent is named by it.

$$\operatorname{orphanB}(p, t, A, L) \iff \exists h.\ \mathit{holder}(L) = h \wedge \neg \exists a \in A.\ \operatorname{live}(p, t, a) \wedge \operatorname{names}(h, a)$$
-/
def orphanB (p : Params) (now : Nat) (agents : List Agent) (l : SimLock) : Bool :=
  match l.holder with
  | none => false
  | some h => !agents.any fun a => live p now a && names h a

/-- A CI conclusion that counts as a failure.

$$\operatorname{ciFailing}(r) \iff \mathit{concl}(r) \in \{\texttt{failure}, \texttt{timed\_out}, \texttt{startup\_failure}\}$$
-/
def ciFailing (r : CiRun) : Bool :=
  r.conclusion == some "failure" || r.conclusion == some "timed_out" || r.conclusion == some "startup_failure"

/-- Whether a run is the latest of its workflow and branch (no run of the same pair started later).

$$\operatorname{ciLatest}(R, r) \iff \forall r' \in R:\ (\mathit{wf}, \mathit{br})(r') = (\mathit{wf}, \mathit{br})(r) \Rightarrow \mathit{start}(r') \le \mathit{start}(r)$$
-/
def ciLatest (runs : List CiRun) (r : CiRun) : Bool :=
  runs.all fun r' => !(r'.workflow == r.workflow && r'.branch == r.branch) || decide (r'.startedAt ≤ r.startedAt)

/-- Whether a run is waiting or running (status queued, in_progress, waiting, requested or pending).

$$\operatorname{running}(r) \iff \mathit{status}(r) \in \{\texttt{queued}, \texttt{in\_progress}, \texttt{waiting}, \texttt{requested}, \texttt{pending}\}$$
-/
def ciRunning (r : CiRun) : Bool :=
  r.status == "queued" || r.status == "in_progress" || r.status == "waiting" || r.status == "requested" ||
    r.status == "pending"

/-- Whether a run is slow: waiting or running for strictly more than `ciSlowMin` minutes since it started.

$$\operatorname{ciSlow}(p, t, r) \iff \operatorname{running}(r) \wedge \mu\,\mathit{ciSlowMin} < t \mathbin{\dot-} \mathit{start}(r)$$
-/
def ciSlowB (p : Params) (now : Nat) (r : CiRun) : Bool :=
  ciRunning r && decide (p.ciSlowMin * msPerMin < now - r.startedAt)

/-- Whether a run that the previous check flagged as slow has finished since: it is completed, it ended after the
previous check's time $q$, and at $q$ it had run for strictly more than `ciSlowMin` minutes (so it was still running
at $q$ and `ci.slow` was raised). False on the first check or without an end time.

$$\operatorname{ciFin}(p, q_\bot, r) \iff \exists q, e.\ q_\bot = q \wedge \mathit{end}(r) = e \wedge \mathit{status}(r) = \texttt{completed} \wedge q < e \wedge \mu\,\mathit{ciSlowMin} < q \mathbin{\dot-} \mathit{start}(r)$$
-/
def ciFinishedB (p : Params) (prev : Option Nat) (r : CiRun) : Bool :=
  match prev, r.endedAt with
  | some q, some e => r.status == "completed" && decide (q < e) && decide (p.ciSlowMin * msPerMin < q - r.startedAt)
  | _, _ => false

/-- Whether a container is orphaned: no live agent started at or before it (so none could have started it).

$$\operatorname{dockerOrphan}(p, t, A, c) \iff \neg \exists a \in A.\ \operatorname{live}(p, t, a) \wedge \mathit{start}(a) \le \mathit{start}(c)$$
-/
def dockerOrphanB (p : Params) (now : Nat) (agents : List Agent) (c : Container) : Bool :=
  !agents.any fun a => live p now a && decide (a.startedAt ≤ c.startedAt)

/-- The checked-in allowlist of programs that run for the whole session on purpose: `caffeinate` (keeps the Mac awake).
A change to it is a reviewed edit of this file.

$$\mathit{Keep} = [\texttt{caffeinate}]$$
-/
def keepProgs : List String := ["caffeinate"]

/-- Whether a process tree is an intended long-runner: its name is on the allowlist `keepProgs`, or one of its pids
(root included) is a service pid or a pid the lead declared (`fw watch --keep`).

$$\operatorname{declared}(S, D, q) \iff \mathit{name}(q) \in \mathit{Keep} \vee \exists x \in \mathit{pid}(q) \mathbin{::} P(q).\ x \in S \vee x \in D,\quad \text{where } P(q) = \text{the list of the tree's other pids}$$
-/
def declaredB (services keep : List Nat) (q : Proc) : Bool :=
  keepProgs.contains q.name || (q.pid :: q.pids).any fun x => services.contains x || keep.contains x

/-- Whether the agent whose Bash call started a process tree is live (false when the tree has no owner, i.e. the lead
started it or the owner is not known, and when the owner is not in the agent list).

$$\operatorname{ownerLive}(p, t, A, q) \iff \exists g.\ \mathit{owner}(q) = g \wedge \exists a \in A.\ \mathit{id}(a) = g \wedge \operatorname{live}(p, t, a)$$
-/
def ownerLiveB (p : Params) (now : Nat) (agents : List Agent) (q : Proc) : Bool :=
  match q.agent with
  | none => false
  | some g => agents.any fun a => a.id == g && live p now a

/-- Whether a process tree runs too long: it is not an intended long-runner, the agent that started it is not live
(the lead's own trees, and orphans of ended or gone agents), and it has been alive for strictly more than `procMaxMin`
minutes.

$$\operatorname{procLong}(p, o, q) \iff \neg\operatorname{declared}(S, D, q) \wedge \neg\operatorname{ownerLive}(p, t, A, q) \wedge \mu\,\mathit{procMax} < t \mathbin{\dot-} \mathit{start}(q),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def procLongB (p : Params) (o : Obs) (q : Proc) : Bool :=
  !declaredB o.system.services o.system.keep q && !ownerLiveB p o.now o.agents q &&
    decide (p.procMaxMin * msPerMin < o.now - q.startedAt)

/-- The number of live agents other than the lead session.

$$\operatorname{nLive}(p, t, A) = |[\, a \in A \mid \operatorname{live}(p, t, a) \wedge k(a) \ne \mathrm{lead} \,]|$$
-/
def nLive (p : Params) (now : Nat) (agents : List Agent) : Nat :=
  (agents.filter fun a => live p now a && a.kind != .lead).length

/-- A gone agent does not count as live: adding it to the list leaves `nLive` (and so `team.overCap`) unchanged.

$$\forall p, t, A, a:\quad \operatorname{gone}(p, t, a) \Rightarrow \neg\operatorname{live}(p, t, a) \wedge \operatorname{nLive}(p, t, a : A) = \operatorname{nLive}(p, t, A)$$
-/
theorem nLive_gone (p : Params) (t : Nat) (A : List Agent) (a : Agent) (h : goneB p t a = true) :
    live p t a = false ∧ nLive p t (a :: A) = nLive p t A := by
  have hl : live p t a = false := by simp [live, ended, h]
  exact ⟨hl, by simp [nLive, hl]⟩

/-- The number of live agents of one kind.

$$\operatorname{nKind}(p, t, A, \kappa) = |[\, a \in A \mid \operatorname{live}(p, t, a) \wedge k(a) = \kappa \,]|$$
-/
def nKind (p : Params) (now : Nat) (agents : List Agent) (k : Kind) : Nat :=
  (agents.filter fun a => live p now a && a.kind == k).length

/-- The number of live non-lead agents spawned by another agent (helpers: they have a parent id).

$$\operatorname{nHelpers}(p, t, A) = |[\, a \in A \mid \operatorname{live}(p, t, a) \wedge k(a) \ne \mathrm{lead} \wedge \mathit{parent}(a) \ne \bot \,]|$$
-/
def nHelpers (p : Params) (now : Nat) (agents : List Agent) : Nat :=
  (agents.filter fun a => live p now a && a.kind != .lead && a.parent.isSome).length

/-- Whether a permission prompt may be open in the lead's terminal: a notification exists and it is newer than the
lead session's last finished tool call (any notification counts when no tool call has finished).

$$\operatorname{permB}(\ell) \iff \exists \nu.\ \mathit{noteAt}(\ell) = \nu \wedge \forall s.\ \mathit{lastToolAt}(\ell) = s \Rightarrow s < \nu$$
-/
def permB (l : Lead) : Bool :=
  match l.noteAt with
  | none => false
  | some n => match l.lastToolAt with
    | none => true
    | some s => decide (s < n)

/-! ### Team and system alerts, one piece per code -/

/-- `team.overCap`: more live non-lead agents than `agentCap` (the detail counts them by kind and counts the helpers).

$$\operatorname{sOver}(p, o) = \operatorname{when}\bigl(\mathit{cap} < n,\ (\texttt{team.overCap}, \texttt{team}, \text{“}n\text{ live agents: }k_{\mathrm{teammate}}\text{ teammate, }k_{\mathrm{subagent}}\text{ subagent, }k_{\mathrm{workflow}}\text{ workflow; }h\text{ with a parent agent”}, \mathrm{false})\bigr),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ n = \operatorname{nLive}(p, t, A),\ k_\kappa = \operatorname{nKind}(p, t, A, \kappa),\ h = \operatorname{nHelpers}(p, t, A)\ \text{(numbers in decimal)}$$
-/
def sOver (p : Params) (o : Obs) : List Alert :=
  when (decide (p.agentCap < nLive p o.now o.agents)) ⟨.overCap, "team",
    s!"{nLive p o.now o.agents} live agents: {nKind p o.now o.agents .teammate} teammate, {nKind p o.now o.agents .subagent} subagent, {nKind p o.now o.agents .workflow} workflow; {nHelpers p o.now o.agents} with a parent agent", false⟩

/-- `sys.diskLow`: free disk strictly below `diskMinGB`.

$$\operatorname{sDisk}(p, o) = \operatorname{when}(\mathit{disk} < \mathit{diskMin},\ (\texttt{sys.diskLow}, \texttt{disk}, \text{“}\mathit{disk}\text{ GB free”}, \mathrm{false})),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sDisk (p : Params) (o : Obs) : List Alert :=
  when (decide (o.system.diskFreeGB < p.diskMinGB)) ⟨.diskLow, "disk", s!"{o.system.diskFreeGB} GB free", false⟩

/-- `sys.memCritical`: memory pressure critical.

$$\operatorname{sMem}(o) = \operatorname{when}(m = \mathrm{critical},\ (\texttt{sys.memCritical}, \texttt{memory}, \text{“memory pressure critical”}, \mathrm{false})),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sMem (o : Obs) : List Alert :=
  when (o.system.memPressure == .critical) ⟨.memCritical, "memory", "memory pressure critical", false⟩

/-- `sys.loadHigh`: the floor of the 1-min load average at or above `loadMax`.

$$\operatorname{sLoad}(p, o) = \operatorname{when}(\mathit{loadMax} \le \lambda,\ (\texttt{sys.loadHigh}, \texttt{load}, \text{“load average }\lambda\text{ (1 min, floor)”}, \mathrm{false})),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sLoad (p : Params) (o : Obs) : List Alert :=
  when (decide (p.loadMax ≤ o.system.loadFloor))
    ⟨.loadHigh, "load", s!"load average {o.system.loadFloor} (1 min, floor)", false⟩

/-- `sim.lockLong`: the simulator lock has a holder and a start time and has been held for `simLockMaxMin` minutes.

$$\operatorname{sLockLong}(p, o) = \operatorname{when}\bigl(\mathit{holder}(L) \ne \bot \wedge \exists \sigma.\ \mathit{since}(L) = \sigma \wedge \mu\,\mathit{simMax} \le t \mathbin{\dot-} \sigma,\ (\texttt{sim.lockLong}, \texttt{sim}, \text{“held by }h\text{ for }\operatorname{mins}(t \mathbin{\dot-} \sigma_0)\text{ min”}, \mathrm{false})\bigr),\quad \text{where } h = \begin{cases} \mathit{holder}(L) & \mathit{holder}(L) \ne \bot \\ \varepsilon & \mathit{holder}(L) = \bot \end{cases},\ \sigma_0 = \begin{cases} \mathit{since}(L) & \mathit{since}(L) \ne \bot \\ 0 & \mathit{since}(L) = \bot \end{cases},\ o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sLockLong (p : Params) (o : Obs) : List Alert :=
  when (o.system.simLock.holder.isSome &&
      o.system.simLock.since.any fun s => decide (p.simLockMaxMin * msPerMin ≤ o.now - s))
    ⟨.simLockLong, "sim",
      s!"held by {o.system.simLock.holder.getD ""} for {mins (o.now - o.system.simLock.since.getD 0)} min", false⟩

/-- `sim.lockOrphan`: the simulator lock is orphaned.

$$\operatorname{sOrphan}(p, o) = \operatorname{when}(\operatorname{orphanB}(p, t, A, L),\ (\texttt{sim.lockOrphan}, \texttt{sim}, \text{“held by }h\text{”}, \mathrm{false})),\quad \text{where } h = \begin{cases} \mathit{holder}(L) & \mathit{holder}(L) \ne \bot \\ \varepsilon & \mathit{holder}(L) = \bot \end{cases},\ o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sOrphan (p : Params) (o : Obs) : List Alert :=
  when (orphanB p o.now o.agents o.system.simLock)
    ⟨.simLockOrphan, "sim", s!"held by {o.system.simLock.holder.getD ""}", false⟩

/-- `ci.failed`: the latest run of a workflow and branch failed (critical when the branch is a critical task's).

$$\operatorname{sCiFailed}(o) = [\,(\texttt{ci.failed}, \mathit{wf}(r)\texttt{@}\mathit{br}(r), \text{“latest run }c_\varepsilon(r)\text{”}, \operatorname{critR}(K, r)) \mid r \leftarrow R,\ \operatorname{ciFailing}(r) \wedge \operatorname{ciLatest}(R, r)\,],\quad \text{where } c_\varepsilon(r) = \begin{cases} \mathit{concl}(r) & \mathit{concl}(r) \ne \bot \\ \varepsilon & \mathit{concl}(r) = \bot \end{cases}\ \text{(the order of } R \text{ is kept)},\ o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sCiFailed (o : Obs) : List Alert :=
  (o.system.ci.filter fun r => ciFailing r && ciLatest o.system.ci r).map fun r =>
    ⟨.ciFailed, s!"{r.workflow}@{r.branch}", s!"latest run {r.conclusion.getD ""}", critCi o.critical r⟩

/-- `ci.slow`: a run waiting or running for more than `ciSlowMin` minutes.

$$\operatorname{sCiSlow}(p, o) = [\,(\texttt{ci.slow}, \mathit{wf}(r)\texttt{@}\mathit{br}(r), \text{“}\mathit{status}(r)\text{ for }\operatorname{mins}(t \mathbin{\dot-} \mathit{start}(r))\text{ min”}, \operatorname{critR}(K, r)) \mid r \leftarrow R,\ \operatorname{ciSlow}(p, t, r)\,],\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sCiSlow (p : Params) (o : Obs) : List Alert :=
  (o.system.ci.filter (ciSlowB p o.now)).map fun r =>
    ⟨.ciSlow, s!"{r.workflow}@{r.branch}", s!"{r.status} for {mins (o.now - r.startedAt)} min", critCi o.critical r⟩

/-- `ci.finished`: a run flagged slow by the previous check has finished (once): its conclusion and duration.

$$\operatorname{sCiFin}(p, o) = [\,(\texttt{ci.finished}, \mathit{wf}(r)\texttt{@}\mathit{br}(r), \text{“}c_\varepsilon(r)\text{ after }\operatorname{mins}(e_0(r) \mathbin{\dot-} \mathit{start}(r))\text{ min”}, \operatorname{critR}(K, r)) \mid r \leftarrow R,\ \operatorname{ciFin}(p, \mathit{prev}, r)\,],\quad \text{where } c_\varepsilon(r) = \begin{cases} \mathit{concl}(r) & \mathit{concl}(r) \ne \bot \\ \varepsilon & \mathit{concl}(r) = \bot \end{cases},\ e_0(r) = \begin{cases} \mathit{end}(r) & \mathit{end}(r) \ne \bot \\ 0 & \mathit{end}(r) = \bot \end{cases},\ o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sCiFin (p : Params) (o : Obs) : List Alert :=
  (o.system.ci.filter (ciFinishedB p o.prevAt)).map fun r =>
    ⟨.ciFinished, s!"{r.workflow}@{r.branch}",
      s!"{r.conclusion.getD ""} after {mins (r.endedAt.getD 0 - r.startedAt)} min", critCi o.critical r⟩

/-- `docker.orphan`: an orphaned container.

$$\operatorname{sDocker}(p, o) = [\,(\texttt{docker.orphan}, \mathit{name}(c), \text{“container }\mathit{id}(c)\text{”}, \mathrm{false}) \mid c \leftarrow C,\ \operatorname{dockerOrphan}(p, t, A, c)\,],\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sDocker (p : Params) (o : Obs) : List Alert :=
  (o.system.docker.filter (dockerOrphanB p o.now o.agents)).map fun c =>
    ⟨.dockerOrphan, c.name, s!"container {c.id}", false⟩

/-- The `proc.long` alert of a process tree: subject `name#pid`, detail its age in whole minutes, plus the owner's
id when an agent started it (that agent is not live, so the tree is an orphan).

$$\operatorname{procAlert}(o, q) = \begin{cases} (\texttt{proc.long}, \mathit{name}(q)\texttt{\#}\mathit{pid}(q), \text{“alive }\operatorname{mins}(t \mathbin{\dot-} \mathit{start}(q))\text{ min”}, \mathrm{false}) & \mathit{owner}(q) = \bot \\ (\texttt{proc.long}, \mathit{name}(q)\texttt{\#}\mathit{pid}(q), \text{“alive }\operatorname{mins}(t \mathbin{\dot-} \mathit{start}(q))\text{ min, agent }g\text{ ended”}, \mathrm{false}) & \mathit{owner}(q) = g \end{cases},\quad \text{where } t = \text{the time of } o$$
-/
def procAlert (o : Obs) (q : Proc) : Alert :=
  match q.agent with
  | none => ⟨.procLong, s!"{q.name}#{q.pid}", s!"alive {mins (o.now - q.startedAt)} min", false⟩
  | some g => ⟨.procLong, s!"{q.name}#{q.pid}", s!"alive {mins (o.now - q.startedAt)} min, agent {g} ended", false⟩

/-- Every `proc.long` alert has code `proc.long`.

$$\forall o, q:\quad \mathit{code}(\operatorname{procAlert}(o, q)) = \texttt{proc.long}$$
-/
theorem procAlert_code (o : Obs) (q : Proc) : (procAlert o q).code = .procLong := by
  unfold procAlert; cases q.agent <;> rfl

/-- `proc.long`: a process tree of the session alive too long, not declared, and not owned by a live agent.

$$\operatorname{sProc}(p, o) = [\,\operatorname{procAlert}(o, q) \mid q \leftarrow Q,\ \operatorname{procLong}(p, o, q)\,],\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sProc (p : Params) (o : Obs) : List Alert :=
  (o.system.procs.filter (procLongB p o)).map (procAlert o)

/-- The `svc.stale` alert of a stale service: subject its name, detail the changed input paths (measured values).

$$\operatorname{staleAlert}(s) = (\texttt{svc.stale}, \mathit{name}(s), \text{“changed on main since its commit: ”} \cdot \operatorname{join}(\text{“, ”}, \operatorname{changed}(s)), \mathrm{false})$$
-/
def staleAlert (s : Svc) : Alert :=
  ⟨.svcStale, s.name, "changed on main since its commit: " ++ ", ".intercalate s.changed, false⟩

/-- `svc.stale`: one alert for each service with an input changed on `main` since its base commit.

$$\operatorname{sStale}(o) = [\,\operatorname{staleAlert}(s) \mid s \leftarrow \Sigma.\mathit{svcs},\ \operatorname{stale}(s)\,]$$
-/
def sStale (o : Obs) : List Alert :=
  (o.system.svcs.filter Svc.staleB).map staleAlert

/-- `worktrees.many`: more worktrees than `worktreesMax`.

$$\operatorname{sWt}(p, o) = \operatorname{when}(\mathit{wtMax} < \mathit{wt},\ (\texttt{worktrees.many}, \texttt{worktrees}, \text{“}\mathit{wt}\text{ worktrees”}, \mathrm{false})),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sWt (p : Params) (o : Obs) : List Alert :=
  when (decide (p.worktreesMax < o.system.worktrees)) ⟨.worktreesMany, "worktrees", s!"{o.system.worktrees} worktrees", false⟩

/-- `team.permissionWait`: a notification newer than the lead's last tool call.

$$\operatorname{sPerm}(o) = \operatorname{when}\bigl(\operatorname{permB}(\ell),\ (\texttt{team.permissionWait}, \texttt{lead}, \text{“notification }\operatorname{mins}(t \mathbin{\dot-} \nu_0)\text{ min ago, no lead tool call since”}, \mathrm{false})\bigr),\quad \text{where } \nu_0 = \begin{cases} \mathit{noteAt}(\ell) & \mathit{noteAt}(\ell) \ne \bot \\ 0 & \mathit{noteAt}(\ell) = \bot \end{cases}\ \text{(the second case never occurs when } \operatorname{permB}(\ell) \text{ holds)},\ o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
-/
def sPerm (o : Obs) : List Alert :=
  when (permB o.lead)
    ⟨.permissionWait, "lead", s!"notification {mins (o.now - o.lead.noteAt.getD 0)} min ago, no lead tool call since", false⟩

/-- The team and system alerts: the pieces in code order.

$$\operatorname{sysAlerts}(p, o) = \operatorname{sCiFailed}(o) \mathbin{+\!\!+} \operatorname{sCiFin}(p, o) \mathbin{+\!\!+} \operatorname{sCiSlow}(p, o) \mathbin{+\!\!+} \operatorname{sDocker}(p, o) \mathbin{+\!\!+} \operatorname{sProc}(p, o) \mathbin{+\!\!+} \operatorname{sLockLong}(p, o) \mathbin{+\!\!+} \operatorname{sOrphan}(p, o) \mathbin{+\!\!+} \operatorname{sDisk}(p, o) \mathbin{+\!\!+} \operatorname{sLoad}(p, o) \mathbin{+\!\!+} \operatorname{sMem}(o) \mathbin{+\!\!+} \operatorname{sOver}(p, o) \mathbin{+\!\!+} \operatorname{sPerm}(o) \mathbin{+\!\!+} \operatorname{sWt}(p, o)$$
-/
def sysAlerts (p : Params) (o : Obs) : List Alert :=
  sCiFailed o ++ sCiFin p o ++ sCiSlow p o ++ sDocker p o ++ sProc p o ++ sLockLong p o ++ sOrphan p o ++
    sStale o ++ sDisk p o ++ sLoad p o ++ sMem o ++ sOver p o ++ sPerm o ++ sWt p o

/-- Every raised alert, unsorted: each agent's alerts, then the team and system alerts.

$$\operatorname{raw}(p, o) = \operatorname{flatMap}(\operatorname{agentAll}(p, o), A) \mathbin{+\!\!+} \operatorname{sysAlerts}(p, o)$$
-/
def raw (p : Params) (o : Obs) : List Alert := o.agents.flatMap (agentAll p o) ++ sysAlerts p o

/-- The state counts.

$$n = (n_{\mathrm{active}}, n_{\mathrm{idle}}, n_{\mathrm{parked}}, n_{\mathrm{stalled}}, n_{\mathrm{gone}}, n_{\mathrm{done}}) \in \mathbb N^6$$
-/
structure Counts where
  active  : Nat
  idle    : Nat
  parked  : Nat
  stalled : Nat
  gone    : Nat
  done    : Nat
deriving DecidableEq, Repr

/-- One output row per agent: id, state, the codes of its alerts.

$$\mathit{row}(a) = (\mathit{id}(a), \operatorname{state}(p, t, A, a), \operatorname{map}(\mathit{code}, \operatorname{agentAll}(p, o, a)))$$
for thresholds $p$ and $o = (t, A, \ell, \Sigma, \mathit{prev}, K)$.
-/
structure Row where
  id     : String
  state  : State
  alerts : List Code
deriving DecidableEq, Repr

/-- The health report: a row per agent (input order), the codes of the team and system alerts (each once, in code
order), the state counts, and every alert, sorted and deduplicated.

$$\operatorname{report} = (\mathit{rows}, \mathit{sysCodes}, n, \mathit{alerts})$$
-/
structure Report where
  agents : List Row
  system : List Code
  counts : Counts
  alerts : List Alert
deriving DecidableEq, Repr

/-- How many agents are in a state.

$$\operatorname{count}(p, t, A, s) = |[\, a \in A \mid \operatorname{state}(p, t, A, a) = s \,]|$$
-/
def countState (p : Params) (now : Nat) (agents : List Agent) (s : State) : Nat :=
  (agents.filter fun a => state p now agents a == s).length

/-- The health report of one observation.

$$\operatorname{health}(p, o) = \bigl(\operatorname{map}(\mathit{row}, A),\ [\, c \in \mathcal C \mid \exists x \in \operatorname{sysAlerts}(p, o).\ \mathit{code}(x) = c \,],\ (\operatorname{count}(p, t, A, s))_{s \in \mathcal S},\ \operatorname{sortU}(\operatorname{raw}(p, o))\bigr),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)\ \text{and } \mathcal C \text{ is taken in rank order}$$
-/
def health (p : Params) (o : Obs) : Report :=
  { agents := o.agents.map fun a => ⟨a.id, state p o.now o.agents a, (agentAll p o a).map (·.code)⟩
    system := Code.all.filter fun c => (sysAlerts p o).any (·.code == c)
    counts := { active := countState p o.now o.agents .active, idle := countState p o.now o.agents .idle,
                parked := countState p o.now o.agents .parked, stalled := countState p o.now o.agents .stalled,
                gone := countState p o.now o.agents .gone, done := countState p o.now o.agents .done }
    alerts := sortU (raw p o) }

/-! ## Report theorems -/

/-- The alert list holds exactly the raised alerts.

$$\forall p, o, x:\quad x \in \operatorname{health}(p, o).\mathit{alerts} \iff x \in \operatorname{raw}(p, o)$$
-/
theorem mem_alerts (p : Params) (o : Obs) (x : Alert) : x ∈ (health p o).alerts ↔ x ∈ raw p o :=
  mem_sortU x _

/-- The alert list is strictly sorted (critical first, then by code, subject and detail), so it has no duplicates.

$$\forall p, o:\quad \operatorname{sorted}_\prec(\operatorname{health}(p, o).\mathit{alerts})$$
-/
theorem alerts_sorted (p : Params) (o : Obs) : (health p o).alerts.Pairwise Alert.Lt := sorted_sortU _

/-- Critical alerts come first: no critical alert follows a non-critical one.

$$\forall p, o:\quad \forall i < j < |\mathit{al}|:\ \mathit{crit}(\mathit{al}_j) \Rightarrow \mathit{crit}(\mathit{al}_i) \qquad \text{where } \mathit{al} = \operatorname{health}(p, o).\mathit{alerts}$$
-/
theorem crit_first (p : Params) (o : Obs) :
    (health p o).alerts.Pairwise (fun x y => y.crit = true → x.crit = true) := by
  refine (alerts_sorted p o).imp ?_
  intro x y h hy
  rcases h with ⟨hx, _⟩ | ⟨e, _⟩
  · exact hx
  · rw [e]; exact hy

/-- The team and system alerts of one code: the piece of `sysAlerts` for that code (none for an `agent.*` code).

$$\operatorname{piece}(p, o, c) = \begin{cases} \operatorname{sCiFailed}(o) & c = \texttt{ci.failed} \\ \operatorname{sCiFin}(p, o) & c = \texttt{ci.finished} \\ \operatorname{sCiSlow}(p, o) & c = \texttt{ci.slow} \\ \operatorname{sDocker}(p, o) & c = \texttt{docker.orphan} \\ \operatorname{sProc}(p, o) & c = \texttt{proc.long} \\ \operatorname{sLockLong}(p, o) & c = \texttt{sim.lockLong} \\ \operatorname{sOrphan}(p, o) & c = \texttt{sim.lockOrphan} \\ \operatorname{sDisk}(p, o) & c = \texttt{sys.diskLow} \\ \operatorname{sLoad}(p, o) & c = \texttt{sys.loadHigh} \\ \operatorname{sMem}(o) & c = \texttt{sys.memCritical} \\ \operatorname{sOver}(p, o) & c = \texttt{team.overCap} \\ \operatorname{sPerm}(o) & c = \texttt{team.permissionWait} \\ \operatorname{sWt}(p, o) & c = \texttt{worktrees.many} \\ [] & \operatorname{isAgent}(c) \end{cases}$$
-/
def sysPiece (p : Params) (o : Obs) : Code → List Alert
  | .ciFailed => sCiFailed o
  | .ciFinished => sCiFin p o
  | .ciSlow => sCiSlow p o
  | .dockerOrphan => sDocker p o
  | .procLong => sProc p o
  | .simLockLong => sLockLong p o
  | .simLockOrphan => sOrphan p o
  | .svcStale => sStale o
  | .diskLow => sDisk p o
  | .loadHigh => sLoad p o
  | .memCritical => sMem o
  | .overCap => sOver p o
  | .permissionWait => sPerm o
  | .worktreesMany => sWt p o
  | .ctxHigh | .ctxWarn | .errStreak | .gone | .stalled | .toolHang | .toolSlow => []

/-- `sysAlerts` is the concatenation of the pieces in rank order.

$$\forall p, o:\quad \operatorname{sysAlerts}(p, o) = \operatorname{piece}(p, o, c_0) \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \operatorname{piece}(p, o, c_{20})$$
-/
theorem sysAlerts_eq (p : Params) (o : Obs) : sysAlerts p o = Code.all.flatMap (sysPiece p o) := by
  simp [sysAlerts, Code.all, sysPiece, List.flatMap_cons, List.append_assoc]

/-- Every alert of a piece carries the piece's code.

$$\forall p, o, c, x:\quad x \in \operatorname{piece}(p, o, c) \Rightarrow \mathit{code}(x) = c$$
-/
theorem piece_code (p : Params) (o : Obs) (c : Code) (x : Alert) (h : x ∈ sysPiece p o c) : x.code = c := by
  cases c <;> simp only [sysPiece, sCiFailed, sCiFin, sCiSlow, sDocker, sProc, sLockLong, sOrphan, sStale, sDisk, sLoad,
    sMem, sOver, sPerm, sWt, List.not_mem_nil] at h
  all_goals first
    | (obtain ⟨_, e⟩ := (mem_when _ _ _).1 h; subst e; rfl)
    | (obtain ⟨_, _, e⟩ := List.mem_map.1 h; subst e; rfl)
    | (obtain ⟨_, _, e⟩ := List.mem_map.1 h; subst e; exact procAlert_code _ _)

/-- A team or system alert lies in the piece of its own code.

$$\forall p, o, x:\quad x \in \operatorname{sysAlerts}(p, o) \iff x \in \operatorname{piece}(p, o, \mathit{code}(x))$$
-/
theorem mem_sys (p : Params) (o : Obs) (x : Alert) : x ∈ sysAlerts p o ↔ x ∈ sysPiece p o x.code := by
  rw [sysAlerts_eq, List.mem_flatMap]
  constructor
  · rintro ⟨c, _, h⟩
    rw [piece_code p o c x h]; exact h
  · intro h
    exact ⟨x.code, by cases x.code <;> decide, h⟩

/-- A team or system alert carries one of the team and system codes, never an `agent.*` code.

$$\forall p, o, x:\quad x \in \operatorname{sysAlerts}(p, o) \Rightarrow \neg\operatorname{isAgent}(\mathit{code}(x))$$
-/
theorem sysAlerts_notAgent (p : Params) (o : Obs) (x : Alert) (h : x ∈ sysAlerts p o) :
    x.code.isAgent = false := by
  rw [mem_sys] at h
  revert h
  cases x.code <;> simp [sysPiece, Code.isAgent, Code.rank]

/-- Every `agent.*` alert in the report names an agent of the observation that is neither done nor parked; a gone
agent raises only `agent.gone`.

$$\forall p, o, x:\quad x \in \operatorname{health}(p, o).\mathit{alerts} \wedge \operatorname{isAgent}(\mathit{code}(x)) \Rightarrow \exists a \in A.\ \operatorname{state}(p, t, A, a) \notin \{\mathrm{done}, \mathrm{parked}\} \wedge (\operatorname{state}(p, t, A, a) = \mathrm{gone} \Rightarrow \mathit{code}(x) = \texttt{agent.gone}) \wedge \mathit{id}(a) = \mathit{subj}(x),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
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

/-- An alert with a team or system code comes from `sysAlerts`.

$$\forall p, o, x:\quad x \in \operatorname{health}(p, o).\mathit{alerts} \wedge \neg\operatorname{isAgent}(\mathit{code}(x)) \Rightarrow x \in \operatorname{sysAlerts}(p, o)$$
-/
theorem mem_sys_of_notAgent (p : Params) (o : Obs) (x : Alert) (hx : x ∈ (health p o).alerts)
    (hc : x.code.isAgent = false) : x ∈ sysAlerts p o := by
  rw [mem_alerts] at hx
  unfold raw at hx
  rcases List.mem_append.1 hx with h | h
  · obtain ⟨a, _, hxa⟩ := List.mem_flatMap.1 h
    rw [(agentAll_subject p o a x hxa).1] at hc; cases hc
  · exact h

/-- The report has an alert of a team or system code exactly when that code's piece is not empty.

$$\forall p, o, c:\quad \neg\operatorname{isAgent}(c) \Rightarrow \bigl((\exists x \in \operatorname{health}(p, o).\mathit{alerts}.\ \mathit{code}(x) = c) \iff \operatorname{piece}(p, o, c) \ne []\bigr)$$
-/
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

/-- `when` is not empty exactly when its condition holds.

$$\forall b, x:\quad \operatorname{when}(b, x) \ne [] \iff b$$
-/
theorem when_ne_nil (b : Bool) (x : Alert) : when b x ≠ [] ↔ b = true := by
  cases b <;> simp [when]

/-- The simulator lock raises `sim.lockOrphan` exactly when it has a holder that names no live agent (by id, name or
task).

$$\forall p, o:\quad (\exists x \in \operatorname{health}(p, o).\mathit{alerts}.\ \mathit{code}(x) = \texttt{sim.lockOrphan}) \iff \exists h.\ \mathit{holder}(L) = h \wedge \neg \exists a \in A.\ \operatorname{live}(p, t, a) \wedge \operatorname{names}(h, a),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ L = \text{the simulator lock of } \Sigma$$
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

$$\forall p, o:\quad (\exists x \in \operatorname{health}(p, o).\mathit{alerts}.\ \mathit{code}(x) = \texttt{team.permissionWait}) \iff \exists \nu.\ \mathit{noteAt}(\ell) = \nu \wedge \forall s.\ \mathit{lastToolAt}(\ell) = s \Rightarrow s < \nu,\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
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

/-- `sys.loadHigh` fires exactly when the floor of the 1-min load average is at or above `loadMax`.

$$\forall p, o:\quad (\exists x \in \operatorname{health}(p, o).\mathit{alerts}.\ \mathit{code}(x) = \texttt{sys.loadHigh}) \iff \mathit{loadMax}_p \le \lambda,\quad \text{where } \lambda = \text{the } \mathit{loadFloor} \text{ of the system snapshot of } o$$
-/
theorem loadHigh_iff (p : Params) (o : Obs) :
    (∃ x ∈ (health p o).alerts, x.code = .loadHigh) ↔ p.loadMax ≤ o.system.loadFloor := by
  rw [sys_code_iff p o _ rfl]
  simp only [sysPiece, sLoad, when_ne_nil, decide_eq_true_eq]

/-- A run waiting or running for more than `ciSlowMin` minutes raises `ci.slow` with subject `workflow@branch`.

$$\forall p, o, r:\quad r \in R \wedge \operatorname{ciSlow}(p, t, r) \Rightarrow \exists x \in \operatorname{health}(p, o).\mathit{alerts}.\ \mathit{code}(x) = \texttt{ci.slow} \wedge \mathit{subj}(x) = \mathit{wf}(r)\texttt{@}\mathit{br}(r),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ R = \text{the run list of } \Sigma$$
-/
theorem ciSlow_raised (p : Params) (o : Obs) (r : CiRun) (hr : r ∈ o.system.ci) (h : ciSlowB p o.now r = true) :
    ∃ x ∈ (health p o).alerts, x.code = .ciSlow ∧ x.subject = s!"{r.workflow}@{r.branch}" := by
  have hy : (⟨.ciSlow, s!"{r.workflow}@{r.branch}", s!"{r.status} for {mins (o.now - r.startedAt)} min",
      critCi o.critical r⟩ : Alert) ∈ sCiSlow p o :=
    List.mem_map.2 ⟨r, List.mem_filter.2 ⟨hr, h⟩, rfl⟩
  exact ⟨_, (mem_alerts p o _).2 (List.mem_append.2 (.inr ((mem_sys p o _).2 hy))), rfl, rfl⟩

/-! ## Long-running processes -/

/-- The report holds a `proc.long` alert exactly when it is the alert of a process tree that runs too long.

$$\forall p, o, x:\quad \bigl(x \in \operatorname{health}(p, o).\mathit{alerts} \wedge \mathit{code}(x) = \texttt{proc.long}\bigr) \iff \exists q \in Q.\ \operatorname{procLong}(p, o, q) \wedge x = \operatorname{procAlert}(o, q),\quad \text{where } Q = \text{the process-tree list of the system snapshot of } o$$
-/
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

/-- A process tree started by a live agent's Bash call never runs too long, whatever its age.

$$\forall p, o, q, a:\quad a \in A \wedge \mathit{owner}(q) = \mathit{id}(a) \wedge \operatorname{live}(p, t, a) \Rightarrow \neg\operatorname{procLong}(p, o, q),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
-/
theorem ownerLive_quiet (p : Params) (o : Obs) (q : Proc) (a : Agent) (ha : a ∈ o.agents)
    (hg : q.agent = some a.id) (hl : live p o.now a = true) : procLongB p o q = false := by
  have hw : ownerLiveB p o.now o.agents q = true := by
    unfold ownerLiveB; rw [hg]; exact List.any_eq_true.2 ⟨a, ha, by simp [hl]⟩
  simp [procLongB, hw]

/-- An intended long-runner (allowlisted program, service pid, or declared pid in its tree) never runs too long.

$$\forall p, o, q:\quad \operatorname{declared}(S, D, q) \Rightarrow \neg\operatorname{procLong}(p, o, q),\quad \text{where } S = \text{the service pids},\ D = \text{the declared pids (both of the system snapshot of } o\text{)}$$
-/
theorem declared_quiet (p : Params) (o : Obs) (q : Proc) (h : declaredB o.system.services o.system.keep q = true) :
    procLongB p o q = false := by
  simp [procLongB, h]

/-! ## Stale services -/

/-- The report holds a `svc.stale` alert exactly when it is the alert of a service with a changed input.

$$\forall p, o, x:\quad \bigl(x \in \operatorname{health}(p, o).\mathit{alerts} \wedge \mathit{code}(x) = \texttt{svc.stale}\bigr) \iff \exists s \in \Sigma.\mathit{svcs}.\ (\exists i \in I(s).\ \mathit{changed}(i)) \wedge x = \operatorname{staleAlert}(s)$$
-/
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

/-- A stale service's alert names the service and lists exactly its changed paths.

$$\forall s:\quad \mathit{subject}(\operatorname{staleAlert}(s)) = \mathit{name}(s) \wedge \mathit{detail}(\operatorname{staleAlert}(s)) = \text{“changed on main since its commit: ”} \cdot \operatorname{join}(\text{“, ”}, \operatorname{changed}(s))$$
-/
theorem staleAlert_fields (s : Svc) :
    (staleAlert s).subject = s.name ∧
      (staleAlert s).detail = "changed on main since its commit: " ++ ", ".intercalate s.changed := ⟨rfl, rfl⟩

/-- A restarted (or rebuilt) service raises no `svc.stale` alert.

$$\forall s:\quad \operatorname{sStale}(o[\mathit{svcs} := [\operatorname{restart}(s)]]) = []$$
-/
theorem sStale_restart (o : Obs) (s : Svc) :
    sStale { o with system := { o.system with svcs := [s.restart] } } = [] := by
  simp [sStale, List.filter, Svc.restart_clears s]

/-- Every `proc.long` alert comes from a process tree of the session that is not declared, whose owner is not a live
agent, and that is alive for strictly more than `procMaxMin` minutes.

$$\forall p, o, x:\quad x \in \operatorname{health}(p, o).\mathit{alerts} \wedge \mathit{code}(x) = \texttt{proc.long} \Rightarrow \exists q \in Q.\ x = \operatorname{procAlert}(o, q) \wedge \neg\operatorname{declared}(S, D, q) \wedge \neg\bigl(\exists a \in A.\ \mathit{owner}(q) = \mathit{id}(a) \wedge \operatorname{live}(p, t, a)\bigr) \wedge \mu\,\mathit{procMax} < t \mathbin{\dot-} \mathit{start}(q),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
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

$$\forall p, o, q, g:\quad q \in Q \wedge \neg\operatorname{declared}(S, D, q) \wedge \mathit{owner}(q) = g \wedge \bigl(\forall a \in A.\ \mathit{id}(a) = g \Rightarrow \neg\operatorname{live}(p, t, a)\bigr) \wedge \mu\,\mathit{procMax} < t \mathbin{\dot-} \mathit{start}(q) \Rightarrow \operatorname{procAlert}(o, q) \in \operatorname{health}(p, o).\mathit{alerts},\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K),\ \Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R, \lambda, Q, S, D)$$
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

$$p \sqsubseteq q \iff \mathit{idle}_p \le \mathit{idle}_q \wedge \mathit{stall}_p \le \mathit{stall}_q \wedge \mathit{hang}_p \le \mathit{hang}_q \wedge \mathit{err}_p \le \mathit{err}_q \wedge \mathit{ctxMax}_p \le \mathit{ctxMax}_q \wedge \mathit{ctxWarn}_p \le \mathit{ctxWarn}_q \wedge \mathit{diskMin}_q \le \mathit{diskMin}_p \wedge \mathit{cap}_p \le \mathit{cap}_q \wedge \mathit{simMax}_p \le \mathit{simMax}_q \wedge \mathit{wtMax}_p \le \mathit{wtMax}_q \wedge \mathit{wfQuiet}_p = \mathit{wfQuiet}_q \wedge \mathit{goneAfter}_p = \mathit{goneAfter}_q \wedge \mathit{toolSlow}_p \le \mathit{toolSlow}_q \wedge \mathit{ciSlowMin}_p \le \mathit{ciSlowMin}_q \wedge \mathit{procMax}_p \le \mathit{procMax}_q \wedge \mathit{loadMax}_p \le \mathit{loadMax}_q$$
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
  ciSlow : p.ciSlowMin ≤ q.ciSlowMin
  procMax : p.procMaxMin ≤ q.procMaxMin
  load : p.loadMax ≤ q.loadMax

/-- Whether an agent has ended depends on the thresholds only through `wfQuietMin` and `goneAfterMin`.

$$\forall p, q, t, a:\quad \mathit{wfQuiet}_p = \mathit{wfQuiet}_q \wedge \mathit{goneAfter}_p = \mathit{goneAfter}_q \Rightarrow \operatorname{ended}(p, t, a) = \operatorname{ended}(q, t, a)$$
-/
theorem ended_congr (p q : Params) (t : Nat) (a : Agent) (h : p.wfQuietMin = q.wfQuietMin)
    (hg : p.goneAfterMin = q.goneAfterMin) : ended p t a = ended q t a := by
  simp [ended, stopped, goneB, h, hg]

/-- So does whether an agent has a live child.

$$\forall p, q, t, A, a:\quad \mathit{wfQuiet}_p = \mathit{wfQuiet}_q \wedge \mathit{goneAfter}_p = \mathit{goneAfter}_q \Rightarrow \operatorname{child}(p, t, A, a) = \operatorname{child}(q, t, A, a)$$
-/
theorem hasLiveChild_congr (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (h : p.wfQuietMin = q.wfQuietMin)
    (hg : p.goneAfterMin = q.goneAfterMin) : hasLiveChild p t A a = hasLiveChild q t A a := by
  simp only [hasLiveChild, live, ended_congr p q t _ h hg]

/-- A tool hung under looser thresholds has also hung under tighter ones.

$$\forall p, q, t, A, a:\quad p \sqsubseteq q \wedge \operatorname{hung}(q, t, A, a) \Rightarrow \operatorname{hung}(p, t, A, a)$$
-/
theorem hungB_mono (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (hpq : Looser p q)
    (h : hungB q t A a = true) : hungB p t A a = true := by
  unfold hungB at *
  rw [hasLiveChild_congr p q t A a hpq.wf hpq.gone]
  cases hf : a.inflight with
  | none => simp [hf] at h
  | some f =>
    simp only [hf, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    exact ⟨h.1, Nat.le_trans (Nat.mul_le_mul_right _ hpq.hang) h.2⟩

/-- A tool slow under looser thresholds is also slow under tighter ones.

$$\forall p, q, t, A, a:\quad p \sqsubseteq q \wedge \operatorname{slow}(q, t, A, a) \Rightarrow \operatorname{slow}(p, t, A, a)$$
-/
theorem slowB_mono (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (hpq : Looser p q)
    (h : slowB q t A a = true) : slowB p t A a = true := by
  unfold slowB at *
  rw [hasLiveChild_congr p q t A a hpq.wf hpq.gone]
  cases hf : a.inflight with
  | none => simp [hf] at h
  | some f =>
    simp only [hf, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    exact ⟨h.1, Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ hpq.toolSlow) h.2⟩

/-- Stalling under looser thresholds implies stalling under tighter ones.

$$\forall p, q, t, A, a:\quad p \sqsubseteq q \wedge \operatorname{state}(q, t, A, a) = \mathrm{stalled} \Rightarrow \operatorname{state}(p, t, A, a) = \mathrm{stalled}$$
-/
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

/-- A live-agent alert under looser thresholds is also raised under tighter ones.

$$\forall p, q, t, A, a, x:\quad p \sqsubseteq q \wedge x \in \operatorname{agentAlerts}(q, t, A, a) \Rightarrow x \in \operatorname{agentAlerts}(p, t, A, a)$$
-/
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

$$\forall p, q, o, a, x:\quad p \sqsubseteq q \wedge x \in \operatorname{agentAll}(q, o, a) \Rightarrow x \in \operatorname{agentAll}(p, o, a)$$
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

/-- A `when` with a weaker condition and the same alert holds more.

$$\forall b, b', y, x:\quad (b \Rightarrow b') \wedge x \in \operatorname{when}(b, y) \Rightarrow x \in \operatorname{when}(b', y)$$
-/
theorem when_sub {b b' : Bool} (y : Alert) (hb : b = true → b' = true) (x : Alert) (h : x ∈ when b y) :
    x ∈ when b' y := by
  rw [mem_when] at h ⊢
  exact ⟨hb h.1, h.2⟩

/-- Filtering with a weaker test and the same alert map keeps more.

$$\forall l, f, g, m, x:\quad (\forall r \in l.\ f(r) \Rightarrow g(r)) \wedge x \in \operatorname{map}(m, [\, r \in l \mid f(r) \,]) \Rightarrow x \in \operatorname{map}(m, [\, r \in l \mid g(r) \,])$$
-/
theorem fm_sub {α : Type} (l : List α) (f g : α → Bool) (m : α → Alert) (hfg : ∀ r ∈ l, f r = true → g r = true)
    (x : Alert) (h : x ∈ (l.filter f).map m) : x ∈ (l.filter g).map m := by
  obtain ⟨r, hr, e⟩ := List.mem_map.1 h
  rw [List.mem_filter] at hr
  exact List.mem_map.2 ⟨r, List.mem_filter.2 ⟨hr.1, hfg r hr.1 hr.2⟩, e⟩

/-- A team or system alert of one code under looser thresholds is also raised under tighter ones.

$$\forall p, q, o, c, x:\quad p \sqsubseteq q \wedge x \in \operatorname{piece}(q, o, c) \Rightarrow x \in \operatorname{piece}(p, o, c)$$
-/
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
        exact ⟨hr.1, Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ hpq.ciSlow) hr.2⟩
  · refine fm_sub _ _ _ _ (fun r _ hr => ?_) x h
    unfold ciSlowB at *
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hr ⊢
    exact ⟨hr.1, Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ hpq.ciSlow) hr.2⟩
  · simp only [sysPiece, sDocker] at h ⊢; rw [← hdo]; exact h
  · refine fm_sub _ _ _ _ (fun r _ hr => ?_) x h
    have hw : ownerLiveB q o.now o.agents r = ownerLiveB p o.now o.agents r := by simp only [ownerLiveB, hl]
    unfold procLongB at *
    rw [hw] at hr
    simp only [Bool.and_eq_true, decide_eq_true_eq] at hr ⊢
    exact ⟨hr.1, Nat.lt_of_le_of_lt (Nat.mul_le_mul_right _ hpq.procMax) hr.2⟩
  · refine when_sub _ (fun hb => ?_) x h
    cases hs : o.system.simLock.since with
    | none => simp [hs] at hb
    | some s =>
      simp only [hs, Option.any_some, Bool.and_eq_true, decide_eq_true_eq] at hb ⊢
      exact ⟨hb.1, Nat.le_trans (Nat.mul_le_mul_right _ hpq.sim) hb.2⟩
  · simp only [sysPiece, sOrphan] at h ⊢; rw [← ho]; exact h
  · exact h
  · exact when_sub _ (fun hb => by simp only [decide_eq_true_eq] at hb ⊢; omega) x h
  · exact when_sub _ (fun hb => by simp only [decide_eq_true_eq] at hb ⊢; omega) x h
  · exact h
  · simp only [sysPiece, sOver] at h ⊢
    rw [hn, hk, hhp] at h
    exact when_sub _ (fun hb => by simp only [decide_eq_true_eq] at hb ⊢; omega) x h
  · exact h
  · exact when_sub _ (fun hb => by simp only [decide_eq_true_eq] at hb ⊢; omega) x h

/-- A team or system alert under looser thresholds is also raised under tighter ones.

$$\forall p, q, o, x:\quad p \sqsubseteq q \wedge x \in \operatorname{sysAlerts}(q, o) \Rightarrow x \in \operatorname{sysAlerts}(p, o)$$
-/
theorem sysAlerts_mono (p q : Params) (o : Obs) (hpq : Looser p q) (x : Alert) (h : x ∈ sysAlerts q o) :
    x ∈ sysAlerts p o := by
  rw [mem_sys] at *
  exact sysPiece_mono p q o hpq x.code x h

/-- Loosening the thresholds never adds an alert: every alert of the report under $q$ is in the report under $p$.
(Raising any upper threshold, or lowering `diskMinGB`, with `wfQuietMin` and `goneAfterMin` unchanged, is a
loosening.)

$$\forall p, q, o, x:\quad p \sqsubseteq q \wedge x \in \operatorname{health}(q, o).\mathit{alerts} \Rightarrow x \in \operatorname{health}(p, o).\mathit{alerts}$$
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

/-- An agent's state and live-agent alerts do not depend on the order of the agent list.

$$\forall p, t, A, l, a:\quad l \sim A \Rightarrow \operatorname{state}(p, t, l, a) = \operatorname{state}(p, t, A, a) \wedge \operatorname{agentAlerts}(p, t, l, a) = \operatorname{agentAlerts}(p, t, A, a)$$
-/
theorem agent_perm (p : Params) (t : Nat) (A l : List Agent) (a : Agent) (hl : l.Perm A) :
    state p t l a = state p t A a ∧ agentAlerts p t l a = agentAlerts p t A a := by
  have hc : hasLiveChild p t l a = hasLiveChild p t A a := by unfold hasLiveChild; rw [hl.any_eq]
  have hh : hungB p t l a = hungB p t A a := by unfold hungB; rw [hc]
  have hsl : slowB p t l a = slowB p t A a := by unfold slowB; rw [hc]
  have hs : stallB p t l a = stallB p t A a := by unfold stallB; rw [hh]
  exact ⟨by unfold state; rw [hs], by unfold agentAlerts; rw [hs, hh, hsl]⟩

/-- The team and system alerts do not depend on the order of the agents.

$$\forall p, o, l:\quad l \sim A \Rightarrow \operatorname{sysAlerts}(p, o[A := l]) = \operatorname{sysAlerts}(p, o),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
-/
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
  simp only [sysAlerts, sCiFailed, sCiFin, sCiSlow, sDocker, sProc, sLockLong, sOrphan, sStale, sDisk, sLoad, sMem, sOver,
    sPerm, sWt, hn, hk, hh, ho, hd, hq, ha]

/-- The report's alerts, system codes and counts do not depend on the order of the agents (the rows follow it).

$$\forall p, o, l:\quad l \sim A \Rightarrow \operatorname{health}(p, o[A := l]).(\mathit{alerts}, \mathit{sysCodes}, n) = \operatorname{health}(p, o).(\mathit{alerts}, \mathit{sysCodes}, n),\quad \text{where } o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
-/
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

/-- The counts add up to the number of agents.

$$\forall p, o:\quad n_{\mathrm{active}} + n_{\mathrm{idle}} + n_{\mathrm{parked}} + n_{\mathrm{stalled}} + n_{\mathrm{gone}} + n_{\mathrm{done}} = |A|,\quad \text{where } (n_{\mathrm{active}}, n_{\mathrm{idle}}, n_{\mathrm{parked}}, n_{\mathrm{stalled}}, n_{\mathrm{gone}}, n_{\mathrm{done}}) = \operatorname{health}(p, o).\mathit{counts},\ o = (t, A, \ell, \Sigma, \mathit{prev}, K)$$
-/
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

/-- A sample agent (a subagent) started at 0 with its last event at minute 0 (for the guards).

$$a_0 = (\texttt{a}, \bot, \bot, \mathrm{subagent}, \bot, 0, 0, \bot, 0, \bot, \bot, \bot, \bot, \mathrm{false}, \mathrm{false}, \bot)$$
-/
def a0 : Agent := { id := "a" }

/-- A sample teammate whose last finished tool call was at minute 0 (for the guards).

$$\mathit{tm}_0 = a_0[k := \mathrm{teammate}, \mathit{lastTool} := \texttt{Bash}, \mathit{lastToolAt} := 0]$$
-/
def tm0 : Agent := { a0 with kind := .teammate, lastTool := some "Bash", lastToolAt := some 0 }

/-- A sample CI run of workflow `ci` on branch `main`, completed at an unknown time, started at 0 (for the guards).

$$r_0 = (\texttt{ci}, \texttt{main}, \texttt{completed}, \bot, 0, \bot)$$
-/
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
#guard (health {} { now := 0, system := { diskFreeGB := 19, loadFloor := 200 } }).system == [.diskLow, .loadHigh]
#guard sortU [⟨.diskLow, "disk", "1", false⟩, ⟨.ctxHigh, "b", "x", false⟩, ⟨.ctxHigh, "a", "x", false⟩,
    ⟨.diskLow, "disk", "1", false⟩, ⟨.worktreesMany, "worktrees", "1", true⟩]
  == [⟨.worktreesMany, "worktrees", "1", true⟩, ⟨.ctxHigh, "a", "x", false⟩, ⟨.ctxHigh, "b", "x", false⟩,
    ⟨.diskLow, "disk", "1", false⟩]

end Fw.Obs.Health
