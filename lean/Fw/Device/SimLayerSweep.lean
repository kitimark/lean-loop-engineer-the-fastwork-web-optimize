import Fw.Device.SimEndCut

/-! # sim-layer-sweep: does a completely accelerated sweep loop remove the last per-frame style recalc on the iOS Simulator -/
namespace Fw.Device.SimLayerSweep

open Fw.Device.SimEndCut Fw.Device.SimEndFloor Fw.Device.EndWktr
open Fw.Device.SimFloorAttrib (Tier EdgeV tier overallEdge overallTier)

/-! ## Tick demand of one source

WebKit source @862f17d, Source/WebCore:
* css/CSSProperties.json:12105-12125 (`transform`) and :7107-7120 (`opacity`) carry `animation-wrapper-acceleration: always`;
  `background-position` (:2334-2350) carries none.
* animation/KeyframeEffect.cpp:1736-1768 `computeAcceleratedPropertiesState` gives None, Some or All over the keyframe properties.
* animation/KeyframeEffect.cpp:2724-2745 `ticksContinuouslyWhileActive`: false for no properties; false for no renderer; for a completely accelerated
  and running-accelerated effect false on the Core Animation path and, under THREADED_ANIMATIONS with a representation, `!representation ||
  !disallowedProperties.isEmpty()`; true otherwise.
* animation/AnimationEffect.cpp:391-401 `timeToNextTick` in the active phase: `endTime - localTime` unless the effect ticks continuously, then 0.
* animation/KeyframeEffect.cpp:2747-2763: a CSSAnimation with a CSSAnimation event listener on the document, not ticking continuously, asks for one tick
  per iteration.
* animation/DocumentTimeline.cpp:371-388 `scheduleNextTick` schedules an animation resolution when a source's `timeToNextTick` is below the animation interval. -/

def accelerated (p : String) : Bool := p == "transform" || p == "opacity"

inductive Share where
  | zero
  | part
  | full
  deriving DecidableEq, Repr

def shareOf (props : List String) : Share :=
  if props.isEmpty then .zero else if props.all accelerated then .full else if props.any accelerated then .part else .zero

theorem shareOf_full_iff (ps : List String) : shareOf ps = .full ↔ ps ≠ [] ∧ ps.all accelerated = true := by
  cases ps with
  | nil => simp [shareOf]
  | cons p t =>
    simp only [shareOf, List.isEmpty_cons, Bool.false_eq_true, ↓reduceIte, ne_eq, reduceCtorEq, not_false_eq_true, true_and]
    by_cases h : (p :: t).all accelerated = true
    · simp [h]
    · simp only [h, Bool.false_eq_true, ↓reduceIte, iff_false]
      split <;> simp

structure Effect where
  props : List String
  rendered : Bool
  running : Bool
  rep : Option Bool
  css : Bool
  deriving DecidableEq, Repr

def Effect.ticks (e : Effect) : Bool :=
  if e.props.isEmpty then false
  else if !e.rendered then false
  else if shareOf e.props == .full && e.running then
    match e.rep with
    | none => false
    | some d => d
  else true

inductive Demand where
  | everyFrame
  | perIteration
  | atEnd
  deriving DecidableEq, Repr

def Demand.name : Demand → String
  | .everyFrame => "everyFrame" | .perIteration => "perIteration" | .atEnd => "atEnd"

def Effect.demand (e : Effect) (listeners : Bool) : Demand :=
  if e.ticks then .everyFrame else if listeners && e.css then .perIteration else .atEnd

theorem ticks_empty (e : Effect) (h : e.props = []) : e.ticks = false := by simp [Effect.ticks, h]

theorem ticks_unrendered (e : Effect) (h : e.rendered = false) : e.ticks = false := by
  unfold Effect.ticks
  by_cases h0 : e.props.isEmpty = true <;> simp [h0, h]

theorem ticks_not_full (e : Effect) (h0 : e.props ≠ []) (h1 : e.rendered = true) (h : shareOf e.props ≠ .full) : e.ticks = true := by
  have hne : e.props.isEmpty = false := by simpa [List.isEmpty_iff] using h0
  have hf : (shareOf e.props == Share.full) = false := by simpa using h
  simp [Effect.ticks, hne, h1, hf]

theorem ticks_not_running (e : Effect) (h0 : e.props ≠ []) (h1 : e.rendered = true) (h : e.running = false) : e.ticks = true := by
  have hne : e.props.isEmpty = false := by simpa [List.isEmpty_iff] using h0
  simp [Effect.ticks, hne, h1, h]

theorem ticks_core (e : Effect) (hf : shareOf e.props = .full) (hr : e.running = true) (h : e.rep = none) : e.ticks = false := by
  obtain ⟨hne, _⟩ := (shareOf_full_iff e.props).1 hf
  have hne' : e.props.isEmpty = false := by simpa [List.isEmpty_iff] using hne
  unfold Effect.ticks
  by_cases hq : e.rendered = true <;> simp [hne', hq, hf, hr, h]

theorem ticks_rep_iff (e : Effect) (d : Bool) (h : e.rep = some d) (hf : shareOf e.props = .full) (hr : e.running = true)
    (hq : e.rendered = true) : e.ticks = d := by
  obtain ⟨hne, _⟩ := (shareOf_full_iff e.props).1 hf
  have hne' : e.props.isEmpty = false := by simpa [List.isEmpty_iff] using hne
  simp [Effect.ticks, hne', hq, hf, hr, h]

theorem accelerated_loop_adds_no_frame_tick (e : Effect) (hne : e.props ≠ []) (ha : e.props.all accelerated = true)
    (hr : e.running = true) (hrep : e.rep = none ∨ e.rep = some false) (l : Bool) :
    e.ticks = false ∧ e.demand l ≠ .everyFrame ∧ (l = false → e.demand l = .atEnd) := by
  have hf : shareOf e.props = .full := (shareOf_full_iff e.props).2 ⟨hne, ha⟩
  have ht : e.ticks = false := by
    rcases hrep with h | h
    · exact ticks_core e hf hr h
    · cases hq : e.rendered
      · exact ticks_unrendered e hq
      · exact ticks_rep_iff e false h hf hr hq
  refine ⟨ht, ?_, ?_⟩
  · simp [Effect.demand, ht]
    split <;> simp
  · intro hl
    simp [Effect.demand, ht, hl]

theorem demand_everyFrame_iff (e : Effect) (l : Bool) : e.demand l = .everyFrame ↔ e.ticks = true := by
  unfold Effect.demand
  cases h : e.ticks <;> simp
  split <;> simp

theorem demand_listener (e : Effect) (h : e.ticks = false) (hc : e.css = true) : e.demand true = .perIteration := by
  simp [Effect.demand, h, hc]

theorem demand_no_listener (e : Effect) (h : e.ticks = false) : e.demand false = .atEnd := by simp [Effect.demand, h]

def sweepDocProps : List String := ["background-position"]

def sweepLayerProps : List String := ["transform"]

theorem sweepDoc_ticks (rep : Option Bool) (running : Bool) : (Effect.mk sweepDocProps true running rep true).ticks = true := by
  cases rep with
  | none => cases running <;> decide
  | some d => cases d <;> cases running <;> decide

theorem sweepLayer_core_no_tick : (Effect.mk sweepLayerProps true true none true).ticks = false := by decide

theorem sweepLayer_rep_no_tick : (Effect.mk sweepLayerProps true true (some false) true).ticks = false := by decide

theorem sweepLayer_rep_disallowed_ticks : (Effect.mk sweepLayerProps true true (some true) true).ticks = true := by decide

theorem sweepLayer_not_running_ticks : (Effect.mk sweepLayerProps true false none true).ticks = true := by decide

theorem sweepLayer_no_listener_at_end : (Effect.mk sweepLayerProps true true none true).demand false = .atEnd := by decide

theorem sweepLayer_listener_per_iteration : (Effect.mk sweepLayerProps true true none true).demand true = .perIteration := by decide

def iterTicks (windowMs iterMs : Nat) : Nat := windowMs / iterMs + 1

def iterRate (loops windowMs iterMs frames : Nat) : Nat := loops * iterTicks windowMs iterMs * 100 / frames

def sweepIterMs : Nat := 4000

def sweepLoopCount : Nat := 5

def windowMsMax : Nat := 24000

theorem iterRate_le (w : Nat) (h : w ≤ windowMsMax) : iterRate sweepLoopCount w sweepIterMs winRaf ≤ 9 := by
  simp only [iterRate, iterTicks, sweepLoopCount, sweepIterMs, winRaf, windowMsMax] at *
  omega

theorem iterRate_in_band (w : Nat) (h : w ≤ windowMsMax) : 100 + iterRate sweepLoopCount w sweepIterMs winRaf ≤ 100 + band := by
  have := iterRate_le w h
  simp only [band] at *
  omega

/-! ## The page model -/

def layerPrefix : String := "sweep-module_sweepLayerX"

def _root_.Fw.Device.SimEndCut.Census.layerRunning (c : Census) : Nat := (c.running.filter fun n => hasPrefix layerPrefix n).length

def _root_.Fw.Device.SimEndCut.Census.foreignRunning (c : Census) : Nat := c.running.length - c.layerRunning

def _root_.Fw.Device.SimEndCut.Census.sweepDocLoops (c : Census) : Nat := (c.running ++ c.paused).filter (fun n => kindOf n == .sweep) |>.length

def _root_.Fw.Device.SimEndCut.Census.layerOnly (c : Census) : Bool := c.viewDriven == 0 && c.scrollDriven == 0 && c.foreignRunning == 0

theorem layerOnly_iff (c : Census) : c.layerOnly = true ↔ c.viewDriven = 0 ∧ c.scrollDriven = 0 ∧ c.foreignRunning = 0 := by
  simp [Census.layerOnly, and_assoc]

theorem foreign_zero_of_running_layer (c : Census) (h : c.running.length = c.layerRunning) : c.foreignRunning = 0 := by
  simp [Census.foreignRunning, h]

structure LayerRead where
  loops : Nat
  props : List String
  reason : Option Bool
  deriving DecidableEq, Repr

def LayerRead.effect (r : LayerRead) (rep : Option Bool) : Effect := ⟨r.props, true, r.reason != some false, rep, true⟩

def LayerRead.evidence (r : LayerRead) : String :=
  if r.loops == 0 then "noLoops"
  else if shareOf r.props != .full then "notAccelerated"
  else match r.reason with
    | some false => "contradicted"
    | some true => "inspector"
    | none => "inferred"

theorem evidence_noLoops (r : LayerRead) (h : r.loops = 0) : r.evidence = "noLoops" := by simp [LayerRead.evidence, h]

theorem evidence_inferred (r : LayerRead) (h0 : r.loops ≠ 0) (h1 : shareOf r.props = .full) (h : r.reason = none) :
    r.evidence = "inferred" := by simp [LayerRead.evidence, h0, h1, h]

theorem evidence_inspector (r : LayerRead) (h0 : r.loops ≠ 0) (h1 : shareOf r.props = .full) (h : r.reason = some true) :
    r.evidence = "inspector" := by simp [LayerRead.evidence, h0, h1, h]

def predTierL (r : Option LayerRead) (rep : Option Bool) (c : Census) : Tier :=
  match r with
  | none => .two
  | some r => if !c.layerOnly then .two else if 0 < c.layerRunning ∧ (r.effect rep).ticks = true then .two else .one

theorem predTierL_foreign (r : Option LayerRead) (rep : Option Bool) (c : Census) (h : c.layerOnly = false) :
    predTierL r rep c = .two := by
  cases r <;> simp [predTierL, h]

theorem predTierL_accelerated (r : LayerRead) (rep : Option Bool) (c : Census) (h : c.layerOnly = true) (hp : r.props ≠ [])
    (ha : r.props.all accelerated = true) (hrun : r.reason ≠ some false) (hrep : rep = none ∨ rep = some false) :
    predTierL (some r) rep c = .one := by
  have hr : (r.effect rep).running = true := by simp [LayerRead.effect, hrun]
  have := (accelerated_loop_adds_no_frame_tick (r.effect rep) hp ha hr (by simpa [LayerRead.effect] using hrep) false).1
  simp [predTierL, h, this]

theorem predTierL_unaccelerated (r : LayerRead) (rep : Option Bool) (c : Census) (h : c.layerOnly = true) (hn : 0 < c.layerRunning)
    (hp : r.props = sweepDocProps) : predTierL (some r) rep c = .two := by
  have : (r.effect rep).ticks = true := by
    have := sweepDoc_ticks rep (r.reason != some false)
    simpa [LayerRead.effect, hp] using this
  simp [predTierL, h, hn, this]

theorem predTierL_rep_irrelevant (r : LayerRead) (c : Census) (hp : r.props = sweepLayerProps) (hrun : r.reason ≠ some false) :
    predTierL (some r) none c = predTierL (some r) (some false) c := by
  have hb : (r.reason != some false) = true := bne_iff_ne.2 hrun
  have h1 : (r.effect none).ticks = false := by
    have := sweepLayer_core_no_tick
    simpa [LayerRead.effect, hp, hb] using this
  have h2 : (r.effect (some false)).ticks = false := by
    have := sweepLayer_rep_no_tick
    simpa [LayerRead.effect, hp, hb] using this
  simp [predTierL, h1, h2]

-- RenderLayerCompositor.cpp:3842-3860@862f17d answers true for an effect stack that merely affects transform
def reasonOf (layers anim : Nat) : Option Bool :=
  if layers == 0 then none else if anim == layers then some true else if anim == 0 then some false else none

theorem reasonOf_no_layer (a : Nat) : reasonOf 0 a = none := by simp [reasonOf]

theorem reasonOf_all (n : Nat) (h : n ≠ 0) : reasonOf n n = some true := by simp [reasonOf, h]

theorem reasonOf_none (n : Nat) (h : n ≠ 0) : reasonOf n 0 = some false := by simp [reasonOf, h, Ne.symm h]

theorem reasonOf_mixed (n a : Nat) (h0 : a ≠ 0) (h1 : a ≠ n) (h2 : n ≠ 0) : reasonOf n a = none := by simp [reasonOf, h0, h1, h2]

theorem predTierL_contradicted (r : LayerRead) (rep : Option Bool) (c : Census) (h : c.layerOnly = true) (hn : 0 < c.layerRunning)
    (hp : r.props ≠ []) (hr : r.reason = some false) : predTierL (some r) rep c = .two := by
  have : (r.effect rep).ticks = true := ticks_not_running _ (by simpa [LayerRead.effect] using hp) rfl (by simp [LayerRead.effect, hr])
  simp [predTierL, h, hn, this]

/-! ## Arms -/

inductive LArm where
  | both
  | bothL
  deriving DecidableEq, Repr

def LArm.name : LArm → String
  | .both => "both" | .bothL => "bothL"

def larms : List LArm := [.both, .bothL]

def layerSweepPart : String × String := ("platform.sweep", "layer-sweep")

def LArm.flags : LArm → List (String × String)
  | .both => ArmId.both.flags
  | .bothL => parkFlags ++ [("hero.accent", "offscreen-pause"), ("hero.cue", "offscreen-pause"), layerSweepPart]

theorem delta_bothL : Fw.Ops.Attrib.delta LArm.both.flags LArm.bothL.flags = ["platform.sweep"] := by decide

theorem delta_bothL_symm : Fw.Ops.Attrib.delta LArm.bothL.flags LArm.both.flags = ["platform.sweep"] := by decide

theorem bothL_one_variant_per_part : (LArm.bothL.flags.map (·.1)).eraseDups = LArm.bothL.flags.map (·.1) := by decide

theorem arms_no_faded_pause : fadedPause ∉ LArm.both.flags ∧ fadedPause ∉ LArm.bothL.flags := by decide

theorem bothL_drops_offscreen_pause : ("platform.sweep", "offscreen-pause") ∈ LArm.both.flags ∧
    ("platform.sweep", "offscreen-pause") ∉ LArm.bothL.flags := by decide

inductive LFlag where
  | base (f : Flag)
  | layerSweep
  deriving DecidableEq, Repr

def LFlag.name : LFlag → String
  | .base f => f.name | .layerSweep => layerSweepFlag

def layerSweepTook (c : Census) : Bool := c.complete && 0 < c.layerRunning && c.sweepDocLoops == 0

theorem layerSweepTook_iff (c : Census) : layerSweepTook c = true ↔ c.complete = true ∧ 0 < c.layerRunning ∧ c.sweepDocLoops = 0 := by
  simp [layerSweepTook, and_assoc]

theorem layerSweepTook_not_complete (c : Census) (h : c.complete = false) : layerSweepTook c = false := by simp [layerSweepTook, h]

theorem layerSweepTook_sweepDoc (c : Census) (n : Nat) (h : c.sweepDocLoops = n + 1) : layerSweepTook c = false := by
  simp [layerSweepTook, h]

theorem layerSweepTook_no_layer (c : Census) (h : c.layerRunning = 0) : layerSweepTook c = false := by simp [layerSweepTook, h]

def LFlag.took (c : Census) : LFlag → Bool
  | .base f => f.took c
  | .layerSweep => layerSweepTook c

def LArm.active : LArm → List LFlag
  | .both => ArmId.both.active.map .base
  | .bothL => [.base .heroPark, .base .scrollPark, .base .accentPause, .base .cuePause, .layerSweep]

theorem active_both_names : LArm.both.active.map LFlag.name = ArmId.both.active.map Flag.name := by decide

theorem active_bothL_names :
    LArm.bothL.active.map LFlag.name =
      ["hero.exit:threaded-park", "engine.scroll:unthrottle-park", "hero.accent:offscreen-pause", "hero.cue:offscreen-pause",
       "platform.sweep:layer-sweep"] := by decide

def missingL (a : LArm) (c : Census) : List String := (a.active.filter fun f => !f.took c).map LFlag.name

def effectNameL (a : LArm) (c : Census) : String :=
  if a.active.isEmpty then "none" else if (missingL a c).isEmpty then "took" else "missing:" ++ String.intercalate "," (missingL a c)

theorem effectL_took (a : LArm) (c : Census) (h0 : a.active.isEmpty = false) (h : missingL a c = []) : effectNameL a c = "took" := by
  simp [effectNameL, h0, h]

theorem effectL_missing (a : LArm) (c : Census) (h0 : a.active.isEmpty = false) (h : (missingL a c).isEmpty = false) :
    effectNameL a c = "missing:" ++ String.intercalate "," (missingL a c) := by
  simp [effectNameL, h0, h]

def sideTookL (a : LArm) (c : Option Census) : Bool :=
  a.active.all fun f => match c with
    | some c => f.took c
    | none => false

theorem sideTookL_some (a : LArm) (c : Census) : sideTookL a (some c) = true ↔ ∀ f ∈ a.active, f.took c = true := by simp [sideTookL]

theorem sideTookL_none (a : LArm) (h : a.active.isEmpty = false) : sideTookL a none = false := by
  cases hh : a.active with
  | nil => simp [hh] at h
  | cons f fs => simp [sideTookL, hh]

structure Stage where
  armCensus : Option Census
  layer : Option LayerRead
  cmpCensus : Option Census
  deriving DecidableEq, Repr

def edgeTookL (rounds : List Stage) : Bool := rounds.all fun s => sideTookL .bothL s.armCensus && sideTookL .both s.cmpCensus

theorem edgeTookL_false (rounds : List Stage) (s : Stage) (h : s ∈ rounds) (hs : (sideTookL .bothL s.armCensus && sideTookL .both s.cmpCensus) = false) :
    edgeTookL rounds = false := by
  simp only [edgeTookL, List.all_eq_false]
  exact ⟨s, h, by simpa using hs⟩

theorem edgeTookL_true (rounds : List Stage)
    (h : ∀ s ∈ rounds, sideTookL .bothL s.armCensus = true ∧ sideTookL .both s.cmpCensus = true) : edgeTookL rounds = true := by
  simp only [edgeTookL, List.all_eq_true]
  intro s hs
  simp [(h s hs).1, (h s hs).2]

def edgeOfL (build : String) (wa wc : Win) : EdgeV :=
  Fw.Device.SimEndCut.edgeTier build build LArm.bothL.flags LArm.both.flags (tier wa) (tier wc)

def predTierArm (rep : Option Bool) : LArm → Option Census → Option LayerRead → Tier
  | .both, c, _ => predTierFor .both c
  | .bothL, some c, r => predTierL r rep c
  | .bothL, none, _ => .two

def predEdgeL (rep : Option Bool) (s : Stage) : EdgeV :=
  Fw.Device.SimEndCut.edgeTier "b" "b" LArm.bothL.flags LArm.both.flags (predTierArm rep .bothL s.armCensus s.layer)
    (predTierArm rep .both s.cmpCensus none)

def overallPredL (rep : Option Bool) (rounds : List Stage) : String := overallNames (rounds.map fun s => (predEdgeL rep s).name)

theorem pred_cut (s : Stage) (rep : Option Bool) (hA : predTierArm rep .bothL s.armCensus s.layer = .one)
    (hC : predTierArm rep .both s.cmpCensus none = .two) : predEdgeL rep s = .cut "platform.sweep" := by
  have := Fw.Device.SimEndCut.edgeTier_cut "b" LArm.bothL.flags LArm.both.flags .one .two "platform.sweep" (by decide) (by decide)
    (by decide) (by decide) (by decide)
  simpa [predEdgeL, hA, hC] using this

theorem pred_noEffect (s : Stage) (rep : Option Bool) (hA : predTierArm rep .bothL s.armCensus s.layer = .two)
    (hC : predTierArm rep .both s.cmpCensus none = .two) : predEdgeL rep s = .noEffect "platform.sweep" := by
  have := Fw.Device.SimEndCut.edgeTier_noEffect "b" LArm.bothL.flags LArm.both.flags .two .two "platform.sweep" (by decide) (by decide)
    (by decide) rfl
  simpa [predEdgeL, hA, hC] using this

theorem pred_cut_of_census (rep : Option Bool) (c d : Census) (r : LayerRead) (hl : c.layerOnly = true) (hp : r.props ≠ [])
    (ha : r.props.all accelerated = true) (hrun : r.reason ≠ some false) (hrep : rep = none ∨ rep = some false)
    (hd : d.sourceRemains = true) : predEdgeL rep ⟨some c, some r, some d⟩ = .noEffect "platform.sweep" ∨
      predEdgeL rep ⟨some c, some r, some d⟩ = .cut "platform.sweep" := by
  right
  apply pred_cut
  · simpa [predTierArm] using predTierL_accelerated r rep c hl hp ha hrun hrep
  · simp [predTierArm, predTierFor_both_remains d hd]

def gateL (v : String) (took : Bool) : String := Fw.Device.SimEndCut.gate v took

private def w (seen recalcs : Nat) : Win := ⟨winRaf, seen, recalcs⟩

private def verdictCases : List (String × Win × Win) :=
  [("bothL one against both two", w 360 360, w 360 720), ("bothL two against both two", w 360 720, w 360 720),
   ("bothL one against both one", w 360 360, w 360 360), ("bothL two against both one", w 360 720, w 360 360),
   ("bothL unreadable", ⟨360, 100, 360⟩, w 360 720), ("both off the grid", w 360 360, w 360 540),
   ("bothL at the band edge", w 360 396, w 360 720), ("bothL one above the band", w 360 400, w 360 720)]

private def layerLoops : List String := List.replicate 5 "sweep-module_sweepLayerX_Hq9d2v"
private def inViewLayer : List String := List.replicate 2 "sweep-module_sweepLayerX_Hq9d2v"
private def sweepDocs : List String := List.replicate 5 "sweep-module_sweepDoc_zGc1tE"
private def idles : List String := ["accent-module_idle0_t7SI92", "accent-module_idle1_a3NQoa", "accent-module_idle2_Q1MyP3"]
private def cue : String := "cue-module_scrollFloat_6RFPnC"
private def fin : List (String × Nat) := [("document:finished", 20), ("document:paused", 7)]

private def cen (b : List (String × Nat)) (run pau : List String) (parked ut utP : Nat) (sw : Option Nat) : Census :=
  ⟨b, run, pau, parked, ut, utP, sw⟩

private def bothLC : Census := cen (fin ++ [("document:running", 5)]) layerLoops (idles ++ [cue]) 1 1 1 (some 0)
private def bothLInViewC : Census := cen (fin ++ [("document:running", 2)]) inViewLayer (layerLoops ++ idles ++ [cue]) 1 1 1 (some 0)
private def bothLNoLayerC : Census := cen fin [] (idles ++ [cue] ++ layerLoops) 1 1 1 (some 0)
private def bothLDocC : Census := cen fin (sweepDocs ++ layerLoops) (idles ++ [cue]) 1 1 1 (some 2)
private def bothLForeignC : Census := cen fin (layerLoops ++ ["glint-module_dash"]) (idles ++ [cue]) 1 1 1 (some 0)
private def bothLViewC : Census := cen (fin ++ [("view:running", 2)]) layerLoops (idles ++ [cue]) 0 1 1 (some 0)
private def bothLMissC : Census := cen fin (layerLoops ++ idles) [cue] 1 1 1 (some 0)
private def bothEndC : Census := cen (fin ++ [("document:running", 2)]) (sweepDocs.take 2) (idles ++ [cue] ++ sweepDocs) 1 1 1 (some 0)
private def bothClearC : Census := cen fin [] (idles ++ [cue] ++ sweepDocs) 1 1 1 (some 0)

private def censusCases : List (String × Census) :=
  [("bothL layer loops run", bothLC), ("bothL in-view layer loops run, hidden paused", bothLInViewC), ("bothL no layer loop runs", bothLNoLayerC),
   ("bothL sweepDoc loops remain", bothLDocC), ("bothL foreign loop runs", bothLForeignC), ("bothL view-driven runs", bothLViewC),
   ("bothL accent still runs", bothLMissC), ("both in-view sweeps run", bothEndC), ("both nothing runs", bothClearC),
   ("running list full", cen fin (List.replicate 24 "sweep-module_sweepLayerX_Hq9d2v") [] 1 1 1 (some 0))]

private def readFull : LayerRead := ⟨4, ["transform"], some true⟩
private def readInferred : LayerRead := ⟨4, ["transform"], none⟩
private def readContradicted : LayerRead := ⟨4, ["transform"], some false⟩
private def readDoc : LayerRead := ⟨4, ["background-position"], none⟩
private def readMixed : LayerRead := ⟨4, ["transform", "background-position"], none⟩
private def readNone : LayerRead := ⟨0, [], none⟩
private def readOpacity : LayerRead := ⟨2, ["transform", "opacity"], none⟩

private def reasonCases : List (String × Nat × Nat) :=
  [("no layer", 0, 0), ("five of five", 5, 5), ("none of five", 5, 0), ("two of five", 5, 2), ("one of one", 1, 1)]

private def readCases : List (String × LayerRead) :=
  [("transform, inspector says composited", readFull), ("transform, inspector not read", readInferred),
   ("transform, inspector says not composited", readContradicted), ("background-position", readDoc),
   ("transform and background-position", readMixed), ("no layer loop", readNone), ("transform and opacity", readOpacity)]

private def effectCases : List (String × Effect) :=
  [("sweepLayerX on the Core Animation path", ⟨["transform"], true, true, none, true⟩),
   ("sweepLayerX on a representation", ⟨["transform"], true, true, some false, true⟩),
   ("sweepLayerX with a disallowed property", ⟨["transform"], true, true, some true, true⟩),
   ("sweepLayerX not running accelerated", ⟨["transform"], true, false, none, true⟩),
   ("sweepLayerX without a renderer", ⟨["transform"], false, true, none, true⟩),
   ("sweepDoc", ⟨["background-position"], true, true, none, true⟩),
   ("transform and background-position", ⟨["transform", "background-position"], true, true, none, true⟩),
   ("opacity and transform", ⟨["opacity", "transform"], true, true, none, true⟩),
   ("no keyframe property", ⟨[], true, true, none, true⟩),
   ("a script animation on transform", ⟨["transform"], true, true, none, false⟩)]

private def predCases : List (String × Option LayerRead × Option Bool × Census) :=
  [("accelerated, Core Animation path", some readInferred, none, bothLC), ("accelerated, inspector composited", some readFull, none, bothLC),
   ("accelerated, representation", some readInferred, some false, bothLC), ("representation with a disallowed property", some readInferred, some true, bothLC),
   ("contradicted by the inspector", some readContradicted, none, bothLC), ("sweepDoc property", some readDoc, none, bothLC),
   ("mixed properties", some readMixed, none, bothLC), ("foreign loop runs", some readInferred, none, bothLForeignC),
   ("view-driven runs", some readInferred, none, bothLViewC), ("no layer loop runs", some readInferred, none, bothLNoLayerC),
   ("no read", none, none, bothLC)]

private def stageCases : List (String × Stage) :=
  [("layer clear against both with in-view sweeps", ⟨some bothLC, some readInferred, some bothEndC⟩),
   ("layer clear against both with nothing running", ⟨some bothLC, some readInferred, some bothClearC⟩),
   ("layer contradicted", ⟨some bothLC, some readContradicted, some bothEndC⟩),
   ("foreign loop", ⟨some bothLForeignC, some readInferred, some bothEndC⟩),
   ("no census for bothL", ⟨none, none, some bothEndC⟩),
   ("no census for both", ⟨some bothLC, some readInferred, none⟩)]

private def tookCases : List (String × List Stage) :=
  [("three jobs took", [⟨some bothLC, some readInferred, some bothEndC⟩, ⟨some bothLC, some readInferred, some bothEndC⟩,
     ⟨some bothLC, some readInferred, some bothEndC⟩]),
   ("one job sweepDoc remains", [⟨some bothLC, some readInferred, some bothEndC⟩, ⟨some bothLDocC, some readInferred, some bothEndC⟩]),
   ("no layer loop", [⟨some bothLNoLayerC, some readNone, some bothEndC⟩]),
   ("both missing its flags", [⟨some bothLC, some readInferred, some bothLMissC⟩]),
   ("no census for bothL", [⟨none, none, some bothEndC⟩])]

private def overallCases : List (String × Option Bool × List Stage) :=
  [("accelerated in 3 of 3", none, [⟨some bothLC, some readInferred, some bothEndC⟩, ⟨some bothLC, some readInferred, some bothEndC⟩,
     ⟨some bothLC, some readInferred, some bothEndC⟩]),
   ("accelerated in 2 of 3, foreign in 1", none, [⟨some bothLC, some readInferred, some bothEndC⟩, ⟨some bothLForeignC, some readInferred, some bothEndC⟩,
     ⟨some bothLC, some readInferred, some bothEndC⟩]),
   ("disallowed representation in 3 of 3", some true, [⟨some bothLC, some readInferred, some bothEndC⟩, ⟨some bothLC, some readInferred, some bothEndC⟩,
     ⟨some bothLC, some readInferred, some bothEndC⟩])]

private def overallEffectCases : List (String × List String) :=
  [("all took", ["took", "took", "took"]), ("one missing", ["took", "missing:platform.sweep:layer-sweep", "took"]),
   ("same missing", ["missing:a", "missing:a", "missing:a"])]

private def wJ (x : Win) : Lean.Json := Lean.Json.mkObj [("raf", x.raf), ("seen", x.seen), ("recalcs", x.recalcs)]

private def flagsJ (fs : List (String × String)) : Lean.Json := Lean.Json.arr (fs.map fun (k, v) => Lean.Json.arr #[Lean.Json.str k, Lean.Json.str v]).toArray

private def strsJ (xs : List String) : Lean.Json := Lean.Json.arr (xs.map Lean.Json.str).toArray

private def optBoolJ : Option Bool → Lean.Json
  | some b => Lean.Json.bool b
  | none => Lean.Json.null

private def censusJ (c : Census) : Lean.Json :=
  Lean.Json.mkObj [("by", Lean.Json.arr (c.byKey.map fun (k, n) => Lean.Json.arr #[Lean.Json.str k, Lean.Json.num n]).toArray),
    ("running", strsJ c.running), ("paused", strsJ c.paused), ("parked", c.parked), ("ut", c.ut), ("utParked", c.utParked),
    ("sweepHidden", match c.sweepHidden with | some n => Lean.Json.num n | none => Lean.Json.null)]

private def optCensusJ : Option Census → Lean.Json
  | some c => censusJ c
  | none => Lean.Json.null

private def readJ (r : LayerRead) : Lean.Json :=
  Lean.Json.mkObj [("loops", r.loops), ("props", strsJ r.props), ("reason", optBoolJ r.reason)]

private def optReadJ : Option LayerRead → Lean.Json
  | some r => readJ r
  | none => Lean.Json.null

private def effectJ (e : Effect) : Lean.Json :=
  Lean.Json.mkObj [("props", strsJ e.props), ("rendered", e.rendered), ("running", e.running), ("rep", optBoolJ e.rep), ("css", e.css)]

private def stageJ (s : Stage) : Lean.Json := Lean.Json.arr #[optCensusJ s.armCensus, optReadJ s.layer, optCensusJ s.cmpCensus]

def goldenLines (_ : Unit) : List String :=
  [(Lean.Json.mkObj [("kind", "consts"), ("band", band), ("winRaf", winRaf), ("windowMsMax", windowMsMax), ("sweepIterMs", sweepIterMs),
    ("sweepLoopCount", sweepLoopCount), ("iterRateMax", iterRate sweepLoopCount windowMsMax sweepIterMs winRaf),
    ("layerPrefix", Lean.Json.str layerPrefix)]).compress] ++
  (larms.map fun a =>
    (Lean.Json.mkObj [("kind", "arm"), ("arm", Lean.Json.str a.name), ("flags", flagsJ a.flags),
      ("active", strsJ (a.active.map LFlag.name))]).compress) ++
  [(Lean.Json.mkObj [("kind", "delta"), ("parts", strsJ (Fw.Ops.Attrib.delta LArm.both.flags LArm.bothL.flags))]).compress] ++
  (effectCases.map fun (n, e) =>
    (Lean.Json.mkObj [("kind", "effect"), ("name", n), ("effect", effectJ e), ("ticks", e.ticks),
      ("shareFull", shareOf e.props == .full), ("demandListener", Lean.Json.str (e.demand true).name),
      ("demandNone", Lean.Json.str (e.demand false).name)]).compress) ++
  (readCases.map fun (n, r) =>
    (Lean.Json.mkObj [("kind", "read"), ("name", n), ("read", readJ r), ("evidence", Lean.Json.str r.evidence),
      ("ticksCore", (r.effect none).ticks), ("ticksRep", (r.effect (some false)).ticks)]).compress) ++
  (reasonCases.map fun (n, l, a) =>
    (Lean.Json.mkObj [("kind", "reason"), ("name", n), ("layers", l), ("animation", a), ("reason", optBoolJ (reasonOf l a))]).compress) ++
  (censusCases.map fun (n, c) =>
    (Lean.Json.mkObj [("kind", "census"), ("name", n), ("census", censusJ c), ("complete", Lean.Json.bool c.complete),
      ("layerRunning", c.layerRunning), ("foreignRunning", c.foreignRunning), ("sweepDocLoops", c.sweepDocLoops),
      ("layerOnly", Lean.Json.bool c.layerOnly), ("layerSweepTook", Lean.Json.bool (layerSweepTook c)),
      ("effects", Lean.Json.mkObj (larms.map fun a => (a.name, Lean.Json.str (effectNameL a c)))),
      ("sourceRemains", Lean.Json.bool c.sourceRemains)]).compress) ++
  (verdictCases.map fun (n, a, c) =>
    (Lean.Json.mkObj [("kind", "verdict"), ("name", n), ("armWin", wJ a), ("cmpWin", wJ c),
      ("verdict", Lean.Json.str (edgeOfL "b" a c).name)]).compress) ++
  (predCases.map fun (n, r, rep, c) =>
    (Lean.Json.mkObj [("kind", "predTierL"), ("name", n), ("read", optReadJ r), ("rep", optBoolJ rep), ("census", censusJ c),
      ("tier", Lean.Json.str (predTierL r rep c).name)]).compress) ++
  (stageCases.map fun (n, s) =>
    (Lean.Json.mkObj [("kind", "predEdgeL"), ("name", n), ("rep", Lean.Json.null), ("stage", stageJ s),
      ("armTier", Lean.Json.str (predTierArm none .bothL s.armCensus s.layer).name),
      ("cmpTier", Lean.Json.str (predTierArm none .both s.cmpCensus none).name),
      ("predicted", Lean.Json.str (predEdgeL none s).name)]).compress) ++
  (tookCases.map fun (n, rs) =>
    (Lean.Json.mkObj [("kind", "edgeTookL"), ("name", n), ("stages", Lean.Json.arr (rs.map stageJ).toArray),
      ("took", Lean.Json.bool (edgeTookL rs))]).compress) ++
  (overallCases.map fun (n, rep, rs) =>
    (Lean.Json.mkObj [("kind", "overallPredL"), ("name", n), ("rep", optBoolJ rep), ("stages", Lean.Json.arr (rs.map stageJ).toArray),
      ("predicted", Lean.Json.str (overallPredL rep rs))]).compress) ++
  (overallEffectCases.map fun (n, ns) =>
    (Lean.Json.mkObj [("kind", "overallEffect"), ("name", n), ("effects", strsJ ns), ("overall", Lean.Json.str (overallEffect ns))]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "sim-layer-sweep.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"sim-layer-sweep golden differs: {goldenPath}")
  IO.println s!"sim-layer-sweep golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.SimLayerSweep
