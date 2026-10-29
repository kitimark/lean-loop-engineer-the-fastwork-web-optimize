import Lean.Data.Json
import Fw.Device.PhoneArms
/-!
# Column picture probe on the CI lanes: arms, push labels, verdict rule
Reads `research/notes/2026/10-27-end-columns-probe.md` P1. The probe flag `morph.columns:probe-off` hides the 21 column pictures
(`visibility: hidden`). Four arms per engine: base, base+off, timed-fixed (morph.geom + geom-timed), timed-fixed+off.
Twin: `packages/measure-chromium/src/cols-verdict.mjs`; golden `packages/contracts/golden/device/cols-probe.jsonl`.
The rule is fixed before the data: per metric, the reference arm's own spread over its jobs is `[lo, hi]`; the off arm "costs" the
pictures when every one of its jobs lies below `lo`.
-/
namespace Fw.Device.ColsProbe
open Lean
open Fw.Device.PhoneArms (probeFlag colsArms samePage)

inductive Engine where
  | chromium | webkit
  deriving DecidableEq, Repr

def Engine.name : Engine → String
  | .chromium => "chromium" | .webkit => "webkit"

/-- Chromium counts lane: `trace.RasterTask`, `trace.DisplayItemListRaster`, `trace.PaintImage`, `trace.cc.Draw`. WebKit Simulator push lane: census layers, census backing bytes, timeline Paint rows per push. The counts lane records neither RasterTask milliseconds nor render passes. -/
inductive Metric where
  | rasterTask | rasterItems | paintImage | draw | layers | backing | paint
  deriving DecidableEq, Repr

def Metric.name : Metric → String
  | .rasterTask => "RasterTask" | .rasterItems => "DisplayItemListRaster" | .paintImage => "PaintImage" | .draw => "cc.Draw"
  | .layers => "layerCount" | .backing => "backingBytes" | .paint => "Paint"

def Engine.metrics : Engine → List Metric
  | .chromium => [.rasterTask, .rasterItems, .paintImage, .draw]
  | .webkit => [.layers, .backing, .paint]

theorem metrics_count : Engine.chromium.metrics.length = 4 ∧ Engine.webkit.metrics.length = 3 := by decide

/-- One arm: whether the pictures are hidden and whether the flip (morph.geom with geom-timed) is on. -/
structure CArm where
  id : String
  off : Bool
  flip : Bool
  deriving DecidableEq, Repr

def cbase : CArm := ⟨"base", false, false⟩
def cbaseOff : CArm := ⟨"base+off", true, false⟩
def ctimed : CArm := ⟨"timed-fixed", false, true⟩
def ctimedOff : CArm := ⟨"timed-fixed+off", true, true⟩

def arms : List CArm := [cbase, cbaseOff, ctimed, ctimedOff]

/-- The fw flags, parts in increasing order (the part ids morph.columns < morph.geom < morph.tween). -/
def CArm.flags (a : CArm) : List String :=
  (if a.off then [probeFlag] else []) ++ (if a.flip then ["morph.geom:on", "morph.tween:geom-timed"] else [])

def CArm.search (a : CArm) : String := if a.flags.isEmpty then "" else "?fw=" ++ String.intercalate "," a.flags

/-- The arm of the reference: the same page with the pictures shown. -/
def CArm.ref (a : CArm) : CArm := ⟨if a.flip then ctimed.id else cbase.id, false, a.flip⟩

/-- Simulator push lane arm name (`packages/measure-webkit/src/throttle/push-cycle.mjs` MORPH_ARMS). -/
def CArm.wkArm (a : CArm) : String :=
  "morph-" ++ (if a.flip then "timed" else "base") ++ (if a.off then "-off" else "")

/-- Chromium counts lane label: the default config is `rewrite`, the `arms=` list is f1, f2, f3 in the order of `chromiumArms`. -/
def chromiumArms : List CArm := [cbaseOff, ctimed, ctimedOff]

def CArm.crLabel (a : CArm) : String :=
  if a == cbase then "rewrite" else s!"f{(chromiumArms.idxOf a) + 1}"

theorem arms_distinct : arms.eraseDups = arms := by decide

theorem off_iff_probe (a : CArm) : probeFlag ∈ a.flags ↔ a.off = true := by
  cases a with | mk i o f => cases o <;> cases f <;> simp [CArm.flags, probeFlag]

theorem ref_shown (a : CArm) : a.ref.off = false := rfl

theorem ref_ref (a : CArm) : a.ref.ref = a.ref := rfl

theorem ref_is_arm : ∀ a ∈ arms, a.ref ∈ arms := by decide

theorem ref_pairs : arms.map (fun a => (a.id, a.ref.id)) =
    [("base", "base"), ("base+off", "base"), ("timed-fixed", "timed-fixed"), ("timed-fixed+off", "timed-fixed")] := by decide

/-- The search strings are the PhoneArms column arms' flags: the same four pages as the phone session. -/
theorem same_pages_as_phone :
    (arms.zip colsArms).all (fun p => Fw.Device.Session.sameFlags p.1.flags p.2.flags) = true := by decide

theorem search_cases : arms.map CArm.search =
    ["", "?fw=morph.columns:probe-off", "?fw=morph.geom:on,morph.tween:geom-timed",
     "?fw=morph.columns:probe-off,morph.geom:on,morph.tween:geom-timed"] := by decide

theorem wk_names : arms.map CArm.wkArm = ["morph-base", "morph-base-off", "morph-timed", "morph-timed-off"] := by decide

theorem cr_labels : arms.map CArm.crLabel = ["rewrite", "f1", "f2", "f3"] := by decide

/-! ## Push label: did the flip run -/

structure PushLog where
  flipArm : Bool
  onDark : Bool
  took : Bool
  deriving DecidableEq, Repr

inductive PushLabel where
  | plain | flip | darkNoTake | lightFallback
  deriving DecidableEq, Repr

def PushLabel.name : PushLabel → String
  | .plain => "plain" | .flip => "flip" | .darkNoTake => "dark-no-take" | .lightFallback => "light-fallback"

/-- The label of one push: `plain` for an arm without the flip; for a flip arm `flip` when a take ran in the push window, else `darkNoTake` (nav was on dark at the push but no take followed) or `lightFallback` (nav was not on dark). -/
def pushLabel (p : PushLog) : PushLabel :=
  if p.flipArm then (if p.took then .flip else if p.onDark then .darkNoTake else .lightFallback) else .plain

theorem pushLabel_plain {p : PushLog} (h : p.flipArm = false) : pushLabel p = .plain := by simp [pushLabel, h]

theorem pushLabel_flip {p : PushLog} (h : p.flipArm = true) (ht : p.took = true) : pushLabel p = .flip := by
  simp [pushLabel, h, ht]

theorem pushLabel_darkNoTake {p : PushLog} (h : p.flipArm = true) (ht : p.took = false) (hd : p.onDark = true) :
    pushLabel p = .darkNoTake := by simp [pushLabel, h, ht, hd]

theorem pushLabel_light {p : PushLog} (h : p.flipArm = true) (ht : p.took = false) (hd : p.onDark = false) :
    pushLabel p = .lightFallback := by simp [pushLabel, h, ht, hd]

/-- A flip arm counts as a flip arm only when at least 3 of 4 pushes took (per mille 750). -/
def flipShareMin : Nat := 750

def flipValid (took pushes : Nat) : Bool := decide (0 < pushes) && decide (flipShareMin * pushes ≤ 1000 * took)

theorem flipValid_none : flipValid 0 0 = false := by decide

theorem flipValid_all {n : Nat} (h : 0 < n) : flipValid n n = true := by
  have : flipShareMin * n ≤ 1000 * n := by unfold flipShareMin; omega
  simp [flipValid, h, this]

theorem flipValid_zero {n : Nat} (h : 0 < n) : flipValid 0 n = false := by
  simp only [flipValid, flipShareMin]
  have : ¬ 750 * n ≤ 1000 * 0 := by omega
  simp [this]

/-! ## Cell verdict: one metric, the reference arm's spread against the off arm's jobs -/

def minJobs : Nat := 3

def lo (xs : List Nat) : Nat := xs.foldl min (xs.headD 0)

def hi (xs : List Nat) : Nat := xs.foldl max (xs.headD 0)

inductive Cell where
  | cost | noCost | mixed | few | zero
  deriving DecidableEq, Repr

def Cell.name : Cell → String
  | .cost => "pictures cost" | .noCost => "no cost" | .mixed => "mixed" | .few => "few jobs" | .zero => "reference zero"

/-- `few`: fewer than 3 jobs on either side. `zero`: the reference never exceeds 0, so nothing can be reduced. `cost`: every off job is below the reference's lowest job. `noCost`: every off job lies inside the reference's spread. Anything else (some below and some inside, or any above) is `mixed`. -/
def below (ref off : List Nat) : Bool := off.all (fun o => decide (o < lo ref))

def inside (ref off : List Nat) : Bool := off.all (fun o => decide (lo ref ≤ o ∧ o ≤ hi ref))

def Cell.of (ref off : List Nat) : Cell :=
  if ref.length < minJobs ∨ off.length < minJobs then .few
  else if hi ref = 0 then .zero
  else if below ref off = true then .cost
  else if inside ref off = true then .noCost
  else .mixed

theorem cell_few_ref {ref off : List Nat} (h : ref.length < minJobs) : Cell.of ref off = .few := by simp [Cell.of, h]

theorem cell_few_off {ref off : List Nat} (h : off.length < minJobs) : Cell.of ref off = .few := by simp [Cell.of, h]

theorem cell_zero {ref off : List Nat} (hr : ¬ ref.length < minJobs) (ho : ¬ off.length < minJobs) (h : hi ref = 0) :
    Cell.of ref off = .zero := by simp [Cell.of, hr, ho, h]

theorem cell_cost {ref off : List Nat} (hr : ¬ ref.length < minJobs) (ho : ¬ off.length < minJobs) (h : hi ref ≠ 0)
    (hb : below ref off = true) : Cell.of ref off = .cost := by simp [Cell.of, hr, ho, h, hb]

theorem cell_noCost {ref off : List Nat} (hr : ¬ ref.length < minJobs) (ho : ¬ off.length < minJobs) (h : hi ref ≠ 0)
    (hb : below ref off = false)
    (hw : inside ref off = true) : Cell.of ref off = .noCost := by
  simp [Cell.of, hr, ho, h, hb, hw]

theorem cell_mixed {ref off : List Nat} (hr : ¬ ref.length < minJobs) (ho : ¬ off.length < minJobs) (h : hi ref ≠ 0)
    (hb : below ref off = false)
    (hw : inside ref off = false) : Cell.of ref off = .mixed := by
  simp [Cell.of, hr, ho, h, hb, hw]

/-- Cost and no cost never hold together: a job below the spread is not inside it. -/
theorem cell_cost_ne_noCost (ref off : List Nat) : Cell.of ref off = .cost → Cell.of ref off ≠ .noCost := by
  intro h h2; rw [h] at h2; exact absurd h2 (by decide)

/-- Checked cases the verdict rule must meet. -/
theorem cell_cases :
    Cell.of [100, 104, 102] [60, 61, 59] = .cost ∧ Cell.of [100, 104, 102] [100, 103, 104] = .noCost ∧
    Cell.of [100, 104, 102] [60, 101, 59] = .mixed ∧ Cell.of [100, 104, 102] [105, 101, 102] = .mixed ∧
    Cell.of [100, 104, 102] [99, 99, 99] = .cost ∧ Cell.of [100, 104, 102] [100, 100, 100] = .noCost ∧
    Cell.of [0, 0, 0] [0, 0, 0] = .zero ∧ Cell.of [100, 104] [60, 61, 59] = .few ∧ Cell.of [100, 104, 102] [60, 61] = .few := by decide

/-! ## Reading of a contrast: all metrics of one engine -/

inductive Reading where
  | cost | noCost | mixed | few
  deriving DecidableEq, Repr

def Reading.name : Reading → String
  | .cost => "pictures cost" | .noCost => "no cost" | .mixed => "mixed" | .few => "undecided (few jobs)"

/-- `valid` is false when a flip arm of the contrast failed `flipValid`: the contrast is then `few`. Any metric at `cost` makes `cost`; else `few` if any cell has too few jobs; else `noCost` when every cell is `noCost` or `zero`; else `mixed`. -/
def anyCost (cells : List Cell) : Bool := cells.any (· == .cost)

def anyFew (cells : List Cell) : Bool := cells.isEmpty || cells.any (· == .few)

def allClear (cells : List Cell) : Bool := cells.all (fun c => c == .noCost || c == .zero)

def reading (valid : Bool) (cells : List Cell) : Reading :=
  if valid = false then .few
  else if anyCost cells = true then .cost
  else if anyFew cells = true then .few
  else if allClear cells = true then .noCost
  else .mixed

theorem reading_invalid (cells : List Cell) : reading false cells = .few := by simp [reading]

theorem reading_cost {cells : List Cell} (h : anyCost cells = true) : reading true cells = .cost := by simp [reading, h]

theorem reading_few {cells : List Cell} (h0 : anyCost cells = false) (h : anyFew cells = true) : reading true cells = .few := by
  simp [reading, h0, h]

theorem reading_noCost {cells : List Cell} (h0 : anyCost cells = false) (h1 : anyFew cells = false) (h : allClear cells = true) :
    reading true cells = .noCost := by simp [reading, h0, h1, h]

theorem reading_mixed {cells : List Cell} (h0 : anyCost cells = false) (h1 : anyFew cells = false) (h : allClear cells = false) :
    reading true cells = .mixed := by simp [reading, h0, h1, h]

/-! ## What the probe decides about P2 to P6 -/

inductive Plan where
  | p2 | p3 | p4 | p5 | p6
  deriving DecidableEq, Repr

def Plan.name : Plan → String
  | .p2 => "P2 leaf opacity" | .p3 => "P3 column scaler" | .p4 => "P4 static wrappers" | .p5 => "P5 hide clipped pictures" | .p6 => "P6 crop reveal"

inductive Fate where
  | keep | drop | open | independent
  deriving DecidableEq, Repr

def Fate.name : Fate → String
  | .keep => "keep" | .drop => "drop" | .open => "open" | .independent => "independent of picture cost"

/-- Readings of the four contrasts: `bc` base against base+off on Chromium, `bw` on WebKit, `fc` timed-fixed against its off arm on Chromium, `fw` on WebKit. P2 (group opacity), P3 (track layers) and P4 (structure) do not depend on the pictures' own paint cost. P5 needs a cost in any contrast, P6 a cost on the base path (`bc`, `bw`): `keep` on a cost, `drop` when every contrast it reads is `noCost`, else `open`. -/
def fate (p : Plan) (bc bw fc fw : Reading) : Fate :=
  match p with
  | .p2 | .p3 | .p4 => .independent
  | .p5 => if [bc, bw, fc, fw].any (· == .cost) then .keep else if [bc, bw, fc, fw].all (· == .noCost) then .drop else .open
  | .p6 => if [bc, bw].any (· == .cost) then .keep else if [bc, bw].all (· == .noCost) then .drop else .open

theorem fate_indep (p : Plan) (h : p = .p2 ∨ p = .p3 ∨ p = .p4) (bc bw fc fw : Reading) : fate p bc bw fc fw = .independent := by
  rcases h with rfl | rfl | rfl <;> rfl

theorem fate_p5_keep {bc bw fc fw : Reading} (h : [bc, bw, fc, fw].any (· == .cost) = true) : fate .p5 bc bw fc fw = .keep := by
  simp [fate, h]

theorem fate_p5_drop {bc bw fc fw : Reading} (h : ([bc, bw, fc, fw].any (· == .cost)) = false) (hn : [bc, bw, fc, fw].all (· == .noCost) = true) :
    fate .p5 bc bw fc fw = .drop := by simp [fate, h, hn]

theorem fate_p6_keep {bc bw fc fw : Reading} (h : [bc, bw].any (· == .cost) = true) : fate .p6 bc bw fc fw = .keep := by
  simp [fate, h]

theorem fate_p6_drop {bc bw fc fw : Reading} (h : [bc, bw].any (· == .cost) = false) (hn : [bc, bw].all (· == .noCost) = true) :
    fate .p6 bc bw fc fw = .drop := by simp [fate, h, hn]

/-- P6 reads only the base path: a cost on the flip contrast alone keeps P5 and leaves P6 open. -/
theorem fate_p6_flip_only : fate .p6 .noCost .noCost .cost .cost = .drop ∧ fate .p5 .noCost .noCost .cost .cost = .keep := by decide

theorem fate_all_noCost : [Plan.p5, .p6].all (fun p => fate p .noCost .noCost .noCost .noCost == .drop) = true := by decide

/-! ## Golden -/

def refCase : List (String × List Nat × List Nat) :=
  [("clear cost", [100, 104, 102], [60, 61, 59]), ("inside", [100, 104, 102], [100, 103, 104]), ("one low", [100, 104, 102], [60, 101, 59]),
   ("above", [100, 104, 102], [105, 101, 102]), ("edge below", [100, 104, 102], [99, 99, 99]), ("edge inside", [100, 104, 102], [100, 100, 100]),
   ("all zero", [0, 0, 0], [0, 0, 0]), ("two ref", [100, 104], [60, 61, 59]), ("two off", [100, 104, 102], [60, 61]),
   ("no spread cost", [500, 500, 500], [0, 0, 0]), ("no spread same", [500, 500, 500], [500, 500, 500]), ("no spread above", [500, 500, 500], [501, 500, 500])]

def readCases : List (String × Bool × List Cell) :=
  [("one cost", true, [.noCost, .cost, .noCost]), ("all no cost", true, [.noCost, .noCost, .zero]), ("all zero", true, [.zero, .zero]),
   ("few", true, [.noCost, .few]), ("mixed", true, [.noCost, .mixed]), ("empty", true, []), ("invalid flip", false, [.cost, .cost]),
   ("cost and few", true, [.cost, .few])]

def pushCases : List (String × PushLog) :=
  [("base push", ⟨false, true, false⟩), ("flip took", ⟨true, true, true⟩), ("flip took light", ⟨true, false, true⟩),
   ("dark no take", ⟨true, true, false⟩), ("light fallback", ⟨true, false, false⟩)]

def shareCases : List (Nat × Nat) := [(0, 0), (10, 10), (8, 10), (7, 10), (0, 10), (3, 4), (2, 4)]

def readings : List Reading := [.cost, .noCost, .mixed, .few]

private def strs (xs : List String) : Json := Json.arr (xs.map Json.str).toArray

private def nats (xs : List Nat) : Json := Json.arr (xs.map fun n => toJson n).toArray

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("minJobs", minJobs), ("flipShareMin", flipShareMin)]).compress,
   (Json.mkObj [("kind", "metrics"), ("chromium", strs (Engine.chromium.metrics.map Metric.name)),
     ("webkit", strs (Engine.webkit.metrics.map Metric.name))]).compress] ++
  (arms.map fun a =>
    (Json.mkObj [("kind", "arm"), ("id", a.id), ("off", a.off), ("flip", a.flip), ("ref", a.ref.id), ("search", a.search),
      ("wkArm", a.wkArm), ("crLabel", a.crLabel), ("flags", strs a.flags)]).compress) ++
  (refCase.map fun (n, r, o) =>
    (Json.mkObj [("kind", "cell"), ("name", n), ("ref", nats r), ("off", nats o), ("lo", lo r), ("hi", hi r), ("cell", (Cell.of r o).name)]).compress) ++
  (readCases.map fun (n, v, cs) =>
    (Json.mkObj [("kind", "reading"), ("name", n), ("valid", v), ("cells", strs (cs.map Cell.name)),
      ("reading", (reading v cs).name)]).compress) ++
  (pushCases.map fun (n, p) =>
    (Json.mkObj [("kind", "push"), ("name", n), ("flipArm", p.flipArm), ("onDark", p.onDark), ("took", p.took),
      ("label", (pushLabel p).name)]).compress) ++
  (shareCases.map fun (t, n) =>
    (Json.mkObj [("kind", "share"), ("took", t), ("pushes", n), ("valid", flipValid t n)]).compress) ++
  (readings.flatMap fun bc => readings.flatMap fun fc =>
    [(Json.mkObj [("kind", "fate"), ("bc", bc.name), ("bw", bc.name), ("fc", fc.name), ("fw", fc.name),
      ("p5", (fate .p5 bc bc fc fc).name), ("p6", (fate .p6 bc bc fc fc).name)]).compress])

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def run (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-cols-probe golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-cols-probe golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "cols-probe.jsonl"

def checkRepo : IO Unit := do
  if (← run ["--check", goldenPath.toString]) != 0 then throw (IO.userError "device-cols-probe golden differs")

end Fw.Device.ColsProbe
