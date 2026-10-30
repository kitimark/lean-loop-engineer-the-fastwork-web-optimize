import Lean.Data.Json
import Fw.Ops.Attrib
import Fw.Device.SimEndFloor

/-! # sim-floor-attrib: per-arm verdict of the Simulator end-of-page recalc rate against one named comparator -/
namespace Fw.Device.SimFloorAttrib

open Lean Fw.Device.SimEndFloor Fw.Device.EndWktr

inductive ArmId where
  | base
  | v2p
  | minusT
  | minusU
  | blank
  | minusBoth
  | v2pCancelScroll
  deriving DecidableEq, Repr

def ArmId.name : ArmId → String
  | .base => "base" | .v2p => "v2p" | .minusT => "minusT" | .minusU => "minusU" | .blank => "blank"
  | .minusBoth => "minusBoth" | .v2pCancelScroll => "v2pCancelScroll"

def allArms : List ArmId := [.base, .v2p, .minusT, .minusU, .blank, .minusBoth, .v2pCancelScroll]

def scrollPart : String := "engine.scroll"
def heroPart : String := "hero.exit"
def platformPart : String := "platform"

def v2pFlags : List (String × String) := [(scrollPart, "unthrottle"), (heroPart, "threaded"), (platformPart, "faded-pause")]

def ArmId.flags : ArmId → List (String × String)
  | .base => []
  | .v2p => v2pFlags
  | .minusT => [(scrollPart, "unthrottle"), (platformPart, "faded-pause")]
  | .minusU => [(heroPart, "threaded"), (platformPart, "faded-pause")]
  | .blank => [("content", "blank")]
  | .minusBoth => [(platformPart, "faded-pause")]
  | .v2pCancelScroll => v2pFlags ++ [("scrollAnimations", "cancelled")]

inductive Tier where
  | unreadable
  | zero
  | one
  | two
  | off
  deriving DecidableEq, Repr

def Tier.name : Tier → String
  | .unreadable => "unreadable" | .zero => "zero" | .one => "one" | .two => "two" | .off => "off"

def Tier.rank : Tier → Nat
  | .unreadable => 0 | .zero => 0 | .one => 1 | .two => 2 | .off => 3

def tier (w : Win) : Tier :=
  if !w.readable then .unreadable
  else if w.rate ≤ band then .zero
  else if 100 - band ≤ w.rate ∧ w.rate ≤ 100 + band then .one
  else if 200 - band ≤ w.rate ∧ w.rate ≤ 200 + band then .two
  else .off

theorem tier_unreadable (w : Win) (h : w.readable = false) : tier w = .unreadable := by simp [tier, h]

theorem tier_zero (w : Win) (h0 : w.readable = true) (h : w.rate ≤ band) : tier w = .zero := by simp [tier, h0, h]

theorem tier_one (w : Win) (h0 : w.readable = true) (h1 : ¬ w.rate ≤ band) (h : 100 - band ≤ w.rate ∧ w.rate ≤ 100 + band) :
    tier w = .one := by simp [tier, h0, h1, h]

theorem tier_two (w : Win) (h0 : w.readable = true) (h1 : ¬ w.rate ≤ band) (h2 : ¬ (100 - band ≤ w.rate ∧ w.rate ≤ 100 + band))
    (h : 200 - band ≤ w.rate ∧ w.rate ≤ 200 + band) : tier w = .two := by
  unfold tier
  have := h0
  split <;> (try split) <;> (try split) <;> (try split) <;> simp_all <;> omega

theorem tier_off (w : Win) (h0 : w.readable = true) (h1 : ¬ w.rate ≤ band) (h2 : ¬ (100 - band ≤ w.rate ∧ w.rate ≤ 100 + band))
    (h3 : ¬ (200 - band ≤ w.rate ∧ w.rate ≤ 200 + band)) : tier w = .off := by
  unfold tier
  have := h0
  split <;> (try split) <;> (try split) <;> (try split) <;> simp_all <;> omega

inductive EdgeV where
  | unreadable
  | offGrid
  | notAttributable
  | noEffect (part : String)
  | cut (part : String)
  | raised (part : String)
  deriving DecidableEq, Repr

def EdgeV.name : EdgeV → String
  | .unreadable => "unreadable" | .offGrid => "offGrid" | .notAttributable => "notAttributable"
  | .noEffect p => "noEffect:" ++ p | .cut p => "cut:" ++ p | .raised p => "raised:" ++ p

def runOf (build : String) (a : ArmId) (pass : Bool) : Fw.Ops.Attrib.Run := ⟨build, a.flags, pass⟩

def edge (buildArm buildCmp : String) (arm cmpArm : ArmId) (wa wc : Win) : EdgeV :=
  if tier wa = .unreadable ∨ tier wc = .unreadable then .unreadable
  else if tier wa = .off ∨ tier wc = .off then .offGrid
  else match Fw.Ops.Attrib.verdict (runOf buildCmp cmpArm true) (runOf buildArm arm (tier wa == tier wc)) with
    | .notAttributable => .notAttributable
    | .noEffect p => .noEffect p
    | .causedBy p _ _ => if (tier wa).rank < (tier wc).rank then .cut p else .raised p

theorem edge_unreadable (ba bc : String) (a c : ArmId) (wa wc : Win) (h : tier wa = .unreadable ∨ tier wc = .unreadable) :
    edge ba bc a c wa wc = .unreadable := by simp [edge, h]

theorem edge_offGrid (ba bc : String) (a c : ArmId) (wa wc : Win) (h0 : ¬ (tier wa = .unreadable ∨ tier wc = .unreadable))
    (h : tier wa = .off ∨ tier wc = .off) : edge ba bc a c wa wc = .offGrid := by simp [edge, h0, h]

theorem edge_notAttributable (ba bc : String) (a c : ArmId) (wa wc : Win) (h0 : ¬ (tier wa = .unreadable ∨ tier wc = .unreadable))
    (h1 : ¬ (tier wa = .off ∨ tier wc = .off))
    (h : Fw.Ops.Attrib.verdict (runOf bc c true) (runOf ba a (tier wa == tier wc)) = .notAttributable) :
    edge ba bc a c wa wc = .notAttributable := by simp [edge, h0, h1, h]

theorem edge_other_build (ba bc : String) (a c : ArmId) (wa wc : Win) (hb : ba ≠ bc)
    (h0 : ¬ (tier wa = .unreadable ∨ tier wc = .unreadable)) (h1 : ¬ (tier wa = .off ∨ tier wc = .off)) :
    edge ba bc a c wa wc = .notAttributable := by
  apply edge_notAttributable ba bc a c wa wc h0 h1
  exact Fw.Ops.Attrib.other_commit_not_attributable _ _ (by simpa [runOf] using hb.symm)

theorem edge_noEffect (b : String) (a c : ArmId) (wa wc : Win) (p : String) (h0 : ¬ (tier wa = .unreadable ∨ tier wc = .unreadable))
    (h1 : ¬ (tier wa = .off ∨ tier wc = .off)) (hd : Fw.Ops.Attrib.delta c.flags a.flags = [p]) (hs : tier wa = tier wc) :
    edge b b a c wa wc = .noEffect p := by
  have hv : Fw.Ops.Attrib.verdict (runOf b c true) (runOf b a (tier wa == tier wc)) = .noEffect p :=
    Fw.Ops.Attrib.noEffect_of_same_outcome _ _ p rfl hd (by simp [runOf, hs])
  simp [edge, h0, h1, hv]

theorem edge_cut (b : String) (a c : ArmId) (wa wc : Win) (p : String) (h0 : ¬ (tier wa = .unreadable ∨ tier wc = .unreadable))
    (h1 : ¬ (tier wa = .off ∨ tier wc = .off)) (hd : Fw.Ops.Attrib.delta c.flags a.flags = [p]) (hne : tier wa ≠ tier wc)
    (hlt : (tier wa).rank < (tier wc).rank) : edge b b a c wa wc = .cut p := by
  have hv := Fw.Ops.Attrib.causedBy_of_fail_second (runOf b c true) (runOf b a (tier wa == tier wc)) p rfl hd rfl
    (by simpa [runOf] using hne)
  simp [edge, h0, h1, hv, hlt]

theorem edge_raised (b : String) (a c : ArmId) (wa wc : Win) (p : String) (h0 : ¬ (tier wa = .unreadable ∨ tier wc = .unreadable))
    (h1 : ¬ (tier wa = .off ∨ tier wc = .off)) (hd : Fw.Ops.Attrib.delta c.flags a.flags = [p]) (hne : tier wa ≠ tier wc)
    (hge : ¬ (tier wa).rank < (tier wc).rank) : edge b b a c wa wc = .raised p := by
  have hv := Fw.Ops.Attrib.causedBy_of_fail_second (runOf b c true) (runOf b a (tier wa == tier wc)) p rfl hd rfl
    (by simpa [runOf] using hne)
  simp [edge, h0, h1, hv, hge]

structure Edge where
  arm : ArmId
  cmp : ArmId
  stages : List String
  deriving DecidableEq, Repr

def allStages : List String := ["end", "back", "paused"]

def edges : List Edge :=
  [⟨.blank, .base, allStages⟩, ⟨.minusBoth, .base, allStages⟩, ⟨.minusBoth, .v2p, allStages⟩, ⟨.minusBoth, .minusT, allStages⟩,
   ⟨.minusBoth, .minusU, allStages⟩, ⟨.v2pCancelScroll, .v2p, ["paused"]⟩]

def Edge.part (e : Edge) : List String := Fw.Ops.Attrib.delta e.cmp.flags e.arm.flags

theorem blank_base_content : (Edge.mk .blank .base allStages).part = ["content"] := by decide

theorem minusBoth_base_platform : (Edge.mk .minusBoth .base allStages).part = ["platform"] := by decide

theorem minusBoth_minusT_scroll : (Edge.mk .minusBoth .minusT allStages).part = ["engine.scroll"] := by decide

theorem minusBoth_minusU_hero : (Edge.mk .minusBoth .minusU allStages).part = ["hero.exit"] := by decide

theorem cancel_v2p_scrollAnimations : (Edge.mk .v2pCancelScroll .v2p ["paused"]).part = ["scrollAnimations"] := by decide

theorem minusBoth_v2p_two_parts : (Edge.mk .minusBoth .v2p allStages).part = ["engine.scroll", "hero.exit"] := by decide

theorem minusBoth_v2p_notAttributable (b : String) (wa wc : Win) (h0 : ¬ (tier wa = .unreadable ∨ tier wc = .unreadable))
    (h1 : ¬ (tier wa = .off ∨ tier wc = .off)) : edge b b .minusBoth .v2p wa wc = .notAttributable := by
  have hd : Fw.Ops.Attrib.delta ArmId.v2p.flags ArmId.minusBoth.flags = ["engine.scroll", "hero.exit"] := by decide
  exact edge_notAttributable b b .minusBoth .v2p wa wc h0 h1 (Fw.Ops.Attrib.two_parts_not_attributable _ _ _ _ hd)

theorem edges_one_part_but_one : ∀ e ∈ edges, e.part.length = 1 ∨ e = ⟨.minusBoth, .v2p, allStages⟩ := by decide

def edgeOf (build : String) (e : Edge) (wa wc : Win) : EdgeV := edge build build e.arm e.cmp wa wc

def overallEdge (vs : List EdgeV) : String :=
  overallNames ((vs.filter fun v => v != .unreadable && v != .offGrid).map EdgeV.name)

theorem overallEdge_inconclusive (vs : List EdgeV) (h : (vs.filter fun v => v != .unreadable && v != .offGrid).length < minRounds) :
    overallEdge vs = "inconclusive" := by
  simpa [overallEdge] using overallNames_inconclusive _ (by simpa [minRounds] using h)

def overallTier (ts : List Tier) : String :=
  overallNames ((ts.filter fun t => t != .unreadable && t != .off).map Tier.name)

theorem overallTier_inconclusive (ts : List Tier) (h : (ts.filter fun t => t != .unreadable && t != .off).length < minRounds) :
    overallTier ts = "inconclusive" := by
  simpa [overallTier] using overallNames_inconclusive _ (by simpa [minRounds] using h)

private def w (seen recalcs : Nat) : Win := ⟨winRaf, seen, recalcs⟩

private def tierCases : List (String × Win) :=
  [("raf differs", ⟨100, 100, 100⟩), ("too few seen", w 100 360), ("zero", w 360 0), ("at the band", w 360 36),
   ("one above the band", w 360 40), ("below one", w 360 320), ("one low edge", w 360 324), ("one", w 360 360),
   ("one high edge", w 360 396), ("above one", w 360 400), ("below two", w 360 680), ("two low edge", w 360 684),
   ("two", w 360 720), ("two high edge", w 360 756), ("above two", w 360 760)]

private def edgeCases : List (String × Edge × Win × Win) :=
  [("blank reads zero against one", ⟨.blank, .base, ["paused"]⟩, w 360 0, w 360 360),
   ("blank reads one against one", ⟨.blank, .base, ["paused"]⟩, w 360 360, w 360 360),
   ("blank reads two against one", ⟨.blank, .base, ["paused"]⟩, w 360 720, w 360 360),
   ("minusBoth one against one", ⟨.minusBoth, .base, ["paused"]⟩, w 360 360, w 360 360),
   ("minusBoth two against one", ⟨.minusBoth, .base, ["paused"]⟩, w 360 720, w 360 360),
   ("minusBoth against v2p, two parts", ⟨.minusBoth, .v2p, ["paused"]⟩, w 360 360, w 360 720),
   ("minusBoth against v2p, same tier, two parts", ⟨.minusBoth, .v2p, ["paused"]⟩, w 360 720, w 360 720),
   ("minusBoth against minusT cut", ⟨.minusBoth, .minusT, ["paused"]⟩, w 360 360, w 360 720),
   ("minusBoth against minusU same", ⟨.minusBoth, .minusU, ["paused"]⟩, w 360 720, w 360 720),
   ("cancel against v2p cut", ⟨.v2pCancelScroll, .v2p, ["paused"]⟩, w 360 360, w 360 720),
   ("cancel against v2p same", ⟨.v2pCancelScroll, .v2p, ["paused"]⟩, w 360 720, w 360 720),
   ("cancel against v2p raised", ⟨.v2pCancelScroll, .v2p, ["paused"]⟩, w 360 720, w 360 360),
   ("unreadable arm window", ⟨.v2pCancelScroll, .v2p, ["paused"]⟩, ⟨360, 100, 360⟩, w 360 720),
   ("unreadable comparator window", ⟨.v2pCancelScroll, .v2p, ["paused"]⟩, w 360 360, ⟨360, 100, 720⟩),
   ("arm off the grid", ⟨.v2pCancelScroll, .v2p, ["paused"]⟩, w 360 540, w 360 720),
   ("comparator off the grid", ⟨.v2pCancelScroll, .v2p, ["paused"]⟩, w 360 360, w 360 540),
   ("same arm twice, zero parts", ⟨.v2p, .v2p, ["paused"]⟩, w 360 720, w 360 720),
   ("base against v2p, three parts", ⟨.base, .v2p, ["paused"]⟩, w 360 360, w 360 720)]

private def overallEdgeCases : List (String × List EdgeV) :=
  [("all cut", [.cut "scrollAnimations", .cut "scrollAnimations", .cut "scrollAnimations"]),
   ("one noEffect", [.cut "scrollAnimations", .noEffect "scrollAnimations", .cut "scrollAnimations"]),
   ("one unreadable", [.cut "scrollAnimations", .unreadable, .cut "scrollAnimations"]),
   ("two off the grid", [.cut "scrollAnimations", .offGrid, .offGrid]),
   ("all notAttributable", [.notAttributable, .notAttributable, .notAttributable])]

private def overallTierCases : List (String × List Tier) :=
  [("all one", [.one, .one, .one]), ("one two", [.one, .two, .one]), ("one unreadable", [.zero, .unreadable, .zero]),
   ("two off", [.zero, .off, .off])]

private def wJ (x : Win) : Json := Json.mkObj [("raf", x.raf), ("seen", x.seen), ("recalcs", x.recalcs)]

private def flagsJ (fs : List (String × String)) : Json := Json.arr (fs.map fun (k, v) => Json.arr #[Json.str k, Json.str v]).toArray

private def edgeJ (e : Edge) : List (String × Json) :=
  [("arm", Json.str e.arm.name), ("cmp", Json.str e.cmp.name), ("stages", Json.arr (e.stages.map Json.str).toArray)]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("band", band), ("winRaf", winRaf), ("minSeen", minSeen), ("minRounds", minRounds)]).compress] ++
  (allArms.map fun a =>
    (Json.mkObj [("kind", "arm"), ("arm", Json.str a.name), ("flags", flagsJ a.flags)]).compress) ++
  (tierCases.map fun (n, x) =>
    (Json.mkObj [("kind", "tier"), ("name", n), ("win", wJ x), ("rate", x.rate), ("verdict", Json.str (tier x).name)]).compress) ++
  (edges.map fun e =>
    (Json.mkObj (("kind", Json.str "edge") :: edgeJ e ++ [("parts", Json.arr (e.part.map Json.str).toArray)])).compress) ++
  (edgeCases.map fun (n, e, a, c) =>
    (Json.mkObj ([("kind", Json.str "verdict"), ("name", Json.str n)] ++ edgeJ e ++ [("armWin", wJ a), ("cmpWin", wJ c),
      ("verdict", Json.str (edgeOf "b" e a c).name)])).compress) ++
  [(Json.mkObj ([("kind", Json.str "verdict"), ("name", Json.str "other build")] ++ edgeJ ⟨.v2pCancelScroll, .v2p, ["paused"]⟩ ++
    [("armWin", wJ (w 360 360)), ("cmpWin", wJ (w 360 720)), ("armBuild", Json.str "b1"), ("cmpBuild", Json.str "b2"),
     ("verdict", Json.str (edge "b1" "b2" .v2pCancelScroll .v2p (w 360 360) (w 360 720)).name)])).compress] ++
  (overallEdgeCases.map fun (n, vs) =>
    (Json.mkObj [("kind", "overallEdge"), ("name", n), ("verdicts", Json.arr (vs.map fun v => Json.str v.name).toArray),
      ("overall", Json.str (overallEdge vs))]).compress) ++
  (overallTierCases.map fun (n, ts) =>
    (Json.mkObj [("kind", "overallTier"), ("name", n), ("tiers", Json.arr (ts.map fun t => Json.str t.name).toArray),
      ("overall", Json.str (overallTier ts))]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "sim-floor-attrib.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"sim-floor-attrib golden differs: {goldenPath}")
  IO.println s!"sim-floor-attrib golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.SimFloorAttrib
