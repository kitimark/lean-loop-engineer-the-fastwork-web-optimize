import Fw.Device.Replay
/-!
# Worst-case replay profiles
Fast-fling, zone-loop and cold profiles made from a recorded one, and the arm order of a replay session.
-/
namespace Fw.Device.Replay
open Fw.Device.Session (Zone zoneOf yAt)

theorem compile_sample_within (p : Profile) {s : Swipe} (hs : s ∈ p.swipes) {e : Sample} (he : e ∈ s.samples) :
    ∃ t ∈ (compile p).filterMap Act.target,
      -10 ≤ 10 * t.1 - e.x ∧ 10 * t.1 - e.x ≤ 10 ∧ -10 ≤ 10 * t.2 - e.y ∧ 10 * t.2 - e.y ≤ 10 := by
  rw [compile_targets]
  have hne : s ∈ p.swipes.filter fun s => !s.samples.isEmpty := by
    simp only [List.mem_filter, Bool.not_eq_true', List.isEmpty_eq_false_iff]
    exact ⟨hs, fun h => by simp [h] at he⟩
  refine ⟨(px e.x, px e.y), ?_, ?_⟩
  · simp only [List.mem_map, List.mem_flatMap]
    refine ⟨⟨ms (s.start + e.t), px e.x, px e.y⟩, ⟨s, hne, ?_⟩, rfl⟩
    simp only [swipePts, List.mem_map]
    exact ⟨e, he, rfl⟩
  · have h1 := px_err e.x
    have h2 := px_err e.y
    simp only
    omega

/-! ## Laying swipes out -/

/-- The swipes in order from `at_`, each starting `gap` after the one before has lifted. -/
def layoutFrom (at_ gap : Int) : List Swipe → List Swipe
  | [] => []
  | s :: ss => { s with start := at_ } :: layoutFrom (at_ + s.lift + gap) gap ss

/-- The swipes in order from 0. -/
def layout (gap : Int) (ss : List Swipe) : List Swipe := layoutFrom 0 gap ss

/-- Each swipe starts exactly `g` after the one before has lifted. -/
def gapsOk (g : Int) : List Swipe → Bool
  | s :: t :: r => decide (t.start = s.start + s.lift + g) && gapsOk g (t :: r)
  | _ => true

theorem layoutFrom_gaps (g : Int) : ∀ (l : List Swipe) (a : Int), gapsOk g (layoutFrom a g l) = true := by
  intro l
  induction l with
  | nil => intro a; simp [layoutFrom, gapsOk]
  | cons s ss ih =>
    intro a
    match ss with
    | [] => simp [layoutFrom, gapsOk]
    | t :: r =>
      have := ih (a + s.lift + g)
      simp only [layoutFrom] at this ⊢
      simp [gapsOk, this]

theorem layoutFrom_length (g : Int) : ∀ (l : List Swipe) (a : Int), (layoutFrom a g l).length = l.length := by
  intro l
  induction l with
  | nil => intro a; rfl
  | cons s ss ih => intro a; simp [layoutFrom, ih]

theorem layoutFrom_samples (g : Int) : ∀ (l : List Swipe) (a : Int), (layoutFrom a g l).map (·.samples) = l.map (·.samples) := by
  intro l
  induction l with
  | nil => intro a; rfl
  | cons s ss ih => intro a; simp [layoutFrom, ih]

/-! ## Fast fling -/

/-- The squared lift-off speed in tenth px per 0.01 ms, times a million, floored. -/
def speed2 (s : Swipe) : Int :=
  match liftVel 5000 (expected s) with
  | (dx, dy, dt) => (dx * dx + dy * dy) * 1000000 / (dt * dt)

/-- Whether the finger ends higher than it started: the page scrolls towards its end. -/
def scrollsDown (s : Swipe) : Bool :=
  match s.samples.head?, s.samples.getLast? with
  | some a, some z => decide (z.y < a.y)
  | _, _ => false

/-- The faster of two swipes, the first when equal. -/
def faster (b s : Swipe) : Swipe := if speed2 b < speed2 s then s else b

/-- The fastest page-scrolling-down swipe, the first of equals. -/
def fastest (l : List Swipe) : Option Swipe :=
  match l.filter scrollsDown with
  | [] => none
  | s :: ss => some (ss.foldl faster s)

theorem faster_ge (b s : Swipe) : speed2 b ≤ speed2 (faster b s) ∧ speed2 s ≤ speed2 (faster b s) := by
  unfold faster
  split <;> omega

theorem foldl_faster_max : ∀ (ss : List Swipe) (b : Swipe),
    speed2 b ≤ speed2 (ss.foldl faster b) ∧ ∀ s ∈ ss, speed2 s ≤ speed2 (ss.foldl faster b) := by
  intro ss
  induction ss with
  | nil => intro b; simp
  | cons s ss ih =>
    intro b
    simp only [List.foldl_cons]
    obtain ⟨h1, h2⟩ := ih (faster b s)
    obtain ⟨g1, g2⟩ := faster_ge b s
    refine ⟨by omega, ?_⟩
    intro x hx
    simp only [List.mem_cons] at hx
    rcases hx with rfl | hx
    · omega
    · exact h2 x hx

theorem foldl_faster_mem : ∀ (ss : List Swipe) (b : Swipe), ss.foldl faster b = b ∨ ss.foldl faster b ∈ ss := by
  intro ss
  induction ss with
  | nil => intro b; simp
  | cons s ss ih =>
    intro b
    simp only [List.foldl_cons, List.mem_cons]
    rcases ih (faster b s) with h | h
    · rw [h]; unfold faster; split
      · exact Or.inr (Or.inl rfl)
      · exact Or.inl rfl
    · exact Or.inr (Or.inr h)

theorem fastest_mem {l : List Swipe} {f : Swipe} (h : fastest l = some f) : f ∈ l ∧ scrollsDown f = true := by
  unfold fastest at h
  split at h
  · simp at h
  · rename_i s ss hs
    cases h
    have hall : ∀ x ∈ l.filter scrollsDown, x ∈ l ∧ scrollsDown x = true := by
      intro x hx; simpa [List.mem_filter] using hx
    have hsub : ∀ x ∈ s :: ss, x ∈ l ∧ scrollsDown x = true := by
      intro x hx; rw [← hs] at hx; exact hall x hx
    rcases foldl_faster_mem ss s with h | h
    · rw [h]; exact hsub s (by simp)
    · exact hsub _ (by simp [h])

/-- No swipe that scrolls down is faster than the one picked. -/
theorem fastest_max {l : List Swipe} {f : Swipe} (h : fastest l = some f) : ∀ s ∈ l, scrollsDown s = true → speed2 s ≤ speed2 f := by
  unfold fastest at h
  split at h
  · simp at h
  · rename_i s0 ss hs
    cases h
    intro x hx hd
    have hx' : x ∈ s0 :: ss := by rw [← hs]; simp [List.mem_filter, hx, hd]
    obtain ⟨h1, h2⟩ := foldl_faster_max ss s0
    simp only [List.mem_cons] at hx'
    rcases hx' with rfl | hx'
    · exact h1
    · exact h2 x hx'

/-- The profile of the fastest down-scroll fling repeated `n` times, `gap` after each lift, no settling between. -/
def fastFling (p : Profile) (n : Nat) (gap : Int) : Option Profile :=
  match fastest p.swipes with
  | none => none
  | some f => some { p with id := p.id ++ "-fast-fling", load := .warm, swipes := layout gap (List.replicate n f) }

theorem fastFling_length {p q : Profile} {n : Nat} {g : Int} (h : fastFling p n g = some q) : q.swipes.length = n := by
  unfold fastFling at h
  split at h
  · simp at h
  · cases h; simp [layout, layoutFrom_length]

theorem fastFling_fastest {p q : Profile} {n : Nat} {g : Int} (h : fastFling p n g = some q) :
    ∃ f, fastest p.swipes = some f ∧ ∀ s ∈ q.swipes, s.samples = f.samples := by
  unfold fastFling at h
  split at h
  · simp at h
  · rename_i f hf
    cases h
    refine ⟨f, hf, ?_⟩
    intro s hs
    have := layoutFrom_samples g (List.replicate n f) 0
    simp only [layout] at hs
    have hm : s.samples ∈ (layoutFrom 0 g (List.replicate n f)).map (·.samples) := List.mem_map_of_mem hs
    rw [this] at hm
    simp only [List.map_replicate, List.mem_replicate] at hm
    exact hm.2

/-! ## Zone loop -/

/-- The zone the page is in when a swipe starts, `t0` the record time of the first swipe. -/
def swipeZone (vh10 maxY10 : Int) (frames : List (Int × Int)) (t0 : Int) (s : Swipe) : Zone :=
  zoneOf vh10 maxY10 (yAt frames (t0 + s.start))

/-- The swipes that start in zone `z`. -/
def segment (z : Zone) (vh10 maxY10 : Int) (frames : List (Int × Int)) (t0 : Int) (l : List Swipe) : List Swipe :=
  l.filter fun s => decide (swipeZone vh10 maxY10 frames t0 s = z)

theorem segment_zone {z : Zone} {vh10 maxY10 : Int} {frames : List (Int × Int)} {t0 : Int} {l : List Swipe} :
    ∀ s ∈ segment z vh10 maxY10 frames t0 l, swipeZone vh10 maxY10 frames t0 s = z := by
  intro s hs
  have h2 := (List.mem_filter.mp hs).2
  simpa using h2

theorem segment_sub {z : Zone} {vh10 maxY10 : Int} {frames : List (Int × Int)} {t0 : Int} {l : List Swipe} :
    ∀ s ∈ segment z vh10 maxY10 frames t0 l, s ∈ l := by
  intro s hs
  exact (List.mem_filter.mp hs).1

/-- A swipe with the finger moving the other way: the page scrolls back. -/
def mirror (h10 : Int) (s : Swipe) : Swipe := { s with samples := s.samples.map fun e => { e with y := h10 - e.y } }

theorem mirror_mirror (h10 : Int) (s : Swipe) : mirror h10 (mirror h10 s) = s := by
  cases s with
  | mk st sm li =>
    have h : ∀ e : Sample, ({ t := e.t, x := e.x, y := h10 - (h10 - e.y) } : Sample) = e := by
      intro e; cases e; simp; omega
    simp [mirror, List.map_map, Function.comp_def, h]

theorem mirror_lift (h10 : Int) (s : Swipe) : (mirror h10 s).lift = s.lift ∧ (mirror h10 s).start = s.start := ⟨rfl, rfl⟩

theorem mirror_length (h10 : Int) (s : Swipe) : (mirror h10 s).samples.length = s.samples.length := by
  simp [mirror]

/-- The profile that scrolls through the swipes that start in zone `z` and back, `reps` times, `gap` after each lift. -/
def zoneLoop (p : Profile) (z : Zone) (maxY10 : Int) (frames : List (Int × Int)) (t0 : Int) (reps : Nat) (gap : Int) : Option Profile :=
  match segment z ((p.h : Int) * 10) maxY10 frames t0 p.swipes with
  | [] => none
  | seg => some { p with id := p.id ++ "-zone-" ++ z.name, load := .warm, swipes := layout gap ((List.replicate reps (seg ++ seg.map (mirror ((p.h : Int) * 10)))).flatten) }

theorem zoneLoop_length {p q : Profile} {z : Zone} {maxY10 : Int} {frames : List (Int × Int)} {t0 : Int} {reps : Nat} {g : Int}
    (h : zoneLoop p z maxY10 frames t0 reps g = some q) :
    q.swipes.length = reps * (2 * (segment z ((p.h : Int) * 10) maxY10 frames t0 p.swipes).length) := by
  unfold zoneLoop at h
  split at h
  · simp at h
  · rename_i seg hseg
    cases h
    simp only [layout, layoutFrom_length]
    rw [List.length_flatten, List.map_replicate, List.sum_replicate_nat]
    simp [Nat.two_mul]

/-- The same swipes with the page loaded fresh and caches cleared before the pass. -/
def cold (p : Profile) : Profile := { p with id := p.id ++ "-cold", load := .cold }

theorem cold_swipes (p : Profile) : (cold p).swipes = p.swipes := rfl

theorem cold_load (p : Profile) : (cold p).load = .cold := rfl

/-! ## The order of arms -/

/-- Arm positions `0 .. n-1` rotated left by `r`, so repeat `r` starts with arm `r` and every arm leads once in `n` repeats. -/
def rotation (n r : Nat) : List Nat := (List.range n).drop (r % n) ++ (List.range n).take (r % n)

theorem rotation_perm (n r : Nat) : (rotation n r).Perm (List.range n) := by
  unfold rotation
  exact (List.perm_append_comm).trans (by rw [List.take_append_drop])

theorem rotation_length (n r : Nat) : (rotation n r).length = n := by
  rw [(rotation_perm n r).length_eq]; simp

theorem rotation_lead (n r : Nat) (hn : 0 < n) : (rotation n r).head? = some (r % n) := by
  have hk : r % n < n := Nat.mod_lt _ hn
  unfold rotation
  rw [List.head?_append, List.head?_drop, List.getElem?_range hk]
  rfl

/-- In `n` repeats every arm leads exactly once. -/
theorem rotation_lead_cover (n : Nat) (a : Nat) (ha : a < n) : ∃ r < n, (rotation n r).head? = some a := by
  refine ⟨a, ha, ?_⟩
  rw [rotation_lead n a (by omega), Nat.mod_eq_of_lt ha]

/-- What a replay profile is made from. -/
inductive Kind where
  | recorded | fastFling | zoneHero | zoneFinish | cold
  deriving DecidableEq, Repr

/-- The name written in the output. -/
def Kind.code : Kind → String
  | .recorded => "recorded" | .fastFling => "fast-fling" | .zoneHero => "zone-hero" | .zoneFinish => "zone-finish" | .cold => "cold"

/-- One pass of the session: a profile kind, its repeat number and the order of the arms in it. -/
structure Run where
  kind : Kind
  rep : Nat
  order : List Nat
  deriving Repr, DecidableEq

/-- Every profile kind, `reps` repeats each, over `n` arms, the arm order rotated per repeat. -/
def schedule (kinds : List Kind) (reps n : Nat) : List Run :=
  kinds.flatMap fun k => (List.range reps).map fun r => ⟨k, r, rotation n r⟩

theorem schedule_length (kinds : List Kind) (reps n : Nat) : (schedule kinds reps n).length = kinds.length * reps := by
  simp [schedule, List.length_flatMap, List.map_const', List.sum_replicate_nat]

theorem schedule_perm (kinds : List Kind) (reps n : Nat) : ∀ r ∈ schedule kinds reps n, r.order.Perm (List.range n) := by
  intro r hr
  simp only [schedule, List.mem_flatMap, List.mem_map, List.mem_range] at hr
  obtain ⟨k, _, i, _, rfl⟩ := hr
  exact rotation_perm n i

end Fw.Device.Replay
