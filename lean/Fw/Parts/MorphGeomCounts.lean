import Fw.Parts.MorphGeomAnim
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav Fw.Engine.Resource

def faithfulLayers (lvl : Nat) (v : Vp) (c : Ctx) : List Lyr :=
  [⟨"nav", "", wp v, hp v, true⟩] ++ (if 1 ≤ lvl then [⟨"panel", "nav", wp v, hp v, true⟩] else []) ++
    (if 2 ≤ lvl then [⟨"platform", "", v.w, c.platH, true⟩] else [])

def shrink (dropPlatform : Bool) (ls : List Lyr) : List Lyr :=
  ls.map fun l => if dropPlatform && l.name == "platform" then { l with backed := false } else l

def netBytes (lvl : Nat) (dropPlatform : Bool) (v : Vp) (c : Ctx) : Int :=
  (gpuBytes (dprOf v) ((shrink dropPlatform (layers v c)).map Lyr.toLayer) : Int) -
    gpuBytes (dprOf v) ((faithfulLayers lvl v c).map Lyr.toLayer)

def netFits (lvl : Nat) (b : Bool) : List Bool :=
  bandVps.map fun v => decide (netBytes lvl b v (Ctx.sample v .webkit) ≤ memBudget)

def netBands (lvl : Nat) (b : Bool) : List Int := bandVps.map fun v => netBytes lvl b v (Ctx.sample v .webkit)

theorem net_lvl0_flip : netBands 0 false =
    [10533888, 11840256, 12949632, 14269824, 20307456, 20860416, 7282560, 10749440, 11395072, 14135296, 31906816,
      48684032] := by decide +kernel

theorem net_lvl0_flip_fits : netFits 0 false =
    [true, true, true, true, true, true, true, true, true, true, false, false] := by decide +kernel

theorem net_lvl0_platform : netBands 0 true =
    [3990528, 3545856, 1099872, -157536, 12013056, -2179584, 103360, -1833472, -1187840, -2248704, 6740992, 6740992] := by
  decide +kernel

theorem net_lvl0_platform_fits : netFits 0 true = List.replicate 12 true := by decide +kernel

theorem net_phone_fold : (netFits 0 false).take 6 = List.replicate 6 true := by decide +kernel

theorem net_lvl2_flip : netFits 2 false = List.replicate 12 true := by decide +kernel

end Fw.Parts.MorphGeom
