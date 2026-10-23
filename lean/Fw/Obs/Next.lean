import Fw.Obs.Health
import Fw.Obs.Signals
import Fw.Obs.Timing
/-!
# Next action per agent: agents that look busy but are idle or held, and what fixes each

`Fw.Obs.Health` derives each agent's state from hook and transcript events. Some agents look busy there while
nothing will happen without the lead: an agent that handed back but whose branch was never landed, an agent whose
own `until grep …; do sleep …` loop can never finish, an agent waiting on a CI run, an active agent close to its
context limit. This module takes, per agent, the Health state plus the facts that tell these cases apart (handback
seen, branch ahead of `main` and landed or not, integrator queue, worktree lock, the agent's child processes with
kind, age and watched-file state, its CI run, the board row of its task) and returns the list of next actions (`next`).

Units as in `Fw.Obs.Health`: times are ms since the epoch, the `…Min` thresholds are minutes
(`μ = 60000` ms), an age is the truncated difference `t ∸ s`. The facts are a snapshot: the Health
state is an input here (the reply of `obs.health` for the same snapshot), not recomputed.

A loop child is **own** when its parent chain reaches the session pid and it is neither the session nor one of its
own ancestors, **sole** when no child of another kind shares its pid, and its watch is **dead** when it watches a file
whose producer has exited (the file's last line is the exit marker) or that is unchanged for more than
`fileStaleMin`. Such a loop can never be satisfied.

Rules (a gate on the Health state, then independent pieces in a fixed order; `none` exactly when no piece fires):
* Every agent, first: `claimTask` when it is live (not done, not gone) and its name is the id of a board task that is
  not done and has no agent (the spawn-time claim ran before the task reached the board and is never retried).
* An **active** agent gets only: `killOrphan` for an own, sole waiting child (sleep loop or stdin wait) with a dead
  watch (killing only wakes the owner's waiting call), `waitCi` (its CI run is running), and `nudgeHandoff` (context
  above `ctxWarn`, or paired with every such kill so the owner learns why its call returned).
* Otherwise: `killOrphan` for each own, sole waiting child whose owner handed back, or whose watch is dead, or which runs
  for more than `loopCapMin`; `waitCi`; `land` or `routeIntegrator` (handed back, no live child, branch ahead and not
  landed; routed when the branch is on the integrator's list); `cleanupWorktree` (worktree present, branch landed, no
  live child, handed back or ended); `respawnFromHandoff` (no handback, stalled or gone, no live child);
  `nudgeHandoff`; `investigate` with a reason (held by a child that gets no kill, a CI wait past its own timeout, a
  sleep loop outside the session's tree, a dead worktree-lock pid of a live agent).

Signals (`Fw.Obs.Signals`): when an agent carries its transcript signals, `resolve` takes its handback from them and
marks a child's producer exited when the child watches a task that has ended or an agent that is finished or done;
`next` then decides on the resolved facts. Retention (`keepB`) keeps an agent while `next` gives it an action other
than `none` or its signal state is not quiet; `meta.finished` is read nowhere.

Proved: `next_total`, `next_det`, `kill_sound`, `kill_only_loops`, `active_quiet`, `active_kill_nudge`, `land_sound`,
`route_sound`, `cleanup_sound`, `respawn_sound`, `claim_sound`, `live_land`, `live_kill`, `live_kill_active`,
`live_claim`, `kill_mono`, `resolve_handback`, `resolveChild_exit`, `keep_of_open_action`, `keep_of_live`,
`keep_withMeta`, `keepHealth_of_open_action`. Wire ops: `obs.next`, `obs.signals` (`Fw.Wire.Obs`).
-/
namespace Fw.Obs.Next
open Fw.Obs.Health (State CiRun ciRunning msPerMin)

/-- The thresholds: the Health thresholds (`ctxWarn` is used here), the loop cap and the file-stale time.
`loopCapMin` = 30: no poll loop of this repo may wait open-ended (CI waits go through `waitrun.sh`, a `ciWait`, with
their own timeout), and 30 min is above `ciSlowMin` (20), the longest wait the lead treats as normal.
`fileStaleMin` = 10: builds, tests and CI logs write at least every few minutes, so a watched file unchanged for
10 min will not bring the awaited text.
-/
structure Params where
  health       : Fw.Obs.Health.Params := {}
  loopCapMin   : Nat := 30
  fileStaleMin : Nat := 10
deriving DecidableEq, Repr

/-- What a child process of the agent's session does: a shell poll loop (`until …; do sleep …; done`), a CI wait
(`waitrun.sh <run>` with its timeout in minutes), a build or test run, anything else, or a background command blocked
reading a stdin that nothing feeds (port-nav's `cat > file`).
-/
inductive ChildKind where
  | sleepLoop
  | ciWait (run : Nat) (timeoutMin : Nat)
  | build
  | other
  | stdinWait
deriving DecidableEq, Repr

/-- The waiting kinds, the only ones that may be killed: a sleep loop or a stdin wait (neither does work). -/
def waitsK (k : ChildKind) : Bool := k == .sleepLoop || k == .stdinWait

/-- What a loop watches, when known: the output of a background task (by task id) or an agent's transcript (by the
agent id its signals carry).
-/
inductive Watch where
  | task (id : String)
  | agent (id : String)
deriving DecidableEq, Repr

/-- A live child process started by the agent: its pid, its parent chain (the ppid, then the ppid's ppid, … up to
pid 1), its kind, its start time (ms), the modification time (ms) of the file it watches (`none`: it watches none),
whether that file's producer has exited (its last line is the exit marker `[exited with code N]` or `[killed]`), and
what the watched file belongs to (`none`: unknown; `resolve` adds an exited producer for an ended task or a finished
or done agent).
-/
structure Child where
  pid            : Nat
  chain          : List Nat := []
  kind           : ChildKind
  startedAt      : Nat
  watchedAt      : Option Nat := none
  producerExited : Bool := false
  watch          : Option Watch := none
deriving DecidableEq, Repr

/-- The agent's branch: name, commits ahead of `main` (`git rev-list --count main..branch`), whether its tip is an
ancestor of `main` (landed), whether it is on the integrator's list (queued), whether it merges into `main` without
conflict (`git merge-tree --write-tree main <branch>` exits 0; default true), and its unlanded dependencies (branches of
other agents it contains that are not on `main`, or tasks of its own dependencies that are not done; default none),
whether a land commit of its task is on `main` (default false), the branch named by the live land lock (default none)
and whether it is in the land queue (default false).

A field left out takes its default; `ℓ = ⊥` means no land lock is held.
-/
structure Branch where
  name   : String
  ahead  : Nat
  landed : Bool
  queued : Bool
  mergesClean : Bool := true
  deps   : List String := []
  /-- a land commit with this task's `Task:` trailer is on `main` (read from main's history, never from the branch's
  existence: `fw land` deletes the branch) -/
  onMain : Bool := false
  /-- the branch named by the live land lock (`none`: no live lock) -/
  landLock : Option String := none
  /-- the branch is in the land queue (`fw land --queue`): a pending entry in `.fw-console/land-queue.jsonl` (task `land-queue`) -/
  inLandQueue : Bool := false
deriving DecidableEq, Repr

/-- The branch is settled: its tip is an ancestor of `main`, or a land commit for its task is on `main`. -/
def Branch.settled (b : Branch) : Bool := b.landed || b.onMain

/-- A `fw land` for this very branch is in flight: the live land lock names it, or the branch is a pending entry of the land
queue (its single runner will land it).
-/
def Branch.locked (b : Branch) : Bool := b.landLock == some b.name || b.inLandQueue

/-- The agent's worktree: the pid in its lock (`none`: not locked) and whether that pid is alive. -/
structure Worktree where
  lockPid   : Option Nat := none
  lockAlive : Bool := false
deriving DecidableEq, Repr

/-- The latest CI run of the agent's `ci/*` branch: its run id and the run (status, conclusion, times). -/
structure Ci where
  id  : Nat
  run : CiRun
deriving DecidableEq, Repr

/-- The board row of the task whose id is the agent's name: task id, whether the task is done, and the agent bound to
it (`none`: unbound).
-/
structure TaskRow where
  id    : String
  done  : Bool
  agent : Option String := none
deriving DecidableEq, Repr

/-- The facts of one agent: id, task id, Health state, time of its handback (`none`: not seen), the session pid its
processes descend from, its branch, worktree and context tokens (0 when unknown), its live child processes, the
latest CI run of its `ci/*` branch, the board row of the task named like the agent (`none`: no such task), whether its
handoff note exists, and its transcript signals (`Fw.Obs.Signals.Facts`; `none`: not read).
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
  /-- the handoff note `docs/team/handoffs/<name>.md` exists -/
  handoff    : Bool := false
  /-- the transcript signals (`none`: not read; then `resolve` leaves the facts as they are) -/
  signals    : Option Fw.Obs.Signals.Facts := none
deriving DecidableEq, Repr

/-- Why an agent needs a look by the lead: held by a child that gets no kill, a CI wait past its own timeout, a sleep
loop outside the session's process tree (never killed here), a dead lock pid on the worktree of an agent that has
not ended and has not handed back, or a branch that does not merge into `main` cleanly.
-/
inductive Reason where
  | heldByChild | ciWaitOverdue | foreignLoop | lockDead | conflict
deriving DecidableEq, Repr

/-- The next actions: nothing, wait for a CI run, land a branch for a task, route a branch to the integrator, kill an
orphan process, remove the worktree, stop and respawn from the handoff note, ask the agent to write its handoff, or
look at it (with a reason), or bind a task to the agent on the board.
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
  | waitDeps (dep : String)
deriving DecidableEq, Repr

/-! ## Tests -/

/-- Whether the agent has handed back. -/
def handedBack (f : AgentFacts) : Bool := f.handbackAt.isSome

/-- Whether a Health state is an ended one (done or gone). -/
def endedS (s : State) : Bool := s == .done || s == .gone

/-- Whether the branch is landed (no branch: not landed). -/
def landedB (f : AgentFacts) : Bool :=
  match f.branch with
  | some b => b.settled
  | none => false

/-- Whether a child's watched file is stale: unchanged for strictly more than `fileStaleMin` (no watched file: no). -/
def staleB (p : Params) (now : Nat) (c : Child) : Bool :=
  match c.watchedAt with
  | some m => decide (p.fileStaleMin * msPerMin < now - m)
  | none => false

/-- Whether a child watches a file whose producer has exited. -/
def exitedB (c : Child) : Bool := c.watchedAt.isSome && c.producerExited

/-- Whether a child's watch is dead: its file's producer has exited or the file is stale. -/
def deadB (p : Params) (now : Nat) (c : Child) : Bool := exitedB c || staleB p now c

/-- Whether a child runs for strictly more than the loop cap. -/
def oldB (p : Params) (now : Nat) (c : Child) : Bool := decide (p.loopCapMin * msPerMin < now - c.startedAt)

/-- Whether a child's pid is unambiguous: every child of the agent with the same pid is of a waiting kind (sleep loop or stdin wait). -/
def soleB (f : AgentFacts) (c : Child) : Bool := f.children.all fun d => d.pid != c.pid || waitsK d.kind

/-- Whether a child is in the session's tree but is neither the session nor one of its own ancestors. -/
def ownB (f : AgentFacts) (c : Child) : Bool :=
  c.chain.contains f.session && c.pid != f.session && !c.chain.contains c.pid

/-- An orphan loop: an own, sole child of a waiting kind whose owner has handed back, or whose watch is dead, or which runs
past the loop cap.
-/
def orphanB (p : Params) (now : Nat) (f : AgentFacts) (c : Child) : Bool :=
  waitsK c.kind && ownB f c && soleB f c && (handedBack f || deadB p now c || oldB p now c)

/-- Whether a child gets `killOrphan`: an orphan loop, and when the agent is active its watch must be dead. -/
def killB (p : Params) (now : Nat) (f : AgentFacts) (c : Child) : Bool :=
  orphanB p now f c && (f.state != .active || deadB p now c)

/-- Whether a child is a CI wait past its own timeout (strictly more than its timeout minutes). -/
def overdueB (now : Nat) (c : Child) : Bool :=
  match c.kind with
  | .ciWait _ m => decide (m * msPerMin < now - c.startedAt)
  | _ => false

/-- A sleep loop outside the session's tree (its chain does not reach the session pid). -/
def foreignB (f : AgentFacts) (c : Child) : Bool := c.kind == .sleepLoop && !c.chain.contains f.session

/-- Stuck: no handback, and stalled or gone. -/
def stuckB (f : AgentFacts) : Bool := !handedBack f && (f.state == .stalled || f.state == .gone)

/-- Whether to ask for the handoff note: no handback, active, idle or parked, and context strictly above `ctxWarn`. -/
def nudgeB (p : Params) (f : AgentFacts) : Bool :=
  !handedBack f && (f.state == .active || f.state == .idle || f.state == .parked) &&
    decide (p.health.ctxWarn < f.ctxTokens)

/-- A worktree lock whose pid is dead, on an agent that has not handed back and has not ended. -/
def lockDeadB (f : AgentFacts) : Bool :=
  !handedBack f && !endedS f.state &&
    match f.worktree with
    | some w => w.lockPid.isSome && !w.lockAlive
    | none => false

/-- The agent's task is open: the board has the task named like the agent and it is not done. -/
def openTaskB (f : AgentFacts) : Bool :=
  match f.board with
  | some r => !r.done
  | none => false

/-- Respawn from the handoff is valid: stuck, no live child, its task exists and is not done, and a handoff note exists. -/
def respawnB (f : AgentFacts) : Bool := stuckB f && f.children.isEmpty && openTaskB f && f.handoff

/-! ## The pieces and the decision -/

/-- A one-element list when the test holds, else empty. -/
def opt (b : Bool) (x : Action) : List Action := if b then [x] else []

/-- One `killOrphan` per child that gets a kill, in child order. -/
def kills (p : Params) (now : Nat) (f : AgentFacts) : List Action :=
  (f.children.filter (killB p now f)).map fun c => .killOrphan c.pid

/-- `waitCi` for the agent's CI run while it is running. -/
def waits (f : AgentFacts) : List Action :=
  match f.ci with
  | some c => opt (ciRunning c.run) (.waitCi c.id)
  | none => []

/-- Land or route a handed-back agent's unlanded branch when it has no live child. On the integrator's list: route.
Otherwise a branch that does not merge cleanly is `investigate conflict`, a branch with an unlanded dependency waits
for it (`waitDeps` of the first), and only a clean branch without unlanded dependencies is `land`ed with the agent's task.
-/
def lands (f : AgentFacts) : List Action :=
  if handedBack f && f.children.isEmpty then
    match f.branch with
    | some b =>
      if decide (0 < b.ahead) && !b.settled && !b.locked then
        (if b.queued then [.routeIntegrator b.name]
         else if b.mergesClean then
           (match b.deps with
            | d :: _ => [.waitDeps d]
            | [] => [.land b.name f.task])
         else [.investigate .conflict])
      else []
    | none => []
  else []

/-- Clean up the worktree: present, branch landed, no live child, and handed back or ended. -/
def cleans (f : AgentFacts) : List Action :=
  opt (f.worktree.isSome && landedB f && f.children.isEmpty && (handedBack f || endedS f.state)) .cleanupWorktree

/-- The `investigate` actions, in reason order: held by a child that gets no kill (stuck, or handed back), an overdue
CI wait, a foreign sleep loop, a dead lock pid.
-/
def probes (p : Params) (now : Nat) (f : AgentFacts) : List Action :=
  opt ((stuckB f || handedBack f) && f.children.any (fun c => !killB p now f c)) (.investigate .heldByChild) ++
  opt (f.children.any (overdueB now)) (.investigate .ciWaitOverdue) ++
  opt (f.children.any (foreignB f)) (.investigate .foreignLoop) ++
  opt (lockDeadB f) (.investigate .lockDead)

/-- `[none]` for an empty list, else the list. -/
def orNone (l : List Action) : List Action := if l.isEmpty then [.none] else l

/-- Claim the agent's task on the board: a live agent (not done, not gone) whose name is the id of a board task that
is not done and has no agent gets `claimTask` of that task for itself.
-/
def claims (f : AgentFacts) : List Action :=
  match f.board with
  | some r => opt (!endedS f.state && r.id == f.id && !r.done && r.agent.isNone) (.claimTask r.id f.id)
  | none => []

/-- The next actions of one agent: claims first; then for an active agent kills (dead watches only), waits and a
nudge (high context or any kill); otherwise kills, waits, land or route, cleanup, respawn, nudge and probes, in this
order; `[none]` when nothing fires.
-/
def next (p : Params) (now : Nat) (f : AgentFacts) : List Action :=
  if f.state == .active then
    orNone (claims f ++ kills p now f ++ waits f ++ opt (nudgeB p f || !(kills p now f).isEmpty) .nudgeHandoff)
  else orNone (claims f ++ kills p now f ++ waits f ++ lands f ++ cleans f ++
    opt (respawnB f) .respawnFromHandoff ++ opt (nudgeB p f) .nudgeHandoff ++ probes p now f)

/-! ## Proofs -/

/-- Membership in `opt`. -/
theorem mem_opt (b : Bool) (x y : Action) : y ∈ opt b x ↔ b = true ∧ y = x := by
  unfold opt; cases b <;> simp

/-- An action other than `none` is in `orNone ℓ` exactly when it is in `ℓ`. -/
theorem mem_orNone (l : List Action) (x : Action) (hx : x ≠ .none) : x ∈ orNone l ↔ x ∈ l := by
  unfold orNone
  cases l with
  | nil => simp [hx]
  | cons _ _ => simp

/-- Membership in `kills`: a kill of the pid of a child that gets a kill. -/
theorem mem_kills (p : Params) (t : Nat) (f : AgentFacts) (x : Action) :
    x ∈ kills p t f ↔ ∃ c ∈ f.children, killB p t f c = true ∧ x = .killOrphan c.pid := by
  unfold kills
  simp only [List.mem_map, List.mem_filter]
  constructor
  · rintro ⟨c, ⟨hc, hk⟩, rfl⟩; exact ⟨c, hc, hk, rfl⟩
  · rintro ⟨c, hc, hk, rfl⟩; exact ⟨c, ⟨hc, hk⟩, rfl⟩

/-- `waits` holds only the `waitCi` of a running CI run of the agent. -/
theorem waits_kind (f : AgentFacts) (x : Action) (h : x ∈ waits f) :
    ∃ c, f.ci = some c ∧ ciRunning c.run = true ∧ x = .waitCi c.id := by
  unfold waits at h
  split at h
  · rename_i c hc; rw [mem_opt] at h; exact ⟨c, hc, h.1, h.2⟩
  · simp at h

/-- `lands` holds only `routeIntegrator`, `land`, `waitDeps` or `investigate conflict` actions. -/
theorem lands_kind (f : AgentFacts) (x : Action) (h : x ∈ lands f) :
    (∃ b, x = .routeIntegrator b) ∨ (∃ b k, x = .land b k) ∨ (∃ d, x = .waitDeps d) ∨ x = .investigate .conflict := by
  unfold lands at h
  repeat' split at h
  all_goals simp only [List.mem_singleton, List.not_mem_nil] at h
  all_goals first
    | (subst h; exact .inl ⟨_, rfl⟩)
    | (subst h; exact .inr (.inl ⟨_, _, rfl⟩))
    | (subst h; exact .inr (.inr (.inl ⟨_, rfl⟩)))
    | (subst h; exact .inr (.inr (.inr rfl)))

/-- `probes` holds only `investigate` actions. -/
theorem probes_kind (p : Params) (t : Nat) (f : AgentFacts) (x : Action) (h : x ∈ probes p t f) :
    ∃ r, x = .investigate r := by
  simp only [probes, List.mem_append, mem_opt] at h
  rcases h with ((⟨_, rfl⟩ | ⟨_, rfl⟩) | ⟨_, rfl⟩) | ⟨_, rfl⟩ <;> exact ⟨_, rfl⟩

/-- `claims` holds only `claimTask` actions. -/
theorem claims_kind (f : AgentFacts) (x : Action) (h : x ∈ claims f) : ∃ k a, x = .claimTask k a := by
  unfold claims at h
  split at h
  · rw [mem_opt] at h; exact ⟨_, _, h.2⟩
  · simp at h

/-- A `claimTask` in `next` comes only from `claims`. -/
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
    intro h; rcases lands_kind f _ h with ⟨_, h⟩ | ⟨_, _, h⟩ | ⟨_, h⟩ | h <;> cases h
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
-/
theorem mem_next (p : Params) (t : Nat) (f : AgentFacts) (x : Action) (hx : x ≠ .none) :
    x ∈ next p t f ↔ x ∈ claims f ∨ x ∈ kills p t f ∨
      if f.state = .active then x ∈ waits f ∨ x ∈ opt (nudgeB p f || !(kills p t f).isEmpty) .nudgeHandoff
      else x ∈ waits f ∨ x ∈ lands f ∨ x ∈ cleans f ∨
        x ∈ opt (respawnB f) .respawnFromHandoff ∨ x ∈ opt (nudgeB p f) .nudgeHandoff ∨
        x ∈ probes p t f := by
  unfold next
  by_cases h : f.state = .active
  · simp [h, mem_orNone _ _ hx]
  · have h' : (f.state == .active) = false := by simp [h]
    simp [h, h', mem_orNone _ _ hx]

/-- **Totality.** For every input the decision gives a non-empty list, and `none` appears only alone. -/
theorem next_total (p : Params) (t : Nat) (f : AgentFacts) :
    next p t f ≠ [] ∧ (Action.none ∈ next p t f → next p t f = [Action.none]) := by
  have hk : Action.none ∉ kills p t f := by
    rw [mem_kills]; rintro ⟨_, _, _, h⟩; cases h
  have hcl : Action.none ∉ claims f := by
    intro h; obtain ⟨_, _, h⟩ := claims_kind f _ h; cases h
  have hw : Action.none ∉ waits f := by
    intro h; obtain ⟨_, _, _, h⟩ := waits_kind f _ h; cases h
  have hl : Action.none ∉ lands f := by
    intro h; rcases lands_kind f _ h with ⟨_, h⟩ | ⟨_, _, h⟩ | ⟨_, h⟩ | h <;> cases h
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

/-- **Determinism.** The decision is a function of its inputs: two results for the same input are equal. -/
theorem next_det (p : Params) (t : Nat) (f : AgentFacts) (l l' : List Action)
    (h : next p t f = l) (h' : next p t f = l') : l = l' := h ▸ h'

/-- A `killOrphan` in `next` comes only from `kills`. -/
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
      · rcases lands_kind f _ h with ⟨_, h⟩ | ⟨_, _, h⟩ | ⟨_, h⟩ | h <;> cases h
      · unfold cleans at h; rw [mem_opt] at h; cases h.2
      · rw [mem_opt] at h; cases h.2
      · rw [mem_opt] at h; cases h.2
      · obtain ⟨_, h⟩ := probes_kind p t f _ h; cases h
  · exact fun h => .inr (.inl h)

/-- The kill test unfolded: an own, sole waiting child whose owner handed back, or whose watch is dead, or which runs
past the cap; for an active agent its watch must be dead.
-/
theorem killB_iff (p : Params) (t : Nat) (f : AgentFacts) (c : Child) :
    killB p t f c = true ↔ waitsK c.kind = true ∧ f.session ∈ c.chain ∧ c.pid ≠ f.session ∧ c.pid ∉ c.chain ∧
      soleB f c = true ∧ (handedBack f = true ∨ deadB p t c = true ∨ oldB p t c = true) ∧
      (f.state ≠ .active ∨ deadB p t c = true) := by
  simp only [killB, orphanB, ownB, Bool.and_eq_true, Bool.or_eq_true, List.contains_iff_mem,
    bne_iff_ne, ne_eq, Bool.not_eq_true', Bool.eq_false_iff]
  constructor
  · rintro ⟨⟨⟨⟨hk, ⟨hs, hne⟩, hnc⟩, hso⟩, hw⟩, ha⟩
    exact ⟨hk, hs, hne, hnc, hso, by simpa [or_assoc] using hw, ha⟩
  · rintro ⟨hk, hs, hne, hnc, hso, hw, ha⟩
    exact ⟨⟨⟨⟨hk, ⟨hs, hne⟩, hnc⟩, hso⟩, by simpa [or_assoc] using hw⟩, ha⟩

/-- The dead-watch test unfolded. -/
theorem deadB_iff (p : Params) (t : Nat) (c : Child) :
    deadB p t c = true ↔ (c.watchedAt ≠ none ∧ c.producerExited = true) ∨
      ∃ m, c.watchedAt = some m ∧ p.fileStaleMin * msPerMin < t - m := by
  unfold deadB exitedB staleB
  cases c.watchedAt <;> simp

/-- **Kill safety.** A killed pid is a waiting child (sleep loop or stdin wait) of the agent whose parent chain reaches the session pid, which
is not the session nor its own ancestor; its owner handed back, or its watch is dead (producer exited or file stale),
or it runs past the loop cap; and if the agent is active, its watch is dead.
-/
theorem kill_sound (p : Params) (t : Nat) (f : AgentFacts) (q : Nat) (h : Action.killOrphan q ∈ next p t f) :
    ∃ c ∈ f.children, c.pid = q ∧ waitsK c.kind = true ∧ f.session ∈ c.chain ∧ q ≠ f.session ∧ q ∉ c.chain ∧
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
-/
theorem kill_only_loops (p : Params) (t : Nat) (f : AgentFacts) (c : Child) (hc : c ∈ f.children)
    (hk : waitsK c.kind = false) : Action.killOrphan c.pid ∉ next p t f := by
  intro h
  obtain ⟨d, _, hd, he⟩ := (mem_kills p t f _).1 ((kill_mem p t f c.pid).1 h)
  simp only [Action.killOrphan.injEq] at he
  obtain ⟨_, _, _, _, hso, _⟩ := (killB_iff p t f d).1 hd
  simp only [soleB, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq] at hso
  rcases hso c hc with h1 | h1
  · exact h1 he
  · simp [hk] at h1

/-- **Active gate.** An active agent gets only `none`, `waitCi`, `nudgeHandoff`, `claimTask`, or `killOrphan` of a
waiting child in the session's tree whose watch is dead (its file's producer has exited or the file is stale).
-/
theorem active_quiet (p : Params) (t : Nat) (f : AgentFacts) (x : Action) (ha : f.state = .active)
    (hx : x ∈ next p t f) :
    x = .none ∨ (∃ r, x = .waitCi r) ∨ x = .nudgeHandoff ∨ (∃ k a, x = .claimTask k a) ∨
      ∃ c ∈ f.children, x = .killOrphan c.pid ∧ waitsK c.kind = true ∧ f.session ∈ c.chain ∧
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

/-- Land and route come only from `lands`, never for an active agent. -/
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

/-- Where an action of `lands` comes from: the agent handed back, has no live child, its branch is ahead of `main` and
not landed, and the action is one of the four cases of `lands`.
-/
theorem lands_cases (f : AgentFacts) (x : Action) (h : x ∈ lands f) :
    f.handbackAt.isSome ∧ f.children = [] ∧ ∃ br, f.branch = some br ∧ 0 < br.ahead ∧ br.settled = false ∧ br.locked = false ∧
      ((br.queued = true ∧ x = .routeIntegrator br.name) ∨
       (br.queued = false ∧ br.mergesClean = false ∧ x = .investigate .conflict) ∨
       (br.queued = false ∧ br.mergesClean = true ∧ ∃ d ds, br.deps = d :: ds ∧ x = .waitDeps d) ∨
       (br.queued = false ∧ br.mergesClean = true ∧ br.deps = [] ∧ x = .land br.name f.task)) := by
  unfold lands at h
  repeat' split at h
  all_goals simp only [List.mem_singleton, List.not_mem_nil] at h
  all_goals subst h
  all_goals simp_all [handedBack]

/-- **Land safety.** `land` only for an agent that handed back, has no live child, and whose branch is ahead of `main`,
not landed, not on the integrator's list, merges cleanly and has no unlanded dependency; the task is the agent's.
-/
theorem land_sound (p : Params) (t : Nat) (f : AgentFacts) (b k : String) (h : Action.land b k ∈ next p t f) :
    f.handbackAt.isSome ∧ f.children = [] ∧ k = f.task ∧
      ∃ br, f.branch = some br ∧ br.name = b ∧ 0 < br.ahead ∧ br.settled = false ∧ br.queued = false ∧
        br.mergesClean = true ∧ br.deps = [] := by
  have h2 := ((lands_mem p t f _ (.inr ⟨b, k, rfl⟩)).1 h).2
  obtain ⟨h1, h3, br, hbr, ha, hl, _, hc⟩ := lands_cases f _ h2
  rcases hc with ⟨_, hx⟩ | ⟨_, _, hx⟩ | ⟨_, _, _, _, _, hx⟩ | ⟨hq, hm, hd, hx⟩
  · cases hx
  · cases hx
  · cases hx
  · simp only [Action.land.injEq] at hx
    exact ⟨h1, h3, hx.2, br, hbr, hx.1.symm, ha, hl, hq, hm, hd⟩

/-- **Route safety.** `routeIntegrator` only for an agent that handed back, has no live child, and whose branch is
ahead of `main`, not landed and on the integrator's list.
-/
theorem route_sound (p : Params) (t : Nat) (f : AgentFacts) (b : String)
    (h : Action.routeIntegrator b ∈ next p t f) :
    f.handbackAt.isSome ∧ f.children = [] ∧
      ∃ br, f.branch = some br ∧ br.name = b ∧ 0 < br.ahead ∧ br.settled = false ∧ br.queued = true := by
  have h2 := ((lands_mem p t f _ (.inl ⟨_, rfl⟩)).1 h).2
  obtain ⟨h1, h3, br, hbr, ha, hl, _, hc⟩ := lands_cases f _ h2
  rcases hc with ⟨hq, hx⟩ | ⟨_, _, hx⟩ | ⟨_, _, _, _, _, hx⟩ | ⟨_, _, _, hx⟩
  · simp only [Action.routeIntegrator.injEq] at hx
    exact ⟨h1, h3, br, hbr, hx.symm, ha, hl, hq⟩
  · cases hx
  · cases hx
  · cases hx

/-- **Wait-deps and conflict safety.** `waitDeps d` only for a handed-back agent whose clean, unqueued, unlanded branch
has `d` as first unlanded dependency; `investigate conflict` only when its unqueued branch does not merge cleanly.
-/
theorem waitDeps_sound (p : Params) (t : Nat) (f : AgentFacts) (d : String)
    (h : Action.waitDeps d ∈ next p t f) :
    ∃ br ds, f.branch = some br ∧ br.deps = d :: ds ∧ br.settled = false ∧ br.queued = false := by
  have hn : Action.waitDeps d ≠ .none := by simp
  rw [mem_next p t f _ hn] at h
  have hk : Action.waitDeps d ∉ kills p t f := by
    rw [mem_kills]; rintro ⟨_, _, _, h⟩; cases h
  have hw : Action.waitDeps d ∉ waits f := by
    intro h; obtain ⟨_, _, _, h⟩ := waits_kind f _ h; cases h
  have hcl : Action.waitDeps d ∉ claims f := by
    intro h; obtain ⟨_, _, h⟩ := claims_kind f _ h; cases h
  have ho : ∀ b y, y ≠ Action.waitDeps d → Action.waitDeps d ∉ opt b y := by
    intro b y hy h; rw [mem_opt] at h; exact hy h.2.symm
  have hc : Action.waitDeps d ∉ cleans f := by unfold cleans; exact ho _ _ (by simp)
  have hpr : Action.waitDeps d ∉ probes p t f := by
    intro h; obtain ⟨_, h⟩ := probes_kind p t f _ h; cases h
  split at h
  · rcases h with h | h | h | h
    · exact absurd h hcl
    · exact absurd h hk
    · exact absurd h hw
    · exact absurd h (ho _ _ (by simp))
  · rcases h with h | h | h | h | h | h | h | h
    · exact absurd h hcl
    · exact absurd h hk
    · exact absurd h hw
    · obtain ⟨_, _, br, hbr, _, hl, _, hc2⟩ := lands_cases f _ h
      rcases hc2 with ⟨_, hx⟩ | ⟨_, _, hx⟩ | ⟨hq, _, d2, ds, hds, hx⟩ | ⟨_, _, _, hx⟩
      · cases hx
      · cases hx
      · simp only [Action.waitDeps.injEq] at hx; subst hx; exact ⟨br, ds, hbr, hds, hl, hq⟩
      · cases hx
    · exact absurd h hc
    · exact absurd h (ho _ _ (by simp))
    · exact absurd h (ho _ _ (by simp))
    · exact absurd h hpr

/-- An action outside `kills`, `waits` and the nudge is in `next` only for a non-active agent, through the matching
piece (used for cleanup and respawn).
-/
theorem plain_mem (p : Params) (t : Nat) (f : AgentFacts) (y : Action)
    (hy : y = .cleanupWorktree ∨ y = .respawnFromHandoff) (h : y ∈ next p t f) :
    f.state ≠ .active ∧ (y ∈ cleans f ∨ y ∈ opt (respawnB f) .respawnFromHandoff) := by
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
    · rcases lands_kind f _ h with ⟨_, h⟩ | ⟨_, _, h⟩ | ⟨_, h⟩ | h <;> rcases hy with hy | hy <;> rw [hy] at h <;> cases h
    · exact .inl h
    · exact .inr h
    · exact absurd h (hnu _)
    · obtain ⟨_, h⟩ := probes_kind p t f _ h; rcases hy with hy | hy <;> rw [hy] at h <;> cases h

/-- **Cleanup safety.** `cleanupWorktree` only when the agent has a worktree, its branch is landed and it has no live
child.
-/
theorem cleanup_sound (p : Params) (t : Nat) (f : AgentFacts) (h : Action.cleanupWorktree ∈ next p t f) :
    f.worktree.isSome ∧ (∃ br, f.branch = some br ∧ br.settled = true) ∧ f.children = [] := by
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

/-- **Respawn safety.** `respawnFromHandoff` only for an agent with no handback, stalled or gone, with no live child,
whose task is on the board and not done, and whose handoff note exists.
-/
theorem respawn_sound (p : Params) (t : Nat) (f : AgentFacts) (h : Action.respawnFromHandoff ∈ next p t f) :
    f.handbackAt = none ∧ (f.state = .stalled ∨ f.state = .gone) ∧ f.children = [] ∧
      (∃ r, f.board = some r ∧ r.done = false) ∧ f.handoff = true := by
  obtain ⟨_, h | h⟩ := plain_mem p t f _ (.inr rfl) h
  · unfold cleans at h; rw [mem_opt] at h; cases h.2
  · rw [mem_opt] at h
    obtain ⟨hc, _⟩ := h
    simp only [respawnB, openTaskB, stuckB, handedBack, Bool.and_eq_true, Bool.not_eq_true',
      Option.isSome_eq_false_iff, Option.isNone_iff_eq_none, Bool.or_eq_true, beq_iff_eq,
      List.isEmpty_iff] at hc
    obtain ⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩ := hc
    refine ⟨h1, h2, h3, ?_, h5⟩
    cases hb : f.board with
    | none => simp [hb] at h4
    | some r => simp [hb] at h4; exact ⟨r, rfl, h4⟩

/-- **Liveness: land.** A non-active agent that handed back, has no live child, and whose branch is ahead of `main`,
not landed, merges cleanly and has no unlanded dependency gets `land` (with its task) or `routeIntegrator`.
-/
theorem live_land (p : Params) (t : Nat) (f : AgentFacts) (β : Branch) (ha : f.state ≠ .active)
    (hb : f.handbackAt.isSome) (hc : f.children = []) (hbr : f.branch = some β) (hah : 0 < β.ahead)
    (hl : β.settled = false) (hlk : β.locked = false) (hm : β.mergesClean = true) (hd : β.deps = []) :
    Action.land β.name f.task ∈ next p t f ∨ Action.routeIntegrator β.name ∈ next p t f := by
  have hhh : (handedBack f && f.children.isEmpty) = true := by simp [handedBack, hb, hc]
  have hcond : (decide (0 < β.ahead) && !β.settled && !β.locked) = true := by simp [hah, hl, hlk]
  cases hq : β.queued
  · have hls : Action.land β.name f.task ∈ lands f := by
      simp [lands, hhh, hbr, hcond, hq, hm, hd]
    exact .inl ((lands_mem p t f _ (.inr ⟨_, _, rfl⟩)).2 ⟨ha, hls⟩)
  · have hls : Action.routeIntegrator β.name ∈ lands f := by
      simp [lands, hhh, hbr, hcond, hq]
    exact .inr ((lands_mem p t f _ (.inl ⟨_, rfl⟩)).2 ⟨ha, hls⟩)

/-! ## Landed from main's history, and the land lock (incidents inc-watch-unlanded-after-land, inc-watch-alert-during-land) -/

/-- **No unlanded alert once the land commit is on `main`.** If a land commit for the task is on `main`
(`onMain(β)`), neither `land` nor `routeIntegrator` is proposed for any branch name, whether or not the
branch still exists or is an ancestor of `main`.
-/
theorem no_unlanded_once_on_main (p : Params) (t : Nat) (f : AgentFacts) (β : Branch)
    (hbr : f.branch = some β) (hm : β.onMain = true) (b k : String) :
    Action.land b k ∉ next p t f ∧ Action.routeIntegrator b ∉ next p t f := by
  constructor
  · intro h
    obtain ⟨_, _, _, br, hbr2, _, _, hs, _⟩ := land_sound p t f b k h
    rw [hbr] at hbr2
    cases hbr2
    simp [Branch.settled, hm] at hs
  · intro h
    obtain ⟨_, _, br, hbr2, _, _, hs, _⟩ := route_sound p t f b h
    rw [hbr] at hbr2
    cases hbr2
    simp [Branch.settled, hm] at hs

/-- **A land in flight is not an unlanded branch.** `land` and `routeIntegrator` are proposed only for a branch the
live land lock does not name and that is not queued: if the branch is in flight (`locked(β)`), neither is
proposed.
-/
theorem no_unlanded_while_locked (p : Params) (t : Nat) (f : AgentFacts) (β : Branch)
    (hbr : f.branch = some β) (hk : β.locked = true) (b k : String) :
    Action.land b k ∉ next p t f ∧ Action.routeIntegrator b ∉ next p t f := by
  constructor
  · intro h
    have h2 := ((lands_mem p t f _ (.inr ⟨b, k, rfl⟩)).1 h).2
    obtain ⟨_, _, br, hbr2, _, _, hl, _⟩ := lands_cases f _ h2
    rw [hbr] at hbr2
    cases hbr2
    rw [hk] at hl
    cases hl
  · intro h
    have h2 := ((lands_mem p t f _ (.inl ⟨b, rfl⟩)).1 h).2
    obtain ⟨_, _, br, hbr2, _, _, hl, _⟩ := lands_cases f _ h2
    rw [hbr] at hbr2
    cases hbr2
    rw [hk] at hl
    cases hl

/-- **A queued land is not an unlanded branch** (task `land-queue`). `land` and `routeIntegrator` are not proposed for a branch that
is a pending entry of the land queue, so `fw watch` raises no `agent.unlanded` for it.
-/
theorem no_unlanded_while_queued (p : Params) (t : Nat) (f : AgentFacts) (β : Branch)
    (hbr : f.branch = some β) (hq : β.inLandQueue = true) (b k : String) :
    Action.land b k ∉ next p t f ∧ Action.routeIntegrator b ∉ next p t f :=
  no_unlanded_while_locked p t f β hbr (by simp [Branch.locked, hq]) b k

/-- **The alert is suppressed exactly when the lock holder is the branch.** For a non-active agent that handed back with
no live child, whose branch is ahead of `main`, not settled, merges cleanly and has no unlanded dependency, the
unlanded alert (`land` or `routeIntegrator`) is absent if and only if the live land lock names that branch.
-/
theorem alert_suppressed_iff_locked (p : Params) (t : Nat) (f : AgentFacts) (β : Branch)
    (ha : f.state ≠ .active) (hb : f.handbackAt.isSome) (hc : f.children = []) (hbr : f.branch = some β)
    (hah : 0 < β.ahead) (hl : β.settled = false) (hm : β.mergesClean = true) (hd : β.deps = []) :
    (Action.land β.name f.task ∉ next p t f ∧ Action.routeIntegrator β.name ∉ next p t f) ↔ β.locked = true := by
  constructor
  · intro h
    cases hk : β.locked with
    | true => rfl
    | false =>
      rcases live_land p t f β ha hb hc hbr hah hl hk hm hd with h1 | h1
      · exact absurd h1 h.1
      · exact absurd h1 h.2
  · intro hk
    exact no_unlanded_while_locked p t f β hbr hk _ _

/-! ## Signals: the handback and exited producers come from the transcripts (`Fw.Obs.Signals`) -/

/-- The signal parameters Next uses: an id is hung after the loop cap. -/
def sigParams (p : Params) : Signals.Params := { hungAfter := p.loopCapMin * msPerMin }

/-- The signal state of an agent at `t` (`none`: no signals). -/
def sigState (p : Params) (now : Nat) (f : AgentFacts) : Option Signals.State :=
  f.signals.map (Signals.classify (sigParams p) now)

/-- Whether a watched producer is over at `t`, judged from the signals of all agents `A`: for a task, some agent's
signals hold an end of it at or before `t`; for an agent, some agent's signals carry that agent id and classify as
finished or done.
-/
def overB (p : Params) (now : Nat) (all : List AgentFacts) : Watch → Bool
  | .task b => all.any fun f =>
      match f.signals with
      | some g => Signals.endedB now g b
      | none => false
  | .agent a => all.any fun f =>
      match f.signals with
      | some g => g.agent == a && Signals.producerDoneB (Signals.classify (sigParams p) now g)
      | none => false

/-- A child with its producer judged from the signals: exited if it was already, or if it has a watch that is over. -/
def resolveChild (p : Params) (now : Nat) (all : List AgentFacts) (c : Child) : Child :=
  { c with producerExited := c.producerExited || match c.watch with
      | some v => overB p now all v
      | none => false }

/-- The facts Next decides on: with signals the handback is the latest one in the transcript at or before `t`
(`none`: none yet), without signals it stays; every child's producer is judged from the signals of all agents `A`.
-/
def resolve (p : Params) (now : Nat) (all : List AgentFacts) (f : AgentFacts) : AgentFacts :=
  { f with
    handbackAt := match f.signals with
      | some g => Signals.lastHandback now g
      | none => f.handbackAt
    children := f.children.map (resolveChild p now all) }

/-- **The handback comes from the signals**: with signals, the resolved handback is the transcript's latest at or before
`t`; without, it is the given one.
-/
theorem resolve_handback (p : Params) (t : Nat) (all : List AgentFacts) (f : AgentFacts) :
    (resolve p t all f).handbackAt =
      match f.signals with
      | some g => Signals.lastHandback t g
      | none => f.handbackAt := rfl

/-- **Resolving only adds exited producers**: a resolved child's producer has exited exactly when it had already, or its
watch is over; every other field of the child is unchanged.
-/
theorem resolveChild_exit (p : Params) (t : Nat) (all : List AgentFacts) (c : Child) :
    ((resolveChild p t all c).producerExited = true ↔
      c.producerExited = true ∨ ∃ v, c.watch = some v ∧ overB p t all v = true) ∧
    { resolveChild p t all c with producerExited := c.producerExited } = c := by
  refine ⟨?_, rfl⟩
  unfold resolveChild
  cases c.watch <;> simp

/-- Replace the `meta.finished` times of an agent's signals by `m`. -/
def withMeta (m : List Nat) (f : AgentFacts) : AgentFacts :=
  { f with signals := f.signals.map fun g => { g with metaFinished := m } }

/-- The watch test never reads `meta.finished`: replacing it in every agent of `A` changes no verdict. -/
theorem overB_withMeta (p : Params) (t : Nat) (all : List AgentFacts) (m : List Nat) (v : Watch) :
    overB p t (all.map (withMeta m)) v = overB p t all v := by
  cases v <;> simp only [overB, List.any_map] <;> congr 1 <;> funext f <;>
    rcases f with ⟨_, _, _, _, _, _, _, _, _, _, _, _, _ | g⟩ <;> rfl

/-- **`meta.finished` is never read by the resolution**: replacing it, in the agent and in every agent of `A`, gives the
same resolved facts up to that replacement.
-/
theorem resolve_withMeta (p : Params) (t : Nat) (all : List AgentFacts) (m : List Nat) (f : AgentFacts) :
    resolve p t (all.map (withMeta m)) (withMeta m f) = withMeta m (resolve p t all f) := by
  have hc : resolveChild p t (all.map (withMeta m)) = resolveChild p t all := by
    funext c; simp only [resolveChild, overB_withMeta]
  rcases f with ⟨_, _, _, _, _, _, _, _, _, _, _, _, _ | g⟩ <;> simp only [resolve, withMeta, hc] <;> rfl

/-- `next` never reads `meta.finished`: replacing the signals' `metaFinished` times leaves its actions unchanged. -/
theorem next_withMeta (p : Params) (t : Nat) (m : List Nat) (f : AgentFacts) :
    next p t (withMeta m f) = next p t f := by
  rcases f with ⟨_, _, _, _, _, _, _, _, _, _, _, _, _ | g⟩ <;> rfl

/-! ## Retention: which agents stay in the snapshot -/

/-- The branch is ahead of `main` and not landed. -/
def openBranchB (f : AgentFacts) : Bool :=
  match f.branch with
  | some b => decide (0 < b.ahead) && !b.settled
  | none => false

/-- The agent's latest CI run is still running. -/
def ciRunningB (f : AgentFacts) : Bool :=
  match f.ci with
  | some c => ciRunning c.run
  | none => false

/-- The structural retention test on the Health state: the agent has not ended, or has an open branch, a worktree, a
live child, a running CI run, or a valid respawn. An ended agent with none of these has no open action
(`keepHealth_of_open_action`).
-/
def keepHealthB (f : AgentFacts) : Bool :=
  !endedS f.state || openBranchB f || f.worktree.isSome || !f.children.isEmpty || ciRunningB f || respawnB f

/-- Whether the agent is live: with signals, its signal state is not quiet (working, waiting, held or hung); without
signals, its Health state has not ended. `meta.finished` plays no part.
-/
def liveB (p : Params) (now : Nat) (f : AgentFacts) : Bool :=
  match f.signals with
  | some g => !Signals.quietB (Signals.classify (sigParams p) now g)
  | none => !endedS f.state

/-- Retention: an agent stays in the snapshot while `next` gives it an action other than `none`, or it is live, or it
has an open branch, a worktree, a live child, a running CI run, or a valid respawn.
-/
def keepB (p : Params) (now : Nat) (f : AgentFacts) : Bool :=
  (next p now f).any (· != .none) || liveB p now f || openBranchB f || f.worktree.isSome ||
    !f.children.isEmpty || ciRunningB f || respawnB f

/-- If a predicate holds for some child, the child list is not empty. -/
theorem any_nonempty (l : List Child) (g : Child → Bool) (h : l.any g = true) : l.isEmpty = false := by
  cases l with
  | nil => simp at h
  | cons _ _ => simp

/-- **Retention is sound.** Every action other than `none` implies the agent is kept: dropping an agent that `keep`
rejects never loses an open action.
-/
theorem keep_of_open_action (p : Params) (t : Nat) (f : AgentFacts) (x : Action) (hx : x ∈ next p t f)
    (hn : x ≠ .none) : keepB p t f = true := by
  have h : (next p t f).any (· != .none) = true := List.any_eq_true.2 ⟨x, hx, by simpa using hn⟩
  simp [keepB, h]

/-- **Retention keeps live agents**: an agent whose signal state is not quiet (or, without signals, whose Health state
has not ended) is kept.
-/
theorem keep_of_live (p : Params) (t : Nat) (f : AgentFacts) (h : liveB p t f = true) : keepB p t f = true := by
  simp [keepB, h]

/-- **Retention never reads `meta.finished`**: replacing the `meta.finished` times, in the agent and in every agent of
`A`, changes neither the next actions nor retention of the resolved facts.
-/
theorem keep_withMeta (p : Params) (t : Nat) (all : List AgentFacts) (m : List Nat) (f : AgentFacts) :
    next p t (resolve p t (all.map (withMeta m)) (withMeta m f)) = next p t (resolve p t all f) ∧
    keepB p t (resolve p t (all.map (withMeta m)) (withMeta m f)) = keepB p t (resolve p t all f) := by
  rw [resolve_withMeta]
  generalize resolve p t all f = g
  refine ⟨next_withMeta p t m g, ?_⟩
  rcases g with ⟨_, _, _, _, _, _, _, _, _, _, _, _, _ | g⟩ <;> rfl

/-- **Structural retention is sound.** Every action other than `none` implies the structural test holds: an ended
agent with an open action has an open branch, a worktree, a live child, a running CI run or a valid respawn.
-/
theorem keepHealth_of_open_action (p : Params) (t : Nat) (f : AgentFacts) (x : Action) (hx : x ∈ next p t f)
    (hn : x ≠ .none) : keepHealthB f = true := by
  by_cases he : endedS f.state = true
  · have hna : ¬ f.state = .active := by
      intro h; simp [endedS, h] at he
    rw [mem_next p t f x hn] at hx
    simp only [hna, ite_false] at hx
    suffices hs : openBranchB f = true ∨ f.worktree.isSome = true ∨ f.children.isEmpty = false ∨
        ciRunningB f = true ∨ respawnB f = true by
      unfold keepHealthB
      rcases hs with h | h | h | h | h <;> simp [h]
    rcases hx with h | h | h | h | h | h | h | h
    · unfold claims at h
      split at h
      · rw [mem_opt] at h; simp [he] at h
      · simp at h
    · rw [mem_kills] at h
      obtain ⟨c, hc, _⟩ := h
      right; right; left
      cases hch : f.children with
      | nil => rw [hch] at hc; simp at hc
      | cons _ _ => simp
    · unfold waits at h
      split at h
      · rename_i c hc
        rw [mem_opt] at h
        right; right; right; left
        simp [ciRunningB, hc, h.1]
      · simp at h
    · obtain ⟨_, _, br, hbr, ha, hl, _, _⟩ := lands_cases f _ h
      left
      simp [openBranchB, hbr, ha, hl]
    · unfold cleans at h
      rw [mem_opt] at h
      right; left
      have := h.1
      simp only [Bool.and_eq_true] at this
      exact this.1.1.1
    · rw [mem_opt] at h
      right; right; right; right; exact h.1
    · rw [mem_opt] at h
      have := h.1
      simp [nudgeB] at this
      simp [endedS] at he
      rcases he with he | he <;> simp [he] at this
    · simp only [probes, List.mem_append, mem_opt] at h
      rcases h with ((⟨h1, _⟩ | ⟨h1, _⟩) | ⟨h1, _⟩) | ⟨h1, _⟩
      · simp only [Bool.and_eq_true] at h1
        right; right; left; exact any_nonempty _ _ h1.2
      · right; right; left; exact any_nonempty _ _ h1
      · right; right; left; exact any_nonempty _ _ h1
      · right; left
        unfold lockDeadB at h1
        split at h1
        · rename_i w hw; simp [hw]
        · simp at h1
  · have : endedS f.state = false := by simpa using he
    simp [keepHealthB, this]

/-- A child gets `killOrphan` when it gets a kill. -/
theorem kill_of_killB (p : Params) (t : Nat) (f : AgentFacts) (c : Child) (hc : c ∈ f.children)
    (hk : killB p t f c = true) : Action.killOrphan c.pid ∈ next p t f :=
  (kill_mem p t f c.pid).2 ((mem_kills p t f _).2 ⟨c, hc, hk, rfl⟩)

/-- Sole from its proposition. -/
theorem soleB_of (f : AgentFacts) (c : Child) (h : ∀ d ∈ f.children, d.pid = c.pid → waitsK d.kind = true) :
    soleB f c = true := by
  simp only [soleB, List.all_eq_true, Bool.or_eq_true, bne_iff_ne, ne_eq]
  intro d hd
  by_cases e : d.pid = c.pid
  · exact .inr (h d hd e)
  · exact .inl e

/-- **Liveness: kill.** A non-active agent's waiting child (sleep loop or stdin wait) in the session's tree (not the session nor its own
ancestor), whose pid no child of a non-waiting kind shares, and that runs past the loop cap, gets `killOrphan`.
-/
theorem live_kill (p : Params) (t : Nat) (f : AgentFacts) (c : Child) (ha : f.state ≠ .active)
    (hc : c ∈ f.children) (hk : waitsK c.kind = true) (hs : f.session ∈ c.chain) (hne : c.pid ≠ f.session)
    (hnc : c.pid ∉ c.chain) (hsole : ∀ d ∈ f.children, d.pid = c.pid → waitsK d.kind = true)
    (hold : p.loopCapMin * msPerMin < t - c.startedAt) : Action.killOrphan c.pid ∈ next p t f :=
  kill_of_killB p t f c hc ((killB_iff p t f c).2
    ⟨hk, hs, hne, hnc, soleB_of f c hsole, .inr (.inr (by simpa [oldB] using hold)), .inl ha⟩)

/-- **Liveness: kill for an active agent.** An active agent's waiting child in the session's tree (not the session
nor its own ancestor), whose pid no child of a non-waiting kind shares, and that watches a file whose producer has exited,
gets `killOrphan`.
-/
theorem live_kill_active (p : Params) (t : Nat) (f : AgentFacts) (c : Child) (_ha : f.state = .active)
    (hc : c ∈ f.children) (hk : waitsK c.kind = true) (hs : f.session ∈ c.chain) (hne : c.pid ≠ f.session)
    (hnc : c.pid ∉ c.chain) (hsole : ∀ d ∈ f.children, d.pid = c.pid → waitsK d.kind = true)
    (hw : c.watchedAt ≠ none) (hx : c.producerExited = true) : Action.killOrphan c.pid ∈ next p t f := by
  have hd : deadB p t c = true := (deadB_iff p t c).2 (.inl ⟨hw, hx⟩)
  exact kill_of_killB p t f c hc ((killB_iff p t f c).2
    ⟨hk, hs, hne, hnc, soleB_of f c hsole, .inr (.inl hd), .inr hd⟩)

/-- Dead watches stay dead as time passes. -/
theorem deadB_mono (p : Params) (t t' : Nat) (c : Child) (htt : t ≤ t') (h : deadB p t c = true) :
    deadB p t' c = true := by
  rw [deadB_iff] at h ⊢
  rcases h with h | ⟨m, hm, hs⟩
  · exact .inl h
  · exact .inr ⟨m, hm, by omega⟩

/-- **Monotonicity in time.** With the facts unchanged, a pid flagged for `killOrphan` at time `t` stays flagged at
every later time `t' ≥ t`.
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

/-- Example time: `t_0 = 1760000000000` ms. -/
def t0 : Nat := 1760000000000

/-- `m` minutes before `t0`. -/
def ago (m : Nat) : Nat := t0 - m * msPerMin

/-- An example agent for the guards: id and task `k`, state `s`, session pid 100, nothing else observed. -/
def ex (k : String) (s : State) : AgentFacts := { id := k, task := k, state := s, session := 100 }

-- port-nav: handed back, branch 3 ahead, queued for the integrator → route; not queued → land
#guard next {} t0
    { ex "port-nav" .done with
      handbackAt := some (ago 90), branch := some { name := "wt-a", ahead := 3, landed := false, queued := true }, worktree := some {} }
  == [.routeIntegrator "wt-a"]
#guard next {} t0
    { ex "port-nav" .done with
      handbackAt := some (ago 90), branch := some { name := "wt-a", ahead := 3, landed := false, queued := false }, worktree := some {} }
  == [.land "wt-a" "port-nav"]
-- ghb-runner: handed back, landed, a sleep loop under the session on a stale file → kill only (cleanup next time)
#guard next {} t0
    { ex "ghb-runner" .done with
      handbackAt := some (ago 25), branch := some { name := "b", ahead := 0, landed := true, queued := false }, worktree := some {},
      children := [{ pid := 555, chain := [100, 1], kind := .sleepLoop, startedAt := ago 22,
                     watchedAt := some (ago 20) }] }
  == [.killOrphan 555]
#guard next {} t0
    { ex "ghb-runner" .done with
      handbackAt := some (ago 25), branch := some { name := "b", ahead := 0, landed := true, queued := false }, worktree := some {} }
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
#guard next {} t0 { ex "g" .gone with board := some { id := "g", done := false }, handoff := true } == [.respawnFromHandoff]
-- respawn needs an open task and a handoff note
#guard next {} t0 { ex "g" .gone with board := some { id := "g", done := false } } == [.none]
#guard next {} t0 { ex "g" .gone with board := some { id := "g", done := true }, handoff := true } == [.none]
#guard next {} t0 { ex "g" .gone with handoff := true } == [.none]
-- land needs a clean merge and no unlanded dependency
#guard next {} t0
    { ex "m" .done with handbackAt := some (ago 9), branch := some { name := "wt-m", ahead := 2, landed := false, queued := false, mergesClean := false } }
  == [.investigate .conflict]
#guard next {} t0
    { ex "m" .done with handbackAt := some (ago 9), branch := some { name := "wt-m", ahead := 2, landed := false, queued := false, deps := ["wt-dep", "x"] } }
  == [.waitDeps "wt-dep"]
-- nothing to do
#guard next {} t0 (ex "e" .idle) == [.none]
-- a build child is never killed; a stuck agent held by it is investigated
#guard next {} t0
    { ex "f" .stalled with children := [{ pid := 800, chain := [100, 1], kind := .build, startedAt := ago 99 }] }
  == [.investigate .heldByChild]
-- retention: an ended agent with an unlanded branch ahead of main is kept; one with nothing open is dropped
#guard keepB {} t0 { ex "port-nav" .done with handbackAt := some (ago 120), branch := some { name := "wt-port-nav", ahead := 3, landed := false, queued := true } }
#guard !keepB {} t0 { ex "old" .done with handbackAt := some (ago 120), branch := some { name := "wt-old", ahead := 0, landed := true, queued := false } }
#guard keepB {} t0 { ex "wt" .done with worktree := some {} }
#guard !keepB {} t0 { ex "g" .gone with board := some { id := "g", done := true }, handoff := true }
#guard keepB {} t0 { ex "g2" .gone with board := some { id := "g2", done := false }, handoff := true }
#guard keepB {} t0 (ex "idle" .idle)

/-- Example signals in the shape of port-nav (incident inc-silent-stdin-bg): turn from 120 to 60 min ago, handback 60
min ago, background id `bh` launched `a` min ago with no end and a live process reading stdin.
-/
def pnSig (a : Nat) : Signals.Facts :=
  { agent := "pn", launched := [⟨"bh", ago a⟩], bounds := [⟨ago 120, true⟩, ⟨ago 60, false⟩], handbacks := [ago 60],
    procs := [⟨"bh", 10476, .stdin⟩], metaFinished := [ago 60] }

/-- Example port-nav agent: Health state `s`, no handback in the raw facts, the signals `pn(a)`, and the
`cat > file` child (pid 10476, stdin wait) started `a` min ago.
-/
def pnAgent (a : Nat) (s : State) : AgentFacts :=
  { ex "port-nav" s with
    signals := some (pnSig a),
    children := [{ pid := 10476, chain := [100, 1], kind := .stdinWait, startedAt := ago a }] }

-- port-nav: the handback comes from the transcript, so the stdin wait under it is an orphan → kill
#guard (resolve {} t0 [] (pnAgent 20 .idle)).handbackAt == some (ago 60)
#guard next {} t0 (resolve {} t0 [] (pnAgent 20 .idle)) == [.killOrphan 10476]
-- without the signals the handback is unseen and the 20-minute-old stdin wait is under the cap → no kill
#guard next {} t0 { pnAgent 20 .idle with signals := none } == [.none]
-- the signal state: held for 20 minutes, hung after the 30-minute cap
#guard sigState {} t0 (pnAgent 20 .idle) == some (.handedBackHeld ["bh"])
#guard sigState {} t0 (pnAgent 31 .idle) == some (.hung "bh")
-- retention follows the signals, not the Health state: held is kept even when Health says done …
#guard keepB {} t0 { resolve {} t0 [] (pnAgent 20 .done) with children := [] }

/-- Example signals of a finished agent with signal id `a`: turn from 9 to 5 min ago, the lead's 'finished' notice 5 min
ago.
-/
def finSig (a : String) : Signals.Facts :=
  { agent := a, bounds := [⟨ago 9, true⟩, ⟨ago 5, false⟩], notices := [⟨ago 5, true⟩] }

/-- Example sleep-loop child (pid `q`, session 100) started 8 min ago on a file written 1 min ago, watching `v`. -/
def loopOn (q : Nat) (v : Watch) : Child :=
  { pid := q, chain := [100, 1], kind := .sleepLoop, startedAt := ago 8, watchedAt := some (ago 1), watch := some v }

-- … and a finished agent (its 'finished' notice seen) is dropped even when Health says idle
#guard !keepB {} t0 { ex "x" .idle with signals := some (finSig "x") }
-- a loop watching agent ax's transcript: ax finished → its producer exited → kill (the watcher is active)
#guard
  let x : AgentFacts := { ex "x" .done with signals := some (finSig "ax") }
  let w : AgentFacts := { ex "w" .active with children := [loopOn 900 (.agent "ax")] }
  next {} t0 (resolve {} t0 [x, w] w) == [.killOrphan 900, .nudgeHandoff] && next {} t0 w == [.none]
-- the same loop on a task id: its producer exits once some agent's signals hold an end of it
#guard
  let o : AgentFacts := { ex "o" .idle with
    signals := some { agent := "ao", launched := [⟨"b9", ago 9⟩], ends := [⟨"b9", ago 2, .exited 0⟩] } }
  (resolveChild {} t0 [o] (loopOn 901 (.task "b9"))).producerExited &&
    !(resolveChild {} (ago 3) [o] (loopOn 901 (.task "b9"))).producerExited


/-! ## Timing alerts: the slow steps that raise `timing.slow` (`Fw.Obs.Timing`) -/

/-- The work part of an alert subject: ` [k=v,…]` over the work dimensions, empty when there are none. -/
def workSuffix (work : List (String × String)) : String :=
  if work.isEmpty then "" else " [" ++ ",".intercalate (work.map fun (k, v) => k ++ "=" ++ v) ++ "]"

/-- An alert subject: `<tool>/<step>`, then `#<kind>` when the run has a kind, then the `workSuffix`. -/
def subject (tool step kind : String) (work : List (String × String)) : String :=
  tool ++ "/" ++ step ++ (if kind == "" then "" else "#" ++ kind) ++ workSuffix work

/-- The alert subject of a sample verdict. -/
def stepName (v : Timing.SampleVerdict) : String := subject v.tool v.step v.kind v.work

#guard subject "lean" "check.sh" "" [] == "lean/check.sh" && subject "w" "s" "k1" [] == "w/s#k1"
#guard subject "fw" "polish commit" "" [("checks", "lakeBuild")] == "fw/polish commit [checks=lakeBuild]"
#guard subject "lean/check" "parallel group" "" [("checks", "light"), ("width", "1")] ==
  "lean/check/parallel group [checks=light,width=1]"

/-- Two sample verdicts are of the same history (same tool, step, host, run kind and work dimensions). -/
def sameKey (v w : Timing.SampleVerdict) : Bool :=
  v.tool == w.tool && v.step == w.step && v.host == w.host && v.kind == w.kind && v.work == w.work

theorem sameKey_work_ne (v w : Timing.SampleVerdict) (h : v.work ≠ w.work) : sameKey v w = false := by
  simp [sameKey, h]

/-- Some later sample verdict of the list is of the same history as `v`. -/
def laterSame (v : Timing.SampleVerdict) (rest : List Timing.Verdict) : Bool :=
  rest.any (fun w => match w with
    | .sample w => sameKey v w
    | .structural _ => false)

/-- The previous sample of the history of `v` (`prev` lists earlier sample verdicts, newest first) was `slow`; false when
there is none.
-/
def prevSlow (v : Timing.SampleVerdict) (prev : List Timing.SampleVerdict) : Bool :=
  match prev.find? (sameKey v) with
  | some u => u.code == .slow
  | none => false

/-- The slow steps that are alerts, given the earlier sample verdicts `prev` (newest first). A sample verdict is an alert
when its code is `slow`, no later sample of the same history exists (a newer sample replaces it), and the previous sample
of its history was not slow (the alert is the ok to slow transition, so a step that stays slow does not re-alert).
Structural verdicts are never alerts. The subjects are in verdict order, with repeats.
-/
def slowLatestFrom (prev : List Timing.SampleVerdict) : List Timing.Verdict → List String
  | [] => []
  | .sample v :: rest =>
      (if v.code == .slow && !laterSame v rest && !prevSlow v prev then [stepName v] else []) ++
        slowLatestFrom (v :: prev) rest
  | .structural _ :: rest => slowLatestFrom prev rest

def slowLatest (vs : List Timing.Verdict) : List String := slowLatestFrom [] vs

def alertsFrom (prev : List Timing.SampleVerdict) : List Timing.Verdict → List Timing.SampleVerdict
  | [] => []
  | .sample v :: rest =>
      (if v.code == .slow && !laterSame v rest && !prevSlow v prev then [v] else []) ++ alertsFrom (v :: prev) rest
  | .structural _ :: rest => alertsFrom prev rest

theorem alertsFrom_map (prev : List Timing.SampleVerdict) (vs : List Timing.Verdict) :
    (alertsFrom prev vs).map stepName = slowLatestFrom prev vs := by
  induction vs generalizing prev with
  | nil => rfl
  | cons x rest ih =>
    cases x with
    | structural w => exact ih prev
    | sample v =>
      simp only [alertsFrom, slowLatestFrom, List.map_append, ih (v :: prev)]
      split <;> simp_all

/-- Remove repeats, keeping the last occurrence of each. -/
def dedupL : List String → List String
  | [] => []
  | x :: xs => if x ∈ xs then dedupL xs else x :: dedupL xs

/-- Dedup keeps exactly the elements. -/
theorem mem_dedupL (xs : List String) (y : String) : y ∈ dedupL xs ↔ y ∈ xs := by
  induction xs with
  | nil => simp [dedupL]
  | cons x xs ih =>
    unfold dedupL
    split
    · rename_i hx
      rw [ih]
      constructor
      · intro h; exact List.mem_cons_of_mem _ h
      · intro h
        rcases List.mem_cons.1 h with rfl | h
        · exact hx
        · exact h
    · simp [ih]

/-- Dedup has no repeats. -/
theorem nodup_dedupL (xs : List String) : (dedupL xs).Nodup := by
  induction xs with
  | nil => simp [dedupL]
  | cons x xs ih =>
    unfold dedupL
    split
    · exact ih
    · rename_i hx
      rw [List.nodup_cons]
      exact ⟨fun h => hx ((mem_dedupL xs x).1 h), ih⟩

/-- The alert subjects without repeats (a step slow on both hosts alerts once; de-duplication across watch polls is the
watch's set difference of `code|subject` keys, which equal subjects give equal keys).
-/
def slowSteps (vs : List Timing.Verdict) : List String := dedupL (slowLatest vs)

/-- **Soundness: an alert is a slow verdict.** Every subject of `slowLatestFrom` is the name of a sample verdict of the
list whose code is `slow`, whatever the earlier verdicts.
-/
theorem slowLatestFrom_sound (prev : List Timing.SampleVerdict) (vs : List Timing.Verdict) (s : String)
    (h : s ∈ slowLatestFrom prev vs) :
    ∃ v, Timing.Verdict.sample v ∈ vs ∧ v.code = .slow ∧ stepName v = s := by
  induction vs generalizing prev with
  | nil => simp [slowLatestFrom] at h
  | cons x rest ih =>
    cases x with
    | structural w =>
      simp only [slowLatestFrom] at h
      obtain ⟨v, hv, hc, he⟩ := ih prev h
      exact ⟨v, List.mem_cons_of_mem _ hv, hc, he⟩
    | sample v =>
      simp only [slowLatestFrom, List.mem_append] at h
      rcases h with h | h
      · split at h
        · rename_i hc
          simp only [List.mem_singleton] at h
          simp only [Bool.and_eq_true, beq_iff_eq] at hc
          exact ⟨v, List.mem_cons_self .., hc.1.1, h.symm⟩
        · simp at h
      · obtain ⟨w, hw, hc, he⟩ := ih (v :: prev) h
        exact ⟨w, List.mem_cons_of_mem _ hw, hc, he⟩

/-- **Soundness: an alert is a slow verdict.** Every subject of `slowLatest` is the name of a sample verdict of the list
whose code is `slow`.
-/
theorem slowLatest_sound (vs : List Timing.Verdict) (s : String) (h : s ∈ slowLatest vs) :
    ∃ v, Timing.Verdict.sample v ∈ vs ∧ v.code = .slow ∧ stepName v = s :=
  slowLatestFrom_sound [] vs s h

/-- **No alert without a slow verdict.** If no sample verdict is `slow`, there is no alert. -/
theorem slowSteps_nil_of_no_slow (vs : List Timing.Verdict)
    (h : ∀ v, Timing.Verdict.sample v ∈ vs → v.code ≠ .slow) : slowSteps vs = [] := by
  unfold slowSteps
  have : slowLatest vs = [] := by
    cases hl : slowLatest vs with
    | nil => rfl
    | cons s ss =>
      obtain ⟨v, hv, hc, _⟩ := slowLatest_sound vs s (by rw [hl]; exact List.mem_cons_self ..)
      exact absurd hc (h v hv)
  rw [this]; rfl

theorem slowSteps_uncontended (p : Timing.Params) (ss : List Timing.Sample) (s : String)
    (h : s ∈ slowSteps (Timing.timingVerdicts p ss)) :
    ∃ x ∈ ss, Timing.contended p x = false ∧ subject x.tool x.step x.kind x.work = s := by
  obtain ⟨v, hv, hc, hn⟩ := slowLatest_sound _ s ((mem_dedupL _ s).1 h)
  obtain ⟨i, hi, rfl⟩ := Timing.mem_sample p ss v hv
  simp only [stepName, Timing.judgeQ_tool, Timing.judgeQ_step, Timing.judgeQ_kind, Timing.judgeQ_work] at hn
  refine ⟨ss[i], List.getElem_mem hi, ?_, hn⟩
  cases hq : Timing.contended p ss[i]
  · rfl
  · exact absurd hc (Timing.contended_not_slow_Q p _ i _ hq)

/-- A later sample of the same history is found by `laterSame`. -/
theorem laterSame_of_mem (v : Timing.SampleVerdict) (rest : List Timing.Verdict)
    (h : ∃ w, Timing.Verdict.sample w ∈ rest ∧ sameKey v w = true) : laterSame v rest = true := by
  obtain ⟨w, hw, hs⟩ := h
  unfold laterSame
  rw [List.any_eq_true]; exact ⟨.sample w, hw, hs⟩

/-- No later sample of the same history makes `laterSame` false. -/
theorem laterSame_false (v : Timing.SampleVerdict) (rest : List Timing.Verdict)
    (hl : ∀ w, Timing.Verdict.sample w ∈ rest → sameKey v w = false) : laterSame v rest = false := by
  unfold laterSame
  rw [Bool.eq_false_iff]
  intro hh
  rw [List.any_eq_true] at hh
  obtain ⟨x, hx, hxs⟩ := hh
  cases x with
  | structural _ => simp at hxs
  | sample w => simp only at hxs; rw [hl w hx] at hxs; cases hxs

/-- **A newer sample replaces the alert.** A slow sample followed by a later sample of the same history is no alert. -/
theorem slowLatestFrom_superseded (prev : List Timing.SampleVerdict) (v : Timing.SampleVerdict)
    (rest : List Timing.Verdict) (h : ∃ w, Timing.Verdict.sample w ∈ rest ∧ sameKey v w = true) :
    slowLatestFrom prev (.sample v :: rest) = slowLatestFrom (v :: prev) rest := by
  simp [slowLatestFrom, laterSame_of_mem v rest h]

/-- **A step that stays slow does not re-alert.** A sample whose previous sample of the same history was slow is no alert. -/
theorem slowLatestFrom_steady (prev : List Timing.SampleVerdict) (v : Timing.SampleVerdict)
    (rest : List Timing.Verdict) (h : prevSlow v prev = true) :
    slowLatestFrom prev (.sample v :: rest) = slowLatestFrom (v :: prev) rest := by
  simp [slowLatestFrom, h]

/-- **The ok to slow transition is an alert.** A slow sample with no later sample of its history, whose previous sample of
the history was not slow, is an alert.
-/
theorem slowLatestFrom_transition (prev : List Timing.SampleVerdict) (v : Timing.SampleVerdict)
    (rest : List Timing.Verdict) (hc : v.code = .slow)
    (hl : ∀ w, Timing.Verdict.sample w ∈ rest → sameKey v w = false) (hp : prevSlow v prev = false) :
    stepName v ∈ slowLatestFrom prev (.sample v :: rest) := by
  simp [slowLatestFrom, hc, laterSame_false v rest hl, hp]

/-- **A newer sample replaces the alert.** A slow sample followed by a later sample of the same history is no alert (from
the start of the list).
-/
theorem slowLatest_superseded (v : Timing.SampleVerdict) (rest : List Timing.Verdict)
    (h : ∃ w, Timing.Verdict.sample w ∈ rest ∧ sameKey v w = true) :
    slowLatest (.sample v :: rest) = slowLatestFrom [v] rest :=
  slowLatestFrom_superseded [] v rest h

/-- **The first slow sample of a history is an alert.** A slow sample with no earlier and no later sample of its history is
an alert.
-/
theorem slowSteps_latest (v : Timing.SampleVerdict) (rest : List Timing.Verdict) (hc : v.code = .slow)
    (hl : ∀ w, Timing.Verdict.sample w ∈ rest → sameKey v w = false) :
    stepName v ∈ slowSteps (.sample v :: rest) := by
  unfold slowSteps slowLatest
  rw [mem_dedupL]
  exact slowLatestFrom_transition [] v rest hc hl rfl

/-- **Work dimensions separate alerts.** A slow sample is an alert when every later sample of its tool, step, host and
kind has other work dimensions: an ok `light` polish commit after a slow `lakeBuild` one does not replace it.
-/
theorem slowSteps_other_work (v : Timing.SampleVerdict) (rest : List Timing.Verdict) (hc : v.code = .slow)
    (hw : ∀ w, Timing.Verdict.sample w ∈ rest → w.work ≠ v.work) :
    stepName v ∈ slowSteps (.sample v :: rest) :=
  slowSteps_latest v rest hc fun w hm => sameKey_work_ne v w fun e => hw w hm e.symm

/-- The previous sample of another work class does not count: `prevSlow` is false when every earlier sample has other
work dimensions.
-/
theorem prevSlow_other_work (v : Timing.SampleVerdict) (prev : List Timing.SampleVerdict)
    (hw : ∀ u ∈ prev, u.work ≠ v.work) : prevSlow v prev = false := by
  unfold prevSlow
  rw [List.find?_eq_none.2 fun u hu => by simp [sameKey_work_ne v u fun e => hw u hu e.symm]]

theorem slowSteps_no_bucket (p : Timing.Params) (ss : List Timing.Sample) (s : String)
    (h : s ∈ slowSteps (Timing.timingVerdicts p ss)) :
    ∃ v, Timing.Verdict.sample v ∈ Timing.timingVerdicts p ss ∧ stepName v = s ∧
      ¬ (v.tool = "fw" ∧ ∃ k ∈ Timing.slotKinds, v.step ∈ Timing.bucketSteps k) := by
  obtain ⟨v, hv, hc, hn⟩ := slowLatest_sound _ s ((mem_dedupL _ s).1 h)
  exact ⟨v, hv, hn, Timing.no_slow_bucket p ss v hv hc⟩

/-- **The alert list has no repeats.** -/
theorem slowSteps_nodup (vs : List Timing.Verdict) : (slowSteps vs).Nodup := by
  exact nodup_dedupL _

theorem slowSteps_of_timing (p : Timing.Params) (ss : List Timing.Sample) (s : String)
    (h : s ∈ slowSteps (Timing.timingVerdicts p ss)) :
    ∃ v, Timing.Verdict.sample v ∈ Timing.timingVerdicts p ss ∧ v.code = .slow ∧ stepName v = s := by
  unfold slowSteps at h
  rw [mem_dedupL] at h
  exact slowLatest_sound _ s h

private def tv (tool step : String) (code : Timing.Code) : Timing.Verdict :=
  .sample { idx := 0, tool, step, host := .ci, durMs := 1, code, n := 5, baseline := 1, budgetMs := 1 }

#guard slowSteps [tv "lean" "check.sh" .slow] == ["lean/check.sh"]
-- a later ok sample of the step replaces the slow one
#guard slowSteps [tv "lean" "check.sh" .slow, tv "lean" "check.sh" .ok] == []
-- other steps do not
#guard slowSteps [tv "lean" "check.sh" .slow, tv "lean" "lake build" .ok] == ["lean/check.sh"]
-- contended and noBaseline are not alerts
#guard slowSteps [tv "a" "b" .contended, tv "a" "c" .noBaseline] == []
-- ok then slow alerts; slow then slow does not re-alert (the transition was the alert); slow, ok, slow alerts again
#guard slowSteps [tv "a" "b" .ok, tv "a" "b" .slow] == ["a/b"]
#guard slowSteps [tv "a" "b" .ok, tv "a" "b" .slow, tv "a" "b" .slow] == []
#guard slowSteps [tv "a" "b" .slow, tv "a" "b" .ok, tv "a" "b" .slow] == ["a/b"]
-- contended between two slows is not slow: the next slow is a transition
#guard slowSteps [tv "a" "b" .slow, tv "a" "b" .contended, tv "a" "b" .slow] == ["a/b"]
-- the run kind separates histories: a slow of kind k1 after a slow of kind k2 is a first slow, named with its kind
private def tvk (tool step kind : String) (code : Timing.Code) : Timing.Verdict :=
  match tv tool step code with | .sample v => .sample { v with kind } | x => x
#guard slowSteps [tvk "w" "s" "k2" .slow, tvk "w" "s" "k1" .slow] == ["w/s#k2", "w/s#k1"]
#guard slowSteps [tvk "w" "s" "k2" .slow, tvk "w" "s" "k1" .ok] == ["w/s#k2"]
#guard slowSteps [tvk "w" "s" "k1" .ok, tvk "w" "s" "k2" .slow, tvk "w" "s" "k1" .slow] == ["w/s#k2", "w/s#k1"]
-- the same step slow on two hosts alerts once
#guard slowSteps [tv "a" "b" .slow, (match tv "a" "b" .slow with | .sample v => .sample { v with host := .«local» } | x => x)] == ["a/b"]
-- work dimensions separate histories: an ok light polish commit after a slow lakeBuild one does not replace it
private def tvw (step : String) (work : List (String × String)) (code : Timing.Code) : Timing.Verdict :=
  match tv "fw" step code with | .sample v => .sample { v with work } | x => x
#guard slowSteps [tvw "polish commit" [("checks", "lakeBuild")] .slow, tvw "polish commit" [("checks", "light")] .ok] ==
  ["fw/polish commit [checks=lakeBuild]"]
#guard slowSteps [tvw "polish commit" [("checks", "lakeBuild")] .slow, tvw "polish commit" [("checks", "lakeBuild")] .ok] == []
#guard slowSteps [tvw "polish commit" [("checks", "light")] .slow, tvw "polish commit" [("checks", "lakeBuild")] .slow] ==
  ["fw/polish commit [checks=light]", "fw/polish commit [checks=lakeBuild]"]
#guard slowSteps [tvw "slot run check" [] .mixed] == []

-- landed from main's history; the land lock
private def lbr (b : Branch) : AgentFacts :=
  { id := "t", task := "t", state := .done, session := 1, handbackAt := some 5, branch := some b }
#guard (lands (lbr { name := "w", ahead := 3, landed := false, queued := false })) == [.land "w" "t"]
-- the branch is gone from git but a land commit for the task is on main
#guard (lands (lbr { name := "w", ahead := 3, landed := false, queued := false, onMain := true })) == []
-- the live land lock names this branch / another branch
#guard (lands (lbr { name := "w", ahead := 3, landed := false, queued := false, landLock := some "w" })) == []
#guard (lands (lbr { name := "w", ahead := 3, landed := false, queued := false, landLock := some "x" })) == [.land "w" "t"]

end Fw.Obs.Next

namespace Fw.Wire.Obs.TimingSlow
open Lean
open Fw.Obs.Timing
open Fw.Wire.Obs.Timing

/-- The `obs.slow` cases: the alert subjects keyed on work dimensions, and no alert for an overflow bucket. -/
def cases : List (String × Params × List Sample) :=
  [("polish commit by checks class: the 38.2 s lakeBuild commit alerts under its class", {}, polishRun),
   ("polish commit without a checks class: the same durations alert under the bare step", {},
      polishRun.map fun s => { s with work := [] }),
   ("a later ok light polish commit does not replace the lakeBuild alert", {}, polishRun ++ [polish ["nodeCheck"] 2 600]),
   ("a later ok lakeBuild polish commit replaces it", {}, polishRun ++ [polish ["lakeBuild"] 2 9000]),
   ("slot run overflow bucket: mixed, no alert", {}, bucketRun "slot run check"),
   ("slot run with a command key: the same durations alert", {}, bucketRun "slot run check sh lean/scripts/check.sh"),
   ("slot width: a 200 s width-1 group alerts under its width", {}, groupMix ++ [group (some 1) 2 200000])]

def slowOf (p : Params) (ss : List Sample) : List String := Fw.Obs.Next.slowSteps (verdictsOf p ss)

#guard cases.map (fun (_, p, ss) => slowOf p ss) ==
  [["fw/polish commit [checks=lakeBuild]"], ["fw/polish commit"], ["fw/polish commit [checks=lakeBuild]"], [], [],
   ["fw/slot run check sh lean/scripts/check.sh"], ["lean/check/parallel group [width=1]"]]

def caseJson (n : String) (p : Params) (ss : List Sample) : Json :=
  Json.mkObj [("name", .str n),
    ("request", Json.mkObj [("op", "obs.slow"), ("params", paramsJson p), ("samples", .arr (ss.map sampleJson).toArray)]),
    ("response", Json.mkObj [("slow", toJson (slowOf p ss))])]

def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, p, ss) => (caseJson n p ss).compress ++ "\n")

def goldenPath : System.FilePath := "../packages/contracts/golden/obs/timing-slow.jsonl"

def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Wire.Obs.TimingSlow
