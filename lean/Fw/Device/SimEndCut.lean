import Lean.Data.Json
import Fw.Device.SimFloorAttrib

/-! # sim-end-cut: the stacked end-of-page cut on the iOS Simulator, one verdict per arm against its comparator -/
namespace Fw.Device.SimEndCut

open Lean Fw.Device.SimEndFloor Fw.Device.EndWktr
open Fw.Device.SimFloorAttrib (Tier EdgeV runOf tier overallEdge overallTier v2pFlags)

inductive ArmId where
  | v2p
  | parks
  | pauses
  | both
  deriving DecidableEq, Repr

def ArmId.name : ArmId → String
  | .v2p => "v2p" | .parks => "parks" | .pauses => "pauses" | .both => "both"

def allArms : List ArmId := [.v2p, .parks, .pauses, .both]

def parksSet : String := "parks"
def pausesSet : String := "pauses"

def onOff (b : Bool) : String := if b then "on" else "off"

def ArmId.hasParks : ArmId → Bool
  | .parks | .both => true
  | _ => false

def ArmId.hasPauses : ArmId → Bool
  | .pauses | .both => true
  | _ => false

def ArmId.sets (a : ArmId) : List (String × String) := [(parksSet, onOff a.hasParks), (pausesSet, onOff a.hasPauses)]

def parkFlags : List (String × String) := [("engine.scroll", "unthrottle-park"), ("hero.exit", "threaded-park")]

def threadFlags : List (String × String) := [("engine.scroll", "unthrottle"), ("hero.exit", "threaded")]

def fadedPause : String × String := ("platform", "faded-pause")

def pauseFlags : List (String × String) :=
  [("hero.accent", "offscreen-pause"), ("hero.cue", "offscreen-pause"), ("platform.sweep", "offscreen-pause")]

def ArmId.flags : ArmId → List (String × String)
  | .v2p => v2pFlags
  | .parks => parkFlags ++ [fadedPause]
  | .pauses => threadFlags ++ pauseFlags
  | .both => parkFlags ++ pauseFlags

theorem pause_arms_swap_faded :
    fadedPause ∈ ArmId.v2p.flags ∧ fadedPause ∈ ArmId.parks.flags ∧
    fadedPause ∉ ArmId.pauses.flags ∧ fadedPause ∉ ArmId.both.flags := by decide

def setParts : String → List String
  | "parks" => ["engine.scroll", "hero.exit"]
  | "pauses" => ["platform", "hero.accent", "hero.cue", "platform.sweep"]
  | _ => []

structure Edge where
  arm : ArmId
  cmp : ArmId
  stages : List String
  deriving DecidableEq, Repr

def liveStages : List String := ["end", "back"]

def edges : List Edge :=
  [⟨.parks, .v2p, liveStages⟩, ⟨.pauses, .v2p, liveStages⟩, ⟨.both, .parks, liveStages⟩, ⟨.both, .pauses, liveStages⟩]

def Edge.part (e : Edge) : List String := Fw.Ops.Attrib.delta e.cmp.sets e.arm.sets

def Edge.realParts (e : Edge) : List String := Fw.Ops.Attrib.delta e.cmp.flags e.arm.flags

theorem parks_v2p_set : (Edge.mk .parks .v2p liveStages).part = [parksSet] := by decide

theorem pauses_v2p_set : (Edge.mk .pauses .v2p liveStages).part = [pausesSet] := by decide

theorem both_parks_set : (Edge.mk .both .parks liveStages).part = [pausesSet] := by decide

theorem both_pauses_set : (Edge.mk .both .pauses liveStages).part = [parksSet] := by decide

theorem both_v2p_two_sets : (Edge.mk .both .v2p liveStages).part = [parksSet, pausesSet] := by decide

theorem edges_one_set : ∀ e ∈ edges, e.part.length = 1 := by decide

theorem parks_v2p_real : (Edge.mk .parks .v2p liveStages).realParts = setParts parksSet := by decide

theorem pauses_v2p_real : (Edge.mk .pauses .v2p liveStages).realParts = setParts pausesSet := by decide

theorem both_parks_real : (Edge.mk .both .parks liveStages).realParts = setParts pausesSet := by decide

theorem both_pauses_real : (Edge.mk .both .pauses liveStages).realParts = setParts parksSet := by decide

def edgeTier (ba bc : String) (fa fc : List (String × String)) (ta tc : Tier) : EdgeV :=
  if ta = .unreadable ∨ tc = .unreadable then .unreadable
  else if ta = .off ∨ tc = .off then .offGrid
  else match Fw.Ops.Attrib.verdict ⟨bc, fc, true⟩ ⟨ba, fa, ta == tc⟩ with
    | .notAttributable => .notAttributable
    | .noEffect p => .noEffect p
    | .causedBy p _ _ => if ta.rank < tc.rank then .cut p else .raised p

theorem edgeTier_eq_attrib (ba bc : String) (a c : Fw.Device.SimFloorAttrib.ArmId) (wa wc : Win) :
    Fw.Device.SimFloorAttrib.edge ba bc a c wa wc = edgeTier ba bc a.flags c.flags (tier wa) (tier wc) := by
  rfl

theorem edgeTier_unreadable (ba bc : String) (fa fc : List (String × String)) (ta tc : Tier)
    (h : ta = .unreadable ∨ tc = .unreadable) : edgeTier ba bc fa fc ta tc = .unreadable := by simp [edgeTier, h]

theorem edgeTier_offGrid (ba bc : String) (fa fc : List (String × String)) (ta tc : Tier)
    (h0 : ¬ (ta = .unreadable ∨ tc = .unreadable)) (h : ta = .off ∨ tc = .off) : edgeTier ba bc fa fc ta tc = .offGrid := by
  simp [edgeTier, h0, h]

theorem edgeTier_other_build (ba bc : String) (fa fc : List (String × String)) (ta tc : Tier) (hb : ba ≠ bc)
    (h0 : ¬ (ta = .unreadable ∨ tc = .unreadable)) (h1 : ¬ (ta = .off ∨ tc = .off)) :
    edgeTier ba bc fa fc ta tc = .notAttributable := by
  have hv : Fw.Ops.Attrib.verdict ⟨bc, fc, true⟩ ⟨ba, fa, ta == tc⟩ = .notAttributable :=
    Fw.Ops.Attrib.other_commit_not_attributable _ _ (by simpa using hb.symm)
  simp [edgeTier, h0, h1, hv]

theorem edgeTier_two_parts (b : String) (fa fc : List (String × String)) (ta tc : Tier) (f g : String)
    (h0 : ¬ (ta = .unreadable ∨ tc = .unreadable)) (h1 : ¬ (ta = .off ∨ tc = .off)) (hd : Fw.Ops.Attrib.delta fc fa = [f, g]) :
    edgeTier b b fa fc ta tc = .notAttributable := by
  have hv := Fw.Ops.Attrib.two_parts_not_attributable (⟨b, fc, true⟩ : Fw.Ops.Attrib.Run) ⟨b, fa, ta == tc⟩ f g hd
  simp [edgeTier, h0, h1, hv]

theorem edgeTier_noEffect (b : String) (fa fc : List (String × String)) (ta tc : Tier) (p : String)
    (h0 : ¬ (ta = .unreadable ∨ tc = .unreadable)) (h1 : ¬ (ta = .off ∨ tc = .off)) (hd : Fw.Ops.Attrib.delta fc fa = [p])
    (hs : ta = tc) : edgeTier b b fa fc ta tc = .noEffect p := by
  have hv : Fw.Ops.Attrib.verdict (⟨b, fc, true⟩ : Fw.Ops.Attrib.Run) ⟨b, fa, ta == tc⟩ = .noEffect p :=
    Fw.Ops.Attrib.noEffect_of_same_outcome _ _ p rfl hd (by simp [hs])
  simp [edgeTier, h0, h1, hv]

theorem edgeTier_cut (b : String) (fa fc : List (String × String)) (ta tc : Tier) (p : String)
    (h0 : ¬ (ta = .unreadable ∨ tc = .unreadable)) (h1 : ¬ (ta = .off ∨ tc = .off)) (hd : Fw.Ops.Attrib.delta fc fa = [p])
    (hne : ta ≠ tc) (hlt : ta.rank < tc.rank) : edgeTier b b fa fc ta tc = .cut p := by
  have hv := Fw.Ops.Attrib.causedBy_of_fail_second (⟨b, fc, true⟩ : Fw.Ops.Attrib.Run) ⟨b, fa, ta == tc⟩ p rfl hd rfl
    (by simpa using hne)
  simp [edgeTier, h0, h1, hv, hlt]

theorem edgeTier_raised (b : String) (fa fc : List (String × String)) (ta tc : Tier) (p : String)
    (h0 : ¬ (ta = .unreadable ∨ tc = .unreadable)) (h1 : ¬ (ta = .off ∨ tc = .off)) (hd : Fw.Ops.Attrib.delta fc fa = [p])
    (hne : ta ≠ tc) (hge : ¬ ta.rank < tc.rank) : edgeTier b b fa fc ta tc = .raised p := by
  have hv := Fw.Ops.Attrib.causedBy_of_fail_second (⟨b, fc, true⟩ : Fw.Ops.Attrib.Run) ⟨b, fa, ta == tc⟩ p rfl hd rfl
    (by simpa using hne)
  simp [edgeTier, h0, h1, hv, hge]

def edgeOf (build : String) (e : Edge) (wa wc : Win) : EdgeV := edgeTier build build e.arm.sets e.cmp.sets (tier wa) (tier wc)

def predTier : ArmId → Tier
  | .v2p => .two | .parks => .two | .pauses => .two | .both => .one

def predEdge (e : Edge) : EdgeV := edgeTier "b" "b" e.arm.sets e.cmp.sets (predTier e.arm) (predTier e.cmp)

theorem pred_parks : predEdge ⟨.parks, .v2p, liveStages⟩ = .noEffect parksSet := by decide

theorem pred_pauses : predEdge ⟨.pauses, .v2p, liveStages⟩ = .noEffect pausesSet := by decide

theorem pred_both_parks : predEdge ⟨.both, .parks, liveStages⟩ = .cut pausesSet := by decide

theorem pred_both_pauses : predEdge ⟨.both, .pauses, liveStages⟩ = .cut parksSet := by decide

def held (overall predicted : String) : String :=
  if overall == predicted then "held"
  else if overall == "inconclusive" || overall == "mixed" then "undecided"
  else "missed"

theorem held_held (n : String) : held n n = "held" := by simp [held]

theorem held_undecided_inconclusive (p : String) (h : "inconclusive" ≠ p) : held "inconclusive" p = "undecided" := by
  simp [held, h]

theorem held_undecided_mixed (p : String) (h : "mixed" ≠ p) : held "mixed" p = "undecided" := by simp [held, h]

theorem held_missed (n p : String) (h : n ≠ p) (h1 : n ≠ "inconclusive") (h2 : n ≠ "mixed") : held n p = "missed" := by
  simp [held, h, h1, h2]

def heldGated (overall predicted : String) (took : Bool) : String := if took then held overall predicted else "untested"

theorem heldGated_untested (overall predicted : String) : heldGated overall predicted false = "untested" := by simp [heldGated]

theorem heldGated_eq_held (overall predicted : String) : heldGated overall predicted true = held overall predicted := by
  simp [heldGated]

inductive Kind where
  | accent
  | cue
  | sweep
  | other
  deriving DecidableEq, Repr

def Kind.name : Kind → String
  | .accent => "accent idle" | .cue => "cue float" | .sweep => "platform sweep" | .other => "other"

def hasPrefix (pre s : String) : Bool := pre.toList.isPrefixOf s.toList

def kindOf (name : String) : Kind :=
  if hasPrefix "accent-module_idle" name then .accent
  else if hasPrefix "cue-module_scrollFloat" name then .cue
  else if hasPrefix "sweep-module_sweepDoc" name then .sweep
  else .other

theorem kindOf_accent : kindOf "accent-module_idle1_a3NQoa" = .accent := by decide

theorem kindOf_cue : kindOf "cue-module_scrollFloat_6RFPnC" = .cue := by decide

theorem kindOf_sweep : kindOf "sweep-module_sweepDoc_zGc1tE" = .sweep := by decide

theorem kindOf_other : kindOf "wave-module_x" = .other := by decide

structure Census where
  byKey : List (String × Nat)
  running : List String
  paused : List String
  parked : Nat
  ut : Nat
  utParked : Nat
  sweepHidden : Option Nat
  deriving DecidableEq, Repr

def censusCap : Nat := 24

def Census.complete (c : Census) : Bool := c.running.length < censusCap && c.paused.length < censusCap

def Census.sumKeys (c : Census) (pre : String) : Nat :=
  (c.byKey.filter fun (k, _) => hasPrefix pre k).foldl (fun s (_, n) => s + n) 0

def Census.viewDriven (c : Census) : Nat := c.sumKeys "view:"

def Census.scrollDriven (c : Census) : Nat := c.sumKeys "scroll:"

def Census.runningOf (c : Census) (k : Kind) : Nat := (c.running.filter fun n => kindOf n == k).length

inductive Flag where
  | unthrottle
  | threaded
  | heroPark
  | scrollPark
  | accentPause
  | cuePause
  | sweepPause
  deriving DecidableEq, Repr

def Flag.name : Flag → String
  | .unthrottle => "engine.scroll:unthrottle" | .threaded => "hero.exit:threaded"
  | .heroPark => "hero.exit:threaded-park" | .scrollPark => "engine.scroll:unthrottle-park"
  | .accentPause => "hero.accent:offscreen-pause" | .cuePause => "hero.cue:offscreen-pause"
  | .sweepPause => "platform.sweep:offscreen-pause"

def pauseTook (c : Census) (k : Kind) : Bool := c.complete && c.runningOf k == 0

def sweepTook (c : Census) : Bool := c.complete && c.sweepHidden == some 0

def Flag.took (c : Census) : Flag → Bool
  | .unthrottle => 0 < c.ut && 0 < c.scrollDriven
  | .threaded => 0 < c.viewDriven && c.parked == 0
  | .heroPark => c.viewDriven == 0 && 0 < c.parked
  | .scrollPark => c.scrollDriven == 0 && 0 < c.utParked
  | .accentPause => pauseTook c .accent
  | .cuePause => pauseTook c .cue
  | .sweepPause => sweepTook c

def allFlags : List Flag := [.unthrottle, .threaded, .heroPark, .scrollPark, .accentPause, .cuePause, .sweepPause]

def ArmId.active (a : ArmId) : List Flag :=
  (if a.hasParks then [Flag.heroPark, .scrollPark] else [Flag.unthrottle, .threaded]) ++
    (if a.hasPauses then [Flag.accentPause, .cuePause, .sweepPause] else [])

theorem active_v2p : ArmId.v2p.active = [.unthrottle, .threaded] := by decide

theorem active_parks : ArmId.parks.active = [.heroPark, .scrollPark] := by decide

theorem active_pauses : ArmId.pauses.active = [.unthrottle, .threaded, .accentPause, .cuePause, .sweepPause] := by decide

theorem active_both : ArmId.both.active = [.heroPark, .scrollPark, .accentPause, .cuePause, .sweepPause] := by decide

def missing (a : ArmId) (c : Census) : List String := (a.active.filter fun f => !f.took c).map Flag.name

def effectName (a : ArmId) (c : Census) : String :=
  if a.active.isEmpty then "none" else if (missing a c).isEmpty then "took" else "missing:" ++ String.intercalate "," (missing a c)

theorem effect_took (a : ArmId) (c : Census) (h0 : a.active.isEmpty = false) (h : missing a c = []) : effectName a c = "took" := by
  simp [effectName, h0, h]

theorem effect_missing (a : ArmId) (c : Census) (h0 : a.active.isEmpty = false) (h : (missing a c).isEmpty = false) :
    effectName a c = "missing:" ++ String.intercalate "," (missing a c) := by
  simp [effectName, h0, h]

theorem heroPark_took_iff (c : Census) : Flag.took c .heroPark = true ↔ c.viewDriven = 0 ∧ 0 < c.parked := by simp [Flag.took]

theorem scrollPark_took_iff (c : Census) : Flag.took c .scrollPark = true ↔ c.scrollDriven = 0 ∧ 0 < c.utParked := by
  simp [Flag.took]

theorem unthrottle_took_iff (c : Census) : Flag.took c .unthrottle = true ↔ 0 < c.ut ∧ 0 < c.scrollDriven := by simp [Flag.took]

theorem threaded_took_iff (c : Census) : Flag.took c .threaded = true ↔ 0 < c.viewDriven ∧ c.parked = 0 := by simp [Flag.took]

theorem sweepPause_took_iff (c : Census) : Flag.took c .sweepPause = true ↔ c.complete = true ∧ c.sweepHidden = some 0 := by
  simp [Flag.took, sweepTook]

theorem sweepPause_in_view_allowed (c : Census) (h : c.complete = true) (hh : c.sweepHidden = some 0) (hr : 0 < c.runningOf .sweep) :
    Flag.took c .sweepPause = true ∧ pauseTook c .sweep = false := by
  refine ⟨(sweepPause_took_iff c).2 ⟨h, hh⟩, ?_⟩
  simp [pauseTook, Nat.pos_iff_ne_zero.mp hr]

theorem sweepPause_hidden_running (c : Census) (n : Nat) (hn : c.sweepHidden = some (n + 1)) : Flag.took c .sweepPause = false := by
  simp [Flag.took, sweepTook, hn]

theorem sweepPause_no_read (c : Census) (h : c.sweepHidden = none) : Flag.took c .sweepPause = false := by
  simp [Flag.took, sweepTook, h]

theorem pause_not_took_running (c : Census) (k : Kind) (h : c.runningOf k ≠ 0) : pauseTook c k = false := by
  simp [pauseTook, h]

theorem pause_took_finished (c : Census) (k : Kind) (h : c.complete = true) (hr : c.runningOf k = 0) : pauseTook c k = true := by
  simp [pauseTook, h, hr]

theorem pause_took_iff (c : Census) (k : Kind) : pauseTook c k = true ↔ c.complete = true ∧ c.runningOf k = 0 := by
  simp [pauseTook]

theorem pause_not_took_incomplete (c : Census) (k : Kind) (h : c.complete = false) : pauseTook c k = false := by
  simp [pauseTook, h]

def sideTook (a : ArmId) (c : Option Census) : Bool :=
  a.active.all fun f => match c with
    | some c => f.took c
    | none => false

def edgeTook (e : Edge) (rounds : List (Option Census × Option Census)) : Bool :=
  rounds.all fun (ca, cc) => sideTook e.arm ca && sideTook e.cmp cc

theorem sideTook_v2p (c : Census) : sideTook .v2p (some c) = true ↔ Flag.took c .unthrottle = true ∧ Flag.took c .threaded = true := by
  simp [sideTook, active_v2p]

theorem sideTook_no_census (a : ArmId) (h : a.active.isEmpty = false) : sideTook a none = false := by
  cases hh : a.active with
  | nil => simp [hh] at h
  | cons f fs => simp [sideTook, hh]

theorem sideTook_some (a : ArmId) (c : Census) : sideTook a (some c) = true ↔ ∀ f ∈ a.active, f.took c = true := by
  simp [sideTook]

theorem edgeTook_false (e : Edge) (rounds : List (Option Census × Option Census)) (ca cc : Option Census) (h : (ca, cc) ∈ rounds)
    (hs : (sideTook e.arm ca && sideTook e.cmp cc) = false) : edgeTook e rounds = false := by
  simp only [edgeTook, List.all_eq_false]
  exact ⟨(ca, cc), h, by simpa using hs⟩

theorem edgeTook_true (e : Edge) (rounds : List (Option Census × Option Census))
    (h : ∀ r ∈ rounds, sideTook e.arm r.1 = true ∧ sideTook e.cmp r.2 = true) : edgeTook e rounds = true := by
  simp only [edgeTook, List.all_eq_true]
  intro r hr
  simp [(h r hr).1, (h r hr).2]

def stillTicks (c : Census) : List (String × Nat) :=
  ([("view-driven", c.viewDriven), ("scroll-driven", c.scrollDriven)] ++
    ([Kind.accent, .cue, .sweep, .other].map fun k => (k.name ++ " running", c.runningOf k))).filter fun (_, n) => 0 < n

theorem stillTicks_empty (c : Census) (h : c.viewDriven = 0 ∧ c.scrollDriven = 0 ∧ c.running = []) : stillTicks c = [] := by
  obtain ⟨h1, h2, h3⟩ := h
  simp [stillTicks, Census.runningOf, h1, h2, h3]

def Census.sourceRemains (c : Census) : Bool := !(stillTicks c).isEmpty

def Census.sweepOnly (c : Census) : Bool :=
  c.viewDriven == 0 && c.scrollDriven == 0 && c.runningOf .accent == 0 && c.runningOf .cue == 0 && c.runningOf .other == 0 &&
    0 < c.runningOf .sweep

theorem sourceRemains_empty (c : Census) (h : c.viewDriven = 0 ∧ c.scrollDriven = 0 ∧ c.running = []) : c.sourceRemains = false := by
  simp [Census.sourceRemains, stillTicks_empty c h]

theorem sweepOnly_remains (c : Census) (h : c.sweepOnly = true) : c.sourceRemains = true := by
  simp only [Census.sweepOnly, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at h
  obtain ⟨⟨⟨⟨⟨h1, h2⟩, h3⟩, h4⟩, h5⟩, h6⟩ := h
  have hmem : ("platform sweep running", c.runningOf .sweep) ∈ stillTicks c := by
    simp [stillTicks, Kind.name, h6]
  cases hs : stillTicks c with
  | nil => simp [hs] at hmem
  | cons x xs => simp [Census.sourceRemains, hs]

def layerSweepFlag : String := "platform.sweep:layer-sweep"

def candidateOf (c : Census) : Option String := if c.sweepOnly then some layerSweepFlag else none

theorem candidate_iff (c : Census) : candidateOf c = some layerSweepFlag ↔ c.sweepOnly = true := by
  simp [candidateOf]

def predTierFor (a : ArmId) : Option Census → Tier
  | some c => if a = .both ∧ c.sourceRemains = true then .two else predTier a
  | none => predTier a

theorem predTierFor_both_clear (c : Census) (h : c.sourceRemains = false) : predTierFor .both (some c) = .one := by
  simp [predTierFor, h, predTier]

theorem predTierFor_both_remains (c : Census) (h : c.sourceRemains = true) : predTierFor .both (some c) = .two := by
  simp [predTierFor, h]

theorem predTierFor_other (a : ArmId) (c : Option Census) (h : a ≠ .both) : predTierFor a c = predTier a := by
  cases c with
  | none => rfl
  | some c => simp [predTierFor, h]

theorem predTierFor_no_census (a : ArmId) : predTierFor a none = predTier a := rfl

def predEdgeFor (e : Edge) (ca cc : Option Census) : EdgeV :=
  edgeTier "b" "b" e.arm.sets e.cmp.sets (predTierFor e.arm ca) (predTierFor e.cmp cc)

theorem predEdgeFor_both_parks_remains (c d : Census) (h : c.sourceRemains = true) :
    predEdgeFor ⟨.both, .parks, liveStages⟩ (some c) (some d) = .noEffect pausesSet := by
  have := edgeTier_noEffect "b" ArmId.both.sets ArmId.parks.sets .two .two pausesSet (by decide) (by decide) (by decide) rfl
  simpa [predEdgeFor, predTierFor, predTier, h] using this

theorem predEdgeFor_both_parks_clear (c d : Census) (h : c.sourceRemains = false) :
    predEdgeFor ⟨.both, .parks, liveStages⟩ (some c) (some d) = .cut pausesSet := by
  have := edgeTier_cut "b" ArmId.both.sets ArmId.parks.sets .one .two pausesSet (by decide) (by decide) (by decide) (by decide)
    (by decide)
  simpa [predEdgeFor, predTierFor, predTier, h] using this

theorem predEdgeFor_both_pauses_remains (c d : Census) (h : c.sourceRemains = true) :
    predEdgeFor ⟨.both, .pauses, liveStages⟩ (some c) (some d) = .noEffect parksSet := by
  have := edgeTier_noEffect "b" ArmId.both.sets ArmId.pauses.sets .two .two parksSet (by decide) (by decide) (by decide) rfl
  simpa [predEdgeFor, predTierFor, predTier, h] using this

theorem predEdgeFor_both_pauses_clear (c d : Census) (h : c.sourceRemains = false) :
    predEdgeFor ⟨.both, .pauses, liveStages⟩ (some c) (some d) = .cut parksSet := by
  have := edgeTier_cut "b" ArmId.both.sets ArmId.pauses.sets .one .two parksSet (by decide) (by decide) (by decide) (by decide)
    (by decide)
  simpa [predEdgeFor, predTierFor, predTier, h] using this

theorem predEdgeFor_no_census (e : Edge) : predEdgeFor e none none = predEdge e := rfl

def overallPred (e : Edge) (rounds : List (Option Census × Option Census)) : String :=
  overallNames (rounds.map fun (ca, cc) => (predEdgeFor e ca cc).name)

def gate (v : String) (took : Bool) : String := if took then v else "untested"

theorem gate_untested (v : String) : gate v false = "untested" := by simp [gate]

theorem gate_took (v : String) : gate v true = v := by simp [gate]

theorem heldGated_eq_gate (o p : String) (t : Bool) : heldGated o p t = gate (held o p) t := by simp [heldGated, gate]

def overallEffect (ns : List String) : String := overallNames (ns.filter fun n => n != "none")

theorem overallEffect_inconclusive (ns : List String) (h : (ns.filter fun n => n != "none").length < minRounds) :
    overallEffect ns = "inconclusive" := by
  simpa [overallEffect] using overallNames_inconclusive _ (by simpa [minRounds] using h)

private def w (seen recalcs : Nat) : Win := ⟨winRaf, seen, recalcs⟩

private def verdictCases : List (String × Edge × Win × Win) :=
  [("parks two against two", ⟨.parks, .v2p, liveStages⟩, w 360 720, w 360 720),
   ("parks one against two", ⟨.parks, .v2p, liveStages⟩, w 360 360, w 360 720),
   ("parks two against one", ⟨.parks, .v2p, liveStages⟩, w 360 720, w 360 360),
   ("pauses two against two", ⟨.pauses, .v2p, liveStages⟩, w 360 724, w 360 720),
   ("pauses zero against two", ⟨.pauses, .v2p, liveStages⟩, w 360 0, w 360 720),
   ("both one against two parks", ⟨.both, .parks, liveStages⟩, w 360 360, w 360 720),
   ("both one against two pauses", ⟨.both, .pauses, liveStages⟩, w 360 360, w 360 720),
   ("both two against two parks", ⟨.both, .parks, liveStages⟩, w 360 720, w 360 720),
   ("both two against two pauses", ⟨.both, .pauses, liveStages⟩, w 360 720, w 360 720),
   ("both against v2p, two sets", ⟨.both, .v2p, liveStages⟩, w 360 360, w 360 720),
   ("v2p against v2p, zero sets", ⟨.v2p, .v2p, liveStages⟩, w 360 720, w 360 720),
   ("unreadable arm window", ⟨.both, .parks, liveStages⟩, ⟨360, 100, 360⟩, w 360 720),
   ("unreadable comparator window", ⟨.both, .parks, liveStages⟩, w 360 360, ⟨360, 100, 720⟩),
   ("arm off the grid", ⟨.both, .parks, liveStages⟩, w 360 540, w 360 720),
   ("comparator off the grid", ⟨.both, .parks, liveStages⟩, w 360 360, w 360 540)]

private def heldCases : List (String × String × String) :=
  [("same cut", "cut:pauses", "cut:pauses"), ("same noEffect", "noEffect:parks", "noEffect:parks"),
   ("other verdict", "cut:parks", "noEffect:parks"), ("inconclusive", "inconclusive", "noEffect:parks"),
   ("mixed", "mixed", "cut:pauses"), ("not attributable", "notAttributable", "cut:pauses")]

private def kindCases : List String :=
  ["accent-module_idle0_t7SI92", "accent-module_idle2_Q1MyP3", "cue-module_scrollFloat_6RFPnC", "sweep-module_sweepDoc_zGc1tE",
   "wave-module_x", "", "accent-module_draw", "cue-module_float"]

private def sweeps : List String := List.replicate 4 "sweep-module_sweepDoc_zGc1tE"
private def inView : List String := List.replicate 2 "sweep-module_sweepDoc_zGc1tE"
private def idles : List String := ["accent-module_idle0_t7SI92", "accent-module_idle1_a3NQoa", "accent-module_idle2_Q1MyP3"]
private def cue : String := "cue-module_scrollFloat_6RFPnC"
private def fin : List (String × Nat) := [("document:finished", 20), ("document:paused", 7)]

private def cen (b : List (String × Nat)) (run pau : List String) (parked ut utP : Nat) (sw : Option Nat) : Census :=
  ⟨b, run, pau, parked, ut, utP, sw⟩

private def censusCases : List (String × Census) :=
  [("v2p at the end", cen (fin ++ [("view:finished", 13), ("scroll:finished", 1), ("document:running", 8)]) (idles ++ [cue] ++ sweeps) [] 0 1 0 (some 2)),
   ("parks took", cen (fin ++ [("document:running", 8)]) (idles ++ [cue] ++ sweeps) [] 1 1 1 (some 2)),
   ("hero park missed", cen (fin ++ [("view:finished", 13), ("document:running", 8)]) (idles ++ [cue] ++ sweeps) [] 0 1 1 (some 2)),
   ("hero park attribute without the animations gone", cen (fin ++ [("view:finished", 13)]) [] [] 1 1 1 none),
   ("scroll park missed", cen (fin ++ [("scroll:running", 1)]) (idles ++ [cue] ++ sweeps) [] 1 1 0 (some 2)),
   ("scroll park gone without the park attribute", cen fin (idles ++ [cue] ++ sweeps) [] 1 0 0 (some 2)),
   ("pauses took, hidden sweeps paused", cen (fin ++ [("document:paused", 15)]) inView (idles ++ [cue] ++ sweeps) 0 1 0 (some 0)),
   ("sweeps still run hidden", cen fin sweeps (idles ++ [cue]) 0 1 0 (some 2)),
   ("sweep census not read", cen fin inView (idles ++ [cue]) 0 1 0 none),
   ("cue still runs", cen fin [cue] (idles ++ sweeps) 0 1 0 (some 0)),
   ("accent finished", cen fin [] ([cue] ++ sweeps) 0 1 0 (some 0)), ("accent running", cen fin idles ([cue] ++ sweeps) 0 1 0 (some 0)),
   ("running list full", cen fin (List.replicate 24 "wave-module_x") (idles ++ [cue] ++ sweeps) 0 1 0 (some 0)),
   ("both took, in-view sweeps run", cen (fin ++ [("document:running", 2)]) inView (idles ++ [cue] ++ sweeps) 1 1 1 (some 0)),
   ("both took, nothing runs", cen fin [] (idles ++ [cue] ++ sweeps) 1 1 1 (some 0)),
   ("both, other loops run", cen fin ["glint-module_dash", "glint-module_dash"] (idles ++ [cue] ++ sweeps) 1 1 1 (some 0)),
   ("both, in-view sweeps and a cue run", cen fin (inView ++ [cue]) (idles ++ sweeps) 1 1 1 (some 0))]

private def heldGatedCases : List (String × String × String × Bool) :=
  [("held and took", "cut:pauses", "cut:pauses", true), ("missed and took", "noEffect:pauses", "cut:pauses", true),
   ("inconclusive and took", "inconclusive", "cut:pauses", true), ("held, flag did not engage", "cut:pauses", "cut:pauses", false),
   ("missed, flag did not engage", "noEffect:pauses", "cut:pauses", false), ("mixed, flag did not engage", "mixed", "cut:pauses", false)]

private def gateCases : List (String × String × Bool) :=
  [("noEffect, flag did not engage", "noEffect:parks", false), ("cut, flag did not engage", "cut:pauses", false),
   ("noEffect, took", "noEffect:parks", true), ("cut, took", "cut:pauses", true), ("raised, flag did not engage", "raised:parks", false)]

private def tookC : Census := cen fin inView (idles ++ [cue] ++ sweeps) 1 1 1 (some 0)
private def v2pC : Census := cen (fin ++ [("view:finished", 13), ("scroll:finished", 1)]) (idles ++ [cue] ++ sweeps) [] 0 1 0 (some 2)
private def parkMissC : Census := cen (fin ++ [("view:finished", 13)]) [] (idles ++ [cue] ++ sweeps) 0 1 1 (some 0)
private def sweepRunC : Census := cen fin sweeps (idles ++ [cue]) 0 1 0 (some 2)
private def accentFinC : Census := cen fin [] ([cue] ++ sweeps) 1 1 1 (some 0)
private def parksC : Census := cen fin (idles ++ [cue] ++ sweeps) [] 1 1 1 (some 2)
private def pausesC : Census := cen (fin ++ [("view:finished", 13), ("scroll:finished", 1)]) inView (idles ++ [cue] ++ sweeps) 0 1 0 (some 0)
private def bothC : Census := cen fin inView (idles ++ [cue] ++ sweeps) 1 1 1 (some 0)
private def bothClearC : Census := cen fin [] (idles ++ [cue] ++ sweeps) 1 1 1 (some 0)

private def edgeTookCases : List (String × Edge × List (Option Census × Option Census)) :=
  [("parks and v2p took", ⟨.parks, .v2p, liveStages⟩, [(some parksC, some v2pC), (some parksC, some v2pC), (some parksC, some v2pC)]),
   ("hero park missed", ⟨.parks, .v2p, liveStages⟩, [(some parkMissC, some v2pC)]),
   ("one round missed", ⟨.both, .parks, liveStages⟩, [(some tookC, some parksC), (some parkMissC, some parksC), (some tookC, some parksC)]),
   ("sweeps still run", ⟨.pauses, .v2p, liveStages⟩, [(some sweepRunC, some v2pC)]),
   ("pauses took, in-view sweeps run", ⟨.pauses, .v2p, liveStages⟩, [(some pausesC, some v2pC), (some pausesC, some v2pC), (some pausesC, some v2pC)]),
   ("accent finished", ⟨.both, .pauses, liveStages⟩, [(some accentFinC, some pausesC)]),
   ("comparator v2p without its sources", ⟨.parks, .v2p, liveStages⟩, [(some parksC, some parksC)]),
   ("no census for the arm", ⟨.parks, .v2p, liveStages⟩, [(none, some v2pC)]),
   ("no census for v2p", ⟨.parks, .v2p, liveStages⟩, [(some parksC, none)])]

private def predForCases : List (String × ArmId × Option Census) :=
  [("v2p", .v2p, some v2pC), ("parks", .parks, some parksC), ("pauses", .pauses, some pausesC),
   ("both, in-view sweeps run", .both, some bothC), ("both, nothing runs", .both, some bothClearC), ("both, no census", .both, none)]

private def predEdgeForCases : List (String × Edge × Option Census × Option Census) :=
  [("both against parks, a source remains", ⟨.both, .parks, liveStages⟩, some bothC, some parksC),
   ("both against parks, nothing remains", ⟨.both, .parks, liveStages⟩, some bothClearC, some parksC),
   ("both against pauses, a source remains", ⟨.both, .pauses, liveStages⟩, some bothC, some pausesC),
   ("both against pauses, nothing remains", ⟨.both, .pauses, liveStages⟩, some bothClearC, some pausesC),
   ("parks against v2p", ⟨.parks, .v2p, liveStages⟩, some parksC, some v2pC),
   ("pauses against v2p", ⟨.pauses, .v2p, liveStages⟩, some pausesC, some v2pC),
   ("both against parks, no census", ⟨.both, .parks, liveStages⟩, none, none)]

private def overallPredCases : List (String × Edge × List (Option Census × Option Census)) :=
  [("a source remains in 3 of 3", ⟨.both, .parks, liveStages⟩, [(some bothC, some parksC), (some bothC, some parksC), (some bothC, some parksC)]),
   ("nothing remains in 3 of 3", ⟨.both, .parks, liveStages⟩, [(some bothClearC, some parksC), (some bothClearC, some parksC), (some bothClearC, some parksC)]),
   ("a source remains in 1 of 3", ⟨.both, .parks, liveStages⟩, [(some bothC, some parksC), (some bothClearC, some parksC), (some bothClearC, some parksC)]),
   ("parks against v2p", ⟨.parks, .v2p, liveStages⟩, [(some parksC, some v2pC), (some parksC, some v2pC), (some parksC, some v2pC)])]

private def overallEffectCases : List (String × List String) :=
  [("all took", ["took", "took", "took"]), ("one missing", ["took", "missing:hero.exit:threaded-park", "took"]),
   ("none skipped", ["none", "none", "none"]), ("same missing", ["missing:a", "missing:a", "missing:a"])]

private def overallTierCases : List (String × List Tier) :=
  [("all one", [.one, .one, .one]), ("all two", [.two, .two, .two]), ("one two", [.one, .two, .one]),
   ("one unreadable", [.one, .unreadable, .one]), ("two off", [.one, .off, .off])]

private def wJ (x : Win) : Json := Json.mkObj [("raf", x.raf), ("seen", x.seen), ("recalcs", x.recalcs)]

private def flagsJ (fs : List (String × String)) : Json := Json.arr (fs.map fun (k, v) => Json.arr #[Json.str k, Json.str v]).toArray

private def strsJ (xs : List String) : Json := Json.arr (xs.map Json.str).toArray

private def edgeJ (e : Edge) : List (String × Json) :=
  [("arm", Json.str e.arm.name), ("cmp", Json.str e.cmp.name), ("stages", strsJ e.stages)]

private def censusJ (c : Census) : Json :=
  Json.mkObj [("by", Json.arr (c.byKey.map fun (k, n) => Json.arr #[Json.str k, Json.num n]).toArray), ("running", strsJ c.running),
    ("paused", strsJ c.paused), ("parked", c.parked), ("ut", c.ut), ("utParked", c.utParked),
    ("sweepHidden", match c.sweepHidden with | some n => Json.num n | none => Json.null)]

private def optCensusJ : Option Census → Json
  | some c => censusJ c
  | none => Json.null

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("band", band), ("winRaf", winRaf), ("minSeen", minSeen), ("minRounds", minRounds),
    ("censusCap", censusCap)]).compress] ++
  (allArms.map fun a =>
    (Json.mkObj [("kind", "arm"), ("arm", Json.str a.name), ("sets", flagsJ a.sets), ("flags", flagsJ a.flags),
      ("active", strsJ (a.active.map Flag.name)), ("predTier", Json.str (predTier a).name)]).compress) ++
  (edges.map fun e =>
    (Json.mkObj (("kind", Json.str "edge") :: edgeJ e ++ [("parts", strsJ e.part), ("realParts", strsJ e.realParts),
      ("predicted", Json.str (predEdge e).name)])).compress) ++
  (verdictCases.map fun (n, e, a, c) =>
    (Json.mkObj ([("kind", Json.str "verdict"), ("name", Json.str n)] ++ edgeJ e ++ [("armWin", wJ a), ("cmpWin", wJ c),
      ("verdict", Json.str (edgeOf "b" e a c).name)])).compress) ++
  [(Json.mkObj ([("kind", Json.str "verdict"), ("name", Json.str "other build")] ++ edgeJ ⟨.both, .parks, liveStages⟩ ++
    [("armWin", wJ (w 360 360)), ("cmpWin", wJ (w 360 720)), ("armBuild", Json.str "b1"), ("cmpBuild", Json.str "b2"),
     ("verdict", Json.str (edgeTier "b1" "b2" ArmId.both.sets ArmId.parks.sets (tier (w 360 360)) (tier (w 360 720))).name)])).compress] ++
  (heldCases.map fun (n, o, p) =>
    (Json.mkObj [("kind", "held"), ("name", n), ("overall", Json.str o), ("predicted", Json.str p), ("verdict", Json.str (held o p))]).compress) ++
  (kindCases.map fun n =>
    (Json.mkObj [("kind", "kindOf"), ("name", Json.str n), ("verdict", Json.str (kindOf n).name)]).compress) ++
  (censusCases.map fun (n, c) =>
    (Json.mkObj [("kind", "census"), ("name", n), ("census", censusJ c), ("viewDriven", c.viewDriven), ("scrollDriven", c.scrollDriven),
      ("complete", Json.bool c.complete), ("effects", Json.mkObj (allArms.map fun a => (a.name, Json.str (effectName a c)))),
      ("stillTicks", Json.arr ((stillTicks c).map fun (k, x) => Json.arr #[Json.str k, Json.num x]).toArray),
      ("flags", Json.mkObj (allFlags.map fun f => (f.name, Json.bool (f.took c)))), ("sourceRemains", Json.bool c.sourceRemains),
      ("sweepOnly", Json.bool c.sweepOnly), ("candidate", match candidateOf c with | some n => Json.str n | none => Json.null)]).compress) ++
  (gateCases.map fun (n, v, t) =>
    (Json.mkObj [("kind", "gate"), ("name", n), ("verdict", Json.str v), ("took", Json.bool t), ("gated", Json.str (gate v t))]).compress) ++
  (predForCases.map fun (n, a, c) =>
    (Json.mkObj [("kind", "predFor"), ("name", n), ("arm", Json.str a.name), ("census", optCensusJ c),
      ("tier", Json.str (predTierFor a c).name)]).compress) ++
  (predEdgeForCases.map fun (n, e, ca, cc) =>
    (Json.mkObj (("kind", Json.str "predEdgeFor") :: ("name", Json.str n) :: edgeJ e ++
      [("armCensus", optCensusJ ca), ("cmpCensus", optCensusJ cc), ("predicted", Json.str (predEdgeFor e ca cc).name)])).compress) ++
  (overallPredCases.map fun (n, e, rs) =>
    (Json.mkObj (("kind", Json.str "overallPred") :: ("name", Json.str n) :: edgeJ e ++
      [("rounds", Json.arr (rs.map fun (a, c) => Json.arr #[optCensusJ a, optCensusJ c]).toArray),
       ("predicted", Json.str (overallPred e rs))])).compress) ++
  (heldGatedCases.map fun (n, o, p, t) =>
    (Json.mkObj [("kind", "heldGated"), ("name", n), ("overall", Json.str o), ("predicted", Json.str p), ("took", Json.bool t),
      ("verdict", Json.str (heldGated o p t))]).compress) ++
  (edgeTookCases.map fun (n, e, rs) =>
    (Json.mkObj (("kind", Json.str "edgeTook") :: ("name", Json.str n) :: edgeJ e ++
      [("rounds", Json.arr (rs.map fun (a, c) => Json.arr #[optCensusJ a, optCensusJ c]).toArray), ("took", Json.bool (edgeTook e rs))])).compress) ++
  (overallEffectCases.map fun (n, ns) =>
    (Json.mkObj [("kind", "overallEffect"), ("name", n), ("effects", strsJ ns), ("overall", Json.str (overallEffect ns))]).compress) ++
  (overallTierCases.map fun (n, ts) =>
    (Json.mkObj [("kind", "overallTier"), ("name", n), ("tiers", strsJ (ts.map Tier.name)),
      ("overall", Json.str (overallTier ts))]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "sim-end-cut.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"sim-end-cut golden differs: {goldenPath}")
  IO.println s!"sim-end-cut golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.SimEndCut
