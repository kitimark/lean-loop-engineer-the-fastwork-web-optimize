import Fw.Measure.TouchLock
/-!
# Fw.Parts.EndPin: a page-end pin that never writes while a pan or its momentum is live
-/
namespace Fw.Parts.EndPin
open Fw.Measure.TouchLock

def quietMs : Nat := 120

structure Pin where
  touching : Bool
  since : Nat
  a : Option Int
  b : Int
deriving Repr, BEq, DecidableEq

inductive Ev where
  | move (y : Int)
  | down
  | up
  | idle (ms : Nat) (s : Int)
deriving Repr, BEq, DecidableEq

def reverses (a : Option Int) (b s : Int) : Bool :=
  match a with
  | none => false
  | some a' => decide ((b - a') * (s - b) < 0)

def mayWrite (p : Pin) (s : Int) : Bool :=
  !p.touching && decide (quietMs ≤ p.since) && decide (p.b ≠ s) && !reverses p.a p.b s

def moveTo (p : Pin) (y : Int) : Pin := { p with since := 0, a := if y = p.b then p.a else some p.b, b := y }

abbrev Policy := Pin → Int → Bool

def faithMay : Policy := fun q s => decide (q.b ≠ s)

def stepBy (may : Policy) (p : Pin) : Ev → Pin × List Int
  | .move y => ({ p with since := 0, a := if y = p.b then p.a else some p.b, b := y }, [y])
  | .down => ({ p with touching := true, since := 0 }, [])
  | .up => ({ p with touching := false, since := 0 }, [])
  | .idle ms s =>
    let q := { p with since := p.since + ms }
    if may q s then ({ q with since := 0, a := some q.b, b := s }, [s]) else (q, [])

def step (p : Pin) (e : Ev) : Pin × List Int := stepBy mayWrite p e

def play : Pin → List Ev → List Int
  | _, [] => []
  | p, e :: es => (step p e).2 ++ play (step p e).1 es

def writes : Pin → List Ev → List Int
  | _, [] => []
  | p, e :: es => (match e with | .idle _ _ => (step p e).2 | _ => []) ++ writes (step p e).1 es

def start (y0 : Int) : Pin := ⟨false, 0, none, y0⟩

def run (y0 : Int) (es : List Ev) : List Sample := ((y0 :: play (start y0) es).map fun y => ⟨y, true⟩)

def faithOut (s : Int) : List Int → List Int
  | [] => []
  | y :: ys => if y = s then y :: faithOut s ys else y :: s :: faithOut s ys

def faithRun (s y0 : Int) (ys : List Int) : List Sample := ((y0 :: faithOut s ys).map fun y => ⟨y, true⟩)

def movesOf : List Ev → List Int
  | [] => []
  | .move y :: es => y :: movesOf es
  | _ :: es => movesOf es

def targetsOf : List Ev → List Int
  | [] => []
  | .idle _ s :: es => s :: targetsOf es
  | _ :: es => targetsOf es

theorem step_idle_writes (p : Pin) (ms : Nat) (s : Int) :
    (step p (.idle ms s)).2 = [] ∨ (step p (.idle ms s)).2 = [s] := by
  simp only [step, stepBy]
  split <;> simp

theorem step_idle_write_iff (p : Pin) (ms : Nat) (s : Int) :
    (step p (.idle ms s)).2 = [s] ↔ mayWrite { p with since := p.since + ms } s = true := by
  simp only [step, stepBy]
  split <;> simp_all

theorem no_write_touching (p : Pin) (ms : Nat) (s : Int) (h : p.touching = true) : (step p (.idle ms s)).2 = [] := by
  have : mayWrite { p with since := p.since + ms } s = false := by simp [mayWrite, h]
  simp [step, stepBy, this]

theorem no_write_live (p : Pin) (ms : Nat) (s : Int) (h : p.since + ms < quietMs) : (step p (.idle ms s)).2 = [] := by
  have : mayWrite { p with since := p.since + ms } s = false := by
    simp [mayWrite, Nat.not_le.mpr h]
  simp [step, stepBy, this]

theorem no_write_settled (p : Pin) (ms : Nat) (s : Int) (h : p.b = s) : (step p (.idle ms s)).2 = [] := by
  have : mayWrite { p with since := p.since + ms } s = false := by simp [mayWrite, h]
  simp [step, stepBy, this]

theorem no_write_reversal (p : Pin) (ms : Nat) (s : Int) (h : reverses p.a p.b s = true) :
    (step p (.idle ms s)).2 = [] := by
  have : mayWrite { p with since := p.since + ms } s = false := by simp [mayWrite, h]
  simp [step, stepBy, this]

theorem write_of_clear (p : Pin) (ms : Nat) (s : Int) (h1 : p.touching = false) (h2 : quietMs ≤ p.since + ms)
    (h3 : p.b ≠ s) (h4 : reverses p.a p.b s = false) : (step p (.idle ms s)).2 = [s] := by
  rw [step_idle_write_iff]
  simp [mayWrite, h1, h2, h3, h4]

theorem no_write_on_input (p : Pin) (e : Ev) (h : ∀ ms s, e ≠ .idle ms s) :
    (step p e).2 = [] ∨ ∃ y, e = .move y ∧ (step p e).2 = [y] := by
  cases e with
  | move y => exact Or.inr ⟨y, rfl, rfl⟩
  | down => exact Or.inl rfl
  | up => exact Or.inl rfl
  | idle ms s => exact absurd rfl (h ms s)

theorem write_is_target (p : Pin) (ms : Nat) (s y : Int) (h : y ∈ (step p (.idle ms s)).2) : y = s := by
  rcases step_idle_writes p ms s with h' | h' <;> rw [h'] at h <;> simp_all

theorem writes_target :
    ∀ (es : List Ev) (p : Pin) (y : Int), y ∈ writes p es → y ∈ targetsOf es := by
  intro es
  induction es with
  | nil => intro p y h; simp [writes] at h
  | cons e es ih =>
    intro p y h
    simp only [writes, List.mem_append] at h
    rcases h with h | h
    · cases e with
      | idle ms s => simp [targetsOf, write_is_target p ms s y h]
      | move z => simp at h
      | down => simp at h
      | up => simp at h
    · have := ih _ y h
      cases e <;> simp [targetsOf, this]

def tailTurns (pr : Int → Bool) : Option Int → Int → List Int → Nat
  | none, b, l => turns pr (b :: l)
  | some a, b, l => turnsFrom pr a b l

theorem dedupFrom_cons_eq (v y : Int) (l : List Int) (h : y = v) : dedupFrom v (y :: l) = dedupFrom v l := by
  simp [dedupFrom, h]

theorem dedupFrom_cons_ne (v y : Int) (l : List Int) (h : y ≠ v) : dedupFrom v (y :: l) = y :: dedupFrom y l := by
  simp [dedupFrom, h]

theorem play_no_turn (s : Int) :
    ∀ (es : List Ev) (p : Pin), (∀ y ∈ movesOf es, y ≠ s) →
      tailTurns (fun c => decide (c = s)) p.a p.b (dedupFrom p.b (play p es)) = 0 := by
  intro es
  induction es with
  | nil => intro p _; cases p.a <;> simp [play, dedupFrom, tailTurns, turns, turnsFrom]
  | cons e es ih =>
    intro p hu
    cases e with
    | down =>
      have := ih { p with touching := true, since := 0 } (by simpa [movesOf] using hu)
      simpa [play, step, stepBy] using this
    | up =>
      have := ih { p with touching := false, since := 0 } (by simpa [movesOf] using hu)
      simpa [play, step, stepBy] using this
    | move y =>
      have hy : y ≠ s := hu y (by simp [movesOf])
      have hr : ∀ z ∈ movesOf es, z ≠ s := fun z hz => hu z (by simp [movesOf, hz])
      by_cases hb : y = p.b
      · have := ih { p with since := 0, a := p.a, b := y } hr
        subst hb
        simpa [play, step, stepBy, dedupFrom_cons_eq] using this
      · have := ih { p with since := 0, a := some p.b, b := y } hr
        simp only [play, step, stepBy, hb, ite_false, List.singleton_append, dedupFrom_cons_ne _ _ _ hb] at this ⊢
        cases ha : p.a with
        | none => simpa [tailTurns, turns, turnsFrom] using this
        | some a' => simpa [tailTurns, turnsFrom, hy] using this
    | idle ms t =>
      by_cases hw : mayWrite { p with since := p.since + ms } t = true
      · have hne : p.b ≠ t := by
          simp only [mayWrite, Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at hw
          exact hw.1.2
        have hrev : reverses p.a p.b t = false := by
          simp only [mayWrite, Bool.and_eq_true, Bool.not_eq_true'] at hw
          exact hw.2
        have := ih { p with since := 0, a := some p.b, b := t } (by simpa [movesOf] using hu)
        simp only [play, step, stepBy, hw, ite_true, List.singleton_append, dedupFrom_cons_ne _ _ _ (Ne.symm hne)] at this ⊢
        cases ha : p.a with
        | none => simpa [tailTurns, turns, turnsFrom] using this
        | some a' =>
          rw [ha] at hrev
          simp only [reverses, decide_eq_false_iff_not] at hrev
          simpa [tailTurns, turnsFrom, hrev] using this
      · have hw' : mayWrite { p with since := p.since + ms } t = false := by simpa using hw
        have := ih { p with since := p.since + ms } (by simpa [movesOf] using hu)
        simpa [play, step, stepBy, hw'] using this

theorem openPhase_all (xs : List Sample) (h : ∀ x ∈ xs, x.isOpen = true) : openPhase xs = xs := by
  have h1 : ∀ l : List Sample, (∀ x ∈ l, x.isOpen = true) → l.dropWhile (fun s => !s.isOpen) = l := by
    intro l hl
    cases l with
    | nil => rfl
    | cons a t => simp [List.dropWhile, hl a (by simp)]
  have h2 : ∀ l : List Sample, (∀ x ∈ l, x.isOpen = true) → l.takeWhile (fun s => s.isOpen) = l := by
    intro l
    induction l with
    | nil => intro _; rfl
    | cons a t ih =>
      intro hl
      simp [List.takeWhile, hl a (by simp), ih (fun x hx => hl x (by simp [hx]))]
  simp [openPhase, h1 xs h, h2 xs h]

theorem pin_fights_zero (s y0 : Int) (es : List Ev) (h : ∀ y ∈ movesOf es, y ≠ s) : fights s (run y0 es) = 0 := by
  have hs : (run y0 es).map (·.y) = y0 :: play (start y0) es := by simp [run, List.map_map, Function.comp_def]
  have ho : openPhase (run y0 es) = run y0 es := by
    apply openPhase_all
    intro x hx
    simp only [run, List.mem_map] at hx
    obtain ⟨y, _, rfl⟩ := hx
    rfl
  have := play_no_turn s es (start y0) h
  simpa [fights, positions, ho, hs, dedup, tailTurns, start] using this

theorem write_adds_no_turn (pr : Int → Bool) (a : Option Int) (b s : Int) (hrev : reverses a b s = false)
    (l : List Int) :
    tailTurns pr a b (s :: l) = tailTurns pr (some b) s l := by
  cases a with
  | none => simp [tailTurns, turns]
  | some a' =>
    simp only [reverses, decide_eq_false_iff_not] at hrev
    simp [tailTurns, turnsFrom, hrev]

theorem faith_fights_witness : fights 0 (faithRun 0 0 [90, 60]) = 2 := by decide

def declineEvents : List Ev := [.down, .move 90, .up, .idle 200 0]

theorem decline_fights_zero : fights 0 (run 0 declineEvents) = 0 := by decide

theorem decline_rests_off_target : (play (start 0) declineEvents).getLast? = some 90 := by decide

theorem faith_ends_on_target : (faithOut 0 [90, 60]).getLast? = some 0 := by decide

theorem quiet_no_write :
    ∀ (es : List Ev) (p : Pin), (∀ t ∈ targetsOf es, t = p.b) → movesOf es = [] → play p es = [] := by
  intro es
  induction es with
  | nil => intro p _ _; rfl
  | cons e es ih =>
    intro p hb hm
    cases e with
    | move y => simp [movesOf] at hm
    | down => simpa [play, step, stepBy] using ih { p with touching := true, since := 0 } (by simpa [targetsOf] using hb) (by simpa [movesOf] using hm)
    | up => simpa [play, step, stepBy] using ih { p with touching := false, since := 0 } (by simpa [targetsOf] using hb) (by simpa [movesOf] using hm)
    | idle ms t =>
      have ht : t = p.b := hb t (by simp [targetsOf])
      have h2 := ih { p with since := p.since + ms } (by simpa [targetsOf] using fun u hu => hb u (by simp [targetsOf, hu])) (by simpa [movesOf] using hm)
      have hw : mayWrite { p with since := p.since + ms } t = false := by simp [mayWrite, ht]
      simpa [play, step, stepBy, hw] using h2

def due (p : Pin) (s : Int) : Option Nat :=
  if p.touching = false ∧ p.b ≠ s ∧ reverses p.a p.b s = false ∧ p.since < quietMs then some (quietMs - p.since) else none

theorem due_write (p : Pin) (s : Int) (d : Nat) (h : due p s = some d) : (step p (.idle d s)).2 = [s] := by
  unfold due at h
  split at h
  · rename_i hc
    obtain ⟨h1, h2, h3, h4⟩ := hc
    have hd : d = quietMs - p.since := by simpa using h.symm
    exact write_of_clear p d s h1 (by omega) h2 h3
  · simp at h

theorem due_none_touching (p : Pin) (s : Int) (h : p.touching = true) : due p s = none := by
  simp [due, h]

theorem due_none_settled (p : Pin) (s : Int) (h : p.b = s) : due p s = none := by
  simp [due, h]

theorem due_none_reversal (p : Pin) (s : Int) (h : reverses p.a p.b s = true) : due p s = none := by
  simp [due, h]

def eventOf (p : Pin) (y : Int) (dt : Nat) (s : Int) : Ev := if y = p.b then .idle dt s else .move y

def observe (s : Int) (p : Pin) (y : Int) (dt : Nat) : Pin × Option Int :=
  match eventOf p y dt s with
  | .idle ms t => ((step p (.idle ms t)).1, (step p (.idle ms t)).2.head?)
  | e => ((step p e).1, none)

theorem observe_state (s : Int) (p : Pin) (y : Int) (dt : Nat) : (observe s p y dt).1 = (step p (eventOf p y dt s)).1 := by
  unfold observe eventOf
  split <;> simp_all [step, stepBy]

theorem observe_move_silent (s : Int) (p : Pin) (y : Int) (dt : Nat) (h : y ≠ p.b) : (observe s p y dt).2 = none := by
  simp [observe, eventOf, h]

theorem observe_write (s : Int) (p : Pin) (y : Int) (dt : Nat) (w : Int) (h : (observe s p y dt).2 = some w) :
    y = p.b ∧ w = s ∧ mayWrite { p with since := p.since + dt } s = true := by
  by_cases hy : y = p.b
  · have hw : (observe s p y dt).2 = (step p (.idle dt s)).2.head? := by simp [observe, eventOf, hy]
    rw [hw] at h
    rcases step_idle_writes p dt s with h' | h'
    · rw [h'] at h; simp at h
    · rw [h'] at h
      simp only [List.head?_cons, Option.some.injEq] at h
      exact ⟨hy, h.symm, (step_idle_write_iff p dt s).mp h'⟩
  · rw [observe_move_silent s p y dt hy] at h; simp at h

def live (q : Pin) : Bool := q.touching || decide (q.since < quietMs)

theorem mayWrite_not_live (q : Pin) (s : Int) (h : mayWrite q s = true) : live q = false := by
  simp only [mayWrite, Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at h
  simp [live, h.1.1.1, Nat.not_lt.mpr h.1.1.2]

theorem live_moveTo (p : Pin) (y : Int) : live (moveTo p y) = true := by
  simp [live, moveTo, quietMs]

theorem live_touching (q : Pin) (h : q.touching = true) : live q = true := by simp [live, h]

def playBy (may : Policy) : Pin → List Ev → List Int
  | _, [] => []
  | p, e :: es => (stepBy may p e).2 ++ playBy may (stepBy may p e).1 es

theorem playBy_mayWrite : ∀ (es : List Ev) (p : Pin), playBy mayWrite p es = play p es := by
  intro es
  induction es with
  | nil => intro p; rfl
  | cons e es ih => intro p; simp [playBy, play, step, ih]

def writesLive (may : Policy) : Pin → List Ev → Nat
  | _, [] => 0
  | p, e :: es =>
    (match e with
      | .idle ms _ => if live { p with since := p.since + ms } then (stepBy may p e).2.length else 0
      | _ => 0) + writesLive may (stepBy may p e).1 es

theorem writesLive_zero_of (may : Policy) (hmay : ∀ q s, may q s = true → live q = false) :
    ∀ (es : List Ev) (p : Pin), writesLive may p es = 0 := by
  intro es
  induction es with
  | nil => intro p; rfl
  | cons e es ih =>
    intro p
    have h := ih (stepBy may p e).1
    cases e with
    | idle ms s =>
      have hl : (if live { p with since := p.since + ms } = true then (stepBy may p (.idle ms s)).2.length else 0) = 0 := by
        by_cases hv : live { p with since := p.since + ms } = true
        · have hm : may { p with since := p.since + ms } s = false := by
            cases hm' : may { p with since := p.since + ms } s
            · rfl
            · rw [hmay _ _ hm'] at hv; simp at hv
          have : (stepBy may p (.idle ms s)).2 = [] := by simp [stepBy, hm]
          simp [this]
        · simp [hv]
      simp only [writesLive, hl, h]
    | move y => simp [writesLive, h]
    | down => simp [writesLive, h]
    | up => simp [writesLive, h]

theorem writesLive_zero (es : List Ev) (p : Pin) : writesLive mayWrite p es = 0 :=
  writesLive_zero_of mayWrite mayWrite_not_live es p

def faithEvents (s : Int) : List Int → List Ev
  | [] => []
  | y :: ys => .move y :: .idle 0 s :: faithEvents s ys

theorem faith_play (s : Int) : ∀ (ys : List Int) (p : Pin), playBy faithMay p (faithEvents s ys) = faithOut s ys := by
  intro ys
  induction ys with
  | nil => intro p; rfl
  | cons y ys ih =>
    intro p
    by_cases hy : y = s
    · subst hy; simp [faithEvents, playBy, stepBy, faithMay, faithOut, ih]
    · simp [faithEvents, playBy, stepBy, faithMay, faithOut, hy, ih]

theorem faith_writesLive (s : Int) : ∀ (ys : List Int) (p : Pin),
    writesLive faithMay p (faithEvents s ys) = (ys.filter fun y => decide (y ≠ s)).length := by
  intro ys
  induction ys with
  | nil => intro p; rfl
  | cons y ys ih =>
    intro p
    by_cases hy : y = s
    · subst hy; simp [faithEvents, writesLive, stepBy, faithMay, live, quietMs, ih]
    · simp [faithEvents, writesLive, stepBy, faithMay, live, quietMs, hy, ih]
      omega

theorem faithOut_length (s : Int) : ∀ ys : List Int, (faithOut s ys).length = ys.length + (ys.filter fun y => decide (y ≠ s)).length := by
  intro ys
  induction ys with
  | nil => rfl
  | cons y ys ih =>
    by_cases hy : y = s
    · simp [faithOut, hy, ih]; omega
    · simp [faithOut, hy, ih]; omega

theorem faith_writesLive_is_writes (s : Int) (ys : List Int) (p : Pin) :
    writesLive faithMay p (faithEvents s ys) = (playBy faithMay p (faithEvents s ys)).length - ys.length := by
  rw [faith_writesLive, faith_play, faithOut_length]; omega

theorem faith_writesLive_pos (s : Int) (ys : List Int) (p : Pin) (y : Int) (hy : y ∈ ys) (hne : y ≠ s) :
    0 < writesLive faithMay p (faithEvents s ys) := by
  rw [faith_writesLive]
  exact List.length_pos_of_mem (List.mem_filter.mpr ⟨hy, by simpa using hne⟩)

def liveEvents : List Ev := [.down, .move 90, .idle 16 0, .up, .move 60, .idle 16 0, .idle 200 0]

theorem faith_writesLive_witness : writesLive faithMay (start 0) liveEvents = 2 := by decide

theorem end_writesLive_witness : writesLive mayWrite (start 0) liveEvents = 0 := writesLive_zero _ _

inductive Why where
  | touching | live | onTarget | reversal
deriving Repr, BEq, DecidableEq

def Why.name : Why → String
  | .touching => "touching"
  | .live => "live"
  | .onTarget => "onTarget"
  | .reversal => "reversal"

def why (q : Pin) (s : Int) : Option Why :=
  if q.touching = true then some .touching
  else if q.since < quietMs then some .live
  else if q.b = s then some .onTarget
  else if reverses q.a q.b s = true then some .reversal
  else none

theorem why_touching (q : Pin) (s : Int) (h : q.touching = true) : why q s = some .touching := by simp [why, h]

theorem why_live (q : Pin) (s : Int) (h1 : q.touching = false) (h2 : q.since < quietMs) : why q s = some .live := by
  simp [why, h1, h2]

theorem why_onTarget (q : Pin) (s : Int) (h1 : q.touching = false) (h2 : quietMs ≤ q.since) (h3 : q.b = s) :
    why q s = some .onTarget := by
  simp [why, h1, Nat.not_lt.mpr h2, h3]

theorem why_reversal (q : Pin) (s : Int) (h1 : q.touching = false) (h2 : quietMs ≤ q.since) (h3 : q.b ≠ s)
    (h4 : reverses q.a q.b s = true) : why q s = some .reversal := by
  simp [why, h1, Nat.not_lt.mpr h2, h3, h4]

theorem why_none_iff (q : Pin) (s : Int) : why q s = none ↔ mayWrite q s = true := by
  unfold why mayWrite
  cases ht : q.touching
  · by_cases h2 : q.since < quietMs
    · have h2' : ¬ quietMs ≤ q.since := Nat.not_le.mpr h2
      simp [h2, h2']
    · have h2' : quietMs ≤ q.since := Nat.not_lt.mp h2
      by_cases h3 : q.b = s
      · simp [h2, h2', h3]
      · by_cases h4 : reverses q.a q.b s = true
        · simp [h2, h2', h3, h4]
        · simp [h2, h2', h3, h4]
  · simp

def dueWhy (q : Pin) (s : Int) : Option Why := why { q with since := quietMs } s

theorem dueWhy_ne_live (q : Pin) (s : Int) : dueWhy q s ≠ some .live := by
  unfold dueWhy why
  cases q.touching
  · by_cases h3 : q.b = s
    · simp [h3]
    · by_cases h4 : reverses q.a q.b s = true <;> simp [h3, h4]
  · simp

theorem due_none_of_dueWhy (q : Pin) (s : Int) (h : dueWhy q s ≠ none) : due q s = none := by
  unfold dueWhy why at h
  unfold due
  cases ht : q.touching
  · by_cases h3 : q.b = s
    · simp [h3]
    · by_cases h4 : reverses q.a q.b s = true
      · simp [h4]
      · simp [ht, h3, h4] at h
  · simp

theorem dueWhy_none_of_due (q : Pin) (s : Int) (d : Nat) (h : due q s = some d) : dueWhy q s = none := by
  unfold due at h
  unfold dueWhy why
  split at h
  · rename_i hc
    obtain ⟨h1, h2, h3, _⟩ := hc
    simp [h1, h2, h3]
  · simp at h

inductive Outcome where
  | moved | wrote | declined (w : Why)
deriving Repr, BEq, DecidableEq

def Outcome.name : Outcome → String
  | .moved => "moved"
  | .wrote => "write"
  | .declined w => w.name

def outcome (s : Int) (p : Pin) (y : Int) (dt : Nat) : Outcome :=
  if y = p.b then
    (match why { p with since := p.since + dt } s with
      | none => .wrote
      | some w => .declined w)
  else .moved

theorem outcome_moved_iff (s : Int) (p : Pin) (y : Int) (dt : Nat) : outcome s p y dt = .moved ↔ y ≠ p.b := by
  unfold outcome
  by_cases hy : y = p.b
  · simp only [hy, ite_true]; split <;> simp
  · simp [hy]

theorem outcome_wrote_iff (s : Int) (p : Pin) (y : Int) (dt : Nat) :
    outcome s p y dt = .wrote ↔ ∃ w, (observe s p y dt).2 = some w := by
  constructor
  · intro h
    have hy : y = p.b := by
      by_cases hy : y = p.b
      · exact hy
      · simp [outcome, hy] at h
    have hn : why { p with since := p.since + dt } s = none := by
      unfold outcome at h
      simp only [hy, ite_true] at h
      split at h <;> simp_all
    have hm := (why_none_iff _ _).mp hn
    refine ⟨s, ?_⟩
    have := (step_idle_write_iff p dt s).mpr hm
    simp [observe, eventOf, hy, this]
  · rintro ⟨w, hw⟩
    obtain ⟨hy, _, hm⟩ := observe_write s p y dt w hw
    have hn := (why_none_iff _ _).mpr hm
    simp [outcome, hy, hn]

theorem outcome_declined_silent (s : Int) (p : Pin) (y : Int) (dt : Nat) (w : Why) (h : outcome s p y dt = .declined w) :
    (observe s p y dt).2 = none := by
  by_cases hy : y = p.b
  · have hn : why { p with since := p.since + dt } s = some w := by
      unfold outcome at h
      simp only [hy, ite_true] at h
      split at h <;> simp_all
    have hm : mayWrite { p with since := p.since + dt } s = false := by
      cases hm' : mayWrite { p with since := p.since + dt } s
      · rfl
      · have := (why_none_iff _ _).mpr hm'
        rw [hn] at this; simp at this
    have : (step p (.idle dt s)).2 = [] := by simp [step, stepBy, hm]
    simp [observe, eventOf, hy, this]
  · exact observe_move_silent s p y dt hy

structure TraceCounts where
  inactive : Nat
  due : Nat
  touches : Nat
  moved : Nat
  wrote : Nat
  touching : Nat
  live : Nat
  onTarget : Nat
  reversal : Nat
deriving Repr, BEq

def traceCounts (l : List String) : TraceCounts :=
  { inactive := l.count "inactive", due := l.count "due", touches := l.count "touch", moved := l.count "moved",
    wrote := l.count "write", touching := l.count "touching", live := l.count "live", onTarget := l.count "onTarget",
    reversal := l.count "reversal" }

def TraceCounts.declined (c : TraceCounts) : Nat := c.touching + c.live + c.onTarget + c.reversal

def TraceCounts.readings (c : TraceCounts) : Nat := c.moved + c.wrote + c.declined

def TraceCounts.ran (c : TraceCounts) : Bool := decide (0 < c.inactive + c.readings)

theorem traceCounts_append (a b : List String) :
    traceCounts (a ++ b) =
      { inactive := (traceCounts a).inactive + (traceCounts b).inactive, due := (traceCounts a).due + (traceCounts b).due,
        touches := (traceCounts a).touches + (traceCounts b).touches, moved := (traceCounts a).moved + (traceCounts b).moved,
        wrote := (traceCounts a).wrote + (traceCounts b).wrote, touching := (traceCounts a).touching + (traceCounts b).touching,
        live := (traceCounts a).live + (traceCounts b).live, onTarget := (traceCounts a).onTarget + (traceCounts b).onTarget,
        reversal := (traceCounts a).reversal + (traceCounts b).reversal } := by
  simp [traceCounts, List.count_append]

theorem traceCounts_nil : traceCounts [] = ⟨0, 0, 0, 0, 0, 0, 0, 0, 0⟩ := rfl

theorem ran_of_declined (l : List String) (w : Why) (h : w.name ∈ l) : (traceCounts l).ran = true := by
  have h0 : 0 < l.count w.name := List.count_pos_iff.mpr h
  unfold TraceCounts.ran TraceCounts.readings TraceCounts.declined traceCounts
  simp only [decide_eq_true_eq]
  cases w <;> simp only [Why.name] at h0 <;> omega

theorem ran_nil : (traceCounts []).ran = false := rfl

theorem ran_of_inactive (l : List String) (h : "inactive" ∈ l) : (traceCounts l).ran = true := by
  have h0 : 0 < l.count "inactive" := List.count_pos_iff.mpr h
  unfold TraceCounts.ran traceCounts
  simp only [decide_eq_true_eq]
  omega

def pinCases : List (String × Pin × Int) := [
  ("at rest off the target, moving on", (⟨false, 200, some 80, 60⟩, 0)),
  ("no history", (⟨false, 200, none, 60⟩, 0)),
  ("a touch is down", (⟨true, 200, none, 60⟩, 0)),
  ("a scroll event 50 ms ago", (⟨false, 50, none, 60⟩, 0)),
  ("on the target", (⟨false, 200, none, 0⟩, 0)),
  ("would turn around", (⟨false, 200, some 0, 90⟩, 0)),
  ("quiet exactly quietMs", (⟨false, 120, some 80, 60⟩, 0)),
  ("one ms short of quiet", (⟨false, 119, some 80, 60⟩, 0)),
  ("below the target, moving up", (⟨false, 200, some (-90), (-60)⟩, 0)),
  ("below the target, turning down", (⟨false, 200, some (-60), (-90)⟩, 0)),
  ("touch down and not quiet", (⟨true, 10, some 80, 60⟩, 0)),
  ("not quiet and on the target", (⟨false, 10, none, 0⟩, 0))]

def observeCases : List (String × Pin × Int × Int × Nat) := [
  ("the page moved", (⟨false, 300, some 80, 60⟩, 0, 40, 16)),
  ("the page moved onto the target", (⟨false, 300, some 80, 60⟩, 0, 0, 16)),
  ("same place, quiet", (⟨false, 0, some 80, 60⟩, 0, 60, 200)),
  ("same place, time accumulates", (⟨false, 70, some 80, 60⟩, 0, 60, 50)),
  ("same place, not quiet yet", (⟨false, 10, some 80, 60⟩, 0, 60, 50)),
  ("same place, touch down", (⟨true, 500, some 80, 60⟩, 0, 60, 500)),
  ("same place, would turn around", (⟨false, 0, some 0, 90⟩, 0, 90, 500)),
  ("same place, on the target", (⟨false, 0, none, 0⟩, 0, 0, 500))]

def dueCases : List (String × Pin × Int) := pinCases ++ [("a touch just ended", (⟨false, 0, some 80, 60⟩, 0))]

def playCases : List (String × Int × Int × List Ev) := [
  ("spring back lands on the target", (0, 0, [.down, .move 90, .move 60, .move 30, .up, .idle 50 0, .idle 100 0])),
  ("a pan away is left where it stopped", (0, 0, declineEvents)),
  ("momentum, then quiet", (0, 50, [.move 40, .move 30, .idle 16 0, .move 20, .idle 16 0, .move 10, .idle 130 0])),
  ("nothing moves, the page is on the target", (0, 0, [.idle 200 0, .down, .up, .idle 200 0])),
  ("one move away, long quiet", (0, 0, [.move 70, .idle 300 0])),
  ("pan toward the target", (0, 100, [.move 80, .idle 200 0])),
  ("pan toward, written, then away again", (0, 100, [.move 80, .idle 200 0, .move 50, .idle 200 0])),
  ("a touch stays down", (0, 100, [.down, .move 80, .idle 5000 0])),
  ("the target moves between waits", (0, 100, [.move 80, .idle 200 60, .move 70, .idle 200 0])),
  ("the target moves while the page is not quiet", (0, 100, [.move 80, .idle 50 0, .idle 100 20])),
  ("the target jumps over the page", (0, 0, [.move 70, .idle 300 90, .idle 300 0])),
  ("readings while a pan is live", (0, 0, liveEvents))]

def faithCases : List (String × Int × Int × List Int) := [
  ("the page springs out and back twice", (0, 0, [90, 60])),
  ("one overscroll", (0, 0, [90])),
  ("pan toward the target", (0, 100, [80, 60]))]

def traceCases : List (String × List String) := [
  ("nothing", []),
  ("every kind", ["inactive", "due", "touch", "moved", "write", "touching", "live", "onTarget", "reversal"]),
  ("a pan and a decline", ["touch", "moved", "moved", "due", "reversal", "touch"]),
  ("only inactive", ["inactive", "inactive"]),
  ("a write after waiting", ["moved", "due", "live", "due", "write"])]

open Lean in
def optJson : Option Int → Json
  | some a => toJson a
  | none => Json.null

open Lean in
def pinJson (p : Pin) : Json :=
  Json.mkObj [("touching", toJson p.touching), ("since", toJson p.since), ("a", optJson p.a), ("b", toJson p.b)]

open Lean in
def evJson : Ev → Json
  | .move y => Json.arr #[Json.str "move", toJson y]
  | .down => Json.arr #[Json.str "down"]
  | .up => Json.arr #[Json.str "up"]
  | .idle ms s => Json.arr #[Json.str "idle", toJson ms, toJson s]

open Lean in
def framesJson (l : List Int) : Json := Json.arr (l.map fun y => Json.arr #[toJson y, toJson (1 : Nat)]).toArray

open Lean in
def whyJson : Option Why → Json
  | some w => Json.str w.name
  | none => Json.null

open Lean in
def countsJson (c : TraceCounts) : Json :=
  Json.mkObj [("inactive", toJson c.inactive), ("due", toJson c.due), ("touches", toJson c.touches), ("moved", toJson c.moved),
    ("wrote", toJson c.wrote), ("touching", toJson c.touching), ("live", toJson c.live), ("onTarget", toJson c.onTarget),
    ("reversal", toJson c.reversal), ("declined", toJson c.declined), ("readings", toJson c.readings), ("ran", toJson c.ran)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "pinConstants"), ("quietMs", toJson quietMs)]).compress
  let ms := pinCases.map fun (name, p, s) =>
    (Json.mkObj [("op", "pinMay"), ("case", Json.str name), ("pin", pinJson p), ("s", toJson s),
      ("out", toJson (mayWrite p s)), ("why", whyJson (why p s))]).compress
  let os := observeCases.map fun (name, p, s, y, dt) =>
    let r := observe s p y dt
    (Json.mkObj [("op", "pinObserve"), ("case", Json.str name), ("pin", pinJson p), ("s", toJson s), ("y", toJson y), ("dt", toJson dt),
      ("pinOut", pinJson r.1), ("write", optJson r.2), ("outcome", Json.str (outcome s p y dt).name)]).compress
  let ds := dueCases.map fun (name, p, s) =>
    (Json.mkObj [("op", "pinDue"), ("case", Json.str name), ("pin", pinJson p), ("s", toJson s),
      ("out", match due p s with | some d => toJson d | none => Json.null), ("why", whyJson (dueWhy p s))]).compress
  let ts := [true, false].map fun down =>
    let p := (step (start 7) (if down then .down else .up)).1
    (Json.mkObj [("op", "pinTouch"), ("down", toJson down), ("pin", pinJson (start 7)), ("pinOut", pinJson p)]).compress
  let ps := playCases.map fun (name, s, y0, es) =>
    let out := play (start y0) es
    (Json.mkObj [("op", "pinPlay"), ("case", Json.str name), ("s", toJson s), ("y0", toJson y0), ("events", Json.arr (es.map evJson).toArray),
      ("positions", toJson out), ("writes", toJson (writes (start y0) es)), ("frames", framesJson (y0 :: out)),
      ("fights", toJson (fights s (run y0 es))), ("reversals", toJson (reversals (run y0 es))),
      ("writesLive", toJson (writesLive mayWrite (start y0) es)), ("faithPositions", toJson (playBy faithMay (start y0) es)),
      ("faithWritesLive", toJson (writesLive faithMay (start y0) es))]).compress
  let fs := faithCases.map fun (name, s, y0, ys) =>
    let out := faithOut s ys
    (Json.mkObj [("op", "pinFaith"), ("case", Json.str name), ("s", toJson s), ("y0", toJson y0), ("moves", toJson ys),
      ("events", Json.arr ((faithEvents s ys).map evJson).toArray), ("positions", toJson out), ("frames", framesJson (y0 :: out)),
      ("fights", toJson (fights s (faithRun s y0 ys))), ("writesLive", toJson (writesLive faithMay (start y0) (faithEvents s ys)))]).compress
  let cs := traceCases.map fun (name, l) =>
    (Json.mkObj [("op", "pinTrace"), ("case", Json.str name), ("names", toJson l), ("counts", countsJson (traceCounts l))]).compress
  [consts] ++ ms ++ os ++ ds ++ ts ++ ps ++ fs ++ cs

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

#guard mayWrite ⟨false, 200, some 80, 60⟩ 0 == true
#guard mayWrite ⟨false, 200, some 0, 90⟩ 0 == false
#guard play (start 0) declineEvents == [90]
#guard play (start 0) [.down, .move 90, .move 60, .move 30, .up, .idle 50 0, .idle 100 0] == [90, 60, 30, 0]
#guard play (start 100) [.move 80, .idle 200 60, .move 70, .idle 200 0] == [80, 60, 70]
#guard writesLive faithMay (start 0) (faithEvents 0 [90, 60]) == 2
#guard playBy faithMay (start 0) (faithEvents 0 [90, 60]) == [90, 0, 60, 0]
#guard writesLive mayWrite (start 0) liveEvents == 0

end Fw.Parts.EndPin
