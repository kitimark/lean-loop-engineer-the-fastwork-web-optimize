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
  deriving DecidableEq, Repr

def censusCap : Nat := 24

def Census.complete (c : Census) : Bool := c.running.length < censusCap && c.paused.length < censusCap

def Census.sumKeys (c : Census) (pre : String) : Nat :=
  (c.byKey.filter fun (k, _) => hasPrefix pre k).foldl (fun s (_, n) => s + n) 0

def Census.viewDriven (c : Census) : Nat := c.sumKeys "view:"

def Census.scrollDriven (c : Census) : Nat := c.sumKeys "scroll:"

def Census.runningOf (c : Census) (k : Kind) : Nat := (c.running.filter fun n => kindOf n == k).length

inductive Flag where
  | heroPark
  | scrollPark
  | accentPause
  | cuePause
  | sweepPause
  deriving DecidableEq, Repr

def Flag.name : Flag → String
  | .heroPark => "hero.exit:threaded-park" | .scrollPark => "engine.scroll:unthrottle-park"
  | .accentPause => "hero.accent:offscreen-pause" | .cuePause => "hero.cue:offscreen-pause"
  | .sweepPause => "platform.sweep:offscreen-pause"

def pauseTook (c : Census) (k : Kind) : Bool := c.complete && c.runningOf k == 0

def Flag.took (c : Census) : Flag → Bool
  | .heroPark => c.viewDriven == 0
  | .scrollPark => c.scrollDriven == 0
  | .accentPause => pauseTook c .accent
  | .cuePause => pauseTook c .cue
  | .sweepPause => pauseTook c .sweep

def ArmId.active (a : ArmId) : List Flag :=
  (if a.hasParks then [Flag.heroPark, .scrollPark] else []) ++ (if a.hasPauses then [Flag.accentPause, .cuePause, .sweepPause] else [])

theorem active_v2p : ArmId.v2p.active = [] := by decide

theorem active_parks : ArmId.parks.active = [.heroPark, .scrollPark] := by decide

theorem active_pauses : ArmId.pauses.active = [.accentPause, .cuePause, .sweepPause] := by decide

theorem active_both : ArmId.both.active = [.heroPark, .scrollPark, .accentPause, .cuePause, .sweepPause] := by decide

def missing (a : ArmId) (c : Census) : List String := (a.active.filter fun f => !f.took c).map Flag.name

def effectName (a : ArmId) (c : Census) : String :=
  if a.active.isEmpty then "none" else if (missing a c).isEmpty then "took" else "missing:" ++ String.intercalate "," (missing a c)

theorem effect_none (c : Census) : effectName .v2p c = "none" := by simp [effectName, active_v2p]

theorem effect_took (a : ArmId) (c : Census) (h0 : a.active.isEmpty = false) (h : missing a c = []) : effectName a c = "took" := by
  simp [effectName, h0, h]

theorem effect_missing (a : ArmId) (c : Census) (h0 : a.active.isEmpty = false) (h : (missing a c).isEmpty = false) :
    effectName a c = "missing:" ++ String.intercalate "," (missing a c) := by
  simp [effectName, h0, h]

theorem heroPark_took_iff (c : Census) : Flag.took c .heroPark = true ↔ c.viewDriven = 0 := by simp [Flag.took]

theorem scrollPark_took_iff (c : Census) : Flag.took c .scrollPark = true ↔ c.scrollDriven = 0 := by simp [Flag.took]

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

theorem sideTook_v2p (c : Option Census) : sideTook .v2p c = true := by simp [sideTook, active_v2p]

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
private def idles : List String := ["accent-module_idle0_t7SI92", "accent-module_idle1_a3NQoa", "accent-module_idle2_Q1MyP3"]
private def cue : String := "cue-module_scrollFloat_6RFPnC"
private def fin : List (String × Nat) := [("document:finished", 20), ("document:paused", 7)]

private def censusCases : List (String × Census) :=
  [("v2p at the end", ⟨fin ++ [("view:finished", 13), ("scroll:finished", 1), ("document:running", 8)], idles ++ [cue] ++ sweeps, []⟩),
   ("parks took", ⟨fin ++ [("document:running", 8)], idles ++ [cue] ++ sweeps, []⟩),
   ("hero park missed", ⟨fin ++ [("view:finished", 13), ("document:running", 8)], idles ++ [cue] ++ sweeps, []⟩),
   ("scroll park missed", ⟨fin ++ [("scroll:running", 1)], idles ++ [cue] ++ sweeps, []⟩),
   ("pauses took", ⟨fin ++ [("document:paused", 15)], [], idles ++ [cue] ++ sweeps⟩),
   ("sweeps still run", ⟨fin, sweeps, idles ++ [cue]⟩),
   ("cue still runs", ⟨fin, [cue], idles ++ sweeps⟩),
   ("accent finished", ⟨fin, [], [cue] ++ sweeps⟩), ("accent running", ⟨fin, idles, [cue] ++ sweeps⟩),
   ("running list full", ⟨fin, List.replicate 24 "wave-module_x", idles ++ [cue] ++ sweeps⟩),
   ("both took", ⟨fin, [], idles ++ [cue] ++ sweeps⟩),
   ("both, other loops run", ⟨fin, ["glint-module_dash", "glint-module_dash"], idles ++ [cue] ++ sweeps⟩)]

private def heldGatedCases : List (String × String × String × Bool) :=
  [("held and took", "cut:pauses", "cut:pauses", true), ("missed and took", "noEffect:pauses", "cut:pauses", true),
   ("inconclusive and took", "inconclusive", "cut:pauses", true), ("held, flag did not engage", "cut:pauses", "cut:pauses", false),
   ("missed, flag did not engage", "noEffect:pauses", "cut:pauses", false), ("mixed, flag did not engage", "mixed", "cut:pauses", false)]

private def tookC : Census := ⟨fin, [], idles ++ [cue] ++ sweeps⟩
private def v2pC : Census := ⟨fin ++ [("view:finished", 13), ("scroll:finished", 1)], idles ++ [cue] ++ sweeps, []⟩
private def parkMissC : Census := ⟨fin ++ [("view:finished", 13)], [], idles ++ [cue] ++ sweeps⟩
private def sweepRunC : Census := ⟨fin, sweeps, idles ++ [cue]⟩
private def accentFinC : Census := ⟨fin, [], [cue] ++ sweeps⟩

private def edgeTookCases : List (String × Edge × List (Option Census × Option Census)) :=
  [("parks and v2p took", ⟨.parks, .v2p, liveStages⟩, [(some tookC, some v2pC), (some tookC, some v2pC), (some tookC, some v2pC)]),
   ("hero park missed", ⟨.parks, .v2p, liveStages⟩, [(some parkMissC, some v2pC)]),
   ("one round missed", ⟨.both, .parks, liveStages⟩, [(some tookC, some tookC), (some parkMissC, some tookC), (some tookC, some tookC)]),
   ("sweeps still run", ⟨.pauses, .v2p, liveStages⟩, [(some sweepRunC, some v2pC)]),
   ("accent finished", ⟨.both, .pauses, liveStages⟩, [(some accentFinC, some accentFinC)]),
   ("no census for the arm", ⟨.parks, .v2p, liveStages⟩, [(none, some v2pC)]),
   ("no census for v2p", ⟨.parks, .v2p, liveStages⟩, [(some tookC, none)])]

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
    ("paused", strsJ c.paused)]

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
      ("stillTicks", Json.arr ((stillTicks c).map fun (k, x) => Json.arr #[Json.str k, Json.num x]).toArray)]).compress) ++
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
