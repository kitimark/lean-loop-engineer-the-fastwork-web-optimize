import Lean.Data.Json
import Fw.Engine.Resource
import Fw.Device.Replay
import Fw.Device.ReplayProfiles

namespace Fw.Measure.PushCycle
open Lean
open Fw.Engine.WebKit (reattachPaint attachPaint)
open Fw.Engine.Resource (repaintPx MiB)
open Fw.Device.Replay (Sample Swipe Profile Load layout layoutFrom layoutFrom_length layoutFrom_gaps gapsOk)

structure Cost where
  first : Nat
  promo : Nat
  run : Nat
  close : Nat
  toolbar : Nat
  deriving Repr, DecidableEq

def Cost.single (c : Cost) : Nat := c.first + c.promo + c.run

def openWork (c : Cost) (keep : Bool) (k : Nat) : Nat :=
  c.run + (if k = 0 then c.first else 0) + (if k = 0 || !keep then c.promo else 0)

def cycleWork (c : Cost) (keep : Bool) (k : Nat) : Nat := openWork c keep k + c.close + c.toolbar

def totalWork (c : Cost) (keep : Bool) : Nat → Nat
  | 0 => 0
  | n + 1 => totalWork c keep n + cycleWork c keep n

def Cost.perCycle (c : Cost) : Nat := c.run + c.promo + c.close + c.toolbar

theorem open_first (c : Cost) (keep : Bool) : openWork c keep 0 = c.single := by
  simp [openWork, Cost.single]; omega

theorem open_repeat (c : Cost) (k : Nat) : openWork c false (k + 1) = c.run + c.promo := by
  simp [openWork]

theorem open_kept (c : Cost) (k : Nat) : openWork c true (k + 1) = c.run := by
  simp [openWork]

theorem repeat_ge_single (c : Cost) (h : c.first ≤ c.close + c.toolbar) (k : Nat) :
    c.single ≤ cycleWork c false k := by
  cases k with
  | zero => simp [cycleWork, openWork, Cost.single]; omega
  | succ k => simp [cycleWork, openWork, Cost.single]; omega

theorem no_fall_released (c : Cost) (k : Nat) : cycleWork c false (k + 2) = cycleWork c false (k + 1) := by
  simp [cycleWork, openWork]

theorem first_ge_later (c : Cost) (keep : Bool) (k : Nat) : cycleWork c keep (k + 1) ≤ cycleWork c keep 0 := by
  cases keep <;> simp [cycleWork, openWork] <;> omega

theorem kept_falls (c : Cost) (h : 0 < c.first + c.promo) : cycleWork c true 1 < cycleWork c true 0 := by
  simp [cycleWork, openWork]; omega

theorem kept_saves (c : Cost) (k : Nat) : cycleWork c false (k + 1) = cycleWork c true (k + 1) + c.promo := by
  simp [cycleWork, openWork]; omega

theorem total_released (c : Cost) (n : Nat) : totalWork c false (n + 1) = (n + 1) * c.perCycle + c.first := by
  induction n with
  | zero => simp [totalWork, cycleWork, openWork, Cost.perCycle] <;> omega
  | succ n ih =>
    have e : (n + 1 + 1) * c.perCycle = (n + 1) * c.perCycle + c.perCycle := Nat.succ_mul _ _
    have h2 : cycleWork c false (n + 1) = c.perCycle := by simp [cycleWork, openWork, Cost.perCycle] <;> omega
    have h3 : totalWork c false (n + 1 + 1) = totalWork c false (n + 1) + cycleWork c false (n + 1) := rfl
    omega

theorem total_kept (c : Cost) (n : Nat) :
    totalWork c true (n + 1) = (n + 1) * (c.run + c.close + c.toolbar) + c.first + c.promo := by
  induction n with
  | zero => simp [totalWork, cycleWork, openWork] <;> omega
  | succ n ih =>
    have e : (n + 1 + 1) * (c.run + c.close + c.toolbar) = (n + 1) * (c.run + c.close + c.toolbar) + (c.run + c.close + c.toolbar) :=
      Nat.succ_mul _ _
    have h2 : cycleWork c true (n + 1) = c.run + c.close + c.toolbar := by simp [cycleWork, openWork] <;> omega
    have h3 : totalWork c true (n + 1 + 1) = totalWork c true (n + 1) + cycleWork c true (n + 1) := rfl
    omega

theorem kept_saves_total (c : Cost) (n : Nat) : totalWork c false (n + 1) = totalWork c true (n + 1) + n * c.promo := by
  rw [total_released, total_kept]
  have e1 : (n + 1) * c.perCycle = (n + 1) * (c.run + c.close + c.toolbar) + (n + 1) * c.promo := by
    simp only [Cost.perCycle]
    rw [← Nat.mul_add]
    congr 1
    omega
  have e2 : (n + 1) * c.promo = n * c.promo + c.promo := Nat.succ_mul n c.promo
  omega

inductive Trend where
  | rises | flat | falls
  deriving DecidableEq, Repr

def Trend.name : Trend → String
  | .rises => "rises"
  | .flat => "flat"
  | .falls => "falls"

def trend : List Nat → Trend
  | [] => .flat
  | f :: t => if 6 * t.length * f < 5 * t.sum then .rises else if 6 * t.sum < 5 * t.length * f then .falls else .flat

def series (c : Cost) (keep : Bool) (n : Nat) : List Nat := (List.range n).map (cycleWork c keep)

theorem sum_le_mul (l : List Nat) (f : Nat) (h : ∀ x ∈ l, x ≤ f) : l.sum ≤ l.length * f := by
  induction l with
  | nil => simp
  | cons x xs ih =>
    have hx := h x (by simp)
    have := ih (fun y hy => h y (by simp [hy]))
    simp only [List.sum_cons, List.length_cons, Nat.succ_mul]
    omega

theorem model_never_rises (c : Cost) (keep : Bool) (n : Nat) : trend (series c keep n) ≠ .rises := by
  cases n with
  | zero => simp [series, trend]
  | succ n =>
    have hs : series c keep (n + 1) = cycleWork c keep 0 :: (List.range n).map (fun k => cycleWork c keep (k + 1)) := by
      simp [series, List.range_succ_eq_map, Function.comp_def]
    rw [hs]
    have hb := sum_le_mul ((List.range n).map (fun k => cycleWork c keep (k + 1))) (cycleWork c keep 0) (by
      intro x hx
      simp only [List.mem_map] at hx
      obtain ⟨k, _, rfl⟩ := hx
      exact first_ge_later c keep k)
    simp only [List.length_map, List.length_range] at hb
    simp only [trend, List.length_map, List.length_range]
    have m6 : 6 * n * cycleWork c keep 0 = 6 * (n * cycleWork c keep 0) := Nat.mul_assoc _ _ _
    intro h
    split at h
    · rename_i hlt; omega
    · split at h <;> simp at h

theorem sum_replicate_eq (m x : Nat) : (List.replicate m x).sum = m * x := by
  induction m with
  | zero => simp
  | succ m ih => simp [List.replicate_succ, ih, Nat.succ_mul]; omega

theorem released_tail_flat (c : Cost) (n : Nat) : trend (List.replicate (n + 1) (cycleWork c false 1)) = .flat := by
  have m6 : 6 * n * cycleWork c false 1 = 6 * (n * cycleWork c false 1) := Nat.mul_assoc _ _ _
  have m5 : 5 * n * cycleWork c false 1 = 5 * (n * cycleWork c false 1) := Nat.mul_assoc _ _ _
  have hs := sum_replicate_eq n (cycleWork c false 1)
  simp only [List.replicate_succ, trend, List.length_replicate, hs]
  have a : ¬ 6 * n * cycleWork c false 1 < 5 * (n * cycleWork c false 1) := by omega
  have b : ¬ 6 * (n * cycleWork c false 1) < 5 * n * cycleWork c false 1 := by omega
  simp [a, b]

def cycleFlags : Nat → List Bool
  | 0 => []
  | n + 1 => false :: true :: cycleFlags n

theorem repaint_released (a : Nat) : ∀ n, reattachPaint a (cycleFlags n) = n * a
  | 0 => by simp [cycleFlags, reattachPaint]
  | 1 => by simp [cycleFlags, reattachPaint, attachPaint]
  | n + 2 => by
    have ih := repaint_released a (n + 1)
    have e : reattachPaint a (cycleFlags (n + 2)) = a + reattachPaint a (cycleFlags (n + 1)) := by
      simp [cycleFlags, reattachPaint, attachPaint]
    rw [e, ih, Nat.succ_mul (n + 1) a]
    omega

theorem repaint_kept (a n : Nat) : reattachPaint a (false :: true :: List.replicate n true) = a := by
  have h := (Fw.Engine.Resource.tween_repaint a (n + 1) []).2
  have e : reattachPaint a (false :: true :: List.replicate n true)
      = attachPaint false true a + reattachPaint a (true :: List.replicate n true) := rfl
  have e2 : reattachPaint a (true :: List.replicate n true) = reattachPaint a (List.replicate (n + 1) true) := rfl
  rw [e, e2, h]
  simp [attachPaint]

theorem released_repaints_more (a n : Nat) (ha : 0 < a) :
    reattachPaint a (false :: true :: List.replicate n true) < reattachPaint a (cycleFlags (n + 2)) := by
  rw [repaint_kept, repaint_released]
  have e : (n + 2) * a = (n + 1) * a + a := Nat.succ_mul _ _
  have : 0 < (n + 1) * a := Nat.mul_pos (by omega) ha
  omega

def cyclePx (dpr a n : Nat) : Nat := repaintPx dpr (reattachPaint a (cycleFlags n)) 1

theorem dpr3_over_dpr2 (a n : Nat) : 4 * cyclePx 3 a n = 9 * cyclePx 2 a n := by
  simp only [cyclePx, Fw.Engine.Resource.repaintPx, Nat.pow_succ, Nat.pow_zero]
  omega

-- IOSurfacePool.h:85-89@862f17d
def poolCap (mac : Bool) : Nat := if mac then 256 * MiB else 64 * MiB

def realloc (cap released : Nat) : Nat := released - min released cap

theorem realloc_mono_cap {c c' : Nat} (r : Nat) (h : c ≤ c') : realloc c' r ≤ realloc c r := by
  simp only [realloc]; omega

theorem realloc_fits (r : Nat) (h : r ≤ 64 * MiB) : realloc (poolCap false) r = 0 ∧ realloc (poolCap true) r = 0 := by
  simp only [realloc, poolCap, MiB] at *; simp; omega

theorem realloc_gap (r : Nat) (h1 : 64 * MiB < r) (h2 : r ≤ 256 * MiB) :
    0 < realloc (poolCap false) r ∧ realloc (poolCap true) r = 0 := by
  simp only [realloc, poolCap, MiB] at *; simp; omega

theorem realloc_big (r : Nat) (h : 256 * MiB < r) : realloc (poolCap false) r = realloc (poolCap true) r + 192 * MiB := by
  simp only [realloc, poolCap, MiB] at *; simp; omega

theorem census_in_gap : 64 * MiB < 90000000 ∧ 106000000 ≤ 256 * MiB := by
  simp only [MiB]; omega

inductive Verdict where
  | holds | refuted | open
  deriving DecidableEq, Repr

def Verdict.name : Verdict → String
  | .holds => "holds"
  | .refuted => "refuted"
  | .open => "open"

-- WKWebViewIOS.mm:143@862f17d
def throttleMs : Nat := 100

-- WKWebViewIOS.mm:3256-3268, :4698-4708@862f17d
def updatesIn (span : Nat) : Nat := span / throttleMs + 1

theorem updates_mono {a b : Nat} (h : a ≤ b) : updatesIn a ≤ updatesIn b := by
  simp only [updatesIn]; exact Nat.add_le_add_right (Nat.div_le_div_right h) 1

theorem updates_floor (span : Nat) (h : span < throttleMs) : updatesIn span = 1 := by
  simp only [updatesIn, throttleMs] at *; omega

-- WebPageIOS.mm:3728-3735, :3745-3747@862f17d
def layoutsOf (interactive : Bool) : Nat := if interactive then 0 else 1

def toolbarLayouts (n tb : Nat) : Nat := n * tb * layoutsOf false

theorem toolbar_layouts_single (tb : Nat) : toolbarLayouts 1 0 = 0 ∧ 0 < toolbarLayouts 1 (tb + 1) := by
  simp [toolbarLayouts, layoutsOf]

structure H1Obs where
  changes : Nat
  slowNear : Nat
  framesNear : Nat
  slowFar : Nat
  framesFar : Nat
  deriving Repr, DecidableEq

def h1MinChanges : Nat := 3

def h1MinSlow : Nat := 5

def h1Verdict (o : H1Obs) : Verdict :=
  if o.changes < h1MinChanges then .open
  else if o.slowNear + o.slowFar < h1MinSlow then .open
  else if o.framesNear = 0 || o.framesFar = 0 then .open
  else if 2 * o.slowFar * o.framesNear ≤ o.slowNear * o.framesFar then .holds
  else .refuted

theorem h1_open_changes (o : H1Obs) (h : o.changes < h1MinChanges) : h1Verdict o = .open := by simp [h1Verdict, h]

theorem h1_open_slow (o : H1Obs) (h0 : ¬ o.changes < h1MinChanges) (h : o.slowNear + o.slowFar < h1MinSlow) :
    h1Verdict o = .open := by simp [h1Verdict, h0, h]

theorem h1_open_frames (o : H1Obs) (h0 : ¬ o.changes < h1MinChanges) (h1 : ¬ o.slowNear + o.slowFar < h1MinSlow)
    (h : o.framesNear = 0 ∨ o.framesFar = 0) : h1Verdict o = .open := by
  rcases h with h | h <;> simp [h1Verdict, h0, h1, h]

theorem h1_holds (o : H1Obs) (h0 : ¬ o.changes < h1MinChanges) (h1 : ¬ o.slowNear + o.slowFar < h1MinSlow)
    (hn : 0 < o.framesNear) (hf : 0 < o.framesFar) (h : 2 * o.slowFar * o.framesNear ≤ o.slowNear * o.framesFar) :
    h1Verdict o = .holds := by
  have a : o.framesNear ≠ 0 := by omega
  have b : o.framesFar ≠ 0 := by omega
  simp [h1Verdict, h0, h1, a, b, h]

theorem h1_refuted (o : H1Obs) (h0 : ¬ o.changes < h1MinChanges) (h1 : ¬ o.slowNear + o.slowFar < h1MinSlow)
    (hn : 0 < o.framesNear) (hf : 0 < o.framesFar) (h : o.slowNear * o.framesFar < 2 * o.slowFar * o.framesNear) :
    h1Verdict o = .refuted := by
  have a : o.framesNear ≠ 0 := by omega
  have b : o.framesFar ≠ 0 := by omega
  have c : ¬ 2 * o.slowFar * o.framesNear ≤ o.slowNear * o.framesFar := by omega
  simp [h1Verdict, h0, h1, a, b, c]

-- ScrollingTreeScrollingNodeDelegateIOS.mm:526-535, :560-566@862f17d
def staleErr (v d : Nat) : Nat := v * d

theorem stale_err_mono {v v' d d' : Nat} (hv : v ≤ v') (hd : d ≤ d') : staleErr v d ≤ staleErr v' d' :=
  Nat.mul_le_mul hv hd

structure H2Obs where
  stretchesFirst : Nat
  fightsFirst : Nat
  stretchesLater : Nat
  fightsLater : Nat
  deriving Repr, DecidableEq

def h2Verdict (o : H2Obs) : Verdict :=
  if o.stretchesFirst = 0 || o.stretchesLater < 2 then .open
  else if o.fightsFirst * o.stretchesLater < o.fightsLater * o.stretchesFirst then .holds
  else .refuted

theorem h2_open (o : H2Obs) (h : o.stretchesFirst = 0 ∨ o.stretchesLater < 2) : h2Verdict o = .open := by
  rcases h with h | h <;> simp [h2Verdict, h]

theorem h2_holds (o : H2Obs) (a : 0 < o.stretchesFirst) (b : 2 ≤ o.stretchesLater)
    (h : o.fightsFirst * o.stretchesLater < o.fightsLater * o.stretchesFirst) : h2Verdict o = .holds := by
  have a' : o.stretchesFirst ≠ 0 := by omega
  have b' : ¬ o.stretchesLater < 2 := by omega
  simp [h2Verdict, a', b', h]

theorem h2_refuted (o : H2Obs) (a : 0 < o.stretchesFirst) (b : 2 ≤ o.stretchesLater)
    (h : o.fightsLater * o.stretchesFirst ≤ o.fightsFirst * o.stretchesLater) : h2Verdict o = .refuted := by
  have a' : o.stretchesFirst ≠ 0 := by omega
  have b' : ¬ o.stretchesLater < 2 := by omega
  have c : ¬ o.fightsFirst * o.stretchesLater < o.fightsLater * o.stretchesFirst := by omega
  simp [h2Verdict, a', b', c]

structure PixObs where
  cyclesSeen : Nat
  firstCyclePx : Nat
  laterCyclePx : Nat
  freedBytes : Nat
  deriving Repr, DecidableEq

def h3Verdict (o : PixObs) : Verdict :=
  if o.cyclesSeen < 3 || o.firstCyclePx = 0 then .open
  else if o.firstCyclePx ≤ o.laterCyclePx then .holds
  else if 2 * o.laterCyclePx < o.firstCyclePx then .refuted
  else .open

def h4Verdict (o : PixObs) : Verdict :=
  if o.freedBytes = 0 then .open
  else if o.freedBytes ≤ 64 * MiB then .refuted
  else if o.freedBytes ≤ 256 * MiB then .holds
  else .open

theorem h3_open (o : PixObs) (h : o.cyclesSeen < 3 ∨ o.firstCyclePx = 0) : h3Verdict o = .open := by
  rcases h with h | h <;> simp [h3Verdict, h]

theorem h3_holds (o : PixObs) (a : 3 ≤ o.cyclesSeen) (b : 0 < o.firstCyclePx) (h : o.firstCyclePx ≤ o.laterCyclePx) :
    h3Verdict o = .holds := by
  have a' : ¬ o.cyclesSeen < 3 := by omega
  have b' : o.firstCyclePx ≠ 0 := by omega
  simp [h3Verdict, a', b', h]

theorem h3_refuted (o : PixObs) (a : 3 ≤ o.cyclesSeen) (b : 0 < o.firstCyclePx) (h : 2 * o.laterCyclePx < o.firstCyclePx) :
    h3Verdict o = .refuted := by
  have a' : ¬ o.cyclesSeen < 3 := by omega
  have b' : o.firstCyclePx ≠ 0 := by omega
  have c : ¬ o.firstCyclePx ≤ o.laterCyclePx := by omega
  simp [h3Verdict, a', b', c, h]

theorem h4_holds (o : PixObs) (a : 64 * MiB < o.freedBytes) (b : o.freedBytes ≤ 256 * MiB) : h4Verdict o = .holds := by
  have z : o.freedBytes ≠ 0 := by simp only [MiB] at *; omega
  have c : ¬ o.freedBytes ≤ 64 * MiB := by omega
  simp [h4Verdict, z, c, b]

theorem h4_refuted (o : PixObs) (a : 0 < o.freedBytes) (b : o.freedBytes ≤ 64 * MiB) : h4Verdict o = .refuted := by
  have z : o.freedBytes ≠ 0 := by omega
  simp [h4Verdict, z, b]

theorem h4_open (o : PixObs) (h : o.freedBytes = 0 ∨ 256 * MiB < o.freedBytes) : h4Verdict o = .open := by
  rcases h with h | h
  · simp [h4Verdict, h]
  · have z : o.freedBytes ≠ 0 := by simp only [MiB] at *; omega
    have c : ¬ o.freedBytes ≤ 64 * MiB := by simp only [MiB] at *; omega
    have d : ¬ o.freedBytes ≤ 256 * MiB := by omega
    simp [h4Verdict, z, c, d]

theorem h4_holds_realloc (o : PixObs) (a : 64 * MiB < o.freedBytes) (b : o.freedBytes ≤ 256 * MiB) :
    h4Verdict o = .holds ∧ 0 < realloc (poolCap false) o.freedBytes := ⟨h4_holds o a b, (realloc_gap _ a b).1⟩

def cycles : Nat := 6

def legFrames : Nat := 24

def dwellFrames (ms : Nat) : Nat := ms * 60 / 1000

def fingerX : Int := 215
def startY : Int := 700
def stepPx : Int := 14

def topY : Int := startY - stepPx * (legFrames - 1)

def cyclePath (d : Nat) : List (Int × Int) :=
  (List.range legFrames).map (fun (i : Nat) => (fingerX, startY - stepPx * (i : Int)))
  ++ List.replicate d (fingerX, topY)
  ++ (List.range legFrames).map (fun (i : Nat) => (fingerX, topY + stepPx * ((i : Int) + 1)))
  ++ List.replicate d (fingerX, topY + stepPx * legFrames)

def cycleLen (d : Nat) : Nat := 2 * legFrames + 2 * d

theorem cyclePath_length (d : Nat) : (cyclePath d).length = cycleLen d := by
  simp [cyclePath, cycleLen]; omega

structure Stroke where
  f0 : Nat
  path : List (Int × Int)
  deriving Repr, DecidableEq

def strokes (n d : Nat) : List Stroke := (List.range n).map fun i => ⟨i * cycleLen d, cyclePath d⟩

def endFrame (n d : Nat) : Nat := n * cycleLen d

def window (d k : Nat) : Nat × Nat := (k * cycleLen d, (k + 1) * cycleLen d)

theorem strokes_length (n d : Nat) : (strokes n d).length = n := by simp [strokes]

theorem strokes_ordered (n d : Nat) : ∀ k, k + 1 < n →
    ((strokes n d)[k]?.map fun s => s.f0 + s.path.length) = ((strokes n d)[k + 1]?.map fun s => s.f0) := by
  intro k hk
  simp [strokes, cyclePath_length, Nat.succ_mul, hk, Nat.lt_of_succ_lt hk]

theorem cyclePath_in_bounds (d : Nat) : ∀ p ∈ cyclePath d, 0 ≤ p.1 ∧ p.1 ≤ 430 ∧ 0 ≤ p.2 ∧ p.2 ≤ 775 := by
  intro p hp
  simp only [cyclePath, List.mem_append, List.mem_map, List.mem_range, List.mem_replicate] at hp
  simp only [fingerX, startY, stepPx, topY, legFrames] at *
  rcases hp with ((⟨i, hi, rfl⟩ | ⟨_, rfl⟩) | ⟨i, hi, rfl⟩) | ⟨_, rfl⟩ <;> simp <;> omega

theorem window_tiles (d k : Nat) : (window d k).2 = (window d (k + 1)).1 ∧ (window d k).2 - (window d k).1 = cycleLen d := by
  refine ⟨?_, ?_⟩ <;> simp [window, Nat.succ_mul] <;> omega

def tick : Int := 1600

def liftGap : Int := 3200

def phoneSamples (ms : Nat) : List Sample :=
  let dw : Int := ms * 100
  let up := (List.range legFrames).map fun (i : Nat) => (⟨tick * (i : Int), fingerX * 10, (startY - stepPx * (i : Int)) * 10⟩ : Sample)
  let t1 : Int := tick * (legFrames - 1) + dw
  let hold1 : Sample := ⟨t1, fingerX * 10, topY * 10⟩
  let down := (List.range legFrames).map fun (i : Nat) => (⟨t1 + tick * ((i : Int) + 1), fingerX * 10, (topY + stepPx * ((i : Int) + 1)) * 10⟩ : Sample)
  let t2 : Int := t1 + tick * legFrames + dw
  up ++ [hold1] ++ down ++ [⟨t2, fingerX * 10, (topY + stepPx * legFrames) * 10⟩]

def phoneLift (ms : Nat) : Int := tick * (2 * legFrames - 1) + 2 * (ms * 100 : Int) + tick

def phoneSwipe (ms : Nat) : Swipe := ⟨0, phoneSamples ms, phoneLift ms⟩

def phoneProfile (n ms : Nat) : Profile :=
  ⟨s!"push-cycle-{n}x{ms}", 430, 775, .warm, layout liftGap (List.replicate n (phoneSwipe ms))⟩

theorem phone_swipes_length (n ms : Nat) : (phoneProfile n ms).swipes.length = n := by
  simp [phoneProfile, layout, layoutFrom_length]

theorem phone_gaps (n ms : Nat) : gapsOk liftGap (phoneProfile n ms).swipes = true := by
  simp only [phoneProfile, layout]
  exact layoutFrom_gaps liftGap _ 0

theorem phoneSamples_in_bounds (ms : Nat) : ∀ e ∈ phoneSamples ms, 0 ≤ e.x ∧ e.x ≤ 4300 ∧ 0 ≤ e.y ∧ e.y ≤ 7750 := by
  intro e he
  simp only [phoneSamples, List.mem_append, List.mem_map, List.mem_range, List.mem_singleton] at he
  simp only [fingerX, startY, stepPx, topY, legFrames, tick] at *
  rcases he with ((⟨i, hi, rfl⟩ | rfl) | ⟨i, hi, rfl⟩) | rfl <;> simp <;> omega

theorem phoneSamples_head (ms : Nat) : (phoneSamples ms).head? = some ⟨0, fingerX * 10, startY * 10⟩ := by
  simp [phoneSamples, legFrames, List.range_succ_eq_map, tick]

theorem phoneSamples_length (ms : Nat) : (phoneSamples ms).length = 2 * legFrames + 2 := by
  simp [phoneSamples]; omega

/-! Cycle versus clock. A full pass and a dwell pass run the same cycles; they differ in how much time passes between cycles. -/

def sepMinPasses : Nat := 3
def sepFullCycles : Nat := 12
def sepDwellCycles : Nat := 6
def sepWindow : List Nat := [3, 4, 5]

def stretch (dwellMs fullMs : Nat) : Nat := if fullMs = 0 then 0 else dwellMs * 1000 / fullMs

def clockIndex (r k : Nat) : Nat := (k * r + 500) / 1000

theorem clockIndex_id (k : Nat) : clockIndex 1000 k = k := by
  simp only [clockIndex]; omega

theorem clockIndex_mono (r : Nat) {a b : Nat} (h : a ≤ b) : clockIndex r a ≤ clockIndex r b := by
  simp only [clockIndex]
  exact Nat.div_le_div_right (by have := Nat.mul_le_mul_right r h; omega)

def windowObs (p : List Nat) (idx : Nat → Nat) : List Nat := sepWindow.filterMap fun k => p[idx k]?

def windowOf (ps : List (List Nat)) (idx : Nat → Nat) : List Nat := ps.flatMap fun p => windowObs p idx

def rate (xs : List Nat) : Nat := xs.sum * 1000 / xs.length

def absDiff (a b : Nat) : Nat := if a ≤ b then b - a else a - b

def separable (i c : Nat) : Bool := 0 < max i c && max i c ≤ 2 * absDiff i c

inductive Why where
  | fewFull | fewDwell | noPeriod | noRoom | noObs | inseparable | between
  deriving DecidableEq, Repr

def Why.name : Why → String
  | .fewFull => "fewFull" | .fewDwell => "fewDwell" | .noPeriod => "noPeriod" | .noRoom => "noRoom"
  | .noObs => "noObs" | .inseparable => "inseparable" | .between => "between"

inductive Sep where
  | cycleDriven | clockDriven | undecided (w : Why)
  deriving DecidableEq, Repr

def Sep.name : Sep → String
  | .cycleDriven => "cycleDriven" | .clockDriven => "clockDriven" | .undecided w => "undecided:" ++ w.name

def pick (i c d : Nat) : Sep :=
  if !separable i c then .undecided .inseparable
  else if 3 * absDiff d i ≤ absDiff d c then .cycleDriven
  else if 3 * absDiff d c ≤ absDiff d i then .clockDriven
  else .undecided .between

structure SepIn where
  full : List (List Nat)
  dwell : List (List Nat)
  periodFull : Nat
  periodDwell : Nat
  deriving Repr

def SepIn.r (s : SepIn) : Nat := stretch s.periodDwell s.periodFull

def sepVerdict (s : SepIn) : Sep :=
  let idxW := windowOf s.full id
  let clkW := windowOf s.full (clockIndex s.r)
  let dwW := windowOf s.dwell id
  if s.full.length < sepMinPasses then .undecided .fewFull
  else if s.dwell.length < sepMinPasses then .undecided .fewDwell
  else if s.periodFull = 0 || s.periodDwell = 0 then .undecided .noPeriod
  else if sepFullCycles ≤ clockIndex s.r 5 then .undecided .noRoom
  else if idxW.isEmpty || clkW.isEmpty || dwW.isEmpty then .undecided .noObs
  else pick (rate idxW) (rate clkW) (rate dwW)

theorem sep_fewFull (s : SepIn) (h : s.full.length < sepMinPasses) : sepVerdict s = .undecided .fewFull := by
  simp [sepVerdict, h]

theorem sep_fewDwell (s : SepIn) (h0 : ¬ s.full.length < sepMinPasses) (h : s.dwell.length < sepMinPasses) :
    sepVerdict s = .undecided .fewDwell := by
  simp [sepVerdict, h0, h]

theorem sep_noPeriod_full (s : SepIn) (h0 : ¬ s.full.length < sepMinPasses) (h1 : ¬ s.dwell.length < sepMinPasses)
    (h : s.periodFull = 0) : sepVerdict s = .undecided .noPeriod := by
  simp [sepVerdict, h0, h1, h]

theorem sep_noPeriod_dwell (s : SepIn) (h0 : ¬ s.full.length < sepMinPasses) (h1 : ¬ s.dwell.length < sepMinPasses)
    (h : s.periodDwell = 0) : sepVerdict s = .undecided .noPeriod := by
  simp [sepVerdict, h0, h1, h]

theorem sep_noRoom (s : SepIn) (h0 : ¬ s.full.length < sepMinPasses) (h1 : ¬ s.dwell.length < sepMinPasses)
    (h2 : s.periodFull ≠ 0) (h3 : s.periodDwell ≠ 0) (h : sepFullCycles ≤ clockIndex s.r 5) :
    sepVerdict s = .undecided .noRoom := by
  simp [sepVerdict, h0, h1, h2, h3, h]

theorem sep_noObs (s : SepIn) (h0 : ¬ s.full.length < sepMinPasses) (h1 : ¬ s.dwell.length < sepMinPasses)
    (h2 : s.periodFull ≠ 0) (h3 : s.periodDwell ≠ 0) (h4 : ¬ sepFullCycles ≤ clockIndex s.r 5)
    (h : (windowOf s.full id).isEmpty = true ∨ (windowOf s.full (clockIndex s.r)).isEmpty = true ∨ (windowOf s.dwell id).isEmpty = true) :
    sepVerdict s = .undecided .noObs := by
  rcases h with h | h | h <;> simp [sepVerdict, h0, h1, h2, h3, h4, h]

theorem sep_inseparable (s : SepIn) (h0 : ¬ s.full.length < sepMinPasses) (h1 : ¬ s.dwell.length < sepMinPasses)
    (h2 : s.periodFull ≠ 0) (h3 : s.periodDwell ≠ 0) (h4 : ¬ sepFullCycles ≤ clockIndex s.r 5)
    (h5 : (windowOf s.full id).isEmpty = false) (h6 : (windowOf s.full (clockIndex s.r)).isEmpty = false)
    (h7 : (windowOf s.dwell id).isEmpty = false)
    (h : separable (rate (windowOf s.full id)) (rate (windowOf s.full (clockIndex s.r))) = false) :
    sepVerdict s = .undecided .inseparable := by
  simp [sepVerdict, h0, h1, h2, h3, h4, h5, h6, h7, pick, h]

theorem sep_pick (s : SepIn) (h0 : ¬ s.full.length < sepMinPasses) (h1 : ¬ s.dwell.length < sepMinPasses)
    (h2 : s.periodFull ≠ 0) (h3 : s.periodDwell ≠ 0) (h4 : ¬ sepFullCycles ≤ clockIndex s.r 5)
    (h5 : (windowOf s.full id).isEmpty = false) (h6 : (windowOf s.full (clockIndex s.r)).isEmpty = false)
    (h7 : (windowOf s.dwell id).isEmpty = false) :
    sepVerdict s = pick (rate (windowOf s.full id)) (rate (windowOf s.full (clockIndex s.r))) (rate (windowOf s.dwell id)) := by
  simp [sepVerdict, h0, h1, h2, h3, h4, h5, h6, h7]

theorem pick_cycle (i c : Nat) (h : separable i c = true) : pick i c i = .cycleDriven := by
  simp [pick, h, absDiff]

theorem pick_clock (i c : Nat) (h : separable i c = true) : pick i c c = .clockDriven := by
  have h' : 0 < max i c ∧ max i c ≤ 2 * absDiff i c := by simpa [separable] using h
  have hd : 0 < absDiff c i := by
    obtain ⟨a, b⟩ := h'
    simp only [absDiff] at b ⊢
    split at b <;> split <;> omega
  simp [pick, h, absDiff] at hd ⊢
  split <;> split at hd <;> omega

theorem pick_between (i c d : Nat) (h : separable i c = true) (a : 3 * absDiff d i > absDiff d c) (b : 3 * absDiff d c > absDiff d i) :
    pick i c d = .undecided .between := by
  have n1 : ¬ 3 * absDiff d i ≤ absDiff d c := by omega
  have n2 : ¬ 3 * absDiff d c ≤ absDiff d i := by omega
  simp [pick, h, n1, n2]

theorem pick_exclusive (i c d : Nat) (h : separable i c = true) :
    ¬ (3 * absDiff d i ≤ absDiff d c ∧ 3 * absDiff d c ≤ absDiff d i) := by
  have h' : 0 < max i c ∧ max i c ≤ 2 * absDiff i c := by simpa [separable] using h
  simp only [absDiff] at *
  split at h' <;> split <;> split <;> omega

theorem filterMap_getElem (p : List Nat) (idx : Nat → Nat) (ks : List Nat) (h : ∀ k ∈ ks, idx k < p.length) :
    ks.filterMap (fun k => p[idx k]?) = ks.map (fun k => p.getD (idx k) 0) := by
  induction ks with
  | nil => rfl
  | cons k rest ih =>
    have hk := h k (by simp)
    have hr := ih (fun j hj => h j (by simp [hj]))
    simp [hr, List.getD_eq_getElem?_getD, List.getElem?_eq_getElem hk]

theorem windowObs_eq_map (p : List Nat) (idx : Nat → Nat) (h : ∀ k ∈ sepWindow, idx k < p.length) :
    windowObs p idx = sepWindow.map (fun k => p.getD (idx k) 0) :=
  filterMap_getElem p idx sepWindow h

theorem windowOf_ne_nil (ps : List (List Nat)) (idx : Nat → Nat) (hne : ps ≠ [])
    (h : ∀ p ∈ ps, ∀ k ∈ sepWindow, idx k < p.length) : (windowOf ps idx).isEmpty = false := by
  cases ps with
  | nil => exact absurd rfl hne
  | cons p rest =>
    have := windowObs_eq_map p idx (h p (by simp))
    simp [windowOf, List.flatMap_cons, this, sepWindow]

theorem windowOf_map (ps : List (List Nat)) (idx jdx : Nat → Nat) (f : List Nat → List Nat)
    (h : ∀ p ∈ ps, windowObs (f p) idx = windowObs p jdx) :
    windowOf (ps.map f) idx = windowOf ps jdx := by
  induction ps with
  | nil => rfl
  | cons p rest ih =>
    have h1 := h p (by simp)
    have h2 := ih (fun q hq => h q (by simp [hq]))
    simp only [windowOf, List.map_cons, List.flatMap_cons] at h2 ⊢
    rw [h1, h2]

theorem pure_cycle_window (s : SepIn) (hm : s.dwell = s.full.map (fun p => p.take sepDwellCycles))
    (hl : ∀ p ∈ s.full, sepDwellCycles ≤ p.length) :
    windowOf s.dwell id = windowOf s.full id := by
  rw [hm]
  apply windowOf_map
  intro p hp
  have hlen := hl p hp
  have e1 := windowObs_eq_map (p.take sepDwellCycles) id (by
    intro k hk; simp only [sepWindow, List.mem_cons, List.not_mem_nil, or_false] at hk
    simp only [sepDwellCycles, List.length_take, id] at hlen ⊢; omega)
  have e2 := windowObs_eq_map p id (by
    intro k hk; simp only [sepWindow, List.mem_cons, List.not_mem_nil, or_false] at hk
    simp only [sepDwellCycles, id] at hlen ⊢; omega)
  rw [e1, e2]
  apply List.map_congr_left
  intro k hk
  simp only [sepWindow, List.mem_cons, List.not_mem_nil, or_false] at hk
  simp only [id, List.getD_eq_getElem?_getD, List.getElem?_take, sepDwellCycles]
  split <;> first | rfl | omega


def clockDwell (r : Nat) (p : List Nat) : List Nat :=
  (List.range sepDwellCycles).map fun k => p.getD (clockIndex r k) 0

theorem pure_clock_window (s : SepIn) (hm : s.dwell = s.full.map (clockDwell s.r))
    (hl : ∀ p ∈ s.full, clockIndex s.r 5 < p.length) :
    windowOf s.dwell id = windowOf s.full (clockIndex s.r) := by
  rw [hm]
  apply windowOf_map
  intro p hp
  have hlen := hl p hp
  have hmono : ∀ k ∈ sepWindow, clockIndex s.r k < p.length := by
    intro k hk
    simp only [sepWindow, List.mem_cons, List.not_mem_nil, or_false] at hk
    have := clockIndex_mono s.r (show k ≤ 5 by omega)
    omega
  have e1 := windowObs_eq_map (clockDwell s.r p) id (by
    intro k hk; simp only [sepWindow, List.mem_cons, List.not_mem_nil, or_false] at hk
    simp [clockDwell, sepDwellCycles]; omega)
  rw [e1, windowObs_eq_map p _ hmono]
  apply List.map_congr_left
  intro k hk
  simp only [sepWindow, List.mem_cons, List.not_mem_nil, or_false] at hk
  have : k < sepDwellCycles := by simp only [sepDwellCycles]; omega
  simp [clockDwell, this]

/-- Cycle-driven: every dwell pass shows what its own first six cycles showed in the full pass. -/
theorem pure_cycle (s : SepIn) (hm : s.dwell = s.full.map (fun p => p.take sepDwellCycles))
    (hl : ∀ p ∈ s.full, sepDwellCycles ≤ p.length)
    (h0 : ¬ s.full.length < sepMinPasses) (h1 : ¬ s.dwell.length < sepMinPasses)
    (h2 : s.periodFull ≠ 0) (h3 : s.periodDwell ≠ 0) (h4 : ¬ sepFullCycles ≤ clockIndex s.r 5)
    (h5 : (windowOf s.full id).isEmpty = false) (h6 : (windowOf s.full (clockIndex s.r)).isEmpty = false)
    (h7 : (windowOf s.dwell id).isEmpty = false)
    (hs : separable (rate (windowOf s.full id)) (rate (windowOf s.full (clockIndex s.r))) = true) :
    sepVerdict s = .cycleDriven := by
  rw [sep_pick s h0 h1 h2 h3 h4 h5 h6 h7, pure_cycle_window s hm hl]
  exact pick_cycle _ _ hs

/-- Clock-driven: every dwell pass shows what the full pass showed at the same elapsed time. -/
theorem pure_clock (s : SepIn) (hm : s.dwell = s.full.map (clockDwell s.r))
    (hl : ∀ p ∈ s.full, clockIndex s.r 5 < p.length)
    (h0 : ¬ s.full.length < sepMinPasses) (h1 : ¬ s.dwell.length < sepMinPasses)
    (h2 : s.periodFull ≠ 0) (h3 : s.periodDwell ≠ 0) (h4 : ¬ sepFullCycles ≤ clockIndex s.r 5)
    (h5 : (windowOf s.full id).isEmpty = false) (h6 : (windowOf s.full (clockIndex s.r)).isEmpty = false)
    (h7 : (windowOf s.dwell id).isEmpty = false)
    (hs : separable (rate (windowOf s.full id)) (rate (windowOf s.full (clockIndex s.r))) = true) :
    sepVerdict s = .clockDriven := by
  rw [sep_pick s h0 h1 h2 h3 h4 h5 h6 h7, pure_clock_window s hm hl]
  exact pick_clock _ _ hs


/-! Census reading: one trend per pass, then the passes are compared, never pooled. -/

inductive Across where
  | few | yes | no | mixed
  deriving DecidableEq, Repr

def Across.name : Across → String
  | .few => "few" | .yes => "yes" | .no => "no" | .mixed => "mixed"

def across (ts : List Trend) : Across :=
  if ts.length < sepMinPasses then .few
  else if ts.all (· == Trend.rises) then .yes
  else if ts.all (· != Trend.rises) then .no
  else .mixed

def readCensus (passes : List (List Nat)) : Across := across (passes.map trend)

theorem across_few (ts : List Trend) (h : ts.length < sepMinPasses) : across ts = .few := by
  simp [across, h]

theorem across_yes (ts : List Trend) (h0 : ¬ ts.length < sepMinPasses) (h : ∀ t ∈ ts, t = Trend.rises) :
    across ts = .yes := by
  have : ts.all (· == Trend.rises) = true := by simpa using h
  simp [across, h0, this]

theorem across_no (ts : List Trend) (h0 : ¬ ts.length < sepMinPasses) (h : ∀ t ∈ ts, t ≠ Trend.rises) :
    across ts = .no := by
  have h1 : ¬ ts.all (· == Trend.rises) = true := by
    intro hh
    have : ts ≠ [] := by intro e; simp [e, sepMinPasses] at h0
    obtain ⟨t, ht⟩ := List.exists_mem_of_ne_nil ts this
    have := (List.all_eq_true.mp hh) t ht
    exact h t ht (by simpa using this)
  have h2 : ts.all (· != Trend.rises) = true := by simpa using h
  simp [across, h0, h1, h2]

theorem across_mixed (ts : List Trend) (h0 : ¬ ts.length < sepMinPasses) (a : ∃ t ∈ ts, t = Trend.rises)
    (b : ∃ t ∈ ts, t ≠ Trend.rises) : across ts = .mixed := by
  obtain ⟨t1, m1, e1⟩ := a
  obtain ⟨t2, m2, e2⟩ := b
  have h1 : ¬ ts.all (· == Trend.rises) = true := by
    intro hh
    have := (List.all_eq_true.mp hh) t2 m2
    exact e2 (by simpa using this)
  have h2 : ¬ ts.all (· != Trend.rises) = true := by
    intro hh
    have := (List.all_eq_true.mp hh) t1 m1
    simp [e1] at this
  simp [across, h0, h1, h2]

theorem trend_replicate (n x : Nat) : trend (List.replicate (n + 1) x) = .flat := by
  have e : (List.replicate (n + 1) x) = x :: List.replicate n x := rfl
  rw [e]
  simp only [trend, List.length_replicate, sum_replicate_eq]
  have : 6 * n * x = 6 * (n * x) := Nat.mul_assoc 6 n x
  have h2 : 5 * n * x = 5 * (n * x) := Nat.mul_assoc 5 n x
  have n1 : ¬ 6 * (n * x) < 5 * (n * x) := by omega
  simp [this, h2, n1]

/-- A pool that holds the same number of bytes after every cycle never reads as growth. -/
theorem across_constant (passes : List (List Nat)) (h0 : ¬ passes.length < sepMinPasses)
    (h : ∀ p ∈ passes, ∃ n x, p = List.replicate (n + 1) x) : readCensus passes = .no := by
  unfold readCensus
  apply across_no
  · simpa using h0
  · intro t ht
    obtain ⟨p, hp, rfl⟩ := List.mem_map.mp ht
    obtain ⟨n, x, rfl⟩ := h p hp
    rw [trend_replicate]; intro e; cases e

/-- The rest after one dwell-pass cycle: what is left of the target period once the cycle and its census took their time, at most `cap`. -/
def restMs (target spent cap : Nat) : Nat := min (target - spent) cap

theorem rest_le_cap (target spent cap : Nat) : restMs target spent cap ≤ cap := by
  simp only [restMs]; omega

theorem rest_late (target spent cap : Nat) (h : target ≤ spent) : restMs target spent cap = 0 := by
  simp only [restMs]; omega

theorem rest_fills (target spent cap : Nat) (h : spent ≤ target) (hc : target - spent ≤ cap) :
    spent + restMs target spent cap = target := by
  simp only [restMs]; omega

theorem rest_capped (target spent cap : Nat) (h : cap < target - spent) : restMs target spent cap = cap := by
  simp only [restMs]; omega

private def pairJ (p : Int × Int) : Json := toJson [p.1, p.2]

private def sampleJ (e : Sample) : Json := toJson [e.t, e.x, e.y]

private def swipeJ (s : Swipe) : Json :=
  Json.mkObj [("start", s.start), ("lift", s.lift), ("s", Json.arr (s.samples.map sampleJ).toArray)]

private def profileJ (p : Profile) : Json :=
  Json.mkObj [("id", p.id), ("w", p.w), ("h", p.h), ("load", match p.load with | .warm => "warm" | .cold => "cold"),
    ("swipes", Json.arr (p.swipes.map swipeJ).toArray)]

private def costJ (c : Cost) : Json :=
  Json.mkObj [("first", c.first), ("promo", c.promo), ("run", c.run), ("close", c.close), ("toolbar", c.toolbar)]

def costCases : List (String × Cost) :=
  [("promo-heavy", ⟨20, 60, 100, 10, 5⟩), ("first-heavy", ⟨90, 10, 100, 20, 10⟩), ("no-promo", ⟨30, 0, 100, 10, 5⟩),
   ("toolbar-heavy", ⟨10, 20, 50, 5, 80⟩)]

def h1Cases : List (String × H1Obs) :=
  [("few-changes", ⟨2, 9, 20, 3, 400⟩), ("few-slow", ⟨8, 2, 20, 1, 400⟩), ("no-near", ⟨8, 6, 0, 3, 400⟩),
   ("near-twice", ⟨8, 6, 20, 6, 400⟩), ("near-equal", ⟨8, 1, 20, 20, 400⟩), ("near-below-twice", ⟨8, 5, 20, 20, 400⟩)]

def h2Cases : List (String × H2Obs) :=
  [("no-first", ⟨0, 0, 5, 9⟩), ("one-later", ⟨2, 3, 1, 9⟩), ("rises", ⟨2, 3, 5, 15⟩), ("same", ⟨2, 4, 5, 10⟩), ("falls", ⟨2, 4, 5, 6⟩)]

def pixCases : List (String × PixObs) :=
  [("few-cycles", ⟨2, 900, 900, 90000000⟩), ("repeats", ⟨6, 900, 900, 90000000⟩), ("half", ⟨6, 900, 400, 60000000⟩),
   ("between", ⟨6, 900, 600, 90000000⟩), ("nothing", ⟨6, 0, 0, 0⟩), ("huge", ⟨6, 900, 900, 300000000⟩)]

def trendCases : List (List Nat) :=
  [[], [5], [3, 3, 3, 3], [3, 4, 4, 4], [3, 5, 6, 7], [10, 5, 5, 5], [0, 0, 0], [0, 2, 3], [6, 7, 7, 8]]

def dwellCases : List Nat := [300, 1000]

def sepRise : List Nat := [0, 0, 0, 2, 3, 4, 6, 8, 9, 10, 10, 10]

def sepFull3 : List (List Nat) := [sepRise, sepRise, sepRise]

def sepNoisy : List (List Nat) :=
  [sepRise, [0, 1, 0, 2, 4, 4, 7, 9, 9, 10, 11, 10], [1, 0, 0, 3, 3, 5, 6, 7, 9, 9, 10, 10]]

def sepCases : List (String × SepIn) :=
  [("cycle", ⟨sepFull3, sepFull3.map (fun p => p.take sepDwellCycles), 30000, 60000⟩),
   ("clock", ⟨sepFull3, sepFull3.map (clockDwell (stretch 60000 30000)), 30000, 60000⟩),
   ("cycle-noisy", ⟨sepNoisy, sepNoisy.map (fun p => p.take sepDwellCycles), 30000, 60000⟩),
   ("clock-noisy", ⟨sepNoisy, sepNoisy.map (clockDwell (stretch 60000 30000)), 30000, 60000⟩),
   ("between", ⟨sepFull3, [[0, 0, 0, 5, 6, 6], [0, 0, 0, 5, 6, 6], [0, 0, 0, 5, 6, 6]], 30000, 60000⟩),
   ("flat", ⟨[List.replicate 12 4, List.replicate 12 4, List.replicate 12 4], [List.replicate 6 4, List.replicate 6 4, List.replicate 6 4], 30000, 60000⟩),
   ("few-full", ⟨[sepRise, sepRise], sepFull3.map (fun p => p.take sepDwellCycles), 30000, 60000⟩),
   ("few-dwell", ⟨sepFull3, [[0, 0, 0, 2, 3, 4], [0, 0, 0, 2, 3, 4]], 30000, 60000⟩),
   ("no-period-full", ⟨sepFull3, sepFull3.map (fun p => p.take sepDwellCycles), 0, 60000⟩),
   ("no-period-dwell", ⟨sepFull3, sepFull3.map (fun p => p.take sepDwellCycles), 30000, 0⟩),
   ("no-room", ⟨sepFull3, sepFull3.map (fun p => p.take sepDwellCycles), 10000, 60000⟩),
   ("no-obs", ⟨[[1, 2], [1, 2], [1, 2]], [[1, 2], [1, 2], [1, 2]], 30000, 30000⟩)]

def restCases : List (Nat × Nat × Nat) :=
  [(200000, 90000, 120000), (200000, 250000, 120000), (200000, 20000, 120000), (200000, 80000, 120000), (0, 0, 0)]

def clockRs : List Nat := [0, 500, 1000, 1500, 2000, 3333]

def censusCases : List (String × List (List Nat)) :=
  [("few", [[1, 2, 3, 4, 5, 6], [1, 2, 3, 4, 5, 6]]),
   ("rise", [[10, 12, 14, 16, 18, 20], [10, 12, 14, 16, 18, 20], [10, 11, 13, 16, 19, 20]]),
   ("flat", [List.replicate 6 5, List.replicate 6 5, List.replicate 6 5]),
   ("mixed", [[10, 12, 14, 16, 18, 20], List.replicate 6 5, [10, 12, 14, 16, 18, 20]]),
   ("fall", [[20, 10, 10, 10, 10, 10], [20, 10, 10, 10, 10, 10], [20, 10, 10, 10, 10, 10]]),
   ("empty", [[], [], []])]

def vJ (v : Verdict) : Json := Json.str v.name

open Lean in
def goldenLines (_ : Unit := ()) : List String :=
  let consts := (Json.mkObj [("op", "constants"), ("cycles", toJson cycles), ("legFrames", toJson legFrames),
    ("throttleMs", toJson throttleMs), ("iosPoolB", toJson (poolCap false)), ("macPoolB", toJson (poolCap true)),
    ("h1MinChanges", toJson h1MinChanges), ("h1MinSlow", toJson h1MinSlow), ("tick", toJson tick), ("liftGap", toJson liftGap),
    ("fingerX", toJson fingerX), ("startY", toJson startY), ("topY", toJson topY), ("sepMinPasses", toJson sepMinPasses),
    ("sepFullCycles", toJson sepFullCycles), ("sepDwellCycles", toJson sepDwellCycles), ("sepWindow", toJson sepWindow)]).compress
  let model := costCases.map fun (name, c) =>
    (Json.mkObj [("op", "model"), ("case", Json.str name), ("cost", costJ c), ("single", toJson c.single),
      ("released", toJson (series c false cycles)), ("kept", toJson (series c true cycles)),
      ("totalReleased", toJson (totalWork c false cycles)), ("totalKept", toJson (totalWork c true cycles)),
      ("trendReleased", Json.str (trend (series c false cycles)).name), ("trendKept", Json.str (trend (series c true cycles)).name)]).compress
  let repaint := [(100, 6), (2500, 2), (0, 5)].map fun (a, n) =>
    (Json.mkObj [("op", "repaint"), ("area", toJson a), ("n", toJson n), ("released", toJson (reattachPaint a (cycleFlags n))),
      ("kept", toJson (reattachPaint a (false :: true :: List.replicate n true))),
      ("px3", toJson (cyclePx 3 a n)), ("px2", toJson (cyclePx 2 a n))]).compress
  let pool := [0, 50 * MiB, 64 * MiB, 90000000, 106000000, 256 * MiB, 300 * MiB].map fun r =>
    (Json.mkObj [("op", "pool"), ("released", toJson r), ("ios", toJson (realloc (poolCap false) r)),
      ("mac", toJson (realloc (poolCap true) r))]).compress
  let upd := [0, 99, 100, 250, 1000].map fun s =>
    (Json.mkObj [("op", "updates"), ("spanMs", toJson s), ("updates", toJson (updatesIn s))]).compress
  let h1 := h1Cases.map fun (name, o) =>
    (Json.mkObj [("op", "h1"), ("case", Json.str name), ("changes", toJson o.changes), ("slowNear", toJson o.slowNear),
      ("framesNear", toJson o.framesNear), ("slowFar", toJson o.slowFar), ("framesFar", toJson o.framesFar),
      ("verdict", vJ (h1Verdict o))]).compress
  let h2 := h2Cases.map fun (name, o) =>
    (Json.mkObj [("op", "h2"), ("case", Json.str name), ("stretchesFirst", toJson o.stretchesFirst),
      ("fightsFirst", toJson o.fightsFirst), ("stretchesLater", toJson o.stretchesLater), ("fightsLater", toJson o.fightsLater),
      ("verdict", vJ (h2Verdict o))]).compress
  let pix := pixCases.map fun (name, o) =>
    (Json.mkObj [("op", "pix"), ("case", Json.str name), ("cyclesSeen", toJson o.cyclesSeen),
      ("firstCyclePx", toJson o.firstCyclePx), ("laterCyclePx", toJson o.laterCyclePx), ("freedBytes", toJson o.freedBytes),
      ("h3", vJ (h3Verdict o)), ("h4", vJ (h4Verdict o))]).compress
  let tr := trendCases.map fun xs =>
    (Json.mkObj [("op", "trend"), ("series", toJson xs), ("trend", Json.str (trend xs).name)]).compress
  let plan := dwellCases.map fun ms =>
    let d := dwellFrames ms
    (Json.mkObj [("op", "plan"), ("dwellMs", toJson ms), ("dwellFrames", toJson d), ("n", toJson cycles),
      ("cycleLen", toJson (cycleLen d)), ("endFrame", toJson (endFrame cycles d)),
      ("windows", Json.arr ((List.range cycles).map fun k => toJson [(window d k).1, (window d k).2]).toArray),
      ("strokes", Json.arr ((strokes cycles d).map fun s =>
        Json.mkObj [("f0", toJson s.f0), ("path", Json.arr (s.path.map pairJ).toArray)]).toArray)]).compress
  let phone := dwellCases.map fun ms =>
    (Json.mkObj [("op", "phone"), ("dwellMs", toJson ms), ("profile", profileJ (phoneProfile cycles ms))]).compress
  let sepOps := sepCases.map fun (name, s) =>
    (Json.mkObj [("op", "sep"), ("case", Json.str name), ("full", toJson s.full), ("dwell", toJson s.dwell),
      ("periodFull", toJson s.periodFull), ("periodDwell", toJson s.periodDwell), ("r", toJson s.r),
      ("idx", toJson (rate (windowOf s.full id))), ("clock", toJson (rate (windowOf s.full (clockIndex s.r)))),
      ("dwellRate", toJson (rate (windowOf s.dwell id))), ("verdict", Json.str (sepVerdict s).name)]).compress
  let clockOps := clockRs.map fun r =>
    (Json.mkObj [("op", "clock"), ("r", toJson r), ("index", toJson ((List.range sepFullCycles).map (clockIndex r)))]).compress
  let censusOps := censusCases.map fun (name, ps) =>
    (Json.mkObj [("op", "census"), ("case", Json.str name), ("passes", toJson ps),
      ("trends", toJson (ps.map fun p => (trend p).name)), ("across", Json.str (readCensus ps).name)]).compress
  let restOps := restCases.map fun (t, s, c) =>
    (Json.mkObj [("op", "rest"), ("target", toJson t), ("spent", toJson s), ("cap", toJson c), ("rest", toJson (restMs t s c))]).compress
  [consts] ++ model ++ repaint ++ pool ++ upd ++ h1 ++ h2 ++ pix ++ tr ++ plan ++ phone ++ sepOps ++ clockOps ++ censusOps ++ restOps

def goldenText (_ : Unit := ()) : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"push-cycle golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"push-cycle golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

#guard dwellFrames 300 == 18 && dwellFrames 1000 == 60
#guard cycleLen 18 == 84 && endFrame 6 18 == 504
#guard (cyclePath 18).length == 84
#guard topY == 378
#guard trend [3, 5, 6, 7] == .rises && trend [10, 5, 5, 5] == .falls && trend [3, 3, 3, 3] == .flat
#guard updatesIn 250 == 3

end Fw.Measure.PushCycle
