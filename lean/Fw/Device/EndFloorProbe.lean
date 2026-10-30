import Lean.Data.Json
import Fw.Device.EndFloorWindow
namespace Fw.Device.EndFloorProbe
open Lean Fw.Device.EndWktr Fw.Device.EndFloorWindow

def probeBand : Nat := 10

def minFrames : Nat := pinN * minReps

inductive Src where
  | raf | update
  deriving DecidableEq, Repr

def Src.name : Src → String
  | .raf => "rAF callbacks" | .update => "rendering updates"

structure Reading where
  frames : Nat
  recalcs : Nat
  src : Src
  deriving DecidableEq, Repr

def Reading.rate (x : Reading) : Nat := if x.frames = 0 then 0 else x.recalcs * 100 / x.frames

inductive V where
  | probeCauses | probePartial | probeInnocent | noFloor | unread
  deriving DecidableEq, Repr

def V.name : V → String
  | .probeCauses => "probeCauses" | .probePartial => "probePartial" | .probeInnocent => "probeInnocent"
  | .noFloor => "noFloor" | .unread => "unread"

def readable (on off : Reading) : Bool :=
  minFrames ≤ on.frames && minFrames ≤ off.frames && !(on.src == .raf && off.src == .raf && on.frames != off.frames)

def verdict (on off : Reading) : V :=
  if !readable on off then .unread
  else if on.rate ≤ probeBand then .noFloor
  else if off.rate ≤ probeBand then .probeCauses
  else if off.rate + probeBand < on.rate then .probePartial
  else .probeInnocent

theorem verdict_unread_on_short (on off : Reading) (h : on.frames < minFrames) : verdict on off = .unread := by
  have : readable on off = false := by simp [readable]; omega
  simp [verdict, this]

theorem verdict_unread_off_short (on off : Reading) (h : off.frames < minFrames) : verdict on off = .unread := by
  have : readable on off = false := by simp [readable]; omega
  simp [verdict, this]

theorem verdict_unread_unequal (on off : Reading) (hs : on.src = .raf) (ho : off.src = .raf) (hf : on.frames ≠ off.frames) :
    verdict on off = .unread := by
  have : readable on off = false := by simp [readable, hs, ho, hf]
  simp [verdict, this]

theorem verdict_noFloor (on off : Reading) (hr : readable on off = true) (h : on.rate ≤ probeBand) : verdict on off = .noFloor := by
  simp [verdict, hr, h]

theorem verdict_causes (on off : Reading) (hr : readable on off = true) (h1 : probeBand < on.rate) (h2 : off.rate ≤ probeBand) :
    verdict on off = .probeCauses := by
  have : ¬ on.rate ≤ probeBand := by omega
  simp [verdict, hr, this, h2]

theorem verdict_partial (on off : Reading) (hr : readable on off = true) (h1 : probeBand < on.rate) (h2 : probeBand < off.rate)
    (h3 : off.rate + probeBand < on.rate) : verdict on off = .probePartial := by
  have a : ¬ on.rate ≤ probeBand := by omega
  have b : ¬ off.rate ≤ probeBand := by omega
  simp [verdict, hr, a, b, h3]

theorem verdict_innocent (on off : Reading) (hr : readable on off = true) (h1 : probeBand < on.rate) (h2 : probeBand < off.rate)
    (h3 : on.rate ≤ off.rate + probeBand) : verdict on off = .probeInnocent := by
  have a : ¬ on.rate ≤ probeBand := by omega
  have b : ¬ off.rate ≤ probeBand := by omega
  have c : ¬ off.rate + probeBand < on.rate := by omega
  simp [verdict, hr, a, b, c]

theorem causes_lowers (on off : Reading) (h : verdict on off = .probeCauses) : off.rate < on.rate := by
  unfold verdict at h
  by_cases h0 : (!readable on off) = true
  · simp [h0] at h
  by_cases h1 : on.rate ≤ probeBand
  · simp [h0, h1] at h
  by_cases h2 : off.rate ≤ probeBand
  · omega
  · simp [h0, h1, h2] at h
    by_cases h3 : off.rate + probeBand < on.rate <;> simp [h3] at h

theorem self_never_blames (x : Reading) : verdict x x = .unread ∨ verdict x x = .noFloor ∨ verdict x x = .probeInnocent := by
  by_cases hr : readable x x = true
  · by_cases h1 : x.rate ≤ probeBand
    · exact Or.inr (Or.inl (verdict_noFloor x x hr h1))
    · exact Or.inr (Or.inr (verdict_innocent x x hr (by omega) (by omega) (by omega)))
  · have : (!readable x x) = true := by simpa using hr
    exact Or.inl (by simp [verdict, this])

def overall (vs : List V) : String := overallNames ((vs.filter fun v => v != .unread).map V.name)

theorem overall_inconclusive (vs : List V) (h : (vs.filter fun v => v != .unread).length < minValid) : overall vs = "inconclusive" := by
  simpa [overall] using overallNames_inconclusive _ (by simpa using h)

structure Seen where
  made : Nat
  idle : Nat
  deriving DecidableEq, Repr

def Seen.allIdle (s : Seen) : Bool := 0 < s.made && s.idle == s.made

def cancelFrom : Nat → List Seen → Option Nat
  | _, [] => none
  | i, s :: ss => if s.allIdle then some i else cancelFrom (i + 1) ss

def cancelFrame (ss : List Seen) : Option Nat := cancelFrom 0 ss

theorem cancelFrame_nil : cancelFrame [] = none := rfl

theorem cancelFrom_none (i : Nat) (ss : List Seen) : cancelFrom i ss = none ↔ ∀ s ∈ ss, s.allIdle = false := by
  induction ss generalizing i with
  | nil => simp [cancelFrom]
  | cons s t ih =>
    by_cases h : s.allIdle = true
    · simp [cancelFrom, h]
    · have h' : s.allIdle = false := by simpa using h
      simp [cancelFrom, h', ih]

theorem cancelFrame_none (ss : List Seen) : cancelFrame ss = none ↔ ∀ s ∈ ss, s.allIdle = false := cancelFrom_none 0 ss

theorem cancelFrom_some (i : Nat) (ss : List Seen) (k : Nat) (h : cancelFrom i ss = some k) :
    i ≤ k ∧ (∃ s, ss[k - i]? = some s ∧ s.allIdle = true) ∧ ∀ j, j < k - i → ∀ s, ss[j]? = some s → s.allIdle = false := by
  induction ss generalizing i k with
  | nil => simp [cancelFrom] at h
  | cons s t ih =>
    by_cases hs : s.allIdle = true
    · simp only [cancelFrom, hs, ite_true, Option.some.injEq] at h
      subst h
      refine ⟨Nat.le_refl _, ⟨s, by simp, hs⟩, ?_⟩
      intro j hj; omega
    · have hs' : s.allIdle = false := by simpa using hs
      simp only [cancelFrom, hs', Bool.false_eq_true, ite_false] at h
      obtain ⟨h1, ⟨s2, h2, h3⟩, h4⟩ := ih (i + 1) k h
      refine ⟨by omega, ⟨s2, ?_, h3⟩, ?_⟩
      · have e : k - i = (k - (i + 1)) + 1 := by omega
        rw [e]; simpa using h2
      · intro j hj s' hs2
        cases j with
        | zero => simp at hs2; subst hs2; exact hs'
        | succ j' =>
          simp at hs2
          exact h4 j' (by omega) s' hs2

theorem cancelFrame_first (ss : List Seen) (k : Nat) (h : cancelFrame ss = some k) :
    (∃ s, ss[k]? = some s ∧ s.allIdle = true) ∧ ∀ j, j < k → ∀ s, ss[j]? = some s → s.allIdle = false := by
  have := cancelFrom_some 0 ss k h
  simpa using this.2

inductive Cv where
  | allCancelled | someCancelled | noneCancelled | unread
  deriving DecidableEq, Repr

def Cv.name : Cv → String
  | .allCancelled => "all cancelled" | .someCancelled => "some cancelled" | .noneCancelled => "none cancelled" | .unread => "unread"

def cancelVerdict (cs : List (Option Nat)) : Cv :=
  if cs.length < minReps then .unread
  else if cs.all Option.isSome then .allCancelled
  else if cs.any Option.isSome then .someCancelled
  else .noneCancelled

theorem cancelVerdict_unread (cs : List (Option Nat)) (h : cs.length < minReps) : cancelVerdict cs = .unread := by
  simp [cancelVerdict, h]

theorem cancelVerdict_all (cs : List (Option Nat)) (h0 : ¬ cs.length < minReps) (h : cs.all Option.isSome = true) :
    cancelVerdict cs = .allCancelled := by
  simp [cancelVerdict, h0, h]

theorem cancelVerdict_some (cs : List (Option Nat)) (h0 : ¬ cs.length < minReps) (h : cs.all Option.isSome = false)
    (h2 : cs.any Option.isSome = true) : cancelVerdict cs = .someCancelled := by
  simp [cancelVerdict, h0, h, h2]

theorem cancelVerdict_none (cs : List (Option Nat)) (h0 : ¬ cs.length < minReps) (h : cs.all Option.isSome = false)
    (h2 : cs.any Option.isSome = false) : cancelVerdict cs = .noneCancelled := by
  simp [cancelVerdict, h0, h, h2]

def cancelSpan (cs : List (Option Nat)) : Option (Nat × Nat) :=
  match cs.filterMap id with
  | [] => none
  | v :: vs => some (vs.foldl min v, vs.foldl max v)

private def rd (frames recalcs : Nat) (src : Src := .raf) : Reading := ⟨frames, recalcs, src⟩

private def readJ (x : Reading) : Json :=
  Json.mkObj [("frames", x.frames), ("recalcs", x.recalcs), ("src", Json.str (match x.src with | .raf => "raf" | .update => "update"))]

private def pairCases : List (String × Reading × Reading) :=
  [("probe explains the floor", rd 576 588, rd 576 4), ("probe explains, off exactly at the band", rd 576 588, rd 576 58),
   ("off one above the band, large drop", rd 576 588, rd 576 64), ("probe adds part", rd 576 588, rd 576 300),
   ("drop exactly the band", rd 576 588, rd 576 530), ("drop one over the band", rd 576 588, rd 576 529),
   ("probe innocent", rd 576 588, rd 576 588), ("off above on", rd 576 300, rd 576 588),
   ("no floor with the probe on", rd 576 20, rd 576 3), ("no floor, on exactly at the band", rd 576 58, rd 576 0),
   ("on one above the band, off zero", rd 576 64, rd 576 0),
   ("unequal rAF windows", rd 576 588, rd 528 0), ("on short", rd 287 300, rd 576 0), ("off short", rd 576 588, rd 287 0),
   ("no frames", rd 0 0, rd 576 0), ("rendering-update source, any frame count", rd 576 588, rd 900 9 .update),
   ("both update-counted, unequal frames", rd 700 700, rd 900 900 .update)]

private def cancelCases : List (String × List Seen) :=
  [("none made", []), ("cancelled at creation sample", [⟨4, 4⟩]), ("never idle", [⟨4, 0⟩, ⟨4, 2⟩, ⟨4, 3⟩]),
   ("idle after three", [⟨4, 0⟩, ⟨4, 0⟩, ⟨4, 2⟩, ⟨4, 4⟩, ⟨4, 4⟩]), ("zero created is not idle", [⟨0, 0⟩, ⟨3, 0⟩, ⟨3, 3⟩]),
   ("idle then more tracks", [⟨2, 2⟩, ⟨5, 2⟩, ⟨5, 5⟩]), ("grows then idle", [⟨1, 0⟩, ⟨55, 10⟩, ⟨55, 55⟩])]

private def cvCases : List (String × List (Option Nat)) :=
  [("all cancelled", List.replicate pinReps (some 30)), ("minimum reps", List.replicate minReps (some 2)),
   ("one rep short", List.replicate (minReps - 1) (some 2)),
   ("one never", none :: List.replicate (pinReps - 1) (some 28)), ("none cancel", List.replicate pinReps none),
   ("no reps", []), ("spread", [some 29, some 31, some 33, some 29, some 30, some 40, some 28, none])]

private def vsCases : List (String × List V) :=
  [("three alike", [.probeCauses, .probeCauses, .probeCauses]), ("one unread", [.probeCauses, .unread, .probeCauses]),
   ("two unread", [.probeInnocent, .unread, .unread]), ("one differs", [.probeInnocent, .probePartial, .probeInnocent]),
   ("no floor", [.noFloor, .noFloor, .noFloor])]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("probeBand", probeBand), ("minFrames", minFrames)]).compress] ++
  (pairCases.map fun (n, on, off) =>
    (Json.mkObj [("kind", "pair"), ("name", n), ("on", readJ on), ("off", readJ off), ("onRate", on.rate), ("offRate", off.rate),
      ("verdict", Json.str (verdict on off).name)]).compress) ++
  (vsCases.map fun (n, vs) =>
    (Json.mkObj [("kind", "overall"), ("name", n), ("verdicts", Json.arr (vs.map fun v => Json.str v.name).toArray),
      ("overall", Json.str (overall vs))]).compress) ++
  (cancelCases.map fun (n, ss) =>
    (Json.mkObj [("kind", "cancel"), ("name", n),
      ("seen", Json.arr (ss.map fun s => Json.arr #[toJson s.made, toJson s.idle]).toArray),
      ("frame", match cancelFrame ss with | some k => toJson k | none => Json.null)]).compress) ++
  (cvCases.map fun (n, cs) =>
    (Json.mkObj [("kind", "cv"), ("name", n),
      ("cancels", Json.arr (cs.map fun c => match c with | some k => toJson k | none => Json.null).toArray),
      ("verdict", Json.str (cancelVerdict cs).name),
      ("span", match cancelSpan cs with | some (a, b) => Json.arr #[toJson a, toJson b] | none => Json.null)]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "end-floor-probe.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"device-end-floor-probe golden differs: {goldenPath}")
  IO.println s!"device-end-floor-probe golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.EndFloorProbe
