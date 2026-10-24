import Lean.Data.Json
import Fw.Device.StillRuns
import Fw.Parts.EngineScrollUnthrottle
import Fw.Parts.Commission
/-!
# Which parts WebKit's 100 ms scroll-update throttle reaches
Per-part model and classification for WKWebViewIOS.mm:3256-3268@862f17d and engine.scroll:unthrottle.
-/
namespace Fw.Device.ThrottleParts
open Lean Fw.Device.StillRuns
open Fw.Parts.EngineScrollUnthrottle (Page Engine throttledOn lift_effect)

inductive Source where
  | mainThread | threaded | time
  deriving DecidableEq, Repr

inductive Mode where
  | throttled | lifted
  deriving DecidableEq, Repr

def period (d : Nat) : Nat := throttleK d + 1

def seen : Mode → Nat → (Nat → Int) → Nat → Int
  | .throttled, p, u, t => u (p * (t / p))
  | .lifted, _, u, t => u t

def shown : Source → Mode → Nat → (Nat → Int) → (Int → Int) → Nat → Int
  | .mainThread, m, p, u, f, t => f (seen m p u t)
  | .threaded, _, _, u, f, t => f (u t)
  | .time, _, _, _, f, t => f t

def series (s : Source) (m : Mode) (p : Nat) (u : Nat → Int) (f : Int → Int) (N : Nat) : List Int :=
  (List.range N).map (shown s m p u f)

def rowsOf (vs : List Int) : List (Int × Int) := vs.map fun v => (v, v)

def stills (s : Source) (m : Mode) (p : Nat) (u : Nat → Int) (f : Int → Int) (N : Nat) : List Run :=
  runs (rowsOf (series s m p u f N))

def bandStills (s : Source) (m : Mode) (p : Nat) (u : Nat → Int) (f : Int → Int) (N : Nat) : Nat :=
  bandRuns (rowsOf (series s m p u f N))

def Distinct (g : Nat → Int) (N : Nat) : Prop := ∀ i j, i < j → j < N → g i ≠ g j

def StrictOn (f : Int → Int) (u : Nat → Int) (N : Nat) : Prop :=
  (∀ i j, i < N → j < N → u i < u j → f (u i) < f (u j)) ∨
    (∀ i j, i < N → j < N → u i < u j → f (u j) < f (u i))

def OneWay (u : Nat → Int) (N : Nat) : Prop :=
  (∀ i j, i < j → j < N → u i < u j) ∨ (∀ i j, i < j → j < N → u j < u i)

def modeOf (e : Engine) (insets : Bool) (pg : Page) : Mode := if throttledOn e insets pg then .throttled else .lifted

def plateaus (p : Nat) (zs : List Int) : List (Int × Int) := zs.flatMap fun z => List.replicate p (z, z)

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

theorem throttled_delay (p : Nat) (hp : 0 < p) (u : Nat → Int) (f : Int → Int) (t : Nat) :
    shown .mainThread .throttled p u f t = shown .mainThread .lifted p u f (p * (t / p)) ∧
      p * (t / p) ≤ t ∧ t - p * (t / p) < p := by
  have h1 := Nat.div_add_mod t p
  have h2 := Nat.mod_lt t hp
  refine ⟨rfl, by omega, by omega⟩

theorem distinct_of_strict {f : Int → Int} {u : Nat → Int} {N : Nat} (hu : OneWay u N) (hf : StrictOn f u N) :
    Distinct (fun t => f (u t)) N := by
  intro i j hij hj heq
  have hi : i < N := by omega
  rcases hu with hu | hu <;> rcases hf with hf | hf
  · have := hf i j hi hj (hu i j hij hj); simp only at heq; omega
  · have := hf i j hi hj (hu i j hij hj); simp only at heq; omega
  · have := hf j i hj hi (hu i j hij hj); simp only at heq; omega
  · have := hf j i hj hi (hu i j hij hj); simp only at heq; omega

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

theorem curve_lifted (p N : Nat) (u : Nat → Int) (f : Int → Int) (h : Distinct (fun t => f (u t)) N) :
    stills .mainThread .lifted p u f N = [] := by
  unfold stills
  apply runs_moving
  rw [allMove_rowsOf]
  exact moves_map_range N _ fun j hj => h j (j + 1) (by omega) hj

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

theorem threaded_same (p : Nat) (u : Nat → Int) (f : Int → Int) (t : Nat) :
    shown .threaded .throttled p u f t = shown .threaded .lifted p u f t := rfl

theorem time_same (p : Nat) (u : Nat → Int) (f : Int → Int) (t : Nat) :
    shown .time .throttled p u f t = shown .time .lifted p u f t := rfl

theorem threaded_no_stills (m : Mode) (p N : Nat) (u : Nat → Int) (f : Int → Int) (h : Distinct (fun t => f (u t)) N) :
    stills .threaded m p u f N = [] := by
  unfold stills
  apply runs_moving
  rw [allMove_rowsOf]
  exact moves_map_range N _ fun j hj => h j (j + 1) (by omega) hj

theorem time_no_stills (m : Mode) (p N : Nat) (u : Nat → Int) (f : Int → Int) (h : Distinct (fun t => f t) N) :
    stills .time m p u f N = [] := by
  unfold stills
  apply runs_moving
  rw [allMove_rowsOf]
  exact moves_map_range N _ fun j hj => h j (j + 1) (by omega) hj

theorem mode_withLift (e : Engine) (pg : Page) (hs : pg.timelineSupported = true) :
    modeOf e true pg.withLift = .lifted := by
  simp [modeOf, lift_effect e pg hs]

theorem mode_baseline (pg : Page) (h : pg.reported = false) : modeOf .webkitIos true pg = .throttled := by
  simp [modeOf, throttledOn, Engine.throttles, Fw.Parts.EngineScrollUnthrottle.throttled, h]

theorem mode_idle (e : Engine) (pg : Page) : modeOf e false pg = .lifted := by
  simp [modeOf, throttledOn, Fw.Parts.EngineScrollUnthrottle.throttled]

theorem mode_chromium (i : Bool) (pg : Page) : modeOf .chromium i pg = .lifted := by
  simp [modeOf, throttledOn, Engine.throttles]

theorem unthrottle_no_stills (e : Engine) (pg : Page) (hs : pg.timelineSupported = true) (p N : Nat) (u : Nat → Int)
    (f : Int → Int) (h : Distinct (fun t => f (u t)) N) :
    stills .mainThread (modeOf e true pg.withLift) p u f N = [] := by
  rw [mode_withLift e pg hs]
  exact curve_lifted p N u f h

theorem throttleK_120hz : throttleK 833 = 12 := by decide

inductive Shape where
  | curve
  | chase
  | snap
  | capture
  | stepLook
  | stepIdle
  | constant
  | noRead
  deriving DecidableEq, Repr

inductive Reach where
  | hit | harmless | notHit
  deriving DecidableEq, Repr

def Reach.name : Reach → String
  | .hit => "hit" | .harmless => "harmless" | .notHit => "not-hit"

def reach : Source → Shape → Reach
  | .mainThread, .curve | .mainThread, .chase | .mainThread, .snap | .mainThread, .capture | .mainThread, .stepLook => .hit
  | .mainThread, .stepIdle | .mainThread, .constant => .harmless
  | .mainThread, .noRead => .notHit
  | .threaded, _ => .notHit
  | .time, _ => .notHit

theorem reach_curve : reach .mainThread .curve = .hit := rfl
theorem reach_chase : reach .mainThread .chase = .hit := rfl
theorem reach_snap : reach .mainThread .snap = .hit := rfl
theorem reach_capture : reach .mainThread .capture = .hit := rfl
theorem reach_stepLook : reach .mainThread .stepLook = .hit := rfl
theorem reach_stepIdle : reach .mainThread .stepIdle = .harmless := rfl
theorem reach_constant : reach .mainThread .constant = .harmless := rfl
theorem reach_noRead : reach .mainThread .noRead = .notHit := rfl
theorem reach_threaded (sh : Shape) : reach .threaded sh = .notHit := rfl
theorem reach_time (sh : Shape) : reach .time sh = .notHit := rfl

theorem reach_ne_notHit {s : Source} {sh : Shape} (h : reach s sh ≠ .notHit) : s = .mainThread := by
  cases s <;> cases sh <;> simp_all [reach]

def symptom : Source → Shape → String
  | .mainThread, .curve => "still runs of throttleK frames, one per update"
  | .mainThread, .chase => "the target steps once per update and the eased value pulses after it"
  | .mainThread, .snap => "the target steps once per update and the follower snaps to it on a rising target: still runs of throttleK frames"
  | .mainThread, .capture => "the captured scrollY is up to throttleK frames old and the restore snaps back to it"
  | .mainThread, .stepLook => "the look flips up to throttleK frames late"
  | .mainThread, .stepIdle => "a time-based animation starts or pauses up to throttleK frames late"
  | _, _ => "none"

def basis : Source → Shape → List String
  | .mainThread, .curve => ["hit_throttled", "curve_lifted", "unthrottle_no_stills"]
  | .mainThread, .chase => ["hit_throttled", "curve_lifted"]
  | .mainThread, .snap => ["hit_throttled", "commission_snaps_up", "enterFollow_rising"]
  | .mainThread, .capture | .mainThread, .stepLook => ["throttled_delay"]
  | .mainThread, .stepIdle => ["throttled_delay", "time_same"]
  | .mainThread, .constant => ["constant_harmless"]
  | .mainThread, .noRead => []
  | .threaded, _ => ["threaded_same", "threaded_no_stills"]
  | .time, _ => ["time_same", "time_no_stills"]

def followUp : Source → Shape → Option String
  | .mainThread, .curve => some "threaded-timeline"
  | .mainThread, .capture => some "root-lock"
  | _, _ => none

structure Part where
  id : String
  zone : String
  source : Source
  shape : Shape
  premise : List String
  deriving Repr

private def pp (s : String) : String := "apps/site/src/parts/" ++ s

def parts : List Part :=
  [⟨"hero.exit", "hero", .mainThread, .curve,
     [pp "hero.exit/driver.ts:32", pp "hero.exit/logic.ts:21-24", "apps/site/src/engine/scroll.ts:94-101"]⟩,
   ⟨"hero.exit:threaded", "hero", .threaded, .curve,
     [pp "hero.exit/threaded.module.css:28", pp "hero.exit/threaded.ts:144"]⟩,
   ⟨"hero.accent", "hero", .mainThread, .stepIdle, [pp "hero.accent/index.tsx:84"]⟩,
   ⟨"hero.countdown", "hero", .mainThread, .stepIdle, [pp "hero.countdown/index.tsx:86"]⟩,
   ⟨"hero.cue", "hero", .mainThread, .noRead, [pp "hero.cue/index.tsx:10"]⟩,
   ⟨"nav", "all", .mainThread, .stepLook, [pp "nav/index.tsx:41-42", pp "nav/index.tsx:104", pp "nav/driver.ts:76-78"]⟩,
   ⟨"nav.hitTest", "all", .mainThread, .stepLook, [pp "nav.hitTest/index.tsx:33", pp "nav.hitTest/probe.ts:66"]⟩,
   ⟨"people.card", "rest", .mainThread, .chase,
     [pp "people.card/index.tsx:54-58", pp "people.card/index.tsx:74", pp "people.card/logic.ts:48-51",
      pp "people.card/logic.ts:105-109"]⟩,
   ⟨"people.deck", "rest", .mainThread, .noRead, [pp "people.deck/driver.ts:82", pp "people.deck/driver.ts:116"]⟩,
   ⟨"people.o", "rest", .mainThread, .stepIdle, [pp "people.o/index.tsx:45-47"]⟩,
   ⟨"people.shared", "rest", .mainThread, .stepIdle, [pp "people/shared.ts:31-33"]⟩,
   ⟨"pain.dark", "rest", .threaded, .curve, [pp "pain/darkScroll.ts:6", pp "pain/darkScroll.ts:47-58"]⟩,
   ⟨"pain.notes", "rest", .mainThread, .stepLook,
     [pp "pain.notes/index.tsx:141-143", pp "pain.notes/driver.ts:134-137", pp "pain.notes/driver.ts:214-218"]⟩,
   ⟨"commission", "rest", .mainThread, .snap, [pp "commission/driver.ts:111-125", pp "commission/logic.ts:46-63"]⟩,
   ⟨"engine.scene", "rest", .mainThread, .stepIdle, [pp "engine.scene/observe.ts:18-30"]⟩,
   ⟨"platform.entries", "finish", .mainThread, .stepIdle, [pp "platform.entries/driver.ts:10"]⟩,
   ⟨"platform.visuals", "finish", .mainThread, .stepIdle, [pp "platform/Visuals.tsx:325-333"]⟩,
   ⟨"platform.shrink", "finish", .mainThread, .curve,
     [pp "platform/index.tsx:98", pp "platform/index.tsx:109", pp "platform/driver.ts:24-36", pp "platform/logic.ts:17-21"]⟩,
   ⟨"morph.mount", "finish", .mainThread, .capture,
     [pp "morph.mount/index.tsx:46-60", pp "morph.mount/index.tsx:107-110"]⟩,
   ⟨"morph.tween", "finish", .mainThread, .capture,
     [pp "morph.tween/driver.ts:113-136", pp "morph.tween/driver.ts:205-207"]⟩,
   ⟨"morph.panel", "finish", .time, .curve, [pp "morph.panel/driver.ts:19", pp "morph.tween/driver.ts:109"]⟩,
   ⟨"morph.countdown", "finish", .mainThread, .stepIdle,
     [pp "morph.countdown/index.tsx:40", pp "morph.countdown/index.tsx:67"]⟩,
   ⟨"morph.columns", "finish", .mainThread, .stepIdle, [pp "morph.columns/index.tsx:23-25"]⟩]

def Part.reach (p : Part) : Reach := ThrottleParts.reach p.source p.shape

theorem parts_premised : parts.all (fun p => !p.premise.isEmpty) = true := by decide

theorem parts_ids_nodup : (parts.map (·.id)).eraseDups.length = parts.length := by decide

def namedHit : List String :=
  ["hero.exit", "people.card", "pain.notes", "nav", "nav.hitTest", "platform.shrink", "commission", "morph.mount", "morph.tween"]

def namedNotHit : List String := ["hero.exit:threaded", "morph.panel", "pain.dark"]

theorem hit_parts :
    let hits := (parts.filter (·.reach == .hit)).map (·.id)
    hits.all namedHit.contains = true ∧ namedHit.all hits.contains = true ∧ hits.length = namedHit.length := by decide

theorem namedNotHit_reach : namedNotHit.all (fun i => parts.any fun p => p.id == i && p.reach == .notHit) = true := by decide

structure Key where
  key : String
  prop : String
  writer : String
  source : Source
  shape : Shape
  premise : String
  deriving Repr

def keys : List Key :=
  [⟨"hero", "--exit-opacity", "hero.exit", .mainThread, .curve, pp "hero.exit/driver.ts:36"⟩,
   ⟨"people", "--future-shrink", "people.card", .mainThread, .chase, pp "people.card/logic.ts:105-109"⟩,
   ⟨"fade", "--morph-fade", "morph.tween", .time, .curve, pp "morph.tween/driver.ts:109"⟩]

inductive Pred where
  | stills (k : Nat)
  | pulses
  | noStills
  deriving DecidableEq, Repr

def Pred.json : Pred → Json
  | .stills k => Json.mkObj [("pattern", "stills"), ("runFrames", k)]
  | .pulses => Json.mkObj [("pattern", "pulses")]
  | .noStills => Json.mkObj [("pattern", "no-stills")]

def predicted : Mode → Source → Shape → Pred
  | .throttled, .mainThread, .curve => .stills (throttleK 1667)
  | .throttled, .mainThread, .chase => .pulses
  | .throttled, .mainThread, .snap => .stills (throttleK 1667)
  | _, _, _ => .noStills

theorem predicted_lifted (s : Source) (sh : Shape) : predicted .lifted s sh = .noStills := rfl

theorem predicted_curve : predicted .throttled .mainThread .curve = .stills 5 := by decide

theorem predicted_time (m : Mode) (sh : Shape) : predicted m .time sh = .noStills := by cases m <;> rfl

theorem predicted_snap : predicted .throttled .mainThread .snap = .stills 5 := by decide

section Snap
open Fw.Parts.Commission (Pair frame target enterRaw)

/-- The commission enter follower writes its target in a frame where the target is at or above it: a step up is not eased. -/
theorem commission_snaps_up (s : Pair) (top bottom h : Rat) (rm c : Bool) (hs : s.n ≤ target rm (enterRaw top h)) :
    (frame s top bottom h rm c).n = target rm (enterRaw top h) := by
  unfold Fw.Parts.Commission.frame Fw.Parts.Commission.gainOf
  simp only []
  generalize target rm (enterRaw top h) = m at *
  generalize (if rm = true then (1 : Rat) else Fw.Parts.Commission.gain) = g
  have h0 := Fw.Parts.Commission.abs_zero_lt
  by_cases hl : s.n < m
  · have h1 : m - m = 0 := by grind
    simp [hl, h1, h0]
  · have h2 : s.n = m := by grind
    subst h2
    have h1 : s.n - s.n = 0 := by grind
    have h5 : s.n - (s.n + 0) = 0 := by grind
    simp [hl, h1, h5, h0]

/-- The enter value over a stream of tops from `n0`. -/
def enterFollow (h : Rat) (rm : Bool) (tops : Nat → Rat) (n0 : Rat) : Nat → Rat
  | 0 => (frame ⟨n0, 0⟩ (tops 0) 0 h rm false).n
  | t + 1 => (frame ⟨enterFollow h rm tops n0 t, 0⟩ (tops (t + 1)) 0 h rm false).n

/-- On a rising target the follower is the target itself, so a throttled read of the target steps like a curve. -/
theorem enterFollow_rising (h : Rat) (rm : Bool) (tops : Nat → Rat) (n0 : Rat)
    (hm : ∀ t, target rm (enterRaw (tops t) h) ≤ target rm (enterRaw (tops (t + 1)) h))
    (h0 : n0 ≤ target rm (enterRaw (tops 0) h)) :
    ∀ t, enterFollow h rm tops n0 t = target rm (enterRaw (tops t) h)
  | 0 => commission_snaps_up _ _ _ _ _ _ h0
  | t + 1 => by
    have ih := enterFollow_rising h rm tops n0 hm h0 t
    exact commission_snaps_up _ _ _ _ _ _ (by simp only []; rw [ih]; exact hm t)
end Snap

inductive Match where
  | agree | disagree | noData
  deriving DecidableEq, Repr

def bandFor (d : Nat) : Nat × Nat := (throttleK d, throttleK d + 1)

theorem bandFor_60hz : bandFor 1667 = (5, 6) := by decide

theorem bandFor_120hz : bandFor 833 = (12, 13) := by decide

theorem bandFor_fixed : bandFor 1667 = (bandLo, bandHi) := by decide

def judgeCounts (p : Pred) (m : Mode) (base arm : Arm) : Match :=
  if arm.frames = 0 then .noData
  else match p, m with
    | .stills _, .throttled => if minBase ≤ arm.runs then .agree else .disagree
    | .stills _, .lifted =>
      match verdict [] base arm with
      | .lifted => .agree
      | .noData => .noData
      | _ => .disagree
    | _, _ => if arm.runs < minBase then .agree else .disagree

theorem judgeCounts_noData_frames (p : Pred) (m : Mode) (base arm : Arm) (h : arm.frames = 0) : judgeCounts p m base arm = .noData := by
  simp [judgeCounts, h]

theorem judgeCounts_stills_throttled_agree (k : Nat) (base arm : Arm) (hf : arm.frames ≠ 0) (h : minBase ≤ arm.runs) :
    judgeCounts (.stills k) .throttled base arm = .agree := by
  simp [judgeCounts, hf, h]

theorem judgeCounts_stills_throttled_disagree (k : Nat) (base arm : Arm) (hf : arm.frames ≠ 0) (h : arm.runs < minBase) :
    judgeCounts (.stills k) .throttled base arm = .disagree := by
  have : ¬ minBase ≤ arm.runs := by omega
  simp [judgeCounts, hf, this]

theorem judgeCounts_stills_lifted_agree (k : Nat) (base arm : Arm) (hf : arm.frames ≠ 0) (h : verdict [] base arm = .lifted) :
    judgeCounts (.stills k) .lifted base arm = .agree := by
  simp [judgeCounts, hf, h]

theorem judgeCounts_stills_lifted_noData (k : Nat) (base arm : Arm) (hf : arm.frames ≠ 0) (h : base.runs < minBase) :
    judgeCounts (.stills k) .lifted base arm = .noData := by
  have : verdict [] base arm = .noData := verdict_noData_base rfl arm h
  simp [judgeCounts, hf, this]

theorem judgeCounts_stills_lifted_disagree (k : Nat) (base arm : Arm) (hf : arm.frames ≠ 0) (h : verdict [] base arm = .notLifted) :
    judgeCounts (.stills k) .lifted base arm = .disagree := by
  simp [judgeCounts, hf, h]

theorem judgeCounts_none_agree (p : Pred) (hp : ∀ k, p ≠ .stills k) (m : Mode) (base arm : Arm) (hf : arm.frames ≠ 0)
    (h : arm.runs < minBase) : judgeCounts p m base arm = .agree := by
  cases p with
  | stills k => exact absurd rfl (hp k)
  | pulses => cases m <;> simp [judgeCounts, hf, h]
  | noStills => cases m <;> simp [judgeCounts, hf, h]

theorem judgeCounts_none_boundary (p : Pred) (hp : ∀ k, p ≠ .stills k) (m : Mode) (base arm : Arm) (hf : arm.frames ≠ 0)
    (h : minBase ≤ arm.runs) : judgeCounts p m base arm = .disagree := by
  have : ¬ arm.runs < minBase := by omega
  cases p with
  | stills k => exact absurd rfl (hp k)
  | pulses => cases m <;> simp [judgeCounts, hf, this]
  | noStills => cases m <;> simp [judgeCounts, hf, this]

/-- The lowest K a pass is judged at: the band `[K, K+1]` starts above the 1 to 2 frame hold of one dropped frame. -/
def minK : Nat := 3

/-- One pass of an arm: its own K, the runs in `[K, K+1]` and the frames of the series strictly inside its range while the toolbar moved. -/
structure Pass where
  k : Nat
  runs : Nat
  frames : Nat
  deriving DecidableEq, Repr

def Pass.inDomain (q : Pass) : Bool := decide (minK ≤ q.k)

/-- The summed counts of the passes whose K is inside the domain. -/
def pool (ps : List Pass) : Arm :=
  ⟨((ps.filter Pass.inDomain).map (·.runs)).sum, ((ps.filter Pass.inDomain).map (·.frames)).sum⟩

/-- The match of an arm's passes with the prediction; a pass whose K is below `minK` counts for nothing, K is per pass. -/
def judge (p : Pred) (m : Mode) (base arm : List Pass) : Match := judgeCounts p m (pool base) (pool arm)

theorem pool_nil : pool [] = ⟨0, 0⟩ := rfl

theorem pool_cons_out (q : Pass) (ps : List Pass) (h : q.k < minK) : pool (q :: ps) = pool ps := by
  have : ¬ minK ≤ q.k := by omega
  simp [pool, Pass.inDomain, this]

theorem pool_cons_in (q : Pass) (ps : List Pass) (h : minK ≤ q.k) :
    pool (q :: ps) = ⟨q.runs + (pool ps).runs, q.frames + (pool ps).frames⟩ := by
  simp [pool, Pass.inDomain, h]

theorem pool_out : ∀ ps : List Pass, (∀ q ∈ ps, q.k < minK) → pool ps = ⟨0, 0⟩
  | [], _ => rfl
  | q :: ps, h => by
    rw [pool_cons_out q ps (h q (by simp))]
    exact pool_out ps fun r hr => h r (List.mem_cons_of_mem _ hr)

theorem judge_noData_out (p : Pred) (m : Mode) (base arm : List Pass) (h : ∀ q ∈ arm, q.k < minK) :
    judge p m base arm = .noData := by
  apply judgeCounts_noData_frames
  rw [pool_out arm h]

theorem judge_noData_frames (p : Pred) (m : Mode) (base arm : List Pass) (h : (pool arm).frames = 0) :
    judge p m base arm = .noData := judgeCounts_noData_frames p m _ _ h

theorem judge_out_cons (p : Pred) (m : Mode) (base : List Pass) (q : Pass) (arm : List Pass) (h : q.k < minK) :
    judge p m base (q :: arm) = judge p m base arm := by
  simp only [judge, pool_cons_out q arm h]

theorem judge_stills_throttled_agree (k : Nat) (base arm : List Pass) (hf : (pool arm).frames ≠ 0)
    (h : minBase ≤ (pool arm).runs) : judge (.stills k) .throttled base arm = .agree :=
  judgeCounts_stills_throttled_agree k _ _ hf h

theorem judge_stills_throttled_disagree (k : Nat) (base arm : List Pass) (hf : (pool arm).frames ≠ 0)
    (h : (pool arm).runs < minBase) : judge (.stills k) .throttled base arm = .disagree :=
  judgeCounts_stills_throttled_disagree k _ _ hf h

theorem judge_stills_lifted_agree (k : Nat) (base arm : List Pass) (hf : (pool arm).frames ≠ 0)
    (h : verdict [] (pool base) (pool arm) = .lifted) : judge (.stills k) .lifted base arm = .agree :=
  judgeCounts_stills_lifted_agree k _ _ hf h

theorem judge_stills_lifted_noData (k : Nat) (base arm : List Pass) (hf : (pool arm).frames ≠ 0)
    (h : (pool base).runs < minBase) : judge (.stills k) .lifted base arm = .noData :=
  judgeCounts_stills_lifted_noData k _ _ hf h

theorem judge_stills_lifted_disagree (k : Nat) (base arm : List Pass) (hf : (pool arm).frames ≠ 0)
    (h : verdict [] (pool base) (pool arm) = .notLifted) : judge (.stills k) .lifted base arm = .disagree :=
  judgeCounts_stills_lifted_disagree k _ _ hf h

theorem judge_none_agree (p : Pred) (hp : ∀ k, p ≠ .stills k) (m : Mode) (base arm : List Pass) (hf : (pool arm).frames ≠ 0)
    (h : (pool arm).runs < minBase) : judge p m base arm = .agree :=
  judgeCounts_none_agree p hp m _ _ hf h

theorem judge_none_boundary (p : Pred) (hp : ∀ k, p ≠ .stills k) (m : Mode) (base arm : List Pass) (hf : (pool arm).frames ≠ 0)
    (h : minBase ≤ (pool arm).runs) : judge p m base arm = .disagree :=
  judgeCounts_none_boundary p hp m _ _ hf h

/-- The domain in gaps: K reaches `minK` exactly for frame intervals of 33.33 ms or less. -/
theorem minK_iff (d : Nat) : minK ≤ throttleK d ↔ 0 < d ∧ d ≤ 3333 := by
  unfold minK throttleK
  constructor
  · intro h
    have hd : 0 < d := by
      rcases Nat.eq_zero_or_pos d with rfl | hd
      · simp at h
      · exact hd
    have a : 4 ≤ (10000 + d - 1) / d := by omega
    have b := (Nat.le_div_iff_mul_le hd).1 a
    exact ⟨hd, by omega⟩
  · rintro ⟨hd, h⟩
    have a : 4 ≤ (10000 + d - 1) / d := (Nat.le_div_iff_mul_le hd).2 (by omega)
    omega

/-- **The converse of `throttleK_mem_band`.** K inside the fixed band 5 to 6 holds only for intervals of 14.29 to 19.99 ms. -/
theorem throttleK_band_iff (d : Nat) : (bandLo ≤ throttleK d ∧ throttleK d ≤ bandHi) ↔ 1429 ≤ d ∧ d < 2000 := by
  constructor
  · rintro ⟨h1, h2⟩
    simp only [bandLo, bandHi] at h1 h2
    unfold throttleK at h1 h2
    have hd : 0 < d := by
      rcases Nat.eq_zero_or_pos d with rfl | hd
      · simp at h1
      · exact hd
    have a : 6 ≤ (10000 + d - 1) / d := by omega
    have b : (10000 + d - 1) / d < 8 := by omega
    have a' := (Nat.le_div_iff_mul_le hd).1 a
    have b' := (Nat.div_lt_iff_lt_mul hd).1 b
    omega
  · rintro ⟨h1, h2⟩
    exact throttleK_mem_band d h1 h2

theorem bandFor_5900 : bandFor 5900 = (1, 2) := by decide

theorem bandFor_rest : bandFor 2300 = (4, 5) ∧ bandFor 2000 = (4, 5) := by decide

/-- One dropped frame holds a value for one frame and lands in the band of a 59 ms pass. -/
theorem drop_in_band_low : count 1 2 (rowsOf [10, 20, 20, 30]) = 1 := by decide

theorem drop_out_of_band (k : Nat) (h : minK ≤ k) : count k (k + 1) (rowsOf [10, 20, 20, 30]) = 0 := by
  have e : runs (rowsOf [10, 20, 20, 30]) = [⟨1, 10, true⟩] := by decide
  simp only [count, e, List.filter_cons, List.filter_nil, inBand]
  have : ¬ k ≤ 1 := by unfold minK at h; omega
  simp [this]

/-- A throttled curve read at any cadence with K at least 1 puts one run of K frames per update in the band `[K, K+1]`. -/
theorem curve_throttled_count (q n lo hi : Nat) (hl : lo ≤ q + 1) (hh : q + 1 ≤ hi) (u : Nat → Int) (f : Int → Int)
    (h : Distinct (fun t => f (u t)) ((q + 2) * n)) (hmid : ∀ t, t < (q + 2) * n → mid (f (u t)) = true) :
    count lo hi (rowsOf (series .mainThread .throttled (q + 2) u f ((q + 2) * n))) = n - 1 := by
  unfold count
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
    have hlen := plateauRuns_band lo hi (q + 1) hl hh _ hz
    rw [List.range_succ_eq_map, List.map_cons] at hm hlen ⊢
    rw [runs_plateaus q _ _ hm, hlen]
    simp

theorem hit_throttled_cadence (d n : Nat) (hK : 1 ≤ throttleK d) (u : Nat → Int) (f : Int → Int)
    (h : Distinct (fun t => f (u t)) (period d * n)) (hmid : ∀ t, t < period d * n → mid (f (u t)) = true) :
    count (bandFor d).1 (bandFor d).2 (rowsOf (series .mainThread .throttled (period d) u f (period d * n))) = n - 1 := by
  have e : period d = (throttleK d - 1) + 2 := by unfold period; omega
  rw [e] at h hmid ⊢
  exact curve_throttled_count _ n _ _ (by simp only [bandFor]; omega) (by simp only [bandFor]; omega) u f h hmid

inductive PartVerdict where
  | agree | agreePartial | disagree | noData
  deriving DecidableEq, Repr

def partVerdict (ms : List Match) : PartVerdict :=
  if ms.contains .disagree then .disagree
  else if ms.contains .agree then (if ms.contains .noData then .agreePartial else .agree)
  else .noData

theorem partVerdict_disagree (ms : List Match) (h : .disagree ∈ ms) : partVerdict ms = .disagree := by
  simp [partVerdict, h]

theorem partVerdict_agree (ms : List Match) (h1 : .disagree ∉ ms) (h2 : .agree ∈ ms) (h3 : .noData ∉ ms) :
    partVerdict ms = .agree := by
  simp [partVerdict, h1, h2, h3]

theorem partVerdict_agreePartial (ms : List Match) (h1 : .disagree ∉ ms) (h2 : .agree ∈ ms) (h3 : .noData ∈ ms) :
    partVerdict ms = .agreePartial := by
  simp [partVerdict, h1, h2, h3]

theorem partVerdict_noData (ms : List Match) (h1 : .disagree ∉ ms) (h2 : .agree ∉ ms) : partVerdict ms = .noData := by
  simp [partVerdict, h1, h2]

theorem partVerdict_nil : partVerdict [] = .noData := rfl

def samplePass (t : Nat) : Int := 10 * t

def sampleFrames : Nat := period 1667 * 10

def chase (target : Nat → Int) : Nat → Int
  | 0 => target 0 - 45
  | t + 1 =>
    let v := chase target t
    let w := v + (target t - v) * 22 / 100
    if dist w (target t) < 1 then target t else w

def exampleSeries (m : Mode) : List (String × Source × List Int) :=
  let p := period 1667
  let n := sampleFrames
  let curve : Int → Int := fun y => 100 + y
  let step : Int → Int := fun y => if y < 305 then 0 else 1000
  [("curve", .mainThread, series .mainThread m p samplePass curve n),
   ("step", .mainThread, series .mainThread m p samplePass step n),
   ("constant", .mainThread, series .mainThread m p samplePass (fun _ => 1000) n),
   ("chase", .mainThread, (List.range n).map (chase fun t => curve (seen m p samplePass t))),
   ("threaded", .threaded, series .threaded m p samplePass curve n),
   ("time", .time, series .time m p samplePass (fun t => 10 + 15 * t) n)]

def maxStep (vs : List Int) : Int := ((vs.zip vs.tail).map fun (a, b) => dist a b).foldl max 0

def diffFrames (a b : List Int) : Nat := ((a.zip b).filter fun (x, y) => x != y).length

#guard reach .mainThread .curve == .hit
#guard reach .mainThread .stepIdle == .harmless
#guard reach .threaded .curve == .notHit
#guard reach .mainThread .noRead == .notHit
#guard followUp .mainThread .curve == some "threaded-timeline"
#guard followUp .time .curve == none
#guard throttleK 1667 == 5 && period 1667 == 6 && sampleFrames == 60
#guard bandRuns (rowsOf (series .mainThread .throttled 6 samplePass (fun y => 100 + y) 60)) == 9
#guard runs (rowsOf (series .mainThread .lifted 6 samplePass (fun y => 100 + y) 60)) == []
#guard diffFrames (series .mainThread .throttled 6 samplePass (fun y => if y < 305 then 0 else 1000) 60)
  (series .mainThread .lifted 6 samplePass (fun y => if y < 305 then 0 else 1000) 60) == 5

def Source.name : Source → String
  | .mainThread => "main-thread" | .threaded => "threaded" | .time => "time"

def Shape.name : Shape → String
  | .curve => "curve" | .chase => "chase" | .snap => "snap" | .capture => "capture" | .stepLook => "step-look" | .stepIdle => "step-idle"
  | .constant => "constant" | .noRead => "no-read"

def Mode.name : Mode → String
  | .throttled => "throttled" | .lifted => "lifted"

def Match.name : Match → String
  | .agree => "agree" | .disagree => "disagree" | .noData => "no-data"

def PartVerdict.name : PartVerdict → String
  | .agree => "agree" | .agreePartial => "agree (partial)" | .disagree => "disagree" | .noData => "no-data"

def judgeBases : List Arm := [⟨0, 0⟩, ⟨9, 1000⟩, ⟨10, 0⟩, ⟨10, 1000⟩, ⟨40, 1000⟩]

def judgeArms : List Arm := [⟨0, 0⟩, ⟨5, 0⟩, ⟨0, 1000⟩, ⟨8, 1000⟩, ⟨9, 1000⟩, ⟨10, 1000⟩, ⟨11, 1000⟩, ⟨40, 1000⟩]

def matchLists : List (List Match) :=
  let ms : List Match := [.agree, .disagree, .noData]
  [[]] ++ ms.map (fun a => [a]) ++ (ms.flatMap fun a => ms.map fun b => [a, b]) ++
    (ms.flatMap fun a => ms.flatMap fun b => ms.map fun c => [a, b, c])

def armJ (a : Arm) : Json := Json.mkObj [("runs", a.runs), ("frames", a.frames)]

def passesJ (ps : List Pass) : Json :=
  Json.arr (ps.map fun q => Json.mkObj [("k", q.k), ("runs", q.runs), ("frames", q.frames)]).toArray

def passBases : List (List Pass) :=
  [[], [⟨5, 9, 1000⟩], [⟨5, 40, 1000⟩], [⟨1, 40, 1000⟩], [⟨5, 40, 600⟩, ⟨2, 40, 400⟩], [⟨4, 12, 1000⟩, ⟨4, 12, 1000⟩]]

def passArms : List (List Pass) :=
  [[], [⟨5, 0, 0⟩], [⟨2, 50, 1000⟩], [⟨1, 10, 1000⟩], [⟨3, 10, 1000⟩], [⟨3, 9, 1000⟩], [⟨4, 0, 1000⟩], [⟨5, 8, 1000⟩],
   [⟨5, 10, 1000⟩], [⟨5, 5, 500⟩, ⟨4, 5, 500⟩], [⟨5, 9, 500⟩, ⟨1, 30, 500⟩], [⟨1, 30, 500⟩, ⟨2, 30, 500⟩],
   [⟨4, 0, 500⟩, ⟨5, 12, 0⟩]]

#guard judge (.stills 5) .throttled [] [⟨1, 30, 1000⟩] == .noData
#guard judge .pulses .throttled [] [⟨1, 30, 500⟩, ⟨4, 9, 500⟩] == .agree
#guard judge .pulses .throttled [] [⟨5, 10, 500⟩, ⟨1, 30, 500⟩] == .disagree
#guard judge (.stills 5) .lifted [⟨5, 40, 1000⟩, ⟨1, 99, 1000⟩] [⟨5, 8, 1000⟩, ⟨2, 99, 1000⟩] == .agree

#guard judgeCounts (.stills 5) .throttled ⟨0, 0⟩ ⟨10, 1000⟩ == .agree
#guard judgeCounts (.stills 5) .throttled ⟨0, 0⟩ ⟨9, 1000⟩ == .disagree
#guard judgeCounts .pulses .throttled ⟨0, 0⟩ ⟨10, 1000⟩ == .disagree
#guard judgeCounts .noStills .lifted ⟨40, 1000⟩ ⟨9, 1000⟩ == .agree
#guard judgeCounts (.stills 5) .lifted ⟨40, 1000⟩ ⟨8, 1000⟩ == .agree
#guard judgeCounts (.stills 5) .lifted ⟨40, 1000⟩ ⟨9, 1000⟩ == .disagree
#guard judgeCounts (.stills 5) .lifted ⟨9, 1000⟩ ⟨0, 1000⟩ == .noData
#guard partVerdict [.agree, .noData] == .agreePartial

private def strsJ (l : List String) : Json := Json.arr (l.map Json.str).toArray

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("throttleMs", (100 : Int)), ("d60", (1667 : Nat)), ("throttleK60", throttleK 1667),
    ("period60", period 1667), ("d120", (833 : Nat)), ("throttleK120", throttleK 833), ("bandLo", bandLo),
    ("bandHi", bandHi), ("minK", minK)]).compress] ++
  (parts.map fun p =>
    (Json.mkObj [("kind", "part"), ("id", p.id), ("zone", p.zone), ("source", p.source.name), ("shape", p.shape.name),
      ("reach", p.reach.name), ("symptom", symptom p.source p.shape), ("basis", strsJ (basis p.source p.shape)),
      ("followUp", match followUp p.source p.shape with | some s => Json.str s | none => Json.null),
      ("premise", strsJ p.premise)]).compress) ++
  (keys.map fun k =>
    (Json.mkObj [("kind", "key"), ("key", k.key), ("prop", k.prop), ("writer", k.writer), ("source", k.source.name),
      ("shape", k.shape.name), ("reach", (reach k.source k.shape).name), ("premise", k.premise),
      ("rule", "still runs of the key's own per-mille series, rows (v, v), value strictly between 0 and 1000"),
      ("predicted", Json.mkObj [("throttled", (predicted .throttled k.source k.shape).json),
        ("lifted", (predicted .lifted k.source k.shape).json)])]).compress) ++
  ([Pred.stills (throttleK 1667), .pulses, .noStills].flatMap fun pr =>
    [Mode.throttled, .lifted].flatMap fun m => judgeBases.flatMap fun b => judgeArms.map fun a =>
      (Json.mkObj [("kind", "judgeCounts"), ("pred", pr.json), ("mode", m.name), ("base", armJ b), ("arm", armJ a),
        ("match", (judgeCounts pr m b a).name)]).compress) ++
  ([Pred.stills (throttleK 1667), .pulses, .noStills].flatMap fun pr =>
    [Mode.throttled, .lifted].flatMap fun m => passBases.flatMap fun b => passArms.map fun a =>
      (Json.mkObj [("kind", "judge"), ("pred", pr.json), ("mode", m.name), ("base", passesJ b), ("arm", passesJ a),
        ("match", (judge pr m b a).name)]).compress) ++
  (matchLists.map fun ms =>
    (Json.mkObj [("kind", "partVerdict"), ("matches", strsJ (ms.map Match.name)),
      ("verdict", (partVerdict ms).name)]).compress) ++
  (([1429, 1600, 1667, 1700, 1999, 833, 2000, 2300, 3300, 3333, 3334, 3500, 5900] : List Nat).map fun (d : Nat) =>
    (Json.mkObj [("kind", "bandFor"), ("d", d), ("lo", (bandFor d).1), ("hi", (bandFor d).2),
      ("inDomain", decide (minK ≤ (bandFor d).1)),
      ("fixed", decide (bandLo ≤ (bandFor d).1 ∧ (bandFor d).1 ≤ bandHi))]).compress) ++
  ((exampleSeries .throttled).zip (exampleSeries .lifted) |>.map fun ((name, src, a), (_, _, b)) =>
    let one (vs : List Int) : Json :=
      Json.mkObj [("values", toJson vs), ("runs", toJson ((runs (rowsOf vs)).map (·.k))), ("band", bandRuns (rowsOf vs)),
        ("maxStep", maxStep vs)]
    (Json.mkObj [("kind", "example"), ("shape", name), ("source", src.name), ("frames", sampleFrames),
      ("pxPerFrame", (10 : Int)), ("throttled", one a), ("lifted", one b), ("diffFrames", diffFrames a b)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-throttle-parts golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-throttle-parts golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Device.ThrottleParts
