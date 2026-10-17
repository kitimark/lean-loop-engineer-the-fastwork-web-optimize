import Fw.Obs.Health
/-!
# Next action per agent: agents that look busy but are idle or held, and what fixes each

`Fw.Obs.Health` derives each agent's state from hook and transcript events. Some agents look busy there while
nothing will happen without the lead: an agent that handed back but whose branch was never landed, an agent whose
own `until grep …; do sleep …` loop can never finish, an agent waiting on a CI run, an active agent close to its
context limit. This module takes, per agent, the Health state plus the facts that tell these cases apart (handback
seen, branch ahead of `main` and landed or not, integrator queue, worktree lock, the agent's child processes with
kind, age and watched-file state, its CI run, the board row of its task) and returns the list of next actions (`next`).

Units as in `Fw.Obs.Health`: times are ms since the epoch, the `…Min` thresholds are minutes
($\mu = 60000$ ms), an age is the truncated difference $t \mathbin{\dot-} s$. The facts are a snapshot: the Health
state is an input here (the reply of `obs.health` for the same snapshot), not recomputed.

A loop child is **own** when its parent chain reaches the session pid and it is neither the session nor one of its
own ancestors, **sole** when no child of another kind shares its pid, and its watch is **dead** when it watches a file
whose producer has exited (the file's last line is the exit marker) or that is unchanged for more than
`fileStaleMin`. Such a loop can never be satisfied.

Rules (a gate on the Health state, then independent pieces in a fixed order; `none` exactly when no piece fires):
* Every agent, first: `claimTask` when it is live (not done, not gone) and its name is the id of a board task that is
  not done and has no agent (the spawn-time claim ran before the task reached the board and is never retried).
* An **active** agent gets only: `killOrphan` for an own, sole sleep loop with a dead watch (killing only wakes the
  owner's waiting call), `waitCi` (its CI run is running), and `nudgeHandoff` (context above `ctxWarn`, or paired with
  every such kill so the owner learns why its call returned).
* Otherwise: `killOrphan` for each own, sole sleep loop whose owner handed back, or whose watch is dead, or which runs
  for more than `loopCapMin`; `waitCi`; `land` or `routeIntegrator` (handed back, no live child, branch ahead and not
  landed; routed when the branch is on the integrator's list); `cleanupWorktree` (worktree present, branch landed, no
  live child, handed back or ended); `respawnFromHandoff` (no handback, stalled or gone, no live child);
  `nudgeHandoff`; `investigate` with a reason (held by a child that gets no kill, a CI wait past its own timeout, a
  sleep loop outside the session's tree, a dead worktree-lock pid of a live agent).

Proved: `next_total`, `next_det`, `kill_sound`, `kill_only_loops`, `active_quiet`, `active_kill_nudge`, `land_sound`,
`route_sound`, `cleanup_sound`, `respawn_sound`, `claim_sound`, `live_land`, `live_kill`, `live_kill_active`,
`live_claim`, `kill_mono`. Wire op:
`obs.next` (`Fw.Wire.Obs`).
-/
namespace Fw.Obs.Next
open Fw.Obs.Health (State CiRun ciRunning msPerMin)

/-- The thresholds: the Health thresholds (`ctxWarn` is used here), the loop cap and the file-stale time.
`loopCapMin` = 30: no poll loop of this repo may wait open-ended (CI waits go through `waitrun.sh`, a `ciWait`, with
their own timeout), and 30 min is above `ciSlowMin` (20), the longest wait the lead treats as normal.
`fileStaleMin` = 10: builds, tests and CI logs write at least every few minutes, so a watched file unchanged for
10 min will not bring the awaited text.

$$p = (h, \mathit{loopCap}, \mathit{fileStale}) \in \mathrm{Health.Params} \times \mathbb N^2,\quad \text{defaults } (h_0, 30, 10)$$
-/
structure Params where
  health       : Fw.Obs.Health.Params := {}
  loopCapMin   : Nat := 30
  fileStaleMin : Nat := 10
deriving DecidableEq, Repr

/-- What a child process of the agent's session does: a shell poll loop (`until …; do sleep …; done`), a CI wait
(`waitrun.sh <run>` with its timeout in minutes), a build or test run, or anything else.

$$\mathcal K = \{\mathrm{sleepLoop}\} \cup \{\mathrm{ciWait}(r, m) : r, m \in \mathbb N\} \cup \{\mathrm{build}, \mathrm{other}\}$$
-/
inductive ChildKind where
  | sleepLoop
  | ciWait (run : Nat) (timeoutMin : Nat)
  | build
  | other
deriving DecidableEq, Repr

/-- A live child process started by the agent: its pid, its parent chain (the ppid, then the ppid's ppid, … up to
pid 1), its kind, its start time (ms), the modification time (ms) of the file it watches (`none`: it watches none),
and whether that file's producer has exited (its last line is the exit marker `[exited with code N]`).

$$c = (\mathit{pid}, P, k, s, w_\bot, \mathit{exit}) \in \mathbb N \times \mathbb N^* \times \mathcal K \times \mathbb N \times \mathbb N_\bot \times \mathbb B$$
-/
structure Child where
  pid            : Nat
  chain          : List Nat := []
  kind           : ChildKind
  startedAt      : Nat
  watchedAt      : Option Nat := none
  producerExited : Bool := false
deriving DecidableEq, Repr

/-- The agent's branch: name, commits ahead of `main` (`git rev-list --count main..branch`), whether its tip is an
ancestor of `main` (landed), and whether it is on the integrator's list (queued).

$$b = (\mathit{name}, \mathit{ahead}, \mathit{landed}, \mathit{queued}) \in \mathrm{String} \times \mathbb N \times \mathbb B^2$$
-/
structure Branch where
  name   : String
  ahead  : Nat
  landed : Bool
  queued : Bool
deriving DecidableEq, Repr

/-- The agent's worktree: the pid in its lock (`none`: not locked) and whether that pid is alive.

$$w = (\mathit{lockPid}_\bot, \mathit{alive}) \in \mathbb N_\bot \times \mathbb B$$
-/
structure Worktree where
  lockPid   : Option Nat := none
  lockAlive : Bool := false
deriving DecidableEq, Repr

/-- The latest CI run of the agent's `ci/*` branch: its run id and the run (status, conclusion, times).

$$r = (\mathit{id}, \rho) \in \mathbb N \times \mathrm{CiRun}$$
-/
structure Ci where
  id  : Nat
  run : CiRun
deriving DecidableEq, Repr

/-- The board row of the task whose id is the agent's name: task id, whether the task is done, and the agent bound to
it (`none`: unbound).

$$\tau = (\mathit{id}, \mathit{done}, a_\bot) \in \mathrm{String} \times \mathbb B \times \mathrm{String}_\bot$$
-/
structure TaskRow where
  id    : String
  done  : Bool
  agent : Option String := none
deriving DecidableEq, Repr

/-- The facts of one agent: id, task id, Health state, time of its handback (`none`: not seen), the session pid its
processes descend from, its branch, worktree and context tokens (0 when unknown), its live child processes, the
latest CI run of its `ci/*` branch, and the board row of the task named like the agent (`none`: no such task).

$$f = (\mathit{id}, \mathit{task}, s, h_\bot, \sigma, b_\bot, w_\bot, \mathit{ctx}, C, r_\bot, \tau_\bot)$$
-/
structure AgentFacts where
  id         : String
  task       : String
  state      : State
  handbackAt : Option Nat := none
  session    : Nat
  branch     : Option Branch := none
  worktree   : Option Worktree := none
  ctxTokens  : Nat := 0
  children   : List Child := []
  ci         : Option Ci := none
  board      : Option TaskRow := none
deriving DecidableEq, Repr

/-- Why an agent needs a look by the lead: held by a child that gets no kill, a CI wait past its own timeout, a sleep
loop outside the session's process tree (never killed here), or a dead lock pid on the worktree of an agent that has
not ended and has not handed back.

$$\mathcal R = \{\mathrm{heldByChild}, \mathrm{ciWaitOverdue}, \mathrm{foreignLoop}, \mathrm{lockDead}\}$$
-/
inductive Reason where
  | heldByChild | ciWaitOverdue | foreignLoop | lockDead
deriving DecidableEq, Repr

/-- The next actions: nothing, wait for a CI run, land a branch for a task, route a branch to the integrator, kill an
orphan process, remove the worktree, stop and respawn from the handoff note, ask the agent to write its handoff, or
look at it (with a reason), or bind a task to the agent on the board.

$$\mathcal A = \{\mathrm{none}, \mathrm{cleanupWorktree}, \mathrm{respawnFromHandoff}, \mathrm{nudgeHandoff}\} \cup \{\mathrm{waitCi}(r), \mathrm{killOrphan}(q) : r, q \in \mathbb N\} \cup \{\mathrm{land}(b, k), \mathrm{routeIntegrator}(b), \mathrm{claimTask}(k, a) : b, k, a \in \mathrm{String}\} \cup \{\mathrm{investigate}(\rho) : \rho \in \mathcal R\}$$
-/
inductive Action where
  | none
  | waitCi (run : Nat)
  | land (branch task : String)
  | routeIntegrator (branch : String)
  | killOrphan (pid : Nat)
  | cleanupWorktree
  | respawnFromHandoff
  | nudgeHandoff
  | investigate (reason : Reason)
  | claimTask (task agent : String)
deriving DecidableEq, Repr

/-! ## Tests -/

/-- Whether the agent has handed back.

$$\operatorname{hb}(f) \iff h_\bot(f) \ne \bot$$
-/
def handedBack (f : AgentFacts) : Bool := f.handbackAt.isSome

/-- Whether a Health state is an ended one (done or gone).

$$\operatorname{ended}(s) \iff s \in \{\mathrm{done}, \mathrm{gone}\}$$
-/
def endedS (s : State) : Bool := s == .done || s == .gone

/-- Whether the branch is landed (no branch: not landed).

$$\operatorname{landed}(f) \iff \exists b.\ b_\bot(f) = b \wedge \mathit{landed}(b)$$
-/
def landedB (f : AgentFacts) : Bool :=
  match f.branch with
  | some b => b.landed
  | none => false

/-- Whether a child's watched file is stale: unchanged for strictly more than `fileStaleMin` (no watched file: no).

$$\operatorname{stale}(p, t, c) \iff \exists m.\ w_\bot(c) = m \wedge \mu\,\mathit{fileStale} < t \mathbin{\dot-} m$$
-/
def staleB (p : Params) (now : Nat) (c : Child) : Bool :=
  match c.watchedAt with
  | some m => decide (p.fileStaleMin * msPerMin < now - m)
  | none => false

/-- Whether a child watches a file whose producer has exited.

$$\operatorname{exited}(c) \iff w_\bot(c) \ne \bot \wedge \mathit{exit}(c)$$
-/
def exitedB (c : Child) : Bool := c.watchedAt.isSome && c.producerExited

/-- Whether a child's watch is dead: its file's producer has exited or the file is stale.

$$\operatorname{dead}(p, t, c) \iff \operatorname{exited}(c) \vee \operatorname{stale}(p, t, c)$$
-/
def deadB (p : Params) (now : Nat) (c : Child) : Bool := exitedB c || staleB p now c

/-- Whether a child runs for strictly more than the loop cap.

$$\operatorname{old}(p, t, c) \iff \mu\,\mathit{loopCap} < t \mathbin{\dot-} s(c)$$
-/
def oldB (p : Params) (now : Nat) (c : Child) : Bool := decide (p.loopCapMin * msPerMin < now - c.startedAt)

/-- Whether a child's pid is unambiguous: every child of the agent with the same pid is a sleep loop.

$$\operatorname{sole}(f, c) \iff \forall d \in C(f).\ \mathit{pid}(d) = \mathit{pid}(c) \Rightarrow k(d) = \mathrm{sleepLoop}$$
-/
def soleB (f : AgentFacts) (c : Child) : Bool := f.children.all fun d => d.pid != c.pid || d.kind == .sleepLoop

/-- Whether a child is in the session's tree but is neither the session nor one of its own ancestors.

$$\operatorname{own}(f, c) \iff \sigma(f) \in P(c) \wedge \mathit{pid}(c) \ne \sigma(f) \wedge \mathit{pid}(c) \notin P(c)$$
-/
def ownB (f : AgentFacts) (c : Child) : Bool :=
  c.chain.contains f.session && c.pid != f.session && !c.chain.contains c.pid

/-- An orphan loop: an own, sole sleep-loop child whose owner has handed back, or whose watch is dead, or which runs
past the loop cap.

$$\operatorname{orphan}(p, t, f, c) \iff k(c) = \mathrm{sleepLoop} \wedge \operatorname{own}(f, c) \wedge \operatorname{sole}(f, c) \wedge (\operatorname{hb}(f) \vee \operatorname{dead}(p, t, c) \vee \operatorname{old}(p, t, c))$$
-/
def orphanB (p : Params) (now : Nat) (f : AgentFacts) (c : Child) : Bool :=
  c.kind == .sleepLoop && ownB f c && soleB f c && (handedBack f || deadB p now c || oldB p now c)

/-- Whether a child gets `killOrphan`: an orphan loop, and when the agent is active its watch must be dead.

$$\operatorname{kill}(p, t, f, c) \iff \operatorname{orphan}(p, t, f, c) \wedge (s(f) \ne \mathrm{active} \vee \operatorname{dead}(p, t, c))$$
-/
def killB (p : Params) (now : Nat) (f : AgentFacts) (c : Child) : Bool :=
  orphanB p now f c && (f.state != .active || deadB p now c)

/-- Whether a child is a CI wait past its own timeout (strictly more than its timeout minutes).

$$\operatorname{overdue}(t, c) \iff \exists r, m.\ k(c) = \mathrm{ciWait}(r, m) \wedge \mu\,m < t \mathbin{\dot-} s(c)$$
-/
def overdueB (now : Nat) (c : Child) : Bool :=
  match c.kind with
  | .ciWait _ m => decide (m * msPerMin < now - c.startedAt)
  | _ => false

/-- A sleep loop outside the session's tree (its chain does not reach the session pid).

$$\operatorname{foreign}(f, c) \iff k(c) = \mathrm{sleepLoop} \wedge \sigma(f) \notin P(c)$$
-/
def foreignB (f : AgentFacts) (c : Child) : Bool := c.kind == .sleepLoop && !c.chain.contains f.session

/-- Stuck: no handback, and stalled or gone.

$$\operatorname{stuck}(f) \iff \neg\operatorname{hb}(f) \wedge s(f) \in \{\mathrm{stalled}, \mathrm{gone}\}$$
-/
def stuckB (f : AgentFacts) : Bool := !handedBack f && (f.state == .stalled || f.state == .gone)

/-- Whether to ask for the handoff note: no handback, active, idle or parked, and context strictly above `ctxWarn`.

$$\operatorname{nudge}(p, f) \iff \neg\operatorname{hb}(f) \wedge s(f) \in \{\mathrm{active}, \mathrm{idle}, \mathrm{parked}\} \wedge \mathit{ctxWarn}(h(p)) < \mathit{ctx}(f)$$
-/
def nudgeB (p : Params) (f : AgentFacts) : Bool :=
  !handedBack f && (f.state == .active || f.state == .idle || f.state == .parked) &&
    decide (p.health.ctxWarn < f.ctxTokens)

/-- A worktree lock whose pid is dead, on an agent that has not handed back and has not ended.

$$\operatorname{lockDead}(f) \iff \neg\operatorname{hb}(f) \wedge \neg\operatorname{ended}(s(f)) \wedge \exists w, q.\ w_\bot(f) = w \wedge \mathit{lockPid}_\bot(w) = q \wedge \neg\mathit{alive}(w)$$
-/
def lockDeadB (f : AgentFacts) : Bool :=
  !handedBack f && !endedS f.state &&
    match f.worktree with
    | some w => w.lockPid.isSome && !w.lockAlive
    | none => false

/-! ## The pieces and the decision -/

/-- A one-element list when the test holds, else empty.

$$\operatorname{opt}(b, x) = \begin{cases} [x] & b \\ [\,] & \neg b \end{cases}$$
-/
def opt (b : Bool) (x : Action) : List Action := if b then [x] else []

/-- One `killOrphan` per child that gets a kill, in child order.

$$\operatorname{kills}(p, t, f) = [\mathrm{killOrphan}(\mathit{pid}(c)) : c \in C(f),\ \operatorname{kill}(p, t, f, c)]$$
-/
def kills (p : Params) (now : Nat) (f : AgentFacts) : List Action :=
  (f.children.filter (killB p now f)).map fun c => .killOrphan c.pid

/-- `waitCi` for the agent's CI run while it is running.

$$\operatorname{waits}(f) = \begin{cases} [\mathrm{waitCi}(\mathit{id}(r))] & r_\bot(f) = r \wedge \operatorname{running}(\rho(r)) \\ [\,] & \text{otherwise} \end{cases}$$
-/
def waits (f : AgentFacts) : List Action :=
  match f.ci with
  | some c => opt (ciRunning c.run) (.waitCi c.id)
  | none => []

/-- Land or route a handed-back agent's unlanded branch when it has no live child: to the integrator when queued,
else `land` with the agent's task.

$$\operatorname{lands}(f) = \begin{cases} [\mathrm{routeIntegrator}(\mathit{name}(b))] & \operatorname{hb}(f) \wedge C(f) = [\,] \wedge b_\bot(f) = b \wedge 0 < \mathit{ahead}(b) \wedge \neg\mathit{landed}(b) \wedge \mathit{queued}(b) \\ [\mathrm{land}(\mathit{name}(b), \mathit{task}(f))] & \text{same but } \neg\mathit{queued}(b) \\ [\,] & \text{otherwise} \end{cases}$$
-/
def lands (f : AgentFacts) : List Action :=
  if handedBack f && f.children.isEmpty then
    match f.branch with
    | some b => opt (decide (0 < b.ahead) && !b.landed) (if b.queued then .routeIntegrator b.name else .land b.name f.task)
    | none => []
  else []

/-- Clean up the worktree: present, branch landed, no live child, and handed back or ended.

$$\operatorname{cleans}(f) = \operatorname{opt}\bigl(w_\bot(f) \ne \bot \wedge \operatorname{landed}(f) \wedge C(f) = [\,] \wedge (\operatorname{hb}(f) \vee \operatorname{ended}(s(f))),\ \mathrm{cleanupWorktree}\bigr)$$
-/
def cleans (f : AgentFacts) : List Action :=
  opt (f.worktree.isSome && landedB f && f.children.isEmpty && (handedBack f || endedS f.state)) .cleanupWorktree

/-- The `investigate` actions, in reason order: held by a child that gets no kill (stuck, or handed back), an overdue
CI wait, a foreign sleep loop, a dead lock pid.

$$\operatorname{probes}(p, t, f) = \operatorname{opt}\bigl((\operatorname{stuck}(f) \vee \operatorname{hb}(f)) \wedge \exists c \in C(f).\ \neg\operatorname{kill}(p, t, f, c),\ \mathrm{inv}(\mathrm{heldByChild})\bigr) \mathbin{+\!\!+} \operatorname{opt}\bigl(\exists c \in C(f).\ \operatorname{overdue}(t, c),\ \mathrm{inv}(\mathrm{ciWaitOverdue})\bigr) \mathbin{+\!\!+} \operatorname{opt}\bigl(\exists c \in C(f).\ \operatorname{foreign}(f, c),\ \mathrm{inv}(\mathrm{foreignLoop})\bigr) \mathbin{+\!\!+} \operatorname{opt}\bigl(\operatorname{lockDead}(f),\ \mathrm{inv}(\mathrm{lockDead})\bigr)$$
-/
def probes (p : Params) (now : Nat) (f : AgentFacts) : List Action :=
  opt ((stuckB f || handedBack f) && f.children.any (fun c => !killB p now f c)) (.investigate .heldByChild) ++
  opt (f.children.any (overdueB now)) (.investigate .ciWaitOverdue) ++
  opt (f.children.any (foreignB f)) (.investigate .foreignLoop) ++
  opt (lockDeadB f) (.investigate .lockDead)

/-- `[none]` for an empty list, else the list.

$$\operatorname{orNone}(\ell) = \begin{cases} [\mathrm{none}] & \ell = [\,] \\ \ell & \text{otherwise} \end{cases}$$
-/
def orNone (l : List Action) : List Action := if l.isEmpty then [.none] else l

/-- Claim the agent's task on the board: a live agent (not done, not gone) whose name is the id of a board task that
is not done and has no agent gets `claimTask` of that task for itself.

$$\operatorname{claims}(f) = \begin{cases} [\mathrm{claimTask}(\mathit{id}(\tau), \mathit{id}(f))] & \neg\operatorname{ended}(s(f)) \wedge \tau_\bot(f) = \tau \wedge \mathit{id}(\tau) = \mathit{id}(f) \wedge \neg\mathit{done}(\tau) \wedge a_\bot(\tau) = \bot \\ [\,] & \text{otherwise} \end{cases}$$
-/
def claims (f : AgentFacts) : List Action :=
  match f.board with
  | some r => opt (!endedS f.state && r.id == f.id && !r.done && r.agent.isNone) (.claimTask r.id f.id)
  | none => []

/-- The next actions of one agent: claims first; then for an active agent kills (dead watches only), waits and a
nudge (high context or any kill); otherwise kills, waits, land or route, cleanup, respawn, nudge and probes, in this
order; `[none]` when nothing fires.

$$\operatorname{next}(p, t, f) = \begin{cases} \operatorname{orNone}\bigl(\operatorname{claims}(f) \mathbin{+\!\!+} \operatorname{kills}(p, t, f) \mathbin{+\!\!+} \operatorname{waits}(f) \mathbin{+\!\!+} \operatorname{opt}(\operatorname{nudge}(p, f) \vee \operatorname{kills}(p, t, f) \ne [\,], \mathrm{nudgeHandoff})\bigr) & s(f) = \mathrm{active} \\ \operatorname{orNone}\bigl(\operatorname{claims}(f) \mathbin{+\!\!+} \operatorname{kills}(p, t, f) \mathbin{+\!\!+} \operatorname{waits}(f) \mathbin{+\!\!+} \operatorname{lands}(f) \mathbin{+\!\!+} \operatorname{cleans}(f) \mathbin{+\!\!+} \operatorname{opt}(\operatorname{stuck}(f) \wedge C(f) = [\,], \mathrm{respawnFromHandoff}) \mathbin{+\!\!+} \operatorname{opt}(\operatorname{nudge}(p, f), \mathrm{nudgeHandoff}) \mathbin{+\!\!+} \operatorname{probes}(p, t, f)\bigr) & \text{otherwise} \end{cases}$$
-/
def next (p : Params) (now : Nat) (f : AgentFacts) : List Action :=
  if f.state == .active then
    orNone (claims f ++ kills p now f ++ waits f ++ opt (nudgeB p f || !(kills p now f).isEmpty) .nudgeHandoff)
  else orNone (claims f ++ kills p now f ++ waits f ++ lands f ++ cleans f ++
    opt (stuckB f && f.children.isEmpty) .respawnFromHandoff ++ opt (nudgeB p f) .nudgeHandoff ++ probes p now f)

/-! ## Proofs -/

/-- Membership in `opt`.

$$\forall b, x, y:\quad y \in \operatorname{opt}(b, x) \iff b \wedge y = x$$
-/
theorem mem_opt (b : Bool) (x y : Action) : y ∈ opt b x ↔ b = true ∧ y = x := by
  unfold opt; cases b <;> simp

/-- An action other than `none` is in `orNone ℓ` exactly when it is in `ℓ`.

$$\forall \ell, x:\quad x \ne \mathrm{none} \Rightarrow (x \in \operatorname{orNone}(\ell) \iff x \in \ell)$$
-/
theorem mem_orNone (l : List Action) (x : Action) (hx : x ≠ .none) : x ∈ orNone l ↔ x ∈ l := by
  unfold orNone
  cases l with
  | nil => simp [hx]
  | cons _ _ => simp

/-- Membership in `kills`: a kill of the pid of a child that gets a kill.

$$\forall p, t, f, x:\quad x \in \operatorname{kills}(p, t, f) \iff \exists c \in C(f).\ \operatorname{kill}(p, t, f, c) \wedge x = \mathrm{killOrphan}(\mathit{pid}(c))$$
-/
theorem mem_kills (p : Params) (t : Nat) (f : AgentFacts) (x : Action) :
    x ∈ kills p t f ↔ ∃ c ∈ f.children, killB p t f c = true ∧ x = .killOrphan c.pid := by
  unfold kills
  simp only [List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨c, ⟨hc, hk⟩, rfl⟩; exact ⟨c, hc, hk, rfl⟩
  · rintro ⟨c, hc, hk, rfl⟩; exact ⟨c, ⟨hc, hk⟩, rfl⟩

/-- `waits` holds only the `waitCi` of a running CI run of the agent.

$$\forall f, x:\quad x \in \operatorname{waits}(f) \Rightarrow \exists r.\ r_\bot(f) = r \wedge \operatorname{running}(\rho(r)) \wedge x = \mathrm{waitCi}(\mathit{id}(r))$$
-/
theorem waits_kind (f : AgentFacts) (x : Action) (h : x ∈ waits f) :
    ∃ c, f.ci = some c ∧ ciRunning c.run = true ∧ x = .waitCi c.id := by
  unfold waits at h
  split at h
  · rename_i c hc; rw [mem_opt] at h; exact ⟨c, hc, h.1, h.2⟩
  · simp at h

/-- `lands` holds only `routeIntegrator` or `land` actions.

$$\forall f, x:\quad x \in \operatorname{lands}(f) \Rightarrow (\exists b.\ x = \mathrm{routeIntegrator}(b)) \vee (\exists b, k.\ x = \mathrm{land}(b, k))$$
-/
theorem lands_kind (f : AgentFacts) (x : Action) (h : x ∈ lands f) :
    (∃ b, x = .routeIntegrator b) ∨ ∃ b k, x = .land b k := by
  unfold lands at h
  split at h
  · split at h
    · rw [mem_opt] at h
      obtain ⟨_, rfl⟩ := h
      split
      · exact .inl ⟨_, rfl⟩
      · exact .inr ⟨_, _, rfl⟩
    · simp at h
  · simp at h

/-- `probes` holds only `investigate` actions.

$$\forall p, t, f, x:\quad x \in \operatorname{probes}(p, t, f) \Rightarrow \exists \rho.\ x = \mathrm{investigate}(\rho)$$
-/
theorem probes_kind (p : Params) (t : Nat) (f : AgentFacts) (x : Action) (h : x ∈ probes p t f) :
    ∃ r, x = .investigate r := by
  simp only [probes, List.mem_append, mem_opt] at h
  rcases h with ((⟨_, rfl⟩ | ⟨_, rfl⟩) | ⟨_, rfl⟩) | ⟨_, rfl⟩ <;> exact ⟨_, rfl⟩

/-- `claims` holds only `claimTask` actions.

$$\forall f, x:\quad x \in \operatorname{claims}(f) \Rightarrow \exists k, a.\ x = \mathrm{claimTask}(k, a)$$
-/
theorem claims_kind (f : AgentFacts) (x : Action) (h : x ∈ claims f) : ∃ k a, x = .claimTask k a := by
  unfold claims at h
  split at h
  · rw [mem_opt] at h; exact ⟨_, _, h.2⟩
  · simp at h

/-- A `claimTask` in `next` comes only from `claims`.

$$\forall p, t, f, k, a:\quad \mathrm{claimTask}(k, a) \in \operatorname{next}(p, t, f) \Rightarrow \mathrm{claimTask}(k, a) \in \operatorname{claims}(f)$$
-/
theorem claim_mem (p : Params) (t : Nat) (f : AgentFacts) (k a : String)
    (h : Action.claimTask k a ∈ next p t f) : Action.claimTask k a ∈ claims f := by
  unfold next at h
  have ho : ∀ b y, (∀ k' a', y ≠ .claimTask k' a') → Action.claimTask k a ∉ opt b y := by
    intro b y hy hm; rw [mem_opt] at hm; exact hy k a hm.2.symm
  have hk : Action.claimTask k a ∉ kills p t f := by
    rw [mem_kills]; rintro ⟨_, _, _, h⟩; cases h
  have hw : Action.claimTask k a ∉ waits f := by
    intro h; obtain ⟨_, _, _, h⟩ := waits_kind f _ h; cases h
  have hl : Action.claimTask k a ∉ lands f := by
    intro h; rcases lands_kind f _ h with ⟨_, h⟩ | ⟨_, _, h⟩ <;> cases h
  have hc : Action.claimTask k a ∉ cleans f := by
    unfold cleans; exact ho _ _ (by simp)
  have hpr : Action.claimTask k a ∉ probes p t f := by
    intro h; obtain ⟨_, h⟩ := probes_kind p t f _ h; cases h
  split at h
  · rw [mem_orNone _ _ (by simp)] at h
    simp only [List.mem_append] at h
    rcases h with ((h | h) | h) | h
    · exact h
    · exact absurd h hk
    · exact absurd h hw
    · exact absurd h (ho _ _ (by simp))
  · rw [mem_orNone _ _ (by simp)] at h
    simp only [List.mem_append] at h
    rcases h with ((((((h | h) | h) | h) | h) | h) | h) | h
    · exact h
    · exact absurd h hk
    · exact absurd h hw
    · exact absurd h hl
    · exact absurd h hc
    · exact absurd h (ho _ _ (by simp))
    · exact absurd h (ho _ _ (by simp))
    · exact absurd h hpr

/-- **Claim safety.** `claimTask` only for a live agent (not done, not gone) whose name is the id of a board task that
is not done and has no agent; the task is that one and the agent is itself.

$$\forall p, t, f, k, a:\quad \mathrm{claimTask}(k, a) \in \operatorname{next}(p, t, f) \Rightarrow s(f) \notin \{\mathrm{done}, \mathrm{gone}\} \wedge a = \mathit{id}(f) \wedge k = \mathit{id}(f) \wedge \exists \tau.\ \tau_\bot(f) = \tau \wedge \mathit{id}(\tau) = k \wedge \neg\mathit{done}(\tau) \wedge a_\bot(\tau) = \bot$$
-/
theorem claim_sound (p : Params) (t : Nat) (f : AgentFacts) (k a : String)
    (h : Action.claimTask k a ∈ next p t f) :
    f.state ≠ .done ∧ f.state ≠ .gone ∧ a = f.id ∧ k = f.id ∧
      ∃ r, f.board = some r ∧ r.id = k ∧ r.done = false ∧ r.agent = none := by
  have h2 := claim_mem p t f k a h
  unfold claims at h2
  split at h2
  · rename_i r hr
    rw [mem_opt] at h2
    obtain ⟨hc, he⟩ := h2
    simp only [Action.claimTask.injEq] at he
    obtain ⟨rfl, rfl⟩ := he
    simp only [endedS, Bool.and_eq_true, Bool.not_eq_true', Bool.or_eq_false_iff, beq_eq_false_iff_ne, ne_eq,
      beq_iff_eq, Option.isNone_iff_eq_none] at hc
    obtain ⟨⟨⟨⟨hd, hg⟩, hid⟩, hdn⟩, hag⟩ := hc
    exact ⟨hd, hg, rfl, hid, r, hr, rfl, hdn, hag⟩
  · simp at h2

/-- **Liveness: claim.** A live agent (not done, not gone) whose name is the id of a board task that is not done and
has no agent gets `claimTask` of that task for itself.

$$\forall p, t, f, \tau:\quad s(f) \notin \{\mathrm{done}, \mathrm{gone}\} \wedge \tau_\bot(f) = \tau \wedge \mathit{id}(\tau) = \mathit{id}(f) \wedge \neg\mathit{done}(\tau) \wedge a_\bot(\tau) = \bot \Rightarrow \mathrm{claimTask}(\mathit{id}(f), \mathit{id}(f)) \in \operatorname{next}(p, t, f)$$
-/
theorem live_claim (p : Params) (t : Nat) (f : AgentFacts) (τ : TaskRow) (hd : f.state ≠ .done)
    (hg : f.state ≠ .gone) (hr : f.board = some τ) (hid : τ.id = f.id) (hdn : τ.done = false)
    (hag : τ.agent = none) : Action.claimTask f.id f.id ∈ next p t f := by
  have hc : Action.claimTask f.id f.id ∈ claims f := by
    unfold claims
    rw [hr, mem_opt]
    refine ⟨?_, by rw [hid]⟩
    simp [endedS, hd, hg, hid, hdn, hag]
  unfold next
  split
  · rw [mem_orNone _ _ (by simp)]; simp [hc]
  · rw [mem_orNone _ _ (by simp)]; simp [hc]

/-- Membership in `next` for an action other than `none`: in the claims or kills, or in the pieces the active gate
allows.

$$\forall p, t, f, x:\quad x \ne \mathrm{none} \Rightarrow \Bigl(x \in \operatorname{next}(p, t, f) \iff x \in \operatorname{claims}(f) \vee x \in \operatorname{kills}(p,t,f) \vee \begin{cases} x \in \operatorname{waits}(f) \vee x \in \operatorname{opt}(\operatorname{nudge}(p, f) \vee \operatorname{kills}(p,t,f) \ne [\,], \mathrm{nudgeHandoff}) & s(f) = \mathrm{active} \\ x \in \operatorname{waits}(f) \vee x \in \operatorname{lands}(f) \vee x \in \operatorname{cleans}(f) \vee x \in \operatorname{opt}(\operatorname{stuck}(f) \wedge C(f) = [\,], \mathrm{respawnFromHandoff}) \vee x \in \operatorname{opt}(\operatorname{nudge}(p, f), \mathrm{nudgeHandoff}) \vee x \in \operatorname{probes}(p,t,f) & \text{otherwise}\end{cases}\Bigr)$$
-/
theorem mem_next (p : Params) (t : Nat) (f : AgentFacts) (x : Action) (hx : x ≠ .none) :
    x ∈ next p t f ↔ x ∈ claims f ∨ x ∈ kills p t f ∨
      if f.state = .active then x ∈ waits f ∨ x ∈ opt (nudgeB p f || !(kills p t f).isEmpty) .nudgeHandoff
      else x ∈ waits f ∨ x ∈ lands f ∨ x ∈ cleans f ∨
        x ∈ opt (stuckB f && f.children.isEmpty) .respawnFromHandoff ∨ x ∈ opt (nudgeB p f) .nudgeHandoff ∨
        x ∈ probes p t f := by
  unfold next
  by_cases h : f.state = .active
  · simp [h, mem_orNone _ _ hx]
  · have h' : (f.state == .active) = false := by simp [h]
    simp [h, h', mem_orNone _ _ hx]

/-- **Totality.** For every input the decision gives a non-empty list, and `none` appears only alone.

$$\forall p, t, f:\quad \operatorname{next}(p, t, f) \ne [\,] \wedge \bigl(\mathrm{none} \in \operatorname{next}(p, t, f) \Rightarrow \operatorname{next}(p, t, f) = [\mathrm{none}]\bigr)$$
-/
theorem next_total (p : Params) (t : Nat) (f : AgentFacts) :
    next p t f ≠ [] ∧ (Action.none ∈ next p t f → next p t f = [Action.none]) := by
  have hk : Action.none ∉ kills p t f := by
    rw [mem_kills]; rintro ⟨_, _, _, h⟩; cases h
  have hcl : Action.none ∉ claims f := by
    intro h; obtain ⟨_, _, h⟩ := claims_kind f _ h; cases h
  have hw : Action.none ∉ waits f := by
    intro h; obtain ⟨_, _, _, h⟩ := waits_kind f _ h; cases h
  have hl : Action.none ∉ lands f := by
    intro h; rcases lands_kind f _ h with ⟨_, h⟩ | ⟨_, _, h⟩ <;> cases h
  have hc : Action.none ∉ cleans f := by
    unfold cleans; rw [mem_opt]; rintro ⟨_, h⟩; cases h
  have hpr : Action.none ∉ probes p t f := by
    intro h; obtain ⟨_, h⟩ := probes_kind p t f _ h; cases h
  have ho : ∀ b y, y ≠ Action.none → Action.none ∉ opt b y := by
    intro b y hy h; rw [mem_opt] at h; exact hy h.2.symm
  have key : ∀ l : List Action, Action.none ∉ l → orNone l ≠ [] ∧ (Action.none ∈ orNone l → orNone l = [.none]) := by
    intro l hl
    unfold orNone
    cases l with
    | nil => simp
    | cons y ys => simp only [List.isEmpty_cons]; exact ⟨by simp, fun h => absurd h hl⟩
  unfold next
  split
  · apply key
    simp only [List.mem_append, not_or]
    exact ⟨⟨⟨hcl, hk⟩, hw⟩, ho _ _ (by simp)⟩
  · apply key
    simp only [List.mem_append, not_or]
    exact ⟨⟨⟨⟨⟨⟨⟨hcl, hk⟩, hw⟩, hl⟩, hc⟩, ho _ _ (by simp)⟩, ho _ _ (by simp)⟩, hpr⟩

/-- **Determinism.** The decision is a function of its inputs: two results for the same input are equal.

$$\forall p, t, f, \ell, \ell':\quad \operatorname{next}(p, t, f) = \ell \wedge \operatorname{next}(p, t, f) = \ell' \Rightarrow \ell = \ell'$$
-/
theorem next_det (p : Params) (t : Nat) (f : AgentFacts) (l l' : List Action)
    (h : next p t f = l) (h' : next p t f = l') : l = l' := h ▸ h'

/-- A `killOrphan` in `next` comes only from `kills`.

$$\forall p, t, f, q:\quad \mathrm{killOrphan}(q) \in \operatorname{next}(p, t, f) \iff \mathrm{killOrphan}(q) \in \operatorname{kills}(p, t, f)$$
-/
theorem kill_mem (p : Params) (t : Nat) (f : AgentFacts) (q : Nat) :
    Action.killOrphan q ∈ next p t f ↔ Action.killOrphan q ∈ kills p t f := by
  rw [mem_next p t f _ (by simp)]
  constructor
  · rintro (h | h | h)
    · obtain ⟨_, _, h⟩ := claims_kind f _ h; cases h
    · exact h
    split at h
    · rcases h with h | h
      · obtain ⟨_, _, _, h⟩ := waits_kind f _ h; cases h
      · rw [mem_opt] at h; cases h.2
    · rcases h with h | h | h | h | h | h
      · obtain ⟨_, _, _, h⟩ := waits_kind f _ h; cases h
      · rcases lands_kind f _ h with ⟨_, h⟩ | ⟨_, _, h⟩ <;> cases h
      · unfold cleans at h; rw [mem_opt] at h; cases h.2
      · rw [mem_opt] at h; cases h.2
      · rw [mem_opt] at h; cases h.2
      · obtain ⟨_, h⟩ := probes_kind p t f _ h; cases h
  · exact fun h => .inr (.inl h)

/-- The kill test unfolded: an own, sole sleep loop whose owner handed back, or whose watch is dead, or which runs
past the cap; for an active agent its watch must be dead.

$$\forall p, t, f, c:\quad \operatorname{kill}(p, t, f, c) \iff k(c) = \mathrm{sleepLoop} \wedge \sigma(f) \in P(c) \wedge \mathit{pid}(c) \ne \sigma(f) \wedge \mathit{pid}(c) \notin P(c) \wedge \operatorname{sole}(f, c) \wedge (\operatorname{hb}(f) \vee \operatorname{dead}(p, t, c) \vee \operatorname{old}(p, t, c)) \wedge (s(f) \ne \mathrm{active} \vee \operatorname{dead}(p, t, c))$$
-/
theorem killB_iff (p : Params) (t : Nat) (f : AgentFacts) (c : Child) :
    killB p t f c = true ↔ c.kind = .sleepLoop ∧ f.session ∈ c.chain ∧ c.pid ≠ f.session ∧ c.pid ∉ c.chain ∧
      soleB f c = true ∧ (handedBack f = true ∨ deadB p t c = true ∨ oldB p t c = true) ∧
      (f.state ≠ .active ∨ deadB p t c = true) := by
  simp only [killB, orphanB, ownB, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq, List.contains_iff_mem,
    bne_iff_ne, ne_eq, Bool.not_eq_true', Bool.eq_false_iff]
  constructor
  · rintro ⟨⟨⟨⟨hk, ⟨hs, hne⟩, hnc⟩, hso⟩, hw⟩, ha⟩
    exact ⟨hk, hs, hne, hnc, hso, by simpa [or_assoc] using hw, ha⟩
  · rintro ⟨hk, hs, hne, hnc, hso, hw, ha⟩
    exact ⟨⟨⟨⟨hk, ⟨hs, hne⟩, hnc⟩, hso⟩, by simpa [or_assoc] using hw⟩, ha⟩

/-- The dead-watch test unfolded.

$$\forall p, t, c:\quad \operatorname{dead}(p, t, c) \iff (w_\bot(c) \ne \bot \wedge \mathit{exit}(c)) \vee (\exists m.\ w_\bot(c) = m \wedge \mu\,\mathit{fileStale} < t \mathbin{\dot-} m)$$
-/
theorem deadB_iff (p : Params) (t : Nat) (c : Child) :
    deadB p t c = true ↔ (c.watchedAt ≠ none ∧ c.producerExited = true) ∨
      ∃ m, c.watchedAt = some m ∧ p.fileStaleMin * msPerMin < t - m := by
  unfold deadB exitedB staleB
  cases c.watchedAt <;> simp

/-- **Kill safety.** A killed pid is a sleep-loop child of the agent whose parent chain reaches the session pid, which
is not the session nor its own ancestor; its owner handed back, or its watch is dead (producer exited or file stale),
or it runs past the loop cap; and if the agent is active, its watch is dead.

$$\forall p, t, f, q:\quad \mathrm{killOrphan}(q) \in \operatorname{next}(p, t, f) \Rightarrow \exists c \in C(f).\ \mathit{pid}(c) = q \wedge k(c) = \mathrm{sleepLoop} \wedge \sigma(f) \in P(c) \wedge q \ne \sigma(f) \wedge q \notin P(c) \wedge \Bigl(h_\bot(f) \ne \bot \vee \bigl((w_\bot(c) \ne \bot \wedge \mathit{exit}(c)) \vee (\exists m.\ w_\bot(c) = m \wedge \mu\,\mathit{fileStale} < t \mathbin{\dot-} m)\bigr) \vee \mu\,\mathit{loopCap} < t \mathbin{\dot-} s(c)\Bigr) \wedge \Bigl(s(f) = \mathrm{active} \Rightarrow (w_\bot(c) \ne \bot \wedge \mathit{exit}(c)) \vee (\exists m.\ w_\bot(c) = m \wedge \mu\,\mathit{fileStale} < t \mathbin{\dot-} m)\Bigr)$$
-/
theorem kill_sound (p : Params) (t : Nat) (f : AgentFacts) (q : Nat) (h : Action.killOrphan q ∈ next p t f) :
    ∃ c ∈ f.children, c.pid = q ∧ c.kind = .sleepLoop ∧ f.session ∈ c.chain ∧ q ≠ f.session ∧ q ∉ c.chain ∧
      (f.handbackAt.isSome ∨
        ((c.watchedAt ≠ none ∧ c.producerExited = true) ∨
          ∃ m, c.watchedAt = some m ∧ p.fileStaleMin * msPerMin < t - m) ∨
        p.loopCapMin * msPerMin < t - c.startedAt) ∧
      (f.state = .active →
        (c.watchedAt ≠ none ∧ c.producerExited = true) ∨
          ∃ m, c.watchedAt = some m ∧ p.fileStaleMin * msPerMin < t - m) := by
  obtain ⟨c, hc, hk, he⟩ := (mem_kills p t f _).1 ((kill_mem p t f q).1 h)
  simp only [Action.killOrphan.injEq] at he
  subst he
  obtain ⟨hk, hs, hne, hnc, _, hw, ha⟩ := (killB_iff p t f c).1 hk
  refine ⟨c, hc, rfl, hk, hs, hne, hnc, ?_, ?_⟩
  · rcases hw with hw | hw | hw
    · exact .inl hw
    · exact .inr (.inl ((deadB_iff p t c).1 hw))
    · right; right; simpa [oldB] using hw
  · intro hact
    rcases ha with ha | ha
    · exact absurd hact ha
    · exact (deadB_iff p t c).1 ha

/-- **No kill but loops.** A child of another kind (CI wait, build, other) is never killed: its pid gets no
`killOrphan`.

$$\forall p, t, f, c:\quad c \in C(f) \wedge k(c) \ne \mathrm{sleepLoop} \Rightarrow \mathrm{killOrphan}(\mathit{pid}(c)) \notin \operatorname{next}(p, t, f)$$
-/
theorem kill_only_loops (p : Params) (t : Nat) (f : AgentFacts) (c : Child) (hc : c ∈ f.children)
    (hk : c.kind ≠ .sleepLoop) : Action.killOrphan c.pid ∉ next p t f := by
  intro h
  obtain ⟨d, _, hd, he⟩ := (mem_kills p t f _).1 ((kill_mem p t f c.pid).1 h)
  simp only [Action.killOrphan.injEq] at he
  obtain ⟨_, _, _, _, hso, _⟩ := (killB_iff p t f d).1 hd
  simp only [soleB, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq] at hso
  rcases hso c hc with h1 | h1
  · exact h1 he
  · exact hk h1

/-- **Active gate.** An active agent gets only `none`, `waitCi`, `nudgeHandoff`, `claimTask`, or `killOrphan` of a
sleep-loop child in the session's tree whose watch is dead (its file's producer has exited or the file is stale).

$$\forall p, t, f, x:\quad s(f) = \mathrm{active} \wedge x \in \operatorname{next}(p, t, f) \Rightarrow x = \mathrm{none} \vee (\exists r.\ x = \mathrm{waitCi}(r)) \vee x = \mathrm{nudgeHandoff} \vee (\exists k, a.\ x = \mathrm{claimTask}(k, a)) \vee \exists c \in C(f).\ x = \mathrm{killOrphan}(\mathit{pid}(c)) \wedge k(c) = \mathrm{sleepLoop} \wedge \sigma(f) \in P(c) \wedge \bigl((w_\bot(c) \ne \bot \wedge \mathit{exit}(c)) \vee (\exists m.\ w_\bot(c) = m \wedge \mu\,\mathit{fileStale} < t \mathbin{\dot-} m)\bigr)$$
-/
theorem active_quiet (p : Params) (t : Nat) (f : AgentFacts) (x : Action) (ha : f.state = .active)
    (hx : x ∈ next p t f) :
    x = .none ∨ (∃ r, x = .waitCi r) ∨ x = .nudgeHandoff ∨ (∃ k a, x = .claimTask k a) ∨
      ∃ c ∈ f.children, x = .killOrphan c.pid ∧ c.kind = .sleepLoop ∧ f.session ∈ c.chain ∧
        ((c.watchedAt ≠ none ∧ c.producerExited = true) ∨
          ∃ m, c.watchedAt = some m ∧ p.fileStaleMin * msPerMin < t - m) := by
  by_cases hn : x = .none
  · exact .inl hn
  rw [mem_next p t f x hn, ite_eq_left ha] at hx
  rcases hx with h | h | h | h
  · exact .inr (.inr (.inr (.inl (claims_kind f _ h))))
  · obtain ⟨c, hc, hk, rfl⟩ := (mem_kills p t f _).1 h
    obtain ⟨hk, hs, _, _, _, _, hd⟩ := (killB_iff p t f c).1 hk
    refine .inr (.inr (.inr (.inr ⟨c, hc, rfl, hk, hs, ?_⟩)))
    rcases hd with hd | hd
    · exact absurd ha hd
    · exact (deadB_iff p t c).1 hd
  · obtain ⟨_, _, _, rfl⟩ := waits_kind f _ h
    exact .inr (.inl ⟨_, rfl⟩)
  · exact .inr (.inr (.inl (mem_opt _ _ _ |>.1 h).2))

/-- **Kill and nudge go together for an active agent.** When an active agent gets a `killOrphan`, it also gets
`nudgeHandoff`, so it learns why its waiting call returned.

$$\forall p, t, f, q:\quad s(f) = \mathrm{active} \wedge \mathrm{killOrphan}(q) \in \operatorname{next}(p, t, f) \Rightarrow \mathrm{nudgeHandoff} \in \operatorname{next}(p, t, f)$$
-/
theorem active_kill_nudge (p : Params) (t : Nat) (f : AgentFacts) (q : Nat) (ha : f.state = .active)
    (h : Action.killOrphan q ∈ next p t f) : Action.nudgeHandoff ∈ next p t f := by
  have hk := (kill_mem p t f q).1 h
  rw [mem_next p t f _ (by simp), ite_eq_left ha]
  right; right; right
  rw [mem_opt]
  refine ⟨?_, rfl⟩
  cases hks : kills p t f with
  | nil => rw [hks] at hk; simp at hk
  | cons _ _ => simp

/-- Land and route come only from `lands`, never for an active agent.

$$\forall p, t, f, x:\quad \bigl((\exists b.\ x = \mathrm{routeIntegrator}(b)) \vee (\exists b, k.\ x = \mathrm{land}(b, k))\bigr) \Rightarrow \bigl(x \in \operatorname{next}(p, t, f) \iff s(f) \ne \mathrm{active} \wedge x \in \operatorname{lands}(f)\bigr)$$
-/
theorem lands_mem (p : Params) (t : Nat) (f : AgentFacts) (x : Action)
    (hx : (∃ b, x = .routeIntegrator b) ∨ ∃ b k, x = .land b k) :
    x ∈ next p t f ↔ f.state ≠ .active ∧ x ∈ lands f := by
  have hn : x ≠ .none := by rcases hx with ⟨b, h⟩ | ⟨b, k, h⟩ <;> rw [h] <;> simp
  have hw : x ∉ waits f := by
    intro h; obtain ⟨_, _, _, rfl⟩ := waits_kind f _ h; rcases hx with ⟨_, h⟩ | ⟨_, _, h⟩ <;> cases h
  have ho : ∀ b y, (∀ z, y ≠ .routeIntegrator z) → (∀ z k, y ≠ .land z k) → x ∉ opt b y := by
    intro b y h1 h2 h; rw [mem_opt] at h; obtain ⟨_, rfl⟩ := h
    rcases hx with ⟨_, h⟩ | ⟨_, _, h⟩
    · exact h1 _ h
    · exact h2 _ _ h
  have hk : x ∉ kills p t f := by
    rw [mem_kills]; rintro ⟨_, _, _, rfl⟩; rcases hx with ⟨_, h⟩ | ⟨_, _, h⟩ <;> cases h
  have hc : x ∉ cleans f := by
    unfold cleans; exact ho _ _ (by simp) (by simp)
  have hpr : x ∉ probes p t f := by
    intro h; obtain ⟨_, rfl⟩ := probes_kind p t f _ h; rcases hx with ⟨_, h⟩ | ⟨_, _, h⟩ <;> cases h
  have hcl : x ∉ claims f := by
    intro h; obtain ⟨_, _, rfl⟩ := claims_kind f _ h; rcases hx with ⟨_, h⟩ | ⟨_, _, h⟩ <;> cases h
  rw [mem_next p t f x hn]
  by_cases ha : f.state = .active
  · simp only [ha, ite_true, ne_eq, not_true_eq_false, false_and, iff_false, not_or]
    exact ⟨hcl, hk, hw, ho _ _ (by simp) (by simp)⟩
  · simp only [ha, ite_false, ne_eq, not_false_eq_true, true_and]
    constructor
    · rintro (h | h | h | h | h | h | h | h)
      · exact absurd h hcl
      · exact absurd h hk
      · exact absurd h hw
      · exact h
      · exact absurd h hc
      · exact absurd h (ho _ _ (by simp) (by simp))
      · exact absurd h (ho _ _ (by simp) (by simp))
      · exact absurd h hpr
    · exact fun h => .inr (.inr (.inr (.inl h)))

/-- **Land safety.** `land` only for an agent that handed back, has no live child, and whose branch is ahead of `main`,
not landed and not on the integrator's list; the task is the agent's.

$$\forall p, t, f, b, k:\quad \mathrm{land}(b, k) \in \operatorname{next}(p, t, f) \Rightarrow h_\bot(f) \ne \bot \wedge C(f) = [\,] \wedge k = \mathit{task}(f) \wedge \exists \beta.\ b_\bot(f) = \beta \wedge \mathit{name}(\beta) = b \wedge 0 < \mathit{ahead}(\beta) \wedge \neg\mathit{landed}(\beta) \wedge \neg\mathit{queued}(\beta)$$
-/
theorem land_sound (p : Params) (t : Nat) (f : AgentFacts) (b k : String) (h : Action.land b k ∈ next p t f) :
    f.handbackAt.isSome ∧ f.children = [] ∧ k = f.task ∧
      ∃ br, f.branch = some br ∧ br.name = b ∧ 0 < br.ahead ∧ br.landed = false ∧ br.queued = false := by
  have h2 := ((lands_mem p t f _ (.inr ⟨b, k, rfl⟩)).1 h).2
  unfold lands at h2
  split at h2
  · rename_i hh
    simp only [handedBack, Bool.and_eq_true, List.isEmpty_iff] at hh
    split at h2
    · rename_i br hbr
      rw [mem_opt] at h2
      obtain ⟨hc, hl⟩ := h2
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hc
      cases hq : br.queued <;> simp only [hq, Bool.false_eq_true, ite_false, ite_true] at hl
      · simp only [Action.land.injEq] at hl
        exact ⟨hh.1, hh.2, hl.2, br, hbr, hl.1.symm, hc.1, hc.2, hq⟩
      · cases hl
    · simp at h2
  · simp at h2

/-- **Route safety.** `routeIntegrator` only for an agent that handed back, has no live child, and whose branch is
ahead of `main`, not landed and on the integrator's list.

$$\forall p, t, f, b:\quad \mathrm{routeIntegrator}(b) \in \operatorname{next}(p, t, f) \Rightarrow h_\bot(f) \ne \bot \wedge C(f) = [\,] \wedge \exists \beta.\ b_\bot(f) = \beta \wedge \mathit{name}(\beta) = b \wedge 0 < \mathit{ahead}(\beta) \wedge \neg\mathit{landed}(\beta) \wedge \mathit{queued}(\beta)$$
-/
theorem route_sound (p : Params) (t : Nat) (f : AgentFacts) (b : String)
    (h : Action.routeIntegrator b ∈ next p t f) :
    f.handbackAt.isSome ∧ f.children = [] ∧
      ∃ br, f.branch = some br ∧ br.name = b ∧ 0 < br.ahead ∧ br.landed = false ∧ br.queued = true := by
  have h2 := ((lands_mem p t f _ (.inl ⟨_, rfl⟩)).1 h).2
  unfold lands at h2
  split at h2
  · rename_i hh
    simp only [handedBack, Bool.and_eq_true, List.isEmpty_iff] at hh
    split at h2
    · rename_i br hbr
      rw [mem_opt] at h2
      obtain ⟨hc, hl⟩ := h2
      simp only [Bool.and_eq_true, decide_eq_true_eq, Bool.not_eq_true'] at hc
      cases hq : br.queued <;> simp only [hq, Bool.false_eq_true, ite_false, ite_true] at hl
      · cases hl
      · simp only [Action.routeIntegrator.injEq] at hl
        exact ⟨hh.1, hh.2, br, hbr, hl.symm, hc.1, hc.2, hq⟩
    · simp at h2
  · simp at h2

/-- An action outside `kills`, `waits` and the nudge is in `next` only for a non-active agent, through the matching
piece (used for cleanup and respawn).

$$\forall p, t, f, y:\quad y \in \{\mathrm{cleanupWorktree}, \mathrm{respawnFromHandoff}\} \wedge y \in \operatorname{next}(p, t, f) \Rightarrow s(f) \ne \mathrm{active} \wedge \bigl(y \in \operatorname{cleans}(f) \vee y \in \operatorname{opt}(\operatorname{stuck}(f) \wedge C(f) = [\,], \mathrm{respawnFromHandoff})\bigr)$$
-/
theorem plain_mem (p : Params) (t : Nat) (f : AgentFacts) (y : Action)
    (hy : y = .cleanupWorktree ∨ y = .respawnFromHandoff) (h : y ∈ next p t f) :
    f.state ≠ .active ∧ (y ∈ cleans f ∨ y ∈ opt (stuckB f && f.children.isEmpty) .respawnFromHandoff) := by
  have hn : y ≠ .none := by rcases hy with rfl | rfl <;> simp
  rw [mem_next p t f y hn] at h
  have hk : y ∉ kills p t f := by
    rw [mem_kills]; rintro ⟨_, _, _, rfl⟩; rcases hy with h | h <;> cases h
  have hw : y ∉ waits f := by
    intro h; obtain ⟨_, _, _, rfl⟩ := waits_kind f _ h; rcases hy with h | h <;> cases h
  have hnu : ∀ b, y ∉ opt b .nudgeHandoff := by
    intro b h; rw [mem_opt] at h; rcases hy with hy | hy <;> rw [hy] at h <;> cases h.2
  rcases h with h | h | h
  · obtain ⟨_, _, h⟩ := claims_kind f _ h; rcases hy with hy | hy <;> rw [hy] at h <;> cases h
  · exact absurd h hk
  split at h
  · rcases h with h | h
    · exact absurd h hw
    · exact absurd h (hnu _)
  · rename_i ha
    refine ⟨ha, ?_⟩
    rcases h with h | h | h | h | h | h
    · exact absurd h hw
    · rcases lands_kind f _ h with ⟨_, h⟩ | ⟨_, _, h⟩ <;> rcases hy with hy | hy <;> rw [hy] at h <;> cases h
    · exact .inl h
    · exact .inr h
    · exact absurd h (hnu _)
    · obtain ⟨_, h⟩ := probes_kind p t f _ h; rcases hy with hy | hy <;> rw [hy] at h <;> cases h

/-- **Cleanup safety.** `cleanupWorktree` only when the agent has a worktree, its branch is landed and it has no live
child.

$$\forall p, t, f:\quad \mathrm{cleanupWorktree} \in \operatorname{next}(p, t, f) \Rightarrow w_\bot(f) \ne \bot \wedge (\exists \beta.\ b_\bot(f) = \beta \wedge \mathit{landed}(\beta)) \wedge C(f) = [\,]$$
-/
theorem cleanup_sound (p : Params) (t : Nat) (f : AgentFacts) (h : Action.cleanupWorktree ∈ next p t f) :
    f.worktree.isSome ∧ (∃ br, f.branch = some br ∧ br.landed = true) ∧ f.children = [] := by
  obtain ⟨_, h | h⟩ := plain_mem p t f _ (.inl rfl) h
  · unfold cleans at h
    rw [mem_opt] at h
    obtain ⟨hc, _⟩ := h
    simp only [Bool.and_eq_true, List.isEmpty_iff] at hc
    obtain ⟨⟨⟨hw, hl⟩, hch⟩, _⟩ := hc
    refine ⟨hw, ?_, hch⟩
    unfold landedB at hl
    split at hl
    · rename_i br hbr; exact ⟨br, hbr, hl⟩
    · cases hl
  · rw [mem_opt] at h; cases h.2

/-- **Respawn safety.** `respawnFromHandoff` only for an agent with no handback, stalled or gone, with no live child.

$$\forall p, t, f:\quad \mathrm{respawnFromHandoff} \in \operatorname{next}(p, t, f) \Rightarrow h_\bot(f) = \bot \wedge s(f) \in \{\mathrm{stalled}, \mathrm{gone}\} \wedge C(f) = [\,]$$
-/
theorem respawn_sound (p : Params) (t : Nat) (f : AgentFacts) (h : Action.respawnFromHandoff ∈ next p t f) :
    f.handbackAt = none ∧ (f.state = .stalled ∨ f.state = .gone) ∧ f.children = [] := by
  obtain ⟨_, h | h⟩ := plain_mem p t f _ (.inr rfl) h
  · unfold cleans at h; rw [mem_opt] at h; cases h.2
  · rw [mem_opt] at h
    obtain ⟨hc, _⟩ := h
    simp only [stuckB, handedBack, Bool.and_eq_true, Bool.not_eq_true', Option.isSome_eq_false_iff,
      Option.isNone_iff_eq_none, Bool.or_eq_true, beq_iff_eq, List.isEmpty_iff] at hc
    exact ⟨hc.1.1, hc.1.2, hc.2⟩

/-- **Liveness: land.** A non-active agent that handed back, has no live child, and whose branch is ahead of `main`
and not landed gets `land` (with its task) or `routeIntegrator`.

$$\forall p, t, f, \beta:\quad s(f) \ne \mathrm{active} \wedge h_\bot(f) \ne \bot \wedge C(f) = [\,] \wedge b_\bot(f) = \beta \wedge 0 < \mathit{ahead}(\beta) \wedge \neg\mathit{landed}(\beta) \Rightarrow \mathrm{land}(\mathit{name}(\beta), \mathit{task}(f)) \in \operatorname{next}(p, t, f) \vee \mathrm{routeIntegrator}(\mathit{name}(\beta)) \in \operatorname{next}(p, t, f)$$
-/
theorem live_land (p : Params) (t : Nat) (f : AgentFacts) (β : Branch) (ha : f.state ≠ .active)
    (hb : f.handbackAt.isSome) (hc : f.children = []) (hbr : f.branch = some β) (hah : 0 < β.ahead)
    (hl : β.landed = false) :
    Action.land β.name f.task ∈ next p t f ∨ Action.routeIntegrator β.name ∈ next p t f := by
  have hls : (if β.queued then Action.routeIntegrator β.name else .land β.name f.task) ∈ lands f := by
    unfold lands
    rw [ite_eq_left (by simp [handedBack, hb, hc]), hbr, mem_opt]
    exact ⟨by simp [hah, hl], rfl⟩
  cases hq : β.queued
  · simp only [hq, Bool.false_eq_true, ite_false] at hls
    exact .inl ((lands_mem p t f _ (.inr ⟨_, _, rfl⟩)).2 ⟨ha, hls⟩)
  · simp only [hq, ite_true] at hls
    exact .inr ((lands_mem p t f _ (.inl ⟨_, rfl⟩)).2 ⟨ha, hls⟩)

/-- A child gets `killOrphan` when it gets a kill.

$$\forall p, t, f, c:\quad c \in C(f) \wedge \operatorname{kill}(p, t, f, c) \Rightarrow \mathrm{killOrphan}(\mathit{pid}(c)) \in \operatorname{next}(p, t, f)$$
-/
theorem kill_of_killB (p : Params) (t : Nat) (f : AgentFacts) (c : Child) (hc : c ∈ f.children)
    (hk : killB p t f c = true) : Action.killOrphan c.pid ∈ next p t f :=
  (kill_mem p t f c.pid).2 ((mem_kills p t f _).2 ⟨c, hc, hk, rfl⟩)

/-- Sole from its proposition.

$$\forall f, c:\quad (\forall d \in C(f).\ \mathit{pid}(d) = \mathit{pid}(c) \Rightarrow k(d) = \mathrm{sleepLoop}) \Rightarrow \operatorname{sole}(f, c)$$
-/
theorem soleB_of (f : AgentFacts) (c : Child) (h : ∀ d ∈ f.children, d.pid = c.pid → d.kind = .sleepLoop) :
    soleB f c = true := by
  simp only [soleB, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq, beq_iff_eq]
  intro d hd
  by_cases e : d.pid = c.pid
  · exact .inr (h d hd e)
  · exact .inl e

/-- **Liveness: kill.** A non-active agent's sleep-loop child in the session's tree (not the session nor its own
ancestor), whose pid no child of another kind shares, and that runs past the loop cap, gets `killOrphan`.

$$\forall p, t, f, c:\quad s(f) \ne \mathrm{active} \wedge c \in C(f) \wedge k(c) = \mathrm{sleepLoop} \wedge \sigma(f) \in P(c) \wedge \mathit{pid}(c) \ne \sigma(f) \wedge \mathit{pid}(c) \notin P(c) \wedge (\forall d \in C(f).\ \mathit{pid}(d) = \mathit{pid}(c) \Rightarrow k(d) = \mathrm{sleepLoop}) \wedge \mu\,\mathit{loopCap} < t \mathbin{\dot-} s(c) \Rightarrow \mathrm{killOrphan}(\mathit{pid}(c)) \in \operatorname{next}(p, t, f)$$
-/
theorem live_kill (p : Params) (t : Nat) (f : AgentFacts) (c : Child) (ha : f.state ≠ .active)
    (hc : c ∈ f.children) (hk : c.kind = .sleepLoop) (hs : f.session ∈ c.chain) (hne : c.pid ≠ f.session)
    (hnc : c.pid ∉ c.chain) (hsole : ∀ d ∈ f.children, d.pid = c.pid → d.kind = .sleepLoop)
    (hold : p.loopCapMin * msPerMin < t - c.startedAt) : Action.killOrphan c.pid ∈ next p t f :=
  kill_of_killB p t f c hc ((killB_iff p t f c).2
    ⟨hk, hs, hne, hnc, soleB_of f c hsole, .inr (.inr (by simpa [oldB] using hold)), .inl ha⟩)

/-- **Liveness: kill for an active agent.** An active agent's sleep-loop child in the session's tree (not the session
nor its own ancestor), whose pid no child of another kind shares, and that watches a file whose producer has exited,
gets `killOrphan`.

$$\forall p, t, f, c:\quad s(f) = \mathrm{active} \wedge c \in C(f) \wedge k(c) = \mathrm{sleepLoop} \wedge \sigma(f) \in P(c) \wedge \mathit{pid}(c) \ne \sigma(f) \wedge \mathit{pid}(c) \notin P(c) \wedge (\forall d \in C(f).\ \mathit{pid}(d) = \mathit{pid}(c) \Rightarrow k(d) = \mathrm{sleepLoop}) \wedge w_\bot(c) \ne \bot \wedge \mathit{exit}(c) \Rightarrow \mathrm{killOrphan}(\mathit{pid}(c)) \in \operatorname{next}(p, t, f)$$
-/
theorem live_kill_active (p : Params) (t : Nat) (f : AgentFacts) (c : Child) (_ha : f.state = .active)
    (hc : c ∈ f.children) (hk : c.kind = .sleepLoop) (hs : f.session ∈ c.chain) (hne : c.pid ≠ f.session)
    (hnc : c.pid ∉ c.chain) (hsole : ∀ d ∈ f.children, d.pid = c.pid → d.kind = .sleepLoop)
    (hw : c.watchedAt ≠ none) (hx : c.producerExited = true) : Action.killOrphan c.pid ∈ next p t f := by
  have hd : deadB p t c = true := (deadB_iff p t c).2 (.inl ⟨hw, hx⟩)
  exact kill_of_killB p t f c hc ((killB_iff p t f c).2
    ⟨hk, hs, hne, hnc, soleB_of f c hsole, .inr (.inl hd), .inr hd⟩)

/-- Dead watches stay dead as time passes.

$$\forall p, t, t', c:\quad t \le t' \wedge \operatorname{dead}(p, t, c) \Rightarrow \operatorname{dead}(p, t', c)$$
-/
theorem deadB_mono (p : Params) (t t' : Nat) (c : Child) (htt : t ≤ t') (h : deadB p t c = true) :
    deadB p t' c = true := by
  rw [deadB_iff] at h ⊢
  rcases h with h | ⟨m, hm, hs⟩
  · exact .inl h
  · exact .inr ⟨m, hm, by omega⟩

/-- **Monotonicity in time.** With the facts unchanged, a pid flagged for `killOrphan` at time $t$ stays flagged at
every later time $t' \ge t$.

$$\forall p, t, t', f, q:\quad t \le t' \wedge \mathrm{killOrphan}(q) \in \operatorname{next}(p, t, f) \Rightarrow \mathrm{killOrphan}(q) \in \operatorname{next}(p, t', f)$$
-/
theorem kill_mono (p : Params) (t t' : Nat) (f : AgentFacts) (q : Nat) (htt : t ≤ t')
    (h : Action.killOrphan q ∈ next p t f) : Action.killOrphan q ∈ next p t' f := by
  obtain ⟨c, hc, hk, he⟩ := (mem_kills p t f _).1 ((kill_mem p t f q).1 h)
  simp only [Action.killOrphan.injEq] at he
  subst he
  obtain ⟨hk, hs, hne, hnc, hso, hw, ha⟩ := (killB_iff p t f c).1 hk
  refine kill_of_killB p t' f c hc ((killB_iff p t' f c).2 ⟨hk, hs, hne, hnc, hso, ?_, ?_⟩)
  · rcases hw with hw | hw | hw
    · exact .inl hw
    · exact .inr (.inl (deadB_mono p t t' c htt hw))
    · right; right; simp only [oldB, decide_eq_true_eq] at hw ⊢; omega
  · rcases ha with ha | ha
    · exact .inl ha
    · exact .inr (deadB_mono p t t' c htt ha)

/-! ## Examples (the observed cases; the golden vectors in `packages/contracts/golden/obs/next.jsonl` repeat them) -/

/-- Example time: $t_0 = 1760000000000$ ms.

$$t_0 = 1760000000000$$
-/
def t0 : Nat := 1760000000000

/-- `m` minutes before `t0`.

$$\operatorname{ago}(m) = t_0 \mathbin{\dot-} \mu m$$
-/
def ago (m : Nat) : Nat := t0 - m * msPerMin

/-- An example agent for the guards: id and task `k`, state `s`, session pid 100, nothing else observed.

$$\operatorname{ex}(k, s) = (k, k, s, \bot, 100, \bot, \bot, 0, [\,], \bot)$$
-/
def ex (k : String) (s : State) : AgentFacts := { id := k, task := k, state := s, session := 100 }

-- port-nav: handed back, branch 3 ahead, queued for the integrator → route; not queued → land
#guard next {} t0
    { ex "port-nav" .done with
      handbackAt := some (ago 90), branch := some ⟨"wt-a", 3, false, true⟩, worktree := some {} }
  == [.routeIntegrator "wt-a"]
#guard next {} t0
    { ex "port-nav" .done with
      handbackAt := some (ago 90), branch := some ⟨"wt-a", 3, false, false⟩, worktree := some {} }
  == [.land "wt-a" "port-nav"]
-- ghb-runner: handed back, landed, a sleep loop under the session on a stale file → kill only (cleanup next time)
#guard next {} t0
    { ex "ghb-runner" .done with
      handbackAt := some (ago 25), branch := some ⟨"b", 0, true, false⟩, worktree := some {},
      children := [{ pid := 555, chain := [100, 1], kind := .sleepLoop, startedAt := ago 22,
                     watchedAt := some (ago 20) }] }
  == [.killOrphan 555]
#guard next {} t0
    { ex "ghb-runner" .done with
      handbackAt := some (ago 25), branch := some ⟨"b", 0, true, false⟩, worktree := some {} }
  == [.cleanupWorktree]
-- port-platform: waiting on its CI run → waitCi
#guard next {} t0
    { ex "port-platform" .idle with
      children := [{ pid := 600, chain := [100, 1], kind := .ciWait 42 10, startedAt := ago 4 }],
      ci := some ⟨42, { workflow := "w", branch := "ci/port-platform", status := "in_progress",
                        startedAt := ago 5 }⟩ }
  == [.waitCi 42]
-- integrate-ports: active, context above ctxWarn, an old loop child on a fresh file → nudge only
#guard next {} t0
    { ex "integrate-ports" .active with
      ctxTokens := 260000,
      children := [{ pid := 700, chain := [100, 1], kind := .sleepLoop, startedAt := ago 99,
                     watchedAt := some (ago 1) }] }
  == [.nudgeHandoff]
-- integrate-ports at 03:15: active, a loop on a background task's output whose producer exited → kill and nudge
#guard next {} t0
    { ex "integrate-ports" .active with
      children := [{ pid := 701, chain := [100, 1], kind := .sleepLoop, startedAt := ago 35,
                     watchedAt := some (ago 3), producerExited := true }] }
  == [.killOrphan 701, .nudgeHandoff]
-- obs-next-lean at 03:05: live, its task reached the board after the spawn-time claim and has no agent → claim
#guard next {} t0 { ex "obs-next-lean" .active with board := some { id := "obs-next-lean", done := false } }
  == [.claimTask "obs-next-lean" "obs-next-lean"]
-- task bound already, task done, or agent gone → no claim
#guard next {} t0
    { ex "g" .active with board := some { id := "g", done := false, agent := some "g" } } == [.none]
#guard next {} t0 { ex "g" .idle with board := some { id := "g", done := true } } == [.none]
#guard next {} t0 { ex "g" .gone with board := some { id := "g", done := false } } == [.respawnFromHandoff]
-- nothing to do
#guard next {} t0 (ex "e" .idle) == [.none]
-- a build child is never killed; a stuck agent held by it is investigated
#guard next {} t0
    { ex "f" .stalled with children := [{ pid := 800, chain := [100, 1], kind := .build, startedAt := ago 99 }] }
  == [.investigate .heldByChild]

end Fw.Obs.Next
