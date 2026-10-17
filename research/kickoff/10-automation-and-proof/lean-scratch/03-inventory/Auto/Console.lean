import Std.Data.HashMap
import Std.Data.HashSet
import Lean.Data.Json
/-!
# Sketch 1: the console reducer (requirement 1: status is derived, never hand-maintained)

The console state is a pure fold of the event log. Agents and scripts *emit events*; nobody
writes status. The executable reducer uses `Std.HashMap`/`Std.HashSet` (the real data structures
an exe would use), and the theorems are about that same code.

math (for the reader):
  S_n = apply(… apply(apply(S_0, e_1), e_2) …, e_n)            -- state = fold of the log
  replay(L₁ ++ L₂) = replayFrom(replay(L₁), L₂)                 -- snapshot + tail = full replay
  apply(apply(S, e), e) = apply(S, e)                           -- duplicate delivery is harmless
  #{ i ≤ n : e_i = answer(k, ·) and e_i was accepted } ≤ 1       -- a step is answered at most once
  e is not a step event ⇒ needsYou(apply(S, e)) = needsYou(S)   -- only steps can ask for the user
-/
namespace Auto.Console
open Std

inductive St where
  | pending | active | answered | skipped | cancelled
deriving Repr, DecidableEq, BEq, Lean.ToJson, Lean.FromJson

def St.isOpen : St → Bool
  | .pending | .active => true
  | _ => false

/-- Event bodies. `note` is everything an agent says about itself (it can never set status). -/
inductive Body where
  | post (step : Nat)
  | start (step : Nat)
  | answer (step : Nat) (text : String)
  | skip (step : Nat)
  | cancel (step : Nat)
  | startOver (step : Nat)
  | note (row : String) (text : String)
deriving Repr, Lean.ToJson, Lean.FromJson

structure Event where
  eid  : Nat      -- unique event id (assigned by the writer; duplicates are re-deliveries)
  body : Body
deriving Repr, Lean.ToJson, Lean.FromJson

structure State where
  steps : HashMap Nat St := {}
  seen  : HashSet Nat := {}

/-- Transition of one step. `none` = refused (the event is logged but changes nothing). -/
def stepNext : Option St → Body → Option St
  | none,            .post _     => some .pending
  | some .pending,   .start _    => some .active
  | some .active,    .answer _ _ => some .answered
  | some .pending,   .skip _     => some .skipped
  | some .active,    .skip _     => some .skipped
  | some .pending,   .cancel _   => some .cancelled
  | some .active,    .cancel _   => some .cancelled
  | some .active,    .startOver _ => some .active
  | _,               _           => none

def Body.step? : Body → Option Nat
  | .post k | .start k | .answer k _ | .skip k | .cancel k | .startOver k => some k
  | .note _ _ => none

def Body.isAnswerFor (k : Nat) : Body → Bool
  | .answer j _ => j == k
  | _ => false

/-- Apply one body. Returns the new state and whether it was accepted. -/
def applyBody (s : State) (b : Body) : State × Bool :=
  match b.step? with
  | none => (s, true)
  | some k =>
    match stepNext s.steps[k]? b with
    | some st => ({ s with steps := s.steps.insert k st }, true)
    | none    => (s, false)

/-- Apply one event: a re-delivered event id is a no-op (at-least-once delivery is safe). -/
def apply (s : State) (e : Event) : State × Bool :=
  if s.seen.contains e.eid then (s, false)
  else
    let (s', ok) := applyBody s e.body
    ({ s' with seen := s'.seen.insert e.eid }, ok)

def replayFrom (s : State) (log : List Event) : State := log.foldl (fun s e => (apply s e).1) s
def replay (log : List Event) : State := replayFrom {} log

/-- The user-facing projection. Derived; there is no field an agent could set. -/
def needsYou (s : State) : Bool := s.steps.toList.any (fun p => p.2.isOpen)

/-! ## Theorems -/

/-- Snapshot + tail = full replay (so a restart from a snapshot is exact). -/
theorem replay_append (l₁ l₂ : List Event) :
    replay (l₁ ++ l₂) = replayFrom (replay l₁) l₂ := by
  simp [replay, replayFrom, List.foldl_append]

/-- Duplicate delivery of the same event is a no-op. -/
theorem apply_idem (s : State) (e : Event) : (apply (apply s e).1 e).1 = (apply s e).1 := by
  unfold apply
  by_cases h : s.seen.contains e.eid
  · simp [h]
  · simp [h]

/-- `answered` is absorbing: no event moves a step out of it. -/
theorem stepNext_answered (b : Body) : stepNext (some .answered) b = none := by
  cases b <;> rfl

theorem applyBody_keeps_answered (s : State) (b : Body) (k : Nat)
    (h : s.steps[k]? = some .answered) : (applyBody s b).1.steps[k]? = some .answered := by
  unfold applyBody
  split
  · exact h
  · rename_i j _
    split
    · rename_i st hst
      simp only [HashMap.getElem?_insert]
      by_cases hjk : j = k
      · subst hjk; rw [h, stepNext_answered] at hst; cases hst
      · simp [hjk, h]
    · exact h

theorem apply_keeps_answered (s : State) (e : Event) (k : Nat)
    (h : s.steps[k]? = some .answered) : (apply s e).1.steps[k]? = some .answered := by
  unfold apply
  split
  · exact h
  · exact applyBody_keeps_answered s e.body k h

/-- An accepted answer for step `k` leaves `k` answered. -/
theorem apply_answer_sets (s : State) (e : Event) (k : Nat)
    (hb : e.body.isAnswerFor k = true) (ok : (apply s e).2 = true) :
    (apply s e).1.steps[k]? = some .answered := by
  unfold apply at *
  split at ok
  · cases ok
  · rename_i hseen
    simp only [hseen] at *
    cases hbody : e.body with
    | answer j t =>
      rw [hbody] at hb ok
      simp [Body.isAnswerFor] at hb; subst hb
      simp only [applyBody, Body.step?] at ok ⊢
      split at ok
      · rename_i st hst
        cases h0 : s.steps[j]? with
        | none => rw [h0] at hst; cases hst
        | some x => rw [h0] at hst; cases x <;> simp [stepNext] at hst; simp [← hst]
      · cases ok
    | _ => rw [hbody] at hb; simp [Body.isAnswerFor] at hb

/-- Accepted answers for step `k` along a log, starting from `s`. -/
def answersAccepted (k : Nat) : State → List Event → Nat
  | _, [] => 0
  | s, e :: es =>
    (if (apply s e).2 && e.body.isAnswerFor k then 1 else 0) + answersAccepted k (apply s e).1 es

/-- Once answered, never answered again. -/
theorem answers_after_answered (k : Nat) (es : List Event) :
    ∀ s : State, s.steps[k]? = some .answered → answersAccepted k s es = 0 := by
  induction es with
  | nil => intro s _; rfl
  | cons e es ih =>
    intro s h
    simp only [answersAccepted]
    have hk := apply_keeps_answered s e k h
    rw [ih _ hk]
    -- the head event cannot be an accepted answer either
    cases hok : (apply s e).2 <;> cases hb : e.body.isAnswerFor k <;> simp
    -- accepted answer from an answered step is impossible
    unfold apply at hok
    split at hok
    · cases hok
    · cases hbody : e.body with
      | answer j t =>
        rw [hbody] at hb hok; simp [Body.isAnswerFor] at hb; subst hb
        simp [applyBody, Body.step?, h, stepNext_answered] at hok
      | _ => rw [hbody] at hb; simp [Body.isAnswerFor] at hb

/-- **A step is answered at most once**, over any log, from any state. -/
theorem answer_at_most_once (k : Nat) (es : List Event) :
    ∀ s : State, answersAccepted k s es ≤ 1 := by
  induction es with
  | nil => intro s; simp [answersAccepted]
  | cons e es ih =>
    intro s
    simp only [answersAccepted]
    by_cases hc : ((apply s e).2 && e.body.isAnswerFor k) = true
    · simp only [hc, ite_true]
      have ⟨h1, h2⟩ : (apply s e).2 = true ∧ e.body.isAnswerFor k = true := by
        simpa using hc
      rw [answers_after_answered k es _ (apply_answer_sets s e k h2 h1)]
      omega
    · simp only [hc]; have := ih (apply s e).1; simp; omega

/-- Agent notes can never change what the user is asked to do. -/
theorem note_preserves_needsYou (s : State) (eid : Nat) (r t : String) :
    needsYou (apply s ⟨eid, .note r t⟩).1 = needsYou s := by
  unfold apply
  split <;> simp [applyBody, Body.step?, needsYou]

/-! ## Examples (run at build time) -/
def demo : List Event :=
  [⟨1, .post 7⟩, ⟨2, .start 7⟩, ⟨3, .note "fix-hero" "waiting"⟩, ⟨4, .answer 7 "done"⟩,
   ⟨4, .answer 7 "done"⟩, ⟨5, .answer 7 "again"⟩]

#guard (replay demo).steps[7]? == some .answered
#guard answersAccepted 7 {} demo == 1
#guard needsYou (replay (demo.take 3)) == true
#guard needsYou (replay demo) == false

end Auto.Console
