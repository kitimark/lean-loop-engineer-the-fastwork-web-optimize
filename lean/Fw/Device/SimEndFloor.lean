import Lean.Data.Json
import Fw.Device.EndFloorDirty

/-! # sim-end-floor: end-of-page style-recalc floor on the iOS Simulator, per arm and per flag -/
namespace Fw.Device.SimEndFloor

open Lean Fw.Device.EndWktr Fw.Device.EndFloorDirty

def band : Nat := 10

theorem band_eq : band = floorBand := rfl

def winRaf : Nat := 360

def minSeen : Nat := EndFloorDirty.minFrames

theorem minSeen_le_winRaf : minSeen ≤ winRaf := by decide

def minRounds : Nat := minValid

structure Win where
  raf : Nat
  seen : Nat
  recalcs : Nat
  deriving DecidableEq, Repr

def Win.rate (w : Win) : Nat := if w.raf = 0 then 0 else w.recalcs * 100 / w.raf

def Win.readable (w : Win) : Bool := w.raf == winRaf && minSeen ≤ w.seen

theorem readable_raf (w : Win) (h : w.readable = true) : w.raf = winRaf := by
  simp [Win.readable] at h
  exact h.1

theorem readable_seen (w : Win) (h : w.readable = true) : minSeen ≤ w.seen := by
  simp [Win.readable] at h
  exact h.2

theorem rate_zero_recalcs (w : Win) (h : w.recalcs = 0) : w.rate = 0 := by simp [Win.rate, h]

theorem rate_every_frame (w : Win) (h0 : w.raf ≠ 0) (h : w.recalcs = w.raf) : w.rate = 100 := by
  simp only [Win.rate, h0, h, ite_false]
  have : 0 < w.raf := Nat.pos_of_ne_zero h0
  rw [Nat.mul_comm]
  exact Nat.mul_div_cancel _ this

inductive FlagV where
  | unreadable
  | noFloor
  | baseFloor
  | carries
  | partialCut
  | none
  deriving DecidableEq, Repr

def FlagV.name : FlagV → String
  | .unreadable => "unreadable" | .noFloor => "noFloor" | .baseFloor => "baseFloor" | .carries => "carries"
  | .partialCut => "partial" | .none => "none"

def flagV (full minusF base : Win) : FlagV :=
  if !(full.readable && minusF.readable && base.readable) then .unreadable
  else if full.rate ≤ band then .noFloor
  else if band < base.rate then .baseFloor
  else if minusF.rate ≤ band then .carries
  else if minusF.rate + band < full.rate then .partialCut
  else .none

theorem flagV_unreadable (full minusF base : Win) (h : (full.readable && minusF.readable && base.readable) = false) :
    flagV full minusF base = .unreadable := by simp [flagV, h]

theorem flagV_noFloor (full minusF base : Win) (h0 : (full.readable && minusF.readable && base.readable) = true)
    (h : full.rate ≤ band) : flagV full minusF base = .noFloor := by simp [flagV, h0, h]

theorem flagV_baseFloor (full minusF base : Win) (h0 : (full.readable && minusF.readable && base.readable) = true)
    (h1 : ¬ full.rate ≤ band) (h : band < base.rate) : flagV full minusF base = .baseFloor := by simp [flagV, h0, h1, h]

theorem flagV_carries (full minusF base : Win) (h0 : (full.readable && minusF.readable && base.readable) = true)
    (h1 : ¬ full.rate ≤ band) (h2 : ¬ band < base.rate) (h : minusF.rate ≤ band) : flagV full minusF base = .carries := by
  simp [flagV, h0, h1, h2, h]

theorem flagV_partial (full minusF base : Win) (h0 : (full.readable && minusF.readable && base.readable) = true)
    (h1 : ¬ full.rate ≤ band) (h2 : ¬ band < base.rate) (h3 : ¬ minusF.rate ≤ band) (h : minusF.rate + band < full.rate) :
    flagV full minusF base = .partialCut := by simp [flagV, h0, h1, h2, h3, h]

theorem flagV_none (full minusF base : Win) (h0 : (full.readable && minusF.readable && base.readable) = true)
    (h1 : ¬ full.rate ≤ band) (h2 : ¬ band < base.rate) (h3 : ¬ minusF.rate ≤ band) (h : ¬ minusF.rate + band < full.rate) :
    flagV full minusF base = .none := by simp [flagV, h0, h1, h2, h3, h]

theorem carries_cuts (full minusF base : Win) (h : flagV full minusF base = .carries) :
    band < full.rate ∧ minusF.rate ≤ band ∧ base.rate ≤ band := by
  unfold flagV at h
  split at h <;> try (simp at h; done)
  split at h <;> try (simp at h; done)
  split at h <;> try (simp at h; done)
  split at h
  · refine ⟨by omega, by assumption, by omega⟩
  · split at h <;> simp at h

theorem none_keeps (full minusF base : Win) (h : flagV full minusF base = .none) :
    band < minusF.rate ∧ full.rate ≤ minusF.rate + band := by
  unfold flagV at h
  split at h <;> try (simp at h; done)
  split at h <;> try (simp at h; done)
  split at h <;> try (simp at h; done)
  split at h
  · simp at h
  · split at h
    · simp at h
    · refine ⟨by omega, by omega⟩

structure Round where
  base : Win
  v2p : Win
  minusT : Win
  minusU : Win
  deriving DecidableEq, Repr

def Round.flags (r : Round) : FlagV × FlagV := (flagV r.v2p r.minusT r.base, flagV r.v2p r.minusU r.base)

inductive Pair where
  | unreadable
  | noFloor
  | baseFloor
  | threaded
  | unthrottle
  | both
  | sharedOrOther
  | mixed
  deriving DecidableEq, Repr

def Pair.name : Pair → String
  | .unreadable => "unreadable" | .noFloor => "noFloor" | .baseFloor => "baseFloor" | .threaded => "threaded"
  | .unthrottle => "unthrottle" | .both => "both" | .sharedOrOther => "sharedOrOther" | .mixed => "mixed"

def pair (vt vu : FlagV) : Pair :=
  match vt, vu with
  | .unreadable, _ => .unreadable
  | _, .unreadable => .unreadable
  | .noFloor, _ => .noFloor
  | _, .noFloor => .noFloor
  | .baseFloor, _ => .baseFloor
  | _, .baseFloor => .baseFloor
  | .carries, .carries => .both
  | .carries, .none => .threaded
  | .none, .carries => .unthrottle
  | .none, .none => .sharedOrOther
  | _, _ => .mixed

theorem pair_unreadable_left (vu : FlagV) : pair .unreadable vu = .unreadable := by cases vu <;> rfl

theorem pair_unreadable_right (vt : FlagV) : pair vt .unreadable = .unreadable := by cases vt <;> rfl

theorem pair_noFloor_left (vu : FlagV) (h : vu ≠ .unreadable) : pair .noFloor vu = .noFloor := by cases vu <;> simp_all [pair]

theorem pair_noFloor_right (vt : FlagV) (h : vt ≠ .unreadable) : pair vt .noFloor = .noFloor := by cases vt <;> simp_all [pair]

theorem pair_baseFloor_left (vu : FlagV) (h : vu ≠ .unreadable ∧ vu ≠ .noFloor) : pair .baseFloor vu = .baseFloor := by
  cases vu <;> simp_all [pair]

theorem pair_baseFloor_right (vt : FlagV) (h : vt ≠ .unreadable ∧ vt ≠ .noFloor) : pair vt .baseFloor = .baseFloor := by
  cases vt <;> simp_all [pair]

theorem pair_both : pair .carries .carries = .both := rfl

theorem pair_threaded : pair .carries .none = .threaded := rfl

theorem pair_unthrottle : pair .none .carries = .unthrottle := rfl

theorem pair_shared : pair .none .none = .sharedOrOther := rfl

theorem pair_mixed_partial_left (vu : FlagV) (h : vu = .carries ∨ vu = .none ∨ vu = .partialCut) : pair .partialCut vu = .mixed := by
  rcases h with h | h | h <;> subst h <;> rfl

theorem pair_mixed_partial_right (vt : FlagV) (h : vt = .carries ∨ vt = .none ∨ vt = .partialCut) : pair vt .partialCut = .mixed := by
  rcases h with h | h | h <;> subst h <;> rfl

def Round.pair (r : Round) : Pair := Fw.Device.SimEndFloor.pair r.flags.1 r.flags.2

def wktrPair : Pair := .sharedOrOther

inductive Cmp where
  | unread
  | same
  | different
  deriving DecidableEq, Repr

def Cmp.name : Cmp → String
  | .unread => "unread" | .same => "same" | .different => "different"

def cmp (p : Pair) : Cmp := if p = .unreadable then .unread else if p = wktrPair then .same else .different

theorem cmp_unread : cmp .unreadable = .unread := rfl

theorem cmp_same : cmp wktrPair = .same := rfl

theorem cmp_different (p : Pair) (h1 : p ≠ .unreadable) (h2 : p ≠ wktrPair) : cmp p = .different := by simp [cmp, h1, h2]

def overallFlag (vs : List FlagV) : String := overallNames ((vs.filter fun v => v != .unreadable).map FlagV.name)

def overallPair (ps : List Pair) : String := overallNames ((ps.filter fun p => p != .unreadable).map Pair.name)

theorem overallFlag_inconclusive (vs : List FlagV) (h : (vs.filter fun v => v != .unreadable).length < minRounds) :
    overallFlag vs = "inconclusive" := by
  simpa [overallFlag] using overallNames_inconclusive _ (by simpa [minRounds] using h)

theorem overallPair_inconclusive (ps : List Pair) (h : (ps.filter fun p => p != .unreadable).length < minRounds) :
    overallPair ps = "inconclusive" := by
  simpa [overallPair] using overallNames_inconclusive _ (by simpa [minRounds] using h)

private def w (seen recalcs : Nat) : Win := ⟨winRaf, seen, recalcs⟩

private def flagCases : List (String × Win × Win × Win) :=
  [("raf differs", ⟨100, 100, 100⟩, w 360 36, w 360 3), ("too few seen", w 100 360, w 360 36, w 360 3),
   ("no floor", w 360 36, w 360 36, w 360 3), ("base keeps a floor", w 360 360, w 360 36, w 360 360),
   ("carries", w 360 360, w 360 3, w 360 3), ("minusF at the band", w 360 360, w 360 39, w 360 3),
   ("minusF one above the band", w 360 360, w 360 40, w 360 3), ("partial", w 360 360, w 360 180, w 360 3),
   ("partial one over the band", w 360 360, w 360 321, w 360 3), ("none", w 360 360, w 360 360, w 360 3),
   ("none at the margin", w 360 360, w 360 324, w 360 3), ("none below the margin", w 360 360, w 360 327, w 360 3), ("full at the band", w 360 39, w 360 0, w 360 0),
   ("full one above the band", w 360 40, w 360 0, w 360 0), ("base at the band", w 360 360, w 360 0, w 360 39),
   ("base one above the band", w 360 360, w 360 0, w 360 40)]

private def pairCases : List (String × FlagV × FlagV) :=
  [("unreadable first", .unreadable, .none), ("unreadable second", .none, .unreadable), ("no floor", .noFloor, .noFloor),
   ("no floor first", .noFloor, .none), ("base floor", .baseFloor, .baseFloor), ("base floor second", .carries, .baseFloor),
   ("both", .carries, .carries), ("threaded", .carries, .none), ("unthrottle", .none, .carries),
   ("shared", .none, .none), ("partial first", .partialCut, .none), ("partial second", .carries, .partialCut),
   ("partial both", .partialCut, .partialCut)]

private def overallFlagCases : List (String × List FlagV) :=
  [("all none", [.none, .none, .none]), ("one carries", [.none, .carries, .none]), ("one unreadable", [.none, .unreadable, .none]),
   ("two unreadable", [.none, .unreadable, .unreadable])]

private def overallPairCases : List (String × List Pair) :=
  [("all shared", [.sharedOrOther, .sharedOrOther, .sharedOrOther]), ("one threaded", [.sharedOrOther, .threaded, .sharedOrOther]),
   ("one unreadable", [.threaded, .unreadable, .threaded]), ("two unreadable", [.threaded, .unreadable, .unreadable])]

private def pairNames : List Pair := [.unreadable, .noFloor, .baseFloor, .threaded, .unthrottle, .both, .sharedOrOther, .mixed]

private def wJ (x : Win) : Json := Json.mkObj [("raf", x.raf), ("seen", x.seen), ("recalcs", x.recalcs)]

private def flagJ (v : FlagV) : Json := Json.str v.name

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("band", band), ("winRaf", winRaf), ("minSeen", minSeen), ("minRounds", minRounds)]).compress] ++
  (flagCases.map fun (n, f, m, b) =>
    (Json.mkObj [("kind", "flag"), ("name", n), ("full", wJ f), ("minusF", wJ m), ("base", wJ b), ("rate", f.rate),
      ("verdict", Json.str (flagV f m b).name)]).compress) ++
  (pairCases.map fun (n, a, b) =>
    (Json.mkObj [("kind", "pair"), ("name", n), ("threaded", flagJ a), ("unthrottle", flagJ b),
      ("verdict", Json.str (pair a b).name)]).compress) ++
  (pairNames.map fun p =>
    (Json.mkObj [("kind", "cmp"), ("pair", Json.str p.name), ("verdict", Json.str (cmp p).name)]).compress) ++
  (overallFlagCases.map fun (n, vs) =>
    (Json.mkObj [("kind", "overallFlag"), ("name", n), ("verdicts", Json.arr (vs.map flagJ).toArray),
      ("overall", Json.str (overallFlag vs))]).compress) ++
  (overallPairCases.map fun (n, ps) =>
    (Json.mkObj [("kind", "overallPair"), ("name", n), ("verdicts", Json.arr (ps.map fun p => Json.str p.name).toArray),
      ("overall", Json.str (overallPair ps))]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "sim-end-floor.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"sim-end-floor golden differs: {goldenPath}")
  IO.println s!"sim-end-floor golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.SimEndFloor
