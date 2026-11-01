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
  | idle (ms : Nat)
deriving Repr, BEq, DecidableEq

def reverses (a : Option Int) (b s : Int) : Bool :=
  match a with
  | none => false
  | some a' => decide ((b - a') * (s - b) < 0)

def mayWrite (p : Pin) (s : Int) : Bool :=
  !p.touching && decide (quietMs ≤ p.since) && decide (p.b ≠ s) && !reverses p.a p.b s

def step (s : Int) (p : Pin) : Ev → Pin × List Int
  | .move y => ({ p with since := 0, a := if y = p.b then p.a else some p.b, b := y }, [y])
  | .down => ({ p with touching := true, since := 0 }, [])
  | .up => ({ p with touching := false, since := 0 }, [])
  | .idle ms =>
    let q := { p with since := p.since + ms }
    if mayWrite q s then ({ q with since := 0, a := some q.b, b := s }, [s]) else (q, [])

def play (s : Int) : Pin → List Ev → List Int
  | _, [] => []
  | p, e :: es => (step s p e).2 ++ play s (step s p e).1 es

def writes (s : Int) : Pin → List Ev → List Int
  | _, [] => []
  | p, e :: es => (match e with | .idle _ => (step s p e).2 | _ => []) ++ writes s (step s p e).1 es

def start (y0 : Int) : Pin := ⟨false, 0, none, y0⟩

def run (s y0 : Int) (es : List Ev) : List Sample := ((y0 :: play s (start y0) es).map fun y => ⟨y, true⟩)

def faithOut (s : Int) : List Int → List Int
  | [] => []
  | y :: ys => if y = s then y :: faithOut s ys else y :: s :: faithOut s ys

def faithRun (s y0 : Int) (ys : List Int) : List Sample := ((y0 :: faithOut s ys).map fun y => ⟨y, true⟩)

def movesOf : List Ev → List Int
  | [] => []
  | .move y :: es => y :: movesOf es
  | _ :: es => movesOf es

theorem step_idle_writes (s : Int) (p : Pin) (ms : Nat) :
    (step s p (.idle ms)).2 = [] ∨ (step s p (.idle ms)).2 = [s] := by
  simp only [step]
  split <;> simp

theorem step_idle_write_iff (s : Int) (p : Pin) (ms : Nat) :
    (step s p (.idle ms)).2 = [s] ↔ mayWrite { p with since := p.since + ms } s = true := by
  simp only [step]
  split <;> simp_all

theorem no_write_touching (s : Int) (p : Pin) (ms : Nat) (h : p.touching = true) : (step s p (.idle ms)).2 = [] := by
  have : mayWrite { p with since := p.since + ms } s = false := by simp [mayWrite, h]
  simp [step, this]

theorem no_write_live (s : Int) (p : Pin) (ms : Nat) (h : p.since + ms < quietMs) : (step s p (.idle ms)).2 = [] := by
  have : mayWrite { p with since := p.since + ms } s = false := by
    simp [mayWrite, Nat.not_le.mpr h]
  simp [step, this]

theorem no_write_settled (s : Int) (p : Pin) (ms : Nat) (h : p.b = s) : (step s p (.idle ms)).2 = [] := by
  have : mayWrite { p with since := p.since + ms } s = false := by simp [mayWrite, h]
  simp [step, this]

theorem no_write_reversal (s : Int) (p : Pin) (ms : Nat) (h : reverses p.a p.b s = true) :
    (step s p (.idle ms)).2 = [] := by
  have : mayWrite { p with since := p.since + ms } s = false := by simp [mayWrite, h]
  simp [step, this]

theorem write_of_clear (s : Int) (p : Pin) (ms : Nat) (h1 : p.touching = false) (h2 : quietMs ≤ p.since + ms)
    (h3 : p.b ≠ s) (h4 : reverses p.a p.b s = false) : (step s p (.idle ms)).2 = [s] := by
  rw [step_idle_write_iff]
  simp [mayWrite, h1, h2, h3, h4]

theorem no_write_on_input (s : Int) (p : Pin) (e : Ev) (h : ∀ ms, e ≠ .idle ms) :
    (step s p e).2 = [] ∨ ∃ y, e = .move y ∧ (step s p e).2 = [y] := by
  cases e with
  | move y => exact Or.inr ⟨y, rfl, rfl⟩
  | down => exact Or.inl rfl
  | up => exact Or.inl rfl
  | idle ms => exact absurd rfl (h ms)

theorem write_is_target (s : Int) (p : Pin) (ms : Nat) (y : Int) (h : y ∈ (step s p (.idle ms)).2) : y = s := by
  rcases step_idle_writes s p ms with h' | h' <;> rw [h'] at h <;> simp_all

theorem writes_target (s : Int) :
    ∀ (es : List Ev) (p : Pin) (y : Int), y ∈ writes s p es → y = s := by
  intro es
  induction es with
  | nil => intro p y h; simp [writes] at h
  | cons e es ih =>
    intro p y h
    simp only [writes, List.mem_append] at h
    rcases h with h | h
    · cases e with
      | idle ms => exact write_is_target s p ms y h
      | move z => simp at h
      | down => simp at h
      | up => simp at h
    · exact ih _ y h

def tailTurns (pr : Int → Bool) : Option Int → Int → List Int → Nat
  | none, b, l => turns pr (b :: l)
  | some a, b, l => turnsFrom pr a b l

theorem dedupFrom_cons_eq (v y : Int) (l : List Int) (h : y = v) : dedupFrom v (y :: l) = dedupFrom v l := by
  simp [dedupFrom, h]

theorem dedupFrom_cons_ne (v y : Int) (l : List Int) (h : y ≠ v) : dedupFrom v (y :: l) = y :: dedupFrom y l := by
  simp [dedupFrom, h]

theorem play_no_turn (s : Int) :
    ∀ (es : List Ev) (p : Pin), (∀ y ∈ movesOf es, y ≠ s) →
      tailTurns (fun c => decide (c = s)) p.a p.b (dedupFrom p.b (play s p es)) = 0 := by
  intro es
  induction es with
  | nil => intro p _; cases p.a <;> simp [play, dedupFrom, tailTurns, turns, turnsFrom]
  | cons e es ih =>
    intro p hu
    cases e with
    | down =>
      have := ih { p with touching := true, since := 0 } (by simpa [movesOf] using hu)
      simpa [play, step] using this
    | up =>
      have := ih { p with touching := false, since := 0 } (by simpa [movesOf] using hu)
      simpa [play, step] using this
    | move y =>
      have hy : y ≠ s := hu y (by simp [movesOf])
      have hr : ∀ z ∈ movesOf es, z ≠ s := fun z hz => hu z (by simp [movesOf, hz])
      by_cases hb : y = p.b
      · have := ih { p with since := 0, a := p.a, b := y } hr
        subst hb
        simpa [play, step, dedupFrom_cons_eq] using this
      · have := ih { p with since := 0, a := some p.b, b := y } hr
        simp only [play, step, hb, ite_false, List.singleton_append, dedupFrom_cons_ne _ _ _ hb] at this ⊢
        cases ha : p.a with
        | none => simpa [tailTurns, turns, turnsFrom] using this
        | some a' => simpa [tailTurns, turnsFrom, hy] using this
    | idle ms =>
      by_cases hw : mayWrite { p with since := p.since + ms } s = true
      · have hne : p.b ≠ s := by
          simp only [mayWrite, Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at hw
          exact hw.1.2
        have hrev : reverses p.a p.b s = false := by
          simp only [mayWrite, Bool.and_eq_true, Bool.not_eq_true'] at hw
          exact hw.2
        have := ih { p with since := 0, a := some p.b, b := s } (by simpa [movesOf] using hu)
        simp only [play, step, hw, ite_true, List.singleton_append, dedupFrom_cons_ne _ _ _ (Ne.symm hne)] at this ⊢
        cases ha : p.a with
        | none => simpa [tailTurns, turns, turnsFrom] using this
        | some a' =>
          rw [ha] at hrev
          simp only [reverses, decide_eq_false_iff_not] at hrev
          simpa [tailTurns, turnsFrom, hrev] using this
      · have hw' : mayWrite { p with since := p.since + ms } s = false := by simpa using hw
        have := ih { p with since := p.since + ms } (by simpa [movesOf] using hu)
        simpa [play, step, hw'] using this

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

theorem pin_fights_zero (s y0 : Int) (es : List Ev) (h : ∀ y ∈ movesOf es, y ≠ s) : fights s (run s y0 es) = 0 := by
  have hs : (run s y0 es).map (·.y) = y0 :: play s (start y0) es := by simp [run, List.map_map, Function.comp_def]
  have ho : openPhase (run s y0 es) = run s y0 es := by
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

def declineEvents : List Ev := [.down, .move 90, .up, .idle 200]

theorem decline_fights_zero : fights 0 (run 0 0 declineEvents) = 0 := by decide

theorem decline_rests_off_target : (play 0 (start 0) declineEvents).getLast? = some 90 := by decide

theorem faith_ends_on_target : (faithOut 0 [90, 60]).getLast? = some 0 := by decide

theorem quiet_no_write (s : Int) :
    ∀ (es : List Ev) (p : Pin), p.b = s → movesOf es = [] → play s p es = [] := by
  intro es
  induction es with
  | nil => intro p _ _; rfl
  | cons e es ih =>
    intro p hb hm
    cases e with
    | move y => simp [movesOf] at hm
    | down => simpa [play, step] using ih { p with touching := true, since := 0 } hb (by simpa [movesOf] using hm)
    | up => simpa [play, step] using ih { p with touching := false, since := 0 } hb (by simpa [movesOf] using hm)
    | idle ms =>
      have := no_write_settled s p ms hb
      have h2 := ih { p with since := p.since + ms } hb (by simpa [movesOf] using hm)
      have hw : mayWrite { p with since := p.since + ms } s = false := by simp [mayWrite, hb]
      simpa [play, step, hw] using h2

def due (p : Pin) (s : Int) : Option Nat :=
  if p.touching = false ∧ p.b ≠ s ∧ reverses p.a p.b s = false ∧ p.since < quietMs then some (quietMs - p.since) else none

theorem due_write (p : Pin) (s : Int) (d : Nat) (h : due p s = some d) : (step s p (.idle d)).2 = [s] := by
  unfold due at h
  split at h
  · rename_i hc
    obtain ⟨h1, h2, h3, h4⟩ := hc
    have hd : d = quietMs - p.since := by simpa using h.symm
    exact write_of_clear s p d h1 (by omega) h2 h3
  · simp at h

theorem due_none_touching (p : Pin) (s : Int) (h : p.touching = true) : due p s = none := by
  simp [due, h]

theorem due_none_settled (p : Pin) (s : Int) (h : p.b = s) : due p s = none := by
  simp [due, h]

theorem due_none_reversal (p : Pin) (s : Int) (h : reverses p.a p.b s = true) : due p s = none := by
  simp [due, h]

def eventOf (p : Pin) (y : Int) (dt : Nat) : Ev := if y = p.b then .idle dt else .move y

def observe (s : Int) (p : Pin) (y : Int) (dt : Nat) : Pin × Option Int :=
  match eventOf p y dt with
  | .idle ms => ((step s p (.idle ms)).1, (step s p (.idle ms)).2.head?)
  | e => ((step s p e).1, none)

theorem observe_state (s : Int) (p : Pin) (y : Int) (dt : Nat) : (observe s p y dt).1 = (step s p (eventOf p y dt)).1 := by
  unfold observe eventOf
  split <;> simp_all [step]

theorem observe_move_silent (s : Int) (p : Pin) (y : Int) (dt : Nat) (h : y ≠ p.b) : (observe s p y dt).2 = none := by
  simp [observe, eventOf, h]

theorem observe_write (s : Int) (p : Pin) (y : Int) (dt : Nat) (w : Int) (h : (observe s p y dt).2 = some w) :
    y = p.b ∧ w = s ∧ mayWrite { p with since := p.since + dt } s = true := by
  by_cases hy : y = p.b
  · have hw : (observe s p y dt).2 = (step s p (.idle dt)).2.head? := by simp [observe, eventOf, hy]
    rw [hw] at h
    rcases step_idle_writes s p dt with h' | h'
    · rw [h'] at h; simp at h
    · rw [h'] at h
      simp only [List.head?_cons, Option.some.injEq] at h
      exact ⟨hy, h.symm, (step_idle_write_iff s p dt).mp h'⟩
  · rw [observe_move_silent s p y dt hy] at h; simp at h

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
  ("below the target, turning down", (⟨false, 200, some (-60), (-90)⟩, 0))]

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
  ("spring back lands on the target", (0, 0, [.down, .move 90, .move 60, .move 30, .up, .idle 50, .idle 100])),
  ("a pan away is left where it stopped", (0, 0, declineEvents)),
  ("momentum, then quiet", (0, 50, [.move 40, .move 30, .idle 16, .move 20, .idle 16, .move 10, .idle 130])),
  ("nothing moves, the page is on the target", (0, 0, [.idle 200, .down, .up, .idle 200])),
  ("one move away, long quiet", (0, 0, [.move 70, .idle 300])),
  ("pan toward the target", (0, 100, [.move 80, .idle 200])),
  ("pan toward, written, then away again", (0, 100, [.move 80, .idle 200, .move 50, .idle 200])),
  ("a touch stays down", (0, 100, [.down, .move 80, .idle 5000]))]

def faithCases : List (String × Int × Int × List Int) := [
  ("the page springs out and back twice", (0, 0, [90, 60])),
  ("one overscroll", (0, 0, [90])),
  ("pan toward the target", (0, 100, [80, 60]))]

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
  | .idle ms => Json.arr #[Json.str "idle", toJson ms]

open Lean in
def framesJson (l : List Int) : Json := Json.arr (l.map fun y => Json.arr #[toJson y, toJson (1 : Nat)]).toArray

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "pinConstants"), ("quietMs", toJson quietMs)]).compress
  let ms := pinCases.map fun (name, p, s) =>
    (Json.mkObj [("op", "pinMay"), ("case", Json.str name), ("pin", pinJson p), ("s", toJson s),
      ("out", toJson (mayWrite p s))]).compress
  let os := observeCases.map fun (name, p, s, y, dt) =>
    let r := observe s p y dt
    (Json.mkObj [("op", "pinObserve"), ("case", Json.str name), ("pin", pinJson p), ("s", toJson s), ("y", toJson y), ("dt", toJson dt),
      ("pinOut", pinJson r.1), ("write", optJson r.2)]).compress
  let ds := dueCases.map fun (name, p, s) =>
    (Json.mkObj [("op", "pinDue"), ("case", Json.str name), ("pin", pinJson p), ("s", toJson s),
      ("out", match due p s with | some d => toJson d | none => Json.null)]).compress
  let ts := [true, false].map fun down =>
    let p := (step 0 (start 7) (if down then .down else .up)).1
    (Json.mkObj [("op", "pinTouch"), ("down", toJson down), ("pin", pinJson (start 7)), ("pinOut", pinJson p)]).compress
  let ps := playCases.map fun (name, s, y0, es) =>
    let out := play s (start y0) es
    (Json.mkObj [("op", "pinPlay"), ("case", Json.str name), ("s", toJson s), ("y0", toJson y0), ("events", Json.arr (es.map evJson).toArray),
      ("positions", toJson out), ("writes", toJson (writes s (start y0) es)), ("frames", framesJson (y0 :: out)),
      ("fights", toJson (fights s (run s y0 es))), ("reversals", toJson (reversals (run s y0 es)))]).compress
  let fs := faithCases.map fun (name, s, y0, ys) =>
    let out := faithOut s ys
    (Json.mkObj [("op", "pinFaith"), ("case", Json.str name), ("s", toJson s), ("y0", toJson y0), ("moves", toJson ys),
      ("positions", toJson out), ("frames", framesJson (y0 :: out)),
      ("fights", toJson (fights s (faithRun s y0 ys)))]).compress
  [consts] ++ ms ++ os ++ ds ++ ts ++ ps ++ fs

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

#guard mayWrite ⟨false, 200, some 80, 60⟩ 0 == true
#guard mayWrite ⟨false, 200, some 0, 90⟩ 0 == false
#guard play 0 (start 0) declineEvents == [90]
#guard play 0 (start 0) [.down, .move 90, .move 60, .move 30, .up, .idle 50, .idle 100] == [90, 60, 30, 0]

end Fw.Parts.EndPin
