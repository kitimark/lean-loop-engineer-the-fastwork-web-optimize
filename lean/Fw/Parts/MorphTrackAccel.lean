import Fw.Parts.MorphGeomAnim
/-! Which `morph.geom` Web Animation tracks run on the compositor, per engine and per driving mode.

A track runs on the compositor only if two gates are open: the animation is Running (play-state gate) and its property is
one the engine moves off the main thread (property gate). Pinned sources:

* WebKit 862f17d, `Source/WebCore/animation/KeyframeEffect.cpp`: `updateAcceleratedActions` (:2060-2106) queues
  `AcceleratedAction::Play` only while `playState() == Running` and the effect is in its active phase (:2078-2082); a
  Paused animation that never started gets no Play (the `NotStarted` branch returns). `canBeAccelerated` (:1970-2033)
  and `preventsAcceleration` (:2035-2058) test the effect (composite replace, no steps timing, no reference filter).
  Property gate: `Style::Interpolation::isAccelerated` (`style/StyleInterpolation.cpp:256-266`) ->
  `CSSProperty::animationIsAccelerated` generated from `animation-wrapper-acceleration` in `css/CSSProperties.json`:
  opacity (:7114), filter (:10263), backdrop-filter (:10639), transform (:12112), translate (:12260), scale (:12281) are
  `always`. Threaded time-based animations (`canHaveAcceleratedRepresentation`) are a preview flag, off by default.
* Chromium f842f52, `third_party/blink/renderer/core/animation/animation.cc`: `Animation::PreCommit` starts an
  animation on the compositor only if `should_start = Playing() && ...` (:785); `Playing()` needs the play state
  Running (`animation.h:211-214`). A Paused animation therefore never reaches `CheckCanStartEffectOnCompositor`. Property
  gate: `compositor_animations.cc:396-420`: opacity, translate, scale, transform and backdrop-filter pass; `filter` sets
  `kFilterRelatedPropertyMayMovePixels` (`compositor_animations.h:104`) when a keyframe holds a filter that moves pixels,
  and `cc/paint/filter_operations.cc:90-102` lists BLUR among them, whatever its radius.

The two drivers: `morph.geom:on` creates every track paused and writes `currentTime` each frame (`driver.ts`); with
`morph.tween:geom-timed` every track is a running animation whose `startTime` is set once (`geom-timed.driver.ts`).
Per-element checks that need a live document (an incompatible animation on the same element, a layer the renderer did
not composite) are not modelled here; the CI probe reads them. -/
namespace Fw.Parts.MorphTrackAccel
open Fw.Parts.Nav Fw.Parts.MorphGeom Fw.Engine.TransitionStart

/-- `scrubbed`: geom:on, paused, `currentTime` written per frame. `timed`: geom-timed, running from a set `startTime`. -/
inductive Mode where
  | scrubbed | timed
  deriving DecidableEq, Repr

/-- Why a track stays on the main thread (`none`: it does not). -/
inductive Why where
  | none | notPlaying | movesPixels | constant
  deriving DecidableEq, Repr

def Why.name : Why → String
  | .none => "none" | .notPlaying => "not-playing" | .movesPixels => "filter-moves-pixels"
  | .constant => "no-visible-change"

def Mode.name : Mode → String
  | .scrubbed => "scrubbed" | .timed => "timed"

/-- Property gate of each engine. WebKit: all six geom properties are in the generated accelerated set. Chromium: `filter`
(the blur tracks) may move pixels, the other five pass. -/
def propWhy : Eng → AnimProp → Why
  | .chromium, .blur => .movesPixels
  | _, _ => .none

/-- Play-state gate: only a Running animation is started on the compositor, in both engines. -/
def playWhy : Mode → Why
  | .scrubbed => .notPlaying
  | .timed => .none

/-- The first closed gate names the reason. -/
def why (e : Eng) (m : Mode) (p : AnimProp) : Why :=
  match playWhy m with
  | .none => propWhy e p
  | w => w

/-- A track whose every keyframe holds one value, in every component. -/
def constantTrack (v : Vp) (a : Anim) : Bool :=
  let ks := a.ks.list v
  a.fns.all fun f => ks.all fun k => f k == f (ks.headD 0)

/-- Third gate, Chromium only: `compositor_animations.cc:284-289@f842f52` sets `kAnimationHasNoVisibleChange` when
`DynamicProperties()` is empty (every keyframe value constant), so the track stays on the main thread. WebKit has no such
test in `canBeAccelerated` (`KeyframeEffect.cpp:1970-2033@862f17d`). -/
def whyTrack (e : Eng) (m : Mode) (v : Vp) (a : Anim) : Why :=
  match why e m a.prop with
  | .none => if e == .chromium && constantTrack v a then .constant else .none
  | w => w

def onCompositorTrack (e : Eng) (m : Mode) (v : Vp) (a : Anim) : Bool := whyTrack e m v a == .none

/-- The "runs on compositor" predicate for one track. -/
def onCompositor (e : Eng) (m : Mode) (p : AnimProp) : Bool := why e m p == .none

/-- Tracks the main thread must still sample each frame (INFERRED to cost per-frame style work, see the note). -/
def mainTracks (e : Eng) (m : Mode) (as : List Anim) : Nat := as.countP fun a => !onCompositor e m a.prop

def blurTracks (as : List Anim) : Nat := as.countP fun a => a.prop == .blur

theorem scrubbed_never (e : Eng) (p : AnimProp) : onCompositor e .scrubbed p = false := by
  simp [onCompositor, why, playWhy]

theorem webkit_timed_all (p : AnimProp) : onCompositor .webkit .timed p = true := by
  cases p <;> simp [onCompositor, why, playWhy, propWhy]

theorem chromium_timed_iff (p : AnimProp) : onCompositor .chromium .timed p = true ↔ p ≠ .blur := by
  cases p <;> simp [onCompositor, why, playWhy, propWhy]

theorem scrubbed_all_main (e : Eng) (as : List Anim) : mainTracks e .scrubbed as = as.length := by
  simp [mainTracks, scrubbed_never]

theorem webkit_timed_none (as : List Anim) : mainTracks .webkit .timed as = 0 := by
  simp [mainTracks, webkit_timed_all]

theorem chromium_timed_blur (as : List Anim) : mainTracks .chromium .timed as = blurTracks as := by
  unfold mainTracks blurTracks
  congr 1
  funext a
  cases h : a.prop <;> simp [onCompositor, why, playWhy, propWhy]

/-- A blur track is the panel's on wide viewports only (`anims`: `v.w ≤ 720` has none), plus earn and platform. -/
theorem blur_bands :
    bandVps.all (fun v => [Eng.webkit, .chromium].all fun e =>
      blurTracks (anims v (Ctx.sample v e)) == (if v.w ≤ 720 then 2 else 3)) = true := by
  decide +kernel

theorem chromium_timed_main_bands :
    bandVps.all (fun v => mainTracks .chromium .timed (anims v (Ctx.sample v .chromium)) == (if v.w ≤ 720 then 2 else 3)) = true := by
  decide +kernel

theorem webkit_timed_main_bands :
    bandVps.all (fun v => mainTracks .webkit .timed (anims v (Ctx.sample v .webkit)) == 0) = true := by
  decide +kernel

theorem scrubbed_main_bands :
    bandVps.all (fun v => [Eng.webkit, .chromium].all fun e =>
      mainTracks e .scrubbed (anims v (Ctx.sample v e)) == (anims v (Ctx.sample v e)).length) = true := by
  decide +kernel

theorem webkit_timed_track_all (v : Vp) (a : Anim) : onCompositorTrack .webkit .timed v a = true := by
  simp [onCompositorTrack, whyTrack, why, playWhy, propWhy]

theorem scrubbed_track_never (e : Eng) (v : Vp) (a : Anim) : onCompositorTrack e .scrubbed v a = false := by
  simp [onCompositorTrack, whyTrack, why, playWhy]

theorem chromium_timed_track_iff (v : Vp) (a : Anim) :
    onCompositorTrack .chromium .timed v a = true ↔ a.prop ≠ .blur ∧ constantTrack v a = false := by
  cases h : a.prop <;> simp [onCompositorTrack, whyTrack, why, playWhy, propWhy, h]

/-- The constant tracks Chromium keeps on the main thread in geom-timed, per band. -/
def constantTracks (v : Vp) (as : List Anim) : Nat := as.countP fun a => constantTrack v a

#guard onCompositor .webkit .timed .blur && !onCompositor .chromium .timed .blur && onCompositor .chromium .timed .backdropBlur
#guard why .chromium .scrubbed .blur == .notPlaying && why .chromium .timed .blur == .movesPixels

/-- One constant track per band (the first column, whose translate is `0 * x`), the same in both engines' samples. -/
theorem constant_bands :
    bandVps.all (fun v => [Eng.webkit, .chromium].all fun e => constantTracks v (anims v (Ctx.sample v e)) == 1) = true := by
  decide +kernel

/-- Chromium geom-timed keeps the blur tracks and the one constant track on the main thread, per band. -/
theorem chromium_timed_track_main_bands :
    bandVps.all (fun v =>
      (anims v (Ctx.sample v .chromium)).countP (fun a => !onCompositorTrack .chromium .timed v a) ==
        (if v.w ≤ 720 then 3 else 4)) = true := by
  decide +kernel

theorem webkit_timed_track_main_bands :
    bandVps.all (fun v => (anims v (Ctx.sample v .webkit)).countP (fun a => !onCompositorTrack .webkit .timed v a) == 0) = true := by
  decide +kernel

end Fw.Parts.MorphTrackAccel
