import Fw.Device.GlintHold
namespace Fw.Device.GlintHoldCompositor
open Lean
open Fw.Device.GlintHold

inductive VC where
  | notRunning | unread | noContrast | uninformative | atFloor | partly | noCut
  deriving DecidableEq, Repr

def VC.name : VC → String
  | .notRunning => "variant animation not running"
  | .unread => "unread" | .noContrast => "no-contrast" | .uninformative => "uninformative"
  | .atFloor => "within the floor band" | .partly => "cuts partly" | .noCut => "no cut"

def VC.judged : VC → Bool
  | .atFloor | .partly | .noCut => true
  | _ => false

def judgeC (minF : Nat) (x : Nums) : VC :=
  if x.nb < minF ∨ x.nf < minF ∨ x.n < minF then .unread
  else if x.b < x.f + minSpread then .noContrast
  else if x.s ≤ 2 * x.band then .uninformative
  else if x.h ≤ x.f + x.band then .atFloor
  else if x.b ≤ x.h + x.band then .noCut
  else .partly

def judgeLive (minF live : Nat) (x : Nums) : VC :=
  if live = 0 then .notRunning else judgeC minF x

theorem judgeLive_notRunning (minF : Nat) (x : Nums) : judgeLive minF 0 x = .notRunning := by
  simp [judgeLive]

theorem judgeLive_of_live (minF live : Nat) (x : Nums) (h : live ≠ 0) : judgeLive minF live x = judgeC minF x := by
  simp [judgeLive, h]

inductive OC where
  | inconclusive | mixed | is (v : VC)
  deriving DecidableEq, Repr

def OC.name : OC → String
  | .inconclusive => "inconclusive" | .mixed => "mixed" | .is v => v.name

def overallC (vs : List VC) : OC :=
  let js := vs.filter VC.judged
  if js.length < minValid then .inconclusive
  else match js with
    | [] => .inconclusive
    | v :: rest => if rest.all (· == v) then .is v else .mixed

theorem judgeC_unread (minF : Nat) (x : Nums) (h : x.nb < minF ∨ x.nf < minF ∨ x.n < minF) : judgeC minF x = .unread := by
  simp [judgeC, h]

theorem judgeC_noContrast (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h : x.b < x.f + minSpread) :
    judgeC minF x = .noContrast := by
  simp only [judgeC, h0, ite_false, h, ite_true]

theorem judgeC_uninformative (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF))
    (h1 : ¬x.b < x.f + minSpread) (h : x.s ≤ 2 * x.band) : judgeC minF x = .uninformative := by
  simp only [judgeC, h0, ite_false, h1, h, ite_true]

theorem judgeC_atFloor (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF))
    (h1 : ¬x.b < x.f + minSpread) (h2 : ¬x.s ≤ 2 * x.band) (h : x.h ≤ x.f + x.band) : judgeC minF x = .atFloor := by
  simp only [judgeC, h0, ite_false, h1, h2, h, ite_true]

theorem judgeC_noCut (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF))
    (h1 : ¬x.b < x.f + minSpread) (h2 : ¬x.s ≤ 2 * x.band) (h3 : ¬x.h ≤ x.f + x.band) (h : x.b ≤ x.h + x.band) :
    judgeC minF x = .noCut := by
  simp only [judgeC, h0, ite_false, h1, h2, h3, h, ite_true]

theorem judgeC_partly (minF : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF))
    (h1 : ¬x.b < x.f + minSpread) (h2 : ¬x.s ≤ 2 * x.band) (h3 : ¬x.h ≤ x.f + x.band) (h : ¬x.b ≤ x.h + x.band) :
    judgeC minF x = .partly := by
  simp only [judgeC, h0, ite_false, h1, h2, h3, h]

theorem atFloor_below_base (minF : Nat) (x : Nums) (h : judgeC minF x = .atFloor) : x.h + x.band < x.b := by
  by_cases c1 : x.nb < minF ∨ x.nf < minF ∨ x.n < minF
  · rw [judgeC_unread minF x c1] at h; simp at h
  by_cases c2 : x.b < x.f + minSpread
  · rw [judgeC_noContrast minF x c1 c2] at h; simp at h
  by_cases c3 : x.s ≤ 2 * x.band
  · rw [judgeC_uninformative minF x c1 c2 c3] at h; simp at h
  by_cases c4 : x.h ≤ x.f + x.band
  · simp only [Nums.s] at c3; omega
  by_cases c5 : x.b ≤ x.h + x.band
  · rw [judgeC_noCut minF x c1 c2 c3 c4 c5] at h; simp at h
  · rw [judgeC_partly minF x c1 c2 c3 c4 c5] at h; simp at h

theorem partly_spec (minF : Nat) (x : Nums) (h : judgeC minF x = .partly) : x.f + x.band < x.h ∧ x.h + x.band < x.b := by
  by_cases c1 : x.nb < minF ∨ x.nf < minF ∨ x.n < minF
  · rw [judgeC_unread minF x c1] at h; simp at h
  by_cases c2 : x.b < x.f + minSpread
  · rw [judgeC_noContrast minF x c1 c2] at h; simp at h
  by_cases c3 : x.s ≤ 2 * x.band
  · rw [judgeC_uninformative minF x c1 c2 c3] at h; simp at h
  by_cases c4 : x.h ≤ x.f + x.band
  · rw [judgeC_atFloor minF x c1 c2 c3 c4] at h; simp at h
  by_cases c5 : x.b ≤ x.h + x.band
  · rw [judgeC_noCut minF x c1 c2 c3 c4 c5] at h; simp at h
  · omega

theorem overallC_inconclusive (vs : List VC) (h : (vs.filter VC.judged).length < minValid) : overallC vs = .inconclusive := by
  simp [overallC, h]

theorem overallC_is (v : VC) (vs : List VC) (hj : v.judged = true) (hall : ∀ w ∈ vs, w = v) (hn : minValid ≤ vs.length) :
    overallC vs = .is v := by
  have hf : vs.filter VC.judged = vs := List.filter_eq_self.mpr (fun a ha => by rw [hall a ha]; exact hj)
  unfold overallC
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

theorem overallC_mixed (a b : VC) (vs : List VC) (ha : a.judged = true) (hb : b.judged = true) (hab : a ≠ b)
    (h : vs = [a, b]) : overallC vs = .mixed := by
  subst h
  cases a <;> cases b <;> first | exact absurd rfl hab | (revert ha hb; decide)

private def rate (r : Nat) (i : Nat) : Nat := if i % 20 * 5 < r then 1 else 0

private def still (k : Nat) (r : Nat) : List Frame := (List.range k).map fun i => ⟨rate r i, none, none⟩

private def baseTwo (r : Nat) : List Arm := [[still 50 r], [still 50 r]]

private def numsJ (x : Nums) : Json :=
  Json.mkObj [("nb", x.nb), ("nf", x.nf), ("n", x.n), ("b", x.b), ("f", x.f), ("h", x.h), ("spread", x.spread)]

private def armJ (a : Arm) : Json :=
  Json.arr (a.map fun w => Json.arr (w.map fun f => Json.arr #[toJson f.recalcs, Json.null, Json.null]).toArray).toArray

private def cellJ (c : Cell) : Json :=
  Json.mkObj [("baseOn", Json.arr (c.baseOn.map armJ).toArray), ("baseOff", armJ c.baseOff), ("holdOn", armJ c.holdOn)]

private def cellCases : List (String × Nat × Cell) :=
  [("at floor", minIdle, ⟨baseTwo 100, [still 50 0], [still 50 0]⟩),
   ("at floor plus band", minIdle, ⟨baseTwo 100, [still 50 0], [still 50 5]⟩),
   ("cuts partly", minIdle, ⟨baseTwo 100, [still 50 0], [still 50 75]⟩),
   ("no cut", minIdle, ⟨baseTwo 100, [still 50 0], [still 50 100]⟩),
   ("unread", minIdle, ⟨baseTwo 100, [still 50 0], [still 10 0]⟩),
   ("no contrast", minIdle, ⟨baseTwo 100, [still 50 100], [still 50 100]⟩)]

private def numsCases : List (String × Nat × Nums) :=
  let ok : Nums := ⟨100, 100, 100, 100, 0, 100, 0, 0, 0⟩
  [("edge at floor", 40, { ok with h := 6 }), ("edge above the floor band", 40, { ok with h := 7 }),
   ("edge no cut", 40, { ok with h := 94 }), ("edge cuts partly", 40, { ok with h := 93 }),
   ("spread widens the band", 40, { ok with h := 12, spread := 12 }), ("edge contrast", 40, { ok with b := 50 }),
   ("edge no contrast", 40, { ok with b := 49 }), ("edge informative", 40, { ok with spread := 49 }),
   ("edge uninformative", 40, { ok with spread := 50 }), ("variant above base", 40, { ok with h := 120 }),
   ("edge unread", 40, { ok with n := 39 }), ("edge read", 40, { ok with n := 40 })]

private def overallCases : List (String × List VC) :=
  [("three at floor", [.atFloor, .atFloor, .atFloor]), ("two at floor one unread", [.atFloor, .unread, .atFloor]),
   ("one judged", [.partly, .unread, .uninformative]), ("mixed", [.atFloor, .partly, .atFloor]),
   ("three partly", [.partly, .partly, .partly]), ("three no cut", [.noCut, .noCut, .noCut]),
   ("none judged", [.noContrast, .noContrast, .uninformative])]

private def vJ (v : VC) : Json := Json.str v.name

private def liveCases : List (String × Nat × Nat × Nums) :=
  let ok : Nums := ⟨100, 100, 100, 100, 0, 100, 0, 0, 0⟩
  [("live zero", 40, 0, ok), ("live zero over a floor read", 40, 0, { ok with h := 0 }), ("one live", 40, 1, { ok with h := 0 }),
   ("two live partly", 40, 2, { ok with h := 80 }), ("live zero unread", 40, 0, { ok with n := 10 })]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("minIdle", minIdle), ("minFlip", minFlip), ("minSpread", minSpread), ("bandDen", bandDen),
    ("minValid", minValid)]).compress] ++
  (numsCases.map fun (n, m, x) =>
    (Json.mkObj [("kind", "judge"), ("name", n), ("minF", m), ("nums", numsJ x), ("band", x.band), ("verdict", vJ (judgeC m x))]).compress) ++
  (liveCases.map fun (n, m, l, x) =>
    (Json.mkObj [("kind", "live"), ("name", n), ("minF", m), ("live", l), ("nums", numsJ x), ("verdict", vJ (judgeLive m l x))]).compress) ++
  (cellCases.map fun (n, m, c) =>
    let x := c.nums
    (Json.mkObj [("kind", "cell"), ("name", n), ("minF", m), ("cell", cellJ c), ("nums", numsJ x), ("band", x.band),
      ("verdict", vJ (judgeC m x))]).compress) ++
  (overallCases.map fun (n, vs) =>
    (Json.mkObj [("kind", "overall"), ("name", n), ("verdicts", Json.arr (vs.map vJ).toArray), ("overall", (overallC vs).name)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "glint-compositor.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"device-glint-compositor golden differs: {goldenPath}")
  IO.println s!"device-glint-compositor golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.GlintHoldCompositor
