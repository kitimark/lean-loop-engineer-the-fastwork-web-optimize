import Lean.Data.Json
import Fw.Measure.TouchLock
/-!
# Closes, re-opens and spring-back fights of the end-of-page morph, by finger direction
Twin: `packages/measure-webkit/src/throttle/morph-end.mjs`. Inputs are the per-frame record of `throttle/finish-page.mjs`: the morph
value `r` (tenth of a percent), the finger direction `d` (-1 up, 0 none, 1 down), the scroll position `y` and the instant `scrollTo` writes.
-/
namespace Fw.Measure.MorphEndCount
open Lean

/-- The finger direction of a frame. -/
inductive Dir where
  | up | down | none
  deriving DecidableEq, Repr

/-- The page reads -1 for a finger moving up, 1 for down, anything else is no direction. -/
def Dir.ofInt (d : Int) : Dir := if d < 0 then .up else if 0 < d then .down else .none

/-- The name used in the report and the golden. -/
def Dir.name : Dir → String
  | .up => "up"
  | .down => "down"
  | .none => "none"

/-- A count per finger direction. -/
structure ByDir where
  up : Nat
  down : Nat
  none : Nat
  deriving DecidableEq, Repr

/-- The sum over the three directions. -/
def ByDir.total (b : ByDir) : Nat := b.up + b.down + b.none

/-- Direction-wise sum, used to pool passes. -/
def ByDir.add (a b : ByDir) : ByDir := ⟨a.up + b.up, a.down + b.down, a.none + b.none⟩

/-- Direction-wise sum of a list. -/
def ByDir.sum (l : List ByDir) : ByDir := ⟨(l.map (·.up)).sum, (l.map (·.down)).sum, (l.map (·.none)).sum⟩

/-- What happened to the morph value. -/
inductive Kind where
  | close | reopen
  deriving DecidableEq, Repr

/-- The name used in the report and the golden. -/
def Kind.name : Kind → String
  | .close => "close"
  | .reopen => "reopen"

/-- A turn of the morph value: at `frame`, with the finger going `dir` at that frame. -/
structure Event where
  kind : Kind
  frame : Nat
  dir : Dir
  deriving DecidableEq, Repr

/-- -1, 0 or 1. -/
def sign (x : Int) : Int := if 0 < x then 1 else if x < 0 then -1 else 0

/-- The signs of the steps of a series that starts at `prev`. -/
def steps (prev : Int) : List Int → List Int
  | [] => []
  | x :: xs => sign (x - prev) :: steps x xs

/-- Number of sign changes along a list of signs, `last` being the sign before it (0 = none yet); zeros are skipped. -/
def changes (last : Int) : List Int → Nat
  | [] => 0
  | s :: t => if s = 0 then changes last t else (if last ≠ 0 ∧ s ≠ last then 1 else 0) + changes s t

/-- Events of the series after `prev`, the next frame having index `i`; `ds` holds the finger directions from frame `i` on. A flat step
changes nothing, a step against the sign of the last moving step is one event, a fall is a close and a rise a re-open. -/
def walk (last prev : Int) (i : Nat) : List Int → List Int → List Event
  | [], _ => []
  | x :: xs, ds =>
    let s := sign (x - prev)
    if s = 0 then walk last x (i + 1) xs ds.tail
    else (if last ≠ 0 ∧ s ≠ last then [⟨if s < 0 then .close else .reopen, i, Dir.ofInt (ds.headD 0)⟩] else [])
      ++ walk s x (i + 1) xs ds.tail

/-- The close and re-open events of a morph series `r` with finger directions `d`; the first step is no event. -/
def events (r d : List Int) : List Event :=
  match r with
  | [] => []
  | x :: xs => walk 0 x 1 xs (d.drop 1)

/-- Events of one kind by finger direction. -/
def countKD (k : Kind) (dr : Dir) (evs : List Event) : Nat := (evs.filter fun e => e.kind == k && e.dir == dr).length

/-- Events of one kind by finger direction, as three counts. -/
def byDirection (k : Kind) (evs : List Event) : ByDir := ⟨countKD k .up evs, countKD k .down evs, countKD k .none evs⟩

/-- Opens: values above 0 that follow a 0 (the series starts at 0). -/
def risesFrom (prev : Int) : List Int → Nat
  | [] => 0
  | x :: xs => (if 0 < x ∧ prev = 0 then 1 else 0) + risesFrom x xs

/-- The number of times the morph starts to open. -/
def opens (r : List Int) : Nat := risesFrom 0 r

/-- Runs of frames with a nonzero flag, as first and last index; `start` is the first index of the run in progress. -/
def stretchesFrom (i : Nat) (start : Option Nat) : List Int → List (Nat × Nat)
  | [] => match start with
    | some a => [(a, i - 1)]
    | none => []
  | x :: xs =>
    if x ≠ 0 then stretchesFrom (i + 1) (start.orElse fun _ => some i) xs
    else match start with
      | some a => (a, i - 1) :: stretchesFrom (i + 1) none xs
      | none => stretchesFrom (i + 1) none xs

/-- The stretches of open frames of the flag series `o`. -/
def stretches (o : List Int) : List (Nat × Nat) := stretchesFrom 0 none o

/-! ## Spring-back fights -/

/-- An instant `scrollTo` of the page: the target `top` (tenth px), whether the morph was open, and the index of the next frame. -/
structure Write where
  top : Int
  isOpen : Bool
  frame : Nat
  deriving DecidableEq, Repr

/-- A step of `move` is against a finger going `d`: a finger moving up lets the page scroll forward, so a write that lowers the position
fights it; a finger moving down is fought by a write that raises it. -/
def against (d move : Int) : Bool := (decide (d < 0) && decide (move < 0)) || (decide (0 < d) && decide (0 < move))

/-- The finger direction of a spring-back fight, or none when the write is not one. The write is judged by the last frame before it. -/
def fightDir (ys ds : List Int) (w : Write) : Option Dir :=
  if w.frame = 0 then Option.none
  else match ys[w.frame - 1]?, ds[w.frame - 1]? with
    | some y, some d => if w.isOpen && against d (w.top - y) then some (Dir.ofInt d) else Option.none
    | _, _ => Option.none

/-- The directions of the fights among the writes, one per fight. -/
def fightDirs (ys ds : List Int) (ws : List Write) : List Dir := ws.filterMap (fightDir ys ds)

/-- Spring-back fights by finger direction: every write is counted at most once. -/
def springBack (ys ds : List Int) (ws : List Write) : ByDir :=
  let l := fightDirs ys ds ws
  ⟨(l.filter (· == Dir.up)).length, (l.filter (· == Dir.down)).length, (l.filter (· == Dir.none)).length⟩

/-! ## One pass and many passes -/

/-- The counts of one pass. -/
structure Counts where
  opens : Nat
  closes : ByDir
  reopens : ByDir
  springBack : ByDir
  deriving DecidableEq, Repr

/-- The counts of one record. -/
def ofRecord (r d y : List Int) (ws : List Write) : Counts :=
  let evs := events r d
  ⟨opens r, byDirection .close evs, byDirection .reopen evs, springBack y d ws⟩

/-- The counts of several passes: field-wise sums. -/
def total (cs : List Counts) : Counts :=
  ⟨(cs.map (·.opens)).sum, ByDir.sum (cs.map (·.closes)), ByDir.sum (cs.map (·.reopens)), ByDir.sum (cs.map (·.springBack))⟩

/-! ## Theorems: events -/

theorem events_nil (d : List Int) : events [] d = [] := rfl

theorem events_single (x : Int) (d : List Int) : events [x] d = [] := rfl

/-- Each turn of the morph value is one event: the number of events is the number of sign changes of its moving steps, however many flat
frames lie between them. -/
theorem walk_length (xs : List Int) : ∀ (last prev : Int) (i : Nat) (ds : List Int),
    (walk last prev i xs ds).length = changes last (steps prev xs) := by
  induction xs with
  | nil => intro last prev i ds; rfl
  | cons x xs ih =>
    intro last prev i ds
    by_cases h : sign (x - prev) = 0
    · simp [walk, steps, changes, h, ih]
    · by_cases h2 : last ≠ 0 ∧ sign (x - prev) ≠ last
      · simp [walk, steps, changes, h, h2, ih, Nat.add_comm]
      · simp [walk, steps, changes, h, h2, ih]

theorem events_length (r d : List Int) :
    (events r d).length = match r with | [] => 0 | x :: xs => changes 0 (steps x xs) := by
  cases r with
  | nil => rfl
  | cons x xs => exact walk_length xs 0 x 1 (d.drop 1)

/-- A flat series has no event. -/
theorem steps_const (v : Int) : ∀ l : List Int, (∀ y ∈ l, y = v) → ∀ prev, prev = v → steps prev l = List.replicate l.length 0 := by
  intro l
  induction l with
  | nil => intros; rfl
  | cons x xs ih =>
    intro h prev hp
    have hx : x = v := h x (by simp)
    have : sign (x - prev) = 0 := by simp [sign, hx, hp]
    simp [steps, this, ih (fun y hy => h y (by simp [hy])) x (by rw [hx]), List.replicate_succ]

theorem changes_zeros (last : Int) : ∀ n : Nat, changes last (List.replicate n 0) = 0 := by
  intro n
  induction n with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, changes, ih]

theorem events_const (v : Int) (d : List Int) (n : Nat) : events (List.replicate n v) d = [] := by
  cases n with
  | zero => rfl
  | succ n =>
    have h := walk_length (List.replicate n v) 0 v 1 (d.drop 1)
    rw [steps_const v (List.replicate n v) (fun y hy => List.eq_of_mem_replicate hy) v rfl, changes_zeros] at h
    exact List.length_eq_zero_iff.mp h

/-- Every event is in exactly one finger-direction bucket of its kind. -/
theorem byDirection_total (k : Kind) : ∀ evs : List Event, (byDirection k evs).total = (evs.filter (·.kind == k)).length := by
  intro evs
  induction evs with
  | nil => rfl
  | cons e t ih =>
    unfold byDirection ByDir.total countKD at *
    cases e with
    | mk ek f dr =>
      cases ek <;> cases k <;> cases dr <;> simp_all <;> omega

/-- Closes and re-opens together are all the events, each once. -/
theorem closes_reopens_total (evs : List Event) :
    (byDirection .close evs).total + (byDirection .reopen evs).total = evs.length := by
  rw [byDirection_total, byDirection_total]
  induction evs with
  | nil => rfl
  | cons e t ih =>
    cases e with
    | mk ek f dr => cases ek <;> simp <;> omega

/-- The events of a series, counted by kind and direction, add up to the sign changes of the series. -/
theorem counted_once (r d : List Int) :
    (byDirection .close (events r d)).total + (byDirection .reopen (events r d)).total
      = match r with | [] => 0 | x :: xs => changes 0 (steps x xs) := by
  rw [closes_reopens_total, events_length]

/-- A falling step after a rise is a close, with the finger direction of its frame. -/
theorem close_after_rise (prev x : Int) (i : Nat) (ds : List Int) (h : x < prev) :
    walk 1 prev i [x] ds = [⟨.close, i, Dir.ofInt (ds.headD 0)⟩] := by
  have : sign (x - prev) = -1 := by simp [sign]; omega
  simp [walk, this]

/-- A rising step after a fall is a re-open, with the finger direction of its frame. -/
theorem reopen_after_fall (prev x : Int) (i : Nat) (ds : List Int) (h : prev < x) :
    walk (-1) prev i [x] ds = [⟨.reopen, i, Dir.ofInt (ds.headD 0)⟩] := by
  have : sign (x - prev) = 1 := by simp [sign]; omega
  simp [walk, this]

/-- A step the same way as the last one is no event. -/
theorem no_event_same_way (prev x : Int) (i : Nat) (ds : List Int) (h : prev < x) : walk 1 prev i [x] ds = [] := by
  have : sign (x - prev) = 1 := by simp [sign]; omega
  simp [walk, this]

/-- The first moving step is no event, whichever way it goes. -/
theorem first_step_no_event (prev x : Int) (i : Nat) (ds : List Int) : walk 0 prev i [x] ds = [] := by
  by_cases h : sign (x - prev) = 0 <;> simp [walk, h]

/-! ## Theorems: opens and stretches -/

theorem opens_nil : opens [] = 0 := rfl

theorem risesFrom_zero_of_zeros (prev : Int) : ∀ l : List Int, (∀ x ∈ l, x = 0) → risesFrom prev l = 0 := by
  intro l
  induction l generalizing prev with
  | nil => intros; rfl
  | cons x xs ih =>
    intro h
    have hx : x = 0 := h x (by simp)
    subst hx
    simp [risesFrom, ih 0 (fun y hy => h y (by simp [hy]))]

theorem opens_zero_of_closed (r : List Int) (h : ∀ x ∈ r, x = 0) : opens r = 0 := risesFrom_zero_of_zeros 0 r h

theorem stretches_nil : stretches [] = [] := rfl

theorem stretches_closed (n : Nat) : stretches (List.replicate n 0) = [] := by
  have : ∀ (m : Nat) (i : Nat), stretchesFrom i none (List.replicate m 0) = [] := by
    intro m
    induction m with
    | zero => intro i; rfl
    | succ m ih => intro i; simp [List.replicate_succ, stretchesFrom, ih]
  exact this n 0

example : stretches [0, 1, 1, 0, 1, 0, 0, 1, 1, 1] = [(1, 2), (4, 4), (7, 9)] := by decide

/-! ## Theorems: spring-back fights -/

theorem fightDir_frame_zero (ys ds : List Int) (w : Write) (h : w.frame = 0) : fightDir ys ds w = Option.none := by
  simp [fightDir, h]

/-- A write while the morph is closed is no fight. -/
theorem fightDir_closed (ys ds : List Int) (w : Write) (h : w.isOpen = false) : fightDir ys ds w = Option.none := by
  unfold fightDir
  split <;> try rfl
  split <;> simp_all

/-- A fight needs a finger: a write with no finger direction is none. -/
theorem fightDir_no_finger (ys ds : List Int) (w : Write) (y : Int) (hy : ys[w.frame - 1]? = some y) (hd : ds[w.frame - 1]? = some 0) :
    fightDir ys ds w = Option.none := by
  unfold fightDir
  split
  · rfl
  · simp [hy, hd, against]

/-- A spring-back fight with the finger going up is a write below the position the page had: it pulls the page back against a finger
that scrolls it forward. -/
theorem fight_up_lowers (ys ds : List Int) (w : Write) (h : fightDir ys ds w = some .up) :
    ∃ y, ys[w.frame - 1]? = some y ∧ w.top < y := by
  unfold fightDir at h
  split at h
  · simp at h
  · split at h
    · rename_i y d hy hd
      by_cases hc : (w.isOpen && against d (w.top - y)) = true
      · simp only [hc, ite_true] at h
        have hd0 : d < 0 := by
          simp only [Bool.and_eq_true, against, Bool.or_eq_true, decide_eq_true_eq] at hc
          unfold Dir.ofInt at h
          by_cases h1 : d < 0
          · exact h1
          · by_cases h2 : 0 < d <;> simp [h1, h2] at h
        refine ⟨y, hy, ?_⟩
        simp only [Bool.and_eq_true, against, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at hc
        omega
      · simp [hc] at h
    · simp at h

/-- A spring-back fight with the finger going down is a write above the position the page had. -/
theorem fight_down_raises (ys ds : List Int) (w : Write) (h : fightDir ys ds w = some .down) :
    ∃ y, ys[w.frame - 1]? = some y ∧ y < w.top := by
  unfold fightDir at h
  split at h
  · simp at h
  · split at h
    · rename_i y d hy hd
      by_cases hc : (w.isOpen && against d (w.top - y)) = true
      · simp only [hc, ite_true] at h
        have hd0 : 0 < d := by
          simp only [Bool.and_eq_true, against, Bool.or_eq_true, decide_eq_true_eq] at hc
          unfold Dir.ofInt at h
          by_cases h1 : d < 0
          · simp [h1] at h
          · by_cases h2 : 0 < d
            · exact h2
            · simp [h1, h2] at h
        refine ⟨y, hy, ?_⟩
        simp only [Bool.and_eq_true, against, Bool.or_eq_true, Bool.and_eq_true, decide_eq_true_eq] at hc
        omega
      · simp [hc] at h
    · simp at h

/-- No fight is ever filed under no direction. -/
theorem fightDir_ne_none (ys ds : List Int) (w : Write) (dr : Dir) (h : fightDir ys ds w = some dr) : dr ≠ Dir.none := by
  intro e
  subst e
  unfold fightDir at h
  split at h
  · simp at h
  · split at h
    · rename_i y d hy hd
      by_cases hc : (w.isOpen && against d (w.top - y)) = true
      · simp only [hc, ite_true] at h
        simp only [Bool.and_eq_true, against, Bool.or_eq_true, decide_eq_true_eq] at hc
        unfold Dir.ofInt at h
        by_cases h1 : d < 0 <;> by_cases h2 : 0 < d <;> simp [h1, h2] at h <;> omega
      · simp [hc] at h
    · simp at h

theorem fightDirs_length_le (ys ds : List Int) (ws : List Write) : (fightDirs ys ds ws).length ≤ ws.length :=
  List.length_filterMap_le _ _

theorem springBack_nil (ys ds : List Int) : springBack ys ds [] = ⟨0, 0, 0⟩ := rfl

/-- The `none` bucket of the fights is always empty. -/
theorem springBack_none_zero (ys ds : List Int) (ws : List Write) : (springBack ys ds ws).none = 0 := by
  unfold springBack
  simp only
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro a ha
  have := List.mem_filterMap.mp ha
  obtain ⟨w, _, hw⟩ := this
  have := fightDir_ne_none ys ds w a hw
  simpa using this

/-- Every fight is counted once: the buckets hold no more than the writes. -/
theorem springBack_total_le (ys ds : List Int) (ws : List Write) : (springBack ys ds ws).total ≤ ws.length := by
  unfold springBack ByDir.total
  simp only
  have h0 := springBack_none_zero ys ds ws
  unfold springBack at h0
  simp only at h0
  have hl := fightDirs_length_le ys ds ws
  unfold fightDirs at *
  generalize (ws.filterMap (fightDir ys ds)) = l at *
  have : ∀ l : List Dir, (l.filter (· == Dir.up)).length + (l.filter (· == Dir.down)).length + (l.filter (· == Dir.none)).length = l.length := by
    intro l
    induction l with
    | nil => rfl
    | cons a t ih => cases a <;> simp <;> omega
  have := this l
  omega

/-! ## Theorems: passes -/

/-- Pooling passes is a field-wise sum, so the pooled counts do not depend on the order of the passes. -/
theorem total_perm {a b : List Counts} (h : a.Perm b) : total a = total b := by
  have hs : ∀ f : Counts → Nat, (a.map f).sum = (b.map f).sum := fun f => (h.map f).sum_nat
  simp [total, ByDir.sum, List.map_map, Function.comp_def, hs]

/-- Pooling two sets of passes adds their counts. -/
theorem total_append (a b : List Counts) :
    total (a ++ b) = ⟨(total a).opens + (total b).opens, (total a).closes.add (total b).closes,
      (total a).reopens.add (total b).reopens, (total a).springBack.add (total b).springBack⟩ := by
  unfold total ByDir.sum ByDir.add
  simp [List.map_append, List.sum_append]

/-! ## The verdict of a brick -/

open Fw.Measure.TouchLock (Cmp cmp)

/-- A pass's count per 1000 open starts; a pass with no open start has no rate. -/
def perThousand (count opens : Nat) : Option Nat := if opens = 0 then Option.none else some (count * 1000 / opens)

/-- The rates of the passes, each given as its count and its open starts. -/
def rates (ps : List (Nat × Nat)) : List Nat := ps.filterMap fun p => perThousand p.1 p.2

/-- The verdict of a brick against the faithful page. -/
inductive Brick where
  | win | trade | noWin
  deriving DecidableEq, Repr

/-- The name used in the report and the golden. -/
def Brick.name : Brick → String
  | .win => "win"
  | .trade => "trade"
  | .noWin => "no-win"

/-- A brick wins when something improves and nothing gets worse, trades when something improves and something gets worse, and has no win
when nothing improves. Better: reversals or fights per open start lower in every pass of the brick than in any faithful pass, or the
still runs lifted. Worse: reversals or fights higher in every pass of the brick than in any faithful pass. -/
def brickVerdict (rev fight : Cmp) (stillLifted : Bool) : Brick :=
  let better := (if rev = .lower then 1 else 0) + (if fight = .lower then 1 else 0) + (if stillLifted then 1 else 0)
  let worse := (if rev = .higher then 1 else 0) + (if fight = .higher then 1 else 0)
  if better = 0 then .noWin else if worse = 0 then .win else .trade

/-- The verdict from the passes: reversals and spring-back fights as (count, open starts) per pass, faithful against brick. -/
def verdictOf (faithRev candRev faithFight candFight : List (Nat × Nat)) (stillLifted : Bool) : Brick :=
  brickVerdict (cmp (rates faithRev) (rates candRev)) (cmp (rates faithFight) (rates candFight)) stillLifted

theorem perThousand_zero (count : Nat) : perThousand count 0 = Option.none := rfl

theorem perThousand_pos (count opens : Nat) (h : opens ≠ 0) : perThousand count opens = some (count * 1000 / opens) := by
  simp [perThousand, h]

theorem rates_length_le (ps : List (Nat × Nat)) : (rates ps).length ≤ ps.length := List.length_filterMap_le _ _

/-- Nothing improves: no win, whatever got worse. -/
theorem brickVerdict_noWin (rev fight : Cmp) (stillLifted : Bool) (h1 : rev ≠ .lower) (h2 : fight ≠ .lower) (h3 : stillLifted = false) :
    brickVerdict rev fight stillLifted = .noWin := by
  simp [brickVerdict, h1, h2, h3]

/-- Something improves and nothing is worse: a win. -/
theorem brickVerdict_win (rev fight : Cmp) (stillLifted : Bool) (hb : rev = .lower ∨ fight = .lower ∨ stillLifted = true)
    (h1 : rev ≠ .higher) (h2 : fight ≠ .higher) : brickVerdict rev fight stillLifted = .win := by
  unfold brickVerdict
  rcases hb with h | h | h <;> cases rev <;> cases fight <;> cases stillLifted <;> simp_all <;> contradiction

/-- Something improves and something is worse: a trade. -/
theorem brickVerdict_trade (rev fight : Cmp) (stillLifted : Bool) (hb : rev = .lower ∨ fight = .lower ∨ stillLifted = true)
    (hw : rev = .higher ∨ fight = .higher) : brickVerdict rev fight stillLifted = .trade := by
  unfold brickVerdict
  rcases hb with h | h | h <;> rcases hw with h' | h' <;> cases rev <;> cases fight <;> cases stillLifted <;> simp_all <;> contradiction

theorem foldl_min_le (l : List Nat) : ∀ m : Nat, l.foldl min m ≤ m := by
  induction l with
  | nil => intro m; exact Nat.le_refl m
  | cons a t ih => intro m; exact Nat.le_trans (ih (min m a)) (Nat.min_le_left m a)

/-- A faithful page against itself is a no-win. -/
theorem verdictOf_self (rev fight : List (Nat × Nat)) : verdictOf rev rev fight fight false = .noWin := by
  unfold verdictOf
  have h : ∀ l : List Nat, cmp l l ≠ .lower := by
    intro l
    have hle : Fw.Measure.TouchLock.minOf l ≤ Fw.Measure.TouchLock.maxOf l := foldl_min_le l _
    have hn : ¬ Fw.Measure.TouchLock.maxOf l < Fw.Measure.TouchLock.minOf l := by omega
    unfold cmp
    simp [hn]
  exact brickVerdict_noWin _ _ _ (h _) (h _) rfl

/-! ## The golden -/

private def intsJ (l : List Int) : Json := Json.arr (l.map toJson).toArray

private def dirJ (b : ByDir) : Json := Json.mkObj [("up", b.up), ("down", b.down), ("none", b.none)]

private def eventJ (e : Event) : Json :=
  Json.mkObj [("kind", e.kind.name), ("frame", e.frame), ("dir", e.dir.name)]

private def writeJ (w : Write) : Json := Json.arr #[toJson w.top, toJson (if w.isOpen then 1 else 0), toJson w.frame]

private def countsJ (c : Counts) : Json :=
  Json.mkObj [("opens", c.opens), ("closes", dirJ c.closes), ("reopens", dirJ c.reopens), ("springBack", dirJ c.springBack)]

private def lcg (s : Nat) : Nat := (s * 1103515245 + 12345) % 2147483648

/-- A pseudo-random morph series: plateaus, rises and falls, with a finger direction per frame. -/
private def noisy (n seed : Nat) : List Int × List Int :=
  let rows := (List.range n).foldl (fun (acc : Nat × Int × Int × List (Int × Int)) _ =>
    let s := lcg acc.1
    let step : Int := if s % 5 < 2 then 0 else (((s / 5) % 7 : Nat) : Int) * 100 - 300
    let r := max 0 (min 1000 (acc.2.1 + step))
    let d : Int := ((s / 31) % 3 : Nat) - 1
    (s, r, d, (r, d) :: acc.2.2.2)) (seed, 0, 0, [])
  (rows.2.2.2.reverse.map (·.1), rows.2.2.2.reverse.map (·.2))

private def eventCases (_ : Unit) : List (String × List Int × List Int) :=
  [("empty", [], []), ("single", [5], [1]), ("flat", [5, 5, 5], [1, 1, 1]), ("monotone rise", [0, 100, 200, 1000], [0, 0, 0, 0]),
   ("two closes and two re-opens", [0, 0, 300, 700, 1000, 1000, 600, 100, 0, 0, 400, 1000, 1000, 500, 800],
    [-1, -1, -1, -1, -1, -1, 1, 1, 1, 1, -1, -1, -1, 1, -1]),
   ("direction none", [0, 500, 400], [0, 0, 0]), ("missing finger reads", [0, 500, 400, 600], [0, -1]),
   ("starts with a fall", [900, 600, 300, 500], [0, 1, 1, -1]),
   ("flat frames between a rise and a fall", [0, 400, 400, 400, 200], [0, -1, -1, -1, 1]),
   ("fall, rise, fall at once", [0, 500, 400, 600, 300], [0, -1, 1, -1, 1]),
   ("constant", List.replicate 8 300, List.replicate 8 1), ("noisy 80", (noisy 80 7).1, (noisy 80 7).2),
   ("noisy 300", (noisy 300 11).1, (noisy 300 11).2)]

private def stretchCases (_ : Unit) : List (List Int) :=
  [[], [0, 0], [1], [1, 1, 1], [0, 1, 1, 0, 1, 0, 0, 1, 1, 1], [1, 0, 1, 0, 1], [0, 0, 0, 1]]

private def mkW (l : List (Int × Bool × Nat)) : List Write := l.map fun (t, o, f) => ⟨t, o, f⟩

private def fightCases (_ : Unit) : List (String × List Int × List Int × List Write) :=
  [("no writes", [5200, 5300], [-1, -1], []),
   ("finger up, write lowers", [5300, 5320, 5330], [-1, -1, -1], mkW [(5223, true, 3)]),
   ("finger up, write raises", [5200, 5210], [-1, -1], mkW [(5300, true, 2)]),
   ("finger down, write raises", [5300, 5290, 5280], [1, 1, 1], mkW [(5400, true, 3)]),
   ("finger down, write lowers", [5300, 5290], [1, 1], mkW [(5100, true, 2)]),
   ("no finger", [5300, 5320], [0, 0], mkW [(5223, true, 2)]),
   ("write while closed", [5300, 5320], [-1, -1], mkW [(5223, false, 2)]),
   ("write at frame 0", [5300], [-1], mkW [(5223, true, 0)]),
   ("write past the record", [5300], [-1], mkW [(5223, true, 9)]),
   ("write equal to the position", [5300, 5300], [-1, -1], mkW [(5300, true, 2)]),
   ("two directions", [5300, 5320, 5100, 5000], [-1, -1, 1, 1], mkW [(5223, true, 2), (5223, true, 3), (5500, true, 4), (5100, true, 4)])]

private def passCases (_ : Unit) : List (String × List Int × List Int × List Int × List Write) :=
  [("one cycle", [0, 0, 300, 700, 1000, 600, 100, 0, 400], [0, -1, -1, -1, -1, 1, 1, 1, -1], [5200, 5210, 5300, 5320, 5330, 5300, 5250, 5240, 5260],
    mkW [(5223, true, 3), (5223, true, 4), (5300, true, 6)]),
   ("never opened", [0, 0, 0], [0, 0, 0], [5200, 5200, 5200], [])]

private def pairsJ (l : List (Nat × Nat)) : Json := Json.arr (l.map fun p => toJson [p.1, p.2]).toArray

private def verdictCases (_ : Unit) : List (String × List (Nat × Nat) × List (Nat × Nat) × List (Nat × Nat) × List (Nat × Nat) × Bool) :=
  [("fewer reversals, fights equal", [(12, 4), (10, 4), (14, 4)], [(2, 4), (3, 4), (4, 4)], [(6, 4), (7, 4)], [(6, 4), (7, 4)], false),
   ("fewer fights", [(12, 4), (10, 4)], [(11, 4), (10, 4)], [(8, 4), (9, 4)], [(1, 4), (2, 4)], false),
   ("lower reversals, higher fights", [(12, 4), (10, 4)], [(2, 4), (3, 4)], [(1, 4), (2, 4)], [(8, 4), (9, 4)], false),
   ("still lifted only", [(12, 4), (10, 4)], [(11, 4), (12, 4)], [(8, 4), (9, 4)], [(8, 4), (9, 4)], true),
   ("still lifted, fights higher", [(12, 4), (10, 4)], [(11, 4), (12, 4)], [(1, 4), (2, 4)], [(8, 4), (9, 4)], true),
   ("everything higher", [(2, 4), (3, 4)], [(12, 4), (10, 4)], [(1, 4), (2, 4)], [(8, 4), (9, 4)], false),
   ("overlap", [(12, 4), (3, 4)], [(8, 4), (9, 4)], [(8, 4), (9, 4)], [(8, 4), (3, 4)], false),
   ("no faithful pass", [], [(2, 4)], [], [(1, 4)], false),
   ("no open starts", [(12, 0)], [(2, 0)], [(1, 0)], [(2, 0)], false),
   ("different open starts per pass", [(10, 2), (30, 6)], [(2, 4), (1, 3)], [(4, 2), (12, 6)], [(1, 4), (1, 3)], false)]

private def goldenLines (_ : Unit) : List String :=
  ((eventCases ()).map fun (name, r, d) =>
    let evs := events r d
    (Json.mkObj [("kind", "events"), ("name", name), ("r", intsJ r), ("d", intsJ d), ("events", Json.arr (evs.map eventJ).toArray),
      ("closes", dirJ (byDirection .close evs)), ("reopens", dirJ (byDirection .reopen evs)), ("opens", opens r)]).compress) ++
  ((stretchCases ()).map fun o =>
    (Json.mkObj [("kind", "stretches"), ("o", intsJ o),
      ("stretches", Json.arr ((stretches o).map fun p => toJson [p.1, p.2]).toArray)]).compress) ++
  ((fightCases ()).map fun (name, ys, ds, ws) =>
    (Json.mkObj [("kind", "fights"), ("name", name), ("y", intsJ ys), ("d", intsJ ds), ("writes", Json.arr (ws.map writeJ).toArray),
      ("springBack", dirJ (springBack ys ds ws))]).compress) ++
  ((passCases ()).map fun (name, r, d, y, ws) =>
    (Json.mkObj [("kind", "pass"), ("name", name), ("r", intsJ r), ("d", intsJ d), ("y", intsJ y), ("writes", Json.arr (ws.map writeJ).toArray),
      ("counts", countsJ (ofRecord r d y ws))]).compress) ++
  ((verdictCases ()).map fun (name, fr, cr, ff, cf, still) =>
    (Json.mkObj [("kind", "verdict"), ("name", name), ("faithRev", pairsJ fr), ("candRev", pairsJ cr), ("faithFight", pairsJ ff),
      ("candFight", pairsJ cf), ("stillLifted", still), ("rev", (cmp (rates fr) (rates cr)).name), ("fight", (cmp (rates ff) (rates cf)).name),
      ("verdict", (verdictOf fr cr ff cf still).name)]).compress) ++
  (let cs := (passCases ()).map fun (_, r, d, y, ws) => ofRecord r d y ws
   let cs3 := cs ++ cs.reverse ++ cs
   [cs, cs.reverse, cs3, []].map fun l =>
    (Json.mkObj [("kind", "total"), ("passes", Json.arr (l.map countsJ).toArray), ("total", countsJ (total l))]).compress)

/-- The bytes of `packages/contracts/golden/device/morph-end-count.jsonl`. -/
def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"morph-end-count golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"morph-end-count golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Measure.MorphEndCount
