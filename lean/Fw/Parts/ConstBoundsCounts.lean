import Lean.Data.Json
import Fw.Device.PhoneArms
import Fw.Parts.MorphConstBounds
/-! WebKit emits one Layout Timeline record per layout pass, whatever the dirty boxes
(`Source/WebCore/page/LocalFrameViewLayoutContext.cpp:223,335@862f17d`). -/
namespace Fw.Parts.ConstBoundsCounts
open Lean
open Fw.Device.Session (Zone zoneOf Verdict verdict spread)
open Fw.Device.PhoneArms (Label labelOf)

def vh10 : Int := 7750

def maxY10 : Int := 52310

def lastY : Int := 5200

def stepZone (y : Int) : Zone := zoneOf vh10 maxY10 (y * 10)

theorem stepZone_hero {y : Int} (h : y < 1550) : stepZone y = .hero :=
  Fw.Device.Session.zoneOf_hero (by unfold vh10; omega)

theorem stepZone_finish {y : Int} (h : 4456 < y) : stepZone y = .finish :=
  Fw.Device.Session.zoneOf_finish (by unfold vh10; omega) (by unfold vh10 maxY10; omega)

theorem stepZone_rest {y : Int} (h1 : 1550 ≤ y) (h2 : y ≤ 4456) : stepZone y = .rest :=
  Fw.Device.Session.zoneOf_rest (by unfold vh10; omega) (by unfold vh10 maxY10; omega)

def windowYs : List Int := (List.range 105).map fun i => ((i : Nat) : Int) * 50

theorem windowYs_hero : (windowYs.filter fun y => stepZone y == .hero).length = 31 := by decide +kernel

theorem windowYs_finish : (windowYs.filter fun y => stepZone y == .finish).length = 15 := by decide +kernel

theorem windowYs_rest : (windowYs.filter fun y => stepZone y == .rest).length = 59 := by decide +kernel

def inWindow (p : Int × Int) : Bool := decide (p.1 ≤ lastY)

def zoneSum (z : Zone) (steps : List (Int × Int)) : Int :=
  ((steps.filter fun p => inWindow p && stepZone p.1 == z).map (·.2)).sum

def windowTotal (steps : List (Int × Int)) : Int := ((steps.filter inWindow).map (·.2)).sum

theorem zoneSum_split : ∀ steps : List (Int × Int),
    zoneSum .hero steps + zoneSum .finish steps + zoneSum .rest steps = windowTotal steps
  | [] => by simp [zoneSum, windowTotal]
  | b :: bs => by
    have ih := zoneSum_split bs
    unfold zoneSum windowTotal at ih ⊢
    cases hw : inWindow b <;> cases h : stepZone b.1 <;> simp [hw, h] <;> omega

def crVh10 : Int := 9320

def crMaxY10 : Int := 53420

def crZone (y : Int) : Zone := zoneOf crVh10 crMaxY10 (y * 10)

theorem crZone_hero {y : Int} (h : y < 1864) : crZone y = .hero :=
  Fw.Device.Session.zoneOf_hero (by unfold crVh10; omega)

theorem crZone_finish {y : Int} (h : 4410 < y) : crZone y = .finish :=
  Fw.Device.Session.zoneOf_finish (by unfold crVh10; omega) (by unfold crVh10 crMaxY10; omega)

theorem crZone_rest {y : Int} (h1 : 1864 ≤ y) (h2 : y ≤ 4410) : crZone y = .rest :=
  Fw.Device.Session.zoneOf_rest (by unfold crVh10; omega) (by unfold crVh10 crMaxY10; omega)

def crSum (z : Zone) (frames : List (Int × Int)) : Int :=
  ((frames.filter fun p => crZone p.1 == z).map (·.2)).sum

def crTotal (frames : List (Int × Int)) : Int := (frames.map (·.2)).sum

theorem crSum_split : ∀ frames : List (Int × Int),
    crSum .hero frames + crSum .finish frames + crSum .rest frames = crTotal frames
  | [] => by simp [crSum, crTotal]
  | b :: bs => by
    have ih := crSum_split bs
    unfold crSum crTotal at ih ⊢
    cases h : crZone b.1 <;> simp [h] <;> omega

def crMetrics : List String :=
  ["trace.Layout", "metric.LayoutCount", "trace.Layout.dirtyObjects", "trace.InvalidateLayout",
   "trace.UpdateLayoutTree", "metric.RecalcStyleCount", "trace.Paint", "trace.PrePaint", "trace.cc.Commit",
   "trace.FunctionCall", "trace.EventDispatch", "raster.invalidationAreaPx", "census.layers",
   "census.drawingAreaPx"]

structure Cen where
  y : Int
  layers : Int
  mem : Int
  deriving Repr

structure Pass where
  vm : Nat
  pass : Nat
  ys : List Int
  vals : List (String × List Int)
  census : List Cen
  deriving Repr

def Pass.series (p : Pass) (m : String) : List Int := ((p.vals.find? (·.1 == m)).map (·.2)).getD []

def vmsOf (ps : List Pass) : Nat := (ps.map (·.vm)).eraseDups.length

def metrics : List String :=
  ["Layout", "RecalculateStyles", "Paint", "Composite", "FunctionCall", "EventDispatch", "paintArea"]

structure Cell where
  zone : Zone
  metric : String
  reqY : Option Int
  base : List Int
  arm : List Int
  vmsBase : Nat
  vmsArm : Nat
  deriving Repr

def Cell.call (c : Cell) : Verdict := verdict c.base c.arm

def Cell.usable (c : Cell) : Bool := decide (3 ≤ c.vmsBase) && decide (3 ≤ c.vmsArm)

def zones : List Zone := [.hero, .finish, .rest]

def countCells (bp ap : List Pass) : List Cell :=
  zones.flatMap fun z => metrics.map fun m =>
    ⟨z, m, none, bp.map fun p => zoneSum z ((p.ys.zip (p.series m))),
      ap.map fun p => zoneSum z ((p.ys.zip (p.series m))), vmsOf bp, vmsOf ap⟩

def censusYs (bp ap : List Pass) : List Int :=
  ((bp ++ ap).flatMap fun p => p.census.map (·.y)).eraseDups

def atY (y : Int) (ps : List Pass) : List (Pass × Cen) :=
  ps.filterMap fun p => (p.census.find? (·.y == y)).map fun c => (p, c)

def censusCells (bp ap : List Pass) : List Cell :=
  (censusYs bp ap).flatMap fun y =>
    let b := atY y bp
    let a := atY y ap
    [⟨stepZone y, "layers", some y, b.map (·.2.layers), a.map (·.2.layers), vmsOf (b.map (·.1)), vmsOf (a.map (·.1))⟩,
     ⟨stepZone y, "memBytes", some y, b.map (·.2.mem), a.map (·.2.mem), vmsOf (b.map (·.1)), vmsOf (a.map (·.1))⟩]

def crCells (bp ap : List Pass) : List Cell :=
  zones.flatMap fun z => crMetrics.map fun m =>
    ⟨z, m, none, bp.map fun p => crSum z (p.ys.zip (p.series m)),
      ap.map fun p => crSum z (p.ys.zip (p.series m)), vmsOf bp, vmsOf ap⟩

def allCells (bp ap : List Pass) : List Cell := countCells bp ap ++ censusCells bp ap

def zoneCells (z : Zone) (cs : List Cell) : List Cell := cs.filter (·.zone == z)

theorem zoneCells_split : ∀ cs : List Cell,
    (zoneCells .hero cs).length + (zoneCells .finish cs).length + (zoneCells .rest cs).length = cs.length
  | [] => by simp [zoneCells]
  | c :: cs => by
    have ih := zoneCells_split cs
    unfold zoneCells at ih ⊢
    cases h : c.zone <;> simp [h] <;> omega

inductive Outcome where
  | win | trade | cost | noWin | unresolved
  deriving DecidableEq, Repr

def Outcome.name : Outcome → String
  | .win => "win" | .trade => "trade" | .cost => "cost" | .noWin => "no-win" | .unresolved => "unresolved"

def outcomeOf (vs : List Verdict) : Outcome :=
  match labelOf vs with
  | .better => .win | .mixed => .trade | .worse => .cost | .same => .noWin | .unresolved => .unresolved

theorem outcome_win_iff (vs : List Verdict) : outcomeOf vs = .win ↔ .beats ∈ vs ∧ .worse ∉ vs := by
  rw [← Fw.Device.PhoneArms.labelOf_better_iff]
  unfold outcomeOf; cases labelOf vs <;> simp

theorem outcome_cost_iff (vs : List Verdict) : outcomeOf vs = .cost ↔ .worse ∈ vs ∧ .beats ∉ vs := by
  rw [← Fw.Device.PhoneArms.labelOf_worse_iff]
  unfold outcomeOf; cases labelOf vs <;> simp

theorem outcome_trade_iff (vs : List Verdict) : outcomeOf vs = .trade ↔ .beats ∈ vs ∧ .worse ∈ vs := by
  unfold outcomeOf labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

theorem outcome_noWin_iff (vs : List Verdict) : outcomeOf vs = .noWin ↔ .beats ∉ vs ∧ .worse ∉ vs ∧ .same ∈ vs := by
  unfold outcomeOf labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

theorem outcome_unresolved_iff (vs : List Verdict) :
    outcomeOf vs = .unresolved ↔ .beats ∉ vs ∧ .worse ∉ vs ∧ .same ∉ vs := by
  unfold outcomeOf labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

def zoneOutcome (z : Zone) (cs : List Cell) : Outcome := outcomeOf ((zoneCells z cs).map Cell.call)

theorem zoneOutcome_other {z : Zone} {c : Cell} (h : c.zone ≠ z) (cs : List Cell) :
    zoneOutcome z (c :: cs) = zoneOutcome z cs := by
  unfold zoneOutcome zoneCells
  simp [h]

theorem cell_beats_clear {c : Cell} (h : c.call = .beats) : ∀ o ∈ c.base, ∀ a ∈ c.arm, a + spread c.base < o :=
  Fw.Device.Session.verdict_beats_beyond h

theorem cell_worse_clear {c : Cell} (h : c.call = .worse) : ∀ o ∈ c.base, ∀ a ∈ c.arm, o + spread c.base < a :=
  Fw.Device.Session.verdict_worse_beyond h

theorem zone_win_cell {z : Zone} {cs : List Cell} (h : zoneOutcome z cs = .win) :
    ∃ c ∈ cs, c.zone = z ∧ c.call = .beats := by
  have := (outcome_win_iff _).1 h
  obtain ⟨c, hc, e⟩ := List.mem_map.1 this.1
  have := List.mem_filter.1 hc
  exact ⟨c, this.1, by simpa using this.2, e⟩

theorem zone_cost_cell {z : Zone} {cs : List Cell} (h : zoneOutcome z cs = .cost) :
    ∃ c ∈ cs, c.zone = z ∧ c.call = .worse := by
  have := (outcome_cost_iff _).1 h
  obtain ⟨c, hc, e⟩ := List.mem_map.1 this.1
  have := List.mem_filter.1 hc
  exact ⟨c, this.1, by simpa using this.2, e⟩

theorem spread_nonneg (l : List Int) : 0 ≤ spread l := by
  unfold spread
  split
  · rename_i h m e1 e2
    have a := List.max?_eq_some_iff.1 e1
    have b := List.min?_eq_some_iff.1 e2
    have := a.2 m (List.min?_mem e2)
    omega
  · exact Int.le_refl 0

theorem self_not_beats {l : List Int} {x : Int} (hx : x ∈ l) : verdict l l ≠ .beats :=
  Fw.Device.Session.not_beats_within hx hx (by have := spread_nonneg l; omega)

theorem self_not_worse {l : List Int} {x : Int} (hx : x ∈ l) : verdict l l ≠ .worse := by
  intro h
  have := Fw.Device.Session.verdict_worse_beyond h x hx x hx
  have := spread_nonneg l
  omega

theorem self_same {l : List Int} (h : 2 ≤ l.length) : verdict l l = .same := by
  obtain ⟨x, hx⟩ : ∃ x, x ∈ l := by
    cases l with
    | nil => simp at h
    | cons a t => exact ⟨a, List.mem_cons_self⟩
  obtain ⟨lo, e1⟩ := Option.isSome_iff_exists.1 (List.isSome_min?_of_mem hx)
  obtain ⟨hi, e2⟩ := Option.isSome_iff_exists.1 (List.isSome_max?_of_mem hx)
  have hlo := (List.min?_eq_some_iff.1 e1).2 hi (List.max?_mem e2)
  have hs := spread_nonneg l
  exact Fw.Device.Session.verdict_same_of h e1 e2 e1 e2 (by omega) (by omega)

open Fw.Parts.Nav (Vp navHeight pillH panelH)
open Fw.Parts.MorphConstBounds (origBox varBox morphing orig_resizes_h varBox_const)

def layoutDirty (boxes : List Bool) : Bool := boxes.any id

def navChanged (v : Vp) (hp : Bool) (m m' : Rat) : Bool := decide (origBox v hp m ≠ origBox v hp m')

def panelOrigChanged (v : Vp) (hp : Bool) (m m' : Rat) : Bool := decide (origBox v hp m ≠ origBox v hp m')

def panelVarChanged (v : Vp) (hp : Bool) (m m' : Rat) : Bool := decide (varBox v hp m ≠ varBox v hp m')

theorem morph_layout_records_same (v : Vp) (hp : Bool) (hh : pillH v < panelH v) (m m' : Rat) (h : m < m') :
    layoutDirty [navChanged v hp m m', panelOrigChanged v hp m m'] = true ∧
    layoutDirty [navChanged v hp m m', panelVarChanged v hp m m'] = true := by
  have hn : navChanged v hp m m' = true := by
    have lt := orig_resizes_h v hh m m' h
    unfold navChanged origBox
    simp only [decide_eq_true_eq]
    intro e
    have := congrArg Prod.snd e
    simp at this
    grind
  constructor
  · simp [layoutDirty, hn]
  · simp [layoutDirty, hn]

theorem panel_var_const (v : Vp) (hp : Bool) (m m' : Rat) (h : Fw.Parts.Nav.morphingCut < m)
    (h' : Fw.Parts.Nav.morphingCut < m') : panelVarChanged v hp m m' = false := by
  unfold panelVarChanged
  simp [varBox_const v hp m m' h h']

theorem panel_orig_changes (v : Vp) (hp : Bool) (hh : pillH v < panelH v) (m m' : Rat) (h : m < m') :
    panelOrigChanged v hp m m' = true := by
  have lt := orig_resizes_h v hh m m' h
  unfold panelOrigChanged origBox
  simp only [decide_eq_true_eq]
  intro e
  have := congrArg Prod.snd e
  simp at this
  grind

def insetKids : Nat := 4

def kidTop (v : Vp) (m : Rat) : Rat := Fw.Parts.MorphConstBounds.off (Fw.Parts.Nav.panelH v) (navHeight v m)

theorem kid_top_moves (v : Vp) (hh : pillH v < panelH v) (m m' : Rat) (h : m < m') : kidTop v m ≠ kidTop v m' := by
  have lt := orig_resizes_h v hh m m' h
  unfold kidTop Fw.Parts.MorphConstBounds.off
  intro e
  grind

def dirtyObjects (orig : Nat) (kidsMoved : Bool) : Nat := orig + if kidsMoved then insetKids else 0

theorem dirty_gap (orig : Nat) : dirtyObjects orig true = dirtyObjects orig false + insetKids := by
  simp [dirtyObjects]

theorem dirty_gt (orig : Nat) : dirtyObjects orig false < dirtyObjects orig true := by
  simp [dirtyObjects, insetKids]

private def intList (j : Json) : Except String (List Int) := do
  (← j.getArr?).toList.mapM fun x => x.getInt?

def passOfJson (ms : List String) (j : Json) : Except String Pass := do
  let steps ← j.getObjVal? "steps"
  let vals ← ms.mapM fun m => do
    let s ← intList (← steps.getObjVal? m)
    pure (m, s)
  let cen ← (← (← j.getObjVal? "census").getArr?).toList.mapM fun c => do
    let y ← (← c.getObjVal? "y").getInt?
    let layers ← (← c.getObjVal? "layers").getInt?
    let mem ← (← c.getObjVal? "mem").getInt?
    pure ({ y, layers, mem } : Cen)
  pure { vm := ← (← j.getObjVal? "vm").getNat?, pass := ← (← j.getObjVal? "pass").getNat?,
         ys := ← intList (← j.getObjVal? "ys"), vals, census := cen }

structure Input where
  baseRun : String
  flagRun : String
  sha : String
  flag : String
  base : List Pass
  arm : List Pass
  crBaseRun : String
  crFlagRun : String
  crSha : String
  crBase : List Pass
  crArm : List Pass

def inputOfJson (j : Json) : Except String Input := do
  let passes (ms : List String) (k : String) : Except String (List Pass) := do
    (← (← j.getObjVal? k).getArr?).toList.mapM (passOfJson ms)
  pure { baseRun := ← (← j.getObjVal? "baseRun").getStr?, flagRun := ← (← j.getObjVal? "flagRun").getStr?,
         sha := ← (← j.getObjVal? "sha").getStr?, flag := ← (← j.getObjVal? "flag").getStr?,
         base := ← passes metrics "base", arm := ← passes metrics "arm",
         crBaseRun := ← (← j.getObjVal? "crBaseRun").getStr?, crFlagRun := ← (← j.getObjVal? "crFlagRun").getStr?,
         crSha := ← (← j.getObjVal? "crSha").getStr?,
         crBase := ← passes crMetrics "crBase", crArm := ← passes crMetrics "crArm" }

private def verdictName : Verdict → String := Verdict.name

private def crFrames (z : Zone) (ps : List Pass) : Nat :=
  match ps with
  | [] => 0
  | p :: _ => (p.ys.filter fun y => crZone y == z).length

private def count (v : Verdict) (cs : List Cell) : Nat := (cs.filter fun c => c.call == v).length

private def intsJ (l : List Int) : Json := Json.arr (l.map fun i => Json.num (JsonNumber.fromInt i)).toArray

private def cellJ (kind : String) (c : Cell) : Json :=
  Json.mkObj [("kind", kind), ("zone", c.zone.name), ("metric", c.metric),
    ("reqY", match c.reqY with | some y => Json.num (JsonNumber.fromInt y) | none => Json.null),
    ("base", intsJ c.base), ("arm", intsJ c.arm), ("vmsBase", c.vmsBase), ("vmsArm", c.vmsArm),
    ("usable", c.usable), ("verdict", verdictName c.call)]

private def zoneJ (kind : String) (z : Zone) (cs : List Cell) : Json :=
  let zc := zoneCells z cs
  Json.mkObj [("kind", kind), ("zone", z.name), ("outcome", (zoneOutcome z cs).name), ("cells", zc.length),
    ("beats", count .beats zc), ("worse", count .worse zc), ("same", count .same zc),
    ("unresolved", count .unresolved zc), ("thin", (zc.filter fun c => !c.usable).length)]

private def stepCases : List (List (Int × Int)) :=
  [[(0, 1), (1550, 2), (4457, 4), (5200, 8), (5250, 16)], [], [(1549, 5), (1550, 7), (4456, 11), (4457, 13)]]

private def cellCases : List (List Int × List Int) :=
  [([10, 12, 11], [3, 4, 2]), ([10, 12, 11], [20, 22, 21]), ([10, 12, 11], [9, 12, 13]), ([5], [1]), ([10, 12], []),
   ([61, 61, 61], [61, 61, 61]), ([61, 61], [60, 60]), ([100, 140], [100, 150])]

private def outcomeCases : List (List Verdict) :=
  [[.beats, .same], [.beats, .worse, .same], [.worse, .same], [.same, .same], [.unresolved], [], [.beats, .unresolved]]

private def pass (vm n : Nat) (ys vs : List Int) (cen : List Cen) : Pass :=
  ⟨vm, n, ys, [("Layout", vs)], cen⟩

private def censusCase : List Pass × List Pass :=
  ([pass 1 1 [0, 50] [1, 2] [⟨5267, 124, 98⟩], pass 2 1 [0, 50] [1, 2] [⟨5231, 128, 106⟩]],
   [pass 1 1 [0, 50] [3, 4] [⟨5267, 124, 98⟩], pass 3 1 [0, 50] [3, 4] [⟨5267, 124, 98⟩]])

private def pairs : List (Rat × Rat) :=
  (Fw.Parts.MorphConstBounds.samples.drop 2).zip (Fw.Parts.MorphConstBounds.samples.drop 3)

private def jrat (q : Rat) : Json := Json.mkObj [("num", .str (toString q.num)), ("den", .str (toString q.den))]

private def layoutRows : List Json :=
  Fw.Parts.MorphConstBounds.viewports.flatMap fun (w, h) => pairs.map fun (m, m') =>
    let v : Vp := ⟨w, h⟩
    Json.mkObj [("kind", "layout"), ("vw", jrat w), ("vh", jrat h), ("m", jrat m), ("m2", jrat m'),
      ("nav", navChanged v false m m'), ("panelOrig", panelOrigChanged v false m m'),
      ("panelVar", panelVarChanged v false m m'),
      ("layoutOrig", layoutDirty [navChanged v false m m', panelOrigChanged v false m m']),
      ("layoutVar", layoutDirty [navChanged v false m m', panelVarChanged v false m m']),
      ("kidTop", jrat (kidTop v m)), ("kidTop2", jrat (kidTop v m'))]

def goldenLines (inp : Input) : List String :=
  let cs := allCells inp.base inp.arm
  let crc := crCells inp.crBase inp.crArm
  [(Json.mkObj [("kind", "consts"), ("vh10", vh10), ("maxY10", maxY10), ("lastY", lastY),
     ("metrics", Json.arr (metrics.map Json.str).toArray), ("minVms", (3 : Nat)),
     ("heroSteps", (windowYs.filter fun y => stepZone y == .hero).length),
     ("finishSteps", (windowYs.filter fun y => stepZone y == .finish).length),
     ("restSteps", (windowYs.filter fun y => stepZone y == .rest).length)]).compress] ++
  (([0, 1500, 1549, 1550, 3000, 4456, 4457, 4500, 5200, 5231, 5267] : List Int).map fun (y : Int) =>
    (Json.mkObj [("kind", "stepzone"), ("y", (toJson y)), ("zone", (stepZone y).name)]).compress) ++
  (stepCases.map fun st =>
    (Json.mkObj [("kind", "zonesum"), ("steps", Json.arr (st.map fun p => intsJ [p.1, p.2]).toArray),
      ("hero", zoneSum .hero st), ("finish", zoneSum .finish st), ("rest", zoneSum .rest st),
      ("total", windowTotal st)]).compress) ++
  (cellCases.map fun (b, a) =>
    (Json.mkObj [("kind", "verdict"), ("base", intsJ b), ("arm", intsJ a), ("spread", spread b),
      ("verdict", verdictName (verdict b a))]).compress) ++
  (outcomeCases.map fun vs =>
    (Json.mkObj [("kind", "outcome"), ("cells", Json.arr (vs.map fun v => Json.str v.name).toArray),
      ("outcome", (outcomeOf vs).name)]).compress) ++
  ((allCells censusCase.1 censusCase.2).map fun c => (cellJ "censuscase" c).compress) ++
  (layoutRows.map (·.compress)) ++
  (([0, 7, 293] : List Nat).map fun (n : Nat) =>
    (Json.mkObj [("kind", "dirty"), ("orig", n), ("origDirty", dirtyObjects n false), ("varDirty", dirtyObjects n true),
      ("insetKids", insetKids)]).compress) ++
  [(Json.mkObj [("kind", "input"), ("baseRun", inp.baseRun), ("flagRun", inp.flagRun), ("sha", inp.sha),
     ("flag", inp.flag), ("basePasses", inp.base.length), ("armPasses", inp.arm.length),
     ("vmsBase", vmsOf inp.base), ("vmsArm", vmsOf inp.arm)]).compress] ++
  (cs.map fun c => (cellJ "cell" c).compress) ++
  (zones.map fun z => (zoneJ "zone" z cs).compress) ++
  [(Json.mkObj [("kind", "crconsts"), ("crVh10", crVh10), ("crMaxY10", crMaxY10),
     ("crMetrics", Json.arr (crMetrics.map Json.str).toArray)]).compress] ++
  (([0, 1500, 1863, 1864, 3000, 4410, 4411, 5342] : List Int).map fun (y : Int) =>
    (Json.mkObj [("kind", "crzonecase"), ("y", (toJson y)), ("zone", (crZone y).name)]).compress) ++
  (stepCases.map fun st =>
    (Json.mkObj [("kind", "crsumcase"), ("frames", Json.arr (st.map fun p => intsJ [p.1, p.2]).toArray),
      ("hero", crSum .hero st), ("finish", crSum .finish st), ("rest", crSum .rest st),
      ("total", crTotal st)]).compress) ++
  [(Json.mkObj [("kind", "crinput"), ("baseRun", inp.crBaseRun), ("flagRun", inp.crFlagRun), ("sha", inp.crSha),
     ("flag", inp.flag), ("baseRuns", inp.crBase.length), ("armRuns", inp.crArm.length),
     ("framesHero", crFrames .hero inp.crBase), ("framesFinish", crFrames .finish inp.crBase),
     ("framesRest", crFrames .rest inp.crBase)]).compress] ++
  (crc.map fun c => (cellJ "crcell" c).compress) ++
  (zones.map fun z => (zoneJ "crzone" z crc).compress)

private def listS (l : List Int) : String := ", ".intercalate (l.map toString)

private def pad2 (n : Int) : String := if n < 10 then s!"0{n}" else s!"{n}"

def mbS (v : Int) : String :=
  let c := (v + 5000) / 10000
  s!"{c / 100}.{pad2 (c % 100)}"

private def valsS (c : Cell) (l : List Int) : String :=
  if c.metric == "memBytes" then ", ".intercalate (l.map mbS) else listS l

def tableText (inp : Input) : String :=
  let cs := allCells inp.base inp.arm
  let crc := crCells inp.crBase inp.crArm
  let head := s!"Base run {inp.baseRun}, flag `{inp.flag}` run {inp.flagRun}, commit {inp.sha}. " ++
    s!"Passes: base {inp.base.length} from {vmsOf inp.base} VMs, flag {inp.arm.length} from {vmsOf inp.arm} VMs. " ++
    "Cell verdict: the flag passes beat (or lose to) every base pass by more than the base spread; " ++
    "thin = fewer than 3 VMs on a side.\n\n"
  let body := zones.map fun z =>
    let zc := zoneCells z cs
    s!"### {z.name}: {(zoneOutcome z cs).name}\n\n" ++
    s!"beats {count .beats zc}, worse {count .worse zc}, same {count .same zc}, unresolved {count .unresolved zc}, " ++
    s!"thin {(zc.filter fun c => !c.usable).length}\n\n" ++
    "| quantity | at y | base passes | flag passes | VMs base/flag | verdict |\n|---|---|---|---|---|---|\n" ++
    String.join (zc.map fun c =>
      s!"| {c.metric} | {match c.reqY with | some y => toString y | none => "-"} | {valsS c c.base} | {valsS c c.arm} | " ++
      s!"{c.vmsBase}/{c.vmsArm}{if c.usable then "" else " thin"} | {verdictName c.call} |\n") ++ "\n"
  let crHead := s!"## Chromium\n\nBase run {inp.crBaseRun}, flag `{inp.flag}` run {inp.crFlagRun}, commit {inp.crSha}. " ++
    s!"Runs: base {inp.crBase.length}, flag {inp.crArm.length}; frames of a run per zone: hero {crFrames .hero inp.crBase}, " ++
    s!"rest {crFrames .rest inp.crBase}, finish {crFrames .finish inp.crBase}. Sums of the per-frame counts of the zone, one number per run; " ++
    "verdict as above.\n\n"
  let crBody := zones.map fun z =>
    let zc := zoneCells z crc
    s!"### Chromium {z.name}: {(zoneOutcome z crc).name}\n\n" ++
    s!"beats {count .beats zc}, worse {count .worse zc}, same {count .same zc}, unresolved {count .unresolved zc}, " ++
    s!"thin {(zc.filter fun c => !c.usable).length}\n\n" ++
    "| count | base runs | flag runs | runs base/flag | verdict |\n|---|---|---|---|---|\n" ++
    String.join (zc.map fun c =>
      s!"| {c.metric} | {listS c.base} | {listS c.arm} | " ++
      s!"{c.vmsBase}/{c.vmsArm}{if c.usable then "" else " thin"} | {verdictName c.call} |\n") ++ "\n"
  "## WebKit Simulator\n\n" ++ head ++ String.join body ++ crHead ++ String.join crBody

def inputPath : System.FilePath := "../results/const-bounds-counts/cells.json"

def run (args : List String) : IO UInt32 := do
  let txt ← IO.FS.readFile inputPath
  let inp ← match Json.parse txt >>= inputOfJson with
    | .ok i => pure i
    | .error e => throw (IO.userError s!"{inputPath}: {e}")
  let golden := String.join ((goldenLines inp).map (· ++ "\n"))
  match args with
  | "--check" :: g :: t :: _ =>
    let cg ← IO.FS.readFile g
    let ct ← IO.FS.readFile t
    if cg == golden && ct == tableText inp then
      IO.eprintln s!"const-bounds-counts golden: {g} and {t} are up to date ({(goldenLines inp).length} lines)"
      return 0
    IO.eprintln s!"const-bounds-counts golden: {g} or {t} differs from the generated bytes"
    return 1
  | "--table" :: _ =>
    IO.print (tableText inp)
    return 0
  | _ =>
    IO.print golden
    return 0

end Fw.Parts.ConstBoundsCounts
