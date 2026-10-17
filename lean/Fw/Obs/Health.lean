/-!
# Team health: per-agent state and alert rules over one observation snapshot

`fw watch` (task `watch-cli`) collects one snapshot per interval: every agent's timing and tool facts, plus system,
simulator-lock, Docker, worktree and CI facts. This module is the pure part: from the snapshot and the thresholds it
derives each agent's state (`active`, `idle`, `waiting`, `stalled`, `done`) and a sorted, duplicate-free list of
alerts. The wire op `obs.health` (`Fw.Wire.Obs`) is its JSON face.

Units: times are ms since the epoch (`Nat`); the `…Min` thresholds are minutes ($\mu = 60000$ ms each); an age is the
truncated difference $\mathit{now} \mathbin{\dot-} t$ (a timestamp after `now` has age 0). Context sizes are tokens,
disk is whole GB.

Rules (proved below):
* `state_done`, `state_waiting`, `state_stalled`, `state_idle`, `state_active`: the state is exactly the one the
  rules name; `state_cases`: exactly one holds.
* `agentAlerts_done`, `agent_alert_live`: a done agent raises no `agent.*` alert.
* `stalled_facts`: a stalled agent is not waiting and its age is at least the stall threshold.
* `health_mono`: loosening the thresholds (raising any upper threshold, lowering `diskMinGB`) never adds an alert.
* `lockOrphan_iff`: `sim.lockOrphan` fires iff the lock has a holder that names no live agent.
* `alerts_sorted`, `mem_alerts`, `health_perm`: the alert list is strictly sorted by (code, subject, detail), holds
  exactly the raised alerts, and does not depend on the order of the agents.
-/
namespace Fw.Obs.Health

/-- Milliseconds per minute, the unit of every `…Min` threshold.

$$\mu = 60000$$
-/
def msPerMin : Nat := 60000

/-- The thresholds. Upper thresholds (an alert needs a value at or above them): `idleMin`, `stallMin`, `toolHangMin`
(minutes), `errStreak` (failed calls), `ctxResumeMax`, `ctxWarn` (tokens), `agentCap` (live spawned agents),
`simLockMaxMin` (minutes), `worktreesMax`; the lower threshold `diskMinGB` (free GB below it alerts).

$$p = (\mathit{idle}, \mathit{stall}, \mathit{hang}, \mathit{err}, \mathit{ctxMax}, \mathit{ctxWarn}, \mathit{disk}, \mathit{cap}, \mathit{simMax}, \mathit{wtMax}) \in \mathbb N^{10}$$
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
deriving DecidableEq, Repr

/-- A tool call still running: the tool's name and its start time (ms).

$$f = (\mathit{tool}, \mathit{since}) \in \mathrm{String} \times \mathbb N$$
-/
structure Inflight where
  tool  : String
  since : Nat
deriving DecidableEq, Repr

/-- One agent as observed: id, optional name and task (a lock holder may name either), spawn depth (0 is the lead
session), start, last event and stop times (ms; `stoppedAt` is `none` while it runs), the number of failed tool calls
at the end of its log, the tool call in flight, whether it waits for a permission answer, and its context size.

$$a = (\mathit{id}, \mathit{name}_\bot, \mathit{task}_\bot, \mathit{depth}, \mathit{start}, \mathit{last}, \mathit{stop}_\bot, \mathit{errTail}, f_\bot, w, \mathit{ctx}_\bot)$$
-/
structure Agent where
  id                : String
  name              : Option String := none
  task              : Option String := none
  depth             : Nat := 1
  startedAt         : Nat := 0
  lastAt            : Nat := 0
  stoppedAt         : Option Nat := none
  errTail           : Nat := 0
  inflight          : Option Inflight := none
  waitingPermission : Bool := false
  ctxTokens         : Option Nat := none
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

/-- One observation: the time it was taken (ms), the agents, the system facts.

$$o = (\mathit{now}, A, \Sigma)$$
-/
structure Obs where
  now    : Nat
  agents : List Agent := []
  system : System := {}
deriving DecidableEq, Repr

/-! ## Agent state -/

/-- The five agent states.

$$\mathcal S = \{\mathrm{active}, \mathrm{idle}, \mathrm{waiting}, \mathrm{stalled}, \mathrm{done}\}$$
-/
inductive State where
  | active | idle | waiting | stalled | done
deriving DecidableEq, Repr

/-- The stall test as a Boolean: no event for `stallMin` minutes, and no tool in flight or the one in flight has run
for `toolHangMin` minutes.

$$\operatorname{stallB}(p, t, a) \iff \mu\,\mathit{stall} \le t \mathbin{\dot-} \mathit{last}(a) \wedge (f(a) = \bot \vee \mu\,\mathit{hang} \le t \mathbin{\dot-} \mathit{since}(f(a)))$$
-/
def stallB (p : Params) (now : Nat) (a : Agent) : Bool :=
  decide (p.stallMin * msPerMin ≤ now - a.lastAt) &&
    (match a.inflight with
     | none => true
     | some f => decide (p.toolHangMin * msPerMin ≤ now - f.since))

/-- The stall condition as a proposition.

$$\operatorname{Stall}(p, t, a) \iff \mu\,\mathit{stall} \le t \mathbin{\dot-} \mathit{last}(a) \wedge \forall f.\ f(a) = f \Rightarrow \mu\,\mathit{hang} \le t \mathbin{\dot-} \mathit{since}(f)$$
-/
def Stall (p : Params) (now : Nat) (a : Agent) : Prop :=
  p.stallMin * msPerMin ≤ now - a.lastAt ∧ ∀ f, a.inflight = some f → p.toolHangMin * msPerMin ≤ now - f.since

/-- The Boolean stall test decides `Stall`.

$$\forall p, t, a:\quad \operatorname{stallB}(p, t, a) = \mathrm{true} \iff \operatorname{Stall}(p, t, a)$$
-/
theorem stallB_iff (p : Params) (t : Nat) (a : Agent) : stallB p t a = true ↔ Stall p t a := by
  unfold stallB Stall
  cases h : a.inflight with
  | none => simp
  | some f => simp

/-- An agent's state: done once stopped; else waiting while a permission prompt is open; else stalled when the stall
test holds; else idle after `idleMin` minutes without an event; else active.

$$\operatorname{state}(p, t, a) = \begin{cases} \mathrm{done} & \mathit{stop}(a) \ne \bot \\ \mathrm{waiting} & \text{else if } w(a) \\ \mathrm{stalled} & \text{else if } \operatorname{Stall}(p, t, a) \\ \mathrm{idle} & \text{else if } \mu\,\mathit{idle} \le t \mathbin{\dot-} \mathit{last}(a) \\ \mathrm{active} & \text{otherwise} \end{cases}$$
-/
def state (p : Params) (now : Nat) (a : Agent) : State :=
  if a.stoppedAt.isSome then .done
  else if a.waitingPermission then .waiting
  else if stallB p now a then .stalled
  else if p.idleMin * msPerMin ≤ now - a.lastAt then .idle
  else .active

/-- Done exactly when stopped.

$$\forall p, t, a:\quad \operatorname{state}(p, t, a) = \mathrm{done} \iff \mathit{stop}(a) \ne \bot$$
-/
theorem state_done (p : Params) (t : Nat) (a : Agent) : state p t a = .done ↔ a.stoppedAt ≠ none := by
  unfold state
  cases a.stoppedAt <;> simp <;> split <;> (try split) <;> (try split) <;> simp

/-- Waiting exactly when not stopped and a permission prompt is open.

$$\forall p, t, a:\quad \operatorname{state}(p, t, a) = \mathrm{waiting} \iff \mathit{stop}(a) = \bot \wedge w(a)$$
-/
theorem state_waiting (p : Params) (t : Nat) (a : Agent) :
    state p t a = .waiting ↔ a.stoppedAt = none ∧ a.waitingPermission = true := by
  unfold state
  cases a.stoppedAt <;> cases a.waitingPermission <;> simp <;> split <;> (try split) <;> simp

/-- Stalled exactly when not stopped, not waiting and the stall condition holds.

$$\forall p, t, a:\quad \operatorname{state}(p, t, a) = \mathrm{stalled} \iff \mathit{stop}(a) = \bot \wedge \neg w(a) \wedge \operatorname{Stall}(p, t, a)$$
-/
theorem state_stalled (p : Params) (t : Nat) (a : Agent) :
    state p t a = .stalled ↔ a.stoppedAt = none ∧ a.waitingPermission = false ∧ Stall p t a := by
  rw [← stallB_iff]
  unfold state
  cases a.stoppedAt <;> cases a.waitingPermission <;> cases stallB p t a <;> simp <;> split <;> simp

/-- Idle exactly when not stopped, not waiting, not stalled and without an event for `idleMin` minutes.

$$\forall p, t, a:\quad \operatorname{state}(p, t, a) = \mathrm{idle} \iff \mathit{stop}(a) = \bot \wedge \neg w(a) \wedge \neg\operatorname{Stall}(p, t, a) \wedge \mu\,\mathit{idle} \le t \mathbin{\dot-} \mathit{last}(a)$$
-/
theorem state_idle (p : Params) (t : Nat) (a : Agent) :
    state p t a = .idle ↔ a.stoppedAt = none ∧ a.waitingPermission = false ∧ ¬ Stall p t a ∧
      p.idleMin * msPerMin ≤ t - a.lastAt := by
  rw [← stallB_iff]
  unfold state
  cases a.stoppedAt <;> cases a.waitingPermission <;> cases stallB p t a <;> simp <;> split <;> simp_all

/-- Active exactly when not stopped, not waiting, not stalled and with an event within `idleMin` minutes.

$$\forall p, t, a:\quad \operatorname{state}(p, t, a) = \mathrm{active} \iff \mathit{stop}(a) = \bot \wedge \neg w(a) \wedge \neg\operatorname{Stall}(p, t, a) \wedge t \mathbin{\dot-} \mathit{last}(a) < \mu\,\mathit{idle}$$
-/
theorem state_active (p : Params) (t : Nat) (a : Agent) :
    state p t a = .active ↔ a.stoppedAt = none ∧ a.waitingPermission = false ∧ ¬ Stall p t a ∧
      t - a.lastAt < p.idleMin * msPerMin := by
  rw [← stallB_iff]
  unfold state
  cases a.stoppedAt <;> cases a.waitingPermission <;> cases stallB p t a <;> simp <;> split <;> simp_all <;> omega

/-- Exactly one of the five rule conditions holds, and the state is the one it names (the five conditions partition
all agents).

$$\forall p, t, a:\quad \bigl(\mathit{stop}(a) \ne \bot\bigr) \oplus \bigl(\mathit{stop}(a) = \bot \wedge w(a)\bigr) \oplus \bigl(\mathit{stop}(a) = \bot \wedge \neg w(a) \wedge \operatorname{Stall}\bigr) \oplus \bigl(\ldots \wedge \neg\operatorname{Stall} \wedge \mu\,\mathit{idle} \le t \mathbin{\dot-} \mathit{last}(a)\bigr) \oplus \bigl(\ldots \wedge \neg\operatorname{Stall} \wedge t \mathbin{\dot-} \mathit{last}(a) < \mu\,\mathit{idle}\bigr),$$
stated as: the state is one of the five, and two different states never hold together.
$$\forall p, t, a:\ \operatorname{state}(p,t,a) \in \mathcal S \quad\text{and}\quad \forall s, s' \in \mathcal S:\ \operatorname{state}(p,t,a) = s \wedge \operatorname{state}(p,t,a) = s' \Rightarrow s = s'$$
-/
theorem state_cases (p : Params) (t : Nat) (a : Agent) :
    (state p t a = .active ∨ state p t a = .idle ∨ state p t a = .waiting ∨ state p t a = .stalled ∨
      state p t a = .done) ∧
    ∀ s s' : State, state p t a = s → state p t a = s' → s = s' := by
  refine ⟨?_, fun s s' h h' => h ▸ h'⟩
  cases state p t a <;> simp

/-- A stalled agent is not waiting, and it has had no event for at least `stallMin` minutes.

$$\forall p, t, a:\quad \operatorname{state}(p, t, a) = \mathrm{stalled} \Rightarrow \neg w(a) \wedge \mu\,\mathit{stall} \le t \mathbin{\dot-} \mathit{last}(a)$$
-/
theorem stalled_facts (p : Params) (t : Nat) (a : Agent) (h : state p t a = .stalled) :
    a.waitingPermission = false ∧ p.stallMin * msPerMin ≤ t - a.lastAt := by
  obtain ⟨_, hw, hs, _⟩ := (state_stalled p t a).1 h
  exact ⟨hw, hs⟩

/-! ## Alerts -/

/-- The alert codes, listed in the order of their wire names.

$$\mathcal C = \{\texttt{agent.ctxHigh}, \texttt{agent.ctxWarn}, \texttt{agent.errStreak}, \texttt{agent.permissionWait}, \texttt{agent.stalled}, \texttt{agent.toolHang}, \texttt{ci.failed}, \texttt{docker.orphan}, \texttt{sim.lockLong}, \texttt{sim.lockOrphan}, \texttt{sys.diskLow}, \texttt{sys.memCritical}, \texttt{team.overCap}, \texttt{worktrees.many}\}$$
-/
inductive Code where
  | ctxHigh | ctxWarn | errStreak | permissionWait | stalled | toolHang
  | ciFailed | dockerOrphan | simLockLong | simLockOrphan | diskLow | memCritical | overCap | worktreesMany
deriving DecidableEq, Repr

/-- Every code, in rank order.

$$\mathcal C = (c_0, \ldots, c_{13})$$
-/
def Code.all : List Code :=
  [.ctxHigh, .ctxWarn, .errStreak, .permissionWait, .stalled, .toolHang,
   .ciFailed, .dockerOrphan, .simLockLong, .simLockOrphan, .diskLow, .memCritical, .overCap, .worktreesMany]

/-- The wire name of a code.

$$\operatorname{name}(c_i) = \text{the } i\text{-th string of } \mathcal C$$
-/
def Code.name : Code → String
  | .ctxHigh => "agent.ctxHigh" | .ctxWarn => "agent.ctxWarn" | .errStreak => "agent.errStreak"
  | .permissionWait => "agent.permissionWait" | .stalled => "agent.stalled" | .toolHang => "agent.toolHang"
  | .ciFailed => "ci.failed" | .dockerOrphan => "docker.orphan" | .simLockLong => "sim.lockLong"
  | .simLockOrphan => "sim.lockOrphan" | .diskLow => "sys.diskLow" | .memCritical => "sys.memCritical"
  | .overCap => "team.overCap" | .worktreesMany => "worktrees.many"

/-- The rank of a code (its position in `Code.all`).

$$\operatorname{rank}(c_i) = i$$
-/
def Code.rank : Code → Nat
  | .ctxHigh => 0 | .ctxWarn => 1 | .errStreak => 2 | .permissionWait => 3 | .stalled => 4 | .toolHang => 5
  | .ciFailed => 6 | .dockerOrphan => 7 | .simLockLong => 8 | .simLockOrphan => 9 | .diskLow => 10
  | .memCritical => 11 | .overCap => 12 | .worktreesMany => 13

/-- Whether a code is about one agent (`agent.*`).

$$\operatorname{isAgent}(c) \iff \operatorname{rank}(c) < 6$$
-/
def Code.isAgent (c : Code) : Bool := c.rank < 6

/-- The rank determines the code.

$$\forall c, c' \in \mathcal C:\quad \operatorname{rank}(c) = \operatorname{rank}(c') \Rightarrow c = c'$$
-/
theorem Code.rank_inj (c c' : Code) (h : c.rank = c'.rank) : c = c' := by
  cases c <;> cases c' <;> simp_all [Code.rank]

/-- Rank order is the order of the wire names: the names in rank order are strictly increasing strings.

$$\operatorname{name}(c_0) < \operatorname{name}(c_1) < \cdots < \operatorname{name}(c_{13}) \quad\text{(lexicographic)}$$
-/
theorem Code.names_sorted : (Code.all.map Code.name).Pairwise (· < ·) := by decide

/-- An alert: its code, its subject (an agent id, `team`, `disk`, `memory`, `sim`, `workflow@branch`, a container
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

/-- Whether a tool in flight has hung: the agent is neither stopped nor waiting, and its tool call has run for
`toolHangMin` minutes.

$$\operatorname{hangB}(p, t, a) \iff \mathit{stop}(a) = \bot \wedge \neg w(a) \wedge \exists f.\ f(a) = f \wedge \mu\,\mathit{hang} \le t \mathbin{\dot-} \mathit{since}(f)$$
-/
def hangB (p : Params) (now : Nat) (a : Agent) : Bool :=
  a.stoppedAt.isNone && !a.waitingPermission &&
    (match a.inflight with
     | none => false
     | some f => decide (p.toolHangMin * msPerMin ≤ now - f.since))

/-- The `agent.*` alerts of one agent (none once it is done), in code order: context over `ctxResumeMax` (do not
resume it), context over `ctxWarn`, at least `errStreak` (and at least one) failed calls in a row, a permission prompt
open, stalled, a tool hung.

$$\operatorname{agentAlerts}(p, t, a) = \begin{cases} [] & \mathit{stop}(a) \ne \bot \\ [\, (c, \mathit{id}(a), \cdot) \mid c \text{ raised} \,] & \text{otherwise} \end{cases}$$
with $\texttt{ctxHigh} \iff \mathit{ctx}(a) > \mathit{ctxMax}$, $\texttt{ctxWarn} \iff \mathit{ctx}(a) > \mathit{ctxWarn}$,
$\texttt{errStreak} \iff \mathit{errTail}(a) \ge \max(\mathit{err}, 1)$, $\texttt{permissionWait} \iff
\operatorname{state} = \mathrm{waiting}$, $\texttt{stalled} \iff \operatorname{state} = \mathrm{stalled}$,
$\texttt{toolHang} \iff \operatorname{hangB}(p, t, a)$.
-/
def agentAlerts (p : Params) (now : Nat) (a : Agent) : List Alert :=
  if a.stoppedAt.isSome then [] else
  let ctx := a.ctxTokens.getD 0
  let st := state p now a
  when (decide (p.ctxResumeMax < ctx)) ⟨.ctxHigh, a.id, s!"{ctx} context tokens"⟩ ++
  when (decide (p.ctxWarn < ctx)) ⟨.ctxWarn, a.id, s!"{ctx} context tokens"⟩ ++
  when (decide (0 < a.errTail ∧ p.errStreak ≤ a.errTail)) ⟨.errStreak, a.id, s!"{a.errTail} failed tool calls in a row"⟩ ++
  when (st == .waiting) ⟨.permissionWait, a.id, s!"waiting for permission, no event for {mins (now - a.lastAt)} min"⟩ ++
  when (st == .stalled) ⟨.stalled, a.id, s!"no event for {mins (now - a.lastAt)} min"⟩ ++
  when (hangB p now a)
    ⟨.toolHang, a.id, match a.inflight with
      | some f => s!"{f.tool} running for {mins (now - f.since)} min"
      | none => ""⟩

/-- A done agent raises no alert.

$$\forall p, t, a:\quad \mathit{stop}(a) \ne \bot \Rightarrow \operatorname{agentAlerts}(p, t, a) = []$$
-/
theorem agentAlerts_done (p : Params) (t : Nat) (a : Agent) (h : a.stoppedAt ≠ none) :
    agentAlerts p t a = [] := by
  unfold agentAlerts
  cases hs : a.stoppedAt with
  | none => exact absurd hs h
  | some _ => rfl

/-- Every alert of an agent is an `agent.*` alert about that agent.

$$\forall p, t, a, x:\quad x \in \operatorname{agentAlerts}(p, t, a) \Rightarrow \operatorname{isAgent}(\mathit{code}(x)) \wedge \mathit{subj}(x) = \mathit{id}(a)$$
-/
theorem agentAlerts_subject (p : Params) (t : Nat) (a : Agent) (x : Alert) (h : x ∈ agentAlerts p t a) :
    x.code.isAgent = true ∧ x.subject = a.id := by
  unfold agentAlerts at h
  split at h
  · simp at h
  · simp only [List.mem_append, mem_when] at h
    rcases h with ((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩) | ⟨_, e⟩ <;> subst e <;> simp [Code.isAgent, Code.rank]

/-- Whether an agent is live (not stopped).

$$\operatorname{live}(a) \iff \mathit{stop}(a) = \bot$$
-/
def live (a : Agent) : Bool := a.stoppedAt.isNone

/-- Whether a lock owner string names an agent: its id, name or task.

$$\operatorname{names}(h, a) \iff h = \mathit{id}(a) \vee \mathit{name}(a) = h \vee \mathit{task}(a) = h$$
-/
def names (h : String) (a : Agent) : Bool := a.id == h || a.name == some h || a.task == some h

/-- Whether the simulator lock is orphaned: it has a holder and no live agent is named by it.

$$\operatorname{orphanB}(A, L) \iff \exists h.\ \mathit{holder}(L) = h \wedge \neg \exists a \in A.\ \operatorname{live}(a) \wedge \operatorname{names}(h, a)$$
-/
def orphanB (agents : List Agent) (l : SimLock) : Bool :=
  match l.holder with
  | none => false
  | some h => !agents.any fun a => live a && names h a

/-- A CI conclusion that counts as a failure.

$$\operatorname{failing}(r) \iff \mathit{concl}(r) \in \{\texttt{failure}, \texttt{timed\_out}, \texttt{startup\_failure}\}$$
-/
def ciFailing (r : CiRun) : Bool :=
  r.conclusion == some "failure" || r.conclusion == some "timed_out" || r.conclusion == some "startup_failure"

/-- Whether a run is the latest of its workflow and branch (no run of the same pair started later).

$$\operatorname{latest}(R, r) \iff \forall r' \in R:\ (\mathit{wf}, \mathit{br})(r') = (\mathit{wf}, \mathit{br})(r) \Rightarrow \mathit{start}(r') \le \mathit{start}(r)$$
-/
def ciLatest (runs : List CiRun) (r : CiRun) : Bool :=
  runs.all fun r' => !(r'.workflow == r.workflow && r'.branch == r.branch) || decide (r'.startedAt ≤ r.startedAt)

/-- Whether a container is orphaned: no live agent started at or before it (so none could have started it).

$$\operatorname{orphanC}(A, c) \iff \neg \exists a \in A.\ \operatorname{live}(a) \wedge \mathit{start}(a) \le \mathit{start}(c)$$
-/
def dockerOrphanB (agents : List Agent) (c : Container) : Bool :=
  !agents.any fun a => live a && decide (a.startedAt ≤ c.startedAt)

/-- The number of live spawned agents (depth at least 1; the lead session is depth 0).

$$\operatorname{nLive}(A) = |\{a \in A \mid \operatorname{live}(a) \wedge \mathit{depth}(a) \ge 1\}|$$
-/
def nLive (agents : List Agent) : Nat := (agents.filter fun a => live a && decide (1 ≤ a.depth)).length

/-- The team and system alerts: more live spawned agents than `agentCap`; free disk below `diskMinGB`; memory
pressure critical; the simulator lock held for `simLockMaxMin` minutes; the lock orphaned; the latest run of a
workflow and branch failed; an orphaned container; more worktrees than `worktreesMax`.

$$\operatorname{sysAlerts}(p, o) = [\texttt{team.overCap} \mid \operatorname{nLive} > \mathit{cap}] \mathbin{+\!\!+} [\texttt{sys.diskLow} \mid \mathit{disk} < \mathit{diskMin}] \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} [\texttt{worktrees.many} \mid \mathit{wt} > \mathit{wtMax}]$$
-/
def sysAlerts (p : Params) (o : Obs) : List Alert :=
  let s := o.system
  let n := nLive o.agents
  when (decide (p.agentCap < n)) ⟨.overCap, "team", s!"{n} live agents"⟩ ++
  when (decide (s.diskFreeGB < p.diskMinGB)) ⟨.diskLow, "disk", s!"{s.diskFreeGB} GB free"⟩ ++
  when (s.memPressure == .critical) ⟨.memCritical, "memory", "memory pressure critical"⟩ ++
  (match s.simLock.since with
   | some t => when (s.simLock.holder.isSome && decide (p.simLockMaxMin * msPerMin ≤ o.now - t))
       ⟨.simLockLong, "sim", s!"held by {s.simLock.holder.getD ""} for {mins (o.now - t)} min"⟩
   | none => []) ++
  when (orphanB o.agents s.simLock) ⟨.simLockOrphan, "sim", s!"held by {s.simLock.holder.getD ""}"⟩ ++
  ((s.ci.filter fun r => ciFailing r && ciLatest s.ci r).map fun r =>
    ⟨.ciFailed, s!"{r.workflow}@{r.branch}", s!"latest run {r.conclusion.getD ""}"⟩) ++
  ((s.docker.filter (dockerOrphanB o.agents)).map fun c => ⟨.dockerOrphan, c.name, s!"container {c.id}"⟩) ++
  when (decide (p.worktreesMax < s.worktrees)) ⟨.worktreesMany, "worktrees", s!"{s.worktrees} worktrees"⟩

/-- Every raised alert, unsorted: each agent's alerts, then the team and system alerts.

$$\operatorname{raw}(p, o) = \operatorname{flatMap}(\operatorname{agentAlerts}(p, \mathit{now}), A) \mathbin{+\!\!+} \operatorname{sysAlerts}(p, o)$$
-/
def raw (p : Params) (o : Obs) : List Alert := o.agents.flatMap (agentAlerts p o.now) ++ sysAlerts p o

/-- The state counts.

$$n = (n_{\mathrm{active}}, n_{\mathrm{idle}}, n_{\mathrm{waiting}}, n_{\mathrm{stalled}}, n_{\mathrm{done}}) \in \mathbb N^5$$
-/
structure Counts where
  active  : Nat
  idle    : Nat
  waiting : Nat
  stalled : Nat
  done    : Nat
deriving DecidableEq, Repr

/-- One output row per agent: id, state, the codes of its alerts.

$$\mathit{row}(a) = (\mathit{id}(a), \operatorname{state}(p, t, a), \operatorname{map}(\mathit{code}, \operatorname{agentAlerts}(p, t, a)))$$
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

$$\operatorname{count}(p, t, A, s) = |\{a \in A \mid \operatorname{state}(p, t, a) = s\}|$$
-/
def countState (p : Params) (now : Nat) (agents : List Agent) (s : State) : Nat :=
  (agents.filter fun a => state p now a == s).length

/-- The health report of one observation.

$$\operatorname{health}(p, o) = \bigl(\operatorname{map}(\mathit{row}, A),\ \operatorname{dedup}(\operatorname{map}(\mathit{code}, \operatorname{sortU}(\operatorname{sysAlerts}(p, o)))),\ (\operatorname{count}(p, t, A, s))_{s \in \mathcal S},\ \operatorname{sortU}(\operatorname{raw}(p, o))\bigr)$$
-/
def health (p : Params) (o : Obs) : Report :=
  { agents := o.agents.map fun a => ⟨a.id, state p o.now a, (agentAlerts p o.now a).map (·.code)⟩
    system := ((sortU (sysAlerts p o)).map (·.code)).eraseDups
    counts := { active := countState p o.now o.agents .active, idle := countState p o.now o.agents .idle,
                waiting := countState p o.now o.agents .waiting, stalled := countState p o.now o.agents .stalled,
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

/-- Every `agent.*` alert in the report names a live agent of the observation: done agents raise none.

$$\forall p, o, x:\quad x \in \operatorname{health}(p, o).\mathit{alerts} \wedge \operatorname{isAgent}(\mathit{code}(x)) \Rightarrow \exists a \in A.\ \mathit{stop}(a) = \bot \wedge \mathit{id}(a) = \mathit{subj}(x)$$
-/
theorem agent_alert_live (p : Params) (o : Obs) (x : Alert) (hx : x ∈ (health p o).alerts)
    (ha : x.code.isAgent = true) : ∃ a ∈ o.agents, a.stoppedAt = none ∧ a.id = x.subject := by
  rw [mem_alerts] at hx
  unfold raw at hx
  rcases List.mem_append.1 hx with h | h
  · obtain ⟨a, ha', hxa⟩ := List.mem_flatMap.1 h
    refine ⟨a, ha', ?_, (agentAlerts_subject p o.now a x hxa).2.symm⟩
    cases hs : a.stoppedAt with
    | none => rfl
    | some _ => rw [agentAlerts_done p o.now a (by simp [hs])] at hxa; simp at hxa
  · exfalso
    unfold sysAlerts at h
    simp only [List.mem_append, mem_when, List.mem_map, List.mem_filter] at h
    rcases h with ((((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | h) | ⟨_, e⟩) | ⟨_, _, e⟩) | ⟨_, _, e⟩) | ⟨_, e⟩
    all_goals first
      | (subst e; simp [Code.isAgent, Code.rank] at ha)
      | skip
    · split at h
      · rw [mem_when] at h; obtain ⟨_, e⟩ := h; subst e; simp [Code.isAgent, Code.rank] at ha
      · simp at h

/-- The simulator lock raises `sim.lockOrphan` exactly when it has a holder that names no live agent (by id, name or
task).

$$\forall p, o:\quad (\texttt{sim.lockOrphan}, \texttt{sim}, \cdot) \in \operatorname{health}(p, o).\mathit{alerts} \iff \exists h.\ \mathit{holder}(L) = h \wedge \neg \exists a \in A.\ \mathit{stop}(a) = \bot \wedge \operatorname{names}(h, a)$$
-/
theorem lockOrphan_iff (p : Params) (o : Obs) :
    (∃ x ∈ (health p o).alerts, x.code = .simLockOrphan) ↔
      ∃ h, o.system.simLock.holder = some h ∧ ¬ ∃ a ∈ o.agents, a.stoppedAt = none ∧ names h a = true := by
  have key : (∃ x ∈ (health p o).alerts, x.code = .simLockOrphan) ↔ orphanB o.agents o.system.simLock = true := by
    constructor
    · rintro ⟨x, hx, hc⟩
      rw [mem_alerts] at hx
      unfold raw at hx
      rcases List.mem_append.1 hx with h | h
      · obtain ⟨a, _, hxa⟩ := List.mem_flatMap.1 h
        have := (agentAlerts_subject p o.now a x hxa).1
        rw [hc] at this; simp [Code.isAgent, Code.rank] at this
      · unfold sysAlerts at h
        simp only [List.mem_append, mem_when, List.mem_map, List.mem_filter] at h
        rcases h with ((((((⟨_, e⟩ | ⟨_, e⟩) | ⟨_, e⟩) | h) | ⟨hb, _⟩) | ⟨_, _, e⟩) | ⟨_, _, e⟩) | ⟨_, e⟩
        all_goals first
          | (subst e; simp at hc)
          | exact hb
          | skip
        split at h
        · rw [mem_when] at h; obtain ⟨_, e⟩ := h; subst e; simp at hc
        · simp at h
    · intro hb
      refine ⟨⟨.simLockOrphan, "sim", s!"held by {o.system.simLock.holder.getD ""}"⟩, (mem_alerts p o _).2 ?_, rfl⟩
      unfold raw sysAlerts
      simp [List.mem_append, mem_when, hb]
  rw [key]
  unfold orphanB
  cases o.system.simLock.holder with
  | none => simp
  | some h => simp [live]

/-! ## Monotonicity -/

/-- `q` is looser than `p`: every upper threshold of `q` is at least `p`'s and the disk floor of `q` is at most `p`'s.

$$p \sqsubseteq q \iff \mathit{idle}_p \le \mathit{idle}_q \wedge \mathit{stall}_p \le \mathit{stall}_q \wedge \mathit{hang}_p \le \mathit{hang}_q \wedge \mathit{err}_p \le \mathit{err}_q \wedge \mathit{ctxMax}_p \le \mathit{ctxMax}_q \wedge \mathit{ctxWarn}_p \le \mathit{ctxWarn}_q \wedge \mathit{diskMin}_q \le \mathit{diskMin}_p \wedge \mathit{cap}_p \le \mathit{cap}_q \wedge \mathit{simMax}_p \le \mathit{simMax}_q \wedge \mathit{wtMax}_p \le \mathit{wtMax}_q$$
-/
def Looser (p q : Params) : Prop :=
  p.idleMin ≤ q.idleMin ∧ p.stallMin ≤ q.stallMin ∧ p.toolHangMin ≤ q.toolHangMin ∧ p.errStreak ≤ q.errStreak ∧
  p.ctxResumeMax ≤ q.ctxResumeMax ∧ p.ctxWarn ≤ q.ctxWarn ∧ q.diskMinGB ≤ p.diskMinGB ∧ p.agentCap ≤ q.agentCap ∧
  p.simLockMaxMin ≤ q.simLockMaxMin ∧ p.worktreesMax ≤ q.worktreesMax

/-- Stalling under looser thresholds implies stalling under tighter ones.

$$\forall p, q, t, a:\quad p \sqsubseteq q \wedge \operatorname{state}(q, t, a) = \mathrm{stalled} \Rightarrow \operatorname{state}(p, t, a) = \mathrm{stalled}$$
-/
theorem stalled_mono (p q : Params) (t : Nat) (a : Agent) (hpq : Looser p q)
    (h : state q t a = .stalled) : state p t a = .stalled := by
  obtain ⟨_, hst, hh, _⟩ := hpq
  rw [state_stalled] at *
  obtain ⟨h1, h2, h3, h4⟩ := h
  refine ⟨h1, h2, ?_, fun f hf => ?_⟩
  · exact Nat.le_trans (Nat.mul_le_mul_right _ hst) h3
  · exact Nat.le_trans (Nat.mul_le_mul_right _ hh) (h4 f hf)

/-- An agent alert under looser thresholds is also raised under tighter ones.

$$\forall p, q, t, a, x:\quad p \sqsubseteq q \wedge x \in \operatorname{agentAlerts}(q, t, a) \Rightarrow x \in \operatorname{agentAlerts}(p, t, a)$$
-/
theorem agentAlerts_mono (p q : Params) (t : Nat) (a : Agent) (hpq : Looser p q) (x : Alert)
    (h : x ∈ agentAlerts q t a) : x ∈ agentAlerts p t a := by
  have hw : (state q t a == .waiting) = (state p t a == .waiting) := by
    rw [Bool.eq_iff_iff, beq_iff_eq, beq_iff_eq, state_waiting, state_waiting]
  have hs : (state q t a == .stalled) = true → (state p t a == .stalled) = true := by
    intro e; simp only [beq_iff_eq] at *; exact stalled_mono p q t a hpq e
  obtain ⟨_, _, hh, he, hc, hwn, _⟩ := hpq
  have hd : a.stoppedAt.isSome = false := by
    cases hs : a.stoppedAt.isSome
    · rfl
    · unfold agentAlerts at h; simp [hs] at h
  unfold agentAlerts at h ⊢
  · simp only [hd, Bool.false_eq_true, ↓reduceIte, List.mem_append, mem_when, hw] at h ⊢
    rcases h with ((((⟨b, e⟩ | ⟨b, e⟩) | ⟨b, e⟩) | ⟨b, e⟩) | ⟨b, e⟩) | ⟨b, e⟩
    · exact .inl (.inl (.inl (.inl (.inl ⟨by simp at b ⊢; omega, e⟩))))
    · exact .inl (.inl (.inl (.inl (.inr ⟨by simp at b ⊢; omega, e⟩))))
    · exact .inl (.inl (.inl (.inr ⟨by simp at b ⊢; omega, e⟩)))
    · exact .inl (.inl (.inr ⟨b, e⟩))
    · exact .inl (.inr ⟨hs b, e⟩)
    · refine .inr ⟨?_, e⟩
      unfold hangB at b ⊢
      cases hf : a.inflight with
      | none => simp [hf] at b
      | some f =>
        simp only [hf, Bool.and_eq_true, decide_eq_true_eq] at b ⊢
        exact ⟨b.1, Nat.le_trans (Nat.mul_le_mul_right _ hh) b.2⟩

/-- A team or system alert under looser thresholds is also raised under tighter ones.

$$\forall p, q, o, x:\quad p \sqsubseteq q \wedge x \in \operatorname{sysAlerts}(q, o) \Rightarrow x \in \operatorname{sysAlerts}(p, o)$$
-/
theorem sysAlerts_mono (p q : Params) (o : Obs) (hpq : Looser p q) (x : Alert) (h : x ∈ sysAlerts q o) :
    x ∈ sysAlerts p o := by
  obtain ⟨_, _, _, _, _, _, hd, hcap, hsim, hwt⟩ := hpq
  unfold sysAlerts at *
  simp only [List.mem_append, mem_when] at h ⊢
  rcases h with ((((((⟨b, e⟩ | ⟨b, e⟩) | ⟨b, e⟩) | h) | ⟨b, e⟩) | h) | h) | ⟨b, e⟩
  · exact .inl (.inl (.inl (.inl (.inl (.inl (.inl ⟨by simp at b ⊢; omega, e⟩))))))
  · exact .inl (.inl (.inl (.inl (.inl (.inl (.inr ⟨by simp at b ⊢; omega, e⟩))))))
  · exact .inl (.inl (.inl (.inl (.inl (.inr ⟨b, e⟩)))))
  · refine .inl (.inl (.inl (.inl (.inr ?_))))
    cases ht : o.system.simLock.since with
    | none => simp [ht] at h
    | some t =>
      simp only [ht, mem_when, Bool.and_eq_true, decide_eq_true_eq] at h ⊢
      exact ⟨⟨h.1.1, Nat.le_trans (Nat.mul_le_mul_right _ hsim) h.1.2⟩, h.2⟩
  · exact .inl (.inl (.inl (.inr ⟨b, e⟩)))
  · exact .inl (.inl (.inr h))
  · exact .inl (.inr h)
  · exact .inr ⟨by simp at b ⊢; omega, e⟩

/-- Loosening the thresholds never adds an alert: every alert of the report under $q$ is in the report under $p$.
(Raising any upper threshold, or lowering `diskMinGB`, is a loosening.)

$$\forall p, q, o, x:\quad p \sqsubseteq q \wedge x \in \operatorname{health}(q, o).\mathit{alerts} \Rightarrow x \in \operatorname{health}(p, o).\mathit{alerts}$$
-/
theorem health_mono (p q : Params) (o : Obs) (hpq : Looser p q) (x : Alert) (h : x ∈ (health q o).alerts) :
    x ∈ (health p o).alerts := by
  rw [mem_alerts] at *
  unfold raw at *
  rcases List.mem_append.1 h with h | h
  · obtain ⟨a, ha, hx⟩ := List.mem_flatMap.1 h
    exact List.mem_append.2 (.inl (List.mem_flatMap.2 ⟨a, ha, agentAlerts_mono p q o.now a hpq x hx⟩))
  · exact List.mem_append.2 (.inr (sysAlerts_mono p q o hpq x h))

/-! ## Agent order does not matter -/

/-- The team and system alerts do not depend on the order of the agents.

$$\forall p, o, l:\quad l \sim A \Rightarrow \operatorname{sysAlerts}(p, o[A := l]) = \operatorname{sysAlerts}(p, o)$$
-/
theorem sysAlerts_perm (p : Params) (o : Obs) (l : List Agent) (hl : l.Perm o.agents) :
    sysAlerts p { o with agents := l } = sysAlerts p o := by
  have hn : nLive l = nLive o.agents := (hl.filter _).length_eq
  have ho : orphanB l o.system.simLock = orphanB o.agents o.system.simLock := by
    unfold orphanB; split <;> simp [hl.any_eq]
  have hd : dockerOrphanB l = dockerOrphanB o.agents := by
    funext c; unfold dockerOrphanB; rw [hl.any_eq]
  unfold sysAlerts
  simp only [hn, ho, hd]

/-- The report's alerts, system codes and counts do not depend on the order of the agents (the rows follow it).

$$\forall p, o, l:\quad l \sim A \Rightarrow \operatorname{health}(p, o[A := l]).(\mathit{alerts}, \mathit{sysCodes}, n) = \operatorname{health}(p, o).(\mathit{alerts}, \mathit{sysCodes}, n)$$
-/
theorem health_perm (p : Params) (o : Obs) (l : List Agent) (hl : l.Perm o.agents) :
    (health p { o with agents := l }).alerts = (health p o).alerts ∧
    (health p { o with agents := l }).system = (health p o).system ∧
    (health p { o with agents := l }).counts = (health p o).counts := by
  have hs := sysAlerts_perm p o l hl
  refine ⟨?_, ?_, ?_⟩
  · apply eq_of_sorted _ _ (alerts_sorted _ _) (alerts_sorted _ _)
    intro z
    rw [mem_alerts, mem_alerts]
    unfold raw
    simp only [List.mem_append, hs]
    rw [(hl.flatMap_right (agentAlerts p o.now)).mem_iff]
  · simp only [health, hs]
  · simp only [health, countState, (hl.filter _).length_eq]

/-- The counts add up to the number of agents.

$$\forall p, o:\quad n_{\mathrm{active}} + n_{\mathrm{idle}} + n_{\mathrm{waiting}} + n_{\mathrm{stalled}} + n_{\mathrm{done}} = |A|$$
-/
theorem counts_total (p : Params) (o : Obs) :
    let c := (health p o).counts
    c.active + c.idle + c.waiting + c.stalled + c.done = o.agents.length := by
  simp only [health, countState]
  induction o.agents with
  | nil => rfl
  | cons a as ih =>
    simp only [List.filter_cons, List.length_cons]
    cases state p o.now a <;> simp <;> omega

/-! ## Examples -/

/-- A sample agent started at 0 with its last event at minute 0 (for the guards).

$$a_0 = (\texttt{a}, \bot, \bot, 1, 0, 0, \bot, 0, \bot, \mathrm{false}, \bot)$$
-/
def a0 : Agent := { id := "a" }

#guard state {} (5 * msPerMin) a0 == .active
#guard state {} (10 * msPerMin - 1) a0 == .active
#guard state {} (10 * msPerMin) a0 == .idle
#guard state {} (20 * msPerMin) a0 == .stalled
#guard state {} (20 * msPerMin) { a0 with inflight := some ⟨"Bash", 0⟩ } == .idle
#guard state {} (30 * msPerMin) { a0 with inflight := some ⟨"Bash", 0⟩ } == .stalled
#guard state {} (99 * msPerMin) { a0 with waitingPermission := true } == .waiting
#guard state {} (99 * msPerMin) { a0 with waitingPermission := true, stoppedAt := some 1 } == .done
#guard state {} 0 { a0 with lastAt := 5 } == .active
#guard agentAlerts {} (99 * msPerMin) { a0 with stoppedAt := some 1, errTail := 9, ctxTokens := some 300000 } == []
#guard (agentAlerts {} 0 { a0 with ctxTokens := some 250001 }).map (·.code) == [.ctxHigh, .ctxWarn]
#guard (agentAlerts {} 0 { a0 with ctxTokens := some 250000 }).map (·.code) == [.ctxWarn]
#guard (agentAlerts {} 0 { a0 with errTail := 3 }).map (·.code) == [.errStreak]
#guard (agentAlerts {} 0 { a0 with errTail := 2 }).map (·.code) == []
#guard (agentAlerts { errStreak := 0 } 0 { a0 with errTail := 0 }).map (·.code) == []
#guard (agentAlerts {} (30 * msPerMin) { a0 with inflight := some ⟨"Bash", 0⟩ }).map (·.code) == [.stalled, .toolHang]
#guard (agentAlerts {} (30 * msPerMin) { a0 with inflight := some ⟨"Bash", 0⟩, waitingPermission := true }).map (·.code) == [.permissionWait]
#guard orphanB [{ a0 with task := some "wktr" }] { holder := some "wktr" } == false
#guard orphanB [{ a0 with task := some "wktr", stoppedAt := some 1 }] { holder := some "wktr" } == true
#guard orphanB [] {} == false
#guard ciLatest [⟨"ci", "main", "completed", some "failure", 1⟩, ⟨"ci", "main", "completed", some "success", 2⟩]
  ⟨"ci", "main", "completed", some "failure", 1⟩ == false
#guard dockerOrphanB [{ a0 with startedAt := 5 }] ⟨"c1", "pg", 4⟩ == true
#guard dockerOrphanB [{ a0 with startedAt := 5 }] ⟨"c1", "pg", 5⟩ == false
#guard ((health {} { now := 0, system := { diskFreeGB := 19, memPressure := .critical } }).alerts.map (·.code))
  == [.diskLow, .memCritical]
#guard (health {} { now := 0, system := { diskFreeGB := 20 } }).alerts == []
#guard sortU [⟨.diskLow, "disk", "1"⟩, ⟨.ctxHigh, "b", "x"⟩, ⟨.ctxHigh, "a", "x"⟩, ⟨.diskLow, "disk", "1"⟩]
  == [⟨.ctxHigh, "a", "x"⟩, ⟨.ctxHigh, "b", "x"⟩, ⟨.diskLow, "disk", "1"⟩]

end Fw.Obs.Health
