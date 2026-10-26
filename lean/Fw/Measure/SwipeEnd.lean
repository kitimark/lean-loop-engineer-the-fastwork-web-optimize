import Fw.Measure.Profile
import Fw.Measure.OffscreenWindows

namespace Fw.Measure.SwipeEnd
open Fw.Measure.Profile Fw.Measure.OffscreenWindows

def windowReach : Nat := ((pushWindows 0 1000).getLast?.map (·.lo)).getD 0

theorem windowReach_eq : windowReach = 120 := rfl

theorem windowReach_spec (e last : Nat) (h : e + windowReach ≤ last) :
    (pushWindows e last).getLast?.map (·.lo) = some (e + windowReach) := by
  rw [windowReach_eq] at h ⊢
  show some (clip last (e + 120)) = some (e + 120)
  simp only [clip, Option.some.injEq]
  omega

def endWinFrames : Nat := 40

def windowTail : Nat := windowReach + endWinFrames

def _root_.Fw.Measure.Profile.Swipe.tail (s : Swipe) : Nat := max windowTail (s.idleFrames + s.holdFrames + 1)

def endFrameOf (n idle : Nat) : Nat := n - idle

def limitEnd (limit y : Nat) : Bool := decide (limit ≤ y)

def endReason (limit y : Nat) : String := if limitEnd limit y then "limit" else "stalled"

def _root_.Fw.Measure.Profile.Swipe.stopAt (s : Swipe) (e nf : Nat) : Nat := max (e + s.tail) (nf + s.holdFrames + 1)

def _root_.Fw.Measure.Profile.Swipe.stops (s : Swipe) (e n : Nat) (done : Bool) : Bool := done && decide (e + s.tail ≤ n)

theorem tail_ge_window (s : Swipe) : windowTail ≤ s.tail := Nat.le_max_left _ _

theorem tail_ge_stall (s : Swipe) : s.idleFrames + s.holdFrames + 1 ≤ s.tail := Nat.le_max_right _ _

theorem endFrameOf_add (e k : Nat) : endFrameOf (e + k) k = e := by
  unfold endFrameOf; omega

theorem endFrameOf_limit (n : Nat) : endFrameOf n 0 = n := rfl

theorem limitEnd_of_ended (s : Swipe) (limit y idle : Nat) (h : s.ended limit y idle = true) (hn : limitEnd limit y = false) :
    limit ≤ y + s.band ∧ s.idleFrames ≤ idle := by
  unfold Swipe.ended at h
  simp only [limitEnd, decide_eq_false_iff_not, Bool.or_eq_true, decide_eq_true_eq, Bool.and_eq_true] at h hn
  rcases h with h | h
  · exact absurd h hn
  · exact h

theorem endReason_limit (limit y : Nat) (h : limit ≤ y) : endReason limit y = "limit" := by
  simp [endReason, limitEnd, h]

theorem endReason_stalled (limit y : Nat) (h : y < limit) : endReason limit y = "stalled" := by
  have : ¬ limit ≤ y := by omega
  simp [endReason, limitEnd, this]

theorem stopAt_ge (s : Swipe) (e nf : Nat) : e + s.tail ≤ s.stopAt e nf := Nat.le_max_left _ _

theorem stopAt_limit (s : Swipe) (e : Nat) : s.stopAt e e = e + s.tail := by
  have := tail_ge_stall s
  unfold Swipe.stopAt
  omega

theorem stopAt_stalled (s : Swipe) (e nf : Nat) (h : nf ≤ e + s.idleFrames) : s.stopAt e nf = e + s.tail := by
  have := tail_ge_stall s
  unfold Swipe.stopAt
  omega

theorem stopAt_same_tail (s : Swipe) (e : Nat) : s.stopAt e e = s.stopAt e (e + s.idleFrames) := by
  rw [stopAt_limit, stopAt_stalled s e _ (Nat.le_refl _)]

theorem stopAt_ge_lift (s : Swipe) (e nf : Nat) : nf + s.holdFrames + 1 ≤ s.stopAt e nf := Nat.le_max_right _ _

theorem stops_before (s : Swipe) (e n : Nat) (done : Bool) (h : n < e + s.tail) : s.stops e n done = false := by
  have : ¬ e + s.tail ≤ n := by omega
  simp [Swipe.stops, this]

theorem stops_at (s : Swipe) (e : Nat) : s.stops e (e + s.tail) true = true := by
  simp [Swipe.stops]

theorem stops_first (s : Swipe) (e nf n : Nat) (h : nf ≤ e + s.idleFrames) :
    s.stops e n (decide (nf + s.holdFrames + 1 ≤ n)) = true ↔ s.stopAt e nf ≤ n := by
  rw [stopAt_stalled s e nf h]
  have := tail_ge_stall s
  simp only [Swipe.stops, Bool.and_eq_true, decide_eq_true_eq]
  omega

theorem stops_first_limit (s : Swipe) (e n : Nat) :
    s.stops e n (decide (e + s.holdFrames + 1 ≤ n)) = true ↔ e + s.tail ≤ n := by
  rw [stops_first s e e n (by omega), stopAt_limit]

theorem recorded_frames (s : Swipe) (e : Nat) : s.stopAt e e + 1 - e = s.tail + 1 := by
  rw [stopAt_limit]; omega

theorem windows_within_tail (s : Swipe) (e eRun : Nat) (hr : e ≤ eRun) :
    ∀ w ∈ allWindows e (lastFrame (eRun + s.tail + 1 + touchTail) touchTail), w.hi ≤ eRun + s.tail + 1 := by
  intro w hw
  have hl : lastFrame (eRun + s.tail + 1 + touchTail) touchTail = eRun + s.tail + 1 := by
    unfold lastFrame; omega
  rw [hl] at hw
  simp only [allWindows, pushWindows, finishWin, clip, List.mem_append, List.mem_cons, List.not_mem_nil, or_false] at hw
  rcases hw with (rfl | rfl | rfl | rfl | rfl) | rfl <;> simp only <;> omega

theorem end_windows_full (s : Swipe) (e eRun : Nat) (h1 : approachFrames ≤ e) (hr : e ≤ eRun) :
    (pushWindows e (eRun + s.tail + 1)).map Win.len = [34, 20, 40, 60, eRun + s.tail + 1 - (e + 120)] ∧
      endWinFrames ≤ eRun + s.tail + 1 - (e + 120) := by
  have hw := tail_ge_window s
  have h2 : e + 120 ≤ eRun + s.tail + 1 := by
    unfold windowTail windowReach endWinFrames at hw
    rw [show ((pushWindows 0 1000).getLast?.map (·.lo)).getD 0 = 120 from rfl] at hw
    omega
  refine ⟨pushWindows_lens e _ h1 h2, ?_⟩
  unfold windowTail endWinFrames at hw
  rw [windowReach_eq] at hw
  unfold endWinFrames
  omega

theorem swipeTouchV1_tail : swipeTouchV1.tail = 165 ∧ windowTail = 160 ∧ swipeTouchV1.stopAt 575 575 = 740 := by decide

theorem swipeTouchV1_stalled_unchanged : swipeTouchV1.stopAt 575 (575 + swipeTouchV1.idleFrames) = 575 + swipeTouchV1.idleFrames + swipeTouchV1.holdFrames + 1 := by decide

theorem swipeTouchV1_tail_in_budget : swipeTouchV1.tail ≤ swipeTouchV1.budget fontPageMaxScroll := by decide

end Fw.Measure.SwipeEnd
