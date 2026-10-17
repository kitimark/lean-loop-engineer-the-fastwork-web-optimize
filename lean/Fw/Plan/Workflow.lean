import Fw.Plan.Core
/-!
# Workflow runs as agent events (task `workflow-claim`)

Task binding (`Fw.Plan.agentOf`) reads only `agent.spawn` / `agent.stop` of named `Agent` spawns. A Workflow
run (`wf_<8 hex>-<3 hex>`) and its unnamed subagents never emit one, and the spawn guard never sees them
(PreToolUse(Agent) does not fire for workflow agents), so a task worked on by a workflow stayed in the
ready lane (incident `inc-workflow-unbound`). This module maps a run to plan commands.

* **Signal (CONFIRMED, research/notes/2026/10-18-transcript-signals.md and the session dir):** Claude Code
  writes `<session>/workflows/scripts/<meta.name>-<runId>.js` when the run starts (the file name carries
  both the name and the run id; the script is not parsed), and `<session>/workflows/<runId>.json`
  (`status` completed | killed) when it ends. `scriptRun` / `runFileId` read those two file names.
* **Mapping:** a run whose name is a task id gives `spawn(name)`, and `stop(name)` once its run file
  exists; the run id is the evidence (the event keys `wf:<runId>` and `wf-end:<runId>`).
  A run whose name is not a task id gives no command.
* **Proved:** the run binds its task (`workflow_binds`), unbinds an undone one at its end
  (`workflow_ends`) and keeps a done one (`workflow_done_keeps`); a name that is no task id binds
  nothing (`workflow_foreign_none`, `workflow_foreign_agentOf`); a define commutes with the run's
  commands (`define_workflow_comm`), so the claim-order race stays gone.

Golden: `packages/contracts/golden/plan/workflow.jsonl` (`Fw.Wire.Plan.Golden`).
-/
namespace Fw.Plan

/-- A run id has the form `wf_` + 8 lowercase hex digits + `-` + 3 lowercase hex digits.

$$\operatorname{isRunId}(s) \iff s \in \texttt{wf\_}\,[0\text{-}9a\text{-}f]^{8}\,\texttt{-}\,[0\text{-}9a\text{-}f]^{3}$$
-/
def isRunId (s : String) : Bool :=
  let cs := s.toList
  let hex (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'f')
  cs.length == 15 && cs.take 3 == ['w', 'f', '_'] && ((cs.drop 3).take 8).all hex
    && cs[11]? == some '-' && (cs.drop 12).all hex

/-- Name and run id of a script file name `<name>-<runId>.js` (the name is non-empty and may itself
contain `-`; the run id is the fixed-width tail).

$$\operatorname{scriptRun}(f) = (n, r) \iff f = n \mathbin{+\!\!+} \texttt{-} \mathbin{+\!\!+} r \mathbin{+\!\!+} \texttt{.js} \land n \ne \varepsilon \land \operatorname{isRunId}(r)$$
-/
def scriptRun (f : String) : Option (String × String) :=
  if f.endsWith ".js" then
    let cs := (f.dropEnd 3).toString.toList
    let n := cs.length
    if 16 < n then
      let r := String.ofList (cs.drop (n - 15))
      if cs[n - 16]? == some '-' && isRunId r then some (String.ofList (cs.take (n - 16)), r) else none
    else none
  else none

/-- The run id of a run file name `<runId>.json`.

$$\operatorname{runFileId}(f) = r \iff f = r \mathbin{+\!\!+} \texttt{.json} \land \operatorname{isRunId}(r)$$
-/
def runFileId (f : String) : Option String :=
  if f.endsWith ".json" then
    let r := (f.dropEnd 5).toString
    if isRunId r then some r else none
  else none

/-- A workflow run: its id (the evidence) and its `meta.name`.

$$w = (\mathit{run}, \mathit{name})$$
-/
structure Wf where
  run  : String
  name : String
deriving Repr, DecidableEq

/-- The plan commands of a run, given the task ids and whether the run has ended: a name that is a task id
spawns that agent, and stops it once the run ended; any other name gives none.

$$\operatorname{cmds}(I, e, w) = \begin{cases} [\mathrm{spawn}(w.\mathit{name}), \mathrm{stop}(w.\mathit{name})] & w.\mathit{name} \in I \land e \\ [\mathrm{spawn}(w.\mathit{name})] & w.\mathit{name} \in I \land \lnot e \\ [\,] & w.\mathit{name} \notin I \end{cases}$$
-/
def Wf.cmds (ids : List String) (ended : Bool) (w : Wf) : List Cmd :=
  if ids.contains w.name then .spawn w.name :: (if ended then [.stop w.name] else []) else []

/-- `run` of an appended list continues the fold.

$$\forall as, bs:\quad \operatorname{run}(as \mathbin{+\!\!+} bs) = \operatorname{foldl}(\operatorname{step}, \operatorname{run}(as), bs)$$
-/
theorem run_append (as bs : List Cmd) : run (as ++ bs) = bs.foldl step (run as) := by
  simp [run, List.foldl_append]

/-- **A running workflow named `t` binds `t`**: if the first row `r` with id `t` has no stored agent and is
not done, and the name `t` is not ended (no more stops than spawns), then after `spawn(t)` the board binds
agent `t` to it.

$$\forall \pi, t, r:\ \operatorname{row}_t(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = \bot \land \#_t(\pi.\mathit{stops}) \le \#_t(\pi.\mathit{spawns}) \Rightarrow \operatorname{boundTo}(\operatorname{step}(\pi, \mathrm{spawn}(t)), t) = t$$
-/
theorem workflow_binds (π : State) (t : String) (r : Task)
    (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none) (he : r.evidence = none)
    (hb : π.stops.count t ≤ π.spawns.count t) :
    boundTo (step π (.spawn t)) t = some t := by
  have hid : r.id = t := by
    have := List.find?_some hr
    simpa using this
  simp [boundTo, step_spawn, hr, agentOf, cands, he, ha, hid, List.count_append, ended]
  omega

/-- **The end of a workflow unbinds an undone task**: after `spawn(t)` and `stop(t)` of a name whose
spawns and stops were balanced, the task is no longer bound (a done task keeps `t`, below).

$$\forall \pi, t, r:\ \operatorname{row}_t(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = \bot \land \#_t(\pi.\mathit{stops}) = \#_t(\pi.\mathit{spawns}) \Rightarrow \operatorname{boundTo}(\operatorname{step}(\operatorname{step}(\pi, \mathrm{spawn}(t)), \mathrm{stop}(t)), t) = \bot$$
-/
theorem workflow_ends (π : State) (t : String) (r : Task)
    (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none) (he : r.evidence = none)
    (hb : π.stops.count t = π.spawns.count t) :
    boundTo (step (step π (.spawn t)) (.stop t)) t = none := by
  have hid : r.id = t := by
    have := List.find?_some hr
    simpa using this
  simp [boundTo, step_spawn, step_stop, hr, agentOf, cands, he, ha, hid, List.count_append, ended]
  omega

/-- A done task keeps the workflow's agent after the run ended.

$$\forall \pi, t, r, e:\ \operatorname{row}_t(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = e \Rightarrow \operatorname{boundTo}(\operatorname{step}(\operatorname{step}(\pi, \mathrm{spawn}(t)), \mathrm{stop}(t)), t) = t$$
-/
theorem workflow_done_keeps (π : State) (t : String) (r : Task) (e : String)
    (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none) (he : r.evidence = some e) :
    boundTo (step (step π (.spawn t)) (.stop t)) t = some t := by
  have hid : r.id = t := by
    have := List.find?_some hr
    simpa using this
  simp [boundTo, step_spawn, step_stop, hr, agentOf, cands, he, ha, hid, List.count_append, ended]
  split <;> simp

/-- A run whose name is not a task id gives no command.

$$\forall I, e, w:\quad w.\mathit{name} \notin I \Rightarrow \operatorname{cmds}(I, e, w) = [\,]$$
-/
theorem workflow_foreign_none (ids : List String) (ended : Bool) (w : Wf)
    (h : w.name ∉ ids) : w.cmds ids ended = [] := by
  simp [Wf.cmds, h]

/-- `find?` agrees for two predicates that agree on the list.

$$\forall p, q, l:\ (\forall a \in l:\ p(a) = q(a)) \Rightarrow \operatorname{find}(p, l) = \operatorname{find}(q, l)$$
-/
theorem find_congr (p q : String → Bool) :
    ∀ l : List String, (∀ a ∈ l, p a = q a) → l.find? p = l.find? q
  | [], _ => rfl
  | a :: l, h => by
    simp only [List.find?_cons, h a (List.mem_cons_self ..)]
    rw [find_congr p q l (fun b hb => h b (List.mem_cons_of_mem _ hb))]

/-- Spawns and stops of one name `n` change the binding of no row whose id is not `n` and whose stored agent
is not `n`: a workflow that is no task id binds nothing.

$$\forall \pi, t, n, xs, ys:\ t.\mathit{id} \ne n \land t.\mathit{agent} \ne \mathrm{some}(n) \land (\forall x \in xs \cup ys:\ x = n) \Rightarrow \operatorname{agentOf}(\pi[\mathit{spawns} := \pi.\mathit{spawns} \mathbin{+\!\!+} xs,\ \mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} ys], t) = \operatorname{agentOf}(\pi, t)$$
-/
theorem workflow_foreign_agentOf (π : State) (t : Task) (n : String) (xs ys : List String)
    (hx : ∀ x ∈ xs, x = n) (hy : ∀ y ∈ ys, y = n) (hid : t.id ≠ n) (hag : t.agent ≠ some n) :
    agentOf { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } t = agentOf π t := by
  have cx : ∀ a, a ≠ n → xs.count a = 0 := fun a ha =>
    List.count_eq_zero.2 fun h => ha (hx a h)
  have cy : ∀ a, a ≠ n → ys.count a = 0 := fun a ha =>
    List.count_eq_zero.2 fun h => ha (hy a h)
  have hend : ∀ a, a ≠ n →
      ended { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } a = ended π a := by
    intro a ha
    simp [ended, List.count_append, cx a ha, cy a ha]
  have hc : cands { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } t = cands π t := by
    simp [cands, List.count_append, cx _ hid]
  have hmem : ∀ a ∈ cands π t, a ≠ n := by
    intro a ha
    simp only [cands, List.mem_append, Option.mem_toList, List.mem_ite_nil_right,
      List.mem_singleton] at ha
    rcases ha with h | ⟨_, h⟩
    · intro e; exact hag (by rw [h, e])
    · intro e; exact hid (by rw [← h, e])
  have hf : (cands π t).find? (fun a => !ended { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } a)
      = (cands π t).find? (fun a => !ended π a) := by
    exact find_congr _ _ _ (fun a ha => by rw [hend a (hmem a ha)])
  unfold agentOf
  rw [hc, hf]

/-- A run of a name that is no task id leaves every binding alone.

$$\forall es, w, I, e, x:\ w.\mathit{name} \notin I \Rightarrow \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} w.\mathit{cmds}), x) = \operatorname{boundTo}(\operatorname{run}(es), x)$$
-/
theorem workflow_foreign_bound (es : List Cmd) (ids : List String) (ended : Bool) (w : Wf) (x : String)
    (h : w.name ∉ ids) : boundTo (run (es ++ w.cmds ids ended)) x = boundTo (run es) x := by
  rw [workflow_foreign_none ids ended w h]
  simp

/-- A define commutes with the commands of a run: the same plan state in either order, after any prefix.

$$\forall es, d, cs:\quad (\forall c \in cs:\ \operatorname{isLife}(c)) \Rightarrow \operatorname{run}(es \mathbin{+\!\!+} \mathrm{define}(d) :: cs) = \operatorname{run}(es \mathbin{+\!\!+} cs \mathbin{+\!\!+} [\mathrm{define}(d)])$$
-/
theorem define_life_comm (d : Def) :
    ∀ (cs es : List Cmd), (∀ c ∈ cs, c.isLife = true) →
      run (es ++ .define d :: cs) = run (es ++ cs ++ [.define d])
  | [], es, _ => by simp
  | c :: cs, es, h => by
    have hc := h c (List.mem_cons_self ..)
    have h1 := run_comm es (c := .define d) (l := c) rfl hc
    have ih := define_life_comm d cs (es ++ [c]) (fun x hx => h x (List.mem_cons_of_mem _ hx))
    calc run (es ++ .define d :: c :: cs) = run (es ++ [.define d, c] ++ cs) := by simp
      _ = cs.foldl step (run (es ++ [.define d, c])) := run_append _ _
      _ = cs.foldl step (run (es ++ [c, .define d])) := by rw [h1]
      _ = run (es ++ [c, .define d] ++ cs) := (run_append _ _).symm
      _ = run ((es ++ [c]) ++ .define d :: cs) := by simp
      _ = run ((es ++ [c]) ++ cs ++ [.define d]) := ih
      _ = run (es ++ c :: cs ++ [.define d]) := by simp

/-- The commands of any run are spawns and stops.

$$\forall I, e, w, c \in w.\mathit{cmds}(I, e):\ \operatorname{isLife}(c) = \mathrm{true}$$
-/
theorem Wf.cmds_life (ids : List String) (ended : Bool) (w : Wf) :
    ∀ c ∈ w.cmds ids ended, c.isLife = true := by
  intro c hc
  unfold Wf.cmds at hc
  split at hc
  · cases ended <;> simp at hc <;> rcases hc with rfl | rfl <;> rfl
  · simp at hc

/-- **The claim-order race stays gone for workflows**: defining task `x` and running a workflow bind the same
agent in either order, after any log prefix.

$$\forall es, d, I, e, w, x:\quad \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} \mathrm{define}(d) :: w.\mathit{cmds}), x) = \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} w.\mathit{cmds} \mathbin{+\!\!+} [\mathrm{define}(d)]), x)$$
-/
theorem define_workflow_comm (es : List Cmd) (d : Def) (ids : List String) (ended : Bool) (w : Wf)
    (x : String) :
    boundTo (run (es ++ .define d :: w.cmds ids ended)) x =
      boundTo (run (es ++ w.cmds ids ended ++ [.define d])) x := by
  rw [define_life_comm d _ es (Wf.cmds_life ids ended w)]

/-- The runs of a list of script file names, each (run id, name) pair once.

$$\operatorname{runs}(fs) = \operatorname{dedup}([\, (r, n) : f \in fs,\ \operatorname{scriptRun}(f) = (n, r) \,])$$
-/
def runsOf (scripts : List String) : List Wf :=
  (scripts.filterMap fun f => (scriptRun f).map fun (n, r) => ({ run := r, name := n } : Wf)).eraseDups

/-- The events (key, type, agent) of the workflow runs seen in the session's `workflows/` dir, given the
task ids, the script file names and the run file names: a run's script gives `agent.spawn` (key
`wf:<runId>`), its run file also `agent.stop` (key `wf-end:<runId>`); only runs named like a task.

$$\operatorname{events}(I, S, R) = \mathop{\mathrm{concat}}_{w \in \operatorname{runs}(S)} \operatorname{ev}(w.\mathit{run}, w.\mathit{cmds}(I, w.\mathit{run} \in \operatorname{ids}(R))),\quad \operatorname{ev}(r, \mathrm{spawn}(a)) = (\texttt{wf:}r, \texttt{agent.spawn}, a),\ \operatorname{ev}(r, \mathrm{stop}(a)) = (\texttt{wf-end:}r, \texttt{agent.stop}, a)$$
-/
def wfEvents (ids scripts runFiles : List String) : List (String × String × String) :=
  let ended := runFiles.filterMap runFileId
  (runsOf scripts).flatMap fun w =>
    (w.cmds ids (ended.contains w.run)).filterMap fun
      | .spawn a => some (s!"wf:{w.run}", "agent.spawn", a)
      | .stop a => some (s!"wf-end:{w.run}", "agent.stop", a)
      | _ => none

/-- No script named like a task, no event: a workflow that is no task id emits nothing.

$$\forall I, S, R:\ (\forall w \in \operatorname{runs}(S):\ w.\mathit{name} \notin I) \Rightarrow \operatorname{events}(I, S, R) = [\,]$$
-/
theorem wfEvents_foreign (ids scripts runFiles : List String)
    (h : ∀ w ∈ runsOf scripts, w.name ∉ ids) : wfEvents ids scripts runFiles = [] := by
  unfold wfEvents
  rw [List.flatMap_eq_nil_iff]
  intro w hw
  rw [workflow_foreign_none ids _ w (h w hw)]
  rfl

end Fw.Plan
