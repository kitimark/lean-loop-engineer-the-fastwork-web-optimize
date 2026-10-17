import Fw.Plan.Graph
/-!
# The plan reducer: `task.*` and `milestone.define` commands, derived task states, the board plan

The console's plan part (work-graph task `lean-plan`). The state stores only definitions and two
observed facts per task (evidence, claiming agent); every task state, blocker list, milestone count,
the critical path and the parallel-safe groups are derived (`view`), never stored.

* `check` refuses a `task.define` that names an undefined dep or would close a dependency cycle,
  a `task.drop` of a done task or of a task an undone task depends on, a `task.claim` / `task.done`
  of an unknown or done task. `exec` applies an accepted command.
* `run_inv`: every reachable state has unique task ids and an acyclic dependency graph.
* `exec_isDone`: done is monotone. `tstate_ready_iff`, `tstate_blocked`, `ready_indep`: the derived
  states. `lane_device_iff`, `ready_split`: a task's lane (`device` iff it needs `"device"`) splits
  the ready set into agent work and device work. `groups_pairwise`, `groups_perm`: the parallel-safe
  groups of the agent-ready tasks. `view_criticalPath`: the critical path is a longest chain of
  undone, uncut tasks.
* Cut tasks (`cut` flag of the definition): state `cut` unless done (`tstate_cut_iff`), never ready
  (`cut_not_ready`, `readyRows_not_cut`), never on the critical path (`view_criticalPath_not_cut`),
  not counted in milestone totals (`msView_kept`).
* Late definitions: a `task.define` carries the live agent names (a fact the console adds); a live
  agent named like the task claims it (`upsert_live`, `step_define_live`).
-/
namespace Fw.Plan

/-- A `task.define` payload: the task's definition, optional evidence that it is already done, the
`cut` flag (the task was cut from the plan; default false), and one observed fact the console adds on
receipt: `live`, the names of the agents alive at that moment (not gone, not done; default empty).

$$d = (\mathit{task}, \mathit{title}, \mathit{stream}, \mathit{milestone}_\bot, \mathit{deps}, \mathit{owner}, \mathit{writes}, \mathit{devices}, \mathit{needs}, \mathit{evidence}_\bot, \mathit{cut}, \mathit{live})$$
-/
structure Def where
  task      : String
  title     : String
  stream    : String
  milestone : Option String
  deps      : List String
  owner     : String
  writes    : List String
  devices   : List String
  needs     : List String
  evidence  : Option String
  cut       : Bool := false
  live      : List String := []
deriving Repr, DecidableEq

/-- The plan commands.

$$\mathrm{Cmd} = \mathrm{define}(d) \mid \mathrm{drop}(\mathit{task}) \mid \mathrm{claim}(\mathit{task}, \mathit{agent}) \mid \mathrm{done}(\mathit{task}, \mathit{evidence}) \mid \mathrm{milestone}(\mathit{id}, \mathit{title})$$
-/
inductive Cmd where
  | define (d : Def)
  | drop (task : String)
  | claim (task agent : String)
  | done (task evidence : String)
  | milestone (id title : String)
deriving Repr, DecidableEq

/-- The plan command types.

$$\mathrm{CmdType} = \{\mathrm{define}, \mathrm{drop}, \mathrm{claim}, \mathrm{done}, \mathrm{milestone}\}$$
-/
inductive CmdType where
  | define | drop | claim | done | milestone
deriving Repr, DecidableEq

/-- The wire name of a plan command type.

$$\operatorname{name}(\mathrm{define}) = \texttt{"task.define"},\ \operatorname{name}(\mathrm{drop}) = \texttt{"task.drop"},\ \operatorname{name}(\mathrm{claim}) = \texttt{"task.claim"},\ \operatorname{name}(\mathrm{done}) = \texttt{"task.done"},\ \operatorname{name}(\mathrm{milestone}) = \texttt{"milestone.define"}$$
-/
def CmdType.name : CmdType → String
  | .define => "task.define" | .drop => "task.drop" | .claim => "task.claim"
  | .done => "task.done" | .milestone => "milestone.define"

/-- The type of a plan command.

$$\operatorname{type}(\mathrm{define}(\cdot)) = \mathrm{define},\ \dots,\ \operatorname{type}(\mathrm{milestone}(\cdot, \cdot)) = \mathrm{milestone}$$
-/
def Cmd.type : Cmd → CmdType
  | .define _ => .define | .drop _ => .drop | .claim .. => .claim | .done .. => .done
  | .milestone .. => .milestone

/-- A milestone row.

$$m = (\mathit{id}, \mathit{title})$$
-/
structure Milestone where
  id    : String
  title : String
deriving Repr, DecidableEq

/-- The plan state: the task rows and the milestone rows, each in definition order.

$$\pi = (\mathit{tasks}, \mathit{milestones}), \qquad \pi_0 = ([\,], [\,])$$
-/
structure State where
  tasks      : List Task := []
  milestones : List Milestone := []
deriving Repr, DecidableEq

/-- The row a definition makes, with the given agent and evidence.

$$\operatorname{row}(d, a, e) = (d.\mathit{task}, d.\mathit{title}, d.\mathit{stream}, d.\mathit{milestone}, d.\mathit{deps}, d.\mathit{owner}, d.\mathit{writes}, d.\mathit{devices}, d.\mathit{needs}, e, a, d.\mathit{cut})$$
-/
def Def.row (d : Def) (agent evidence : Option String) : Task :=
  { id := d.task, title := d.title, stream := d.stream, milestone := d.milestone, deps := d.deps,
    owner := d.owner, writes := d.writes, devices := d.devices, needs := d.needs, evidence, agent,
    cut := d.cut }

/-- The agent a definition claims its task for: the live agent whose name is the task id, if there is
one.

$$\operatorname{liveAgent}(d) = \begin{cases} d.\mathit{task} & d.\mathit{task} \in d.\mathit{live} \\ \bot & \text{otherwise} \end{cases}$$
-/
def Def.liveAgent (d : Def) : Option String := if d.live.contains d.task then some d.task else none

/-- Apply `f` to every row with id `x`.

$$\operatorname{setRow}(ts, x, f) = [\, \textbf{if } t.\mathit{id} = x \textbf{ then } f(t) \textbf{ else } t : t \in ts \,]$$
-/
def setRow (ts : List Task) (x : String) (f : Task → Task) : List Task :=
  ts.map fun t => if t.id = x then f t else t

/-- Upsert a definition: an existing id gets the new definition and keeps its evidence (new evidence
only fills a missing one); a new id is appended. A live agent named like the task claims it (an agent
spawned before its task was defined); otherwise an existing row keeps its agent and a new row is
unclaimed.

$$\operatorname{upsert}(ts, d) = \begin{cases} \operatorname{setRow}\big(ts, d.\mathit{task}, t \mapsto \operatorname{row}(d, \operatorname{liveAgent}(d) \mathbin{\langle|\rangle} t.\mathit{agent}, t.\mathit{evidence} \mathbin{\langle|\rangle} d.\mathit{evidence})\big) & d.\mathit{task} \in \operatorname{ids}(ts) \\ ts \mathbin{+\!\!+} [\operatorname{row}(d, \operatorname{liveAgent}(d), d.\mathit{evidence})] & \text{otherwise} \end{cases}$$

where $a \mathbin{\langle|\rangle} b$ is $a$ if present, else $b$.
-/
def upsert (ts : List Task) (d : Def) : List Task :=
  if (ids ts).contains d.task then
    setRow ts d.task fun t => d.row (d.liveAgent <|> t.agent) (t.evidence <|> d.evidence)
  else ts ++ [d.row d.liveAgent d.evidence]

/-- A task id is done: some row with that id has evidence.

$$\operatorname{isDone}(ts, x) \iff \exists t \in ts:\ t.\mathit{id} = x \land t.\mathit{evidence} \ne \bot$$
-/
def isDone (ts : List Task) (x : String) : Bool := ts.any fun t => t.id == x && t.evidence.isSome

/-- The first refusal of a plan command, or `none` when it is accepted (first match wins, top to
bottom inside each case).

$$\operatorname{check}(\pi, c) = \begin{cases}
\begin{array}{l} \texttt{"title: at most 200 characters"} \text{ if } |d.\mathit{title}| > 200;\ \texttt{"deps: at most 32"} \text{ if } |d.\mathit{deps}| > 32; \\
\quad \texttt{"writes: at most 32"} \text{ if } |d.\mathit{writes}| > 32;\ \texttt{"devices: at most 8"} \text{ if } |d.\mathit{devices}| > 8; \\
\quad \texttt{"needs: at most 8"} \text{ if } |d.\mathit{needs}| > 8; \\
\quad \texttt{"dep not defined: "} x \text{ for the first } x \in d.\mathit{deps} \setminus \operatorname{ids}(U); \\
\quad \texttt{"dependency cycle"} \text{ if } \neg\operatorname{acyclicB}(U);\ \bot \end{array} & c = \mathrm{define}(d),\ U = \operatorname{upsert}(\pi.\mathit{tasks}, d) \\
\begin{array}{l} \texttt{"no such task"} \text{ if } x \notin \operatorname{ids}(\pi.\mathit{tasks});\ \texttt{"task is done"} \text{ if } \operatorname{isDone}(\pi.\mathit{tasks}, x); \\
\quad \texttt{"task "} y \texttt{" depends on it"} \text{ for the first } t \in \pi.\mathit{tasks} \text{ with } t.\mathit{evidence} = \bot \land x \in t.\mathit{deps},\ y = t.\mathit{id};\ \bot \end{array} & c = \mathrm{drop}(x) \\
\texttt{"no such task"} \text{ if } x \notin \operatorname{ids}(\pi.\mathit{tasks});\ \texttt{"task already done"} \text{ if } \operatorname{isDone}(\pi.\mathit{tasks}, x);\ \bot & c \in \{\mathrm{claim}(x, \cdot), \mathrm{done}(x, \cdot)\} \\
\bot & c = \mathrm{milestone}(\cdot, \cdot)
\end{cases}$$
-/
def check (s : State) (c : Cmd) : Option String :=
  match c with
  | .define d =>
    let u := upsert s.tasks d
    if d.title.length > 200 then some "title: at most 200 characters"
    else if d.deps.length > 32 then some "deps: at most 32"
    else if d.writes.length > 32 then some "writes: at most 32"
    else if d.devices.length > 8 then some "devices: at most 8"
    else if d.needs.length > 8 then some "needs: at most 8"
    else match d.deps.find? (fun x => !(ids u).contains x) with
      | some x => some s!"dep not defined: {x}"
      | none => if acyclicB u then none else some "dependency cycle"
  | .drop x =>
    if !(ids s.tasks).contains x then some "no such task"
    else if isDone s.tasks x then some "task is done"
    else match s.tasks.find? (fun t => t.evidence.isNone && t.deps.contains x) with
      | some t => some s!"task {t.id} depends on it"
      | none => none
  | .claim x _ | .done x _ =>
    if !(ids s.tasks).contains x then some "no such task"
    else if isDone s.tasks x then some "task already done"
    else none
  | .milestone .. => none

/-- The effect of a plan command (applied after `check` accepted it).

$$\operatorname{exec}(\pi, c) = \begin{cases}
\pi[\mathit{tasks} := \operatorname{upsert}(\mathit{tasks}, d)] & \mathrm{define}(d) \\
\pi[\mathit{tasks} := [\, t \in \mathit{tasks} : t.\mathit{id} \ne x \,]] & \mathrm{drop}(x) \\
\pi[\mathit{tasks} := \operatorname{setRow}(\mathit{tasks}, x, t \mapsto t[\mathit{agent} := a])] & \mathrm{claim}(x, a) \\
\pi[\mathit{tasks} := \operatorname{setRow}(\mathit{tasks}, x, t \mapsto t[\mathit{evidence} := e])] & \mathrm{done}(x, e) \\
\pi[\mathit{milestones} := \text{the row } m \text{ retitled if present, else appended}] & \mathrm{milestone}(m, \mathit{title})
\end{cases}$$
-/
def exec (s : State) (c : Cmd) : State :=
  match c with
  | .define d => { s with tasks := upsert s.tasks d }
  | .drop x => { s with tasks := s.tasks.filter fun t => t.id != x }
  | .claim x a => { s with tasks := setRow s.tasks x fun t => { t with agent := some a } }
  | .done x e => { s with tasks := setRow s.tasks x fun t => { t with evidence := some e } }
  | .milestone m title =>
    if s.milestones.any (·.id == m) then
      { s with milestones := s.milestones.map fun r => if r.id = m then { r with title } else r }
    else { s with milestones := s.milestones ++ [{ id := m, title }] }

/-- One plan step: an accepted command is executed, a refused one leaves the state unchanged.

$$\operatorname{step}(\pi, c) = \begin{cases} \operatorname{exec}(\pi, c) & \operatorname{check}(\pi, c) = \bot \\ \pi & \text{otherwise} \end{cases}$$
-/
def step (s : State) (c : Cmd) : State := if check s c = none then exec s c else s

/-- The plan state of a command list: the left fold of `step` from the empty state.

$$\operatorname{run}([c_1, \dots, c_n]) = \operatorname{step}(\cdots \operatorname{step}(\pi_0, c_1) \cdots, c_n)$$
-/
def run (cs : List Cmd) : State := cs.foldl step {}

/-! ## Derived task states -/

/-- The derived state of a task.

$$\mathrm{TState} = \{\mathrm{done}, \mathrm{cut}, \mathrm{running}, \mathrm{ready}, \mathrm{blocked}\}$$
-/
inductive TState where
  | done | cut | running | ready | blocked
deriving Repr, DecidableEq

/-- The wire name of a task state.

$$\operatorname{name}(\mathrm{done}) = \texttt{"done"},\ \operatorname{name}(\mathrm{cut}) = \texttt{"cut"},\ \operatorname{name}(\mathrm{running}) = \texttt{"running"},\ \operatorname{name}(\mathrm{ready}) = \texttt{"ready"},\ \operatorname{name}(\mathrm{blocked}) = \texttt{"blocked"}$$
-/
def TState.name : TState → String
  | .done => "done" | .cut => "cut" | .running => "running" | .ready => "ready" | .blocked => "blocked"

/-- The blockers of a task: its deps that are not done, in dep order.

$$\operatorname{blockers}(ts, t) = [\, d \in t.\mathit{deps} : \neg\operatorname{isDone}(ts, d) \,]$$
-/
def blockers (ts : List Task) (t : Task) : List String := t.deps.filter fun d => !isDone ts d

/-- The state of a task is computed, never written (first match wins).

$$\operatorname{tstate}(ts, t) = \begin{cases} \mathrm{done} & t.\mathit{evidence} \ne \bot \\ \mathrm{cut} & t.\mathit{cut} \\ \mathrm{running} & t.\mathit{agent} \ne \bot \\ \mathrm{ready} & \operatorname{blockers}(ts, t) = [\,] \\ \mathrm{blocked} & \text{otherwise} \end{cases}$$
-/
def tstate (ts : List Task) (t : Task) : TState :=
  if t.evidence.isSome then .done
  else if t.cut then .cut
  else if t.agent.isSome then .running
  else if blockers ts t = [] then .ready
  else .blocked

/-- `isDone` as a proposition.

$$\forall ts, x:\quad \operatorname{isDone}(ts, x) = \mathrm{true} \iff \exists t \in ts:\ t.\mathit{id} = x \land t.\mathit{evidence} \ne \bot$$
-/
theorem isDone_iff {ts : List Task} {x : String} :
    isDone ts x = true ↔ ∃ t ∈ ts, t.id = x ∧ t.evidence ≠ none := by
  simp [isDone, Option.isSome_iff_ne_none]

/-- The blockers are exactly the undone deps.

$$\forall ts, t, d:\quad d \in \operatorname{blockers}(ts, t) \iff d \in t.\mathit{deps} \land \operatorname{isDone}(ts, d) = \mathrm{false}$$
-/
theorem mem_blockers {ts : List Task} {t : Task} {d : String} :
    d ∈ blockers ts t ↔ d ∈ t.deps ∧ isDone ts d = false := by
  simp [blockers]

/-- **Ready means: not done, not cut, not running, and every dep done.**

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{ready} \iff t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{false} \land t.\mathit{agent} = \bot \land \forall d \in t.\mathit{deps}:\ \operatorname{isDone}(ts, d) = \mathrm{true}$$
-/
theorem tstate_ready_iff (ts : List Task) (t : Task) : tstate ts t = .ready ↔
    t.evidence = none ∧ t.cut = false ∧ t.agent = none ∧ ∀ d ∈ t.deps, isDone ts d = true := by
  have hb : blockers ts t = [] ↔ ∀ d ∈ t.deps, isDone ts d = true := by
    simp [blockers, List.filter_eq_nil_iff]
  unfold tstate
  cases he : t.evidence <;> cases hc : t.cut <;> cases ha : t.agent <;> simp [hb]

/-- **Cut means: not done and flagged cut.** (Evidence wins: a task done before it was cut stays done.)

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{cut} \iff t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{true}$$
-/
theorem tstate_cut_iff (ts : List Task) (t : Task) :
    tstate ts t = .cut ↔ t.evidence = none ∧ t.cut = true := by
  unfold tstate
  cases he : t.evidence <;> cases hc : t.cut <;> cases ha : t.agent <;> simp <;> split <;> simp

/-- **A cut task is never ready.**

$$\forall ts, t:\quad t.\mathit{cut} = \mathrm{true} \Rightarrow \operatorname{tstate}(ts, t) \ne \mathrm{ready}$$
-/
theorem cut_not_ready {ts : List Task} {t : Task} (h : t.cut = true) : tstate ts t ≠ .ready := by
  intro hr
  have := ((tstate_ready_iff ts t).mp hr).2.1
  rw [h] at this; cases this

/-- **A blocked task has a blocker, and its blockers are exactly its undone deps.**

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{blocked} \Rightarrow \operatorname{blockers}(ts, t) \ne [\,] \land \forall d:\ \big(d \in \operatorname{blockers}(ts, t) \iff d \in t.\mathit{deps} \land \operatorname{isDone}(ts, d) = \mathrm{false}\big)$$
-/
theorem tstate_blocked {ts : List Task} {t : Task} (h : tstate ts t = .blocked) :
    blockers ts t ≠ [] ∧ ∀ d, d ∈ blockers ts t ↔ d ∈ t.deps ∧ isDone ts d = false := by
  refine ⟨?_, fun _ => mem_blockers⟩
  intro hn
  unfold tstate at h
  simp [hn] at h
  split at h <;> (try split at h) <;> (try split at h) <;> cases h

/-- **Done is exactly "has evidence".**

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{done} \iff t.\mathit{evidence} \ne \bot$$
-/
theorem tstate_done_iff (ts : List Task) (t : Task) : tstate ts t = .done ↔ t.evidence ≠ none := by
  unfold tstate
  split <;> (try split) <;> (try split) <;> (try split) <;> simp_all [Option.isSome_iff_ne_none]

/-- **Running is exactly "claimed, not done and not cut".**

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{running} \iff t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{false} \land t.\mathit{agent} \ne \bot$$
-/
theorem tstate_running_iff (ts : List Task) (t : Task) :
    tstate ts t = .running ↔ t.evidence = none ∧ t.cut = false ∧ t.agent ≠ none := by
  unfold tstate
  split <;> (try split) <;> (try split) <;> (try split) <;> simp_all [Option.isSome_iff_ne_none]

/-- With unique ids, rows with equal ids are equal.

$$\forall ts, a, b:\quad \operatorname{Nodup}(\operatorname{ids}(ts)) \land a \in ts \land b \in ts \land a.\mathit{id} = b.\mathit{id} \Rightarrow a = b$$
-/
theorem row_unique : ∀ {ts : List Task} {a b : Task}, (ids ts).Nodup → a ∈ ts → b ∈ ts →
    a.id = b.id → a = b
  | [], _, _, _, ha, _, _ => by cases ha
  | t :: ts, a, b, hn, ha, hb, he => by
    simp only [ids, List.map_cons, List.nodup_cons] at hn
    obtain ⟨hnot, hn⟩ := hn
    rcases List.mem_cons.mp ha with ha1 | ha1 <;> rcases List.mem_cons.mp hb with hb1 | hb1
    · rw [ha1, hb1]
    · subst ha1; exact absurd (he ▸ List.mem_map_of_mem (f := Task.id) hb1) hnot
    · subst hb1; exact absurd (he.symm ▸ List.mem_map_of_mem (f := Task.id) ha1) hnot
    · exact row_unique hn ha1 hb1 he

/-- **Two ready tasks never depend on each other**: with unique ids, no ready task lists a ready row
among its deps (applied both ways it gives independence; `a` need not even be a row).

$$\forall ts, a, b:\quad \operatorname{Nodup}(\operatorname{ids}(ts)) \land b \in ts \land \operatorname{tstate}(ts, a) = \operatorname{tstate}(ts, b) = \mathrm{ready} \Rightarrow b.\mathit{id} \notin a.\mathit{deps}$$
-/
theorem ready_indep {ts : List Task} {a b : Task} (hn : (ids ts).Nodup) (hb : b ∈ ts)
    (hra : tstate ts a = .ready) (hrb : tstate ts b = .ready) : b.id ∉ a.deps := by
  intro hd
  obtain ⟨_, _, _, hall⟩ := (tstate_ready_iff ts a).mp hra
  obtain ⟨hbe, _, _, _⟩ := (tstate_ready_iff ts b).mp hrb
  obtain ⟨r, hr, hid, hev⟩ := isDone_iff.mp (hall _ hd)
  rw [row_unique hn hr hb hid] at hev
  exact hev hbe

/-! ## Invariant: unique ids and an acyclic graph in every reachable state -/

/-- The plan invariant: task ids are unique and the dependency graph is acyclic.

$$\operatorname{Inv}(\pi) \iff \operatorname{Nodup}(\operatorname{ids}(\pi.\mathit{tasks})) \land \operatorname{Acyclic}(\pi.\mathit{tasks})$$
-/
def Inv (s : State) : Prop := (ids s.tasks).Nodup ∧ Acyclic s.tasks

/-- `setRow` with a map that keeps the id of the rows it touches keeps the ids.

$$\forall ts, x, f:\quad (\forall t:\ t.\mathit{id} = x \Rightarrow f(t).\mathit{id} = t.\mathit{id}) \Rightarrow \operatorname{ids}(\operatorname{setRow}(ts, x, f)) = \operatorname{ids}(ts)$$
-/
theorem ids_setRow {ts : List Task} {x : String} {f : Task → Task}
    (hf : ∀ t, t.id = x → (f t).id = t.id) : ids (setRow ts x f) = ids ts := by
  induction ts with
  | nil => rfl
  | cons t ts ih =>
    simp only [setRow, ids, List.map_cons] at ih ⊢
    rw [ih]
    split
    · rename_i h; rw [hf t h]
    · rfl

/-- `setRow` with an id- and deps-preserving map keeps every dependency edge.

$$\forall ts, x, f, a, b:\quad (\forall t:\ f(t).\mathit{id} = t.\mathit{id} \land f(t).\mathit{deps} = t.\mathit{deps}) \land \operatorname{Dep}_{\operatorname{setRow}(ts, x, f)}(a, b) \Rightarrow \operatorname{Dep}_{ts}(a, b)$$
-/
theorem dep_setRow {ts : List Task} {x : String} {f : Task → Task}
    (hf : ∀ t, (f t).id = t.id ∧ (f t).deps = t.deps) {a b : String}
    (h : Dep (setRow ts x f) a b) : Dep ts a b := by
  obtain ⟨t, ht, hid, hd⟩ := h
  obtain ⟨t0, h0, rfl⟩ := List.mem_map.mp ht
  refine ⟨t0, h0, ?_, ?_⟩
  · split at hid
    · rw [← (hf t0).1]; exact hid
    · exact hid
  · split at hd
    · rw [← (hf t0).2]; exact hd
    · exact hd

/-- An upsert keeps unique ids.

$$\forall ts, d:\quad \operatorname{Nodup}(\operatorname{ids}(ts)) \Rightarrow \operatorname{Nodup}(\operatorname{ids}(\operatorname{upsert}(ts, d)))$$
-/
theorem upsert_nodup {ts : List Task} (d : Def) (h : (ids ts).Nodup) : (ids (upsert ts d)).Nodup := by
  unfold upsert
  split
  · rw [ids_setRow (fun t ht => by simp [Def.row, ht])]
    exact h
  · rename_i hc
    simp only [ids, List.map_append, List.map_cons, List.map_nil]
    refine List.nodup_append.mpr ⟨h, by simp, ?_⟩
    intro a ha b hb hab
    simp only [List.mem_singleton] at hb
    subst hb hab
    exact hc (by simpa [ids, Def.row] using ha)

/-- **An accepted definition never closes a cycle.**

$$\forall \pi, d:\quad \operatorname{check}(\pi, \mathrm{define}(d)) = \bot \Rightarrow \operatorname{Acyclic}(\operatorname{upsert}(\pi.\mathit{tasks}, d))$$
-/
theorem define_acyclic {π : State} {d : Def} (h : check π (.define d) = none) :
    Acyclic (upsert π.tasks d) := by
  refine (acyclicB_iff _).mp ?_
  simp only [check] at h
  split at h; · cases h
  split at h; · cases h
  split at h; · cases h
  split at h; · cases h
  split at h; · cases h
  split at h
  · cases h
  · split at h
    · assumption
    · cases h

/-- **A definition that would close a cycle is refused.**

$$\forall \pi, d:\quad \neg\operatorname{Acyclic}(\operatorname{upsert}(\pi.\mathit{tasks}, d)) \Rightarrow \operatorname{check}(\pi, \mathrm{define}(d)) \ne \bot$$
-/
theorem define_cycle_refused {π : State} {d : Def} (h : ¬ Acyclic (upsert π.tasks d)) :
    check π (.define d) ≠ none := fun hc => h (define_acyclic hc)

/-- **An accepted command keeps the invariant.**

$$\forall \pi, c:\quad \operatorname{Inv}(\pi) \land \operatorname{check}(\pi, c) = \bot \Rightarrow \operatorname{Inv}(\operatorname{exec}(\pi, c))$$
-/
theorem exec_inv {π : State} {c : Cmd} (hi : Inv π) (hc : check π c = none) : Inv (exec π c) := by
  obtain ⟨hn, ha⟩ := hi
  cases c with
  | define d => exact ⟨upsert_nodup d hn, define_acyclic hc⟩
  | drop x =>
    refine ⟨?_, fun a h => ha a (tg_mono (fun _ _ => dep_filter) h)⟩
    simp only [exec, ids]
    exact List.Nodup.sublist (List.Sublist.map _ List.filter_sublist) hn
  | claim x a =>
    have hf : ∀ t : Task, ({ t with agent := some a } : Task).id = t.id ∧
        ({ t with agent := some a } : Task).deps = t.deps := fun _ => ⟨rfl, rfl⟩
    refine ⟨?_, fun b h => ha b (tg_mono (fun _ _ => dep_setRow hf) h)⟩
    simp only [exec]
    rw [ids_setRow (fun t _ => (hf t).1)]
    exact hn
  | done x e =>
    have hf : ∀ t : Task, ({ t with evidence := some e } : Task).id = t.id ∧
        ({ t with evidence := some e } : Task).deps = t.deps := fun _ => ⟨rfl, rfl⟩
    refine ⟨?_, fun b h => ha b (tg_mono (fun _ _ => dep_setRow hf) h)⟩
    simp only [exec]
    rw [ids_setRow (fun t _ => (hf t).1)]
    exact hn
  | milestone m title =>
    simp only [exec]
    split <;> exact ⟨hn, ha⟩

/-- The empty plan state satisfies the invariant.

$$\operatorname{Inv}(\pi_0)$$
-/
theorem inv_init : Inv {} := by
  refine ⟨List.nodup_nil, fun a h => ?_⟩
  obtain ⟨_, t, ht, _⟩ := tg_first h
  cases ht

/-- One step keeps the invariant.

$$\forall \pi, c:\quad \operatorname{Inv}(\pi) \Rightarrow \operatorname{Inv}(\operatorname{step}(\pi, c))$$
-/
theorem step_inv {π : State} (c : Cmd) (h : Inv π) : Inv (step π c) := by
  unfold step
  split
  · rename_i hc; exact exec_inv h hc
  · exact h

/-- Folding steps keeps the invariant.

$$\forall cs, \pi:\quad \operatorname{Inv}(\pi) \Rightarrow \operatorname{Inv}\big(\operatorname{foldl}(\operatorname{step}, \pi, cs)\big)$$
-/
theorem foldl_inv : ∀ (cs : List Cmd) {π : State}, Inv π → Inv (cs.foldl step π)
  | [], _, h => h
  | c :: cs, _, h => foldl_inv cs (step_inv c h)

/-- **Every reachable plan state has unique task ids and an acyclic dependency graph.**

$$\forall cs:\quad \operatorname{Inv}(\operatorname{run}(cs))$$
-/
theorem run_inv (cs : List Cmd) : Inv (run cs) := foldl_inv cs inv_init

/-! ## Done is monotone -/

/-- `isDone` survives `setRow` with a map that keeps the id and the evidence presence of the rows it
touches.

$$\forall ts, x, f, y:\quad (\forall t:\ t.\mathit{id} = x \Rightarrow f(t).\mathit{id} = t.\mathit{id} \land (t.\mathit{evidence} \ne \bot \Rightarrow f(t).\mathit{evidence} \ne \bot)) \land \operatorname{isDone}(ts, y) \Rightarrow \operatorname{isDone}(\operatorname{setRow}(ts, x, f), y)$$
-/
theorem isDone_setRow {ts : List Task} {x y : String} {f : Task → Task}
    (hf : ∀ t, t.id = x → (f t).id = t.id ∧ (t.evidence ≠ none → (f t).evidence ≠ none))
    (h : isDone ts y = true) : isDone (setRow ts x f) y = true := by
  obtain ⟨t, ht, hid, he⟩ := isDone_iff.mp h
  refine isDone_iff.mpr ⟨if t.id = x then f t else t, List.mem_map_of_mem ht, ?_, ?_⟩
  · split
    · rename_i hx; rw [(hf t hx).1]; exact hid
    · exact hid
  · split
    · rename_i hx; exact (hf t hx).2 he
    · exact he

/-- **Done is monotone**: an accepted command never un-does a task.

$$\forall \pi, c, x:\quad \operatorname{check}(\pi, c) = \bot \land \operatorname{isDone}(\pi.\mathit{tasks}, x) \Rightarrow \operatorname{isDone}(\operatorname{exec}(\pi, c).\mathit{tasks}, x)$$
-/
theorem exec_isDone {π : State} {c : Cmd} {x : String} (hc : check π c = none)
    (h : isDone π.tasks x = true) : isDone (exec π c).tasks x = true := by
  cases c with
  | define d =>
    simp only [exec, upsert]
    split
    · refine isDone_setRow (fun t ht => ⟨by simp [Def.row, ht], ?_⟩) h
      intro he
      simp only [Def.row]
      cases hte : t.evidence with
      | none => exact absurd hte he
      | some v => simp
    · obtain ⟨t, ht, hid, he⟩ := isDone_iff.mp h
      exact isDone_iff.mpr ⟨t, List.mem_append_left _ ht, hid, he⟩
  | drop y =>
    have hy : isDone π.tasks y = false := by
      simp only [check] at hc
      split at hc; · cases hc
      split at hc; · cases hc
      rename_i h2; simpa using h2
    obtain ⟨t, ht, hid, he⟩ := isDone_iff.mp h
    have hxy : x ≠ y := by
      rintro rfl; rw [h] at hy; cases hy
    refine isDone_iff.mpr ⟨t, ?_, hid, he⟩
    simp only [exec]
    exact List.mem_filter.mpr ⟨ht, by simp [hid, hxy]⟩
  | claim y a => exact isDone_setRow (fun _ _ => ⟨rfl, id⟩) h
  | done y e => exact isDone_setRow (fun _ _ => ⟨rfl, fun _ => by simp⟩) h
  | milestone m title => simp only [exec]; split <;> exact h

/-- **Done is monotone over steps.**

$$\forall \pi, c, x:\quad \operatorname{isDone}(\pi.\mathit{tasks}, x) \Rightarrow \operatorname{isDone}(\operatorname{step}(\pi, c).\mathit{tasks}, x)$$
-/
theorem step_isDone {π : State} (c : Cmd) {x : String} (h : isDone π.tasks x = true) :
    isDone (step π c).tasks x = true := by
  unfold step
  split
  · rename_i hc; exact exec_isDone hc h
  · exact h

/-! ## Late definitions: a live agent named like the task claims it -/

/-- An upsert with a live agent named like the task: the task has a row, and every row with that id
is claimed by that agent.

$$\forall ts, d:\quad d.\mathit{task} \in d.\mathit{live} \Rightarrow \big[(\exists t \in \operatorname{upsert}(ts, d):\ t.\mathit{id} = d.\mathit{task}) \land (\forall t \in \operatorname{upsert}(ts, d):\ t.\mathit{id} = d.\mathit{task} \Rightarrow t.\mathit{agent} = \mathrm{some}(d.\mathit{task}))\big]$$
-/
theorem upsert_live {ts : List Task} {d : Def} (hl : d.task ∈ d.live) :
    (∃ t ∈ upsert ts d, t.id = d.task) ∧ ∀ t ∈ upsert ts d, t.id = d.task → t.agent = some d.task := by
  have ha : d.liveAgent = some d.task := by simp [Def.liveAgent, hl]
  unfold upsert
  split
  · rename_i hc
    obtain ⟨t0, h0, hid0⟩ := List.mem_map.mp (List.contains_iff_mem.mp hc)
    refine ⟨⟨_, List.mem_map_of_mem (f := fun t => if t.id = d.task then
      d.row (d.liveAgent <|> t.agent) (t.evidence <|> d.evidence) else t) h0, by simp [hid0, Def.row]⟩, ?_⟩
    intro t ht hid
    obtain ⟨t1, _, rfl⟩ := List.mem_map.mp ht
    split at hid
    · rename_i h1; simp [h1, Def.row, ha]
    · rename_i hne; exact absurd hid hne
  · rename_i hc
    refine ⟨⟨d.row d.liveAgent d.evidence, by simp, rfl⟩, ?_⟩
    intro t ht hid
    rcases List.mem_append.mp ht with ht | ht
    · exact absurd (List.contains_iff_mem.mpr (hid ▸ List.mem_map_of_mem (f := Task.id) ht)) hc
    · simp only [List.mem_singleton] at ht; subst ht; exact ha

/-- **A task defined after its agent was spawned is claimed by it**: an accepted definition whose
live agents include one named like the task leaves the task present and claimed by that agent.

$$\forall \pi, d:\quad \big(\operatorname{check}(\pi, \mathrm{define}(d)) = \mathrm{none} \land d.\mathit{task} \in d.\mathit{live}\big) \Rightarrow \big[(\exists t \in \operatorname{step}(\pi, \mathrm{define}(d)).\mathit{tasks}:\ t.\mathit{id} = d.\mathit{task}) \land (\forall t \in \operatorname{step}(\pi, \mathrm{define}(d)).\mathit{tasks}:\ t.\mathit{id} = d.\mathit{task} \Rightarrow t.\mathit{agent} = \mathrm{some}(d.\mathit{task}))\big]$$
-/
theorem step_define_live {π : State} {d : Def} (hc : check π (.define d) = none)
    (hl : d.task ∈ d.live) :
    (∃ t ∈ (step π (.define d)).tasks, t.id = d.task) ∧
    ∀ t ∈ (step π (.define d)).tasks, t.id = d.task → t.agent = some d.task := by
  simp only [step, hc, ↓reduceIte, exec]
  exact upsert_live hl

/-! ## The board plan: views, milestone counts, parallel-safe groups -/

/-- Two tasks may run side by side: neither conflicts with the other (writes or devices).

$$\operatorname{ok}(x, y) \iff \neg\operatorname{conflict}(x, y) \land \neg\operatorname{conflict}(y, x)$$
-/
def ok (x y : Task) : Prop := conflict x y = false ∧ conflict y x = false

/-- A task fits a group when it may run side by side with every member.

$$\operatorname{fits}(g, t) \iff \forall x \in g:\ \operatorname{ok}(x, t)$$
-/
def fits (g : List Task) (t : Task) : Bool := g.all fun x => !conflict x t && !conflict t x

/-- Greedy placement: append the task to the first group it fits, or open a new group.

$$\operatorname{place}([\,], t) = [[t]], \qquad \operatorname{place}(g :: G, t) = \begin{cases} (g \mathbin{+\!\!+} [t]) :: G & \operatorname{fits}(g, t) \\ g :: \operatorname{place}(G, t) & \text{otherwise} \end{cases}$$
-/
def place : List (List Task) → Task → List (List Task)
  | [], t => [[t]]
  | g :: gs, t => if fits g t then (g ++ [t]) :: gs else g :: place gs t

/-- The ready rows, in row order.

$$\operatorname{readyRows}(ts) = [\, t \in ts : \operatorname{tstate}(ts, t) = \mathrm{ready} \,]$$
-/
def readyRows (ts : List Task) : List Task := ts.filter fun t => tstate ts t == .ready

/-- **The ready set excludes cut tasks.**

$$\forall ts, t:\quad t \in \operatorname{readyRows}(ts) \Rightarrow t.\mathit{cut} = \mathrm{false}$$
-/
theorem readyRows_not_cut {ts : List Task} {t : Task} (h : t ∈ readyRows ts) : t.cut = false := by
  have hr : tstate ts t = .ready := by simpa [readyRows] using (List.mem_filter.mp h).2
  exact ((tstate_ready_iff ts t).mp hr).2.1

/-! ## Lanes: agent work and device work -/

/-- The lane of a task: an agent alone can do it, or it needs the device (the measurement iPhone
and the user at it).

$$\mathrm{Lane} = \{\mathrm{agent}, \mathrm{device}\}$$
-/
inductive Lane where
  | agent | device
deriving Repr, DecidableEq

/-- The wire name of a lane.

$$\operatorname{name}(\mathrm{agent}) = \texttt{"agent"},\ \operatorname{name}(\mathrm{device}) = \texttt{"device"}$$
-/
def Lane.name : Lane → String
  | .agent => "agent" | .device => "device"

/-- The lane of a task is derived from its needs: `device` when it needs `"device"`, else `agent`.

$$\operatorname{lane}(t) = \begin{cases} \mathrm{device} & \texttt{"device"} \in t.\mathit{needs} \\ \mathrm{agent} & \text{otherwise} \end{cases}$$
-/
def lane (t : Task) : Lane := if t.needs.contains "device" then .device else .agent

/-- The ready rows of one lane, in row order.

$$\operatorname{readyIn}(ts, l) = [\, t \in \operatorname{readyRows}(ts) : \operatorname{lane}(t) = l \,]$$
-/
def readyIn (ts : List Task) (l : Lane) : List Task := (readyRows ts).filter fun t => lane t == l

/-- **A task is in the device lane exactly when it needs the device.**

$$\forall t:\quad \operatorname{lane}(t) = \mathrm{device} \iff \texttt{"device"} \in t.\mathit{needs}$$
-/
theorem lane_device_iff (t : Task) : lane t = .device ↔ "device" ∈ t.needs := by
  unfold lane
  split <;> simp_all

/-- A task is in the agent lane exactly when it does not need the device.

$$\forall t:\quad \operatorname{lane}(t) = \mathrm{agent} \iff \texttt{"device"} \notin t.\mathit{needs}$$
-/
theorem lane_agent_iff (t : Task) : lane t = .agent ↔ "device" ∉ t.needs := by
  unfold lane
  split <;> simp_all

/-- The ready rows of a lane are the ready rows in that lane.

$$\forall ts, l, t:\quad t \in \operatorname{readyIn}(ts, l) \iff t \in \operatorname{readyRows}(ts) \land \operatorname{lane}(t) = l$$
-/
theorem mem_readyIn {ts : List Task} {l : Lane} {t : Task} :
    t ∈ readyIn ts l ↔ t ∈ readyRows ts ∧ lane t = l := by
  simp [readyIn]

/-- **The ready set splits by lane**: the agent-ready rows followed by the device-ready rows are a
permutation of the ready rows, and no row is in both.

$$\forall ts:\quad \operatorname{readyIn}(ts, \mathrm{agent}) \mathbin{+\!\!+} \operatorname{readyIn}(ts, \mathrm{device}) \sim \operatorname{readyRows}(ts) \;\land\; \forall t:\ \neg\big(t \in \operatorname{readyIn}(ts, \mathrm{agent}) \land t \in \operatorname{readyIn}(ts, \mathrm{device})\big)$$
-/
theorem ready_split (ts : List Task) :
    (readyIn ts .agent ++ readyIn ts .device).Perm (readyRows ts) ∧
    ∀ t, ¬ (t ∈ readyIn ts .agent ∧ t ∈ readyIn ts .device) := by
  refine ⟨?_, fun t ⟨ha, hd⟩ => ?_⟩
  · have hc : readyIn ts .device = (readyRows ts).filter fun t => !(lane t == .agent) := by
      unfold readyIn
      exact List.filter_congr fun t _ => by cases lane t <;> rfl
    rw [hc]
    exact List.filter_append_perm _ _
  · have := (mem_readyIn.mp ha).2.symm.trans (mem_readyIn.mp hd).2
    cases this

/-- The parallel-safe groups: the agent-ready rows placed greedily in row order (device-lane tasks
wait for the user and are not grouped).

$$\operatorname{groups}(ts) = \operatorname{foldl}(\operatorname{place}, [\,], \operatorname{readyIn}(ts, \mathrm{agent}))$$
-/
def groups (ts : List Task) : List (List Task) := (readyIn ts .agent).foldl place []

/-- `fits` as a proposition.

$$\forall g, t:\quad \operatorname{fits}(g, t) = \mathrm{true} \iff \forall x \in g:\ \operatorname{ok}(x, t)$$
-/
theorem fits_iff {g : List Task} {t : Task} : fits g t = true ↔ ∀ x ∈ g, ok x t := by
  simp [fits, ok]

/-- Placement keeps every group pairwise ok.

$$\forall G, t:\quad (\forall g \in G:\ \operatorname{Pairwise}_{\operatorname{ok}}(g)) \Rightarrow \forall g \in \operatorname{place}(G, t):\ \operatorname{Pairwise}_{\operatorname{ok}}(g)$$
-/
theorem place_pairwise : ∀ (gs : List (List Task)) (t : Task), (∀ g ∈ gs, g.Pairwise ok) →
    ∀ g ∈ place gs t, g.Pairwise ok
  | [], t, _ => by simp [place]
  | g :: gs, t, h => by
    simp only [place]
    split
    · rename_i hf
      intro g' hg'
      rcases List.mem_cons.mp hg' with rfl | hg'
      · refine List.pairwise_append.mpr ⟨h g List.mem_cons_self, by simp, ?_⟩
        intro a ha b hb
        simp only [List.mem_singleton] at hb
        subst hb
        exact fits_iff.mp hf a ha
      · exact h g' (List.mem_cons_of_mem _ hg')
    · intro g' hg'
      rcases List.mem_cons.mp hg' with rfl | hg'
      · exact h _ List.mem_cons_self
      · exact place_pairwise gs t (fun g hg => h g (List.mem_cons_of_mem _ hg)) g' hg'

/-- Placement adds exactly the task.

$$\forall G, t:\quad \operatorname{flatten}(\operatorname{place}(G, t)) \sim \operatorname{flatten}(G) \mathbin{+\!\!+} [t]$$
-/
theorem place_perm : ∀ (gs : List (List Task)) (t : Task), (place gs t).flatten.Perm (gs.flatten ++ [t])
  | [], t => by simp [place]
  | g :: gs, t => by
    simp only [place]
    split
    · simp only [List.flatten_cons, List.append_assoc]
      exact List.Perm.append_left g (List.perm_append_comm (l₁ := [t]))
    · simp only [List.flatten_cons, List.append_assoc]
      exact List.Perm.append_left g (place_perm gs t)

/-- Folding placements keeps groups pairwise ok and adds exactly the folded tasks.

$$\forall l, G:\quad (\forall g \in G:\ \operatorname{Pairwise}_{\operatorname{ok}}(g)) \Rightarrow (\forall g \in \operatorname{foldl}(\operatorname{place}, G, l):\ \operatorname{Pairwise}_{\operatorname{ok}}(g)) \land \operatorname{flatten}(\operatorname{foldl}(\operatorname{place}, G, l)) \sim \operatorname{flatten}(G) \mathbin{+\!\!+} l$$
-/
theorem foldl_place : ∀ (l : List Task) (gs : List (List Task)), (∀ g ∈ gs, g.Pairwise ok) →
    (∀ g ∈ l.foldl place gs, g.Pairwise ok) ∧ (l.foldl place gs).flatten.Perm (gs.flatten ++ l)
  | [], gs, h => ⟨h, by simp⟩
  | t :: l, gs, h => by
    obtain ⟨h1, h2⟩ := foldl_place l (place gs t) (place_pairwise gs t h)
    refine ⟨h1, h2.trans ?_⟩
    have := List.Perm.append_right l (place_perm gs t)
    simpa [List.append_assoc] using this

/-- **Tasks in one parallel-safe group are pairwise non-conflicting** (on writes and on devices, in
both directions).

$$\forall ts, g:\quad g \in \operatorname{groups}(ts) \Rightarrow \forall i < j < |g|:\ \neg\operatorname{conflict}(g_i, g_j) \land \neg\operatorname{conflict}(g_j, g_i)$$
-/
theorem groups_pairwise (ts : List Task) : ∀ g ∈ groups ts, g.Pairwise ok :=
  (foldl_place _ [] (by simp)).1

/-- **The parallel-safe groups partition the agent-ready tasks.**

$$\forall ts:\quad \operatorname{flatten}(\operatorname{groups}(ts)) \sim \operatorname{readyIn}(ts, \mathrm{agent})$$
-/
theorem groups_perm (ts : List Task) : (groups ts).flatten.Perm (readyIn ts .agent) := by
  have := (foldl_place (readyIn ts .agent) [] (by simp)).2
  unfold groups
  simpa using this

/-- A task as the board shows it.

$$v = (\mathit{id}, \mathit{title}, \mathit{stream}, \mathit{milestone}_\bot, \mathit{owner}, \mathit{deps}, \mathit{needs}, \mathit{lane}, \mathit{state}, \mathit{blockers}, \mathit{agent}_\bot, \mathit{evidence}_\bot)$$
-/
structure TaskView where
  id        : String
  title     : String
  stream    : String
  milestone : Option String
  owner     : String
  deps      : List String
  needs     : List String
  lane      : Lane
  state     : TState
  blockers  : List String
  agent     : Option String
  evidence  : Option String
deriving Repr, DecidableEq

/-- A milestone as the board shows it: its done and total task counts.

$$m = (\mathit{id}, \mathit{title}, \mathit{done}, \mathit{total})$$
-/
structure MilestoneView where
  id    : String
  title : String
  done  : Nat
  total : Nat
deriving Repr, DecidableEq

/-- The board plan.

$$P = (\mathit{tasks}, \mathit{milestones}, \mathit{criticalPath}, \mathit{parallelSafe})$$
-/
structure View where
  tasks        : List TaskView
  milestones   : List MilestoneView
  criticalPath : List String
  parallelSafe : List (List String)
deriving Repr, DecidableEq

/-- The board view of one task.

$$\operatorname{taskView}(ts, t) = (t.\mathit{id}, t.\mathit{title}, t.\mathit{stream}, t.\mathit{milestone}, t.\mathit{owner}, t.\mathit{deps}, t.\mathit{needs}, \operatorname{lane}(t), \operatorname{tstate}(ts, t), \operatorname{blockers}(ts, t), t.\mathit{agent}, t.\mathit{evidence})$$
-/
def taskView (ts : List Task) (t : Task) : TaskView :=
  { id := t.id, title := t.title, stream := t.stream, milestone := t.milestone, owner := t.owner,
    deps := t.deps, needs := t.needs, lane := lane t, state := tstate ts t,
    blockers := blockers ts t, agent := t.agent,
    evidence := t.evidence }

/-- The rows that are not cut, in row order.

$$\operatorname{kept}(ts) = [\, t \in ts : t.\mathit{cut} = \mathrm{false} \,]$$
-/
def kept (ts : List Task) : List Task := ts.filter fun t => !t.cut

/-- The board view of one milestone: its tasks and its done tasks, cut tasks not counted.

$$\operatorname{msView}(ts, m) = \big(m.\mathit{id}, m.\mathit{title},\ |[\, t \in \operatorname{kept}(ts) : t.\mathit{milestone} = m.\mathit{id} \land t.\mathit{evidence} \ne \bot \,]|,\ |[\, t \in \operatorname{kept}(ts) : t.\mathit{milestone} = m.\mathit{id} \,]|\big)$$
-/
def msView (ts : List Task) (m : Milestone) : MilestoneView :=
  let mine := (kept ts).filter fun t => t.milestone == some m.id
  { id := m.id, title := m.title, done := (mine.filter fun t => t.evidence.isSome).length,
    total := mine.length }

/-- The board plan of a plan state.

$$\operatorname{view}(\pi) = \big([\operatorname{taskView}(\pi.\mathit{tasks}, t) : t \in \pi.\mathit{tasks}],\ [\operatorname{msView}(\pi.\mathit{tasks}, m) : m \in \pi.\mathit{milestones}],\ \operatorname{criticalPath}(\operatorname{kept}(\pi.\mathit{tasks})),\ [\operatorname{ids}(g) : g \in \operatorname{groups}(\pi.\mathit{tasks})]\big)$$
-/
def view (s : State) : View :=
  { tasks := s.tasks.map (taskView s.tasks), milestones := s.milestones.map (msView s.tasks),
    criticalPath := criticalPath (kept s.tasks), parallelSafe := (groups s.tasks).map ids }

/-- A milestone never has more done tasks than tasks.

$$\forall ts, m:\quad \operatorname{msView}(ts, m).\mathit{done} \le \operatorname{msView}(ts, m).\mathit{total}$$
-/
theorem msView_done_le (ts : List Task) (m : Milestone) : (msView ts m).done ≤ (msView ts m).total :=
  List.length_filter_le _ _

/-- **Cut tasks are not counted in milestone totals**: a milestone's counts are those of the rows
that are not cut.

$$\forall ts, m:\quad \operatorname{msView}(ts, m) = \operatorname{msView}(\operatorname{kept}(ts), m)$$
-/
theorem msView_kept (ts : List Task) (m : Milestone) : msView ts m = msView (kept ts) m := by
  simp [msView, kept, List.filter_filter]

/-- **The board's critical path is a longest chain of undone, uncut tasks** (on an invariant state).

$$\forall \pi:\quad \operatorname{Inv}(\pi) \Rightarrow \operatorname{UChain}_{\operatorname{kept}(\pi.\mathit{tasks})}(\operatorname{view}(\pi).\mathit{criticalPath}) \land \forall l:\ \operatorname{UChain}_{\operatorname{kept}(\pi.\mathit{tasks})}(l) \Rightarrow |l| \le |\operatorname{view}(\pi).\mathit{criticalPath}|$$
-/
theorem view_criticalPath {π : State} (h : Inv π) : UChain (kept π.tasks) (view π).criticalPath ∧
    ∀ l, UChain (kept π.tasks) l → l.length ≤ (view π).criticalPath.length :=
  ⟨criticalPath_chain _,
   fun _ hl => criticalPath_longest (fun a h' => h.2 a (tg_mono (fun _ _ => dep_filter) h')) hl⟩

/-- **No cut task is on the critical path**: every id on it is an undone row that is not cut.

$$\forall \pi, x:\quad x \in \operatorname{view}(\pi).\mathit{criticalPath} \Rightarrow \exists t \in \pi.\mathit{tasks}:\ t.\mathit{id} = x \land t.\mathit{cut} = \mathrm{false} \land t.\mathit{evidence} = \bot$$
-/
theorem view_criticalPath_not_cut {π : State} {x : String} (hx : x ∈ (view π).criticalPath) :
    ∃ t ∈ π.tasks, t.id = x ∧ t.cut = false ∧ t.evidence = none := by
  have hu := (criticalPath_chain (kept π.tasks)).2 x hx
  simp only [uids, ids, undone, kept, List.filter_filter, List.mem_map, List.mem_filter,
    Bool.and_eq_true, Bool.not_eq_true', Option.isNone_iff_eq_none] at hu
  obtain ⟨t, ⟨ht, he, hc⟩, rfl⟩ := hu
  exact ⟨t, ht, rfl, hc, he⟩

/-! ## Examples -/

/-- A definition with the given id and deps (test helper).

$$\operatorname{mk}(x, D, W) = (x, x, \texttt{"s"}, \bot, D, \texttt{"o"}, W, [\,], [\,], \bot)$$
-/
def mk (x : String) (deps : List String) (writes : List String := []) : Def :=
  { task := x, title := x, stream := "s", milestone := none, deps, owner := "o", writes,
    devices := [], needs := [], evidence := none }

#guard check {} (.define (mk "a" ["b"])) == some "dep not defined: b"
#guard check {} (.define (mk "a" ["a"])) == some "dependency cycle"
#guard check (run [.define (mk "a" []), .define (mk "b" ["a"])]) (.define (mk "a" ["b"]))
  == some "dependency cycle"
#guard check (run [.define (mk "a" []), .define (mk "b" ["a"])]) (.drop "a")
  == some "task b depends on it"
#guard check (run [.define (mk "a" []), .done "a" "abc1234"]) (.drop "a") == some "task is done"
#guard check (run [.define (mk "a" [])]) (.claim "z" "x") == some "no such task"
#guard check (run [.define (mk "a" []), .done "a" "abc1234"]) (.done "a" "e") == some "task already done"
#guard check {} (.define { mk "a" [] with title := String.ofList (List.replicate 201 'x') })
  == some "title: at most 200 characters"
#guard (run [.define (mk "a" []), .define (mk "b" ["a"]), .drop "b"]).tasks.map (·.id) == ["a"]
#guard let s := run [.define (mk "a" []), .define (mk "b" ["a"]), .define (mk "c" []),
    .claim "c" "agent-1"]
  (s.tasks.map (tstate s.tasks)) == [.ready, .blocked, .running]
#guard let s := run [.define (mk "a" []), .define (mk "b" ["a"]), .done "a" "abc1234"]
  (s.tasks.map (tstate s.tasks)) == [.done, .ready]
#guard let s := run [.define (mk "a" []), .define (mk "b" ["a"]), .define (mk "c" ["b"]),
    .define (mk "d" [])]
  criticalPath s.tasks == ["a", "b", "c"]
#guard let s := run [.define (mk "a" [] ["x/**"]), .define (mk "b" [] ["x/y.lean"]),
    .define (mk "c" [] ["z/**"])]
  (view s).parallelSafe == [["a", "c"], ["b"]]
#guard let s := run [.milestone "M0" "Start", .define { mk "a" [] with milestone := some "M0" },
    .define { mk "b" [] with milestone := some "M0" }, .done "a" "abc1234"]
  (view s).milestones == [{ id := "M0", title := "Start", done := 1, total := 2 }]
#guard check {} (.define { mk "a" [] with needs := List.replicate 9 "x" }) == some "needs: at most 8"
#guard lane { (mk "a" []).row none none with needs := ["device"] } == .device
#guard lane { (mk "a" []).row none none with needs := ["other", "device"] } == .device
#guard lane { (mk "a" []).row none none with needs := ["other"] } == .agent
#guard lane ((mk "a" []).row none none) == .agent
#guard let s := run [.define (mk "a" [] ["x/**"]), .define { mk "p" [] with needs := ["device"] },
    .define { mk "q" ["a"] with needs := ["device"] }, .define (mk "c" [] ["z/**"])]
  (view s).parallelSafe == [["a", "c"]] && (readyIn s.tasks .device).map (·.id) == ["p"] &&
  (view s).tasks.map (·.lane) == [.agent, .device, .device, .agent]
-- late definition: a live agent named like the task claims it; another live agent does not
#guard let s := run [.define { mk "a" [] with live := ["a", "x"] }, .define { mk "b" [] with live := ["x"] }]
  s.tasks.map (·.agent) == [some "a", none] && s.tasks.map (tstate s.tasks) == [.running, .ready]
#guard let s := run [.define (mk "a" []), .claim "a" "lead-1", .define { mk "a" [] with live := ["z"] }]
  s.tasks.map (·.agent) == [some "lead-1"]
#guard let s := run [.define (mk "a" []), .define { mk "a" ["b"] with live := ["a"] }]
  s.tasks.map (·.agent) == [none]
#guard (mk "a" []).liveAgent == none && { mk "a" [] with live := ["a"] }.liveAgent == some "a"
-- cut: never ready, not grouped, not on the critical path, not counted; evidence still wins
#guard let s := run [.milestone "M0" "Zero", .define { mk "a" [] ["x/**"] with milestone := some "M0" },
    .define { mk "c" [] ["y/**"] with milestone := some "M0", cut := true },
    .define { mk "d" ["c"] with milestone := some "M0", cut := true },
    .define { mk "e" [] with milestone := some "M0", cut := true, evidence := some "abc1234" },
    .claim "c" "agent-c"]
  s.tasks.map (tstate s.tasks) == [.ready, .cut, .cut, .done] && (view s).parallelSafe == [["a"]] &&
  (view s).criticalPath == ["a"] &&
  (view s).milestones == [{ id := "M0", title := "Zero", done := 0, total := 1 }]
#guard let s := run [.define { mk "a" [] with cut := true }, .define (mk "a" [])]
  s.tasks.map (tstate s.tasks) == [.ready]

end Fw.Plan
