import Lean.Data.Json
import Fw.Engine.ResourceVerdict
import Fw.Parts.HeroExitOpt
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

/-! Resource footprints of nine flags on both engines, their verdicts, and their checks against the phone and CI
measurements. -/

namespace Fw.Engine.Resource.Flags

open Lean Fw.Engine Fw.Engine.Resource

/-- Passes of stage `s` summed over a run. -/
def sumP (ws : List Work) (s : Stage) : Nat := (ws.map (·.passes s)).sum

/-- Units of stage `s` summed over a run. -/
def sumU (ws : List Work) (s : Stage) : Nat := (ws.map (·.units s)).sum

/-- The sign of stage `s` from base run `os` to flag run `vs`. -/
def runSign (os vs : List Work) (s : Stage) : Sign := pairSign (sumP os s, sumU os s) (sumP vs s, sumU vs s)

/-- The sign of stage `s` over (flag, base) frame pairs. -/
def pairsSign (ps : List (Work × Work)) (s : Stage) : Sign := runSign (ps.map (·.2)) (ps.map (·.1)) s

/-- Two effects on one resource: one alone decides, equal signs agree, opposite moves are unknown. -/
def combine (a b : Sign) : Sign :=
  if a = .same then b else if b = .same then a else if a = b then a else .unknown

theorem combine_opposite : combine .down .up = .unknown ∧ combine .up .down = .unknown := by decide

theorem combine_same (s : Sign) : combine .same s = s ∧ combine s .same = s := by cases s <;> decide

#guard combine .down .down == .down && combine .unknown .same == .unknown && combine .up .unknown == .unknown

/-- An effect with no bound. -/
def ef (s : Sign) (src : String) : Effect := ⟨s, none, src⟩

/-- An effect with a bound `b` on the change, in unit `u`. -/
def efB (s : Sign) (b : Nat) (u src : String) : Effect := ⟨s, some (b, u), src⟩

/-- Style, layout, paint records and script from a stage-sign function, with one source. -/
def stageEffects (f : Stage → Sign) (src : String) : List (Res × Effect) :=
  [(.style, ef (f .style) src), (.layout, ef (f .layout) src), (.paintRec, ef (f .paint) src),
   (.script, ef (f .script) src)]

/-- The largest GPU peak over the phone base passes, in bytes (MEASURED). -/
def basePeak : Nat := 197145405

/-- Backing bytes the nav bar and the logo add while morphing: two layers of at most the 440 × 120 CSS-px nav box. -/
def navMorphBytes : Nat := gpuBytes 3 [⟨440, 120, true, true⟩, ⟨440, 120, true, true⟩]

/-- The strip's added clock backing on the WebKit Simulator, bounded by its whole backing (2.287 MB). -/
def stripBytes : Nat := 2287000

section Threaded
open Fw.Parts.HeroExitOpt

/-- `hero.exit:threaded` on Chromium. -/
def threadedCr : Footprint :=
  ⟨"hero.exit:threaded", .chromium,
    stageEffects (pairsSign crFrames) "HeroExitOpt.crFrames (CI lane), cr_lane_mixed" ++
    [(.event, ef .up "ReactRootOpt.records_orig: 2 records per animation event; wkAnims_length: N + 3 CSS animations"),
     (.repaint, ef (pairsSign crFrames .raster) "HeroExitOpt.crFrames raster stage"),
     (.layers, ef .up "ledger n=6: each animated consumer adds a composited layer"),
     (.composite, ef (pairsSign crFrames .comp) "cr_lane_mixed: V.passes comp = 1, O.passes comp = 0"),
     (.gpuMem, ef .up "one backing per added layer"),
     (.frames, ef (pairsSign crFrames .script) "cr_lane_mixed: script passes drop (no rAF)")],
    none⟩

/-- `hero.exit:threaded` on WebKit. -/
def threadedWk : Footprint :=
  ⟨"hero.exit:threaded", .webkit,
    [(.style, ef (pairsSign wkFrames .style) "HeroExitOpt.wkFrames, wk_var_exact"),
     (.layout, ef (pairsSign wkFrames .layout) "HeroExitOpt.wkFrames"),
     (.paintRec, ef (combine (pairsSign wkFrames .paint) .up) "wkFrames paint down; promote_tween re-attach paint up"),
     (.script, ef (pairsSign wkFrames .script) "HeroExitOpt.wkFrames"),
     (.event, ef .up "ReactRootOpt.records_orig: 2 records per animation event; N + 3 CSS animations"),
     (.repaint, ef (combine (pairsSign wkFrames .paint) .up) "tween_repaint: one full paint per promotion"),
     (.layers, ef .up "wk_all_comp: every animation threaded, its target composited"),
     (.composite, ef (pairsSign wkFrames .commit) "HeroExitOpt.wkFrames commit stage"),
     (.gpuMem, ef .up "promote_tween: resident grows by the promoted area"),
     (.frames, ef (pairsSign wkFrames .script) "wkFrames: FireAnimationFrame <o")],
    none⟩

end Threaded

section ScenePause
open Fw.Parts.HeroScenePause Fw.Parts.HeroCountdownOpt

/-- The hero layers composited before and after the pause on host `h`. -/
def heroLayers (h : Host) : Nat × Nat := (layers h false heroWcOnly, layers h true heroWcOnly)

theorem heroLayers_drop : heroLayers .chromium = (85, 0) ∧ heroLayers (.webkit .normal) = (85, 0) := by
  have c := hero_paused_drop .chromium rfl
  have w := hero_paused_drop (.webkit .normal) wk_normal_owns
  simp [heroLayers, c.1, c.2, w.1, w.2]

/-- The effects shared by both engines. -/
def sceneCommon (h : Host) : List (Res × Effect) :=
  [(.paintRec, ef .same "hero_wc_paint_same"), (.repaint, ef .same "hero_wc_paint_same"),
   (.layers, ef (signOf (heroLayers h).1 (heroLayers h).2) "hero_paused_drop: 85 -> 0 hero layers"),
   (.composite, ef .same "no composite pass added or removed"),
   (.gpuMem, ef .same "detached_zero: the dropped hero layers are outside coverage at the page end"),
   (.frames, ef .same "heroScene_eq_original: the rule sets an attribute from an IntersectionObserver (hero/scene.ts:23), no rAF")]

/-- `hero:scene-pause` on Chromium. -/
def scenePauseCr : Footprint :=
  ⟨"hero:scene-pause", .chromium,
    [(.style, ef .same "cr_realChrome_pause_eq: pausing changes no main-thread stage in real Chrome (cr_pause_style_units drops one style unit per paused animation in the CI lane only)"),
     (.layout, ef .same "cr_realChrome_pause_eq"), (.script, ef .same "cr_realChrome_pause_eq"),
     (.event, ef .unknown "no Chromium source line read for the iteration events of a paused animation")] ++
    sceneCommon .chromium, none⟩

/-- `hero:scene-pause` on WebKit; the peak is the arm's MEASURED phone maximum. -/
def scenePauseWk : Footprint :=
  ⟨"hero:scene-pause", .webkit,
    [(.style, ef .same "wk_pause_eq: pausing a compositor animation changes no web-process stage"),
     (.layout, ef .same "wk_pause_eq"), (.script, ef .same "wk_pause_eq"),
     (.event, ef .down "INFERRED: a paused animation's iteration does not change, so no animationiteration is enqueued (StyleOriginatedAnimation.cpp:340-345@862f17d)")] ++
    sceneCommon (.webkit .normal), some 211786247⟩

end ScenePause

section IdleNone
open Fw.Parts.MorphIdleNone Fw.Parts.MorphMountDormant

/-- Marquee chunk layers with the tracks animating and with `animation-name: none`. -/
def idleLayers : Nat × Nat :=
  ((layerize (fun s => decide (1 ≤ s)) ([backdrop] ++ tracksOn ++ above)).length,
    (layerize (fun s => decide (1 ≤ s)) ([backdrop] ++ tracksOff ++ above)).length)

theorem idleLayers_eq : idleLayers = (5, 1) := by
  simp only [idleLayers, tracks_layers_drop.1, tracks_layers_drop.2]

/-- The effects shared by both engines besides style and events. -/
def idleCommon : List (Res × Effect) :=
  [(.layout, ef .same "the tracks animate transform only (2.gBuqKVzi.css .track keyframes up/down, HiddenPause module doc)"),
   (.paintRec, ef .unknown "INFERRED: the dropped track layers paint into their host (tracks_layers_drop); the host's paint at panel opacity 0 is not modelled"),
   (.script, ef .unknown "the flag's MutationObserver callback per scene change (morph.columns/index.tsx:72-97) is not modelled"),
   (.repaint, ef .unknown "INFERRED: the dropped track layers paint into their host (tracks_layers_drop); the host's paint at panel opacity 0 is not modelled"),
   (.layers, ef (signOf idleLayers.1 idleLayers.2) "tracks_layers_drop: 5 -> 1 marquee chunk layers"),
   (.composite, ef .down "tracks_layers_drop: fewer layers to composite"),
   (.gpuMem, ef .down "tracks_layers_drop: the dropped track layers held backing"),
   (.frames, ef .same "the flag requests no frame: a MutationObserver only (morph.columns/index.tsx:72-97)")]

/-- `morph.columns:idle-none` on Chromium. -/
def idleNoneCr : Footprint :=
  ⟨"morph.columns:idle-none", .chromium,
    [(.style, ef .same "cr_realChrome_pause_eq: a compositor animation touches no main-thread stage in real Chrome; CI style 1832 vs 1833"),
     (.event, ef .unknown "INFERRED: iteration events are equal, since the base holds the tracks paused (varStep acts only while scenePaused); animation-name none (morph.module.css:14-16) re-creates the tracks, and each new animation enqueues animationstart (css_animations.cc:3660-3666@f842f52), a count the walk does not fix")] ++
    idleCommon, none⟩

/-- `morph.columns:idle-none` on WebKit; the peak is the arm's MEASURED phone maximum. -/
def idleNoneWk : Footprint :=
  ⟨"morph.columns:idle-none", .webkit,
    [(.style, ef .same "wk_pause_eq: a compositor animation costs the web process no stage"),
     (.event, ef .unknown "INFERRED: iteration events are equal, since the base holds the tracks paused (varStep acts only while scenePaused); animation-name none (morph.module.css:14-16) cancels and re-creates the tracks, which enqueues animationcancel and animationstart (StyleOriginatedAnimation.cpp:333-334,353-354@862f17d), a count the walk does not fix")] ++
    idleCommon, some 173708059⟩

end IdleNone

section HiddenPause
open Fw.Parts.HiddenPause

open Fw.Engine.Chromium in
/-- The countdown pairs of `crPairs` (gated, original): 1 and 6 springing digits in every layer state. The flag gates
only the face writes (`installFaceGate`, morph.countdown/index.tsx:59-64), so the marquee pairs do not apply. -/
def hiddenCrPairs : List (Work × Work) :=
  [1, 6].flatMap fun d => [LayerState.none, .layer, .own].map fun l =>
    let f := cdFrame (CrProp.css .transform) d l; (frameWork chromium (skipWrites f), frameWork chromium f)

open Fw.Engine.WebKit in
/-- The countdown pairs of `wkPairs`, as `hiddenCrPairs` with the WebKit table. -/
def hiddenWkPairs : List (Work × Work) :=
  [1, 6].flatMap fun d => [LayerState.none, .layer, .own].map fun l =>
    let f := cdFrame WkProp.transform d l; (frameWork webkit (skipWrites f), frameWork webkit f)

/-- The effects shared by both engines besides the stage and repaint signs. -/
def hiddenCommon : List (Res × Effect) :=
  [(.event, ef .same "the flag gates JS face writes only (morph.countdown/index.tsx:59-64); the clock runs no CSS animation"),
   (.layers, ef .same "the gate changes no layer reason"), (.composite, ef .same "the gate changes no layer"),
   (.gpuMem, ef .same "the gate changes no layer"), (.frames, ef .same "skipWrites keeps the callbacks")]

/-- `morph.countdown:hidden-pause` on Chromium. -/
def hiddenCr (_ : Unit) : Footprint :=
  ⟨"morph.countdown:hidden-pause", .chromium,
    stageEffects (pairsSign hiddenCrPairs) "hiddenCrPairs, cr_countdown_style" ++
    (.repaint, ef (pairsSign hiddenCrPairs .raster) "hiddenCrPairs raster stage") :: hiddenCommon, none⟩

/-- `morph.countdown:hidden-pause` on WebKit; the peak is the arm's MEASURED phone maximum. -/
def hiddenWk (_ : Unit) : Footprint :=
  ⟨"morph.countdown:hidden-pause", .webkit,
    stageEffects (pairsSign hiddenWkPairs) "hiddenWkPairs, wk_countdown_style" ++
    (.repaint, ef (pairsSign hiddenWkPairs .paint) "hiddenWkPairs paint stage") :: hiddenCommon, some 168397197⟩

end HiddenPause

section Strip
open Fw.Parts.HeroCountdownOpt Fw.Parts.MorphCountdownStrip

/-- One frame writing the eight faces of every digit, and one writing the eight strips. -/
def stripRuns {P M : Type} (E : Engine P M) (p : P) : List Work × List Work :=
  ([frameWork E (withWrites ⟨0, 0, 0, 0, [], 0⟩ (faceWrites p .own (List.range 8)))],
    [frameWork E (withWrites ⟨0, 0, 0, 0, [], 0⟩ (stripWrites p .own (List.range 8)))])

/-- Clock layers on host `h` with faces and with strips, eight digits. -/
def clockLayerPair (h : Host) : Nat × Nat := ((facesResident h true 8 1).layers, (stripResident h true 8 1).layers)

theorem clockLayerPair_eq : clockLayerPair .chromium = (80, 8) ∧ clockLayerPair (.webkit .normal) = (80, 8) := by
  have c := hero_layers .chromium true 1 rfl
  have w := hero_layers (.webkit .normal) true 1 Fw.Parts.HeroScenePause.wk_normal_owns
  simp [clockLayerPair, c.1, c.2.1, w.1, w.2.1]

/-- The strip writes one inline transform per digit from the same spring driver: no CSS animation, no new frame. -/
def stripDriverSrc : String := "the same spring driver writes one inline transform per digit (hero.countdown/driver.ts:61-70)"

/-- `morph.countdown:strip` on Chromium. -/
def stripCr : Footprint :=
  let r := stripRuns Chromium.chromium (Chromium.CrProp.css .transform)
  ⟨"morph.countdown:strip", .chromium,
    stageEffects (runSign r.1 r.2) "strip_units: 9 fewer units per digit" ++
    [(.event, ef .same stripDriverSrc),
     (.repaint, ef .unknown "Chromium tile retention off-screen not modelled"),
     (.layers, efB (signOf (clockLayerPair .chromium).1 (clockLayerPair .chromium).2) 72 "layers per census state"
        "hero_layers: 80 -> 8 clock layers"),
     (.composite, ef .down "hero_layers: fewer layers to composite"),
     (.gpuMem, ef .up "strip_backing_gt: 10na -> 12na"), (.frames, ef .same stripDriverSrc)],
    none⟩

/-- `morph.countdown:strip` on WebKit; the peak is the MEASURED base peak plus the bound on the strip's backing. -/
def stripWk : Footprint :=
  let r := stripRuns WebKit.webkit WebKit.WkProp.transform
  ⟨"morph.countdown:strip", .webkit,
    stageEffects (runSign r.1 r.2) "strip_units: 9 fewer units per digit" ++
    [(.event, ef .same stripDriverSrc),
     (.repaint, ef .down "face_reattach vs strip_no_reattach: faces re-attach, strips stay attached"),
     (.layers, efB (signOf (clockLayerPair (.webkit .normal)).1 (clockLayerPair (.webkit .normal)).2) 72
        "layers per census state" "hero_layers, layers_80_to_16: 80 -> 8 clock layers"),
     (.composite, ef .down "hero_layers: fewer layers to composite"),
     (.gpuMem, efB .up stripBytes "bytes of hero clock backing"
        "strip_backing_gt: 10na -> 12na; bound the Simulator's 2.287 MB clock backing"),
     (.frames, ef .same stripDriverSrc)],
    some (basePeak + stripBytes)⟩

end Strip

section PanelRest
open Fw.Parts.MorphPanelOpt

/-- The flag changes only the filter value the per-frame fade writes at rest: no event, no new frame. -/
def panelRestSrc : String := "filterO_rest, filterV_rest: only the rest filter value changes"

/-- `morph.panel:rest` on Chromium. -/
def panelCr : Footprint :=
  ⟨"morph.panel:rest", .chromium,
    stageEffects (runSign crO crV) "MorphPanelOpt.crO/crV, cr_toggle_not_le" ++
    [(.event, ef .same panelRestSrc), (.repaint, ef (runSign crO crV .raster) "MorphPanelOpt.crO/crV raster"),
     (.layers, ef .same "Chromium keeps no layer for blur(0)"), (.composite, ef (runSign crO crV .comp) "crO/crV comp"),
     (.gpuMem, ef .same "Chromium keeps no layer for blur(0)"), (.frames, ef .same panelRestSrc)],
    none⟩

/-- `morph.panel:rest` on WebKit. -/
def panelWk : Footprint :=
  ⟨"morph.panel:rest", .webkit,
    stageEffects (runSign wkO wkV) "MorphPanelOpt.wkO/wkV" ++
    [(.event, ef .same panelRestSrc),
     (.repaint, ef .unknown "INFERRED: a none->blur toggle may create the group layer and paint it in full; no theorem links filterToggle to a re-attach paint"),
     (.layers, efB .down 1 "layers per census state" "wk_rest_layers: one layer less at rest"),
     (.composite, ef (runSign wkO wkV .comp) "wkO/wkV comp"),
     (.gpuMem, ef .down "wkResident: the group layer's backing is freed at rest"), (.frames, ef .same panelRestSrc)],
    none⟩

end PanelRest

section Logo
open Fw.Parts.NavBarFixedWork

/-- Chromium: the logo moved by `left` and by a composited transform. -/
def logoCrRuns : List Work × List Work :=
  ([frameWork Chromium.chromium ⟨0, 0, 0, 0, [⟨1, .css .left, .none⟩], 0⟩],
    [frameWork Chromium.chromium ⟨0, 0, 0, 0, [⟨1, .css .transform, .own⟩], 0⟩])

/-- WebKit: the logo and the bar moved by inset, and by transform under the normal policy. -/
def logoWkRuns : List Work × List Work :=
  ([frameWork WebKit.webkit logoLeftFrame, frameWork WebKit.webkit barInsetFrame],
    [frameWork WebKit.webkit (logo3dFrame .normal), frameWork WebKit.webkit (barTranslateFrame .normal)])

/-- The effects shared by both engines besides the stage signs. -/
def logoCommon : List (Res × Effect) :=
  [(.event, ef .unknown "the logo moves by transform instead of translate and scale (nav/box.module.css:53-57) while the nav keeps the original transition lists (box.module.css:4); transition events not modelled"),
   (.repaint, ef .down "bar_resizePaint_zero vs bar_orig_resizes: the fixed bar never resizes"),
   (.layers, ef .up "layer_budget: mask, bar and logo while morphing; none at rest (box.module.css .is-morphing)"),
   (.composite, ef .up "layer_budget: three more layers while morphing"),
   (.gpuMem, ef .up "layer_budget: bar and logo backing while morphing; the mask holds none"),
   (.frames, ef .same "a CSS-only change (nav/box.module.css:53-57): no rAF")]

/-- `nav:logo-3d` on Chromium. -/
def logoCr : Footprint :=
  ⟨"nav:logo-3d", .chromium, stageEffects (runSign logoCrRuns.1 logoCrRuns.2) "Chromium stage rules: left vs transform" ++
    logoCommon, none⟩

/-- `nav:logo-3d` on WebKit; the peak is the MEASURED base peak plus the modelled nav backing. -/
def logoWk : Footprint :=
  ⟨"nav:logo-3d", .webkit,
    stageEffects (runSign logoWkRuns.1 logoWkRuns.2) "logo3d_layout_normal, bar_layout_normal" ++ logoCommon,
    some (basePeak + navMorphBytes)⟩

end Logo

section ShiftDormant
open Fw.Parts.MorphMountOpt

/-- The effects shared by both engines besides the stage signs. -/
def dormantCommon : List (Res × Effect) :=
  [(.event, ef .same "the dormant panel runs no animation before the original trigger (dormant_iff)"),
   (.repaint, ef .same "visSame_dormant: same pixels"), (.layers, ef .same "census_dormant_eq"),
   (.composite, ef .same "layers_dormant_eq"), (.gpuMem, ef .same "census_dormant_eq"),
   (.frames, ef .same "no countdown driver before the trigger")]

/-- `morph.mount:shift-dormant` on Chromium. -/
def dormantCr : Footprint :=
  ⟨"morph.mount:shift-dormant", .chromium,
    stageEffects (runSign crO crV) "MorphMountOpt.crO/crV: the mount shifts, totals equal" ++ dormantCommon, none⟩

/-- `morph.mount:shift-dormant` on WebKit; the peak is the arm's MEASURED phone maximum. -/
def dormantWk : Footprint :=
  ⟨"morph.mount:shift-dormant", .webkit,
    stageEffects (runSign wkO wkV) "MorphMountOpt.wkO/wkV: the mount shifts, totals equal" ++ dormantCommon,
    some 191681597⟩

end ShiftDormant

section Quiet
open Fw.Parts.ReactRootOpt

/-- EventDispatch records of one quiet event at the original root and at the quiet root. -/
def quietRecords : Nat × Nat := (records regs "animationend", records quietRegs "animationend")

theorem quietRecords_eq : quietRecords = (2, 0) := by
  have o := records_orig "animationend" (by decide)
  have q := records_quiet "animationend" (by decide)
  simp [quietRecords, o, q]

/-- The flag drops root listener registrations only. -/
def quietSrc : String := "quietRegs: the flag only drops root listener registrations"

/-- The effects shared by both engines besides events and script. -/
def quietCommon : List (Res × Effect) :=
  [(.style, ef .same quietSrc), (.layout, ef .same quietSrc), (.paintRec, ef .same quietSrc),
   (.repaint, ef .same quietSrc), (.layers, ef .same quietSrc), (.composite, ef .same quietSrc),
   (.gpuMem, ef .same quietSrc), (.frames, ef .same quietSrc)]

/-- `engine.events:quiet` on Chromium. -/
def quietCr : Footprint :=
  ⟨"engine.events:quiet", .chromium,
    [(.event, ef .unknown "css_animations.cc:3610@f842f52 creates an animation event only while the document has a listener of its type; the page's other listeners are not enumerated"),
     (.script, ef .unknown "Chromium listener call records not read from source")] ++ quietCommon, none⟩

/-- `engine.events:quiet` on WebKit; the peak is the arm's MEASURED phone maximum. -/
def quietWk : Footprint :=
  ⟨"engine.events:quiet", .webkit,
    [(.event, ef (signOf quietRecords.1 quietRecords.2) "records_orig, records_quiet: 2 -> 0 records per quiet event"),
     (.script, ef .down "records_quiet: no root listener call (EventTarget.cpp:313-357@862f17d)")] ++ quietCommon,
    some 191681597⟩

end Quiet

/-- The eighteen footprints. -/
def footprints (_ : Unit) : List Footprint :=
  [threadedCr, threadedWk, scenePauseCr, scenePauseWk, idleNoneCr, idleNoneWk, hiddenCr (), hiddenWk (), stripCr, stripWk,
   panelCr, panelWk, logoCr, logoWk, dormantCr, dormantWk, quietCr, quietWk]

/-- The footprint of a flag on an engine. -/
def footprint? (flag : String) (e : Eng) : Option Footprint := (footprints ()).find? fun f => f.flag == flag && f.eng == e

/-- The verdict of every footprint at budget `B`. -/
def verdicts (B : Nat) : List (String × Eng × Verdict) := (footprints ()).map fun f => (f.flag, f.eng, verdict B f)

#guard (footprints ()).length == 18
#guard (footprints ()).all fun f => Res.all.all fun r => (f.effects.filter (·.1 == r)).length == 1
#guard verdicts budgetB == [
  ("hero.exit:threaded", .chromium, .trade), ("hero.exit:threaded", .webkit, .trade),
  ("hero:scene-pause", .chromium, .open), ("hero:scene-pause", .webkit, .win),
  ("morph.columns:idle-none", .chromium, .open), ("morph.columns:idle-none", .webkit, .open),
  ("morph.countdown:hidden-pause", .chromium, .win), ("morph.countdown:hidden-pause", .webkit, .win),
  ("morph.countdown:strip", .chromium, .open), ("morph.countdown:strip", .webkit, .win),
  ("morph.panel:rest", .chromium, .trade), ("morph.panel:rest", .webkit, .open),
  ("nav:logo-3d", .chromium, .open), ("nav:logo-3d", .webkit, .open),
  ("morph.mount:shift-dormant", .chromium, .neutral), ("morph.mount:shift-dormant", .webkit, .neutral),
  ("engine.events:quiet", .chromium, .open), ("engine.events:quiet", .webkit, .win)]

/-- **Strip on WebKit: the Core claim is a trade, the resource verdict a win.** The strip holds more backing than the
faces, so `claim` calls it a trade; GPU memory is not gated, so the verdict is a win within `B`. -/
theorem strip_claim_trade_verdict_win (a : Nat) (ha : 0 < a) :
    claim (.ok .dominates) (Fw.Parts.HeroCountdownOpt.stripResident (.webkit .normal) true 8 a)
        (Fw.Parts.HeroCountdownOpt.facesResident (.webkit .normal) true 8 a) = .trade ∧
      stripWk.sign .gpuMem = .up ∧ stripWk.peak = some (basePeak + stripBytes) ∧ basePeak + stripBytes ≤ budgetB :=
  ⟨(Fw.Parts.HeroCountdownOpt.strip_label_fullLayer _ true 8 a Fw.Parts.HeroScenePause.wk_normal_owns (by decide) ha).2,
    rfl, rfl, by decide⟩

theorem navMorphBytes_eq : navMorphBytes = 3801600 := by decide

/-- A phone-data source: the end-of-session counts, n = 3 passes per arm. -/
def phoneSrc : String := "phone 2026-10-25 (results/phone/2026-10-25-end-counts)"

/-- One measured resource: its unit, base and arm ranges over passes, the tolerance, and whether the arm's walk was
slow. -/
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

/-- The unit of a phone resource: census resources are summed over the three census states y >= 3000 (3000, 4500, max). -/
def phoneUnit : Res → String
  | .gpuMem => "KiB summed over the three census states y >= 3000"
  | .layers => "layers summed over the three census states y >= 3000"
  | .repaint => "thousand root-view CSS px² summed over a walk" | .frames => "frames per run"
  | _ => "records per run"

/-- Phone base ranges over the two base arms, in `phoneUnit`. -/
def phoneBase : Res → Range
  | .style => ⟨646, 651⟩ | .layout => ⟨609, 632⟩ | .paintRec => ⟨1569, 1608⟩ | .script => ⟨1436, 1558⟩
  | .event => ⟨902, 1024⟩ | .repaint => ⟨77464, 82927⟩ | .layers => ⟨401, 401⟩ | .composite => ⟨213, 213⟩
  | .gpuMem => ⟨384778, 412853⟩ | .frames => ⟨693, 696⟩

/-- The slowest phone base walk in ms. -/
def phoneBaseWallHi : Nat := 4077

/-- One phone arm: flag, fastest walk in ms, and its ranges in `Res.all` order. -/
def phoneArm (flag : String) (wallLo : Nat) (rs : List Range) : List Obs :=
  (Res.all.zip rs).map fun (r, a) =>
    ⟨flag, .webkit, phoneSrc, r, phoneUnit r, phoneBase r, a, 0, slowWalk phoneBaseWallHi wallLo⟩

/-- The phone observations of the seven arms that finished. -/
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

/-- The CI observations cited in the ledger rows (run ids in `src`). -/
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
      .style, "resolved elements relative to faithful", ⟨0, 0⟩, ⟨200, 200⟩, 0, false⟩]

/-- Every observation. -/
def observations : List Obs := phoneObs ++ ciObs

/-- The predicted sign for an observation. -/
def predicted (o : Obs) : Sign := ((footprint? o.flag o.eng).map (·.sign o.res)).getD .unknown

/-- The check of an observation. -/
def obsCheck (o : Obs) : Check := check o.res o.slow (predicted o) (measuredSign o.base o.arm o.tol)

/-- The observations whose check is `c`. -/
def withCheck (c : Check) : List Obs := observations.filter (obsCheck · == c)

/-- Disagreements and unpredicted moves with their mechanism, keyed by (flag, engine, resource). -/
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
     "OPEN: the animationcancel and animationstart of the re-created tracks are not counted; measured inside the pass spread")]

/-- The ledger labels (chromium, webkit) before this model. -/
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

/-- Ledger trade rows the resource verdict turns into wins. -/
def becomesWin (B : Nat) : List (String × Eng) :=
  (ledgerLabels.filter fun (f, e, l) => l == "trade" && ((footprint? f e).map (verdict B ·)) == some .win).map
    fun (f, e, _) => (f, e)

/-- Ledger win rows the resource verdict no longer calls a win. -/
def leavesWin (B : Nat) : List (String × Eng × Verdict) :=
  (ledgerLabels.filter fun (f, e, l) => l == "win" && ((footprint? f e).map (verdict B ·)) != some .win).filterMap
    fun (f, e, _) => (footprint? f e).map fun fp => (f, e, verdict B fp)

#guard becomesWin budgetB == [("morph.countdown:strip", .webkit)]
#guard leavesWin budgetB == [("morph.columns:idle-none", .chromium, .open), ("morph.columns:idle-none", .webkit, .open),
  ("morph.panel:rest", .webkit, .open)]
#guard [Check.agree, .unresolved, .confounded, .disagree, .unpredicted].map (withCheck · |>.length) == [43, 5, 24, 5, 6]
#guard (withCheck .unpredicted).map (fun o => (o.flag, o.eng.name, o.res.name)) == [
  ("hero.exit:threaded", "webkit", "paintRecords"), ("hero.exit:threaded", "webkit", "repaintArea"),
  ("morph.columns:idle-none", "webkit", "paintRecords"), ("morph.columns:idle-none", "webkit", "script"),
  ("morph.columns:idle-none", "webkit", "eventDispatch"), ("morph.columns:idle-none", "webkit", "repaintArea")]
#guard (withCheck .disagree).map (fun o => (o.flag, o.eng.name, o.res.name)) == [
  ("morph.mount:shift-dormant", "webkit", "script"),
  ("morph.mount:shift-dormant", "webkit", "eventDispatch"), ("engine.events:quiet", "webkit", "layers"),
  ("morph.mount:shift-dormant", "chromium", "layout"), ("morph.mount:shift-dormant", "chromium", "style")]
#guard (withCheck .disagree ++ withCheck .unpredicted).all fun o =>
  mechanisms.any fun (f, e, r, _) => f == o.flag && e == o.eng && r == o.res

/-- The largest change the base and arm ranges allow. -/
def maxChange (b a : Range) : Nat := max (a.hi - b.lo) (b.hi - a.lo)

/-- The observations of resource `r` of footprint `fp`. -/
def obsOf (fp : Footprint) (r : Res) : List Obs :=
  observations.filter fun o => o.flag == fp.flag && o.eng == fp.eng && o.res == r

/-- Does every observation of a bounded effect share the bound's unit and change by at most the bound? -/
def boundHolds (fp : Footprint) (r : Res) (e : Effect) : Bool :=
  match e.bound with
  | none => true
  | some (b, u) => (obsOf fp r).all fun o => o.unit == u && decide (maxChange o.base o.arm ≤ b)

/-- The bounded effects as (flag, engine, resource, bound, unit, observations of it). -/
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

/-- One golden row of a predicted effect, with the footprint's verdict at `budgetB`. -/
def predictRow (fp : Footprint) (r : Res) (e : Effect) : Json :=
  Json.mkObj ([("bound", match e.bound with | some (b, _) => toJson b | none => Json.null),
    ("engine", toJson fp.eng.name), ("flag", toJson fp.flag), ("kind", toJson "predict"),
    ("resource", toJson r.name), ("sign", toJson e.sign.name), ("src", toJson e.src),
    ("stage", toJson (Res.stage fp.eng r)),
    ("unit", toJson (match e.bound with | some (_, u) => u | none => r.unit)), ("verdict", toJson (verdict budgetB fp).name)] ++
    (if r = .gpuMem then [("budget", toJson budgetB), ("peak", match fp.peak with | some p => toJson p | none => Json.null)]
      else []))

/-- One golden row of a check. -/
def checkRow (o : Obs) : Json :=
  Json.mkObj [("arm", Json.mkObj [("hi", toJson o.arm.hi), ("lo", toJson o.arm.lo)]),
    ("base", Json.mkObj [("hi", toJson o.base.hi), ("lo", toJson o.base.lo)]),
    ("check", toJson (obsCheck o).name), ("engine", toJson o.eng.name), ("flag", toJson o.flag),
    ("kind", toJson "check"), ("measured", toJson (measuredSign o.base o.arm o.tol).name),
    ("predicted", toJson (predicted o).name), ("resource", toJson o.res.name), ("slow", toJson o.slow),
    ("source", toJson o.src), ("stage", toJson (Res.stage o.eng o.res)), ("tol", toJson o.tol),
    ("unit", toJson o.unit)]

/-- The golden rows: every predicted effect, then every check. -/
def goldenRows (_ : Unit) : List Json :=
  (footprints ()).flatMap (fun fp => Res.all.filterMap fun r => (fp.effects.find? (·.1 == r)).map fun (_, e) =>
    predictRow fp r e) ++ observations.map checkRow

/-- The golden text (`packages/contracts/golden/engine/resource.jsonl`). -/
def goldenText (_ : Unit) : String := String.join ((goldenRows ()).map fun j => j.compress ++ "\n")

#guard (goldenRows ()).length == 18 * 10 + 70 + 13

end Fw.Engine.Resource.Flags
