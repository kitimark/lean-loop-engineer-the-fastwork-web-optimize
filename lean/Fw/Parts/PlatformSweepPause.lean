import Fw.Parts.PlatformSweep
/-!
# `platform.sweep:offscreen-pause`: the sweep stops ticking while its element is offscreen, and shows the same phase

Named premise `Running` (TS guard, not proved about the engine): the watcher `watchSweepPause` (apps/site/src/parts/platform.sweep/pause.ts)
reads `getAnimations()` at each report and pauses every running animation. A loop with a start time resumes with that start time, which is `seek`
to `orig`. A loop with no start time yet (a play still pending) has current time 0 or the hold time, and resumes at that time plus the time
paused (`resumeTime`), within one frame of `orig` (INFERRED, both engines).
Named premises `Scene` and `Override` (WebKit CONFIRMED, Chromium INFERRED the same): the platform section's CSS rule starts a loop again when the scene
attribute turns active, also one whose word is still out of the viewport; the watcher holds the reported elements again on that attribute change
(MutationObserver, no per-frame work). A script `pause()` overrides the CSS play state for good (`Override`, CSSAnimation.cpp:278-287@862f17d), so
the rule no longer freezes a held loop; the watcher tracks the spans with the scene paused and leaves them out. See "Held loops" below.
-/
namespace Fw.Parts.PlatformSweepPause
open Fw.Parts.PlatformSweep (phase pos)

/-- A frame: length in ms, visible, reported offscreen. -/
abbrev Step := Rat × Bool × Bool

def Ok (f : Step) : Prop := f.2.2 = true → f.2.1 = false

structure St where
  loc : Rat
  clk : Rat
  paused : Bool
  off : Rat
deriving Repr

def init (o : Rat) : St := ⟨o, 0, false, o⟩

def seek (s : St) (f : Step) : St :=
  if f.2.2 then { s with paused := true }
  else if s.paused then { s with paused := false, loc := s.clk + s.off } else s

def tick (s : St) (f : Step) : St :=
  { s with clk := s.clk + f.1, loc := if f.2.2 then s.loc else s.loc + f.1 }

def step (s : St) (f : Step) : St := tick (seek s f) f

def run (s : St) (tr : List Step) : St := tr.foldl step s

def ticks (f : Step) : Nat := if f.2.2 then 0 else 1

def orig (o : Rat) (tr : List Step) : Rat := o + (tr.map (·.1)).sum

#guard (run (init 100) [(16, true, false), (16, false, false), (16, false, true), (16, false, true), (16, true, false)]).loc
  == orig 100 [(16, true, false), (16, false, false), (16, false, true), (16, false, true), (16, true, false)]
#guard (seek ⟨7, 50, true, 3⟩ (16, true, false)).loc == 53
#guard (seek ⟨7, 50, false, 3⟩ (16, true, false)).loc == 7
#guard ticks (16, false, true) == 0 && ticks (16, true, false) == 1

def Inv (s : St) (c : Rat) : Prop := s.clk = c ∧ (s.paused = false → s.loc = c + s.off)

theorem init_inv (o : Rat) : Inv (init o) 0 := by
  simp [Inv, init]
  grind

theorem seek_shown (s : St) (c : Rat) (f : Step) (hI : Inv s c) (hh : f.2.2 = false) :
    (seek s f).loc = c + s.off := by
  obtain ⟨h0, h1⟩ := hI
  unfold seek
  rw [hh]
  cases hs : s.paused
  · simpa using h1 hs
  · simp [h0]

theorem step_inv (s : St) (c : Rat) (f : Step) (hI : Inv s c) : Inv (step s f) (c + f.1) ∧ (step s f).off = s.off := by
  obtain ⟨h0, h1⟩ := hI
  obtain ⟨d, v, r⟩ := f
  unfold step seek tick Inv
  cases r <;> cases hs : s.paused <;> simp_all <;> grind

theorem run_inv (s : St) (c : Rat) (tr : List Step) (hI : Inv s c) :
    Inv (run s tr) (c + (tr.map (·.1)).sum) ∧ (run s tr).off = s.off := by
  induction tr generalizing s c with
  | nil =>
    have : c + ((([] : List Step).map (·.1)).sum) = c := by simp; grind
    rw [this]; exact ⟨hI, rfl⟩
  | cons f tr ih =>
    obtain ⟨h1, h2⟩ := step_inv s c f hI
    obtain ⟨h3, h4⟩ := ih (step s f) (c + f.1) h1
    refine ⟨?_, by simpa [run, h2] using h4⟩
    have : c + ((f :: tr).map (·.1)).sum = c + f.1 + (tr.map (·.1)).sum := by simp only [List.map_cons, List.sum_cons]; grind
    rw [this]
    exact h3

theorem shown_same (o : Rat) (pre : List Step) (f : Step) (hh : f.2.2 = false) :
    (seek (run (init o) pre) f).loc = orig o pre := by
  obtain ⟨hI, hoff⟩ := run_inv (init o) 0 pre (init_inv o)
  rw [seek_shown _ _ f hI hh, hoff]
  simp [orig, init]; grind

theorem visible_same (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    (seek (run (init o) pre) f).loc = orig o pre := by
  apply shown_same
  cases h : f.2.2
  · rfl
  · have := hok h; simp_all

theorem visible_phase (o : Rat) (pre : List Step) (f : Step) (hok : Ok f) (hv : f.2.1 = true) :
    phase (seek (run (init o) pre) f).loc = phase (orig o pre) ∧
    pos (seek (run (init o) pre) f).loc = pos (orig o pre) := by
  rw [visible_same o pre f hok hv]; exact ⟨rfl, rfl⟩

theorem reported_no_tick (s : St) (f : Step) (hr : f.2.2 = true) : (step s f).loc = s.loc ∧ ticks f = 0 := by
  simp [step, seek, tick, hr, ticks]

theorem reported_run (s : St) (tr : List Step) (h : ∀ f ∈ tr, f.2.2 = true) : (run s tr).loc = s.loc := by
  induction tr generalizing s with
  | nil => rfl
  | cons f tr ih =>
    have := (reported_no_tick s f (h f (by simp))).1
    simpa [run, this] using ih (step s f) (fun g hg => h g (by simp [hg]))

def Lag (p f : Step) : Prop := p.2.1 = false → f.2.1 = false → f.2.2 = true

def totalTicks (tr : List Step) : Nat := (tr.map ticks).sum

def LagList : Step → List Step → Prop
  | _, [] => True
  | p, f :: tr => Lag p f ∧ LagList f tr

theorem offscreen_ticks_le_one (g : Step) (rest : List Step) (hv : g.2.1 = false ∧ ∀ f ∈ rest, f.2.1 = false)
    (hl : LagList g rest) : totalTicks (g :: rest) ≤ 1 := by
  have key : ∀ (p : Step) (tr : List Step), p.2.1 = false → (∀ f ∈ tr, f.2.1 = false) → LagList p tr →
      totalTicks tr = 0 := by
    intro p tr
    induction tr generalizing p with
    | nil => intros; rfl
    | cons f tr ih =>
      intro hp hf hl
      have hr : f.2.2 = true := hl.1 hp (hf f (by simp))
      have := ih f (hf f (by simp)) (fun g hg => hf g (by simp [hg])) hl.2
      simp [totalTicks, ticks, hr] at this ⊢
      exact this
  have := key g rest hv.1 hv.2 hl
  simp only [totalTicks, List.map_cons, List.sum_cons] at this ⊢
  have h0 : ticks g ≤ 1 := by unfold ticks; split <;> omega
  omega

theorem ticks_le_original (f : Step) : ticks f ≤ 1 := by unfold ticks; split <;> omega

/-! ## Held loops: scene-frozen spans

The watcher holds a running loop with a script `pause()`. WebKit then keeps the loop's play state overridden for good
(Source/WebCore/animation/CSSAnimation.cpp:278-287@862f17d: after `play()` or `pause()`, `m_overriddenProperties` gets `PlayState`), so the
platform section's CSS rule (`animation-play-state: paused` while the scene attribute is `paused`) no longer freezes a loop the watcher has
resumed or holds. That fact is the named premise `Override` (CONFIRMED for WebKit, INFERRED for Chromium). Without tracking, a resumed loop
shows its hold phase plus all the wall-clock time (`untracked`), which the flag-off page does not: there the rule freezes it while the scene is
paused. The flag-off phase (`Unpaused`) is the hold phase plus the sum of the durations of the spans in which the scene was active.

The hold is a list of spans (duration, scene active). The TS state is `Held`: `cur` the active time so far (starting at the loop's current
time), `fz` the frozen time so far, `since` the clock at the last close, `frozen` the scene state of the open span. `advance` adds one closed
span; `close` closes the open span at a clock value; `setScene` closes it and opens the next one (the MutationObserver callback). A resume
calls `close` and reads `cur` (no start time) or `fz` (a start time: the start moves later by the frozen time). A hold of a loop with a start
time saves `cur = since - start`, because a running loop shows the clock minus its start time (premise `Clock`). -/

abbrev Span := Rat × Bool

/-- A held loop: active time so far, frozen time so far, clock at the last close, scene frozen in the open span. -/
structure Held where
  cur : Rat
  fz : Rat
  since : Rat
  frozen : Bool
deriving Repr

/-- One closed span of the given duration and scene state. -/
def advance (h : Held) (s : Span) : Held :=
  if s.2 then { h with cur := h.cur + s.1, since := h.since + s.1 }
  else { h with fz := h.fz + s.1, since := h.since + s.1 }

/-- Close the open span at clock `now`: it counts as frozen or active by the saved scene state. -/
def close (h : Held) (now : Rat) : Held :=
  if h.frozen then { h with fz := h.fz + (now - h.since), since := now }
  else { h with cur := h.cur + (now - h.since), since := now }

/-- The scene attribute changed at `now`: close the open span, open one with the new state. -/
def setScene (h : Held) (now : Rat) (active : Bool) : Held := { close h now with frozen := !active }

/-- The time a no-start-time loop resumes at. -/
def resumeTime (h : Held) (now : Rat) : Rat := (close h now).cur

/-- The frozen time a loop with a start time moves its start by. -/
def startShift (h : Held) (now : Rat) : Rat := (close h now).fz

def activeSum (spans : List Span) : Rat := ((spans.filter (·.2)).map (·.1)).sum

def frozenSum (spans : List Span) : Rat := ((spans.filter (fun s => !s.2)).map (·.1)).sum

def totalSum (spans : List Span) : Rat := (spans.map (·.1)).sum

/-- What the flag-off page shows: the hold phase plus the durations of the spans in which the scene was active (the CSS rule runs the loop only then). -/
def Unpaused (cur : Rat) (spans : List Span) : Rat := cur + activeSum spans

/-- What a held loop shows without tracking, once the script pause has overridden the CSS rule (premise `Override`). -/
def untracked (cur : Rat) (spans : List Span) : Rat := cur + totalSum spans

theorem activeSum_cons (s : Span) (t : List Span) : activeSum (s :: t) = (if s.2 then s.1 else 0) + activeSum t := by
  unfold activeSum
  cases h : s.2 <;> simp [h] <;> grind

theorem frozenSum_cons (s : Span) (t : List Span) : frozenSum (s :: t) = (if s.2 then 0 else s.1) + frozenSum t := by
  unfold frozenSum
  cases h : s.2 <;> simp [h] <;> grind

theorem totalSum_cons (s : Span) (t : List Span) : totalSum (s :: t) = s.1 + totalSum t := by
  simp [totalSum]

theorem total_split (spans : List Span) : totalSum spans = activeSum spans + frozenSum spans := by
  induction spans with
  | nil => simp [totalSum, activeSum, frozenSum]; grind
  | cons s t ih =>
    rw [totalSum_cons, activeSum_cons, frozenSum_cons, ih]
    cases s.2 <;> simp <;> grind

theorem advance_cur (h : Held) (s : Span) : (advance h s).cur = h.cur + (if s.2 then s.1 else 0) := by
  unfold advance; split <;> simp_all <;> grind

theorem advance_fz (h : Held) (s : Span) : (advance h s).fz = h.fz + (if s.2 then 0 else s.1) := by
  unfold advance; split <;> simp_all <;> grind

theorem advance_since (h : Held) (s : Span) : (advance h s).since = h.since + s.1 := by
  unfold advance; split <;> simp

/-- The fold of `advance` over the spans: all three accumulators, by induction. -/
theorem fold_core (h : Held) (spans : List Span) :
    (spans.foldl advance h).cur = Unpaused h.cur spans ∧ (spans.foldl advance h).fz = h.fz + frozenSum spans ∧
    (spans.foldl advance h).since = h.since + totalSum spans := by
  induction spans generalizing h with
  | nil => simp [Unpaused, activeSum, frozenSum, totalSum]; grind
  | cons s t ih =>
    obtain ⟨h1, h2, h3⟩ := ih (advance h s)
    simp only [List.foldl_cons]
    rw [advance_cur] at h1
    rw [advance_fz] at h2
    rw [advance_since] at h3
    unfold Unpaused at h1 ⊢
    rw [activeSum_cons, frozenSum_cons, totalSum_cons]
    refine ⟨?_, ?_, ?_⟩ <;> grind

theorem fold_cur (h : Held) (spans : List Span) : (spans.foldl advance h).cur = Unpaused h.cur spans :=
  (fold_core h spans).1

/-- The fold equals the flag-off phase, and the page without tracking differs from it by exactly the frozen time. -/
theorem untracked_off (cur : Rat) (spans : List Span) : untracked cur spans = Unpaused cur spans + frozenSum spans := by
  unfold untracked Unpaused
  rw [total_split]; grind

/-- A scene-frozen span of positive length makes the untracked page differ (the path of the refused round: hidden, scene paused, scrolled back). -/
theorem untracked_differs (cur : Rat) (spans : List Span) (hz : 0 < frozenSum spans) :
    untracked cur spans ≠ Unpaused cur spans := by
  rw [untracked_off]; grind

/-- The spans an event list cuts the hold into: from `since` with scene state `frozen`, each event (clock, new active) ends one span. -/
def spansOf : Rat → Bool → List (Rat × Bool) → Rat → List Span
  | since, frozen, [], now => [(now - since, !frozen)]
  | since, frozen, e :: rest, now => (e.1 - since, !frozen) :: spansOf e.1 (!e.2) rest now

/-- The TS handler: the events applied one by one with `setScene`. -/
def events (h : Held) (evs : List (Rat × Bool)) : Held := evs.foldl (fun g e => setScene g e.1 e.2) h

def core (h : Held) : Rat × Rat × Rat := (h.cur, h.fz, h.since)

theorem close_core (h : Held) (now : Rat) : core (close h now) = core (advance h (now - h.since, !h.frozen)) := by
  unfold close advance core
  cases h.frozen <;> simp <;> grind

theorem fold_core_ext (h h' : Held) (hc : core h = core h') (l : List Span) :
    core (l.foldl advance h) = core (l.foldl advance h') := by
  have a := fold_core h l
  have b := fold_core h' l
  simp only [core, Prod.mk.injEq] at hc ⊢
  obtain ⟨c1, c2, c3⟩ := hc
  unfold Unpaused at a b
  refine ⟨?_, ?_, ?_⟩ <;> grind

/-- The event handler closed at the resume equals the span fold: the TS event code is the span model. -/
theorem events_core (h : Held) (evs : List (Rat × Bool)) (now : Rat) :
    core (close (events h evs) now) = core ((spansOf h.since h.frozen evs now).foldl advance h) := by
  induction evs generalizing h with
  | nil =>
    simp only [events, List.foldl_nil, spansOf, List.foldl_cons, List.foldl_nil]
    exact close_core h now
  | cons e rest ih =>
    have := ih (setScene h e.1 e.2)
    simp only [events, List.foldl_cons] at this ⊢
    rw [this]
    simp only [spansOf, List.foldl_cons]
    have hs : (setScene h e.1 e.2).since = e.1 := by simp [setScene, close]; cases h.frozen <;> simp
    have hf : (setScene h e.1 e.2).frozen = !e.2 := by simp [setScene]
    rw [hs, hf]
    apply fold_core_ext
    have hc := close_core h e.1
    unfold setScene
    simpa [core] using hc

/-- No start time: the resumed time equals the flag-off phase over the spans (not by `rfl`: it is the fold above). -/
theorem resume_same (h : Held) (evs : List (Rat × Bool)) (now : Rat) :
    resumeTime (events h evs) now = Unpaused h.cur (spansOf h.since h.frozen evs now) := by
  have := congrArg (·.1) (events_core h evs now)
  simpa [core, resumeTime, fold_cur] using this

/-- Any looking function of the resumed loop equals the one of the flag-off page. -/
theorem look_same_pending {α : Type} (g : Rat → α) (h : Held) (evs : List (Rat × Bool)) (now : Rat) :
    g (resumeTime (events h evs) now) = g (Unpaused h.cur (spansOf h.since h.frozen evs now)) := by
  rw [resume_same]

theorem resume_pending_phase (h : Held) (evs : List (Rat × Bool)) (now : Rat) :
    phase (resumeTime (events h evs) now) = phase (Unpaused h.cur (spansOf h.since h.frozen evs now)) ∧
    pos (resumeTime (events h evs) now) = pos (Unpaused h.cur (spansOf h.since h.frozen evs now)) := by
  rw [resume_same]; exact ⟨rfl, rfl⟩

/-- A loop with a start time `st` (premise `Clock`: `h.cur = h.since - st` at the hold) resumes with start `st + startShift`: it shows `now - start`, the flag-off phase. -/
theorem start_same (h : Held) (st : Rat) (hc : h.cur = h.since - st) (hfz : h.fz = 0) (evs : List (Rat × Bool)) (now : Rat) :
    now - (st + startShift (events h evs) now) = Unpaused h.cur (spansOf h.since h.frozen evs now) := by
  have e := events_core h evs now
  have f := fold_core h (spansOf h.since h.frozen evs now)
  simp only [core, Prod.mk.injEq] at e
  obtain ⟨e1, e2, e3⟩ := e
  obtain ⟨f1, f2, f3⟩ := f
  have cl : (close (events h evs) now).since = now := by unfold close; cases (events h evs).frozen <;> simp
  have tot := total_split (spansOf h.since h.frozen evs now)
  unfold startShift
  unfold Unpaused at f1 ⊢
  grind

/-- Hold one running animation: skipped when already held (first hold wins), not running left alone. -/
def holdNew (held running : Bool) : Bool := !held && running

theorem hold_already_held (running : Bool) : holdNew true running = false := by simp [holdNew]

theorem hold_running_new : holdNew false true = true := rfl

theorem hold_not_running (held : Bool) : holdNew held false = false := by simp [holdNew]

/-- The held table: animation id to its saved hold. `hold` inserts only an id not yet present. -/
def hold (H : List (Nat × Held)) (a : Nat) (h : Held) : List (Nat × Held) :=
  if H.any (·.1 == a) then H else (a, h) :: H

theorem hold_present (H : List (Nat × Held)) (a : Nat) (h : Held) (hp : H.any (·.1 == a) = true) :
    hold H a h = H := by simp [hold, hp]

/-- A re-hold on a scene attribute change never moves an earlier hold. -/
theorem rehold_keeps (H : List (Nat × Held)) (a : Nat) (h h' : Held) :
    hold (hold H a h) a h' = hold H a h := by
  unfold hold
  by_cases hp : H.any (·.1 == a) = true
  · simp [hp]
  · simp at hp
    simp [hp]

/-- The scene re-hold is idempotent on the held table. -/
theorem rehold_idem (H : List (Nat × Held)) (a : Nat) (h : Held) : hold (hold H a h) a h = hold H a h :=
  rehold_keeps H a h h

#guard resumeTime (Held.mk 250 0 1000 false) 1400 == 650
#guard resumeTime (Held.mk 0 0 5 false) 5 == 0
#guard resumeTime (events (Held.mk 100 0 0 false) [(30, false), (80, true)]) 100 == 100 + 30 + 20
#guard startShift (events (Held.mk 100 0 0 false) [(30, false), (80, true)]) 100 == 50
#guard holdNew false true && !holdNew true true && !holdNew false false

end Fw.Parts.PlatformSweepPause
