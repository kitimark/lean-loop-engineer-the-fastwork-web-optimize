import Fw.Parts.MorphGeomEarn
import Fw.Engine.Resource
/-! `morph.geom:on`: the flip layers, their Web Animations, the WebKit acceleration rules they meet, end states and
the backing bytes they add. -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav Fw.Parts.MorphTween Fw.Engine.TransitionStart
open Fw.Parts.NavEarnOpt (frameMs frames)

/-- Animated properties: the accelerated set of `GraphicsLayerCA.cpp:1183-1215@862f17d`, nothing else. -/
inductive AnimProp where
  | translate | scale | transformList | opacity | blur | backdropBlur
  deriving DecidableEq, Repr

def AnimProp.css : AnimProp → String
  | .translate => "translate" | .scale => "scale" | .transformList => "transform" | .opacity => "opacity"
  | .blur => "filter" | .backdropBlur => "backdrop-filter"

/-- Numbers per keyframe: `translate: x y`, `scale: sx sy`, `transform: translate(x, y) scale(sx, sy)`, one for the rest. -/
def AnimProp.arity : AnimProp → Nat
  | .translate => 2 | .scale => 2 | .transformList => 4 | .opacity => 1 | .blur => 1 | .backdropBlur => 1

inductive Easing where
  | linear
  | cubic (x1 y1 x2 y2 : Rat)
  deriving DecidableEq, Repr

inductive Composite where
  | replace | add | accumulate
  deriving DecidableEq, Repr

inductive PlayDir where
  | normal | reverse | alternate
  deriving DecidableEq, Repr

/-- Knot sets: the rational grid, `[0, 1]`, the earn knot 0.2, the panel knots, the fade knot, the 60 Hz time grid. -/
inductive Ks where
  | grid | unit | earn | panel | fade | time
  deriving DecidableEq, Repr

def Ks.list (v : Vp) : Ks → List Rat
  | .grid => knots v | .unit => [0, 1] | .earn => earnKnots | .panel => panelKnots | .fade => fadeKnots
  | .time => gridFrom 0 frameMs frames

/-- End of the time grid in ms. -/
def timeEnd : Rat := (frames : Rat) * frameMs

/-- Keyframe offsets of a knot set: `m` itself, or time over `timeEnd`. -/
def Ks.offsets (v : Vp) (k : Ks) : List Rat := if k = .time then (k.list v).map (· / timeEnd) else k.list v

/-- One effect: element, index (column, image), property, knot set and one function per keyframe number. -/
structure Anim where
  el : String
  key : Nat × Nat
  prop : AnimProp
  ks : Ks
  fns : List (Rat → Rat)
  kfEasing : Easing
  easing : Easing
  composite : Composite
  rate : Rat
  dir : PlayDir

def anim (el : String) (prop : AnimProp) (ks : Ks) (fns : List (Rat → Rat)) (key : Nat × Nat := (0, 0)) : Anim :=
  ⟨el, key, prop, ks, fns, .linear, .linear, .replace, 1, .normal⟩

def Anim.tracks (v : Vp) (a : Anim) : List Track := a.fns.map fun f => MorphGeom.mk f (a.ks.list v)

/-- Inputs the layout fixes: push, engine, logo, label, button and gap widths, centre, footer and platform heights,
and per column the images as (final top less the gaps above, height). -/
structure Ctx where
  eng : Eng
  a : Rat
  b : Rat
  inset : Rat
  logoW : Rat
  logoH : Rat
  langW : Rat
  lw : Rat
  w0 : Rat
  gL : Rat
  centreH : Rat
  footH : Rat
  platH : Rat
  imgs : List (List (Rat × Rat))

/-! ## The flip tree -/

/-- One layer of the flip tree: laid-out size in css px and whether WebKit gives it a backing store. -/
structure Lyr where
  name : String
  parent : String
  w : Rat
  h : Rat
  backed : Bool
  deriving Repr

/-- Rows of a column's images: `(key, final top, height)`. -/
def imgRows (c : Ctx) : List ((Nat × Nat) × Rat × Rat) :=
  (c.imgs.zipIdx).flatMap fun (col, i) => (col.zipIdx).map fun ((y, h), j) => ((i, j), y, h)

/-- The flip tree of the design note at final size. Clippers, counters, solid fills, the panel and directly
composited images paint nothing (`RenderLayerBacking.cpp:3509-3535,3687-3690@862f17d`). -/
def layers (v : Vp) (c : Ctx) : List Lyr :=
  let W := wp v; let H := hp v
  [⟨"nav", "", W, H, false⟩, ⟨"K0", "nav", 2 * W, 2 * H, false⟩, ⟨"K1", "K0", 2 * W, 2 * H, false⟩,
    ⟨"K2", "K1", 2 * W, 2 * H, false⟩, ⟨"K3", "K2", 2 * W, 2 * H, false⟩, ⟨"U", "K3", W, H, false⟩,
    ⟨"G", "U", W, H + (if phone v.w then 0 else 4), false⟩, ⟨"D", "U", W, H, false⟩,
    ⟨"bar", "U", W, pillH v, false⟩, ⟨"logo", "bar", c.logoW, c.logoH, true⟩, ⟨"actions", "bar", W, 48, false⟩,
    ⟨"lang", "actions", c.langW, 48, true⟩, ⟨"earn", "actions", c.w0, 48, true⟩,
    ⟨"earnClip", "earn", c.w0, 48, false⟩, ⟨"earnLabel", "earnClip", c.w0, 48, true⟩,
    ⟨"panel", "U", W, H, false⟩, ⟨"backdropClip", "panel", 53 / 50 * W, H, false⟩,
    ⟨"Kb", "backdropClip", 53 / 50 * W, H, false⟩, ⟨"Ub", "Kb", 53 / 50 * W, H, false⟩] ++
  ((List.range (nCols v).floor.toNat).map fun i => ⟨s!"column{i}", "Ub", cw v 1, H, false⟩) ++
  ((imgRows c).map fun ((i, j), _, h) => ⟨s!"image{i}.{j}", s!"column{i}", cw v 1, h, false⟩) ++
  [⟨"veil", "panel", W, H, true⟩, ⟨"centre", "panel", W, c.centreH, true⟩, ⟨"footer", "panel", W, c.footH, true⟩,
    ⟨"footerGrad", "footer", W, c.footH, true⟩, ⟨"footerEnd", "footer", W, c.footH, true⟩,
    ⟨"platform", "", v.w, c.platH, true⟩]

/-- Every effect of the variant for viewport `v`. -/
def anims (v : Vp) (c : Ctx) : List Anim :=
  [anim "K0" .transformList .grid [x0 v, y0 v, kk v, kk v],
    anim "K1" .translate .grid [tauX v, fun _ => 0],
    anim "K2" .translate .grid [fun x => -tauX v x, tauY v],
    anim "K3" .translate .grid [tauX v, fun _ => 0],
    anim "U" .transformList .grid [tUx v, tUy v, sU v, sU v],
    anim "G" .backdropBlur .unit [navBlur],
    anim "D" .opacity .unit [fun x => x],
    anim "bar" .translate .unit [fun _ => 0, y0 v],
    anim "logo" .translate .grid [logoT v c.inset c.logoW, fun _ => 0],
    anim "actions" .translate .unit [fun x => -x0 v x, fun _ => 0],
    anim "lang" .translate .earn [fun x => c.gL - actionsGap v false x, fun _ => 0],
    anim "lang" .transformList .time [fun t => c.w0 - earnWF c.eng v c.lw c.a c.b (idx t), fun _ => 0,
      fun _ => 1, fun _ => 1],
    anim "earn" .opacity .time [fun t => opF c.a c.b (idx t)],
    anim "earn" .blur .earn [earnBlur],
    anim "earn" .translate .earn [fun _ => 0, earnShift],
    anim "earnClip" .translate .time [fun t => c.w0 - earnWF c.eng v c.lw c.a c.b (idx t), fun _ => 0],
    if padRuns c.eng then
      anim "earnLabel" .translate .time [fun t => padF c.eng v c.a c.b (idx t) - earnPad v false 0, fun _ => 0]
    else anim "earnLabel" .translate .earn [fun x => earnPad v false x - earnPad v false 0, fun _ => 0],
    anim "panel" .translate .unit [fun _ => 0, dP v],
    anim "panel" .scale .unit [pS, pS],
    anim "panel" .transformList .unit [fun _ => 0, fun x => -dP v x, fun _ => 1, fun _ => 1],
    anim "panel" .opacity .panel [panelO]] ++
  (if v.w ≤ 720 then [] else [anim "panel" .blur .panel [panelBlur v]]) ++
  [anim "backdropClip" .translate .unit [fun x => 53 / 50 * x0 v x, y0 v],
    anim "Kb" .translate .unit [fun x => -(106 / 50) * x0 v x, fun x => ht v x - hp v],
    anim "Ub" .translate .unit [fun x => 106 / 50 * x0 v x, fun x => hp v - ht v x]] ++
  ((List.range (nCols v).floor.toNat).map fun i => anim "column" .translate .unit [colTx v i, fun _ => 0] (i, 0)) ++
  ((imgRows c).map fun ((i, j), y, _) =>
    anim "image" .transformList .unit [fun _ => 0, imgTy v j y 0, sImg v, sImg v] (i, j)) ++
  [anim "veil" .transformList .unit [x0 v, y0 v, fun x => wd v x / wp v, fun x => ht v x / hp v],
    anim "centre" .translate .unit [fun _ => 0, dP v],
    anim "footer" .translate .unit [x0 v, fun x => y0 v x + ht v x - hp v],
    anim "footerGrad" .scale .unit [fun x => wd v x / wp v, fun _ => 1],
    anim "footerEnd" .translate .unit [fun x => -2 * x0 v x, fun _ => 0],
    anim "platform" .opacity .fade [fade],
    anim "platform" .blur .fade [fadeBlur]]

/-! ## Acceleration -/

def sortedB : List Rat → Bool
  | p :: q :: rest => decide (p < q) && sortedB (q :: rest)
  | _ => true

/-- Offsets 0 and 1 present and sorted. -/
def offsetsOk (os : List Rat) : Bool := sortedB os && os.head? == some 0 && os.getLast? == some 1

/-- Effect easing CA can run: linear, or a cubic with control points in `[0, 1]` (`GraphicsLayerCA.cpp:1192-1198`). -/
def easingOk : Easing → Bool
  | .linear => true
  | .cubic x1 y1 x2 y2 => decide (0 ≤ x1 ∧ x1 ≤ 1 ∧ 0 ≤ x2 ∧ x2 ≤ 1 ∧ 0 ≤ y1 ∧ y1 ≤ 1 ∧ 0 ≤ y2 ∧ y2 ≤ 1)

/-- One effect meets `animationCanBeAccelerated` and `KeyframeEffect.cpp:1987-2017@862f17d`. -/
def accelOne (a : Anim) : Bool :=
  a.fns.length == a.prop.arity && a.kfEasing == .linear && easingOk a.easing && a.composite == .replace &&
    a.rate == 1 && a.dir == .normal

def keysOf (as : List Anim) : List (String × (Nat × Nat) × AnimProp) := as.map fun a => (a.el, a.key, a.prop)

/-- Every effect accelerable, one effect per (element, index, property), every knot set's offsets sorted from 0 to 1. -/
def accelerable (v : Vp) (as : List Anim) : Bool :=
  as.all accelOne && (keysOf as).Nodup && [Ks.grid, .unit, .earn, .panel, .fade, .time].all (offsetsOk ∘ Ks.offsets v)

/-- Elements the generated `.is-flip` rule sets to `transition: none`. -/
def flipEls : List String :=
  ["nav", "K0", "K1", "K2", "K3", "U", "G", "D", "bar", "logo", "actions", "lang", "earn", "earnClip", "earnLabel",
    "panel", "backdropClip", "Kb", "Ub", "column", "image", "veil", "centre", "footer", "footerGrad", "footerEnd",
    "platform"]

def noTransition (as : List Anim) : Bool := as.all fun a => flipEls.contains a.el

/-- Sample layout inputs for the band check: three images per column. -/
def Ctx.sample (v : Vp) (e : Eng) : Ctx :=
  let ph := phone v.w
  ⟨e, 0, 1, if ph then 16 else 24, if ph then 120 else 160, if ph then 32 else 40, 100,
    if ph then 120 else 144, earnMaxW v false 0, actionsGap v false 1, if ph then 360 else 420,
    if ph then 160 else 68, v.h, List.replicate (nCols v).floor.toNat [(0, 200), (200, 200), (400, 200)]⟩

theorem accelerable_bands :
    bandVps.all (fun v => [Eng.webkit, .chromium].all fun e => accelerable v (anims v (Ctx.sample v e))) = true := by
  decide +kernel

theorem noTransition_bands :
    bandVps.all (fun v => [Eng.webkit, .chromium].all fun e => noTransition (anims v (Ctx.sample v e))) = true := by
  decide +kernel

theorem timed_easing_ok : easingOk (.cubic (1 / 3) 1 (2 / 3) 1) = true := by decide +kernel

theorem layers_cover_anims :
    bandVps.all (fun v => (anims v (Ctx.sample v .webkit)).all fun a =>
      (layers v (Ctx.sample v .webkit)).any fun l => l.name = a.el ∨ l.name.startsWith a.el) = true := by
  decide +kernel

#guard sortedB [0, 1 / 5, 1] && !sortedB [0, 0, 1]
#guard offsetsOk [0, 1 / 2, 1] && !offsetsOk [0, 1 / 2] && !offsetsOk [1 / 10, 1]
#guard easingOk (.cubic (1 / 3) 1 (2 / 3) 1) && !easingOk (.cubic (1 / 3) (-1 / 10) (2 / 3) 1)
#guard accelOne (anim "D" .opacity .unit [fun x => x]) && !accelOne (anim "D" .translate .unit [fun x => x])
#guard noTransition [anim "veil" .opacity .unit [fun x => x]] && !noTransition [anim "title" .opacity .unit [fun x => x]]

end Fw.Parts.MorphGeom
