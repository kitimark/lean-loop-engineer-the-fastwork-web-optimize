import Lean.Data.Json
/-! End of page on the WKTR flip arm: verdict rules for per-100-frame counts. -/
namespace Fw.Device.EndWktr
open Lean

def minFlip : Nat := 12

def minSpreadRecalc : Nat := 50

def minSpreadOther : Nat := 20

def bandDen : Nat := 16

def minValid : Nat := 2

def rpf100 (fs : List Nat) : Nat := if fs.length = 0 then 0 else fs.sum * 100 / fs.length

def spreadOf (xs : List Nat) : Nat := xs.foldl max 0 - xs.foldl min (xs.foldl max 0)

structure Cell where
  base : List (List Nat)
  floor : List Nat
  var : List Nat
  deriving DecidableEq, Repr

structure Nums where
  nb : Nat
  nf : Nat
  n : Nat
  b : Nat
  f : Nat
  v : Nat
  spread : Nat
  deriving DecidableEq, Repr

def Cell.nums (c : Cell) : Nums where
  nb := (c.base.map List.length).sum
  nf := c.floor.length
  n := c.var.length
  b := rpf100 c.base.flatten
  f := rpf100 c.floor
  v := rpf100 c.var
  spread := spreadOf (c.base.map rpf100)

def Nums.s (x : Nums) : Nat := x.b - x.f

def Nums.band (x : Nums) : Nat := max (x.s / bandDen) x.spread

def Nums.atFloor (x : Nums) : Bool := decide (x.v ≤ x.f + x.band)

inductive V where
  | unread | noContrast | uninformative | cuts | noChange | adds
  deriving DecidableEq, Repr

def V.name : V → String
  | .unread => "unread" | .noContrast => "no-contrast" | .uninformative => "uninformative"
  | .cuts => "cuts" | .noChange => "no change" | .adds => "adds"

def V.judged : V → Bool
  | .cuts | .noChange | .adds => true
  | _ => false

def judge (minF minS : Nat) (x : Nums) : V :=
  if x.nb < minF ∨ x.nf < minF ∨ x.n < minF then .unread
  else if x.b < x.f + minS then .noContrast
  else if x.s ≤ 2 * x.band then .uninformative
  else if x.v + x.band < x.b then .cuts
  else if x.b + x.band < x.v then .adds
  else .noChange

theorem judge_unread (minF minS : Nat) (x : Nums) (h : x.nb < minF ∨ x.nf < minF ∨ x.n < minF) : judge minF minS x = .unread := by
  simp [judge, h]

theorem judge_noContrast (minF minS : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF)) (h : x.b < x.f + minS) :
    judge minF minS x = .noContrast := by
  simp only [judge, h0, ite_false, h, ite_true]

theorem judge_uninformative (minF minS : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF))
    (h1 : ¬x.b < x.f + minS) (h : x.s ≤ 2 * x.band) : judge minF minS x = .uninformative := by
  simp only [judge, h0, ite_false, h1, h, ite_true]

theorem judge_cuts (minF minS : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF))
    (h1 : ¬x.b < x.f + minS) (h2 : ¬x.s ≤ 2 * x.band) (h : x.v + x.band < x.b) : judge minF minS x = .cuts := by
  simp only [judge, h0, ite_false, h1, h2, h, ite_true]

theorem judge_adds (minF minS : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF))
    (h1 : ¬x.b < x.f + minS) (h2 : ¬x.s ≤ 2 * x.band) (h3 : ¬x.v + x.band < x.b) (h : x.b + x.band < x.v) :
    judge minF minS x = .adds := by
  simp only [judge, h0, ite_false, h1, h2, h3, h, ite_true]

theorem judge_noChange (minF minS : Nat) (x : Nums) (h0 : ¬(x.nb < minF ∨ x.nf < minF ∨ x.n < minF))
    (h1 : ¬x.b < x.f + minS) (h2 : ¬x.s ≤ 2 * x.band) (h3 : ¬x.v + x.band < x.b) (h4 : ¬x.b + x.band < x.v) :
    judge minF minS x = .noChange := by
  simp only [judge, h0, ite_false, h1, h2, h3, h4]

theorem cuts_spec (minF minS : Nat) (x : Nums) (h : judge minF minS x = .cuts) :
    x.f + minS ≤ x.b ∧ 2 * x.band < x.s ∧ x.v + x.band < x.b := by
  by_cases c1 : x.nb < minF ∨ x.nf < minF ∨ x.n < minF
  · rw [judge_unread minF minS x c1] at h; simp at h
  by_cases c2 : x.b < x.f + minS
  · rw [judge_noContrast minF minS x c1 c2] at h; simp at h
  by_cases c3 : x.s ≤ 2 * x.band
  · rw [judge_uninformative minF minS x c1 c2 c3] at h; simp at h
  by_cases c4 : x.v + x.band < x.b
  · exact ⟨by omega, by omega, c4⟩
  by_cases c5 : x.b + x.band < x.v
  · rw [judge_adds minF minS x c1 c2 c3 c4 c5] at h; simp at h
  · rw [judge_noChange minF minS x c1 c2 c3 c4 c5] at h; simp at h

theorem adds_spec (minF minS : Nat) (x : Nums) (h : judge minF minS x = .adds) :
    x.f + minS ≤ x.b ∧ 2 * x.band < x.s ∧ x.b + x.band < x.v := by
  by_cases c1 : x.nb < minF ∨ x.nf < minF ∨ x.n < minF
  · rw [judge_unread minF minS x c1] at h; simp at h
  by_cases c2 : x.b < x.f + minS
  · rw [judge_noContrast minF minS x c1 c2] at h; simp at h
  by_cases c3 : x.s ≤ 2 * x.band
  · rw [judge_uninformative minF minS x c1 c2 c3] at h; simp at h
  by_cases c4 : x.v + x.band < x.b
  · rw [judge_cuts minF minS x c1 c2 c3 c4] at h; simp at h
  by_cases c5 : x.b + x.band < x.v
  · exact ⟨by omega, by omega, c5⟩
  · rw [judge_noChange minF minS x c1 c2 c3 c4 c5] at h; simp at h

theorem noChange_spec (minF minS : Nat) (x : Nums) (h : judge minF minS x = .noChange) :
    x.v ≤ x.b + x.band ∧ x.b ≤ x.v + x.band := by
  by_cases c1 : x.nb < minF ∨ x.nf < minF ∨ x.n < minF
  · rw [judge_unread minF minS x c1] at h; simp at h
  by_cases c2 : x.b < x.f + minS
  · rw [judge_noContrast minF minS x c1 c2] at h; simp at h
  by_cases c3 : x.s ≤ 2 * x.band
  · rw [judge_uninformative minF minS x c1 c2 c3] at h; simp at h
  by_cases c4 : x.v + x.band < x.b
  · rw [judge_cuts minF minS x c1 c2 c3 c4] at h; simp at h
  by_cases c5 : x.b + x.band < x.v
  · rw [judge_adds minF minS x c1 c2 c3 c4 c5] at h; simp at h
  · omega

theorem cuts_ne_adds (minF minS : Nat) (x : Nums) (h : judge minF minS x = .cuts) : judge minF minS x ≠ .adds := by
  rw [h]; simp

theorem cuts_lt_base (minF minS : Nat) (x : Nums) (h : judge minF minS x = .cuts) : x.v < x.b := by
  have := cuts_spec minF minS x h
  omega

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

theorem overall_mixed (a b : V) (ha : a.judged = true) (hb : b.judged = true) (hab : a ≠ b) : overall [a, b] = .mixed := by
  cases a <;> cases b <;> first | exact absurd rfl hab | (revert ha hb; decide)

structure Trio where
  f : Nat
  p : Nat
  v : Nat
  band : Nat
  deriving DecidableEq, Repr

inductive Cause where
  | none | running | markup | both | offset
  deriving DecidableEq, Repr

def Cause.name : Cause → String
  | .none => "no residual" | .running => "the running animation" | .markup => "the variant markup"
  | .both => "markup and running animation" | .offset => "floor offset between processes"

def causeOf (t : Trio) : Cause :=
  if t.v ≤ t.f + t.band then .none
  else if t.p + t.band < t.v then (if t.f + t.band < t.p then .both else .running)
  else if t.f + t.band < t.p then .markup else .offset

theorem cause_none (t : Trio) (h : t.v ≤ t.f + t.band) : causeOf t = .none := by
  simp [causeOf, h]

theorem cause_running (t : Trio) (h0 : ¬t.v ≤ t.f + t.band) (h1 : t.p + t.band < t.v) (h2 : ¬t.f + t.band < t.p) :
    causeOf t = .running := by
  simp [causeOf, h0, h1, h2]

theorem cause_both (t : Trio) (h0 : ¬t.v ≤ t.f + t.band) (h1 : t.p + t.band < t.v) (h2 : t.f + t.band < t.p) :
    causeOf t = .both := by
  simp [causeOf, h0, h1, h2]

theorem cause_markup (t : Trio) (h0 : ¬t.v ≤ t.f + t.band) (h1 : ¬t.p + t.band < t.v) (h2 : t.f + t.band < t.p) :
    causeOf t = .markup := by
  simp [causeOf, h0, h1, h2]

theorem cause_offset (t : Trio) (h0 : ¬t.v ≤ t.f + t.band) (h1 : ¬t.p + t.band < t.v) (h2 : ¬t.f + t.band < t.p) :
    causeOf t = .offset := by
  simp [causeOf, h0, h1, h2]

theorem offset_le (t : Trio) (h : causeOf t = .offset) : t.v ≤ t.f + 2 * t.band := by
  by_cases c0 : t.v ≤ t.f + t.band
  · omega
  by_cases c1 : t.p + t.band < t.v
  · by_cases c2 : t.f + t.band < t.p
    · rw [cause_both t c0 c1 c2] at h; simp at h
    · rw [cause_running t c0 c1 c2] at h; simp at h
  · by_cases c2 : t.f + t.band < t.p
    · rw [cause_markup t c0 c1 c2] at h; simp at h
    · omega

structure SFrame where
  r : Nat
  written : Bool
  elems : Bool
  deriving DecidableEq, Repr

inductive Cat where
  | written | animated | empty
  deriving DecidableEq, Repr

def Cat.name : Cat → String
  | .written => "written" | .animated => "animated" | .empty => "empty"

def catOf (f : SFrame) : Option Cat :=
  if f.r = 0 then none else if f.written then some .written else if f.elems then some .animated else some .empty

def catSum (c : Cat) : List SFrame → Nat
  | [] => 0
  | f :: t => (if catOf f = some c then f.r else 0) + catSum c t

def catRate (c : Cat) (fs : List SFrame) : Nat := if fs.length = 0 then 0 else catSum c fs * 100 / fs.length

private theorem frame_partition (f : SFrame) :
    (if catOf f = some .written then f.r else 0) + (if catOf f = some .animated then f.r else 0) +
      (if catOf f = some .empty then f.r else 0) = f.r := by
  unfold catOf
  by_cases h0 : f.r = 0 <;> by_cases h1 : f.written = true <;> by_cases h2 : f.elems = true <;> simp [h0, h1, h2]

theorem catSum_partition (fs : List SFrame) :
    catSum .written fs + catSum .animated fs + catSum .empty fs = (fs.map (·.r)).sum := by
  induction fs with
  | nil => simp [catSum]
  | cons f t ih =>
    have := frame_partition f
    simp only [catSum, List.map_cons, List.sum_cons]
    omega

inductive Mech where
  | nothing | one (c : Cat) | several
  deriving DecidableEq, Repr

def Mech.name : Mech → String
  | .nothing => "nothing above the band" | .one c => s!"one category: {c.name}" | .several => "several categories"

def above (band : Nat) (live paused : List SFrame) : List Cat :=
  [Cat.written, .animated, .empty].filter fun c => band < catRate c live - catRate c paused

def mechOf (band : Nat) (live paused : List SFrame) : Mech :=
  match above band live paused with
  | [] => .nothing
  | [c] => .one c
  | _ => .several

theorem mech_nothing (band : Nat) (l p : List SFrame) (h : above band l p = []) : mechOf band l p = .nothing := by
  simp [mechOf, h]

theorem mech_one (band : Nat) (l p : List SFrame) (c : Cat) (h : above band l p = [c]) : mechOf band l p = .one c := by
  simp [mechOf, h]

theorem mech_several (band : Nat) (l p : List SFrame) (a b : Cat) (t : List Cat) (h : above band l p = a :: b :: t) :
    mechOf band l p = .several := by
  simp [mechOf, h]

def Mech.next : Mech → String
  | .nothing => "no candidate: the residual is not in the recalcs"
  | .one .written => "stop the DOM write the top key names while the flip runs"
  | .one .animated => "find the animation that restyles elements in the flip and hold it for the flip"
  | .one .empty => "no page-side fix: read the WebKit invalidation path for a recalc that restyles no element"
  | .several => "one intervention arm per category above the band"

def overallNames (ns : List String) : String :=
  match ns with
  | [] => "inconclusive"
  | n :: rest => if ns.length < minValid then "inconclusive" else if rest.all (· == n) then n else "mixed"

theorem overallNames_inconclusive (ns : List String) (h : ns.length < minValid) : overallNames ns = "inconclusive" := by
  cases ns with
  | nil => simp [overallNames]
  | cons c t =>
    have : ¬minValid ≤ t.length + 1 := by simp at h; omega
    simp [overallNames, this]

theorem overallNames_alike (n : String) (rest : List String) (hn : minValid ≤ rest.length + 1) (hall : ∀ w ∈ rest, w = n) :
    overallNames (n :: rest) = n := by
  have h1 : ¬(n :: rest).length < minValid := by simp; omega
  have h2 : rest.all (· == n) = true := by
    simp only [List.all_eq_true, beq_iff_eq]
    intro w hw; exact hall w hw
  simp only [overallNames, h1, h2, ite_false, ite_true]

theorem overallNames_mixed (n : String) (rest : List String) (hn : minValid ≤ rest.length + 1) (w : String) (hw : w ∈ rest) (hne : w ≠ n) :
    overallNames (n :: rest) = "mixed" := by
  have h1 : ¬(n :: rest).length < minValid := by simp; omega
  have h2 : ¬(rest.all (· == n) = true) := by
    intro hc
    simp only [List.all_eq_true, beq_iff_eq] at hc
    exact hne (hc w hw)
  have h3 : rest.all (· == n) = false := by simpa using h2
  simp only [overallNames, h1, h3, ite_false]
  rfl

def overallCause (cs : List Cause) : String := overallNames (cs.map Cause.name)

def overallMech (ms : List Mech) : String := overallNames (ms.map Mech.name)

private def rate (r : Nat) (i : Nat) : Nat := if i % 20 * 5 < r then 1 else 0

private def still (k : Nat) (r : Nat) : List Nat := (List.range k).map (rate r)

private def baseTwo (r : Nat) : List (List Nat) := [still 50 r, still 50 r]

private def numsJ (x : Nums) : Json :=
  Json.mkObj [("nb", x.nb), ("nf", x.nf), ("n", x.n), ("b", x.b), ("f", x.f), ("v", x.v), ("spread", x.spread)]

private def listJ (xs : List Nat) : Json := Json.arr (xs.map fun x => toJson x).toArray

private def cellJ (c : Cell) : Json :=
  Json.mkObj [("base", Json.arr (c.base.map listJ).toArray), ("floor", listJ c.floor), ("var", listJ c.var)]

private def cellCases : List (String × Nat × Nat × Cell) :=
  [("cuts to the floor", minFlip, minSpreadRecalc, ⟨baseTwo 100, still 50 0, still 50 0⟩),
   ("cuts partly", minFlip, minSpreadRecalc, ⟨baseTwo 100, still 50 0, still 50 75⟩),
   ("no change", minFlip, minSpreadRecalc, ⟨baseTwo 100, still 50 0, still 50 100⟩),
   ("adds", minFlip, minSpreadRecalc, ⟨[still 50 60, still 50 60], still 50 0, still 50 100⟩),
   ("unread", minFlip, minSpreadRecalc, ⟨baseTwo 100, still 50 0, still 10 0⟩),
   ("uninformative", minFlip, minSpreadRecalc, ⟨[still 50 100, still 50 40], still 50 0, still 50 0⟩),
   ("no contrast", minFlip, minSpreadRecalc, ⟨baseTwo 100, still 50 100, still 50 100⟩),
   ("layout needs less contrast", minFlip, minSpreadOther, ⟨baseTwo 30, still 50 0, still 50 0⟩)]

private def numsCases : List (String × Nat × Nat × Nums) :=
  let ok : Nums := ⟨100, 100, 100, 100, 0, 100, 0⟩
  [("edge cuts", minFlip, minSpreadRecalc, { ok with v := 93 }), ("edge no change below", minFlip, minSpreadRecalc, { ok with v := 94 }),
   ("edge no change above", minFlip, minSpreadRecalc, { ok with v := 106 }), ("edge adds", minFlip, minSpreadRecalc, { ok with v := 107 }),
   ("spread widens the band", minFlip, minSpreadRecalc, { ok with v := 80, spread := 20 }),
   ("edge contrast", minFlip, minSpreadRecalc, { ok with b := 50 }), ("edge no contrast", minFlip, minSpreadRecalc, { ok with b := 49 }),
   ("edge informative", minFlip, minSpreadRecalc, { ok with spread := 49, v := 0 }), ("edge uninformative", minFlip, minSpreadRecalc, { ok with spread := 50 }),
   ("edge unread", minFlip, minSpreadRecalc, { ok with n := 11 }), ("edge read", minFlip, minSpreadRecalc, { ok with n := 12 }),
   ("other metric contrast", minFlip, minSpreadOther, { ok with b := 20 })]

private def overallCases : List (String × List V) :=
  [("three cut", [.cuts, .cuts, .cuts]), ("two cut one unread", [.cuts, .unread, .cuts]), ("one judged", [.adds, .unread, .uninformative]),
   ("mixed", [.cuts, .noChange, .cuts]), ("three no change", [.noChange, .noChange, .noChange]), ("three add", [.adds, .adds, .adds]),
   ("none judged", [.noContrast, .noContrast, .uninformative])]

private def trioCases : List (String × Trio) :=
  [("at floor", ⟨70, 70, 74, 6⟩), ("edge at floor", ⟨70, 70, 76, 6⟩), ("running", ⟨70, 72, 90, 6⟩), ("both", ⟨70, 90, 110, 6⟩),
   ("markup", ⟨70, 90, 92, 6⟩), ("offset", ⟨70, 75, 80, 6⟩), ("edge running", ⟨70, 72, 79, 6⟩), ("edge offset", ⟨70, 72, 78, 6⟩)]

private def causeCases : List (String × List Cause) :=
  [("three offset", [.offset, .offset, .offset]), ("two none", [.none, .none]), ("one job", [.running]), ("mixed", [.running, .offset, .running])]

private def mechOverallCases : List (String × List Mech) :=
  [("three empty", [.one .empty, .one .empty, .one .empty]), ("mixed", [.one .empty, .one .written]), ("one job", [.several])]

private def sframeJ (f : SFrame) : Json := Json.arr #[toJson f.r, toJson (if f.written then 1 else 0), toJson (if f.elems then 1 else 0)]

private def mk (r : Nat) (w e : Bool) : SFrame := ⟨r, w, e⟩

private def quiet (k : Nat) : List SFrame := (List.range k).map fun _ => mk 0 false false

private def mechCases : List (String × Nat × List SFrame × List SFrame) :=
  [("nothing", 6, quiet 20, quiet 20),
   ("one written", 6, mk 2 true true :: mk 1 true false :: quiet 18, quiet 20),
   ("one animated", 6, mk 2 false true :: mk 1 false true :: quiet 18, quiet 20),
   ("one empty", 6, mk 2 false false :: mk 1 false false :: quiet 18, quiet 20),
   ("several", 6, mk 2 true true :: mk 2 false false :: quiet 18, quiet 20),
   ("paused arm has them too", 6, mk 2 true true :: quiet 19, mk 2 true true :: quiet 19),
   ("zero frames", 6, [], [])]

private def vJ (v : V) : Json := Json.str v.name

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("minFlip", minFlip), ("minSpreadRecalc", minSpreadRecalc), ("minSpreadOther", minSpreadOther),
    ("bandDen", bandDen), ("minValid", minValid)]).compress] ++
  (numsCases.map fun (n, mf, ms, x) =>
    (Json.mkObj [("kind", "judge"), ("name", n), ("minF", mf), ("minS", ms), ("nums", numsJ x), ("band", x.band), ("atFloor", x.atFloor),
      ("verdict", vJ (judge mf ms x))]).compress) ++
  (cellCases.map fun (n, mf, ms, c) =>
    let x := c.nums
    (Json.mkObj [("kind", "cell"), ("name", n), ("minF", mf), ("minS", ms), ("cell", cellJ c), ("nums", numsJ x), ("band", x.band),
      ("atFloor", x.atFloor), ("verdict", vJ (judge mf ms x))]).compress) ++
  (overallCases.map fun (n, vs) =>
    (Json.mkObj [("kind", "overall"), ("name", n), ("verdicts", Json.arr (vs.map vJ).toArray), ("overall", (overall vs).name)]).compress) ++
  (trioCases.map fun (n, t) =>
    (Json.mkObj [("kind", "cause"), ("name", n), ("f", t.f), ("p", t.p), ("v", t.v), ("band", t.band), ("cause", (causeOf t).name)]).compress) ++
  (causeCases.map fun (n, cs) =>
    (Json.mkObj [("kind", "overallCause"), ("name", n), ("causes", Json.arr (cs.map fun c => Json.str c.name).toArray),
      ("overall", overallCause cs)]).compress) ++
  (mechOverallCases.map fun (n, ms) =>
    (Json.mkObj [("kind", "overallMech"), ("name", n), ("mechs", Json.arr (ms.map fun m => Json.str m.name).toArray),
      ("overall", overallMech ms)]).compress) ++
  (mechCases.map fun (n, band, l, p) =>
    (Json.mkObj [("kind", "mech"), ("name", n), ("band", band), ("live", Json.arr (l.map sframeJ).toArray), ("paused", Json.arr (p.map sframeJ).toArray),
      ("rates", Json.arr ([Cat.written, .animated, .empty].map fun c => toJson (catRate c l)).toArray),
      ("pausedRates", Json.arr ([Cat.written, .animated, .empty].map fun c => toJson (catRate c p)).toArray),
      ("mech", (mechOf band l p).name), ("next", (mechOf band l p).next)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "end-wktr.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"device-end-wktr golden differs: {goldenPath}")
  IO.println s!"device-end-wktr golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.EndWktr
