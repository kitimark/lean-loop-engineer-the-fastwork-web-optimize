import Lean.Data.Json
import Fw.Gate.Smooth
/-!
# Fw.Measure.TouchLock: does the end-of-page scroll lock fight a touch pan in the Simulator?
-/
namespace Fw.Measure.TouchLock

structure Sample where
  y : Int
  isOpen : Bool
deriving Repr, BEq

def openPhase (xs : List Sample) : List Sample :=
  (xs.dropWhile (fun s => !s.isOpen)).takeWhile (fun s => s.isOpen)

structure Run where
  frames : List Sample
  events : List Sample
  calls : List Sample
deriving Repr, BEq

def storedLock (calls : List Sample) : Option Int := (calls.find? (·.isOpen)).map (·.y)

def lockOf (r : Run) : Option Int := storedLock r.calls

def lockSteady (r : Run) : Bool :=
  match lockOf r with
  | none => true
  | some s => ((r.calls.filter (·.isOpen)).all fun c => decide (c.y = s))

def dedupFrom (prev : Int) : List Int → List Int
  | [] => []
  | x :: xs => if x = prev then dedupFrom prev xs else x :: dedupFrom x xs

def dedup : List Int → List Int
  | [] => []
  | x :: xs => x :: dedupFrom x xs

def turnsFrom (p : Int → Bool) (a b : Int) : List Int → Nat
  | [] => 0
  | c :: rest => (if (b - a) * (c - b) < 0 && p c then 1 else 0) + turnsFrom p b c rest

def turns (p : Int → Bool) : List Int → Nat
  | a :: b :: rest => turnsFrom p a b rest
  | _ => 0

def positions (xs : List Sample) : List Int := dedup ((openPhase xs).map (·.y))

def reversals (xs : List Sample) : Nat := turns (fun _ => true) (positions xs)

def fights (s : Int) (xs : List Sample) : Nat := turns (fun c => decide (c = s)) (positions xs)

def displaced (s : Int) (xs : List Sample) : Nat := ((openPhase xs).filter (fun x => decide (x.y ≠ s))).length

def fightsAt (s : Option Int) (xs : List Sample) : Nat := s.elim 0 (fights · xs)

def displacedAt (s : Option Int) (xs : List Sample) : Nat := s.elim 0 (displaced · xs)

def minOpenFrames : Nat := 10

inductive Refusal where
  | noOpen | tooShort | lockMoved
deriving Repr, BEq, DecidableEq

def Refusal.name : Refusal → String
  | .noOpen => "noOpen"
  | .tooShort => "tooShort"
  | .lockMoved => "lockMoved"

def refusal (r : Run) : Option Refusal :=
  if (openPhase r.frames).length = 0 then some .noOpen
  else if (openPhase r.frames).length < minOpenFrames then some .tooShort
  else if lockSteady r then none
  else some .lockMoved

structure Result where
  openFrames : Nat
  displacedFrames : Nat
  frameReversals : Nat
  frameFights : Nat
  restores : Nat
  eventReversals : Nat
  eventFights : Nat
  jitter : Bool
  lock : Option Int
  openCalls : Nat
deriving Repr, BEq

def openCalls (r : Run) : Nat := (r.calls.filter (·.isOpen)).length

def reduce (r : Run) : Result :=
  let s := lockOf r
  { openFrames := (openPhase r.frames).length, displacedFrames := displacedAt s r.frames,
    frameReversals := reversals r.frames, frameFights := fightsAt s r.frames,
    restores := displacedAt s r.events, eventReversals := reversals r.events, eventFights := fightsAt s r.events,
    jitter := decide (0 < fightsAt s r.frames), lock := s, openCalls := openCalls r }

inductive Cmp where
  | lower | higher | overlap
deriving Repr, BEq, DecidableEq

def Cmp.name : Cmp → String
  | .lower => "lower"
  | .higher => "higher"
  | .overlap => "overlap"

def maxOf (xs : List Nat) : Nat := xs.foldl max 0
def minOf (xs : List Nat) : Nat := xs.foldl min (xs.foldl max 0)

def cmp (faith cand : List Nat) : Cmp :=
  if faith.isEmpty || cand.isEmpty then .overlap
  else if maxOf cand < minOf faith then .lower
  else if maxOf faith < minOf cand then .higher
  else .overlap

inductive Look where
  | same | change
deriving Repr, BEq, DecidableEq

def Look.name : Look → String
  | .same => "same"
  | .change => "change"

def look (faith cand : List Nat) : Look :=
  if faith.all (· = 0) && cand.all (· = 0) then .same else .change

def minSamples : Nat := 3

def known (faith cand : List Nat) : Bool := decide (minSamples ≤ faith.length) && decide (minSamples ≤ cand.length)

/-- `cmp` when both sides hold `minSamples`, `none` (undecided) otherwise. -/
def cmpKnown (faith cand : List Nat) : Option Cmp := if known faith cand then some (cmp faith cand) else none

/-- `look` when both sides hold `minSamples`, `none` (undecided) otherwise. -/
def lookKnown (faith cand : List Nat) : Option Look := if known faith cand then some (look faith cand) else none

def optName {α : Type} (name : α → String) : Option α → String
  | some a => name a
  | none => "undecided"

def tally (rs : List Run) : Nat × Nat :=
  let ok := rs.filter (fun r => (refusal r).isNone)
  (ok.length, (ok.filter (fun r => (reduce r).jitter)).length)

theorem openPhase_nil : openPhase [] = [] := rfl

theorem openPhase_closed (xs : List Sample) (h : ∀ x ∈ xs, x.isOpen = false) : openPhase xs = [] := by
  induction xs with
  | nil => rfl
  | cons a t ih =>
    have ha := h a (by simp)
    simp [openPhase, List.dropWhile, ha] at *
    exact ih (fun x hx => h x (by simp [hx]))

theorem refusal_noOpen (r : Run) (h : (openPhase r.frames).length = 0) : refusal r = some .noOpen := by
  simp [refusal, h]

theorem refusal_tooShort (r : Run) (h0 : (openPhase r.frames).length ≠ 0) (h1 : (openPhase r.frames).length < minOpenFrames) :
    refusal r = some .tooShort := by
  simp [refusal, h0, h1]

theorem refusal_lockMoved (r : Run) (h1 : minOpenFrames ≤ (openPhase r.frames).length) (h2 : lockSteady r = false) :
    refusal r = some .lockMoved := by
  have h0 : (openPhase r.frames).length ≠ 0 := by unfold minOpenFrames at h1; omega
  have h3 : ¬ (openPhase r.frames).length < minOpenFrames := by omega
  simp [refusal, h0, h3, h2]

theorem refusal_none_iff (r : Run) :
    refusal r = none ↔ minOpenFrames ≤ (openPhase r.frames).length ∧ lockSteady r = true := by
  unfold refusal minOpenFrames
  by_cases h0 : (openPhase r.frames).length = 0 <;> by_cases h1 : (openPhase r.frames).length < 10 <;>
    by_cases h2 : lockSteady r = true <;> simp [h0, h1, h2] <;> omega

theorem dedupFrom_const (v : Int) (l : List Int) (h : ∀ y ∈ l, y = v) : dedupFrom v l = [] := by
  induction l with
  | nil => rfl
  | cons a t ih =>
    have ha := h a (by simp)
    simp [dedupFrom, ha]
    exact ih (fun y hy => h y (by simp [hy]))

theorem turns_singleton (p : Int → Bool) (a : Int) : turns p [a] = 0 := rfl

theorem turns_const (p : Int → Bool) (v : Int) (l : List Int) (h : ∀ y ∈ l, y = v) : turns p (dedup l) = 0 := by
  cases l with
  | nil => rfl
  | cons a t =>
    have ha := h a (by simp)
    have := dedupFrom_const a t (fun y hy => by rw [h y (by simp [hy]), ha])
    simp [dedup, this, turns]

theorem turnsFrom_le (p : Int → Bool) (a b : Int) (l : List Int) : turnsFrom p a b l ≤ turnsFrom (fun _ => true) a b l := by
  induction l generalizing a b with
  | nil => simp [turnsFrom]
  | cons c t ih =>
    simp only [turnsFrom]
    have := ih b c
    by_cases h : (b - a) * (c - b) < 0 <;> by_cases hp : p c = true <;> simp [h, hp] <;> omega

theorem turns_le (p : Int → Bool) (l : List Int) : turns p l ≤ turns (fun _ => true) l := by
  match l with
  | a :: b :: rest => exact turnsFrom_le p a b rest
  | [] => simp [turns]
  | [_] => simp [turns]

theorem fights_le_reversals (s : Int) (xs : List Sample) : fights s xs ≤ reversals xs := turns_le _ _

theorem fights_zero_of_steady (s : Int) (xs : List Sample) (h : ∀ x ∈ openPhase xs, x.y = s) : fights s xs = 0 := by
  unfold fights positions
  exact turns_const _ s _ (by intro y hy; obtain ⟨x, hx, rfl⟩ := List.mem_map.mp hy; exact h x hx)

theorem reversals_zero_of_steady (s : Int) (xs : List Sample) (h : ∀ x ∈ openPhase xs, x.y = s) : reversals xs = 0 := by
  unfold reversals positions
  exact turns_const _ s _ (by intro y hy; obtain ⟨x, hx, rfl⟩ := List.mem_map.mp hy; exact h x hx)

theorem displaced_zero_iff (s : Int) (xs : List Sample) : displaced s xs = 0 ↔ ∀ x ∈ openPhase xs, x.y = s := by
  unfold displaced
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  simp

theorem jitter_iff (r : Run) : (reduce r).jitter = true ↔ 0 < (reduce r).frameFights := by
  simp [reduce]

theorem fightsAt_none (xs : List Sample) : fightsAt none xs = 0 := rfl

theorem fightsAt_some (s : Int) (xs : List Sample) : fightsAt (some s) xs = fights s xs := rfl

theorem displacedAt_none (xs : List Sample) : displacedAt none xs = 0 := rfl

theorem displacedAt_some (s : Int) (xs : List Sample) : displacedAt (some s) xs = displaced s xs := rfl

theorem jitter_false_of_steady (r : Run) (h : displacedAt (lockOf r) r.frames = 0) : (reduce r).jitter = false := by
  cases hl : lockOf r with
  | none => simp [reduce, hl, fightsAt_none]
  | some s =>
    rw [hl, displacedAt_some] at h
    have := fights_zero_of_steady s r.frames ((displaced_zero_iff _ _).mp h)
    simp [reduce, hl, fightsAt_some, this]

theorem lockOf_frames_irrelevant (f f' e e' c : List Sample) : lockOf ⟨f, e, c⟩ = lockOf ⟨f', e', c⟩ := rfl

theorem lockOf_none_iff (r : Run) : lockOf r = none ↔ ∀ c ∈ r.calls, c.isOpen = false := by
  unfold lockOf storedLock
  rw [Option.map_eq_none_iff, List.find?_eq_none]
  simp

theorem lockOf_some (r : Run) (s : Int) (h : lockOf r = some s) : ∃ c ∈ r.calls, c.isOpen = true ∧ c.y = s := by
  unfold lockOf storedLock at h
  obtain ⟨c, hc, rfl⟩ := Option.map_eq_some_iff.mp h
  exact ⟨c, List.mem_of_find?_eq_some hc, by simpa using List.find?_some hc, rfl⟩

theorem storedLock_closed (y : Int) (cs : List Sample) : storedLock (⟨y, false⟩ :: cs) = storedLock cs := by
  simp [storedLock, List.find?]

theorem storedLock_open (y : Int) (cs : List Sample) : storedLock (⟨y, true⟩ :: cs) = some y := by
  simp [storedLock, List.find?]

theorem fights_zero_of_unrestored (r : Run) (h : lockOf r = none) : (reduce r).frameFights = 0 := by
  simp [reduce, h, fightsAt_none]

theorem openCalls_zero_iff (r : Run) : openCalls r = 0 ↔ lockOf r = none := by
  rw [lockOf_none_iff]
  unfold openCalls
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  simp

theorem displaced_zero_of_unrestored (r : Run) (h : openCalls r = 0) : displacedAt (lockOf r) r.frames = 0 := by
  rw [(openCalls_zero_iff r).mp h]
  rfl

theorem lockSteady_iff (r : Run) (s : Int) (h : lockOf r = some s) :
    lockSteady r = true ↔ ∀ c ∈ r.calls, c.isOpen = true → c.y = s := by
  simp only [lockSteady, h, List.all_eq_true, List.mem_filter, decide_eq_true_eq, and_imp]

theorem cmp_empty_faith (cand : List Nat) : cmp [] cand = .overlap := by simp [cmp]

theorem cmp_empty_cand (faith : List Nat) : cmp faith [] = .overlap := by simp [cmp]

theorem cmp_lower (faith cand : List Nat) (hf : faith.isEmpty = false) (hc : cand.isEmpty = false)
    (h : maxOf cand < minOf faith) : cmp faith cand = .lower := by
  simp [cmp, hf, hc, h]

theorem cmp_higher (faith cand : List Nat) (hf : faith.isEmpty = false) (hc : cand.isEmpty = false)
    (h1 : ¬ maxOf cand < minOf faith) (h2 : maxOf faith < minOf cand) : cmp faith cand = .higher := by
  simp [cmp, hf, hc, h1, h2]

theorem cmp_overlap (faith cand : List Nat) (hf : faith.isEmpty = false) (hc : cand.isEmpty = false)
    (h1 : ¬ maxOf cand < minOf faith) (h2 : ¬ maxOf faith < minOf cand) : cmp faith cand = .overlap := by
  simp [cmp, hf, hc, h1, h2]

theorem look_same (faith cand : List Nat) (hf : ∀ x ∈ faith, x = 0) (hc : ∀ x ∈ cand, x = 0) : look faith cand = .same := by
  have h : (faith.all (· = 0) && cand.all (· = 0)) = true := by simpa using And.intro hf hc
  simp [look, h]

theorem look_change_faith (faith cand : List Nat) (x : Nat) (hx : x ∈ faith) (h : x ≠ 0) : look faith cand = .change := by
  simp only [look]
  have : faith.all (· = 0) = false := by
    rw [List.all_eq_false]; exact ⟨x, hx, by simpa using h⟩
  simp [this]

theorem look_change_cand (faith cand : List Nat) (x : Nat) (hx : x ∈ cand) (h : x ≠ 0) : look faith cand = .change := by
  simp only [look]
  have : cand.all (· = 0) = false := by
    rw [List.all_eq_false]; exact ⟨x, hx, by simpa using h⟩
  simp [this]

theorem cmp_lower_nonempty (faith cand : List Nat) (h : cmp faith cand = .lower) : faith ≠ [] ∧ cand ≠ [] := by
  constructor <;> rintro rfl <;> simp [cmp_empty_faith, cmp_empty_cand] at h

theorem known_iff (faith cand : List Nat) :
    known faith cand = true ↔ minSamples ≤ faith.length ∧ minSamples ≤ cand.length := by
  simp [known]

theorem known_ne_nil (faith cand : List Nat) (h : known faith cand = true) : faith ≠ [] ∧ cand ≠ [] := by
  rw [known_iff] at h
  constructor <;> rintro rfl <;> simp [minSamples] at h

theorem cmpKnown_empty_faith (cand : List Nat) : cmpKnown [] cand = none := by simp [cmpKnown, known, minSamples]

theorem cmpKnown_empty_cand (faith : List Nat) : cmpKnown faith [] = none := by simp [cmpKnown, known, minSamples]

theorem cmpKnown_short (faith cand : List Nat) (h : faith.length < minSamples ∨ cand.length < minSamples) :
    cmpKnown faith cand = none := by
  rcases h with h | h <;> simp [cmpKnown, known, Nat.not_le.mpr h]

theorem cmpKnown_one_faith (x : Nat) (cand : List Nat) : cmpKnown [x] cand = none := by
  apply cmpKnown_short; left; simp [minSamples]

theorem cmpKnown_one_cand (faith : List Nat) (y : Nat) : cmpKnown faith [y] = none := by
  apply cmpKnown_short; right; simp [minSamples]

theorem cmpKnown_some_needs (faith cand : List Nat) (c : Cmp) (h : cmpKnown faith cand = some c) :
    minSamples ≤ faith.length ∧ minSamples ≤ cand.length := by
  unfold cmpKnown known at h
  split at h
  · rename_i hk; simpa using hk
  · simp at h

theorem cmpKnown_of_known (faith cand : List Nat) (h : known faith cand = true) :
    cmpKnown faith cand = some (cmp faith cand) := by simp [cmpKnown, h]

theorem lookKnown_empty_faith (cand : List Nat) : lookKnown [] cand = none := by simp [lookKnown, known, minSamples]

theorem lookKnown_empty_cand (faith : List Nat) : lookKnown faith [] = none := by simp [lookKnown, known, minSamples]

theorem lookKnown_short (faith cand : List Nat) (h : faith.length < minSamples ∨ cand.length < minSamples) :
    lookKnown faith cand = none := by
  rcases h with h | h <;> simp [lookKnown, known, Nat.not_le.mpr h]

theorem lookKnown_one_faith (x : Nat) (cand : List Nat) : lookKnown [x] cand = none := by
  apply lookKnown_short; left; simp [minSamples]

theorem lookKnown_one_cand (faith : List Nat) (y : Nat) : lookKnown faith [y] = none := by
  apply lookKnown_short; right; simp [minSamples]

theorem lookKnown_some_needs (faith cand : List Nat) (l : Look) (h : lookKnown faith cand = some l) :
    minSamples ≤ faith.length ∧ minSamples ≤ cand.length := by
  unfold lookKnown known at h
  split at h
  · rename_i hk; simpa using hk
  · simp at h

theorem lookKnown_of_known (faith cand : List Nat) (h : known faith cand = true) :
    lookKnown faith cand = some (look faith cand) := by simp [lookKnown, h]

structure Counted where
  lock : Option Int
  n : Nat
deriving Repr, BEq

def lockedOf (ks : List Counted) : List Nat := (ks.filter (·.lock.isSome)).map (·.n)

inductive LockedCmp where
  | undecided | na | out (c : Cmp)
deriving Repr, DecidableEq

def LockedCmp.name : LockedCmp → String
  | .undecided => "undecided"
  | .na => "n/a"
  | .out c => c.name

def lockedCmp (faith cand : List Counted) : LockedCmp :=
  if faith.isEmpty || cand.isEmpty then .undecided
  else if (lockedOf faith).isEmpty || (lockedOf cand).isEmpty then .na
  else match cmpKnown (lockedOf faith) (lockedOf cand) with
    | some c => .out c
    | none => .undecided

theorem lockedOf_none (ks : List Counted) (h : ∀ k ∈ ks, k.lock = none) : lockedOf ks = [] := by
  unfold lockedOf
  rw [List.map_eq_nil_iff, List.filter_eq_nil_iff]
  intro k hk
  simp [h k hk]

theorem lockedCmp_na_cand (faith cand : List Counted) (hf : faith ≠ []) (hc : cand ≠ []) (h : ∀ k ∈ cand, k.lock = none) :
    lockedCmp faith cand = .na := by
  have hl := lockedOf_none cand h
  have h1 : faith.isEmpty = false := by simpa using hf
  have h2 : cand.isEmpty = false := by simpa using hc
  simp [lockedCmp, h1, h2, hl]

theorem lockedCmp_na_faith (faith cand : List Counted) (hf : faith ≠ []) (hc : cand ≠ []) (h : ∀ k ∈ faith, k.lock = none) :
    lockedCmp faith cand = .na := by
  have hl := lockedOf_none faith h
  have h1 : faith.isEmpty = false := by simpa using hf
  have h2 : cand.isEmpty = false := by simpa using hc
  simp [lockedCmp, h1, h2, hl]

theorem lockedCmp_undecided_empty_faith (cand : List Counted) : lockedCmp [] cand = .undecided := by simp [lockedCmp]

theorem lockedCmp_undecided_empty_cand (faith : List Counted) : lockedCmp faith [] = .undecided := by simp [lockedCmp]

theorem lockedCmp_out_locked (faith cand : List Counted) (c : Cmp) (h : lockedCmp faith cand = .out c) :
    lockedOf faith ≠ [] ∧ lockedOf cand ≠ [] := by
  unfold lockedCmp at h
  split at h
  · simp at h
  · split at h
    · simp at h
    · rename_i _ h2
      simp only [Bool.or_eq_true, not_or] at h2
      constructor <;> intro e <;> simp_all

theorem lockedCmp_all_locked (faith cand : List Counted) (hf : ∀ k ∈ faith, k.lock.isSome = true) (hc : ∀ k ∈ cand, k.lock.isSome = true)
    (c : Cmp) (h : cmpKnown (faith.map (·.n)) (cand.map (·.n)) = some c) : lockedCmp faith cand = .out c := by
  have e1 : lockedOf faith = faith.map (·.n) := by
    unfold lockedOf; rw [List.filter_eq_self.mpr (by simpa using hf)]
  have e2 : lockedOf cand = cand.map (·.n) := by
    unfold lockedOf; rw [List.filter_eq_self.mpr (by simpa using hc)]
  have hk := cmpKnown_some_needs _ _ _ h
  have hfne : faith ≠ [] := by rintro rfl; simp [minSamples] at hk
  have hcne : cand ≠ [] := by rintro rfl; simp [minSamples] at hk
  have h1 : faith.isEmpty = false := by simpa using hfne
  have h2 : cand.isEmpty = false := by simpa using hcne
  have n1 : (faith.map (·.n)).isEmpty = false := by simpa using hfne
  have n2 : (cand.map (·.n)).isEmpty = false := by simpa using hcne
  simp [lockedCmp, h1, h2, e1, e2, n1, n2, h]

theorem tally_le (rs : List Run) : (tally rs).2 ≤ (tally rs).1 := by
  simp only [tally]
  exact List.length_filter_le _ _

open Fw.Gate.Smooth (Verdict)

def pinVerdict : LockedCmp → Verdict
  | .out .lower => .second
  | .out .higher => .first
  | .out .overlap => .same
  | .na => .insufficient
  | .undecided => .insufficient

def pinDecisive (vs : List LockedCmp) : Nat := Fw.Gate.Smooth.decisive (vs.map pinVerdict)

def acrossPin (vs : List LockedCmp) : Verdict := Fw.Gate.Smooth.acrossDecisive (vs.map pinVerdict)

theorem minSamples_eq : minSamples = Fw.Gate.Smooth.minSamples := rfl

theorem pinVerdict_lower : pinVerdict (.out .lower) = .second := rfl

theorem pinVerdict_higher : pinVerdict (.out .higher) = .first := rfl

theorem pinVerdict_overlap : pinVerdict (.out .overlap) = .same := rfl

theorem pinVerdict_na : pinVerdict .na = .insufficient := rfl

theorem pinVerdict_undecided : pinVerdict .undecided = .insufficient := rfl

theorem count_second (vs : List LockedCmp) : (vs.map pinVerdict).count Verdict.second = vs.count (.out .lower) := by
  induction vs with
  | nil => rfl
  | cons c cs ih =>
    simp only [List.map_cons, List.count_cons, ih]
    cases c with
    | undecided => simp [pinVerdict] <;> decide
    | na => simp [pinVerdict] <;> decide
    | out c => cases c <;> simp [pinVerdict] <;> decide

theorem count_first (vs : List LockedCmp) : (vs.map pinVerdict).count Verdict.first = vs.count (.out .higher) := by
  induction vs with
  | nil => rfl
  | cons c cs ih =>
    simp only [List.map_cons, List.count_cons, ih]
    cases c with
    | undecided => simp [pinVerdict] <;> decide
    | na => simp [pinVerdict] <;> decide
    | out c => cases c <;> simp [pinVerdict] <;> decide

theorem count_same (vs : List LockedCmp) : (vs.map pinVerdict).count Verdict.same = vs.count (.out .overlap) := by
  induction vs with
  | nil => rfl
  | cons c cs ih =>
    simp only [List.map_cons, List.count_cons, ih]
    cases c with
    | undecided => simp [pinVerdict] <;> decide
    | na => simp [pinVerdict] <;> decide
    | out c => cases c <;> simp [pinVerdict] <;> decide

theorem pinDecisive_eq (vs : List LockedCmp) :
    pinDecisive vs = vs.count (.out .higher) + vs.count (.out .lower) + vs.count (.out .overlap) := by
  simp only [pinDecisive, Fw.Gate.Smooth.decisive, count_first, count_second, count_same]

theorem acrossPin_insufficient (vs : List LockedCmp) (h : pinDecisive vs < minSamples) : acrossPin vs = .insufficient :=
  Fw.Gate.Smooth.acrossDecisive_insufficient _ h

theorem acrossPin_none_decisive (vs : List LockedCmp) (h : ∀ c ∈ vs, c = .na ∨ c = .undecided) : acrossPin vs = .insufficient := by
  apply acrossPin_insufficient
  rw [pinDecisive_eq]
  have h1 : vs.count (.out .higher) = 0 := List.count_eq_zero.mpr (fun hm => by rcases h _ hm with e | e <;> cases e)
  have h2 : vs.count (.out .lower) = 0 := List.count_eq_zero.mpr (fun hm => by rcases h _ hm with e | e <;> cases e)
  have h3 : vs.count (.out .overlap) = 0 := List.count_eq_zero.mpr (fun hm => by rcases h _ hm with e | e <;> cases e)
  simp [h1, h2, h3, minSamples]

theorem acrossPin_second (vs : List LockedCmp) (hn : minSamples ≤ pinDecisive vs)
    (hl : Fw.Gate.Smooth.agreeNeeded (pinDecisive vs) ≤ vs.count (.out .lower)) (hh : vs.count (.out .higher) = 0) :
    acrossPin vs = .second := by
  apply Fw.Gate.Smooth.acrossDecisive_second _ hn
  · simpa [pinDecisive, count_second] using hl
  · simpa [count_first] using hh

theorem acrossPin_first (vs : List LockedCmp) (hn : minSamples ≤ pinDecisive vs)
    (hh : Fw.Gate.Smooth.agreeNeeded (pinDecisive vs) ≤ vs.count (.out .higher)) (hl : vs.count (.out .lower) = 0) :
    acrossPin vs = .first := by
  apply Fw.Gate.Smooth.acrossDecisive_first _ hn
  · simpa [pinDecisive, count_first] using hh
  · simpa [count_second] using hl

theorem acrossPin_split (vs : List LockedCmp) (hn : minSamples ≤ pinDecisive vs)
    (hh : 0 < vs.count (.out .higher)) (hl : 0 < vs.count (.out .lower)) : acrossPin vs = .same := by
  apply Fw.Gate.Smooth.acrossDecisive_split _ hn
  · simpa [count_first] using hh
  · simpa [count_second] using hl

theorem acrossPin_same (vs : List LockedCmp) (hn : minSamples ≤ pinDecisive vs)
    (hh : vs.count (.out .higher) < Fw.Gate.Smooth.agreeNeeded (pinDecisive vs))
    (hl : vs.count (.out .lower) < Fw.Gate.Smooth.agreeNeeded (pinDecisive vs)) : acrossPin vs = .same := by
  apply Fw.Gate.Smooth.acrossDecisive_same _ hn
  · simpa [pinDecisive, count_first] using hh
  · simpa [pinDecisive, count_second] using hl

structure Entry where
  op : String
  t : Nat
  x : Int
deriving Repr, BEq

structure Replay where
  touching : Bool
  last : Option Nat
  n : Nat
deriving Repr, BEq

def quiet10 : Nat := 1200

def slack10 : Nat := 10

def liveAt (r : Replay) (t : Nat) : Bool := r.touching || r.last.elim false fun l => decide (t + slack10 < l + quiet10)

def replayStep (r : Replay) (e : Entry) : Replay :=
  if e.op = "touch" then { r with touching := decide (e.x = 1), last := some e.t }
  else if e.op = "moved" then { r with last := some e.t }
  else if e.op = "write" then { r with last := some e.t, n := r.n + (if liveAt r e.t then 1 else 0) }
  else r

def replayFrom (r : Replay) (es : List Entry) : Replay := es.foldl replayStep r

def liveWrites (es : List Entry) : Nat := (replayFrom ⟨false, none, 0⟩ es).n

theorem liveWrites_nil : liveWrites [] = 0 := rfl

theorem replayStep_write_live (r : Replay) (e : Entry) (h : e.op = "write") (hl : liveAt r e.t = true) :
    (replayStep r e).n = r.n + 1 := by
  simp [replayStep, h, hl]

theorem replayStep_write_quiet (r : Replay) (e : Entry) (h : e.op = "write") (hl : liveAt r e.t = false) :
    (replayStep r e).n = r.n := by
  simp [replayStep, h, hl]

theorem replayStep_other (r : Replay) (e : Entry) (h1 : e.op ≠ "write") : (replayStep r e).n = r.n := by
  by_cases a : e.op = "touch" <;> by_cases b : e.op = "moved" <;> simp [replayStep, a, b, h1]

theorem liveAt_touching (r : Replay) (t : Nat) (h : r.touching = true) : liveAt r t = true := by simp [liveAt, h]

theorem liveAt_quiet (r : Replay) (t l : Nat) (h0 : r.touching = false) (h1 : r.last = some l) (h : l + quiet10 ≤ t + slack10) :
    liveAt r t = false := by
  simp [liveAt, h0, h1]
  omega

theorem liveAt_recent (r : Replay) (t l : Nat) (h1 : r.last = some l) (h : t + slack10 < l + quiet10) : liveAt r t = true := by
  simp [liveAt, h1, h]

theorem liveAt_unknown (t : Nat) : liveAt ⟨false, none, 0⟩ t = false := rfl

theorem liveWrites_single (e : Entry) (h : e.op = "write") : liveWrites [e] = 0 := by
  simp [liveWrites, replayFrom, List.foldl, replayStep, h, liveAt]

theorem replay_n_mono (es : List Entry) : ∀ r : Replay, r.n ≤ (replayFrom r es).n := by
  induction es with
  | nil => intro r; exact Nat.le_refl _
  | cons e es ih =>
    intro r
    have h := ih (replayStep r e)
    have : r.n ≤ (replayStep r e).n := by
      by_cases a : e.op = "touch" <;> by_cases b : e.op = "moved" <;> by_cases c : e.op = "write" <;> simp [replayStep, a, b, c]
    simpa [replayFrom, List.foldl] using Nat.le_trans this h

def restTol10 : Nat := 100

def restMargin : Nat := 3

inductive Rest where
  | notReached | atEnd | over | short
deriving Repr, DecidableEq

def Rest.name : Rest → String
  | .notReached => "notReached"
  | .atEnd => "atEnd"
  | .over => "over"
  | .short => "short"

structure Win where
  max10 : Int
  final10 : Int
  peak10 : Int
  target10 : Option Int
deriving Repr, BEq

def goal (w : Win) : Int :=
  match w.target10 with
  | some t => min t w.max10
  | none => w.max10

def gap (w : Win) : Nat := (w.final10 - goal w).natAbs

def restOf (w : Win) : Rest :=
  if w.peak10 + restTol10 < goal w then .notReached
  else if gap w ≤ restTol10 then .atEnd
  else if goal w < w.final10 then .over
  else .short

def targetOf (ss : List (Option Int)) : Option Int := ss.reverse.findSome? id

theorem goal_none (w : Win) (h : w.target10 = none) : goal w = w.max10 := by simp [goal, h]

theorem goal_some (w : Win) (t : Int) (h : w.target10 = some t) : goal w = min t w.max10 := by simp [goal, h]

theorem goal_le_max (w : Win) : goal w ≤ w.max10 := by
  unfold goal
  split <;> omega

theorem restOf_notReached_iff (w : Win) : restOf w = .notReached ↔ w.peak10 + restTol10 < goal w := by
  unfold restOf
  by_cases h1 : w.peak10 + restTol10 < goal w
  · simp [h1]
  · by_cases h2 : gap w ≤ restTol10 <;> by_cases h3 : goal w < w.final10 <;> simp [h1, h2, h3]

theorem restOf_atEnd (w : Win) (h1 : goal w ≤ w.peak10 + restTol10) (h2 : gap w ≤ restTol10) : restOf w = .atEnd := by
  have : ¬ w.peak10 + restTol10 < goal w := by omega
  simp [restOf, this, h2]

theorem restOf_over (w : Win) (h1 : goal w ≤ w.peak10 + restTol10) (h2 : restTol10 < gap w) (h3 : goal w < w.final10) :
    restOf w = .over := by
  have a : ¬ w.peak10 + restTol10 < goal w := by omega
  have b : ¬ gap w ≤ restTol10 := by omega
  simp [restOf, a, b, h3]

theorem restOf_short (w : Win) (h1 : goal w ≤ w.peak10 + restTol10) (h2 : restTol10 < gap w) (h3 : w.final10 ≤ goal w) :
    restOf w = .short := by
  have a : ¬ w.peak10 + restTol10 < goal w := by omega
  have b : ¬ gap w ≤ restTol10 := by omega
  have c : ¬ goal w < w.final10 := by omega
  simp [restOf, a, b, c]

theorem restOf_atEnd_of_final_eq_goal (w : Win) (h : w.final10 = goal w) (hp : goal w ≤ w.peak10) : restOf w = .atEnd := by
  apply restOf_atEnd
  · unfold restTol10; omega
  · simp [gap, h, restTol10]

def withinTol (final : Int) (f : Int × Nat) : Bool := decide ((f.1 - final).natAbs ≤ restTol10)

def arrival (final : Int) (fs : List (Int × Nat)) : Option Nat :=
  ((fs.reverse.takeWhile (withinTol final)).getLast?).map (·.2)

def touchEnd10 (ev0 firstScroll swipe : Nat) : Nat := ev0 + 10 * swipe - 10 * firstScroll

def settle10 (touchEnd : Option Nat) (final : Int) (fs : List (Int × Nat)) : Option Nat :=
  match touchEnd, arrival final fs with
  | some e, some a => some (a - e)
  | _, _ => none

theorem arrival_nil (final : Int) : arrival final [] = none := by simp [arrival]

theorem arrival_far_last (final : Int) (fs : List (Int × Nat)) (f : Int × Nat) (h : withinTol final f = false) :
    arrival final (fs ++ [f]) = none := by
  simp [arrival, h]

theorem arrival_single (final : Int) (y : Int) (t : Nat) (h : withinTol final (y, t) = true) :
    arrival final [(y, t)] = some t := by
  simp [arrival, h]

theorem settle10_no_touch (final : Int) (fs : List (Int × Nat)) : settle10 none final fs = none := by
  simp [settle10]

theorem settle10_before_lift (e a : Nat) (final : Int) (fs : List (Int × Nat)) (h : arrival final fs = some a) (hl : a ≤ e) :
    settle10 (some e) final fs = some 0 := by
  simp [settle10, h]
  omega

theorem settle10_after_lift (e a : Nat) (final : Int) (fs : List (Int × Nat)) (h : arrival final fs = some a) :
    settle10 (some e) final fs = some (a - e) := by
  simp [settle10, h]

structure RestTally where
  rested : Nat
  reached : Nat
deriving Repr, BEq

def tallyRest (rs : List Rest) : RestTally := ⟨rs.count .atEnd, rs.length - rs.count .notReached⟩

theorem count_atEnd_add_notReached_le (rs : List Rest) : rs.count .atEnd + rs.count .notReached ≤ rs.length := by
  induction rs with
  | nil => simp
  | cons x xs ih => cases x <;> simp <;> omega

theorem rested_le_reached (rs : List Rest) : (tallyRest rs).rested ≤ (tallyRest rs).reached := by
  have := count_atEnd_add_notReached_le rs
  simp only [tallyRest]
  omega

inductive RestCmp where
  | undecided | pinBetter | pinWorse | same
deriving Repr, DecidableEq

def RestCmp.name : RestCmp → String
  | .undecided => "undecided"
  | .pinBetter => "pinBetter"
  | .pinWorse => "pinWorse"
  | .same => "same"

def restDiff (base pin : RestTally) : Int := (pin.rested : Int) * base.reached - (base.rested : Int) * pin.reached

def restCmp (base pin : RestTally) : RestCmp :=
  if base.reached < minSamples ∨ pin.reached < minSamples then .undecided
  else if (pin.reached : Int) * base.reached ≤ restMargin * restDiff base pin then .pinBetter
  else if restMargin * restDiff base pin ≤ -((pin.reached : Int) * base.reached) then .pinWorse
  else .same

theorem restCmp_undecided_base (base pin : RestTally) (h : base.reached < minSamples) : restCmp base pin = .undecided := by
  simp [restCmp, h]

theorem restCmp_undecided_pin (base pin : RestTally) (h : pin.reached < minSamples) : restCmp base pin = .undecided := by
  simp [restCmp, h]

private theorem reached_prod_pos (base pin : RestTally) (hb : minSamples ≤ base.reached) (hp : minSamples ≤ pin.reached) :
    0 < (pin.reached : Int) * base.reached := by
  unfold minSamples at *
  exact Int.mul_pos (by omega) (by omega)

theorem restCmp_better (base pin : RestTally) (hb : minSamples ≤ base.reached) (hp : minSamples ≤ pin.reached)
    (h : (pin.reached : Int) * base.reached ≤ restMargin * restDiff base pin) : restCmp base pin = .pinBetter := by
  have a : ¬ base.reached < minSamples := by omega
  have b : ¬ pin.reached < minSamples := by omega
  simp [restCmp, a, b, h]

theorem restCmp_worse (base pin : RestTally) (hb : minSamples ≤ base.reached) (hp : minSamples ≤ pin.reached)
    (h : restMargin * restDiff base pin ≤ -((pin.reached : Int) * base.reached)) : restCmp base pin = .pinWorse := by
  have a : ¬ base.reached < minSamples := by omega
  have b : ¬ pin.reached < minSamples := by omega
  have pos := reached_prod_pos base pin hb hp
  have c : ¬ (pin.reached : Int) * base.reached ≤ restMargin * restDiff base pin := by omega
  simp [restCmp, a, b, c, h]

theorem restCmp_same (base pin : RestTally) (hb : minSamples ≤ base.reached) (hp : minSamples ≤ pin.reached)
    (h1 : restMargin * restDiff base pin < (pin.reached : Int) * base.reached)
    (h2 : -((pin.reached : Int) * base.reached) < restMargin * restDiff base pin) : restCmp base pin = .same := by
  have a : ¬ base.reached < minSamples := by omega
  have b : ¬ pin.reached < minSamples := by omega
  have c : ¬ (pin.reached : Int) * base.reached ≤ restMargin * restDiff base pin := by omega
  have d : ¬ restMargin * restDiff base pin ≤ -((pin.reached : Int) * base.reached) := by omega
  simp [restCmp, a, b, c, d]

theorem restCmp_self (t : RestTally) (h : minSamples ≤ t.reached) : restCmp t t = .same := by
  have pos := reached_prod_pos t t h h
  have z : restDiff t t = 0 := by simp [restDiff]
  apply restCmp_same t t h h
  · rw [z]; omega
  · rw [z]; omega

open Fw.Gate.Smooth (Verdict)

def RestCmp.verdict : RestCmp → Verdict
  | .pinBetter => .second
  | .pinWorse => .first
  | .same => .same
  | .undecided => .insufficient

structure RestJob where
  cmp : RestCmp
  live : Nat
deriving Repr, BEq

def jobVerdict (j : RestJob) : Verdict :=
  if 0 < j.live ∧ j.cmp = .pinBetter then .insufficient else j.cmp.verdict

def acrossRest (js : List RestJob) : Verdict := Fw.Gate.Smooth.acrossDecisive (js.map jobVerdict)

def restDecisive (js : List RestJob) : Nat := Fw.Gate.Smooth.decisive (js.map jobVerdict)

theorem jobVerdict_clear (j : RestJob) (h : j.live = 0) : jobVerdict j = j.cmp.verdict := by
  simp [jobVerdict, h]

theorem jobVerdict_live_better (j : RestJob) (hl : 0 < j.live) (hc : j.cmp = .pinBetter) : jobVerdict j = .insufficient := by
  simp [jobVerdict, hl, hc]

theorem jobVerdict_live_worse (j : RestJob) (hc : j.cmp = .pinWorse) : jobVerdict j = .first := by
  simp [jobVerdict, hc, RestCmp.verdict]

theorem jobVerdict_live_same (j : RestJob) (hc : j.cmp = .same) : jobVerdict j = .same := by
  simp [jobVerdict, hc, RestCmp.verdict]

theorem jobVerdict_live_undecided (j : RestJob) (hc : j.cmp = .undecided) : jobVerdict j = .insufficient := by
  simp [jobVerdict, hc, RestCmp.verdict]

theorem jobVerdict_second_iff (j : RestJob) : jobVerdict j = .second ↔ j.live = 0 ∧ j.cmp = .pinBetter := by
  unfold jobVerdict
  cases hc : j.cmp <;> by_cases hl : j.live = 0 <;> simp [hl, RestCmp.verdict]
  all_goals omega

theorem jobVerdict_live_ne_second (j : RestJob) (hl : 0 < j.live) : jobVerdict j ≠ .second := by
  intro h
  have := (jobVerdict_second_iff j).1 h
  omega

private theorem count_second_map (js : List RestJob) :
    (js.map jobVerdict).count Verdict.second = (js.filter fun j => decide (j.live = 0 ∧ j.cmp = .pinBetter)).length := by
  induction js with
  | nil => simp
  | cons j js ih =>
    have := jobVerdict_second_iff j
    by_cases h : jobVerdict j = .second
    · have h2 := this.1 h
      simp [List.count_cons, ih, h, h2] <;> decide
    · have h2 : ¬ (j.live = 0 ∧ j.cmp = .pinBetter) := fun x => h (this.2 x)
      have h3 : (jobVerdict j == Verdict.second) = false := by
        cases hv : jobVerdict j <;> simp_all <;> decide
      simp only [List.map_cons, List.count_cons, List.filter_cons, ih, h3, h2, decide_false]
      simp

theorem acrossRest_second_unguarded (js : List RestJob) (h : acrossRest js = .second) :
    ∃ j ∈ js, j.live = 0 ∧ j.cmp = .pinBetter := by
  obtain ⟨hn, h3, -⟩ := Fw.Gate.Smooth.acrossDecisive_second_two_thirds _ h
  have hpos : 0 < (js.map jobVerdict).count Verdict.second := by
    unfold Fw.Gate.Smooth.minSamples at hn
    omega
  rw [count_second_map] at hpos
  obtain ⟨j, hj⟩ := List.exists_mem_of_length_pos hpos
  exact ⟨j, (List.mem_filter.mp hj).1, by simpa using (List.mem_filter.mp hj).2⟩

theorem acrossRest_all_live (js : List RestJob) (h : ∀ j ∈ js, 0 < j.live) : acrossRest js ≠ .second := by
  intro hs
  obtain ⟨j, hj, hl, -⟩ := acrossRest_second_unguarded js hs
  have := h j hj
  omega

theorem acrossRest_insufficient (js : List RestJob) (h : restDecisive js < minSamples) : acrossRest js = .insufficient :=
  Fw.Gate.Smooth.acrossDecisive_insufficient _ h

theorem acrossRest_undecided (js : List RestJob) (h : ∀ j ∈ js, j.cmp = .undecided) : acrossRest js = .insufficient := by
  apply acrossRest_insufficient
  have hd : ∀ vs : List Verdict, (∀ v ∈ vs, v = .insufficient) → Fw.Gate.Smooth.decisive vs = 0 := by
    intro vs
    induction vs with
    | nil => intro _; rfl
    | cons x xs ih =>
      intro hx
      have h1 : x = .insufficient := hx x (by simp)
      have h2 := ih (fun v hv => hx v (by simp [hv]))
      subst h1
      simp only [Fw.Gate.Smooth.decisive, List.count_cons] at h2 ⊢
      simp_all <;> decide
  have : restDecisive js = 0 := by
    apply hd
    intro v hv
    obtain ⟨j, hj, rfl⟩ := List.mem_map.mp hv
    simp [jobVerdict, h j hj, RestCmp.verdict]
  rw [this]
  simp [minSamples]

def rJobs41369102226 : List (RestTally × RestTally) :=
  [(⟨2, 5⟩, ⟨5, 6⟩), (⟨3, 6⟩, ⟨3, 5⟩), (⟨2, 3⟩, ⟨0, 0⟩), (⟨3, 5⟩, ⟨6, 6⟩), (⟨3, 6⟩, ⟨6, 6⟩), (⟨3, 5⟩, ⟨5, 5⟩), (⟨3, 6⟩, ⟨5, 5⟩)]

def restJobs (ps : List (RestTally × RestTally)) (live : List Nat) : List RestJob :=
  (ps.zip live).map fun ((b, p), l) => ⟨restCmp b p, l⟩

theorem rank_41369102226_clear : acrossRest (restJobs rJobs41369102226 (List.replicate 7 0)) = .second := by decide

theorem rank_41369102226_decisive : restDecisive (restJobs rJobs41369102226 (List.replicate 7 0)) = 6 := by decide

theorem rank_41369102226_all_live : acrossRest (restJobs rJobs41369102226 (List.replicate 7 1)) = .insufficient := by decide

theorem rank_41369102226_two_live : acrossRest (restJobs rJobs41369102226 [1, 0, 0, 1, 0, 0, 0]) = .second := by decide

theorem rank_41369102226_four_live : acrossRest (restJobs rJobs41369102226 [1, 0, 0, 1, 1, 1, 0]) = .insufficient := by decide

theorem rest_on_end : restOf ⟨52270, 52270, 52270, none⟩ = .atEnd := by decide

theorem rest_past_end : restOf ⟨52270, 52910, 52910, none⟩ = .over := by decide

theorem rest_left_end : restOf ⟨52670, 45910, 52670, none⟩ = .short := by decide

theorem rest_never_reached : restOf ⟨52670, 45910, 51300, none⟩ = .notReached := by decide

theorem rest_target_below_end : restOf ⟨51910, 51850, 51910, some 51850⟩ = .atEnd := by decide

theorem rest_target_beyond_end : restOf ⟨52270, 52270, 52270, some 52460⟩ = .atEnd := by decide

theorem rest_target_above_rest : restOf ⟨52270, 52270, 52270, some 52000⟩ = .over := by decide

theorem rest_tolerance_edge : restOf ⟨52270, 52170, 52270, none⟩ = .atEnd ∧ restOf ⟨52270, 52160, 52270, none⟩ = .short := by decide

theorem touchEnd_job1_pin0 : touchEnd10 95990 133 4309 = 137750 := by decide

theorem settle_before_lift_case : settle10 (some 137750) 52270 [(50000, 100000), (52270, 120000), (52270, 160000)] = some 0 := by decide

theorem settle_after_lift_case : settle10 (some 100000) 52270 [(50000, 100000), (51000, 150000), (52270, 300000), (52270, 400000)] = some 200000 := by decide

theorem restCmp_margin_edge : restCmp ⟨1, 3⟩ ⟨2, 3⟩ = .pinBetter ∧ restCmp ⟨3, 6⟩ ⟨4, 6⟩ = .same := by decide

theorem restCmp_run_41369102226 : rJobs41369102226.map (fun (b, p) => restCmp b p) =
    [.pinBetter, .same, .undecided, .pinBetter, .pinBetter, .pinBetter, .pinBetter] := by decide

inductive Arm where
  | orig | base | lock | pin
deriving Repr, BEq, DecidableEq

def Arm.name : Arm → String
  | .orig => "orig"
  | .base => "base"
  | .lock => "lock"
  | .pin => "pin"

def repOrder (rep : Nat) : List Arm :=
  if rep % 2 = 0 then [.base, .lock, .pin, .orig] else [.pin, .lock, .base, .orig]

theorem repOrder_orig_last (rep : Nat) : (repOrder rep).getLast? = some .orig := by
  unfold repOrder; split <;> rfl

theorem repOrder_once (rep : Nat) (a : Arm) : (repOrder rep).count a = 1 := by
  unfold repOrder; split <;> cases a <;> decide

theorem repOrder_even (rep : Nat) (h : rep % 2 = 0) : (repOrder rep).head? = some .base := by
  simp [repOrder, h]

theorem repOrder_odd (rep : Nat) (h : rep % 2 = 1) : (repOrder rep).head? = some .pin := by
  simp [repOrder, h]

def maxRestarts : Nat := 2

def serveTag (restarts : Nat) : String := if restarts = 0 then "serve" else "serve-r" ++ toString restarts

theorem serveTag_zero : serveTag 0 = "serve" := rfl

theorem serveTag_new_each_restart : ∀ i j : Fin (maxRestarts + 1), i ≠ j → serveTag i ≠ serveTag j := by
  unfold maxRestarts serveTag
  decide

inductive Lane where
  | keep | restart | stop
deriving Repr, BEq, DecidableEq

def Lane.name : Lane → String
  | .keep => "keep"
  | .restart => "restart"
  | .stop => "stop"

def afterWindow (used : Nat) (stalled : Bool) : Lane :=
  if stalled then (if used < maxRestarts then .restart else .stop) else .keep

theorem afterWindow_keep (used : Nat) : afterWindow used false = .keep := rfl

theorem afterWindow_restart (used : Nat) (h : used < maxRestarts) : afterWindow used true = .restart := by
  simp [afterWindow, h]

theorem afterWindow_stop (used : Nat) (h : maxRestarts ≤ used) : afterWindow used true = .stop := by
  simp [afterWindow, Nat.not_lt.mpr h]

def mk (l : List (Int × Bool)) : List Sample := l.map fun (y, o) => ⟨y, o⟩

def steadyFrames : List Sample := mk (List.replicate 3 (0, false) ++ List.replicate 12 (5000, true))

def fightFrames : List Sample :=
  mk (List.replicate 3 (4990, false) ++ [(5000, true), (5000, true), (5080, true), (5000, true), (5060, true), (5000, true),
    (5000, true), (5000, true), (5000, true), (5000, true), (5000, true), (5000, true)])

def monotoneFrames : List Sample :=
  mk ([(4990, false), (4995, false)] ++ [(5000, true), (5040, true), (5080, true), (5120, true), (5160, true), (5200, true),
    (5240, true), (5280, true), (5320, true), (5360, true), (5400, true), (5440, true)])

def bounceFrames : List Sample :=
  mk ([(5000, true), (5090, true), (5150, true), (5100, true), (5000, true), (5000, true), (5000, true), (5000, true),
    (5000, true), (5000, true), (5000, true), (5000, true)])

def neverOpen : Run := ⟨mk (List.replicate 20 (4000, false)), mk [], mk []⟩

def shortOpen : Run := ⟨mk [(5000, true), (5000, true), (5040, true), (5000, true)], mk [], mk []⟩

def overscrollFrames : List Sample :=
  mk ([(52270, false), (53460, true), (52360, true), (52270, true), (52360, true), (52270, true), (52360, true), (52270, true),
    (52360, true), (52270, true), (52270, true), (52270, true)])

def overscrollRun (stored : Int) : Run := ⟨overscrollFrames, overscrollFrames, mk [(stored, true), (stored, true)]⟩

theorem overscroll_lock : lockOf (overscrollRun 52270) = some 52270 := rfl

theorem overscroll_fights_at_stored : (reduce (overscrollRun 52270)).frameFights = 3 := by decide

theorem overscroll_fights_at_first_sample : fightsAt (some 53460) overscrollFrames = 0 := by decide

theorem overscroll_first_sample_hid_the_fights :
    fightsAt (some 53460) overscrollFrames ≠ (reduce (overscrollRun 52270)).frameFights := by decide

def runCases : List (String × Run) := [
  ("steady open phase", ⟨steadyFrames, steadyFrames, mk []⟩),
  ("restore after a displaced frame", ⟨fightFrames, fightFrames, mk [(5000, true), (5000, true)]⟩),
  ("frames steady, events fight", ⟨steadyFrames, fightFrames, mk [(5000, true)]⟩),
  ("one way drift is not a fight", ⟨monotoneFrames, monotoneFrames, mk [(5000, true)]⟩),
  ("bounce back to the lock", ⟨bounceFrames, bounceFrames, mk [(5000, true)]⟩),
  ("never open", neverOpen),
  ("open for 4 frames", shortOpen),
  ("closed, open, closed", ⟨mk ([(1, false)] ++ List.replicate 10 (5000, true) ++ [(1, false), (1, true)]), mk [], mk []⟩),
  ("overscroll first sample, lock stored at the end", overscrollRun 52270),
  ("overscroll first sample, lock stored at the other end", overscrollRun 52360),
  ("restore calls disagree", ⟨fightFrames, fightFrames, mk [(5000, true), (5040, true)]⟩),
  ("restore call before the morph opened", ⟨fightFrames, fightFrames, mk [(4990, false), (5000, true)]⟩),
  ("drift and the site never restored", ⟨monotoneFrames, monotoneFrames, mk []⟩)]

def cmpCases : List (String × List Nat × List Nat) := [
  ("candidate below", ([2, 3, 5], [0, 0, 1])),
  ("candidate above", ([0, 1], [3, 4])),
  ("ranges overlap", ([0, 4], [1, 2])),
  ("both zero", ([0, 0, 0], [0, 0, 0])),
  ("touching ranges", ([2, 3], [1, 2])),
  ("no faithful run", ([], [1])),
  ("no candidate run", ([1], []))]

def lookCases : List (String × List Nat × List Nat) := [
  ("both steady", ([0, 0], [0, 0, 0])),
  ("faithful displaced", ([0, 2], [0, 0])),
  ("candidate displaced", ([0, 0], [1])),
  ("both displaced", ([3], [4])),
  ("nothing measured", ([], [])),
  ("no faithful run", ([], [0])),
  ("no candidate run", ([0], []))]

def cmpKnownCases : List (String × List Nat × List Nat) := [
  ("candidate below", ([2, 3, 5], [0, 0, 1])),
  ("candidate above", ([0, 1, 1], [3, 4, 4])),
  ("ranges overlap", ([0, 4, 2], [1, 2, 3])),
  ("both zero", ([0, 0, 0], [0, 0, 0])),
  ("touching ranges", ([2, 3, 3], [1, 2, 2])),
  ("no faithful run", ([], [1, 1, 1])),
  ("no candidate run", ([1, 1, 1], [])),
  ("one faithful run", ([5], [0, 0, 1])),
  ("one candidate run", ([5, 6, 7], [0])),
  ("two runs each, separated", ([0, 1], [3, 4])),
  ("two candidate runs, separated", ([5, 6, 7], [0, 1]))]

def lockedCmpCases : List (String × List Counted × List Counted) := [
  ("both locked, candidate below", ([⟨some 5, 2⟩, ⟨some 5, 3⟩, ⟨some 5, 5⟩], [⟨some 5, 0⟩, ⟨some 5, 0⟩, ⟨some 5, 1⟩])),
  ("candidate never stored a lock", ([⟨some 5, 2⟩, ⟨some 5, 3⟩, ⟨some 5, 5⟩], [⟨none, 0⟩, ⟨none, 0⟩, ⟨none, 0⟩, ⟨none, 0⟩])),
  ("faithful never stored a lock", ([⟨none, 0⟩, ⟨none, 0⟩, ⟨none, 0⟩], [⟨some 5, 1⟩, ⟨some 5, 2⟩, ⟨some 5, 1⟩])),
  ("both never stored a lock", ([⟨none, 0⟩], [⟨none, 0⟩])),
  ("no candidate run", ([⟨some 5, 1⟩, ⟨some 5, 1⟩, ⟨some 5, 1⟩], [])),
  ("no faithful run", ([], [⟨some 5, 1⟩])),
  ("mixed candidate, locked runs only", ([⟨some 5, 4⟩, ⟨some 5, 5⟩, ⟨some 5, 6⟩], [⟨some 5, 0⟩, ⟨none, 9⟩, ⟨some 5, 1⟩, ⟨some 5, 0⟩])),
  ("one locked run each", ([⟨some 5, 4⟩], [⟨some 5, 0⟩])),
  ("candidate above", ([⟨some 5, 0⟩, ⟨some 5, 1⟩, ⟨some 5, 1⟩], [⟨some 5, 3⟩, ⟨some 5, 4⟩, ⟨some 5, 4⟩]))]

def lookKnownCases : List (String × List Nat × List Nat) := [
  ("both steady", ([0, 0, 0], [0, 0, 0])),
  ("faithful displaced", ([0, 2, 0], [0, 0, 0])),
  ("candidate displaced", ([0, 0, 0], [1, 0, 0])),
  ("both displaced", ([3, 3, 3], [4, 4, 4])),
  ("nothing measured", ([], [])),
  ("no faithful run", ([], [0, 0, 0])),
  ("no candidate run", ([0, 0, 0], [])),
  ("one steady run each", ([0], [0])),
  ("two steady runs each", ([0, 0], [0, 0])),
  ("one candidate run, displaced", ([0, 0, 0], [1]))]

def lockedNames : List LockedCmp := [.undecided, .na, .out .lower, .out .higher, .out .overlap]

def acrossCases : List (String × List LockedCmp) := [
  ("5 jobs, the pin lower in all", List.replicate 5 (.out .lower)),
  ("12 jobs, the pin wrote nowhere", List.replicate 12 .na),
  ("12 jobs, 3 overlap and 9 without a pin write", List.replicate 3 (.out .overlap) ++ List.replicate 9 .na),
  ("2 lower, the rest undecided", List.replicate 2 (.out .lower) ++ List.replicate 10 .undecided),
  ("4 lower and 1 overlap", List.replicate 4 (.out .lower) ++ [.out .overlap]),
  ("3 lower, 1 overlap and 1 higher", List.replicate 3 (.out .lower) ++ [.out .overlap, .out .higher]),
  ("4 higher and 1 overlap", List.replicate 4 (.out .higher) ++ [.out .overlap]),
  ("3 overlap", List.replicate 3 (.out .overlap)),
  ("no jobs", []),
  ("3 lower among 9 without a pin write", List.replicate 3 (.out .lower) ++ List.replicate 6 .na ++ List.replicate 3 .undecided)]

def liveCases : List (String × List Entry) := [
  ("no write", [⟨"touch", 1000, 1⟩, ⟨"moved", 2000, 0⟩, ⟨"touch", 3000, 0⟩]),
  ("the write of run 41289882234 job 1, 121 ms after the last move", [⟨"touch", 1000, 1⟩, ⟨"touch", 100000, 0⟩, ⟨"moved", 111240, 0⟩, ⟨"write", 112450, 51890⟩]),
  ("a write with the finger down", [⟨"touch", 1000, 1⟩, ⟨"write", 5000, 0⟩]),
  ("a write 50 ms after a move", [⟨"moved", 1000, 0⟩, ⟨"write", 1500, 0⟩]),
  ("a write 119.5 ms after a move, inside the stamp slack", [⟨"moved", 10000, 0⟩, ⟨"write", 11195, 0⟩]),
  ("a write 118 ms after a move", [⟨"moved", 10000, 0⟩, ⟨"write", 11180, 0⟩]),
  ("a second write soon after the first", [⟨"moved", 1000, 0⟩, ⟨"write", 2300, 0⟩, ⟨"write", 2500, 0⟩]),
  ("a write before any event", [⟨"write", 5000, 0⟩]),
  ("a write right after the finger lifted", [⟨"touch", 1000, 1⟩, ⟨"touch", 2000, 0⟩, ⟨"write", 2500, 0⟩]),
  ("declines and due entries only", [⟨"inactive", 100, 0⟩, ⟨"due", 200, 80⟩, ⟨"reversal", 300, 0⟩, ⟨"live", 400, 0⟩, ⟨"onTarget", 500, 0⟩, ⟨"touching", 600, 0⟩])]

def restCases : List (String × Win) := [
  ("rests on the page end", ⟨52270, 52270, 52270, none⟩),
  ("rests 9 px below the end, inside the tolerance", ⟨52270, 52180, 52270, none⟩),
  ("rests 11 px below the end", ⟨52270, 52160, 52270, none⟩),
  ("rests 64 px past the end", ⟨52270, 52910, 52910, none⟩),
  ("the pan never reached the end", ⟨52670, 45910, 51300, none⟩),
  ("the page left the end it had reached", ⟨52670, 45910, 52670, none⟩),
  ("the peak is exactly the tolerance short", ⟨52270, 52270, 52170, none⟩),
  ("pin target below the page end, rests on it", ⟨51910, 51850, 51910, some 51850⟩),
  ("pin target beyond the page end, rests at the end", ⟨52270, 52270, 52270, some 52460⟩),
  ("pin target above the rest", ⟨52270, 52270, 52270, some 52000⟩)]

def settleCases : List (String × Option Nat × Int × List (Int × Nat)) := [
  ("arrived before the finger lifted", (some 137750, 52270, [(50000, 100000), (52270, 120000), (52270, 160000)])),
  ("arrives 2 s after the lift", (some 100000, 52270, [(50000, 100000), (51000, 150000), (52270, 300000), (52270, 400000)])),
  ("still moving at the last frame", (some 100000, 52270, [(52270, 100000), (52000, 200000)])),
  ("no touch end known", (none, 52270, [(52270, 100000)])),
  ("no frames", (some 100000, 52270, [])),
  ("bounces out and back inside", (some 100000, 52270, [(52270, 100000), (52900, 150000), (52270, 200000), (52280, 250000)]))]

def touchEndCases : List (String × Nat × Nat × Nat) := [
  ("run 41369102226 job 1 pin window 0", (95990, 133, 4309)),
  ("first scroll later than the swipe", (1000, 500, 30)),
  ("no swipe", (50000, 0, 0))]

def targetCases : List (String × List (Option Int)) := [
  ("no reading", []),
  ("only declines", [none, none]),
  ("one target", [none, some 52460, none]),
  ("the last target wins", [some 52460, some 52250, none])]

def restCmpCases : List (String × RestTally × RestTally) := [
  ("pin rests more often", (⟨2, 5⟩, ⟨5, 6⟩)),
  ("same rate", (⟨3, 6⟩, ⟨3, 6⟩)),
  ("pin rests less often", (⟨5, 6⟩, ⟨2, 6⟩)),
  ("two reached windows in the base", (⟨2, 2⟩, ⟨0, 6⟩)),
  ("no reached window in the pin", (⟨2, 3⟩, ⟨0, 0⟩)),
  ("exactly at the margin", (⟨1, 3⟩, ⟨2, 3⟩)),
  ("one window short of the margin", (⟨3, 6⟩, ⟨4, 6⟩)),
  ("pin all, base none", (⟨0, 4⟩, ⟨4, 4⟩))]

def restAcrossCases : List (String × List RestJob) := [
  ("run 41369102226, no live write", restJobs rJobs41369102226 (List.replicate 7 0)),
  ("run 41369102226, every pin live", restJobs rJobs41369102226 (List.replicate 7 1)),
  ("run 41369102226, two jobs live", restJobs rJobs41369102226 [1, 0, 0, 1, 0, 0, 0]),
  ("run 41369102226, four better jobs live", restJobs rJobs41369102226 [1, 0, 0, 1, 1, 1, 0]),
  ("three worse jobs, live writes do not hide them", [⟨.pinWorse, 2⟩, ⟨.pinWorse, 0⟩, ⟨.pinWorse, 1⟩]),
  ("a split", [⟨.pinBetter, 0⟩, ⟨.pinWorse, 0⟩, ⟨.pinBetter, 0⟩]),
  ("all undecided", List.replicate 5 ⟨.undecided, 0⟩),
  ("no jobs", [])]

open Lean in
def countedJson (k : Counted) : Json := Json.arr #[match k.lock with | some l => toJson l | none => Json.null, toJson k.n]

open Lean in
def sampleJson (s : Sample) : Json := Json.arr #[toJson s.y, toJson (if s.isOpen then 1 else 0)]

open Lean in
def samplesJson (xs : List Sample) : Json := Json.arr (xs.map sampleJson).toArray

open Lean in
def resultJson (r : Result) : Json :=
  Json.mkObj [("openFrames", toJson r.openFrames), ("displacedFrames", toJson r.displacedFrames),
    ("frameReversals", toJson r.frameReversals), ("frameFights", toJson r.frameFights), ("restores", toJson r.restores),
    ("eventReversals", toJson r.eventReversals), ("eventFights", toJson r.eventFights), ("jitter", toJson r.jitter),
    ("openCalls", toJson r.openCalls),
    ("lock", match r.lock with | some l => toJson l | none => Json.null)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("minOpenFrames", toJson minOpenFrames), ("maxRestarts", toJson maxRestarts), ("minSamples", toJson minSamples), ("quiet10", toJson quiet10), ("slack10", toJson slack10), ("restTol10", toJson restTol10), ("restMargin", toJson restMargin)]).compress
  let rs := runCases.map fun (name, r) =>
    (Json.mkObj [("op", "run"), ("case", Json.str name), ("frames", samplesJson r.frames), ("events", samplesJson r.events), ("calls", samplesJson r.calls),
      ("refusal", match refusal r with | some f => Json.str f.name | none => Json.null),
      ("result", resultJson (reduce r))]).compress
  let cs := cmpCases.map fun (name, f, c) =>
    (Json.mkObj [("op", "cmp"), ("case", Json.str name), ("faith", toJson f), ("cand", toJson c),
      ("out", Json.str (cmp f c).name)]).compress
  let ls := lookCases.map fun (name, f, c) =>
    (Json.mkObj [("op", "look"), ("case", Json.str name), ("faith", toJson f), ("cand", toJson c),
      ("out", Json.str (look f c).name)]).compress
  let cks := cmpKnownCases.map fun (name, f, c) =>
    (Json.mkObj [("op", "cmpKnown"), ("case", Json.str name), ("faith", toJson f), ("cand", toJson c),
      ("out", Json.str (optName Cmp.name (cmpKnown f c)))]).compress
  let lks := lookKnownCases.map fun (name, f, c) =>
    (Json.mkObj [("op", "lookKnown"), ("case", Json.str name), ("faith", toJson f), ("cand", toJson c),
      ("out", Json.str (optName Look.name (lookKnown f c)))]).compress
  let lcs := lockedCmpCases.map fun (name, f, c) =>
    (Json.mkObj [("op", "lockedCmp"), ("case", Json.str name), ("faith", Json.arr (f.map countedJson).toArray),
      ("cand", Json.arr (c.map countedJson).toArray), ("out", Json.str (lockedCmp f c).name)]).compress
  let ts := [("two arms", [⟨steadyFrames, steadyFrames, mk []⟩, ⟨fightFrames, fightFrames, mk [(5000, true)]⟩, neverOpen, shortOpen])].map fun (name, l) =>
    (Json.mkObj [("op", "tally"), ("case", Json.str name), ("runs", Json.arr (l.map fun r =>
      Json.mkObj [("frames", samplesJson r.frames), ("events", samplesJson r.events), ("calls", samplesJson r.calls)]).toArray),
      ("accepted", toJson (tally l).1), ("jitter", toJson (tally l).2)]).compress
  let os := (List.range 4).map fun rep =>
    (Json.mkObj [("op", "order"), ("rep", toJson rep), ("arms", toJson ((repOrder rep).map Arm.name))]).compress
  let ws := [(0, false), (0, true), (1, true), (2, true), (3, false)].map fun (used, stalled) =>
    (Json.mkObj [("op", "lane"), ("used", toJson used), ("stalled", toJson stalled),
      ("out", Json.str (afterWindow used stalled).name)]).compress
  let tg := (List.range 4).map fun n =>
    (Json.mkObj [("op", "tag"), ("restarts", toJson n), ("tag", Json.str (serveTag n))]).compress
  let pvs := lockedNames.map fun c =>
    (Json.mkObj [("op", "pinVerdict"), ("cmp", Json.str c.name), ("out", Json.str (pinVerdict c).name)]).compress
  let acs := acrossCases.map fun (name, vs) =>
    (Json.mkObj [("op", "across"), ("case", Json.str name), ("jobs", toJson (vs.map LockedCmp.name)),
      ("decisive", toJson (pinDecisive vs)), ("out", Json.str (acrossPin vs).name)]).compress
  let lws := liveCases.map fun (name, es) =>
    (Json.mkObj [("op", "liveWrites"), ("case", Json.str name),
      ("entries", Json.arr (es.map fun e => Json.arr #[Json.str e.op, toJson e.t, toJson e.x]).toArray),
      ("out", toJson (liveWrites es))]).compress
  let rcs := restCases.map fun (name, w) =>
    (Json.mkObj [("op", "rest"), ("case", Json.str name), ("max", toJson w.max10), ("final", toJson w.final10), ("peak", toJson w.peak10),
      ("target", match w.target10 with | some t => toJson t | none => Json.null),
      ("goal", toJson (goal w)), ("gap", toJson (gap w)), ("out", Json.str (restOf w).name)]).compress
  let sts := settleCases.map fun (name, e, final, fs) =>
    (Json.mkObj [("op", "settle"), ("case", Json.str name), ("touchEnd", match e with | some v => toJson v | none => Json.null), ("final", toJson final),
      ("frames", Json.arr (fs.map fun (y, t) => Json.arr #[toJson y, toJson t]).toArray),
      ("arrival", match arrival final fs with | some v => toJson v | none => Json.null),
      ("out", match settle10 e final fs with | some v => toJson v | none => Json.null)]).compress
  let tes := touchEndCases.map fun (name, ev0, fsm, sw) =>
    (Json.mkObj [("op", "touchEnd"), ("case", Json.str name), ("ev0", toJson ev0), ("firstScroll", toJson fsm), ("swipe", toJson sw),
      ("out", toJson (touchEnd10 ev0 fsm sw))]).compress
  let tgs := targetCases.map fun (name, ss) =>
    (Json.mkObj [("op", "target"), ("case", Json.str name),
      ("seen", Json.arr (ss.map fun o => match o with | some v => toJson v | none => Json.null).toArray),
      ("out", match targetOf ss with | some v => toJson v | none => Json.null)]).compress
  let rks := restCmpCases.map fun (name, b, p) =>
    (Json.mkObj [("op", "restCmp"), ("case", Json.str name), ("base", toJson [b.rested, b.reached]), ("pin", toJson [p.rested, p.reached]),
      ("out", Json.str (restCmp b p).name), ("verdict", Json.str (restCmp b p).verdict.name)]).compress
  let ras := restAcrossCases.map fun (name, js) =>
    (Json.mkObj [("op", "restAcross"), ("case", Json.str name),
      ("jobs", Json.arr (js.map fun j => Json.arr #[Json.str j.cmp.name, toJson j.live]).toArray),
      ("jobVerdicts", toJson (js.map fun j => (jobVerdict j).name)),
      ("decisive", toJson (restDecisive js)), ("out", Json.str (acrossRest js).name)]).compress
  [consts] ++ rs ++ cs ++ ls ++ ts ++ os ++ ws ++ tg ++ cks ++ lks ++ lcs ++ pvs ++ acs ++ lws ++ rcs ++ sts ++ tes ++ tgs ++ rks ++ ras

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def runText (text : String) (lines : Nat) (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == text.toUTF8.data then
      IO.eprintln s!"touch-lock golden: {path} is up to date ({lines} lines)"
      return 0
    IO.eprintln s!"touch-lock golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print text
    return 0

def run (args : List String) : IO UInt32 := runText goldenText goldenLines.length args

#guard (reduce ⟨fightFrames, fightFrames, mk [(5000, true)]⟩).jitter == true
#guard (reduce ⟨steadyFrames, steadyFrames, mk []⟩).jitter == false
#guard (reduce ⟨monotoneFrames, monotoneFrames, mk []⟩).frameReversals == 0
#guard cmp [2, 3, 5] [0, 0, 1] == .lower
#guard cmpKnown [] [1] == none
#guard cmpKnown [0, 1] [3, 4] == none
#guard cmpKnown [2, 3, 5] [0, 0, 1] == some .lower
#guard lockedCmp [⟨some 5, 1⟩] [⟨none, 0⟩] == .na
#guard lookKnown [] [] == none
#guard lookKnown [0] [0] == none
#guard lookKnown [0, 0, 0] [0, 0, 0] == some .same

end Fw.Measure.TouchLock
