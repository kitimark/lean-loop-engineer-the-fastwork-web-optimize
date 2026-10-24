import Lean.Data.Json
import Fw.Device.StillRuns
import Fw.Parts.EngineScrollUnthrottle
/-!
# Which parts WebKit's 100 ms scroll-update throttle reaches
A part shows a value that is a function of the web process's scrollY (main-thread readers), of the compositor's scroll
offset (threaded scroll-driven animations) or of time. While Safari changes the toolbar insets interactively and no
main-thread scroll-driven animation is active, the web process gets one scroll update per 100 ms
(WKWebViewIOS.mm:3256-3268@862f17d); otherwise one per frame. Part premises cite `apps/site/src/parts/` and
`research/notes/2026/10-2x-scroll-throttle-parts.md`.
-/
namespace Fw.Device.ThrottleParts
open Lean Fw.Device.StillRuns
open Fw.Parts.EngineScrollUnthrottle (Page Engine throttledOn lift_effect)

/-! ## The model -/

/-- What a part's shown value is a function of. -/
inductive Source where
  | mainThread | threaded | time
  deriving DecidableEq, Repr

/-- How the web process's scrollY follows the compositor: one update per `p` frames, or one per frame. -/
inductive Mode where
  | throttled | lifted
  deriving DecidableEq, Repr

/-- The frames between two updates 100 ms apart at a frame interval of `d` hundredths of a millisecond. -/
def period (d : Nat) : Nat := throttleK d + 1

/-- The web process's scrollY at frame `t`, from the compositor offset `u`: throttled, the offset of the last update frame
`p * (t / p)`. -/
def seen : Mode → Nat → (Nat → Int) → Nat → Int
  | .throttled, p, u, t => u (p * (t / p))
  | .lifted, _, u, t => u t

/-- The value a part shows at frame `t`: `f` of the web process's scrollY, of the compositor offset, or of the frame. -/
def shown : Source → Mode → Nat → (Nat → Int) → (Int → Int) → Nat → Int
  | .mainThread, m, p, u, f, t => f (seen m p u t)
  | .threaded, _, _, u, f, t => f (u t)
  | .time, _, _, _, f, t => f t

/-- The shown values of the first `N` frames. -/
def series (s : Source) (m : Mode) (p : Nat) (u : Nat → Int) (f : Int → Int) (N : Nat) : List Int :=
  (List.range N).map (shown s m p u f)

/-- A value series as still-run rows: the value is both the position and the in-range test. -/
def rowsOf (vs : List Int) : List (Int × Int) := vs.map fun v => (v, v)

/-- The still runs of the shown value over `N` frames. -/
def stills (s : Source) (m : Mode) (p : Nat) (u : Nat → Int) (f : Int → Int) (N : Nat) : List Run :=
  runs (rowsOf (series s m p u f N))

/-- The still runs of 5 to 6 frames with the shown value strictly between 0 and 1000. -/
def bandStills (s : Source) (m : Mode) (p : Nat) (u : Nat → Int) (f : Int → Int) (N : Nat) : Nat :=
  bandRuns (rowsOf (series s m p u f N))

/-- The shown value differs at every two frames of the pass: a strictly monotone `f` on a pass that moves one way. -/
def Distinct (g : Nat → Int) (N : Nat) : Prop := ∀ i j, i < j → j < N → g i ≠ g j

/-- `f` is strictly increasing or strictly decreasing on the offsets the pass visits. -/
def StrictOn (f : Int → Int) (u : Nat → Int) (N : Nat) : Prop :=
  (∀ i j, i < N → j < N → u i < u j → f (u i) < f (u j)) ∨ (∀ i j, i < N → j < N → u i < u j → f (u j) < f (u i))

/-- The pass moves one way in every frame. -/
def OneWay (u : Nat → Int) (N : Nat) : Prop :=
  (∀ i j, i < j → j < N → u i < u j) ∨ (∀ i j, i < j → j < N → u j < u i)

/-- The mode WebKit uses for an engine, the toolbar inset state and the page (Fw.Parts.EngineScrollUnthrottle). -/
def modeOf (e : Engine) (insets : Bool) (pg : Page) : Mode := if throttledOn e insets pg then .throttled else .lifted

/-! ## Lemmas on still runs -/

/-- `p` frames of each value in turn. -/
def plateaus (p : Nat) (zs : List Int) : List (Int × Int) := zs.flatMap fun z => List.replicate p (z, z)

/-- One run of `k` frames per move between neighbouring values, in range when its value is. -/
def plateauRuns (k : Nat) : List Int → List Run
  | z :: z' :: rest => ⟨k, dist z z', mid z⟩ :: plateauRuns k (z' :: rest)
  | _ => []

theorem moves_cons (a : Int) (l : List Int) :
    moves (a :: l) = ((match l with | [] => true | b :: _ => a != b) && moves l) := by
  cases l with
  | nil => rfl
  | cons b rest => rfl

theorem moves_map_range : ∀ (n : Nat) (g : Nat → Int), (∀ j, j + 1 < n → g j ≠ g (j + 1)) →
    moves ((List.range n).map g) = true
  | 0, _, _ => rfl
  | n + 1, g, h => by
    rw [List.range_succ_eq_map, List.map_cons, List.map_map, moves_cons]
    have ih := moves_map_range n (g ∘ Nat.succ) (fun j hj => h (j + 1) (by omega))
    rw [ih, Bool.and_true]
    cases n with
    | zero => rfl
    | succ m =>
      rw [List.range_succ_eq_map, List.map_cons]
      simpa using h 0 (by omega)

theorem allMove_rowsOf : ∀ l : List Int, allMove (rowsOf l) = moves l
  | [] => rfl
  | [_] => rfl
  | a :: b :: rest => by
    have ih := allMove_rowsOf (b :: rest)
    simp only [rowsOf, List.map_cons] at ih ⊢
    simp only [allMove, moves, ih]

theorem scan_plateaus (q : Nat) : ∀ (zs : List Int) (z : Int), moves (z :: zs) = true →
    scan z 0 true (List.replicate (q + 1) (z, z) ++ plateaus (q + 2) zs) = plateauRuns (q + 1) (z :: zs)
  | [], z, _ => by simp [plateaus, plateauRuns, scan_const]
  | z' :: rest, z, h => by
    simp only [moves, Bool.and_eq_true, bne_iff_ne, ne_eq] at h
    have ih := scan_plateaus q rest z' h.2
    have e : plateaus (q + 2) (z' :: rest) = (z', z') :: (List.replicate (q + 1) (z', z') ++ plateaus (q + 2) rest) := by
      simp [plateaus, List.replicate_succ]
    rw [e, scan_plateau]
    rw [scan_move _ _ _ _ _ _ (by omega) (Ne.symm h.1), ih]
    simp [plateauRuns]

theorem runs_plateaus (q : Nat) (z : Int) (zs : List Int) (h : moves (z :: zs) = true) :
    runs (plateaus (q + 2) (z :: zs)) = plateauRuns (q + 1) (z :: zs) := by
  have e : plateaus (q + 2) (z :: zs) = (z, z) :: (List.replicate (q + 1) (z, z) ++ plateaus (q + 2) zs) := by
    simp [plateaus, List.replicate_succ]
  rw [e]
  exact scan_plateaus q zs z h

theorem plateauRuns_k (k : Nat) : ∀ zs : List Int, (plateauRuns k zs).map (·.k) = List.replicate (zs.length - 1) k
  | [] => rfl
  | [_] => rfl
  | z :: z' :: rest => by
    have ih := plateauRuns_k k (z' :: rest)
    simp only [plateauRuns, List.map_cons, ih, List.length_cons]
    simp [List.replicate_succ]

theorem plateauRuns_band (lo hi k : Nat) (hl : lo ≤ k) (hh : k ≤ hi) :
    ∀ zs : List Int, (∀ z ∈ zs, mid z = true) → ((plateauRuns k zs).filter (inBand lo hi)).length = zs.length - 1
  | [], _ => rfl
  | [_], _ => rfl
  | z :: z' :: rest, hm => by
    have ih := plateauRuns_band lo hi k hl hh (z' :: rest) (fun x hx => hm x (List.mem_cons_of_mem _ hx))
    have hb : inBand lo hi ⟨k, dist z z', mid z⟩ = true := by
      simp [inBand, hm z (by simp), hl, hh]
    simp only [plateauRuns, List.filter_cons, hb, ite_true, List.length_cons] at ih ⊢
    omega

/-- Throttled, the main-thread series over `p * n` frames is `p` frames of each update's value. -/
theorem series_throttled (p : Nat) (hp : 0 < p) (u : Nat → Int) (f : Int → Int) : ∀ n : Nat,
    rowsOf (series .mainThread .throttled p u f (p * n)) = plateaus p ((List.range n).map fun j => f (u (p * j)))
  | 0 => by simp [series, rowsOf, plateaus]
  | n + 1 => by
    have ih := series_throttled p hp u f n
    have blk : (List.range p).map (fun i => shown .mainThread .throttled p u f (p * n + i)) =
        List.replicate p (f (u (p * n))) := by
      rw [List.eq_replicate_iff]
      refine ⟨by simp, ?_⟩
      intro b hb
      simp only [List.mem_map, List.mem_range] at hb
      obtain ⟨i, hi, rfl⟩ := hb
      have : (p * n + i) / p = n := by
        rw [Nat.add_comm, Nat.add_mul_div_left _ _ hp, Nat.div_eq_of_lt hi, Nat.zero_add]
      simp [shown, seen, this]
    rw [Nat.mul_succ, series, List.range_add, List.map_append, List.map_map]
    simp only [rowsOf, series] at ih ⊢
    rw [List.map_append, ih]
    simp only [Function.comp_def]
    rw [blk, List.range_succ, List.map_append, plateaus, plateaus, List.flatMap_append]
    simp [List.map_replicate]

/-! ## Main-thread readers -/

/-- **Throttled, a main-thread reader is a pure delay.** Its value at frame `t` is the value it would show lifted at the last
update frame, which is at most `p - 1` frames earlier. -/
theorem throttled_delay (p : Nat) (hp : 0 < p) (u : Nat → Int) (f : Int → Int) (t : Nat) :
    shown .mainThread .throttled p u f t = shown .mainThread .lifted p u f (p * (t / p)) ∧
      p * (t / p) ≤ t ∧ t - p * (t / p) < p := by
  have h1 := Nat.div_add_mod t p
  have h2 := Nat.mod_lt t hp
  refine ⟨rfl, by omega, by omega⟩

/-- A pass that moves one way and an `f` strictly monotone on its offsets give a shown value that differs at every two frames. -/
theorem distinct_of_strict {f : Int → Int} {u : Nat → Int} {N : Nat} (hu : OneWay u N) (hf : StrictOn f u N) :
    Distinct (fun t => f (u t)) N := by
  intro i j hij hj heq
  have hi : i < N := by omega
  rcases hu with hu | hu <;> rcases hf with hf | hf
  · have := hf i j hi hj (hu i j hij hj); simp only at heq; omega
  · have := hf i j hi hj (hu i j hij hj); simp only at heq; omega
  · have := hf j i hj hi (hu i j hij hj); simp only at heq; omega
  · have := hf j i hj hi (hu i j hij hj); simp only at heq; omega

/-- **Throttled, a monotone main-thread reader stands still for `p - 1` frames per update.** Over `p * n` frames of a pass
whose shown value never repeats it has `n - 1` still runs, each `p - 1` frames long. -/
theorem curve_throttled (q n : Nat) (u : Nat → Int) (f : Int → Int) (h : Distinct (fun t => f (u t)) ((q + 2) * n)) :
    (stills .mainThread .throttled (q + 2) u f ((q + 2) * n)).map (·.k) = List.replicate (n - 1) (q + 1) := by
  unfold stills
  rw [series_throttled (q + 2) (by omega) u f n]
  cases n with
  | zero => rfl
  | succ m =>
    have hm : moves ((List.range (m + 1)).map fun j => f (u ((q + 2) * j))) = true :=
      moves_map_range (m + 1) _ fun j hj => h _ _ (by
        have := Nat.mul_lt_mul_of_pos_left (show j < j + 1 by omega) (show 0 < q + 2 by omega); omega)
        (Nat.mul_lt_mul_of_pos_left hj (by omega))
    rw [List.range_succ_eq_map, List.map_cons] at hm ⊢
    rw [runs_plateaus q _ _ hm, plateauRuns_k]
    simp

/-- With every shown value strictly between 0 and 1000, each of those runs is in the band when `p - 1` is 5 or 6. -/
theorem curve_throttled_band (q n : Nat) (hq1 : 4 ≤ q) (hq2 : q ≤ 5) (u : Nat → Int) (f : Int → Int)
    (h : Distinct (fun t => f (u t)) ((q + 2) * n)) (hmid : ∀ t, t < (q + 2) * n → mid (f (u t)) = true) :
    bandStills .mainThread .throttled (q + 2) u f ((q + 2) * n) = n - 1 := by
  unfold bandStills bandRuns count
  rw [series_throttled (q + 2) (by omega) u f n]
  cases n with
  | zero => rfl
  | succ m =>
    have hm : moves ((List.range (m + 1)).map fun j => f (u ((q + 2) * j))) = true :=
      moves_map_range (m + 1) _ fun j hj => h _ _ (by
        have := Nat.mul_lt_mul_of_pos_left (show j < j + 1 by omega) (show 0 < q + 2 by omega); omega)
        (Nat.mul_lt_mul_of_pos_left hj (by omega))
    have hz : ∀ z ∈ (List.range (m + 1)).map (fun j => f (u ((q + 2) * j))), mid z = true := by
      intro z hz
      simp only [List.mem_map, List.mem_range] at hz
      obtain ⟨j, hj, rfl⟩ := hz
      exact hmid _ (by have := Nat.mul_lt_mul_of_pos_left hj (show 0 < q + 2 by omega); omega)
    have hlen := plateauRuns_band bandLo bandHi (q + 1) (by simp [bandLo]; omega) (by simp [bandHi]; omega) _ hz
    rw [List.range_succ_eq_map, List.map_cons] at hm hlen ⊢
    rw [runs_plateaus q _ _ hm, hlen]
    simp

/-- **Lifted, a monotone main-thread reader never stands still.** -/
theorem curve_lifted (p N : Nat) (u : Nat → Int) (f : Int → Int) (h : Distinct (fun t => f (u t)) N) :
    stills .mainThread .lifted p u f N = [] := by
  unfold stills
  apply runs_moving
  rw [allMove_rowsOf]
  exact moves_map_range N _ fun j hj => h j (j + 1) (by omega) hj

/-- **The throttle at 50 to 70 Hz.** At a frame interval from 14.29 to 19.99 ms, a monotone main-thread reader in its range
shows `n - 1` still runs of `throttleK d` frames each, every one in the 5-to-6 frame band. -/
theorem hit_throttled (d n : Nat) (h1 : 1429 ≤ d) (h2 : d < 2000) (u : Nat → Int) (f : Int → Int)
    (h : Distinct (fun t => f (u t)) (period d * n)) (hmid : ∀ t, t < period d * n → mid (f (u t)) = true) :
    (stills .mainThread .throttled (period d) u f (period d * n)).map (·.k) = List.replicate (n - 1) (throttleK d) ∧
      bandStills .mainThread .throttled (period d) u f (period d * n) = n - 1 := by
  obtain ⟨b1, b2⟩ := throttleK_mem_band d h1 h2
  simp only [bandLo, bandHi] at b1 b2
  have e : period d = (throttleK d - 1) + 2 := by unfold period; omega
  rw [e] at h hmid ⊢
  refine ⟨?_, curve_throttled_band _ n (by omega) (by omega) u f h hmid⟩
  rw [curve_throttled _ n u f h]
  congr 1
  omega

/-- **Harmless: a reader constant on the pass.** Throttled and lifted show the same value in every frame, and neither has a
still run. -/
theorem constant_harmless (p N : Nat) (u : Nat → Int) (f : Int → Int) (c : Int) (h : ∀ t, t < N → f (u t) = c) :
    (∀ t, t < N → shown .mainThread .throttled p u f t = shown .mainThread .lifted p u f t) ∧
      stills .mainThread .throttled p u f N = [] ∧ stills .mainThread .lifted p u f N = [] := by
  have hle : ∀ t, p * (t / p) ≤ t := fun t => Nat.mul_div_le t p
  have const : ∀ m : Mode, series .mainThread m p u f N = List.replicate N c := by
    intro m
    rw [series, List.eq_replicate_iff]
    refine ⟨by simp, ?_⟩
    intro b hb
    simp only [List.mem_map, List.mem_range] at hb
    obtain ⟨t, ht, rfl⟩ := hb
    cases m with
    | throttled => exact h _ (Nat.lt_of_le_of_lt (hle t) ht)
    | lifted => exact h t ht
  refine ⟨fun t ht => ?_, ?_, ?_⟩
  · show f (u (p * (t / p))) = f (u t)
    rw [h _ (Nat.lt_of_le_of_lt (hle t) ht), h t ht]
  · unfold stills; rw [const, rowsOf, List.map_replicate]; exact runs_const c c N
  · unfold stills; rw [const, rowsOf, List.map_replicate]; exact runs_const c c N

/-! ## Threaded and time-based parts -/

/-- **Threaded parts do not see the throttle.** -/
theorem threaded_same (p : Nat) (u : Nat → Int) (f : Int → Int) (t : Nat) :
    shown .threaded .throttled p u f t = shown .threaded .lifted p u f t := rfl

/-- **Time-based parts do not see the throttle.** -/
theorem time_same (p : Nat) (u : Nat → Int) (f : Int → Int) (t : Nat) :
    shown .time .throttled p u f t = shown .time .lifted p u f t := rfl

/-- A threaded part on a pass whose shown value never repeats has no still run in either mode. -/
theorem threaded_no_stills (m : Mode) (p N : Nat) (u : Nat → Int) (f : Int → Int) (h : Distinct (fun t => f (u t)) N) :
    stills .threaded m p u f N = [] := by
  unfold stills
  apply runs_moving
  rw [allMove_rowsOf]
  exact moves_map_range N _ fun j hj => h j (j + 1) (by omega) hj

/-- A time-based part whose value changes every frame has no still run in either mode, whatever the scroll does. -/
theorem time_no_stills (m : Mode) (p N : Nat) (u : Nat → Int) (f : Int → Int) (h : Distinct (fun t => f t) N) :
    stills .time m p u f N = [] := by
  unfold stills
  apply runs_moving
  rw [allMove_rowsOf]
  exact moves_map_range N _ fun j hj => h j (j + 1) (by omega) hj

/-! ## When WebKit throttles -/

/-- The unthrottle flag on a page whose engine supports scroll timelines gives the lifted mode on every engine. -/
theorem mode_withLift (e : Engine) (pg : Page) (hs : pg.timelineSupported = true) :
    modeOf e true pg.withLift = .lifted := by
  simp [modeOf, lift_effect e pg hs]

/-- iOS WebKit, toolbar insets changing and no main-thread scroll-driven animation reported: throttled. -/
theorem mode_baseline (pg : Page) (h : pg.reported = false) : modeOf .webkitIos true pg = .throttled := by
  simp [modeOf, throttledOn, Engine.throttles, Fw.Parts.EngineScrollUnthrottle.throttled, h]

/-- Toolbar insets still: lifted. -/
theorem mode_idle (e : Engine) (pg : Page) : modeOf e false pg = .lifted := by
  simp [modeOf, throttledOn, Fw.Parts.EngineScrollUnthrottle.throttled]

/-- Chromium never throttles. -/
theorem mode_chromium (i : Bool) (pg : Page) : modeOf .chromium i pg = .lifted := by
  simp [modeOf, throttledOn, Engine.throttles]

/-- **engine.scroll:unthrottle removes every main-thread reader's stills.** -/
theorem unthrottle_no_stills (e : Engine) (pg : Page) (hs : pg.timelineSupported = true) (p N : Nat) (u : Nat → Int)
    (f : Int → Int) (h : Distinct (fun t => f (u t)) N) :
    stills .mainThread (modeOf e true pg.withLift) p u f N = [] := by
  rw [mode_withLift e pg hs]
  exact curve_lifted p N u f h

/-- The step count at 120 Hz (8.33 ms frames): 12 frames per update, outside the 5-to-6 band. -/
theorem throttleK_120hz : throttleK 833 = 12 := by decide

end Fw.Device.ThrottleParts
