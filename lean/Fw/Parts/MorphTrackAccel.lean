import Fw.Parts.MorphGeomAnim
/-! Which `morph.geom` Web Animation tracks run on the compositor, per engine and per driving mode. -/
namespace Fw.Parts.MorphTrackAccel
open Fw.Parts.Nav Fw.Parts.MorphGeom Fw.Engine.TransitionStart

inductive Mode where
  | scrubbed | timed
  deriving DecidableEq, Repr

inductive Why where
  | none | notPlaying | movesPixels | constant
  deriving DecidableEq, Repr

def Why.name : Why → String
  | .none => "none" | .notPlaying => "not-playing" | .movesPixels => "filter-moves-pixels"
  | .constant => "no-visible-change"

def Mode.name : Mode → String
  | .scrubbed => "scrubbed" | .timed => "timed"

-- WebKit 862f17d `Source/WebCore/animation/KeyframeEffect.cpp:2078-2082`, `style/StyleInterpolation.cpp:256-266`
-- Chromium f842f52 `compositor_animations.cc:396-420`, `cc/paint/filter_operations.cc:90-102`
def propWhy : Eng → AnimProp → Why
  | .chromium, .blur => .movesPixels
  | _, _ => .none

-- WebKit 862f17d `KeyframeEffect.cpp:2078-2082`, Chromium f842f52 `animation.cc:785`
def playWhy : Mode → Why
  | .scrubbed => .notPlaying
  | .timed => .none

def why (e : Eng) (m : Mode) (p : AnimProp) : Why :=
  match playWhy m with
  | .none => propWhy e p
  | w => w

def constantTrack (v : Vp) (a : Anim) : Bool :=
  let ks := a.ks.list v
  a.fns.all fun f => ks.all fun k => f k == f (ks.headD 0)

-- Chromium `compositor_animations.cc:284-289@f842f52`: `kAnimationHasNoVisibleChange`; WebKit has none (`KeyframeEffect.cpp:1970-2033@862f17d`)
def whyTrack (e : Eng) (m : Mode) (v : Vp) (a : Anim) : Why :=
  match why e m a.prop with
  | .none => if e == .chromium && constantTrack v a then .constant else .none
  | w => w

def onCompositorTrack (e : Eng) (m : Mode) (v : Vp) (a : Anim) : Bool := whyTrack e m v a == .none

def onCompositor (e : Eng) (m : Mode) (p : AnimProp) : Bool := why e m p == .none

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

def constantTracks (v : Vp) (as : List Anim) : Nat := as.countP fun a => constantTrack v a

#guard onCompositor .webkit .timed .blur && !onCompositor .chromium .timed .blur && onCompositor .chromium .timed .backdropBlur
#guard why .chromium .scrubbed .blur == .notPlaying && why .chromium .timed .blur == .movesPixels

theorem constant_bands :
    bandVps.all (fun v => [Eng.webkit, .chromium].all fun e => constantTracks v (anims v (Ctx.sample v e)) == 1) = true := by
  decide +kernel

theorem chromium_timed_track_main_bands :
    bandVps.all (fun v =>
      (anims v (Ctx.sample v .chromium)).countP (fun a => !onCompositorTrack .chromium .timed v a) ==
        (if v.w ≤ 720 then 3 else 4)) = true := by
  decide +kernel

theorem webkit_timed_track_main_bands :
    bandVps.all (fun v => (anims v (Ctx.sample v .webkit)).countP (fun a => !onCompositorTrack .webkit .timed v a) == 0) = true := by
  decide +kernel

/-! ## Per-flip style totals -/

inductive Rec where
  | updateLayoutTree | recalculateStyles | other
  deriving DecidableEq, Repr

structure TraceRec where
  onThread : Bool
  ts : Nat
  name : Rec
  el : Nat
  dur : Nat

def counted (t0 t1 : Nat) (r : TraceRec) : Bool :=
  r.onThread && decide (t0 ≤ r.ts) && decide (r.ts ≤ t1) && (r.name != .other)

structure FlipTotal where
  frames : Nat
  recalcs : Nat
  elements : Nat
  centiMs : Nat
  deriving Repr

def flipTotal (frames t0 t1 : Nat) (rs : List TraceRec) : FlipTotal :=
  let cs := rs.filter (counted t0 t1)
  { frames, recalcs := cs.length, elements := (cs.map (·.el)).sum, centiMs := (cs.map (·.dur)).sum / 10 }

theorem counted_edges (t0 t1 el dur : Nat) (n : Rec) (h : n ≠ .other) (h01 : t0 ≤ t1) :
    counted t0 t1 ⟨true, t0, n, el, dur⟩ = true ∧ counted t0 t1 ⟨true, t1, n, el, dur⟩ = true := by
  cases n <;> simp_all [counted]

theorem counted_off_thread (t0 t1 : Nat) (r : TraceRec) (h : r.onThread = false) : counted t0 t1 r = false := by
  simp [counted, h]

theorem counted_other (t0 t1 : Nat) (r : TraceRec) (h : r.name = .other) : counted t0 t1 r = false := by
  simp [counted, h]

theorem counted_outside (t0 t1 : Nat) (r : TraceRec) (h : r.ts < t0 ∨ t1 < r.ts) : counted t0 t1 r = false := by
  rcases h with h | h <;> simp [counted] <;> omega

def lowerBy (f : FlipTotal → Nat) (nt all : List FlipTotal) : Bool :=
  nt.all fun x => all.all fun y => decide (f x < f y)

def foldReason (all noTransform : List FlipTotal) : Bool :=
  !all.isEmpty && !noTransform.isEmpty && lowerBy (·.elements) noTransform all && lowerBy (·.centiMs) noTransform all

theorem foldReason_not_of_elements (all nt : List FlipTotal) (x y : FlipTotal) (hx : x ∈ nt) (hy : y ∈ all)
    (h : y.elements ≤ x.elements) : foldReason all nt = false := by
  have : lowerBy (·.elements) nt all = false := by
    refine Bool.eq_false_iff.mpr fun hh => ?_
    have h2 := List.all_eq_true.mp (List.all_eq_true.mp hh x hx) y hy
    simp only [decide_eq_true_eq] at h2
    omega
  simp [foldReason, this]

theorem foldReason_not_of_time (all nt : List FlipTotal) (x y : FlipTotal) (hx : x ∈ nt) (hy : y ∈ all)
    (h : y.centiMs ≤ x.centiMs) : foldReason all nt = false := by
  have : lowerBy (·.centiMs) nt all = false := by
    refine Bool.eq_false_iff.mpr fun hh => ?_
    have h2 := List.all_eq_true.mp (List.all_eq_true.mp hh x hx) y hy
    simp only [decide_eq_true_eq] at h2
    omega
  simp [foldReason, this]

def all390 : List FlipTotal := [⟨27, 26, 1143, 1973⟩, ⟨26, 25, 1252, 2497⟩, ⟨22, 21, 980, 1892⟩]
def nt390 : List FlipTotal := [⟨35, 34, 1267, 2446⟩, ⟨34, 33, 1247, 2620⟩, ⟨34, 33, 1248, 2306⟩]
def all768 : List FlipTotal := [⟨14, 14, 1279, 2648⟩, ⟨12, 12, 1022, 2122⟩, ⟨12, 12, 1148, 2472⟩]
def nt768 : List FlipTotal := [⟨33, 33, 1899, 3476⟩, ⟨32, 32, 1967, 4560⟩, ⟨33, 33, 1927, 3748⟩]
def all1440 : List FlipTotal := [⟨7, 7, 641, 1460⟩, ⟨8, 8, 702, 1556⟩, ⟨7, 6, 585, 1372⟩]
def nt1440 : List FlipTotal := [⟨31, 31, 1546, 2851⟩, ⟨31, 30, 1514, 3342⟩, ⟨30, 28, 1353, 2725⟩]

theorem no_fold_reason_any_band :
    foldReason all390 nt390 = false ∧ foldReason all768 nt768 = false ∧ foldReason all1440 nt1440 = false := by
  decide +kernel

theorem all_lowest_wide :
    lowerBy (·.elements) all768 nt768 = true ∧ lowerBy (·.centiMs) all768 nt768 = true ∧
    lowerBy (·.elements) all1440 nt1440 = true ∧ lowerBy (·.centiMs) all1440 nt1440 = true := by
  decide +kernel

theorem all_not_lowest_390 : lowerBy (·.elements) all390 nt390 = false := by decide +kernel

theorem frames_differ_wide :
    (nt768.all fun x => all768.all fun y => decide (2 * y.frames < x.frames)) = true ∧
    (nt1440.all fun x => all1440.all fun y => decide (3 * y.frames < x.frames)) = true := by
  decide +kernel

/-! ## Mid-flip tick rule (WebKit) -/

structure Eff where
  pending : Bool
  running : Bool
  active : Bool
  rendered : Bool
  complete : Bool
  accel : Bool
  threaded : Bool
  disallowed : Bool
  deriving DecidableEq, Repr

-- WebKit 862f17d `KeyframeEffect.cpp:2724-2744` (the effect of every geom track changes a style property)
def ticksContinuously (s : Eff) : Bool :=
  s.rendered && (if s.complete && s.accel then s.threaded && s.disallowed else true)

-- WebKit 862f17d `WebAnimation.cpp:1917-1929`, `AnimationEffect.cpp:385-396`
def ticksMain (s : Eff) : Bool := s.pending || (s.running && s.active && ticksContinuously s)

inductive Tick where
  | pending | quiet | accelerated | main
  deriving DecidableEq, Repr

def Tick.name : Tick → String
  | .pending => "pending" | .quiet => "quiet" | .accelerated => "accelerated" | .main => "main"

def tickOf (s : Eff) : Tick :=
  if s.pending then .pending
  else if !(s.running && s.active) then .quiet
  else if !ticksContinuously s then .accelerated
  else .main

def timelineTicks (ss : List Eff) : Bool := ss.any ticksMain

def tickingTracks (ss : List Eff) : Nat := ss.countP ticksMain

theorem ticksMain_pending (s : Eff) (h : s.pending = true) : ticksMain s = true := by
  simp [ticksMain, h]

theorem ticksMain_not_running (s : Eff) (hp : s.pending = false) (h : s.running = false) : ticksMain s = false := by
  simp [ticksMain, hp, h]

theorem ticksMain_not_active (s : Eff) (hp : s.pending = false) (h : s.active = false) : ticksMain s = false := by
  simp [ticksMain, hp, h]

theorem ticksMain_unrendered (s : Eff) (hp : s.pending = false) (h : s.rendered = false) : ticksMain s = false := by
  simp [ticksMain, ticksContinuously, hp, h]

theorem ticksMain_unaccelerated (s : Eff) (hp : s.pending = false) (hr : s.running = true) (ha : s.active = true)
    (hv : s.rendered = true) (h : s.accel = false) : ticksMain s = true := by
  simp [ticksMain, ticksContinuously, hp, hr, ha, hv, h]

theorem ticksMain_incomplete (s : Eff) (hp : s.pending = false) (hr : s.running = true) (ha : s.active = true)
    (hv : s.rendered = true) (h : s.complete = false) : ticksMain s = true := by
  simp [ticksMain, ticksContinuously, hp, hr, ha, hv, h]

theorem ticksMain_accelerated_plain (s : Eff) (hp : s.pending = false) (hc : s.complete = true) (h : s.accel = true)
    (ht : s.threaded = false) : ticksMain s = false := by
  simp [ticksMain, ticksContinuously, hp, hc, h, ht]

theorem ticksMain_accelerated_threaded_clean (s : Eff) (hp : s.pending = false) (hc : s.complete = true)
    (h : s.accel = true) (hd : s.disallowed = false) : ticksMain s = false := by
  simp [ticksMain, ticksContinuously, hp, hc, h, hd]

theorem ticksMain_accelerated_threaded_disallowed (s : Eff) (hp : s.pending = false) (hr : s.running = true)
    (ha : s.active = true) (hv : s.rendered = true) (hc : s.complete = true) (h : s.accel = true)
    (ht : s.threaded = true) (hd : s.disallowed = true) : ticksMain s = true := by
  simp [ticksMain, ticksContinuously, hp, hr, ha, hv, hc, h, ht, hd]

theorem timelineTicks_of_mem (ss : List Eff) (s : Eff) (h : s ∈ ss) (ht : ticksMain s = true) : timelineTicks ss = true := by
  simp only [timelineTicks, List.any_eq_true]
  exact ⟨s, h, ht⟩

theorem timelineTicks_quiet (ss : List Eff) (h : ∀ s ∈ ss, ticksMain s = false) : timelineTicks ss = false := by
  simp only [timelineTicks, List.any_eq_false]
  intro s hs
  simp [h s hs]

theorem tickOf_main_iff (s : Eff) : tickOf s = .main ↔ ticksMain s = true ∧ s.pending = false := by
  cases hp : s.pending <;> cases hr : s.running <;> cases ha : s.active <;> cases hv : s.rendered <;>
    cases hc : s.complete <;> cases hx : s.accel <;> cases ht : s.threaded <;> cases hd : s.disallowed <;>
    simp [tickOf, ticksMain, ticksContinuously, hp, hr, ha, hv, hc, hx, ht, hd]

/-- The mid-flip sample bins of a track's phase in permille of the tween: 30, 50 and 80 percent, none outside the tween. -/
def binOf (permille : Nat) : Option Nat :=
  if permille == 0 || 1000 ≤ permille then none
  else if permille < 400 then some 30
  else if permille < 650 then some 50
  else some 80

theorem binOf_none_iff (p : Nat) : binOf p = none ↔ p = 0 ∨ 1000 ≤ p := by
  unfold binOf
  simp only [Bool.or_eq_true, beq_iff_eq, decide_eq_true_eq]
  by_cases h : p = 0 ∨ 1000 ≤ p
  · simp [h]
  · have h1 : ¬ p = 0 := fun e => h (Or.inl e)
    have h2 : ¬ 1000 ≤ p := fun e => h (Or.inr e)
    by_cases a : p < 400 <;> by_cases b : p < 650 <;> simp [h, a, b]

def readsAccel (norm : String → String) (prop : String) (reported : List String) : Bool :=
  reported.any fun r => norm r == norm prop

/-- Names are compared lower-cased with every non-letter dropped (`backdropFilter` and `backdrop-filter` agree). -/
def normName (s : String) : String := String.ofList ((s.toList.filter Char.isAlpha).map Char.toLower)

#guard normName "backdrop-filter" == normName "backdropFilter"
#guard readsAccel normName "translate" ["Translate", "opacity"] && !readsAccel normName "scale" ["translate"]
/-- The Core Animation path (threaded animations off) reports `translate`, `scale` and `rotate` animations as `transform`
(GraphicsLayer.cpp:103-124@862f17d), so those four names are one class when the entries of an element are matched to its tracks. -/
def classOf (norm : String → String) (p : String) : String :=
  let n := norm p
  if n == "translate" || n == "scale" || n == "rotate" || n == "transform" then "transform" else n

/-- A track of an element reads accelerated when the element reports at least as many entries of its class as it has tracks of that class. -/
def readsAccelCls (norm : String → String) (prop : String) (reported : List String) (tracks : Nat) : Bool :=
  decide (0 < tracks) && decide (tracks ≤ (reported.filter fun r => classOf norm r == classOf norm prop).length)

theorem readsAccelCls_no_tracks (norm : String → String) (prop : String) (reported : List String) :
    readsAccelCls norm prop reported 0 = false := by
  simp [readsAccelCls]

theorem readsAccelCls_empty (norm : String → String) (prop : String) (n : Nat) :
    readsAccelCls norm prop [] n = false := by
  simp [readsAccelCls]
  omega

theorem classOf_translate (norm : String → String) (h : norm "translate" = "translate") (h2 : norm "transform" = "transform") :
    classOf norm "translate" = classOf norm "transform" := by
  simp [classOf, h, h2]

#guard readsAccelCls normName "translate" ["transform"] 1
#guard !readsAccelCls normName "translate" ["transform"] 2
#guard readsAccelCls normName "transform" ["transform", "transform"] 2
#guard !readsAccelCls normName "opacity" ["transform"] 1
#guard readsAccelCls normName "backdrop-filter" ["backdropFilter"] 1
#guard ticksMain ⟨false, true, true, true, true, true, false, false⟩ == false
#guard ticksMain ⟨false, true, true, true, true, false, false, false⟩ == true
#guard ticksMain ⟨true, false, false, true, true, true, false, false⟩ == true

end Fw.Parts.MorphTrackAccel
