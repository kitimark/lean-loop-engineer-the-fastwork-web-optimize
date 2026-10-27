import Fw.Parts.MorphGeomAnim
/-! `morph.geom:on` backing memory as net bytes: the flip tree's census minus what the faithful page already backs at
morph frames, with the two shrink steps of the design (fold the veil into the fill, drop the platform's own layer). -/
namespace Fw.Parts.MorphGeom
open Fw.Parts.Nav Fw.Engine.Resource

def faithfulLayers (lvl : Nat) (v : Vp) (c : Ctx) : List Lyr :=
  [⟨"nav", "", wp v, hp v, true⟩] ++ (if 1 ≤ lvl then [⟨"panel", "nav", wp v, hp v, true⟩] else []) ++
    (if 2 ≤ lvl then [⟨"platform", "", v.w, c.platH, true⟩] else [])

def shrink (foldVeil dropPlatform : Bool) (ls : List Lyr) : List Lyr :=
  ls.map fun l =>
    if foldVeil && l.name == "veil" then { l with backed := false }
    else if dropPlatform && l.name == "platform" then { l with backed := false }
    else l

def netBytes (lvl : Nat) (foldVeil dropPlatform : Bool) (v : Vp) (c : Ctx) : Int :=
  (gpuBytes (dprOf v) ((shrink foldVeil dropPlatform (layers v c)).map Lyr.toLayer) : Int) -
    gpuBytes (dprOf v) ((faithfulLayers lvl v c).map Lyr.toLayer)

def netFits (lvl : Nat) (a b : Bool) : List Bool :=
  bandVps.map fun v => decide (netBytes lvl a b v (Ctx.sample v .webkit) ≤ memBudget)

def netBands (lvl : Nat) (a b : Bool) : List Int := bandVps.map fun v => netBytes lvl a b v (Ctx.sample v .webkit)

theorem net_lvl0_flip : netFits 0 false false =
    [true, true, false, false, false, false, true, true, true, false, false, false] := by decide +kernel

theorem net_lvl0_fold : netFits 0 true false =
    [true, true, true, true, true, true, true, true, true, true, false, false] := by decide +kernel

theorem net_lvl0_fold_platform : netFits 0 true true = List.replicate 12 true := by decide +kernel

theorem net_lvl2_flip : netFits 2 false false = List.replicate 12 true := by decide +kernel

theorem net_phone_fold : (netFits 0 true false).take 6 = List.replicate 6 true := by decide +kernel

theorem net_lvl0_veil_bytes : netBands 0 false false =
    [16330752, 19291392, 23753952, 27541152, 27758592, 42504192, 13629120, 20300800, 22856704, 29213696, 57072640, 73849856] := by
  decide +kernel

theorem net_lvl0_fold_bytes : netBands 0 true false =
    [10533888, 11840256, 12949632, 14269824, 20307456, 20860416, 7282560, 10749440, 11395072, 14135296, 31906816, 48684032] := by
  decide +kernel

theorem net_lvl2_flip_bytes : netBands 2 false false =
    [3990528, 3545856, 1099872, -157536, 12013056, -2179584, 103360, -1833472, -1187840, -2248704, 6740992, 6740992] := by
  decide +kernel

end Fw.Parts.MorphGeom
