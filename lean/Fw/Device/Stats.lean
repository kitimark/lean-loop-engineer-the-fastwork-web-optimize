import Fw.Device.Session
/-!
# Miss counts, hitch time and touch latency of a phone pass
The second reduction of a recorded pass, twinned by `reduceV2` in `packages/measure-webkit/src/device-session.mjs`.
-/
namespace Fw.Device.Stats
open Lean Fw.Device.Session

/-! ## Slots and intervals -/

/-- 25 ms in hundredths of a millisecond. -/
def miss : Int := 2500

theorem miss_lt_slow : miss < slow := by decide

/-- The 60 Hz slot of time `t` counted from `t0`, rounded half up. -/
def slotOf (t0 t : Int) : Int := ((t - t0) * 6 + 5000) / 10000

/-- An interval longer than two 60 Hz slots advances the slot count by 2 or more. -/
theorem slot_skip_of_over_two_slots (t0 a b : Int) (h : 200000 < (b - a) * 60) : 1 < slotOf t0 b - slotOf t0 a := by
  unfold slotOf
  omega

/-- A recorded frame: rAF time (hundredths of a ms), scroll position (tenth px), part values (per mille). -/
structure Frame where
  t : Int
  y : Int
  p : List Int
  deriving Repr, DecidableEq

/-- A frame interval: index and time of the frame that ends it, length, slots advanced, position, page moved, anything changed. -/
structure Iv where
  i : Nat
  t : Int
  dt : Int
  dk : Int
  y : Int
  moving : Bool
  animating : Bool
  deriving Repr, DecidableEq

/-- The intervals of the frames from index `i`, slots counted from `t0`. -/
def ivsAux (t0 : Int) : Nat → List Frame → List Iv
  | i, a :: b :: rest =>
    ⟨i + 1, b.t, b.t - a.t, slotOf t0 b.t - slotOf t0 a.t, b.y, b.y != a.y, b.y != a.y || b.p != a.p⟩ :: ivsAux t0 (i + 1) (b :: rest)
  | _, _ => []

/-- The intervals of a pass, slots counted from its first frame. -/
def ivs : List Frame → List Iv
  | [] => []
  | f :: rest => ivsAux f.t 0 (f :: rest)

theorem ivsAux_length (t0 : Int) : ∀ (i : Nat) (fs : List Frame), (ivsAux t0 i fs).length = fs.length - 1
  | _, [] => by simp [ivsAux]
  | _, [_] => by simp [ivsAux]
  | i, a :: b :: rest => by
    have := ivsAux_length t0 (i + 1) (b :: rest)
    simp only [ivsAux, List.length_cons] at this ⊢
    omega

theorem ivs_length (fs : List Frame) : (ivs fs).length = fs.length - 1 := by
  cases fs with
  | nil => simp [ivs]
  | cons f rest => exact ivsAux_length _ _ _

/-- A skipped slot: the interval advanced the slot count by more than 1. -/
def skip (v : Iv) : Bool := decide (1 < v.dk)

/-- The interval is longer than two 60 Hz slots. -/
def twoSlots (v : Iv) : Bool := decide (200000 < v.dt * 60)

theorem ivsAux_twoSlots (t0 : Int) : ∀ (i : Nat) (fs : List Frame) (v : Iv), v ∈ ivsAux t0 i fs → twoSlots v = true → skip v = true
  | _, [], _, h, _ => by simp [ivsAux] at h
  | _, [_], _, h, _ => by simp [ivsAux] at h
  | i, a :: b :: rest, v, h, h2 => by
    simp only [ivsAux, List.mem_cons] at h
    rcases h with rfl | h
    · simp only [twoSlots, skip, decide_eq_true_eq] at h2 ⊢
      exact slot_skip_of_over_two_slots t0 a.t b.t h2
    · exact ivsAux_twoSlots t0 (i + 1) (b :: rest) v h h2

/-- Every interval of a pass longer than two slots is a skipped slot. -/
theorem ivs_twoSlots_skip {fs : List Frame} {v : Iv} (h : v ∈ ivs fs) (h2 : twoSlots v = true) : skip v = true := by
  cases fs with
  | nil => simp [ivs] at h
  | cons f rest => exact ivsAux_twoSlots _ _ _ v h h2

/-- Frames at 0, 8.5 and 34 ms sit in slots 0, 1 and 2: the 25.5 ms interval is over 25 ms and skips no slot. -/
def cexFrames : List Frame := [⟨0, 0, []⟩, ⟨850, 10, []⟩, ⟨3400, 20, []⟩]

theorem miss_without_skip : ∃ v ∈ ivs cexFrames, miss < v.dt ∧ skip v = false := by decide

#guard slotOf 0 833 = 0
#guard slotOf 0 834 = 1
#guard slotOf 0 3400 = 2
#guard (ivs cexFrames).map (·.dk) = [1, 1]
#guard (ivs cexFrames).map skip = [false, false]
#guard (ivs [⟨0, 0, []⟩, ⟨3400, 0, []⟩]).map skip = [true]
#guard twoSlots ⟨1, 0, 3400, 2, 0, false, false⟩ && !twoSlots ⟨1, 0, 3333, 2, 0, false, false⟩
#guard (ivs [⟨0, 0, []⟩, ⟨1667, 0, []⟩, ⟨1667, 10, []⟩, ⟨1700, 10, [5]⟩]).map (fun v => (v.moving, v.animating)) =
  [(false, false), (true, true), (false, true)]

/-- A frame in which the page moved is a frame in which something changed. -/
theorem ivsAux_moving_animating (t0 : Int) : ∀ (i : Nat) (fs : List Frame) (v : Iv), v ∈ ivsAux t0 i fs → v.moving = true → v.animating = true
  | _, [], _, h, _ => by simp [ivsAux] at h
  | _, [_], _, h, _ => by simp [ivsAux] at h
  | i, a :: b :: rest, v, h, hm => by
    simp only [ivsAux, List.mem_cons] at h
    rcases h with rfl | h
    · simp_all
    · exact ivsAux_moving_animating t0 (i + 1) (b :: rest) v h hm

/-! ## Counts -/

/-- The intervals longer than `th`. -/
def over (th : Int) (v : Iv) : Bool := decide (th < v.dt)

/-- The intervals of a list that satisfy `p`. -/
def cnt (p : Iv → Bool) (vs : List Iv) : Nat := vs.countP p

theorem cnt_over_mono {a b : Int} (h : a ≤ b) (vs : List Iv) : cnt (over b) vs ≤ cnt (over a) vs := by
  apply List.countP_mono_left
  intro v _ hv
  simp only [over, decide_eq_true_eq] at hv ⊢
  omega

/-- Every interval over 50 ms is over 34 ms, and every interval over 34 ms is over 25 ms. -/
theorem over50_le_over34_le_miss25 (vs : List Iv) :
    cnt (over bad) vs ≤ cnt (over slow) vs ∧ cnt (over slow) vs ≤ cnt (over miss) vs :=
  ⟨cnt_over_mono (by decide) vs, cnt_over_mono (by decide) vs⟩

/-- In any set of intervals of a pass, the count over two slots is at most the skipped-slot count. -/
theorem twoSlots_le_skips {fs : List Frame} {vs : List Iv} (h : ∀ v ∈ vs, v ∈ ivs fs) : cnt twoSlots vs ≤ cnt skip vs :=
  List.countP_mono_left fun v hv h2 => ivs_twoSlots_skip (h v hv) h2

/-- The slots skipped in total. -/
def lost (vs : List Iv) : Int := (vs.map fun v => max 0 (v.dk - 1)).sum

/-- The summed length of the intervals. -/
def span (vs : List Iv) : Int := (vs.map (·.dt)).sum

/-- The summed time past the expected interval `e`. -/
def late (e : Int) (vs : List Iv) : Int := (vs.map fun v => max 0 (v.dt - e)).sum

/-- Hundredths of a ms late per second of interval time, 0 for no time. -/
def hitch (e : Int) (vs : List Iv) : Int := if span vs ≤ 0 then 0 else late e vs * 100000 / span vs

theorem late_nonneg (e : Int) : ∀ vs : List Iv, 0 ≤ late e vs
  | [] => by simp [late]
  | v :: vs => by
    have := late_nonneg e vs
    simp only [late, List.map_cons, List.sum_cons] at this ⊢
    omega

theorem hitch_nonneg (e : Int) (vs : List Iv) : 0 ≤ hitch e vs := by
  unfold hitch
  split
  · exact Int.le_refl 0
  · exact Int.ediv_nonneg (Int.mul_nonneg (late_nonneg e vs) (by decide)) (by omega)

/-- Apple's hitch-time-ratio band of the Xcode Organizer. -/
inductive Band where
  | good | warning | critical | urgent
  deriving DecidableEq, Repr

/-- The name written in the output. -/
def Band.name : Band → String
  | .good => "good" | .warning => "warning" | .critical => "critical" | .urgent => "urgent"

/-- The band of a hitch ratio in hundredths of a ms per s: up to 10 good, 25 warning, 50 critical, above urgent. -/
def bandOf (h : Int) : Band :=
  if h ≤ 1000 then .good else if h ≤ 2500 then .warning else if h ≤ 5000 then .critical else .urgent

theorem bandOf_good {h : Int} (h1 : h ≤ 1000) : bandOf h = .good := by simp [bandOf, h1]

theorem bandOf_warning {h : Int} (h1 : 1000 < h) (h2 : h ≤ 2500) : bandOf h = .warning := by
  simp [bandOf, h2, show ¬ h ≤ 1000 by omega]

theorem bandOf_critical {h : Int} (h1 : 2500 < h) (h2 : h ≤ 5000) : bandOf h = .critical := by
  simp [bandOf, h2, show ¬ h ≤ 1000 by omega, show ¬ h ≤ 2500 by omega]

theorem bandOf_urgent {h : Int} (h1 : 5000 < h) : bandOf h = .urgent := by
  simp [bandOf, show ¬ h ≤ 1000 by omega, show ¬ h ≤ 2500 by omega, show ¬ h ≤ 5000 by omega]

#guard over miss ⟨1, 0, 2550, 1, 0, false, false⟩ && !over miss ⟨1, 0, 2500, 1, 0, false, false⟩
#guard hitch 1667 (ivs [⟨0, 0, []⟩, ⟨1667, 0, []⟩, ⟨5000, 0, []⟩, ⟨6667, 0, []⟩]) = 24988
#guard hitch 1667 [] = 0
#guard [1000, 1001, 2500, 2501, 5000, 5001].map bandOf = [.good, .warning, .warning, .critical, .critical, .urgent]

/-- The values in ascending order. -/
def sortI (l : List Int) : List Int := l.mergeSort fun a b => decide (a ≤ b)

/-- The value at index `n / 2` of the sorted values, 0 for none. -/
def medianL (l : List Int) : Int := (sortI l).getD (l.length / 2) 0

/-- The nearest-rank 95th percentile: index ⌈0.95 n⌉ - 1 of the sorted values, 0 for none. -/
def p95L (l : List Int) : Int := (sortI l).getD ((95 * l.length + 99) / 100 - 1) 0

theorem sortI_pairwise (l : List Int) : (sortI l).Pairwise fun a b => decide (a ≤ b) = true :=
  List.pairwise_mergeSort (fun a b c h1 h2 => by simp only [decide_eq_true_eq] at *; omega)
    (fun a b => by by_cases h : a ≤ b <;> simp [h]; omega) l

theorem median_le_p95 (l : List Int) : medianL l ≤ p95L l := by
  rcases Nat.eq_zero_or_pos l.length with h0 | hpos
  · simp [medianL, p95L, List.length_eq_zero_iff.1 h0, sortI]
  · have hl : (sortI l).length = l.length := List.length_mergeSort _
    have hi : l.length / 2 < (sortI l).length := by omega
    have hj : (95 * l.length + 99) / 100 - 1 < (sortI l).length := by omega
    unfold medianL p95L
    rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hi, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hj]
    simp only [Option.getD_some]
    rcases Nat.lt_or_eq_of_le (show l.length / 2 ≤ (95 * l.length + 99) / 100 - 1 by omega) with hlt | heq
    · have := (List.pairwise_iff_getElem.1 (sortI_pairwise l)) _ _ hi hj hlt
      simpa using this
    · simp [heq]

theorem p95_mem {l : List Int} (h : l ≠ []) : p95L l ∈ l := by
  have hl : (sortI l).length = l.length := List.length_mergeSort _
  have hpos : 0 < l.length := List.length_pos_iff.2 h
  have hj : (95 * l.length + 99) / 100 - 1 < (sortI l).length := by omega
  unfold p95L
  rw [List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hj]
  exact List.mem_mergeSort.1 (List.getElem_mem _)

theorem p95_le_longest {l : List Int} (h : l ≠ []) : p95L l ≤ maxOf0 l := le_maxOf0 (p95_mem h)

#guard medianL [3, 1, 2] = 2 && medianL [] = 0
#guard p95L ((List.range 20).map fun k : Nat => (k : Int) + 1) = 19 && p95L [5] = 5 && p95L [] = 0

/-- The longest run of skipped slots in consecutive frames, given the index of the last skip, the current run and the best. -/
def runGo : Int → Nat → Nat → List Iv → Nat
  | _, _, best, [] => best
  | last, cur, best, v :: vs =>
    if skip v then
      let c := if (v.i : Int) = last + 1 then cur + 1 else 1
      runGo v.i c (max best c) vs
    else runGo last cur best vs

/-- The longest run of consecutive frames in which the page updated at 30 fps or slower. -/
def run30 (vs : List Iv) : Nat := runGo (-2) 0 0 vs

theorem runGo_le : ∀ (last : Int) (cur best : Nat) (vs : List Iv), runGo last cur best vs ≤ max best (cur + cnt skip vs)
  | _, _, best, [] => by simp only [runGo, cnt, List.countP_nil]; omega
  | last, cur, best, v :: vs => by
    unfold runGo
    split
    · rename_i hs
      have hc : (if (v.i : Int) = last + 1 then cur + 1 else 1) ≤ cur + 1 := by split <;> omega
      generalize (if (v.i : Int) = last + 1 then cur + 1 else 1) = c at hc ⊢
      have := runGo_le v.i c (max best c) vs
      simp only [cnt, List.countP_cons, hs, ite_true] at this ⊢
      omega
    · rename_i hs
      have := runGo_le last cur best vs
      simp only [cnt, List.countP_cons, hs] at this ⊢
      simpa using this

theorem run30_le_skips (vs : List Iv) : run30 vs ≤ cnt skip vs := by
  have := runGo_le (-2) 0 0 vs
  simp only [run30] at *
  omega

#guard run30 (ivs [⟨0, 0, []⟩, ⟨3400, 0, []⟩, ⟨6800, 0, []⟩, ⟨8467, 0, []⟩, ⟨11867, 0, []⟩]) = 2

/-! ## The stats of a set of intervals -/

/-- Miss counts, hitch time and spread of a set of intervals. -/
structure Stat2 where
  n : Nat
  skips : Nat
  lost : Int
  over25 : Nat
  over34 : Nat
  over50 : Nat
  perSkip : Nat
  per25 : Nat
  per34 : Nat
  per50 : Nat
  span : Int
  late : Int
  hitch : Int
  band : Band
  median : Int
  p95 : Int
  longest : Int
  run30 : Nat
  deriving Repr, DecidableEq

/-- The stats of a set of intervals against the expected interval `e`. -/
def stat2 (e : Int) (vs : List Iv) : Stat2 :=
  let n := vs.length
  let dts := vs.map (·.dt)
  { n, skips := cnt skip vs, lost := lost vs, over25 := cnt (over miss) vs, over34 := cnt (over slow) vs,
    over50 := cnt (over bad) vs, perSkip := per100 (cnt skip vs) n, per25 := per100 (cnt (over miss) vs) n,
    per34 := per100 (cnt (over slow) vs) n, per50 := per100 (cnt (over bad) vs) n, span := span vs, late := late e vs,
    hitch := hitch e vs, band := bandOf (hitch e vs), median := medianL dts, p95 := p95L dts, longest := maxOf0 dts,
    run30 := run30 vs }

theorem stat2_order (e : Int) (vs : List Iv) :
    (stat2 e vs).over50 ≤ (stat2 e vs).over34 ∧ (stat2 e vs).over34 ≤ (stat2 e vs).over25 :=
  over50_le_over34_le_miss25 vs

theorem stat2_run30_le (e : Int) (vs : List Iv) : (stat2 e vs).run30 ≤ (stat2 e vs).skips := run30_le_skips vs

/-! ## One pass -/

/-- The frames of a record. -/
def framesOf (r : Record) : List Frame :=
  ((r.ts.zip r.ys).zipIdx).map fun ((t, y), k) => ⟨t, y, r.parts.map fun pv => pv.2.getD k 0⟩

/-- The expected interval: the median of every interval of the pass. -/
def expected (vs : List Iv) : Int := medianL (vs.map (·.dt))

/-- Which intervals a set holds. -/
inductive Sel where
  | all | animating | moving
  deriving DecidableEq, Repr

/-- The name written in the output. -/
def Sel.name : Sel → String
  | .all => "all" | .animating => "animating" | .moving => "moving"

/-- Whether an interval is in a set. -/
def Sel.keep : Sel → Iv → Bool
  | .all, _ => true
  | .animating, v => v.animating
  | .moving, v => v.moving

/-- The intervals of a zone, `none` for the whole pass. -/
def zoneSel (vh10 maxY10 : Int) : Option Zone → Iv → Bool
  | none, _ => true
  | some z, v => zoneOf vh10 maxY10 v.y == z

/-- The zone keys of the output. -/
def zoneKeys : List (Option Zone) := [none, some .hero, some .finish, some .rest]

/-- The name written in the output. -/
def zoneName : Option Zone → String
  | none => "whole" | some z => z.name

/-- The index of the first frame at the end of the page, the last index when no frame reaches it. -/
def firstEnd (vh10 maxY10 : Int) (fs : List Frame) : Nat :=
  (fs.findIdx? fun f => zoneOf vh10 maxY10 f.y == .finish).getD fs.length

#guard Sel.animating.keep ⟨1, 0, 1667, 1, 0, false, true⟩ && !Sel.moving.keep ⟨1, 0, 1667, 1, 0, false, true⟩
#guard zoneSel 100 1000 (some .finish) ⟨1, 0, 1667, 1, 950, false, false⟩ && !zoneSel 100 1000 (some .hero) ⟨1, 0, 1667, 1, 950, false, false⟩
#guard firstEnd 100 1000 [⟨0, 0, []⟩, ⟨1667, 500, []⟩, ⟨3333, 950, []⟩] = 2
#guard firstEnd 100 1000 [⟨0, 0, []⟩, ⟨1667, 500, []⟩] = 2

/-! ## Felt marks -/

/-- A felt mark's lookback: 3 s in hundredths of a ms. -/
def lookback3 : Int := 300000

/-- The taps of a stream with the start time of each. -/
def tapsW (ts : List Touch) : List (Int × Tap) :=
  (strokes ts).filterMap fun s =>
    match s.head?, tapOf s with
    | some a, some tp => some (a.t, tp)
    | _, _ => none

theorem tapsW_map (ts : List Touch) : (tapsW ts).map (·.2) = taps ts := by
  unfold tapsW taps
  induction strokes ts with
  | nil => rfl
  | cons s ss ih =>
    simp only [List.filterMap_cons]
    cases hs : s.head? with
    | none =>
      have : tapOf s = none := by simp [tapOf, hs]
      simp [this, ih]
    | some a =>
      cases ht : tapOf s with
      | none => simp [ih]
      | some tp => simp [ih]

/-- The first tap's start and the third tap of every felt mark, scanning from the left. -/
def marksW : List (Int × Tap) → List (Int × Tap)
  | a :: b :: c :: rest => if triple a.2 b.2 c.2 then (a.1, c.2) :: marksW rest else marksW (b :: c :: rest)
  | _ => []
termination_by l => l.length

/-- The marks of `marksW` are the marks of `marksOf`. -/
theorem marksW_map : ∀ l : List (Int × Tap), (marksW l).map (·.2) = marksOf (l.map (·.2))
  | [] => by simp [marksW, marksOf]
  | [_] => by simp [marksW, marksOf]
  | [_, _] => by simp [marksW, marksOf]
  | a :: b :: c :: rest => by
    have h1 := marksW_map rest
    have h2 := marksW_map (b :: c :: rest)
    rw [marksW, List.map_cons, List.map_cons, List.map_cons, marksOf]
    split
    · simp [h1]
    · simpa using h2
termination_by l => l.length

#guard marksW (tapsW [⟨0, .start, 0, 0, 1⟩, ⟨1000, .stop, 0, 0, 0⟩, ⟨20000, .start, 0, 0, 1⟩, ⟨21000, .stop, 0, 0, 0⟩,
  ⟨40000, .start, 0, 0, 1⟩, ⟨41000, .stop, 0, 0, 0⟩]) = [(0, ⟨41000, 0, 0⟩)]

/-- The intervals ending in the 3 s before the first tap of a mark. -/
def feltWindow (anchor : Int) (vs : List Iv) : List Iv :=
  vs.filter fun v => decide (anchor - lookback3 ≤ v.t ∧ v.t ≤ anchor)

theorem mem_feltWindow {anchor : Int} {vs : List Iv} {v : Iv} :
    v ∈ feltWindow anchor vs ↔ v ∈ vs ∧ anchor - lookback3 ≤ v.t ∧ v.t ≤ anchor := by
  simp [feltWindow]

#guard (feltWindow 400000 (ivs [⟨0, 0, []⟩, ⟨99999, 0, []⟩, ⟨100000, 0, []⟩, ⟨400000, 0, []⟩, ⟨400001, 0, []⟩])).map (·.t) =
  [100000, 400000]

/-- A felt mark of the second reduction: position and zone at the first tap, every interval and the animating ones of its window, and whether the first window counted no frame. -/
structure FeltV2 where
  y : Int
  zone : Zone
  all : Stat2
  animating : Stat2
  oldEmpty : Bool
  deriving Repr, DecidableEq

/-- The felt mark of a (first-tap start, third tap) pair. -/
def feltV2 (vh10 maxY10 e : Int) (fs : List (Int × Int)) (vs : List Iv) (m : Int × Tap) : FeltV2 :=
  let y := yAt fs m.1
  let w := feltWindow m.1 vs
  ⟨y, zoneOf vh10 maxY10 y, stat2 e w, stat2 e (w.filter (·.animating)), (feltOf vh10 maxY10 fs m.2).stat.n == 0⟩

/-! ## Touch latency and finger offset -/

/-- The strokes that are not taps and had one finger down throughout. -/
def drags (ts : List Touch) : List (List Touch) :=
  (strokes ts).filter fun s => !isTap s && s.all fun e => decide (e.n ≤ 1)

/-- From touch start to the first frame in which the page moved, for a stroke that started on a still page and scrolled it before the finger lifted. -/
def startLatency (fs : List (Int × Int)) (s : List Touch) : Option Int :=
  match s.head?, s.getLast? with
  | some a, some z =>
    match (fs.filter fun f => decide (f.1 ≤ a.t)).reverse with
    | f1 :: f2 :: _ =>
      if f1.2 = f2.2 then
        (fs.find? fun f => decide (a.t < f.1 ∧ f.1 ≤ z.t ∧ f.2 ≠ f1.2)).map (·.1 - a.t)
      else none
    | _ => none
  | _, _ => none

theorem startLatency_pos {fs : List (Int × Int)} {s : List Touch} {d : Int} (h : startLatency fs s = some d) : 0 < d := by
  unfold startLatency at h
  split at h
  · rename_i a z _ _
    split at h
    · split at h
      · obtain ⟨f, hf, rfl⟩ := Option.map_eq_some_iff.1 h
        have := List.find?_some hf
        simp only [decide_eq_true_eq] at this
        omega
      · simp at h
    · simp at h
  · simp at h

/-- The finger's position (tenth px) at time `t`: its last event at or before `t`, else its first. -/
def fingerY (s : List Touch) (t : Int) : Int :=
  match (s.filter fun e => decide (e.t ≤ t)).getLast? with
  | some e => e.y
  | none => (s.head?.map (·.y)).getD 0

/-- The largest gap (tenth px) between the page's travel and the finger's travel in a stroke, counted from the first frame the page moved, frames at the page ends left out. -/
def offsetMax (maxY10 : Int) (fs : List (Int × Int)) (s : List Touch) : Option Nat :=
  match s.head?, s.getLast? with
  | some a, some z =>
    let y0 := yAt fs a.t
    let during := fs.filter fun f => decide (a.t < f.1 ∧ f.1 ≤ z.t)
    match during.find? fun f => f.2 != y0 with
    | some r =>
      let after := during.filter fun f => decide (r.1 ≤ f.1 ∧ 0 < f.2 ∧ f.2 < maxY10)
      some ((after.map fun f => ((f.2 - r.2) - (fingerY s r.1 - fingerY s f.1)).natAbs).foldr max 0)
    | none => none
  | _, _ => none

/-- A page that follows the finger exactly has no offset. -/
theorem offset_zero_of_follow (r f : Int × Int) (s : List Touch) (h : f.2 - r.2 = fingerY s r.1 - fingerY s f.1) :
    ((f.2 - r.2) - (fingerY s r.1 - fingerY s f.1)).natAbs = 0 := by
  rw [h]; simp

#guard drags [⟨0, .start, 0, 1000, 1⟩, ⟨1000, .stop, 0, 1000, 0⟩] = []
#guard (drags [⟨0, .start, 0, 1000, 1⟩, ⟨1000, .move, 0, 500, 1⟩, ⟨2000, .stop, 0, 0, 0⟩]).length = 1
#guard startLatency [(0, 0), (1000, 0), (2000, 0), (3000, 50)] [⟨1500, .start, 0, 0, 1⟩, ⟨4000, .stop, 0, 0, 0⟩] = some 1500
#guard startLatency [(0, 10), (1000, 0), (2000, 0), (3000, 50)] [⟨1200, .start, 0, 0, 1⟩, ⟨4000, .stop, 0, 0, 0⟩] = none
#guard offsetMax 1000 [(0, 0), (1000, 0), (2000, 100), (3000, 200)]
  [⟨500, .start, 0, 1000, 1⟩, ⟨1500, .move, 0, 900, 1⟩, ⟨2500, .move, 0, 800, 1⟩, ⟨3500, .stop, 0, 700, 0⟩] = some 0
#guard offsetMax 1000 [(0, 0), (1000, 0), (2000, 100), (3000, 250)]
  [⟨500, .start, 0, 1000, 1⟩, ⟨1500, .move, 0, 900, 1⟩, ⟨2500, .move, 0, 800, 1⟩, ⟨3500, .stop, 0, 700, 0⟩] = some 50

/-! ## The pass report -/

/-- The second reduction of one pass. -/
structure ReportV2 where
  expected : Int
  sets : List (Sel × List (Option Zone × Stat2))
  traversal : List (String × List (Sel × Stat2))
  felt : List FeltV2
  starts : List Int
  offsets : List Nat

/-- The second reduction of a pass. -/
def reduceV2 (r : Record) : ReportV2 :=
  let frs := framesOf r
  let vs := ivs frs
  let e := expected vs
  let vh10 : Int := (r.h : Int) * 10
  let fs := r.ts.zip r.ys
  let fe := firstEnd vh10 r.maxY10 frs
  let sels : List Sel := [.all, .animating, .moving]
  let part (keepI : Iv → Bool) : List (Sel × Stat2) := sels.map fun s => (s, stat2 e (vs.filter fun v => keepI v && s.keep v))
  { expected := e
    sets := sels.map fun s => (s, zoneKeys.map fun z => (z, stat2 e (vs.filter fun v => s.keep v && zoneSel vh10 r.maxY10 z v)))
    traversal := [("first", part fun v => decide (v.i ≤ fe)), ("later", part fun v => decide (fe < v.i))]
    felt := (marksW (tapsW r.touches)).map (feltV2 vh10 r.maxY10 e fs vs)
    starts := (drags r.touches).filterMap (startLatency fs)
    offsets := (drags r.touches).filterMap (offsetMax r.maxY10 fs) }

/-- The second reduction keeps one felt mark per mark of the first. -/
theorem reduceV2_felt_length (r : Record) : (reduceV2 r).felt.length = (reducePass r).felt.length := by
  have := congrArg List.length (marksW_map (tapsW r.touches))
  simp only [List.length_map, tapsW_map] at this
  simp [reduceV2, reducePass, this]

/-! ## The golden -/

private def stat2J (s : Stat2) : Json :=
  Json.mkObj [("n", s.n), ("skips", s.skips), ("lost", s.lost), ("over25", s.over25), ("over34", s.over34),
    ("over50", s.over50), ("perSkip", s.perSkip), ("per25", s.per25), ("per34", s.per34), ("per50", s.per50),
    ("span", s.span), ("late", s.late), ("hitch", s.hitch), ("band", s.band.name), ("median", s.median), ("p95", s.p95),
    ("longest", s.longest), ("run30", s.run30)]

private def ivJ (v : Iv) : Json :=
  toJson [toJson v.i, toJson v.t, toJson v.dt, toJson v.dk, toJson v.y, toJson v.moving, toJson v.animating]

private def frameJ (f : Frame) : Json := toJson [toJson f.t, toJson f.y, toJson f.p]

private def feltV2J (f : FeltV2) : Json :=
  Json.mkObj [("y", f.y), ("zone", f.zone.name), ("all", stat2J f.all), ("animating", stat2J f.animating),
    ("oldEmpty", f.oldEmpty)]

private def selsJ (l : List (Sel × Stat2)) : Json := Json.mkObj (l.map fun (s, st) => (s.name, stat2J st))

/-- The report in the shape the TS twin writes. -/
def reportV2J (r : ReportV2) : Json :=
  Json.mkObj [("expected", r.expected),
    ("sets", Json.mkObj (r.sets.map fun (s, zs) => (s.name, Json.mkObj (zs.map fun (z, st) => (zoneName z, stat2J st))))),
    ("traversal", Json.mkObj (r.traversal.map fun (k, l) => (k, selsJ l))),
    ("felt", Json.arr (r.felt.map feltV2J).toArray), ("starts", toJson r.starts), ("offsets", toJson r.offsets)]

private def touchJ (e : Touch) : Json := toJson [Json.num e.t, Json.str e.ph.code, Json.num e.x, Json.num e.y, Json.num e.n]

private def recordJ (r : Record) : Json :=
  Json.mkObj [("schema", "fw.phone.record.int/1"), ("arm", "original"), ("pass", (1 : Nat)), ("w", r.w), ("h", r.h),
    ("maxY10", r.maxY10), ("t", toJson r.ts), ("y", toJson r.ys),
    ("p", Json.mkObj (r.parts.map fun (n, vs) => (n, toJson vs))), ("touches", Json.arr (r.touches.map touchJ).toArray)]

private def fr (t y : Int) (p : List Int := []) : Frame := ⟨t, y, p⟩

private def ivCases : List (List Frame) :=
  [cexFrames, [], [fr 0 0], [fr 0 0 [5], fr 1700 0 [5], fr 3300 0 [6], fr 5000 10 [6], fr 8300 20 [6], fr 10000 20 [6]],
   [fr 100 0, fr 1767 0, fr 3433 0, fr 5100 0, fr 6767 0, fr 8433 0, fr 10100 0],
   [fr 0 0, fr 3300 0, fr 3400 0, fr 6700 0, fr 6800 0, fr 8400 0],
   [fr 0 0, fr 3334 10, fr 6667 20, fr 10000 30, fr 16700 40, fr 18300 40, fr 21700 50, fr 25000 60]]

private def statCases : List (Int × List Int) :=
  [(1700, []), (1700, [1700]), (1700, [1700, 1600, 1700, 3300, 3400, 3500, 5000, 5100, 1700]), (1600, [2550, 800, 1700, 21500]),
   (0, [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 1100, 1200, 1300, 1400, 1500, 1600, 1700, 1800, 1900, 2000, 2100])]

/-- Intervals with given lengths, slot steps from their lengths, consecutive indices. -/
private def ivsOfDts (dts : List Int) : List Iv :=
  ivs ((dts.foldl (fun (acc : List Int) d => acc ++ [acc.getLastD 0 + d]) [0]).map fun t => fr t t)

private def bandCases : List Int := [0, 1000, 1001, 2500, 2501, 5000, 5001]

private def slotCases : List (Int × Int) := [(0, 0), (0, 833), (0, 834), (0, 850), (0, 3400), (100, 1767), (0, -900), (0, 166667)]

private def tW (s t x y : Int) : Int × Tap := (s, ⟨t, x, y⟩)

private def markWCases : List (List (Int × Tap)) :=
  [[tW 0 5000 100 100, tW 20000 30000 110 100, tW 50000 60000 105 95],
   [tW 0 5000 100 100, tW 50000 60000 110 100, tW 60000 70000 105 95, tW 70000 80000 100 100],
   [tW 0 5000 100 100, tW 20000 30000 110 100], []]

private def tc (t : Int) (ph : Phase) (x y : Int) (n : Nat := 1) : Touch := ⟨t, ph, x, y, n⟩

private def stillFrames : List (Int × Int) :=
  [(0, 0), (1700, 0), (3300, 0), (5000, 0), (6700, 50), (8300, 150), (10000, 300), (11700, 450), (13300, 500), (15000, 500)]

private def touchCases : List (List (Int × Int) × List Touch) :=
  [(stillFrames, [tc 4000 .start 2000 6000, tc 6000 .move 2000 5900, tc 9000 .move 2000 5700, tc 12000 .move 2000 5500, tc 14000 .stop 2000 5500]),
   (stillFrames, [tc 1000 .start 2000 6000, tc 2000 .move 2000 5900, tc 2500 .stop 2000 5900]),
   (stillFrames, [tc 7000 .start 2000 6000, tc 9000 .move 2000 5800, tc 12000 .stop 2000 5600]),
   (stillFrames, [tc 4000 .start 2000 6000, tc 6000 .move 2000 5900, tc 9000 .move 2000 5700 2, tc 14000 .stop 2000 5500]),
   (stillFrames, [tc 4000 .start 2000 6000, tc 5000 .stop 2000 6000]),
   ([], [tc 4000 .start 2000 6000, tc 9000 .move 2000 5000, tc 14000 .stop 2000 4000])]

private def lcg (s : Nat) : Nat := (s * 1103515245 + 12345) % 2147483648

private def lcgs : Nat → Nat → List Nat
  | 0, _ => []
  | n + 1, s => lcg s :: lcgs n (lcg s)

private def synthN : Nat := 360

private def synthDt (k r : Nat) : Int :=
  if k = 40 then 3300 else if k = 41 then 3400 else if k = 60 then 2600 else if k = 61 then 800
  else if 90 ≤ k ∧ k ≤ 94 then 3300 else if k = 120 then 21500 else if k = 200 then 5100 else if k = 250 then 3500
  else if k % 3 = 0 then 1600 else 1700 + ((r / 65536 : Nat) % 3 : Nat) - 1

private def synthY (k : Nat) : Int :=
  if k < 20 then 0 else if k < 140 then 100 * (((k : Int) - 20)) else if k < 180 then 12000
  else if k < 300 then 12000 + 120 * ((k : Int) - 180) else 26400

private def synthP (k : Nat) : Int := if 150 ≤ k ∧ k < 170 then 50 * ((k : Int) - 150) else if k < 150 then 0 else 1000

private def synthRecord (_ : Unit) : Record :=
  let dts := (List.range synthN).zip (lcgs synthN 7) |>.map fun (k, r) => if k = 0 then 0 else synthDt k r
  let ts := (dts.foldl (fun (acc : List Int) d => acc ++ [acc.getLastD 100000 + d]) []).map id
  let tAt (k : Nat) : Int := ts.getD k 0
  let drag (k0 k1 : Nat) (y0 : Int) : List Touch :=
    tc (tAt k0 - 500) .start 2000 y0 :: ((List.range (k1 - k0)).map fun j => tc (tAt (k0 + j + 1) - 300) .move 2000 (y0 - 90 * ((j + 1 : Nat) : Int))) ++
      [tc (tAt k1 + 200) .stop 2000 (y0 - 90 * ((k1 - k0 : Nat) : Int))]
  let tap (k : Nat) (x y : Int) : List Touch := [tc (tAt k - 200) .start x y, tc (tAt k) .stop x y]
  { w := 430, h := 800, maxY10 := 26400, ts := ts, ys := (List.range synthN).map synthY
    parts := [("hero", (List.range synthN).map synthP)]
    touches := drag 18 60 7000 ++ tap 145 1500 3000 ++ tap 150 1520 3010 ++ tap 156 1510 3000 ++ drag 178 230 7000 ++
      tap 320 1500 3000 ++ tap 325 1500 3000 ++ tap 330 1500 3000 }

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "v2.consts"), ("miss", miss), ("slow", slow), ("bad", bad), ("lookback", lookback3),
    ("slotNum", (6 : Int)), ("slotHalf", (5000 : Int)), ("slotDen", (10000 : Int)), ("twoSlots", (200000 : Int)),
    ("bands", toJson [(1000 : Int), 2500, 5000])]).compress] ++
  (slotCases.map fun (t0, t) => (Json.mkObj [("kind", "v2.slot"), ("t0", t0), ("t", t), ("slot", slotOf t0 t)]).compress) ++
  [(Json.mkObj [("kind", "v2.counterexample"), ("frames", Json.arr (cexFrames.map frameJ).toArray),
    ("ivs", Json.arr ((ivs cexFrames).map ivJ).toArray), ("miss", (ivs cexFrames).map (over miss) |> toJson),
    ("skip", (ivs cexFrames).map skip |> toJson)]).compress] ++
  (ivCases.map fun fs =>
    let vs := ivs fs
    (Json.mkObj [("kind", "v2.ivs"), ("frames", Json.arr (fs.map frameJ).toArray), ("ivs", Json.arr (vs.map ivJ).toArray),
      ("expected", expected vs), ("stat", stat2J (stat2 (expected vs) vs))]).compress) ++
  (statCases.map fun (e, dts) =>
    (Json.mkObj [("kind", "v2.stat"), ("expected", e), ("dts", toJson dts), ("stat", stat2J (stat2 e (ivsOfDts dts)))]).compress) ++
  (bandCases.map fun (h : Int) => (Json.mkObj [("kind", "v2.band"), ("hitch", h), ("band", (bandOf h).name)]).compress) ++
  (markWCases.map fun l =>
    (Json.mkObj [("kind", "v2.marks"), ("taps", Json.arr (l.map fun (s, t) => toJson [s, t.t, t.x, t.y]).toArray),
      ("marks", Json.arr ((marksW l).map fun (s, t) => toJson [s, t.t, t.x, t.y]).toArray)]).compress) ++
  (touchCases.map fun (fs, ts) =>
    (Json.mkObj [("kind", "v2.touch"), ("frames", Json.arr (fs.map fun f => toJson [f.1, f.2]).toArray),
      ("touches", Json.arr (ts.map touchJ).toArray), ("maxY10", (400 : Int)),
      ("drags", (drags ts).length), ("starts", toJson ((drags ts).filterMap (startLatency fs))),
      ("offsets", toJson ((drags ts).filterMap (offsetMax 400 fs)))]).compress) ++
  (let r := synthRecord ()
   [(Json.mkObj [("kind", "v2.session"), ("record", recordJ r), ("report", reportV2J (reduceV2 r))]).compress])

/-- The bytes of `packages/contracts/golden/device/session.jsonl`: the first reduction's lines, then the second's. -/
def goldenText (_ : Unit) : String := Fw.Device.Session.goldenText () ++ String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- Print the golden, or with `--check <file>` compare its bytes; exit 1 when they differ. -/
def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-session golden: {path} is up to date"
      return 0
    IO.eprintln s!"device-session golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.Stats
