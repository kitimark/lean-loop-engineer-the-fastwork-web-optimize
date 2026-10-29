import Lean.Data.Json
import Fw.Engine.ResourceVerdict
import Fw.Parts.HeroExitOpt
import Fw.Parts.HeroExitWork
import Fw.Parts.HiddenPause
import Fw.Parts.MorphPanelOpt
import Fw.Parts.MorphMountOpt
import Fw.Parts.MorphMountDormant
import Fw.Parts.HeroCountdownOpt
import Fw.Parts.MorphCountdownStrip
import Fw.Parts.MorphIdleNone
import Fw.Parts.HeroScenePause
import Fw.Parts.NavBarFixedWork
import Fw.Parts.ReactRootOpt
import Fw.Preset.Gen

namespace Fw.Engine.Resource.Flags

open Lean Fw.Engine Fw.Engine.Resource

def sumP (ws : List Work) (s : Stage) : Nat := (ws.map (·.passes s)).sum

def sumU (ws : List Work) (s : Stage) : Nat := (ws.map (·.units s)).sum

def runSign (os vs : List Work) (s : Stage) : Sign := pairSign (sumP os s, sumU os s) (sumP vs s, sumU vs s)

def pairsSign (ps : List (Work × Work)) (s : Stage) : Sign := runSign (ps.map (·.2)) (ps.map (·.1)) s

def combine (a b : Sign) : Sign :=
  if a = .same then b else if b = .same then a else if a = b then a else .unknown

theorem combine_opposite : combine .down .up = .unknown ∧ combine .up .down = .unknown := by decide

theorem combine_same (s : Sign) : combine .same s = s ∧ combine s .same = s := by cases s <;> decide

#guard combine .down .down == .down && combine .unknown .same == .unknown && combine .up .unknown == .unknown

def ef (s : Sign) (src : String) : Effect := ⟨s, none, src⟩

def efB (s : Sign) (b : Nat) (u src : String) : Effect := ⟨s, some (b, u), src⟩

def stageEffects (f : Stage → Sign) (src : String) : List (Res × Effect) :=
  [(.style, ef (f .style) src), (.layout, ef (f .layout) src), (.paintRec, ef (f .paint) src),
   (.script, ef (f .script) src)]

def basePeak : Nat := 197145405

def navMorphBytes : Nat := gpuBytes 3 [⟨440, 120, true, true⟩, ⟨440, 120, true, true⟩]

def stripBytes : Nat := 2287000

section Threaded
open Fw.Parts.HeroExitOpt

def threadedCr : Footprint :=
  ⟨"hero.exit:threaded", .chromium,
    stageEffects (pairsSign crFrames) "HeroExitOpt.crFrames (CI lane), cr_lane_mixed" ++
    [(.event, ef .up "ReactRootOpt.records_orig: 2 records per animation event; animCount_eq: 2N + 5 CSS animations"),
     (.repaint, ef (pairsSign crFrames .raster) "HeroExitOpt.crFrames raster stage"),
     (.layers, ef .up "ledger n=6: each animated consumer adds a composited layer"),
     (.composite, ef (pairsSign crFrames .comp) "cr_lane_mixed: V.passes comp = 1, O.passes comp = 0"),
     (.gpuMem, ef .up "one backing per added layer"),
     (.frames, ef (pairsSign crFrames .script) "cr_lane_mixed: script passes drop (no rAF)")],
    none⟩

def wkStyleElemPair : (Nat × Nat) × (Nat × Nat) :=
  let EX := WebKit.webkitX WebKit.WkMode.safari
  let sum (fs : List (FrameIn WebKit.WkPropX)) : Nat × Nat :=
    ((fs.map fun f => (frameWork EX f).passes .style).sum, (fs.map (Fw.Parts.HeroExitWork.styleElems EX)).sum)
  (sum [Fw.Parts.HeroExitWork.wkOrigR2 Restyle.Node.wkFull gBand .layer, WebKit.emptyX],
    sum [wkVar WebKit.WkMode.safari gBand gN, wkIdle WebKit.WkMode.safari gBand gN])

#guard wkStyleElemPair == ((1, 123), (1, 6))
#guard pairSign wkStyleElemPair.1 wkStyleElemPair.2 == .down

def threadedWk : Footprint :=
  ⟨"hero.exit:threaded", .webkit,
    [(.style, ef (pairSign wkStyleElemPair.1 wkStyleElemPair.2)
        ("HeroExitWork.wk_style_saving: one style pass each, 6 restyled elements against 123; direction per " ++
          "element only: the phone row counts style recalcs (passes tie per frame), so its drop follows the " ++
          "frame drop 588 vs 693-696 (INFERRED)")),
     (.layout, ef (pairsSign wkFrames .layout) "HeroExitOpt.wkFrames"),
     (.paintRec, ef (combine (pairsSign wkFrames .paint) .up) "wkFrames paint down; promote_tween re-attach paint up"),
     (.script, ef (pairsSign wkFrames .script) "HeroExitOpt.wkFrames"),
     (.event, ef .up "ReactRootOpt.records_orig: 2 records per animation event; 2N + 5 CSS animations"),
     (.repaint, ef (combine (pairsSign wkFrames .paint) .up) "tween_repaint: one full paint per promotion"),
     (.layers, ef .up "wk_all_comp: every animation threaded, its target composited"),
     (.composite, ef (pairsSign wkFrames .commit) "HeroExitOpt.wkFrames commit stage"),
     (.gpuMem, ef .up "promote_tween: resident grows by the promoted area"),
     (.frames, ef (pairsSign wkFrames .script) "wkFrames: FireAnimationFrame <o")],
    none⟩

end Threaded

section ScenePause
open Fw.Parts.HeroScenePause Fw.Parts.HeroCountdownOpt

def heroLayers (h : Host) : Nat × Nat := (layers h false heroWcOnly, layers h true heroWcOnly)

theorem heroLayers_drop : heroLayers .chromium = (85, 0) ∧ heroLayers (.webkit .normal) = (85, 0) := by
  have c := hero_paused_drop .chromium rfl
  have w := hero_paused_drop (.webkit .normal) wk_normal_owns
  simp [heroLayers, c.1, c.2, w.1, w.2]

def sceneCommon (h : Host) : List (Res × Effect) :=
  [(.paintRec, ef .same "hero_wc_paint_same"), (.repaint, ef .same "hero_wc_paint_same"),
   (.layers, ef (signOf (heroLayers h).1 (heroLayers h).2) "hero_paused_drop: 85 -> 0 hero layers"),
   (.composite, ef .same "no composite pass added or removed"),
   (.gpuMem, ef .same "detached_zero: the dropped hero layers are outside coverage at the page end"),
   (.frames, ef .same "heroScene_eq_original: the rule sets an attribute from an IntersectionObserver (hero/scene.ts:23), no rAF")]

def scenePauseCr : Footprint :=
  ⟨"hero:scene-pause", .chromium,
    [(.style, ef .same "cr_realChrome_pause_eq: pausing changes no main-thread stage in real Chrome (cr_pause_style_units drops one style unit per paused animation in the CI lane only)"),
     (.layout, ef .same "cr_realChrome_pause_eq"), (.script, ef .same "cr_realChrome_pause_eq"),
     (.event, ef .unknown "no Chromium source line read for the iteration events of a paused animation")] ++
    sceneCommon .chromium, none⟩

def scenePauseWk : Footprint :=
  ⟨"hero:scene-pause", .webkit,
    [(.style, ef .same "wk_pause_eq: pausing a compositor animation changes no web-process stage"),
     (.layout, ef .same "wk_pause_eq"), (.script, ef .same "wk_pause_eq"),
     (.event, ef .unknown "OPEN: the source fall (StyleOriginatedAnimation.cpp:340-345@862f17d) is not seen; CI EventDispatch is the same on a non-slow arm (webkit-sim 40151813906 vs 40151792642)")] ++
    sceneCommon (.webkit .normal), some 211786247⟩

end ScenePause

section IdleNone
open Fw.Parts.MorphIdleNone Fw.Parts.MorphMountDormant

def idleLayers : Nat × Nat :=
  ((layerize (fun s => decide (1 ≤ s)) ([backdrop] ++ tracksOn ++ above)).length,
    (layerize (fun s => decide (1 ≤ s)) ([backdrop] ++ tracksOff ++ above)).length)

theorem idleLayers_eq : idleLayers = (5, 1) := by
  simp only [idleLayers, tracks_layers_drop.1, tracks_layers_drop.2]

def idleCommon : List (Res × Effect) :=
  [(.layout, ef .same "the tracks animate transform only (2.gBuqKVzi.css .track keyframes up/down, HiddenPause module doc)"),
   (.paintRec, ef .unknown "INFERRED: the dropped track layers paint into their host (tracks_layers_drop); the host's paint at panel opacity 0 is not modelled"),
   (.script, ef .unknown "the flag's MutationObserver callback per scene change (morph.columns/index.tsx:72-97) is not modelled"),
   (.repaint, ef .unknown "INFERRED: the dropped track layers paint into their host (tracks_layers_drop); the host's paint at panel opacity 0 is not modelled"),
   (.layers, ef (signOf idleLayers.1 idleLayers.2) "tracks_layers_drop: 5 -> 1 marquee chunk layers"),
   (.composite, ef .down "tracks_layers_drop: fewer layers to composite"),
   (.gpuMem, ef .down "tracks_layers_drop: the dropped track layers held backing"),
   (.frames, ef .same "the flag requests no frame: a MutationObserver only (morph.columns/index.tsx:72-97)")]

def idleNoneCr : Footprint :=
  ⟨"morph.columns:idle-none", .chromium,
    [(.style, ef .same "INFERRED, removal treated as pause: cr_realChrome_pause_eq covers a paused compositor animation, not animation-name none; CI style 1832 vs 1833"),
     (.event, ef .unknown "INFERRED: iteration events are equal, since the base holds the tracks paused (varStep acts only while scenePaused); animation-name none (morph.module.css:14-16) re-creates the tracks, and each new animation enqueues animationstart (css_animations.cc:3660-3666@f842f52), a count the walk does not fix")] ++
    idleCommon, none⟩

def idleNoneWk : Footprint :=
  ⟨"morph.columns:idle-none", .webkit,
    [(.style, ef .same "INFERRED, removal treated as pause: wk_pause_eq covers a paused compositor animation, not animation-name none"),
     (.event, ef .unknown "INFERRED: iteration events are equal, since the base holds the tracks paused (varStep acts only while scenePaused); animation-name none (morph.module.css:14-16) cancels and re-creates the tracks, which enqueues animationcancel and animationstart (StyleOriginatedAnimation.cpp:333-334,353-354@862f17d), a count the walk does not fix")] ++
    idleCommon, some 173708059⟩

end IdleNone

section HiddenPause
open Fw.Parts.HiddenPause

open Fw.Engine.Chromium in
def hiddenCrPairs : List (Work × Work) :=
  [1, 6].flatMap fun d => [LayerState.none, .layer, .own].map fun l =>
    let f := cdFrame (CrProp.css .transform) d l; (frameWork chromium (skipWrites f), frameWork chromium f)

open Fw.Engine.WebKit in
def hiddenWkPairs : List (Work × Work) :=
  [1, 6].flatMap fun d => [LayerState.none, .layer, .own].map fun l =>
    let f := cdFrame WkProp.transform d l; (frameWork webkit (skipWrites f), frameWork webkit f)

def hiddenCommon : List (Res × Effect) :=
  [(.event, ef .same "the flag gates JS face writes only (morph.countdown/index.tsx:59-64); the clock runs no CSS animation"),
   (.layers, ef .same "the gate changes no layer reason"), (.composite, ef .same "the gate changes no layer"),
   (.gpuMem, ef .same "the gate changes no layer"), (.frames, ef .same "skipWrites keeps the callbacks")]

def hiddenCr (_ : Unit) : Footprint :=
  ⟨"morph.countdown:hidden-pause", .chromium,
    stageEffects (pairsSign hiddenCrPairs) "hiddenCrPairs, cr_countdown_style" ++
    (.repaint, ef (pairsSign hiddenCrPairs .raster) "hiddenCrPairs raster stage") :: hiddenCommon, none⟩

def hiddenWk (_ : Unit) : Footprint :=
  ⟨"morph.countdown:hidden-pause", .webkit,
    stageEffects (pairsSign hiddenWkPairs) "hiddenWkPairs, wk_countdown_style" ++
    (.repaint, ef (pairsSign hiddenWkPairs .paint) "hiddenWkPairs paint stage") :: hiddenCommon, some 168397197⟩

end HiddenPause

section Repaint
open Fw.Engine.WebKit Fw.Parts.NavBarFixedWork Fw.Parts.NavBarFixed

theorem strip_repaint_down (a n : Nat) (ha : 0 < a) (pre mid q : List Bool) (d p : Bool) :
    signOf (repaintPx 3 (reattachPaint a ((pre ++ false :: (mid ++ true :: q)).map fun x => coverageAttached x true false)) 1)
      (repaintPx 3 (reattachPaint a (List.replicate n (coverageAttached true d p))) 1) = .down := by
  have hf := face_reattach a pre mid q
  rw [strip_no_reattach, repaintPx_dpr3, repaintPx_dpr3]
  generalize reattachPaint a _ = x at hf ⊢
  simp only [signOf]
  split <;> (try split) <;> first | rfl | omega

theorem own_frame_repaint (dpr hostPx a n : Nat) (v : Bool) : repaintPx dpr (changePx true hostPx a v) n = 0 := by
  simp [changePx, repaintPx]

theorem logo_repaint_down (v : Fw.Parts.Nav.Vp) (ms sizes : List Rat) (bar logo : Nat) (hb : 0 < bar)
    (hl : logo ≤ bar) (hr : 3 ≤ resizeCount sizes) :
    signOf (repaintPx 3 (pushResizePaint true false bar sizes) 1)
      (repaintPx 3 (pushResizePaint true false bar (ms.map (barW v)) + attachPaint false true (addedKpx .logo3d bar logo)) 1)
      = .down := by
  rw [bar_resizePaint_zero, (layer_budget bar logo).2.2.2, repaintPx_dpr3, repaintPx_dpr3]
  have h3 : 3 * bar ≤ resizeCount sizes * bar := Nat.mul_le_mul_right bar hr
  simp only [pushResizePaint, resizePaint, usesBacking, attachPaint, Bool.true_or, Bool.and_self, ite_true,
    Bool.not_false]
  generalize resizeCount sizes * bar = x at h3 ⊢
  simp only [signOf]
  split <;> (try split) <;> first | rfl | omega

theorem logo_frame_repaint_down (hostPx a n : Nat) (v : Bool) (ha : 0 < a) (h : a ≤ hostPx) (hn : 0 < n) :
    signOf (repaintPx 3 (changePx false hostPx a v) n) (repaintPx 3 (changePx true hostPx a v) n) = .down := by
  have hp := (pushed_repaint hostPx a v h).2.1
  rw [own_frame_repaint, repaintPx_dpr3]
  have : 0 < 9 * changePx false hostPx a v * n := Nat.mul_pos (by omega) hn
  simp only [signOf]
  split <;> first | rfl | omega

theorem panel_repaint_up (a n : Nat) (ha : 0 < a) (l : List Bool) :
    signOf (repaintPx 3 (reattachPaint a (List.replicate n true)) 1)
      (repaintPx 3 (reattachPaint a (false :: true :: l)) 1) = .up := by
  have ⟨hu, hz⟩ := tween_repaint a n l
  rw [hz, repaintPx_dpr3, repaintPx_dpr3]
  generalize reattachPaint a (false :: true :: l) = x at hu ⊢
  simp only [signOf]
  split <;> (try split) <;> first | rfl | omega

def stripRepaint : Nat × Nat :=
  (repaintPx 3 (reattachPaint 1 [true, false, true]) 1, repaintPx 3 (reattachPaint 1 (List.replicate 3 true)) 1)

def logoRepaint : Nat × Nat :=
  (repaintPx 3 (pushResizePaint true false 1 [0, 1, 2, 3]) 1, repaintPx 3 (attachPaint false true (addedKpx .logo3d 1 1)) 1)

def logoFrameRepaint : Nat × Nat :=
  (repaintPx 3 (changePx false 8192 1 true) 1, repaintPx 3 (changePx true 8192 1 true) 1)

def panelRepaint : Nat × Nat :=
  (repaintPx 3 (reattachPaint 1 (List.replicate 3 true)) 1, repaintPx 3 (reattachPaint 1 [false, true, true]) 1)

#guard stripRepaint == (9, 0) && logoRepaint == (27, 18) && logoFrameRepaint == (9, 0) && panelRepaint == (0, 9)
#guard signOf stripRepaint.1 stripRepaint.2 == .down && signOf logoRepaint.1 logoRepaint.2 == .down
#guard signOf panelRepaint.1 panelRepaint.2 == .up

end Repaint

section Strip
open Fw.Parts.HeroCountdownOpt Fw.Parts.MorphCountdownStrip

def stripRuns {P M : Type} (E : Engine P M) (p : P) : List Work × List Work :=
  ([frameWork E (withWrites ⟨0, 0, 0, 0, [], 0⟩ (faceWrites p .own (List.range 8)))],
    [frameWork E (withWrites ⟨0, 0, 0, 0, [], 0⟩ (stripWrites p .own (List.range 8)))])

def clockLayerPair (h : Host) : Nat × Nat := ((facesResident h true 8 1).layers, (stripResident h true 8 1).layers)

theorem clockLayerPair_eq : clockLayerPair .chromium = (80, 8) ∧ clockLayerPair (.webkit .normal) = (80, 8) := by
  have c := hero_layers .chromium true 1 rfl
  have w := hero_layers (.webkit .normal) true 1 Fw.Parts.HeroScenePause.wk_normal_owns
  simp [clockLayerPair, c.1, c.2.1, w.1, w.2.1]

def stripDriverSrc : String := "the same spring driver writes one inline transform per digit (hero.countdown/driver.ts:61-70)"

def stripCr : Footprint :=
  let r := stripRuns Chromium.chromium (Chromium.CrProp.css .transform)
  ⟨"morph.countdown:strip", .chromium,
    stageEffects (runSign r.1 r.2) "strip_units: 9 fewer units per digit" ++
    [(.event, ef .same stripDriverSrc),
     (.repaint, ef .unknown "own_frame_repaint: faces and strips repaint the same per frame; Chromium tile retention off-screen not modelled"),
     (.layers, efB (signOf (clockLayerPair .chromium).1 (clockLayerPair .chromium).2) 72 "layers per census state"
        "hero_layers: 80 -> 8 clock layers"),
     (.composite, ef .down "hero_layers: fewer layers to composite"),
     (.gpuMem, ef .up "strip_backing_gt: 10na -> 12na"), (.frames, ef .same stripDriverSrc)],
    none⟩

def stripWk : Footprint :=
  let r := stripRuns WebKit.webkit WebKit.WkProp.transform
  ⟨"morph.countdown:strip", .webkit,
    stageEffects (runSign r.1 r.2) "strip_units: 9 fewer units per digit" ++
    [(.event, ef .same stripDriverSrc),
     (.repaint, ef (signOf stripRepaint.1 stripRepaint.2) "strip_repaint_down at DPR 3: a face re-attach repaints 9a device px, a strip none"),
     (.layers, efB (signOf (clockLayerPair (.webkit .normal)).1 (clockLayerPair (.webkit .normal)).2) 72
        "layers per census state" "hero_layers, layers_80_to_16: 80 -> 8 clock layers"),
     (.composite, ef .down "hero_layers: fewer layers to composite"),
     (.gpuMem, efB .up stripBytes "bytes of hero clock backing"
        "strip_backing_gt: 10na -> 12na; bound the Simulator's 2.287 MB clock backing"),
     (.frames, ef .same stripDriverSrc)],
    some (basePeak + stripBytes)⟩

def stripPeakSrc : String :=
  "mixed: phone end-counts base peak (basePeak, 2026-10-25) plus the Simulator's hero clock backing (stripBytes, run 40081936555)"

def stripPhonePeak : Nat := 191681597

theorem strip_peaks_fit :
    stripWk.peak = some (basePeak + stripBytes) ∧ basePeak + stripBytes ≤ budgetB ∧ stripPhonePeak ≤ budgetB ∧
      stripPhonePeak ≤ basePeak + stripBytes := ⟨rfl, by decide, by decide, by decide⟩

end Strip

section PanelRest
open Fw.Parts.MorphPanelOpt

def panelRestSrc : String := "filterO_rest, filterV_rest: only the rest filter value changes"

def panelCr : Footprint :=
  ⟨"morph.panel:rest", .chromium,
    stageEffects (runSign crO crV) "MorphPanelOpt.crO/crV, cr_toggle_not_le" ++
    [(.event, ef .same panelRestSrc), (.repaint, ef (runSign crO crV .raster) "MorphPanelOpt.crO/crV raster"),
     (.layers, ef .same "Chromium keeps no layer for blur(0)"), (.composite, ef (runSign crO crV .comp) "crO/crV comp"),
     (.gpuMem, ef .same "Chromium keeps no layer for blur(0)"), (.frames, ef .same panelRestSrc)],
    none⟩

def panelWk : Footprint :=
  ⟨"morph.panel:rest", .webkit,
    stageEffects (runSign wkO wkV) "MorphPanelOpt.wkO/wkV" ++
    [(.event, ef .same panelRestSrc),
     (.repaint, ef (signOf panelRepaint.1 panelRepaint.2) "INFERRED: panel_repaint_up at DPR 3, one full group-layer paint per none to blur toggle; no theorem links filterToggle to the re-attach"),
     (.layers, efB .down 1 "layers per census state" "wk_rest_layers: one layer less at rest"),
     (.composite, ef (runSign wkO wkV .comp) "wkO/wkV comp"),
     (.gpuMem, ef .down "wkResident: the group layer's backing is freed at rest"), (.frames, ef .same panelRestSrc)],
    none⟩

end PanelRest

section Logo
open Fw.Parts.NavBarFixedWork

def logoCrRuns : List Work × List Work :=
  ([frameWork Chromium.chromium ⟨0, 0, 0, 0, [⟨1, .css .left, .none⟩], 0⟩],
    [frameWork Chromium.chromium ⟨0, 0, 0, 0, [⟨1, .css .transform, .own⟩], 0⟩])

def logoWkRuns : List Work × List Work :=
  ([frameWork WebKit.webkit logoLeftFrame, frameWork WebKit.webkit barInsetFrame],
    [frameWork WebKit.webkit (logo3dFrame .normal), frameWork WebKit.webkit (barTranslateFrame .normal)])

def logoCommon : List (Res × Effect) :=
  [(.event, ef .unknown "the logo moves by transform instead of translate and scale (nav/box.module.css:53-57) while the nav keeps the original transition lists (box.module.css:4); transition events not modelled"),
   (.layers, ef .up "layer_budget: mask, bar and logo while morphing; none at rest (box.module.css .is-morphing)"),
   (.composite, ef .up "layer_budget: three more layers while morphing"),
   (.gpuMem, ef .up "layer_budget: bar and logo backing while morphing; the mask holds none"),
   (.frames, ef .same "a CSS-only change (nav/box.module.css:53-57): no rAF")]

def logoCr : Footprint :=
  ⟨"nav:logo-3d", .chromium, stageEffects (runSign logoCrRuns.1 logoCrRuns.2) "Chromium stage rules: left vs transform" ++
    (.repaint, ef (signOf logoFrameRepaint.1 logoFrameRepaint.2)
      "INFERRED: logo_frame_repaint_down at DPR 3 per frame; the promotion raster is not modelled") :: logoCommon, none⟩

def logoWk : Footprint :=
  ⟨"nav:logo-3d", .webkit,
    stageEffects (runSign logoWkRuns.1 logoWkRuns.2) "logo3d_layout_normal, bar_layout_normal" ++
      (.repaint, ef (signOf logoRepaint.1 logoRepaint.2)
        "INFERRED: logo_repaint_down at DPR 3 if the bar resizes at least three times per morph") :: logoCommon,
    some (basePeak + navMorphBytes)⟩

end Logo

section ShiftDormant
open Fw.Parts.MorphMountOpt

def dormantCommon : List (Res × Effect) :=
  [(.event, ef .same "the dormant panel runs no animation before the original trigger (dormant_iff)"),
   (.repaint, ef .same "visSame_dormant: same pixels"), (.layers, ef .same "census_dormant_eq"),
   (.composite, ef .same "layers_dormant_eq"), (.gpuMem, ef .same "census_dormant_eq"),
   (.frames, ef .same "no countdown driver before the trigger")]

def dormantCr : Footprint :=
  ⟨"morph.mount:shift-dormant", .chromium,
    stageEffects (runSign crO crV) "MorphMountOpt.crO/crV: the mount shifts, totals equal" ++ dormantCommon, none⟩

def dormantWk : Footprint :=
  ⟨"morph.mount:shift-dormant", .webkit,
    stageEffects (runSign wkO wkV) "MorphMountOpt.wkO/wkV: the mount shifts, totals equal" ++ dormantCommon,
    some 191681597⟩

end ShiftDormant

section Quiet
open Fw.Parts.ReactRootOpt

def quietRecords : Nat × Nat := (records regs "animationend", records quietRegs "animationend")

theorem quietRecords_eq : quietRecords = (2, 0) := by
  have o := records_orig "animationend" (by decide)
  have q := records_quiet "animationend" (by decide)
  simp [quietRecords, o, q]

def quietSrc : String := "quietRegs: the flag only drops root listener registrations"

def quietCommon : List (Res × Effect) :=
  [(.style, ef .same quietSrc), (.layout, ef .same quietSrc), (.paintRec, ef .same quietSrc),
   (.repaint, ef .same quietSrc), (.layers, ef .same quietSrc), (.composite, ef .same quietSrc),
   (.gpuMem, ef .same quietSrc), (.frames, ef .same quietSrc)]

def quietCr : Footprint :=
  ⟨"engine.events:quiet", .chromium,
    [(.event, ef .unknown "css_animations.cc:3610@f842f52 creates an animation event only while the document has a listener of its type; the page's other listeners are not enumerated"),
     (.script, ef .unknown "Chromium listener call records not read from source")] ++ quietCommon, none⟩

def quietWk : Footprint :=
  ⟨"engine.events:quiet", .webkit,
    [(.event, ef (signOf quietRecords.1 quietRecords.2) "records_orig, records_quiet: 2 -> 0 records per quiet event"),
     (.script, ef .down "records_quiet: no root listener call (EventTarget.cpp:313-357@862f17d)")] ++ quietCommon,
    some 191681597⟩

end Quiet

def footprints (_ : Unit) : List Footprint :=
  [threadedCr, threadedWk, scenePauseCr, scenePauseWk, idleNoneCr, idleNoneWk, hiddenCr (), hiddenWk (), stripCr, stripWk,
   panelCr, panelWk, logoCr, logoWk, dormantCr, dormantWk, quietCr, quietWk]

def footprint? (flag : String) (e : Eng) : Option Footprint := (footprints ()).find? fun f => f.flag == flag && f.eng == e

def verdicts (B : Nat) : List (String × Eng × Verdict) := (footprints ()).map fun f => (f.flag, f.eng, verdict B f)

#guard (footprints ()).length == 18
#guard (footprints ()).all fun f => Res.all.all fun r => (f.effects.filter (·.1 == r)).length == 1
#guard verdicts budgetB == [
  ("hero.exit:threaded", .chromium, .trade), ("hero.exit:threaded", .webkit, .trade),
  ("hero:scene-pause", .chromium, .open), ("hero:scene-pause", .webkit, .open),
  ("morph.columns:idle-none", .chromium, .open), ("morph.columns:idle-none", .webkit, .open),
  ("morph.countdown:hidden-pause", .chromium, .win), ("morph.countdown:hidden-pause", .webkit, .win),
  ("morph.countdown:strip", .chromium, .open), ("morph.countdown:strip", .webkit, .win),
  ("morph.panel:rest", .chromium, .trade), ("morph.panel:rest", .webkit, .trade),
  ("nav:logo-3d", .chromium, .open), ("nav:logo-3d", .webkit, .open),
  ("morph.mount:shift-dormant", .chromium, .neutral), ("morph.mount:shift-dormant", .webkit, .neutral),
  ("engine.events:quiet", .chromium, .open), ("engine.events:quiet", .webkit, .win)]

theorem strip_claim_trade_verdict_win (a : Nat) (ha : 0 < a) :
    claim (.ok .dominates) (Fw.Parts.HeroCountdownOpt.stripResident (.webkit .normal) true 8 a)
        (Fw.Parts.HeroCountdownOpt.facesResident (.webkit .normal) true 8 a) = .trade ∧
      stripWk.sign .gpuMem = .up ∧ stripWk.peak = some (basePeak + stripBytes) ∧ basePeak + stripBytes ≤ budgetB :=
  ⟨(Fw.Parts.HeroCountdownOpt.strip_label_fullLayer _ true 8 a Fw.Parts.HeroScenePause.wk_normal_owns (by decide) ha).2,
    rfl, rfl, by decide⟩

theorem navMorphBytes_eq : navMorphBytes = 3801600 := by decide

def phoneSrc : String := "phone 2026-10-25 (results/phone/2026-10-25-end-counts)"

structure Obs where
  flag : String
  eng : Eng
  src : String
  res : Res
  unit : String
  base : Range
  arm : Range
  tol : Nat
  slow : Bool
deriving Repr

def phoneUnit : Res → String
  | .gpuMem => "KiB summed over the three census states y >= 3000"
  | .layers => "layers summed over the three census states y >= 3000"
  | .repaint => "thousand root-view CSS px² summed over a walk" | .frames => "frames per run"
  | _ => "records per run"

def phoneBase : Res → Range
  | .style => ⟨646, 651⟩ | .layout => ⟨609, 632⟩ | .paintRec => ⟨1569, 1608⟩ | .script => ⟨1436, 1558⟩
  | .event => ⟨902, 1024⟩ | .repaint => ⟨77464, 82927⟩ | .layers => ⟨401, 401⟩ | .composite => ⟨213, 213⟩
  | .gpuMem => ⟨384778, 412853⟩ | .frames => ⟨693, 696⟩

def phoneBaseWallHi : Nat := 4077

def phoneArm (flag : String) (wallLo : Nat) (rs : List Range) : List Obs :=
  (Res.all.zip rs).map fun (r, a) =>
    ⟨flag, .webkit, phoneSrc, r, phoneUnit r, phoneBase r, a, 0, slowWalk phoneBaseWallHi wallLo⟩

def phoneObs : List Obs :=
  phoneArm "hero.exit:threaded" 3677 [⟨627, 631⟩, ⟨518, 531⟩, ⟨1801, 1939⟩, ⟨1492, 1577⟩, ⟨1079, 1165⟩,
    ⟨79543, 83636⟩, ⟨414, 414⟩, ⟨213, 213⟩, ⟨384778, 400258⟩, ⟨588, 588⟩] ++
  phoneArm "hero:scene-pause" 8640 [⟨668, 690⟩, ⟨608, 641⟩, ⟨1279, 1339⟩, ⟨1675, 2018⟩, ⟨1163, 1505⟩,
    ⟨67326, 72623⟩, ⟨146, 146⟩, ⟨213, 213⟩, ⟨384778, 446784⟩, ⟨712, 741⟩] ++
  phoneArm "morph.columns:idle-none" 3646 [⟨647, 649⟩, ⟨621, 631⟩, ⟨1491, 1573⟩, ⟨1512, 1634⟩, ⟨975, 1096⟩,
    ⟨77797, 80656⟩, ⟨365, 365⟩, ⟨213, 213⟩, ⟨354860, 354860⟩, ⟨694, 695⟩] ++
  phoneArm "morph.countdown:hidden-pause" 6791 [⟨664, 694⟩, ⟨605, 641⟩, ⟨1280, 1371⟩, ⟨1733, 2035⟩, ⟨1223, 1523⟩,
    ⟨68025, 78212⟩, ⟨401, 413⟩, ⟨213, 213⟩, ⟨384778, 384778⟩, ⟨708, 741⟩] ++
  phoneArm "morph.mount:shift-dormant" 3694 [⟨650, 652⟩, ⟨617, 632⟩, ⟨1564, 1580⟩, ⟨1612, 1721⟩, ⟨1072, 1184⟩,
    ⟨78724, 81458⟩, ⟨401, 413⟩, ⟨213, 213⟩, ⟨392518, 407517⟩, ⟨695, 696⟩] ++
  phoneArm "nav:logo-3d" 8032 [⟨661, 670⟩, ⟨612, 628⟩, ⟨1342, 1374⟩, ⟨1687, 1723⟩, ⟨1150, 1188⟩,
    ⟨72440, 75167⟩, ⟨401, 401⟩, ⟨213, 213⟩, ⟨377520, 400258⟩, ⟨725, 727⟩] ++
  phoneArm "engine.events:quiet" 3664 [⟨646, 647⟩, ⟨614, 623⟩, ⟨1606, 1622⟩, ⟨993, 999⟩, ⟨460, 462⟩,
    ⟨81084, 82620⟩, ⟨402, 402⟩, ⟨213, 213⟩, ⟨407517, 407517⟩, ⟨694, 695⟩]

def thermalSrc : String :=
  "phone 2026-10-25 thermal session (phone-thermal-check): 9 base and 3 strip passes, every visit ended at Serious"

def thermalStrip : List Obs :=
  let rows : List (Res × Range × Range) :=
    [(.style, ⟨621, 648⟩, ⟨646, 646⟩), (.layout, ⟨580, 620⟩, ⟨609, 616⟩), (.paintRec, ⟨1432, 1618⟩, ⟨1572, 1573⟩),
     (.script, ⟨1428, 1545⟩, ⟨1442, 1445⟩), (.event, ⟨893, 1012⟩, ⟨910, 914⟩), (.repaint, ⟨69688, 82278⟩, ⟨80110, 81312⟩),
     (.composite, ⟨213, 213⟩, ⟨213, 213⟩), (.frames, ⟨671, 681⟩, ⟨681, 681⟩)]
  rows.map fun (r, b, a) => ⟨"morph.countdown:strip", .webkit, thermalSrc, r, phoneUnit r, b, a, 0, slowWalk 3784 3607⟩

def sceneSimSrc : String := "webkit-sim 40151813906 vs 40151792642 (4 base, 6 flag passes)"

def sceneSimSlow : Bool := slowWalk 7262 7378

def panelSimSrc : String := "webkit-sim 40174475566 vs 40174472900 (6 passes each)"

def panelSimSlow : Bool := slowWalk 11316 6757

#guard !sceneSimSlow && !panelSimSlow && !slowWalk 3784 3607

def ciObs : List Obs :=
  [⟨"morph.columns:idle-none", .webkit, "webkit-sim 39897814980 vs 39897807511, y=3000", .layers,
      "layers per census state", ⟨136, 140⟩, ⟨124, 128⟩, 0, false⟩,
   ⟨"morph.columns:idle-none", .webkit, "webkit-sim 39897814980 vs 39897807511, backing MB", .gpuMem,
      "MB of layer backing per census state", ⟨101, 101⟩, ⟨85, 85⟩, 0, false⟩,
   ⟨"morph.columns:idle-none", .chromium, "chromium 39897804079 vs 39897818039, layer-frames", .layers,
      "layer-frames per run", ⟨28107, 28107⟩, ⟨24667, 24667⟩, 0, false⟩,
   ⟨"morph.columns:idle-none", .chromium, "chromium 39897804079 vs 39897818039", .style, "records per run",
      ⟨1832, 1832⟩, ⟨1833, 1833⟩, 1, false⟩,
   ⟨"morph.columns:idle-none", .chromium, "chromium 39897804079 vs 39897818039", .layout, "records per run",
      ⟨318, 318⟩, ⟨319, 319⟩, 1, false⟩,
   ⟨"hero:scene-pause", .webkit, "webkit-sim 40151813906 vs 40151792642, y=3000", .layers, "layers per census state",
      ⟨124, 128⟩, ⟨39, 47⟩, 0, false⟩,
   ⟨"morph.countdown:strip", .webkit, "webkit-sim 39897814980 vs 40081936555, finish zone", .layers,
      "layers per census state", ⟨124, 128⟩, ⟨56, 56⟩, 0, false⟩,
   ⟨"morph.countdown:strip", .webkit, "webkit-sim 39897814980 vs 40081936555, hero clock backing", .gpuMem,
      "bytes of hero clock backing", ⟨591000, 591000⟩, ⟨2287000, 2287000⟩, 0, false⟩,
   ⟨"engine.events:quiet", .webkit, "webkit-sim 40134016822 vs 40134234199", .event, "records per run",
      ⟨1099, 1132⟩, ⟨527, 529⟩, 0, false⟩,
   ⟨"engine.events:quiet", .webkit, "webkit-sim 40134016822 vs 40134234199", .script, "records per run",
      ⟨1623, 1646⟩, ⟨1042, 1045⟩, 0, false⟩,
   ⟨"morph.mount:shift-dormant", .chromium, "chromium 39325709978 vs 39325721909, layer census", .layers,
      "layers per census state", ⟨0, 0⟩, ⟨0, 0⟩, 0, false⟩,
   ⟨"morph.mount:shift-dormant", .chromium, "chromium 39325709978 vs 39325721909, layouts relative to faithful",
      .layout, "layouts relative to faithful", ⟨3, 3⟩, ⟨0, 0⟩, 0, false⟩,
   ⟨"morph.mount:shift-dormant", .chromium, "chromium 39325709978 vs 39325721909, resolved elements relative",
      .style, "resolved elements relative to faithful", ⟨0, 0⟩, ⟨200, 200⟩, 0, false⟩,
   ⟨"hero:scene-pause", .webkit, sceneSimSrc, .event, "records per run", ⟨1053, 1179⟩, ⟨1072, 1674⟩, 0, sceneSimSlow⟩,
   ⟨"hero:scene-pause", .webkit, sceneSimSrc, .style, "records per run", ⟨647, 651⟩, ⟨657, 688⟩, 0, sceneSimSlow⟩,
   ⟨"morph.panel:rest", .webkit, panelSimSrc, .paintRec, "records per run", ⟨1352, 1409⟩, ⟨1433, 1678⟩, 0, panelSimSlow⟩,
   ⟨"morph.panel:rest", .webkit, panelSimSrc, .repaint, "root-view CSS px² summed over a walk",
      ⟨70220353, 75135657⟩, ⟨63691076, 72290092⟩, 0, panelSimSlow⟩,
   ⟨"morph.panel:rest", .webkit, panelSimSrc, .event, "records per run", ⟨988, 1420⟩, ⟨1183, 1948⟩, 0, panelSimSlow⟩,
   ⟨"morph.panel:rest", .webkit, panelSimSrc, .style, "records per run", ⟨648, 677⟩, ⟨648, 693⟩, 0, panelSimSlow⟩,
   ⟨"morph.panel:rest", .webkit, panelSimSrc, .layout, "records per run", ⟨610, 630⟩, ⟨617, 664⟩, 0, panelSimSlow⟩,
   ⟨"morph.panel:rest", .webkit, panelSimSrc, .gpuMem, "KiB summed over the census states y >= 3000",
      ⟨347962, 358260⟩, ⟨304047, 304047⟩, 0, panelSimSlow⟩]

def observations : List Obs := phoneObs ++ ciObs ++ thermalStrip


def predicted (o : Obs) : Sign := ((footprint? o.flag o.eng).map (·.sign o.res)).getD .unknown

def obsCheck (o : Obs) : Check := check o.res o.slow (predicted o) (measuredSign o.base o.arm o.tol)

def withCheck (c : Check) : List Obs := observations.filter (obsCheck · == c)

def mechanisms : List (String × Eng × Res × String) :=
  [("hero.exit:threaded", .webkit, .paintRec,
     "INFERRED: re-attach paints of the promoted animation targets (promote_tween) outweigh the per-frame paint drop"),
   ("hero.exit:threaded", .webkit, .repaint,
     "INFERRED: the re-attach area is a small share of the walk's paint area, inside the pass spread"),
   ("morph.mount:shift-dormant", .webkit, .event,
     "INFERRED: the early-mounted panel's transitions reach the React root listeners (records_orig)"),
   ("morph.mount:shift-dormant", .webkit, .script,
     "INFERRED: the same root listener calls as the EventDispatch rise"),
   ("morph.mount:shift-dormant", .chromium, .layout,
     "MEASURED: the early mount merges into a frame that already lays out; the shift model keeps totals equal"),
   ("morph.mount:shift-dormant", .chromium, .style,
     "MEASURED: about 200 more resolved elements while the dormant panel is mounted; the model has no dormant restyle"),
   ("engine.events:quiet", .webkit, .layers, "OPEN: one more layer at y=4500 in all three passes"),
   ("morph.columns:idle-none", .webkit, .paintRec,
     "OPEN: the host's paint of the dropped track layers is not modelled; measured inside the pass spread"),
   ("morph.columns:idle-none", .webkit, .repaint,
     "OPEN: the host's paint of the dropped track layers is not modelled; measured inside the pass spread"),
   ("morph.columns:idle-none", .webkit, .script,
     "OPEN: the flag's MutationObserver callbacks are not modelled; measured inside the pass spread"),
   ("morph.columns:idle-none", .webkit, .event,
     "OPEN: the animationcancel and animationstart of the re-created tracks are not counted; measured inside the pass spread"),
   ("hero:scene-pause", .webkit, .style,
     "MEASURED: 6 to 37 more style records per run on a non-slow arm; INFERRED: the pause attribute write per scene change (hero/scene.ts:23) restyles the hero subtree"),
   ("hero:scene-pause", .webkit, .event,
     "OPEN: the INFERRED source fall is not seen; EventDispatch is inside the pass spread on a non-slow arm"),
   ("morph.panel:rest", .webkit, .paintRec,
     "raw MEASURED: Paint records rise on rest frames, quarantined and load-confounded (panel-rest-n11); the decided trade is INFERRED, from the group layer's re-attach paint per toggle (panel_repaint_up)")]

def ledgerLabels : List (String × Eng × String) :=
  [("hero.exit:threaded", .chromium, "trade"), ("hero.exit:threaded", .webkit, "trade"),
   ("hero:scene-pause", .chromium, "trade"), ("hero:scene-pause", .webkit, "win"),
   ("morph.columns:idle-none", .chromium, "win"), ("morph.columns:idle-none", .webkit, "win"),
   ("morph.countdown:hidden-pause", .chromium, "win"), ("morph.countdown:hidden-pause", .webkit, "win"),
   ("morph.countdown:strip", .chromium, "trade"), ("morph.countdown:strip", .webkit, "trade"),
   ("morph.panel:rest", .chromium, "trade"), ("morph.panel:rest", .webkit, "win"),
   ("nav:logo-3d", .chromium, "unknown"), ("nav:logo-3d", .webkit, "unknown"),
   ("morph.mount:shift-dormant", .chromium, "trade"), ("morph.mount:shift-dormant", .webkit, "unknown"),
   ("engine.events:quiet", .chromium, "no-win"), ("engine.events:quiet", .webkit, "win")]

#guard [Check.agree, .unresolved, .confounded, .disagree, .unpredicted].map (withCheck · |>.length) == [52, 9, 24, 7, 7]
#guard (withCheck .unpredicted).map (fun o => (o.flag, o.eng.name, o.res.name)) == [
  ("hero.exit:threaded", "webkit", "paintRecords"), ("hero.exit:threaded", "webkit", "repaintArea"),
  ("morph.columns:idle-none", "webkit", "paintRecords"), ("morph.columns:idle-none", "webkit", "script"),
  ("morph.columns:idle-none", "webkit", "eventDispatch"), ("morph.columns:idle-none", "webkit", "repaintArea"),
  ("hero:scene-pause", "webkit", "eventDispatch")]
#guard (withCheck .disagree).map (fun o => (o.flag, o.eng.name, o.res.name)) == [
  ("morph.mount:shift-dormant", "webkit", "script"),
  ("morph.mount:shift-dormant", "webkit", "eventDispatch"), ("engine.events:quiet", "webkit", "layers"),
  ("morph.mount:shift-dormant", "chromium", "layout"), ("morph.mount:shift-dormant", "chromium", "style"),
  ("hero:scene-pause", "webkit", "style"), ("morph.panel:rest", "webkit", "paintRecords")]
#guard (withCheck .disagree ++ withCheck .unpredicted).all fun o =>
  mechanisms.any fun (f, e, r, _) => f == o.flag && e == o.eng && r == o.res

def maxChange (b a : Range) : Nat := max (a.hi - b.lo) (b.hi - a.lo)

def obsOf (fp : Footprint) (r : Res) : List Obs :=
  observations.filter fun o => o.flag == fp.flag && o.eng == fp.eng && o.res == r

def boundHolds (fp : Footprint) (r : Res) (e : Effect) : Bool :=
  match e.bound with
  | none => true
  | some (b, u) => (obsOf fp r).all fun o => o.unit == u && decide (maxChange o.base o.arm ≤ b)

def bounded (_ : Unit) : List (String × Eng × Res × Nat × String × Nat) :=
  (footprints ()).flatMap fun fp => fp.effects.filterMap fun (r, e) =>
    e.bound.map fun (b, u) => (fp.flag, fp.eng, r, b, u, (obsOf fp r).length)

#guard (footprints ()).all fun fp => fp.effects.all fun (r, e) => boundHolds fp r e
#guard bounded () == [
  ("morph.countdown:strip", .chromium, .layers, 72, "layers per census state", 0),
  ("morph.countdown:strip", .webkit, .layers, 72, "layers per census state", 1),
  ("morph.countdown:strip", .webkit, .gpuMem, 2287000, "bytes of hero clock backing", 1),
  ("morph.panel:rest", .webkit, .layers, 1, "layers per census state", 0)]
#guard maxChange ⟨124, 128⟩ ⟨56, 56⟩ == 72 && maxChange ⟨591000, 591000⟩ ⟨2287000, 2287000⟩ == 1696000
#guard maxChange ⟨124, 128⟩ ⟨39, 47⟩ == 89 && maxChange ⟨136, 140⟩ ⟨124, 128⟩ == 16

structure CensusRow where
  y : Nat
  base : Range
  arm : Range
deriving Repr

def thermalStripLayers : List CensusRow :=
  [⟨0, ⟨110, 112⟩, ⟨38, 40⟩⟩, ⟨1500, ⟨116, 118⟩, ⟨40, 42⟩⟩, ⟨3000, ⟨136, 136⟩, ⟨64, 64⟩⟩, ⟨4500, ⟨139, 142⟩, ⟨69, 69⟩⟩,
   ⟨5267, ⟨124, 124⟩, ⟨52, 52⟩⟩]

def thermalStripBytes : List CensusRow :=
  [⟨0, ⟨39510317, 39510317⟩, ⟨41630605, 41630605⟩⟩, ⟨1500, ⟨99667292, 99723526⟩, ⟨99667292, 99730800⟩⟩,
   ⟨3000, ⟨108952364, 108952364⟩, ⟨108952364, 116385244⟩⟩, ⟨4500, ⟨168397197, 168397197⟩, ⟨168397197, 191681597⟩⟩,
   ⟨5267, ⟨109230592, 109230592⟩, ⟨109230592, 109230592⟩⟩]

def minDrop (b a : Range) : Nat := b.lo - a.hi

#guard thermalStripLayers.map (fun c => (c.y, maxChange c.base c.arm)) == [(0, 74), (1500, 78), (3000, 72), (4500, 73), (5267, 72)]
#guard thermalStripLayers.map (fun c => (c.y, minDrop c.base c.arm)) == [(0, 70), (1500, 74), (3000, 72), (4500, 70), (5267, 72)]
#guard thermalStripBytes.map (fun c => (c.y, c.arm.hi - c.base.lo)) ==
  [(0, 2120288), (1500, 63508), (3000, 7432880), (4500, 23284400), (5267, 0)]

def moved (o : Obs) : Option Sign :=
  if o.slow && !o.res.census then none
  else match measuredSign o.base o.arm o.tol with
    | .same => none
    | s => some s

def evidenceSign : List Sign → Option Sign
  | [] => none
  | s :: ss => some (if ss.all (· == s) then s else .unknown)

def resolvedSign (fp : Footprint) (r : Res) : Sign := (evidenceSign ((obsOf fp r).filterMap moved)).getD (fp.sign r)

def resolved (fp : Footprint) : Footprint :=
  { fp with effects := fp.effects.map fun (r, e) => (r, { e with sign := resolvedSign fp r }) }

def decided (B : Nat) (fp : Footprint) : Verdict := verdict B (resolved fp)

theorem moved_slow (o : Obs) (hs : o.slow = true) (hc : o.res.census = false) : moved o = none := by
  simp [moved, hs, hc]

theorem moved_same (o : Obs) (h : measuredSign o.base o.arm o.tol = .same) : moved o = none := by
  unfold moved; split <;> simp [h]

theorem moved_move (o : Obs) (h : (o.slow && !o.res.census) = false) (hm : measuredSign o.base o.arm o.tol ≠ .same) :
    moved o = some (measuredSign o.base o.arm o.tol) := by
  unfold moved
  simp only [h, Bool.false_eq_true, ite_false]

theorem evidence_none : evidenceSign [] = none := rfl

theorem evidence_agree (s : Sign) (ss : List Sign) (h : ∀ x ∈ ss, x = s) : evidenceSign (s :: ss) = some s := by
  have : ss.all (· == s) = true := List.all_eq_true.mpr fun x hx => by simp [h x hx]
  simp [evidenceSign, this]

theorem evidence_conflict (s t : Sign) (ss : List Sign) (ht : t ∈ ss) (hne : t ≠ s) :
    evidenceSign (s :: ss) = some .unknown := by
  have : ss.all (· == s) = false := List.all_eq_false.mpr ⟨t, ht, by simpa using hne⟩
  simp [evidenceSign, this]

theorem resolved_predicted (fp : Footprint) (r : Res) (h : (obsOf fp r).filterMap moved = []) :
    resolvedSign fp r = fp.sign r := by
  simp [resolvedSign, h, evidence_none]

theorem resolved_measured (fp : Footprint) (r : Res) (s : Sign) (ss : List Sign)
    (h : (obsOf fp r).filterMap moved = s :: ss) (hs : ∀ x ∈ ss, x = s) : resolvedSign fp r = s := by
  simp [resolvedSign, h, evidence_agree s ss hs]

#guard evidenceSign [.up, .up] == some .up && evidenceSign [.up, .down] == some .unknown && evidenceSign [] == none
#guard moved ⟨"x", .webkit, "", .style, "", ⟨1, 2⟩, ⟨5, 6⟩, 0, true⟩ == none
#guard moved ⟨"x", .webkit, "", .layers, "", ⟨1, 2⟩, ⟨5, 6⟩, 0, true⟩ == some .up
#guard moved ⟨"x", .webkit, "", .style, "", ⟨1, 2⟩, ⟨2, 6⟩, 0, false⟩ == none

def decidedVerdicts (B : Nat) : List (String × Eng × Verdict) := (footprints ()).map fun f => (f.flag, f.eng, decided B f)

def decidedOf (flag : String) (e : Eng) : Option Verdict := (footprint? flag e).map (decided budgetB ·)

def becomesWin (B : Nat) : List (String × Eng) :=
  (ledgerLabels.filter fun (f, e, l) => l == "trade" && ((footprint? f e).map (decided B ·)) == some .win).map
    fun (f, e, _) => (f, e)

def leavesWin (B : Nat) : List (String × Eng × Verdict) :=
  (ledgerLabels.filter fun (f, e, l) => l == "win" && ((footprint? f e).map (decided B ·)) != some .win).filterMap
    fun (f, e, _) => (footprint? f e).map fun fp => (f, e, decided B fp)

#guard decidedVerdicts budgetB == [
  ("hero.exit:threaded", .chromium, .trade), ("hero.exit:threaded", .webkit, .trade),
  ("hero:scene-pause", .chromium, .open), ("hero:scene-pause", .webkit, .trade),
  ("morph.columns:idle-none", .chromium, .open), ("morph.columns:idle-none", .webkit, .open),
  ("morph.countdown:hidden-pause", .chromium, .win), ("morph.countdown:hidden-pause", .webkit, .win),
  ("morph.countdown:strip", .chromium, .open), ("morph.countdown:strip", .webkit, .win),
  ("morph.panel:rest", .chromium, .trade), ("morph.panel:rest", .webkit, .trade),
  ("nav:logo-3d", .chromium, .open), ("nav:logo-3d", .webkit, .open),
  ("morph.mount:shift-dormant", .chromium, .trade), ("morph.mount:shift-dormant", .webkit, .trade),
  ("engine.events:quiet", .chromium, .open), ("engine.events:quiet", .webkit, .win)]
#guard becomesWin budgetB == [("morph.countdown:strip", .webkit)]
#guard leavesWin budgetB == [("hero:scene-pause", .webkit, .trade), ("morph.columns:idle-none", .chromium, .open),
  ("morph.columns:idle-none", .webkit, .open), ("morph.panel:rest", .webkit, .trade)]
#guard ((decidedVerdicts budgetB).zip (verdicts budgetB)).filterMap (fun ((f, e, v), (_, _, w)) =>
  if v == w then none else some (f, e)) == [("hero:scene-pause", .webkit), ("morph.mount:shift-dormant", .chromium),
    ("morph.mount:shift-dormant", .webkit)]

def predictRow (fp : Footprint) (r : Res) (e : Effect) : Json :=
  Json.mkObj ([("bound", match e.bound with | some (b, _) => toJson b | none => Json.null),
    ("decided", toJson (decided budgetB fp).name), ("engine", toJson fp.eng.name), ("flag", toJson fp.flag),
    ("kind", toJson "predict"), ("resolved", toJson (resolvedSign fp r).name),
    ("resource", toJson r.name), ("sign", toJson e.sign.name), ("src", toJson e.src),
    ("stage", toJson (Res.stage fp.eng r)),
    ("unit", toJson (match e.bound with | some (_, u) => u | none => r.unit)), ("verdict", toJson (verdict budgetB fp).name)] ++
    (if r = .gpuMem then [("budget", toJson budgetB), ("peak", match fp.peak with | some p => toJson p | none => Json.null)]
      else []))

def checkRow (o : Obs) : Json :=
  Json.mkObj [("arm", Json.mkObj [("hi", toJson o.arm.hi), ("lo", toJson o.arm.lo)]),
    ("base", Json.mkObj [("hi", toJson o.base.hi), ("lo", toJson o.base.lo)]),
    ("check", toJson (obsCheck o).name), ("engine", toJson o.eng.name), ("flag", toJson o.flag),
    ("kind", toJson "check"), ("measured", toJson (measuredSign o.base o.arm o.tol).name),
    ("predicted", toJson (predicted o).name), ("resource", toJson o.res.name), ("slow", toJson o.slow),
    ("source", toJson o.src), ("stage", toJson (Res.stage o.eng o.res)), ("tol", toJson o.tol),
    ("unit", toJson o.unit)]

def goldenRows (_ : Unit) : List Json :=
  (footprints ()).flatMap (fun fp => Res.all.filterMap fun r => (fp.effects.find? (·.1 == r)).map fun (_, e) =>
    predictRow fp r e) ++ observations.map checkRow

def goldenText (_ : Unit) : String := String.join ((goldenRows ()).map fun j => j.compress ++ "\n")

#guard (goldenRows ()).length == 18 * 10 + 70 + 21 + 8

end Fw.Engine.Resource.Flags

namespace Fw.Engine.Resource.Preset
open Fw.Engine.Resource Fw.Preset

def resourceOf (f : Flag) : List (Eng × Verdict × Verdict) :=
  [Eng.chromium, .webkit].filterMap fun e =>
    (Flags.footprint? f.key e).map fun fp => (e, verdict budgetB fp, Flags.decided budgetB fp)

def resourceTrade (f : Flag) : Bool := let rs := resourceOf f; !rs.isEmpty && rs.all (·.2.2 == .trade)

#guard resourceOf ⟨"morph.panel", "rest"⟩ == [(.chromium, .trade, .trade), (.webkit, .trade, .trade)]
#guard resourceOf ⟨"morph.countdown", "strip"⟩ == [(.chromium, .open, .open), (.webkit, .win, .win)]
#guard resourceOf ⟨"morph.columns", "idle-none"⟩ == [(.chromium, .open, .open), (.webkit, .open, .open)]
#guard resourceTrade ⟨"morph.panel", "rest"⟩ && !resourceTrade ⟨"morph.countdown", "strip"⟩ &&
  !resourceTrade ⟨"morph.columns", "idle-none"⟩ && !resourceTrade ⟨"hero.accent", "steps"⟩

#guard Gen.curated.all fun (f, x) => match x with | .resourceTrade => resourceTrade f | .hand _ => true

end Fw.Engine.Resource.Preset
