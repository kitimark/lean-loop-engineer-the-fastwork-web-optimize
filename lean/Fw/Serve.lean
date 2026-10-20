import Std.Data.HashSet
import Fw.Console
import Fw.Board
import Fw.Wire
import Fw.Wire.Plan
import Fw.Plan.Fast
import Fw.Plan.FastView
/-!
# `fwcore serve`: the stateful console session (PLAN §3.2, the `TS → fwcore` row)

`fwcore` holds the console state for its whole life, so console-api sends one event per
`console.apply`, not the state. The pure core is `Fw.Serve.exec : Srv → Cmd → Srv × Resp`; the IO
loop (`Fw.Wire.Serve.loop`) only reads a line, runs `serveLine` inside `IO.Ref.modifyGet` and
writes the reply.

* `Srv` stands for a console `State` (`Srv.st`) but keeps each table as an array with a hash index
  from id to position, and the seen keys in a hash set, so an event costs O(1) lookups and in-place
  edits instead of list scans and copies. `fcheck_eq`, `faccept_st`, `fstep_spec`: on an indexed
  server (`Indexed`, kept by every step) it decides exactly as `check`/`accept`/`step`.
* `run_eq_fold`, `run_init_eq_project`: the state after any sequence of serve calls without a reset
  is the left fold of `apply` over their events, so `apply`-by-`apply` equals one `replay`
  (`apply_each_eq_replay`). `run_reset`: a reset forgets everything before it.
* `refused_unchanged`: a refused event leaves the server state unchanged and reports no changed
  rows; an accepted one reports the rows it touched (`accepted_changed`).
* `query_keeps`, `query_eq_of_st`, `query_after_run`: a query changes nothing and its reply is the
  board of the console state only. It is computed by `fastBoard` (two hash indexes, one pass),
  proved equal to `Fw.Console.board` (`fastBoard_eq`).

Measured (`lake test`, console-api `test/serve.test.ts`): 100k synthetic events replay in ≈0.4 s
through console-api, apply round trip ≈40 µs, query ≈40 ms on that state. The real log (14,460 events, 2026-10-20)
replays in ≈0.14 s, 4× that in ≈0.6 s (`Fw.Plan.Fast`: no whole-graph cycle pass per `task.define`).

The JSON codecs and the IO loop are in `Fw.Wire.Serve` (glue, outside the math view).
-/
namespace Fw.Serve
open Fw.Console

/-! ## Indexed tables -/

/-- A table: its rows in order and a hash index from a row's id to its position. -/
structure Tbl (α : Type) where
  rows : Array α
  idx  : Std.HashMap String Nat

/-- The empty table. -/
def Tbl.empty {α : Type} : Tbl α := ⟨#[], {}⟩

/-- The index is exact for the id function `key`: it maps `k` to `i` exactly when row `i` exists and has
id `k` (so ids are unique).
-/
def Tbl.Ok {α : Type} (key : α → String) (t : Tbl α) : Prop :=
  ∀ k i, t.idx[k]? = some i ↔ ∃ h : i < t.rows.size, key t.rows[i] = k

/-- Whether a row with id `k` exists (an index lookup). -/
def Tbl.has {α : Type} (t : Tbl α) (k : String) : Bool := t.idx.contains k

/-- The row with id `k` (an index lookup). -/
def Tbl.get? {α : Type} (t : Tbl α) (k : String) : Option α :=
  match t.idx[k]? with
  | some i => t.rows[i]?
  | none => none

/-- Append a row and index it under its id. -/
def Tbl.push {α : Type} (key : α → String) (t : Tbl α) (a : α) : Tbl α :=
  match t with
  | ⟨rows, idx⟩ => let idx := idx.insert (key a) rows.size; ⟨rows.push a, idx⟩

/-- Apply `f` to the row with id `k` (in place), if there is one; an index entry past the last row
changes nothing.
-/
def Tbl.modify {α : Type} (t : Tbl α) (k : String) (f : α → α) : Tbl α :=
  match t with
  | ⟨rows, idx⟩ =>
    match idx[k]? with
    | some i => ⟨rows.modify i f, idx⟩
    | none => ⟨rows, idx⟩

namespace Tbl
variable {α : Type} {key : α → String}

/-- The empty table is exact. -/
theorem empty_ok : Ok key (Tbl.empty (α := α)) := by
  intro k i
  simp [Tbl.empty]

/-- In an exact table, two rows with the same id are the same row. -/
theorem ok_unique {t : Tbl α} (h : Ok key t) {i j : Nat} (hi : i < t.rows.size) (hj : j < t.rows.size)
    (he : key t.rows[i] = key t.rows[j]) : i = j := by
  have a := (h (key t.rows[j]) i).mpr ⟨hi, he⟩
  have b := (h (key t.rows[j]) j).mpr ⟨hj, rfl⟩
  rw [a] at b; exact Option.some.inj b

/-- In an exact table, the index lookup `has` is the linear scan `any`. -/
theorem has_eq {t : Tbl α} (h : Ok key t) (k : String) :
    t.has k = t.rows.toList.any (fun x => key x == k) := by
  unfold has
  rw [Std.HashMap.contains_eq_isSome_getElem?]
  cases hk : t.idx[k]? with
  | some i =>
    obtain ⟨hi, hx⟩ := (h k i).mp hk
    symm
    simp only [Option.isSome_some, List.any_eq_true, beq_iff_eq]
    exact ⟨t.rows[i], Array.getElem_mem_toList hi, hx⟩
  | none =>
    symm
    simp only [Option.isSome_none, List.any_eq_false, beq_iff_eq]
    intro x hx hxk
    obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem hx
    have := (h k i).mpr ⟨by simpa using hi, by simpa using hxk⟩
    rw [hk] at this; cases this

/-- In an exact table, the index lookup `get` is the linear scan `find?` (the first row with id `k`). -/
theorem get?_eq {t : Tbl α} (h : Ok key t) (k : String) :
    t.get? k = t.rows.toList.find? (fun x => key x == k) := by
  unfold get?
  cases hk : t.idx[k]? with
  | some i =>
    obtain ⟨hi, hx⟩ := (h k i).mp hk
    simp only [Array.getElem?_eq_getElem hi]
    symm
    rw [List.find?_eq_some_iff_getElem]
    refine ⟨by simpa using hx, i, by simpa using hi, by simp, ?_⟩
    intro j hj
    simp only [Bool.not_eq_eq_eq_not, Bool.not_true, beq_eq_false_iff_ne]
    intro hjk
    have hj' : j < t.rows.size := by omega
    have := ok_unique h hj' hi (by simpa [hx] using hjk)
    omega
  | none =>
    symm
    rw [List.find?_eq_none]
    intro x hx hxk
    obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem hx
    have := (h k i).mpr ⟨by simpa using hi, by simpa using hxk⟩
    rw [hk] at this; cases this

/-- Pushing appends the row. -/
theorem push_rows (t : Tbl α) (a : α) : (t.push key a).rows.toList = t.rows.toList ++ [a] := by
  cases t; simp [push]

/-- `push` in projection form (its code destructures the table so the array is updated in place). -/
theorem push_eq (t : Tbl α) (a : α) : t.push key a = ⟨t.rows.push a, t.idx.insert (key a) t.rows.size⟩ := by
  cases t; rfl

/-- `modify` in projection form (its code destructures the table so the array is updated in place). -/
theorem modify_eq (t : Tbl α) (k : String) (f : α → α) :
    t.modify k f = match t.idx[k]? with
      | some i => ⟨t.rows.modify i f, t.idx⟩
      | none => t := by
  cases t; rfl

/-- Pushing a row whose id is new keeps the table exact. -/
theorem push_ok {t : Tbl α} (h : Ok key t) {a : α} (hn : t.has (key a) = false) :
    Ok key (t.push key a) := by
  intro k i
  simp only [push_eq, Std.HashMap.getElem?_insert, Array.size_push, Array.getElem_push]
  have hnone : t.idx[key a]? = none := by
    unfold has at hn
    rw [Std.HashMap.contains_eq_isSome_getElem?] at hn
    match h' : t.idx[key a]? with
    | none => rfl
    | some _ => rw [h'] at hn; cases hn
  by_cases hka : key a = k
  · subst hka
    simp only [beq_self_eq_true, ite_true, Option.some.injEq]
    constructor
    · rintro rfl; exact ⟨by omega, by simp⟩
    · rintro ⟨hi, hx⟩
      by_cases hlt : i < t.rows.size
      · simp only [hlt, dite_true] at hx
        have := (h (key a) i).mpr ⟨hlt, hx⟩
        rw [hnone] at this; cases this
      · omega
  · have hb : (key a == k) = false := by simpa using hka
    simp only [hb, Bool.false_eq_true, ite_false]
    constructor
    · intro hk
      obtain ⟨hi, hx⟩ := (h k i).mp hk
      exact ⟨by omega, by simpa [hi] using hx⟩
    · rintro ⟨hi, hx⟩
      by_cases hlt : i < t.rows.size
      · simp only [hlt, dite_true] at hx
        exact (h k i).mpr ⟨hlt, hx⟩
      · simp only [hlt, dite_false] at hx
        exact absurd hx hka

/-- In an exact table, modifying the row with id `k` is mapping `f` over every row with id `k`. -/
theorem modify_rows {t : Tbl α} (h : Ok key t) (k : String) (f : α → α) :
    (t.modify k f).rows.toList = t.rows.toList.map (fun x => if key x = k then f x else x) := by
  rw [modify_eq]
  cases hk : t.idx[k]? with
  | some i =>
    obtain ⟨hi, hx⟩ := (h k i).mp hk
    apply List.ext_getElem (by simp)
    intro j h1 h2
    simp only [Array.getElem_toList, List.getElem_map, Array.getElem_modify]
    have hj : j < t.rows.size := by simpa using h2
    by_cases hij : i = j
    · subst hij; simp [hx]
    · have hne : ¬ key t.rows[j] = k := by
        intro hjk
        exact hij (ok_unique h hi hj (by rw [hx, hjk]))
      simp [hij, hne]
  | none =>
    simp only
    conv => lhs; rw [← List.map_id t.rows.toList]
    apply List.map_congr_left
    intro x hx
    have hne : ¬ key x = k := by
      intro hxk
      obtain ⟨i, hi, rfl⟩ := List.getElem_of_mem hx
      have := (h k i).mpr ⟨by simpa using hi, by simpa using hxk⟩
      rw [hk] at this; cases this
    simp [hne]

/-- Modifying with an id-preserving `f` keeps the table exact. -/
theorem modify_ok {t : Tbl α} (h : Ok key t) (k : String) {f : α → α} (hf : ∀ x, key (f x) = key x) :
    Ok key (t.modify k f) := by
  rw [modify_eq]
  split
  · intro k' i
    rw [h k' i]
    constructor
    · rintro ⟨hi, hx⟩
      refine ⟨by simpa using hi, ?_⟩
      rw [Array.getElem_modify]; split <;> simp_all
    · rintro ⟨hi, hx⟩
      refine ⟨by simpa using hi, ?_⟩
      rw [Array.getElem_modify] at hx; split at hx <;> simp_all
  · exact h

end Tbl
/-! ## The server state -/

/-- The server state: the seen keys (a list, newest first, and a hash set), the three tables and
the plan (the work graph; its spawn, stop, mark and label lists are stored newest first, see `Fw.Plan.unrev`).
-/
structure Srv where
  seen  : List String
  keys  : Std.HashSet String
  cards : Tbl Card
  steps : Tbl Step
  runs  : Tbl Run
  plan  : Fw.Plan.State

/-- The console state a server state stands for. -/
def Srv.st (v : Srv) : State :=
  ⟨v.seen, v.cards.rows.toList, v.steps.rows.toList, v.runs.rows.toList, Fw.Plan.unrev v.plan⟩

/-- The initial server state. -/
def init : Srv := ⟨[], {}, .empty, .empty, .empty, {}⟩

/-- The indexes agree with the rows: the key set is the seen list, every table is exact for its id, and the plan holds its
invariant (unique task ids, acyclic graph), which the fast cycle test of `fcheck` relies on.
-/
def Indexed (v : Srv) : Prop :=
  (∀ k, v.keys.contains k = v.seen.contains k) ∧ v.cards.Ok Card.id ∧ v.steps.Ok Step.id ∧ v.runs.Ok Run.id ∧
    Fw.Plan.Inv v.plan

/-- The initial server state is indexed and stands for the empty console state. -/
theorem init_spec : Indexed init ∧ init.st = {} :=
  ⟨⟨by intro k; simp [init], Tbl.empty_ok, Tbl.empty_ok, Tbl.empty_ok, Fw.Plan.inv_init⟩, rfl⟩

/-- `check` with index lookups instead of list scans (same cases, same reasons, same order). -/
def fcheck (v : Srv) (e : Event) : Option String :=
  if !may e.actor e.body.type then some s!"actor {e.actor.name} may not cause {e.body.type.name}" else
  match e.body with
  | .cardOpen id _ _ => if v.cards.has id then some "card exists" else none
  | .stepPost id card _ kind opts _ _ =>
    if v.steps.has id then some "step exists"
    else if (match card with | some c => !(v.cards.has c) | none => false) then some "no such card"
    else if kind = .choice && (opts.getD []).length < 2 then some "choice step needs at least 2 options"
    else none
  | .stepStart id | .stepAnswer id _ | .stepDone id _ | .stepCancel id =>
    match v.steps.get? id with
    | none => some "no such step"
    | some st => stepRefusal st e.actor e.body
  | .runStart r card _ =>
    if !(v.cards.has card) then some "no such card"
    else if v.runs.has r then some "run exists" else none
  | .runFinish r _ =>
    match v.runs.get? r with
    | none => some "no such run"
    | some run => if run.status = .running then none else some "run already finished"
  | .plan c => Fw.Plan.checkFast v.plan c
  | b => match cardOf b with
    | none => none
    | some id => match v.cards.get? id with
      | none => some "no such card"
      | some c => cardRefusal c b

/-- The step update of `mapSteps`: apply `f`, then record activity at `t`. -/
def stepUpd (t : Nat) (f : Step → Step) (s : Step) : Step := { f s with lastAt := max s.lastAt t }

/-- The run update of `runFinish`: passed or failed. -/
def runFin (ok : Bool) (x : Run) : Run := { x with status := if ok then .passed else .failed }

/-- `accept` on the tables: appends are pushes, in-place edits are index-addressed `modify`s. -/
def faccept (v : Srv) (e : Event) : Srv :=
  let t := e.ts
  match v with
  | ⟨seen, keys, cards, steps, runs, plan⟩ =>
  match e.body with
  | .cardOpen id owner dev =>
    ⟨seen, keys, cards.push Card.id { id, owner, needsDevice := dev, lastAt := t }, steps, runs, plan⟩
  | .stepPost id card title kind opts audience body =>
    ⟨seen, keys, cards, steps.push Step.id { id, card, title, kind, options := opts, postedAt := t, lastAt := t, audience, body }, runs, plan⟩
  | .stepStart id => ⟨seen, keys, cards, steps.modify id (stepUpd t fun x => { x with status := .started }), runs, plan⟩
  | .stepAnswer id a =>
    ⟨seen, keys, cards, steps.modify id (stepUpd t fun x => { x with status := .answered, answer := some a }), runs, plan⟩
  | .stepDone id note =>
    ⟨seen, keys, cards, steps.modify id (stepUpd t fun x => { x with status := .done, answer := note.orElse fun _ => x.answer }), runs, plan⟩
  | .stepCancel id => ⟨seen, keys, cards, steps.modify id (stepUpd t fun x => { x with status := .cancelled }), runs, plan⟩
  | .runStart r card kind =>
    ⟨seen, keys, cards.modify card (touch t), steps, runs.push Run.id { id := r, card, kind, startedAt := t }, plan⟩
  | .runFinish r ok =>
    match runs.get? r with
    | some run => ⟨seen, keys, cards.modify run.card (touch t), steps, runs.modify r (runFin ok), plan⟩
    | none => ⟨seen, keys, cards, steps, runs, plan⟩
  | .plan c => ⟨seen, keys, cards, steps, runs, Fw.Plan.execR plan c⟩
  | b => match cardOf b with
    | some id => ⟨seen, keys, cards.modify id (cardStep t b), steps, runs, plan⟩
    | none => ⟨seen, keys, cards, steps, runs, plan⟩

/-- `faccept` leaves the seen list and the key set alone. -/
theorem faccept_seen (v : Srv) (e : Event) : (faccept v e).seen = v.seen ∧ (faccept v e).keys = v.keys := by
  obtain ⟨seen, keys, cards, steps, runs, plan⟩ := v
  cases e with
  | mk key ts actor body =>
    cases body <;> simp only [faccept] <;> (try split) <;> simp

/-- The reducer step on the server state: like `step`, with the hash set for the duplicate check and
`fcheck`/`faccept` for the rest.
-/
def fstep (v : Srv) (e : Event) : Srv × Outcome :=
  if v.keys.contains e.key then (v, .accepted true)
  else match fcheck v e with
    | some w => (v, .refused w)
    | none =>
      match faccept v e with
      | ⟨seen, keys, cards, steps, runs, plan⟩ =>
        (⟨e.key :: seen, keys.insert e.key, cards, steps, runs, plan⟩, .accepted false)

/-- The server state after one event. -/
def fapply (v : Srv) (e : Event) : Srv := (fstep v e).1

/-- A card transition never changes the card's id. -/
theorem cardStep_id (t : Nat) (b : Body) (c : Card) : (cardStep t b c).id = c.id := by
  unfold cardStep touch
  split
  · rfl
  · split <;> rfl

/-- On an indexed server, `fcheck` gives the same answer as `check` on the console state. -/
theorem fcheck_eq {v : Srv} (h : Indexed v) (e : Event) : fcheck v e = check v.st e := by
  obtain ⟨_, hc, hs, hr, hp⟩ := h
  cases e with
  | mk key ts actor body =>
    cases body <;>
      simp only [fcheck, check, Srv.st, Tbl.has_eq hc, Tbl.has_eq hs, Tbl.has_eq hr, Tbl.get?_eq hc,
        Tbl.get?_eq hs, Tbl.get?_eq hr]
    case plan c => simp only [Fw.Plan.checkFast_eq hp.2 c, Fw.Plan.check_unrev]
    all_goals rfl

/-- On an indexed server, `faccept` stands for `accept` on the console state. -/
theorem faccept_st {v : Srv} (h : Indexed v) (e : Event) : (faccept v e).st = accept v.st e := by
  obtain ⟨_, hc, hs, hr, hp⟩ := h
  cases e with
  | mk key ts actor body =>
    cases body <;>
      simp only [faccept, accept, Srv.st, Tbl.push_rows, Tbl.modify_rows hc, Tbl.modify_rows hs,
        Tbl.get?_eq hr, mapCards, mapSteps, stepUpd, cardOf]
    case plan c => simp only [Fw.Plan.unrev_execR]
    case runFinish r ok =>
      cases hf : List.find? (fun x => x.id == r) v.runs.rows.toList with
      | none => rfl
      | some run => dsimp only; simp only [Tbl.modify_rows hc, Tbl.modify_rows hr, runFin]

/-- `faccept` keeps the server indexed when `fcheck` accepts the event (a push only ever adds a new id,
and every in-place edit keeps the row's id).
-/
theorem faccept_indexed {v : Srv} (h : Indexed v) (e : Event) (hn : fcheck v e = none) :
    Indexed (faccept v e) := by
  obtain ⟨hk, hc, hs, hr, hp⟩ := h
  have mc : ∀ k (f : Card → Card), (∀ x, (f x).id = x.id) → Tbl.Ok Card.id (v.cards.modify k f) :=
    fun k _ hf => Tbl.modify_ok hc k hf
  have ms : ∀ t k (f : Step → Step), (∀ x, (f x).id = x.id) →
      Tbl.Ok Step.id (v.steps.modify k (stepUpd t f)) :=
    fun _ k _ hf => Tbl.modify_ok hs k (fun x => by simp [stepUpd, hf])
  cases e with
  | mk key ts actor body =>
    cases body with
    | cardOpen id o d =>
      simp only [fcheck] at hn
      split at hn
      · cases hn
      · split at hn
        · cases hn
        · exact ⟨hk, Tbl.push_ok hc (Bool.eq_false_iff.mpr ‹¬ v.cards.has id = true›), hs, hr, hp⟩
    | stepPost id card title kind opts audience body =>
      simp only [fcheck] at hn
      split at hn
      · cases hn
      · split at hn
        · cases hn
        · exact ⟨hk, hc, Tbl.push_ok hs (Bool.eq_false_iff.mpr ‹¬ v.steps.has id = true›), hr, hp⟩
    | runStart r card kind =>
      simp only [fcheck] at hn
      split at hn
      · cases hn
      · split at hn
        · cases hn
        · split at hn
          · cases hn
          · exact ⟨hk, mc _ _ (fun _ => rfl), hs, Tbl.push_ok hr (Bool.eq_false_iff.mpr ‹¬ v.runs.has r = true›), hp⟩
    | runFinish r ok =>
      simp only [faccept]
      split
      · exact ⟨hk, mc _ _ (fun _ => rfl), hs, Tbl.modify_ok hr _ (fun _ => rfl), hp⟩
      · exact ⟨hk, hc, hs, hr, hp⟩
    | stepStart id => exact ⟨hk, hc, ms _ _ _ (fun _ => rfl), hr, hp⟩
    | stepAnswer id a => exact ⟨hk, hc, ms _ _ _ (fun _ => rfl), hr, hp⟩
    | stepDone id note => exact ⟨hk, hc, ms _ _ _ (fun _ => rfl), hr, hp⟩
    | stepCancel id => exact ⟨hk, hc, ms _ _ _ (fun _ => rfl), hr, hp⟩
    | plan c =>
      simp only [fcheck] at hn
      split at hn
      · cases hn
      · exact ⟨hk, hc, hs, hr, (Fw.Plan.inv_unrev (Fw.Plan.execR v.plan c)).mp (by rw [Fw.Plan.unrev_execR]; exact Fw.Plan.exec_inv ((Fw.Plan.inv_unrev _).mpr hp) (by rw [Fw.Plan.check_unrev, ← Fw.Plan.checkFast_eq hp.2 c]; exact hn))⟩
    | _ => exact ⟨hk, mc _ _ (cardStep_id _ _), hs, hr, hp⟩

/-- On an indexed server, `fstep` gives exactly the console state and the outcome of `step`. -/
theorem fstep_spec {v : Srv} (h : Indexed v) (e : Event) :
    (fstep v e).1.st = (step v.st e).1 ∧ (fstep v e).2 = (step v.st e).2 := by
  have hf := fcheck_eq h e
  have ha := faccept_st h e
  unfold fstep step
  rw [h.1 e.key, hf]
  have hseen : v.st.seen = v.seen := rfl
  rw [hseen]
  by_cases hk : e.key ∈ v.seen
  · simp [hk]
  · cases hc : check v.st e with
    | some w => simp [hk]
    | none =>
      simp only [hk, List.contains_eq_mem, decide_false, Bool.false_eq_true, ite_false]
      refine ⟨?_, trivial⟩
      simp only [Srv.st] at ha ⊢
      rw [← ha, (faccept_seen v e).1]

/-- `fstep` keeps the server indexed. -/
theorem fstep_indexed {v : Srv} (h : Indexed v) (e : Event) : Indexed (fstep v e).1 := by
  unfold fstep
  split
  · exact h
  · split
    · exact h
    · rename_i hn
      obtain ⟨_, hc, hs, hr, hp⟩ := faccept_indexed h e hn
      refine ⟨?_, hc, hs, hr, hp⟩
      intro k
      simp only [Std.HashSet.contains_insert, List.contains_cons]
      cases hk : (e.key == k) <;> cases hk' : (k == e.key) <;> simp_all [beq_iff_eq]

/-- A refused event leaves the whole server state unchanged. -/
theorem fstep_refused {v : Srv} {e : Event} {w : String} (h : (fstep v e).2 = .refused w) :
    (fstep v e).1 = v := by
  revert h
  unfold fstep
  split
  · intro _; rfl
  · split
    · intro _; rfl
    · intro h; simp at h

/-! ## Changed rows -/

/-- The rows an event touches: the card, step and run it names (for `runFinish` also the run's card). -/
structure Delta where
  cards : List Card
  steps : List Step
  runs  : List Run

/-- The rows of `σ` that event `e` touches, each the first row with that id (none if absent): the card of
a card event or `runStart`, the step of a step event, the run of a run event and, for `runFinish`, the
card of that run.
-/
def touched (s : State) (e : Event) : Delta :=
  match e.body with
  | .cardOpen id _ _ => ⟨(s.cards.find? (·.id == id)).toList, [], []⟩
  | .stepPost id .. | .stepStart id | .stepAnswer id _ | .stepDone id _ | .stepCancel id =>
    ⟨[], (s.steps.find? (·.id == id)).toList, []⟩
  | .runStart r c _ => ⟨(s.cards.find? (·.id == c)).toList, [], (s.runs.find? (·.id == r)).toList⟩
  | .runFinish r _ =>
    match s.runs.find? (·.id == r) with
    | some x => ⟨(s.cards.find? (·.id == x.card)).toList, [], [x]⟩
    | none => ⟨[], [], []⟩
  | b => match cardOf b with
    | some id => ⟨(s.cards.find? (·.id == id)).toList, [], []⟩
    | none => ⟨[], [], []⟩

/-- `touched` with index lookups. -/
def ftouched (v : Srv) (e : Event) : Delta :=
  match e.body with
  | .cardOpen id _ _ => ⟨(v.cards.get? id).toList, [], []⟩
  | .stepPost id .. | .stepStart id | .stepAnswer id _ | .stepDone id _ | .stepCancel id =>
    ⟨[], (v.steps.get? id).toList, []⟩
  | .runStart r c _ => ⟨(v.cards.get? c).toList, [], (v.runs.get? r).toList⟩
  | .runFinish r _ =>
    match v.runs.get? r with
    | some x => ⟨(v.cards.get? x.card).toList, [], [x]⟩
    | none => ⟨[], [], []⟩
  | b => match cardOf b with
    | some id => ⟨(v.cards.get? id).toList, [], []⟩
    | none => ⟨[], [], []⟩

/-- On an indexed server, `ftouched` is `touched` of the console state. -/
theorem ftouched_eq {v : Srv} (h : Indexed v) (e : Event) : ftouched v e = touched v.st e := by
  obtain ⟨_, hc, hs, hr, hp⟩ := h
  cases e with
  | mk key ts actor body =>
    cases body <;>
      simp only [ftouched, touched, Srv.st, Tbl.get?_eq hc, Tbl.get?_eq hs, Tbl.get?_eq hr]

/-- The changed rows reported for an outcome: the rows the event touched in the new state when it was
accepted fresh, none otherwise (a duplicate or a refusal changes nothing).
-/
def changed (v' : Srv) (e : Event) (o : Outcome) : Delta :=
  if o = .accepted false then ftouched v' e else ⟨[], [], []⟩

/-! ## The board in one pass

`Fw.Console.board` scans all steps and runs once per card. `fastBoard` builds two hash indexes first
(one pass each) and is proved equal to it (`fastBoard_eq`), so a query costs O(cards + steps + runs).
-/

/-- The first open step of each card: folding from the right, the leftmost open step of a card is
inserted last, so it wins.
-/
def openIdx (ss : List Step) : Std.HashMap String Step :=
  ss.foldr (fun x m => match x.card with
    | some c => if x.status.isOpen then m.insert c x else m
    | none => m) {}

/-- The number of running runs of each card (each list entry counts; a card with no running run has
no entry).
-/
def runIdx (rs : List Run) : Std.HashMap String Nat :=
  rs.foldr (fun r m => if r.status == .running then m.insert r.card (m.getD r.card 0 + 1) else m) {}

/-- The index lookup of `openIdx` is the scan `boardCard` does. -/
theorem openIdx_get (ss : List Step) (cid : String) :
    (openIdx ss)[cid]? = ss.find? (fun x => x.status.isOpen && x.card == some cid) := by
  induction ss with
  | nil => simp [openIdx]
  | cons x xs ih =>
    simp only [openIdx, List.foldr_cons] at ih ⊢
    rw [List.find?_cons]
    cases hc : x.card with
    | none => simpa using ih
    | some c =>
      cases ho : x.status.isOpen
      · simpa using ih
      · simp only [ite_true, Std.HashMap.getElem?_insert, Bool.true_and]
        by_cases h : c = cid
        · subst h; simp
        · have h' : (c == cid) = false := by simpa using h
          have h'' : (some c == some cid) = false := by simpa using h
          simp only [h', h'', Bool.false_eq_true, ite_false]
          exact ih

/-- The index lookup of `runIdx`, reading an absent card as 0, is the count `boardCard` does. -/
theorem runIdx_get (rs : List Run) (cid : String) :
    (runIdx rs).getD cid 0 = (rs.filter (fun r => r.card == cid && r.status == .running)).length := by
  induction rs with
  | nil => simp [runIdx]
  | cons x xs ih =>
    simp only [runIdx, List.foldr_cons, List.filter_cons] at ih ⊢
    by_cases hs : x.status = .running
    · simp only [hs, beq_self_eq_true, ite_true, Std.HashMap.getD_insert, Bool.and_true]
      by_cases h : x.card = cid
      · subst h; simpa using ih
      · have h' : (x.card == cid) = false := by simpa using h
        simp only [h', Bool.false_eq_true, ite_false]
        exact ih
    · have hs' : (x.status == .running) = false := by simpa using hs
      simp only [hs', Bool.false_eq_true, ite_false, Bool.and_false]
      exact ih

/-- One board row from the two indexes (the same fields as `boardCard`, with the open step and the
running count read from the indexes instead of scanned).
-/
def fastRow (oi : Std.HashMap String Step) (ri : Std.HashMap String Nat) (now : Nat) (c : Card) : BoardCard :=
  let st := stage c
  let mine := oi[c.id]?
  let running := ri.getD c.id 0
  { id := c.id, owner := c.owner, stage := st, next := next c st, lastAt := c.lastAt,
    needsYou := mine.map needs, runningRuns := running, head := c.head, landed := c.landed,
    violation := c.violation,
    stale := !c.landed && running == 0 && mine.isNone && decide (staleMs ≤ now - c.lastAt) }

/-- The board with the indexes built once. -/
def fastBoard (s : State) (now seq : Nat) : Board :=
  let oi := openIdx s.steps
  let ri := runIdx s.runs
  { seq, now, cards := s.cards.map (fastRow oi ri now), steps := s.steps,
    needsYou := (s.steps.filter (·.status.isOpen)).map needs }

/-- The one-pass board is the board. -/
theorem fastBoard_eq (s : State) (now seq : Nat) : fastBoard s now seq = board s now seq := by
  simp only [fastBoard, board]
  congr 1
  apply List.map_congr_left
  intro c _
  simp only [fastRow, boardCard, openIdx_get, runIdx_get]

#guard
  let s := project [⟨"k1", 1, .owner, .cardOpen "A" "o" false⟩, ⟨"k2", 2, .owner, .cardOpen "B" "o" false⟩,
    ⟨"k3", 3, .script, .stepPost "S" (some "A") "t" .action none⟩, ⟨"k4", 4, .owner, .runStart "R" "B" .gate⟩,
    ⟨"k5", 5, .owner, .runStart "Q" "B" .run⟩]
  (fastBoard s 9 1).cards == (board s 9 1).cards
  && (fastBoard s 9 1).cards.map (fun r => (r.runningRuns, r.needsYou.map (·.step))) == [(0, some "S"), (2, none)]
  && (fastBoard s (5 + staleMs) 1).cards.map (·.stale) == [false, false]

#guard
  let t := ((Tbl.empty : Tbl Run).push Run.id ⟨"a", "A", .run, .running, 1⟩).push Run.id ⟨"b", "A", .run, .running, 2⟩
  (t.get? "b").map (·.startedAt) == some 2 && t.has "a" && !t.has "c"
  && ((t.modify "a" (runFin true)).get? "a").map (·.status) == some .passed
  && (t.modify "c" (runFin true)).rows.toList == t.rows.toList

/-! ## Commands -/

/-- A serve command: apply one event, replay a list of events, query the board, or reset (tests). -/
inductive Cmd where
  | apply (e : Event)
  | replay (es : List Event)
  | query (now seq : Nat)
  | reset

/-- The events a command feeds to the reducer. -/
def Cmd.events : Cmd → List Event
  | .apply e => [e]
  | .replay es => es
  | _ => []

/-- Whether a command is a reset. -/
def Cmd.isReset : Cmd → Bool
  | .reset => true
  | _ => false

/-- What a replay did: how many events were accepted fresh, accepted as duplicates, or refused. -/
structure Tally where
  accepted  : Nat := 0
  duplicate : Nat := 0
  refused   : Nat := 0

/-- Count one outcome. -/
def Tally.count (t : Tally) : Outcome → Tally
  | .accepted false => { t with accepted := t.accepted + 1 }
  | .accepted true => { t with duplicate := t.duplicate + 1 }
  | .refused _ => { t with refused := t.refused + 1 }

/-- The total of a tally. -/
def Tally.total (t : Tally) : Nat := t.accepted + t.duplicate + t.refused

/-- Replay a list of events from a server state, counting outcomes. -/
def replayFrom : Srv → Tally → List Event → Srv × Tally
  | v, t, [] => (v, t)
  | v, t, e :: es => let r := fstep v e; replayFrom r.1 (t.count r.2) es

/-- The reply of a serve command. -/
inductive Resp where
  | applied (o : Outcome) (d : Delta)
  | replayed (t : Tally)
  | board (b : Board) (p : Fw.Plan.View)
  | reset

/-- One serve command: apply reports the outcome and the changed rows, replay the tally, query the
board and the board plan of the current console state; reset returns to the initial state.
-/
def exec (v : Srv) : Cmd → Srv × Resp
  | .apply e => let r := fstep v e; (r.1, .applied r.2 (changed r.1 e r.2))
  | .replay es => let r := replayFrom v {} es; (r.1, .replayed r.2)
  | .query now seq => (v, .board (fastBoard v.st now seq) (Fw.Plan.fastView Fw.Plan.quietMs now v.st.plan))
  | .reset => (init, .reset)

/-- Run a sequence of serve commands, keeping only the final server state. -/
def run (v : Srv) (cs : List Cmd) : Srv := cs.foldl (fun v c => (exec v c).1) v

/-! ## Theorems: serve calls are the reducer's fold -/

/-- Replay keeps the server indexed, and its console state is the fold of `apply` over the events. -/
theorem replayFrom_spec : ∀ (v : Srv) (t : Tally) (es : List Event), Indexed v →
    Indexed (replayFrom v t es).1 ∧ (replayFrom v t es).1.st = es.foldl apply v.st
  | _, _, [], h => ⟨h, rfl⟩
  | v, t, e :: es, h => by
    have ih := replayFrom_spec (fstep v e).1 (t.count (fstep v e).2) es (fstep_indexed h e)
    simp only [replayFrom, List.foldl_cons]
    refine ⟨ih.1, ?_⟩
    rw [ih.2, (fstep_spec h e).1]; rfl

/-- The replay tally counts every event exactly once. -/
theorem replayFrom_total : ∀ (v : Srv) (t : Tally) (es : List Event),
    (replayFrom v t es).2.total = t.total + es.length
  | _, _, [] => rfl
  | v, t, e :: es => by
    simp only [replayFrom, List.length_cons]
    rw [replayFrom_total]
    cases (fstep v e).2 with
    | accepted d => cases d <;> simp [Tally.count, Tally.total] <;> omega
    | refused w => simp [Tally.count, Tally.total]; omega

/-- A command other than reset keeps the server indexed, and its console state is the fold of `apply`
over the command's events.
-/
theorem exec_spec {v : Srv} (h : Indexed v) (c : Cmd) (hc : c.isReset = false) :
    Indexed (exec v c).1 ∧ (exec v c).1.st = c.events.foldl apply v.st := by
  cases c with
  | apply e => exact ⟨fstep_indexed h e, by simp [exec, Cmd.events, (fstep_spec h e).1, apply]⟩
  | replay es => exact replayFrom_spec v {} es h
  | query now seq => exact ⟨h, rfl⟩
  | reset => simp [Cmd.isReset] at hc

/-- **Serve is the fold.** After any sequence of serve calls without a reset, the server is indexed
and its console state is the left fold of `apply` over all their events, in order.
-/
theorem run_eq_fold : ∀ (v : Srv) (cs : List Cmd), Indexed v → (∀ c ∈ cs, c.isReset = false) →
    Indexed (run v cs) ∧ (run v cs).st = (cs.flatMap Cmd.events).foldl apply v.st
  | _, [], h, _ => ⟨h, rfl⟩
  | v, c :: cs, h, hr => by
    have hc := exec_spec h c (hr c List.mem_cons_self)
    have ih := run_eq_fold (exec v c).1 cs hc.1 (fun c' hm => hr c' (List.mem_cons_of_mem _ hm))
    simp only [run, List.foldl_cons, List.flatMap_cons, List.foldl_append] at ih ⊢
    exact ⟨ih.1, by rw [ih.2, hc.2]⟩

/-- From a fresh server, the console state after serve calls without a reset is the projection (full
replay) of their events.
-/
theorem run_init_eq_project (cs : List Cmd) (hr : ∀ c ∈ cs, c.isReset = false) :
    (run init cs).st = project (cs.flatMap Cmd.events) := by
  rw [(run_eq_fold init cs init_spec.1 hr).2, init_spec.2]; rfl

/-- Applying events one call at a time gives the same console state as one replay call, and both equal
the projection of the events.
-/
theorem apply_each_eq_replay (es : List Event) :
    (run init (es.map .apply)).st = (run init [.replay es]).st ∧
    (run init [.replay es]).st = project es := by
  have e1 : (es.map Cmd.apply).flatMap Cmd.events = es := by
    induction es with
    | nil => rfl
    | cons e es ih => simp [Cmd.events] at ih ⊢; exact ih
  have h1 := run_init_eq_project (es.map .apply) (by simp [Cmd.isReset])
  have h2 := run_init_eq_project [.replay es] (by simp [Cmd.isReset])
  have e2 : [Cmd.replay es].flatMap Cmd.events = es := by simp [Cmd.events]
  rw [e1] at h1; rw [e2] at h2
  exact ⟨h1.trans h2.symm, h2⟩

/-- A reset forgets everything before it: the calls after the last reset decide the state. -/
theorem run_reset (v : Srv) (cs rs : List Cmd) : run v (cs ++ .reset :: rs) = run init rs := by
  simp [run, List.foldl_append, exec]

/-- A refused `console.apply` leaves the server state unchanged and reports no changed rows. -/
theorem refused_unchanged {v : Srv} {e : Event} {w : String} {d : Delta}
    (h : (exec v (.apply e)).2 = .applied (.refused w) d) :
    (exec v (.apply e)).1 = v ∧ d = ⟨[], [], []⟩ := by
  simp only [exec, Resp.applied.injEq] at h
  refine ⟨fstep_refused h.1, ?_⟩
  rw [← h.2, changed, h.1]
  simp

/-- An accepted fresh `console.apply` on an indexed server reports exactly the rows the event touched in
the new console state.
-/
theorem accepted_changed {v : Srv} (hv : Indexed v) {e : Event} {d : Delta}
    (h : (exec v (.apply e)).2 = .applied (.accepted false) d) :
    d = touched (exec v (.apply e)).1.st e := by
  simp only [exec, Resp.applied.injEq] at h ⊢
  have hd : d = ftouched (fstep v e).1 e := by rw [← h.2, h.1]; simp [changed]
  rw [hd]
  exact ftouched_eq (fstep_indexed hv e) e

/-- A query changes nothing and answers the board and the board plan of the current console state. -/
theorem query_keeps (v : Srv) (now seq : Nat) :
    exec v (.query now seq) = (v, .board (board v.st now seq) (Fw.Plan.view Fw.Plan.quietMs now v.st.plan)) := by
  simp [exec, fastBoard_eq, Fw.Plan.fastView_eq]

/-- The query reply is a function of the console state alone (not of the indexes or of how the state
was reached).
-/
theorem query_eq_of_st {v w : Srv} (h : v.st = w.st) (now seq : Nat) :
    (exec v (.query now seq)).2 = (exec w (.query now seq)).2 := by
  simp [exec, h]

/-- After serve calls without a reset from a fresh server, the query reply is the board and the board
plan of the projection of their events.
-/
theorem query_after_run (cs : List Cmd) (hr : ∀ c ∈ cs, c.isReset = false) (now seq : Nat) :
    (exec (run init cs) (.query now seq)).2 = .board (board (project (cs.flatMap Cmd.events)) now seq)
      (Fw.Plan.view Fw.Plan.quietMs now (project (cs.flatMap Cmd.events)).plan) := by
  simp [exec, run_init_eq_project cs hr, fastBoard_eq, Fw.Plan.fastView_eq]

#guard
  let es : List Event := [⟨"k1", 1, .owner, .cardOpen "A" "o" false⟩, ⟨"k2", 2, .owner, .cardApprove "A"⟩,
    ⟨"k3", 3, .lead, .cardApprove "A"⟩, ⟨"k3", 4, .lead, .cardApprove "A"⟩,
    ⟨"k4", 5, .owner, .runStart "R" "A" .screen⟩, ⟨"k5", 6, .script, .runFinish "R" false⟩]
  let (v, r) := exec init (.replay es)
  (match r with | .replayed t => (t.accepted, t.duplicate, t.refused) == (4, 1, 1) | _ => false)
  && v.st == project es && (run init (es.map .apply)).st == project es
  && (match (exec v (.apply ⟨"k6", 7, .owner, .cardApprove "A"⟩)).2 with
      | .applied (.refused _) d => d.cards.isEmpty | _ => false)
  && (match (exec v (.apply ⟨"k7", 8, .git, .cardBuild "A" "s" "b"⟩)).2 with
      | .applied (.accepted false) d => d.cards.map (·.head) == [some "s"] | _ => false)
  && (match (exec v (.apply ⟨"k5", 9, .script, .runFinish "R" true⟩)).2 with
      | .applied (.accepted true) d => d.runs.isEmpty | _ => false)

end Fw.Serve

/-! ## JSON glue and the IO loop (outside the math view) -/
namespace Fw.Wire.Serve
open Lean Fw.Console Fw.Serve

/-- Decode a stateful command; `none` for an op that is not stateful. A `console.apply` that carries
a `state` is the stateless op (`Fw.Wire.opConsoleApply`), so it is `none` here. A replay decodes
every event before applying any (all or nothing). -/
def cmdOf (op : String) (req : Json) : Option (Except String Cmd) :=
  match op with
  | "console.apply" =>
    if (opt req "state").isSome then none
    else some (do pure (.apply (← Fw.Wire.Plan.eventOfJson (← field req "event"))))
  | "console.replay" =>
    some (do pure (.replay (← (← arr req "events").toList.mapM Fw.Wire.Plan.eventOfJson)))
  | "console.query" => some (do pure (.query (← nat req "now") (← nat req "seq")))
  | "console.reset" => some (pure .reset)
  | _ => none

/-- Encode the changed rows. -/
def deltaJson (d : Delta) : Json := Json.mkObj [
  ("cards", .arr (d.cards.toArray.map cardJson)), ("steps", .arr (d.steps.toArray.map stepJson)),
  ("runs", .arr (d.runs.toArray.map runJson))]

/-- Encode a serve reply. -/
def respFields : Resp → Reply
  | .applied o d => [("outcome", outcomeJson o), ("changed", deltaJson d)]
  | .replayed t => [("replayed", Json.mkObj [("accepted", toJson t.accepted),
      ("duplicate", toJson t.duplicate), ("refused", toJson t.refused)])]
  | .board b p => [("board", Fw.Wire.Plan.withPlan (boardJson b) p)]
  | .reset => [("reset", .bool true)]

/-- Answer one input line against the server state: stateful ops run `exec`, every other op is the
stateless `Fw.Wire.handle`. Exactly one reply line per input line (as `Fw.Wire.handleLine`). -/
def serveLine (v : Srv) (line : String) : Srv × String :=
  let t := line.trimAscii.toString
  if t.isEmpty then (v, renderError .null "empty request") else
  match Json.parse t with
  | .error e => (v, renderError .null s!"invalid JSON: {e}")
  | .ok req =>
    match req with
    | .obj _ =>
      let id := idOf req
      match str req "op" with
      | .error e => (v, renderError id e)
      | .ok op =>
        match cmdOf op req with
        | some (.ok c) => let (v', r) := exec v c; (v', render id (respFields r))
        | some (.error e) => (v, renderError id e)
        | none =>
          match Fw.Wire.Plan.handle op req with  -- incident-lint: plan.incidentLint
          | some (.ok fields) => (v, render id fields)
          | some (.error e) => (v, renderError id e)
          | none =>
          match handle req with
          | .ok fields => (v, render id fields)
          | .error e => (v, renderError id e)
    | _ => (v, renderError .null "request must be a JSON object")

/-- Serve until end of input: the server state lives in `ref` and each line updates it with one
`modifyGet` (no copy of the state; PLAN §3.2). -/
partial def loop (ref : IO.Ref Srv) (stdin stdout : IO.FS.Stream) : IO Unit := do
  let line ← stdin.getLine
  if line.isEmpty then return            -- end of input (a blank line is "\n", not "")
  let out ← ref.modifyGet fun v => let (v', o) := serveLine v line; (o, v')
  stdout.putStrLn out
  stdout.flush
  loop ref stdin stdout

/-- Run the stateful session on the given streams, from the initial server state. -/
def main (stdin stdout : IO.FS.Stream) : IO Unit := do
  loop (← IO.mkRef init) stdin stdout

/-- Board golden cases: a name, an event log, and the `now`/`seq` of the query. -/
def boardCases : List (String × List Event × Nat × Nat) :=
  let o : List Event := [⟨"b1", 1000, .owner, .cardOpen "A" "o" false⟩]
  let ap := o ++ [⟨"b2", 1100, .lead, .cardApprove "A"⟩]
  let built := ap ++ [⟨"b3", 1200, .git, .cardBuild "A" "s1" "o"⟩]
  let screened := built ++ [⟨"b4", 1300, .script, .cardScreen "A" "s1" true⟩]
  let reviewed := screened ++ [⟨"b5", 1400, .reviewer, .cardReview "A" "s1" "r" true⟩]
  let landReq := reviewed ++ [⟨"b6", 1500, .lead, .cardLandRequest "A" "s1"⟩]
  let landed := landReq ++ [⟨"b7", 1600, .git, .cardLanded "A" "s1"⟩]
  let dev : List Event := [⟨"d1", 10, .owner, .cardOpen "D" "p" true⟩, ⟨"d2", 20, .user, .cardApprove "D"⟩,
    ⟨"d3", 30, .git, .cardBuild "D" "x" "p"⟩, ⟨"d4", 40, .script, .cardScreen "D" "x" true⟩,
    ⟨"d5", 50, .reviewer, .cardReview "D" "x" "r" true⟩]
  let steps : List Event := ap ++ [
    ⟨"s1", 2000, .script, .stepPost "S1" (some "A") "Plug in the phone" .action none⟩,
    ⟨"s2", 2100, .lead, .stepPost "S2" none "Ship it?" .yes_no none⟩,
    ⟨"s3", 2200, .owner, .stepPost "S3" (some "A") "Pick one" .choice (some ["a", "b", "c"])⟩,
    ⟨"s4", 2300, .lead, .stepPost "S4" none "Why?" .text none⟩,
    ⟨"s5", 2400, .user, .stepStart "S1"⟩]
  let stepsDone := steps ++ [⟨"s6", 2500, .user, .stepDone "S1"⟩, ⟨"s7", 2600, .user, .stepAnswer "S2" "yes"⟩,
    ⟨"s8", 2700, .lead, .stepCancel "S4"⟩]
  let runs := built ++ [⟨"r1", 3000, .script, .runStart "R1" "A" .screen⟩]
  let runsDone := runs ++ [⟨"r2", 3100, .script, .runFinish "R1" true⟩]
  [("empty board", [], 0, 0),
   ("question stage", o, 5000, 1),
   ("question stage, stale after 30 min", o, 1000 + staleMs, 1),
   ("just under stale", o, 999 + staleMs, 1),
   ("build stage", ap, 5000, 2),
   ("screen stage", built, 5000, 3),
   ("review stage", screened, 5000, 4),
   ("land_ready, no land request", reviewed, 5000, 5),
   ("land_ready, land requested", landReq, 5000, 6),
   ("landed is never stale", landed, 1600 + 10 * staleMs, 7),
   ("device stage", dev, 100, 5),
   ("device card stale", dev, 50 + staleMs, 5),
   ("open steps: needs you", steps, 3000, 7),
   ("open step blocks stale", steps, 2400 + 2 * staleMs, 7),
   ("finished steps", stepsDone, 3000, 10),
   ("running run blocks stale", runs, 3000 + 2 * staleMs, 4),
   ("finished run, stale", runsDone, 3100 + staleMs, 5),
   ("two cards", o ++ dev, 5000, 6),
   ("clock before lastAt (truncated subtraction)", built, 0, 3)]

/-- Encode an event in the flat command form of `events.jsonl` (`seq` omitted). -/
def eventJson (e : Event) : Json :=
  let b : List (String × Json) := match e.body with
    | .cardOpen c o d => [("card", .str c), ("owner", .str o), ("needsDevice", .bool d)]
    | .cardApprove c => [("card", .str c)]
    | .cardBuild c s a => [("card", .str c), ("sha", .str s), ("agent", .str a)]
    | .cardScreen c s p => [("card", .str c), ("sha", .str s), ("pass", .bool p)]
    | .cardReview c s by_ acc => [("card", .str c), ("sha", .str s), ("signedBy", .str by_), ("accept", .bool acc)]
    | .cardSwipe c s b => [("card", .str c), ("sha", .str s), ("better", .bool b)]
    | .cardLandRequest c s => [("card", .str c), ("sha", .str s)]
    | .cardLanded c s => [("card", .str c), ("sha", .str s)]
    | .stepPost s c t k os a b => [("step", .str s), ("card", ostr c), ("title", .str t),
        ("kind", .str (stepKindName k)), ("options", optStrs os), ("audience", .str a.name), ("body", .str b)]
    | .stepStart s => [("step", .str s)]
    | .stepAnswer s a => [("step", .str s), ("answer", .str a)]
    | .stepDone s n => [("step", .str s), ("note", ostr n)]
    | .stepCancel s => [("step", .str s)]
    | .runStart r c k => [("run", .str r), ("card", .str c), ("kind", .str (runKindName k))]
    | .runFinish r ok => [("run", .str r), ("ok", .bool ok)]
    | .plan c => Fw.Wire.Plan.cmdFields c
  Json.mkObj ([("key", .str e.key), ("ts", toJson e.ts), ("type", .str e.body.type.name),
    ("actor", .str e.actor.name)] ++ b)

/-- The board golden file (`console-board.jsonl`), one case per line: `name`, `events` (the log),
`request` (`state` = the projection of the log, `now`, `seq`) and `response` (`board`). -/
def boardGolden (_ : Unit := ()) : List String :=
  boardCases.map fun (name, es, now, seq) =>
    let s := project es
    (Json.mkObj [("name", .str name), ("events", .arr (es.toArray.map eventJson)),
      ("request", Json.mkObj [("state", stateJson s), ("now", toJson now), ("seq", toJson seq)]),
      ("response", Json.mkObj [("board", boardJson (board s now seq))])]).compress

end Fw.Wire.Serve
