import Lean.Data.Json
import Fw.Device.Session
/-! Replaying a recorded finger path on the phone: W3C action compiler and per-stroke replay check. -/
namespace Fw.Device.Replay
open Lean
open Fw.Device.Session (Touch Phase replayStrokes t0Of singleFinger Zone zoneOf yAt)

/-! ## The profile -/

/-- A finger position: time since the swipe's first event (hundredths of a ms), position (tenth px). -/
structure Sample where
  t : Int
  x : Int
  y : Int
  deriving Repr, DecidableEq

/-- One swipe: its start since the first swipe's start, the touch start and moves, and the time of the lift. -/
structure Swipe where
  start : Int
  samples : List Sample
  lift : Int
  deriving Repr, DecidableEq

/-- Whether the page is loaded fresh with empty caches before the pass. -/
inductive Load where
  | warm | cold
  deriving DecidableEq, Repr

/-- The finger path of a pass in a viewport of `w` by `h` px. -/
structure Profile where
  id : String
  w : Nat
  h : Nat
  load : Load
  swipes : List Swipe
  deriving Repr, DecidableEq

/-- The swipe of one stroke of touches, `t0` the first swipe's start. -/
def swipeOf (t0 : Int) (s : List Touch) : Option Swipe :=
  match s.head?, s.getLast? with
  | some a, some z =>
    some ⟨a.t - t0, (s.filter fun e => decide (e.ph ≠ .stop)).map fun e => ⟨e.t - a.t, e.x, e.y⟩, z.t - a.t⟩
  | _, _ => none

/-- The swipes of a touch stream: its strokes that are not taps. -/
def swipesOf (ts : List Touch) : List Swipe :=
  (replayStrokes ts).filterMap (swipeOf (t0Of (replayStrokes ts)))

/-- The profile of a recorded pass, none when a second finger was ever down. -/
def ofTouches (id : String) (ts : List Touch) (w h : Nat) : Option Profile :=
  if singleFinger ts then some ⟨id, w, h, .warm, swipesOf ts⟩ else none

theorem ofTouches_multi_refused {ts : List Touch} (id : String) (w h : Nat) (hm : singleFinger ts = false) :
    ofTouches id ts w h = none := by
  simp [ofTouches, hm]

/-! ## The W3C action compiler -/

/-- A tenth px as a whole px, halves up. -/
def px (v : Int) : Int := (v + 5) / 10

theorem px_err (v : Int) : -4 ≤ 10 * px v - v ∧ 10 * px v - v ≤ 5 := by
  unfold px; omega

/-- Hundredths of a ms as whole ms, halves up. -/
def ms (t : Int) : Int := (t + 50) / 100

theorem ms_mono {a b : Int} (h : a ≤ b) : ms a ≤ ms b := by
  unfold ms; omega

/-- The longest tick: a move this short is one event, so no move enters WebKit's interpolation loop. -/
def tickMax : Nat := 16

/-- One action of the single touch source; durations in ms, positions in whole px. -/
inductive Act where
  | move (x y d : Int)
  | down
  | up
  | pause (d : Int)
  deriving Repr, DecidableEq

/-- The time an action takes. -/
def Act.dur : Act → Int
  | .move _ _ d => d
  | .pause d => d
  | _ => 0

/-- The target of a move. -/
def Act.target : Act → Option (Int × Int)
  | .move x y _ => some (x, y)
  | _ => none

@[simp] theorem target_move (x y d : Int) : (Act.move x y d).target = some (x, y) := rfl
@[simp] theorem target_down : Act.down.target = none := rfl
@[simp] theorem target_up : Act.up.target = none := rfl
@[simp] theorem target_pause (d : Int) : (Act.pause d).target = none := rfl

/-- A span of ms as pieces of at most `tickMax`. -/
def chunks (n : Nat) : List Nat :=
  if n ≤ tickMax then [n] else tickMax :: chunks (n - tickMax)
termination_by n
decreasing_by simp only [tickMax]; omega

theorem chunks_le (n : Nat) : ∀ c ∈ chunks n, c ≤ tickMax := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    unfold chunks
    split
    · simp_all
    · rename_i h
      intro c hc
      simp only [List.mem_cons] at hc
      rcases hc with rfl | hc
      · exact Nat.le_refl _
      · exact ih (n - tickMax) (by simp only [tickMax] at h ⊢; omega) c hc

theorem chunks_sum (n : Nat) : (chunks n).sum = n := by
  induction n using Nat.strongRecOn with
  | _ n ih =>
    unfold chunks
    split
    · simp
    · rename_i h
      simp only [List.sum_cons]
      have := ih (n - tickMax) (by simp only [tickMax] at h ⊢; omega)
      simp only [tickMax] at h this ⊢
      omega

/-- The ms from `a` to `b`, 0 when `b` is not later. -/
def gap (a b : Int) : Nat := (b - a).toNat

/-- A wait of `n` ms as pauses of at most `tickMax`. -/
def pauseRun (n : Nat) : List Act :=
  if n = 0 then [] else (chunks n).map fun (c : Nat) => .pause (c : Int)

theorem pauseRun_dur_le (n : Nat) : ∀ a ∈ pauseRun n, 0 ≤ a.dur ∧ a.dur ≤ tickMax := by
  intro a ha
  unfold pauseRun at ha
  split at ha
  · simp at ha
  · simp only [List.mem_map] at ha
    obtain ⟨c, hc, rfl⟩ := ha
    exact ⟨by simp [Act.dur], by simpa [Act.dur] using chunks_le n c hc⟩

theorem pauseRun_dur_sum (n : Nat) : ((pauseRun n).map Act.dur).sum = n := by
  unfold pauseRun
  split
  · simp_all
  · have := chunks_sum n
    have h : ((chunks n).map fun (c : Nat) => Act.pause (c : Int)).map Act.dur = (chunks n).map (fun (c : Nat) => (c : Int)) := by
      simp [List.map_map, Function.comp_def, Act.dur]
    rw [h]
    clear h
    have : ∀ l : List Nat, (l.map (fun (c : Nat) => (c : Int))).sum = (l.sum : Int) := by
      intro l; induction l with
      | nil => simp
      | cons a l ih => simp [ih]
    rw [this, ‹(chunks n).sum = n›]

theorem pauseRun_no_target (n : Nat) : (pauseRun n).filterMap Act.target = [] := by
  unfold pauseRun
  split
  · rfl
  · simp [List.filterMap_map, Function.comp_def]

structure Pt where
  m : Int
  x : Int
  y : Int
  deriving Repr, DecidableEq

def nextMs : List Pt → Int → Int
  | [], fin => fin
  | q :: _, _ => q.m

/-- A point after the first: the move to it, as long as the wait until the next point allows, then the rest of the wait. -/
def emit : Pt → List Pt → Int → List Act
  | p, rest, fin =>
    let g := gap p.m (nextMs rest fin)
    [.move p.x p.y (min g tickMax : Nat)] ++ pauseRun (g - min g tickMax) ++
      (match rest with
        | [] => []
        | q :: qs => emit q qs fin)
termination_by _ rest => rest.length
decreasing_by simp_wf

/-- The actions of a swipe: to the first point, down, the wait, every later point, up at the lift. -/
def swipeActs : List Pt → Int → List Act
  | [], _ => []
  | f :: rest, fin =>
    [.move f.x f.y 0, .down] ++ pauseRun (gap f.m (nextMs rest fin)) ++
      (match rest with
        | [] => []
        | q :: qs => emit q qs fin) ++ [.up]

/-- The points of a swipe on the ms grid. -/
def swipePts (s : Swipe) : List Pt :=
  s.samples.map fun e => ⟨ms (s.start + e.t), px e.x, px e.y⟩

/-- The end of a swipe on the ms grid. -/
def swipeEnd (s : Swipe) : Int := ms (s.start + s.lift)

def goActs : Int → List Swipe → List Act
  | _, [] => []
  | prev, s :: ss =>
    match swipePts s with
    | [] => goActs prev ss
    | f :: _ => pauseRun (gap prev f.m) ++ swipeActs (swipePts s) (swipeEnd s) ++ goActs (swipeEnd s) ss

/-- The W3C actions of a profile: one touch source, every tick at most `tickMax` ms. -/
def compile (p : Profile) : List Act :=
  match (p.swipes.filter fun s => !s.samples.isEmpty) with
  | [] => []
  | s :: ss =>
    match swipePts s with
    | [] => []
    | f :: _ => goActs f.m (s :: ss)

theorem emit_dur_le : ∀ (n : Nat) (p : Pt) (rest : List Pt) (fin : Int), rest.length = n →
    ∀ a ∈ emit p rest fin, 0 ≤ a.dur ∧ a.dur ≤ tickMax := by
  intro n
  induction n with
  | zero =>
    intro p rest fin hr a ha
    have : rest = [] := List.length_eq_zero_iff.mp hr
    subst this
    unfold emit at ha
    simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at ha
    rcases ha with rfl | ha
    · simp only [Act.dur, tickMax]; omega
    · exact pauseRun_dur_le _ a ha
  | succ n ih =>
    intro p rest fin hr a ha
    match rest, hr with
    | q :: qs, hr =>
      unfold emit at ha
      simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at ha
      rcases ha with (rfl | ha) | ha
      · simp only [Act.dur, tickMax]; omega
      · exact pauseRun_dur_le _ a ha
      · exact ih q qs fin (by simpa using hr) a ha

theorem swipeActs_dur_le (pts : List Pt) (fin : Int) : ∀ a ∈ swipeActs pts fin, 0 ≤ a.dur ∧ a.dur ≤ tickMax := by
  intro a ha
  match pts with
  | [] => simp [swipeActs] at ha
  | f :: rest =>
    unfold swipeActs at ha
    simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at ha
    rcases ha with (((rfl | rfl) | ha) | ha) | rfl
    · simp [Act.dur, tickMax]
    · simp [Act.dur, tickMax]
    · exact pauseRun_dur_le _ a ha
    · match rest with
      | [] => simp at ha
      | q :: qs => exact emit_dur_le _ q qs fin rfl a ha
    · simp [Act.dur, tickMax]

theorem goActs_dur_le : ∀ (prev : Int) (ss : List Swipe), ∀ a ∈ goActs prev ss, 0 ≤ a.dur ∧ a.dur ≤ tickMax := by
  intro prev ss
  induction ss generalizing prev with
  | nil => simp [goActs]
  | cons s ss ih =>
    intro a ha
    unfold goActs at ha
    split at ha
    · exact ih prev a ha
    · simp only [List.mem_append] at ha
      rcases ha with (ha | ha) | ha
      · exact pauseRun_dur_le _ a ha
      · exact swipeActs_dur_le _ _ a ha
      · exact ih _ a ha

theorem compile_dur_le (p : Profile) : ∀ a ∈ compile p, 0 ≤ a.dur ∧ a.dur ≤ tickMax := by
  intro a ha
  unfold compile at ha
  split at ha
  · simp at ha
  · split at ha
    · simp at ha
    · exact goActs_dur_le _ _ a ha

theorem emit_targets : ∀ (n : Nat) (p : Pt) (rest : List Pt) (fin : Int), rest.length = n →
    (emit p rest fin).filterMap Act.target = (p :: rest).map fun q => (q.x, q.y) := by
  intro n
  induction n with
  | zero =>
    intro p rest fin hr
    have : rest = [] := List.length_eq_zero_iff.mp hr
    subst this
    unfold emit
    simp [pauseRun_no_target]
  | succ n ih =>
    intro p rest fin hr
    match rest, hr with
    | q :: qs, hr =>
      unfold emit
      simp [List.filterMap_append, pauseRun_no_target, ih q qs fin (by simpa using hr)]

theorem swipeActs_targets (pts : List Pt) (fin : Int) :
    (swipeActs pts fin).filterMap Act.target = pts.map fun q => (q.x, q.y) := by
  match pts with
  | [] => simp [swipeActs]
  | f :: rest =>
    unfold swipeActs
    match rest with
    | [] => simp only [List.filterMap_append]; simp [pauseRun_no_target]
    | q :: qs => simp only [List.filterMap_append]; simp [List.filterMap_cons, pauseRun_no_target, emit_targets _ q qs fin rfl]

theorem goActs_targets : ∀ (prev : Int) (ss : List Swipe),
    (goActs prev ss).filterMap Act.target = (ss.flatMap swipePts).map fun q => (q.x, q.y) := by
  intro prev ss
  induction ss generalizing prev with
  | nil => simp [goActs]
  | cons s ss ih =>
    unfold goActs
    split
    · rename_i h
      simp [h, ih]
    · rename_i f rest h
      simp [List.filterMap_append, pauseRun_no_target, swipeActs_targets, ih, List.map_append]

theorem compile_targets (p : Profile) :
    (compile p).filterMap Act.target = ((p.swipes.filter fun s => !s.samples.isEmpty).flatMap swipePts).map fun q => (q.x, q.y) := by
  unfold compile
  split
  · rename_i h
    rw [h]; simp
  · rename_i s ss h
    split
    · rename_i h2
      have : swipePts s ≠ [] := by
        have hs : s ∈ p.swipes.filter fun s => !s.samples.isEmpty := by rw [h]; simp
        simp only [List.mem_filter, Bool.not_eq_true', List.isEmpty_eq_false_iff] at hs
        intro h3
        unfold swipePts at h3
        simp at h3
        exact hs.2 h3
      exact absurd h2 this
    · rename_i f rest h2
      rw [goActs_targets, h]

/-- The wait times of a point list are in order, from `a` through the points to `fin`. -/
def chain : Int → List Pt → Int → Prop
  | a, [], fin => a ≤ fin
  | a, q :: qs, fin => a ≤ q.m ∧ chain q.m qs fin

theorem emit_dur_sum : ∀ (n : Nat) (p : Pt) (rest : List Pt) (fin : Int), rest.length = n → chain p.m rest fin →
    ((emit p rest fin).map Act.dur).sum = fin - p.m := by
  intro n
  induction n with
  | zero =>
    intro p rest fin hr hc
    have : rest = [] := List.length_eq_zero_iff.mp hr
    subst this
    unfold emit
    simp only [chain] at hc
    simp only [List.map_append, List.sum_append, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, pauseRun_dur_sum,
      Act.dur, nextMs, gap, tickMax]
    omega
  | succ n ih =>
    intro p rest fin hr hc
    match rest, hr with
    | q :: qs, hr =>
      simp only [chain] at hc
      have := ih q qs fin (by simpa using hr) hc.2
      unfold emit
      simp only [List.map_append, List.sum_append, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, pauseRun_dur_sum,
        Act.dur, nextMs, gap, tickMax]
      omega

theorem swipeActs_dur_sum (f : Pt) (rest : List Pt) (fin : Int) (hc : chain f.m rest fin) :
    ((swipeActs (f :: rest) fin).map Act.dur).sum = fin - f.m := by
  unfold swipeActs
  match rest with
  | [] =>
    simp only [chain] at hc
    simp only [List.map_append, List.sum_append, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, pauseRun_dur_sum,
      Act.dur, nextMs, gap]
    omega
  | q :: qs =>
    simp only [chain] at hc
    have := emit_dur_sum _ q qs fin rfl hc.2
    simp only [List.map_append, List.sum_append, List.map_cons, List.map_nil, List.sum_cons, List.sum_nil, pauseRun_dur_sum,
      Act.dur, nextMs, gap] at this ⊢
    omega

/-! ## The replay in pieces -/

/-- The actions cut at the swipes: one piece per swipe with points, its lead-in wait first, the finger up at its end. -/
def goPieces : Int → List Swipe → List (List Act)
  | _, [] => []
  | prev, s :: ss =>
    match swipePts s with
    | [] => goPieces prev ss
    | f :: _ => (pauseRun (gap prev f.m) ++ swipeActs (swipePts s) (swipeEnd s)) :: goPieces (swipeEnd s) ss

/-- The pieces of a profile; joined they are `compile`. -/
def pieces (p : Profile) : List (List Act) :=
  match (p.swipes.filter fun s => !s.samples.isEmpty) with
  | [] => []
  | s :: ss =>
    match swipePts s with
    | [] => []
    | f :: _ => goPieces f.m (s :: ss)

/-- How long the client waits for the call of a piece that takes `d` ms before it names the call hung. -/
def pieceTimeoutMs (d : Nat) : Nat := 2 * d + 10000

theorem goPieces_join : ∀ (prev : Int) (ss : List Swipe), (goPieces prev ss).flatten = goActs prev ss := by
  intro prev ss
  induction ss generalizing prev with
  | nil => simp [goPieces, goActs]
  | cons s ss ih =>
    unfold goPieces goActs
    split
    · exact ih prev
    · simp [ih]

theorem pieces_join (p : Profile) : (pieces p).flatten = compile p := by
  unfold pieces compile
  split
  · simp
  · split
    · simp
    · exact goPieces_join _ _

theorem pieces_dur_le (p : Profile) : ∀ pc ∈ pieces p, ∀ a ∈ pc, 0 ≤ a.dur ∧ a.dur ≤ tickMax := by
  intro pc hpc a ha
  apply compile_dur_le p a
  rw [← pieces_join]
  exact List.mem_flatten.mpr ⟨pc, hpc, ha⟩

theorem pieces_targets (p : Profile) : ((pieces p).flatMap fun pc => pc.filterMap Act.target) = (compile p).filterMap Act.target := by
  rw [← pieces_join, List.filterMap_flatten]
  simp [List.flatMap_def]

theorem lt_pieceTimeoutMs (d : Nat) : d < pieceTimeoutMs d := by
  unfold pieceTimeoutMs; omega

theorem pieceTimeoutMs_mono {a b : Nat} (h : a ≤ b) : pieceTimeoutMs a ≤ pieceTimeoutMs b := by
  unfold pieceTimeoutMs; omega

theorem pieceTimeoutMs_floor (d : Nat) : 10000 ≤ pieceTimeoutMs d := by
  unfold pieceTimeoutMs; omega

theorem goPieces_length : ∀ (prev : Int) (ss : List Swipe), (∀ s ∈ ss, s.samples ≠ []) → (goPieces prev ss).length = ss.length := by
  intro prev ss
  induction ss generalizing prev with
  | nil => intro _; simp [goPieces]
  | cons s ss ih =>
    intro h
    have hs : swipePts s ≠ [] := by
      have := h s (by simp)
      unfold swipePts
      simpa using this
    unfold goPieces
    split
    · rename_i h2; exact absurd h2 hs
    · simp [ih _ (fun t ht => h t (by simp [ht]))]

theorem pieces_length (p : Profile) : (pieces p).length = (p.swipes.filter fun s => !s.samples.isEmpty).length := by
  unfold pieces
  split
  · rename_i h; rw [h]; rfl
  · rename_i s ss h
    split
    · rename_i h2
      exfalso
      have hs : s ∈ p.swipes.filter fun s => !s.samples.isEmpty := by rw [h]; simp
      simp only [List.mem_filter, Bool.not_eq_true', List.isEmpty_eq_false_iff] at hs
      unfold swipePts at h2
      simp at h2
      exact hs.2 h2
    · rw [h, goPieces_length]
      intro t ht
      have : t ∈ p.swipes.filter fun s => !s.samples.isEmpty := by rw [h]; simp [ht]
      simp only [List.mem_filter, Bool.not_eq_true', List.isEmpty_eq_false_iff] at this
      exact this.2

/-- A move or a pause: an action that neither puts the finger down nor lifts it. -/
def Act.isStep : Act → Bool
  | .move .. => true
  | .pause _ => true
  | _ => false

theorem pauseRun_steps (n : Nat) : ∀ a ∈ pauseRun n, a.isStep = true := by
  intro a ha
  unfold pauseRun at ha
  split at ha
  · simp at ha
  · simp only [List.mem_map] at ha
    obtain ⟨c, _, rfl⟩ := ha
    rfl

theorem emit_steps : ∀ (n : Nat) (p : Pt) (rest : List Pt) (fin : Int), rest.length = n →
    ∀ a ∈ emit p rest fin, a.isStep = true := by
  intro n
  induction n with
  | zero =>
    intro p rest fin hr a ha
    have : rest = [] := List.length_eq_zero_iff.mp hr
    subst this
    unfold emit at ha
    simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at ha
    rcases ha with rfl | ha
    · rfl
    · exact pauseRun_steps _ a ha
  | succ n ih =>
    intro p rest fin hr a ha
    match rest, hr with
    | q :: qs, hr =>
      unfold emit at ha
      simp only [List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at ha
      rcases ha with (rfl | ha) | ha
      · rfl
      · exact pauseRun_steps _ a ha
      · exact ih q qs fin (by simpa using hr) a ha

/-- A swipe's actions are its steps with one finger down before and one finger up after the later ones: `[move, down] ++ steps ++ [up]`. -/
theorem swipeActs_shape (f : Pt) (rest : List Pt) (fin : Int) :
    ∃ steps : List Act, (∀ a ∈ steps, a.isStep = true) ∧ swipeActs (f :: rest) fin = [.move f.x f.y 0, .down] ++ steps ++ [.up] := by
  unfold swipeActs
  match rest with
  | [] => exact ⟨pauseRun (gap f.m (nextMs [] fin)), pauseRun_steps _, by simp⟩
  | q :: qs =>
    refine ⟨pauseRun (gap f.m (nextMs (q :: qs) fin)) ++ emit q qs fin, ?_, by simp⟩
    intro a ha
    rcases List.mem_append.mp ha with ha | ha
    · exact pauseRun_steps _ a ha
    · exact emit_steps _ q qs fin rfl a ha

theorem goPieces_mem : ∀ (prev : Int) (ss : List Swipe) (pc : List Act), pc ∈ goPieces prev ss →
    ∃ (prev' : Int) (s : Swipe) (f : Pt) (rest : List Pt), swipePts s = f :: rest ∧
      pc = pauseRun (gap prev' f.m) ++ swipeActs (f :: rest) (swipeEnd s) := by
  intro prev ss
  induction ss generalizing prev with
  | nil => intro pc h; simp [goPieces] at h
  | cons s ss ih =>
    intro pc h
    unfold goPieces at h
    split at h
    · exact ih prev pc h
    · rename_i f rest hf
      rcases List.mem_cons.mp h with rfl | h
      · exact ⟨prev, s, f, rest, hf, by rw [← hf]⟩
      · exact ih _ pc h

theorem piece_shape {prev' : Int} {f : Pt} {rest : List Pt} {fin : Int} {pc : List Act}
    (h : pc = pauseRun (gap prev' f.m) ++ swipeActs (f :: rest) fin) :
    pc.count .down = 1 ∧ pc.count .up = 1 ∧ pc.getLast? = some .up := by
  obtain ⟨steps, hs, he⟩ := swipeActs_shape f rest fin
  have hp : ∀ a ∈ pauseRun (gap prev' f.m), a.isStep = true := pauseRun_steps _
  have step_ne : ∀ (l : List Act), (∀ a ∈ l, a.isStep = true) → ∀ b : Act, b.isStep = false → b ∉ l := by
    intro l hl b hb hm
    have := hl b hm
    rw [hb] at this
    exact Bool.noConfusion this
  have c1 : (pauseRun (gap prev' f.m)).count .down = 0 := List.count_eq_zero.mpr (step_ne _ hp _ rfl)
  have c2 : steps.count .down = 0 := List.count_eq_zero.mpr (step_ne _ hs _ rfl)
  have c3 : (pauseRun (gap prev' f.m)).count .up = 0 := List.count_eq_zero.mpr (step_ne _ hp _ rfl)
  have c4 : steps.count .up = 0 := List.count_eq_zero.mpr (step_ne _ hs _ rfl)
  subst h
  rw [he]
  refine ⟨?_, ?_, ?_⟩
  · simp [List.count_append, c1, c2]
  · simp [List.count_append, c3, c4]
  · rw [← List.append_assoc]
    exact List.getLast?_concat

theorem pieces_shape (p : Profile) : ∀ pc ∈ pieces p, pc.count .down = 1 ∧ pc.count .up = 1 ∧ pc.getLast? = some .up := by
  intro pc hpc
  unfold pieces at hpc
  split at hpc
  · simp at hpc
  · split at hpc
    · simp at hpc
    · obtain ⟨_, _, _, _, _, h⟩ := goPieces_mem _ _ pc hpc
      exact piece_shape h

theorem piece_dur_sum {prev : Int} {f : Pt} {rest : List Pt} {fin : Int} (hc : chain f.m rest fin) :
    ((pauseRun (gap prev f.m) ++ swipeActs (f :: rest) fin).map Act.dur).sum = (gap prev f.m : Int) + (fin - f.m) := by
  simp only [List.map_append, List.sum_append, pauseRun_dur_sum, swipeActs_dur_sum f rest fin hc]

theorem pieces_dur_sum (p : Profile) :
    (((pieces p).map fun pc => (pc.map Act.dur).sum)).sum = ((compile p).map Act.dur).sum := by
  rw [← pieces_join]
  have : ∀ l : List (List Act), (l.flatten.map Act.dur).sum = (l.map fun pc => (pc.map Act.dur).sum).sum := by
    intro l
    induction l with
    | nil => simp
    | cons a l ih => simp only [List.flatten_cons, List.map_append, List.sum_append, List.map_cons, List.sum_cons, ih]
  exact (this _).symm

/-! ## What the page sees of a replay -/

/-- The samples whose whole px differ from the sample kept before them. -/
def keep : Int × Int → List Sample → List Sample
  | _, [] => []
  | prev, e :: es =>
    if (px e.x, px e.y) = prev then keep prev es else e :: keep (px e.x, px e.y) es

/-- Where the last sample is. -/
def lastPos (s : Swipe) : Int × Int :=
  match s.samples.getLast? with
  | some e => (e.x, e.y)
  | none => (0, 0)

/-- The events a swipe of the source should make the page see: touch start, a move per change of whole px, touch end. -/
def expected (s : Swipe) : List Sample :=
  match s.samples with
  | [] => []
  | f :: r => f :: keep (px f.x, px f.y) r ++ [⟨s.lift, (lastPos s).1, (lastPos s).2⟩]

/-- The events a recorded replay swipe made the page see, every one of them. -/
def seen (s : Swipe) : List Sample :=
  match s.samples with
  | [] => []
  | _ => s.samples ++ [⟨s.lift, (lastPos s).1, (lastPos s).2⟩]

/-- The limits of the replay check; the defaults are the research's proposals, to be calibrated on the pilot. -/
structure Lim where
  pos : Int := 10
  time : Int := 1700
  speedPct : Int := 10
  startGap : Int := 5000
  window : Int := 5000
  deriving Repr

/-- The lift-off velocity of events as (dx, dy, dt): the move over the last `window`, dt at least 1. -/
def liftVel (window : Int) (evs : List Sample) : Int × Int × Int :=
  match evs.getLast? with
  | none => (0, 0, 1)
  | some z =>
    match evs.find? (fun e => decide (z.t - window ≤ e.t)) with
    | some a => (z.x - a.x, z.y - a.y, max 1 (z.t - a.t))
    | none => (0, 0, 1)

/-- The same number of events. -/
def eventsOk (a b : Swipe) : Bool := decide ((expected a).length = (seen b).length)

/-- Every event within `lim.pos` of the source's event, in each axis. -/
def posOk (lim : Lim) (a b : Swipe) : Bool :=
  ((expected a).zip (seen b)).all fun (e, r) =>
    decide (-lim.pos ≤ r.x - e.x ∧ r.x - e.x ≤ lim.pos ∧ -lim.pos ≤ r.y - e.y ∧ r.y - e.y ≤ lim.pos)

/-- Every event within `lim.time` of the source's event, both relative to their swipe's first event. -/
def timeOk (lim : Lim) (a b : Swipe) : Bool :=
  ((expected a).zip (seen b)).all fun (e, r) => decide (-lim.time ≤ r.t - e.t ∧ r.t - e.t ≤ lim.time)

/-- The lift-off velocity within `lim.speedPct` percent of the source's, as a vector, by cross-multiplication. -/
def speedOk (lim : Lim) (a b : Swipe) : Bool :=
  match liftVel lim.window (expected a), liftVel lim.window (seen b) with
  | (ax, ay, at_), (bx, by_, bt) =>
    let ex := bx * at_ - ax * bt
    let ey := by_ * at_ - ay * bt
    decide (10000 * (ex * ex + ey * ey) ≤ lim.speedPct * lim.speedPct * ((ax * bt) * (ax * bt) + (ay * bt) * (ay * bt)))

/-- The swipe starts within `lim.startGap` of the source's start, both relative to their pass's first swipe. -/
def startOk (lim : Lim) (a b : Swipe) : Bool :=
  decide (-lim.startGap ≤ b.start - a.start ∧ b.start - a.start ≤ lim.startGap)

/-- One swipe of the replay matches the source's: every conjunct holds. -/
def swipeMatches (lim : Lim) (a b : Swipe) : Bool :=
  eventsOk a b && posOk lim a b && timeOk lim a b && speedOk lim a b && startOk lim a b

/-- A replay pass matches its source when it has the same number of swipes and each swipe matches on its own. -/
def replayMatches (lim : Lim) (src rep : List Swipe) : Bool :=
  decide (src.length = rep.length) && (src.zip rep).all fun (a, b) => swipeMatches lim a b

theorem replayMatches_count {lim : Lim} {src rep : List Swipe} (h : replayMatches lim src rep = true) :
    src.length = rep.length := by
  unfold replayMatches at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.1

theorem replayMatches_swipe {lim : Lim} {src rep : List Swipe} (h : replayMatches lim src rep = true) {a b : Swipe}
    (hm : (a, b) ∈ src.zip rep) : swipeMatches lim a b = true := by
  unfold replayMatches at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  exact h.2 (a, b) hm

theorem replayMatches_of {lim : Lim} {src rep : List Swipe} (hc : src.length = rep.length)
    (h : ∀ a b, (a, b) ∈ src.zip rep → swipeMatches lim a b = true) : replayMatches lim src rep = true := by
  unfold replayMatches
  simp only [Bool.and_eq_true, List.all_eq_true, decide_eq_true_eq]
  exact ⟨hc, fun p hp => h p.1 p.2 hp⟩

theorem replayMatches_false_of_swipe {lim : Lim} {src rep : List Swipe} {a b : Swipe} (hm : (a, b) ∈ src.zip rep)
    (hf : swipeMatches lim a b = false) : replayMatches lim src rep = false := by
  cases h : replayMatches lim src rep
  · rfl
  · rw [replayMatches_swipe h hm] at hf; exact absurd hf (by simp)

theorem replayMatches_false_of_count {lim : Lim} {src rep : List Swipe} (h : src.length ≠ rep.length) :
    replayMatches lim src rep = false := by
  cases h' : replayMatches lim src rep
  · rfl
  · exact absurd (replayMatches_count h') h

theorem swipeMatches_events {lim : Lim} {a b : Swipe} (h : swipeMatches lim a b = true) : eventsOk a b = true := by
  unfold swipeMatches at h; simp only [Bool.and_eq_true] at h; exact h.1.1.1.1

theorem swipeMatches_pos {lim : Lim} {a b : Swipe} (h : swipeMatches lim a b = true) : posOk lim a b = true := by
  unfold swipeMatches at h; simp only [Bool.and_eq_true] at h; exact h.1.1.1.2

theorem swipeMatches_time {lim : Lim} {a b : Swipe} (h : swipeMatches lim a b = true) : timeOk lim a b = true := by
  unfold swipeMatches at h; simp only [Bool.and_eq_true] at h; exact h.1.1.2

theorem swipeMatches_speed {lim : Lim} {a b : Swipe} (h : swipeMatches lim a b = true) : speedOk lim a b = true := by
  unfold swipeMatches at h; simp only [Bool.and_eq_true] at h; exact h.1.2

theorem swipeMatches_start {lim : Lim} {a b : Swipe} (h : swipeMatches lim a b = true) : startOk lim a b = true := by
  unfold swipeMatches at h; simp only [Bool.and_eq_true] at h; exact h.2

theorem swipeMatches_of {lim : Lim} {a b : Swipe} (h1 : eventsOk a b = true) (h2 : posOk lim a b = true)
    (h3 : timeOk lim a b = true) (h4 : speedOk lim a b = true) (h5 : startOk lim a b = true) :
    swipeMatches lim a b = true := by
  simp [swipeMatches, h1, h2, h3, h4, h5]

theorem swipeMatches_false_events {lim : Lim} {a b : Swipe} (h : eventsOk a b = false) : swipeMatches lim a b = false := by
  simp [swipeMatches, h]

theorem swipeMatches_false_pos {lim : Lim} {a b : Swipe} (h : posOk lim a b = false) : swipeMatches lim a b = false := by
  simp [swipeMatches, h]

theorem swipeMatches_false_time {lim : Lim} {a b : Swipe} (h : timeOk lim a b = false) : swipeMatches lim a b = false := by
  simp [swipeMatches, h]

theorem swipeMatches_false_speed {lim : Lim} {a b : Swipe} (h : speedOk lim a b = false) : swipeMatches lim a b = false := by
  simp [swipeMatches, h]

theorem swipeMatches_false_start {lim : Lim} {a b : Swipe} (h : startOk lim a b = false) : swipeMatches lim a b = false := by
  simp [swipeMatches, h]

theorem eventsOk_length {a b : Swipe} (h : eventsOk a b = true) : (expected a).length = (seen b).length := by
  simpa [eventsOk] using h

theorem posOk_spec {lim : Lim} {a b : Swipe} (h : posOk lim a b = true) {e r : Sample} (hm : (e, r) ∈ (expected a).zip (seen b)) :
    -lim.pos ≤ r.x - e.x ∧ r.x - e.x ≤ lim.pos ∧ -lim.pos ≤ r.y - e.y ∧ r.y - e.y ≤ lim.pos := by
  unfold posOk at h
  simp only [List.all_eq_true, decide_eq_true_eq] at h
  exact h (e, r) hm

theorem timeOk_spec {lim : Lim} {a b : Swipe} (h : timeOk lim a b = true) {e r : Sample} (hm : (e, r) ∈ (expected a).zip (seen b)) :
    -lim.time ≤ r.t - e.t ∧ r.t - e.t ≤ lim.time := by
  unfold timeOk at h
  simp only [List.all_eq_true, decide_eq_true_eq] at h
  exact h (e, r) hm

theorem startOk_spec {lim : Lim} {a b : Swipe} (h : startOk lim a b = true) :
    -lim.startGap ≤ b.start - a.start ∧ b.start - a.start ≤ lim.startGap := by
  simpa [startOk] using h

theorem startOk_self {lim : Lim} (h : 0 ≤ lim.startGap) (a : Swipe) : startOk lim a a = true := by
  simp [startOk]; omega

end Fw.Device.Replay
