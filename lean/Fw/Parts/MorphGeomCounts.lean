import Fw.Parts.MorphGeomAnim
/-! `morph.geom:on` backing memory as net bytes: the flip tree's census minus what the faithful page already backs at
morph frames, with the two shrink steps of the design (fold the veil into the fill, drop the platform's own layer). -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav Fw.Engine.Resource

/-- Layers the faithful page backs while the morph runs, by confidence. Level 0 is certain (the nav paints a colour-mix
fill under a backdrop blur and has `will-change`); level 1 adds the panel (opacity, blur and scale animate); level 2 adds the
platform (opacity and blur from `--morph-fade`). Levels 1 and 2 are INFERRED from the CSS; the Simulator census lane is the
measurement. Sizes are the final box and the viewport, the upper bound of what the faithful page backs. -/
def faithfulLayers (lvl : Nat) (v : Vp) (c : Ctx) : List Lyr :=
  [⟨"nav", "", wp v, hp v, true⟩] ++ (if 1 ≤ lvl then [⟨"panel", "nav", wp v, hp v, true⟩] else []) ++
    (if 2 ≤ lvl then [⟨"platform", "", v.w, c.platH, true⟩] else [])

/-- The flip tree with the shrink step applied. `dropPlatform`: the platform fade runs on the page's own layer. The veil
needs no step: it is folded into the solid fill D, which paints nothing and has no backing. -/
def shrink (dropPlatform : Bool) (ls : List Lyr) : List Lyr :=
  ls.map fun l => if dropPlatform && l.name == "platform" then { l with backed := false } else l

/-- Flip bytes minus faithful bytes at a band (negative: the flip tree backs less than the faithful page). -/
def netBytes (lvl : Nat) (dropPlatform : Bool) (v : Vp) (c : Ctx) : Int :=
  (gpuBytes (dprOf v) ((shrink dropPlatform (layers v c)).map Lyr.toLayer) : Int) -
    gpuBytes (dprOf v) ((faithfulLayers lvl v c).map Lyr.toLayer)

def netFits (lvl : Nat) (b : Bool) : List Bool :=
  bandVps.map fun v => decide (netBytes lvl b v (Ctx.sample v .webkit) ≤ memBudget)

def netBands (lvl : Nat) (b : Bool) : List Int := bandVps.map fun v => netBytes lvl b v (Ctx.sample v .webkit)

/-- Net bytes per band with only the certain faithful layer (the nav), the flip tree as designed (veil folded into the solid
D): 10 of the 12 bands fit the budget; 1440x900 and 1920x1080 are over. -/
theorem net_lvl0_flip : netBands 0 false =
    [10533888, 11840256, 12949632, 14269824, 20307456, 20860416, 7282560, 10749440, 11395072, 14135296, 31906816,
      48684032] := by decide +kernel

theorem net_lvl0_flip_fits : netFits 0 false =
    [true, true, true, true, true, true, true, true, true, true, false, false] := by decide +kernel

/-- The platform fade on the page's own layer as well: all 12 bands fit under level 0 (the two big bands net 6.7 MB). -/
theorem net_lvl0_platform : netBands 0 true =
    [3990528, 3545856, 1099872, -157536, 12013056, -2179584, 103360, -1833472, -1187840, -2248704, 6740992, 6740992] := by
  decide +kernel

theorem net_lvl0_platform_fits : netFits 0 true = List.replicate 12 true := by decide +kernel

/-- The phone bands (width up to 640, dpr 3) fit with the veil folded, whatever else the faithful page backs. -/
theorem net_phone_fold : (netFits 0 false).take 6 = List.replicate 6 true := by decide +kernel

/-- If the faithful page also backs the panel and the platform at the final box and viewport (INFERRED), the flip tree as
designed fits every band. -/
theorem net_lvl2_flip : netFits 2 false = List.replicate 12 true := by decide +kernel

end Fw.Parts.MorphGeom
