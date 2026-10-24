import Fw.Device.ThrottleParts
import Fw.Parts.EngineScrollUnthrottle
/-!
# engine.scroll:unthrottle-follow
A frame loop that keeps requesting frames while scrollY moves; WebPageIOS.mm:2240-2256, LocalFrameView.cpp:3784-3790, Page.cpp:2294-2329@862f17d.
-/
namespace Fw.Parts.EngineScrollFollow

open Fw.Device.StillRuns Fw.Device.ThrottleParts
open Fw.Parts.EngineScrollUnthrottle (Env)

/-- Still frames in a row after which the loop stops requesting frames. -/
def stillMax : Nat := 8

/-- Most frames one gesture may request. -/
def frameCap : Nat := 3600

/-- The loop: the scrollY read at the previous frame, the still frames since the last move, the frames run, and whether the next frame is requested. -/
structure St where
  last : Int
  still : Nat
  frames : Nat
  on : Bool
deriving Repr, DecidableEq

/-- The idle loop at position `y`. -/
def St.init (y : Int) : St := ⟨y, 0, 0, false⟩

/-- The state after the first moved frame of a gesture. -/
def St.wake (y : Int) : St := ⟨y, 0, 1, true⟩

/-- One frame that read `y`; `ended` is a `scrollend` seen since the previous frame. -/
def step (s : St) (y : Int) (ended : Bool) : St :=
  if s.on then
    let still := if y = s.last then s.still + 1 else 0
    let frames := s.frames + 1
    ⟨y, still, frames, !ended && decide (still < stillMax) && decide (frames < frameCap)⟩
  else if y = s.last then s
  else St.wake y

/-- The frames of one gesture: each reads the next position while the loop requests one; returns the final state and the frames run. -/
def drive : St → List Int → St × Nat
  | s, [] => (s, 0)
  | s, y :: ys =>
    if s.on then
      let r := drive (step s y false) ys
      (r.1, r.2 + 1)
    else (s, 0)

/-- Frames the loop requests, by environment: none without a coarse pointer. -/
def stepG (e : Env) (s : St) (y : Int) (ended : Bool) : St := if e.coarse then step s y ended else s

/-- The invariant of every reachable state. -/
def Inv (s : St) : Prop := s.on = true → s.still < stillMax ∧ s.frames < frameCap

theorem inv_init (y : Int) : Inv (St.init y) := by simp [Inv, St.init]

theorem inv_wake (y : Int) : Inv (St.wake y) := by
  simp [Inv, St.wake, stillMax, frameCap]

theorem inv_step (s : St) (y : Int) (ended : Bool) (h : Inv s) : Inv (step s y ended) := by
  unfold step
  split
  · intro hon
    simp only [Bool.and_eq_true, Bool.not_eq_true', decide_eq_true_eq] at hon ⊢
    exact ⟨hon.1.2, hon.2⟩
  · split
    · exact h
    · exact inv_wake y

/-- Idle costs zero frames: an idle loop at an unmoved position stays idle and requests nothing. -/
theorem idle_zero (s : St) (y : Int) (ended : Bool) (h : s.on = false) (hy : y = s.last) : step s y ended = s := by
  simp [step, h, hy]

theorem drive_idle (s : St) (h : s.on = false) (ys : List Int) : drive s ys = (s, 0) := by
  cases ys <;> simp [drive, h]

/-- An idle loop over any run of frames runs none. -/
theorem idle_drive_zero (y : Int) (ys : List Int) : (drive (St.init y) ys).2 = 0 := by
  rw [drive_idle _ rfl]

/-- A fine pointer never wakes the loop. -/
theorem fine_never_requests (e : Env) (hf : e.coarse = false) (s : St) (y : Int) (ended : Bool) :
    stepG e s y ended = s := by simp [stepG, hf]

/-- A coarse pointer runs the loop's own step. -/
theorem coarse_steps (e : Env) (hc : e.coarse = true) (s : St) (y : Int) (ended : Bool) :
    stepG e s y ended = step s y ended := by simp [stepG, hc]

/-- A moved frame wakes an idle loop. -/
theorem wakes_on_move (s : St) (y : Int) (ended : Bool) (h : s.on = false) (hy : y ≠ s.last) :
    step s y ended = St.wake y := by simp [step, h, hy]

/-- `scrollend` stops a running loop. -/
theorem scrollend_stops (s : St) (y : Int) (h : s.on = true) : (step s y true).on = false := by
  simp [step, h]

theorem drive_frames_le (ys : List Int) : ∀ (s : St), Inv s → s.on = true →
    (drive s ys).2 + s.frames ≤ frameCap := by
  induction ys with
  | nil => intro s hi hon; have := (hi hon).2; simp [drive]; omega
  | cons y ys ih =>
    intro s hi hon
    have hf := (hi hon).2
    simp only [drive, hon, ite_true]
    have hs : (step s y false).frames = s.frames + 1 := by simp [step, hon]
    by_cases h' : (step s y false).on = true
    · have := ih _ (inv_step s y false hi) h'
      omega
    · have h0 : (step s y false).on = false := by simpa using h'
      rw [drive_idle _ h0]
      simp; omega

/-- **The loop stops by the cap.** A gesture of any length runs at most `frameCap` loop frames. -/
theorem frames_bounded (y : Int) (ys : List Int) : (drive (St.wake y) ys).2 + 1 ≤ frameCap := by
  have := drive_frames_le ys (St.wake y) (inv_wake y) rfl
  simpa [St.wake] using this

/-- Runs of still frames keep the loop on until `stillMax`. -/
theorem drive_still (n : Nat) : ∀ (s : St), s.on = true → s.still + n < stillMax → s.frames + n < frameCap →
    drive s (List.replicate n s.last) = (⟨s.last, s.still + n, s.frames + n, true⟩, n) := by
  induction n with
  | zero => intro s hon _ _; simp [drive]; cases s; simp_all
  | succ n ih =>
    intro s hon h1 h2
    have e : step s s.last false = ⟨s.last, s.still + 1, s.frames + 1, true⟩ := by
      simp [step, hon]; omega
    simp only [List.replicate_succ, drive, hon, ite_true, e]
    have := ih ⟨s.last, s.still + 1, s.frames + 1, true⟩ rfl (by simp; omega) (by simp; omega)
    simp only at this
    rw [this]
    simp [Nat.add_assoc, Nat.add_comm 1 n, Nat.add_left_comm]

/-- **The loop stops after `stillMax` still frames.** From any running state, that many frames at the last read position turn it off. -/
theorem stops_after_still (n : Nat) : ∀ (s : St), Inv s → stillMax ≤ s.still + n → 1 ≤ n →
    (drive s (List.replicate n s.last)).1.on = false := by
  induction n with
  | zero => intro _ _ _ h; omega
  | succ n ih =>
    intro s hinv hk _
    by_cases hon : s.on = true
    · have e : step s s.last false =
          ⟨s.last, s.still + 1, s.frames + 1, decide (s.still + 1 < stillMax) && decide (s.frames + 1 < frameCap)⟩ := by
        simp [step, hon]
      simp only [List.replicate_succ, drive, hon, ite_true]
      by_cases h' : (step s s.last false).on = true
      · have hi := inv_step s s.last false hinv
        have hl : (step s s.last false).last = s.last := by simp [step, hon]
        have hs : (step s s.last false).still = s.still + 1 := by simp [step, hon]
        have n1 : 1 ≤ n := by
          rcases Nat.eq_zero_or_pos n with h0 | h0
          · subst h0
            have hh := (hinv hon).1
            rw [e] at h'
            simp only [Bool.and_eq_true, decide_eq_true_eq] at h'
            omega
          · exact h0
        have := ih (step s s.last false) hi (by rw [hs]; omega) n1
        rw [hl] at this
        simpa using this
      · have h0 : (step s s.last false).on = false := by simpa using h'
        rw [drive_idle _ h0]; exact h0
    · have h0 : s.on = false := by simpa using hon
      simp [List.replicate_succ, drive, h0]

/-- **A throttled series does not stop the loop.** The loop outlasts the 5 to 6 still frames that a 100 ms throttle leaves. -/
theorem stillMax_gt_band : bandHi < stillMax := by decide

/-- A plateau of `p` frames at a new position leaves the loop running when `p ≤ stillMax`, `p` frames fit in the cap. -/
theorem plateau_survives (s : St) (hon : s.on = true) (z : Int) (hz : z ≠ s.last) (p : Nat)
    (hp : 1 ≤ p) (hpm : p ≤ stillMax) (hcap : s.frames + p < frameCap) :
    (drive s (List.replicate p z)).1.on = true := by
  obtain ⟨q, rfl⟩ : ∃ q, p = q + 1 := ⟨p - 1, by omega⟩
  have e : step s z false = ⟨z, 0, s.frames + 1, true⟩ := by
    have h1 : 0 < stillMax := by decide
    have h2 : s.frames + 1 < frameCap := by omega
    simp [step, hon, hz, h1, h2]
  simp only [List.replicate_succ, drive, hon, ite_true, e]
  have := drive_still q ⟨z, 0, s.frames + 1, true⟩ rfl (by simp; omega) (by simp; omega)
  simp only at this
  rw [this]

/-- **A moving gesture runs a frame at every update.** While every update moves, the loop runs one frame per update and stays on. -/
theorem moving_runs_every_update (ys : List Int) : ∀ (s : St) , s.on = true → Fw.Device.StillRuns.moves (s.last :: ys) = true →
    s.frames + ys.length < frameCap → (drive s ys).2 = ys.length := by
  induction ys with
  | nil => intro s _ _ _; simp [drive]
  | cons y ys ih =>
    intro s hon hm hf
    simp only [Fw.Device.StillRuns.moves, Bool.and_eq_true, bne_iff_ne, ne_eq] at hm
    have h1 : 0 < stillMax := by decide
    have h2 : s.frames + 1 < frameCap := by simp at hf; omega
    have e : step s y false = ⟨y, 0, s.frames + 1, true⟩ := by
      simp [step, hon, Ne.symm hm.1, h1, h2]
    simp only [drive, hon, ite_true, e]
    have := ih ⟨y, 0, s.frames + 1, true⟩ rfl (by simpa using hm.2) (by simp at hf ⊢; omega)
    simp only [List.length_cons]
    rw [this]

/-- The frames the event-driven engine runs in `n` updates when `scroll` fires once per `p`-update window. -/
def eventFrames (p n : Nat) : Nat := (n + p - 1) / p

/-- **More frames while moving.** In a throttled window the loop runs a frame at every moving update; events run one per window. -/
theorem follow_gt_event (p n : Nat) (hp : 2 ≤ p) (hn : 2 ≤ n) : eventFrames p n < n := by
  unfold eventFrames
  apply (Nat.div_lt_iff_lt_mul (by omega)).2
  obtain ⟨q, rfl⟩ : ∃ q, p = q + 2 := ⟨p - 2, by omega⟩
  have h1 : q ≤ n * q := Nat.le_mul_of_pos_left q (by omega)
  have h2 : n * (q + 2) = n * q + 2 * n := by rw [Nat.mul_add]; omega
  omega

/-- With no delay (`p = 1`) the engine already runs a frame per update. -/
theorem eventFrames_one (n : Nat) : eventFrames 1 n = n := by simp [eventFrames]

/-- **The loop gains frames exactly when the event is delayed.** Over two or more moving updates it beats the engine iff the window is two updates or more. -/
theorem gain_iff (p n : Nat) (hp : 1 ≤ p) (hn : 2 ≤ n) : eventFrames p n < n ↔ 2 ≤ p := by
  constructor
  · intro h
    by_cases h2 : 2 ≤ p
    · exact h2
    · have : p = 1 := by omega
      subst this
      rw [eventFrames_one] at h
      omega
  · intro h2
    exact follow_gt_event p n h2 hn

/-- **Each frame reads the newest scrollY.** A loop frame at update `t` reads `u t`, which is what an unthrottled engine reads. -/
theorem follow_reads_newest (p : Nat) (u : Nat → Int) (t : Nat) : u t = seen .lifted p u t := rfl

/-- A throttled event reads a position up to `p - 1` updates old. -/
theorem event_read_age_lt (p t : Nat) (hp : 0 < p) : t - p * (t / p) < p := by
  have := Nat.mod_lt t hp
  rw [Nat.mod_def] at this
  exact this

/-- **Outputs stay functions of scrollY.** A part whose frame output is `f y` shows `f (u t)` at every loop frame, as the lifted mode does. -/
theorem follow_same_look (p : Nat) (u : Nat → Int) (f : Int → Int) (t : Nat) :
    f (u t) = shown .mainThread .lifted p u f t := rfl

/-- The loop adds no CSS: the variant's style text is the unthrottle text. -/
def css : String := Fw.Parts.EngineScrollUnthrottle.css

end Fw.Parts.EngineScrollFollow
