import Lean.Data.Json
import Fw.Parts.PlatformGlintHold
/-! Glint hold-freeze recalc prediction and verdict for the WebKit lane. -/
namespace Fw.Device.GlintHold
open Lean
open Fw.Parts.PlatformGlint (Side)
open Fw.Parts.PlatformGlintHold (ticking faithfulTicking holds ticking_le)

structure Frame where
  recalcs : Nat
  l : Option Int
  r : Option Int
  deriving DecidableEq, Repr

def tickAt (hold : Bool) (s : Side) (e : Int) : Nat :=
  if e < 0 then 0 else if hold then ticking s (e : Rat) else faithfulTicking

def tickO (hold : Bool) (s : Side) : Option Int → Bool
  | none => false
  | some e => decide (0 < tickAt hold s e)

def frameTicks (hold : Bool) (prev : Option Frame) (f : Frame) : Bool :=
  tickO hold .left f.l || tickO hold .right f.r ||
    (match prev with
      | none => false
      | some p => tickO hold .left p.l || tickO hold .right p.r)

def ticksFrom (hold : Bool) : Option Frame → List Frame → Nat
  | _, [] => 0
  | p, f :: fs => (if frameTicks hold p f then 1 else 0) + ticksFrom hold (some f) fs

def ticks (hold : Bool) (fs : List Frame) : Nat := ticksFrom hold none fs

def rpf100 (fs : List Frame) : Nat :=
  if fs.length = 0 then 0 else (fs.map (·.recalcs)).sum * 100 / fs.length

abbrev Arm := List (List Frame)

def Arm.frames (a : Arm) : List Frame := a.flatten

def Arm.ticks (hold : Bool) (a : Arm) : Nat := (a.map (Fw.Device.GlintHold.ticks hold)).sum

structure Cell where
  baseOn : List Arm
  baseOff : Arm
  holdOn : Arm
  deriving DecidableEq, Repr

structure Nums where
  nb : Nat
  bq : Nat
  nf : Nat
  n : Nat
  q : Nat
  b : Nat
  f : Nat
  h : Nat
  spread : Nat
  deriving DecidableEq, Repr

def spreadOf (xs : List Nat) : Nat := xs.foldl max 0 - xs.foldl min (xs.foldl max 0)

def Cell.nums (c : Cell) : Nums where
  nb := (c.baseOn.map fun a => a.frames.length).sum
  bq := (c.baseOn.map (Arm.ticks false)).sum
  nf := c.baseOff.frames.length
  n := c.holdOn.frames.length
  q := c.holdOn.ticks true
  b := rpf100 (c.baseOn.map Arm.frames).flatten
  f := rpf100 c.baseOff.frames
  h := rpf100 c.holdOn.frames
  spread := spreadOf (c.baseOn.map fun a => rpf100 a.frames)

def minIdle : Nat := 40

def minFlip : Nat := 12

def minSpread : Nat := 50

def bandDen : Nat := 16

def minValid : Nat := 2

def Nums.s (x : Nums) : Nat := x.b - x.f

def Nums.pred (x : Nums) : Nat := if x.n = 0 then x.b else x.f + x.s * x.q / x.n

def Nums.band (x : Nums) : Nat := max (x.s / bandDen) x.spread

def Nums.predCut (x : Nums) : Nat := x.b - x.pred

inductive V where
  | unread | premise | noContrast | uninformative | asPredicted | cutsLess | cutsMore | noCut
  deriving DecidableEq, Repr

def V.name : V → String
  | .unread => "unread" | .premise => "premise" | .noContrast => "no-contrast" | .uninformative => "uninformative"
  | .asPredicted => "cuts as predicted" | .cutsLess => "cuts less" | .cutsMore => "cuts more" | .noCut => "no cut"

def V.judged : V → Bool
  | .asPredicted | .cutsLess | .cutsMore | .noCut => true
  | _ => false

def judge (minF : Nat) (x : Nums) : V :=
  if x.nb < minF ∨ x.nf < minF ∨ x.n < minF then .unread
  else if x.bq < x.nb then .premise
  else if x.b < x.f + minSpread then .noContrast
  else if x.predCut < 2 * x.band then .uninformative
  else if x.h + x.band < x.pred then .cutsMore
  else if x.pred + x.band < x.h then (if x.b ≤ x.h + x.band then .noCut else .cutsLess)
  else .asPredicted

inductive O where
  | inconclusive | mixed | is (v : V)
  deriving DecidableEq, Repr

def O.name : O → String
  | .inconclusive => "inconclusive" | .mixed => "mixed" | .is v => v.name

def overall (vs : List V) : O :=
  let js := vs.filter V.judged
  if js.length < minValid then .inconclusive
  else match js with
    | [] => .inconclusive
    | v :: rest => if rest.all (· == v) then .is v else .mixed

def rampSegs (s : Side) : List Nat := (List.range 5).filter fun k => !holds s k

theorem ramp_left : rampSegs .left = [0, 3] := by decide

theorem ramp_right : rampSegs .right = [1, 2] := by decide

theorem hold_both : (List.range 5).filter (fun k => holds .left k && holds .right k) = [4] := by decide

theorem union_ramp : ((List.range 5).filter fun k => !(holds .left k && holds .right k)).length = 4 := by decide

theorem tickAt_base (s : Side) (e : Int) (h : 0 ≤ e) : tickAt false s e = 2 := by
  simp [tickAt, faithfulTicking, Int.not_lt.mpr h]

theorem tickAt_le (s : Side) (e : Int) : tickAt true s e ≤ tickAt false s e := by
  unfold tickAt
  by_cases h : e < 0
  · simp [h]
  · simpa [h] using ticking_le s (e : Rat)

theorem tickO_le (s : Side) (o : Option Int) : tickO true s o = true → tickO false s o = true := by
  cases o with
  | none => simp [tickO]
  | some e => have := tickAt_le s e; simp only [tickO, decide_eq_true_eq]; omega

theorem frameTicks_le (p : Option Frame) (f : Frame) : frameTicks true p f = true → frameTicks false p f = true := by
  unfold frameTicks
  have hl := tickO_le .left
  have hr := tickO_le .right
  cases p <;> simp only [Bool.or_eq_true] <;> grind

theorem ticksFrom_le (p : Option Frame) (fs : List Frame) : ticksFrom true p fs ≤ ticksFrom false p fs := by
  induction fs generalizing p with
  | nil => simp [ticksFrom]
  | cons f t ih =>
    have := ih (some f)
    have h : (if frameTicks true p f then 1 else 0) ≤ (if frameTicks false p f then 1 else 0) := by
      by_cases a : frameTicks true p f = true
      · simp [a, frameTicks_le p f a]
      · simp [a]
    simp only [ticksFrom]
    omega

theorem ticks_hold_le (fs : List Frame) : ticks true fs ≤ ticks false fs := ticksFrom_le none fs

theorem Arm.ticks_hold_le (a : Arm) : a.ticks true ≤ a.ticks false := by
  induction a with
  | nil => simp [Arm.ticks]
  | cons w t ih =>
    have h := Fw.Device.GlintHold.ticks_hold_le w
    simp only [Arm.ticks, List.map_cons, List.sum_cons] at ih ⊢
    omega

theorem ticksFrom_le_length (hold : Bool) (p : Option Frame) (fs : List Frame) : ticksFrom hold p fs ≤ fs.length := by
  induction fs generalizing p with
  | nil => simp [ticksFrom]
  | cons f t ih =>
    have := ih (some f)
    simp only [ticksFrom, List.length_cons]
    split <;> omega

theorem ticks_le_length (hold : Bool) (fs : List Frame) : ticks hold fs ≤ fs.length := ticksFrom_le_length hold none fs

theorem pred_le_base (x : Nums) (hq : x.q ≤ x.n) (hf : x.f ≤ x.b) : x.pred ≤ x.b := by
  unfold Nums.pred Nums.s
  split
  · exact Nat.le_refl _
  · have : (x.b - x.f) * x.q / x.n ≤ x.b - x.f := by
      apply Nat.div_le_of_le_mul
      rw [Nat.mul_comm x.n]
      exact Nat.mul_le_mul_left _ hq
    omega

theorem floor_le_pred (x : Nums) : x.f ≤ x.pred ∨ x.n = 0 := by
  unfold Nums.pred
  by_cases h : x.n = 0
  · exact Or.inr h
  · left; simp [h]

theorem pred_all_ticks (x : Nums) (hn : 0 < x.n) (hq : x.q = x.n) (hf : x.f ≤ x.b) : x.pred = x.b := by
  unfold Nums.pred Nums.s
  have hne : x.n ≠ 0 := by omega
  simp only [hne, ite_false, hq]
  rw [Nat.mul_div_cancel _ hn]
  omega

theorem pred_no_ticks (x : Nums) (hn : 0 < x.n) (hq : x.q = 0) : x.pred = x.f := by
  unfold Nums.pred
  have hne : x.n ≠ 0 := by omega
  simp [hne, hq]

theorem judge_unread (minF : Nat) (x : Nums) (h : x.nb < minF ∨ x.nf < minF ∨ x.n < minF) : judge minF x = .unread := by
  simp [judge, h]

theorem judge_premise (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h : x.bq < x.nb) :
    judge minF x = .premise := by
  simp only [judge, h0, ite_false, h, ite_true]

theorem judge_noContrast (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h1 : ¬x.bq < x.nb)
    (h : x.b < x.f + minSpread) : judge minF x = .noContrast := by
  simp only [judge, h0, ite_false, h1, h, ite_true]

theorem judge_uninformative (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h1 : ¬x.bq < x.nb)
    (h2 : ¬x.b < x.f + minSpread) (h : x.predCut < 2 * x.band) : judge minF x = .uninformative := by
  simp only [judge, h0, ite_false, h1, h2, h, ite_true]

theorem judge_cutsMore (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h1 : ¬x.bq < x.nb)
    (h2 : ¬x.b < x.f + minSpread) (h3 : ¬x.predCut < 2 * x.band) (h : x.h + x.band < x.pred) : judge minF x = .cutsMore := by
  simp only [judge, h0, ite_false, h1, h2, h3, h, ite_true]

theorem judge_noCut (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h1 : ¬x.bq < x.nb)
    (h2 : ¬x.b < x.f + minSpread) (h3 : ¬x.predCut < 2 * x.band) (h4 : ¬x.h + x.band < x.pred)
    (h : x.pred + x.band < x.h) (hb : x.b ≤ x.h + x.band) : judge minF x = .noCut := by
  simp only [judge, h0, ite_false, h1, h2, h3, h4, h, hb, ite_true]

theorem judge_cutsLess (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h1 : ¬x.bq < x.nb)
    (h2 : ¬x.b < x.f + minSpread) (h3 : ¬x.predCut < 2 * x.band) (h4 : ¬x.h + x.band < x.pred)
    (h : x.pred + x.band < x.h) (hb : ¬x.b ≤ x.h + x.band) : judge minF x = .cutsLess := by
  simp only [judge, h0, ite_false, h1, h2, h3, h4, h, hb, ite_true]

theorem judge_asPredicted (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h1 : ¬x.bq < x.nb)
    (h2 : ¬x.b < x.f + minSpread) (h3 : ¬x.predCut < 2 * x.band) (h4 : ¬x.h + x.band < x.pred)
    (h5 : ¬x.pred + x.band < x.h) : judge minF x = .asPredicted := by
  simp only [judge, h0, ite_false, h1, h2, h3, h4, h5]

theorem judged_informative (minF : Nat) (x : Nums) (h : (judge minF x).judged = true) : 2 * x.band ≤ x.predCut := by
  unfold judge at h
  repeat' split at h
  all_goals (simp_all [V.judged]; try omega)

theorem noCut_small (minF : Nat) (x : Nums) (h : judge minF x = .noCut) : x.b ≤ x.h + x.band := by
  unfold judge at h
  repeat' split at h
  all_goals simp_all

theorem cutsLess_spec (minF : Nat) (x : Nums) (h : judge minF x = .cutsLess) :
    x.h + x.band < x.b ∧ x.pred + x.band < x.h := by
  unfold judge at h
  repeat' split at h
  all_goals (simp_all; try omega)

theorem cutsMore_spec (minF : Nat) (x : Nums) (h : judge minF x = .cutsMore) : x.h + x.band < x.pred := by
  unfold judge at h
  repeat' split at h
  all_goals simp_all

theorem asPredicted_spec (minF : Nat) (x : Nums) (h : judge minF x = .asPredicted) :
    x.pred ≤ x.h + x.band ∧ x.h ≤ x.pred + x.band := by
  unfold judge at h
  repeat' split at h
  all_goals (simp_all; try omega)

theorem overall_inconclusive (vs : List V) (h : (vs.filter V.judged).length < minValid) : overall vs = .inconclusive := by
  simp [overall, h]

theorem overall_is (v : V) (vs : List V) (hj : v.judged = true) (hall : ∀ w ∈ vs, w = v) (hn : minValid ≤ vs.length) :
    overall vs = .is v := by
  have hf : vs.filter V.judged = vs := List.filter_eq_self.mpr (fun a ha => by rw [hall a ha]; exact hj)
  unfold overall
  simp only [hf]
  cases vs with
  | nil => simp [minValid] at hn
  | cons a t =>
    have ha : a = v := hall a (by simp)
    have : ¬(a :: t).length < minValid := by omega
    simp only [this, ite_false]
    have : t.all (· == a) = true := by
      simp only [List.all_eq_true, beq_iff_eq]
      intro w hw; rw [hall w (by simp [hw]), ha]
    subst ha
    simp only [this, ite_true]

theorem overall_mixed (a b : V) (vs : List V) (ha : a.judged = true) (hb : b.judged = true) (hab : a ≠ b)
    (h : vs = [a, b]) : overall vs = .mixed := by
  subst h
  cases a <;> cases b <;> first | exact absurd rfl hab | (revert ha hb; decide)

private def mkFrame (r : Nat) (l e : Option Int) : Frame := ⟨r, l, e⟩

private def runR (k step l0 r0 : Int) (rcs : Nat → Nat) : List Frame :=
  (List.range k.toNat).map fun i => mkFrame (rcs i) (some (step * (i : Int) + l0)) (some (step * (i : Int) + r0))

private def run (k step l0 r0 : Int) (rc : Nat) : List Frame := runR k step l0 r0 fun _ => rc

private def holdRun (k step l0 r0 : Int) (onTick off : Nat → Nat) : List Frame :=
  let rec go (p : Option Frame) (i : Nat) : List Frame → List Frame
    | [] => []
    | f :: t => { f with recalcs := if frameTicks true p f then onTick i else off i } :: go (some f) (i + 1) t
  go none 0 (run k step l0 r0 0)

private def rate (r : Nat) (i : Nat) : Nat := if i % 20 * 5 < r then 1 else 0

private def still (k : Nat) (r : Nat) : List Frame := (List.range k).map fun i => mkFrame (rate r i) (some 0) (some 0)

private def frameJ (f : Frame) : Json :=
  Json.arr #[toJson f.recalcs, (match f.l with | none => Json.null | some e => toJson e), (match f.r with | none => Json.null | some e => toJson e)]

private def framesJ (fs : List Frame) : Json := Json.arr (fs.map frameJ).toArray

private def armJ (a : Arm) : Json := Json.arr (a.map framesJ).toArray

private def numsJ (x : Nums) : Json :=
  Json.mkObj [("nb", x.nb), ("bq", x.bq), ("nf", x.nf), ("n", x.n), ("q", x.q), ("b", x.b), ("f", x.f), ("h", x.h), ("spread", x.spread)]

private def cellJ (c : Cell) : Json :=
  Json.mkObj [("baseOn", Json.arr (c.baseOn.map armJ).toArray), ("baseOff", armJ c.baseOff), ("holdOn", armJ c.holdOn)]

private def tickCases : List (String × List Frame) :=
  [("idle full cycle", run 50 100 0 0 0), ("idle offset dashes", run 50 100 0 1500 0), ("inside hold segment 4", run 30 25 4100 4100 0),
   ("inside ramp 0", run 30 25 100 100 0), ("flip window of 3", run 3 30 3900 3900 0),
   ("not begun", (List.range 20).map fun _ => mkFrame 0 none none),
   ("begun halfway", (List.range 20).map fun i => mkFrame 0 (if i < 10 then none else some 4000) (if i < 10 then none else some 4000))]

private def baseTwo (r : Nat) : List Arm := [[runR 50 100 0 0 (rate r)], [runR 50 100 0 0 (rate r)]]

private def cellCases : List (String × Nat × Cell) :=
  let hold (l0 r0 : Int) (a b : Nat) : Arm := [holdRun 50 100 l0 r0 (rate a) (rate b)]
  let flipBase : List Arm := [[run 4 30 3000 3000 1, run 4 30 3000 3000 1, run 4 30 3000 3000 1, run 4 30 3000 3000 1],
    [run 4 30 3000 3000 1, run 4 30 3000 3000 1, run 4 30 3000 3000 1, run 4 30 3000 3000 1]]
  [("as predicted", minIdle, ⟨baseTwo 100, [still 50 0], hold 0 0 100 0⟩),
   ("as predicted dashes out of step", minIdle, ⟨baseTwo 100, [still 50 0], hold 0 1500 100 0⟩),
   ("as predicted base 90 floor 10", minIdle, ⟨baseTwo 90, [still 50 10], hold 0 0 90 10⟩),
   ("no cut", minIdle, ⟨baseTwo 100, [still 50 0], [run 50 100 0 0 1]⟩),
   ("cuts less", minIdle, ⟨baseTwo 100, [still 50 0], [runR 50 100 0 0 (fun i => if i % 25 < 23 then 1 else 0)]⟩),
   ("cuts more", minIdle, ⟨baseTwo 100, [still 50 0], [run 50 100 0 0 0]⟩),
   ("unread", minIdle, ⟨[[run 10 25 0 0 1], [run 10 25 0 0 1]], [still 50 0], hold 0 0 100 0⟩),
   ("premise", minIdle, ⟨[[(List.range 50).map fun _ => mkFrame 1 none none], [run 50 100 0 0 1]], [still 50 0], hold 0 0 100 0⟩),
   ("no contrast", minIdle, ⟨baseTwo 100, [still 50 100], hold 0 0 100 100⟩),
   ("uninformative", minIdle, ⟨baseTwo 100, [still 50 0], [holdRun 40 25 100 100 (rate 100) (rate 0)]⟩),
   ("flip windows", minFlip, ⟨flipBase, [still 4 0, still 4 0, still 4 0, still 4 0],
      [holdRun 4 30 3950 3950 (rate 100) (rate 0), holdRun 4 30 4300 4300 (rate 100) (rate 0), holdRun 4 30 4300 4300 (rate 100) (rate 0),
       holdRun 4 30 4300 4300 (rate 100) (rate 0)]⟩)]

private def numsCases : List (String × Nat × Nums) :=
  let ok : Nums := ⟨100, 100, 100, 100, 80, 100, 0, 80, 0⟩
  [("edge as predicted high", 40, { ok with h := 86 }), ("edge cuts less", 40, { ok with h := 87 }),
   ("edge as predicted low", 40, { ok with h := 74 }), ("edge cuts more", 40, { ok with h := 73 }),
   ("edge no cut", 40, { ok with h := 94 }), ("edge cuts less top", 40, { ok with h := 93 }),
   ("spread widens the band", 40, { ok with h := 90, spread := 12 }), ("edge contrast", 40, { ok with b := 50, h := 40 }),
   ("edge no contrast", 40, { ok with b := 49, h := 40 }), ("edge uninformative", 40, { ok with q := 89 }),
   ("edge informative", 40, { ok with q := 88 }), ("hold frames zero", 40, { ok with n := 0 })]

private def overallCases : List (String × List V) :=
  [("three as predicted", [.asPredicted, .asPredicted, .asPredicted]), ("two as predicted one unread", [.asPredicted, .unread, .asPredicted]),
   ("one judged", [.cutsLess, .unread, .uninformative]), ("mixed", [.asPredicted, .cutsLess, .asPredicted]),
   ("three no cut", [.noCut, .noCut, .noCut]), ("none judged", [.premise, .noContrast, .uninformative])]

private def vJ (v : V) : Json := Json.str v.name

private def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("minIdle", minIdle), ("minFlip", minFlip), ("minSpread", minSpread), ("bandDen", bandDen),
    ("minValid", minValid)]).compress] ++
  (tickCases.map fun (n, fs) =>
    (Json.mkObj [("kind", "ticks"), ("name", n), ("frames", framesJ fs), ("hold", ticks true fs), ("base", ticks false fs)]).compress) ++
  (numsCases.map fun (n, m, x) =>
    (Json.mkObj [("kind", "judge"), ("name", n), ("minF", m), ("nums", numsJ x), ("pred", x.pred), ("band", x.band),
      ("verdict", vJ (judge m x))]).compress) ++
  (cellCases.map fun (n, m, c) =>
    let x := c.nums
    (Json.mkObj [("kind", "cell"), ("name", n), ("minF", m), ("cell", cellJ c), ("nums", numsJ x), ("pred", x.pred), ("band", x.band),
      ("verdict", vJ (judge m x))]).compress) ++
  (overallCases.map fun (n, vs) =>
    (Json.mkObj [("kind", "overall"), ("name", n), ("verdicts", Json.arr (vs.map vJ).toArray), ("overall", (overall vs).name)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def runGolden (args : List String) : IO UInt32 := do
  match args with
  | "--check" :: path :: _ =>
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"device-glint-hold golden: {path} is up to date ({(goldenLines ()).length} lines)"
      return 0
    IO.eprintln s!"device-glint-hold golden: {path} differs from the generated bytes"
    return 1
  | _ =>
    IO.print (goldenText ())
    return 0

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "glint-hold.jsonl"

def checkRepo : IO Unit := do
  if (← runGolden ["--check", goldenPath.toString]) != 0 then throw (IO.userError "device-glint-hold golden differs")

end Fw.Device.GlintHold
