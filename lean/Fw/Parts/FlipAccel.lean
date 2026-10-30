import Fw.Parts.MorphTrackAccel
/-! The end-of-page flip on WebKit: which animated properties force a style recalc per frame, and what an accelerated-only variant would change. -/
namespace Fw.Parts.FlipAccel
open Fw.Parts.Nav Fw.Parts.MorphGeom Fw.Parts.MorphTrackAccel Fw.Engine.TransitionStart

-- WebKit 862f17d `Source/WebCore/css/CSSProperties.json`: `animation-wrapper-acceleration` is "always" for opacity (7114), filter (10263),
-- backdrop-filter (10639), transform (12112), translate (12260), scale (12281), rotate (12306); the offset-* properties are "threaded-only".
-- `process-css-properties.py:4093-4096`: "always" returns true, "threaded-only" returns the two threaded settings.
def wkAlways (css : String) : Bool :=
  ["opacity", "filter", "backdrop-filter", "transform", "translate", "scale", "rotate"].contains css

/-- A property forces the effect onto the main thread when WebKit does not list it as accelerated (`KeyframeEffect.cpp:1965-1969`, `computeAcceleratedPropertiesState`). -/
def forcesRecalc (p : AnimProp) : Bool := !wkAlways p.css

theorem none_force (p : AnimProp) : forcesRecalc p = false := by
  cases p <;> decide

-- `KeyframeEffect::canBeAccelerated` (KeyframeEffect.cpp:1970-2030@862f17d) conditions that depend only on the track as built.
def staticEligible (v : Vp) (a : Anim) : Bool :=
  wkAlways a.prop.css && a.composite == .replace && (a.ks.offsets v).head? == some 0 && (a.ks.offsets v).getLast? == some 1

/-- The accelerated-only variant keeps the tracks WebKit accelerates and drops the rest. -/
def accelOnly (as : List Anim) : List Anim := as.filter fun a => !forcesRecalc a.prop

/-- The variant removes nothing: the flip already animates accelerated properties only. -/
theorem accelOnly_id (as : List Anim) : accelOnly as = as := by
  unfold accelOnly
  apply List.filter_eq_self.mpr
  intro a _
  simp [none_force]

/-- Same look: every per-frame reading of the variant equals the reading of the original tracks. -/
theorem same_look {α : Type} (read : List Anim → α) (as : List Anim) : read (accelOnly as) = read as := by
  rw [accelOnly_id]

/-- No track of the flip forces a recalc by its property, at every band viewport. -/
theorem forcing_tracks_zero (e : Eng) :
    bandVps.all (fun v => (anims v (Ctx.sample v e)).countP (fun a => forcesRecalc a.prop) == 0) = true := by
  simp [List.all_eq_true, none_force]

theorem static_eligible_bands :
    bandVps.all (fun v => (anims v (Ctx.sample v .webkit)).all (staticEligible v)) = true := by
  decide +kernel

#guard wkAlways "translate" && wkAlways "scale" && wkAlways "backdrop-filter" && !wkAlways "max-width" && !wkAlways "offset-path"

end Fw.Parts.FlipAccel
