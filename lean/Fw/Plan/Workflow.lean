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
* **Mapping (identity only, task `task-state-truth`):** a run whose name is a task id labels its run
  key `wf:<runId>` with the name, spawns the run key, and stops the run key once its run file exists
  (event keys `wfr-label:<runId>`, `wfr:<runId>`, `wfr-end:<runId>`). A labelled agent of a run does
  the same with its agent id (event keys `wfid-label:`, `wfid:`, `wfid-end:` + `<runId>:<id>`). A task
  name is never a life key, only a label, so the stop of one agent never ends a task another agent
  of the same task still works on (`concurrent_keep`, `workflow_concurrent`). A run whose name is
  not a task id gives no command.
* **Proved:** the run binds its task (`workflow_binds`), unbinds an undone one at its end when nothing
  else keeps it (`workflow_ends`) and keeps a done one (`workflow_done_keeps`); a name that is no task
  id binds nothing (`workflow_foreign_none`, `workflow_foreign_agentOf`); every event is keyed by a
  run key or an agent id (`wfAllEvents_identity`); a define commutes with the run's commands
  (`define_workflow_comm`), so the claim-order race stays gone.

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

/-- The life key of a run: `wf:` followed by the run id.

$$\operatorname{runKey}(r) = \texttt{wf:} \mathbin{+\!\!+} r$$

The run's own identity, never a task name.
-/
def runKey (r : String) : String := "wf:" ++ r

/-- The plan commands of a run at time $n$, given the task ids and whether the run has ended: a name
that is a task id labels the run key with the name and spawns the run key, and stops the run key
once the run ended; any other name gives none. (In the event wire the time is the event's stamp, so
`wfEvents` passes $0$.)

$$\operatorname{cmds}(I, e, w, n) = \begin{cases} [\mathrm{label}(\kappa, w.\mathit{name}), \mathrm{spawn}(\kappa, n), \mathrm{stop}(\kappa, n)] & w.\mathit{name} \in I \land e \\ [\mathrm{label}(\kappa, w.\mathit{name}), \mathrm{spawn}(\kappa, n)] & w.\mathit{name} \in I \land \lnot e \\ [\,] & w.\mathit{name} \notin I \end{cases},\qquad \kappa = \operatorname{runKey}(w.\mathit{run})$$
-/
def Wf.cmds (ids : List String) (ended : Bool) (w : Wf) (n : Nat) : List Cmd :=
  if ids.contains w.name then
    .label (runKey w.run) w.name :: .spawn (runKey w.run) n ::
      (if ended then [.stop (runKey w.run) n] else [])
  else []

/-- `run` of an appended list continues the fold.

$$\forall as, bs:\quad \operatorname{run}(as \mathbin{+\!\!+} bs) = \operatorname{foldl}(\operatorname{step}, \operatorname{run}(as), bs)$$
-/
theorem run_append (as bs : List Cmd) : run (as ++ bs) = bs.foldl step (run as) := by
  simp [run, List.foldl_append]

/-- A label step only appends the label.

$$\forall \pi, k, a:\quad \operatorname{step}(\pi, \mathrm{label}(k, a)) = \pi[\mathit{labels} := \pi.\mathit{labels} \mathbin{+\!\!+} [(k, a)]]$$
-/
theorem step_label (π : State) (k a : String) :
    step π (.label k a) = { π with labels := π.labels ++ [(k, a)] } := by
  simp [step, check, exec]

/-- **A labelled key binds its name**: if the first row with id $t$ has no stored agent and is not
done, and every stop of the key $k$ is earlier than $n$, then after $\mathrm{label}(k, t)$ and
$\mathrm{spawn}(k, n)$ the board binds agent $t$ to it.

$$\forall \pi, k, t, n, r:\ \operatorname{row}_t(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = \bot \land (\forall (b, m) \in \pi.\mathit{stops}:\ b = k \Rightarrow m < n) \Rightarrow \operatorname{boundTo}(\operatorname{step}(\operatorname{step}(\pi, \mathrm{label}(k, t)), \mathrm{spawn}(k, n)), t) = \mathrm{some}(t)$$

A fresh id or run key that works on a task makes the task running.
-/
theorem bind_key (π : State) (k t : String) (n : Nat) (r : Task)
    (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none) (he : r.evidence = none)
    (hb : ∀ q ∈ π.stops, q.1 = k → q.2 < n) :
    boundTo (step (step π (.label k t)) (.spawn k n)) t = some t := by
  have hid : r.id = t := by simpa using List.find?_some hr
  rw [step_label]
  have hk : k ∈ keysOf { π with labels := π.labels ++ [(k, t)] } t := by simp [keysOf]
  obtain ⟨hl, hend⟩ := revive_on_event { π with labels := π.labels ++ [(k, t)] } (n := n) hk hb
  have ho : opened (step { π with labels := π.labels ++ [(k, t)] } (.spawn k n)) t = true := by
    simp only [liveK, Bool.and_eq_true] at hl
    simp only [opened, List.any_eq_true]
    exact ⟨k, by rw [step_spawn]; exact hk, hl.1⟩
  have hr' : (step { π with labels := π.labels ++ [(k, t)] } (.spawn k n)).tasks.find? (·.id == t) =
      some r := by rw [step_spawn]; exact hr
  simp [boundTo, hr', agentOf, cands, ho, he, ha, hid, hend]

/-- More sightings and the same stops make no key less live.

$$\forall \pi, \pi', k:\quad (\forall p \in \operatorname{sights}(\pi):\ p \in \operatorname{sights}(\pi')) \land \pi'.\mathit{stops} = \pi.\mathit{stops} \land \operatorname{liveK}(\pi, k) = \mathrm{true} \Rightarrow \operatorname{liveK}(\pi', k) = \mathrm{true}$$
-/
theorem liveK_mono {π π' : State} {k : String} (hs : ∀ p ∈ sights π, p ∈ sights π')
    (hq : π'.stops = π.stops) (h : liveK π k = true) : liveK π' k = true := by
  simp only [liveK, openedK, endedK, Bool.and_eq_true, Bool.not_eq_true', List.any_eq_true,
    List.any_eq_false, List.all_eq_true, hq] at h ⊢
  obtain ⟨⟨p, hp, hpk⟩, h2⟩ := h
  exact ⟨⟨p, hs p hp, hpk⟩, fun q hq' hq2 => h2 q hq' ⟨hq2.1, fun p hp => hq2.2 p (hs p hp)⟩⟩

/-- No step removes a label.

$$\forall \pi, c, p:\quad p \in \pi.\mathit{labels} \Rightarrow p \in \operatorname{step}(\pi, c).\mathit{labels}$$
-/
theorem labels_step (π : State) (c : Cmd) : ∀ p ∈ π.labels, p ∈ (step π c).labels := by
  intro p hp
  unfold step
  split
  · cases c with
    | milestone m tt => simp only [exec]; split <;> exact hp
    | _ => simp [exec, hp]
  · exact hp

/-- No step removes a key of a name.

$$\forall \pi, c, k, a:\quad k \in \operatorname{keysOf}(\pi, a) \Rightarrow k \in \operatorname{keysOf}(\operatorname{step}(\pi, c), a)$$
-/
theorem keysOf_step (π : State) (c : Cmd) {k a : String} (hk : k ∈ keysOf π a) :
    k ∈ keysOf (step π c) a := by
  simp only [keysOf, List.mem_cons, List.mem_map, List.mem_filter] at hk ⊢
  rcases hk with rfl | ⟨p, ⟨hp, hpa⟩, rfl⟩
  · exact .inl rfl
  · exact .inr ⟨p, ⟨labels_step π c p hp, hpa⟩, rfl⟩

/-- **Only a stop of a key ends it**: a live key stays live under every command that is not a stop
of that key.

$$\forall \pi, c, k:\quad (\forall m:\ c \ne \mathrm{stop}(k, m)) \land \operatorname{liveK}(\pi, k) = \mathrm{true} \Rightarrow \operatorname{liveK}(\operatorname{step}(\pi, c), k) = \mathrm{true}$$
-/
theorem liveK_step (π : State) (c : Cmd) (k : String) (hc : ∀ m, c ≠ .stop k m)
    (h : liveK π k = true) : liveK (step π c) k = true := by
  cases c with
  | stop b m =>
    have hb : k ≠ b := fun e => hc m (by rw [e])
    rw [step_stop, (liveK_stop π b m k).2 hb]
    exact h
  | milestone x tt =>
    unfold step
    split
    · simp only [exec]; split <;> exact h
    · exact h
  | _ =>
    unfold step
    split
    · refine liveK_mono (fun p hp => ?_) ?_ h <;> simp_all [exec, sights] <;>
        rcases hp with hp | hp <;> simp [hp]
    · exact h

/-- A run of commands with no stop of a live key of $a$ keeps that key live and a key of $a$.

$$\forall cs, \pi, k, a:\quad (\forall c \in cs, m:\ c \ne \mathrm{stop}(k, m)) \land k \in \operatorname{keysOf}(\pi, a) \land \operatorname{liveK}(\pi, k) = \mathrm{true} \Rightarrow k \in \operatorname{keysOf}(\pi', a) \land \operatorname{liveK}(\pi', k) = \mathrm{true},\quad \pi' = \operatorname{foldl}(\operatorname{step}, \pi, cs)$$
-/
theorem live_fold {k a : String} : ∀ (cs : List Cmd) (π : State), (∀ c ∈ cs, ∀ m, c ≠ .stop k m) →
    k ∈ keysOf π a → liveK π k = true →
    k ∈ keysOf (cs.foldl step π) a ∧ liveK (cs.foldl step π) k = true
  | [], _, _, hk, hl => ⟨hk, hl⟩
  | c :: cs, π, h, hk, hl =>
    live_fold cs (step π c) (fun x hx => h x (List.mem_cons_of_mem _ hx)) (keysOf_step π c hk)
      (liveK_step π c k (h c List.mem_cons_self) hl)

/-- **The stop of one key never ends a name another live key carries** (`concurrent_keep`): for keys
$k \ne k_2$ where $k_2$ is labelled with $a$ and live, a stop of $k$ (another id or run of the same
task included) leaves $k_2$ as live as it was, so $a$ has not ended.

$$\forall \pi, k, k_2, a, m:\quad k \ne k_2 \land (k_2, a) \in \pi.\mathit{labels} \land \operatorname{liveK}(\pi, k_2) = \mathrm{true} \Rightarrow \operatorname{liveK}(\pi', k_2) = \operatorname{liveK}(\pi, k_2) \land \operatorname{ended}(\pi', a) = \mathrm{false},\quad \pi' = \operatorname{step}(\pi, \mathrm{stop}(k, m))$$

When two agents work on one task and one stops, the task stays running.
-/
theorem concurrent_keep (π : State) {k k₂ a : String} (m : Nat) (hne : k ≠ k₂)
    (hl : (k₂, a) ∈ π.labels) (hlive : liveK π k₂ = true) :
    liveK (step π (.stop k m)) k₂ = liveK π k₂ ∧ ended (step π (.stop k m)) a = false := by
  have h1 : liveK (step π (.stop k m)) k₂ = liveK π k₂ := by
    rw [step_stop]; exact (liveK_stop π k m k₂).2 (Ne.symm hne)
  refine ⟨h1, ?_⟩
  have hk : k₂ ∈ keysOf (step π (.stop k m)) a := by
    rw [step_stop]
    exact List.mem_cons.2 (.inr (List.mem_map.2 ⟨(k₂, a), List.mem_filter.2 ⟨hl, by simp⟩, rfl⟩))
  simp only [ended, Bool.not_eq_false', List.any_eq_true]
  exact ⟨k₂, hk, h1 ▸ hlive⟩

/-- **A key that labels and spawns keeps its name running until its own stop**: after
$\mathrm{label}(k, t)$ and $\mathrm{spawn}(k, n)$ with $n$ later than every stop of $k$, any commands
without a stop of $k$ leave $t$ not ended.

$$\forall \pi, k, t, n, cs:\quad (\forall (b, m) \in \pi.\mathit{stops}:\ b = k \Rightarrow m < n) \land (\forall c \in cs, m:\ c \ne \mathrm{stop}(k, m)) \Rightarrow \operatorname{ended}(\operatorname{foldl}(\operatorname{step}, \pi, \mathrm{label}(k, t) :: \mathrm{spawn}(k, n) :: cs), t) = \mathrm{false}$$
-/
theorem key_keeps (π : State) (k t : String) (n : Nat) (cs : List Cmd)
    (hb : ∀ q ∈ π.stops, q.1 = k → q.2 < n) (hcs : ∀ c ∈ cs, ∀ m, c ≠ .stop k m) :
    ended ((Cmd.label k t :: Cmd.spawn k n :: cs).foldl step π) t = false := by
  have hk : k ∈ keysOf (step π (.label k t)) t := by rw [step_label]; simp [keysOf]
  have hs : ∀ q ∈ (step π (.label k t)).stops, q.1 = k → q.2 < n := by rw [step_label]; exact hb
  obtain ⟨hl, -⟩ := revive_on_event _ (n := n) hk hs
  have hk2 : k ∈ keysOf (step (step π (.label k t)) (.spawn k n)) t := keysOf_step _ _ hk
  obtain ⟨hk3, hl3⟩ := live_fold cs _ hcs hk2 hl
  simp only [List.foldl_cons]
  simp only [ended, Bool.not_eq_false', List.any_eq_true]
  exact ⟨k, hk3, hl3⟩

/-- **The stop of a key unbinds an undone task nothing else keeps**: after $\mathrm{label}(k, t)$,
$\mathrm{spawn}(k, n)$ and $\mathrm{stop}(k, n)$, where $n$ is no earlier than every sighting of $k$
so far and $t$ had ended before, the first row with id $t$ (no stored agent, not done) is unbound.

$$\forall \pi, k, t, n, r:\ \operatorname{row}_t(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = \bot \land \operatorname{ended}(\pi, t) = \mathrm{true} \land \operatorname{lastAt}(\pi, k) \le n \Rightarrow \operatorname{boundTo}(\operatorname{foldl}(\operatorname{step}, \pi, [\mathrm{label}(k, t), \mathrm{spawn}(k, n), \mathrm{stop}(k, n)]), t) = \bot$$
-/
theorem key_ends (π : State) (k t : String) (n : Nat) (r : Task)
    (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none) (he : r.evidence = none)
    (hend : ended π t = true) (hb : lastAt π k ≤ n) :
    boundTo ([Cmd.label k t, .spawn k n, .stop k n].foldl step π) t = none := by
  have hid : r.id = t := by simpa using List.find?_some hr
  simp only [List.foldl_cons, List.foldl_nil, step_label]
  generalize hπ1 : ({ π with labels := π.labels ++ [(k, t)] } : State) = π1
  have hle : lastAt (step π1 (.spawn k n)) k ≤ n :=
    lastAt_le fun p hp hpk => by
      rw [step_spawn, ← hπ1] at hp
      simp only [sights, List.mem_append, List.mem_singleton] at hp
      rcases hp with hp | hp | hp
      · have := le_lastAt (π := π) (k := k) (n := p.2) (by rw [← hpk]; exact List.mem_append_left _ hp)
        omega
      · have := le_lastAt (π := π) (k := k) (n := p.2) (by rw [← hpk]; exact List.mem_append_right _ hp)
        omega
      · rw [hp]; exact Nat.le_refl _
  have hE := stop_ends hle
  generalize hπ3 : step (step π1 (.spawn k n)) (.stop k n) = π3 at hE
  have hold : ∀ j ∈ keysOf π t, liveK π j = false := by
    simpa [ended] using hend
  have hk3 : keysOf π3 t = keysOf π1 t := by rw [← hπ3, step_spawn, step_stop]; rfl
  have hend3 : ended π3 t = true := by
    simp only [ended, Bool.not_eq_true', List.any_eq_false, Bool.not_eq_true]
    intro j hj
    by_cases hjk : j = k
    · rw [hjk]; simp [liveK, hE]
    · have hj' : j ∈ keysOf π t := by
        rw [hk3, ← hπ1] at hj
        simp only [keysOf, List.filter_append, List.map_append, List.mem_cons, List.mem_append,
          List.mem_map, List.mem_filter, List.not_mem_nil, or_false] at hj ⊢
        rcases hj with h | h | ⟨p, ⟨rfl, -⟩, rfl⟩
        · exact .inl h
        · exact .inr h
        · exact absurd rfl hjk
      have h1 : liveK π3 j = liveK π1 j := by
        rw [← hπ3, step_spawn, step_stop, (liveK_stop _ k n j).2 hjk, (liveK_spawn _ k n j).2 hjk]
      have h3 : liveK π1 j = liveK π j := by rw [← hπ1]; rfl
      rw [h1, h3]
      exact hold j hj'
  have hr3 : π3.tasks.find? (·.id == t) = some r := by
    rw [← hπ3, step_spawn, step_stop, ← hπ1]; exact hr
  simp only [boundTo, hr3, Option.bind_some, agentOf, he, Option.isSome_none, Bool.false_eq_true,
    ↓reduceIte, cands, ha, Option.toList_none, List.filter_nil, List.nil_append, hid]
  split <;> simp [hend3]

/-- **A done task keeps the key's name after the key's stop**: after $\mathrm{label}(k, t)$,
$\mathrm{spawn}(k, n)$ and $\mathrm{stop}(k, n)$, the first row with id $t$ (no stored agent, done
with evidence $e$) is bound to $t$.

$$\forall \pi, k, t, n, r, e:\ \operatorname{row}_t(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = \mathrm{some}(e) \Rightarrow \operatorname{boundTo}(\operatorname{foldl}(\operatorname{step}, \pi, [\mathrm{label}(k, t), \mathrm{spawn}(k, n), \mathrm{stop}(k, n)]), t) = \mathrm{some}(t)$$
-/
theorem key_done_keeps (π : State) (k t : String) (n : Nat) (r : Task) (e : String)
    (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none) (he : r.evidence = some e) :
    boundTo ([Cmd.label k t, .spawn k n, .stop k n].foldl step π) t = some t := by
  have hid : r.id = t := by simpa using List.find?_some hr
  simp only [List.foldl_cons, List.foldl_nil, step_label]
  generalize hπ3 : step (step ({ π with labels := π.labels ++ [(k, t)] } : State) (.spawn k n))
    (.stop k n) = π3
  have ho : opened π3 t = true := by
    rw [← hπ3, step_spawn, step_stop]
    simp only [opened, List.any_eq_true]
    exact ⟨k, by simp [keysOf], by simp [openedK, sights]⟩
  have hr3 : π3.tasks.find? (·.id == t) = some r := by
    rw [← hπ3, step_spawn, step_stop]; exact hr
  simp only [boundTo, hr3, Option.bind_some, agentOf, he, Option.isSome_some, ↓reduceIte, cands, ha,
    Option.toList_none, List.filter_nil, List.nil_append, hid, ho]
  simp only [List.find?_cons, List.find?_nil, List.head?_cons]; split <;> rfl

/-- **A running workflow named $t$ binds $t$**: for a run $w$ whose name is a task id, if the first
row with that id has no stored agent and is not done, and every stop of the run key is earlier than
$n$, the commands of the running run bind it.

$$\forall \pi, I, w, n, r:\ w.\mathit{name} \in I \land \operatorname{row}_{w.\mathit{name}}(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = \bot \land (\forall (b, m) \in \pi.\mathit{stops}:\ b = \operatorname{runKey}(w.\mathit{run}) \Rightarrow m < n) \Rightarrow \operatorname{boundTo}(\operatorname{foldl}(\operatorname{step}, \pi, \operatorname{cmds}(I, \mathrm{false}, w, n)), w.\mathit{name}) = \mathrm{some}(w.\mathit{name})$$
-/
theorem workflow_binds (π : State) (ids : List String) (w : Wf) (n : Nat) (r : Task)
    (hi : w.name ∈ ids) (hr : π.tasks.find? (·.id == w.name) = some r) (ha : r.agent = none)
    (he : r.evidence = none) (hb : ∀ q ∈ π.stops, q.1 = runKey w.run → q.2 < n) :
    boundTo ((w.cmds ids false n).foldl step π) w.name = some w.name := by
  have hc : ids.contains w.name = true := List.contains_iff_mem.2 hi
  simp only [Wf.cmds, hc, ↓reduceIte, Bool.false_eq_true, List.foldl_cons, List.foldl_nil]
  exact bind_key π _ _ n r hr ha he hb

/-- **The end of a workflow unbinds an undone task nothing else keeps**: for a run $w$ whose name is
a task id that had ended before, with $n$ no earlier than every sighting of the run key, the
commands of the ended run leave the first row with that id (no stored agent, not done) unbound.

$$\forall \pi, I, w, n, r:\ w.\mathit{name} \in I \land \operatorname{row}_{w.\mathit{name}}(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = \bot \land \operatorname{ended}(\pi, w.\mathit{name}) = \mathrm{true} \land \operatorname{lastAt}(\pi, \operatorname{runKey}(w.\mathit{run})) \le n \Rightarrow \operatorname{boundTo}(\operatorname{foldl}(\operatorname{step}, \pi, \operatorname{cmds}(I, \mathrm{true}, w, n)), w.\mathit{name}) = \bot$$
-/
theorem workflow_ends (π : State) (ids : List String) (w : Wf) (n : Nat) (r : Task)
    (hi : w.name ∈ ids) (hr : π.tasks.find? (·.id == w.name) = some r) (ha : r.agent = none)
    (he : r.evidence = none) (hend : ended π w.name = true) (hb : lastAt π (runKey w.run) ≤ n) :
    boundTo ((w.cmds ids true n).foldl step π) w.name = none := by
  have hc : ids.contains w.name = true := List.contains_iff_mem.2 hi
  simp only [Wf.cmds, hc, ↓reduceIte]
  exact key_ends π _ _ n r hr ha he hend hb

/-- A done task keeps the workflow's name after the run ended.

$$\forall \pi, I, w, n, r, e:\ w.\mathit{name} \in I \land \operatorname{row}_{w.\mathit{name}}(\pi) = r \land r.\mathit{agent} = \bot \land r.\mathit{evidence} = \mathrm{some}(e) \Rightarrow \operatorname{boundTo}(\operatorname{foldl}(\operatorname{step}, \pi, \operatorname{cmds}(I, \mathrm{true}, w, n)), w.\mathit{name}) = \mathrm{some}(w.\mathit{name})$$
-/
theorem workflow_done_keeps (π : State) (ids : List String) (w : Wf) (n : Nat) (r : Task) (e : String)
    (hi : w.name ∈ ids) (hr : π.tasks.find? (·.id == w.name) = some r) (ha : r.agent = none)
    (he : r.evidence = some e) :
    boundTo ((w.cmds ids true n).foldl step π) w.name = some w.name := by
  have hc : ids.contains w.name = true := List.contains_iff_mem.2 hi
  simp only [Wf.cmds, hc, ↓reduceIte]
  exact key_done_keeps π _ _ n r e hr ha he

/-- A run whose name is not a task id gives no command.

$$\forall I, e, w, n:\quad w.\mathit{name} \notin I \Rightarrow \operatorname{cmds}(I, e, w, n) = [\,]$$
-/
theorem workflow_foreign_none (ids : List String) (ended : Bool) (w : Wf) (n : Nat)
    (h : w.name ∉ ids) : w.cmds ids ended n = [] := by
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

/-- Spawns and stops of one key `n` leave every other key as it was: seen and live alike.

$$\forall \pi, n, k, xs, ys:\ (\forall (b, m) \in xs \mathbin{+\!\!+} ys:\ b = n) \land k \ne n \Rightarrow \operatorname{openedK}(\pi', k) = \operatorname{openedK}(\pi, k) \land \operatorname{liveK}(\pi', k) = \operatorname{liveK}(\pi, k), \qquad \pi' = \pi[\mathit{spawns} := \pi.\mathit{spawns} \mathbin{+\!\!+} xs,\ \mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} ys]$$
-/
theorem key_other (π : State) (n k : String) (xs ys : List (String × Nat))
    (hx : ∀ x ∈ xs, x.1 = n) (hy : ∀ y ∈ ys, y.1 = n) (hk : k ≠ n) :
    openedK { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } k = openedK π k ∧
      liveK { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } k = liveK π k := by
  have hsg : sights { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } = sights π ++ xs := by
    simp [sights]
  have h0 : xs.any (·.1 == k) = false :=
    List.any_eq_false.mpr fun p hp => by simp [hx p hp, Ne.symm hk]
  have ho : openedK { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } k = openedK π k := by
    simp only [openedK, hsg, List.any_append, h0, Bool.or_false]
  refine ⟨ho, ?_⟩
  have hxa : ∀ m : Nat, xs.all (fun p => p.1 != k || decide (p.2 ≤ m)) = true := fun m =>
    List.all_eq_true.mpr fun p hp => by simp [hx p hp, Ne.symm hk]
  have hya : (ys.any fun q => q.1 == k &&
      (sights π ++ xs).all fun p => p.1 != k || decide (p.2 ≤ q.2)) = false :=
    List.any_eq_false.mpr fun q hq => by simp [hy q hq, Ne.symm hk]
  have hE : endedK { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } k = endedK π k := by
    simp only [endedK, hsg, List.any_append, hya, Bool.or_false]
    simp only [List.all_append, hxa, Bool.and_true]
  simp only [liveK, ho, hE]

/-- Spawns and stops of one key `n` (at any times) change the binding of no row whose id is not `n`
and whose stored agent is not `n`, when `n` is no labelled key (no label pairs the id `n` with a name): a workflow
that is no task id binds nothing.

$$\forall \pi, t, n, xs, ys:\ t.\mathit{id} \ne n \land t.\mathit{agent} \ne \mathrm{some}(n) \land (\forall (b, m) \in xs \mathbin{+\!\!+} ys:\ b = n) \land (\forall (k, b) \in \pi.\mathit{labels}:\ k \ne n) \Rightarrow \operatorname{agentOf}(\pi[\mathit{spawns} := \pi.\mathit{spawns} \mathbin{+\!\!+} xs,\ \mathit{stops} := \pi.\mathit{stops} \mathbin{+\!\!+} ys], t) = \operatorname{agentOf}(\pi, t)$$
-/
theorem workflow_foreign_agentOf (π : State) (t : Task) (n : String) (xs ys : List (String × Nat))
    (hx : ∀ x ∈ xs, x.1 = n) (hy : ∀ y ∈ ys, y.1 = n) (hid : t.id ≠ n) (hag : t.agent ≠ some n)
    (hl : ∀ p ∈ π.labels, p.1 ≠ n) :
    agentOf { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } t = agentOf π t := by
  have hkeys : ∀ a, a ≠ n → ∀ k ∈ keysOf π a, k ≠ n := by
    intro a ha k hk
    simp only [keysOf, List.mem_cons, List.mem_map, List.mem_filter] at hk
    rcases hk with rfl | ⟨p, ⟨hp, _⟩, rfl⟩
    · exact ha
    · exact hl p hp
  have hk' : ∀ a, keysOf { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } a = keysOf π a :=
    fun _ => rfl
  have hend : ∀ a, a ≠ n →
      ended { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } a = ended π a := by
    intro a ha
    simp only [ended, hk']
    rw [any_congr_mem fun k hk => (key_other π n k xs ys hx hy (hkeys a ha k hk)).2]
  have hop : ∀ a, a ≠ n →
      opened { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } a = opened π a := by
    intro a ha
    simp only [opened, hk']
    rw [any_congr_mem fun k hk => (key_other π n k xs ys hx hy (hkeys a ha k hk)).1]
  have hc : cands { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } t = cands π t := by
    have hfl : t.agent.toList.filter (opened { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys })
        = t.agent.toList.filter (opened π) :=
      List.filter_congr fun a ha => hop a fun e => hag (by simp_all)
    simp only [cands, hfl, hop t.id hid]
  have hmem : ∀ a ∈ cands π t, a ≠ n := by
    intro a ha
    simp only [cands, List.mem_append, List.mem_filter, Option.mem_toList, List.mem_ite_nil_right,
      List.mem_singleton] at ha
    rcases ha with ⟨h, _⟩ | ⟨_, h⟩
    · intro e; exact hag (by rw [h, e])
    · intro e; exact hid (by rw [← h, e])
  have hf : (cands π t).find? (fun a => !ended { π with spawns := π.spawns ++ xs, stops := π.stops ++ ys } a)
      = (cands π t).find? (fun a => !ended π a) := by
    exact find_congr _ _ _ (fun a ha => by rw [hend a (hmem a ha)])
  unfold agentOf
  rw [hc, hf]


/-- A run of a name that is no task id leaves every binding alone.

$$\forall es, I, e, w, n, x:\ w.\mathit{name} \notin I \Rightarrow \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} \operatorname{cmds}(I, e, w, n)), x) = \operatorname{boundTo}(\operatorname{run}(es), x)$$
-/
theorem workflow_foreign_bound (es : List Cmd) (ids : List String) (ended : Bool) (w : Wf) (n : Nat) (x : String)
    (h : w.name ∉ ids) : boundTo (run (es ++ w.cmds ids ended n)) x = boundTo (run es) x := by
  rw [workflow_foreign_none ids ended w n h]
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

/-- A define and a label commute.

$$\forall \pi, d, k, a:\quad \operatorname{step}(\operatorname{step}(\pi, \mathrm{define}(d)), \mathrm{label}(k, a)) = \operatorname{step}(\operatorname{step}(\pi, \mathrm{label}(k, a)), \mathrm{define}(d))$$
-/
theorem step_define_label (π : State) (d : Def) (k a : String) :
    step (step π (.define d)) (.label k a) = step (step π (.label k a)) (.define d) := by
  have hc : check { π with labels := π.labels ++ [(k, a)] } (.define d) = check π (.define d) := rfl
  rw [step_label, step_label]
  unfold step
  rw [hc]
  by_cases h : check π (.define d) = none
  · simp only [h, ↓reduceIte]; rfl
  · simp only [h, ↓reduceIte]

/-- A spawn, stop or label command (the commands a workflow gives).

$$\operatorname{isWf}(c) = \mathrm{true} \iff \exists a, n, b:\ c = \mathrm{spawn}(a, n) \lor c = \mathrm{stop}(a, n) \lor c = \mathrm{label}(a, b)$$
-/
def Cmd.isWf : Cmd → Bool
  | .spawn .. | .stop .. | .label .. => true
  | _ => false

/-- A define commutes with spawn, stop and label commands: the same plan state in either order,
after any prefix.

$$\forall d, cs, es:\quad (\forall c \in cs:\ \operatorname{isWf}(c) = \mathrm{true}) \Rightarrow \operatorname{run}(es \mathbin{+\!\!+} \mathrm{define}(d) :: cs) = \operatorname{run}(es \mathbin{+\!\!+} cs \mathbin{+\!\!+} [\mathrm{define}(d)])$$
-/
theorem define_wf_comm (d : Def) :
    ∀ (cs es : List Cmd), (∀ c ∈ cs, c.isWf = true) →
      run (es ++ .define d :: cs) = run (es ++ cs ++ [.define d])
  | [], es, _ => by simp
  | c :: cs, es, h => by
    have hc := h c (List.mem_cons_self ..)
    have h1 : run (es ++ [.define d, c]) = run (es ++ [c, .define d]) := by
      cases c with
      | spawn _ _ => exact run_comm es rfl rfl
      | stop _ _ => exact run_comm es rfl rfl
      | label k a =>
        simp only [run_append, List.foldl_cons, List.foldl_nil]
        exact step_define_label _ d k a
      | _ => simp [Cmd.isWf] at hc
    have ih := define_wf_comm d cs (es ++ [c]) (fun x hx => h x (List.mem_cons_of_mem _ hx))
    calc run (es ++ .define d :: c :: cs) = run (es ++ [.define d, c] ++ cs) := by simp
      _ = cs.foldl step (run (es ++ [.define d, c])) := run_append _ _
      _ = cs.foldl step (run (es ++ [c, .define d])) := by rw [h1]
      _ = run (es ++ [c, .define d] ++ cs) := (run_append _ _).symm
      _ = run ((es ++ [c]) ++ .define d :: cs) := by simp
      _ = run ((es ++ [c]) ++ cs ++ [.define d]) := ih
      _ = run (es ++ c :: cs ++ [.define d]) := by simp

/-- The commands of any run are spawns, stops and labels.

$$\forall I, e, w, n, c:\quad c \in \operatorname{cmds}(I, e, w, n) \Rightarrow \operatorname{isWf}(c) = \mathrm{true}$$
-/
theorem Wf.cmds_wf (ids : List String) (ended : Bool) (w : Wf) (n : Nat) :
    ∀ c ∈ w.cmds ids ended n, c.isWf = true := by
  intro c hc
  unfold Wf.cmds at hc
  split at hc
  · cases ended <;> simp at hc <;> rcases hc with rfl | rfl | rfl <;> rfl
  · simp at hc

/-- Every stop a run gives is a stop of its run key.

$$\forall I, e, w, n, k, m:\quad \mathrm{stop}(k, m) \in \operatorname{cmds}(I, e, w, n) \Rightarrow k = \operatorname{runKey}(w.\mathit{run})$$
-/
theorem Wf.cmds_stop (ids : List String) (ended : Bool) (w : Wf) (n : Nat) (k : String) (m : Nat)
    (h : Cmd.stop k m ∈ w.cmds ids ended n) : k = runKey w.run := by
  unfold Wf.cmds at h
  split at h
  · cases ended <;> simp at h
    exact h.1
  · simp at h

/-- **The claim-order race stays gone for workflows**: defining task `x` and running a workflow bind the same
agent in either order, after any log prefix.

$$\forall es, d, I, e, w, n, x:\quad \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} \mathrm{define}(d) :: \operatorname{cmds}(I, e, w, n)), x) = \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} \operatorname{cmds}(I, e, w, n) \mathbin{+\!\!+} [\mathrm{define}(d)]), x)$$
-/
theorem define_workflow_comm (es : List Cmd) (d : Def) (ids : List String) (ended : Bool) (w : Wf)
    (n : Nat) (x : String) :
    boundTo (run (es ++ .define d :: w.cmds ids ended n)) x =
      boundTo (run (es ++ w.cmds ids ended n ++ [.define d])) x := by
  rw [define_wf_comm d _ es (Wf.cmds_wf ids ended w n)]

/-- The runs of a list of script file names, each (run id, name) pair once.

$$\operatorname{runs}(fs) = \operatorname{dedup}([\, (r, n) : f \in fs,\ \operatorname{scriptRun}(f) = (n, r) \,])$$
-/
def runsOf (scripts : List String) : List Wf :=
  (scripts.filterMap fun f => (scriptRun f).map fun (n, r) => ({ run := r, name := n } : Wf)).eraseDups

/-- The event key of a workflow command, from a prefix $p$ and a suffix $s$: a label gets
$p$`-label:`$s$, a stop $p$`-end:`$s$, any other command $p$`:`$s$.

$$\operatorname{evKey}(p, s, c) = \begin{cases} p \mathbin{+\!\!+} \texttt{-label:} \mathbin{+\!\!+} s & c = \mathrm{label}(\cdot, \cdot) \\ p \mathbin{+\!\!+} \texttt{-end:} \mathbin{+\!\!+} s & c = \mathrm{stop}(\cdot, \cdot) \\ p \mathbin{+\!\!+} \texttt{:} \mathbin{+\!\!+} s & \text{otherwise} \end{cases}$$

One distinct key per command kind, so the event store never drops one as a duplicate of another.
-/
def evKey (p s : String) : Cmd → String
  | .label .. => p ++ "-label:" ++ s
  | .stop .. => p ++ "-end:" ++ s
  | _ => p ++ ":" ++ s

/-- The events (event key, command) of the workflow runs seen in the session's `workflows/` dir,
given the task ids, the script file names and the run file names: a run's script gives the label and
spawn of its run key (event keys `wfr-label:<runId>`, `wfr:<runId>`), its run file also the stop
(`wfr-end:<runId>`); only runs named like a task.

$$\operatorname{events}(I, S, R) = \mathop{\mathrm{concat}}_{w \in \operatorname{runs}(S)} [\, (\operatorname{evKey}(\texttt{wfr}, w.\mathit{run}, c), c) : c \in \operatorname{cmds}(I, w.\mathit{run} \in \operatorname{ids}(R), w, 0) \,]$$

($\operatorname{ids}(R)$: the run ids of the run file names $R$.)
-/
def wfEvents (ids scripts runFiles : List String) : List (String × Cmd) :=
  let ended := runFiles.filterMap runFileId
  (runsOf scripts).flatMap fun w =>
    (w.cmds ids (ended.contains w.run) 0).map fun c => (evKey "wfr" w.run c, c)

/-- No script named like a task, no event: a workflow that is no task id emits nothing.

$$\forall I, S, R:\ (\forall w \in \operatorname{runs}(S):\ w.\mathit{name} \notin I) \Rightarrow \operatorname{events}(I, S, R) = [\,]$$
-/
theorem wfEvents_foreign (ids scripts runFiles : List String)
    (h : ∀ w ∈ runsOf scripts, w.name ∉ ids) : wfEvents ids scripts runFiles = [] := by
  unfold wfEvents
  rw [List.flatMap_eq_nil_iff]
  intro w hw
  rw [workflow_foreign_none ids _ w _ (h w hw)]
  rfl


/-! ### Labelled workflow agents (task `workflow-multi-claim`)

A run that works several tasks (`integrate-and-engine-fix`, `guard-hardening-r2`) names its agents
`<phase>:<task>`. **Signal (CONFIRMED, session dir):** `<session>/subagents/workflows/<runId>/journal.jsonl` has a
`{"type":"started","agentId":…,"label":…}` line when an agent starts and a `{"type":"result","agentId":…}` line when it
ends; the glue reads only those fields, never a result text, script or transcript. A label's task is the text
after its first `:`; the agent binds that task while it runs, as `meta.name` does for the whole run. -/

/-- The task named by a label `<phase>:<task>`: the non-empty text after the first `:`.

$$\operatorname{labelTask}(\ell) = \begin{cases} \mathrm{some}(t) & \ell = p \mathbin{+\!\!+} \texttt{:} \mathbin{+\!\!+} t \land \texttt{:} \notin p \land t \ne \varepsilon \\ \mathrm{none} & \text{otherwise}\end{cases}$$
-/
def labelTask (l : String) : Option String :=
  let r := l.dropWhile (· != ':')
  if r.isEmpty then none else
    let t := (r.drop 1).toString
    if t.isEmpty then none else some t

/-- A journal line: the run (its directory name), the agent id, whether it is a `started` line (else a `result`
line) and the label of a `started` line.

$$j = (\mathit{run}, \mathit{id}, \mathit{started}, \mathit{label})$$
-/
structure JLine where
  run     : String
  id      : String
  started : Bool
  label   : String
deriving Repr, DecidableEq

/-- A workflow agent: run, agent id, label, and whether its `result` line exists.

$$a = (\mathit{run}, \mathit{id}, \ell, \mathit{done})$$
-/
structure WfAgent where
  run   : String
  id    : String
  label : String
  done  : Bool
deriving Repr, DecidableEq

/-- The agents of a journal: one per `started` line of a valid run id (duplicates once), done iff a `result` line
of the same run and agent id exists.

$$\operatorname{agents}(J) = \operatorname{dedup}\{(r, i, \ell, \exists k \in J:\ \lnot k.\mathit{started} \land k.\mathit{run} = r \land k.\mathit{id} = i) : (r, i, \ell) \in J_{\mathit{started}},\ \operatorname{isRunId}(r)\}$$
-/
def wfAgents (js : List JLine) : List WfAgent :=
  ((js.filter fun j => j.started && isRunId j.run).map fun j =>
    ({ run := j.run, id := j.id, label := j.label,
       done := js.any fun k => !k.started && k.run == j.run && k.id == j.id } : WfAgent)).eraseDups

/-- The commands of a labelled agent, given the task ids and whether its run ended: a label naming a
task id labels the agent id with that task and spawns the agent id, and stops the agent id once the
agent or its run ended; any other label gives none.

$$\operatorname{acmds}(I, e, a, n) = \begin{cases} [\mathrm{label}(a.\mathit{id}, t), \mathrm{spawn}(a.\mathit{id}, n), \mathrm{stop}(a.\mathit{id}, n)] & \operatorname{labelTask}(a.\ell) = \mathrm{some}(t) \land t \in I \land (a.\mathit{done} \lor e) \\ [\mathrm{label}(a.\mathit{id}, t), \mathrm{spawn}(a.\mathit{id}, n)] & \operatorname{labelTask}(a.\ell) = \mathrm{some}(t) \land t \in I \land \lnot(a.\mathit{done} \lor e) \\ [\,] & \text{otherwise}\end{cases}$$
-/
def WfAgent.cmds (ids : List String) (runEnded : Bool) (a : WfAgent) (n : Nat) : List Cmd :=
  match labelTask a.label with
  | some t =>
    if ids.contains t then
      .label a.id t :: .spawn a.id n :: (if a.done || runEnded then [.stop a.id n] else [])
    else []
  | none => []

/-- The events of the labelled agents (event keys `wfid-label:<run>:<id>`, `wfid:<run>:<id>` and
`wfid-end:<run>:<id>`).

$$\operatorname{aevents}(I, R, J) = \mathop{\mathrm{concat}}_{a \in \operatorname{agents}(J)} [\, (\operatorname{evKey}(\texttt{wfid}, a.\mathit{run} \mathbin{+\!\!+} \texttt{:} \mathbin{+\!\!+} a.\mathit{id}, c), c) : c \in \operatorname{acmds}(I, a.\mathit{run} \in \operatorname{ids}(R), a, 0) \,]$$
-/
def agentEvents (ids runFiles : List String) (journal : List JLine) : List (String × Cmd) :=
  let ended := runFiles.filterMap runFileId
  (wfAgents journal).flatMap fun a =>
    (a.cmds ids (ended.contains a.run) 0).map fun c => (evKey "wfid" (a.run ++ ":" ++ a.id) c, c)

/-- All workflow events: those of the runs named like a task, then those of the labelled agents.

$$\operatorname{all}(I, S, R, J) = \operatorname{events}(I, S, R) \mathbin{+\!\!+} \operatorname{aevents}(I, R, J)$$
-/
def wfAllEvents (ids scripts runFiles : List String) (journal : List JLine) : List (String × Cmd) :=
  wfEvents ids scripts runFiles ++ agentEvents ids runFiles journal

/-- **The run-only behaviour is kept**: with no journal lines the events are exactly the run events.

$$\forall I, S, R:\quad \operatorname{all}(I, S, R, [\,]) = \operatorname{events}(I, S, R)$$
-/
theorem wfAllEvents_nil (ids scripts runFiles : List String) :
    wfAllEvents ids scripts runFiles [] = wfEvents ids scripts runFiles := by
  simp [wfAllEvents, agentEvents, wfAgents]

/-- A running agent labelled with a task id labels and spawns its id (no stop).

$$\forall I, a, t, n:\quad \operatorname{labelTask}(a.\ell) = \mathrm{some}(t) \land t \in I \land a.\mathit{done} = \mathrm{false} \Rightarrow \operatorname{acmds}(I, \mathrm{false}, a, n) = [\mathrm{label}(a.\mathit{id}, t), \mathrm{spawn}(a.\mathit{id}, n)]$$
-/
theorem WfAgent.cmds_running (ids : List String) (a : WfAgent) (t : String) (n : Nat)
    (hl : labelTask a.label = some t) (ht : ids.contains t = true) (hd : a.done = false) :
    a.cmds ids false n = [.label a.id t, .spawn a.id n] := by
  have := List.contains_iff_mem.1 ht
  simp [WfAgent.cmds, hl, hd, this]

/-- An ended agent (or one of an ended run) labels, spawns and stops its id: its own key ends with
it.

$$\forall I, e, a, t, n:\quad \operatorname{labelTask}(a.\ell) = \mathrm{some}(t) \land t \in I \land (a.\mathit{done} \lor e) \Rightarrow \operatorname{acmds}(I, e, a, n) = [\mathrm{label}(a.\mathit{id}, t), \mathrm{spawn}(a.\mathit{id}, n), \mathrm{stop}(a.\mathit{id}, n)]$$
-/
theorem WfAgent.cmds_ended (ids : List String) (e : Bool) (a : WfAgent) (t : String) (n : Nat)
    (hl : labelTask a.label = some t) (ht : ids.contains t = true) (hd : (a.done || e) = true) :
    a.cmds ids e n = [.label a.id t, .spawn a.id n, .stop a.id n] := by
  have := List.contains_iff_mem.1 ht
  simp [WfAgent.cmds, hl, hd, this]

/-- The commands of an agent are spawns, stops and labels.

$$\forall I, e, a, n, c:\quad c \in \operatorname{acmds}(I, e, a, n) \Rightarrow \operatorname{isWf}(c) = \mathrm{true}$$
-/
theorem WfAgent.cmds_wf (ids : List String) (e : Bool) (a : WfAgent) (n : Nat) :
    ∀ c ∈ a.cmds ids e n, c.isWf = true := by
  intro c hc
  unfold WfAgent.cmds at hc
  split at hc
  · split at hc
    · cases hde : (a.done || e) <;> simp [hde] at hc <;> rcases hc with rfl | rfl | rfl <;> rfl
    · simp at hc
  · simp at hc

/-- Every stop an agent gives is a stop of its own id.

$$\forall I, e, a, n, k, m:\quad \mathrm{stop}(k, m) \in \operatorname{acmds}(I, e, a, n) \Rightarrow k = a.\mathit{id}$$
-/
theorem WfAgent.cmds_stop (ids : List String) (e : Bool) (a : WfAgent) (n : Nat) (k : String) (m : Nat)
    (h : Cmd.stop k m ∈ a.cmds ids e n) : k = a.id := by
  unfold WfAgent.cmds at h
  split at h
  · split at h
    · cases hde : (a.done || e) <;> simp [hde] at h
      exact h.1
    · simp at h
  · simp at h

/-- **A define commutes with the commands of a labelled agent**, as with a run's.

$$\forall es, d, I, e, a, n, x:\quad \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} \mathrm{define}(d) :: \operatorname{acmds}(I, e, a, n)), x) = \operatorname{boundTo}(\operatorname{run}(es \mathbin{+\!\!+} \operatorname{acmds}(I, e, a, n) \mathbin{+\!\!+} [\mathrm{define}(d)]), x)$$
-/
theorem define_agent_comm (es : List Cmd) (d : Def) (ids : List String) (e : Bool) (a : WfAgent)
    (n : Nat) (x : String) :
    boundTo (run (es ++ .define d :: a.cmds ids e n)) x =
      boundTo (run (es ++ a.cmds ids e n ++ [.define d])) x := by
  rw [define_wf_comm d _ es (WfAgent.cmds_wf ids e a n)]

/-- **Concurrent agents of one task** (`workflow_concurrent`): a running agent $b$ labelled with task
$t$, spawned at $n$ later than every stop of its id, keeps $t$ not ended through any later commands
with no stop of $b$'s id, such as the commands of every other agent (`WfAgent.cmds_stop`) and of
every run (`Wf.cmds_stop`), the stop of another agent of $t$ included.

$$\forall \pi, I, b, t, n, cs:\ \operatorname{labelTask}(b.\ell) = \mathrm{some}(t) \land t \in I \land b.\mathit{done} = \mathrm{false} \land (\forall (k, m) \in \pi.\mathit{stops}:\ k = b.\mathit{id} \Rightarrow m < n) \land (\forall c \in cs, m:\ c \ne \mathrm{stop}(b.\mathit{id}, m)) \Rightarrow \operatorname{ended}(\operatorname{foldl}(\operatorname{step}, \pi, \operatorname{acmds}(I, \mathrm{false}, b, n) \mathbin{+\!\!+} cs), t) = \mathrm{false}$$

A task stays running while one of its agents runs, whatever its other agents do.
-/
theorem workflow_concurrent (π : State) (ids : List String) (b : WfAgent) (t : String) (n : Nat)
    (cs : List Cmd) (hl : labelTask b.label = some t) (ht : t ∈ ids) (hd : b.done = false)
    (hs : ∀ q ∈ π.stops, q.1 = b.id → q.2 < n) (hcs : ∀ c ∈ cs, ∀ m, c ≠ .stop b.id m) :
    ended ((b.cmds ids false n ++ cs).foldl step π) t = false := by
  rw [WfAgent.cmds_running ids b t n hl (List.contains_iff_mem.2 ht) hd]
  exact key_keeps π b.id t n cs hs hcs

/-- **Identity only** (`wfAllEvents_identity`): every workflow event is a label, spawn or stop of a
run key `wf:<runId>` of a run in `scripts` named like a task, labelled with that name, or of the agent
id of a journal agent whose label names a task, labelled with that task; never of a task name.

$$\forall (\epsilon, c) \in \operatorname{all}(I, S, R, J):\ \big(\exists w \in \operatorname{runs}(S):\ w.\mathit{name} \in I \land c \in \{\mathrm{label}(\kappa_w, w.\mathit{name}), \mathrm{spawn}(\kappa_w, 0), \mathrm{stop}(\kappa_w, 0)\}\big) \lor \big(\exists a \in \operatorname{agents}(J), t:\ \operatorname{labelTask}(a.\ell) = \mathrm{some}(t) \land t \in I \land c \in \{\mathrm{label}(a.\mathit{id}, t), \mathrm{spawn}(a.\mathit{id}, 0), \mathrm{stop}(a.\mathit{id}, 0)\}\big)$$

($\kappa_w = \operatorname{runKey}(w.\mathit{run})$.) A task name only ever appears as a label.
-/
theorem wfAllEvents_identity (ids scripts runFiles : List String) (journal : List JLine)
    (ev : String) (c : Cmd) (he : (ev, c) ∈ wfAllEvents ids scripts runFiles journal) :
    (∃ w ∈ runsOf scripts, w.name ∈ ids ∧ (c = .label (runKey w.run) w.name ∨
        c = .spawn (runKey w.run) 0 ∨ c = .stop (runKey w.run) 0)) ∨
      ∃ a ∈ wfAgents journal, ∃ t, labelTask a.label = some t ∧ t ∈ ids ∧
        (c = .label a.id t ∨ c = .spawn a.id 0 ∨ c = .stop a.id 0) := by
  unfold wfAllEvents at he
  rcases List.mem_append.1 he with h | h
  · left
    unfold wfEvents at h
    obtain ⟨w, hw, h⟩ := List.mem_flatMap.1 h
    obtain ⟨c', hc, hce⟩ := List.mem_map.1 h
    simp only [Prod.mk.injEq] at hce
    obtain ⟨-, rfl⟩ := hce
    unfold Wf.cmds at hc
    split at hc
    · rename_i hid
      refine ⟨w, hw, List.contains_iff_mem.1 hid, ?_⟩
      simp only [List.mem_cons] at hc
      rcases hc with h1 | h1 | h1
      · exact .inl h1
      · exact .inr (.inl h1)
      · split at h1 <;> simp_all
    · simp at hc
  · right
    unfold agentEvents at h
    obtain ⟨a, ha, h⟩ := List.mem_flatMap.1 h
    obtain ⟨c', hc, hce⟩ := List.mem_map.1 h
    simp only [Prod.mk.injEq] at hce
    obtain ⟨-, rfl⟩ := hce
    unfold WfAgent.cmds at hc
    split at hc
    · rename_i t hl
      split at hc
      · rename_i hid
        refine ⟨a, ha, t, hl, List.contains_iff_mem.1 hid, ?_⟩
        simp only [List.mem_cons] at hc
        rcases hc with h1 | h1 | h1
        · exact .inl h1
        · exact .inr (.inl h1)
        · split at h1 <;> simp_all
      · simp at hc
    · simp at hc

end Fw.Plan
