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

/-- The flip tree with a shrink step applied. `foldVeil`: the veil's gradient is painted into D (no own backing);
`dropPlatform`: the platform fade runs on the page's own layer. -/
def shrink (foldVeil dropPlatform : Bool) (ls : List Lyr) : List Lyr :=
  ls.map fun l =>
    if foldVeil && l.name == "veil" then { l with backed := false }
    else if dropPlatform && l.name == "platform" then { l with backed := false }
    else l

/-- Flip bytes minus faithful bytes at a band (negative: the flip tree backs less than the faithful page). -/
def netBytes (lvl : Nat) (foldVeil dropPlatform : Bool) (v : Vp) (c : Ctx) : Int :=
  (gpuBytes (dprOf v) ((shrink foldVeil dropPlatform (layers v c)).map Lyr.toLayer) : Int) -
    gpuBytes (dprOf v) ((faithfulLayers lvl v c).map Lyr.toLayer)

def netFits (lvl : Nat) (a b : Bool) : List Bool :=
  bandVps.map fun v => decide (netBytes lvl a b v (Ctx.sample v .webkit) ≤ memBudget)

def netBands (lvl : Nat) (a b : Bool) : List Int := bandVps.map fun v => netBytes lvl a b v (Ctx.sample v .webkit)

/-- Net census with only the certain faithful layer (the nav): the flip tree as designed fits 5 of 12 bands. -/
theorem net_lvl0_flip : netFits 0 false false =
    [true, true, false, false, false, false, true, true, true, false, false, false] := by decide +kernel

/-- Shrink step 1, the veil folded into the fill (REFUTED as a design, kept as a bound: the veil paints above the pictures, D below; see the finding in research/notes/2026/10-2x-geom-veil-restore.md): fits every band but 1440x900 and 1920x1080. -/
theorem net_lvl0_fold : netFits 0 true false =
    [true, true, true, true, true, true, true, true, true, true, false, false] := by decide +kernel

/-- Shrink step 2, the platform fade on the page's own layer as well: fits all 12 bands. -/
theorem net_lvl0_fold_platform : netFits 0 true true = List.replicate 12 true := by decide +kernel

/-- If the faithful page also backs the panel and the platform at the final box and viewport (INFERRED), the flip tree as
designed already fits every band: its extra layers cost less than the faithful nav, panel and platform backings it replaces. -/
theorem net_lvl2_flip : netFits 2 false false = List.replicate 12 true := by decide +kernel

/-- The phone bands (width up to 640, the dpr 3 bands) fit after step 1 whatever else the faithful page backs. -/
theorem net_phone_fold : (netFits 0 true false).take 6 = List.replicate 6 true := by decide +kernel

/-- Net bytes per band with the veil as its own layer and only the nav backed by the faithful page. The veil layer (final box,
viewport size) costs the difference to the folded design, the extra GPU memory of this restore. -/
theorem net_lvl0_veil_bytes : netBands 0 false false =
    [16330752, 19291392, 23753952, 27541152, 27758592, 42504192, 13629120, 20300800, 22856704, 29213696, 57072640, 73849856] := by
  decide +kernel

theorem net_lvl0_fold_bytes : netBands 0 true false =
    [10533888, 11840256, 12949632, 14269824, 20307456, 20860416, 7282560, 10749440, 11395072, 14135296, 31906816, 48684032] := by
  decide +kernel

/-- If the faithful page also backs the panel and the platform (level 2, INFERRED), the veil layer replaces the panel's
backing exactly (both are the final box at the viewport), so the net bytes equal the folded design with the platform dropped. -/
theorem net_lvl2_flip_bytes : netBands 2 false false =
    [3990528, 3545856, 1099872, -157536, 12013056, -2179584, 103360, -1833472, -1187840, -2248704, 6740992, 6740992] := by
  decide +kernel

end Fw.Parts.MorphGeom
