import Lean.Data.Json
import Fw.Measure.TouchLock
namespace Fw.Measure.MorphEndCount
open Lean

inductive Dir where
  | up | down | none
  deriving DecidableEq, Repr

def Dir.ofInt (d : Int) : Dir := if d < 0 then .up else if 0 < d then .down else .none

def Dir.name : Dir → String
  | .up => "up"
  | .down => "down"
  | .none => "none"

structure ByDir where
  up : Nat
  down : Nat
  none : Nat
  deriving DecidableEq, Repr

def ByDir.total (b : ByDir) : Nat := b.up + b.down + b.none

def ByDir.add (a b : ByDir) : ByDir := ⟨a.up + b.up, a.down + b.down, a.none + b.none⟩

def ByDir.sum (l : List ByDir) : ByDir := ⟨(l.map (·.up)).sum, (l.map (·.down)).sum, (l.map (·.none)).sum⟩

inductive Kind where
  | close | reopen
  deriving DecidableEq, Repr

def Kind.name : Kind → String
  | .close => "close"
  | .reopen => "reopen"

structure Event where
  kind : Kind
  frame : Nat
  dir : Dir
  deriving DecidableEq, Repr

def sign (x : Int) : Int := if 0 < x then 1 else if x < 0 then -1 else 0

def steps (prev : Int) : List Int → List Int
  | [] => []
  | x :: xs => sign (x - prev) :: steps x xs

def changes (last : Int) : List Int → Nat
  | [] => 0
  | s :: t => if s = 0 then changes last t else (if last ≠ 0 ∧ s ≠ last then 1 else 0) + changes s t

def walk (last prev : Int) (i : Nat) : List Int → List Int → List Event
  | [], _ => []
  | x :: xs, ds =>
    let s := sign (x - prev)
    if s = 0 then walk last x (i + 1) xs ds.tail
    else (if last ≠ 0 ∧ s ≠ last then [⟨if s < 0 then .close else .reopen, i, Dir.ofInt (ds.headD 0)⟩] else [])
      ++ walk s x (i + 1) xs ds.tail

def events (r d : List Int) : List Event :=
  match r with
  | [] => []
  | x :: xs => walk 0 x 1 xs (d.drop 1)

def countKD (k : Kind) (dr : Dir) (evs : List Event) : Nat := (evs.filter fun e => e.kind == k && e.dir == dr).length

def byDirection (k : Kind) (evs : List Event) : ByDir := ⟨countKD k .up evs, countKD k .down evs, countKD k .none evs⟩

def risesFrom (prev : Int) : List Int → Nat
  | [] => 0
  | x :: xs => (if 0 < x ∧ prev = 0 then 1 else 0) + risesFrom x xs

def opens (r : List Int) : Nat := risesFrom 0 r

def stretchesFrom (i : Nat) (start : Option Nat) : List Int → List (Nat × Nat)
  | [] => match start with
    | some a => [(a, i - 1)]
    | none => []
  | x :: xs =>
    if x ≠ 0 then stretchesFrom (i + 1) (start.orElse fun _ => some i) xs
    else match start with
      | some a => (a, i - 1) :: stretchesFrom (i + 1) none xs
      | none => stretchesFrom (i + 1) none xs

def stretches (o : List Int) : List (Nat × Nat) := stretchesFrom 0 none o

structure Write where
  top : Int
  isOpen : Bool
  frame : Nat
  deriving DecidableEq, Repr

def against (d move : Int) : Bool := (decide (d < 0) && decide (move < 0)) || (decide (0 < d) && decide (0 < move))

def fightDir (ys ds : List Int) (w : Write) : Option Dir :=
  if w.frame = 0 then Option.none
  else match ys[w.frame - 1]?, ds[w.frame - 1]? with
    | some y, some d => if w.isOpen && against d (w.top - y) then some (Dir.ofInt d) else Option.none
    | _, _ => Option.none

def fightDirs (ys ds : List Int) (ws : List Write) : List Dir := ws.filterMap (fightDir ys ds)

def springBack (ys ds : List Int) (ws : List Write) : ByDir :=
  let l := fightDirs ys ds ws
  ⟨(l.filter (· == Dir.up)).length, (l.filter (· == Dir.down)).length, (l.filter (· == Dir.none)).length⟩

structure Counts where
  opens : Nat
  closes : ByDir
  reopens : ByDir
  springBack : ByDir
  deriving DecidableEq, Repr

def ofRecord (r d y : List Int) (ws : List Write) : Counts :=
  let evs := events r d
  ⟨opens r, byDirection .close evs, byDirection .reopen evs, springBack y d ws⟩

def total (cs : List Counts) : Counts :=
  ⟨(cs.map (·.opens)).sum, ByDir.sum (cs.map (·.closes)), ByDir.sum (cs.map (·.reopens)), ByDir.sum (cs.map (·.springBack))⟩

theorem events_nil (d : List Int) : events [] d = [] := rfl

theorem events_single (x : Int) (d : List Int) : events [x] d = [] := rfl

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

theorem byDirection_total (k : Kind) : ∀ evs : List Event, (byDirection k evs).total = (evs.filter (·.kind == k)).length := by
  intro evs
  induction evs with
  | nil => rfl
  | cons e t ih =>
    unfold byDirection ByDir.total countKD at *
    cases e with
    | mk ek f dr =>
      cases ek <;> cases k <;> cases dr <;> simp_all <;> omega

theorem closes_reopens_total (evs : List Event) :
    (byDirection .close evs).total + (byDirection .reopen evs).total = evs.length := by
  rw [byDirection_total, byDirection_total]
  induction evs with
  | nil => rfl
  | cons e t ih =>
    cases e with
    | mk ek f dr => cases ek <;> simp <;> omega

theorem counted_once (r d : List Int) :
    (byDirection .close (events r d)).total + (byDirection .reopen (events r d)).total
      = match r with | [] => 0 | x :: xs => changes 0 (steps x xs) := by
  rw [closes_reopens_total, events_length]

theorem close_after_rise (prev x : Int) (i : Nat) (ds : List Int) (h : x < prev) :
    walk 1 prev i [x] ds = [⟨.close, i, Dir.ofInt (ds.headD 0)⟩] := by
  have : sign (x - prev) = -1 := by simp [sign]; omega
  simp [walk, this]

theorem reopen_after_fall (prev x : Int) (i : Nat) (ds : List Int) (h : prev < x) :
    walk (-1) prev i [x] ds = [⟨.reopen, i, Dir.ofInt (ds.headD 0)⟩] := by
  have : sign (x - prev) = 1 := by simp [sign]; omega
  simp [walk, this]

theorem no_event_same_way (prev x : Int) (i : Nat) (ds : List Int) (h : prev < x) : walk 1 prev i [x] ds = [] := by
  have : sign (x - prev) = 1 := by simp [sign]; omega
  simp [walk, this]

theorem first_step_no_event (prev x : Int) (i : Nat) (ds : List Int) : walk 0 prev i [x] ds = [] := by
  by_cases h : sign (x - prev) = 0 <;> simp [walk, h]

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

theorem fightDir_frame_zero (ys ds : List Int) (w : Write) (h : w.frame = 0) : fightDir ys ds w = Option.none := by
  simp [fightDir, h]

theorem fightDir_closed (ys ds : List Int) (w : Write) (h : w.isOpen = false) : fightDir ys ds w = Option.none := by
  unfold fightDir
  split <;> try rfl
  split <;> simp_all

theorem fightDir_no_finger (ys ds : List Int) (w : Write) (y : Int) (hy : ys[w.frame - 1]? = some y) (hd : ds[w.frame - 1]? = some 0) :
    fightDir ys ds w = Option.none := by
  unfold fightDir
  split
  · rfl
  · simp [hy, hd, against]

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

theorem springBack_none_zero (ys ds : List Int) (ws : List Write) : (springBack ys ds ws).none = 0 := by
  unfold springBack
  simp only
  rw [List.length_eq_zero_iff, List.filter_eq_nil_iff]
  intro a ha
  have := List.mem_filterMap.mp ha
  obtain ⟨w, _, hw⟩ := this
  have := fightDir_ne_none ys ds w a hw
  simpa using this

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

theorem total_perm {a b : List Counts} (h : a.Perm b) : total a = total b := by
  have hs : ∀ f : Counts → Nat, (a.map f).sum = (b.map f).sum := fun f => (h.map f).sum_nat
  simp [total, ByDir.sum, List.map_map, Function.comp_def, hs]

theorem total_append (a b : List Counts) :
    total (a ++ b) = ⟨(total a).opens + (total b).opens, (total a).closes.add (total b).closes,
      (total a).reopens.add (total b).reopens, (total a).springBack.add (total b).springBack⟩ := by
  unfold total ByDir.sum ByDir.add
  simp [List.map_append, List.sum_append]

open Fw.Measure.TouchLock (Cmp cmp)

def perThousand (count opens : Nat) : Option Nat := if opens = 0 then Option.none else some (count * 1000 / opens)

def rates (ps : List (Nat × Nat)) : List Nat := ps.filterMap fun p => perThousand p.1 p.2

inductive Brick where
  | win | trade | noWin | undecided
  deriving DecidableEq, Repr

def Brick.name : Brick → String
  | .win => "win"
  | .trade => "trade"
  | .noWin => "no-win"
  | .undecided => "undecided"

def brickVerdict (rev fight : Cmp) (stillLifted stillWorse : Bool) : Brick :=
  let better := (if rev = .lower then 1 else 0) + (if fight = .lower then 1 else 0) + (if stillLifted then 1 else 0)
  let worse := (if rev = .higher then 1 else 0) + (if fight = .higher then 1 else 0) + (if stillWorse then 1 else 0)
  if better = 0 then .noWin else if worse = 0 then .win else .trade

def perStretch (counts : List Nat) : List (Nat × Nat) := counts.map fun c => (c, 1)

abbrev JobStill := List (Nat × Nat) × List (Nat × Nat)

def JobStill.both (j : JobStill) : Bool := !(rates j.1).isEmpty && !(rates j.2).isEmpty

def stillWorseOf (jobs : List JobStill) : Bool :=
  let ok := jobs.filter JobStill.both
  !ok.isEmpty && ok.all fun j => cmp (rates j.1) (rates j.2) == .higher

def verdictOf (faithRev candRev faithFight candFight : List (Nat × Nat)) (stillJobs : List JobStill) (stillLifted : Bool) : Brick :=
  brickVerdict (cmp (rates faithRev) (rates candRev)) (cmp (rates faithFight) (rates candFight)) stillLifted (stillWorseOf stillJobs)

theorem perThousand_zero (count : Nat) : perThousand count 0 = Option.none := rfl

theorem perThousand_pos (count opens : Nat) (h : opens ≠ 0) : perThousand count opens = some (count * 1000 / opens) := by
  simp [perThousand, h]

theorem rates_length_le (ps : List (Nat × Nat)) : (rates ps).length ≤ ps.length := List.length_filterMap_le _ _

theorem brickVerdict_noWin (rev fight : Cmp) (stillLifted stillWorse : Bool) (h1 : rev ≠ .lower) (h2 : fight ≠ .lower)
    (h3 : stillLifted = false) : brickVerdict rev fight stillLifted stillWorse = .noWin := by
  simp [brickVerdict, h1, h2, h3]

theorem brickVerdict_win (rev fight : Cmp) (stillLifted stillWorse : Bool) (hb : rev = .lower ∨ fight = .lower ∨ stillLifted = true)
    (h1 : rev ≠ .higher) (h2 : fight ≠ .higher) (h3 : stillWorse = false) : brickVerdict rev fight stillLifted stillWorse = .win := by
  unfold brickVerdict
  rcases hb with h | h | h <;> cases rev <;> cases fight <;> cases stillLifted <;> cases stillWorse <;> simp_all <;> contradiction

theorem brickVerdict_trade_rev (rev fight : Cmp) (stillLifted stillWorse : Bool)
    (hb : rev = .lower ∨ fight = .lower ∨ stillLifted = true) (hw : rev = .higher) :
    brickVerdict rev fight stillLifted stillWorse = .trade := by
  unfold brickVerdict
  rcases hb with h | h | h <;> cases rev <;> cases fight <;> cases stillLifted <;> cases stillWorse <;> simp_all <;> contradiction

theorem brickVerdict_trade_fight (rev fight : Cmp) (stillLifted stillWorse : Bool)
    (hb : rev = .lower ∨ fight = .lower ∨ stillLifted = true) (hw : fight = .higher) :
    brickVerdict rev fight stillLifted stillWorse = .trade := by
  unfold brickVerdict
  rcases hb with h | h | h <;> cases rev <;> cases fight <;> cases stillLifted <;> cases stillWorse <;> simp_all <;> contradiction

theorem brickVerdict_trade_still (rev fight : Cmp) (stillLifted stillWorse : Bool)
    (hb : rev = .lower ∨ fight = .lower ∨ stillLifted = true) (hw : stillWorse = true) :
    brickVerdict rev fight stillLifted stillWorse = .trade := by
  unfold brickVerdict
  rcases hb with h | h | h <;> cases rev <;> cases fight <;> cases stillLifted <;> cases stillWorse <;> simp_all <;> contradiction

theorem brickVerdict_trade (rev fight : Cmp) (stillLifted stillWorse : Bool)
    (hb : rev = .lower ∨ fight = .lower ∨ stillLifted = true) (hw : rev = .higher ∨ fight = .higher ∨ stillWorse = true) :
    brickVerdict rev fight stillLifted stillWorse = .trade := by
  rcases hw with h | h | h
  · exact brickVerdict_trade_rev _ _ _ _ hb h
  · exact brickVerdict_trade_fight _ _ _ _ hb h
  · exact brickVerdict_trade_still _ _ _ _ hb h

theorem brickVerdict_win_iff (rev fight : Cmp) (stillLifted stillWorse : Bool) :
    brickVerdict rev fight stillLifted stillWorse = .win ↔
      (rev = .lower ∨ fight = .lower ∨ stillLifted = true) ∧ rev ≠ .higher ∧ fight ≠ .higher ∧ stillWorse = false := by
  unfold brickVerdict
  cases rev <;> cases fight <;> cases stillLifted <;> cases stillWorse <;> simp

theorem stillWorseOf_iff (jobs : List JobStill) : stillWorseOf jobs = true ↔
    (∃ j ∈ jobs, j.both = true) ∧ ∀ j ∈ jobs, j.both = true → cmp (rates j.1) (rates j.2) = .higher := by
  unfold stillWorseOf
  have key : ∀ c : Cmp, (c == .higher) = true ↔ c = .higher := by intro c; cases c <;> decide
  simp only [Bool.and_eq_true, Bool.not_eq_true', List.all_eq_true, List.mem_filter, key]
  constructor
  · rintro ⟨h1, h2⟩
    refine ⟨?_, fun j hj hb => h2 j ⟨hj, hb⟩⟩
    cases hl : jobs.filter JobStill.both with
    | nil => simp [hl] at h1
    | cons x t => exact ⟨x, (List.mem_filter.mp (hl ▸ List.mem_cons_self)).1, (List.mem_filter.mp (hl ▸ List.mem_cons_self)).2⟩
  · rintro ⟨⟨j, hj, hb⟩, h⟩
    refine ⟨?_, fun k hk => h k hk.1 hk.2⟩
    have : j ∈ jobs.filter JobStill.both := List.mem_filter.mpr ⟨hj, hb⟩
    cases hl : jobs.filter JobStill.both with
    | nil => rw [hl] at this; simp at this
    | cons x t => rfl

theorem verdictOf_still_worse (fr cr ff cf : List (Nat × Nat)) (jobs : List JobStill) (stillLifted : Bool)
    (h : stillWorseOf jobs = true)
    (hb : cmp (rates fr) (rates cr) = .lower ∨ cmp (rates ff) (rates cf) = .lower ∨ stillLifted = true) :
    verdictOf fr cr ff cf jobs stillLifted = .trade := by
  unfold verdictOf
  exact brickVerdict_trade_still _ _ _ _ hb h

theorem rates_perStretch (counts : List Nat) : rates (perStretch counts) = counts.map (· * 1000) := by
  unfold rates perStretch
  induction counts with
  | nil => rfl
  | cons c t ih =>
    simp only [List.map_cons, List.filterMap_cons]
    simp [perThousand] at *
    exact ih

theorem foldl_min_le (l : List Nat) : ∀ m : Nat, l.foldl min m ≤ m := by
  induction l with
  | nil => intro m; exact Nat.le_refl m
  | cons a t ih => intro m; exact Nat.le_trans (ih (min m a)) (Nat.min_le_left m a)

theorem verdictOf_self (rev fight : List (Nat × Nat)) (jobs : List JobStill) : verdictOf rev rev fight fight jobs false = .noWin := by
  unfold verdictOf
  have h : ∀ l : List Nat, cmp l l ≠ .lower := by
    intro l
    have hle : Fw.Measure.TouchLock.minOf l ≤ Fw.Measure.TouchLock.maxOf l := foldl_min_le l _
    have hn : ¬ Fw.Measure.TouchLock.maxOf l < Fw.Measure.TouchLock.minOf l := by omega
    unfold cmp
    simp [hn]
  exact brickVerdict_noWin _ _ _ _ (h _) (h _) rfl

#guard verdictOf (perStretch [0, 0, 0, 1, 1, 1, 3, 3, 4, 4, 5, 5, 5]) (perStretch [1, 1, 1, 1, 1, 1, 1])
  (perStretch [0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3]) (perStretch [0, 0, 0, 0, 0, 0, 0]) [] false == Brick.noWin
#guard verdictOf [(12, 4), (10, 4)] [(2, 4), (3, 4)] [(8, 4), (9, 4)] [(1, 4), (2, 4)] [([(25, 1000)], [(34, 1000)]), ([(28, 1000)], [(41, 1000)])] false
  == Brick.trade
#guard cmp (rates [(20, 1000), (40, 1000)]) (rates [(30, 1000), (50, 1000)]) == Cmp.overlap
  && stillWorseOf [([(20, 1000)], [(30, 1000)]), ([(40, 1000)], [(50, 1000)])]

private def intsJ (l : List Int) : Json := Json.arr (l.map toJson).toArray

private def dirJ (b : ByDir) : Json := Json.mkObj [("up", b.up), ("down", b.down), ("none", b.none)]

private def eventJ (e : Event) : Json :=
  Json.mkObj [("kind", e.kind.name), ("frame", e.frame), ("dir", e.dir.name)]

private def writeJ (w : Write) : Json := Json.arr #[toJson w.top, toJson (if w.isOpen then 1 else 0), toJson w.frame]

private def countsJ (c : Counts) : Json :=
  Json.mkObj [("opens", c.opens), ("closes", dirJ c.closes), ("reopens", dirJ c.reopens), ("springBack", dirJ c.springBack)]

private def lcg (s : Nat) : Nat := (s * 1103515245 + 12345) % 2147483648

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

private def sameStill : List JobStill := [([(5, 100), (6, 100)], [(5, 100), (6, 100)])]

private def liftedStill : List JobStill := [([(5, 100), (6, 100)], [(1, 100), (2, 100)])]

private def worseStill : List JobStill := [([(25, 1000)], [(34, 1000)]), ([(28, 1000)], [(41, 1000)])]

private def verdictCases (_ : Unit) :
    List (String × List (Nat × Nat) × List (Nat × Nat) × List (Nat × Nat) × List (Nat × Nat) × List JobStill × Bool) :=
  [("fewer reversals, fights equal", [(12, 4), (10, 4), (14, 4)], [(2, 4), (3, 4), (4, 4)], [(6, 4), (7, 4)], [(6, 4), (7, 4)], sameStill, false),
   ("fewer fights", [(12, 4), (10, 4)], [(11, 4), (10, 4)], [(8, 4), (9, 4)], [(1, 4), (2, 4)], sameStill, false),
   ("lower reversals, higher fights", [(12, 4), (10, 4)], [(2, 4), (3, 4)], [(1, 4), (2, 4)], [(8, 4), (9, 4)], sameStill, false),
   ("still lifted only", [(12, 4), (10, 4)], [(11, 4), (12, 4)], [(8, 4), (9, 4)], [(8, 4), (9, 4)], liftedStill, true),
   ("still lifted, fights higher", [(12, 4), (10, 4)], [(11, 4), (12, 4)], [(1, 4), (2, 4)], [(8, 4), (9, 4)], liftedStill, true),
   ("everything higher", [(2, 4), (3, 4)], [(12, 4), (10, 4)], [(1, 4), (2, 4)], [(8, 4), (9, 4)], sameStill, false),
   ("overlap", [(12, 4), (3, 4)], [(8, 4), (9, 4)], [(8, 4), (9, 4)], [(8, 4), (3, 4)], sameStill, false),
   ("no faithful pass", [], [(2, 4)], [], [(1, 4)], [([], [(1, 100)])], false),
   ("no open starts", [(12, 0)], [(2, 0)], [(1, 0)], [(2, 0)], [([(5, 0)], [(2, 0)])], false),
   ("different open starts per pass", [(10, 2), (30, 6)], [(2, 4), (1, 3)], [(4, 2), (12, 6)], [(1, 4), (1, 3)], sameStill, false),
   ("fewer reversals and fights, still runs worse in every job", [(12, 4), (10, 4)], [(2, 4), (3, 4)], [(8, 4), (9, 4)], [(1, 4), (2, 4)],
    worseStill, false),
   ("still runs worse only", [(12, 4), (10, 4)], [(11, 4), (12, 4)], [(8, 4), (9, 4)], [(8, 4), (9, 4)], worseStill, false),
   ("still runs worse in one job, better in the other", [(12, 4), (10, 4)], [(2, 4), (3, 4)], [(8, 4), (9, 4)], [(1, 4), (2, 4)],
    [([(25, 1000)], [(34, 1000)]), ([(28, 1000)], [(24, 1000)])], false),
   ("still runs overlap inside a job", [(12, 4), (10, 4)], [(2, 4), (3, 4)], [(8, 4), (9, 4)], [(1, 4), (2, 4)],
    [([(25, 1000), (35, 1000)], [(30, 1000)])], false),
   ("still runs worse job by job, overlapping pooled", [(12, 4), (10, 4)], [(2, 4), (3, 4)], [(8, 4), (9, 4)], [(1, 4), (2, 4)],
    [([(20, 1000)], [(30, 1000)]), ([(40, 1000)], [(50, 1000)])], false),
   ("a job with no faithful pass is left out of the still runs", [(12, 4), (10, 4)], [(2, 4), (3, 4)], [(8, 4), (9, 4)], [(1, 4), (2, 4)],
    [([], [(60, 1000)]), ([(25, 1000)], [(34, 1000)])], false),
   ("no job to compare the still runs in", [(12, 4), (10, 4)], [(2, 4), (3, 4)], [(8, 4), (9, 4)], [(1, 4), (2, 4)], [([], [(60, 1000)])], false),
   ("still runs counted per frame of each pass", [(12, 4)], [(2, 4)], [(8, 4)], [(1, 4)], [([(30, 1000)], [(20, 300)])], false),
   ("first stretches, one open start each, release against faithful",
    perStretch [0, 0, 0, 1, 1, 1, 3, 3, 4, 4, 5, 5, 5], perStretch [1, 1, 1, 1, 1, 1, 1],
    perStretch [0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 3, 3], perStretch [0, 0, 0, 0, 0, 0, 0], sameStill, false),
   ("first stretches, release against a faithful page that reverses more", perStretch [3, 4, 5, 3], perStretch [1, 1, 1],
    perStretch [2, 2, 3, 2], perStretch [0, 0, 0], worseStill, false)]

def stepFramesFrom (prev : Int) (i : Nat) : List Int → List Nat
  | [] => []
  | x :: xs => (if x ≠ prev then [i] else []) ++ stepFramesFrom x (i + 1) xs

def stepFrames : List Int → List Nat
  | [] => []
  | x :: xs => stepFramesFrom x 1 xs

def consecutive : List Nat → List (Nat × Nat)
  | a :: b :: rest => (a, b) :: consecutive (b :: rest)
  | _ => []

def burstMaxCs : Nat := 50000

def throttleCs : Nat := 10000

def stepGaps (t : List Int) (fs : List Nat) : List Nat :=
  (consecutive fs).filterMap fun p =>
    match t[p.1]?, t[p.2]? with
    | some x, some y => if 0 < y - x ∧ y - x ≤ (burstMaxCs : Int) then some (y - x).toNat else Option.none
    | _, _ => Option.none

def insertSorted (a : Nat) : List Nat → List Nat
  | [] => [a]
  | b :: t => if a ≤ b then a :: b :: t else b :: insertSorted a t

def sortNat : List Nat → List Nat
  | [] => []
  | a :: t => insertSorted a (sortNat t)

def medianCs (l : List Nat) : Nat := (sortNat l).getD (l.length / 2) 0

def frameGapCs (t : List Int) : Nat :=
  medianCs ((t.zip t.tail).filterMap fun p => if 0 < p.2 - p.1 then some (p.2 - p.1).toNat else Option.none)

def stepsLifted (frameCs : Nat) (gaps : List Nat) : Bool := !gaps.isEmpty && decide (2 * medianCs gaps < frameCs + throttleCs)

theorem stepFramesFrom_const (v : Int) (n i : Nat) : stepFramesFrom v i (List.replicate n v) = [] := by
  induction n generalizing i with
  | zero => rfl
  | succ n ih => simp [List.replicate_succ, stepFramesFrom, ih]

theorem stepFramesFrom_range (prev : Int) (l : List Int) : ∀ i f, f ∈ stepFramesFrom prev i l → i ≤ f ∧ f < i + l.length := by
  induction l generalizing prev with
  | nil => intro i f h; simp [stepFramesFrom] at h
  | cons x xs ih =>
    intro i f h
    simp only [stepFramesFrom, List.mem_append] at h
    rcases h with h | h
    · split at h <;> simp_all <;> omega
    · have := ih x (i + 1) f h
      simp only [List.length_cons]
      omega

theorem stepGaps_le (t : List Int) (fs : List Nat) : ∀ g ∈ stepGaps t fs, g ≤ burstMaxCs := by
  intro g hg
  unfold stepGaps at hg
  rw [List.mem_filterMap] at hg
  obtain ⟨p, _, hp⟩ := hg
  revert hp
  cases t[p.1]? <;> cases t[p.2]? <;> simp
  rename_i x y
  intro h1 h2 h3
  omega

theorem stepsLifted_empty (frameCs : Nat) : stepsLifted frameCs [] = false := rfl

theorem stepsLifted_iff (frameCs : Nat) (gaps : List Nat) :
    stepsLifted frameCs gaps = true ↔ gaps ≠ [] ∧ 2 * medianCs gaps < frameCs + throttleCs := by
  unfold stepsLifted
  cases gaps <;> simp

theorem stepsLifted_per_frame : stepsLifted 1667 [1667, 1667, 1666] = true := by decide

theorem stepsLifted_slow_frames : stepsLifted 5000 [5000, 5000, 6000] = true := by decide

theorem stepsLifted_throttled : stepsLifted 1667 [10000, 10000, 9900] = false := by decide

theorem stepsLifted_not_at_throttle (frameCs : Nat) (gaps : List Nat) (hf : frameCs ≤ throttleCs) (hm : throttleCs ≤ medianCs gaps) :
    stepsLifted frameCs gaps = false := by
  unfold stepsLifted
  simp only [Bool.and_eq_false_iff, decide_eq_false_iff_not]
  right
  omega

def gestureOf (g : List Int) (i : Nat) : Int := g.getD i 0

def gestureCount (g : List Int) : Nat := (g.foldl max 0).toNat

def inGesture (g : List Int) (frames : List Nat) (k : Nat) : Nat := (frames.filter fun i => gestureOf g i = (k : Int)).length

def perGesture (g : List Int) (frames : List Nat) : List Nat := (List.range (gestureCount g)).map fun k => inGesture g frames (k + 1)

theorem perGesture_length (g : List Int) (frames : List Nat) : (perGesture g frames).length = gestureCount g := by
  simp [perGesture]

theorem inGesture_le (g : List Int) (frames : List Nat) (k : Nat) : inGesture g frames k ≤ frames.length := List.length_filter_le _ _

theorem perGesture_nil (g : List Int) : perGesture g [] = List.replicate (gestureCount g) 0 := by
  simp [perGesture, inGesture, List.map_const']

def onsetsFrom (prev : Int) (i : Nat) : List Int → List Nat
  | [] => []
  | x :: xs => (if 0 < x ∧ prev = 0 then [i] else []) ++ onsetsFrom x (i + 1) xs

def onsetFrames (r : List Int) : List Nat := onsetsFrom 0 0 r

theorem onsetsFrom_length (l : List Int) : ∀ prev i, (onsetsFrom prev i l).length = risesFrom prev l := by
  induction l with
  | nil => intro prev i; rfl
  | cons x xs ih =>
    intro prev i
    simp only [onsetsFrom, risesFrom, List.length_append, ih]
    split <;> simp

theorem onsetFrames_length (r : List Int) : (onsetFrames r).length = opens r := onsetsFrom_length r 0 0

def refreshHz (gapCs : Nat) : Nat := if gapCs = 0 then 0 else (200000 / gapCs + 1) / 2

def foldOf (hz : Nat) : Nat := hz / 10

theorem refreshHz_60 : refreshHz 1667 = 60 := by decide

theorem refreshHz_120 : refreshHz 833 = 120 := by decide

theorem fold_60 : foldOf 60 = 6 := rfl

theorem fold_120 : foldOf 120 = 12 := rfl

structure TbPass where
  gestures : Nat
  reversals : Nat
  swaps : Nat
  onsets : Nat
  onsetGestures : Nat
  gaps : List Nat
  peak : Nat
  settled : Bool
  layout : Nat
  recalc : Nat
  frames : Nat
  frameCs : Nat
  deriving DecidableEq, Repr

def tbPass (t vh r d g : List Int) (reversals layout recalc frames : Nat) : TbPass :=
  ⟨gestureCount g, reversals, (events r d).length, opens r,
   ((perGesture g (onsetFrames r)).filter (0 < ·)).length, stepGaps t (stepFrames vh),
   (r.foldl max 0).toNat, decide (r.getLast?.getD 0 = 0), layout, recalc, frames, frameGapCs t⟩

def cmpBy (num den : TbPass → Nat) (base cand : List TbPass) : Cmp :=
  cmp (rates (base.map fun p => (num p, den p))) (rates (cand.map fun p => (num p, den p)))

def floorHolds (base cand : List Nat) : Bool :=
  !base.isEmpty && !cand.isEmpty && decide (Fw.Measure.TouchLock.minOf base ≤ Fw.Measure.TouchLock.minOf cand)

def sameLook (base cand : List TbPass) : Bool :=
  floorHolds (base.map (·.peak)) (cand.map (·.peak))
  && floorHolds (rates (base.map fun p => (p.onsetGestures, p.gestures))) (rates (cand.map fun p => (p.onsetGestures, p.gestures)))
  && (!base.all (·.settled) || cand.all (·.settled))

def betterN (rev reopen onset : Cmp) (lifted : Bool) : Nat :=
  (if rev = .lower then 1 else 0) + (if reopen = .lower then 1 else 0) + (if onset = .lower then 1 else 0) + (if lifted then 1 else 0)

def worseN (rev reopen onset layout recalc : Cmp) (look : Bool) : Nat :=
  (if rev = .higher then 1 else 0) + (if reopen = .higher then 1 else 0) + (if onset = .higher then 1 else 0)
  + (if layout = .higher then 1 else 0) + (if recalc = .higher then 1 else 0) + (if look then 0 else 1)

def armVerdict (rev reopen onset layout recalc : Cmp) (lifted look : Bool) : Brick :=
  if betterN rev reopen onset lifted = 0 then .noWin
  else if worseN rev reopen onset layout recalc look = 0 then .win else .trade

theorem armVerdict_noWin (rev reopen onset layout recalc : Cmp) (lifted look : Bool)
    (h1 : rev ≠ .lower) (h2 : reopen ≠ .lower) (h3 : onset ≠ .lower) (h4 : lifted = false) :
    armVerdict rev reopen onset layout recalc lifted look = .noWin := by
  simp [armVerdict, betterN, h1, h2, h3, h4]

theorem armVerdict_win (rev reopen onset layout recalc : Cmp) (lifted look : Bool)
    (hb : rev = .lower ∨ reopen = .lower ∨ onset = .lower ∨ lifted = true)
    (h1 : rev ≠ .higher) (h2 : reopen ≠ .higher) (h3 : onset ≠ .higher) (h4 : layout ≠ .higher) (h5 : recalc ≠ .higher)
    (h6 : look = true) : armVerdict rev reopen onset layout recalc lifted look = .win := by
  have hp : betterN rev reopen onset lifted ≠ 0 := by
    rcases hb with h | h | h | h <;> simp [betterN, h] <;> omega
  simp [armVerdict, hp, worseN, h1, h2, h3, h4, h5, h6]

theorem armVerdict_trade_rev (rev reopen onset layout recalc : Cmp) (lifted look : Bool)
    (hb : rev = .lower ∨ reopen = .lower ∨ onset = .lower ∨ lifted = true) (hw : rev = .higher ∨ reopen = .higher ∨ onset = .higher ∨ layout = .higher ∨ recalc = .higher ∨ look = false) :
    armVerdict rev reopen onset layout recalc lifted look = .trade := by
  have hp : betterN rev reopen onset lifted ≠ 0 := by
    rcases hb with h | h | h | h <;> simp [betterN, h] <;> omega
  have hq : worseN rev reopen onset layout recalc look ≠ 0 := by
    rcases hw with h | h | h | h | h | h <;> simp [worseN, h] <;> omega
  simp [armVerdict, hp, hq]

theorem unthrottle_costly_is_trade :
    armVerdict .overlap .overlap .overlap .higher .higher true true = .trade := by decide

theorem lifted_alone_wins : armVerdict .overlap .overlap .overlap .overlap .overlap true true = .win := by decide

theorem broken_look_is_not_a_win : armVerdict .lower .lower .lower .overlap .overlap false false = .trade := by decide

theorem floorHolds_below (base cand : List Nat) (h : floorHolds base cand = true) :
    Fw.Measure.TouchLock.minOf base ≤ Fw.Measure.TouchLock.minOf cand := by
  simp [floorHolds] at h
  exact h.2

theorem sameLook_peak (base cand : List TbPass) (h : floorHolds (base.map (·.peak)) (cand.map (·.peak)) = false) :
    sameLook base cand = false := by
  simp [sameLook, h]

theorem sameLook_onsets (base cand : List TbPass)
    (h : floorHolds (rates (base.map fun p => (p.onsetGestures, p.gestures))) (rates (cand.map fun p => (p.onsetGestures, p.gestures))) = false) :
    sameLook base cand = false := by
  simp [sameLook, h]

theorem sameLook_unsettled (base cand : List TbPass) (hb : base.all (·.settled) = true) (hc : cand.all (·.settled) = false) :
    sameLook base cand = false := by
  simp [sameLook, hb, hc]

theorem sameLook_empty_cand (base : List TbPass) : sameLook base [] = false := by
  simp [sameLook, floorHolds]

def liftedBy (base cand : List TbPass) : Bool :=
  stepsLifted (medianCs (cand.map (·.frameCs))) (cand.flatMap (·.gaps)) && !stepsLifted (medianCs (base.map (·.frameCs))) (base.flatMap (·.gaps))

def minCostWindows : Nat := 3

def costWindows (num : TbPass → Nat) (ps : List TbPass) : Nat := (rates (ps.map fun p => (num p, p.frames))).length

def costKnown (base cand : List TbPass) : Bool :=
  decide (minCostWindows ≤ costWindows (·.layout) base) && decide (minCostWindows ≤ costWindows (·.layout) cand)
  && decide (minCostWindows ≤ costWindows (·.recalc) base) && decide (minCostWindows ≤ costWindows (·.recalc) cand)

def costCmp (known : Bool) (c : Cmp) : Cmp := if known then c else .overlap

def flagVerdict (base cand : List TbPass) : Brick :=
  let known := costKnown base cand
  let v := armVerdict (cmpBy (·.reversals) (·.gestures) base cand) (cmpBy (·.swaps) (·.gestures) base cand)
    (cmpBy (·.onsets) (·.gestures) base cand) (costCmp known (cmpBy (·.layout) (·.frames) base cand))
    (costCmp known (cmpBy (·.recalc) (·.frames) base cand)) (liftedBy base cand) (sameLook base cand)
  if !known && v == .win then .undecided else v

theorem cmpBy_empty_cand (num den : TbPass → Nat) (base : List TbPass) : cmpBy num den base [] = .overlap := by
  simp [cmpBy, Fw.Measure.TouchLock.cmp_empty_cand, rates]

theorem costCmp_overlap (known : Bool) : costCmp known .overlap = .overlap := by
  cases known <;> rfl

theorem flagVerdict_empty_cand (base : List TbPass) : flagVerdict base [] = .noWin := by
  have h : armVerdict (cmpBy (·.reversals) (·.gestures) base []) (cmpBy (·.swaps) (·.gestures) base [])
      (cmpBy (·.onsets) (·.gestures) base []) (costCmp (costKnown base []) (cmpBy (·.layout) (·.frames) base []))
      (costCmp (costKnown base []) (cmpBy (·.recalc) (·.frames) base [])) (liftedBy base []) (sameLook base []) = .noWin := by
    apply armVerdict_noWin <;> simp [cmpBy_empty_cand, liftedBy, stepsLifted_empty]
  unfold flagVerdict
  simp only [h]
  simp

theorem flagVerdict_cost_known (base cand : List TbPass) (h : costKnown base cand = true) :
    flagVerdict base cand =
      armVerdict (cmpBy (·.reversals) (·.gestures) base cand) (cmpBy (·.swaps) (·.gestures) base cand)
        (cmpBy (·.onsets) (·.gestures) base cand) (cmpBy (·.layout) (·.frames) base cand)
        (cmpBy (·.recalc) (·.frames) base cand) (liftedBy base cand) (sameLook base cand) := by
  simp [flagVerdict, costCmp, h]

theorem flagVerdict_cost_unknown_not_win (base cand : List TbPass) (h : costKnown base cand = false) :
    flagVerdict base cand ≠ .win := by
  unfold flagVerdict
  simp only [h, Bool.not_false, Bool.true_and]
  split <;> simp_all

theorem flagVerdict_undecided (base cand : List TbPass) (h : costKnown base cand = false)
    (hv : armVerdict (cmpBy (·.reversals) (·.gestures) base cand) (cmpBy (·.swaps) (·.gestures) base cand)
        (cmpBy (·.onsets) (·.gestures) base cand) .overlap .overlap (liftedBy base cand) (sameLook base cand) = .win) :
    flagVerdict base cand = .undecided := by
  simp [flagVerdict, costCmp, h, hv]

theorem flagVerdict_unknown_keeps_loss (base cand : List TbPass) (h : costKnown base cand = false)
    (hv : armVerdict (cmpBy (·.reversals) (·.gestures) base cand) (cmpBy (·.swaps) (·.gestures) base cand)
        (cmpBy (·.onsets) (·.gestures) base cand) .overlap .overlap (liftedBy base cand) (sameLook base cand) ≠ .win) :
    flagVerdict base cand = armVerdict (cmpBy (·.reversals) (·.gestures) base cand) (cmpBy (·.swaps) (·.gestures) base cand)
        (cmpBy (·.onsets) (·.gestures) base cand) .overlap .overlap (liftedBy base cand) (sameLook base cand) := by
  simp [flagVerdict, costCmp, h, hv]

theorem costKnown_empty_base_layout (base cand : List TbPass) (h : rates (base.map fun p => (p.layout, p.frames)) = []) :
    costKnown base cand = false := by
  simp [costKnown, costWindows, h, minCostWindows]

theorem costKnown_empty_base_recalc (base cand : List TbPass) (h : rates (base.map fun p => (p.recalc, p.frames)) = []) :
    costKnown base cand = false := by
  simp [costKnown, costWindows, h, minCostWindows]

theorem costKnown_short_base (base cand : List TbPass) (h : costWindows (·.layout) base < minCostWindows) :
    costKnown base cand = false := by
  have : ¬ minCostWindows ≤ costWindows (·.layout) base := by omega
  simp [costKnown, this]

theorem costKnown_short_cand (base cand : List TbPass) (h : costWindows (·.layout) cand < minCostWindows) :
    costKnown base cand = false := by
  have : ¬ minCostWindows ≤ costWindows (·.layout) cand := by omega
  simp [costKnown, this]

theorem costKnown_short_base_recalc (base cand : List TbPass) (h : costWindows (·.recalc) base < minCostWindows) :
    costKnown base cand = false := by
  have : ¬ minCostWindows ≤ costWindows (·.recalc) base := by omega
  simp [costKnown, this]

theorem costKnown_short_cand_recalc (base cand : List TbPass) (h : costWindows (·.recalc) cand < minCostWindows) :
    costKnown base cand = false := by
  have : ¬ minCostWindows ≤ costWindows (·.recalc) cand := by omega
  simp [costKnown, this]

theorem unthrottle_no_cost_undecided (base cand : List TbPass) (h : rates (base.map fun p => (p.layout, p.frames)) = []) :
    flagVerdict base cand ≠ .win :=
  flagVerdict_cost_unknown_not_win base cand (costKnown_empty_base_layout base cand h)

def enters (lookChange : Bool) (v : Brick) : Bool := !lookChange && v == .win

theorem look_class_never_enters (v : Brick) : enters true v = false := by simp [enters]

theorem plain_win_enters : enters false .win = true := rfl

theorem undecided_never_enters (lookChange : Bool) : enters lookChange .undecided = false := by simp [enters]

theorem plain_trade_stays_out : enters false .trade = false := rfl

inductive Win where
  | wait | record | done
  deriving DecidableEq, Repr

def Win.name : Win → String
  | .wait => "wait"
  | .record => "record"
  | .done => "done"

def winLead : Nat := 2

def winStart : Nat := 4

def winCapMs : Nat := 150000

def winPhase (g : Nat) : Option Nat → Win
  | none => if g < winLead then .wait else if g < winStart then .record else .done
  | some ms => if winStart < g ∨ winCapMs ≤ ms then .done else .record

theorem win_waits_before_lead (g : Nat) (h : g < winLead) : winPhase g none = .wait := by
  simp [winPhase, h]

theorem win_opens_in_lead (g : Nat) (h1 : winLead ≤ g) (h2 : g < winStart) : winPhase g none = .record := by
  have : ¬ g < winLead := by omega
  simp [winPhase, this, h2]

theorem win_missed (g : Nat) (h : winStart ≤ g) : winPhase g none = .done := by
  have : ¬ g < winLead := by simp [winLead, winStart] at *; omega
  have : ¬ g < winStart := by omega
  simp [winPhase, *]

theorem win_next_gesture_ends (ms : Nat) (g : Nat) (h : winStart < g) : winPhase g (some ms) = .done := by
  simp [winPhase, h]

theorem win_cap_ends (g : Nat) : winPhase g (some winCapMs) = .done := by
  simp [winPhase]

theorem win_record_bounded (g ms : Nat) (h : winPhase g (some ms) = .record) : ms < winCapMs := by
  simp only [winPhase] at h
  split at h <;> simp_all

inductive RowKind where
  | layout | recalc | frame | mark (g : Nat) | other
  deriving DecidableEq, Repr

structure Row where
  kind : RowKind
  time : Int
  deriving DecidableEq, Repr

def markAt (g : Nat) (rows : List Row) : Option Int := (rows.find? fun r => decide (r.kind = .mark g)).map (·.time)

def countIn (k : RowKind) (a b : Int) (rows : List Row) : Nat := (rows.filter fun r => decide (r.kind = k ∧ a ≤ r.time ∧ r.time < b)).length

def windowCost (g : Nat) (rows : List Row) : Option (Nat × Nat × Nat) :=
  match markAt g rows, markAt (g + 1) rows with
  | some a, some b => if a < b then some (countIn .layout a b rows, countIn .recalc a b rows, countIn .frame a b rows) else Option.none
  | _, _ => Option.none

theorem windowCost_no_start_mark (g : Nat) (rows : List Row) (h : markAt g rows = Option.none) : windowCost g rows = Option.none := by
  simp [windowCost, h]

theorem windowCost_no_end_mark (g : Nat) (rows : List Row) (h : markAt (g + 1) rows = Option.none) : windowCost g rows = Option.none := by
  simp [windowCost, h]

theorem windowCost_empty (g : Nat) : windowCost g [] = Option.none := rfl

theorem windowCost_whole : windowCost 4
    [⟨.mark 4, 0⟩, ⟨.layout, 1⟩, ⟨.frame, 1⟩, ⟨.recalc, 2⟩, ⟨.frame, 3⟩, ⟨.layout, 4⟩, ⟨.mark 5, 5⟩, ⟨.layout, 6⟩] = some (2, 1, 2) := by decide

theorem windowCost_ignores_outside : windowCost 4
    [⟨.layout, 0⟩, ⟨.mark 4, 10⟩, ⟨.layout, 11⟩, ⟨.mark 5, 20⟩, ⟨.layout, 21⟩, ⟨.mark 6, 30⟩] = some (1, 0, 0) := by decide

private def tbIntsJ (l : List Int) : Json := Json.arr (l.map toJson).toArray

private def tbNatsJ (l : List Nat) : Json := Json.arr (l.map toJson).toArray

def tbPassJ (p : TbPass) : Json :=
  Json.mkObj [("gestures", p.gestures), ("reversals", p.reversals), ("swaps", p.swaps), ("onsets", p.onsets),
    ("onsetGestures", p.onsetGestures), ("gaps", tbNatsJ p.gaps), ("peak", p.peak), ("settled", p.settled),
    ("layout", p.layout), ("recalc", p.recalc), ("frames", p.frames), ("frameCs", p.frameCs)]

private def evenly (n period : Nat) : List Int := (List.range n).map fun i => ((i * period : Nat) : Int)

private def stepped (n every : Nat) : List Int := (List.range n).map fun i => ((7750 + (i / every) * 10 : Nat) : Int)

private def gesturesOf (n per : Nat) : List Int := (List.range n).map fun i => ((i / per + 1 : Nat) : Int)

private def holdGap (n period hold : Nat) : List Int :=
  (List.range n).map fun i => ((i * period + (if i < n / 2 then 0 else hold) : Nat) : Int)

private def tbStepCases (_ : Unit) : List (String × List Int × List Int) :=
  [("empty", [], []), ("one frame", [0], [7750]), ("flat", evenly 20 1667, List.replicate 20 7750),
   ("throttled, a step every 6 frames at 60 Hz", evenly 60 1667, stepped 60 6),
   ("unthrottled, a step every frame at 60 Hz", evenly 60 1667, stepped 60 1),
   ("unthrottled at 120 Hz", evenly 120 833, stepped 120 1),
   ("unthrottled at 20 Hz, frames 50 ms apart", evenly 60 5000, stepped 60 1),
   ("throttled at 20 Hz, a step every 2 frames", evenly 60 5000, stepped 60 2),
   ("lifted at 40 Hz, a step every 2 frames", evenly 60 2500, stepped 60 2),
   ("a long hold between two bursts is no step gap", holdGap 60 1667 70000, stepped 60 6),
   ("vh shorter than t", evenly 10 1667, [7750, 7760, 7760]),
   ("t shorter than vh", evenly 3 1667, stepped 10 1)]

private def tbGestureCases (_ : Unit) : List (String × List Int × List Nat) :=
  [("no touches", List.replicate 6 0, [1, 2, 3]), ("three gestures", gesturesOf 12 4, [0, 5, 6, 11]),
   ("frame past the record", gesturesOf 6 3, [2, 3, 9]), ("no frames", gesturesOf 6 3, []), ("empty record", [], [0, 1])]

private def tbOnsetCases (_ : Unit) : List (List Int) :=
  [[], [0, 0], [500], [0, 400, 800, 0, 0, 300, 0, 100, 100, 0], [1000, 500, 0, 600]]

private def tbRecCases (_ : Unit) : List (String × List Int × List Int × List Int × List Int × List Int × Nat × Nat × Nat × Nat) :=
  [("throttled pass", evenly 60 1667, stepped 60 6,
    [0, 0, 0, 300, 700, 1000, 1000, 600, 100, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 400, 1000, 1000, 500, 800, 1000, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    (List.range 60).map (fun i => if i < 9 then (-1 : Int) else if i < 21 then 1 else -1), gesturesOf 60 20, 2, 11, 13, 61),
   ("unthrottled pass, never opened", evenly 40 1667, stepped 40 1, List.replicate 40 0, List.replicate 40 0, gesturesOf 40 10, 0, 40, 41, 40),
   ("empty pass", [], [], [], [], [], 0, 0, 0, 0)]

private def mkP (gestures reversals swaps onsets og : Nat) (gaps : List Nat) (peak : Nat) (settled : Bool) (layout recalc frames : Nat)
    (frameCs : Nat := 1667) : TbPass :=
  ⟨gestures, reversals, swaps, onsets, og, gaps, peak, settled, layout, recalc, frames, frameCs⟩

private def baseP : List TbPass :=
  [mkP 12 6 4 6 4 [10000, 10100, 9900] 1000 true 60 90 600, mkP 12 5 5 7 4 [10000, 9800] 1000 true 66 96 600,
   mkP 12 7 3 6 4 [10100, 10000] 1000 true 63 93 600]

private def slowP (_ : Nat) : List TbPass :=
  [mkP 12 6 4 6 4 [10000, 10100, 9900] 1000 true 60 90 600 5000, mkP 12 5 5 7 4 [10000, 9800] 1000 true 66 96 600 5000,
   mkP 12 7 3 6 4 [10100, 10000] 1000 true 63 93 600 5000]

private def noCostP : List TbPass :=
  [mkP 12 6 4 6 4 [10000, 10100, 9900] 1000 true 0 0 0, mkP 12 5 5 7 4 [10000, 9800] 1000 true 0 0 0,
   mkP 12 7 3 6 4 [10100, 10000] 1000 true 0 0 0]

private def unP : List TbPass :=
  [mkP 12 6 4 6 4 [1667, 1667, 1700] 1000 true 60 90 600, mkP 12 5 5 7 4 [1667, 1600] 1000 true 66 96 600,
   mkP 12 7 3 6 4 [1700, 1667] 1000 true 63 93 600]

private def unCostlyP : List TbPass :=
  [mkP 12 6 4 6 4 [1667, 1667, 1700] 1000 true 360 540 600, mkP 12 5 5 7 4 [1667, 1600] 1000 true 372 558 600,
   mkP 12 7 3 6 4 [1700, 1667] 1000 true 366 546 600]

private def tbVerdictCases (_ : Unit) : List (String × List TbPass × List TbPass) :=
  [("the same passes", baseP, baseP),
   ("unthrottle: a step every frame, layout and style recalcs per frame higher", baseP,
    [mkP 12 6 4 6 4 [1667, 1667, 1700] 1000 true 360 540 600, mkP 12 5 5 7 4 [1667, 1600] 1000 true 372 558 600,
     mkP 12 7 3 6 4 [1700, 1667] 1000 true 366 546 600]),
   ("open-once: one fade onset per gesture, same look", baseP,
    [mkP 12 6 1 4 4 [10000, 10100] 1000 true 60 90 600, mkP 12 5 1 4 4 [10000, 9800] 1000 true 66 96 600,
     mkP 12 7 0 4 4 [10100, 10000] 1000 true 63 93 600]),
   ("touch-first: fewer re-opens but the first push never opens (fewer gestures with an onset)", baseP,
    [mkP 12 6 0 3 3 [10000, 10100] 1000 true 60 90 600, mkP 12 5 0 3 3 [10000, 9800] 1000 true 66 96 600,
     mkP 12 7 0 3 3 [10100, 10000] 1000 true 63 93 600]),
   ("a candidate that never reaches the full morph", baseP,
    [mkP 12 0 0 1 1 [10000] 400 true 60 90 600, mkP 12 0 0 1 1 [10000] 450 true 66 96 600, mkP 12 0 0 1 1 [10000] 500 true 63 93 600]),
   ("the morph stays open at the end of the pass", baseP,
    [mkP 12 1 1 4 4 [10000] 1000 false 60 90 600, mkP 12 1 1 4 4 [10000] 1000 false 66 96 600, mkP 12 1 1 4 4 [10000] 1000 false 63 93 600]),
   ("unthrottle at 20 Hz frames: a step every frame against every second frame", slowP 2,
    [mkP 12 6 4 6 4 [5000, 5000, 6000] 1000 true 360 540 600 5000, mkP 12 5 5 7 4 [5000, 5500] 1000 true 372 558 600 5000,
     mkP 12 7 3 6 4 [6000, 5000] 1000 true 366 546 600 5000]),
   ("no cost reading (no frames)", baseP, [mkP 12 6 4 6 4 [10000] 1000 true 0 0 0, mkP 12 6 4 6 4 [10000] 1000 true 0 0 0]),
   ("no candidate pass", baseP, []), ("no default pass", [], baseP),
   ("unthrottle, cost known on both sides, nothing higher: a win", baseP, unP),
   ("unthrottle, empty cost base (no default pass holds a cost window): undecided", noCostP, unP),
   ("unthrottle, two cost windows in the default: undecided", baseP.take 2 ++ [mkP 12 6 4 6 4 [10000] 1000 true 0 0 0], unP),
   ("unthrottle, two cost windows in the flag arm: undecided", baseP, unP.take 2 ++ [mkP 12 6 4 6 4 [1667, 1667] 1000 true 0 0 0]),
   ("unthrottle, cost known and higher: trade", baseP, unCostlyP),
   ("unthrottle without cost, broken look: trade", noCostP, unP.map fun p => { p with peak := 400 }),
   ("no cadence lift without cost: no-win", noCostP, noCostP)]

private def tbHzCases (_ : Unit) : List Nat := [0, 833, 1667, 1666, 1700, 1000, 3334]

private def kindJ : RowKind → Json
  | .layout => "layout" | .recalc => "recalc" | .frame => "frame" | .mark g => Json.mkObj [("mark", g)] | .other => "other"

private def rowJ (r : Row) : Json := Json.arr #[kindJ r.kind, toJson r.time]

private def tbCostCases (_ : Unit) : List (String × Nat × List Row) :=
  [("no rows", 4, []), ("whole gesture", 4, [⟨.other, 0⟩, ⟨.mark 4, 10⟩, ⟨.layout, 11⟩, ⟨.frame, 11⟩, ⟨.recalc, 12⟩, ⟨.frame, 13⟩, ⟨.layout, 14⟩, ⟨.mark 5, 20⟩, ⟨.layout, 21⟩]),
   ("recording began inside the gesture", 4, [⟨.layout, 1⟩, ⟨.mark 5, 20⟩]),
   ("stopped before the next gesture", 4, [⟨.mark 4, 10⟩, ⟨.layout, 11⟩]),
   ("marks out of order", 4, [⟨.mark 5, 5⟩, ⟨.mark 4, 10⟩, ⟨.layout, 11⟩]),
   ("a gesture with no cost", 4, [⟨.mark 4, 10⟩, ⟨.mark 5, 20⟩]),
   ("another gesture", 2, [⟨.mark 2, 0⟩, ⟨.recalc, 1⟩, ⟨.recalc, 2⟩, ⟨.mark 3, 3⟩])]

private def tbWinCases (_ : Unit) : List (Nat × Option Nat) :=
  [(0, none), (1, none), (2, none), (3, none), (4, none), (5, none), (9, none), (4, some 0), (4, some 149999), (4, some 150000), (3, some 20000), (5, some 100), (7, some 0)]

def tbGoldenLines (_ : Unit) : List String :=
  ((tbStepCases ()).map fun (name, t, vh) =>
    let fs := stepFrames vh
    let gaps := stepGaps t fs
    (Json.mkObj [("kind", "tb-steps"), ("name", name), ("t", tbIntsJ t), ("vh", tbIntsJ vh), ("frames", tbNatsJ fs), ("gaps", tbNatsJ gaps),
      ("median", medianCs gaps), ("frameCs", frameGapCs t), ("lifted", stepsLifted (frameGapCs t) gaps)]).compress) ++
  ((tbGestureCases ()).map fun (name, g, frames) =>
    (Json.mkObj [("kind", "tb-gestures"), ("name", name), ("g", tbIntsJ g), ("frames", tbNatsJ frames), ("count", gestureCount g),
      ("per", tbNatsJ (perGesture g frames))]).compress) ++
  ((tbOnsetCases ()).map fun r =>
    (Json.mkObj [("kind", "tb-onsets"), ("r", tbIntsJ r), ("frames", tbNatsJ (onsetFrames r)), ("opens", opens r)]).compress) ++
  ((tbRecCases ()).map fun (name, t, vh, r, d, g, rev, lay, rec, fr) =>
    (Json.mkObj [("kind", "tb-pass"), ("name", name), ("t", tbIntsJ t), ("vh", tbIntsJ vh), ("r", tbIntsJ r), ("d", tbIntsJ d), ("g", tbIntsJ g),
      ("reversals", rev), ("layout", lay), ("recalc", rec), ("frames", fr), ("pass", tbPassJ (tbPass t vh r d g rev lay rec fr))]).compress) ++
  ((tbVerdictCases ()).map fun (name, base, cand) =>
    (Json.mkObj [("kind", "tb-verdict"), ("name", name), ("base", Json.arr (base.map tbPassJ).toArray), ("cand", Json.arr (cand.map tbPassJ).toArray),
      ("reversals", (cmpBy (·.reversals) (·.gestures) base cand).name), ("swaps", (cmpBy (·.swaps) (·.gestures) base cand).name),
      ("onsets", (cmpBy (·.onsets) (·.gestures) base cand).name), ("layout", (cmpBy (·.layout) (·.frames) base cand).name),
      ("recalc", (cmpBy (·.recalc) (·.frames) base cand).name), ("lifted", liftedBy base cand), ("look", sameLook base cand), ("costKnown", costKnown base cand),
      ("verdict", (flagVerdict base cand).name), ("entersPlain", enters false (flagVerdict base cand)),
      ("entersLook", enters true (flagVerdict base cand))]).compress) ++
  ((tbHzCases ()).map fun (gap : Nat) => (Json.mkObj [("kind", "tb-hz"), ("gapCs", gap), ("hz", refreshHz gap), ("fold", foldOf (refreshHz gap))]).compress) ++
  ((tbWinCases ()).map fun (g, ms) =>
    (Json.mkObj [("kind", "tb-win"), ("g", g), ("inMs", match ms with | none => Json.null | some m => toJson m), ("phase", (winPhase g ms).name)]).compress) ++
  ((tbCostCases ()).map fun (name, g, rows) =>
    (Json.mkObj [("kind", "tb-cost"), ("name", name), ("g", g), ("rows", Json.arr (rows.map rowJ).toArray),
      ("cost", match windowCost g rows with
        | some (l, r, f) => Json.mkObj [("layout", l), ("recalc", r), ("frames", f)]
        | Option.none => Json.null)]).compress)

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
  ((verdictCases ()).map fun (name, fr, cr, ff, cf, js, still) =>
    (Json.mkObj [("kind", "verdict"), ("name", name), ("faithRev", pairsJ fr), ("candRev", pairsJ cr), ("faithFight", pairsJ ff),
      ("candFight", pairsJ cf), ("stillJobs", Json.arr (js.map fun j => Json.arr #[pairsJ j.1, pairsJ j.2]).toArray), ("stillLifted", still),
      ("rev", (cmp (rates fr) (rates cr)).name), ("fight", (cmp (rates ff) (rates cf)).name), ("stillWorse", stillWorseOf js),
      ("verdict", (verdictOf fr cr ff cf js still).name)]).compress) ++
  (let cs := (passCases ()).map fun (_, r, d, y, ws) => ofRecord r d y ws
   let cs3 := cs ++ cs.reverse ++ cs
   [cs, cs.reverse, cs3, []].map fun l =>
    (Json.mkObj [("kind", "total"), ("passes", Json.arr (l.map countsJ).toArray), ("total", countsJ (total l))]).compress) ++
  tbGoldenLines ()

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
