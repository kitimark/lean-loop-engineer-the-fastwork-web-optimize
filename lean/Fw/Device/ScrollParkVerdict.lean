import Lean.Data.Json
import Fw.Device.EndFloorDirty

/-!
# scrolldriven-park verdicts: the end-of-page floor split per scroll-driven flag, and the park variants' effect

Readings are recalcs per 100 rAF callbacks of one arm (`EndFloorDirty.Reading`). The band is the floor band of the
end-floor lane (`EndFloorDirty.floorBand`), a named constant shared with that lane.
-/
namespace Fw.Device.ScrollParkVerdict

open Lean Fw.Device.EndWktr Fw.Device.EndFloorDirty

/-- A rate at or below this is no floor. -/
def band : Nat := floorBand

/-- Fewest frames of a readable arm. -/
def minRead : Nat := minFrames

theorem band_eq : band = 10 := rfl

/-- The split verdict of one flag F, from four arms: `full` (both flags), `minusF` (the other flag only), `onlyF`
(F only) and `base` (neither). -/
inductive S where
  | unread
  | noFloor
  | baseFloor
  | innocent
  | sole
  | shared
deriving DecidableEq, Repr

def S.name : S → String
  | .unread => "unread" | .noFloor => "noFloor" | .baseFloor => "baseFloor"
  | .innocent => "innocent" | .sole => "sole" | .shared => "shared"

/-- Four readings of the split. -/
structure Split where
  full : Reading
  minusF : Reading
  onlyF : Reading
  base : Reading
deriving DecidableEq, Repr

def Split.short (x : Split) : Bool :=
  x.full.frames < minRead || x.minusF.frames < minRead || x.onlyF.frames < minRead || x.base.frames < minRead

/-- Which of the flag's two readings holds the floor. -/
def split (x : Split) : S :=
  if x.short then .unread
  else if x.full.rate ≤ band then .noFloor
  else if band < x.base.rate then .baseFloor
  else if x.onlyF.rate ≤ band then .innocent
  else if x.minusF.rate ≤ band then .sole
  else .shared

theorem split_unread (x : Split) (h : x.short = true) : split x = .unread := by simp [split, h]

theorem split_noFloor (x : Split) (h0 : x.short = false) (h : x.full.rate ≤ band) : split x = .noFloor := by simp [split, h0, h]

theorem split_baseFloor (x : Split) (h0 : x.short = false) (h1 : ¬ x.full.rate ≤ band) (h : band < x.base.rate) :
    split x = .baseFloor := by simp [split, h0, h1, h]

theorem split_innocent (x : Split) (h0 : x.short = false) (h1 : ¬ x.full.rate ≤ band) (h2 : ¬ band < x.base.rate)
    (h : x.onlyF.rate ≤ band) : split x = .innocent := by simp [split, h0, h1, h2, h]

theorem split_sole (x : Split) (h0 : x.short = false) (h1 : ¬ x.full.rate ≤ band) (h2 : ¬ band < x.base.rate)
    (h3 : ¬ x.onlyF.rate ≤ band) (h : x.minusF.rate ≤ band) : split x = .sole := by simp [split, h0, h1, h2, h3, h]

theorem split_shared (x : Split) (h0 : x.short = false) (h1 : ¬ x.full.rate ≤ band) (h2 : ¬ band < x.base.rate)
    (h3 : ¬ x.onlyF.rate ≤ band) (h : ¬ x.minusF.rate ≤ band) : split x = .shared := by simp [split, h0, h1, h2, h3, h]

/-- A flag that is `sole` or `shared` holds the floor alone. -/
theorem carries_alone (x : Split) (h : split x = .sole ∨ split x = .shared) : band < x.onlyF.rate := by
  unfold split at h
  split at h <;> try (simp at h; done)
  split at h <;> try (simp at h; done)
  split at h <;> try (simp at h; done)
  split at h
  · simp at h
  · omega

/-- The park verdict of one arm against the reference arm. -/
inductive P where
  | unread
  | noFloor
  | cut
  | partialCut
  | noEffect
deriving DecidableEq, Repr

def P.name : P → String
  | .unread => "unread" | .noFloor => "noFloor" | .cut => "cut" | .partialCut => "partial" | .noEffect => "none"

def readable (on off : Reading) : Bool := minRead ≤ on.frames && minRead ≤ off.frames && on.frames == off.frames

def park (on off : Reading) : P :=
  if !readable on off then .unread
  else if on.rate ≤ band then .noFloor
  else if off.rate ≤ band then .cut
  else if off.rate + band < on.rate then .partialCut
  else .noEffect

theorem park_unread (on off : Reading) (h : readable on off = false) : park on off = .unread := by simp [park, h]

theorem park_noFloor (on off : Reading) (h0 : readable on off = true) (h : on.rate ≤ band) : park on off = .noFloor := by
  simp [park, h0, h]

theorem park_cut (on off : Reading) (h0 : readable on off = true) (h1 : ¬ on.rate ≤ band) (h : off.rate ≤ band) :
    park on off = .cut := by simp [park, h0, h1, h]

theorem park_partial (on off : Reading) (h0 : readable on off = true) (h1 : ¬ on.rate ≤ band) (h2 : ¬ off.rate ≤ band)
    (h : off.rate + band < on.rate) : park on off = .partialCut := by simp [park, h0, h1, h2, h]

theorem park_none (on off : Reading) (h0 : readable on off = true) (h1 : ¬ on.rate ≤ band) (h2 : ¬ off.rate ≤ band)
    (h : ¬ off.rate + band < on.rate) : park on off = .noEffect := by simp [park, h0, h1, h2, h]

/-- A cut leaves the arm in the band. -/
theorem cut_in_band (on off : Reading) (h : park on off = .cut) : off.rate ≤ band := by
  unfold park at h
  split at h <;> try (simp at h; done)
  split at h <;> try (simp at h; done)
  split at h
  · assumption
  · split at h <;> simp at h

/-- Verdicts across jobs: the shared rule of the lane. -/
def overallS (ss : List S) : String := overallNames ((ss.filter fun s => s != .unread).map S.name)

def overallP (ps : List P) : String := overallNames ((ps.filter fun p => p != .unread).map P.name)

theorem overallS_inconclusive (ss : List S) (h : (ss.filter fun s => s != .unread).length < minValid) :
    overallS ss = "inconclusive" := by
  simpa [overallS] using overallNames_inconclusive _ (by simpa using h)

theorem overallP_inconclusive (ps : List P) (h : (ps.filter fun p => p != .unread).length < minValid) :
    overallP ps = "inconclusive" := by
  simpa [overallP] using overallNames_inconclusive _ (by simpa using h)

private def r (f c : Nat) : Reading := ⟨f, c⟩

private def splitCases : List (String × Split) :=
  [("short", ⟨r 100 100, r 576 590, r 576 590, r 576 25⟩), ("no floor", ⟨r 576 25, r 576 25, r 576 25, r 576 25⟩),
   ("base keeps a floor", ⟨r 576 590, r 576 590, r 576 590, r 576 590⟩),
   ("the flag alone holds nothing", ⟨r 576 590, r 576 590, r 576 25, r 576 25⟩),
   ("sole carrier", ⟨r 576 590, r 576 25, r 576 590, r 576 25⟩),
   ("shared carrier", ⟨r 576 590, r 576 590, r 576 590, r 576 25⟩),
   ("onlyF at the band", ⟨r 576 590, r 576 590, r 576 57, r 576 25⟩),
   ("onlyF one above the band", ⟨r 576 590, r 576 590, r 576 58, r 576 25⟩),
   ("minusF at the band", ⟨r 576 590, r 576 57, r 576 590, r 576 25⟩),
   ("minusF one above the band", ⟨r 576 590, r 576 58, r 576 590, r 576 25⟩),
   ("base at the band", ⟨r 576 590, r 576 57, r 576 590, r 576 57⟩),
   ("base one above the band", ⟨r 576 590, r 576 57, r 576 590, r 576 58⟩)]

private def parkCases : List (String × Reading × Reading) :=
  [("short", r 100 100, r 100 5), ("frames differ", r 576 590, r 575 5), ("no floor", r 576 25, r 576 5),
   ("cut", r 576 590, r 576 25), ("cut at the band", r 576 590, r 576 57), ("partial", r 576 590, r 576 300),
   ("partial one over the band", r 576 590, r 576 58), ("none", r 576 590, r 576 585), ("none at the margin", r 576 590, r 576 530)]

private def sCases : List (String × List S) :=
  [("all shared", [.shared, .shared, .shared]), ("one sole", [.shared, .sole, .shared]), ("one unread", [.shared, .unread, .shared]),
   ("two unread", [.shared, .unread, .unread])]

private def pCases : List (String × List P) :=
  [("all cut", [.cut, .cut, .cut]), ("one partial", [.cut, .partialCut, .cut]), ("one unread", [.cut, .unread, .cut]),
   ("two unread", [.cut, .unread, .unread])]

private def rJ (x : Reading) : Json := Json.mkObj [("frames", x.frames), ("recalcs", x.recalcs)]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("band", band), ("minRead", minRead)]).compress] ++
  (splitCases.map fun (n, x) =>
    (Json.mkObj [("kind", "split"), ("name", n), ("full", rJ x.full), ("minusF", rJ x.minusF), ("onlyF", rJ x.onlyF), ("base", rJ x.base),
      ("verdict", Json.str (split x).name)]).compress) ++
  (parkCases.map fun (n, on, off) =>
    (Json.mkObj [("kind", "park"), ("name", n), ("on", rJ on), ("off", rJ off), ("verdict", Json.str (park on off).name)]).compress) ++
  (sCases.map fun (n, ss) =>
    (Json.mkObj [("kind", "overallS"), ("name", n), ("verdicts", Json.arr (ss.map fun s => Json.str s.name).toArray),
      ("overall", Json.str (overallS ss))]).compress) ++
  (pCases.map fun (n, ps) =>
    (Json.mkObj [("kind", "overallP"), ("name", n), ("verdicts", Json.arr (ps.map fun p => Json.str p.name).toArray),
      ("overall", Json.str (overallP ps))]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "scroll-park-verdict.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"scroll-park-verdict golden differs: {goldenPath}")
  IO.println s!"scroll-park-verdict golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.ScrollParkVerdict
