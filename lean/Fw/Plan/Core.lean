import Fw.Plan.Graph
import Fw.Plan.Lint
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
* Late definitions (legacy): a `task.define` may carry the live agent names (a fact older consoles
  added); a live agent named like the task claims it (`upsert_live`, `step_define_live`). Kept only so
  that old logs replay to the same board.
* Agent binding (`agentOf`, `bound`, `boundTo`): `agent.spawn` / `agent.stop` are recorded as
  multisets; the agent of a task is derived from its explicit claim, the spawns and stops of agents
  named like it, and its evidence, never stored. Spawn and stop commute with every command
  (`step_life_comm`, `run_comm`, `run_split`), so the board depends only on the order of the other
  commands and on the spawn/stop multisets (`view_perm`); old logs without them reduce to the old
  board (`view_compat`). `boundTo_keep`, `boundTo_spawn`: a binding survives every command except an
  explicit claim of the task, its drop, a stop of the bound agent and a spawn (which may switch it
  to the spawned agent).
* Evidence on main (task `evidence-on-main`): a `task.define` carries the ancestry fact `onMain` of
  its evidence (`git merge-base --is-ancestor <evidence> main`, collected by the glue). A define with
  commit evidence that is not on main is refused, naming the sha, and the state is kept
  (`upsert_cannot_mark_done_early`, `define_offMain_reason`). A row records whether its evidence came
  from a land event (`task.done`, `landed`); a define without evidence clears evidence that did not
  (`define_removes_unlanded_evidence`), and a land is never undone (`land_never_undone`,
  `run_land_never_undone`). Every done row has landed evidence or on-main define evidence
  (`done_needs_landed_evidence`).
-/
namespace Fw.Plan

/-- A `task.define` payload: the task's definition, optional evidence that it is already done, the
`cut` flag (the task was cut from the plan; default false), `live`, the names of the agents alive
at that moment (default empty), and `onMain`, the ancestry fact of the evidence that the glue
collected (`git merge-base --is-ancestor <evidence> main` succeeded; default true, which is also what
an event without the field decodes to, so logs from before the fact existed replay unchanged). `live`
is a legacy fact: older consoles added it on receipt; the console no longer does (spawns are events
now), and it is decoded only so old logs replay unchanged.

$$d = (\mathit{task}, \mathit{title}, \mathit{stream}, \mathit{milestone}_\bot, \mathit{deps}, \mathit{owner}, \mathit{writes}, \mathit{devices}, \mathit{needs}, \mathit{evidence}_\bot, \mathit{cut}, \mathit{live}, \mathit{onMain})$$
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
  onMain    : Bool := true
deriving Repr, DecidableEq

/-- The plan commands.

$$\mathrm{Cmd} = \mathrm{define}(d) \mid \mathrm{drop}(\mathit{task}) \mid \mathrm{claim}(\mathit{task}, \mathit{agent}, \mathit{ts}) \mid \mathrm{done}(\mathit{task}, \mathit{evidence}) \mid \mathrm{milestone}(\mathit{id}, \mathit{title}) \mid \mathrm{spawn}(\mathit{agent}, \mathit{ts}) \mid \mathrm{stop}(\mathit{agent}, \mathit{ts}) \\ \mid \mathrm{label}(\mathit{agent}, \mathit{name}) \mid \mathrm{handback}(\mathit{task}, \mathit{agent}, \mathit{tip}_\bot) \mid \mathrm{integrate}(\mathit{task}, \mathit{branch}, \mathit{tip}) \mid \mathrm{park}(\mathit{task}, \mathit{reason}) \mid \mathrm{unpark}(\mathit{task})$$

The last four (task `task-state-truth`) record what became of a task's work when its agent ended
without a land: handed back, merged into a non-main integration branch, or parked by the lead
(`unpark` removes the mark). A spawn or a stop carries a time $\mathit{ts} \in \mathbb{N}$ (ms): when
the agent was seen starting or working (spawn) or ending (stop), so the board can tell whether a stop
came after the agent's last sign of life, whatever order the commands reach the log in. The
`agent` of a spawn or stop is a life key: the agent id of the hook records (task `task-state-truth`,
round 3: liveness by id), or a name for facts that have no id (a spawn guard, a workflow run). A
`label` gives the life key `agent` the display name `name` (from the console's health index), which
binds it to tasks; a claim carries its time $\mathit{ts}$ (ms), which counts as a sighting of the
claimed name (so a claim without any spawn expires after the quiet limit: `no_forever_running`).
-/
inductive Cmd where
  | define (d : Def)
  | drop (task : String)
  | claim (task agent : String) (ts : Nat)
  | done (task evidence : String)
  | milestone (id title : String)
  | spawn (agent : String) (ts : Nat)
  | stop (agent : String) (ts : Nat)
  | handback (task agent : String) (tip : Option String)
  | integrate (task branch tip : String)
  | park (task reason : String)
  | unpark (task : String)
  | label (agent name : String)
deriving Repr, DecidableEq

/-- The plan command types.

$$\mathrm{CmdType} = \{\mathrm{define}, \mathrm{drop}, \mathrm{claim}, \mathrm{done}, \mathrm{milestone}, \mathrm{spawn}, \mathrm{stop}, \mathrm{handback}, \mathrm{integrate}, \mathrm{park}, \mathrm{unpark}, \mathrm{label}\}$$
-/
inductive CmdType where
  | define | drop | claim | done | milestone | spawn | stop | handback | integrate | park | unpark | label
deriving Repr, DecidableEq

/-- The wire name of a plan command type.

$$\operatorname{name}(\mathrm{define}) = \texttt{"task.define"},\ \operatorname{name}(\mathrm{drop}) = \texttt{"task.drop"},\ \operatorname{name}(\mathrm{claim}) = \texttt{"task.claim"},\ \operatorname{name}(\mathrm{done}) = \texttt{"task.done"},\ \operatorname{name}(\mathrm{milestone}) = \texttt{"milestone.define"},\ \operatorname{name}(\mathrm{spawn}) = \texttt{"agent.spawn"},\ \operatorname{name}(\mathrm{stop}) = \texttt{"agent.stop"},\ \operatorname{name}(\mathrm{handback}) = \texttt{"task.handback"},\ \operatorname{name}(\mathrm{integrate}) = \texttt{"task.integrate"},\ \operatorname{name}(\mathrm{park}) = \texttt{"task.park"},\ \operatorname{name}(\mathrm{unpark}) = \texttt{"task.unpark"},\ \operatorname{name}(\mathrm{label}) = \texttt{"agent.label"}$$
-/
def CmdType.name : CmdType → String
  | .define => "task.define" | .drop => "task.drop" | .claim => "task.claim"
  | .done => "task.done" | .milestone => "milestone.define" | .spawn => "agent.spawn"
  | .stop => "agent.stop" | .handback => "task.handback" | .integrate => "task.integrate"
  | .park => "task.park" | .unpark => "task.unpark" | .label => "agent.label"

/-- The type of a plan command.

$$\operatorname{type}(\mathrm{define}(\cdot)) = \mathrm{define},\ \dots,\ \operatorname{type}(\mathrm{milestone}(\cdot, \cdot)) = \mathrm{milestone},\ \operatorname{type}(\mathrm{spawn}(\cdot, \cdot)) = \mathrm{spawn},\ \operatorname{type}(\mathrm{stop}(\cdot, \cdot)) = \mathrm{stop},\ \operatorname{type}(\mathrm{handback}(\cdot,\cdot,\cdot)) = \mathrm{handback},\ \operatorname{type}(\mathrm{integrate}(\cdot,\cdot,\cdot)) = \mathrm{integrate},\ \operatorname{type}(\mathrm{park}(\cdot,\cdot)) = \mathrm{park},\ \operatorname{type}(\mathrm{unpark}(\cdot)) = \mathrm{unpark},\ \operatorname{type}(\mathrm{label}(\cdot, \cdot)) = \mathrm{label}$$
-/
def Cmd.type : Cmd → CmdType
  | .define _ => .define | .drop _ => .drop | .claim .. => .claim | .done .. => .done
  | .milestone .. => .milestone | .spawn .. => .spawn | .stop .. => .stop
  | .handback .. => .handback | .integrate .. => .integrate | .park .. => .park | .unpark _ => .unpark
  | .label .. => .label

/-- A milestone row.

$$m = (\mathit{id}, \mathit{title})$$
-/
structure Milestone where
  id    : String
  title : String
deriving Repr, DecidableEq

/-- The plan state: the task rows and the milestone rows, each in definition order, and the (agent
name, time) pairs of the accepted `agent.spawn` and `agent.stop` commands, one entry per command, in
log order (the board reads them only as multisets: `view_perm`), and the outcome marks of the accepted
`task.handback` / `task.integrate` / `task.park` / `task.unpark` commands, one pair (task id, mark)
per command in log order (`unpark` records no mark; the board reads the last pair of a task), the
(life key, name) pairs of the accepted `agent.label` commands (read as a multiset), and the (agent,
time) pairs of the accepted `task.claim` commands in log order.

$$\pi = (\mathit{tasks}, \mathit{milestones}, \mathit{spawns}, \mathit{stops}, \mathit{marks}, \mathit{labels}, \mathit{claims}), \qquad \pi_0 = ([\,], [\,], [\,], [\,], [\,], [\,], [\,])$$
-/
structure State where
  tasks      : List Task := []
  milestones : List Milestone := []
  spawns     : List (String × Nat) := []
  stops      : List (String × Nat) := []
  marks      : List (String × Option Mark) := []
  labels     : List (String × String) := []
  claims     : List (String × Nat) := []
deriving Repr, DecidableEq

/-- The row a definition makes, with the given agent, evidence and evidence provenance.

$$\operatorname{row}(d, a, e, \ell) = (d.\mathit{task}, d.\mathit{title}, d.\mathit{stream}, d.\mathit{milestone}, d.\mathit{deps}, d.\mathit{owner}, d.\mathit{writes}, d.\mathit{devices}, d.\mathit{needs}, e, a, d.\mathit{cut}, \ell)$$
-/
def Def.row (d : Def) (agent evidence : Option String) (landed : Bool) : Task :=
  { id := d.task, title := d.title, stream := d.stream, milestone := d.milestone, deps := d.deps,
    owner := d.owner, writes := d.writes, devices := d.devices, needs := d.needs, evidence, agent,
    cut := d.cut, landed }

/-- The commit evidence of a definition that is not on main: its evidence when that is a commit id
(`Fw.Plan.Lint.evKind`) and the ancestry fact says it is not an ancestor of main; none otherwise
(no evidence, evidence of another kind, or on main).

$$\operatorname{offMain}(d) = \begin{cases} e & d.\mathit{evidence} = e \land \operatorname{kind}(e) = \mathrm{commit} \land d.\mathit{onMain} = \mathrm{false} \\ \bot & \text{otherwise} \end{cases}$$
-/
def Def.offMain (d : Def) : Option String :=
  match d.evidence with
  | some e => if Lint.evKind e == .commit && !d.onMain then some e else none
  | none => none

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

/-- The evidence an upsert gives an existing row: landed evidence (from a `task.done`) is kept;
otherwise the definition's evidence replaces it, so a definition without evidence clears evidence
that an earlier definition gave.

$$\operatorname{keepEv}(t, d) = \begin{cases} t.\mathit{evidence} & t.\mathit{landed} = \mathrm{true} \\ d.\mathit{evidence} & t.\mathit{landed} = \mathrm{false} \end{cases}$$
-/
def keepEv (t : Task) (d : Def) : Option String := if t.landed then t.evidence else d.evidence

/-- Upsert a definition: an existing id gets the new definition, keeps its provenance flag, and gets
`keepEv` as its evidence (landed evidence stays; otherwise the definition's evidence, possibly none);
a new id is appended with its evidence not landed. A live agent named like the task claims it (an
agent spawned before its task was defined); otherwise an existing row keeps its agent and a new row
is unclaimed.

$$\operatorname{upsert}(ts, d) = \begin{cases} \operatorname{setRow}\big(ts, d.\mathit{task}, t \mapsto \operatorname{row}(d, \operatorname{liveAgent}(d) \mathbin{\langle|\rangle} t.\mathit{agent}, \operatorname{keepEv}(t, d), t.\mathit{landed})\big) & d.\mathit{task} \in \operatorname{ids}(ts) \\ ts \mathbin{+\!\!+} [\operatorname{row}(d, \operatorname{liveAgent}(d), d.\mathit{evidence}, \mathrm{false})] & \text{otherwise} \end{cases}$$

where $a \mathbin{\langle|\rangle} b$ is $a$ if present, else $b$.
-/
def upsert (ts : List Task) (d : Def) : List Task :=
  if (ids ts).contains d.task then
    setRow ts d.task fun t => d.row (d.liveAgent <|> t.agent) (keepEv t d) t.landed
  else ts ++ [d.row d.liveAgent d.evidence false]

/-- A task id is done: some row with that id has evidence.

$$\operatorname{isDone}(ts, x) \iff \exists t \in ts:\ t.\mathit{id} = x \land t.\mathit{evidence} \ne \bot$$
-/
def isDone (ts : List Task) (x : String) : Bool := ts.any fun t => t.id == x && t.evidence.isSome

/-- The ref prefixes an integrate command may target: CI branches, worktree branches and integration
branches, always as full refs (the runner resolves a short name with `git rev-parse --verify
--symbolic-full-name`, or refuses).

$$\operatorname{allowPrefixes} = [\texttt{"refs/heads/ci/"}, \texttt{"refs/heads/worktree-"}, \texttt{"refs/heads/integrate-"}]$$

The three branch families that integration may write to.
-/
def allowPrefixes : List String := ["refs/heads/ci/", "refs/heads/worktree-", "refs/heads/integrate-"]

/-- A character allowed in an integrate ref: an ASCII letter or digit, `.`, `_`, `/` or `-`.

$$\operatorname{refChar}(c) \iff c \in \{\texttt{a}, \dots, \texttt{z}, \texttt{A}, \dots, \texttt{Z}, \texttt{0}, \dots, \texttt{9}, \texttt{.}, \texttt{\_}, \texttt{/}, \texttt{-}\}$$

The characters of a plain branch name, without git's revision syntax (`~`, `^`, `@`, `:`, …).
-/
def refChar (c : Char) : Bool := c.isAlphanum || c == '.' || c == '_' || c == '/' || c == '-'

/-- **An integrate target is allowed** when it is a full ref that starts with one of `allowPrefixes`
and goes on past it, uses only `refChar` characters, and has no two dots in a row.

$$\operatorname{allowedRef}(b) \iff \big(\exists p \in \operatorname{allowPrefixes}:\ p \text{ is a prefix of } b \land |b| > |p|\big) \land (\forall i < |b|:\ \operatorname{refChar}(b_i)) \land \lnot\big(\exists i:\ i + 1 < |b| \land b_i = b_{i+1} = \texttt{.}\big)$$

Every spelling of main (`main`, `refs/heads/main`, `origin/main`, `origin/HEAD`, `HEAD`, `main~0`,
`@`) fails the prefix test, so it is refused.
-/
def allowedRef (b : String) : Bool :=
  allowPrefixes.any (fun p => b.startsWith p && decide (b.length > p.length)) &&
    b.toList.all refChar && !(b.toList.zip b.toList.tail).any (fun (x, y) => x == '.' && y == '.')

#guard allowedRef "refs/heads/ci/integrate-ports-3" && allowedRef "refs/heads/worktree-wf_dd322f5d-433-1"
#guard allowedRef "refs/heads/integrate-x"
#guard !allowedRef "main" && !allowedRef "Main" && !allowedRef "refs/heads/main" && !allowedRef "origin/main"
#guard !allowedRef "origin/HEAD" && !allowedRef "HEAD" && !allowedRef "@" && !allowedRef "main~0"
#guard !allowedRef "refs/remotes/origin/main" && !allowedRef "heads/main" && !allowedRef "ci/x"
#guard !allowedRef "refs/heads/ci/" && !allowedRef "refs/heads/ci/a..b" && !allowedRef "refs/heads/ci/x~1"
#guard !allowedRef "refs/heads/ci/x^" && !allowedRef "refs/heads/ci/x@{0}" && !allowedRef "refs/heads/worktree-"
#guard !allowedRef "refs/heads/feature" && !allowedRef "" && !allowedRef "refs/heads/ci/a b"

/-- The first refusal of a plan command, or `none` when it is accepted (first match wins, top to
bottom inside each case).

$$\operatorname{check}(\pi, c) = \begin{cases}
\begin{array}{l} \texttt{"title: at most 200 characters"} \text{ if } |d.\mathit{title}| > 200;\ \texttt{"deps: at most 32"} \text{ if } |d.\mathit{deps}| > 32; \\
\quad \texttt{"writes: at most 32"} \text{ if } |d.\mathit{writes}| > 32;\ \texttt{"devices: at most 8"} \text{ if } |d.\mathit{devices}| > 8; \\
\quad \texttt{"needs: at most 8"} \text{ if } |d.\mathit{needs}| > 8;\ \texttt{"evidence not on main: "} e \text{ if } \operatorname{offMain}(d) = e; \\
\quad \texttt{"dep not defined: "} x \text{ for the first } x \in d.\mathit{deps} \setminus \operatorname{ids}(U); \\
\quad \texttt{"dependency cycle"} \text{ if } \neg\operatorname{acyclicB}(U);\ \bot \end{array} & c = \mathrm{define}(d),\ U = \operatorname{upsert}(\pi.\mathit{tasks}, d) \\
\begin{array}{l} \texttt{"no such task"} \text{ if } x \notin \operatorname{ids}(\pi.\mathit{tasks});\ \texttt{"task is done"} \text{ if } \operatorname{isDone}(\pi.\mathit{tasks}, x); \\
\quad \texttt{"task "} y \texttt{" depends on it"} \text{ for the first } t \in \pi.\mathit{tasks} \text{ with } t.\mathit{evidence} = \bot \land x \in t.\mathit{deps},\ y = t.\mathit{id};\ \bot \end{array} & c = \mathrm{drop}(x) \\
\texttt{"no such task"} \text{ if } x \notin \operatorname{ids}(\pi.\mathit{tasks});\ \texttt{"task already done"} \text{ if } \operatorname{isDone}(\pi.\mathit{tasks}, x);\ \bot & c \in \{\mathrm{claim}(x, \cdot, \cdot), \mathrm{done}(x, \cdot), \mathrm{handback}(x, \cdot, \cdot), \mathrm{park}(x, \cdot), \mathrm{unpark}(x)\} \\
\begin{array}{l} \texttt{"no such task"} \text{ if } x \notin \operatorname{ids}(\pi.\mathit{tasks});\ \texttt{"task already done"} \text{ if } \operatorname{isDone}(\pi.\mathit{tasks}, x); \\ \quad \texttt{"integrate only into refs/heads/ci/*, refs/heads/worktree-* or refs/heads/integrate-*"} \text{ if } \lnot\operatorname{allowedRef}(b);\ \bot \end{array} & c = \mathrm{integrate}(x, b, \cdot) \\
\bot & c \in \{\mathrm{milestone}(\cdot, \cdot), \mathrm{spawn}(\cdot, \cdot), \mathrm{stop}(\cdot, \cdot), \mathrm{label}(\cdot, \cdot)\}
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
    else match d.offMain with
    | some e => some s!"evidence not on main: {e}"
    | none => match d.deps.find? (fun x => !(ids u).contains x) with
      | some x => some s!"dep not defined: {x}"
      | none => if acyclicB u then none else some "dependency cycle"
  | .drop x =>
    if !(ids s.tasks).contains x then some "no such task"
    else if isDone s.tasks x then some "task is done"
    else match s.tasks.find? (fun t => t.evidence.isNone && t.deps.contains x) with
      | some t => some s!"task {t.id} depends on it"
      | none => none
  | .claim x _ _ | .done x _ | .handback x _ _ | .park x _ | .unpark x =>
    if !(ids s.tasks).contains x then some "no such task"
    else if isDone s.tasks x then some "task already done"
    else none
  | .integrate x b _ =>
    if !(ids s.tasks).contains x then some "no such task"
    else if isDone s.tasks x then some "task already done"
    else if !allowedRef b then
      some "integrate only into refs/heads/ci/*, refs/heads/worktree-* or refs/heads/integrate-*"
    else none
  | .milestone .. | .spawn .. | .stop .. | .label .. => none

/-- The effect of a plan command (applied after `check` accepted it).

$$\operatorname{exec}(\pi, c) = \begin{cases}
\pi[\mathit{tasks} := \operatorname{upsert}(\mathit{tasks}, d)] & \mathrm{define}(d) \\
\pi[\mathit{tasks} := [\, t \in \mathit{tasks} : t.\mathit{id} \ne x \,]] & \mathrm{drop}(x) \\
\pi[\mathit{tasks} := \operatorname{setRow}(\mathit{tasks}, x, t \mapsto t[\mathit{agent} := a]),\ \mathit{claims} := \mathit{claims} \mathbin{+\!\!+} [(a, n)]] & \mathrm{claim}(x, a, n) \\
\pi[\mathit{tasks} := \operatorname{setRow}(\mathit{tasks}, x, t \mapsto t[\mathit{evidence} := e,\ \mathit{landed} := \mathrm{true}])] & \mathrm{done}(x, e) \\
\pi[\mathit{milestones} := \text{the row } m \text{ retitled if present, else appended}] & \mathrm{milestone}(m, \mathit{title}) \\
\pi[\mathit{spawns} := \mathit{spawns} \mathbin{+\!\!+} [(a, n)]] & \mathrm{spawn}(a, n) \\
\pi[\mathit{stops} := \mathit{stops} \mathbin{+\!\!+} [(a, n)]] & \mathrm{stop}(a, n) \\
\pi[\mathit{marks} := \mathit{marks} \mathbin{+\!\!+} [(x, \mathrm{handedBack}(a, p))]] & \mathrm{handback}(x, a, p) \\
\pi[\mathit{marks} := \mathit{marks} \mathbin{+\!\!+} [(x, \mathrm{integrated}(b, p))]] & \mathrm{integrate}(x, b, p) \\
\pi[\mathit{marks} := \mathit{marks} \mathbin{+\!\!+} [(x, \mathrm{parked}(r))]] & \mathrm{park}(x, r) \\
\pi[\mathit{marks} := \mathit{marks} \mathbin{+\!\!+} [(x, \bot)]] & \mathrm{unpark}(x) \\
\pi[\mathit{labels} := \mathit{labels} \mathbin{+\!\!+} [(k, a)]] & \mathrm{label}(k, a)
\end{cases}$$
-/
def exec (s : State) (c : Cmd) : State :=
  match c with
  | .define d => { s with tasks := upsert s.tasks d }
  | .drop x => { s with tasks := s.tasks.filter fun t => t.id != x }
  | .claim x a n => { s with tasks := setRow s.tasks x (fun t => { t with agent := some a }),
                             claims := s.claims ++ [(a, n)] }
  | .done x e => { s with tasks := setRow s.tasks x fun t => { t with evidence := some e, landed := true } }
  | .milestone m title =>
    if s.milestones.any (·.id == m) then
      { s with milestones := s.milestones.map fun r => if r.id = m then { r with title } else r }
    else { s with milestones := s.milestones ++ [{ id := m, title }] }
  | .spawn a n => { s with spawns := s.spawns ++ [(a, n)] }
  | .stop a n => { s with stops := s.stops ++ [(a, n)] }
  | .handback x a p => { s with marks := s.marks ++ [(x, some (.handedBack a p))] }
  | .integrate x b p => { s with marks := s.marks ++ [(x, some (.integrated b p))] }
  | .park x r => { s with marks := s.marks ++ [(x, some (.parked r))] }
  | .unpark x => { s with marks := s.marks ++ [(x, none)] }
  | .label k a => { s with labels := s.labels ++ [(k, a)] }

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

$$\mathrm{TState} = \{\mathrm{done}, \mathrm{cut}, \mathrm{running}, \mathrm{handedBack}, \mathrm{integrated}, \mathrm{parked}, \mathrm{ready}, \mathrm{blocked}\}$$
-/
inductive TState where
  | done | cut | running | handedBack | integrated | parked | ready | blocked
deriving Repr, DecidableEq

/-- The wire name of a task state.

$$\operatorname{name}(\mathrm{done}) = \texttt{"done"},\ \operatorname{name}(\mathrm{cut}) = \texttt{"cut"},\ \operatorname{name}(\mathrm{running}) = \texttt{"running"},\ \operatorname{name}(\mathrm{ready}) = \texttt{"ready"},\ \operatorname{name}(\mathrm{blocked}) = \texttt{"blocked"},\ \operatorname{name}(\mathrm{handedBack}) = \texttt{"handedBack"},\ \operatorname{name}(\mathrm{integrated}) = \texttt{"integrated"},\ \operatorname{name}(\mathrm{parked}) = \texttt{"parked"}$$
-/
def TState.name : TState → String
  | .done => "done" | .cut => "cut" | .running => "running" | .ready => "ready" | .blocked => "blocked"
  | .handedBack => "handedBack" | .integrated => "integrated" | .parked => "parked"

/-- The park reason of a task whose work was folded into another task with no change of its own
(task `task-state-truth`): such a park clears the task as a dependency (`cleared`).

$$\operatorname{foldedNoChange} = \texttt{"folded-no-change"}$$

The reason the lead gives when a task needs no work because another task did it.
-/
def foldedNoChange : String := "folded-no-change"

/-- A dependency is cleared when a row of that id is done, or carries the mark
$\mathrm{parked}(\operatorname{foldedNoChange})$ (its work was folded into another task with no change
of its own, so waiting for it would wait forever).

$$\operatorname{cleared}(ts, x) = \mathrm{true} \iff \exists r \in ts:\ r.\mathit{id} = x \land \big(r.\mathit{evidence} \ne \bot \lor r.\mathit{mark} = \mathrm{parked}(\operatorname{foldedNoChange})\big)$$

A dep stops blocking when it is done or folded away.
-/
def cleared (ts : List Task) (x : String) : Bool :=
  ts.any fun r => r.id == x && (r.evidence.isSome || r.mark == some (.parked foldedNoChange))

/-- The blockers of a task: its deps that are not cleared (neither done nor parked as folded), in dep
order.

$$\operatorname{blockers}(ts, t) = [\, d \in t.\mathit{deps} : \neg\operatorname{cleared}(ts, d) \,]$$
-/
def blockers (ts : List Task) (t : Task) : List String := t.deps.filter fun d => !cleared ts d

/-- The state a mark shows.

$$\operatorname{mstate}(\mathrm{handedBack}(\cdot,\cdot)) = \mathrm{handedBack},\quad \operatorname{mstate}(\mathrm{integrated}(\cdot,\cdot)) = \mathrm{integrated},\quad \operatorname{mstate}(\mathrm{parked}(\cdot)) = \mathrm{parked}$$
-/
def Mark.state : Mark → TState
  | .handedBack .. => .handedBack | .integrated .. => .integrated | .parked _ => .parked

/-- The state of a task is computed, never written (first match wins). A task with an agent is
running when it has no blockers and blocked otherwise (task `task-state-truth`: a task with open
blockers is never shown running, and for a live agent the blockers win over any outcome mark); a
task without an agent shows its outcome mark, if any, then ready or blocked.

$$\operatorname{tstate}(ts, t) = \begin{cases} \mathrm{done} & t.\mathit{evidence} \ne \bot \\ \mathrm{cut} & t.\mathit{cut} \\ \mathrm{running} & t.\mathit{agent} \ne \bot \land \operatorname{blockers}(ts, t) = [\,] \\ \mathrm{blocked} & t.\mathit{agent} \ne \bot \land \operatorname{blockers}(ts, t) \ne [\,] \\ \operatorname{mstate}(m) & t.\mathit{mark} = m \ne \bot \\ \mathrm{ready} & \operatorname{blockers}(ts, t) = [\,] \\ \mathrm{blocked} & \text{otherwise} \end{cases}$$
-/
def tstate (ts : List Task) (t : Task) : TState :=
  if t.evidence.isSome then .done
  else if t.cut then .cut
  else if t.agent.isSome then (if blockers ts t = [] then .running else .blocked)
  else match t.mark with
    | some m => m.state
    | none => if blockers ts t = [] then .ready else .blocked

/-- `isDone` as a proposition.

$$\forall ts, x:\quad \operatorname{isDone}(ts, x) = \mathrm{true} \iff \exists t \in ts:\ t.\mathit{id} = x \land t.\mathit{evidence} \ne \bot$$
-/
theorem isDone_iff {ts : List Task} {x : String} :
    isDone ts x = true ↔ ∃ t ∈ ts, t.id = x ∧ t.evidence ≠ none := by
  simp [isDone, Option.isSome_iff_ne_none]

/-- `cleared` as a proposition.

$$\forall ts, x:\quad \operatorname{cleared}(ts, x) = \mathrm{true} \iff \exists t \in ts:\ t.\mathit{id} = x \land \big(t.\mathit{evidence} \ne \bot \lor t.\mathit{mark} = \mathrm{parked}(\operatorname{foldedNoChange})\big)$$
-/
theorem cleared_iff {ts : List Task} {x : String} :
    cleared ts x = true ↔
      ∃ t ∈ ts, t.id = x ∧ (t.evidence ≠ none ∨ t.mark = some (.parked foldedNoChange)) := by
  simp [cleared, Option.isSome_iff_ne_none]

/-- A done dependency is cleared.

$$\forall ts, x:\quad \operatorname{isDone}(ts, x) = \mathrm{true} \Rightarrow \operatorname{cleared}(ts, x) = \mathrm{true}$$
-/
theorem cleared_of_isDone {ts : List Task} {x : String} (h : isDone ts x = true) :
    cleared ts x = true := by
  obtain ⟨t, ht, hid, he⟩ := isDone_iff.mp h
  exact cleared_iff.mpr ⟨t, ht, hid, .inl he⟩

/-- **A folded park clears the dependency** (task `task-state-truth`): a row parked with reason
`foldedNoChange` no longer blocks the tasks that depend on it.

$$\forall ts, r:\quad r \in ts \land r.\mathit{mark} = \mathrm{parked}(\operatorname{foldedNoChange}) \Rightarrow \operatorname{cleared}(ts, r.\mathit{id}) = \mathrm{true}$$
-/
theorem cleared_of_folded {ts : List Task} {r : Task} (hr : r ∈ ts)
    (hm : r.mark = some (.parked foldedNoChange)) : cleared ts r.id = true :=
  cleared_iff.mpr ⟨r, hr, rfl, .inr hm⟩

/-- The blockers are exactly the deps that are not cleared.

$$\forall ts, t, d:\quad d \in \operatorname{blockers}(ts, t) \iff d \in t.\mathit{deps} \land \operatorname{cleared}(ts, d) = \mathrm{false}$$
-/
theorem mem_blockers {ts : List Task} {t : Task} {d : String} :
    d ∈ blockers ts t ↔ d ∈ t.deps ∧ cleared ts d = false := by
  simp [blockers]

/-- `blockers` is empty exactly when every dep is cleared.

$$\forall ts, t:\quad \operatorname{blockers}(ts, t) = [\,] \iff \forall d \in t.\mathit{deps}:\ \operatorname{cleared}(ts, d) = \mathrm{true}$$
-/
theorem blockers_nil_iff (ts : List Task) (t : Task) :
    blockers ts t = [] ↔ ∀ d ∈ t.deps, cleared ts d = true := by
  simp [blockers, List.filter_eq_nil_iff]

/-- A mark never shows ready, blocked, running, done or cut.

$$\forall m:\quad \operatorname{mstate}(m) \in \{\mathrm{handedBack}, \mathrm{integrated}, \mathrm{parked}\}$$
-/
theorem Mark.state_mem (m : Mark) : m.state = .handedBack ∨ m.state = .integrated ∨ m.state = .parked := by
  cases m <;> simp [Mark.state]

/-- **Ready means: not done, not cut, no agent, no outcome mark, and every dep cleared.**

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{ready} \iff t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{false} \land t.\mathit{agent} = \bot \land t.\mathit{mark} = \bot \land \forall d \in t.\mathit{deps}:\ \operatorname{cleared}(ts, d) = \mathrm{true}$$
-/
theorem tstate_ready_iff (ts : List Task) (t : Task) : tstate ts t = .ready ↔
    t.evidence = none ∧ t.cut = false ∧ t.agent = none ∧ t.mark = none ∧
      ∀ d ∈ t.deps, cleared ts d = true := by
  rw [← blockers_nil_iff]
  unfold tstate
  cases he : t.evidence <;> cases hc : t.cut <;> cases ha : t.agent <;> cases hm : t.mark <;>
    by_cases hb : blockers ts t = [] <;> simp [hb] <;>
    rcases Mark.state_mem ‹Mark› with h | h | h <;> simp [h]

/-- **Cut means: not done and flagged cut.** (Evidence wins: a task done before it was cut stays done.)

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{cut} \iff t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{true}$$
-/
theorem tstate_cut_iff (ts : List Task) (t : Task) :
    tstate ts t = .cut ↔ t.evidence = none ∧ t.cut = true := by
  unfold tstate
  cases he : t.evidence <;> cases hc : t.cut <;> cases ha : t.agent <;> cases hm : t.mark <;>
    by_cases hb : blockers ts t = [] <;> simp [hb] <;>
    rcases Mark.state_mem ‹Mark› with h | h | h <;> simp [h]

/-- **A cut task is never ready.**

$$\forall ts, t:\quad t.\mathit{cut} = \mathrm{true} \Rightarrow \operatorname{tstate}(ts, t) \ne \mathrm{ready}$$
-/
theorem cut_not_ready {ts : List Task} {t : Task} (h : t.cut = true) : tstate ts t ≠ .ready := by
  intro hr
  have := ((tstate_ready_iff ts t).mp hr).2.1
  rw [h] at this; cases this

/-- **A blocked task has a blocker, and its blockers are exactly its deps that are not cleared.**

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{blocked} \Rightarrow \operatorname{blockers}(ts, t) \ne [\,] \land \forall d:\ \big(d \in \operatorname{blockers}(ts, t) \iff d \in t.\mathit{deps} \land \operatorname{cleared}(ts, d) = \mathrm{false}\big)$$
-/
theorem tstate_blocked {ts : List Task} {t : Task} (h : tstate ts t = .blocked) :
    blockers ts t ≠ [] ∧ ∀ d, d ∈ blockers ts t ↔ d ∈ t.deps ∧ cleared ts d = false := by
  refine ⟨?_, fun _ => mem_blockers⟩
  intro hn
  unfold tstate at h
  cases he : t.evidence <;> cases hc : t.cut <;> cases ha : t.agent <;> cases hm : t.mark <;>
    simp [he, hc, ha, hm, hn] at h <;>
    rcases Mark.state_mem ‹Mark› with h' | h' | h' <;> simp [h'] at h

/-- **Done is exactly "has evidence".**

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{done} \iff t.\mathit{evidence} \ne \bot$$
-/
theorem tstate_done_iff (ts : List Task) (t : Task) : tstate ts t = .done ↔ t.evidence ≠ none := by
  unfold tstate
  cases he : t.evidence <;> cases hc : t.cut <;> cases ha : t.agent <;> cases hm : t.mark <;>
    by_cases hb : blockers ts t = [] <;> simp [hb] <;>
    rcases Mark.state_mem ‹Mark› with h | h | h <;> simp [h]

/-- **Running is exactly "has an agent, no blockers, not done and not cut".**

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{running} \iff t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{false} \land t.\mathit{agent} \ne \bot \land \operatorname{blockers}(ts, t) = [\,]$$
-/
theorem tstate_running_iff (ts : List Task) (t : Task) :
    tstate ts t = .running ↔
      t.evidence = none ∧ t.cut = false ∧ t.agent ≠ none ∧ blockers ts t = [] := by
  unfold tstate
  cases he : t.evidence <;> cases hc : t.cut <;> cases ha : t.agent <;> cases hm : t.mark <;>
    by_cases hb : blockers ts t = [] <;> simp [hb] <;>
    rcases Mark.state_mem ‹Mark› with h | h | h <;> simp [h]

/-- **A task with open blockers is never shown running** (task `task-state-truth`).

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) = \mathrm{running} \Rightarrow \operatorname{blockers}(ts, t) = [\,]$$
-/
theorem running_no_blockers {ts : List Task} {t : Task} (h : tstate ts t = .running) :
    blockers ts t = [] := ((tstate_running_iff ts t).mp h).2.2.2

/-- **For a live agent, open blockers win over an outcome mark** (task `task-state-truth`): an
undone, uncut task with an agent and an open blocker shows blocked, whatever mark it has.

$$\forall ts, t:\quad t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{false} \land t.\mathit{agent} \ne \bot \land \operatorname{blockers}(ts, t) \ne [\,] \Rightarrow \operatorname{tstate}(ts, t) = \mathrm{blocked}$$
-/
theorem tstate_agent_blocked {ts : List Task} {t : Task} (he : t.evidence = none)
    (hc : t.cut = false) (ha : t.agent ≠ none) (hb : blockers ts t ≠ []) :
    tstate ts t = .blocked := by
  unfold tstate
  cases ha' : t.agent
  · exact absurd ha' ha
  · simp [he, hc, hb]

/-- **An outcome mark shows only without an agent**: a task shown handed back, integrated or parked
has no agent (a live agent shows running or blocked).

$$\forall ts, t:\quad \operatorname{tstate}(ts, t) \in \{\mathrm{handedBack}, \mathrm{integrated}, \mathrm{parked}\} \Rightarrow t.\mathit{agent} = \bot$$
-/
theorem tstate_mark_no_agent {ts : List Task} {t : Task}
    (h : tstate ts t = .handedBack ∨ tstate ts t = .integrated ∨ tstate ts t = .parked) :
    t.agent = none := by
  cases ha : t.agent with
  | none => rfl
  | some a =>
    exfalso
    unfold tstate at h
    cases he : t.evidence <;> cases hc : t.cut <;> by_cases hb : blockers ts t = [] <;>
      simp [ha, he, hc, hb] at h

/-- **An undone, uncut task without an agent shows its mark when it has one.**

$$\forall ts, t, m:\quad t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{false} \land t.\mathit{agent} = \bot \land t.\mathit{mark} = m \Rightarrow \operatorname{tstate}(ts, t) = \operatorname{mstate}(m)$$
-/
theorem tstate_mark {ts : List Task} {t : Task} {m : Mark} (he : t.evidence = none)
    (hc : t.cut = false) (ha : t.agent = none) (hm : t.mark = some m) :
    tstate ts t = m.state := by
  unfold tstate
  simp [he, hc, ha, hm]

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
  obtain ⟨_, _, _, _, hall⟩ := (tstate_ready_iff ts a).mp hra
  obtain ⟨hbe, _, _, hbm, _⟩ := (tstate_ready_iff ts b).mp hrb
  obtain ⟨r, hr, hid, hev⟩ := cleared_iff.mp (hall _ hd)
  rw [row_unique hn hr hb hid] at hev
  rcases hev with hev | hev
  · exact hev hbe
  · rw [hbm] at hev; cases hev

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
    have hf : ∀ t : Task, ({ t with evidence := some e, landed := true } : Task).id = t.id ∧
        ({ t with evidence := some e, landed := true } : Task).deps = t.deps := fun _ => ⟨rfl, rfl⟩
    refine ⟨?_, fun b h => ha b (tg_mono (fun _ _ => dep_setRow hf) h)⟩
    simp only [exec]
    rw [ids_setRow (fun t _ => (hf t).1)]
    exact hn
  | milestone m title =>
    simp only [exec]
    split <;> exact ⟨hn, ha⟩
  | spawn a => exact ⟨hn, ha⟩
  | stop a | label _ _ | handback _ _ _ | integrate _ _ _ | park _ _ | unpark _ => exact ⟨hn, ha⟩

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

/-! ## Done and landed: what survives a command -/

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

/-- A task id has landed evidence: some row with that id has evidence that came from a land event.

$$\operatorname{isLanded}(ts, x) \iff \exists t \in ts:\ t.\mathit{id} = x \land t.\mathit{landed} = \mathrm{true} \land t.\mathit{evidence} \ne \bot$$
-/
def isLanded (ts : List Task) (x : String) : Bool :=
  ts.any fun t => t.id == x && t.landed && t.evidence.isSome

/-- `isLanded` as a proposition.

$$\forall ts, x:\quad \operatorname{isLanded}(ts, x) = \mathrm{true} \iff \exists t \in ts:\ t.\mathit{id} = x \land t.\mathit{landed} = \mathrm{true} \land t.\mathit{evidence} \ne \bot$$
-/
theorem isLanded_iff {ts : List Task} {x : String} :
    isLanded ts x = true ↔ ∃ t ∈ ts, t.id = x ∧ t.landed = true ∧ t.evidence ≠ none := by
  simp [isLanded, Option.isSome_iff_ne_none, and_assoc]

/-- **A landed task is done.**

$$\forall ts, x:\quad \operatorname{isLanded}(ts, x) \Rightarrow \operatorname{isDone}(ts, x)$$
-/
theorem isLanded_isDone {ts : List Task} {x : String} (h : isLanded ts x = true) :
    isDone ts x = true := by
  obtain ⟨t, ht, hid, _, he⟩ := isLanded_iff.mp h
  exact isDone_iff.mpr ⟨t, ht, hid, he⟩

/-- An accepted definition has no commit evidence off main.

$$\forall \pi, d:\quad \operatorname{check}(\pi, \mathrm{define}(d)) = \bot \Rightarrow \operatorname{offMain}(d) = \bot$$
-/
theorem check_define_offMain {π : State} {d : Def} (h : check π (.define d) = none) :
    d.offMain = none := by
  simp only [check] at h
  split at h; · cases h
  split at h; · cases h
  split at h; · cases h
  split at h; · cases h
  split at h; · cases h
  split at h
  · cases h
  · assumption

/-- Evidence that is not off main: none, another kind than a commit, or on main.

$$\forall d, e:\quad \operatorname{offMain}(d) = \bot \land d.\mathit{evidence} = e \Rightarrow \operatorname{kind}(e) \ne \mathrm{commit} \lor d.\mathit{onMain} = \mathrm{true}$$
-/
theorem offMain_none {d : Def} {e : String} (h : d.offMain = none) (he : d.evidence = some e) :
    Lint.evKind e ≠ .commit ∨ d.onMain = true := by
  simp only [Def.offMain, he] at h
  by_cases hk : Lint.evKind e = .commit
  · right
    cases hm : d.onMain
    · simp [hk, hm] at h
    · rfl
  · exact .inl hk

/-- **A define with commit evidence off main is refused, and the state is kept.**

$$\forall \pi, d, e:\quad d.\mathit{evidence} = e \land \operatorname{kind}(e) = \mathrm{commit} \land d.\mathit{onMain} = \mathrm{false} \Rightarrow \operatorname{check}(\pi, \mathrm{define}(d)) \ne \bot \land \operatorname{step}(\pi, \mathrm{define}(d)) = \pi$$
-/
theorem define_offMain_refused {π : State} {d : Def} {e : String} (he : d.evidence = some e)
    (hk : Lint.evKind e = .commit) (hm : d.onMain = false) :
    check π (.define d) ≠ none ∧ step π (.define d) = π := by
  have hc : check π (.define d) ≠ none := by
    intro h
    have := check_define_offMain h
    simp [Def.offMain, he, hk, hm] at this
  exact ⟨hc, by simp [step, hc]⟩

/-- **The refusal names the sha**: within the size limits, a define with commit evidence off main
is refused with the reason `evidence not on main: <sha>`.

$$\forall \pi, d, e:\quad |d.\mathit{title}| \le 200 \land |d.\mathit{deps}| \le 32 \land |d.\mathit{writes}| \le 32 \land |d.\mathit{devices}| \le 8 \land |d.\mathit{needs}| \le 8 \land d.\mathit{evidence} = e \land \operatorname{kind}(e) = \mathrm{commit} \land d.\mathit{onMain} = \mathrm{false} \Rightarrow \operatorname{check}(\pi, \mathrm{define}(d)) = \texttt{"evidence not on main: "} \mathbin{+\!\!+} e$$
-/
theorem define_offMain_reason {π : State} {d : Def} {e : String}
    (h1 : d.title.length ≤ 200) (h2 : d.deps.length ≤ 32) (h3 : d.writes.length ≤ 32)
    (h4 : d.devices.length ≤ 8) (h5 : d.needs.length ≤ 8) (he : d.evidence = some e)
    (hk : Lint.evKind e = .commit) (hm : d.onMain = false) :
    check π (.define d) = some s!"evidence not on main: {e}" := by
  have ho : d.offMain = some e := by simp [Def.offMain, he, hk, hm]
  simp only [check, ho]
  simp [Nat.not_lt.mpr h1, Nat.not_lt.mpr h2, Nat.not_lt.mpr h3, Nat.not_lt.mpr h4,
    Nat.not_lt.mpr h5]

/-- **A define cannot mark a task done early**: when an accepted define makes task `x` done, it is
the define of `x` and its evidence is not a commit off main.

$$\forall \pi, d, x:\quad \operatorname{check}(\pi, \mathrm{define}(d)) = \bot \land \neg\operatorname{isDone}(\pi.\mathit{tasks}, x) \land \operatorname{isDone}(\operatorname{step}(\pi, \mathrm{define}(d)).\mathit{tasks}, x) \Rightarrow d.\mathit{task} = x \land \exists e:\ d.\mathit{evidence} = e \land (\operatorname{kind}(e) \ne \mathrm{commit} \lor d.\mathit{onMain} = \mathrm{true})$$
-/
theorem upsert_cannot_mark_done_early {π : State} {d : Def} {x : String}
    (hc : check π (.define d) = none) (hn : isDone π.tasks x = false)
    (hd : isDone (step π (.define d)).tasks x = true) :
    d.task = x ∧ ∃ e, d.evidence = some e ∧ (Lint.evKind e ≠ .commit ∨ d.onMain = true) := by
  have ho := check_define_offMain hc
  have hold : ∀ t ∈ π.tasks, t.id = x → t.evidence = none := by
    intro t ht hid
    cases he : t.evidence
    · rfl
    · have : isDone π.tasks x = true := isDone_iff.mpr ⟨t, ht, hid, by simp [he]⟩
      rw [hn] at this; cases this
  have fin : ∀ e, d.task = x → d.evidence = some e →
      d.task = x ∧ ∃ e, d.evidence = some e ∧ (Lint.evKind e ≠ .commit ∨ d.onMain = true) :=
    fun e h1 h2 => ⟨h1, e, h2, offMain_none ho h2⟩
  simp only [step, hc, ↓reduceIte, exec] at hd
  obtain ⟨t, ht, hid, he⟩ := isDone_iff.mp hd
  unfold upsert at ht
  split at ht
  · obtain ⟨t0, h0, rfl⟩ := List.mem_map.mp ht
    by_cases hx : t0.id = d.task
    · simp only [hx, ↓reduceIte, Def.row, keepEv] at hid he
      by_cases hl : t0.landed = true
      · simp only [hl, ↓reduceIte] at he
        exact absurd (hold t0 h0 (hx ▸ hid)) he
      · have hl' : t0.landed = false := by simpa using hl
        simp only [hl', Bool.false_eq_true, ↓reduceIte] at he
        obtain ⟨e, hev⟩ := Option.ne_none_iff_exists'.mp he
        exact fin e hid hev
    · simp only [hx, ↓reduceIte] at hid he
      exact absurd (hold t0 h0 hid) he
  · rcases List.mem_append.mp ht with ht | ht
    · exact absurd (hold t ht hid) he
    · simp only [List.mem_singleton] at ht
      subst ht
      simp only [Def.row] at hid he
      obtain ⟨e, hev⟩ := Option.ne_none_iff_exists'.mp he
      exact fin e hid hev

/-- **A define without evidence takes back evidence that did not land**: after an accepted define of
task `x` without evidence, every row of `x` whose evidence did not come from a land event has no
evidence, so its state is derived again (not done).

$$\forall \pi, d:\quad \operatorname{check}(\pi, \mathrm{define}(d)) = \bot \land d.\mathit{evidence} = \bot \Rightarrow \forall t \in \operatorname{step}(\pi, \mathrm{define}(d)).\mathit{tasks}:\ t.\mathit{id} = d.\mathit{task} \land t.\mathit{landed} = \mathrm{false} \Rightarrow t.\mathit{evidence} = \bot \land \forall ts:\ \operatorname{tstate}(ts, t) \ne \mathrm{done}$$
-/
theorem define_removes_unlanded_evidence {π : State} {d : Def} (hc : check π (.define d) = none)
    (he : d.evidence = none) :
    ∀ t ∈ (step π (.define d)).tasks, t.id = d.task → t.landed = false →
      t.evidence = none ∧ ∀ ts, tstate ts t ≠ .done := by
  intro t ht hid hl
  suffices h : t.evidence = none from
    ⟨h, fun ts hs => (tstate_done_iff ts t).mp hs h⟩
  simp only [step, hc, ↓reduceIte, exec] at ht
  unfold upsert at ht
  split at ht
  · obtain ⟨t0, _, rfl⟩ := List.mem_map.mp ht
    by_cases hx : t0.id = d.task
    · simp only [hx, ↓reduceIte, Def.row, keepEv] at hl ⊢
      simp [hl, he]
    · simp only [hx, ↓reduceIte] at hid
  · rename_i hin
    rcases List.mem_append.mp ht with ht | ht
    · exact absurd (List.contains_iff_mem.mpr (hid ▸ List.mem_map_of_mem (f := Task.id) ht)) hin
    · simp only [List.mem_singleton] at ht
      subst ht
      simpa [Def.row] using he

/-- **Done survives every accepted command but one**: a define of that task without evidence, when no
row of the task holds landed evidence (the work-graph edit that takes evidence back).

$$\forall \pi, c, x:\quad \operatorname{check}(\pi, c) = \bot \land \operatorname{isDone}(\pi.\mathit{tasks}, x) \land \big(\forall d:\ c = \mathrm{define}(d) \land d.\mathit{task} = x \Rightarrow d.\mathit{evidence} \ne \bot \lor \operatorname{isLanded}(\pi.\mathit{tasks}, x)\big) \Rightarrow \operatorname{isDone}(\operatorname{exec}(\pi, c).\mathit{tasks}, x)$$
-/
theorem exec_isDone {π : State} {c : Cmd} {x : String} (hc : check π c = none)
    (h : isDone π.tasks x = true)
    (hk : ∀ d, c = .define d → d.task = x → d.evidence ≠ none ∨ isLanded π.tasks x = true) :
    isDone (exec π c).tasks x = true := by
  cases c with
  | define d =>
    simp only [exec, upsert]
    split
    · -- a row of `x` that keeps evidence: the witness itself, or a landed row
      have keep : ∀ t ∈ π.tasks, t.id = x → t.evidence ≠ none →
          (t.landed = true ∨ d.task ≠ x ∨ d.evidence ≠ none) →
          isDone (setRow π.tasks d.task fun t => d.row (d.liveAgent <|> t.agent) (keepEv t d) t.landed) x
            = true := by
        intro t ht hid he hor
        refine isDone_iff.mpr ⟨_, List.mem_map_of_mem ht, ?_, ?_⟩
        · split
          · rename_i hx; simp only [Def.row]; rw [← hx]; exact hid
          · exact hid
        · split
          · rename_i hx
            simp only [Def.row, keepEv]
            split
            · exact he
            · rename_i hl
              rcases hor with hor | hor | hor
              · simp [hor] at hl
              · exact absurd (hx ▸ hid) hor
              · exact hor
          · exact he
      obtain ⟨t, ht, hid, he⟩ := isDone_iff.mp h
      by_cases hx : d.task = x
      · rcases hk d rfl hx with hk | hk
        · exact keep t ht hid he (.inr (.inr hk))
        · obtain ⟨t', ht', hid', hl', he'⟩ := isLanded_iff.mp hk
          exact keep t' ht' hid' he' (.inl hl')
      · exact keep t ht hid he (.inr (.inl hx))
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
  | spawn a => exact h
  | stop a | label _ _ | handback _ _ _ | integrate _ _ _ | park _ _ | unpark _ => exact h

/-- **Done survives every step but one**: a define of that task without evidence, when no row of
the task holds landed evidence.

$$\forall \pi, c, x:\quad \operatorname{isDone}(\pi.\mathit{tasks}, x) \land \big(\forall d:\ c = \mathrm{define}(d) \land d.\mathit{task} = x \Rightarrow d.\mathit{evidence} \ne \bot \lor \operatorname{isLanded}(\pi.\mathit{tasks}, x)\big) \Rightarrow \operatorname{isDone}(\operatorname{step}(\pi, c).\mathit{tasks}, x)$$
-/
theorem step_isDone {π : State} (c : Cmd) {x : String} (h : isDone π.tasks x = true)
    (hk : ∀ d, c = .define d → d.task = x → d.evidence ≠ none ∨ isLanded π.tasks x = true) :
    isDone (step π c).tasks x = true := by
  unfold step
  split
  · rename_i hc; exact exec_isDone hc h hk
  · exact h

/-- Landed evidence survives every accepted command.

$$\forall \pi, c, x:\quad \operatorname{check}(\pi, c) = \bot \land \operatorname{isLanded}(\pi.\mathit{tasks}, x) \Rightarrow \operatorname{isLanded}(\operatorname{exec}(\pi, c).\mathit{tasks}, x)$$
-/
theorem exec_isLanded {π : State} {c : Cmd} {x : String} (hc : check π c = none)
    (h : isLanded π.tasks x = true) : isLanded (exec π c).tasks x = true := by
  obtain ⟨t, ht, hid, hl, he⟩ := isLanded_iff.mp h
  -- a `setRow` whose map keeps id, provenance and evidence presence of a landed row keeps it landed
  have viaSet : ∀ (y : String) (f : Task → Task), (t.id = y → (f t).id = t.id ∧ (f t).landed = true ∧
      (f t).evidence ≠ none) → isLanded (setRow π.tasks y f) x = true := by
    intro y f hf
    refine isLanded_iff.mpr ⟨if t.id = y then f t else t, List.mem_map_of_mem ht, ?_⟩
    split
    · rename_i hy; obtain ⟨h1, h2, h3⟩ := hf hy; exact ⟨h1 ▸ hid, h2, h3⟩
    · exact ⟨hid, hl, he⟩
  cases c with
  | define d =>
    simp only [exec, upsert]
    split
    · exact viaSet _ _ fun hy => ⟨by simp [Def.row, hy], by simp [Def.row, hl],
        by simp [Def.row, keepEv, hl, he]⟩
    · exact isLanded_iff.mpr ⟨t, List.mem_append_left _ ht, hid, hl, he⟩
  | drop y =>
    have hy : isDone π.tasks y = false := by
      simp only [check] at hc
      split at hc; · cases hc
      split at hc; · cases hc
      rename_i h2; simpa using h2
    have hxy : x ≠ y := by
      rintro rfl; rw [isLanded_isDone h] at hy; cases hy
    refine isLanded_iff.mpr ⟨t, ?_, hid, hl, he⟩
    simp only [exec]
    exact List.mem_filter.mpr ⟨ht, by simp [hid, hxy]⟩
  | claim y a => exact viaSet _ _ fun _ => ⟨rfl, hl, he⟩
  | done y e => exact viaSet _ _ fun _ => ⟨rfl, rfl, by simp⟩
  | milestone m title => simp only [exec]; split <;> exact h
  | spawn a => exact h
  | stop a | label _ _ | handback _ _ _ | integrate _ _ _ | park _ _ | unpark _ => exact h

/-- **A land is never undone**: landed evidence survives every step, including a define without
evidence, so the task stays done.

$$\forall \pi, c, x:\quad \operatorname{isLanded}(\pi.\mathit{tasks}, x) \Rightarrow \operatorname{isLanded}(\operatorname{step}(\pi, c).\mathit{tasks}, x) \land \operatorname{isDone}(\operatorname{step}(\pi, c).\mathit{tasks}, x)$$
-/
theorem land_never_undone {π : State} (c : Cmd) {x : String} (h : isLanded π.tasks x = true) :
    isLanded (step π c).tasks x = true ∧ isDone (step π c).tasks x = true := by
  have : isLanded (step π c).tasks x = true := by
    unfold step
    split
    · rename_i hc; exact exec_isLanded hc h
    · exact h
  exact ⟨this, isLanded_isDone this⟩

/-- **A land is never undone by any later commands** (work-graph edits included).

$$\forall L_1, L_2, x:\quad \operatorname{isLanded}(\operatorname{run}(L_1).\mathit{tasks}, x) \Rightarrow \operatorname{isLanded}(\operatorname{run}(L_1 \mathbin{+\!\!+} L_2).\mathit{tasks}, x) \land \operatorname{isDone}(\operatorname{run}(L_1 \mathbin{+\!\!+} L_2).\mathit{tasks}, x)$$
-/
theorem run_land_never_undone (l₁ l₂ : List Cmd) {x : String} (h : isLanded (run l₁).tasks x = true) :
    isLanded (run (l₁ ++ l₂)).tasks x = true ∧ isDone (run (l₁ ++ l₂)).tasks x = true := by
  suffices ∀ (l : List Cmd) (π : State), isLanded π.tasks x = true →
      isLanded (l.foldl step π).tasks x = true by
    have hl : isLanded (run (l₁ ++ l₂)).tasks x = true := by
      simp only [run, List.foldl_append]; exact this l₂ _ h
    exact ⟨hl, isLanded_isDone hl⟩
  intro l
  induction l with
  | nil => intro π h; exact h
  | cons c l ih => intro π h; exact ih _ (land_never_undone c h).1

/-! ### Where done comes from -/

/-- Where the evidence `e` of row `t` comes from in command list `L`: a land event of the task with
that evidence (the row is landed), or a define of the task with that evidence that is not a commit
off main (the row is not landed).

$$\operatorname{src}(L, t, e) \iff \big(t.\mathit{landed} = \mathrm{true} \land \mathrm{done}(t.\mathit{id}, e) \in L\big) \lor \big(t.\mathit{landed} = \mathrm{false} \land \exists d:\ \mathrm{define}(d) \in L \land d.\mathit{task} = t.\mathit{id} \land d.\mathit{evidence} = e \land (\operatorname{kind}(e) \ne \mathrm{commit} \lor d.\mathit{onMain} = \mathrm{true})\big)$$
-/
def EvSrc (l : List Cmd) (t : Task) (e : String) : Prop :=
  (t.landed = true ∧ Cmd.done t.id e ∈ l) ∨
  (t.landed = false ∧ ∃ d, Cmd.define d ∈ l ∧ d.task = t.id ∧ d.evidence = some e ∧
    (Lint.evKind e ≠ .commit ∨ d.onMain = true))

/-- `EvSrc` reads a row only through its id and provenance, and grows with the list.

$$\forall L, L', t, r, e:\quad r.\mathit{id} = t.\mathit{id} \land r.\mathit{landed} = t.\mathit{landed} \land (\forall c \in L:\ c \in L') \land \operatorname{src}(L, t, e) \Rightarrow \operatorname{src}(L', r, e)$$
-/
theorem EvSrc.mono {l l' : List Cmd} {t r : Task} {e : String} (hid : r.id = t.id)
    (hl : r.landed = t.landed) (hs : ∀ c ∈ l, c ∈ l') (h : EvSrc l t e) : EvSrc l' r e := by
  rcases h with ⟨h1, h2⟩ | ⟨h1, d, h2, h3, h4, h5⟩
  · exact .inl ⟨hl ▸ h1, hid ▸ hs _ h2⟩
  · exact .inr ⟨hl ▸ h1, d, hs _ h2, hid ▸ h3, h4, h5⟩

/-- Every row's evidence has a source in the commands so far, and one more step keeps that.

$$\forall L, \pi, c:\quad (\forall t \in \pi.\mathit{tasks}, \forall e:\ t.\mathit{evidence} = e \Rightarrow \operatorname{src}(L, t, e)) \Rightarrow \forall t \in \operatorname{step}(\pi, c).\mathit{tasks}, \forall e:\ t.\mathit{evidence} = e \Rightarrow \operatorname{src}(L \mathbin{+\!\!+} [c], t, e)$$
-/
theorem step_evSrc {l : List Cmd} {π : State} (c : Cmd)
    (h : ∀ t ∈ π.tasks, ∀ e, t.evidence = some e → EvSrc l t e) :
    ∀ t ∈ (step π c).tasks, ∀ e, t.evidence = some e → EvSrc (l ++ [c]) t e := by
  have sub : ∀ c' ∈ l, c' ∈ l ++ [c] := fun _ h => List.mem_append_left _ h
  have old : ∀ t ∈ π.tasks, ∀ e, t.evidence = some e → EvSrc (l ++ [c]) t e :=
    fun t ht e he => (h t ht e he).mono rfl rfl sub
  -- a `setRow` whose map keeps id, provenance and evidence keeps every source
  have viaSet : ∀ (y : String) (f : Task → Task), (∀ t, (f t).id = t.id ∧ (f t).landed = t.landed ∧
      (f t).evidence = t.evidence) → ∀ t ∈ setRow π.tasks y f, ∀ e, t.evidence = some e →
      EvSrc (l ++ [c]) t e := by
    intro y f hf t ht e he
    obtain ⟨t0, h0, rfl⟩ := List.mem_map.mp ht
    split at he
    · obtain ⟨h1, h2, h3⟩ := hf t0
      rw [h3] at he
      simp only [*, ↓reduceIte]
      exact (old t0 h0 e he).mono h1 h2 (fun _ h => h)
    · simp only [*, ↓reduceIte]
  unfold step
  split
  · rename_i hc
    cases c with
    | define d =>
      have ho := check_define_offMain hc
      simp only [exec]
      unfold upsert
      split
      · intro t ht e he
        obtain ⟨t0, h0, rfl⟩ := List.mem_map.mp ht
        split at he
        · rename_i hx
          simp only [Def.row, keepEv] at he
          simp only [hx, ↓reduceIte]
          split at he
          · rename_i hl
            rcases h t0 h0 e he with ⟨_, h2⟩ | ⟨h1, _⟩
            · exact .inl ⟨by simp [Def.row, hl], by simpa [Def.row, hx] using sub _ h2⟩
            · simp [hl] at h1
          · rename_i hl
            exact .inr ⟨by simpa [Def.row] using hl, d, List.mem_append_right _ (List.mem_singleton_self _),
              by simp [Def.row, hx], he, offMain_none ho he⟩
        · rename_i hx
          simp only [hx, ↓reduceIte]
          exact old t0 h0 e he
      · intro t ht e he
        rcases List.mem_append.mp ht with ht | ht
        · exact old t ht e he
        · simp only [List.mem_singleton] at ht
          subst ht
          simp only [Def.row] at he
          exact .inr ⟨rfl, d, List.mem_append_right _ (List.mem_singleton_self _), rfl, he,
            offMain_none ho he⟩
    | drop y =>
      intro t ht e he
      exact old t (List.mem_filter.mp ht).1 e he
    | claim y a => exact viaSet y _ fun _ => ⟨rfl, rfl, rfl⟩
    | done y e' =>
      simp only [exec]
      intro t ht e he
      obtain ⟨t0, h0, rfl⟩ := List.mem_map.mp ht
      split at he
      · rename_i hx
        simp only [Option.some.injEq] at he
        subst he
        simp only [hx, ↓reduceIte]
        exact .inl ⟨rfl, List.mem_append_right _ (List.mem_singleton_self _)⟩
      · rename_i hx
        simp only [hx, ↓reduceIte]
        exact old t0 h0 e he
    | milestone m title =>
      simp only [exec]
      split <;> exact old
    | spawn a => exact old
    | stop a | label _ _ | handback _ _ _ | integrate _ _ _ | park _ _ | unpark _ => exact old
  · exact old

/-- **Done needs landed evidence**: in every reachable plan state, a row with evidence `e` either
landed it (a `task.done` of the task with `e` is in the log) or got it from a define of the task in
the log whose evidence `e` is not a commit off main.

$$\forall L, t, e:\quad t \in \operatorname{run}(L).\mathit{tasks} \land t.\mathit{evidence} = e \Rightarrow \big(t.\mathit{landed} = \mathrm{true} \land \mathrm{done}(t.\mathit{id}, e) \in L\big) \lor \big(t.\mathit{landed} = \mathrm{false} \land \exists d:\ \mathrm{define}(d) \in L \land d.\mathit{task} = t.\mathit{id} \land d.\mathit{evidence} = e \land (\operatorname{kind}(e) \ne \mathrm{commit} \lor d.\mathit{onMain} = \mathrm{true})\big)$$
-/
theorem done_needs_landed_evidence (l : List Cmd) {t : Task} {e : String}
    (ht : t ∈ (run l).tasks) (he : t.evidence = some e) :
    (t.landed = true ∧ Cmd.done t.id e ∈ l) ∨
    (t.landed = false ∧ ∃ d, Cmd.define d ∈ l ∧ d.task = t.id ∧ d.evidence = some e ∧
      (Lint.evKind e ≠ .commit ∨ d.onMain = true)) := by
  suffices ∀ (l acc : List Cmd) (π : State), (∀ t ∈ π.tasks, ∀ e, t.evidence = some e → EvSrc acc t e) →
      ∀ t ∈ (l.foldl step π).tasks, ∀ e, t.evidence = some e → EvSrc (acc ++ l) t e from
    this l [] {} (fun _ h => by simp at h) t ht e he
  intro l
  induction l with
  | nil => intro acc π h; simpa using h
  | cons c l ih =>
    intro acc π h
    have := ih (acc ++ [c]) (step π c) (step_evSrc c h)
    simpa using this

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
      d.row (d.liveAgent <|> t.agent) (keepEv t d) t.landed else t) h0, by simp [hid0, Def.row]⟩, ?_⟩
    intro t ht hid
    obtain ⟨t1, _, rfl⟩ := List.mem_map.mp ht
    split at hid
    · rename_i h1; simp [h1, Def.row, ha]
    · rename_i hne; exact absurd hid hne
  · rename_i hc
    refine ⟨⟨d.row d.liveAgent d.evidence false, by simp, rfl⟩, ?_⟩
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

/-! ## Agent binding: derived from spawns, stops, explicit claims and evidence

Task `task-state-truth`: liveness is decided per life key. A key is the agent id of the hook
records (or a name, for facts without an id: a spawn guard, a workflow run, a claim). A key is live
when it was seen (a spawn: its start or any later event of it; or a claim of it) and no stop came at
or after its last sighting. A name (a task's claim or id) is live when one of its keys is: the name
itself or an agent id labelled with it (`label`, from the console's health index). The times make
this independent of the order in which the spawn and stop commands reach the log (`view_perm`), so a
drain that reads the hook spool file by file still gives the board of the real timeline.
-/

/-- A spawn or a stop command (the commands that touch only the spawn and stop lists).

$$\operatorname{isLife}(c) = \mathrm{true} \iff \exists a, n:\ c = \mathrm{spawn}(a, n) \lor c = \mathrm{stop}(a, n)$$
-/
def Cmd.isLife : Cmd → Bool
  | .spawn .. | .stop .. => true
  | _ => false

/-- The (agent, time) pair a spawn command names.

$$\operatorname{spawnOf}(c) = \begin{cases} (a, n) & c = \mathrm{spawn}(a, n) \\ \bot & \text{otherwise} \end{cases}$$
-/
def Cmd.spawnOf : Cmd → Option (String × Nat)
  | .spawn a n => some (a, n)
  | _ => none

/-- The (agent, time) pair a stop command names.

$$\operatorname{stopOf}(c) = \begin{cases} (a, n) & c = \mathrm{stop}(a, n) \\ \bot & \text{otherwise} \end{cases}$$
-/
def Cmd.stopOf : Cmd → Option (String × Nat)
  | .stop a n => some (a, n)
  | _ => none

/-- The sightings of life keys: every claim (a claim sights the claimed name at its claim time),
then every spawn.

$$\operatorname{sights}(\pi) = \pi.\mathit{claims} \mathbin{+\!\!+} \pi.\mathit{spawns}$$

Each (key, time) pair that shows a key alive at that time.
-/
def sights (s : State) : List (String × Nat) := s.claims ++ s.spawns

/-- A life key was seen: some sighting names it.

$$\operatorname{openedK}(\pi, k) = \mathrm{true} \iff \exists n:\ (k, n) \in \operatorname{sights}(\pi)$$

A key with a spawn or a claim.
-/
def openedK (s : State) (k : String) : Bool := (sights s).any (·.1 == k)

/-- **A life key has ended**: some stop of it is at or after every sighting of it (so a key seen again
after its stop, at a later time, has not ended; a stop with no sighting at all ends the key).

$$\operatorname{endedK}(\pi, k) = \mathrm{true} \iff \exists (k, m) \in \pi.\mathit{stops}:\ \forall (k, n) \in \operatorname{sights}(\pi):\ n \le m$$
-/
def endedK (s : State) (k : String) : Bool :=
  s.stops.any fun q => q.1 == k && (sights s).all fun p => p.1 != k || decide (p.2 ≤ q.2)

/-- **A life key is live**: seen and not ended.

$$\operatorname{liveK}(\pi, k) = \mathrm{true} \iff \operatorname{openedK}(\pi, k) = \mathrm{true} \land \operatorname{endedK}(\pi, k) = \mathrm{false}$$
-/
def liveK (s : State) (k : String) : Bool := openedK s k && !endedK s k

/-- The time a life key was last seen: the largest time of its sightings, $0$ when it has none.

$$\operatorname{lastAt}(\pi, k) = \max\big(\{0\} \cup \{\, n : (k, n) \in \operatorname{sights}(\pi) \,\}\big)$$
-/
def lastAt (s : State) (k : String) : Nat :=
  ((sights s).filter (·.1 == k)).foldr (fun p m => max p.2 m) 0

/-- The life keys of a name: the name itself, then every key labelled with it, in label order.

$$\operatorname{keysOf}(\pi, a) = [a] \mathbin{+\!\!+} [\, k : (k, b) \in \pi.\mathit{labels},\ b = a \,]$$
-/
def keysOf (s : State) (a : String) : List String := a :: (s.labels.filter (·.2 == a)).map (·.1)

/-- A name was seen: one of its keys was.

$$\operatorname{opened}(\pi, a) = \mathrm{true} \iff \exists k \in \operatorname{keysOf}(\pi, a):\ \operatorname{openedK}(\pi, k) = \mathrm{true}$$
-/
def opened (s : State) (a : String) : Bool := (keysOf s a).any (openedK s)

/-- **A name has ended** when none of its keys is live (a name never seen has ended too).

$$\operatorname{ended}(\pi, a) = \mathrm{true} \iff \forall k \in \operatorname{keysOf}(\pi, a):\ \operatorname{liveK}(\pi, k) = \mathrm{false}$$
-/
def ended (s : State) (a : String) : Bool := !(keysOf s a).any (liveK s)

/-- When a seen name was last seen: the largest last-seen time of its keys; none for a name never
seen.

$$\operatorname{seenAt}(\pi, a) = \begin{cases} \max\big(\{0\} \cup \{\, \operatorname{lastAt}(\pi, k) : k \in \operatorname{keysOf}(\pi, a) \,\}\big) & \operatorname{opened}(\pi, a) = \mathrm{true} \\ \bot & \text{otherwise} \end{cases}$$
-/
def seenAt (s : State) (a : String) : Option Nat :=
  if opened s a then some ((keysOf s a).foldr (fun k m => max (lastAt s k) m) 0) else none

/-- The live keys of a name with their last-seen times, in key order (the input of the quiet
timeout).

$$\operatorname{liveKeys}(\pi, a) = [\, (k, \operatorname{lastAt}(\pi, k)) : k \in \operatorname{keysOf}(\pi, a),\ \operatorname{liveK}(\pi, k) = \mathrm{true} \,]$$
-/
def liveKeys (s : State) (a : String) : List (String × Nat) :=
  ((keysOf s a).filter (liveK s)).map fun k => (k, lastAt s k)

/-- The candidate agents of a row, in priority order: its stored agent (an explicit `task.claim`, or
a legacy live define) if that name was seen, then the task id itself if a name like it was seen.

$$\operatorname{cands}(\pi, t) = [\, a : t.\mathit{agent} = \mathrm{some}(a),\ \operatorname{opened}(\pi, a) = \mathrm{true} \,] \mathbin{+\!\!+} \begin{cases} [t.\mathit{id}] & \operatorname{opened}(\pi, t.\mathit{id}) = \mathrm{true} \\ [\,] & \text{otherwise} \end{cases}$$
-/
def cands (s : State) (t : Task) : List String :=
  t.agent.toList.filter (opened s) ++ (if opened s t.id then [t.id] else [])
/-- **The agent of a task, derived (never stored).** An undone task has its first candidate that has
not ended, if any; a done task has that one, or else its first candidate, so a stop never unbinds a
done task.

$$\operatorname{agentOf}(\pi, t) = \begin{cases} \operatorname{find}(C) \mathbin{\langle|\rangle} \operatorname{head}(C) & t.\mathit{evidence} \ne \bot \\ \operatorname{find}(C) & t.\mathit{evidence} = \bot \end{cases} \qquad C = \operatorname{cands}(\pi, t),\ \operatorname{find}(C) = \text{the first } a \in C \text{ with } \operatorname{ended}(\pi, a) = \mathrm{false} \ (\bot \text{ if none}),\ \operatorname{head}([\,]) = \bot,\ u \mathbin{\langle|\rangle} v = \begin{cases} u & u \ne \bot \\ v & u = \bot \end{cases}$$
-/
def agentOf (s : State) (t : Task) : Option String :=
  if t.evidence.isSome then (cands s t).find? (fun a => !ended s a) <|> (cands s t).head?
  else (cands s t).find? (fun a => !ended s a)

/-- The last outcome mark recorded for task id `x`: the mark of the last pair of `x` in the mark
log; none when that pair is an `unpark`, or when `x` has no pair.

$$\operatorname{markOf}(\pi, x) = \begin{cases} m_\bot & (x, m_\bot) \text{ is the last pair } (y, \cdot) \text{ of } \pi.\mathit{marks} \text{ with } y = x \\ \bot & \text{no pair of } \pi.\mathit{marks} \text{ has task } x \end{cases}$$
-/
def markOf (s : State) (x : String) : Option Mark :=
  ((s.marks.filter (·.1 == x)).getLast?).bind (·.2)

/-- The reason the board gives a task whose every candidate agent ended with no mark recorded.

$$\operatorname{noHandback} = \texttt{"agent ended without a handback"}$$
-/
def noHandback : String := "agent ended without a handback"

/-- The reason the board gives a task whose candidate agents were only claimed, never spawned, and
were ended by the quiet timeout.

$$\operatorname{expired} = \texttt{"claim expired: no live agent within the quiet limit"}$$
-/
def expired : String := "claim expired: no live agent within the quiet limit"

/-- A name was spawned: one of its keys has a spawn (a claim alone does not count).

$$\operatorname{spawned}(\pi, a) = \mathrm{true} \iff \exists k \in \operatorname{keysOf}(\pi, a), n:\ (k, n) \in \pi.\mathit{spawns}$$
-/
def spawned (s : State) (a : String) : Bool := (keysOf s a).any fun k => s.spawns.any (·.1 == k)

/-- Why a row whose candidates all ended is parked: `noHandback` when a candidate was ever spawned,
`expired` when they were only claimed.

$$\operatorname{endReason}(\pi, t) = \begin{cases} \operatorname{noHandback} & \exists a \in \operatorname{cands}(\pi, t):\ \operatorname{spawned}(\pi, a) = \mathrm{true} \\ \operatorname{expired} & \text{otherwise} \end{cases}$$
-/
def endReason (s : State) (t : Task) : String :=
  if (cands s t).any (spawned s) then noHandback else expired

/-- **The outcome mark of a row, derived (never stored)**: its last recorded mark; failing that, a
row that had a candidate agent (`cands`) and has no unended one (`agentOf` is none) is parked with
reason `endReason`; otherwise none.

$$\operatorname{outcomeOf}(\pi, t) = \begin{cases} m & \operatorname{markOf}(\pi, t.\mathit{id}) = m \ne \bot \\ \mathrm{parked}(\operatorname{endReason}(\pi, t)) & \operatorname{markOf}(\pi, t.\mathit{id}) = \bot \land \operatorname{cands}(\pi, t) \ne [\,] \land \operatorname{agentOf}(\pi, t) = \bot \\ \bot & \text{otherwise} \end{cases}$$
-/
def outcomeOf (s : State) (t : Task) : Option Mark :=
  markOf s t.id <|>
    (if !(cands s t).isEmpty && (agentOf s t).isNone then some (.parked (endReason s t)) else none)

/-- A row as the board shows it: with its derived agent and its derived outcome mark.

$$\operatorname{bindRow}(\pi, t) = t[\mathit{agent} := \operatorname{agentOf}(\pi, t),\ \mathit{mark} := \operatorname{outcomeOf}(\pi, t)]$$
-/
def bindRow (s : State) (t : Task) : Task := { t with agent := agentOf s t, mark := outcomeOf s t }

/-- The rows with their derived agents and outcome marks (the rows the board shows).

$$\operatorname{bound}(\pi) = [\, \operatorname{bindRow}(\pi, t) : t \in \pi.\mathit{tasks} \,]$$
-/
def bound (s : State) : List Task := s.tasks.map (bindRow s)

/-- The derived agent of task id `x`: that of the first row with id `x`; none when no row has it.

$$\operatorname{boundTo}(\pi, x) = \begin{cases} \operatorname{agentOf}(\pi, t) & t = \text{the first row of } \pi.\mathit{tasks} \text{ with } t.\mathit{id} = x \\ \bot & \text{no row of } \pi.\mathit{tasks} \text{ has id } x \end{cases}$$
-/
def boundTo (s : State) (x : String) : Option String := (s.tasks.find? (·.id == x)).bind (agentOf s)

/-- `lastAt` reads the sightings only as a multiset.

$$\forall \pi_1, \pi_2, k:\quad \operatorname{sights}(\pi_1) \sim \operatorname{sights}(\pi_2) \Rightarrow \operatorname{lastAt}(\pi_1, k) = \operatorname{lastAt}(\pi_2, k)$$

($\sim$: is a permutation of).
-/
theorem lastAt_perm {π₁ π₂ : State} (h : (sights π₁).Perm (sights π₂)) (k : String) :
    lastAt π₁ k = lastAt π₂ k := by
  unfold lastAt
  exact (h.filter _).foldr_eq' (fun x _ y _ z => by omega) 0

/-- **The derived agent, outcome reason and seen times read the spawn and stop lists only as
multisets** (with the same claims and labels).

$$\forall \pi_1, \pi_2:\quad \pi_1.\mathit{spawns} \sim \pi_2.\mathit{spawns} \land \pi_1.\mathit{stops} \sim \pi_2.\mathit{stops} \land \pi_1.\mathit{claims} = \pi_2.\mathit{claims} \land \pi_1.\mathit{labels} = \pi_2.\mathit{labels} \Rightarrow \operatorname{ended}(\pi_1, \cdot) = \operatorname{ended}(\pi_2, \cdot) \land \operatorname{opened}(\pi_1, \cdot) = \operatorname{opened}(\pi_2, \cdot) \land \operatorname{seenAt}(\pi_1, \cdot) = \operatorname{seenAt}(\pi_2, \cdot) \land \operatorname{agentOf}(\pi_1, \cdot) = \operatorname{agentOf}(\pi_2, \cdot) \land \operatorname{liveKeys}(\pi_1, \cdot) = \operatorname{liveKeys}(\pi_2, \cdot) \land \operatorname{endReason}(\pi_1, \cdot) = \operatorname{endReason}(\pi_2, \cdot)$$

($\sim$: is a permutation of).
-/
theorem life_congr {π₁ π₂ : State} (h1 : π₁.spawns.Perm π₂.spawns) (h2 : π₁.stops.Perm π₂.stops)
    (h3 : π₁.claims = π₂.claims) (h4 : π₁.labels = π₂.labels) :
    ended π₁ = ended π₂ ∧ opened π₁ = opened π₂ ∧ seenAt π₁ = seenAt π₂ ∧ agentOf π₁ = agentOf π₂ ∧
      liveKeys π₁ = liveKeys π₂ ∧ endReason π₁ = endReason π₂ := by
  have hs : (sights π₁).Perm (sights π₂) := by unfold sights; rw [h3]; exact h1.append_left _
  have hk : keysOf π₁ = keysOf π₂ := by funext a; simp only [keysOf, h4]
  have hoK : openedK π₁ = openedK π₂ := by funext k; unfold openedK; rw [hs.any_eq]
  have heK : endedK π₁ = endedK π₂ := by
    funext k
    unfold endedK
    rw [h2.any_eq]
    congr 1
    funext q
    rw [hs.all_eq]
  have hl : lastAt π₁ = lastAt π₂ := funext (lastAt_perm hs)
  have hlK : liveK π₁ = liveK π₂ := by funext k; simp only [liveK, hoK, heK]
  have he : ended π₁ = ended π₂ := by funext a; simp only [ended, hk, hlK]
  have ho : opened π₁ = opened π₂ := by funext a; simp only [opened, hk, hoK]
  have hc : cands π₁ = cands π₂ := by funext t; simp only [cands, ho]
  have hsp : spawned π₁ = spawned π₂ := by
    funext a; simp only [spawned, hk, h1.any_eq]
  refine ⟨he, ho, ?_, ?_, ?_, ?_⟩
  · funext a; simp only [seenAt, ho, hk, hl]
  · funext t; simp only [agentOf, hc, he]
  · funext a; simp only [liveKeys, hk, hlK, hl]
  · funext t; simp only [endReason, hc, hsp]

/-! ### Spawn and stop commute with every command -/

/-- `check` does not read the spawn and stop lists.

$$\forall \pi, c, x, y:\quad \operatorname{check}(\pi[\mathit{spawns} := x, \mathit{stops} := y], c) = \operatorname{check}(\pi, c)$$
-/
theorem check_life_irrel (π : State) (c : Cmd) (x y : List (String × Nat)) :
    check { π with spawns := x, stops := y } c = check π c := by
  cases c <;> rfl

/-- A command that is not a spawn or stop neither reads nor writes the spawn and stop lists.

$$\forall \pi, c, x, y:\quad \operatorname{isLife}(c) = \mathrm{false} \Rightarrow \operatorname{step}(\pi[\mathit{spawns} := x, \mathit{stops} := y], c) = \operatorname{step}(\pi, c)[\mathit{spawns} := x, \mathit{stops} := y]$$
-/
theorem step_life_irrel (π : State) {c : Cmd} (hc : c.isLife = false) (x y : List (String × Nat)) :
    step { π with spawns := x, stops := y } c = { step π c with spawns := x, stops := y } := by
  unfold step
  rw [check_life_irrel]
  split
  · cases c with
    | milestone m title =>
      simp only [exec]
      by_cases hm : π.milestones.any (·.id == m) <;> simp [hm]
    | spawn _ _ => simp [Cmd.isLife] at hc
    | stop _ _ => simp [Cmd.isLife] at hc
    | _ => rfl
  · rfl

/-- A command that is not a spawn or stop keeps the spawn and stop lists.

$$\forall \pi, c:\quad \operatorname{isLife}(c) = \mathrm{false} \Rightarrow \operatorname{step}(\pi, c).\mathit{spawns} = \pi.\mathit{spawns} \land \operatorname{step}(\pi, c).\mathit{stops} = \pi.\mathit{stops}$$
-/
theorem step_life_keep (π : State) {c : Cmd} (hc : c.isLife = false) :
    (step π c).spawns = π.spawns ∧ (step π c).stops = π.stops := by
  have h := step_life_irrel π hc π.spawns π.stops
  have e : ({ π with spawns := π.spawns, stops := π.stops } : State) = π := rfl
  rw [e] at h
  rw [h]
  exact ⟨rfl, rfl⟩

/-- A spawn is always accepted and only appends to the spawn list.

$$\forall \pi, a, n:\quad \operatorname{step}(\pi, \mathrm{spawn}(a, n)) = \pi[\mathit{spawns} := \pi.\mathit{spawns} \mathbin{+\!\!+} [(a, n)]]$$
-/
theorem step_spawn (π : State) (a : String) (n : Nat) :
    step π (.spawn a n) = { π with spawns := π.spawns ++ [(a, n)] } := by
  simp [step, check, exec]

/-- A stop is always accepted and only appends to the stop list.

$$\forall \pi, a, n:\quad \operatorname{step}(\pi, \mathrm{stop}(a, n)) = \pi[\mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} [(a, n)]]$$
-/
theorem step_stop (π : State) (a : String) (n : Nat) :
    step π (.stop a n) = { π with stops := π.stops ++ [(a, n)] } := by
  simp [step, check, exec]

/-- Folding commands that are not spawns or stops leaves the spawn and stop lists alone.

$$\forall cs, \pi, x, y:\quad (\forall c \in cs:\ \operatorname{isLife}(c) = \mathrm{false}) \Rightarrow \operatorname{foldl}(\operatorname{step}, \pi[\mathit{spawns} := x, \mathit{stops} := y], cs) = \operatorname{foldl}(\operatorname{step}, \pi, cs)[\mathit{spawns} := x, \mathit{stops} := y]$$
-/
theorem foldl_life_irrel : ∀ (cs : List Cmd) (π : State) (x y : List (String × Nat)),
    (∀ c ∈ cs, c.isLife = false) →
    cs.foldl step { π with spawns := x, stops := y } = { cs.foldl step π with spawns := x, stops := y }
  | [], _, _, _, _ => rfl
  | c :: cs, π, x, y, h => by
    simp only [List.foldl_cons]
    rw [step_life_irrel π (h c List.mem_cons_self) x y]
    exact foldl_life_irrel cs _ x y (fun c' hc' => h c' (List.mem_cons_of_mem _ hc'))

/-- **Folding splits into the other commands and the spawn/stop lists.**

$$\forall cs, \pi:\quad \operatorname{foldl}(\operatorname{step}, \pi, cs) = \operatorname{foldl}\big(\operatorname{step}, \pi, [\, c \in cs : \operatorname{isLife}(c) = \mathrm{false} \,]\big)\big[\mathit{spawns} := \pi.\mathit{spawns} \mathbin{+\!\!+} [\, (a, n) : \mathrm{spawn}(a, n) \in cs \,],\ \mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} [\, (a, n) : \mathrm{stop}(a, n) \in cs \,]\big]$$

(the two lists keep the order of $cs$, one entry per command).
-/
theorem foldl_split : ∀ (cs : List Cmd) (π : State), cs.foldl step π =
    { (cs.filter (!·.isLife)).foldl step π with
      spawns := π.spawns ++ cs.filterMap Cmd.spawnOf, stops := π.stops ++ cs.filterMap Cmd.stopOf }
  | [], π => by simp
  | c :: cs, π => by
    rw [List.foldl_cons, foldl_split cs (step π c)]
    have hmem : ∀ c' ∈ cs.filter (!·.isLife), c'.isLife = false := fun c' h => by
      simpa using (List.mem_filter.mp h).2
    cases hl : c.isLife
    · obtain ⟨h1, h2⟩ := step_life_keep π hl
      rw [h1, h2]
      have hs : c.spawnOf = none := by cases c <;> simp_all [Cmd.isLife, Cmd.spawnOf]
      have hp : c.stopOf = none := by cases c <;> simp_all [Cmd.isLife, Cmd.stopOf]
      simp [hl, hs, hp]
    · cases c with
      | spawn a n =>
        rw [step_spawn]
        have e : ({ π with spawns := π.spawns ++ [(a, n)] } : State) =
            { π with spawns := π.spawns ++ [(a, n)], stops := π.stops } := rfl
        rw [e, foldl_life_irrel _ π _ _ hmem]
        simp [Cmd.isLife, Cmd.spawnOf, Cmd.stopOf, List.filterMap_cons]
      | stop a n =>
        rw [step_stop]
        have e : ({ π with stops := π.stops ++ [(a, n)] } : State) =
            { π with spawns := π.spawns, stops := π.stops ++ [(a, n)] } := rfl
        rw [e, foldl_life_irrel _ π _ _ hmem]
        simp [Cmd.isLife, Cmd.spawnOf, Cmd.stopOf, List.filterMap_cons]
      | _ => simp [Cmd.isLife] at hl

/-- **The plan state of a log splits**: the other commands in their order, and the spawn and stop
lists.

$$\forall cs:\quad \operatorname{run}(cs) = \operatorname{run}\big([\, c \in cs : \operatorname{isLife}(c) = \mathrm{false} \,]\big)\big[\mathit{spawns} := [\, (a, n) : \mathrm{spawn}(a, n) \in cs \,],\ \mathit{stops} := [\, (a, n) : \mathrm{stop}(a, n) \in cs \,]\big]$$
-/
theorem run_split (cs : List Cmd) : run cs = { run (cs.filter (!·.isLife)) with
    spawns := cs.filterMap Cmd.spawnOf, stops := cs.filterMap Cmd.stopOf } := by
  unfold run
  rw [foldl_split]
  rfl

/-- **Spawn and stop commute with every command.**

$$\forall \pi, c, l:\quad \operatorname{isLife}(c) = \mathrm{false} \land \operatorname{isLife}(l) = \mathrm{true} \Rightarrow \operatorname{step}(\operatorname{step}(\pi, c), l) = \operatorname{step}(\operatorname{step}(\pi, l), c)$$
-/
theorem step_life_comm (π : State) {c l : Cmd} (hc : c.isLife = false) (hl : l.isLife = true) :
    step (step π c) l = step (step π l) c := by
  have h1 := foldl_split [c, l] π
  have h2 := foldl_split [l, c] π
  simp only [List.foldl_cons, List.foldl_nil] at h1 h2
  rw [h1, h2]
  cases l <;> cases c <;> simp_all [Cmd.isLife, Cmd.spawnOf, Cmd.stopOf, List.filterMap_cons]

/-- **Commute**: a define (or any other command) and a spawn or stop give the same plan state in
either order, after any log prefix. Stronger than the agent field alone: the whole state agrees.

$$\forall es, c, l:\quad \operatorname{isLife}(c) = \mathrm{false} \land \operatorname{isLife}(l) = \mathrm{true} \Rightarrow \operatorname{run}(es \mathbin{+\!\!+} [c, l]) = \operatorname{run}(es \mathbin{+\!\!+} [l, c])$$
-/
theorem run_comm (es : List Cmd) {c l : Cmd} (hc : c.isLife = false) (hl : l.isLife = true) :
    run (es ++ [c, l]) = run (es ++ [l, c]) := by
  simp only [run, List.foldl_append, List.foldl_cons, List.foldl_nil]
  exact step_life_comm _ hc hl

/-- **The obs-next-lean race is gone**: defining task `x` and spawning agent `a` bind the same agent
in either order, after any log prefix.

$$\forall es, d, a, n, x:\quad \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} [\mathrm{define}(d), \mathrm{spawn}(a, n)]), x) = \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} [\mathrm{spawn}(a, n), \mathrm{define}(d)]), x)$$
-/
theorem define_spawn_comm (es : List Cmd) (d : Def) (a : String) (n : Nat) (x : String) :
    boundTo (run (es ++ [.define d, .spawn a n])) x = boundTo (run (es ++ [.spawn a n, .define d])) x := by
  rw [run_comm es (c := .define d) (l := .spawn a n) rfl rfl]

/-! ### A binding is stable: only a claim, a label, a drop, a stop of a key of the bound agent or a spawn changes it -/

/-- `find?` over a list that grows at the end by entries equal to `b`, with a predicate that may
newly hold only at `b`, finds what it found before or `b`.

$$\forall p, p', b, m, l:\quad (\forall c:\ p(c) \Rightarrow p'(c)) \land (\forall c:\ p'(c) \Rightarrow p(c) \lor c = b) \land (\forall c \in m:\ c = b) \Rightarrow \operatorname{find}(p', l \mathbin{+\!\!+} m) = \operatorname{find}(p, l) \lor \operatorname{find}(p', l \mathbin{+\!\!+} m) = \mathrm{some}(b)$$
-/
theorem find?_grow {p p' : String → Bool} {b : String} (hp : ∀ c, p c = true → p' c = true)
    (hb : ∀ c, p' c = true → p c = true ∨ c = b) (m : List String) (hm : ∀ c ∈ m, c = b) :
    ∀ l : List String, (l ++ m).find? p' = l.find? p ∨ (l ++ m).find? p' = some b
  | [] => by
    simp only [List.nil_append, List.find?_nil]
    cases h : m.find? p' with
    | none => exact Or.inl rfl
    | some y => exact Or.inr (by rw [hm y (List.mem_of_find?_eq_some h)])
  | c :: l => by
    cases hc : p c
    · cases hc' : p' c
      · simp only [List.cons_append, List.find?_cons, hc, hc']
        exact find?_grow hp hb m hm l
      · have e : c = b := (hb c hc').resolve_left (by simp [hc])
        right
        subst e
        simp [hc']
    · left
      simp [hc, hp c hc]

/-- `find?` keeps its hit under a weaker predicate that still holds at the hit.

$$\forall p, p', a, l:\quad (\forall c:\ p'(c) \Rightarrow p(c)) \land p'(a) \land \operatorname{find}(p, l) = \mathrm{some}(a) \Rightarrow \operatorname{find}(p', l) = \mathrm{some}(a)$$
-/
theorem find?_keep {p p' : String → Bool} {a : String} (hp : ∀ c, p' c = true → p c = true)
    (ha : p' a = true) : ∀ l : List String, l.find? p = some a → l.find? p' = some a
  | [], h => by simp at h
  | c :: l, h => by
    cases hc : p c
    · have hc' : p' c = false := by
        cases h' : p' c
        · rfl
        · exact absurd (hp c h') (by simp [hc])
      simp only [List.find?_cons, hc, hc'] at h ⊢
      exact find?_keep hp ha l h
    · simp only [List.find?_cons, hc, Option.some.injEq] at h
      subst h
      simp [ha]

/-- A row with the same id and stored agent, and evidence whenever the old row had it, keeps the
derived agent.

$$\forall \pi, t, r, a:\quad r.\mathit{id} = t.\mathit{id} \land r.\mathit{agent} = t.\mathit{agent} \land (t.\mathit{evidence} \ne \bot \Rightarrow r.\mathit{evidence} \ne \bot) \land \operatorname{agentOf}(\pi, t) = a \Rightarrow \operatorname{agentOf}(\pi, r) = a$$
-/
theorem agentOf_row {π : State} {t r : Task} {a : String} (hid : r.id = t.id)
    (hag : r.agent = t.agent) (hev : t.evidence.isSome → r.evidence.isSome)
    (h : agentOf π t = some a) : agentOf π r = some a := by
  have hc : cands π r = cands π t := by simp [cands, hid, hag]
  unfold agentOf at h ⊢
  rw [hc]
  cases he : t.evidence.isSome
  · simp only [he, Bool.false_eq_true, ↓reduceIte] at h
    split <;> simp [h]
  · simp only [he, ↓reduceIte, hev he] at h ⊢
    exact h

/-- `any` agrees for two predicates that agree on the list.

$$\forall p, q, l:\quad (\forall a \in l:\ p(a) = q(a)) \Rightarrow \operatorname{any}(p, l) = \operatorname{any}(q, l)$$
-/
theorem any_congr_mem {α : Type} {p q : α → Bool} :
    ∀ {l : List α}, (∀ a ∈ l, p a = q a) → l.any p = l.any q
  | [], _ => rfl
  | a :: l, h => by
    simp only [List.any_cons, h a (List.mem_cons_self ..),
      any_congr_mem (fun b hb => h b (List.mem_cons_of_mem _ hb))]

/-- A stop makes no key more live, and leaves the other keys as they were.

$$\forall \pi, b, m, k:\quad \big(\operatorname{liveK}(\pi', k) \Rightarrow \operatorname{liveK}(\pi, k)\big) \land \big(k \ne b \Rightarrow \operatorname{liveK}(\pi', k) = \operatorname{liveK}(\pi, k)\big), \qquad \pi' = \pi[\mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} [(b, m)]]$$
-/
theorem liveK_stop (π : State) (b : String) (m : Nat) (k : String) :
    (liveK { π with stops := π.stops ++ [(b, m)] } k = true → liveK π k = true) ∧
      (k ≠ b → liveK { π with stops := π.stops ++ [(b, m)] } k = liveK π k) := by
  have hsg : sights { π with stops := π.stops ++ [(b, m)] } = sights π := rfl
  refine ⟨fun h => ?_, fun hk => ?_⟩
  · simp only [liveK, openedK, endedK, hsg, List.any_append, Bool.and_eq_true, Bool.not_eq_true',
      Bool.or_eq_false_iff] at h ⊢
    exact ⟨h.1, h.2.1⟩
  · have hb : (b == k) = false := by simpa using Ne.symm hk
    simp [liveK, openedK, endedK, hsg, List.any_append, hb]

/-- A spawn makes no key less live, and leaves the other keys as they were.

$$\forall \pi, b, m, k:\quad \big(\operatorname{liveK}(\pi, k) \Rightarrow \operatorname{liveK}(\pi', k)\big) \land \big(k \ne b \Rightarrow \operatorname{liveK}(\pi', k) = \operatorname{liveK}(\pi, k)\big), \qquad \pi' = \pi[\mathit{spawns} := \pi.\mathit{spawns} \mathbin{+\!\!+} [(b, m)]]$$
-/
theorem liveK_spawn (π : State) (b : String) (m : Nat) (k : String) :
    (liveK π k = true → liveK { π with spawns := π.spawns ++ [(b, m)] } k = true) ∧
      (k ≠ b → liveK { π with spawns := π.spawns ++ [(b, m)] } k = liveK π k) := by
  have hsg : sights { π with spawns := π.spawns ++ [(b, m)] } = sights π ++ [(b, m)] := by
    simp [sights]
  refine ⟨fun h => ?_, fun hk => ?_⟩
  · simp only [liveK, Bool.and_eq_true, Bool.not_eq_true'] at h ⊢
    refine ⟨by simp only [openedK, hsg, List.any_append]; simp [openedK] at h; simp [h.1], ?_⟩
    have h2 := h.2
    simp only [endedK, hsg, List.all_append, List.any_eq_false] at h2 ⊢
    intro q hq hq'
    apply h2 q hq
    simp only [Bool.and_eq_true] at hq' ⊢
    exact ⟨hq'.1, hq'.2.1⟩
  · have hb : (b == k) = false := by simpa using Ne.symm hk
    have hb' : (b != k) = true := by simpa using Ne.symm hk
    simp [liveK, openedK, endedK, hsg, List.any_append, List.all_append, hb, hb']

/-- A stop makes no name less ended, and leaves alone every name that does not have the stopped key.

$$\forall \pi, b, m, c:\quad \big(\operatorname{ended}(\pi, c) \Rightarrow \operatorname{ended}(\pi', c)\big) \land \big(b \notin \operatorname{keysOf}(\pi, c) \Rightarrow \operatorname{ended}(\pi', c) = \operatorname{ended}(\pi, c)\big), \qquad \pi' = \pi[\mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} [(b, m)]]$$
-/
theorem ended_stop (π : State) (b : String) (m : Nat) (c : String) :
    (ended π c = true → ended { π with stops := π.stops ++ [(b, m)] } c = true) ∧
      (b ∉ keysOf π c → ended { π with stops := π.stops ++ [(b, m)] } c = ended π c) := by
  have hk : keysOf { π with stops := π.stops ++ [(b, m)] } c = keysOf π c := rfl
  refine ⟨fun h => ?_, fun hb => ?_⟩
  · simp only [ended, hk, Bool.not_eq_true', List.any_eq_false] at h ⊢
    exact fun k hk' h' => h k hk' ((liveK_stop π b m k).1 h')
  · simp only [ended, hk]
    rw [any_congr_mem fun k hk' => (liveK_stop π b m k).2 fun e => hb (e ▸ hk')]

/-- A spawn makes no name more ended, and leaves alone every name that does not have the spawned key.

$$\forall \pi, b, m, c:\quad \big(\operatorname{ended}(\pi', c) \Rightarrow \operatorname{ended}(\pi, c)\big) \land \big(b \notin \operatorname{keysOf}(\pi, c) \Rightarrow \operatorname{ended}(\pi', c) = \operatorname{ended}(\pi, c)\big), \qquad \pi' = \pi[\mathit{spawns} := \pi.\mathit{spawns} \mathbin{+\!\!+} [(b, m)]]$$
-/
theorem ended_spawn (π : State) (b : String) (m : Nat) (c : String) :
    (ended { π with spawns := π.spawns ++ [(b, m)] } c = true → ended π c = true) ∧
      (b ∉ keysOf π c → ended { π with spawns := π.spawns ++ [(b, m)] } c = ended π c) := by
  have hk : keysOf { π with spawns := π.spawns ++ [(b, m)] } c = keysOf π c := rfl
  refine ⟨fun h => ?_, fun hb => ?_⟩
  · simp only [ended, hk, Bool.not_eq_true', List.any_eq_false] at h ⊢
    exact fun k hk' h' => h k hk' ((liveK_spawn π b m k).1 h')
  · simp only [ended, hk]
    rw [any_congr_mem fun k hk' => (liveK_spawn π b m k).2 fun e => hb (e ▸ hk')]

/-- A stop of a key that is not a key of the bound agent keeps the derived agent.

$$\forall \pi, t, a, b, m:\quad b \notin \operatorname{keysOf}(\pi, a) \land \operatorname{agentOf}(\pi, t) = a \Rightarrow \operatorname{agentOf}(\pi[\mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} [(b, m)]], t) = a$$
-/
theorem agentOf_stop {π : State} {t : Task} {a b : String} {m : Nat} (hab : b ∉ keysOf π a)
    (h : agentOf π t = some a) : agentOf { π with stops := π.stops ++ [(b, m)] } t = some a := by
  have hc : cands { π with stops := π.stops ++ [(b, m)] } t = cands π t := rfl
  have hp : ∀ c, (!ended { π with stops := π.stops ++ [(b, m)] } c) = true → (!ended π c) = true := by
    intro c hc
    cases he : ended π c
    · rfl
    · rw [(ended_stop π b m c).1 he] at hc; cases hc
  have ha : ended { π with stops := π.stops ++ [(b, m)] } a = ended π a :=
    (ended_stop π b m a).2 hab
  unfold agentOf at h ⊢
  rw [hc]
  split
  · rename_i he
    simp only [he, ↓reduceIte] at h
    cases hf : (cands π t).find? (fun a => !ended π a) with
    | none =>
      rw [hf] at h
      rw [List.find?_eq_none.mpr (fun c hc' h' => (List.find?_eq_none.mp hf) c hc' (hp c h'))]
      exact h
    | some y =>
      rw [hf] at h
      have h' : some y = some a := h
      cases h'
      have hy := List.find?_some hf
      rw [find?_keep hp (by rw [ha]; exact hy) _ hf]
      rfl
  · rename_i he
    simp only [he, Bool.false_eq_true, ↓reduceIte] at h
    have hy := List.find?_some h
    exact find?_keep hp (by rw [ha]; exact hy) _ h

/-- `find?` over `setRow` with an id-preserving map: the hit of the mapped list is the mapped hit.

$$\forall ts, x, y, f:\quad (\forall t:\ t.\mathit{id} = x \Rightarrow f(t).\mathit{id} = t.\mathit{id}) \Rightarrow \operatorname{find}(\cdot.\mathit{id} = y, \operatorname{setRow}(ts, x, f)) = g(\operatorname{find}(\cdot.\mathit{id} = y, ts)), \quad g(t) = \textbf{if } t.\mathit{id} = x \textbf{ then } f(t) \textbf{ else } t$$

($g(\bot) = \bot$).
-/
theorem find?_setRow {ts : List Task} {x y : String} {f : Task → Task}
    (hf : ∀ t, t.id = x → (f t).id = t.id) :
    (setRow ts x f).find? (·.id == y) =
      (ts.find? (·.id == y)).map fun t => if t.id = x then f t else t := by
  unfold setRow
  rw [List.find?_map]
  have e : ((·.id == y) ∘ fun t : Task => if t.id = x then f t else t) = (·.id == y) := by
    funext t
    by_cases h : t.id = x <;> simp [h, hf]
  rw [e]

/-- `find?` over a filter that keeps every row the predicate can hit.

$$\forall p, q, l:\quad (\forall t:\ p(t) \Rightarrow q(t)) \Rightarrow \operatorname{find}(p, [\, t \in l : q(t) \,]) = \operatorname{find}(p, l)$$
-/
theorem find?_filter_of {p q : Task → Bool} (h : ∀ t, p t = true → q t = true) :
    ∀ l : List Task, (l.filter q).find? p = l.find? p
  | [] => rfl
  | t :: l => by
    by_cases hq : q t = true
    · simp only [List.filter_cons, hq, ↓reduceIte, List.find?_cons]
      rw [find?_filter_of h l]
    · have hp : p t = false := by
        cases hp : p t
        · rfl
        · exact absurd (h t hp) hq
      simp only [List.filter_cons, hq, Bool.false_eq_true, ↓reduceIte, List.find?_cons, hp]
      exact find?_filter_of h l

/-- The commands that keep task `x` bound to agent `a` in plan state $\pi$.

$$\operatorname{keeps}(\pi, x, a, c) \iff \begin{cases} d.\mathit{task} = x \Rightarrow x \notin d.\mathit{live} & c = \mathrm{define}(d) \\ y \ne x & c = \mathrm{drop}(y) \\ \mathrm{true} & c = \mathrm{done}(\cdot, \cdot) \text{ or } c = \mathrm{milestone}(\cdot, \cdot) \text{ or } \operatorname{isMark}(c) \\ \mathrm{false} & c = \mathrm{claim}(\cdot, \cdot, \cdot) \text{ or } c = \mathrm{spawn}(\cdot, \cdot) \text{ or } c = \mathrm{label}(\cdot, \cdot) \\ b \notin \operatorname{keysOf}(\pi, a) & c = \mathrm{stop}(b, \cdot) \end{cases}$$
-/
def Keeps (s : State) (x a : String) : Cmd → Prop
  | .define d => d.task = x → x ∉ d.live
  | .drop y => y ≠ x
  | .done .. | .milestone .. => True
  | .handback .. | .integrate .. | .park .. | .unpark _ => True
  | .claim .. | .spawn .. | .label .. => False
  | .stop b _ => b ∉ keysOf s a

/-- **A binding is stable**: once task `x` is bound to `a`, a define of `x` (without `x` among its
legacy live names, and not taking back evidence that did not land), a drop of another task, any done,
any milestone, any mark and a stop of a key that is not a key of `a` keep it bound to `a`. Only a
claim (a claim sights its agent, which may revive a candidate), a label, a spawn, the drop of `x`, a
define of `x` with `x` among its legacy live names, a define of `x` without evidence while a row of
`x` holds evidence that did not land (`x` is undone again, so an ended agent no longer binds it) and
a stop of a key of `a` (then an undone `x` falls back to its next candidate) can change it.

$$\forall \pi, x, a, c:\quad \operatorname{boundTo}(\pi, x) = a \land \operatorname{keeps}(\pi, x, a, c) \land \big(\forall d:\ c = \mathrm{define}(d) \land d.\mathit{task} = x \land d.\mathit{evidence} = \bot \Rightarrow \forall t \in \pi.\mathit{tasks}:\ t.\mathit{id} = x \land t.\mathit{evidence} \ne \bot \Rightarrow t.\mathit{landed} = \mathrm{true}\big) \Rightarrow \operatorname{boundTo}(\operatorname{step}(\pi, c), x) = a$$
-/
theorem boundTo_keep {π : State} {x a : String} {c : Cmd} (h : boundTo π x = some a)
    (hk : Keeps π x a c)
    (hr : ∀ d, c = .define d → d.task = x → d.evidence = none →
      ∀ t ∈ π.tasks, t.id = x → t.evidence ≠ none → t.landed = true) :
    boundTo (step π c) x = some a := by
  obtain ⟨t, ht, hta⟩ : ∃ t, π.tasks.find? (·.id == x) = some t ∧ agentOf π t = some a := by
    unfold boundTo at h
    cases hf : π.tasks.find? (·.id == x) with
    | none => rw [hf] at h; simp at h
    | some t => rw [hf] at h; exact ⟨t, rfl, h⟩
  have htx : t.id = x := by simpa using List.find?_some ht
  unfold step
  split
  · rename_i hc
    cases c with
    | define d =>
      simp only [exec, boundTo]
      unfold upsert
      split
      · rw [find?_setRow (fun t' h' => by simp [Def.row, h'])]
        rw [ht]
        simp only [Option.map_some, Option.bind_some]
        split
        · rename_i hx
          have hl : d.liveAgent = none := by
            have : x ∉ d.live := hk (hx ▸ htx)
            simp [Def.liveAgent, ← hx, htx, this]
          refine agentOf_row (by simp [Def.row, hx]) (by simp [Def.row, hl]) ?_ hta
          intro he
          simp only [Def.row, keepEv]
          split
          · exact he
          · rename_i hlt
            cases hde : d.evidence with
            | some v => simp
            | none =>
              have := hr d rfl (hx ▸ htx) hde t (List.mem_of_find?_eq_some ht) htx
                (by simpa [Option.isSome_iff_ne_none] using he)
              simp [this] at hlt
        · exact hta
      · rw [List.find?_append, ht]
        exact hta
    | drop y =>
      simp only [exec, boundTo]
      rw [find?_filter_of (fun t' h' => by
        have : t'.id = x := by simpa using h'
        simpa [this] using Ne.symm hk), ht]
      exact hta
    | claim _ _ _ => exact hk.elim
    | label _ _ => exact hk.elim
    | done y e =>
      simp only [exec, boundTo]
      rw [find?_setRow (f := fun t => { t with evidence := some e, landed := true }) (fun _ _ => rfl), ht]
      simp only [Option.map_some, Option.bind_some]
      split
      · exact agentOf_row (π := π) (t := t) (r := { t with evidence := some e, landed := true }) rfl rfl
          (fun _ => rfl) hta
      · exact hta
    | milestone m title =>
      simp only [exec]
      split <;> exact h
    | spawn _ _ => exact hk.elim
    | stop b _ =>
      simp only [exec, boundTo, ht, Option.bind_some]
      exact agentOf_stop hk hta
    | handback _ _ _ | integrate _ _ _ | park _ _ | unpark _ => exact h
  · exact h

/-- A done task with a candidate is always bound (so no stop unbinds it).

$$\forall \pi, t:\quad t.\mathit{evidence} \ne \bot \Rightarrow \big(\operatorname{agentOf}(\pi, t) \ne \bot \iff \operatorname{cands}(\pi, t) \ne [\,]\big)$$
-/
theorem agentOf_done {π : State} {t : Task} (he : t.evidence ≠ none) :
    agentOf π t ≠ none ↔ cands π t ≠ [] := by
  have he' : t.evidence.isSome = true := by
    cases h : t.evidence
    · exact absurd h he
    · rfl
  unfold agentOf
  simp only [he', ↓reduceIte]
  cases hc : cands π t with
  | nil => simp
  | cons y ys =>
    simp only [ne_eq, reduceCtorEq, not_false_eq_true, iff_true, List.head?_cons]
    cases (y :: ys).find? (fun a => !ended π a) <;> simp

/-- **Running means: bound, no blockers, not done, not cut** (on the board rows).

$$\forall \pi, t:\quad \operatorname{tstate}(\operatorname{bound}(\pi), \operatorname{bindRow}(\pi, t)) = \mathrm{running} \iff t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{false} \land \operatorname{agentOf}(\pi, t) \ne \bot \land \operatorname{blockers}(\operatorname{bound}(\pi), t) = [\,]$$
-/
theorem bound_running_iff (π : State) (t : Task) :
    tstate (bound π) (bindRow π t) = .running ↔
      t.evidence = none ∧ t.cut = false ∧ agentOf π t ≠ none ∧ blockers (bound π) t = [] :=
  tstate_running_iff _ _

/-! ### Plan sync from main's head -/

/-- A define applied twice is applied once (re-syncing an unchanged task changes nothing).

$$\forall ts, d:\quad \operatorname{upsert}(\operatorname{upsert}(ts, d), d) = \operatorname{upsert}(ts, d)$$
-/
theorem upsert_idem (ts : List Task) (d : Def) : upsert (upsert ts d) d = upsert ts d := by
  have hrow : ∀ t : Task, t.id = d.task →
      (d.row (d.liveAgent <|> t.agent) (keepEv t d) t.landed).id = t.id := fun t h => by
    simp [Def.row, h]
  unfold upsert
  split
  · rename_i hin
    split
    case isFalse h' => exact (h' (by rw [ids_setRow hrow]; exact hin)).elim
    unfold setRow
    rw [List.map_map]
    apply List.map_congr_left
    intro t _
    by_cases h : t.id = d.task
    · simp only [Function.comp, h, ↓reduceIte, Def.row]
      cases d.liveAgent <;> cases hl : t.landed <;> simp [keepEv, hl]
    · simp [Function.comp, h]
  · rename_i hin
    split
    case isFalse h' => exact (h' (by simp [ids, Def.row])).elim
    unfold setRow
    rw [List.map_append]
    congr 1
    · conv => rhs; rw [← List.map_id ts]
      apply List.map_congr_left
      intro t ht
      have : t.id ≠ d.task := fun e => hin (List.contains_iff_mem.mpr (e ▸ List.mem_map_of_mem ht))
      simp [this]
    · simp only [Def.row, List.map_cons, List.map_nil, ↓reduceIte]
      cases d.liveAgent <;> simp [keepEv]

/-- **Sync is idempotent**: a define applied twice is applied once, accepted or refused.

$$\forall \pi, d:\quad \operatorname{step}(\operatorname{step}(\pi, \mathrm{define}(d)), \mathrm{define}(d)) = \operatorname{step}(\pi, \mathrm{define}(d))$$
-/
theorem step_define_idem (π : State) (d : Def) :
    step (step π (.define d)) (.define d) = step π (.define d) := by
  by_cases hc : check π (.define d) = none
  · have e : step π (.define d) = { π with tasks := upsert π.tasks d } := by
      simp [step, hc, exec]
    rw [e]
    have hc' : check { π with tasks := upsert π.tasks d } (.define d) = none := by
      rw [← hc]; simp only [check, upsert_idem]
    simp [step, hc', exec, upsert_idem]
  · have e : step π (.define d) = π := by simp [step, hc]
    rw [e, e]

/-- **Which commit a plan sync reads the work graph from**: main's head (the first ref named `main`),
when it differs from the commit the previous sync read; none (skip) when main is unknown or has not
moved.

$$\operatorname{syncFrom}(m, R, \ell) = \begin{cases} \mathrm{some}(h) & (m, h) \text{ is the first } r \in R \text{ with } r_1 = m,\ \ell \ne \mathrm{some}(h) \\ \bot & \text{that } r \text{ exists and } \ell = \mathrm{some}(h) \\ \bot & \text{no } r \in R \text{ has } r_1 = m \end{cases}$$
-/
def syncFrom (main : String) (refs : List (String × String)) (last : Option String) : Option String :=
  match refs.find? (·.1 == main) with
  | some r => if last = some r.2 then none else some r.2
  | none => none

/-- **Sync only from main**: a sync reads main's head, and only when it moved.

$$\forall m, R, \ell, h:\quad \operatorname{syncFrom}(m, R, \ell) = \mathrm{some}(h) \Rightarrow \operatorname{find}(\cdot_1 = m, R) = \mathrm{some}(m, h) \land \ell \ne \mathrm{some}(h)$$
-/
theorem sync_only_main {m : String} {refs : List (String × String)} {last : Option String} {h : String}
    (hs : syncFrom m refs last = some h) : refs.find? (·.1 == m) = some (m, h) ∧ last ≠ some h := by
  unfold syncFrom at hs
  cases hf : refs.find? (·.1 == m) with
  | none => rw [hf] at hs; simp at hs
  | some r =>
    rw [hf] at hs
    have hr : r.1 = m := by simpa using List.find?_some hf
    by_cases hl : last = some r.2
    · simp [hl] at hs
    · simp only [hl, ↓reduceIte, Option.some.injEq] at hs
      subst hs
      exact ⟨by rw [← hr], hl⟩

/-- **Same-head passes skip**: after a sync from `h`, the same refs give no sync.

$$\forall m, R, \ell, h:\quad \operatorname{syncFrom}(m, R, \ell) = \mathrm{some}(h) \Rightarrow \operatorname{syncFrom}(m, R, \mathrm{some}(h)) = \bot$$
-/
theorem sync_skip_same {m : String} {refs : List (String × String)} {last : Option String} {h : String}
    (hs : syncFrom m refs last = some h) : syncFrom m refs (some h) = none := by
  have hf := (sync_only_main hs).1
  simp [syncFrom, hf]

/-- **Every move of main is synced**: when main's head differs from the last synced commit, the
sync reads it.

$$\forall m, R, \ell, h:\quad \operatorname{find}(\cdot_1 = m, R) = \mathrm{some}(m, h) \land \ell \ne \mathrm{some}(h) \Rightarrow \operatorname{syncFrom}(m, R, \ell) = \mathrm{some}(h)$$
-/
theorem sync_due {m : String} {refs : List (String × String)} {last : Option String} {h : String}
    (hf : refs.find? (·.1 == m) = some (m, h)) (hl : last ≠ some h) : syncFrom m refs last = some h := by
  simp [syncFrom, hf, hl]

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

$$v = (\mathit{id}, \mathit{title}, \mathit{stream}, \mathit{milestone}_\bot, \mathit{owner}, \mathit{deps}, \mathit{needs}, \mathit{lane}, \mathit{state}, \mathit{blockers}, \mathit{agent}_\bot, \mathit{since}_\bot, \mathit{keys}, \mathit{evidence}_\bot, \mathit{outcome}_\bot)$$

`since`: when the task's agent was last seen (`seenAt`); `keys`: the live life keys of that agent
with their last-seen times (`liveKeys`), the input of the quiet timeout.
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
  since     : Option Nat
  keys      : List (String × Nat)
  evidence  : Option String
  outcome   : Option Mark
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

$$\operatorname{taskView}(\pi, ts, t) = (t.\mathit{id}, t.\mathit{title}, t.\mathit{stream}, t.\mathit{milestone}, t.\mathit{owner}, t.\mathit{deps}, t.\mathit{needs}, \operatorname{lane}(t), \operatorname{tstate}(ts, t), \operatorname{blockers}(ts, t), t.\mathit{agent}, s, K, t.\mathit{evidence}, t.\mathit{mark}), \qquad (s, K) = \begin{cases} (\operatorname{seenAt}(\pi, a), \operatorname{liveKeys}(\pi, a)) & t.\mathit{agent} = a \\ (\bot, [\,]) & t.\mathit{agent} = \bot \end{cases}$$
-/
def taskView (s : State) (ts : List Task) (t : Task) : TaskView :=
  { id := t.id, title := t.title, stream := t.stream, milestone := t.milestone, owner := t.owner,
    deps := t.deps, needs := t.needs, lane := lane t, state := tstate ts t,
    blockers := blockers ts t, agent := t.agent, since := t.agent.bind (seenAt s),
    keys := (t.agent.map (liveKeys s)).getD [],
    evidence := t.evidence, outcome := t.mark }

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

/-- The board plan of a plan state with the given rows for the task list and the parallel-safe
groups (milestone counts and the critical path never read an agent, so they use the stored rows).

$$\operatorname{viewWith}(\pi, b) = \big([\operatorname{taskView}(\pi, b, t) : t \in b],\ [\operatorname{msView}(\pi.\mathit{tasks}, m) : m \in \pi.\mathit{milestones}],\ \operatorname{criticalPath}(\operatorname{kept}(\pi.\mathit{tasks})),\ [\operatorname{ids}(g) : g \in \operatorname{groups}(b)]\big)$$
-/
def viewWith (s : State) (b : List Task) : View :=
  { tasks := b.map (taskView s b), milestones := s.milestones.map (msView s.tasks),
    criticalPath := criticalPath (kept s.tasks), parallelSafe := (groups b).map ids }

/-- The board plan of a plan state: rows with their derived agents (`bound`).

$$\operatorname{view}(\pi) = \operatorname{viewWith}(\pi, \operatorname{bound}(\pi))$$
-/
def view (s : State) : View := viewWith s (bound s)

/-! ## Task outcomes (task `task-state-truth`)

Why the board showed `running` for tasks whose agents had long ended: `agent.stop` was the only end
signal, and none arrived (the hook records were dropped), so `agentOf` kept every claim bound. Even
with stops, a task whose agent ended went back to `ready` or `blocked`, which hid where its work went.
The outcome commands record that; the theorems below say what the board may then show.
-/

/-- The task a mark command names (`handback`, `integrate`, `park`, `unpark`); none for the others.

$$\operatorname{markTask}(c) = \begin{cases} x & c \in \{\mathrm{handback}(x, \cdot, \cdot), \mathrm{integrate}(x, \cdot, \cdot), \mathrm{park}(x, \cdot), \mathrm{unpark}(x)\} \\ \bot & \text{otherwise} \end{cases}$$
-/
def Cmd.markTask : Cmd → Option String
  | .handback x .. | .integrate x .. | .park x _ | .unpark x => some x
  | _ => none

/-- A mark command: one that names a task through `markTask`.

$$\operatorname{isMark}(c) = \mathrm{true} \iff \operatorname{markTask}(c) \ne \bot$$
-/
def Cmd.isMark (c : Cmd) : Bool := c.markTask.isSome

/-- A command that is not a mark command leaves the mark log unchanged.

$$\forall \pi, c:\quad \operatorname{isMark}(c) = \mathrm{false} \Rightarrow \operatorname{exec}(\pi, c).\mathit{marks} = \pi.\mathit{marks}$$
-/
theorem exec_marks_keep (π : State) {c : Cmd} (h : c.isMark = false) :
    (exec π c).marks = π.marks := by
  cases c <;> simp_all [Cmd.isMark, Cmd.markTask, exec] <;> split <;> rfl

/-- A step of a command that is not a mark command leaves the mark log unchanged.

$$\forall \pi, c:\quad \operatorname{isMark}(c) = \mathrm{false} \Rightarrow \operatorname{step}(\pi, c).\mathit{marks} = \pi.\mathit{marks}$$
-/
theorem step_marks_keep (π : State) {c : Cmd} (h : c.isMark = false) :
    (step π c).marks = π.marks := by
  unfold step; split
  · exact exec_marks_keep π h
  · rfl

/-- A fold of commands none of which is a mark command leaves the mark log unchanged.

$$\forall cs, \pi:\quad (\forall c \in cs:\ \operatorname{isMark}(c) = \mathrm{false}) \Rightarrow \operatorname{foldl}(\operatorname{step}, \pi, cs).\mathit{marks} = \pi.\mathit{marks}$$
-/
theorem foldl_marks_keep : ∀ (cs : List Cmd) (π : State), (∀ c ∈ cs, c.isMark = false) →
    (cs.foldl step π).marks = π.marks
  | [], _, _ => rfl
  | c :: cs, π, h => by
    rw [List.foldl_cons, foldl_marks_keep cs _ (fun x hx => h x (List.mem_cons_of_mem _ hx)),
      step_marks_keep π (h c List.mem_cons_self)]

/-- A mark command changes neither the rows nor the spawn, stop, claim and label lists.

$$\forall \pi, c:\quad \operatorname{isMark}(c) = \mathrm{true} \Rightarrow \operatorname{step}(\pi, c).\mathit{tasks} = \pi.\mathit{tasks} \land \operatorname{step}(\pi, c).\mathit{spawns} = \pi.\mathit{spawns} \land \operatorname{step}(\pi, c).\mathit{stops} = \pi.\mathit{stops} \land \operatorname{step}(\pi, c).\mathit{claims} = \pi.\mathit{claims} \land \operatorname{step}(\pi, c).\mathit{labels} = \pi.\mathit{labels}$$
-/
theorem step_mark_frame (π : State) {c : Cmd} (h : c.isMark = true) :
    (step π c).tasks = π.tasks ∧ (step π c).spawns = π.spawns ∧ (step π c).stops = π.stops ∧
      (step π c).claims = π.claims ∧ (step π c).labels = π.labels := by
  unfold step; split
  · cases c <;> simp_all [Cmd.isMark, Cmd.markTask, exec]
  · exact ⟨rfl, rfl, rfl, rfl, rfl⟩

/-- `setRow` keeps rows without a mark when `f` does.

$$\forall ts, x, f:\quad (\forall u \in ts:\ u.\mathit{mark} = \bot \Rightarrow f(u).\mathit{mark} = \bot) \land (\forall t \in ts:\ t.\mathit{mark} = \bot) \Rightarrow \forall t \in \operatorname{setRow}(ts, x, f):\ t.\mathit{mark} = \bot$$
-/
theorem setRow_mark_none {ts : List Task} {x : String} {f : Task → Task}
    (hf : ∀ u ∈ ts, u.mark = none → (f u).mark = none) (h : ∀ t ∈ ts, t.mark = none) :
    ∀ t ∈ setRow ts x f, t.mark = none := by
  intro t ht
  simp only [setRow, List.mem_map] at ht
  obtain ⟨u, hu, rfl⟩ := ht
  split
  · exact hf u hu (h u hu)
  · exact h u hu

/-- An accepted or refused command keeps "no stored row has a mark".

$$\forall \pi, c:\quad (\forall t \in \pi.\mathit{tasks}:\ t.\mathit{mark} = \bot) \Rightarrow \forall t \in \operatorname{step}(\pi, c).\mathit{tasks}:\ t.\mathit{mark} = \bot$$
-/
theorem step_mark_none (π : State) (c : Cmd) (h : ∀ t ∈ π.tasks, t.mark = none) :
    ∀ t ∈ (step π c).tasks, t.mark = none := by
  unfold step; split
  · cases c with
    | define d =>
      simp only [exec, upsert]
      split
      · exact setRow_mark_none (fun _ _ _ => rfl) h
      · intro t ht
        rcases List.mem_append.mp ht with ht | ht
        · exact h t ht
        · rw [List.mem_singleton] at ht; subst ht; rfl
    | drop x => intro t ht; simp only [exec, List.mem_filter] at ht; exact h t ht.1
    | claim x a => exact setRow_mark_none (fun _ _ hu => hu) h
    | done x e => exact setRow_mark_none (fun _ _ hu => hu) h
    | milestone m ti => simp only [exec]; split <;> exact h
    | spawn _ | stop _ | label _ _ | handback _ _ _ | integrate _ _ _ | park _ _ | unpark _ => exact h
  · exact h

/-- **No reachable stored row has a mark** (marks live only on the board rows, `bindRow`).

$$\forall cs:\quad \forall t \in \operatorname{run}(cs).\mathit{tasks}:\ t.\mathit{mark} = \bot$$
-/
theorem run_mark_none (cs : List Cmd) : ∀ t ∈ (run cs).tasks, t.mark = none := by
  suffices ∀ (cs : List Cmd) (π : State), (∀ t ∈ π.tasks, t.mark = none) →
      ∀ t ∈ (cs.foldl step π).tasks, t.mark = none from this cs {} (fun _ h => by cases h)
  intro cs
  induction cs with
  | nil => intro π h; exact h
  | cons c cs ih => intro π h; exact ih _ (step_mark_none π c h)

/-- **Frame: a mark command changes the mark of its own task only.**

$$\forall \pi, c, x:\quad \operatorname{markTask}(c) \ne x \Rightarrow \operatorname{markOf}(\operatorname{step}(\pi, c), x) = \operatorname{markOf}(\pi, x)$$
-/
theorem markOf_step_other {π : State} {c : Cmd} {x : String} (h : c.markTask ≠ some x) :
    markOf (step π c) x = markOf π x := by
  unfold step; split
  · cases c <;> simp_all [Cmd.markTask, exec, markOf, List.filter_append] <;> split <;> rfl
  · rfl

/-- **An accepted mark command sets the mark of its task** (the last one wins; `unpark` clears it).

$$\forall \pi, c, x:\quad \operatorname{markTask}(c) = x \land \operatorname{check}(\pi, c) = \bot \Rightarrow \operatorname{markOf}(\operatorname{step}(\pi, c), x) = \begin{cases} \mathrm{handedBack}(a, p) & c = \mathrm{handback}(x, a, p) \\ \mathrm{integrated}(b, p) & c = \mathrm{integrate}(x, b, p) \\ \mathrm{parked}(r) & c = \mathrm{park}(x, r) \\ \bot & c = \mathrm{unpark}(x) \end{cases}$$
-/
theorem markOf_step_self {π : State} {c : Cmd} {x : String} (h : c.markTask = some x)
    (hc : check π c = none) :
    markOf (step π c) x = match c with
      | .handback _ a p => some (.handedBack a p)
      | .integrate _ b p => some (.integrated b p)
      | .park _ r => some (.parked r)
      | _ => none := by
  simp only [step, hc, ↓reduceIte]
  cases c <;> simp only [Cmd.markTask, reduceCtorEq, Option.some.injEq] at h <;> subst h <;>
    simp [exec, markOf, List.filter_append]

/-- **Frame: a mark command of another task leaves a row's board form unchanged.**

$$\forall \pi, c, t:\quad \operatorname{isMark}(c) = \mathrm{true} \land \operatorname{markTask}(c) \ne t.\mathit{id} \Rightarrow \operatorname{bindRow}(\operatorname{step}(\pi, c), t) = \operatorname{bindRow}(\pi, t)$$
-/
theorem bindRow_step_other {π : State} {c : Cmd} {t : Task} (hm : c.isMark = true)
    (h : c.markTask ≠ some t.id) : bindRow (step π c) t = bindRow π t := by
  obtain ⟨_, hs, hp, hcl, hl⟩ := step_mark_frame π hm
  obtain ⟨_, ho, _, ha, _, hr⟩ := life_congr (by rw [hs]) (by rw [hp]) hcl hl
  have hc : cands (step π c) t = cands π t := by simp only [cands, ho]
  simp only [bindRow, outcomeOf, ha, hc, hr, markOf_step_other h]

/-- **Running means a live agent**: on the board, a running task's agent is one of its candidates
(its claim, or an agent named like it) that has not ended: no stop of it is at or after its last
spawn.

$$\forall \pi, t:\quad \operatorname{tstate}(\operatorname{bound}(\pi), \operatorname{bindRow}(\pi, t)) = \mathrm{running} \Rightarrow \exists a:\ \operatorname{agentOf}(\pi, t) = a \land a \in \operatorname{cands}(\pi, t) \land \neg\operatorname{ended}(\pi, a)$$
-/
theorem bound_running_live {π : State} {t : Task} (h : tstate (bound π) (bindRow π t) = .running) :
    ∃ a, agentOf π t = some a ∧ a ∈ cands π t ∧ ended π a = false := by
  obtain ⟨he, _, ha, _⟩ := (bound_running_iff π t).mp h
  obtain ⟨a, hA⟩ := Option.ne_none_iff_exists'.mp ha
  have hf : (cands π t).find? (fun a => !ended π a) = some a := by
    simpa [agentOf, he] using hA
  refine ⟨a, hA, List.mem_of_find?_eq_some hf, ?_⟩
  simpa using List.find?_some hf

/-- **The board never shows a task with open blockers as running.**

$$\forall \pi, v:\quad v \in \operatorname{view}(\pi).\mathit{tasks} \land v.\mathit{state} = \mathrm{running} \Rightarrow v.\mathit{blockers} = [\,]$$
-/
theorem view_running_no_blockers {π : State} {v : TaskView} (hv : v ∈ (view π).tasks)
    (h : v.state = .running) : v.blockers = [] := by
  simp only [view, viewWith, List.mem_map] at hv
  obtain ⟨t, _, rfl⟩ := hv
  exact running_no_blockers h

/-- **Done on the board needs landed evidence**: a board task shown done has evidence $e$, and its
stored row got $e$ from a land event of the task or from an on-main define of it in the log
(`done_needs_landed_evidence`).

$$\forall L, v:\quad v \in \operatorname{view}(\operatorname{run}(L)).\mathit{tasks} \land v.\mathit{state} = \mathrm{done} \Rightarrow \exists t \in \operatorname{run}(L).\mathit{tasks}, \exists e:\ v.\mathit{evidence} = e \land v.\mathit{id} = t.\mathit{id} \land \operatorname{src}(L, t, e)$$
-/
theorem view_done_landed (l : List Cmd) {v : TaskView} (hv : v ∈ (view (run l)).tasks)
    (h : v.state = .done) :
    ∃ t ∈ (run l).tasks, ∃ e, v.evidence = some e ∧ v.id = t.id ∧ EvSrc l t e := by
  simp only [view, viewWith, bound, List.map_map, List.mem_map, Function.comp] at hv
  obtain ⟨t, ht, rfl⟩ := hv
  have hne : t.evidence ≠ none := (tstate_done_iff _ (bindRow (run l) t)).mp h
  obtain ⟨e, he⟩ := Option.ne_none_iff_exists'.mp hne
  exact ⟨t, ht, e, he, rfl, done_needs_landed_evidence l ht he⟩

/-- **An undone, uncut task whose candidate agents all ended shows its last mark, or parked**:
with no mark recorded, parked with reason `endReason` (`noHandback`, or `expired` for a claim that
was never spawned).

$$\forall ts, \pi, t:\quad t.\mathit{evidence} = \bot \land t.\mathit{cut} = \mathrm{false} \land \operatorname{cands}(\pi, t) \ne [\,] \land (\forall a \in \operatorname{cands}(\pi, t):\ \operatorname{ended}(\pi, a)) \Rightarrow \operatorname{tstate}(ts, \operatorname{bindRow}(\pi, t)) = \begin{cases} \operatorname{mstate}(m) & \operatorname{markOf}(\pi, t.\mathit{id}) = m \ne \bot \\ \operatorname{mstate}(\mathrm{parked}(\operatorname{endReason}(\pi, t))) & \operatorname{markOf}(\pi, t.\mathit{id}) = \bot \end{cases}$$
-/
theorem ended_state (ts : List Task) {π : State} {t : Task} (hev : t.evidence = none)
    (hc : t.cut = false) (hn : cands π t ≠ []) (he : ∀ a ∈ cands π t, ended π a = true) :
    tstate ts (bindRow π t) = ((markOf π t.id).getD (.parked (endReason π t))).state := by
  have hA : agentOf π t = none := by
    simp only [agentOf, hev, Option.isSome_none, Bool.false_eq_true, ↓reduceIte,
      List.find?_eq_none]
    intro a ha; simp [he a ha]
  have hne : (cands π t).isEmpty = false := by
    cases hc' : cands π t
    · exact absurd hc' hn
    · rfl
  have ho : outcomeOf π t = some ((markOf π t.id).getD (.parked (endReason π t))) := by
    cases hk : markOf π t.id <;> simp [outcomeOf, hk, hA, hne]
  exact tstate_mark (by simp [bindRow, hev]) (by simp [bindRow, hc]) (by simp [bindRow, hA])
    (by simp [bindRow, ho])

/-- **Every claimed task whose agents all ended is done, handed back, integrated or parked** (exactly
one, since the state is one value): never running, ready or blocked, so it does not invite a respawn.
A candidate is the claim or an agent named like the task (`cands`).

$$\forall ts, \pi, t:\quad t.\mathit{cut} = \mathrm{false} \land \operatorname{cands}(\pi, t) \ne [\,] \land (\forall a \in \operatorname{cands}(\pi, t):\ \operatorname{ended}(\pi, a)) \Rightarrow \operatorname{tstate}(ts, \operatorname{bindRow}(\pi, t)) \in \{\mathrm{done}, \mathrm{handedBack}, \mathrm{integrated}, \mathrm{parked}\}$$
-/
theorem ended_outcome (ts : List Task) {π : State} {t : Task} (hc : t.cut = false)
    (hn : cands π t ≠ []) (he : ∀ a ∈ cands π t, ended π a = true) :
    tstate ts (bindRow π t) = .done ∨ tstate ts (bindRow π t) = .handedBack ∨
      tstate ts (bindRow π t) = .integrated ∨ tstate ts (bindRow π t) = .parked := by
  cases hev : t.evidence with
  | some e => exact .inl ((tstate_done_iff _ _).mpr (by simp [bindRow, hev]))
  | none =>
    rw [ended_state ts hev hc hn he]
    exact .inr (Mark.state_mem _)

/-- **Integrate allowlist** (`integrate_allowlist`): an integrate command of task `x` into ref `b` is
accepted exactly when `x` is a task, it is not done, and `b` is an allowed full ref (`allowedRef`:
under `refs/heads/ci/`, `refs/heads/worktree-` or `refs/heads/integrate-`). So work reaches main only
by landing (`task.done`, which needs on-main evidence), whatever spelling of main the command uses.

$$\forall \pi, x, b, p:\quad \operatorname{check}(\pi, \mathrm{integrate}(x, b, p)) = \bot \iff x \in \operatorname{ids}(\pi.\mathit{tasks}) \land \lnot\operatorname{isDone}(\pi.\mathit{tasks}, x) \land \operatorname{allowedRef}(b) = \mathrm{true}$$
-/
theorem integrate_allowlist (π : State) (x b p : String) :
    check π (.integrate x b p) = none ↔
      x ∈ ids π.tasks ∧ isDone π.tasks x = false ∧ allowedRef b = true := by
  simp only [check]
  by_cases h1 : (ids π.tasks).contains x = true
  · have h1' : x ∈ ids π.tasks := List.contains_iff_mem.mp h1
    by_cases h2 : isDone π.tasks x = true
    · simp [h1', h2]
    · by_cases h3 : allowedRef b = true
      · simp [h1', h2, h3]
      · simp [h1', h2, h3]
  · have h1' : x ∉ ids π.tasks := fun h => h1 (List.contains_iff_mem.mpr h)
    simp [h1']

/-- **An accepted integrate targets an allowed branch family**: its ref starts with one of
`allowPrefixes` (so never `main`, `refs/heads/main`, `origin/HEAD`, `HEAD` or `main~0`).

$$\forall \pi, x, b, p:\quad \operatorname{check}(\pi, \mathrm{integrate}(x, b, p)) = \bot \Rightarrow \exists q \in \operatorname{allowPrefixes}:\ q \text{ is a prefix of } b$$
-/
theorem integrate_prefix {π : State} {x b p : String} (h : check π (.integrate x b p) = none) :
    ∃ q ∈ allowPrefixes, b.startsWith q = true := by
  have h3 := ((integrate_allowlist π x b p).mp h).2.2
  simp only [allowedRef, Bool.and_eq_true, List.any_eq_true] at h3
  obtain ⟨⟨⟨q, hq, hs, _⟩, _⟩, _⟩ := h3
  exact ⟨q, hq, hs⟩

/-- **A refused command changes nothing** (for a mark command: no mark is recorded, the board is unchanged).

$$\forall \pi, c:\quad \operatorname{check}(\pi, c) \ne \bot \Rightarrow \operatorname{step}(\pi, c) = \pi$$
-/
theorem step_refused {π : State} {c : Cmd} (h : check π c ≠ none) : step π c = π := by
  obtain ⟨e, he⟩ := Option.ne_none_iff_exists'.mp h
  simp [step, he]

/-- **The board depends on the spawn/stop commands only as multisets**: two logs whose other
commands agree in order and whose spawn and stop (agent, time) pairs are permutations of each other
give the same board (so where in the log a spawn or stop lands never matters; its time does).

$$\forall cs_1, cs_2:\quad [\, c \in cs_1 : \neg\operatorname{isLife}(c) \,] = [\, c \in cs_2 : \neg\operatorname{isLife}(c) \,] \land [\, (a, n) : \mathrm{spawn}(a, n) \in cs_1 \,] \sim [\, (a, n) : \mathrm{spawn}(a, n) \in cs_2 \,] \land [\, (a, n) : \mathrm{stop}(a, n) \in cs_1 \,] \sim [\, (a, n) : \mathrm{stop}(a, n) \in cs_2 \,] \Rightarrow \operatorname{view}(\operatorname{run}(cs_1)) = \operatorname{view}(\operatorname{run}(cs_2))$$

The pair lists are in log order, one entry per command, and $\sim$ is "is a permutation of".
-/
theorem view_perm {cs₁ cs₂ : List Cmd} (h : cs₁.filter (!·.isLife) = cs₂.filter (!·.isLife))
    (hs : (cs₁.filterMap Cmd.spawnOf).Perm (cs₂.filterMap Cmd.spawnOf))
    (hp : (cs₁.filterMap Cmd.stopOf).Perm (cs₂.filterMap Cmd.stopOf)) :
    view (run cs₁) = view (run cs₂) := by
  have hs' : (run cs₁).spawns.Perm (run cs₂).spawns := by rw [run_split, run_split cs₂]; exact hs
  have hp' : (run cs₁).stops.Perm (run cs₂).stops := by rw [run_split, run_split cs₂]; exact hp
  have hcl : (run cs₁).claims = (run cs₂).claims := by rw [run_split, run_split cs₂, h]
  have hl : (run cs₁).labels = (run cs₂).labels := by rw [run_split, run_split cs₂, h]
  obtain ⟨_, ho, hseen, ha, hlk, hr⟩ := life_congr hs' hp' hcl hl
  have ht : (run cs₁).tasks = (run cs₂).tasks := by rw [run_split, run_split cs₂, h]
  have hm : (run cs₁).milestones = (run cs₂).milestones := by rw [run_split, run_split cs₂, h]
  have hk : (run cs₁).marks = (run cs₂).marks := by rw [run_split, run_split cs₂, h]
  have hc : cands (run cs₁) = cands (run cs₂) := by
    funext t; simp only [cands, ho]
  have hb : bindRow (run cs₁) = bindRow (run cs₂) := by
    funext t; simp only [bindRow, outcomeOf, markOf, ha, hk, hc, hr]
  have hv : taskView (run cs₁) = taskView (run cs₂) := by
    funext ts t; simp only [taskView, hseen, hlk]
  simp only [view, viewWith, bound, hb, ht, hm, hv]


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

/-! ## Quiet timeout (task `task-state-truth`)

A SubagentStop hook can fail to fire (a killed session, a crash), and before the admission fix the
drain dropped 6376 stop records. So a stop is not the only end of an agent: a live key with no
sighting (spawn, heartbeat or claim) for `quietMs` milliseconds is ended by a timeout stop, which
the console appends as `agent.stop(k, n)` at the key's last sighting $n$, so any later event of the
key revives it (`revive_on_event`). The rule reads the board only (`TaskView.keys`), so it runs on
what the console already has. A claim is a sighting at its claim time, so a claim whose agent never
shows up expires at claim time plus `quietMs` and the row is parked with reason `expired`
(`no_forever_running`).
-/

/-- The quiet limit in milliseconds: 120 minutes, the console's `goneAfterMin`.

$$\mathit{quietMs} = 120 \cdot 60000 = 7200000$$
-/
def quietMs : Nat := 120 * 60000

/-- **The timeout stops due at time `now`**: for every board task with no evidence, each live key
$(k, n)$ of its agent with $n + q < \mathit{now}$, in board and key order (a pair repeats when two
tasks share an agent).

$$\operatorname{timeouts}(q, \mathit{now}, vs) = [\, (k, n) : v \in vs,\ v.\mathit{evidence} = \bot,\ (k, n) \in v.\mathit{keys},\ n + q < \mathit{now} \,]$$
-/
def timeouts (q now : Nat) (vs : List TaskView) : List (String × Nat) :=
  vs.flatMap fun v => if v.evidence.isNone then v.keys.filter (fun p => decide (p.2 + q < now)) else []

/-- **A timeout is due exactly for a quiet live key of an undone task's agent.**

$$\forall q, \mathit{now}, vs, k, n:\quad (k, n) \in \operatorname{timeouts}(q, \mathit{now}, vs) \iff \exists v \in vs:\ v.\mathit{evidence} = \bot \land (k, n) \in v.\mathit{keys} \land n + q < \mathit{now}$$
-/
theorem mem_timeouts (q now : Nat) (vs : List TaskView) (k : String) (n : Nat) :
    (k, n) ∈ timeouts q now vs ↔ ∃ v ∈ vs, v.evidence = none ∧ (k, n) ∈ v.keys ∧ n + q < now := by
  simp only [timeouts, List.mem_flatMap]
  constructor
  · rintro ⟨v, hv, h⟩
    cases he : v.evidence with
    | none =>
      simp only [he, Option.isNone_none, ↓reduceIte, List.mem_filter, decide_eq_true_eq] at h
      exact ⟨v, hv, he, h.1, h.2⟩
    | some _ => simp [he] at h
  · rintro ⟨v, hv, he, hk, hn⟩
    exact ⟨v, hv, by simp [he, hk, hn]⟩

/-- **The board rows**: every board task is the view of a stored row with its derived agent.

$$\forall \pi, v:\quad v \in \operatorname{view}(\pi).\mathit{tasks} \iff \exists t \in \pi.\mathit{tasks}:\ v = \operatorname{taskView}(\pi, \operatorname{bound}(\pi), \operatorname{bindRow}(\pi, t))$$
-/
theorem mem_view_tasks (π : State) (v : TaskView) :
    v ∈ (view π).tasks ↔ ∃ t ∈ π.tasks, v = taskView π (bound π) (bindRow π t) := by
  simp only [view, viewWith, bound, List.map_map, List.mem_map, Function.comp]
  constructor
  · rintro ⟨t, ht, rfl⟩; exact ⟨t, ht, rfl⟩
  · rintro ⟨t, ht, rfl⟩; exact ⟨t, ht, rfl⟩

/-- Every sighting time of a key is at most its last-seen time.

$$\forall \pi, k, n:\quad (k, n) \in \operatorname{sights}(\pi) \Rightarrow n \le \operatorname{lastAt}(\pi, k)$$
-/
theorem le_lastAt {π : State} {k : String} {n : Nat} (h : (k, n) ∈ sights π) : n ≤ lastAt π k := by
  unfold lastAt
  have hm : (k, n) ∈ (sights π).filter (·.1 == k) := List.mem_filter.mpr ⟨h, by simp⟩
  generalize (sights π).filter (·.1 == k) = l at hm
  induction l with
  | nil => cases hm
  | cons p ps ih =>
    rcases List.mem_cons.mp hm with rfl | hm
    · simp only [List.foldr_cons]; omega
    · have := ih hm; simp only [List.foldr_cons]; omega

/-- A bound on every sighting time of a key bounds its last-seen time.

$$\forall \pi, k, m:\quad (\forall (b, n) \in \operatorname{sights}(\pi):\ b = k \Rightarrow n \le m) \Rightarrow \operatorname{lastAt}(\pi, k) \le m$$
-/
theorem lastAt_le {π : State} {k : String} {m : Nat} (h : ∀ p ∈ sights π, p.1 = k → p.2 ≤ m) :
    lastAt π k ≤ m := by
  unfold lastAt
  have hm : ∀ p ∈ (sights π).filter (·.1 == k), p.2 ≤ m := fun p hp => by
    have := List.mem_filter.mp hp
    exact h p this.1 (by simpa using this.2)
  generalize (sights π).filter (·.1 == k) = l at hm
  induction l with
  | nil => simp
  | cons p ps ih =>
    have h1 := hm p (List.mem_cons_self ..)
    have h2 := ih (fun q hq => hm q (List.mem_cons_of_mem _ hq))
    simp only [List.foldr_cons]; omega

/-- A stop of a key at or after its last sighting, anywhere in the stop list, ends the key.

$$\forall \pi, k, m:\quad (k, m) \in \pi.\mathit{stops} \land \operatorname{lastAt}(\pi, k) \le m \Rightarrow \operatorname{endedK}(\pi, k) = \mathrm{true}$$
-/
theorem endedK_of_stop {π : State} {k : String} {m : Nat} (hs : (k, m) ∈ π.stops)
    (h : lastAt π k ≤ m) : endedK π k = true := by
  simp only [endedK, List.any_eq_true, Bool.and_eq_true, beq_iff_eq, List.all_eq_true]
  refine ⟨(k, m), hs, rfl, fun p hp => ?_⟩
  by_cases e : p.1 = k
  · have : p.2 ≤ lastAt π k := le_lastAt (by rw [← e]; exact hp)
    simp only [e, bne_self_eq_false, Bool.false_or, decide_eq_true_eq]; omega
  · simp [e]

/-- **A stop at or after the last sighting ends the key** (whatever was logged before or after it).

$$\forall \pi, k, m:\quad \operatorname{lastAt}(\pi, k) \le m \Rightarrow \operatorname{endedK}(\operatorname{step}(\pi, \mathrm{stop}(k, m)), k) = \mathrm{true}$$
-/
theorem stop_ends {π : State} {k : String} {m : Nat} (h : lastAt π k ≤ m) :
    endedK (step π (.stop k m)) k = true := by
  rw [step_stop]
  exact endedK_of_stop (by simp) h

/-- **Any event revives its key** (`revive_on_event`): a spawn of key $k$ (its start, a heartbeat of
any later event, named or unnamed) at a time later than every stop of $k$ makes $k$ live, and every
name that has the key $k$ is then not ended, whatever stops came before.

$$\forall \pi, k, a, n:\quad k \in \operatorname{keysOf}(\pi, a) \land (\forall (b, m) \in \pi.\mathit{stops}:\ b = k \Rightarrow m < n) \Rightarrow \operatorname{liveK}(\pi', k) = \mathrm{true} \land \operatorname{ended}(\pi', a) = \mathrm{false}, \qquad \pi' = \operatorname{step}(\pi, \mathrm{spawn}(k, n))$$
-/
theorem revive_on_event (π : State) {k a : String} {n : Nat} (hk : k ∈ keysOf π a)
    (hs : ∀ q ∈ π.stops, q.1 = k → q.2 < n) :
    liveK (step π (.spawn k n)) k = true ∧ ended (step π (.spawn k n)) a = false := by
  rw [step_spawn]
  have hsg : sights { π with spawns := π.spawns ++ [(k, n)] } = sights π ++ [(k, n)] := by
    simp [sights]
  have hl : liveK { π with spawns := π.spawns ++ [(k, n)] } k = true := by
    simp only [liveK, Bool.and_eq_true, Bool.not_eq_true']
    refine ⟨by simp [openedK, hsg], ?_⟩
    simp only [endedK, hsg, List.any_eq_false, Bool.and_eq_true, beq_iff_eq, List.all_append,
      List.all_cons, List.all_nil, Bool.and_true, Bool.or_eq_true, bne_iff_ne, ne_eq,
      not_true_eq_false, decide_eq_true_eq, false_or, not_and]
    intro q hq hqk _ hle
    have := hs q hq hqk
    omega
  refine ⟨hl, ?_⟩
  have hk' : keysOf { π with spawns := π.spawns ++ [(k, n)] } a = keysOf π a := rfl
  simp only [ended, hk', Bool.not_eq_false', List.any_eq_true]
  exact ⟨k, hk, hl⟩

/-- **A recent sighting is never timed out** (`timeout_spares_recent`): if key $k$ was seen at $m$
and $\mathit{now} \le m + q$, the board lists no timeout of $k$ at all.

$$\forall q, \mathit{now}, \pi, k, m, n:\quad (k, m) \in \operatorname{sights}(\pi) \land \mathit{now} \le m + q \Rightarrow (k, n) \notin \operatorname{timeouts}(q, \mathit{now}, \operatorname{view}(\pi).\mathit{tasks})$$
-/
theorem timeout_spares_recent (q now : Nat) (π : State) {k : String} {m n : Nat}
    (hs : (k, m) ∈ sights π) (hr : now ≤ m + q) : (k, n) ∉ timeouts q now (view π).tasks := by
  intro h
  obtain ⟨v, hv, _, hk, hn⟩ := (mem_timeouts _ _ _ _ _).mp h
  obtain ⟨t, _, rfl⟩ := (mem_view_tasks π v).mp hv
  have hk' : (k, n) ∈ ((agentOf π t).map (liveKeys π)).getD [] := by
    simpa [taskView, bindRow] using hk
  cases ha : agentOf π t with
  | none => rw [ha] at hk'; simp at hk'
  | some a =>
    rw [ha] at hk'
    simp only [Option.map_some, Option.getD_some, liveKeys, List.mem_map, List.mem_filter,
      Prod.mk.injEq] at hk'
    obtain ⟨k', _, rfl, rfl⟩ := hk'
    have := le_lastAt hs
    omega

/-- The console sweep at time `now`: the plan state after the timeout stops of its board,
$\mathrm{stop}(k, n)$ for each $(k, n) \in \operatorname{timeouts}(q, \mathit{now}, \operatorname{view}(\pi).\mathit{tasks})$, in order.

$$\operatorname{sweep}(q, \mathit{now}, \pi) = \operatorname{foldl}\big((\sigma, (k, n)) \mapsto \operatorname{step}(\sigma, \mathrm{stop}(k, n)),\ \pi,\ \operatorname{timeouts}(q, \mathit{now}, \operatorname{view}(\pi).\mathit{tasks})\big)$$
-/
def sweep (q now : Nat) (s : State) : State :=
  (timeouts q now (view s).tasks).foldl (fun σ p => step σ (.stop p.1 p.2)) s

/-- Folding stops only appends them to the stop list.

$$\forall l, \pi:\quad \operatorname{foldl}\big((\sigma, (k, n)) \mapsto \operatorname{step}(\sigma, \mathrm{stop}(k, n)),\ \pi,\ l\big) = \pi[\mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} l]$$
-/
theorem foldl_stops : ∀ (l : List (String × Nat)) (π : State),
    l.foldl (fun σ p => step σ (.stop p.1 p.2)) π = { π with stops := π.stops ++ l }
  | [], π => by simp
  | p :: l, π => by
    rw [List.foldl_cons, step_stop, foldl_stops l]
    simp

/-- **No task runs forever** (`no_forever_running`): for every undone row bound to agent $a$, either
some key of $a$ is live and was seen within the quiet limit, or every live key of $a$ is listed as a
timeout, and after the sweep the row is no longer bound to $a$. A claim is a sighting at its claim
time, so a claim with no live bound agent ends by claim time plus $q$.

$$\forall q, \mathit{now}, \pi, t, a:\quad t \in \pi.\mathit{tasks} \land t.\mathit{evidence} = \bot \land \operatorname{agentOf}(\pi, t) = a \Rightarrow \Big(\exists k \in \operatorname{keysOf}(\pi, a):\ \operatorname{liveK}(\pi, k) \land \mathit{now} \le \operatorname{lastAt}(\pi, k) + q\Big) \lor \Big(\big(\forall k \in \operatorname{keysOf}(\pi, a):\ \operatorname{liveK}(\pi, k) \Rightarrow (k, \operatorname{lastAt}(\pi, k)) \in \operatorname{timeouts}(q, \mathit{now}, \operatorname{view}(\pi).\mathit{tasks})\big) \land \operatorname{agentOf}(\operatorname{sweep}(q, \mathit{now}, \pi), t) \ne a\Big)$$
-/
theorem no_forever_running (q now : Nat) {π : State} {t : Task} {a : String} (ht : t ∈ π.tasks)
    (he : t.evidence = none) (ha : agentOf π t = some a) :
    (∃ k ∈ keysOf π a, liveK π k = true ∧ now ≤ lastAt π k + q) ∨
      ((∀ k ∈ keysOf π a, liveK π k = true → (k, lastAt π k) ∈ timeouts q now (view π).tasks) ∧
        agentOf (sweep q now π) t ≠ some a) := by
  by_cases hr : ∃ k ∈ keysOf π a, liveK π k = true ∧ now ≤ lastAt π k + q
  · exact .inl hr
  · right
    have hq : ∀ k ∈ keysOf π a, liveK π k = true → lastAt π k + q < now := by
      intro k hk hl; exact Nat.lt_of_not_le fun hc => hr ⟨k, hk, hl, hc⟩
    have hmem : ∀ k ∈ keysOf π a, liveK π k = true →
        (k, lastAt π k) ∈ timeouts q now (view π).tasks := by
      intro k hk hl
      refine (mem_timeouts _ _ _ _ _).mpr
        ⟨_, (mem_view_tasks π _).mpr ⟨t, ht, rfl⟩, by simp [taskView, bindRow, he], ?_, hq k hk hl⟩
      simp only [taskView, bindRow, ha, Option.map_some, Option.getD_some, liveKeys, List.mem_map,
        List.mem_filter]
      exact ⟨k, ⟨hk, hl⟩, rfl⟩
    refine ⟨hmem, ?_⟩
    have hsw : sweep q now π = { π with stops := π.stops ++ timeouts q now (view π).tasks } :=
      foldl_stops _ _
    have hend : ended (sweep q now π) a = true := by
      rw [hsw]
      have hk' : keysOf { π with stops := π.stops ++ timeouts q now (view π).tasks } a = keysOf π a :=
        rfl
      simp only [ended, hk', Bool.not_eq_true', List.any_eq_false]
      intro k hk hl
      have hsg : sights { π with stops := π.stops ++ timeouts q now (view π).tasks } = sights π := rfl
      have hla : lastAt { π with stops := π.stops ++ timeouts q now (view π).tasks } k = lastAt π k :=
        rfl
      have hop : openedK { π with stops := π.stops ++ timeouts q now (view π).tasks } k = openedK π k :=
        rfl
      by_cases hl0 : liveK π k = true
      · have := endedK_of_stop (π := { π with stops := π.stops ++ timeouts q now (view π).tasks })
          (k := k) (m := lastAt π k) (List.mem_append_right _ (hmem k hk hl0)) (Nat.le_of_eq hla)
        simp [liveK, this] at hl
      · have hE : openedK π k = true → endedK π k = true := by
          intro ho; simpa [liveK, ho] using hl0
        simp only [liveK, hop, Bool.and_eq_true, Bool.not_eq_true'] at hl
        have h1 := hE hl.1
        have h2 : endedK { π with stops := π.stops ++ timeouts q now (view π).tasks } k = true := by
          simp only [endedK, hsg, List.any_append] at h1 ⊢
          simp [h1]
        rw [h2] at hl; cases hl.2
    intro h
    simp only [agentOf, he, Option.isSome_none, Bool.false_eq_true, ↓reduceIte] at h
    have := List.find?_some h
    simp [hend] at this

/-! ## Examples -/


/-- A definition with the given id and deps (test helper).

$$\operatorname{mk}(x, D, W) = (x, x, \texttt{"s"}, \bot, D, \texttt{"o"}, W, [\,], [\,], \bot, \mathrm{false}, [\,]) \quad (W = [\,] \text{ by default})$$

The twelve fields are task, title, stream, milestone, deps, owner, writes, devices, needs, evidence, cut, live; the last two keep their defaults.
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
#guard check (run [.define (mk "a" [])]) (.claim "z" "x" 0) == some "no such task"
#guard check (run [.define (mk "a" []), .done "a" "abc1234"]) (.done "a" "e") == some "task already done"
#guard check {} (.define { mk "a" [] with title := String.ofList (List.replicate 201 'x') })
  == some "title: at most 200 characters"
#guard (run [.define (mk "a" []), .define (mk "b" ["a"]), .drop "b"]).tasks.map (·.id) == ["a"]
#guard let s := run [.define (mk "a" []), .define (mk "b" ["a"]), .define (mk "c" []),
    .claim "c" "agent-1" 0]
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
#guard lane { (mk "a" []).row none none false with needs := ["device"] } == .device
#guard lane { (mk "a" []).row none none false with needs := ["other", "device"] } == .device
#guard lane { (mk "a" []).row none none false with needs := ["other"] } == .agent
#guard lane ((mk "a" []).row none none false) == .agent
#guard let s := run [.define (mk "a" [] ["x/**"]), .define { mk "p" [] with needs := ["device"] },
    .define { mk "q" ["a"] with needs := ["device"] }, .define (mk "c" [] ["z/**"])]
  (view s).parallelSafe == [["a", "c"]] && (readyIn s.tasks .device).map (·.id) == ["p"] &&
  (view s).tasks.map (·.lane) == [.agent, .device, .device, .agent]
-- late definition: a live agent named like the task claims it; another live agent does not
#guard let s := run [.define { mk "a" [] with live := ["a", "x"] }, .define { mk "b" [] with live := ["x"] }]
  s.tasks.map (·.agent) == [some "a", none] && s.tasks.map (tstate s.tasks) == [.running, .ready]
#guard let s := run [.define (mk "a" []), .claim "a" "lead-1" 0, .define { mk "a" [] with live := ["z"] }]
  s.tasks.map (·.agent) == [some "lead-1"]
#guard let s := run [.define (mk "a" []), .define { mk "a" ["b"] with live := ["a"] }]
  s.tasks.map (·.agent) == [none]
#guard (mk "a" []).liveAgent == none && { mk "a" [] with live := ["a"] }.liveAgent == some "a"
-- cut: never ready, not grouped, not on the critical path, not counted; evidence still wins
#guard let s := run [.milestone "M0" "Zero", .define { mk "a" [] ["x/**"] with milestone := some "M0" },
    .define { mk "c" [] ["y/**"] with milestone := some "M0", cut := true },
    .define { mk "d" ["c"] with milestone := some "M0", cut := true },
    .define { mk "e" [] with milestone := some "M0", cut := true, evidence := some "abc1234" },
    .claim "c" "agent-c" 0]
  s.tasks.map (tstate s.tasks) == [.ready, .cut, .cut, .done] && (view s).parallelSafe == [["a"]] &&
  (view s).criticalPath == ["a"] &&
  (view s).milestones == [{ id := "M0", title := "Zero", done := 0, total := 1 }]
#guard let s := run [.define { mk "a" [] with cut := true }, .define (mk "a" [])]
  s.tasks.map (tstate s.tasks) == [.ready]
-- agent binding: the obs-next-lean trace, define then spawn and spawn then define, bind the same agent
#guard let s := run [.define (mk "obs-next-lean" []), .spawn "obs-next-lean" 1]
  boundTo s "obs-next-lean" == some "obs-next-lean" &&
  (view s).tasks.map (·.state) == [.running]
#guard let s := run [.spawn "obs-next-lean" 2, .define (mk "obs-next-lean" [])]
  boundTo s "obs-next-lean" == some "obs-next-lean" &&
  (view s).tasks.map (·.state) == [.running]
-- stop before define: the agent ended before its task existed and left no handback, so the task
-- is parked (reason `noHandback`), unbound (task `task-state-truth`; it was ready before)
#guard let s := run [.spawn "a" 3, .stop "a" 4, .define (mk "a" [])]
  boundTo s "a" == none && (view s).tasks.map (·.state) == [.parked]
-- a stop unbinds an undone task; a respawn under the same name binds it again
#guard let s := run [.define (mk "a" []), .spawn "a" 5, .stop "a" 6]
  boundTo s "a" == none && ended s "a"
#guard let s := run [.define (mk "a" []), .spawn "a" 7, .stop "a" 8, .spawn "a" 9]
  boundTo s "a" == some "a" && !ended s "a"
-- a done task keeps its agent after the stop
#guard let s := run [.define (mk "a" []), .spawn "a" 10, .done "a" "abc1234", .stop "a" 11]
  boundTo s "a" == some "a" && (view s).tasks.map (·.state) == [.done]
-- an explicit claim wins over the name match; once its agent stops, the name match takes over
#guard let s := run [.define (mk "a" []), .spawn "a" 12, .claim "a" "lead-1" 12]
  boundTo s "a" == some "lead-1"
#guard let s := run [.define (mk "a" []), .spawn "a" 13, .claim "a" "lead-1" 13, .stop "lead-1" 14]
  boundTo s "a" == some "a"
-- an agent named unlike every task binds nothing; no row gives none
#guard let s := run [.define (mk "a" []), .spawn "x" 15]
  boundTo s "a" == none && boundTo s "zz" == none
-- old logs (no spawn/stop): a legacy live define with no sighting binds nothing (liveness comes
-- from sightings only), so it can never run forever
#guard let s := run [.define { mk "a" [] with live := ["a"] }]
  boundTo s "a" == none && (view s).tasks.map (·.state) == [.ready]
-- plan sync reads main's head, once per head
#guard syncFrom "main" [("ci/x", "c1"), ("main", "m1")] none == some "m1"
#guard syncFrom "main" [("main", "m1")] (some "m1") == none
#guard syncFrom "main" [("main", "m2")] (some "m1") == some "m2"
#guard syncFrom "main" [("ci/x", "c1")] (some "m1") == none
#guard syncFrom "main" [] none == none
#guard syncFrom "main" [("main", "m1"), ("main", "m2")] none == some "m1"
-- sync idempotence: the same define twice is the same state
#guard let s := run [.define (mk "a" []), .define (mk "a" [])]
  s == run [.define (mk "a" [])]

-- evidence on main: commit evidence off main is refused with its sha and the state is kept
#guard Def.offMain { mk "a" [] with evidence := some "9a5c552", onMain := false } == some "9a5c552"
#guard Def.offMain { mk "a" [] with evidence := some "9a5c552" } == none
#guard Def.offMain { mk "a" [] with evidence := some "12345678", onMain := false } == none
#guard Def.offMain { mk "a" [] with evidence := some "user", onMain := false } == none
#guard Def.offMain { mk "a" [] with onMain := false } == none
#guard check {} (.define { mk "a" [] with evidence := some "9a5c552", onMain := false })
  == some "evidence not on main: 9a5c552"
#guard let s := run [.define (mk "a" [])]
  step s (.define { mk "a" [] with evidence := some "9a5c552", onMain := false }) == s
-- keepEv: landed evidence stays, unlanded evidence follows the define
#guard keepEv ((mk "a" []).row none (some "abc1234") true) (mk "a" []) == some "abc1234"
#guard keepEv ((mk "a" []).row none (some "abc1234") false) (mk "a" []) == none
#guard keepEv ((mk "a" []).row none none false) { mk "a" [] with evidence := some "def5678" }
  == some "def5678"
-- a define without evidence takes back define evidence (ready again) but never a land
#guard let s := run [.define { mk "a" [] with evidence := some "abc1234" }, .define (mk "a" [])]
  s.tasks.map (tstate s.tasks) == [.ready]
#guard let s := run [.define (mk "a" []), .done "a" "abc1234", .define (mk "a" [])]
  s.tasks.map (tstate s.tasks) == [.done] && isLanded s.tasks "a"
#guard let s := run [.define { mk "a" [] with evidence := some "abc1234" }]
  isDone s.tasks "a" && !isLanded s.tasks "a"
#guard !isLanded [] "a"

-- outcomes (task `task-state-truth`): a live agent wins over a mark; once it ends the mark shows
#guard let s := run [.define (mk "a" []), .spawn "a" 16, .handback "a" "a" (some "abc1234")]
  (view s).tasks.map (·.state) == [.running]
#guard let s := run [.define (mk "a" []), .spawn "a" 17, .handback "a" "a" (some "abc1234"), .stop "a" 18]
  (view s).tasks.map (·.state) == [.handedBack] &&
  (view s).tasks.map (·.outcome) == [some (.handedBack "a" (some "abc1234"))]
#guard let s := run [.define (mk "a" []), .spawn "a" 19, .stop "a" 20, .integrate "a" "refs/heads/ci/i-3" "b00ef68"]
  (view s).tasks.map (·.state) == [.integrated]
#guard let s := run [.define (mk "a" []), .spawn "a" 21, .stop "a" 22, .park "a" "folded"]
  (view s).tasks.map (·.state) == [.parked] &&
  (view s).tasks.map (·.outcome) == [some (.parked "folded")]
-- the last mark wins; unpark clears it, and the ended agent then shows parked (no handback)
#guard let s := run [.define (mk "a" []), .park "a" "x", .integrate "a" "refs/heads/ci/i" "t1"]
  (view s).tasks.map (·.state) == [.integrated]
#guard let s := run [.define (mk "a" []), .park "a" "x", .unpark "a"]
  (view s).tasks.map (·.state) == [.ready] && markOf s "a" == none
#guard let s := run [.define (mk "a" []), .spawn "a" 23, .stop "a" 24, .park "a" "x", .unpark "a"]
  (view s).tasks.map (·.outcome) == [some (.parked noHandback)]
-- an ended agent with no mark: parked with reason noHandback; a respawn shows running again
#guard let s := run [.define (mk "a" []), .spawn "a" 25, .stop "a" 26]
  (view s).tasks.map (·.state) == [.parked] &&
  s.tasks.map (outcomeOf s) == [some (.parked noHandback)]
#guard let s := run [.define (mk "a" []), .spawn "a" 27, .stop "a" 28, .spawn "a" 29]
  (view s).tasks.map (·.state) == [.running]
-- done wins over every mark
#guard let s := run [.define (mk "a" []), .park "a" "x", .done "a" "abc1234"]
  (view s).tasks.map (·.state) == [.done]
-- a live agent on a task with open blockers: the board shows blocked, not running
#guard let s := run [.define (mk "b" []), .define (mk "a" ["b"]), .spawn "a" 30]
  (view s).tasks.map (·.state) == [.ready, .blocked] && boundTo s "a" == some "a"
-- ... even when it has a mark: open blockers win over marks while the agent lives
-- (`tstate_agent_blocked`); once it ends, the mark shows
#guard let s := run [.define (mk "b" []), .define (mk "a" ["b"]), .spawn "a" 31, .integrate "a" "refs/heads/ci/i" "t"]
  (view s).tasks.map (·.state) == [.ready, .blocked]
#guard let s := run [.define (mk "b" []), .define (mk "a" ["b"]), .spawn "a" 31, .integrate "a" "refs/heads/ci/i" "t",
    .stop "a" 32]
  (view s).tasks.map (·.state) == [.ready, .integrated]
-- a task parked `folded-no-change` clears its dependents' deps; another park does not
#guard let s := run [.define (mk "b" []), .define (mk "a" ["b"]), .park "b" foldedNoChange]
  (view s).tasks.map (·.state) == [.parked, .ready]
#guard let s := run [.define (mk "b" []), .define (mk "a" ["b"]), .park "b" "folded"]
  (view s).tasks.map (·.state) == [.parked, .blocked]
-- times, not log order, decide: a stop logged before an earlier spawn still ends the agent; a
-- spawn (or tool-event heartbeat) after the stop revives it
#guard let s := run [.define (mk "a" []), .stop "a" 5, .spawn "a" 3]
  ended s "a" && (view s).tasks.map (·.state) == [.parked]
#guard let s := run [.define (mk "a" []), .spawn "a" 3, .stop "a" 5, .spawn "a" 7]
  !ended s "a" && (view s).tasks.map (·.state) == [.running] &&
  (view s).tasks.map (·.since) == [some 7]
-- integration is accepted only into the allowlist: every spelling of main is refused
#guard ["main", "HEAD", "origin/main", "refs/heads/main", "@", "main~0", "origin/HEAD", "ci/x"].all fun b =>
  check (run [.define (mk "a" [])]) (.integrate "a" b "t") ==
    some "integrate only into refs/heads/ci/*, refs/heads/worktree-* or refs/heads/integrate-*"
#guard ["refs/heads/ci/x", "refs/heads/worktree-wf_1", "refs/heads/integrate-ports-3"].all fun b =>
  check (run [.define (mk "a" [])]) (.integrate "a" b "t") == none
-- refusals: unknown task, done task, integration into main
#guard check {} (.park "a" "x") == some "no such task"
#guard check (run [.define (mk "a" []), .done "a" "abc1234"]) (.handback "a" "a" none) ==
  some "task already done"
#guard check (run [.define (mk "a" [])]) (.integrate "a" "main" "t") ==
  some "integrate only into refs/heads/ci/*, refs/heads/worktree-* or refs/heads/integrate-*"
#guard check (run [.define (mk "a" [])]) (.unpark "a") == none
#guard markOf (run [.define (mk "a" []), .park "a" "x"]) "b" == none
-- quiet timeout: due only after more than `quietMs`, never for a done task or a bare claim
#guard let s := run [.define (mk "a" []), .spawn "a" 1000]
  timeouts quietMs (1000 + quietMs + 1) (view s).tasks == [("a", 1000)] &&
  timeouts quietMs (1000 + quietMs) (view s).tasks == []
#guard let s := run [.define (mk "a" []), .spawn "a" 1000, .done "a" "abc1234"]
  timeouts quietMs (10 * quietMs) (view s).tasks == []
-- claim TTL: a claim with no spawn is a sighting at claim time; it expires after `quietMs` and the
-- sweep parks the row with reason `expired`
#guard let s := run [.define (mk "a" []), .claim "a" "lead-1" 500]
  timeouts quietMs (500 + quietMs) (view s).tasks == [] &&
  (view s).tasks.map (·.state) == [.running] && (view s).tasks.map (·.since) == [some 500] &&
  timeouts quietMs (500 + quietMs + 1) (view s).tasks == [("lead-1", 500)] &&
  (view (sweep quietMs (500 + quietMs + 1) s)).tasks.map (·.outcome) == [some (.parked expired)]
-- a spawned agent that goes quiet is parked with reason noHandback after the sweep
#guard let s := run [.define (mk "a" []), .spawn "a" 1000]
  (view (sweep quietMs (1000 + quietMs + 1) s)).tasks.map (·.outcome) == [some (.parked noHandback)] &&
  (view (sweep quietMs (1000 + quietMs) s)).tasks.map (·.state) == [.running]
-- liveness by key: a labelled id keeps its name live; the id's stop ends it; any later event of the
-- id revives it, and the quiet timeout stops the id at its last sighting
#guard let s := run [.define (mk "a" []), .label "id-1" "a", .spawn "id-1" 10]
  keysOf s "a" == ["a", "id-1"] && boundTo s "a" == some "a" && !ended s "a" &&
  liveKeys s "a" == [("id-1", 10)]
#guard let s := run [.define (mk "a" []), .label "id-1" "a", .spawn "id-1" 10, .stop "id-1" 20]
  ended s "a" && boundTo s "a" == none &&
  (view s).tasks.map (·.outcome) == [some (.parked noHandback)]
#guard let s := run [.define (mk "a" []), .label "id-1" "a", .spawn "id-1" 10, .stop "id-1" 20,
    .spawn "id-1" 30]
  !ended s "a" && boundTo s "a" == some "a" && (view s).tasks.map (·.state) == [.running]
#guard let s := run [.define (mk "a" []), .label "id-1" "a", .spawn "id-1" 10]
  let s' := sweep quietMs (10 + quietMs + 1) s
  ended s' "a" && !ended (step s' (.spawn "id-1" 11)) "a"
-- two keys: the name stays live while one key is live
#guard let s := run [.define (mk "a" []), .label "id-1" "a", .label "id-2" "a", .spawn "id-1" 1,
    .spawn "id-2" 2, .stop "id-1" 3]
  !ended s "a" && liveKeys s "a" == [("id-2", 2)] && seenAt s "a" == some 2
-- labels and claims are not life commands: a stop of an unlabelled id does not touch the name
#guard let s := run [.define (mk "a" []), .spawn "a" 1, .stop "id-9" 5]
  !ended s "a" && s.tasks.map (endReason s) == [noHandback]
#guard let s := run [.define (mk "a" []), .spawn "a" 1000]
  let s' := step s (.stop "a" (1000 + quietMs + 1))
  ended s' "a" && (view s').tasks.map (·.state) == [.parked]

end Fw.Plan
