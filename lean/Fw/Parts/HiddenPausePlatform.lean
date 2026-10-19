import Fw.Parts.HiddenPause
import Fw.Parts.PlatformScene
/-!
# engine.scene `hidden-pause` on the platform section: the clock the variant seeks with

The platform's own rule (`PlatformScene`) freezes its animations while the section is not near. The variant also pauses
them while the section does not meet the viewport, and on return adds the scene clock's advance over the hidden span,
where the clock runs only while the section is active. Proves `hsync` of `HiddenPause.hiddenPause_visSame` against the
original's local time `PlatformScene.local'`. Consumer: `apps/site/src/parts/engine.scene` (golden `engine.scene.jsonl`).
-/
namespace Fw.Parts.HiddenPausePlatform
open Fw.Engine
open Fw.Parts.HiddenPause (Tmpl inst HiddenOrStill hiddenPause_visSame sceneHidden)
open Fw.Parts.PlatformScene (local' advance origFrames near)

/-- One frame of the variant: its length in ms, the section's scene activity (`watchActive`) and whether the variant
hides it (`sceneHidden`).

A frame is a duration, an activity flag and a hidden flag. -/
abbrev Step := Rat × Bool × Bool

/-- A frame the two observers can report: a section that is not hidden is active.

Meeting the viewport implies being near it (`meets_near`). -/
def Ok (f : Step) : Prop := f.2.2 = false → f.2.1 = true

/-- The variant's state for one animation: its local time, the scene clock, whether it is hidden, and the clock at the
last hide.

The four values `engine.scene` keeps per section and animation. -/
structure St where
  loc : Rat
  clk : Rat
  hid : Bool
  mark : Rat
deriving Repr

/-- The observer callbacks at a frame's start: a hide records the clock, an unhide adds the clock's advance since the
hide to local time (a `currentTime` seek); otherwise nothing changes.

Hiding marks the clock; showing again moves the animation forward by the clock's advance while hidden. -/
def seek (s : St) (f : Step) : St :=
  if f.2.2 then (if s.hid then s else { s with hid := true, mark := s.clk })
  else (if s.hid then { s with hid := false, loc := s.loc + (s.clk - s.mark) } else s)

/-- The frame's time passes: local time advances only while neither rule pauses (not hidden and active), the clock while
active.

The animation runs while shown and active; the clock runs while active. -/
def tick (s : St) (f : Step) : St :=
  { s with loc := if !f.2.2 && f.2.1 then s.loc + f.1 else s.loc,
           clk := if f.2.1 then s.clk + f.1 else s.clk }

/-- One variant frame: callbacks, then the frame's time.

The observers run before the frame's time passes. -/
def step (s : St) (f : Step) : St := tick (seek s f) f

/-- The variant after a frame list.

The empty list leaves the state as it is. -/
def run (s : St) (tr : List Step) : St := tr.foldl step s

/-- The original's local time after the same frames: `PlatformScene.local'` over the activity trace.

The original ignores the hidden flag and pauses only while the section is not active. -/
def orig (ℓ0 : Rat) (tr : List Step) : Rat := local' ℓ0 (origFrames (tr.map fun f => (f.1, f.2.1)))

#guard (run ⟨0, 0, false, 0⟩ [(16, true, true), (16, false, true), (16, true, true), (16, true, false)]).loc == 48
#guard orig 0 [(16, true, true), (16, false, true), (16, true, true), (16, true, false)] == 48
#guard (seek (run ⟨0, 0, false, 0⟩ [(16, true, true), (16, false, true), (16, true, true)]) (16, true, false)).loc == 32
#guard orig 0 [(16, true, true), (16, false, true), (16, true, true)] == 32
#guard (run ⟨5, 0, false, 0⟩ []).loc == 5 && (seek ⟨1, 9, true, 4⟩ (0, true, false)).loc == 6
#guard (seek ⟨1, 9, false, 4⟩ (0, true, true)).mark == 9 && (seek ⟨1, 9, true, 4⟩ (0, true, true)).mark == 4

/-- The invariant: when shown, the variant's local time is the original's; when hidden, adding the clock's advance since
the hide gives the original's.

The state is in sync with original local time `ℓ`. -/
def Inv (s : St) (ℓ : Rat) : Prop := (s.hid = false → s.loc = ℓ) ∧ (s.hid = true → s.loc + (s.clk - s.mark) = ℓ)

/-- The original's local time after one more frame at the front.

An active first frame adds its length; an inactive one adds nothing. -/
theorem orig_cons (ℓ0 : Rat) (f : Step) (tr : List Step) :
    orig ℓ0 (f :: tr) = orig (if f.2.1 then ℓ0 + f.1 else ℓ0) tr := by
  unfold orig
  simp only [List.map_cons, origFrames, local', List.foldl_cons, advance, Fw.Parts.PlatformScene.pauses_attr]
  cases f.2.1 <;> simp

/-- After the callbacks of a shown frame, the variant's local time is the original's.

On a shown frame the seek lands on the original's local time. -/
theorem seek_shown (s : St) (ℓ : Rat) (f : Step) (hI : Inv s ℓ) (hh : f.2.2 = false) : (seek s f).loc = ℓ := by
  obtain ⟨h0, h1⟩ := hI
  unfold seek
  rw [hh]
  cases hs : s.hid
  · simpa using h0 hs
  · simpa using h1 hs

/-- One frame keeps the invariant.

Each frame advances both sides by the same active time. -/
theorem step_inv (s : St) (ℓ : Rat) (f : Step) (hI : Inv s ℓ) (hf : Ok f) :
    Inv (step s f) (if f.2.1 then ℓ + f.1 else ℓ) := by
  obtain ⟨h0, h1⟩ := hI
  obtain ⟨d, a, h⟩ := f
  unfold Ok at hf
  unfold step seek tick Inv
  cases h <;> cases a <;> cases hs : s.hid <;> simp_all <;> grind

/-- The invariant holds after any frame list of reportable frames.

Variant and original stay in sync over the whole trace. -/
theorem run_inv (s : St) (ℓ0 : Rat) (tr : List Step) (hI : Inv s ℓ0) (hok : ∀ f ∈ tr, Ok f) :
    Inv (run s tr) (orig ℓ0 tr) := by
  induction tr generalizing s ℓ0 with
  | nil => simpa [run, orig, origFrames, local'] using hI
  | cons f tr ih =>
    rw [orig_cons]
    exact ih (step s f) _ (step_inv s ℓ0 f hI (hok f (by simp))) (fun g hg => hok g (by simp [hg]))

/-- **`hsync` for the platform.** On every shown frame, after its callbacks, the variant's local time is the original's.

Whatever happened before, a shown frame shows the original's local time. -/
theorem hsync_platform (s : St) (ℓ0 : Rat) (pre : List Step) (f : Step) (hI : Inv s ℓ0) (hok : ∀ g ∈ pre, Ok g)
    (hh : f.2.2 = false) : (seek (run s pre) f).loc = orig ℓ0 pre :=
  seek_shown _ _ f (run_inv s ℓ0 pre hI hok) hh

/-- The frame at index `k`, or a shown active frame of length 0 past the end.

Index `k` of the trace, padded past its end. -/
def at' (tr : List Step) (k : Nat) : Step := tr.getD k (0, true, false)

/-- The variant's local time shown at frame `k`.

Here `F_(<k)` is the first `min(k, |F|)` frames. -/
def shownAt (s : St) (tr : List Step) (k : Nat) : Rat := (seek (run s (tr.take k)) (at' tr k)).loc

/-- The original's local time at frame `k`.

The original's local time after the first `min(k, |F|)` frames. -/
def origAt (ℓ0 : Rat) (tr : List Step) (k : Nat) : Rat := orig ℓ0 (tr.take k)

/-- **Hidden pause on the platform is class E.** For a trace of reportable frames from a synced state, if every moving
box is hidden or still at each hidden frame, the variant's visible scene is the original's at every environment and frame.

The boxes take local time as their animation value, so any animation sampled from it is covered. -/
theorem platform_visSame {Env : Type} (vp : Env → Rect) (tm : Env → Nat → Tmpl Rat) (tr : Env → List Step)
    (s : Env → St) (ℓ0 : Env → Rat) (hI : ∀ env, Inv (s env) (ℓ0 env)) (hok : ∀ env, ∀ f ∈ tr env, Ok f)
    (hH : ∀ env k, (at' (tr env) k).2.2 = true → HiddenOrStill (vp env) (tm env k)) :
    VisSame E vp (fun env k => inst (tm env k) (origAt (ℓ0 env) (tr env) k))
      (fun env k => inst (tm env k) (shownAt (s env) (tr env) k)) := by
  refine hiddenPause_visSame vp tm _ _ (fun env k => (at' (tr env) k).2.2 = true) hH ?_
  intro env k hk
  have hh : (at' (tr env) k).2.2 = false := by simpa using hk
  exact hsync_platform (s env) (ℓ0 env) _ _ (hI env)
    (fun g hg => hok env g (List.mem_of_mem_take hg)) hh

/-- A section that meets the viewport is near it, with top and bottom taken relative to the viewport's top edge.

So every frame the two observers report is `Ok`. -/
theorem meets_near (vp R : Rect) (h : vp.meets R = true) : near (R.y - vp.y) (R.y + R.h - vp.y) vp.h = true := by
  simp only [Rect.meets, Bool.and_eq_true, decide_eq_true_eq] at h
  simp only [near, Bool.and_eq_true, decide_eq_true_eq]
  grind

/-- Frames built from the two decision functions are reportable.

The hypothesis of `platform_visSame` holds for frames from `near` and `sceneHidden`. -/
theorem ok_of_rect (d : Rat) (vp R : Rect) :
    Ok (d, near (R.y - vp.y) (R.y + R.h - vp.y) vp.h, sceneHidden vp R) := by
  intro h
  simp only [sceneHidden, Bool.not_eq_false'] at h
  exact meets_near vp R (by simpa using h)

end Fw.Parts.HiddenPausePlatform
