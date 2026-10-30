import Lean.Data.Json
import Fw.Parts.FlipAccel
import Fw.Parts.MorphGeomGen
/-! The two `canBeAccelerated` conditions FlipAccel leaves unmodelled, over the keyframes the geom-timed driver plays. -/
namespace Fw.Parts.FlipAccelRun
open Lean Fw.Parts.Nav Fw.Parts.MorphGeom Fw.Parts.MorphTrackAccel Fw.Parts.FlipAccel Fw.Engine.TransitionStart

inductive Fn where
  | translate | scale | matrix | matrix3d
  deriving DecidableEq, Repr

def Fn.isMatrix : Fn → Bool
  | .matrix | .matrix3d => true
  | _ => false

def playedFns : AnimProp → List Fn
  | .transformList => [.translate, .scale]
  | _ => []

-- `BlendingKeyframes.cpp:397-398@862f17d`: the flag is read only from keyframes that animate `transform`;
-- `StyleTransformList.cpp:66-69@862f17d`: it needs a `matrix` or `matrix3d` function that is also non-invertible.
def discreteInterval (p : AnimProp) : Bool := p == .transformList && (playedFns p).any Fn.isMatrix

theorem discrete_needs_matrix (p : AnimProp) (h : discreteInterval p = true) : (playedFns p).any Fn.isMatrix = true := by
  simp only [discreteInterval, Bool.and_eq_true] at h
  exact h.2

theorem no_played_matrix (p : AnimProp) : discreteInterval p = false := by
  cases p <;> decide

-- `KeyframeEffect.cpp:1978@862f17d` reads `m_hasAcceleratedPropertyOverriddenByCascadeProperty`, set at `:2931` from
-- `KeyframeEffectStack::cascadeDidOverrideProperties` (`KeyframeEffectStack.cpp:306-320@862f17d`), which keeps the accelerated properties
-- that an author `!important` declaration wins over the animation.
def importantDecls : List (String × String) := [("nav", "backdrop-filter"), ("earn", "transform")]

def overridden (el css : String) : Bool := importantDecls.contains (el, css)

def cascadeOverride (a : Anim) : Bool := overridden a.el a.prop.css

def unmodelledOk (a : Anim) : Bool := !cascadeOverride a && !discreteInterval a.prop

theorem unmodelled_bands (e : Eng) :
    bandVps.all (fun v => (anims v (Ctx.sample v e)).all unmodelledOk) = true := by
  cases e <;> decide +kernel

#guard overridden "earn" "transform" && overridden "nav" "backdrop-filter" && !overridden "earn" "translate" && !overridden "G" "backdrop-filter"

def Fn.name : Fn → String
  | .translate => "translate" | .scale => "scale" | .matrix => "matrix" | .matrix3d => "matrix3d"

def allProps : List AnimProp := [.translate, .scale, .transformList, .opacity, .blur, .backdropBlur]

def playedLines (_ : Unit) : List String :=
  allProps.map fun p =>
    gline "played" [("prop", .str p.css)] (Json.mkObj [("fns", jl ((playedFns p).map fun f => Json.str f.name)), ("discrete", .bool (discreteInterval p))])

def declLines (_ : Unit) : List String :=
  importantDecls.map fun (el, css) => gline "decl" [("el", .str el), ("css", .str css)] (.bool (overridden el css))

def probeLines (_ : Unit) : List String :=
  [("earn", "transform"), ("earn", "translate"), ("earn", "filter"), ("nav", "backdrop-filter"), ("G", "backdrop-filter")].map fun (el, css) =>
    gline "overridden" [("el", .str el), ("css", .str css)] (.bool (overridden el css))

def trackLines (_ : Unit) : List String :=
  bandVps.map fun v =>
    let as := anims v (Ctx.sample v .webkit)
    gline "tracks" (vpIn v)
      (Json.mkObj [("n", .num ⟨as.length, 0⟩), ("cascade", .num ⟨(as.filter cascadeOverride).length, 0⟩),
        ("discrete", .num ⟨(as.filter fun a => discreteInterval a.prop).length, 0⟩), ("ok", .num ⟨(as.filter unmodelledOk).length, 0⟩)])

def goldenText (_ : Unit) : String := String.join ((playedLines () ++ declLines () ++ probeLines () ++ trackLines ()).map (· ++ "\n"))

def gen (args : List String) : IO UInt32 := do
  match args with
  | ["--check", path] =>
    if (← IO.FS.readFile path) == goldenText () then
      IO.eprintln s!"flip-accel-run golden: {path} is up to date"
      return 0
    IO.eprintln s!"flip-accel-run golden: {path} differs from the generated text"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

end Fw.Parts.FlipAccelRun
