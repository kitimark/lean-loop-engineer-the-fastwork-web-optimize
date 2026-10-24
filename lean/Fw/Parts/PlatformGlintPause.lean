import Fw.Parts.PlatformGlint
/-!
# platform.glint:offscreen-pause: pause the SMIL clock offscreen, seek it from the document clock on return

The glint's two `<animate>` elements run on the SMIL clock of their `<svg>`. The variant calls `pauseAnimations()` on
the svg when the stage leaves the viewport and, on return, `unpauseAnimations()` then `setCurrentTime` with the value
the clock would show had it never stopped, read from the document clock (`performance.now()`) and an offset stored at
the pause. This file models the WebKit time container, the pause policy and the joint play state, and proves two
things: on every frame where the glint is visible its SMIL phase is the uninterrupted phase (`local_time_same`), and
while the stage is away the container fires no timer (`variant_no_ticks_away`).

WebKit source, pinned `862f17dcae0a` (WebKit-7625.1.29.10.29):

* `Source/WebCore/svg/animation/SMILTimeContainer.cpp:94-100` `elapsed()`: frozen `m_accumulatedActiveTime` while paused,
  else `now + accumulated - lastResumeTime`; `SMILTimeContainer.h:83` `lastResumeTime = m_resumeTime ? m_resumeTime : m_beginTime`;
* `SMILTimeContainer.cpp:141-150` `pause()` adds `now - lastResumeTime` to the accumulated time and stops the timer;
* `SMILTimeContainer.cpp:152-162` `resume()` sets the resume time to now;
* `SMILTimeContainer.cpp:164-194` `setElapsed(x)`: begin time `now - x`, resume time cleared, accumulated `x` if paused, else 0;
* `SMILTimeContainer.cpp:196-208` `startTimer` returns at once while paused: **no timer is armed while paused**;
* `SMILTimeContainer.cpp:42-43,86-91` the timer delay is 1/60 s, 1/30 s in Low Power Mode, so one tick per rendering update at most;
* `Source/WebCore/svg/SVGSVGElement.cpp:551-566,585-593` `pauseAnimations`, `unpauseAnimations`, `getCurrentTime`
  (`elapsed()`), `setCurrentTime` (`setElapsed`).

Not modelled: the clamp of `setCurrentTime` at 0 (`SVGSVGElement.cpp:593`; the targets here are never negative because the container began before the first report) and the float32 seconds of `getCurrentTime` and `setCurrentTime` (a rounding of a millisecond fraction after
hours), and the delivery time of the observer callback (premises in the part's `part.json`). Times are in ms, `Rat`.
-/
namespace Fw.Parts.PlatformGlintPause
open Fw.Parts.PlatformGlint (St sample)

/-! ## 1. The time container -/

/-- The three fields of a begun container: `m_accumulatedActiveTime`, `lastResumeTime()` and `isPaused()`. -/
structure Cont where
  accum : Rat
  last : Rat
  paused : Bool
deriving Repr, DecidableEq

/-- A container that began at document time `b` and was never touched. -/
def Cont.start (b : Rat) : Cont := ⟨0, b, false⟩

/-- `elapsed()` at document time `t` (SMILTimeContainer.cpp:94-100). -/
def Cont.elapsed (c : Cont) (t : Rat) : Rat := if c.paused then c.accum else t + c.accum - c.last

/-- `pauseAnimations()` at `t` (SVGSVGElement.cpp:551-555, SMILTimeContainer.cpp:141-150). -/
def Cont.pause (c : Cont) (t : Rat) : Cont :=
  if c.paused then c else { accum := c.accum + (t - c.last), last := c.last, paused := true }

/-- `unpauseAnimations()` at `t` (SVGSVGElement.cpp:558-562, SMILTimeContainer.cpp:152-162). -/
def Cont.resume (c : Cont) (t : Rat) : Cont :=
  if c.paused then { accum := c.accum, last := t, paused := false } else c

/-- `setCurrentTime(x)` at `t`, `x` in ms (SMILTimeContainer.cpp:164-194). -/
def Cont.seek (c : Cont) (t x : Rat) : Cont :=
  { accum := if c.paused then x else 0, last := t - x, paused := c.paused }

/-- Timer fires at one rendering update: none while paused (`startTimer` returns, :198), at most one otherwise, and
only when an animation is scheduled (`armed`). -/
def ticks (c : Cont) (armed : Bool) : Nat := if c.paused then 0 else if armed then 1 else 0

theorem elapsed_start (b s : Rat) : (Cont.start b).elapsed s = s - b := by
  simp [Cont.start, Cont.elapsed]; grind

/-- A paused container shows the value it had at the pause, whatever the time is now. -/
theorem pause_frozen (c : Cont) (t s : Rat) (h : c.paused = false) :
    (c.pause t).elapsed s = c.elapsed t := by
  simp [Cont.pause, Cont.elapsed, h]; grind

theorem pause_paused (c : Cont) (t : Rat) : (c.pause t).paused = true := by
  unfold Cont.pause; split <;> simp_all

theorem ticks_paused (c : Cont) (hp : c.paused = true) (armed : Bool) : ticks c armed = 0 := by
  simp [ticks, hp]

/-- Seeking a running container to `x` makes it show `x + (s - t)` at `s`. -/
theorem seek_running (c : Cont) (t x s : Rat) (h : c.paused = false) : (c.seek t x).elapsed s = s - t + x := by
  simp [Cont.seek, Cont.elapsed, h]; grind

theorem resume_running (c : Cont) (t : Rat) : (c.resume t).paused = false := by
  unfold Cont.resume; split <;> simp_all

/-! ## 2. The pause policy -/

/-- The driver state for one svg: the container and the offset `clock - document time`, stored at the pause. -/
structure P where
  c : Cont
  off : Rat
deriving Repr, DecidableEq

/-- The observer reports the stage away (`hide`) or back (`reveal`) at document time `t`. -/
inductive Obs
  | hide (t : Rat)
  | reveal (t : Rat)
deriving Repr, DecidableEq

/-- Hide: store `off = getCurrentTime() - now()` and pause. Reveal after a pause: unpause, then
`setCurrentTime(now() + off)`. A repeat of either does nothing (the calls are guarded by `paused`). -/
def P.step (p : P) : Obs → P
  | .hide t => if p.c.paused then p else ⟨p.c.pause t, p.c.elapsed t - t⟩
  | .reveal t => if p.c.paused then ⟨(p.c.resume t).seek t (t + p.off), p.off⟩ else p

/-- The seek target of a reveal in ms, `none` when nothing is paused (no call). -/
def P.target (p : P) (t : Rat) : Option Rat := if p.c.paused then some (t + p.off) else none

/-- The uninterrupted clock: a container that began at `b` shows `s - b`. -/
def Same (b : Rat) (p : P) : Prop :=
  p.off = -b ∧ (p.c.paused = false → ∀ s, p.c.elapsed s = s - b)

theorem same_start (b : Rat) : Same b ⟨Cont.start b, -b⟩ := ⟨rfl, fun _ s => elapsed_start b s⟩

theorem same_step (b : Rat) (p : P) (o : Obs) (h : Same b p) : Same b (p.step o) := by
  obtain ⟨ho, hr⟩ := h
  cases o with
  | hide t =>
    by_cases hp : p.c.paused = true
    · have e : p.step (.hide t) = p := by simp [P.step, hp]
      rw [e]; exact ⟨ho, hr⟩
    · have hp' : p.c.paused = false := by simpa using hp
      have e : p.step (.hide t) = ⟨p.c.pause t, p.c.elapsed t - t⟩ := by simp [P.step, hp]
      rw [e]
      refine ⟨?_, fun h => by simp [pause_paused] at h⟩
      show p.c.elapsed t - t = -b
      rw [hr hp']; grind
  | reveal t =>
    by_cases hp : p.c.paused = true
    · have e : p.step (.reveal t) = ⟨(p.c.resume t).seek t (t + p.off), p.off⟩ := by simp [P.step, hp]
      rw [e]
      refine ⟨ho, fun _ s => ?_⟩
      show ((p.c.resume t).seek t (t + p.off)).elapsed s = s - b
      rw [seek_running _ _ _ _ (resume_running _ _), ho]; grind
    · have e : p.step (.reveal t) = p := by simp [P.step, hp]
      rw [e]; exact ⟨ho, hr⟩

/-- **Same clock.** From a fresh container, after any sequence of hides and reveals, a running container shows the
uninterrupted value at every time. -/
theorem same_run (b : Rat) (p : P) (h : Same b p) (os : List Obs) : Same b (os.foldl P.step p) := by
  induction os generalizing p with
  | nil => exact h
  | cons o os ih => exact ih _ (same_step b p o h)

/-! ## 3. The glint and the observer together -/

/-- Events of the stage: the observer's ratio (the glint's `ratio`), reduced motion, the start timer. -/
inductive Io
  | ratio (r : Rat)
  | reduced (b : Bool)
  | fire
deriving Repr

/-- The glint's play state, the pause driver, and whether the last observer report was "not intersecting". -/
structure W where
  g : St
  p : P
  away : Bool
deriving Repr

def W.init (b : Rat) (reduced : Bool) : W :=
  ⟨Fw.Parts.PlatformGlint.init reduced, ⟨Cont.start b, -b⟩, false⟩

/-- One event at document time `t`. The observer's `isIntersecting` is `0 < r`; the callback pauses on `r = 0`
and reveals on `0 < r`, before the glint sees the ratio. -/
def W.step (w : W) (t : Rat) : Io → W
  | .ratio r =>
    { g := Fw.Parts.PlatformGlint.step w.g t (.ratio r)
      p := w.p.step (if r = 0 then .hide t else .reveal t)
      away := decide (r = 0) }
  | .reduced b => { w with g := Fw.Parts.PlatformGlint.step w.g t (.reduced b) }
  | .fire => { w with g := Fw.Parts.PlatformGlint.step w.g t .fire }

/-- The invariant of a stage that began at `b`. -/
structure J (b : Rat) (w : W) : Prop where
  same : Same b w.p
  glint : Fw.Parts.PlatformGlint.Inv w.g
  seen : w.g.h = true → w.p.c.paused = false
  away : w.away = true → w.p.c.paused = true ∧ w.g.h = false

theorem J_init (b : Rat) (r : Bool) : J b (W.init b r) :=
  ⟨same_start b, Fw.Parts.PlatformGlint.inv_init r, by simp [W.init, Fw.Parts.PlatformGlint.init],
    by simp [W.init]⟩

theorem minRatio_zero : decide (Fw.Parts.PlatformGlint.minRatio ≤ 0) = false := by
  unfold Fw.Parts.PlatformGlint.minRatio
  simp only [decide_eq_false_iff_not, Rat.not_le]
  grind

theorem h_ratio (g : St) (t r : Rat) :
    (Fw.Parts.PlatformGlint.step g t (.ratio r)).h = decide (Fw.Parts.PlatformGlint.minRatio ≤ r) := by
  unfold Fw.Parts.PlatformGlint.step Fw.Parts.PlatformGlint.reset
  simp only []
  by_cases hb : (decide (Fw.Parts.PlatformGlint.minRatio ≤ r) == g.h) = true
  · simp only [hb, ite_true]; simp_all
  · simp [hb]

theorem h_reduced (g : St) (t : Rat) (b : Bool) : (Fw.Parts.PlatformGlint.step g t (.reduced b)).h = g.h := by
  simp [Fw.Parts.PlatformGlint.step, Fw.Parts.PlatformGlint.reset]

theorem h_fire (g : St) (t : Rat) : (Fw.Parts.PlatformGlint.step g t .fire).h = g.h := by
  unfold Fw.Parts.PlatformGlint.step
  cases g.timer with
  | none => rfl
  | some d => simp only []; split <;> rfl

theorem J_step (b : Rat) (w : W) (t : Rat) (e : Io) (hj : J b w) : J b (w.step t e) := by
  obtain ⟨hs, hg, hseen, haway⟩ := hj
  cases e with
  | ratio r =>
    have hh := h_ratio w.g t r
    have hP : Same b (w.p.step (if r = 0 then .hide t else .reveal t)) := same_step b _ _ hs
    refine ⟨hP, Fw.Parts.PlatformGlint.inv_step _ _ _ hg, ?_, ?_⟩
    · intro hh'
      simp only [W.step] at hh' ⊢
      by_cases h0 : r = 0
      · subst h0
        rw [minRatio_zero] at hh
        simp [hh] at hh'
      · have : (if r = 0 then Obs.hide t else Obs.reveal t) = Obs.reveal t := by simp [h0]
        rw [this]
        by_cases hp : w.p.c.paused = true
        · have e : w.p.step (.reveal t) = ⟨(w.p.c.resume t).seek t (t + w.p.off), w.p.off⟩ := by simp [P.step, hp]
          rw [e]; simp [resume_running, Cont.seek]
        · have e : w.p.step (.reveal t) = w.p := by simp [P.step, hp]
          rw [e]; simpa using hp
    · intro ha
      simp only [W.step, decide_eq_true_eq] at ha ⊢
      subst ha
      refine ⟨?_, ?_⟩
      · simp only [ite_true]
        by_cases hp : w.p.c.paused = true
        · have e : w.p.step (.hide t) = w.p := by simp [P.step, hp]
          rw [e]; exact hp
        · have e : w.p.step (.hide t) = ⟨w.p.c.pause t, w.p.c.elapsed t - t⟩ := by simp [P.step, hp]
          rw [e]; exact pause_paused _ _
      · rw [minRatio_zero] at hh
        exact hh
  | reduced bb =>
    refine ⟨hs, Fw.Parts.PlatformGlint.inv_step _ _ _ hg, ?_, ?_⟩
    · intro hh'; simp only [W.step, h_reduced] at hh'; exact hseen hh'
    · intro ha; simp only [W.step, h_reduced]; exact haway ha
  | fire =>
    refine ⟨hs, Fw.Parts.PlatformGlint.inv_step _ _ _ hg, ?_, ?_⟩
    · intro hh'; simp only [W.step, h_fire] at hh'; exact hseen hh'
    · intro ha; simp only [W.step, h_fire]; exact haway ha

theorem J_run (b : Rat) (w : W) (hj : J b w) (es : List (Rat × Io)) :
    J b (es.foldl (fun w x => w.step x.1 x.2) w) := by
  induction es generalizing w with
  | nil => exact hj
  | cons x es ih => exact ih _ (J_step b w x.1 x.2 hj)

/-! ## 4. Theorems -/

/-- **Same phase on every visible frame.** Whenever the glint is playing, its container is running and shows the
uninterrupted value `s - b`, after any trace of events. -/
theorem visible_same_phase (b : Rat) (w : W) (hj : J b w) (hv : w.g.v = true) (s : Rat) :
    w.p.c.paused = false ∧ w.p.c.elapsed s = s - b := by
  have hh : w.g.h = true := (hj.glint.1 hv).1
  have hp := hj.seen hh
  exact ⟨hp, hj.same.2 hp s⟩

/-- **Local time.** The glint begins (`beginElement`) at document time `t0` while playing, and is drawn at `s`
in a later playing state: its local time is `s - t0`, the one of the uninterrupted container. So `sample` agrees with
`PlatformGlint.view`, and the faithful arm. -/
theorem local_time_same (b : Rat) (w1 w2 : W) (h1 : J b w1) (h2 : J b w2) (v1 : w1.g.v = true) (v2 : w2.g.v = true)
    (t0 s : Rat) (side : Fw.Parts.PlatformGlint.Side) :
    sample side (w2.p.c.elapsed s - w1.p.c.elapsed t0) = sample side (s - t0) := by
  rw [(visible_same_phase b w1 h1 v1 t0).2, (visible_same_phase b w2 h2 v2 s).2]
  congr 1; grind

/-- The faithful arm's container is never touched. -/
theorem faithful_local_time (b s t0 : Rat) (side : Fw.Parts.PlatformGlint.Side) :
    sample side ((Cont.start b).elapsed s - (Cont.start b).elapsed t0) = sample side (s - t0) := by
  rw [elapsed_start, elapsed_start]; congr 1; grind

/-- **No SMIL tick while the stage is away (variant).** After an observer report of "not intersecting", the
container is paused and fires no timer, whether or not an `<animate>` is still mounted. -/
theorem variant_no_ticks_away (b : Rat) (w : W) (hj : J b w) (ha : w.away = true) (armed : Bool) :
    ticks w.p.c armed = 0 :=
  ticks_paused _ (hj.away ha).1 armed

/-- **No SMIL tick while the stage is away (faithful).** The play flag is clear whenever the stage is away
(`PlatformGlint.Inv`: playing implies visible), so the `<animate>` pair is not mounted and the unpaused container has
nothing scheduled. The mount follows the flag at the next commit (a named premise). -/
theorem faithful_no_ticks_away (b : Rat) (w : W) (hj : J b w) (ha : w.away = true) (c : Cont) :
    ticks c w.g.v = 0 := by
  have hh := (hj.away ha).2
  have hv : w.g.v = false := by
    cases hv : w.g.v
    · rfl
    · have := (hj.glint.1 hv).1; simp_all
  simp [ticks, hv]

/-- **The gain is zero in this model.** While away, faithful and variant fire the same number of ticks (none),
because the faithful arm has already unmounted its animations; the variant only helps in the commit window
between the observer report and the unmount, where `armed` is still true. -/
theorem away_ticks_equal (b : Rat) (w : W) (hj : J b w) (ha : w.away = true) :
    ticks (Cont.start b) w.g.v = ticks w.p.c w.g.v :=
  (faithful_no_ticks_away b w hj ha _).trans (variant_no_ticks_away b w hj ha _).symm

/-- In the commit window the pause removes the tick the faithful arm still fires. -/
theorem window_gain (b : Rat) (w : W) (hj : J b w) (ha : w.away = true) :
    ticks w.p.c true = 0 ∧ ticks (Cont.start b) true = 1 :=
  ⟨variant_no_ticks_away b w hj ha true, by simp [ticks, Cont.start]⟩

/-! ## 5. Examples -/

/-- Container began at 0; hide at 1000, reveal at 4000: the clock shows 4000 at 4000, as if never stopped. -/
def eg : P := ((⟨Cont.start 0, 0⟩ : P).step (.hide 1000)).step (.reveal 4000)

#guard eg.c.elapsed 4000 == 4000
#guard eg.c.elapsed 4500 == 4500
#guard (((⟨Cont.start 0, 0⟩ : P).step (.hide 1000)).c.elapsed 3000) == 1000
#guard ((Cont.start 0).pause 1000 |>.resume 4000).elapsed 4000 == 1000

end Fw.Parts.PlatformGlintPause
