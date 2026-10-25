import Lean.Data.Json
import Fw.Device.PhoneArms
/-!
# morph.mount:shift-dormant: the verdict per zone and engine from filed counts

Task dormant-counts; note research/notes/2026/10-2x-dormant-counts.md. The input is
`results/dormant-counts/zones.json`, written by `results/dormant-counts/reduce.mjs` from the filed runs: per sample, the
count sums per 500 px bin and (WebKit) the layer census per scroll state. This module decides, per engine, zone (hero,
finish, rest) and metric, whether an arm beats, loses to or equals the base, and `gen` writes the decisions as the golden
`packages/contracts/golden/parts/dormant-counts.jsonl`.

A sample is one Simulator VM (summed over its passes) or one Chromium counts run. A cell is judged by
`Fw.Device.Session.verdict`: the arm beats the base only when its worst sample is clear of the base's best sample by more
than the base's sample-to-sample spread, and loses only the other way round. A step under `minPercent` of the larger value
is then no win or loss. A zone is `win` when some decided cell beats and none loses, `trade` when one beats and one
loses, `noWin` otherwise, and `unresolved` when no cell has two base samples.
-/
namespace Fw.Parts.DormantCounts

open Lean
open Fw.Device.Session (Zone zoneOf Verdict verdict spread)
open Fw.Device.PhoneArms (zoneSum labelOf Label)

/-! ## Data -/

/-- One layer-census state of one VM, summed over its passes. -/
structure Census where
  y : Int
  layers : Int
  bytes : Int
  deriving DecidableEq, Repr

/-- One VM's page geometry in tenths of a pixel: viewport height and the last scroll position. -/
structure Geo where
  vh10 : Int
  maxY10 : Int
  deriving DecidableEq, Repr

/-- One Simulator VM: count sums per metric and 500 px bin (the bin's first scroll position), and the census. The last
scroll position differs between VMs of one run, so each VM carries its own geometry. -/
structure Vm where
  geo : Geo
  bins : List (String × List (Int × Int))
  census : List Census
  deriving Repr

/-- What a cell counts: a trace count (or `paintArea`) per bin, the layers of the census states, or their backing bytes. -/
inductive Metric where
  | bin (name : String)
  | layers
  | bytes
  deriving DecidableEq, Repr

def Metric.name : Metric → String
  | .bin n => n
  | .layers => "layerCount"
  | .bytes => "backingBytes"

/-! ## Cells -/

/-- The census states whose scroll position lies in the zone, summed by `f`. -/
def censusSum (g : Geo) (z : Zone) (f : Census → Int) (cs : List Census) : Int :=
  ((cs.filter fun c => zoneOf g.vh10 g.maxY10 (c.y * 10) == z).map f).sum

/-- A VM's value in the zone for the metric. -/
def Vm.value (z : Zone) : Metric → Vm → Int
  | .bin n, v => zoneSum v.geo.vh10 v.geo.maxY10 z (((v.bins.find? (·.1 == n)).map (·.2)).getD [])
  | .layers, v => censusSum v.geo z (·.layers) v.census
  | .bytes, v => censusSum v.geo z (·.bytes) v.census

/-- The cell's values, one per VM. -/
def column (z : Zone) (m : Metric) (vms : List Vm) : List Int := vms.map (Vm.value z m)

/-- A step smaller than this share (percent) of the larger value is not a win or a loss, even when no spread hides it. -/
def minPercent : Int := 1

/-- Every base value and every arm value differ by at least `minPercent` of the larger of the two. -/
def material (bs xs : List Int) : Bool :=
  bs.all fun o => xs.all fun a =>
    (if o ≥ a then o - a else a - o) * 100 ≥ minPercent * (if o ≥ a then o else a)

/-- The sample verdict, kept only when its step is material. Lower is better, as for every count. -/
def judge (bs xs : List Int) : Verdict :=
  match verdict bs xs with
  | .beats => if material bs xs then .beats else .same
  | .worse => if material bs xs then .worse else .same
  | v => v

def cellVerdict (z : Zone) (m : Metric) (base arm : List Vm) : Verdict :=
  judge (column z m base) (column z m arm)

theorem judge_beats {bs xs : List Int} (h : judge bs xs = .beats) :
    verdict bs xs = .beats ∧ material bs xs = true := by
  unfold judge at h
  split at h <;> rename_i hv <;> simp_all <;> split at h <;> simp_all

theorem judge_worse {bs xs : List Int} (h : judge bs xs = .worse) :
    verdict bs xs = .worse ∧ material bs xs = true := by
  unfold judge at h
  split at h <;> rename_i hv <;> simp_all <;> split at h <;> simp_all

/-- An unresolved sample verdict stays unresolved. -/
theorem judge_unresolved {bs xs : List Int} (h : verdict bs xs = .unresolved) : judge bs xs = .unresolved := by
  simp [judge, h]

inductive Engine where
  | webkit | chromium
  deriving DecidableEq, Repr

def Engine.name : Engine → String
  | .webkit => "webkit" | .chromium => "chromium"

/-- The metrics a zone is decided on. WebKit: the four trace counts and the two census figures the task names.
Chromium: layout, style (UpdateLayoutTree), script (FunctionCall) and compositor commits from the trace, and the layers
and drawing layers of the per-frame census (summed over the frames of the zone). -/
def decided : Engine → List Metric
  | .webkit => [.bin "Layout", .bin "RecalculateStyles", .bin "FunctionCall", .bin "Composite", .layers, .bytes]
  | .chromium => [.bin "trace.Layout", .bin "trace.UpdateLayoutTree", .bin "trace.FunctionCall", .bin "trace.Commit",
      .bin "census.layers", .bin "census.drawingLayers"]

/-- Metrics shown beside them and never part of a decision. -/
def reported : Engine → List Metric
  | .webkit => [.bin "Paint", .bin "FireAnimationFrame", .bin "EventDispatch", .bin "paintArea"]
  | .chromium => [.bin "trace.Paint", .bin "trace.FireAnimationFrame", .bin "trace.EventDispatch",
      .bin "raster.invalidationAreaPx", .bin "census.drawingAreaPx"]

def zones : List Zone := [.hero, .finish, .rest]

def zoneVerdicts (ms : List Metric) (z : Zone) (base arm : List Vm) : List Verdict :=
  ms.map fun m => cellVerdict z m base arm

-- The census states of the page (scroll positions 0, 1500, 3000, 4500 and the last) fall in these zones.
#guard [0, 1500, 3000, 4500, 5267].map (fun (y : Int) => zoneOf 7750 52670 (y * 10)) ==
  [Zone.hero, .hero, .rest, .finish, .finish]

/-! ## The decision -/

/-- A zone's outcome for an arm against the base. -/
inductive Outcome where
  | win | trade | noWin | unresolved
  deriving DecidableEq, Repr

def Outcome.name : Outcome → String
  | .win => "win" | .trade => "trade" | .noWin => "no-win" | .unresolved => "unresolved"

def outcomeOf (vs : List Verdict) : Outcome :=
  match labelOf vs with
  | .better => .win
  | .mixed => .trade
  | .worse => .noWin
  | .same => .noWin
  | .unresolved => .unresolved

def zoneOutcome (ms : List Metric) (z : Zone) (base arm : List Vm) : Outcome := outcomeOf (zoneVerdicts ms z base arm)

/-- The whole page: every decided cell of every zone. -/
def engineOutcome (ms : List Metric) (base arm : List Vm) : Outcome :=
  outcomeOf (zones.flatMap fun z => zoneVerdicts ms z base arm)

/-- Fewer VMs than this in a cell is reported with its number. -/
def minVms : Nat := 3

def short (n : Nat) : Bool := n < minVms

theorem outcomeOf_win_iff (vs : List Verdict) : outcomeOf vs = .win ↔ .beats ∈ vs ∧ .worse ∉ vs := by
  unfold outcomeOf labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

theorem outcomeOf_trade_iff (vs : List Verdict) : outcomeOf vs = .trade ↔ .beats ∈ vs ∧ .worse ∈ vs := by
  unfold outcomeOf labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

/-- No-win by losing: no cell beats and some cell loses. -/
theorem outcomeOf_noWin_of_worse {vs : List Verdict} (h1 : .beats ∉ vs) (h2 : .worse ∈ vs) : outcomeOf vs = .noWin := by
  simp [outcomeOf, labelOf, h1, h2]

/-- No-win by equality: no cell beats or loses and some cell is the same. -/
theorem outcomeOf_noWin_of_same {vs : List Verdict} (h1 : .beats ∉ vs) (h2 : .worse ∉ vs) (h3 : .same ∈ vs) :
    outcomeOf vs = .noWin := by
  simp [outcomeOf, labelOf, h1, h2, h3]

theorem outcomeOf_noWin_iff (vs : List Verdict) :
    outcomeOf vs = .noWin ↔ .beats ∉ vs ∧ (.worse ∈ vs ∨ .same ∈ vs) := by
  unfold outcomeOf labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

theorem outcomeOf_unresolved_iff (vs : List Verdict) :
    outcomeOf vs = .unresolved ↔ .beats ∉ vs ∧ .worse ∉ vs ∧ .same ∉ vs := by
  unfold outcomeOf labelOf
  by_cases h1 : Verdict.beats ∈ vs <;> by_cases h2 : Verdict.worse ∈ vs <;> by_cases h3 : Verdict.same ∈ vs <;>
    simp [h1, h2, h3]

theorem outcomeOf_unresolved_of_all {vs : List Verdict} (h : ∀ v ∈ vs, v = .unresolved) :
    outcomeOf vs = .unresolved := by
  rw [outcomeOf_unresolved_iff]
  refine ⟨fun hm => ?_, fun hm => ?_, fun hm => ?_⟩ <;> have := h _ hm <;> simp at this

/-- A cell with fewer than two base VMs has no spread to judge against. -/
theorem cellVerdict_unresolved_short (z : Zone) (m : Metric) (base arm : List Vm)
    (h : base.length < 2) : cellVerdict z m base arm = .unresolved := by
  unfold cellVerdict column
  exact judge_unresolved (Fw.Device.Session.verdict_unresolved_single _ (by simpa using h))

theorem zoneOutcome_unresolved_short (ms : List Metric) (z : Zone) (base arm : List Vm) (h : base.length < 2) :
    zoneOutcome ms z base arm = .unresolved := by
  apply outcomeOf_unresolved_of_all
  intro v hv
  unfold zoneVerdicts at hv
  obtain ⟨m, _, rfl⟩ := List.mem_map.1 hv
  exact cellVerdict_unresolved_short z m base arm h

/-- Fewer than two base VMs is always reported with its number. -/
theorem short_of_lt_two {n : Nat} (h : n < 2) : short n = true := by
  unfold short minVms
  exact decide_eq_true (by omega)

/-- A win has a cell where every arm VM is below every base VM by more than the base's spread. -/
theorem zoneOutcome_win_cell {ms : List Metric} {z : Zone} {base arm : List Vm} (h : zoneOutcome ms z base arm = .win) :
    ∃ m ∈ ms, ∀ o ∈ column z m base, ∀ a ∈ column z m arm, a + spread (column z m base) < o := by
  have hb := ((outcomeOf_win_iff _).1 h).1
  unfold zoneVerdicts at hb
  obtain ⟨m, hm, he⟩ := List.mem_map.1 hb
  exact ⟨m, hm, Fw.Device.Session.verdict_beats_beyond (judge_beats he).1⟩

/-- A trade has a cell that wins and a cell that loses. -/
theorem zoneOutcome_trade_cells {ms : List Metric} {z : Zone} {base arm : List Vm} (h : zoneOutcome ms z base arm = .trade) :
    (∃ m ∈ ms, cellVerdict z m base arm = .beats) ∧ (∃ m ∈ ms, cellVerdict z m base arm = .worse) := by
  obtain ⟨hb, hw⟩ := (outcomeOf_trade_iff _).1 h
  unfold zoneVerdicts at hb hw
  obtain ⟨m, hm, he⟩ := List.mem_map.1 hb
  obtain ⟨m', hm', he'⟩ := List.mem_map.1 hw
  exact ⟨⟨m, hm, he⟩, ⟨m', hm', he'⟩⟩

/-- A losing cell has every arm VM above every base VM by more than the base's spread. -/
theorem zoneVerdicts_worse_cell {ms : List Metric} {z : Zone} {base arm : List Vm} (hw : .worse ∈ zoneVerdicts ms z base arm) :
    ∃ m ∈ ms, ∀ o ∈ column z m base, ∀ a ∈ column z m arm, o + spread (column z m base) < a := by
  unfold zoneVerdicts at hw
  obtain ⟨m, hm, he⟩ := List.mem_map.1 hw
  exact ⟨m, hm, Fw.Device.Session.verdict_worse_beyond (judge_worse he).1⟩

/-! ## The zones partition a VM's counts -/

theorem censusSum_split (g : Geo) (f : Census → Int) :
    ∀ cs : List Census, censusSum g .hero f cs + censusSum g .finish f cs + censusSum g .rest f cs = (cs.map f).sum
  | [] => by simp [censusSum]
  | c :: cs => by
    have ih := censusSum_split g f cs
    unfold censusSum at ih ⊢
    cases h : zoneOf g.vh10 g.maxY10 (c.y * 10) <;> simp [h] <;> omega

/-- Every metric's three zone values add up to the VM's total. -/
theorem value_split (m : Metric) (v : Vm) :
    v.value .hero m + v.value .finish m + v.value .rest m =
      match m with
      | .bin n => ((((v.bins.find? (·.1 == n)).map (·.2)).getD []).map (·.2)).sum
      | .layers => (v.census.map (·.layers)).sum
      | .bytes => (v.census.map (·.bytes)).sum := by
  cases m with
  | bin n => exact Fw.Device.PhoneArms.zoneSum_split v.geo.vh10 v.geo.maxY10 _
  | layers => exact censusSum_split v.geo _ v.census
  | bytes => exact censusSum_split v.geo _ v.census

/-! ## Cases that pin each branch -/

private def col (bs as : List Int) : Verdict := judge bs as

#guard col [100, 104, 108] [10, 11, 12] == .beats
#guard col [100, 104, 108] [200, 210, 220] == .worse
#guard col [100, 104, 108] [101, 106, 112] == .same
#guard col [788, 788, 788] [787, 787, 787] == .same
#guard col [1000, 1000, 1000] [990, 990, 990] == .beats
#guard col [1000, 1000, 1000] [1020, 1020, 1020] == .worse
#guard col [100] [10] == .unresolved
#guard col [100, 104, 108] [] == .unresolved
#guard outcomeOf [.beats, .same, .unresolved] == .win
#guard outcomeOf [.beats, .worse] == .trade
#guard outcomeOf [.worse, .same] == .noWin
#guard outcomeOf [.same, .unresolved] == .noWin
#guard outcomeOf [.unresolved, .unresolved] == .unresolved
#guard outcomeOf [] == .unresolved

def caseColumns : List (String × List Int × List Int) :=
  [("beats", [100, 104, 108], [10, 11, 12]), ("worse", [100, 104, 108], [200, 210, 220]),
   ("same", [100, 104, 108], [101, 106, 112]), ("one-base-vm", [100], [10]), ("no-arm-vm", [100, 104, 108], []),
   ("edge-not-clear", [100, 104, 108], [91, 92, 92]), ("clear-but-immaterial", [788, 788, 788], [787, 787, 787]),
   ("material-one-percent", [1000, 1000, 1000], [990, 990, 990])]

def caseOutcomes : List (String × List Verdict) :=
  [("win", [.beats, .same, .unresolved]), ("trade", [.beats, .worse]), ("no-win-worse", [.worse, .same]),
   ("no-win-same", [.same, .unresolved]), ("unresolved", [.unresolved, .unresolved]), ("empty", [])]

/-! ## Reading the reduced file -/

structure ArmData where
  engine : Engine
  name : String
  runId : String
  profile : String
  sha : String
  fw : List String
  vms : List Vm

private def pairOf (j : Json) : Except String (Int × Int) := do
  match (← j.getArr?).toList with
  | [a, b] => return (← a.getInt?, ← b.getInt?)
  | _ => throw "a bin is [y0, count]"

private def parseVm (j : Json) : Except String Vm := do
  let vh ← j.getObjValAs? Int "vh"
  let maxY ← j.getObjValAs? Int "maxY"
  let bins ← (← (← j.getObjVal? "bins").getArr?).toList.mapM fun b => do
    let m ← b.getObjValAs? String "m"
    let v ← (← (← b.getObjVal? "v").getArr?).toList.mapM pairOf
    return (m, v)
  let census ← (← (← j.getObjVal? "census").getArr?).toList.mapM fun c => do
    return { y := ← c.getObjValAs? Int "y", layers := ← c.getObjValAs? Int "layers", bytes := ← c.getObjValAs? Int "bytes" : Census }
  return { geo := ⟨vh * 10, maxY * 10⟩, bins, census }

private def parseEngine (s : String) : Except String Engine :=
  match s with
  | "webkit" => .ok .webkit
  | "chromium" => .ok .chromium
  | _ => .error s!"unknown engine {s}"

def parseArm (j : Json) : Except String ArmData := do
  let engine ← parseEngine (← j.getObjValAs? String "engine")
  let name ← j.getObjValAs? String "name"
  let runId ← j.getObjValAs? String "runId"
  let profile ← j.getObjValAs? String "profile"
  let sha ← j.getObjValAs? String "sha"
  let fw ← (← (← j.getObjVal? "fw").getArr?).toList.mapM (·.getStr?)
  let vms ← (← (← j.getObjVal? "vms").getArr?).toList.mapM parseVm
  if vms.isEmpty then throw s!"{engine.name}/{name}: no usable sample"
  return { engine, name, runId, profile, sha, fw, vms }

def parseArms (j : Json) : Except String (List ArmData) := do
  (← (← j.getObjVal? "arms").getArr?).toList.mapM parseArm

/-! ## The golden -/

def line (kind : String) (fs : List (String × Json)) : String :=
  (Json.mkObj (("kind", Json.str kind) :: fs)).compress

def ints (l : List Int) : Json := Json.arr (l.map toJson).toArray

def geos (a : ArmData) : Json :=
  Json.arr (a.vms.map fun v => Json.arr #[toJson v.geo.vh10, toJson v.geo.maxY10]).toArray

def cellLine (a base : ArmData) (z : Zone) (m : Metric) (isDecided : Bool) : String :=
  let b := column z m base.vms
  let x := column z m a.vms
  line "cell" [("engine", a.engine.name), ("arm", a.name), ("zone", z.name), ("metric", m.name), ("decided", isDecided),
    ("base", ints b), ("armVms", ints x), ("spread", toJson (spread b)), ("verdict", (judge b x).name), ("raw", (verdict b x).name),
    ("nBase", b.length), ("nArm", x.length)]

def zoneLine (a base : ArmData) (z : Zone) : String :=
  let vs := zoneVerdicts (decided a.engine) z base.vms a.vms
  line "zone" [("engine", a.engine.name), ("arm", a.name), ("zone", z.name), ("label", (labelOf vs).name),
    ("outcome", (outcomeOf vs).name), ("nBase", base.vms.length), ("nArm", a.vms.length),
    ("short", short base.vms.length || short a.vms.length)]

def armLines (base a : ArmData) : List String :=
  zones.flatMap (fun z =>
    ((decided a.engine).map fun m => cellLine a base z m true) ++ ((reported a.engine).map fun m => cellLine a base z m false) ++
      [zoneLine a base z]) ++
  [line "engine" [("engine", a.engine.name), ("arm", a.name), ("runId", a.runId), ("profile", a.profile), ("sha", a.sha),
    ("fw", Json.arr (a.fw.map Json.str).toArray), ("geosBase", geos base), ("geosArm", geos a),
    ("outcome", (engineOutcome (decided a.engine) base.vms a.vms).name)]]

/-- Whether the VM carries the metric. -/
def Vm.has (v : Vm) : Metric → Bool
  | .bin n => v.bins.any (·.1 == n)
  | .layers => !v.census.isEmpty
  | .bytes => !v.census.isEmpty

/-- A sample that lacks a decided or reported metric fails here and not as a silent zero in the note. -/
def checkPresent (a : ArmData) : Except String Unit :=
  if a.vms.all (fun v => (decided a.engine ++ reported a.engine).all v.has) then .ok ()
  else .error s!"{a.engine.name}/{a.name}: a sample lacks a metric"

def render (arms : List ArmData) : Except String String := do
  for a in arms do checkPresent a
  let consts := line "consts" [("minVms", minVms), ("minPercent", toJson minPercent),
    ("webkitDecided", Json.arr ((decided .webkit).map fun m => Json.str m.name).toArray),
    ("chromiumDecided", Json.arr ((decided .chromium).map fun m => Json.str m.name).toArray)]
  let cases := caseColumns.map (fun (n, b, x) =>
      line "case" [("name", n), ("base", ints b), ("armVms", ints x), ("verdict", (judge b x).name)]) ++
    caseOutcomes.map fun (n, vs) => line "outcome" [("name", n), ("verdicts", Json.arr (vs.map fun v => Json.str v.name).toArray),
      ("outcome", (outcomeOf vs).name)]
  let mut rows : List String := []
  for e in [Engine.webkit, .chromium] do
    let mine := arms.filter (·.engine == e)
    if mine.isEmpty then continue
    let some base := mine.find? (·.name == "base") | throw s!"{e.name}: no base arm"
    rows := rows ++ (mine.filter (·.name != "base")).flatMap (armLines base)
  return String.join ((consts :: cases ++ rows).map (· ++ "\n"))

def dataPath : String := "../results/dormant-counts/zones.json"
def goldenPath : String := "../packages/contracts/golden/parts/dormant-counts.jsonl"

def gen (args : List String) : IO Unit := do
  let j ← IO.ofExcept (Json.parse (← IO.FS.readFile dataPath))
  let text ← IO.ofExcept (parseArms j >>= render)
  if args.contains "--check" then
    let disk ← IO.FS.readFile goldenPath
    if disk != text then
      throw (IO.userError s!"dormant-counts: {goldenPath} is stale; regenerate with Fw.Parts.DormantCounts.gen []")
    IO.println s!"dormant-counts: {goldenPath} equals the Lean output"
  else
    IO.FS.writeFile goldenPath text

end Fw.Parts.DormantCounts
