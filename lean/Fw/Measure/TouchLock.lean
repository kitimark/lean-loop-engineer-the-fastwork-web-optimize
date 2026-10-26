import Lean.Data.Json
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
deriving Repr, BEq

def reduce (r : Run) : Result :=
  let s := lockOf r
  { openFrames := (openPhase r.frames).length, displacedFrames := displacedAt s r.frames,
    frameReversals := reversals r.frames, frameFights := fightsAt s r.frames,
    restores := displacedAt s r.events, eventReversals := reversals r.events, eventFights := fightsAt s r.events,
    jitter := decide (0 < fightsAt s r.frames), lock := s }

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

/-- Samples each side needs before `cmpKnown` or `lookKnown` decides: 3, like `Fw.Measure.Offscreen.minRuns`. -/
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

theorem tally_le (rs : List Run) : (tally rs).2 ≤ (tally rs).1 := by
  simp only [tally]
  exact List.length_filter_le _ _

inductive Arm where
  | orig | base | lock
deriving Repr, BEq, DecidableEq

def Arm.name : Arm → String
  | .orig => "orig"
  | .base => "base"
  | .lock => "lock"

def repOrder (rep : Nat) : List Arm :=
  if rep % 2 = 0 then [.base, .lock, .orig] else [.lock, .base, .orig]

theorem repOrder_orig_last (rep : Nat) : (repOrder rep).getLast? = some .orig := by
  unfold repOrder; split <;> rfl

theorem repOrder_once (rep : Nat) (a : Arm) : (repOrder rep).count a = 1 := by
  unfold repOrder; split <;> cases a <;> decide

theorem repOrder_even (rep : Nat) (h : rep % 2 = 0) : (repOrder rep).head? = some .base := by
  simp [repOrder, h]

theorem repOrder_odd (rep : Nat) (h : rep % 2 = 1) : (repOrder rep).head? = some .lock := by
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

/-- Rows for `cmpKnown`: complete rows hold `minSamples` values per side and keep the `cmp` word; short rows are undecided. -/
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

/-- Rows for `lookKnown`, as for `cmpKnownCases`. -/
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

open Lean in
def sampleJson (s : Sample) : Json := Json.arr #[toJson s.y, toJson (if s.isOpen then 1 else 0)]

open Lean in
def samplesJson (xs : List Sample) : Json := Json.arr (xs.map sampleJson).toArray

open Lean in
def resultJson (r : Result) : Json :=
  Json.mkObj [("openFrames", toJson r.openFrames), ("displacedFrames", toJson r.displacedFrames),
    ("frameReversals", toJson r.frameReversals), ("frameFights", toJson r.frameFights), ("restores", toJson r.restores),
    ("eventReversals", toJson r.eventReversals), ("eventFights", toJson r.eventFights), ("jitter", toJson r.jitter),
    ("lock", match r.lock with | some l => toJson l | none => Json.null)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("minOpenFrames", toJson minOpenFrames), ("maxRestarts", toJson maxRestarts), ("minSamples", toJson minSamples)]).compress
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
  [consts] ++ rs ++ cs ++ ls ++ ts ++ os ++ ws ++ tg ++ cks ++ lks

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"touch-lock golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"touch-lock golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

#guard (reduce ⟨fightFrames, fightFrames, mk [(5000, true)]⟩).jitter == true
#guard (reduce ⟨steadyFrames, steadyFrames, mk []⟩).jitter == false
#guard (reduce ⟨monotoneFrames, monotoneFrames, mk []⟩).frameReversals == 0
#guard cmp [2, 3, 5] [0, 0, 1] == .lower
#guard cmpKnown [] [1] == none
#guard cmpKnown [0, 1] [3, 4] == none
#guard cmpKnown [2, 3, 5] [0, 0, 1] == some .lower
#guard lookKnown [] [] == none
#guard lookKnown [0] [0] == none
#guard lookKnown [0, 0, 0] [0, 0, 0] == some .same

end Fw.Measure.TouchLock
