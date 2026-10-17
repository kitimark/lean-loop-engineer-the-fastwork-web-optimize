/-!
# Team health: per-agent state and alert rules over one observation snapshot

`fw watch` (task `watch-cli`) collects one snapshot per interval: every agent's kind, timing and tool facts, the lead
session's last tool event and last notification, plus system, simulator-lock, Docker, worktree and CI facts. This
module is the pure part: from the snapshot and the thresholds it derives each agent's state (`active`, `idle`,
`parked`, `stalled`, `done`) and a sorted, duplicate-free list of alerts. The wire op `obs.health` (`Fw.Wire.Obs`) is
its JSON face.

Units: times are ms since the epoch (`Nat`); the `…Min` thresholds are minutes ($\mu = 60000$ ms each); an age is the
truncated difference $\mathit{now} \mathbin{\dot-} t$ (a timestamp after `now` has age 0). Context sizes are tokens,
disk is whole GB.

Why no per-agent "waiting for permission" state: every `Notification` hook event arrives without an agent id, so a
permission prompt cannot be attributed to an agent. It is a team-level alert instead (`team.permissionWait`: a
notification newer than the lead session's last tool event; the user answers it in the terminal).

Rules (proved below):
* `state_done`, `state_parked`, `state_stalled`, `state_idle`, `state_active`: the state is exactly the one the rules
  name; `state_cases`: exactly one holds; `counts_total`: the counts add up.
* `agentAlerts_quiet`, `agent_alert_live`: a done or parked agent raises no `agent.*` alert.
* `wait_not_hang`: an `Agent` or `SendMessage` call in flight while a child of the agent is live is a wait: no
  `agent.toolHang`, never stalled.
* `stalled_facts`: a stalled agent is not parked and its age is at least the stall threshold.
* `health_mono`: loosening the thresholds (raising any upper threshold, lowering `diskMinGB`, same `wfQuietMin`)
  never adds an alert.
* `lockOrphan_iff`, `permissionWait_iff`: when `sim.lockOrphan` and `team.permissionWait` fire.
* `alerts_sorted`, `mem_alerts`, `health_perm`: the alert list is strictly sorted by (code, subject, detail), holds
  exactly the raised alerts, and does not depend on the order of the agents.
-/
namespace Fw.Obs.Health

/-- Milliseconds per minute, the unit of every `…Min` threshold.

$$\mu = 60000$$
-/
def msPerMin : Nat := 60000

/-- The thresholds. Upper thresholds reached at or above (a value equal to the threshold alerts): `idleMin`,
`stallMin`, `toolHangMin` (minutes), `errStreak` (failed calls), `simLockMaxMin` (minutes); upper thresholds passed
only strictly above (a value equal to the threshold does not alert): `ctxResumeMax`, `ctxWarn` (tokens), `agentCap`
(live non-lead agents), `worktreesMax`; the lower threshold `diskMinGB` (free GB strictly below it alerts); and
`wfQuietMin`, the minutes without an event after which a workflow agent seen only in its transcript counts as done
(it is not an alert threshold).

$$p = (\mathit{idle}, \mathit{stall}, \mathit{hang}, \mathit{err}, \mathit{ctxMax}, \mathit{ctxWarn}, \mathit{diskMin}, \mathit{cap}, \mathit{simMax}, \mathit{wtMax}, \mathit{wfQuiet}) \in \mathbb N^{11}$$
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

/-- A CI run: workflow, branch, status, conclusion (`none` while running), start time (ms).

$$r = (\mathit{wf}, \mathit{br}, \mathit{status}, \mathit{concl}_\bot, \mathit{start})$$
-/
structure CiRun where
  workflow   : String
  branch     : String
  status     : String
  conclusion : Option String := none
  startedAt  : Nat
deriving DecidableEq, Repr

/-- The machine-level facts the rules read: free disk (GB), memory pressure, the simulator lock, running containers,
the number of git worktrees and recent CI runs.

$$\Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R)$$
-/
structure System where
  diskFreeGB  : Nat := 0
  memPressure : Mem := .normal
  simLock     : SimLock := {}
  docker      : List Container := []
  worktrees   : Nat := 0
  ci          : List CiRun := []
deriving DecidableEq, Repr

/-- One observation: the time it was taken (ms), the agents, the lead session's facts, the system facts.

$$o = (\mathit{now}, A, \ell, \Sigma)$$
-/
structure Obs where
  now    : Nat
  agents : List Agent := []
  lead   : Lead := {}
  system : System := {}
deriving DecidableEq, Repr

/-! ## Agent state -/

/-- The five agent states.

$$\mathcal S = \{\mathrm{active}, \mathrm{idle}, \mathrm{parked}, \mathrm{stalled}, \mathrm{done}\}$$
-/
inductive State where
  | active | idle | parked | stalled | done
deriving DecidableEq, Repr

/-- Whether an agent has ended: it stopped, or it is a workflow agent whose workflow run finished, or a workflow agent
seen only in its transcript with no event for `wfQuietMin` minutes.

$$\operatorname{ended}(p, t, a) \iff \mathit{stop}(a) \ne \bot \vee \bigl(k(a) = \mathrm{workflow} \wedge (\mathit{wfDone}(a) \vee (\mathit{trOnly}(a) \wedge \mu\,\mathit{wfQuiet} \le t \mathbin{\dot-} \mathit{last}(a)))\bigr)$$
-/
def ended (p : Params) (now : Nat) (a : Agent) : Bool :=
  a.stoppedAt.isSome ||
    (a.kind == .workflow && (a.workflowDone || (a.transcriptOnly && decide (p.wfQuietMin * msPerMin ≤ now - a.lastAt))))

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

/-- An agent's state: done once ended; else parked (a teammate waiting for a message on purpose); else stalled when
the stall test holds; else idle after `idleMin` minutes without an event; else active.

$$\operatorname{state}(p, t, A, a) = \begin{cases} \mathrm{done} & \operatorname{ended}(p, t, a) \\ \mathrm{parked} & \text{else if } \operatorname{parked}(a) \\ \mathrm{stalled} & \text{else if } \operatorname{Stall}(p, t, A, a) \\ \mathrm{idle} & \text{else if } \mu\,\mathit{idle} \le t \mathbin{\dot-} \mathit{last}(a) \\ \mathrm{active} & \text{otherwise} \end{cases}$$
-/
def state (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : State :=
  if ended p now a then .done
  else if parkedB a then .parked
  else if stallB p now agents a then .stalled
  else if p.idleMin * msPerMin ≤ now - a.lastAt then .idle
  else .active

/-- Done exactly when ended.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{done} \iff \operatorname{ended}(p, t, a)$$
-/
theorem state_done (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .done ↔ ended p t a = true := by
  unfold state
  cases ended p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Parked exactly when not ended and parked.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{parked} \iff \neg\operatorname{ended}(p, t, a) \wedge \operatorname{parked}(a)$$
-/
theorem state_parked (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .parked ↔ ended p t a = false ∧ parkedB a = true := by
  unfold state
  cases ended p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Stalled exactly when not ended, not parked and the stall condition holds.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{stalled} \iff \neg\operatorname{ended}(p, t, a) \wedge \neg\operatorname{parked}(a) \wedge \operatorname{Stall}(p, t, A, a)$$
-/
theorem state_stalled (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .stalled ↔ ended p t a = false ∧ parkedB a = false ∧ Stall p t A a := by
  rw [← stallB_iff]
  unfold state
  cases ended p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp

/-- Idle exactly when not ended, not parked, not stalled and without an event for `idleMin` minutes.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{idle} \iff \neg\operatorname{ended}(p, t, a) \wedge \neg\operatorname{parked}(a) \wedge \neg\operatorname{Stall}(p, t, A, a) \wedge \mu\,\mathit{idle} \le t \mathbin{\dot-} \mathit{last}(a)$$
-/
theorem state_idle (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .idle ↔ ended p t a = false ∧ parkedB a = false ∧ ¬ Stall p t A a ∧
      p.idleMin * msPerMin ≤ t - a.lastAt := by
  rw [← stallB_iff]
  unfold state
  cases ended p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp_all

/-- Active exactly when not ended, not parked, not stalled and with an event within `idleMin` minutes.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) = \mathrm{active} \iff \neg\operatorname{ended}(p, t, a) \wedge \neg\operatorname{parked}(a) \wedge \neg\operatorname{Stall}(p, t, A, a) \wedge t \mathbin{\dot-} \mathit{last}(a) < \mu\,\mathit{idle}$$
-/
theorem state_active (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    state p t A a = .active ↔ ended p t a = false ∧ parkedB a = false ∧ ¬ Stall p t A a ∧
      t - a.lastAt < p.idleMin * msPerMin := by
  rw [← stallB_iff]
  unfold state
  cases ended p t a <;> cases parkedB a <;> cases stallB p t A a <;> simp <;> split <;> simp_all <;> omega

/-- Every agent has exactly one state: the state is one of the five, and two different states never hold together
(with `state_done` … `state_active`, the five rule conditions partition all agents).

$$\forall p, t, A, a:\quad \operatorname{state}(p,t,A,a) \in \mathcal S \quad\text{and}\quad \forall s, s' \in \mathcal S:\ \operatorname{state}(p,t,A,a) = s \wedge \operatorname{state}(p,t,A,a) = s' \Rightarrow s = s'$$
-/
theorem state_cases (p : Params) (t : Nat) (A : List Agent) (a : Agent) :
    (state p t A a = .active ∨ state p t A a = .idle ∨ state p t A a = .parked ∨ state p t A a = .stalled ∨
      state p t A a = .done) ∧
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

$$\mathcal C = \{\texttt{agent.ctxHigh}, \texttt{agent.ctxWarn}, \texttt{agent.errStreak}, \texttt{agent.stalled}, \texttt{agent.toolHang}, \texttt{ci.failed}, \texttt{docker.orphan}, \texttt{sim.lockLong}, \texttt{sim.lockOrphan}, \texttt{sys.diskLow}, \texttt{sys.memCritical}, \texttt{team.overCap}, \texttt{team.permissionWait}, \texttt{worktrees.many}\}$$
-/
inductive Code where
  | ctxHigh | ctxWarn | errStreak | stalled | toolHang
  | ciFailed | dockerOrphan | simLockLong | simLockOrphan | diskLow | memCritical | overCap | permissionWait
  | worktreesMany
deriving DecidableEq, Repr

/-- Every code, in rank order.

$$\mathcal C = (c_0, \ldots, c_{13})$$
-/
def Code.all : List Code :=
  [.ctxHigh, .ctxWarn, .errStreak, .stalled, .toolHang,
   .ciFailed, .dockerOrphan, .simLockLong, .simLockOrphan, .diskLow, .memCritical, .overCap, .permissionWait,
   .worktreesMany]

/-- The wire name of a code.

$$\operatorname{name}(c_i) = \text{the } i\text{-th string of } \mathcal C$$
-/
def Code.name : Code → String
  | .ctxHigh => "agent.ctxHigh" | .ctxWarn => "agent.ctxWarn" | .errStreak => "agent.errStreak"
  | .stalled => "agent.stalled" | .toolHang => "agent.toolHang"
  | .ciFailed => "ci.failed" | .dockerOrphan => "docker.orphan" | .simLockLong => "sim.lockLong"
  | .simLockOrphan => "sim.lockOrphan" | .diskLow => "sys.diskLow" | .memCritical => "sys.memCritical"
  | .overCap => "team.overCap" | .permissionWait => "team.permissionWait" | .worktreesMany => "worktrees.many"

/-- The rank of a code (its position in `Code.all`).

$$\operatorname{rank}(c_i) = i$$
-/
def Code.rank : Code → Nat
  | .ctxHigh => 0 | .ctxWarn => 1 | .errStreak => 2 | .stalled => 3 | .toolHang => 4
  | .ciFailed => 5 | .dockerOrphan => 6 | .simLockLong => 7 | .simLockOrphan => 8 | .diskLow => 9
  | .memCritical => 10 | .overCap => 11 | .permissionWait => 12 | .worktreesMany => 13

/-- Whether a code is about one agent (`agent.*`).

$$\operatorname{isAgent}(c) \iff \operatorname{rank}(c) < 5$$
-/
def Code.isAgent (c : Code) : Bool := c.rank < 5

/-- The rank determines the code.

$$\forall c, c' \in \mathcal C:\quad \operatorname{rank}(c) = \operatorname{rank}(c') \Rightarrow c = c'$$
-/
theorem Code.rank_inj (c c' : Code) (h : c.rank = c'.rank) : c = c' := by
  cases c <;> cases c' <;> simp_all [Code.rank]

/-- Rank order is the order of the wire names: the names in rank order are strictly increasing strings.

$$\operatorname{name}(c_0) < \operatorname{name}(c_1) < \cdots < \operatorname{name}(c_{13}) \quad\text{(lexicographic)}$$
-/
theorem Code.names_sorted : (Code.all.map Code.name).Pairwise (· < ·) := by decide

/-- An alert: its code, its subject (an agent id, `team`, `lead`, `disk`, `memory`, `sim`, `workflow@branch`, a container
name or `worktrees`) and a detail text built from measured values only (never from a threshold).

$$x = (\mathit{code}, \mathit{subject}, \mathit{detail}) \in \mathcal C \times \mathrm{String}^2$$
-/
structure Alert where
  code    : Code
  subject : String
  detail  : String
deriving DecidableEq, Repr

/-- The output order: by code rank, then subject, then detail (strings lexicographic).

$$x \prec y \iff \operatorname{rank}(x) < \operatorname{rank}(y) \vee (\operatorname{rank}(x) = \operatorname{rank}(y) \wedge (\mathit{subj}(x) < \mathit{subj}(y) \vee (\mathit{subj}(x) = \mathit{subj}(y) \wedge \mathit{det}(x) < \mathit{det}(y))))$$
-/
def Alert.Lt (x y : Alert) : Prop :=
  x.code.rank < y.code.rank ∨
    (x.code.rank = y.code.rank ∧ (x.subject < y.subject ∨ (x.subject = y.subject ∧ x.detail < y.detail)))

instance (x y : Alert) : Decidable (Alert.Lt x y) := by unfold Alert.Lt; infer_instance

/-- The order is irreflexive.

$$\forall x:\quad \neg (x \prec x)$$
-/
theorem Alert.lt_irrefl (x : Alert) : ¬ Alert.Lt x x := by
  unfold Alert.Lt
  have := String.lt_irrefl x.subject
  have := String.lt_irrefl x.detail
  simp_all

/-- The order is transitive.

$$\forall x, y, z:\quad x \prec y \wedge y \prec z \Rightarrow x \prec z$$
-/
theorem Alert.lt_trans {x y z : Alert} (h₁ : Alert.Lt x y) (h₂ : Alert.Lt y z) : Alert.Lt x z := by
  unfold Alert.Lt at *
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
  obtain ⟨c, s, d⟩ := x
  obtain ⟨c', s', d'⟩ := y
  unfold Alert.Lt
  simp only
  by_cases hr : c.rank = c'.rank
  · have hc := Code.rank_inj c c' hr
    subst hc
    by_cases hs : s = s'
    · subst hs
      have hd : d ≠ d' := fun e => h (e ▸ rfl)
      rcases str_trich hd with l | l
      · exact .inl (.inr ⟨rfl, .inr ⟨rfl, l⟩⟩)
      · exact .inr (.inr ⟨rfl, .inr ⟨rfl, l⟩⟩)
    · rcases str_trich hs with l | l
      · exact .inl (.inr ⟨rfl, .inl l⟩)
      · exact .inr (.inr ⟨rfl, .inl l⟩)
  · rcases Nat.lt_or_gt_of_ne hr with l | l
    · exact .inl (.inl l)
    · exact .inr (.inl l)

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

/-- The `agent.*` alerts of one agent (none once it is done or parked), in code order: context over `ctxResumeMax`
(do not resume it), context over `ctxWarn`, at least `errStreak` (and at least one) failed calls in a row, stalled, a
tool hung. An unknown context size counts as 0.

$$\operatorname{agentAlerts}(p, t, A, a) = \begin{cases} [] & \operatorname{ended}(p, t, a) \vee \operatorname{parked}(a) \\ \operatorname{when}(\kappa > \mathit{ctxMax}, (\texttt{ctxHigh}, \mathit{id}(a), \text{“}\kappa\text{ context tokens”})) \mathbin{+\!\!+} \operatorname{when}(\kappa > \mathit{ctxWarn}, (\texttt{ctxWarn}, \mathit{id}(a), \text{“}\kappa\text{ context tokens”})) \\ \quad \mathbin{+\!\!+} \operatorname{when}(\mathit{errTail}(a) \ge \max(\mathit{err}, 1), (\texttt{errStreak}, \mathit{id}(a), \text{“}\mathit{errTail}(a)\text{ failed tool calls in a row”})) \\ \quad \mathbin{+\!\!+} \operatorname{when}(\operatorname{stallB}(p, t, A, a), (\texttt{stalled}, \mathit{id}(a), \text{“no event for }\operatorname{mins}(t \mathbin{\dot-} \mathit{last}(a))\text{ min”})) \\ \quad \mathbin{+\!\!+} \operatorname{when}(\operatorname{hung}(p, t, A, a), (\texttt{toolHang}, \mathit{id}(a), \delta)) & \text{otherwise} \end{cases}$$
where $\kappa = \mathit{ctx}(a)$ if $\mathit{ctx}(a) \ne \bot$, else $\kappa = 0$; and
$\delta = \text{“}\mathit{tool}(\varphi)\text{ running for }\operatorname{mins}(t \mathbin{\dot-} \mathit{since}(\varphi))\text{ min”}$ if
$f(a) = \varphi$, else $\delta = \varepsilon$ (numbers in decimal).
-/
def agentAlerts (p : Params) (now : Nat) (agents : List Agent) (a : Agent) : List Alert :=
  if ended p now a || parkedB a then [] else
  let ctx := a.ctxTokens.getD 0
  when (decide (p.ctxResumeMax < ctx)) ⟨.ctxHigh, a.id, s!"{ctx} context tokens"⟩ ++
  when (decide (p.ctxWarn < ctx)) ⟨.ctxWarn, a.id, s!"{ctx} context tokens"⟩ ++
  when (decide (0 < a.errTail ∧ p.errStreak ≤ a.errTail)) ⟨.errStreak, a.id, s!"{a.errTail} failed tool calls in a row"⟩ ++
  when (stallB p now agents a) ⟨.stalled, a.id, s!"no event for {mins (now - a.lastAt)} min"⟩ ++
  when (hungB p now agents a)
    ⟨.toolHang, a.id, match a.inflight with
      | some f => s!"{f.tool} running for {mins (now - f.since)} min"
      | none => ""⟩

/-- A done or parked agent raises no alert.

$$\forall p, t, A, a:\quad \operatorname{state}(p, t, A, a) \in \{\mathrm{done}, \mathrm{parked}\} \Rightarrow \operatorname{agentAlerts}(p, t, A, a) = []$$
-/
theorem agentAlerts_quiet (p : Params) (t : Nat) (A : List Agent) (a : Agent)
    (h : state p t A a = .done ∨ state p t A a = .parked) : agentAlerts p t A a = [] := by
  unfold agentAlerts
  rcases h with h | h
  · simp [(state_done p t A a).1 h]
  · simp [((state_parked p t A a).1 h).2]

/-- Every alert of an agent is an `agent.*` alert about that agent.

$$\forall p, t, A, a, x:\quad x \in \operatorname{agentAlerts}(p, t, A, a) \Rightarrow \operatorname{isAgent}(\mathit{code}(x)) \wedge \mathit{subj}(x) = \mathit{id}(a)$$
-/
theorem agentAlerts_subject (p : Params) (t : Nat) (A : List Agent) (a : Agent) (x : Alert)
    (h : x ∈ agentAlerts p t A a) : x.code.isAgent = true ∧ x.subject = a.id := by
  unfold agentAlerts at h
  split at h
  · simp at h
  · simp only [List.mem_append, mem_when] at h
    rcases h with (((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩ <;> subst e <;> simp [Code.isAgent, Code.rank]

/-- An `Agent` or `SendMessage` call in flight while a child of the agent is live is a wait, not a hang: the tool
has not hung, the agent is not stalled, and it raises no `agent.toolHang`.

$$\forall p, t, A, a, \varphi:\quad f(a) = \varphi \wedge \operatorname{waitTool}(\mathit{tool}(\varphi)) \wedge \operatorname{child}(p, t, A, a) \Rightarrow \neg\operatorname{hung}(p, t, A, a) \wedge \operatorname{state}(p, t, A, a) \ne \mathrm{stalled} \wedge \forall x \in \operatorname{agentAlerts}(p, t, A, a).\ \mathit{code}(x) \ne \texttt{agent.toolHang}$$
-/
theorem wait_not_hang (p : Params) (t : Nat) (A : List Agent) (a : Agent) (f : Inflight)
    (hf : a.inflight = some f) (hw : waitTool f.tool = true) (hc : hasLiveChild p t A a = true) :
    hungB p t A a = false ∧ state p t A a ≠ .stalled ∧ ∀ x ∈ agentAlerts p t A a, x.code ≠ .toolHang := by
  have hh : hungB p t A a = false := by unfold hungB; simp [hf, hw, hc]
  refine ⟨hh, ?_, ?_⟩
  · intro hs
    obtain ⟨_, _, _, h⟩ := (state_stalled p t A a).1 hs
    exact (h f hf).1 ⟨hw, hc⟩
  · intro x hx
    unfold agentAlerts at hx
    split at hx
    · simp at hx
    · simp only [List.mem_append, mem_when, hh] at hx
      rcases hx with (((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨b, _⟩ <;> first | (subst e; simp) | simp at b

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

/-- Whether a container is orphaned: no live agent started at or before it (so none could have started it).

$$\operatorname{dockerOrphan}(p, t, A, c) \iff \neg \exists a \in A.\ \operatorname{live}(p, t, a) \wedge \mathit{start}(a) \le \mathit{start}(c)$$
-/
def dockerOrphanB (p : Params) (now : Nat) (agents : List Agent) (c : Container) : Bool :=
  !agents.any fun a => live p now a && decide (a.startedAt ≤ c.startedAt)

/-- The number of live agents other than the lead session.

$$\operatorname{nLive}(p, t, A) = |[\, a \in A \mid \operatorname{live}(p, t, a) \wedge k(a) \ne \mathrm{lead} \,]|$$
-/
def nLive (p : Params) (now : Nat) (agents : List Agent) : Nat :=
  (agents.filter fun a => live p now a && a.kind != .lead).length

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

$$\operatorname{permB}(\ell) \iff \exists n.\ \mathit{noteAt}(\ell) = n \wedge \forall s.\ \mathit{lastToolAt}(\ell) = s \Rightarrow s < n$$
-/
def permB (l : Lead) : Bool :=
  match l.noteAt with
  | none => false
  | some n => match l.lastToolAt with
    | none => true
    | some s => decide (s < n)

/-- The team and system alerts: more live non-lead agents than `agentCap` (the detail counts them by kind and counts
the helpers); free disk below `diskMinGB`; memory pressure critical; the simulator lock held for `simLockMaxMin`
minutes; the lock orphaned; the latest run of a workflow and branch failed; an orphaned container; more worktrees than
`worktreesMax`; a notification newer than the lead's last tool call.

$$\begin{aligned} \operatorname{sysAlerts}(p, o) ={} & [(\texttt{team.overCap}, \texttt{team}, \text{“}n\text{ live agents: }k_{\mathrm{teammate}}\text{ teammate, }k_{\mathrm{subagent}}\text{ subagent, }k_{\mathrm{workflow}}\text{ workflow; }\operatorname{nHelpers}(p, t, A)\text{ with a parent agent”}) \mid \mathit{cap} < n] \\ & \mathbin{+\!\!+} [(\texttt{sys.diskLow}, \texttt{disk}, \text{“}\mathit{disk}\text{ GB free”}) \mid \mathit{disk} < \mathit{diskMin}] \mathbin{+\!\!+} [(\texttt{sys.memCritical}, \texttt{memory}, \text{“memory pressure critical”}) \mid m = \mathrm{critical}] \\ & \mathbin{+\!\!+} [(\texttt{sim.lockLong}, \texttt{sim}, \text{“held by }h\text{ for }\operatorname{mins}(t \mathbin{\dot-} s)\text{ min”}) \mid \exists s.\ \mathit{since}(L) = s \wedge \mathit{holder}(L) \ne \bot \wedge \mu\,\mathit{simMax} \le t \mathbin{\dot-} s] \\ & \mathbin{+\!\!+} [(\texttt{sim.lockOrphan}, \texttt{sim}, \text{“held by }h\text{”}) \mid \operatorname{orphanB}(p, t, A, L)] \\ & \mathbin{+\!\!+} [\,(\texttt{ci.failed}, \mathit{wf}(r)\texttt{@}\mathit{br}(r), \text{“latest run }c_\varepsilon(r)\text{”}) \mid r \leftarrow R,\ \operatorname{ciFailing}(r) \wedge \operatorname{ciLatest}(R, r)\,] \\ & \mathbin{+\!\!+} [\,(\texttt{docker.orphan}, \mathit{name}(c), \text{“container }\mathit{id}(c)\text{”}) \mid c \leftarrow C,\ \operatorname{dockerOrphan}(p, t, A, c)\,] \\ & \mathbin{+\!\!+} [(\texttt{worktrees.many}, \texttt{worktrees}, \text{“}\mathit{wt}\text{ worktrees”}) \mid \mathit{wtMax} < \mathit{wt}] \\ & \mathbin{+\!\!+} [(\texttt{team.permissionWait}, \texttt{lead}, \text{“notification }\operatorname{mins}(t \mathbin{\dot-} n)\text{ min ago, no lead tool call since”}) \mid \exists n.\ \mathit{noteAt}(\ell) = n \wedge \operatorname{permB}(\ell)] \end{aligned}$$

where $o = (t, A, \ell, \Sigma)$ and $\Sigma = (\mathit{disk}, m, L, C, \mathit{wt}, R)$; $n = \operatorname{nLive}(p, t, A)$ and
$k_\kappa = \operatorname{nKind}(p, t, A, \kappa)$; $h$ is $\mathit{holder}(L)$, or $\varepsilon$ when it is $\bot$;
$c_\varepsilon(r)$ is $\mathit{concl}(r)$, or $\varepsilon$ when it is $\bot$; numbers are written in decimal;
$[x \mid c]$ is $[x]$ when $c$ holds and $[]$ otherwise, and the list comprehensions keep the order of $R$ and $C$.
-/
def sysAlerts (p : Params) (o : Obs) : List Alert :=
  let s := o.system
  let n := nLive p o.now o.agents
  let k := nKind p o.now o.agents
  when (decide (p.agentCap < n)) ⟨.overCap, "team",
    s!"{n} live agents: {k .teammate} teammate, {k .subagent} subagent, {k .workflow} workflow; {nHelpers p o.now o.agents} with a parent agent"⟩ ++
  when (decide (s.diskFreeGB < p.diskMinGB)) ⟨.diskLow, "disk", s!"{s.diskFreeGB} GB free"⟩ ++
  when (s.memPressure == .critical) ⟨.memCritical, "memory", "memory pressure critical"⟩ ++
  (match s.simLock.since with
   | some t => when (s.simLock.holder.isSome && decide (p.simLockMaxMin * msPerMin ≤ o.now - t))
       ⟨.simLockLong, "sim", s!"held by {s.simLock.holder.getD ""} for {mins (o.now - t)} min"⟩
   | none => []) ++
  when (orphanB p o.now o.agents s.simLock) ⟨.simLockOrphan, "sim", s!"held by {s.simLock.holder.getD ""}"⟩ ++
  ((s.ci.filter fun r => ciFailing r && ciLatest s.ci r).map fun r =>
    ⟨.ciFailed, s!"{r.workflow}@{r.branch}", s!"latest run {r.conclusion.getD ""}"⟩) ++
  ((s.docker.filter (dockerOrphanB p o.now o.agents)).map fun c => ⟨.dockerOrphan, c.name, s!"container {c.id}"⟩) ++
  when (decide (p.worktreesMax < s.worktrees)) ⟨.worktreesMany, "worktrees", s!"{s.worktrees} worktrees"⟩ ++
  (match o.lead.noteAt with
   | some t => when (permB o.lead)
       ⟨.permissionWait, "lead", s!"notification {mins (o.now - t)} min ago, no lead tool call since"⟩
   | none => [])

/-- Every raised alert, unsorted: each agent's alerts, then the team and system alerts.

$$\operatorname{raw}(p, o) = \operatorname{flatMap}(\operatorname{agentAlerts}(p, \mathit{now}, A), A) \mathbin{+\!\!+} \operatorname{sysAlerts}(p, o)$$
-/
def raw (p : Params) (o : Obs) : List Alert := o.agents.flatMap (agentAlerts p o.now o.agents) ++ sysAlerts p o

/-- The state counts.

$$n = (n_{\mathrm{active}}, n_{\mathrm{idle}}, n_{\mathrm{parked}}, n_{\mathrm{stalled}}, n_{\mathrm{done}}) \in \mathbb N^5$$
-/
structure Counts where
  active  : Nat
  idle    : Nat
  parked  : Nat
  stalled : Nat
  done    : Nat
deriving DecidableEq, Repr

/-- One output row per agent: id, state, the codes of its alerts.

$$\mathit{row}(a) = (\mathit{id}(a), \operatorname{state}(p, t, A, a), \operatorname{map}(\mathit{code}, \operatorname{agentAlerts}(p, t, A, a)))$$
-/
structure Row where
  id     : String
  state  : State
  alerts : List Code
deriving DecidableEq, Repr

/-- The health report: a row per agent (input order), the codes of the team and system alerts (deduplicated, in code
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

$$\operatorname{health}(p, o) = \bigl(\operatorname{map}(\mathit{row}, A),\ \operatorname{dedup}(\operatorname{map}(\mathit{code}, \operatorname{sortU}(\operatorname{sysAlerts}(p, o)))),\ (\operatorname{count}(p, t, A, s))_{s \in \mathcal S},\ \operatorname{sortU}(\operatorname{raw}(p, o))\bigr)$$
-/
def health (p : Params) (o : Obs) : Report :=
  { agents := o.agents.map fun a => ⟨a.id, state p o.now o.agents a, (agentAlerts p o.now o.agents a).map (·.code)⟩
    system := ((sortU (sysAlerts p o)).map (·.code)).eraseDups
    counts := { active := countState p o.now o.agents .active, idle := countState p o.now o.agents .idle,
                parked := countState p o.now o.agents .parked, stalled := countState p o.now o.agents .stalled,
                done := countState p o.now o.agents .done }
    alerts := sortU (raw p o) }

/-! ## Report theorems -/

/-- The alert list holds exactly the raised alerts.

$$\forall p, o, x:\quad x \in \operatorname{health}(p, o).\mathit{alerts} \iff x \in \operatorname{raw}(p, o)$$
-/
theorem mem_alerts (p : Params) (o : Obs) (x : Alert) : x ∈ (health p o).alerts ↔ x ∈ raw p o :=
  mem_sortU x _

/-- The alert list is strictly sorted by (code, subject, detail), so it has no duplicates.

$$\forall p, o:\quad \operatorname{sorted}_\prec(\operatorname{health}(p, o).\mathit{alerts})$$
-/
theorem alerts_sorted (p : Params) (o : Obs) : (health p o).alerts.Pairwise Alert.Lt := sorted_sortU _

/-- A team or system alert carries one of the team and system codes, never an `agent.*` code.

$$\forall p, o, x:\quad x \in \operatorname{sysAlerts}(p, o) \Rightarrow \neg\operatorname{isAgent}(\mathit{code}(x))$$
-/
theorem sysAlerts_notAgent (p : Params) (o : Obs) (x : Alert) (h : x ∈ sysAlerts p o) :
    x.code.isAgent = false := by
  unfold sysAlerts at h
  simp only [List.mem_append, mem_when, List.mem_map, List.mem_filter] at h
  rcases h with ((((((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | h) | ⟨_, e⟩) | ⟨_, _, e⟩) | ⟨_, _, e⟩) | ⟨_, e⟩) | h)
  all_goals first
    | (subst e; rfl)
    | (split at h
       · rw [mem_when] at h; obtain ⟨_, e⟩ := h; subst e; rfl
       · simp at h)

/-- Every `agent.*` alert in the report names a live agent of the observation that is not parked: done and parked
agents raise none.

$$\forall p, o, x:\quad x \in \operatorname{health}(p, o).\mathit{alerts} \wedge \operatorname{isAgent}(\mathit{code}(x)) \Rightarrow \exists a \in A.\ \operatorname{state}(p, t, A, a) \notin \{\mathrm{done}, \mathrm{parked}\} \wedge \mathit{id}(a) = \mathit{subj}(x)$$
where $o = (t, A, \ell, \Sigma)$.
-/
theorem agent_alert_live (p : Params) (o : Obs) (x : Alert) (hx : x ∈ (health p o).alerts)
    (ha : x.code.isAgent = true) :
    ∃ a ∈ o.agents, state p o.now o.agents a ≠ .done ∧ state p o.now o.agents a ≠ .parked ∧ a.id = x.subject := by
  rw [mem_alerts] at hx
  unfold raw at hx
  rcases List.mem_append.1 hx with h | h
  · obtain ⟨a, ha', hxa⟩ := List.mem_flatMap.1 h
    refine ⟨a, ha', ?_, ?_, (agentAlerts_subject p o.now o.agents a x hxa).2.symm⟩
    · intro hs; rw [agentAlerts_quiet p o.now o.agents a (.inl hs)] at hxa; simp at hxa
    · intro hs; rw [agentAlerts_quiet p o.now o.agents a (.inr hs)] at hxa; simp at hxa
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
    rw [(agentAlerts_subject p o.now o.agents a x hxa).1] at hc; cases hc
  · exact h

/-- The simulator lock raises `sim.lockOrphan` exactly when it has a holder that names no live agent (by id, name or
task).

$$\forall p, o:\quad (\exists x \in \operatorname{health}(p, o).\mathit{alerts}.\ \mathit{code}(x) = \texttt{sim.lockOrphan}) \iff \exists h.\ \mathit{holder}(L) = h \wedge \neg \exists a \in A.\ \operatorname{live}(p, t, a) \wedge \operatorname{names}(h, a)$$
where $o = (t, A, \ell, \Sigma)$ and $L$ is the simulator lock of $\Sigma$.
-/
theorem lockOrphan_iff (p : Params) (o : Obs) :
    (∃ x ∈ (health p o).alerts, x.code = .simLockOrphan) ↔
      ∃ h, o.system.simLock.holder = some h ∧ ¬ ∃ a ∈ o.agents, live p o.now a = true ∧ names h a = true := by
  have key : (∃ x ∈ (health p o).alerts, x.code = .simLockOrphan) ↔
      orphanB p o.now o.agents o.system.simLock = true := by
    constructor
    · rintro ⟨x, hx, hc⟩
      have h := mem_sys_of_notAgent p o x hx (by rw [hc]; rfl)
      unfold sysAlerts at h
      simp only [List.mem_append, mem_when, List.mem_map, List.mem_filter] at h
      rcases h with ((((((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | h) | ⟨hb, _⟩) | ⟨_, _, e⟩) | ⟨_, _, e⟩) | ⟨_, e⟩) | h)
      all_goals first
        | (subst e; simp at hc)
        | exact hb
        | (split at h
           · rw [mem_when] at h; obtain ⟨_, e⟩ := h; subst e; simp at hc
           · simp at h)
    · intro hb
      refine ⟨⟨.simLockOrphan, "sim", s!"held by {o.system.simLock.holder.getD ""}"⟩, (mem_alerts p o _).2 ?_, rfl⟩
      unfold raw sysAlerts
      simp [List.mem_append, mem_when, hb]
  rw [key]
  unfold orphanB
  cases o.system.simLock.holder with
  | none => simp
  | some h => simp

/-- `team.permissionWait` fires exactly when a notification exists that is newer than the lead's last finished tool
call (or the lead has finished none).

$$\forall p, o:\quad (\exists x \in \operatorname{health}(p, o).\mathit{alerts}.\ \mathit{code}(x) = \texttt{team.permissionWait}) \iff \exists n.\ \mathit{noteAt}(\ell) = n \wedge \forall s.\ \mathit{lastToolAt}(\ell) = s \Rightarrow s < n$$
-/
theorem permissionWait_iff (p : Params) (o : Obs) :
    (∃ x ∈ (health p o).alerts, x.code = .permissionWait) ↔
      ∃ n, o.lead.noteAt = some n ∧ ∀ s, o.lead.lastToolAt = some s → s < n := by
  have key : (∃ x ∈ (health p o).alerts, x.code = .permissionWait) ↔ permB o.lead = true := by
    constructor
    · rintro ⟨x, hx, hc⟩
      have h := mem_sys_of_notAgent p o x hx (by rw [hc]; rfl)
      unfold sysAlerts at h
      simp only [List.mem_append, mem_when, List.mem_map, List.mem_filter] at h
      rcases h with ((((((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | h) | ⟨_, e⟩) | ⟨_, _, e⟩) | ⟨_, _, e⟩) | ⟨_, e⟩) | h)
      all_goals first
        | (subst e; simp at hc)
        | (split at h
           · rw [mem_when] at h; obtain ⟨_, e⟩ := h; subst e; simp at hc
           · simp at h)
        | (split at h
           · rw [mem_when] at h; exact h.1
           · simp at h)
    · intro hb
      cases hn : o.lead.noteAt with
      | none => simp [permB, hn] at hb
      | some n =>
        refine ⟨⟨.permissionWait, "lead", s!"notification {mins (o.now - n)} min ago, no lead tool call since"⟩,
          (mem_alerts p o _).2 ?_, rfl⟩
        unfold raw sysAlerts
        simp [List.mem_append, mem_when, hb, hn]
  rw [key]
  unfold permB
  cases o.lead.noteAt with
  | none => simp
  | some n => cases o.lead.lastToolAt <;> simp

/-! ## Monotonicity -/

/-- `q` is looser than `p`: every upper threshold of `q` is at least `p`'s, the disk floor of `q` is at most `p`'s,
and both use the same `wfQuietMin` (it decides which agents have ended, so it is not a loosening knob).

$$p \sqsubseteq q \iff \mathit{idle}_p \le \mathit{idle}_q \wedge \mathit{stall}_p \le \mathit{stall}_q \wedge \mathit{hang}_p \le \mathit{hang}_q \wedge \mathit{err}_p \le \mathit{err}_q \wedge \mathit{ctxMax}_p \le \mathit{ctxMax}_q \wedge \mathit{ctxWarn}_p \le \mathit{ctxWarn}_q \wedge \mathit{diskMin}_q \le \mathit{diskMin}_p \wedge \mathit{cap}_p \le \mathit{cap}_q \wedge \mathit{simMax}_p \le \mathit{simMax}_q \wedge \mathit{wtMax}_p \le \mathit{wtMax}_q \wedge \mathit{wfQuiet}_p = \mathit{wfQuiet}_q$$
-/
def Looser (p q : Params) : Prop :=
  p.idleMin ≤ q.idleMin ∧ p.stallMin ≤ q.stallMin ∧ p.toolHangMin ≤ q.toolHangMin ∧ p.errStreak ≤ q.errStreak ∧
  p.ctxResumeMax ≤ q.ctxResumeMax ∧ p.ctxWarn ≤ q.ctxWarn ∧ q.diskMinGB ≤ p.diskMinGB ∧ p.agentCap ≤ q.agentCap ∧
  p.simLockMaxMin ≤ q.simLockMaxMin ∧ p.worktreesMax ≤ q.worktreesMax ∧ p.wfQuietMin = q.wfQuietMin

/-- Whether an agent has ended depends on the thresholds only through `wfQuietMin`.

$$\forall p, q, t, a:\quad \mathit{wfQuiet}_p = \mathit{wfQuiet}_q \Rightarrow \operatorname{ended}(p, t, a) = \operatorname{ended}(q, t, a)$$
-/
theorem ended_congr (p q : Params) (t : Nat) (a : Agent) (h : p.wfQuietMin = q.wfQuietMin) :
    ended p t a = ended q t a := by
  simp [ended, h]

/-- So does whether an agent has a live child.

$$\forall p, q, t, A, a:\quad \mathit{wfQuiet}_p = \mathit{wfQuiet}_q \Rightarrow \operatorname{child}(p, t, A, a) = \operatorname{child}(q, t, A, a)$$
-/
theorem hasLiveChild_congr (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (h : p.wfQuietMin = q.wfQuietMin) :
    hasLiveChild p t A a = hasLiveChild q t A a := by
  simp only [hasLiveChild, live, ended_congr p q t _ h]

/-- A tool hung under looser thresholds has also hung under tighter ones.

$$\forall p, q, t, A, a:\quad p \sqsubseteq q \wedge \operatorname{hung}(q, t, A, a) \Rightarrow \operatorname{hung}(p, t, A, a)$$
-/
theorem hungB_mono (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (hpq : Looser p q)
    (h : hungB q t A a = true) : hungB p t A a = true := by
  obtain ⟨_, _, hh, _, _, _, _, _, _, _, hw⟩ := hpq
  unfold hungB at *
  rw [hasLiveChild_congr p q t A a hw]
  cases hf : a.inflight with
  | none => simp [hf] at h
  | some f =>
    simp only [hf, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
    exact ⟨h.1, Nat.le_trans (Nat.mul_le_mul_right _ hh) h.2⟩

/-- Stalling under looser thresholds implies stalling under tighter ones.

$$\forall p, q, t, A, a:\quad p \sqsubseteq q \wedge \operatorname{state}(q, t, A, a) = \mathrm{stalled} \Rightarrow \operatorname{state}(p, t, A, a) = \mathrm{stalled}$$
-/
theorem stalled_mono (p q : Params) (t : Nat) (A : List Agent) (a : Agent) (hpq : Looser p q)
    (h : state q t A a = .stalled) : state p t A a = .stalled := by
  have hs : stallB q t A a = true → stallB p t A a = true := by
    intro e
    unfold stallB at *
    simp only [Bool.and_eq_true, Bool.or_eq_true, decide_eq_true_eq] at e ⊢
    exact ⟨Nat.le_trans (Nat.mul_le_mul_right _ hpq.2.1) e.1, e.2.imp id (hungB_mono p q t A a hpq)⟩
  have he := ended_congr p q t a hpq.2.2.2.2.2.2.2.2.2.2
  rw [state_stalled] at h ⊢
  obtain ⟨h1, h2, h3⟩ := h
  exact ⟨by rw [he]; exact h1, h2, (stallB_iff p t A a).1 (hs ((stallB_iff q t A a).2 h3))⟩

/-- An agent alert under looser thresholds is also raised under tighter ones.

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
  have he := ended_congr p q t a hpq.2.2.2.2.2.2.2.2.2.2
  obtain ⟨_, _, _, hle, hc, hwn, _⟩ := hpq
  unfold agentAlerts at h ⊢
  rw [he]
  split at h
  · simp at h
  · rename_i hg
    simp only [hg, Bool.false_eq_true, ↓reduceIte, List.mem_append, mem_when] at h ⊢
    rcases h with (((⟨b, e⟩ | ⟨b, e⟩) | ⟨b, e⟩) | ⟨b, e⟩) | ⟨b, e⟩
    · exact .inl (.inl (.inl (.inl ⟨by simp at b ⊢; omega, e⟩)))
    · exact .inl (.inl (.inl (.inr ⟨by simp at b ⊢; omega, e⟩)))
    · exact .inl (.inl (.inr ⟨by simp at b ⊢; omega, e⟩))
    · exact .inl (.inr ⟨hs b, e⟩)
    · exact .inr ⟨hh b, e⟩

/-- A team or system alert under looser thresholds is also raised under tighter ones.

$$\forall p, q, o, x:\quad p \sqsubseteq q \wedge x \in \operatorname{sysAlerts}(q, o) \Rightarrow x \in \operatorname{sysAlerts}(p, o)$$
-/
theorem sysAlerts_mono (p q : Params) (o : Obs) (hpq : Looser p q) (x : Alert) (h : x ∈ sysAlerts q o) :
    x ∈ sysAlerts p o := by
  obtain ⟨_, _, _, _, _, _, hd, hcap, hsim, hwt, hw⟩ := hpq
  have hl : live q = live p := by funext t a; simp [live, ended_congr p q t a hw]
  have hn : nLive q o.now o.agents = nLive p o.now o.agents := by simp only [nLive, hl]
  have hk : nKind q o.now o.agents = nKind p o.now o.agents := by funext k; simp only [nKind, hl]
  have hhp : nHelpers q o.now o.agents = nHelpers p o.now o.agents := by simp only [nHelpers, hl]
  have ho : orphanB q o.now o.agents = orphanB p o.now o.agents := by funext l; simp only [orphanB, hl]
  have hdo : dockerOrphanB q o.now o.agents = dockerOrphanB p o.now o.agents := by
    funext c; simp only [dockerOrphanB, hl]
  unfold sysAlerts at *
  simp only [hn, hk, hhp, ho, hdo] at h
  simp only [List.mem_append, mem_when] at h ⊢
  rcases h with ((((((((⟨b, e⟩ | ⟨b, e⟩) | ⟨b, e⟩) | h) | ⟨b, e⟩) | h) | h) | ⟨b, e⟩) | h)
  · exact .inl (.inl (.inl (.inl (.inl (.inl (.inl (.inl ⟨by simp at b ⊢; omega, e⟩)))))))
  · exact .inl (.inl (.inl (.inl (.inl (.inl (.inl (.inr ⟨by simp at b ⊢; omega, e⟩)))))))
  · exact .inl (.inl (.inl (.inl (.inl (.inl (.inr ⟨b, e⟩))))))
  · refine .inl (.inl (.inl (.inl (.inl (.inr ?_)))))
    cases ht : o.system.simLock.since with
    | none => simp [ht] at h
    | some t =>
      simp only [ht, mem_when, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
      exact ⟨⟨h.1.1, Nat.le_trans (Nat.mul_le_mul_right _ hsim) h.1.2⟩, h.2⟩
  · exact .inl (.inl (.inl (.inl (.inr ⟨b, e⟩))))
  · exact .inl (.inl (.inl (.inr h)))
  · exact .inl (.inl (.inr h))
  · exact .inl (.inr ⟨by simp at b ⊢; omega, e⟩)
  · exact .inr h

/-- Loosening the thresholds never adds an alert: every alert of the report under $q$ is in the report under $p$.
(Raising any upper threshold, or lowering `diskMinGB`, with `wfQuietMin` unchanged, is a loosening.)

$$\forall p, q, o, x:\quad p \sqsubseteq q \wedge x \in \operatorname{health}(q, o).\mathit{alerts} \Rightarrow x \in \operatorname{health}(p, o).\mathit{alerts}$$
-/
theorem health_mono (p q : Params) (o : Obs) (hpq : Looser p q) (x : Alert) (h : x ∈ (health q o).alerts) :
    x ∈ (health p o).alerts := by
  rw [mem_alerts] at *
  unfold raw at *
  rcases List.mem_append.1 h with h | h
  · obtain ⟨a, ha, hx⟩ := List.mem_flatMap.1 h
    exact List.mem_append.2 (.inl (List.mem_flatMap.2 ⟨a, ha, agentAlerts_mono p q o.now o.agents a hpq x hx⟩))
  · exact List.mem_append.2 (.inr (sysAlerts_mono p q o hpq x h))

/-! ## Agent order does not matter -/

/-- An agent's state and alerts do not depend on the order of the agent list.

$$\forall p, t, A, l, a:\quad l \sim A \Rightarrow \operatorname{state}(p, t, l, a) = \operatorname{state}(p, t, A, a) \wedge \operatorname{agentAlerts}(p, t, l, a) = \operatorname{agentAlerts}(p, t, A, a)$$
-/
theorem agent_perm (p : Params) (t : Nat) (A l : List Agent) (a : Agent) (hl : l.Perm A) :
    state p t l a = state p t A a ∧ agentAlerts p t l a = agentAlerts p t A a := by
  have hc : hasLiveChild p t l a = hasLiveChild p t A a := by unfold hasLiveChild; rw [hl.any_eq]
  have hh : hungB p t l a = hungB p t A a := by unfold hungB; rw [hc]
  have hs : stallB p t l a = stallB p t A a := by unfold stallB; rw [hh]
  exact ⟨by unfold state; rw [hs], by unfold agentAlerts; rw [hs, hh]⟩

/-- The team and system alerts do not depend on the order of the agents.

$$\forall p, o, l:\quad l \sim A \Rightarrow \operatorname{sysAlerts}(p, o[A := l]) = \operatorname{sysAlerts}(p, o)$$
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
  unfold sysAlerts
  simp only [hn, hk, hh, ho, hd]

/-- The report's alerts, system codes and counts do not depend on the order of the agents (the rows follow it).

$$\forall p, o, l:\quad l \sim A \Rightarrow \operatorname{health}(p, o[A := l]).(\mathit{alerts}, \mathit{sysCodes}, n) = \operatorname{health}(p, o).(\mathit{alerts}, \mathit{sysCodes}, n)$$
-/
theorem health_perm (p : Params) (o : Obs) (l : List Agent) (hl : l.Perm o.agents) :
    (health p { o with agents := l }).alerts = (health p o).alerts ∧
    (health p { o with agents := l }).system = (health p o).system ∧
    (health p { o with agents := l }).counts = (health p o).counts := by
  have hs := sysAlerts_perm p o l hl
  have ha : agentAlerts p o.now l = agentAlerts p o.now o.agents := by
    funext a; exact (agent_perm p o.now o.agents l a hl).2
  have hst : state p o.now l = state p o.now o.agents := by
    funext a; exact (agent_perm p o.now o.agents l a hl).1
  refine ⟨?_, ?_, ?_⟩
  · apply eq_of_sorted _ _ (alerts_sorted _ _) (alerts_sorted _ _)
    intro z
    rw [mem_alerts, mem_alerts]
    unfold raw
    simp only [List.mem_append, hs, ha]
    rw [(hl.flatMap_right (agentAlerts p o.now o.agents)).mem_iff]
  · simp only [health, hs]
  · simp only [health, countState, hst, (hl.filter _).length_eq]

/-- The counts add up to the number of agents.

$$\forall p, o:\quad n_{\mathrm{active}} + n_{\mathrm{idle}} + n_{\mathrm{parked}} + n_{\mathrm{stalled}} + n_{\mathrm{done}} = |A|$$
where $(n_{\mathrm{active}}, n_{\mathrm{idle}}, n_{\mathrm{parked}}, n_{\mathrm{stalled}}, n_{\mathrm{done}}) =
\operatorname{health}(p, o).\mathit{counts}$ and $o = (t, A, \ell, \Sigma)$.
-/
theorem counts_total (p : Params) (o : Obs) :
    let c := (health p o).counts
    c.active + c.idle + c.parked + c.stalled + c.done = o.agents.length := by
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

#guard state {} (5 * msPerMin) [] a0 == .active
#guard state {} (10 * msPerMin - 1) [] a0 == .active
#guard state {} (10 * msPerMin) [] a0 == .idle
#guard state {} (20 * msPerMin) [] a0 == .stalled
#guard state {} (20 * msPerMin) [] { a0 with inflight := some ⟨"Bash", 0⟩ } == .idle
#guard state {} (30 * msPerMin) [] { a0 with inflight := some ⟨"Bash", 0⟩ } == .stalled
#guard state {} (99 * msPerMin) [] { a0 with stoppedAt := some 1 } == .done
#guard state {} 0 [] { a0 with lastAt := 5 } == .active
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
  == [.toolHang]
#guard agentAlerts {} (99 * msPerMin) [] { a0 with stoppedAt := some 1, errTail := 9, ctxTokens := some 300000 } == []
#guard agentAlerts {} (99 * msPerMin) [] { tm0 with idleAt := some 1, errTail := 9, ctxTokens := some 300000 } == []
#guard (agentAlerts {} 0 [] { a0 with ctxTokens := some 250001 }).map (·.code) == [.ctxHigh, .ctxWarn]
#guard (agentAlerts {} 0 [] { a0 with ctxTokens := some 250000 }).map (·.code) == [.ctxWarn]
#guard (agentAlerts {} 0 [] { a0 with errTail := 3 }).map (·.code) == [.errStreak]
#guard (agentAlerts {} 0 [] { a0 with errTail := 2 }).map (·.code) == []
#guard (agentAlerts { errStreak := 0 } 0 [] { a0 with errTail := 0 }).map (·.code) == []
#guard (agentAlerts {} (30 * msPerMin) [] { a0 with inflight := some ⟨"Bash", 0⟩ }).map (·.code) == [.stalled, .toolHang]
#guard permB {} == false
#guard permB { noteAt := some 5 } == true
#guard permB { noteAt := some 5, lastToolAt := some 4 } == true
#guard permB { noteAt := some 5, lastToolAt := some 5 } == false
#guard permB { lastToolAt := some 5 } == false
#guard orphanB {} 0 [{ a0 with task := some "wktr" }] { holder := some "wktr" } == false
#guard orphanB {} 0 [{ a0 with task := some "wktr", stoppedAt := some 1 }] { holder := some "wktr" } == true
#guard orphanB {} 0 [] {} == false
#guard ciLatest [⟨"ci", "main", "completed", some "failure", 1⟩, ⟨"ci", "main", "completed", some "success", 2⟩]
  ⟨"ci", "main", "completed", some "failure", 1⟩ == false
#guard dockerOrphanB {} 0 [{ a0 with startedAt := 5 }] ⟨"c1", "pg", 4⟩ == true
#guard dockerOrphanB {} 0 [{ a0 with startedAt := 5 }] ⟨"c1", "pg", 5⟩ == false
#guard nLive {} 0 [a0, { a0 with kind := .lead }, { a0 with kind := .workflow, workflowDone := true }] == 1
#guard ((health {} { now := 0, system := { diskFreeGB := 19, memPressure := .critical } }).alerts.map (·.code))
  == [.diskLow, .memCritical]
#guard (health {} { now := 0, system := { diskFreeGB := 20 } }).alerts == []
#guard ((health {} { now := 0, lead := { noteAt := some 0 }, system := { diskFreeGB := 20 } }).alerts.map (·.code))
  == [.permissionWait]
#guard sortU [⟨.diskLow, "disk", "1"⟩, ⟨.ctxHigh, "b", "x"⟩, ⟨.ctxHigh, "a", "x"⟩, ⟨.diskLow, "disk", "1"⟩]
  == [⟨.ctxHigh, "a", "x"⟩, ⟨.ctxHigh, "b", "x"⟩, ⟨.diskLow, "disk", "1"⟩]

end Fw.Obs.Health
