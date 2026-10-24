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

def lockOf (xs : List Sample) : Option Int := (openPhase xs).head?.map (·.y)

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

structure Run where
  frames : List Sample
  events : List Sample
deriving Repr, BEq

def minOpenFrames : Nat := 10

inductive Refusal where
  | noOpen | tooShort
deriving Repr, BEq, DecidableEq

def Refusal.name : Refusal → String
  | .noOpen => "noOpen"
  | .tooShort => "tooShort"

def refusal (r : Run) : Option Refusal :=
  if (openPhase r.frames).length = 0 then some .noOpen
  else if (openPhase r.frames).length < minOpenFrames then some .tooShort
  else none

structure Result where
  openFrames : Nat
  displacedFrames : Nat
  frameReversals : Nat
  frameFights : Nat
  restores : Nat
  eventReversals : Nat
  eventFights : Nat
  jitter : Bool
deriving Repr, BEq

def reduce (r : Run) : Result :=
  let s := (lockOf r.frames).getD 0
  { openFrames := (openPhase r.frames).length, displacedFrames := displaced s r.frames,
    frameReversals := reversals r.frames, frameFights := fights s r.frames,
    restores := displaced s r.events, eventReversals := reversals r.events, eventFights := fights s r.events,
    jitter := decide (0 < fights s r.frames) }

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

theorem refusal_none_iff (r : Run) : refusal r = none ↔ minOpenFrames ≤ (openPhase r.frames).length := by
  unfold refusal minOpenFrames
  by_cases h0 : (openPhase r.frames).length = 0 <;> by_cases h1 : (openPhase r.frames).length < 10 <;> simp [h0, h1] <;> omega

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

theorem jitter_false_of_steady (r : Run) (h : displaced ((lockOf r.frames).getD 0) r.frames = 0) : (reduce r).jitter = false := by
  have := fights_zero_of_steady ((lockOf r.frames).getD 0) r.frames ((displaced_zero_iff _ _).mp h)
  simp [reduce, this]

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

def neverOpen : Run := ⟨mk (List.replicate 20 (4000, false)), mk []⟩

def shortOpen : Run := ⟨mk [(5000, true), (5000, true), (5040, true), (5000, true)], mk []⟩

def runCases : List (String × Run) := [
  ("steady open phase", ⟨steadyFrames, steadyFrames⟩),
  ("restore after a displaced frame", ⟨fightFrames, fightFrames⟩),
  ("frames steady, events fight", ⟨steadyFrames, fightFrames⟩),
  ("one way drift is not a fight", ⟨monotoneFrames, monotoneFrames⟩),
  ("bounce back to the lock", ⟨bounceFrames, bounceFrames⟩),
  ("never open", neverOpen),
  ("open for 4 frames", shortOpen),
  ("closed, open, closed", ⟨mk ([(1, false)] ++ List.replicate 10 (5000, true) ++ [(1, false), (1, true)]), mk []⟩)]

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
  ("nothing measured", ([], []))]

open Lean in
def sampleJson (s : Sample) : Json := Json.arr #[toJson s.y, toJson (if s.isOpen then 1 else 0)]

open Lean in
def samplesJson (xs : List Sample) : Json := Json.arr (xs.map sampleJson).toArray

open Lean in
def resultJson (r : Result) : Json :=
  Json.mkObj [("openFrames", toJson r.openFrames), ("displacedFrames", toJson r.displacedFrames),
    ("frameReversals", toJson r.frameReversals), ("frameFights", toJson r.frameFights), ("restores", toJson r.restores),
    ("eventReversals", toJson r.eventReversals), ("eventFights", toJson r.eventFights), ("jitter", toJson r.jitter)]

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("minOpenFrames", toJson minOpenFrames), ("maxRestarts", toJson maxRestarts)]).compress
  let rs := runCases.map fun (name, r) =>
    (Json.mkObj [("op", "run"), ("case", Json.str name), ("frames", samplesJson r.frames), ("events", samplesJson r.events),
      ("refusal", match refusal r with | some f => Json.str f.name | none => Json.null),
      ("result", resultJson (reduce r))]).compress
  let cs := cmpCases.map fun (name, f, c) =>
    (Json.mkObj [("op", "cmp"), ("case", Json.str name), ("faith", toJson f), ("cand", toJson c),
      ("out", Json.str (cmp f c).name)]).compress
  let ls := lookCases.map fun (name, f, c) =>
    (Json.mkObj [("op", "look"), ("case", Json.str name), ("faith", toJson f), ("cand", toJson c),
      ("out", Json.str (look f c).name)]).compress
  let ts := [("two arms", [⟨steadyFrames, steadyFrames⟩, ⟨fightFrames, fightFrames⟩, neverOpen, shortOpen])].map fun (name, l) =>
    (Json.mkObj [("op", "tally"), ("case", Json.str name), ("runs", Json.arr (l.map fun r =>
      Json.mkObj [("frames", samplesJson r.frames), ("events", samplesJson r.events)]).toArray),
      ("accepted", toJson (tally l).1), ("jitter", toJson (tally l).2)]).compress
  let os := (List.range 4).map fun rep =>
    (Json.mkObj [("op", "order"), ("rep", toJson rep), ("arms", toJson ((repOrder rep).map Arm.name))]).compress
  let ws := [(0, false), (0, true), (1, true), (2, true), (3, false)].map fun (used, stalled) =>
    (Json.mkObj [("op", "lane"), ("used", toJson used), ("stalled", toJson stalled),
      ("out", Json.str (afterWindow used stalled).name)]).compress
  [consts] ++ rs ++ cs ++ ls ++ ts ++ os ++ ws

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

#guard (reduce ⟨fightFrames, fightFrames⟩).jitter == true
#guard (reduce ⟨steadyFrames, steadyFrames⟩).jitter == false
#guard (reduce ⟨monotoneFrames, monotoneFrames⟩).frameReversals == 0
#guard cmp [2, 3, 5] [0, 0, 1] == .lower

end Fw.Measure.TouchLock
