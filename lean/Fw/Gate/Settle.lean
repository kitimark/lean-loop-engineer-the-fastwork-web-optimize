import Lean.Data.Json
/-! Gate settle decisions: the wait, the report and the golden vectors for the Node twin. -/
namespace Fw.Gate.Settle
open Lean

/-- One observation of a page arm while the gate waits. -/
structure Obs where
  running : Nat
  frames : Nat
  stable : Nat
  hoverInside : Bool
  t : Nat
  deriving DecidableEq, Repr

/-- The wait policy: frames, quiet run, eps (millionths), time and frame budget. -/
structure Policy where
  minFrames : Nat
  minStable : Nat
  eps : Nat
  timeoutMs : Nat
  maxFrames : Nat
  deriving DecidableEq, Repr

/-- The policy the gate uses. -/
def gatePolicy : Policy := { minFrames := 2, minStable := 3, eps := 100, timeoutMs := 30000, maxFrames := 60 }

/-- Nothing animates, enough real frames, enough quiet frames, pointer not in a hover target. -/
def settled (p : Policy) (o : Obs) : Bool :=
  o.running == 0 && decide (p.minFrames ≤ o.frames) && decide (p.minStable ≤ o.stable) && !o.hoverInside

def sampleOk (p : Policy) (o : Obs) : Bool := settled p o

inductive Outcome where
  | settled (at_ : Nat)
  | unsettled
  deriving DecidableEq, Repr

/-- The time or the frame budget is spent at an observation. -/
def spent (p : Policy) (o : Obs) : Bool := decide (p.timeoutMs < o.t) || decide (p.maxFrames < o.frames)

def scan (p : Policy) (o : Nat → Obs) : Nat → Nat → Outcome
  | _, 0 => .unsettled
  | i, f + 1 =>
    if spent p (o i) then .unsettled
    else if settled p (o i) then .settled i
    else scan p o (i + 1) f

/-- The first settled observation inside the budget, else `unsettled`. -/
def wait (p : Policy) (o : Nat → Obs) : Outcome := scan p o 0 (p.timeoutMs + 1)

inductive Report where
  | pass
  | fail
  | unsettled
  deriving DecidableEq, Repr

/-- `pass`/`fail` only when both arms settled, else `unsettled`. -/
def report : Outcome → Outcome → Bool → Report
  | .settled _, .settled _, true => .pass
  | .settled _, .settled _, false => .fail
  | _, _, _ => .unsettled

theorem spent_false_iff (p : Policy) (o : Obs) :
    spent p o = false ↔ o.t ≤ p.timeoutMs ∧ o.frames ≤ p.maxFrames := by
  simp only [spent, Bool.or_eq_false_iff, decide_eq_false_iff_not, Nat.not_lt]

theorem scan_sound (p : Policy) (o : Nat → Obs) :
    ∀ f i k, scan p o i f = .settled k →
      settled p (o k) = true ∧ (o k).t ≤ p.timeoutMs ∧ (o k).frames ≤ p.maxFrames ∧ i ≤ k := by
  intro f
  induction f with
  | zero => intro i k h; simp [scan] at h
  | succ f ih =>
    intro i k h
    simp only [scan] at h
    cases h1 : spent p (o i)
    · have hb := (spent_false_iff p (o i)).1 h1
      by_cases h2 : settled p (o i) = true
      · simp [h1, h2] at h
        subst h
        exact ⟨h2, hb.1, hb.2, Nat.le_refl _⟩
      · simp [h1, h2] at h
        obtain ⟨a, b, c, d⟩ := ih (i + 1) k h
        exact ⟨a, b, c, by omega⟩
    · simp [h1] at h

theorem wait_sound (p : Policy) (o : Nat → Obs) (k : Nat) (h : wait p o = .settled k) :
    settled p (o k) = true ∧ (o k).t ≤ p.timeoutMs ∧ (o k).frames ≤ p.maxFrames := by
  obtain ⟨a, b, c, _⟩ := scan_sound p o _ _ _ h
  exact ⟨a, b, c⟩

theorem scan_unsettled_of_never (p : Policy) (o : Nat → Obs) (never : ∀ i, settled p (o i) = false) :
    ∀ f i, scan p o i f = .unsettled := by
  intro f
  induction f with
  | zero => intro i; simp [scan]
  | succ f ih =>
    intro i
    simp only [scan]
    cases h1 : spent p (o i)
    · simp [never i]
      exact ih (i + 1)
    · simp

theorem wait_unsettled_of_never (p : Policy) (o : Nat → Obs) (never : ∀ i, settled p (o i) = false) :
    wait p o = .unsettled :=
  scan_unsettled_of_never p o never _ _

theorem mono_le (g : Nat → Nat) (h : ∀ n, g n ≤ g (n + 1)) (i j : Nat) (hij : i ≤ j) : g i ≤ g j := by
  have : ∀ d, g i ≤ g (i + d) := by
    intro d
    induction d with
    | zero => exact Nat.le_refl _
    | succ d ihd => exact Nat.le_trans ihd (h (i + d))
  have h2 := this (j - i)
  rwa [show i + (j - i) = j by omega] at h2

theorem scan_complete (p : Policy) (o : Nat → Obs) (tmono : ∀ n, (o n).t ≤ (o (n + 1)).t)
    (fmono : ∀ n, (o n).frames ≤ (o (n + 1)).frames) :
    ∀ f i j, i ≤ j → j < i + f → settled p (o j) = true → (o j).t ≤ p.timeoutMs → (o j).frames ≤ p.maxFrames →
      ∃ k, scan p o i f = .settled k ∧ i ≤ k ∧ k ≤ j := by
  intro f
  induction f with
  | zero => intro i j _ hj; omega
  | succ f ih =>
    intro i j hij hjf hs ht hfr
    simp only [scan]
    have hti := mono_le (fun n => (o n).t) tmono i j hij
    have hfi := mono_le (fun n => (o n).frames) fmono i j hij
    have h1 : spent p (o i) = false := (spent_false_iff p (o i)).2 ⟨by omega, by omega⟩
    by_cases h2 : settled p (o i) = true
    · exact ⟨i, by simp [h1, h2], Nat.le_refl _, hij⟩
    · by_cases hji : j = i
      · subst hji; exact absurd hs h2
      · obtain ⟨k, hk, hk1, hk2⟩ := ih (i + 1) j (by omega) (by omega) hs ht hfr
        exact ⟨k, by simp [h1, h2, hk], by omega, hk2⟩

theorem wait_complete (p : Policy) (o : Nat → Obs) (tmono : ∀ n, (o n).t ≤ (o (n + 1)).t)
    (fmono : ∀ n, (o n).frames ≤ (o (n + 1)).frames) (j : Nat)
    (hj : j ≤ p.timeoutMs) (hs : settled p (o j) = true) (ht : (o j).t ≤ p.timeoutMs) (hf : (o j).frames ≤ p.maxFrames) :
    ∃ k, wait p o = .settled k ∧ k ≤ j := by
  obtain ⟨k, hk, _, hk2⟩ := scan_complete p o tmono fmono (p.timeoutMs + 1) 0 j (by omega) (by omega) hs ht hf
  exact ⟨k, hk, hk2⟩

theorem unsettled_never_pass (a b : Outcome) (e : Bool) (h : a = .unsettled ∨ b = .unsettled) :
    report a b e ≠ .pass := by
  rcases a with _ | _ <;> rcases b with _ | _ <;> cases e <;> simp [report] at h ⊢

theorem unsettled_never_fail (a b : Outcome) (e : Bool) (h : a = .unsettled ∨ b = .unsettled) :
    report a b e = .unsettled := by
  rcases a with _ | _ <;> rcases b with _ | _ <;> cases e <;> simp [report] at h ⊢

theorem report_decided_settled (a b : Outcome) (e : Bool) (h : report a b e ≠ .unsettled) :
    ∃ i j, a = .settled i ∧ b = .settled j := by
  rcases a with i | _ <;> rcases b with j | _ <;> cases e <;> simp [report] at h ⊢

theorem report_settled (i j : Nat) (e : Bool) :
    report (.settled i) (.settled j) e = (if e then .pass else .fail) := by
  cases e <;> rfl

def withBudget (p : Policy) (F : Nat) : Policy := { p with maxFrames := F }

theorem settled_withBudget (p : Policy) (F : Nat) (o : Obs) : settled (withBudget p F) o = settled p o := rfl

theorem scan_budget_cases (p : Policy) (o : Nat → Obs) (F : Nat) (hF : F ≤ p.maxFrames) :
    ∀ f i, scan (withBudget p F) o i f = scan p o i f ∨ scan (withBudget p F) o i f = .unsettled := by
  intro f
  induction f with
  | zero => intro i; simp [scan]
  | succ f ih =>
    intro i
    simp only [scan, settled_withBudget]
    by_cases h1 : spent (withBudget p F) (o i) = true
    · simp [h1]
    · have hb := (spent_false_iff _ (o i)).1 (by simpa using h1)
      have h0 : spent p (o i) = false := (spent_false_iff p (o i)).2 ⟨hb.1, Nat.le_trans hb.2 hF⟩
      by_cases h2 : settled p (o i) = true
      · simp [h1, h0, h2]
      · have h1' : spent (withBudget p F) (o i) = false := by simpa using h1
        simp only [h1', h0, h2, Bool.false_eq_true, ite_false]
        exact ih (i + 1)

theorem wait_budget_cases (p : Policy) (o : Nat → Obs) (F : Nat) (hF : F ≤ p.maxFrames) :
    wait (withBudget p F) o = wait p o ∨ wait (withBudget p F) o = .unsettled :=
  scan_budget_cases p o F hF _ _

theorem scan_budget_keeps (p : Policy) (o : Nat → Obs) (F : Nat) (fmono : ∀ n, (o n).frames ≤ (o (n + 1)).frames) :
    ∀ f i k, scan p o i f = .settled k → (o k).frames ≤ F → scan (withBudget p F) o i f = .settled k := by
  intro f
  induction f with
  | zero => intro i k h; simp [scan] at h
  | succ f ih =>
    intro i k h hk
    have hik := (scan_sound p o (f + 1) i k h).2.2.2
    have hfi := mono_le (fun n => (o n).frames) fmono i k hik
    simp only [scan, settled_withBudget] at h ⊢
    by_cases h1 : spent p (o i) = true
    · simp [h1] at h
    · have h1' : spent p (o i) = false := by simpa using h1
      have hb := (spent_false_iff p (o i)).1 h1'
      have h0 : spent (withBudget p F) (o i) = false :=
        (spent_false_iff (withBudget p F) (o i)).2 ⟨hb.1, Nat.le_trans hfi hk⟩
      by_cases h2 : settled p (o i) = true
      · simp only [h1', h2, Bool.false_eq_true, ite_false, ite_true] at h
        simp only [h0, h2, Bool.false_eq_true, ite_false, ite_true]
        exact h
      · simp only [h1', h2, Bool.false_eq_true, ite_false] at h
        simp only [h0, h2, Bool.false_eq_true, ite_false]
        exact ih (i + 1) k h hk

theorem wait_budget_keeps (p : Policy) (o : Nat → Obs) (F k : Nat) (fmono : ∀ n, (o n).frames ≤ (o (n + 1)).frames)
    (h : wait p o = .settled k) (hk : (o k).frames ≤ F) : wait (withBudget p F) o = .settled k :=
  scan_budget_keeps p o F fmono _ _ _ h hk

theorem report_budget (p : Policy) (F : Nat) (hF : F ≤ p.maxFrames) (oa ob : Nat → Obs) (e : Bool) :
    report (wait (withBudget p F) oa) (wait (withBudget p F) ob) e = report (wait p oa) (wait p ob) e ∨
      report (wait (withBudget p F) oa) (wait (withBudget p F) ob) e = .unsettled := by
  rcases wait_budget_cases p oa F hF with ha | ha <;> rcases wait_budget_cases p ob F hF with hb | hb
  · exact Or.inl (by rw [ha, hb])
  · exact Or.inr (unsettled_never_fail _ _ e (Or.inr hb))
  · exact Or.inr (unsettled_never_fail _ _ e (Or.inl ha))
  · exact Or.inr (unsettled_never_fail _ _ e (Or.inl ha))

theorem scan_decided_by (p : Policy) (o o' : Nat → Obs) (n : Nat) (hs : spent p (o n) = true) :
    ∀ f i, i ≤ n → (∀ m, i ≤ m → m ≤ n → o m = o' m) → scan p o i f = scan p o' i f := by
  intro f
  induction f with
  | zero => intro i _ _; simp [scan]
  | succ f ih =>
    intro i hi hag
    have he : o i = o' i := hag i (Nat.le_refl _) hi
    by_cases hin : i = n
    · subst hin
      have h' : spent p (o' i) = true := he ▸ hs
      simp [scan, hs, h']
    · have hr := ih (i + 1) (by omega) (fun m h1 h2 => hag m (by omega) h2)
      simp only [scan, he, hr]

theorem wait_stops_by_frames (p : Policy) (o o' : Nat → Obs) (hfr : ∀ i, i ≤ (o i).frames)
    (hag : ∀ m, m ≤ p.maxFrames + 1 → o m = o' m) : wait p o = wait p o' := by
  have hs : spent p (o (p.maxFrames + 1)) = true := by
    have := hfr (p.maxFrames + 1)
    simp only [spent, Bool.or_eq_true, decide_eq_true_eq]
    exact Or.inr (by omega)
  exact scan_decided_by p o o' (p.maxFrames + 1) hs _ 0 (by omega) (fun m _ h => hag m h)

/-- The mount stage's idle wait: nothing runs, under the arm's cap and the frame budget. -/
def idlePolicy (p : Policy) (c : Nat) : Policy := { p with minFrames := 0, minStable := 0, timeoutMs := c }

theorem idle_settled_iff (p : Policy) (c : Nat) (o : Obs) :
    settled (idlePolicy p c) o = true ↔ o.running = 0 ∧ o.hoverInside = false := by
  simp [settled, idlePolicy]

def fold1 (a w : Outcome) : Outcome := if a = .unsettled ∨ w = .unsettled then .unsettled else a

/-- A sample is unsettled when any of its waits is. -/
def fold (first : Outcome) (extra : List Outcome) : Outcome := extra.foldl fold1 first

theorem fold_unsettled_start : ∀ ws : List Outcome, fold .unsettled ws = .unsettled := by
  intro ws
  induction ws with
  | nil => rfl
  | cons w ws ih => simpa [fold, List.foldl, fold1] using ih

theorem fold_unsettled (a : Outcome) (ws : List Outcome) (h : a = .unsettled ∨ Outcome.unsettled ∈ ws) :
    fold a ws = .unsettled := by
  induction ws generalizing a with
  | nil =>
    rcases h with h | h
    · subst h; rfl
    · simp at h
  | cons w ws ih =>
    simp only [fold, List.foldl]
    rcases h with h | h
    · subst h; exact fold_unsettled_start (w :: ws)
    · rcases List.mem_cons.1 h with h | h
      · subst h
        have h1 : fold1 a .unsettled = .unsettled := by simp [fold1]
        rw [h1]; exact fold_unsettled_start ws
      · exact ih (fold1 a w) (Or.inr h)

theorem fold_settled (a : Outcome) (ws : List Outcome) (ha : a ≠ .unsettled) (h : Outcome.unsettled ∉ ws) :
    fold a ws = a := by
  induction ws with
  | nil => rfl
  | cons w ws ih =>
    simp only [fold, List.foldl]
    have hw : w ≠ .unsettled := fun e => h (e ▸ List.mem_cons_self ..)
    have h1 : fold1 a w = a := by simp [fold1, ha, hw]
    rw [h1]
    exact ih (fun e => h (List.mem_cons_of_mem _ e))

theorem fold_unsettled_never_pass (a : Outcome) (ws : List Outcome) (b : Outcome) (e : Bool)
    (h : Outcome.unsettled ∈ ws) : report (fold a ws) b e ≠ .pass :=
  unsettled_never_pass _ _ e (Or.inl (fold_unsettled a ws (Or.inr h)))

#guard fold (.settled 2) [.settled 0, .settled 5] == .settled 2
#guard fold (.settled 2) [.settled 0, .unsettled] == .unsettled
#guard fold .unsettled [] == .unsettled
#guard settled (idlePolicy gatePolicy 20000) { running := 0, frames := 0, stable := 0, hoverInside := false, t := 0 } == true
#guard settled (idlePolicy gatePolicy 20000) { running := 2, frames := 9, stable := 9, hoverInside := false, t := 10 } == false

/-- No ancestor (itself included) skips its subtree. -/
def rendered (skips : List Bool) : Bool := !skips.any id

inductive Verdict where
  | notRendered
  | unsettled
  | ok
  deriving DecidableEq, Repr

def classify (p : Policy) (r : Bool) (o : Obs) : Verdict :=
  if r then (if sampleOk p o then .ok else .unsettled) else .notRendered

inductive Cell where
  | pass
  | fail
  | unsettled
  | notRendered
  deriving DecidableEq, Repr

/-- `notRendered` when the node is not rendered in either arm, else `report`. -/
def cell (ra rb : Bool) (a b : Outcome) (e : Bool) : Cell :=
  if ra && rb then
    match report a b e with
    | .pass => .pass
    | .fail => .fail
    | .unsettled => .unsettled
  else .notRendered

def Cell.passes : Cell → Bool
  | .pass => true
  | _ => false

theorem Cell.passes_iff (c : Cell) : c.passes = true ↔ c = .pass := by
  cases c <;> simp [Cell.passes]

theorem skipped_classified_notRendered (p : Policy) (skips : List Bool) (o : Obs) (h : true ∈ skips) :
    classify p (rendered skips) o = .notRendered := by
  have : (skips.any id) = true := List.any_eq_true.mpr ⟨true, h, rfl⟩
  simp [classify, rendered, this]

theorem classify_rendered_ok (p : Policy) (o : Obs) : classify p true o = .ok ↔ sampleOk p o = true := by
  unfold classify
  by_cases h : sampleOk p o = true <;> simp [h]

theorem notRendered_never_pass (ra rb : Bool) (a b : Outcome) (e : Bool) (h : ra = false ∨ rb = false) :
    cell ra rb a b e ≠ .pass := by
  rcases h with h | h <;> simp [cell, h]

theorem notRendered_never_fail (ra rb : Bool) (a b : Outcome) (e : Bool) (h : ra = false ∨ rb = false) :
    cell ra rb a b e = .notRendered := by
  rcases h with h | h <;> simp [cell, h]

theorem cell_rendered (a b : Outcome) (e : Bool) :
    (cell true true a b e = .pass ↔ report a b e = .pass) ∧ (cell true true a b e = .fail ↔ report a b e = .fail)
    ∧ (cell true true a b e = .unsettled ↔ report a b e = .unsettled) := by
  cases h : report a b e <;> simp [cell, h]

theorem cell_decided (ra rb : Bool) (a b : Outcome) (e : Bool) (h : cell ra rb a b e = .pass ∨ cell ra rb a b e = .fail) :
    ra = true ∧ rb = true ∧ ∃ i j, a = .settled i ∧ b = .settled j := by
  rcases ra with _ | _ <;> rcases rb with _ | _ <;> simp [cell] at h ⊢
  rcases a with i | _ <;> rcases b with j | _ <;> cases e <;> simp [report] at h ⊢

structure Reading (α : Type) where
  skipped : Bool
  val : α
  deriving Repr

/-- The reading the gate keeps for a node. -/
def view {α : Type} (bring : Bool) (first again : Reading α) : Reading α := if bring then again else first

def Covered {α : Type} (bring : Bool) (first : Reading α) : Prop := first.skipped = true → bring = true

/-- The cell of one node from the two arms' first and second readings. -/
def viewCell {α : Type} [DecidableEq α] (bo br : Bool) (fo go fr gr : Reading α) (a b : Outcome) : Cell :=
  cell (!(view bo fo go).skipped) (!(view br fr gr).skipped) a b (decide ((view bo fo go).val = (view br fr gr).val))

theorem view_bring {α : Type} (f g : Reading α) : view true f g = g := by simp [view]

theorem viewCell_inert {α : Type} [DecidableEq α] (fo go fr gr : Reading α) (a b : Outcome) :
    viewCell false false fo go fr gr a b = cell (!fo.skipped) (!fr.skipped) a b (decide (fo.val = fr.val)) := by
  simp [viewCell, view]

theorem viewCell_notRendered_iff {α : Type} [DecidableEq α] (bo br : Bool) (fo go fr gr : Reading α) (a b : Outcome) :
    viewCell bo br fo go fr gr a b = .notRendered ↔ (view bo fo go).skipped = true ∨ (view br fr gr).skipped = true := by
  unfold viewCell cell
  rcases h1 : (view bo fo go).skipped <;> rcases h2 : (view br fr gr).skipped <;> simp <;>
    cases report a b _ <;> simp

theorem skipped_after_view_only_if_brought {α : Type} (bring : Bool) (f g : Reading α) (hc : Covered bring f)
    (h : (view bring f g).skipped = true) : bring = true ∧ g.skipped = true := by
  cases bring
  · exact absurd (hc (by simpa [view] using h)) (by simp)
  · exact ⟨rfl, by simpa [view] using h⟩

theorem viewCell_fail_of_rendered_diff {α : Type} [DecidableEq α] (bo br : Bool) (fo go fr gr : Reading α) (i j : Nat)
    (ho : (view bo fo go).skipped = false) (hr : (view br fr gr).skipped = false)
    (hd : (view bo fo go).val ≠ (view br fr gr).val) :
    viewCell bo br fo go fr gr (.settled i) (.settled j) = .fail := by
  simp [viewCell, cell, ho, hr, hd, report]

theorem viewCell_pass_sound {α : Type} [DecidableEq α] (bo br : Bool) (fo go fr gr : Reading α) (a b : Outcome)
    (h : viewCell bo br fo go fr gr a b = .pass) :
    (view bo fo go).skipped = false ∧ (view br fr gr).skipped = false ∧ (view bo fo go).val = (view br fr gr).val
      ∧ ∃ i j, a = .settled i ∧ b = .settled j := by
  obtain ⟨h1, h2, i, j, ha, hb⟩ := cell_decided _ _ a b _ (Or.inl h)
  have h1' : (view bo fo go).skipped = false := by simpa using h1
  have h2' : (view br fr gr).skipped = false := by simpa using h2
  subst ha hb
  refine ⟨h1', h2', ?_, i, j, rfl, rfl⟩
  cases hd : decide ((view bo fo go).val = (view br fr gr).val)
  · simp [viewCell, cell, report, h1', h2', hd] at h
  · simpa using hd

inductive ViewEngine where
  | chromium
  | webkit
  deriving DecidableEq, Repr

def engineOf (n : String) : Option ViewEngine :=
  if n = "chromium" then some .chromium else if n = "playwright-webkit" then some .webkit else none

def viewOn : ViewEngine → Bool
  | .chromium => true
  | .webkit => false

/-- Whether an engine's probes bring a skipped part into view and read it again. -/
def viewFor (s : Option String) (n : String) : Bool :=
  match s with
  | some "1" => true
  | some "0" => false
  | _ => (engineOf n).any viewOn

theorem viewFor_default : viewFor none "chromium" = true ∧ viewFor none "playwright-webkit" = false := by
  decide

theorem viewFor_switch (n : String) : viewFor (some "1") n = true ∧ viewFor (some "0") n = false := by
  simp [viewFor]

theorem viewFor_other (s n : String) (h1 : s ≠ "1") (h0 : s ≠ "0") : viewFor (some s) n = viewFor none n := by
  simp [viewFor, h1, h0]

theorem viewFor_unknown (n : String) (h : engineOf n = none) : viewFor none n = false := by
  simp [viewFor, h]

theorem viewCell_webkit_default {α : Type} [DecidableEq α] (fo go fr gr : Reading α) (a b : Outcome) :
    viewCell (viewFor none "playwright-webkit") (viewFor none "playwright-webkit") fo go fr gr a b =
      cell (!fo.skipped) (!fr.skipped) a b (decide (fo.val = fr.val)) := by
  rw [viewFor_default.2]
  exact viewCell_inert fo go fr gr a b

structure Traj (p : Policy) (α : Type) where
  obs : Nat → Obs
  props : Nat → α
  running_mono : ∀ n, (obs (n + 1)).running ≤ (obs n).running
  frames_succ : ∀ n, (obs (n + 1)).frames = (obs n).frames + 1
  hover_const : ∀ n, (obs (n + 1)).hoverInside = (obs n).hoverInside
  stable_succ : ∀ n, props (n + 1) = props n → (obs (n + 1)).stable = (obs n).stable + 1
  quiet : ∀ n, settled p (obs n) = true → props (n + 1) = props n

theorem Traj.settled_succ {p : Policy} {α : Type} (T : Traj p α) (n : Nat) (h : settled p (T.obs n) = true) :
    settled p (T.obs (n + 1)) = true ∧ T.props (n + 1) = T.props n := by
  have hq := T.quiet n h
  have hr := T.running_mono n
  have hf := T.frames_succ n
  have hh := T.hover_const n
  have hs := T.stable_succ n hq
  refine ⟨?_, hq⟩
  simp only [settled, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq, Bool.not_eq_true'] at h ⊢
  obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := h
  refine ⟨⟨⟨by omega, by omega⟩, by omega⟩, by rw [hh]; exact h4⟩

theorem Traj.settled_after {p : Policy} {α : Type} (T : Traj p α) (i : Nat) (h : settled p (T.obs i) = true) :
    ∀ k, settled p (T.obs (i + k)) = true ∧ T.props (i + k) = T.props i := by
  intro k
  induction k with
  | zero => exact ⟨h, rfl⟩
  | succ k ih =>
    obtain ⟨h1, h2⟩ := T.settled_succ (i + k) ih.1
    exact ⟨h1, h2.trans ih.2⟩

theorem sample_delay_invariant {p : Policy} {α : Type} (T : Traj p α) (i j : Nat)
    (hi : settled p (T.obs i) = true) (hj : settled p (T.obs j) = true) : T.props i = T.props j := by
  rcases Nat.le_total i j with hij | hji
  · obtain ⟨_, h2⟩ := T.settled_after i hi (j - i)
    rw [show i + (j - i) = j by omega] at h2
    exact h2.symm
  · obtain ⟨_, h2⟩ := T.settled_after j hj (i - j)
    rw [show j + (i - j) = i by omega] at h2
    exact h2

theorem pain_notes_unsettled (p : Policy) (o : Obs) (h : o.frames < p.minFrames) : settled p o = false := by
  simp only [settled]
  have : ¬ p.minFrames ≤ o.frames := by omega
  simp [this]

theorem pain_notes_wait_unsettled (p : Policy) (o : Nat → Obs) (h : ∀ i, (o i).frames < p.minFrames) :
    wait p o = .unsettled :=
  wait_unsettled_of_never p o (fun i => pain_notes_unsettled p (o i) (h i))

theorem hero_orbit_unsettled (p : Policy) (o : Obs) (h : o.hoverInside = true) : settled p o = false := by
  simp [settled, h]

def park (o : Obs) : Obs := { o with hoverInside := false }

theorem park_settled_iff (p : Policy) (o : Obs) :
    settled p (park o) = true ↔ (o.running = 0 ∧ p.minFrames ≤ o.frames ∧ p.minStable ≤ o.stable) := by
  unfold settled park
  by_cases h1 : o.running = 0 <;> by_cases h2 : p.minFrames ≤ o.frames <;> by_cases h3 : p.minStable ≤ o.stable <;>
    simp [h1, h2, h3]

structure Anim where
  dur : Nat
  elapsed : Nat
  onDocument : Bool := true
  deriving DecidableEq, Repr

/-- Finite animations on the document timeline that have not run their duration. -/
def runCount (as : List Anim) : Nat := (as.filter (fun a => a.onDocument && decide (a.elapsed < a.dur))).length

def runCountAll (as : List Anim) : Nat := (as.filter (fun a => decide (a.elapsed < a.dur))).length

theorem signup_unsettled (p : Policy) (as : List Anim) (a : Anim) (ha : a ∈ as) (he : a.elapsed < a.dur)
    (hd : a.onDocument = true)
    (frames stable t : Nat) (hov : Bool) :
    settled p { running := runCount as, frames := frames, stable := stable, hoverInside := hov, t := t } = false := by
  have hpos : 0 < runCount as := by
    unfold runCount
    apply List.length_pos_of_mem (a := a)
    simp [List.mem_filter, ha, he, hd]
  simp only [settled]
  have : ¬ runCount as = 0 := by omega
  simp [this]

theorem runCount_document (as : List Anim) (h : ∀ a ∈ as, a.onDocument = true) : runCount as = runCountAll as := by
  unfold runCount runCountAll
  congr 1
  apply List.filter_congr
  intro a ha
  simp [h a ha]

theorem runCount_cons_scroll (a : Anim) (as : List Anim) (h : a.onDocument = false) : runCount (a :: as) = runCount as := by
  simp [runCount, h]

theorem runCount_cons_document (a : Anim) (as : List Anim) (h : a.onDocument = true) :
    runCount (a :: as) = runCount as + (if a.elapsed < a.dur then 1 else 0) := by
  by_cases he : a.elapsed < a.dur <;> simp [runCount, h, he]

theorem settled_cons_scroll (p : Policy) (a : Anim) (as : List Anim) (h : a.onDocument = false) (frames stable t : Nat) (hov : Bool) :
    settled p { running := runCount (a :: as), frames := frames, stable := stable, hoverInside := hov, t := t }
      = settled p { running := runCount as, frames := frames, stable := stable, hoverInside := hov, t := t } := by
  rw [runCount_cons_scroll a as h]

theorem runCount_zero_of_scroll_or_done (as : List Anim) (h : ∀ a ∈ as, a.onDocument = false ∨ a.dur ≤ a.elapsed) :
    runCount as = 0 := by
  unfold runCount
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro a ha
  rcases h a ha with h1 | h2
  · simp [h1]
  · have : ¬ a.elapsed < a.dur := by omega
    simp [this]

theorem runCountAll_scroll_blocks (p : Policy) (a : Anim) (as : List Anim) (ha : a ∈ as) (he : a.elapsed < a.dur)
    (frames stable t : Nat) (hov : Bool) :
    settled p { running := runCountAll as, frames := frames, stable := stable, hoverInside := hov, t := t } = false := by
  have hpos : 0 < runCountAll as := by
    unfold runCountAll
    apply List.length_pos_of_mem (a := a)
    simp [List.mem_filter, ha, he]
  simp only [settled]
  have : ¬ runCountAll as = 0 := by omega
  simp [this]

theorem scroll_cannot_block (p : Policy) (as : List Anim) (h : ∀ a ∈ as, a.onDocument = false ∨ a.dur ≤ a.elapsed)
    (frames stable t : Nat) (hf : p.minFrames ≤ frames) (hs : p.minStable ≤ stable) :
    settled p { running := runCount as, frames := frames, stable := stable, hoverInside := false, t := t } = true := by
  simp [settled, runCount_zero_of_scroll_or_done as h, hf, hs]

theorem signup_enter_finished (e : Nat) : runCount [{ dur := 400, elapsed := e }] = 0 ↔ 400 ≤ e := by
  unfold runCount
  by_cases h : e < 400 <;> simp [h] <;> omega

/-- Same number of values, each moved by at most `eps` (millionths). -/
def quiet (eps : Nat) (u v : List Int) : Bool :=
  u.length == v.length && (List.zipWith (fun a b => decide ((a - b).natAbs ≤ eps)) u v).all id

def nextStable (eps : Nat) (s : Nat) (u v : List Int) : Nat := if quiet eps u v then s + 1 else 0

theorem quiet_refl (eps : Nat) (u : List Int) : quiet eps u u = true := by
  induction u with
  | nil => simp [quiet]
  | cons x xs ih =>
    simp only [quiet, List.length_cons, beq_self_eq_true, Bool.true_and, List.zipWith_cons_cons, List.all_cons] at ih ⊢
    simp

theorem quiet_length (eps : Nat) (u v : List Int) (h : u.length ≠ v.length) : quiet eps u v = false := by
  simp [quiet, h]

theorem moving_not_quiet (eps : Nat) (s : Nat) (x y : Int) (h : eps < (x - y).natAbs) :
    quiet eps [x] [y] = false ∧ nextStable eps s [x] [y] = 0 := by
  have : quiet eps [x] [y] = false := by
    simp [quiet]; omega
  exact ⟨this, by simp [nextStable, this]⟩

theorem lerp_moving_unsettled (p : Policy) (s : Nat) (x y : Int) (h : p.eps < (x - y).natAbs) (hm : 1 ≤ p.minStable)
    (running frames t : Nat) (hov : Bool) :
    settled p { running := running, frames := frames, stable := nextStable p.eps s [x] [y], hoverInside := hov, t := t } = false := by
  obtain ⟨_, h2⟩ := moving_not_quiet p.eps s x y h
  simp only [settled]
  rw [h2]
  have : ¬ p.minStable ≤ 0 := by omega
  simp [this]

structure Lerp where
  x : Nat → Int
  target : Int
  a : Nat
  b : Nat
  pos : 0 < a
  step : ∀ n, (b : Int) * (x (n + 1) - x n) = (a : Int) * (target - x n)

theorem Lerp.quiet_near (L : Lerp) (eps n : Nat) (h : (L.x (n + 1) - L.x n).natAbs ≤ eps) :
    L.a * (L.target - L.x n).natAbs ≤ eps * L.b := by
  have h1 := L.step n
  have h2 : (↑L.b * (L.x (n + 1) - L.x n)).natAbs = (↑L.a * (L.target - L.x n)).natAbs := by rw [h1]
  rw [Int.natAbs_mul, Int.natAbs_mul] at h2
  simp only [Int.natAbs_natCast] at h2
  rw [← h2]
  calc L.b * (L.x (n + 1) - L.x n).natAbs ≤ L.b * eps := Nat.mul_le_mul_left _ h
    _ = eps * L.b := Nat.mul_comm _ _

theorem Lerp.sample_delay_invariant (L : Lerp) (eps i j : Nat)
    (hi : (L.x (i + 1) - L.x i).natAbs ≤ eps) (hj : (L.x (j + 1) - L.x j).natAbs ≤ eps) :
    L.a * (L.x i - L.x j).natAbs ≤ 2 * (eps * L.b) := by
  have h1 := L.quiet_near eps i hi
  have h2 := L.quiet_near eps j hj
  have h3 : (L.x i - L.x j).natAbs ≤ (L.target - L.x i).natAbs + (L.target - L.x j).natAbs := by omega
  calc L.a * (L.x i - L.x j).natAbs ≤ L.a * ((L.target - L.x i).natAbs + (L.target - L.x j).natAbs) :=
        Nat.mul_le_mul_left _ h3
    _ = L.a * (L.target - L.x i).natAbs + L.a * (L.target - L.x j).natAbs := Nat.mul_add _ _ _
    _ ≤ 2 * (eps * L.b) := by omega

def scrollSig (fs : List (Int → Int)) (o : Int) : List Int := fs.map (fun f => f o)

theorem scroll_fixed_quiet (eps : Nat) (fs : List (Int → Int)) (o₁ o₂ : Int) (h : o₁ = o₂) :
    quiet eps (scrollSig fs o₁) (scrollSig fs o₂) = true := by
  subst h
  exact quiet_refl eps _

theorem scroll_fixed_nextStable (eps s : Nat) (fs : List (Int → Int)) (o₁ o₂ : Int) (h : o₁ = o₂) :
    nextStable eps s (scrollSig fs o₁) (scrollSig fs o₂) = s + 1 := by
  simp [nextStable, scroll_fixed_quiet eps fs o₁ o₂ h]

def obsJson (o : Obs) : Json :=
  Json.mkObj [("running", toJson o.running), ("frames", toJson o.frames), ("stable", toJson o.stable),
    ("hoverInside", toJson o.hoverInside), ("t", toJson o.t)]

def policyJson (p : Policy) : Json :=
  Json.mkObj [("minFrames", toJson p.minFrames), ("minStable", toJson p.minStable), ("eps", toJson p.eps), ("timeoutMs", toJson p.timeoutMs),
    ("maxFrames", toJson p.maxFrames)]

def outcomeText : Outcome → String
  | .settled i => s!"settled@{i}"
  | .unsettled => "unsettled"

def reportText : Report → String
  | .pass => "pass"
  | .fail => "fail"
  | .unsettled => "unsettled"

def cellText : Cell → String
  | .pass => "pass"
  | .fail => "fail"
  | .unsettled => "unsettled"
  | .notRendered => "notRendered"

def pastEnd : Obs := { running := 1, frames := 0, stable := 0, hoverInside := false, t := 1000000000 }

def waitList (p : Policy) (tr : List Obs) : Outcome := wait p (fun i => tr.getD i pastEnd)

private def ob (running frames stable : Nat) (hov : Bool) (t : Nat) : Obs :=
  { running := running, frames := frames, stable := stable, hoverInside := hov, t := t }

def obsCases : List (String × Obs) :=
  [ ("all conditions hold", ob 0 2 3 false 100),
    ("exactly at the thresholds", ob 0 2 3 false 0),
    ("an animation runs", ob 1 5 5 false 100),
    ("one frame since the resize", ob 0 1 5 false 100),
    ("no frame at all", ob 0 0 0 false 100),
    ("boxes still changing", ob 0 5 1 false 100),
    ("pointer inside a hover target", ob 0 5 5 true 100),
    ("pain.notes: laid out one resize behind (1 frame)", ob 0 1 1 false 40),
    ("hero.orbit: parked pointer over card 2", ob 0 9 9 true 600),
    ("overlays.signup: dialog enter animation running", ob 1 7 3 false 120),
    ("hero.orbit after parking", park (ob 0 9 9 true 600)) ]

def waitCases : List (String × Policy × List Obs) :=
  [ ("settles at the third frame",
      gatePolicy, [ob 1 1 0 false 16, ob 0 2 1 false 33, ob 0 3 3 false 50, ob 0 4 4 false 66]),
    ("settles at once",
      gatePolicy, [ob 0 2 3 false 0, ob 0 3 4 false 16]),
    ("an animation outlasts the budget",
      gatePolicy, [ob 1 1 0 false 16, ob 1 2 0 false 1500, ob 1 3 0 false 29900, ob 0 4 1 false 30100, ob 0 5 2 false 30116]),
    ("settles only after the budget",
      gatePolicy, [ob 0 1 0 false 1000, ob 0 2 3 false 30001, ob 0 3 4 false 30017]),
    ("settles exactly at the budget",
      gatePolicy, [ob 0 1 0 false 1000, ob 0 2 3 false 30000]),
    ("no frame ever (requestAnimationFrame never fires)",
      gatePolicy, [ob 0 0 0 false 250, ob 0 0 0 false 1000, ob 0 0 0 false 30000]),
    ("pointer stays inside a hover target",
      gatePolicy, [ob 0 2 2 true 16, ob 0 3 3 true 33, ob 0 4 4 true 50]),
    ("empty trace", gatePolicy, []),
    ("a stricter policy needs more frames",
      { minFrames := 4, minStable := 2, eps := 100, timeoutMs := 100, maxFrames := 60 }, [ob 0 2 2 false 16, ob 0 3 3 false 33, ob 0 4 4 false 50]),
    ("a lerp that never stops spends the frame budget long before the timeout",
      gatePolicy, [ob 0 1 0 false 16, ob 0 30 0 false 500, ob 0 60 0 false 1000, ob 0 61 0 false 1016, ob 0 62 3 false 1033]),
    ("settles exactly at the frame budget",
      gatePolicy, [ob 1 1 0 false 16, ob 0 58 1 false 966, ob 0 60 3 false 1000]),
    ("settles one frame after the frame budget",
      gatePolicy, [ob 1 1 0 false 16, ob 0 59 1 false 983, ob 0 61 3 false 1016]),
    ("slow frames: the timeout comes before the frame budget",
      gatePolicy, [ob 1 1 0 false 3000, ob 1 40 0 false 29000, ob 1 41 0 false 30001]),
    ("idle: nothing runs at once",
      idlePolicy gatePolicy 20000, [ob 0 0 0 false 0]),
    ("idle: animations finish after some frames",
      idlePolicy gatePolicy 20000, [ob 2 0 0 false 0, ob 1 10 0 false 170, ob 0 20 0 false 340]),
    ("idle: timers keep restarting animations past the frame budget",
      idlePolicy gatePolicy 20000, [ob 3 0 0 false 0, ob 2 60 0 false 1000, ob 4 61 0 false 1016, ob 0 70 0 false 1200]),
    ("idle: the cap comes first on slow frames",
      idlePolicy gatePolicy 15000, [ob 1 0 0 false 0, ob 1 20 0 false 14000, ob 1 21 0 false 15001]) ]

def foldCases : List (String × Outcome × List Outcome) :=
  [ ("no later waits", .settled 3, []),
    ("all settled", .settled 3, [.settled 0, .settled 7]),
    ("an overlay did not settle", .settled 3, [.settled 0, .unsettled]),
    ("the main wait did not settle", .unsettled, [.settled 0]),
    ("the idle wait did not settle", .settled 1, [.unsettled]) ]

def reportCases : List (String × Outcome × Outcome × Bool) :=
  [ ("both settled and equal", .settled 2, .settled 0, true),
    ("both settled and different", .settled 2, .settled 5, false),
    ("original unsettled, values equal", .unsettled, .settled 1, true),
    ("rewrite unsettled, values different", .settled 1, .unsettled, false),
    ("both unsettled", .unsettled, .unsettled, true) ]

def viewForCases : List (String × Option String × String) :=
  [ ("chromium, no switch", none, "chromium"),
    ("webkit, no switch", none, "playwright-webkit"),
    ("webkit forced on", some "1", "playwright-webkit"),
    ("chromium forced off", some "0", "chromium"),
    ("chromium, empty switch", some "", "chromium"),
    ("webkit, other switch value", some "yes", "playwright-webkit"),
    ("unknown engine, no switch", none, "firefox"),
    ("unknown engine forced on", some "1", "firefox") ]

def cellCases : List (String × Bool × Bool × Outcome × Outcome × Bool) :=
  [ ("both rendered, equal", true, true, .settled 1, .settled 2, true),
    ("both rendered, different", true, true, .settled 1, .settled 2, false),
    ("both rendered, one unsettled", true, true, .unsettled, .settled 2, true),
    ("original flagged unrendered, values different", false, true, .settled 1, .settled 2, false),
    ("rewrite not rendered, values equal", true, false, .settled 1, .settled 2, true),
    ("neither rendered, both unsettled", false, false, .unsettled, .unsettled, false) ]

def viewCases : List (String × Bool × Bool × (Bool × Nat) × (Bool × Nat) × (Bool × Nat) × (Bool × Nat) × Outcome × Outcome) :=
  [ ("nothing skipped, equal", false, false, (false, 132), (false, 0), (false, 132), (false, 0), .settled 1, .settled 2),
    ("nothing skipped, different", false, false, (false, 132), (false, 0), (false, 0), (false, 0), .settled 1, .settled 2),
    ("commission: stale first margin 0, fresh after view equal", false, true, (false, 132), (false, 0), (true, 0), (false, 132), .settled 1, .settled 2),
    ("stale first margin 0, fresh after view different", false, true, (false, 132), (false, 0), (true, 0), (false, 7), .settled 1, .settled 2),
    ("still skipped after view", false, true, (false, 132), (false, 0), (true, 0), (true, 0), .settled 1, .settled 2),
    ("both skipped, both brought, equal fresh values", true, true, (true, 1), (false, 9), (true, 2), (false, 9), .settled 1, .settled 2),
    ("rendered difference is not hidden by a brought node elsewhere", true, true, (true, 1), (false, 9), (true, 2), (false, 8), .settled 1, .settled 2),
    ("rendered, one arm unsettled", false, true, (false, 5), (false, 0), (true, 0), (false, 5), .settled 1, .unsettled) ]

def renderedCases : List (String × List Bool) :=
  [ ("no ancestors", []), ("none skips", [false, false, false]), ("the middle one skips", [false, true, false]),
    ("only the root skips", [true]) ]

def quietCases : List (String × Nat × List Int × List Int) :=
  [ ("identical", 100, [1000000, 250000], [1000000, 250000]),
    ("moved exactly eps", 100, [1000000], [1000100]),
    ("moved by more than eps", 100, [1000000], [1000101]),
    ("one of two moved too far", 100, [1000000, 5000], [1000000, 5200]),
    ("a value appeared", 100, [1000000], [1000000, 0]),
    ("negative direction", 100, [-5000], [-5100]),
    ("loose eps", 5000, [0, 0], [4000, -5000]),
    ("no values at all", 100, [], []),
    ("people.deck scale mid lerp", 100, [977000], [979000]) ]

def runCases : List (String × List (Bool × Nat × Nat)) :=
  [ ("no animation", []),
    ("document animation running", [(true, 400, 120)]),
    ("document animation finished", [(true, 400, 400)]),
    ("document: two running, one finished", [(true, 400, 0), (true, 1000, 999), (true, 200, 200)]),
    ("scroll animation at a fixed offset (never finishes)", [(false, 1000000, 0)]),
    ("hero.exit:threaded: view-timeline animations beside a finished transition", [(false, 1000000, 300000), (false, 1000000, 300000), (true, 400, 400)]),
    ("scroll animations do not hide a running document animation", [(false, 1000000, 0), (true, 400, 120), (false, 1000000, 500000)]) ]

def goldenLines (_ : Unit := ()) : List String :=
  obsCases.map (fun (n, o) =>
    (Json.mkObj [("kind", "settled"), ("name", toJson n), ("policy", policyJson gatePolicy), ("obs", obsJson o),
      ("settled", toJson (settled gatePolicy o))]).compress)
  ++ waitCases.map (fun (n, p, tr) =>
    (Json.mkObj [("kind", "wait"), ("name", toJson n), ("policy", policyJson p), ("trace", Json.arr (tr.map obsJson).toArray),
      ("outcome", toJson (outcomeText (waitList p tr)))]).compress)
  ++ quietCases.map (fun (n, e, u, v) =>
    (Json.mkObj [("kind", "quiet"), ("name", toJson n), ("eps", toJson e), ("prev", toJson u), ("cur", toJson v),
      ("quiet", toJson (quiet e u v)), ("next", toJson (nextStable e 2 u v))]).compress)
  ++ renderedCases.map (fun (n, sk) =>
    (Json.mkObj [("kind", "rendered"), ("name", toJson n), ("skips", toJson sk), ("rendered", toJson (rendered sk))]).compress)
  ++ cellCases.map (fun (n, ra, rb, a, b, e) =>
    (Json.mkObj [("kind", "cell"), ("name", toJson n), ("renderedA", toJson ra), ("renderedB", toJson rb),
      ("a", toJson (outcomeText a)), ("b", toJson (outcomeText b)), ("equal", toJson e),
      ("cell", toJson (cellText (cell ra rb a b e)))]).compress)
  ++ viewCases.map (fun (n, bo, br, fo, go, fr, gr, a, b) =>
    let rd (x : Bool × Nat) : Json := Json.mkObj [("skipped", toJson x.1), ("val", toJson x.2)]
    let mk (x : Bool × Nat) : Reading Nat := { skipped := x.1, val := x.2 }
    (Json.mkObj [("kind", "view"), ("name", toJson n), ("bringO", toJson bo), ("bringR", toJson br),
      ("firstO", rd fo), ("againO", rd go), ("firstR", rd fr), ("againR", rd gr),
      ("a", toJson (outcomeText a)), ("b", toJson (outcomeText b)),
      ("cell", toJson (cellText (viewCell bo br (mk fo) (mk go) (mk fr) (mk gr) a b)))]).compress)
  ++ foldCases.map (fun (n, a, ws) =>
    (Json.mkObj [("kind", "fold"), ("name", toJson n), ("first", toJson (outcomeText a)),
      ("extra", toJson (ws.map outcomeText)), ("outcome", toJson (outcomeText (fold a ws)))]).compress)
  ++ reportCases.map (fun (n, a, b, e) =>
    (Json.mkObj [("kind", "report"), ("name", toJson n), ("a", toJson (outcomeText a)), ("b", toJson (outcomeText b)),
      ("equal", toJson e), ("report", toJson (reportText (report a b e)))]).compress)
  ++ viewForCases.map (fun (n, s, e) =>
    (Json.mkObj [("kind", "viewFor"), ("name", toJson n), ("switch", toJson s), ("engine", toJson e),
      ("view", toJson (viewFor s e))]).compress)
  ++ runCases.map (fun (n, as) =>
    let anims := as.map (fun (d, dur, e) => ({ dur := dur, elapsed := e, onDocument := d } : Anim))
    (Json.mkObj [("kind", "runs"), ("name", toJson n),
      ("anims", Json.arr (as.map (fun (d, dur, e) =>
        Json.mkObj [("onDocument", toJson d), ("dur", toJson dur), ("elapsed", toJson e)])).toArray),
      ("running", toJson (runCount anims)), ("before", toJson (runCountAll anims))]).compress)

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"settle golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"settle golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

#guard settled gatePolicy (ob 0 2 3 false 100) == true
#guard settled gatePolicy (ob 0 1 5 false 100) == false
#guard waitList gatePolicy [ob 1 1 0 false 16, ob 0 2 1 false 33, ob 0 3 3 false 50] == .settled 2
#guard waitList gatePolicy [ob 0 1 0 false 1000, ob 0 2 3 false 30001, ob 0 3 4 false 30017] == .unsettled
#guard waitList gatePolicy [] == .unsettled
#guard waitList gatePolicy [ob 0 60 3 false 1000] == .settled 0
#guard waitList gatePolicy [ob 0 61 3 false 1000] == .unsettled
#guard spent gatePolicy (ob 0 61 0 false 10) == true
#guard spent gatePolicy (ob 0 60 0 false 30000) == false
#guard runCount [{ dur := 1000000, elapsed := 0, onDocument := false }] == 0
#guard runCountAll [{ dur := 1000000, elapsed := 0, onDocument := false }] == 1
#guard cell false true (.settled 1) (.settled 2) false == .notRendered
#guard cell true true (.settled 1) (.settled 2) false == .fail
#guard rendered [false, true, false] == false
#guard viewCell true false (α := Nat) ⟨true, 0⟩ ⟨false, 132⟩ ⟨false, 132⟩ ⟨false, 0⟩ (.settled 1) (.settled 2) == .pass
#guard viewCell false true (α := Nat) ⟨false, 132⟩ ⟨false, 0⟩ ⟨true, 0⟩ ⟨false, 7⟩ (.settled 1) (.settled 2) == .fail
#guard viewCell false true (α := Nat) ⟨false, 132⟩ ⟨false, 0⟩ ⟨true, 0⟩ ⟨true, 0⟩ (.settled 1) (.settled 2) == .notRendered

end Fw.Gate.Settle
