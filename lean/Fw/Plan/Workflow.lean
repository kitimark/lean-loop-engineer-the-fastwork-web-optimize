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
  (event keys `wfr-label:<runId>`, `wfr:<runId>`, `wfr-end:<runId>`). Each journal agent of a run
  labels its agent id with the run's name when that is a task id, whatever its label, and with its
  label's task when that is a task id; when it works on at least one task, it spawns its id and stops
  it at its `result` or `failed` line or at the run's end; an agent that works on no task gives no
  command (event keys `wfid-label:<runId>:<id>:<task>`, `wfid:`, `wfid-end:` +
  `<runId>:<id>`). A task name is never a life key, only a label, so the stop of one agent never ends
  a task another agent of the same task still works on (`concurrent_keep`, `workflow_concurrent`). A
  run whose name is not a task id gives no command for its run key.
* **Proved:** a run binds its task while seen within `q` (`workflow_binds`), its end ends a task
  nothing else keeps (`workflow_ends`); a run whose name is no task id binds nothing
  (`workflow_foreign_none`, `workflow_foreign_bound`), and spawns and stops of a key no label binds
  change no row (`unbound_key_fold`); every agent of a task-named run works on that task
  (`run_task_binds`); every event is keyed by a run key or an agent id (`wfAllEvents_identity`); a
  define commutes with the run's commands (`define_workflow_comm`), so the claim-order race stays
  gone.

Golden: `packages/contracts/golden/plan/workflow.jsonl` (`Fw.Wire.Plan.Golden`).
-/
namespace Fw.Plan

/-- A run id has the form `wf_` + 8 lowercase hex digits + `-` + 3 lowercase hex digits. -/
def isRunId (s : String) : Bool :=
  let cs := s.toList
  let hex (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'f')
  cs.length == 15 && cs.take 3 == ['w', 'f', '_'] && ((cs.drop 3).take 8).all hex
    && cs[11]? == some '-' && (cs.drop 12).all hex

/-- Name and run id of a script file name `<name>-<runId>.js` (the name is non-empty and may itself
contain `-`; the run id is the fixed-width tail).
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

/-- The run id of a run file name `<runId>.json`. -/
def runFileId (f : String) : Option String :=
  if f.endsWith ".json" then
    let r := (f.dropEnd 5).toString
    if isRunId r then some r else none
  else none

/-- A workflow run: its id (the evidence) and its `meta.name`. -/
structure Wf where
  run  : String
  name : String
deriving Repr, DecidableEq

/-- The life key of a run: `wf:` followed by the run id.

The run's own identity, never a task name.
-/
def runKey (r : String) : String := "wf:" ++ r

/-- The plan commands of a run at time `n`, given the task ids and whether the run has ended: a name
that is a task id labels the run key with the name and spawns the run key, and stops the run key
once the run ended; any other name gives none. (In the event wire the time is the event's stamp, so
`wfEvents` passes `0`.)
-/
def Wf.cmds (ids : List String) (ended : Bool) (w : Wf) (n : Nat) : List Cmd :=
  if ids.contains w.name then
    .label (runKey w.run) w.name :: .spawn (runKey w.run) n ::
      (if ended then [.stop (runKey w.run) n] else [])
  else []

/-- `run` of an appended list continues the fold. -/
theorem run_append (as bs : List Cmd) : run (as ++ bs) = bs.foldl step (run as) := by
  simp [run, List.foldl_append]

/-- A label step only appends the label. -/
theorem step_label (π : State) (k a : String) :
    step π (.label k a) = { π with labels := π.labels ++ [(k, a)] } := by
  simp [step, check, exec]

/-- Label steps only append their labels. -/
theorem labels_fold (k : String) : ∀ (ts : List String) (π : State),
    (ts.map (Cmd.label k ·)).foldl step π = { π with labels := π.labels ++ ts.map (k, ·) }
  | [], π => by simp
  | t :: ts, π => by
    simp only [List.map_cons, List.foldl_cons, step_label]
    rw [labels_fold k ts]
    simp

/-- **A labelled key binds its task while it is seen within `q`**: if the first row with id `t` has
no stored agent, `t` is among the labels `ts`, every stop of the key `k` is earlier than `n` and
`now ≤ n + q`, then after labelling `k` with every task of `ts` and spawning `k` at `n`
the board binds agent `t` to it at time `now`.

A fresh id or run key that works on a task makes the task running.
-/
theorem bind_labels (q now : Nat) (π : State) (k : String) (ts : List String) (t : String) (n : Nat)
    (r : Task) (ht : t ∈ ts) (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none)
    (hb : ∀ p ∈ π.stops, p.1 = k → p.2 < n) (hq : now ≤ n + q) :
    boundTo q now ((ts.map (Cmd.label k ·) ++ [Cmd.spawn k n]).foldl step π) t = some t := by
  have hid : r.id = t := by simpa using List.find?_some hr
  rw [List.foldl_append, labels_fold]
  generalize hπ1 : ({ π with labels := π.labels ++ ts.map (k, ·) } : State) = π1
  have hk : k ∈ keysOf π1 t := by
    rw [← hπ1]
    simp only [keysOf, List.mem_map, List.mem_filter, List.mem_append]
    exact ⟨(k, t), ⟨.inr ⟨t, ht, rfl⟩, by simp⟩, rfl⟩
  have hs : ∀ p ∈ π1.stops, p.1 = k → p.2 < n := by rw [← hπ1]; exact hb
  obtain ⟨hl, -⟩ := revive_on_event π1 (n := n) hk hs
  have hle : n ≤ lastAt (step π1 (.spawn k n)) k :=
    le_lastAt (by rw [step_spawn]; simp [sights])
  have hrun : runs q now (step π1 (.spawn k n)) t = true := by
    unfold runs
    refine List.any_eq_true.2 ⟨k, ?_, ?_⟩
    · rw [step_spawn]; exact hk
    · simp only [runK, hl, Bool.true_and, decide_eq_true_eq]; omega
  have hr' : (step π1 (.spawn k n)).tasks.find? (·.id == t) = some r := by
    rw [step_spawn, ← hπ1]; exact hr
  simp only [List.foldl_cons, List.foldl_nil, boundTo, hr', Option.bind_some, agentOf, names, ha,
    Option.toList_none, List.nil_append, hid, List.find?_cons, hrun]

/-- **A labelled key binds its name**: the case of one label.

A key seen at `n` keeps its task running until `n + q`.
-/
theorem bind_key (q now : Nat) (π : State) (k t : String) (n : Nat) (r : Task)
    (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none)
    (hb : ∀ p ∈ π.stops, p.1 = k → p.2 < n) (hq : now ≤ n + q) :
    boundTo q now (step (step π (.label k t)) (.spawn k n)) t = some t := by
  have := bind_labels q now π k [t] t n r List.mem_cons_self hr ha hb hq
  simpa using this

/-- More sightings and the same stops make no key less live. -/
theorem liveK_mono {π π' : State} {k : String} (hs : ∀ p ∈ sights π, p ∈ sights π')
    (hq : π'.stops = π.stops) (h : liveK π k = true) : liveK π' k = true := by
  simp only [liveK, openedK, endedK, Bool.and_eq_true, Bool.not_eq_true', List.any_eq_true,
    List.any_eq_false, List.all_eq_true, hq] at h ⊢
  obtain ⟨⟨p, hp, hpk⟩, h2⟩ := h
  exact ⟨⟨p, hs p hp, hpk⟩, fun q hq' hq2 => h2 q hq' ⟨hq2.1, fun p hp => hq2.2 p (hs p hp)⟩⟩

/-- No step removes a label. -/
theorem labels_step (π : State) (c : Cmd) : ∀ p ∈ π.labels, p ∈ (step π c).labels := by
  intro p hp
  unfold step
  split
  · cases c with
    | milestone m tt => simp only [exec]; split <;> exact hp
    | _ => simp [exec, hp]
  · exact hp

/-- No step removes a key of a name. -/
theorem keysOf_step (π : State) (c : Cmd) {k a : String} (hk : k ∈ keysOf π a) :
    k ∈ keysOf (step π c) a := by
  simp only [keysOf, List.mem_map, List.mem_filter] at hk ⊢
  obtain ⟨p, ⟨hp, hpa⟩, rfl⟩ := hk
  exact ⟨p, ⟨labels_step π c p hp, hpa⟩, rfl⟩

/-- **Only a stop of a key ends it**: a live key stays live under every command that is not a stop
of that key.
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
    · refine liveK_mono (fun p hp => ?_) ?_ h <;> simp_all [exec, sights]
    · exact h

/-- A run of commands with no stop of a live key of `a` keeps that key live and a key of `a`. -/
theorem live_fold {k a : String} : ∀ (cs : List Cmd) (π : State), (∀ c ∈ cs, ∀ m, c ≠ .stop k m) →
    k ∈ keysOf π a → liveK π k = true →
    k ∈ keysOf (cs.foldl step π) a ∧ liveK (cs.foldl step π) k = true
  | [], _, _, hk, hl => ⟨hk, hl⟩
  | c :: cs, π, h, hk, hl =>
    live_fold cs (step π c) (fun x hx => h x (List.mem_cons_of_mem _ hx)) (keysOf_step π c hk)
      (liveK_step π c k (h c List.mem_cons_self) hl)

/-- **The stop of one key never ends a name another live key carries** (`concurrent_keep`): for keys
`k ≠ k_2` where `k_2` is labelled with `a` and live, a stop of `k` (another id or run of the same
task included) leaves `k_2` as live as it was, so `a` has not ended.

When two agents work on one task and one stops, the task does not end.
-/
theorem concurrent_keep (π : State) {k k₂ a : String} (m : Nat) (hne : k ≠ k₂)
    (hl : (k₂, a) ∈ π.labels) (hlive : liveK π k₂ = true) :
    liveK (step π (.stop k m)) k₂ = liveK π k₂ ∧ ended (step π (.stop k m)) a = false := by
  have h1 : liveK (step π (.stop k m)) k₂ = liveK π k₂ := by
    rw [step_stop]; exact (liveK_stop π k m k₂).2 (Ne.symm hne)
  refine ⟨h1, ?_⟩
  have hk : k₂ ∈ keysOf (step π (.stop k m)) a := by
    rw [step_stop]
    exact List.mem_map.2 ⟨(k₂, a), List.mem_filter.2 ⟨hl, by simp⟩, rfl⟩
  simp only [ended, Bool.not_eq_false', List.any_eq_true]
  exact ⟨k₂, hk, h1 ▸ hlive⟩

/-- **A key that labels and spawns keeps its tasks unended until its own stop**: after labelling
`k` with every task of `ts` and `spawn(k, n)`, with `n` later than every stop of `k`, any
commands without a stop of `k` leave every `t ∈ ts` not ended (a bound key stays live, so the row has an agent or a quiet time and k never parks it).
-/
theorem key_keeps (π : State) (k : String) (ts : List String) (t : String) (n : Nat) (cs : List Cmd)
    (ht : t ∈ ts) (hb : ∀ p ∈ π.stops, p.1 = k → p.2 < n) (hcs : ∀ c ∈ cs, ∀ m, c ≠ .stop k m) :
    ended ((ts.map (Cmd.label k ·) ++ Cmd.spawn k n :: cs).foldl step π) t = false := by
  rw [List.foldl_append, labels_fold]
  generalize hπ1 : ({ π with labels := π.labels ++ ts.map (k, ·) } : State) = π1
  have hk : k ∈ keysOf π1 t := by
    rw [← hπ1]
    simp only [keysOf, List.mem_map, List.mem_filter, List.mem_append]
    exact ⟨(k, t), ⟨.inr ⟨t, ht, rfl⟩, by simp⟩, rfl⟩
  have hs : ∀ p ∈ π1.stops, p.1 = k → p.2 < n := by rw [← hπ1]; exact hb
  obtain ⟨hl, -⟩ := revive_on_event π1 (n := n) hk hs
  obtain ⟨hk3, hl3⟩ := live_fold cs _ hcs (keysOf_step π1 (.spawn k n) hk) hl
  simp only [List.foldl_cons]
  simp only [ended, Bool.not_eq_false', List.any_eq_true]
  exact ⟨k, hk3, hl3⟩

/-- **The stop of a key unbinds a task nothing else keeps, at every time**: after
`label(k, t)`, `spawn(k, n)` and `stop(k, n)`, where `n` is no earlier than
every sighting of `k` so far and `t` had ended before, the first row with id `t` (no stored agent)
is unbound at every quiet limit `q` and time `now`.
-/
theorem key_ends (q now : Nat) (π : State) (k t : String) (n : Nat) (r : Task)
    (hr : π.tasks.find? (·.id == t) = some r) (ha : r.agent = none)
    (hend : ended π t = true) (hb : lastAt π k ≤ n) :
    ended ([Cmd.label k t, .spawn k n, .stop k n].foldl step π) t = true ∧
      boundTo q now ([Cmd.label k t, .spawn k n, .stop k n].foldl step π) t = none := by
  have hid : r.id = t := by simpa using List.find?_some hr
  simp only [List.foldl_cons, List.foldl_nil, step_label]
  generalize hπ1 : ({ π with labels := π.labels ++ [(k, t)] } : State) = π1
  have hle : lastAt (step π1 (.spawn k n)) k ≤ n :=
    lastAt_le fun p hp hpk => by
      rw [step_spawn, ← hπ1] at hp
      simp only [sights, List.mem_append, List.mem_singleton] at hp
      rcases hp with hp | hp
      · have := le_lastAt (π := π) (k := k) (n := p.2) (by rw [← hpk]; exact hp)
        omega
      · simp [hp]
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
        simp only [keysOf, List.filter_append, List.map_append, List.mem_append,
          List.mem_map, List.mem_filter] at hj ⊢
        rcases hj with h | ⟨p, ⟨hp, -⟩, rfl⟩
        · exact h
        · simp only [List.mem_cons, List.not_mem_nil, or_false] at hp
          exact absurd (by rw [hp]) hjk
      have h1 : liveK π3 j = liveK π1 j := by
        rw [← hπ3, step_spawn, step_stop, (liveK_stop _ k n j).2 hjk, (liveK_spawn _ k n j).2 hjk]
      have h3 : liveK π1 j = liveK π j := by rw [← hπ1]; rfl
      rw [h1, h3]
      exact hold j hj'
  have hr3 : π3.tasks.find? (·.id == t) = some r := by
    rw [← hπ3, step_spawn, step_stop, ← hπ1]; exact hr
  refine ⟨hend3, ?_⟩
  have hdead : ∀ j ∈ tkeys π3 r, liveK π3 j = false := by
    simp only [tkeys, names, ha, Option.toList_none, List.nil_append, List.flatMap_cons,
      List.flatMap_nil, List.append_nil, hid]
    simpa [ended] using hend3
  simp only [boundTo, hr3, Option.bind_some]
  exact agentOf_none_of_dead hdead

/-- **A running workflow named `t` binds `t` while seen within `q`**: for a run `w` whose name is a
task id, if the first row with that id has no stored agent, every stop of the run key is earlier
than `n` and `now ≤ n + q`, the commands of the running run bind it at `now`.
-/
theorem workflow_binds (q now : Nat) (π : State) (ids : List String) (w : Wf) (n : Nat) (r : Task)
    (hi : w.name ∈ ids) (hr : π.tasks.find? (·.id == w.name) = some r) (ha : r.agent = none)
    (hb : ∀ p ∈ π.stops, p.1 = runKey w.run → p.2 < n) (hq : now ≤ n + q) :
    boundTo q now ((w.cmds ids false n).foldl step π) w.name = some w.name := by
  have hc : ids.contains w.name = true := List.contains_iff_mem.2 hi
  simp only [Wf.cmds, hc, ↓reduceIte, Bool.false_eq_true, List.foldl_cons, List.foldl_nil]
  exact bind_key q now π _ _ n r hr ha hb hq

/-- **The end of a workflow ends a task nothing else keeps**: for a run `w` whose name is a task id
that had ended before, with `n` no earlier than every sighting of the run key, the commands of the
ended run leave the name ended and the first row with that id (no stored agent) unbound, at every
`q` and `now`.
-/
theorem workflow_ends (q now : Nat) (π : State) (ids : List String) (w : Wf) (n : Nat) (r : Task)
    (hi : w.name ∈ ids) (hr : π.tasks.find? (·.id == w.name) = some r) (ha : r.agent = none)
    (hend : ended π w.name = true) (hb : lastAt π (runKey w.run) ≤ n) :
    ended ((w.cmds ids true n).foldl step π) w.name = true ∧
      boundTo q now ((w.cmds ids true n).foldl step π) w.name = none := by
  have hc : ids.contains w.name = true := List.contains_iff_mem.2 hi
  simp only [Wf.cmds, hc, ↓reduceIte]
  exact key_ends q now π _ _ n r hr ha hend hb

/-- A run whose name is not a task id gives no command. -/
theorem workflow_foreign_none (ids : List String) (ended : Bool) (w : Wf) (n : Nat)
    (h : w.name ∉ ids) : w.cmds ids ended n = [] := by
  simp [Wf.cmds, h]

/-- **Spawns and stops of a key bound to no row change nothing on it**: commands that are each a
spawn or a stop of the key `k` (at any times), where `k` is not a bound key of row `t`, leave its
board form unchanged at every `q` and `now`. A run whose key no label binds to a task binds
nothing.
-/
theorem unbound_key_fold (q now : Nat) (t : Task) {k : String} : ∀ (cs : List Cmd) (π : State),
    (∀ c ∈ cs, ∃ n, c = .spawn k n ∨ c = .stop k n) → k ∉ tkeys π t →
    bindRow q now (cs.foldl step π) t = bindRow q now π t
  | [], _, _, _ => rfl
  | c :: cs, π, h, hk => by
    have h' : ∀ x ∈ cs, ∃ n, x = .spawn k n ∨ x = .stop k n := fun x hx =>
      h x (List.mem_cons_of_mem _ hx)
    obtain ⟨n, rfl | rfl⟩ := h c List.mem_cons_self
    · have ht : tkeys (step π (.spawn k n)) t = tkeys π t := by rw [step_spawn]; rfl
      simp only [List.foldl_cons]
      rw [unbound_key_fold q now t cs _ h' (ht ▸ hk)]
      exact (names_never_sight q now π t n hk).1
    · have ht : tkeys (step π (.stop k n)) t = tkeys π t := by rw [step_stop]; rfl
      simp only [List.foldl_cons]
      rw [unbound_key_fold q now t cs _ h' (ht ▸ hk)]
      exact (names_never_sight q now π t n hk).2

/-- A run of a name that is no task id leaves every binding alone. -/
theorem workflow_foreign_bound (q now : Nat) (es : List Cmd) (ids : List String) (ended : Bool)
    (w : Wf) (n : Nat) (x : String) (h : w.name ∉ ids) :
    boundTo q now (run (es ++ w.cmds ids ended n)) x = boundTo q now (run es) x := by
  rw [workflow_foreign_none ids ended w n h]
  simp

/-- A define commutes with the commands of a run: the same plan state in either order, after any prefix. -/
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

/-- A define and a label commute. -/
theorem step_define_label (π : State) (d : Def) (k a : String) :
    step (step π (.define d)) (.label k a) = step (step π (.label k a)) (.define d) := by
  have hc : check { π with labels := π.labels ++ [(k, a)] } (.define d) = check π (.define d) := rfl
  rw [step_label, step_label]
  unfold step
  rw [hc]
  by_cases h : check π (.define d) = none
  · simp only [h, ↓reduceIte]; rfl
  · simp only [h, ↓reduceIte]

/-- A spawn, stop or label command (the commands a workflow gives). -/
def Cmd.isWf : Cmd → Bool
  | .spawn .. | .stop .. | .label .. => true
  | _ => false

/-- A define commutes with spawn, stop and label commands: the same plan state in either order,
after any prefix.
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

/-- The commands of any run are spawns, stops and labels. -/
theorem Wf.cmds_wf (ids : List String) (ended : Bool) (w : Wf) (n : Nat) :
    ∀ c ∈ w.cmds ids ended n, c.isWf = true := by
  intro c hc
  unfold Wf.cmds at hc
  split at hc
  · cases ended <;> simp at hc <;> rcases hc with rfl | rfl | rfl <;> rfl
  · simp at hc

/-- Every stop a run gives is a stop of its run key. -/
theorem Wf.cmds_stop (ids : List String) (ended : Bool) (w : Wf) (n : Nat) (k : String) (m : Nat)
    (h : Cmd.stop k m ∈ w.cmds ids ended n) : k = runKey w.run := by
  unfold Wf.cmds at h
  split at h
  · cases ended <;> simp at h
    exact h.1
  · simp at h

/-- **The claim-order race stays gone for workflows**: defining task `x` and running a workflow bind the same
agent in either order, after any log prefix.
-/
theorem define_workflow_comm (q now : Nat) (es : List Cmd) (d : Def) (ids : List String)
    (ended : Bool) (w : Wf) (n : Nat) (x : String) :
    boundTo q now (run (es ++ .define d :: w.cmds ids ended n)) x =
      boundTo q now (run (es ++ w.cmds ids ended n ++ [.define d])) x := by
  rw [define_wf_comm d _ es (Wf.cmds_wf ids ended w n)]

/-- The runs of a list of script file names, each (run id, name) pair once. -/
def runsOf (scripts : List String) : List Wf :=
  (scripts.filterMap fun f => (scriptRun f).map fun (n, r) => ({ run := r, name := n } : Wf)).eraseDups

/-- The event key of a workflow command, from a prefix `p` and a suffix `s`: a label gets
`p``-label:``s`, a stop `p``-end:``s`, any other command `p``:``s`.

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

(`ids(R)`: the run ids of the run file names `R`.)
-/
def wfEvents (ids scripts runFiles : List String) : List (String × Cmd) :=
  let ended := runFiles.filterMap runFileId
  (runsOf scripts).flatMap fun w =>
    (w.cmds ids (ended.contains w.run) 0).map fun c => (evKey "wfr" w.run c, c)

/-- No script named like a task, no event: a workflow that is no task id emits nothing. -/
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
`{"type":"started","agentId":…,"label":…}` line when an agent starts and a `{"type":"result","agentId":…}` or
`{"type":"failed","agentId":…}` line when it ends; the glue reads only those fields, never a result text, script or
transcript. Every agent of a run whose `meta.name` is a task id works on that task, whatever its label
(`run_task_binds`); an agent labelled `<phase>:<task>` also works on the task after the first `:`. Each binds
through its own agent id, which its `result` or `failed` line stops. -/

/-- The task named by a label `<phase>:<task>`: the non-empty text after the first `:`. -/
def labelTask (l : String) : Option String :=
  let r := l.dropWhile (· != ':')
  if r.isEmpty then none else
    let t := (r.drop 1).toString
    if t.isEmpty then none else some t

/-- A journal line: the run (its directory name), the agent id, whether it is a `started` line (else a `result` or
`failed` line) and the label of a `started` line.
-/
structure JLine where
  run     : String
  id      : String
  started : Bool
  label   : String
deriving Repr, DecidableEq

/-- A workflow agent: run, agent id, label, and whether its `result` or `failed` line exists. -/
structure WfAgent where
  run   : String
  id    : String
  label : String
  done  : Bool
deriving Repr, DecidableEq

/-- The agents of a journal: one per `started` line of a valid run id (duplicates once), done iff a `result` or
`failed` line (any line that is not `started`) of the same run and agent id exists.

(`dedup` keeps the first of equal entries, in journal order.)
-/
def wfAgents (js : List JLine) : List WfAgent :=
  ((js.filter fun j => j.started && isRunId j.run).map fun j =>
    ({ run := j.run, id := j.id, label := j.label,
       done := js.any fun k => !k.started && k.run == j.run && k.id == j.id } : WfAgent)).eraseDups

/-- The tasks an agent works on, given the task ids and the name of its run (none when no script of
the run is known): the run's name when it is a task id, whatever the agent's label says, then the
label's task when that is a task id, each once.

(`o^(?)`: the one-element list of `some(x)`, the empty list of `⊥`.)
-/
def WfAgent.tasks (ids : List String) (rn : Option String) (a : WfAgent) : List String :=
  ((rn.toList ++ (labelTask a.label).toList).filter ids.contains).eraseDups

/-- The commands of a workflow agent, given the task ids, the name of its run and whether its run
has ended: when it works on a task, a label of its agent id with each of its tasks, a spawn of the
agent id, and a stop of the agent id once its journal has a `result` or `failed` line or its run
ended; none when it works on no task.
-/
def WfAgent.cmds (ids : List String) (rn : Option String) (runEnded : Bool) (a : WfAgent) (n : Nat) :
    List Cmd :=
  if (a.tasks ids rn).isEmpty then []
  else (a.tasks ids rn).map (Cmd.label a.id ·) ++
    .spawn a.id n :: (if a.done || runEnded then [.stop a.id n] else [])

/-- The name of run `r` among the runs of the script file names: that of the first run with id `r`;
none when no script names run `r`.
-/
def runName (scripts : List String) (r : String) : Option String :=
  ((runsOf scripts).find? (·.run == r)).map (·.name)

/-- The event key of an agent command of run `r` and agent id `i`: a label of task `t` gets
`wfid-label:``r``:``i``:``t`; a spawn or stop gets `evKey(wfid, r ++ : ++ i, c)`.

One distinct key per label, so two labels of one agent never collide.
-/
def aKey (r i : String) : Cmd → String
  | .label _ t => "wfid-label:" ++ r ++ ":" ++ i ++ ":" ++ t
  | c => evKey "wfid" (r ++ ":" ++ i) c

/-- The events of the workflow agents: each journal agent's commands, with its run's name from the
scripts and its run ended iff a run file names the run.
-/
def agentEvents (ids scripts runFiles : List String) (journal : List JLine) : List (String × Cmd) :=
  let ended := runFiles.filterMap runFileId
  (wfAgents journal).flatMap fun a =>
    (a.cmds ids (runName scripts a.run) (ended.contains a.run) 0).map fun c => (aKey a.run a.id c, c)

/-- All workflow events: those of the runs named like a task, then those of their agents. -/
def wfAllEvents (ids scripts runFiles : List String) (journal : List JLine) : List (String × Cmd) :=
  wfEvents ids scripts runFiles ++ agentEvents ids scripts runFiles journal

/-- **The run-only behaviour is kept**: with no journal lines the events are exactly the run events. -/
theorem wfAllEvents_nil (ids scripts runFiles : List String) :
    wfAllEvents ids scripts runFiles [] = wfEvents ids scripts runFiles := by
  simp [wfAllEvents, agentEvents, wfAgents]

/-- **Every agent of a run named like a task works on it** (`run_task_binds`): whatever its label,
an agent of a run whose name `t` is a task id has `t` among its tasks.
-/
theorem run_task_binds (ids : List String) (t : String) (a : WfAgent) (h : t ∈ ids) :
    t ∈ a.tasks ids (some t) := by
  simp [WfAgent.tasks, List.mem_eraseDups, h]

/-- A running agent that works on a task labels its id with its tasks and spawns it (no stop). -/
theorem WfAgent.cmds_running (ids : List String) (rn : Option String) (a : WfAgent) (n : Nat)
    (ht : a.tasks ids rn ≠ []) (hd : a.done = false) :
    a.cmds ids rn false n = (a.tasks ids rn).map (Cmd.label a.id ·) ++ [.spawn a.id n] := by
  simp [WfAgent.cmds, ht, hd]

/-- An ended agent (or one of an ended run) that works on a task labels, spawns and stops its id:
its own key ends with it.
-/
theorem WfAgent.cmds_ended (ids : List String) (rn : Option String) (e : Bool) (a : WfAgent)
    (n : Nat) (ht : a.tasks ids rn ≠ []) (hd : (a.done || e) = true) :
    a.cmds ids rn e n =
      (a.tasks ids rn).map (Cmd.label a.id ·) ++ [.spawn a.id n, .stop a.id n] := by
  simp [WfAgent.cmds, ht, hd]

/-- The commands of an agent are spawns, stops and labels. -/
theorem WfAgent.cmds_wf (ids : List String) (rn : Option String) (e : Bool) (a : WfAgent) (n : Nat) :
    ∀ c ∈ a.cmds ids rn e n, c.isWf = true := by
  intro c hc
  unfold WfAgent.cmds at hc
  split at hc
  · simp at hc
  · simp only [List.mem_append, List.mem_map, List.mem_cons] at hc
    rcases hc with ⟨t, -, rfl⟩ | rfl | hc
    · rfl
    · rfl
    · split at hc <;> simp_all [Cmd.isWf]

/-- Every stop an agent gives is a stop of its own id. -/
theorem WfAgent.cmds_stop (ids : List String) (rn : Option String) (e : Bool) (a : WfAgent) (n : Nat)
    (k : String) (m : Nat) (h : Cmd.stop k m ∈ a.cmds ids rn e n) : k = a.id := by
  unfold WfAgent.cmds at h
  split at h
  · simp at h
  · simp only [List.mem_append, List.mem_map, List.mem_cons] at h
    rcases h with ⟨t, -, h⟩ | h | h
    · cases h
    · cases h
    · split at h <;> simp_all

/-- **A define commutes with the commands of a workflow agent**, as with a run's. -/
theorem define_agent_comm (q now : Nat) (es : List Cmd) (d : Def) (ids : List String)
    (rn : Option String) (e : Bool) (a : WfAgent) (n : Nat) (x : String) :
    boundTo q now (run (es ++ .define d :: a.cmds ids rn e n)) x =
      boundTo q now (run (es ++ a.cmds ids rn e n ++ [.define d])) x := by
  rw [define_wf_comm d _ es (WfAgent.cmds_wf ids rn e a n)]

/-- **Concurrent agents of one task** (`workflow_concurrent`): a running agent `b` working on task
`t`, spawned at `n` later than every stop of its id, keeps `t` not ended through any later commands
with no stop of `b`'s id, such as the commands of every other agent (`WfAgent.cmds_stop`) and of
every run (`Wf.cmds_stop`), the stop of another agent of `t` included.

A task never ends while one of its agents has not stopped, whatever its other agents do.
-/
theorem workflow_concurrent (π : State) (ids : List String) (rn : Option String) (b : WfAgent)
    (t : String) (n : Nat) (cs : List Cmd) (ht : t ∈ b.tasks ids rn) (hd : b.done = false)
    (hs : ∀ p ∈ π.stops, p.1 = b.id → p.2 < n) (hcs : ∀ c ∈ cs, ∀ m, c ≠ .stop b.id m) :
    ended ((b.cmds ids rn false n ++ cs).foldl step π) t = false := by
  rw [WfAgent.cmds_running ids rn b n (List.ne_nil_of_mem ht) hd, List.append_assoc]
  exact key_keeps π b.id _ t n cs ht hs hcs

/-- **Identity only** (`wfAllEvents_identity`): every workflow event is a label, spawn or stop of a
run key `wf:<runId>` of a run in `scripts` named like a task, labelled with that name, or of the agent
id of a journal agent that works on a task, labelled with one of its tasks; never of a task name.

(`κ_w = runKey(w.run)`, `T_a = tasks(I, runName(S, a.run), a)`.) A task
name only ever appears as a label.
-/
theorem wfAllEvents_identity (ids scripts runFiles : List String) (journal : List JLine)
    (ev : String) (c : Cmd) (he : (ev, c) ∈ wfAllEvents ids scripts runFiles journal) :
    (∃ w ∈ runsOf scripts, w.name ∈ ids ∧ (c = .label (runKey w.run) w.name ∨
        c = .spawn (runKey w.run) 0 ∨ c = .stop (runKey w.run) 0)) ∨
      ∃ a ∈ wfAgents journal,
        (∃ t ∈ a.tasks ids (runName scripts a.run), c = .label a.id t) ∨
        (a.tasks ids (runName scripts a.run) ≠ [] ∧ (c = .spawn a.id 0 ∨ c = .stop a.id 0)) := by
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
    refine ⟨a, ha, ?_⟩
    unfold WfAgent.cmds at hc
    split at hc
    · simp at hc
    · rename_i hne
      have hne' : a.tasks ids (runName scripts a.run) ≠ [] := by simpa using hne
      simp only [List.mem_append, List.mem_map, List.mem_cons] at hc
      rcases hc with ⟨t, ht, rfl⟩ | rfl | hc
      · exact .inl ⟨t, ht, rfl⟩
      · exact .inr ⟨hne', .inl rfl⟩
      · split at hc
        · simp only [List.mem_singleton] at hc
          exact .inr ⟨hne', .inr hc⟩
        · simp at hc

end Fw.Plan
