import Lean.Data.Json
import Fw.Measure.WebKit
import Fw.Device.Session
import Fw.Parts.NavBarFixedWork
/-!
# nav:clip-box, nav:bar-fixed, nav:logo-3d on the WebKit Simulator: the verdict per zone

Raw material: `packages/contracts/golden/parts/nav-fixed-counts.webkit-passes.json`, the per-step counts of the scroll window of each pass (3 VMs, 2 passes each,
per arm), written by `results/nav-fixed-counts/extract.mjs` (I/O only). This module reduces them to per-zone cells, decides each cell of a
flag against the base, and decides the flag per zone from its own cells. Zones are `Fw.Device.Session.zoneOf` (hero: the first two
viewports; finish: the last viewport; rest). Steps above 5200 px are left out: the passes end at 5231 or 5267 and the last steps differ by
the page-height variant of the Simulator.
-/
namespace Fw.Parts.NavFixedCounts
open Lean
open Fw.Measure.WebKit (Tol cellStatus stats stStep absI)
open Fw.Device.Session (Zone zoneOf)

/-! ## The rule on one cell -/

/-- The values of one arm in one cell (one value per pass) and the number of distinct VMs they come from. -/
structure Cell where
  vms : Nat
  vals : List Int
deriving Repr, DecidableEq

/-- Fewer VMs than this in either arm and the cell is not decided. -/
def minVms : Nat := 3

/-- Why a cell is not decided. -/
inductive Why where
  | fewVms
  | quarantined
deriving DecidableEq, Repr

/-- The decision of one cell, flag against base, lower is better. -/
inductive V where
  | win
  | cost
  | same
  | unusable (w : Why)
deriving DecidableEq, Repr

/-- The raw position of the flag's range against the base's range. -/
inductive Raw where
  | below
  | above
  | overlap
  | empty
deriving DecidableEq, Repr

def rawOf (f b : List Int) : Raw :=
  if f.isEmpty || b.isEmpty then .empty
  else if (stats f).2.1 < (stats b).1 then .below
  else if (stats b).2.1 < (stats f).1 then .above
  else .overlap

/-- Not decided when an arm has fewer than `minVms` VMs, or its passes spread beyond the tolerance `t` (class quarantined). -/
def whyNot (t : Tol) (b f : Cell) : Option Why :=
  if b.vms < minVms || f.vms < minVms then some .fewVms
  else if cellStatus t b.vals == 2 || cellStatus t f.vals == 2 then some .quarantined
  else none

/-- Decided cells: win (every flag pass below every base pass), cost (above), same (the ranges overlap). -/
def verdict (t : Tol) (b f : Cell) : V :=
  match whyNot t b f with
  | some w => .unusable w
  | none =>
    match rawOf f.vals b.vals with
    | .below => .win
    | .above => .cost
    | .overlap => .same
    | .empty => .unusable .fewVms

theorem verdict_few_base (t : Tol) (b f : Cell) (h : b.vms < minVms) : verdict t b f = .unusable .fewVms := by
  simp [verdict, whyNot, h]

theorem verdict_few_flag (t : Tol) (b f : Cell) (h : f.vms < minVms) : verdict t b f = .unusable .fewVms := by
  simp [verdict, whyNot, h]

theorem verdict_quarantined_base (t : Tol) (b f : Cell) (hb : ¬ b.vms < minVms) (hf : ¬ f.vms < minVms)
    (h : cellStatus t b.vals = 2) : verdict t b f = .unusable .quarantined := by
  simp [verdict, whyNot, hb, hf, h]

theorem verdict_quarantined_flag (t : Tol) (b f : Cell) (hb : ¬ b.vms < minVms) (hf : ¬ f.vms < minVms)
    (h : cellStatus t f.vals = 2) : verdict t b f = .unusable .quarantined := by
  simp [verdict, whyNot, hb, hf, h]

theorem foldl_bounds : ∀ (vs : List Int) (st : Int × Int × Int),
    (vs.foldl stStep st).1 ≤ st.1 ∧ st.2.1 ≤ (vs.foldl stStep st).2.1 ∧
      ∀ x ∈ vs, (vs.foldl stStep st).1 ≤ x ∧ x ≤ (vs.foldl stStep st).2.1
  | [], st => by simp
  | v :: vs, st => by
    have ih := foldl_bounds vs (stStep st v)
    simp only [List.foldl_cons, stStep] at ih ⊢
    refine ⟨by omega, by omega, ?_⟩
    intro x hx
    rcases List.mem_cons.mp hx with rfl | hx
    · omega
    · exact ih.2.2 x hx

theorem stats_bounds (vs : List Int) (x : Int) (hx : x ∈ vs) : (stats vs).1 ≤ x ∧ x ≤ (stats vs).2.1 := by
  cases vs with
  | nil => simp at hx
  | cons v vs =>
    have h := foldl_bounds vs (v, v, absI v)
    simp only [stats]
    rcases List.mem_cons.mp hx with rfl | hx
    · exact ⟨by simpa using h.1, by simpa using h.2.1⟩
    · exact h.2.2 x hx

theorem rawOf_below {f b : List Int} (h : rawOf f b = .below) : ∀ x ∈ f, ∀ y ∈ b, x < y := by
  intro x hx y hy
  unfold rawOf at h
  split at h
  · cases h
  · rename_i hne
    split at h
    · rename_i hlt
      have := (stats_bounds f x hx).2
      have := (stats_bounds b y hy).1
      omega
    · split at h <;> cases h

theorem rawOf_above {f b : List Int} (h : rawOf f b = .above) : ∀ x ∈ f, ∀ y ∈ b, y < x := by
  intro x hx y hy
  unfold rawOf at h
  split at h
  · cases h
  · split at h
    · cases h
    · rename_i hlt
      split at h
      · rename_i hlt2
        have := (stats_bounds f x hx).1
        have := (stats_bounds b y hy).2
        omega
      · cases h

theorem verdict_win_iff (t : Tol) (b f : Cell) :
    verdict t b f = .win ↔ whyNot t b f = none ∧ rawOf f.vals b.vals = .below := by
  unfold verdict
  cases hw : whyNot t b f with
  | some w => simp
  | none =>
    cases hr : rawOf f.vals b.vals <;> simp

theorem verdict_cost_iff (t : Tol) (b f : Cell) :
    verdict t b f = .cost ↔ whyNot t b f = none ∧ rawOf f.vals b.vals = .above := by
  unfold verdict
  cases hw : whyNot t b f with
  | some w => simp
  | none =>
    cases hr : rawOf f.vals b.vals <;> simp

theorem verdict_same_iff (t : Tol) (b f : Cell) :
    verdict t b f = .same ↔ whyNot t b f = none ∧ rawOf f.vals b.vals = .overlap := by
  unfold verdict
  cases hw : whyNot t b f with
  | some w => simp
  | none =>
    cases hr : rawOf f.vals b.vals <;> simp

/-- A win is certified: both arms have at least three VMs and are inside the tolerance, and every flag pass is below every base pass. -/
theorem win_sound {t : Tol} {b f : Cell} (h : verdict t b f = .win) :
    minVms ≤ b.vms ∧ minVms ≤ f.vms ∧ cellStatus t b.vals ≠ 2 ∧ cellStatus t f.vals ≠ 2 ∧ ∀ x ∈ f.vals, ∀ y ∈ b.vals, x < y := by
  obtain ⟨hw, hr⟩ := (verdict_win_iff t b f).1 h
  unfold whyNot at hw
  refine ⟨?_, ?_, ?_, ?_, rawOf_below hr⟩ <;> split at hw <;> simp_all

/-- A cost is certified the same way, with every flag pass above every base pass. -/
theorem cost_sound {t : Tol} {b f : Cell} (h : verdict t b f = .cost) :
    minVms ≤ b.vms ∧ minVms ≤ f.vms ∧ cellStatus t b.vals ≠ 2 ∧ cellStatus t f.vals ≠ 2 ∧ ∀ x ∈ f.vals, ∀ y ∈ b.vals, y < x := by
  obtain ⟨hw, hr⟩ := (verdict_cost_iff t b f).1 h
  unfold whyNot at hw
  refine ⟨?_, ?_, ?_, ?_, rawOf_above hr⟩ <;> split at hw <;> simp_all

theorem win_cost_exclusive {t : Tol} {b f : Cell} (h : verdict t b f = .win) : verdict t b f ≠ .cost := by
  rw [h]; intro e; cases e

/-- A same cell has overlapping ranges: some flag pass is not below the base's lowest and not above its highest. -/
theorem same_overlap {t : Tol} {b f : Cell} (h : verdict t b f = .same) :
    rawOf f.vals b.vals = .overlap := ((verdict_same_iff t b f).1 h).2

theorem stats_le (vs : List Int) (h : vs.isEmpty = false) : (stats vs).1 ≤ (stats vs).2.1 := by
  cases vs with
  | nil => simp at h
  | cons v vs =>
    have := stats_bounds (v :: vs) v (List.mem_cons_self ..)
    exact Int.le_trans this.1 this.2

/-- Swapping the arms swaps win and cost. -/
theorem verdict_swap_win (t : Tol) (b f : Cell) : verdict t f b = .cost ↔ verdict t b f = .win := by
  rw [verdict_cost_iff, verdict_win_iff]
  have hw : whyNot t f b = whyNot t b f := by
    unfold whyNot
    simp [Bool.or_comm]
  have hr : rawOf b.vals f.vals = .above ↔ rawOf f.vals b.vals = .below := by
    unfold rawOf
    cases hf : f.vals.isEmpty <;> cases hb : b.vals.isEmpty <;> simp
    have := stats_le f.vals hf
    have := stats_le b.vals hb
    by_cases h1 : (stats b.vals).snd.fst < (stats f.vals).fst <;>
      by_cases h2 : (stats f.vals).snd.fst < (stats b.vals).fst <;> simp [h1, h2] <;> omega
  rw [hw, hr]

/-! ## From cells to a flag -/

/-- A flag's decision in one zone: win (a win cell and no cost cell), trade (both), no-win (no win cell). -/
inductive A where
  | win
  | trade
  | noWin
deriving DecidableEq, Repr

def V.isWin : V → Bool
  | .win => true
  | _ => false

def V.isCost : V → Bool
  | .cost => true
  | _ => false

def armOf (vs : List V) : A :=
  if vs.any V.isWin then (if vs.any V.isCost then .trade else .win) else .noWin

theorem any_isWin (vs : List V) : vs.any V.isWin = true ↔ ∃ v ∈ vs, v = .win := by
  simp only [List.any_eq_true]
  constructor
  · rintro ⟨v, hv, h⟩; exact ⟨v, hv, by cases v <;> simp_all [V.isWin]⟩
  · rintro ⟨v, hv, rfl⟩; exact ⟨_, hv, rfl⟩

theorem any_isCost (vs : List V) : vs.any V.isCost = true ↔ ∃ v ∈ vs, v = .cost := by
  simp only [List.any_eq_true]
  constructor
  · rintro ⟨v, hv, h⟩; exact ⟨v, hv, by cases v <;> simp_all [V.isCost]⟩
  · rintro ⟨v, hv, rfl⟩; exact ⟨_, hv, rfl⟩

theorem armOf_win_iff (vs : List V) : armOf vs = .win ↔ (∃ v ∈ vs, v = .win) ∧ ¬ ∃ v ∈ vs, v = .cost := by
  rw [← any_isWin, ← any_isCost]
  unfold armOf
  cases vs.any V.isWin <;> cases vs.any V.isCost <;> simp

theorem armOf_trade_iff (vs : List V) : armOf vs = .trade ↔ (∃ v ∈ vs, v = .win) ∧ ∃ v ∈ vs, v = .cost := by
  rw [← any_isWin, ← any_isCost]
  unfold armOf
  cases vs.any V.isWin <;> cases vs.any V.isCost <;> simp

theorem armOf_noWin_iff (vs : List V) : armOf vs = .noWin ↔ ¬ ∃ v ∈ vs, v = .win := by
  rw [← any_isWin]
  unfold armOf
  cases vs.any V.isWin <;> cases vs.any V.isCost <;> simp


/-- A flag is worth a look review only with a count win in every one of its decided cells and no cost: a trade or a no-win posts nothing. -/
def lookReview : A → Bool
  | .win => true
  | _ => false

theorem lookReview_iff (a : A) : lookReview a = true ↔ a = .win := by
  cases a <;> simp [lookReview]

/-- No count win, no look review. -/
theorem no_win_no_review (vs : List V) (h : ¬ ∃ v ∈ vs, v = .win) : lookReview (armOf vs) = false := by
  have := (armOf_noWin_iff vs).2 h
  simp [this, lookReview]

/-! ## The raw passes -/

/-- One pass of one VM: the step positions, the four counts of each step (Layout, RecalculateStyles, FunctionCall, Composite) and the
census as (requested y, layers, backing bytes). -/
structure Pass where
  vm : Nat
  vh : Nat
  maxY : Int
  ys : List Int
  steps : List (List Int)
  census : List (Int × Int × Int)
deriving Repr

structure ArmData where
  arm : String
  run : Nat
  passes : List Pass
deriving Repr

private def listOf (j : Json) (k : String) : Except String (List Json) := do
  pure (← (← j.getObjVal? k).getArr?).toList

private def intList (j : Json) : Except String (List Int) := do
  (← j.getArr?).toList.mapM (·.getInt?)

private def decPass (j : Json) : Except String Pass := do
  let vm ← (← j.getObjVal? "vm").getNat?
  let vh ← (← j.getObjVal? "vh").getNat?
  let maxY ← (← j.getObjVal? "maxY").getInt?
  let ys ← intList (← j.getObjVal? "ys")
  let steps ← (← listOf j "steps").mapM intList
  let census ← (← listOf j "census").mapM fun r => do
    match ← intList r with
    | [a, b, c] => pure (a, b, c)
    | _ => throw "census row"
  pure ⟨vm, vh, maxY, ys, steps, census⟩

def decode (text : String) : Except String (List ArmData) := do
  let j ← Json.parse text
  (← listOf j "arms").mapM fun a => do
    let arm ← (← a.getObjVal? "arm").getStr?
    let run ← (← a.getObjVal? "run").getNat?
    let passes ← (← listOf a "passes").mapM decPass
    pure ⟨arm, run, passes⟩

def rawText : String := include_str "../../../packages/contracts/golden/parts/nav-fixed-counts.webkit-passes.json"

def data : List ArmData := (decode rawText).toOption.getD []

def armData (name : String) : Option ArmData := data.find? (·.arm == name)

/-! ## Zone sums -/

/-- Steps above this are left out (the passes end at 5231 or 5267, a page-height variant of the Simulator). -/
def lastStep : Int := 5200

def stepZone (p : Pass) (y : Int) : Zone := zoneOf ((p.vh : Int) * 10) (p.maxY * 10) (y * 10)

def kept (p : Pass) : List (Int × List Int) := (p.ys.zip p.steps).filter fun s => s.1 ≤ lastStep

def workVal (p : Pass) (z : Zone) (i : Nat) : Int :=
  (((kept p).filter fun s => stepZone p s.1 == z).map fun s => s.2.getD i 0).sum

def totalVal (p : Pass) (i : Nat) : Int := ((kept p).map fun s => s.2.getD i 0).sum

theorem zone_partition {α : Type} (zf : α → Zone) (g : α → Int) (l : List α) :
    ((l.filter fun a => zf a == .hero).map g).sum + ((l.filter fun a => zf a == .finish).map g).sum +
      ((l.filter fun a => zf a == .rest).map g).sum = (l.map g).sum := by
  induction l with
  | nil => simp
  | cons a l ih =>
    cases h : zf a <;> simp [h] <;> omega

/-- The three zones' sums add up to the pass's sum: every kept step is in exactly one zone. -/
theorem workVal_partition (p : Pass) (i : Nat) :
    workVal p .hero i + workVal p .finish i + workVal p .rest i = totalVal p i := by
  unfold workVal totalVal
  exact zone_partition (fun s => stepZone p s.1) (fun s => s.2.getD i 0) (kept p)

/-! ## Cells -/

inductive Metric where
  | layout
  | recalc
  | functionCall
  | composite
  | layers
  | bytes
deriving DecidableEq, Repr

def Metric.name : Metric → String
  | .layout => "Layout"
  | .recalc => "RecalculateStyles"
  | .functionCall => "FunctionCall"
  | .composite => "Composite"
  | .layers => "layers"
  | .bytes => "backingBytes"

/-- The index of the metric in a step's four counts. -/
def Metric.stepIx : Metric → Nat
  | .layout => 0
  | .recalc => 1
  | .functionCall => 2
  | .composite => 3
  | _ => 0

/-- The lane's tolerances (`packages/measure-webkit/src/reduce.mjs`): zone sums, census layer counts, backing memory. -/
def Metric.tol : Metric → Tol
  | .layers => ⟨1, 1 / 20⟩
  | .bytes => ⟨0, 1 / 50⟩
  | _ => ⟨2, 1 / 10⟩

/-- One cell: a zone and a metric; a census cell also names the requested scroll position of its state. -/
structure CellId where
  zone : Zone
  metric : Metric
  y : Option Int
deriving DecidableEq, Repr

def censusMaxY (p : Pass) : Int := (p.census.getLast?.map (·.1)).getD 0

def censusZone (p : Pass) (y : Int) : Zone := zoneOf ((p.vh : Int) * 10) (censusMaxY p * 10) (y * 10)

/-- The census state a cell names: the one requested at `y`, or, for `endState`, the pass's last one (its y differs with the page-height
variant of the Simulator, 5231 or 5267, so the end state is matched by position, not by y). -/
def endState : Int := -1

def censusEntry (p : Pass) (y : Int) : Option (Int × Int × Int) :=
  if y == endState then p.census.getLast? else p.census.find? (·.1 == y)

/-- A pass's value in a cell, if the pass has one: a census state belongs to the cell only when the pass puts it in the cell's zone. -/
def sample (p : Pass) (c : CellId) : Option Int :=
  match c.y with
  | none => some (workVal p c.zone c.metric.stepIx)
  | some y =>
    match censusEntry p y with
    | some e => if censusZone p e.1 == c.zone then some (if c.metric == .layers then e.2.1 else e.2.2) else none
    | none => none

def cellOf (a : ArmData) (c : CellId) : Cell :=
  let s := a.passes.filterMap fun p => (sample p c).map (p.vm, ·)
  ⟨(s.map (·.1)).eraseDups.length, s.map (·.2)⟩

def zones : List Zone := [.hero, .rest, .finish]

def Zone.label (z : Zone) : String := z.name

def workCells : List CellId :=
  zones.flatMap fun z => [Metric.layout, .recalc, .functionCall, .composite].map fun m => ⟨z, m, none⟩

/-- The census states of all arms, as (zone, requested y), lowest y first, the end state last. -/
def censusStates : List (Zone × Int) :=
  let all := data.flatMap fun a => a.passes.flatMap fun p => p.census.dropLast.map fun e => (censusZone p e.1, e.1)
  (all.eraseDups.mergeSort fun a b => a.2 ≤ b.2) ++ [(.finish, endState)]

def censusCells : List CellId :=
  censusStates.flatMap fun s => [Metric.layers, .bytes].map fun m => ⟨s.1, m, some s.2⟩

def cells : List CellId := workCells ++ censusCells

def flags : List String := ["clip-box", "bar-fixed", "logo-3d"]

def cellVerdict (flag : String) (c : CellId) : V :=
  match armData "base", armData flag with
  | some b, some f => verdict c.metric.tol (cellOf b c) (cellOf f c)
  | _, _ => .unusable .fewVms

/-- A flag's decision in one zone, from its own cells against the base. -/
def zoneVerdict (flag : String) (z : Zone) : A :=
  armOf ((cells.filter (·.zone == z)).map (cellVerdict flag))

def flagVerdict (flag : String) : A := armOf (cells.map (cellVerdict flag))

/-! ## Chromium bands

The filed Chromium runs (`swipe-touch-v1`, 3 runs per arm) sum the trace counts per 500 px band of the scroll
(`packages/contracts/golden/parts/nav-fixed-counts.chromium-bands.json`, written by `extract-chromium.mjs`). The bands are mapped to zones by hand: the first
bands and the load frames are the hero, the last band and the tail are the finish, the bands between are the rest. -/

structure CPass where
  vm : Nat
  bands : List (String × List Int)
deriving Repr

structure CArm where
  arm : String
  run : Nat
  passes : List CPass
deriving Repr

private def decCPass (j : Json) : Except String CPass := do
  let vm ← (← j.getObjVal? "vm").getNat?
  let bands ← (← listOf j "bands").mapM fun b => do
    pure ((← (← b.getObjVal? "id").getStr?), ← intList (← b.getObjVal? "v"))
  pure ⟨vm, bands⟩

def decodeC (text : String) : Except String (List CArm) := do
  let j ← Json.parse text
  (← listOf j "arms").mapM fun a => do
    let arm ← (← a.getObjVal? "arm").getStr?
    let run ← (← a.getObjVal? "run").getNat?
    let passes ← (← listOf a "passes").mapM decCPass
    pure ⟨arm, run, passes⟩

def chromiumText : String := include_str "../../../packages/contracts/golden/parts/nav-fixed-counts.chromium-bands.json"

def cdata : List CArm := (decodeC chromiumText).toOption.getD []

def carmData (name : String) : Option CArm := cdata.find? (·.arm == name)

def bandZone (id : String) : Zone :=
  if id == "y05000" || id == "tail" then .finish
  else if id == "rest" || id == "settle" || id == "y00000" || id == "y00500" || id == "y01000" || id == "y01500" then .hero
  else .rest

/-- The five Chromium counts, in the order of the band file: `Layout`, `UpdateLayoutTree` (the style recalculations), `FunctionCall`,
`cc.Draw` (the draws, the closest count to a WebKit `Composite`) and the layer census summed over the frames. -/
inductive CMetric where
  | layout
  | recalc
  | functionCall
  | draw
  | layers
deriving DecidableEq, Repr

def CMetric.ix : CMetric → Nat
  | .layout => 0
  | .recalc => 1
  | .functionCall => 2
  | .draw => 3
  | .layers => 4

def CMetric.name : CMetric → String
  | .layout => "Layout"
  | .recalc => "UpdateLayoutTree"
  | .functionCall => "FunctionCall"
  | .draw => "cc.Draw"
  | .layers => "census.layers"

def CMetric.tol : CMetric → Tol
  | .layers => ⟨1, 1 / 20⟩
  | _ => ⟨2, 1 / 10⟩

def cmetrics : List CMetric := [.layout, .recalc, .functionCall, .draw, .layers]

def csample (p : CPass) (z : Zone) (m : CMetric) : Int :=
  (((p.bands.filter fun b => bandZone b.1 == z).map fun b => b.2.getD m.ix 0)).sum

def ccellOf (a : CArm) (z : Zone) (m : CMetric) : Cell :=
  ⟨(a.passes.map (·.vm)).eraseDups.length, a.passes.map (csample · z m)⟩

def ccellVerdict (flag : String) (z : Zone) (m : CMetric) : V :=
  match carmData "base", carmData flag with
  | some b, some f => verdict m.tol (ccellOf b z m) (ccellOf f z m)
  | _, _ => .unusable .fewVms

def czoneVerdict (flag : String) (z : Zone) : A := armOf (cmetrics.map (ccellVerdict flag z))

def cflagVerdict (flag : String) : A := armOf (zones.flatMap fun z => cmetrics.map (ccellVerdict flag z))

/-! ## Why the counts do not move (model) -/

open Fw.Engine.WebKit (Policy) in
/-- Layout units queued by one morph frame: the panel, the bar and the logo. The panel is placed by the insets in every flag arm;
`bar-fixed` moves the bar by `translate` and `logo-3d` moves the logo by `translate3d`, which Normal compositing takes off the layout
(`NavBarFixedWork.bar_layout_normal`, `logo3d_layout_normal`); the original resizes the nav every frame (`NavBarFixed.barWOrig_resizes`). -/
def unitsPerFrame : NavBarFixedWork.Arm → Policy → List Nat
  | .faithful, _ => [1]
  | .clipBox, _ => [NavBarFixedWork.layoutUnits NavBarFixedWork.barInsetFrame, NavBarFixedWork.layoutUnits NavBarFixedWork.barInsetFrame,
      NavBarFixedWork.layoutUnits NavBarFixedWork.logoLeftFrame]
  | .barFixed, p => [NavBarFixedWork.layoutUnits NavBarFixedWork.barInsetFrame, NavBarFixedWork.layoutUnits (NavBarFixedWork.barTranslateFrame p),
      NavBarFixedWork.layoutUnits ⟨0, 0, 0, 0, [⟨1, .transform, .layer⟩], 0⟩]
  | .logo3d, p => [NavBarFixedWork.layoutUnits NavBarFixedWork.barInsetFrame, NavBarFixedWork.layoutUnits (NavBarFixedWork.barTranslateFrame p),
      NavBarFixedWork.layoutUnits (NavBarFixedWork.logo3dFrame p)]

/-- A morph frame has one layout pass (one `Layout` record) when any unit is queued, none otherwise. -/
def passes (units : List Nat) : Nat := if units.sum = 0 then 0 else 1

/-- Normal compositing: the layout units fall from 3 (clip-box) to 2 (bar-fixed) to 1 (logo-3d). -/
theorem units_fall_normal :
    (unitsPerFrame .clipBox .normal).sum = 3 ∧ (unitsPerFrame .barFixed .normal).sum = 2 ∧
      (unitsPerFrame .logo3d .normal).sum = 1 := by
  decide +kernel

/-- Every arm queues a layout pass in every morph frame, under both policies: the panel's inset is a unit the arms keep, so the
`Layout` record count per morph frame is 1 in every arm and a lane that counts records cannot see the units fall. -/
theorem pass_every_arm (a : NavBarFixedWork.Arm) (p : Fw.Engine.WebKit.Policy) : passes (unitsPerFrame a p) = 1 := by
  cases a <;> cases p <;> decide +kernel

/-- Fewer units, equal passes. -/
theorem units_fall_passes_equal :
    (unitsPerFrame .logo3d .normal).sum < (unitsPerFrame .clipBox .normal).sum ∧
      passes (unitsPerFrame .logo3d .normal) = passes (unitsPerFrame .clipBox .normal) := by
  refine ⟨by decide +kernel, ?_⟩
  rw [pass_every_arm, pass_every_arm]

/-- The model's prediction for the four counts of every zone is "equal"; a certified win or cost cell refutes it. -/
def refutes : V → Bool
  | .win => true
  | .cost => true
  | _ => false

theorem refutes_iff (v : V) : refutes v = true ↔ v = .win ∨ v = .cost := by
  cases v <;> simp [refutes]

/-- The layers a flag adds while the morph class is on (`NavBarFixedWork.added`): at most 1, 2 and 3 for the three arms. The finish zone is
where the class stays on after the morph (`NavClipBox.used_eq_rest_one`), so this is the most the finish census can gain. -/
def addedLayers (a : NavBarFixedWork.Arm) : Nat := (NavBarFixedWork.added a 0 0).length

theorem addedLayers_arms :
    addedLayers .clipBox = 1 ∧ addedLayers .barFixed = 2 ∧ addedLayers .logo3d = 3 := by
  decide +kernel

/-- Adding `d ≥ 0` to every value of a cell is never read as a win. -/
theorem shift_not_below (b : List Int) (d : Int) (hd : 0 ≤ d) (hb : b ≠ []) : rawOf (b.map (· + d)) b ≠ .below := by
  intro h
  obtain ⟨y, hy⟩ := List.exists_mem_of_ne_nil b hb
  have := rawOf_below h (y + d) (List.mem_map.2 ⟨y, hy, rfl⟩) y hy
  omega

/-- Adding `d` to every value of a cell is read as a cost only when `d` exceeds the cell's own spread `hi - lo`: a layer census that
varies by 4 between passes cannot show the 3 layers a flag adds. -/
theorem shift_not_above (b : List Int) (d lo hi : Int) (hlo : lo ∈ b) (hhi : hi ∈ b) (h : d ≤ hi - lo) :
    rawOf (b.map (· + d)) b ≠ .above := by
  intro hr
  have := rawOf_above hr (lo + d) (List.mem_map.2 ⟨lo, hlo, rfl⟩) hi hhi
  omega

/-- The base's end-state layer census of the finish zone. -/
def baseEndLayers : List Int :=
  match armData "base" with
  | some b => (cellOf b ⟨.finish, .layers, some endState⟩).vals
  | none => []

/-- The spread of the base's end-state layer census, 4 in the filed passes, is at least the 3 layers the largest arm adds, so no arm's
end-state layer cell can be certified from the filed passes whatever the arm adds. -/
def endSpread : Int := (stats baseEndLayers).2.1 - (stats baseEndLayers).1

/-! ## Golden -/

private def jstr (s : String) : Json := .str s

def whyName : Why → String
  | .fewVms => "fewVms"
  | .quarantined => "quarantined"

def vName : V → String
  | .win => "win"
  | .cost => "cost"
  | .same => "same"
  | .unusable _ => "unusable"

def vWhy : V → Json
  | .unusable w => .str (whyName w)
  | _ => .null

def rawName : Raw → String
  | .below => "below"
  | .above => "above"
  | .overlap => "overlap"
  | .empty => "empty"

def aName : A → String
  | .win => "win"
  | .trade => "trade"
  | .noWin => "noWin"

private def jint (i : Int) : Json := .num (.fromInt i)

private def cellJson (c : Cell) (t : Tol) : Json :=
  Json.mkObj [("vms", .num (.fromNat c.vms)), ("vals", .arr (c.vals.map jint).toArray), ("status", .num (.fromNat (cellStatus t c.vals)))]

def cellLine (flag : String) (c : CellId) : String :=
  match armData "base", armData flag with
  | some b, some f =>
    let cb := cellOf b c
    let cf := cellOf f c
    (Json.mkObj [("fn", jstr "cell"), ("flag", jstr flag), ("zone", jstr c.zone.name), ("metric", jstr c.metric.name),
      ("y", match c.y with | some y => jint y | none => .null), ("base", cellJson cb c.metric.tol), ("flagArm", cellJson cf c.metric.tol),
      ("raw", jstr (rawName (rawOf cf.vals cb.vals))), ("verdict", jstr (vName (cellVerdict flag c))),
      ("why", vWhy (cellVerdict flag c))]).compress
  | _, _ => ""

def zoneLine (flag : String) (z : Zone) : String :=
  (Json.mkObj [("fn", jstr "zone"), ("flag", jstr flag), ("zone", jstr z.name), ("verdict", jstr (aName (zoneVerdict flag z))),
    ("review", .bool (lookReview (zoneVerdict flag z)))]).compress

def flagLine (flag : String) : String :=
  (Json.mkObj [("fn", jstr "flag"), ("flag", jstr flag), ("verdict", jstr (aName (flagVerdict flag))),
    ("review", .bool (lookReview (flagVerdict flag)))]).compress

def ccellLine (flag : String) (z : Zone) (m : CMetric) : String :=
  match carmData "base", carmData flag with
  | some b, some f =>
    let cb := ccellOf b z m
    let cf := ccellOf f z m
    (Json.mkObj [("fn", jstr "ccell"), ("flag", jstr flag), ("zone", jstr z.name), ("metric", jstr m.name),
      ("base", cellJson cb m.tol), ("flagArm", cellJson cf m.tol), ("raw", jstr (rawName (rawOf cf.vals cb.vals))),
      ("verdict", jstr (vName (ccellVerdict flag z m))), ("why", vWhy (ccellVerdict flag z m))]).compress
  | _, _ => ""

def czoneLine (flag : String) (z : Zone) : String :=
  (Json.mkObj [("fn", jstr "czone"), ("flag", jstr flag), ("zone", jstr z.name), ("verdict", jstr (aName (czoneVerdict flag z))),
    ("review", .bool (lookReview (czoneVerdict flag z)))]).compress

def cflagLine (flag : String) : String :=
  (Json.mkObj [("fn", jstr "cflag"), ("flag", jstr flag), ("verdict", jstr (aName (cflagVerdict flag))),
    ("review", .bool (lookReview (cflagVerdict flag)))]).compress

def lines : List String :=
  flags.flatMap fun f =>
    (cells.map (cellLine f)) ++ (zones.map (zoneLine f)) ++ [flagLine f] ++
      (zones.flatMap fun z => cmetrics.map (ccellLine f z)) ++ (zones.map (czoneLine f)) ++ [cflagLine f]

def jsonl : String := String.join ((lines.filter (· ≠ "")).map (· ++ "\n"))

/-! ## What the raw files must hold

Lake does not track `include_str`, so a cached build can outlive a changed data file. These guards name the runs and the passes the files
hold; changing a file means changing them here, and so the module's source. -/

#guard data.map (fun a => (a.arm, a.run, a.passes.length)) ==
  [("base", 40196215217, 6), ("clip-box", 40196217959, 4), ("bar-fixed", 40196221086, 6), ("logo-3d", 40196212618, 6)]
#guard cdata.map (fun a => (a.arm, a.run, a.passes.length)) ==
  [("base", 40171939293, 3), ("clip-box", 40171943772, 3), ("bar-fixed", 40171960215, 3), ("logo-3d", 40171946109, 3)]
#guard data.all fun a => a.passes.all fun p => p.vh == 775 && p.ys.length == p.steps.length
#guard 3 ≤ endSpread

/-! The golden is this module's own output (written from `jsonl`, never by hand). -/
#guard jsonl == include_str "../../../packages/contracts/golden/parts/nav-fixed-counts.jsonl"

end Fw.Parts.NavFixedCounts
