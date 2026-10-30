import Lean.Data.Json
import Fw.Device.EndFloorProbe
namespace Fw.Device.EndFloorDirty
open Lean Fw.Device.EndWktr

/-- Recalcs per 100 frames at or below which the floor counts as gone (the probe band). -/
def floorBand : Nat := EndFloorProbe.probeBand

/-- Percent of recalc frames in which one name must be dirty to be the carrier. -/
def carrierShare : Nat := 90

/-- Percent of recalc frames with no dirty name at all for the document-level verdict. -/
def documentShare : Nat := 90

/-- Leading frames of every rep that are not read: the flip tracks may still run there. -/
def skipFrames : Nat := 8

/-- Frames a reading needs, after the skipped ones. -/
def minFrames : Nat := EndFloorProbe.minFrames

/-- One sampled frame: recalcs in the frame, names dirty at the start of the frame's rAF callback (`h`), names dirty in
the first task after the frame's rendering update (`e`). -/
structure Frame where
  r : Nat
  h : List String
  e : List String
  deriving DecidableEq, Repr

/-- A frame's recalcs against the names that vary around it: dirty in some of the three samples that bracket the frame
(`prev`, the previous frame's first task after its update; `h`, the rAF start; `e`, the first task after the frame's own
update) and clean in another, so something cleaned or made them dirty. A name dirty in all three is inert: the resolver
leaves it alone (or it is made dirty again before every sample) and the samples cannot tell it from a carrier. -/
def varies (prev : List String) (f : Frame) : List String :=
  ((prev ++ f.h ++ f.e).eraseDups).filter fun n => !(prev.contains n && f.h.contains n && f.e.contains n)

def pair : List String → List Frame → List (Nat × List String)
  | _, [] => []
  | prev, f :: fs => (f.r, varies prev f) :: pair f.e fs

/-- A name dirty in all three samples of a frame is not offered as a cause. -/
theorem varies_inert (prev : List String) (f : Frame) (n : String) (hp : n ∈ prev) (hh : n ∈ f.h) (he : n ∈ f.e) :
    n ∉ varies prev f := by
  simp [varies, hp, hh, he]

/-- A name dirty in the sample after the update and clean at the rAF start of the same frame is offered. -/
theorem varies_cleaned (prev : List String) (f : Frame) (n : String) (he : n ∈ f.e) (hh : n ∉ f.h) :
    n ∈ varies prev f := by
  simp [varies, he, hh]

/-- The read frames of one rep. -/
def repSets (fs : List Frame) : List (Nat × List String) := (pair [] fs).drop skipFrames

def hitN : List (Nat × List String) → Nat
  | [] => 0
  | (r, _) :: xs => (if 0 < r then 1 else 0) + hitN xs

def bareN : List (Nat × List String) → Nat
  | [] => 0
  | (r, s) :: xs => (if 0 < r && s.isEmpty then 1 else 0) + bareN xs

def countName (n : String) : List (Nat × List String) → Nat
  | [] => 0
  | (r, s) :: xs => (if 0 < r && s.contains n then 1 else 0) + countName n xs

def recalcN : List (Nat × List String) → Nat
  | [] => 0
  | (r, _) :: xs => r + recalcN xs

def rate (xs : List (Nat × List String)) : Nat := if xs.length = 0 then 0 else recalcN xs * 100 / xs.length

def names (xs : List (Nat × List String)) : List String := (xs.flatMap (·.2)).eraseDups

/-- `a` beats `b`: more recalc frames with the name dirty, or the same count and the smaller name (element names `e:`
sort before part names `p:`). -/
def better (xs : List (Nat × List String)) (a b : String) : Bool :=
  countName b xs < countName a xs || (countName a xs == countName b xs && decide (a < b))

def top (xs : List (Nat × List String)) : Option String :=
  (names xs).foldl (fun acc n => match acc with
    | none => some n
    | some m => if better xs n m then some n else acc) none

inductive D where
  | unread | noFloor | documentLevel | carrier (name : String) | spread
  deriving DecidableEq, Repr

def D.kind : D → String
  | .unread => "unread" | .noFloor => "noFloor" | .documentLevel => "documentLevel" | .carrier _ => "carrier" | .spread => "spread"

def D.name : D → String
  | .carrier n => "carrier " ++ n
  | d => d.kind

def verdict (xs : List (Nat × List String)) : D :=
  if xs.length < minFrames then .unread
  else if rate xs ≤ floorBand then .noFloor
  else if documentShare * hitN xs ≤ 100 * bareN xs then .documentLevel
  else match top xs with
    | some n => if carrierShare * hitN xs ≤ 100 * countName n xs then .carrier n else .spread
    | none => .spread

theorem verdict_unread (xs : List (Nat × List String)) (h : xs.length < minFrames) : verdict xs = .unread := by
  simp [verdict, h]

theorem verdict_noFloor (xs : List (Nat × List String)) (h0 : ¬ xs.length < minFrames) (h : rate xs ≤ floorBand) :
    verdict xs = .noFloor := by
  simp [verdict, h0, h]

theorem verdict_documentLevel (xs : List (Nat × List String)) (h0 : ¬ xs.length < minFrames) (h1 : ¬ rate xs ≤ floorBand)
    (h : documentShare * hitN xs ≤ 100 * bareN xs) : verdict xs = .documentLevel := by
  simp [verdict, h0, h1, h]

theorem verdict_carrier (xs : List (Nat × List String)) (n : String) (h0 : ¬ xs.length < minFrames) (h1 : ¬ rate xs ≤ floorBand)
    (h2 : ¬ documentShare * hitN xs ≤ 100 * bareN xs) (ht : top xs = some n) (h : carrierShare * hitN xs ≤ 100 * countName n xs) :
    verdict xs = .carrier n := by
  simp [verdict, h0, h1, h2, ht, h]

theorem verdict_spread_low (xs : List (Nat × List String)) (n : String) (h0 : ¬ xs.length < minFrames) (h1 : ¬ rate xs ≤ floorBand)
    (h2 : ¬ documentShare * hitN xs ≤ 100 * bareN xs) (ht : top xs = some n) (h : ¬ carrierShare * hitN xs ≤ 100 * countName n xs) :
    verdict xs = .spread := by
  simp [verdict, h0, h1, h2, ht, h]

theorem verdict_spread_none (xs : List (Nat × List String)) (h0 : ¬ xs.length < minFrames) (h1 : ¬ rate xs ≤ floorBand)
    (h2 : ¬ documentShare * hitN xs ≤ 100 * bareN xs) (ht : top xs = none) : verdict xs = .spread := by
  simp [verdict, h0, h1, h2, ht]

/-- A carrier verdict carries the share it was given for. -/
theorem carrier_share (xs : List (Nat × List String)) (n : String) (h : verdict xs = .carrier n) :
    carrierShare * hitN xs ≤ 100 * countName n xs := by
  unfold verdict at h
  by_cases h0 : xs.length < minFrames
  · simp [h0] at h
  by_cases h1 : rate xs ≤ floorBand
  · simp [h0, h1] at h
  by_cases h2 : documentShare * hitN xs ≤ 100 * bareN xs
  · simp [h0, h1, h2] at h
  cases ht : top xs with
  | none => simp [h0, h1, h2, ht] at h
  | some m =>
    by_cases h3 : carrierShare * hitN xs ≤ 100 * countName m xs
    · simp [h0, h1, h2, ht, h3] at h
      subst h
      exact h3
    · simp [h0, h1, h2, ht, h3] at h

/-- A frame with recalcs and a name dirty is not a frame with recalcs and no name: the two shares compete. -/
theorem count_add_bare_le (n : String) (xs : List (Nat × List String)) : countName n xs + bareN xs ≤ hitN xs := by
  induction xs with
  | nil => simp [countName, bareN, hitN]
  | cons x t ih =>
    obtain ⟨r, s⟩ := x
    cases s with
    | nil => by_cases hr : 0 < r <;> simp [countName, bareN, hitN, hr] <;> omega
    | cons a b => by_cases hr : 0 < r <;> by_cases hc : (n = a ∨ n ∈ b) <;> simp [countName, bareN, hitN, hr, hc] <;> omega

/-- The document-level and carrier conditions cannot both hold on a reading with recalc frames. -/
theorem document_and_carrier_exclusive (xs : List (Nat × List String)) (n : String) (hh : 0 < hitN xs)
    (hd : documentShare * hitN xs ≤ 100 * bareN xs) (hc : carrierShare * hitN xs ≤ 100 * countName n xs) : False := by
  have := count_add_bare_le n xs
  simp [documentShare, carrierShare] at hd hc
  omega

/-- What the hide arm says about a named carrier. -/
inductive H where
  | unread | unmatched | noReference | confirmed | notConfirmed
  deriving DecidableEq, Repr

def H.name : H → String
  | .unread => "unread" | .unmatched => "unmatched" | .noReference => "noReference" | .confirmed => "confirmed"
  | .notConfirmed => "notConfirmed"

structure Reading where
  frames : Nat
  recalcs : Nat
  deriving DecidableEq, Repr

def Reading.rate (x : Reading) : Nat := if x.frames = 0 then 0 else x.recalcs * 100 / x.frames

def hideVerdict (carrier : String) (hidden : Option String) (ref hide : Reading) : H :=
  if ref.frames < minFrames || hide.frames < minFrames then .unread
  else if hidden != some carrier then .unmatched
  else if ref.rate ≤ floorBand then .noReference
  else if hide.rate ≤ floorBand then .confirmed
  else .notConfirmed

theorem hide_unread (c : String) (hd : Option String) (ref hide : Reading)
    (h : ref.frames < minFrames ∨ hide.frames < minFrames) : hideVerdict c hd ref hide = .unread := by
  rcases h with h | h <;> simp [hideVerdict, h]

theorem hide_unmatched (c : String) (hd : Option String) (ref hide : Reading) (h1 : ¬ ref.frames < minFrames)
    (h2 : ¬ hide.frames < minFrames) (h : hd ≠ some c) : hideVerdict c hd ref hide = .unmatched := by
  simp [hideVerdict, h1, h2, h]

theorem hide_noReference (c : String) (ref hide : Reading) (h1 : ¬ ref.frames < minFrames) (h2 : ¬ hide.frames < minFrames)
    (h : ref.rate ≤ floorBand) : hideVerdict c (some c) ref hide = .noReference := by
  simp [hideVerdict, h1, h2, h]

theorem hide_confirmed (c : String) (ref hide : Reading) (h1 : ¬ ref.frames < minFrames) (h2 : ¬ hide.frames < minFrames)
    (h3 : ¬ ref.rate ≤ floorBand) (h : hide.rate ≤ floorBand) : hideVerdict c (some c) ref hide = .confirmed := by
  simp [hideVerdict, h1, h2, h3, h]

theorem hide_notConfirmed (c : String) (ref hide : Reading) (h1 : ¬ ref.frames < minFrames) (h2 : ¬ hide.frames < minFrames)
    (h3 : ¬ ref.rate ≤ floorBand) (h : ¬ hide.rate ≤ floorBand) : hideVerdict c (some c) ref hide = .notConfirmed := by
  simp [hideVerdict, h1, h2, h3, h]

/-- A confirmed hide lowered the rate from above the band to the band or below. -/
theorem confirmed_lowers (c : String) (hd : Option String) (ref hide : Reading) (h : hideVerdict c hd ref hide = .confirmed) :
    hide.rate ≤ floorBand ∧ floorBand < ref.rate := by
  unfold hideVerdict at h
  by_cases h0 : (ref.frames < minFrames || hide.frames < minFrames) = true
  · simp [h0] at h
  by_cases h1 : (hd != some c) = true
  · simp [h0, h1] at h
  by_cases h2 : ref.rate ≤ floorBand
  · simp [h0, h1, h2] at h
  by_cases h3 : hide.rate ≤ floorBand
  · exact ⟨h3, by omega⟩
  · simp [h0, h1, h2, h3] at h

/-- Where the document-level dirt sits, read from a forced style flush (`getComputedStyle`) in the frame loop. `auto` are
the recalcs the rendering update made on its own, `flush` those the forced flush made. -/
inductive F where
  | unread | none | held | arises | both
  deriving DecidableEq, Repr

def F.name : F → String
  | .unread => "unread" | .none => "none" | .held => "held" | .arises => "arises" | .both => "both"

structure Flushed where
  frames : Nat
  auto : Nat
  flush : Nat
  deriving DecidableEq, Repr

/-- `held`: the flush finds the dirt pending and the next update has none of its own; `arises`: the flush finds nothing
and the next update recalcs anyway. -/
def flushVerdict (x : Flushed) : F :=
  if x.frames < minFrames then .unread
  else
    let a := floorBand < x.auto * 100 / x.frames
    let f := floorBand < x.flush * 100 / x.frames
    if a && f then .both else if f then .held else if a then .arises else .none

theorem flush_unread (x : Flushed) (h : x.frames < minFrames) : flushVerdict x = .unread := by
  simp [flushVerdict, h]

theorem flush_held (x : Flushed) (h0 : ¬ x.frames < minFrames) (hf : floorBand < x.flush * 100 / x.frames)
    (ha : ¬ floorBand < x.auto * 100 / x.frames) : flushVerdict x = .held := by
  simp [flushVerdict, h0, hf, ha]

theorem flush_arises (x : Flushed) (h0 : ¬ x.frames < minFrames) (hf : ¬ floorBand < x.flush * 100 / x.frames)
    (ha : floorBand < x.auto * 100 / x.frames) : flushVerdict x = .arises := by
  simp [flushVerdict, h0, hf, ha]

theorem flush_none (x : Flushed) (h0 : ¬ x.frames < minFrames) (hf : ¬ floorBand < x.flush * 100 / x.frames)
    (ha : ¬ floorBand < x.auto * 100 / x.frames) : flushVerdict x = .none := by
  simp [flushVerdict, h0, hf, ha]

theorem flush_both (x : Flushed) (h0 : ¬ x.frames < minFrames) (hf : floorBand < x.flush * 100 / x.frames)
    (ha : floorBand < x.auto * 100 / x.frames) : flushVerdict x = .both := by
  simp [flushVerdict, h0, hf, ha]

/-- Verdict strings of the jobs; unread jobs are left out, fewer than two judged jobs is inconclusive. -/
def overall (ds : List D) : String := overallNames ((ds.filter fun d => d != .unread).map D.name)

theorem overall_inconclusive (ds : List D) (h : (ds.filter fun d => d != .unread).length < minValid) : overall ds = "inconclusive" := by
  simpa [overall] using overallNames_inconclusive _ (by simpa using h)

/-- Hide verdicts of the jobs, unread left out; a carrier is confirmed overall only if every judged job confirmed it. -/
def hideOverall (hs : List H) : String := overallNames ((hs.filter fun h => h != .unread).map H.name)

theorem hideOverall_inconclusive (hs : List H) (h : (hs.filter fun h => h != .unread).length < minValid) :
    hideOverall hs = "inconclusive" := by
  simpa [hideOverall] using overallNames_inconclusive _ (by simpa using h)

/-- Flush verdicts of the jobs, unread left out; fewer than two judged jobs is inconclusive. -/
def flushOverall (fs : List F) : String := overallNames ((fs.filter fun f => f != .unread).map F.name)

theorem flushOverall_inconclusive (fs : List F) (h : (fs.filter fun f => f != .unread).length < minValid) :
    flushOverall fs = "inconclusive" := by
  simpa [flushOverall] using overallNames_inconclusive _ (by simpa using h)

/-- All reps of one arm side by side: each rep's frames are paired and cut on their own, so no name carries over a rep border. -/
def armSets (reps : List (List Frame)) : List (Nat × List String) := reps.flatMap repSets

theorem armSets_length (reps : List (List Frame)) : (armSets reps).length = (reps.map fun r => (repSets r).length).sum := by
  simp [armSets, List.length_flatMap]

/-- Run-length input for the golden: `n` frames with `r` recalcs and the dirty names. -/
private def expand (gs : List (Nat × Nat × List String)) : List (Nat × List String) :=
  gs.flatMap fun (n, r, s) => List.replicate n (r, s)

private def verdictCases : List (String × List (Nat × Nat × List String)) :=
  [("short reading", [(287, 1, ["e:a"])]),
   ("no floor", [(400, 0, []), (2, 1, [])]),
   ("floor exactly at the band", [(360, 0, []), (40, 1, [])]),
   ("floor one above the band", [(356, 0, []), (44, 1, [])]),
   ("document level, every recalc bare", [(400, 1, [])]),
   ("document level, exactly 90 percent bare", [(36, 1, []), (4, 1, ["e:a"]), (260, 0, [])]),
   ("document level, one frame below 90 percent", [(35, 1, []), (5, 1, ["e:a"]), (260, 0, [])]),
   ("one name in every recalc frame", [(400, 1, ["e:a|div[0]", "p:a"])]),
   ("element beats its part on a tie", [(400, 1, ["p:a", "e:a|div[0]"])]),
   ("carrier exactly at the share", [(36, 1, ["e:a|div[0]"]), (4, 1, ["e:b|svg[0]"]), (260, 0, [])]),
   ("carrier one below the share", [(35, 1, ["e:a|div[0]"]), (5, 1, ["e:b|svg[0]"]), (260, 0, [])]),
   ("two names alternate", [(200, 1, ["e:a|div[0]"]), (200, 1, ["e:b|div[0]"])]),
   ("part carries what no element does", [(100, 1, ["p:a", "e:a|x[0]"]), (100, 1, ["p:a", "e:a|y[0]"]), (100, 1, ["p:a", "e:a|z[0]"]),
      (100, 1, ["p:a", "e:a|w[0]"])]),
   ("recalcs without dirt and with dirt mixed", [(200, 1, []), (200, 1, ["e:a|div[0]"])]),
   ("two recalcs in a frame count once as a frame", [(400, 2, ["e:a|div[0]"])])]

private def frameCases : List (String × List Frame) :=
  [("dirty only after the update, kept for the next frame", (List.range 12).map fun i => ⟨1, [], if i = 9 then ["y"] else []⟩),
   ("name dirty in every sample is inert", (List.range 12).map fun _ => ⟨1, ["x"], ["x"]⟩),
   ("name cleaned by the update varies", (List.range 12).map fun i => ⟨1, if i = 9 then ["z"] else [], []⟩),
   ("name dirty before the update and after it is inert", (List.range 12).map fun _ => ⟨1, ["x", "w"], ["x"]⟩),
   ("shorter than the skip", (List.range 5).map fun _ => ⟨1, [], ["x"]⟩),
   ("duplicate name is kept once", (List.range 10).map fun _ => ⟨1, ["y"], ["x", "x", "y"]⟩)]

private def hideCases : List (String × String × Option String × Reading × Reading) :=
  [("confirmed", "e:a", some "e:a", ⟨576, 588⟩, ⟨576, 3⟩), ("exactly at the band", "e:a", some "e:a", ⟨576, 588⟩, ⟨576, 63⟩),
   ("one above the band", "e:a", some "e:a", ⟨576, 588⟩, ⟨576, 64⟩), ("no change", "e:a", some "e:a", ⟨576, 588⟩, ⟨576, 590⟩),
   ("other element hidden", "e:a", some "e:b", ⟨576, 588⟩, ⟨576, 3⟩), ("nothing hidden", "e:a", none, ⟨576, 588⟩, ⟨576, 3⟩),
   ("no floor to remove", "e:a", some "e:a", ⟨576, 5⟩, ⟨576, 3⟩), ("reference short", "e:a", some "e:a", ⟨100, 100⟩, ⟨576, 3⟩),
   ("hide short", "e:a", some "e:a", ⟨576, 588⟩, ⟨100, 3⟩)]

private def dsCases : List (String × List D) :=
  [("three alike", [.documentLevel, .documentLevel, .documentLevel]),
   ("same carrier", [.carrier "e:a", .carrier "e:a", .carrier "e:a"]),
   ("different carriers", [.carrier "e:a", .carrier "e:b", .carrier "e:a"]),
   ("one unread", [.spread, .unread, .spread]), ("two unread", [.spread, .unread, .unread]),
   ("no floor", [.noFloor, .noFloor, .noFloor])]

private def hsCases : List (String × List H) :=
  [("all confirmed", [.confirmed, .confirmed, .confirmed]), ("one not confirmed", [.confirmed, .notConfirmed, .confirmed]),
   ("one unread", [.confirmed, .unread, .confirmed]), ("two unread", [.confirmed, .unread, .unread]),
   ("unmatched everywhere", [.unmatched, .unmatched, .unmatched])]

private def flushCases : List (String × Flushed) :=
  [("short", ⟨287, 0, 287⟩), ("held", ⟨576, 3, 576⟩), ("arises", ⟨576, 576, 0⟩), ("both", ⟨576, 576, 576⟩), ("none", ⟨576, 3, 3⟩),
   ("flush exactly at the band", ⟨576, 3, 57⟩), ("flush one above the band", ⟨576, 3, 58⟩),
   ("auto exactly at the band", ⟨576, 57, 576⟩), ("auto one above the band", ⟨576, 58, 576⟩)]

private def fsCases : List (String × List F) :=
  [("all held", [.held, .held, .held]), ("one arises", [.held, .arises, .held]), ("one unread", [.held, .unread, .held]),
   ("two unread", [.held, .unread, .unread])]

private def repCases : List (String × List (List Frame)) :=
  [("two reps do not share names", [(List.range 10).map fun i => ⟨1, [], if i = 8 then ["y"] else []⟩,
      (List.range 9).map fun _ => ⟨1, [], ["z"]⟩])]

private def namesJ (s : List String) : Json := Json.arr (s.map Json.str).toArray

private def dJ (d : D) : Json :=
  Json.mkObj [("kind", Json.str d.kind), ("name", match d with | .carrier n => Json.str n | _ => Json.null)]

def goldenLines (_ : Unit) : List String :=
  [(Json.mkObj [("kind", "consts"), ("floorBand", floorBand), ("carrierShare", carrierShare), ("documentShare", documentShare),
    ("skipFrames", skipFrames), ("minFrames", minFrames)]).compress] ++
  (verdictCases.map fun (n, gs) =>
    let xs := expand gs
    (Json.mkObj [("kind", "verdict"), ("name", n),
      ("groups", Json.arr (gs.map fun (k, r, s) => Json.arr #[toJson k, toJson r, namesJ s]).toArray),
      ("rate", rate xs), ("hit", hitN xs), ("bare", bareN xs), ("top", match top xs with | some t => Json.str t | none => Json.null),
      ("verdict", dJ (verdict xs)), ("name2", Json.str (verdict xs).name)]).compress) ++
  (frameCases.map fun (n, fs) =>
    (Json.mkObj [("kind", "rep"), ("name", n),
      ("frames", Json.arr (fs.map fun f => Json.arr #[toJson f.r, namesJ f.h, namesJ f.e]).toArray),
      ("sets", Json.arr ((repSets fs).map fun (r, s) => Json.arr #[toJson r, namesJ s]).toArray)]).compress) ++
  (hideCases.map fun (n, c, hd, ref, hide) =>
    (Json.mkObj [("kind", "hide"), ("name", n), ("carrier", Json.str c), ("hidden", match hd with | some h => Json.str h | none => Json.null),
      ("ref", Json.mkObj [("frames", ref.frames), ("recalcs", ref.recalcs)]), ("hide", Json.mkObj [("frames", hide.frames), ("recalcs", hide.recalcs)]),
      ("verdict", Json.str (hideVerdict c hd ref hide).name)]).compress) ++
  (repCases.map fun (n, rs) =>
    (Json.mkObj [("kind", "arm"), ("name", n),
      ("reps", Json.arr (rs.map fun fs => Json.arr (fs.map fun f => Json.arr #[toJson f.r, namesJ f.h, namesJ f.e]).toArray).toArray),
      ("sets", Json.arr ((armSets rs).map fun (r, s) => Json.arr #[toJson r, namesJ s]).toArray)]).compress) ++
  (flushCases.map fun (n, x) =>
    (Json.mkObj [("kind", "flush"), ("name", n), ("frames", x.frames), ("auto", x.auto), ("flush", x.flush),
      ("verdict", Json.str (flushVerdict x).name)]).compress) ++
  (fsCases.map fun (n, fs) =>
    (Json.mkObj [("kind", "flushOverall"), ("name", n), ("verdicts", Json.arr (fs.map fun f => Json.str f.name).toArray),
      ("overall", Json.str (flushOverall fs))]).compress) ++
  (hsCases.map fun (n, hs) =>
    (Json.mkObj [("kind", "hideOverall"), ("name", n), ("verdicts", Json.arr (hs.map fun h => Json.str h.name).toArray),
      ("overall", Json.str (hideOverall hs))]).compress) ++
  (dsCases.map fun (n, ds) =>
    (Json.mkObj [("kind", "overall"), ("name", n), ("verdicts", Json.arr (ds.map dJ).toArray), ("overall", Json.str (overall ds))]).compress)

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "device" / "end-floor-dirty.jsonl"

def checkRepo : IO Unit := do
  let cur ← IO.FS.readBinFile goldenPath
  if cur.data != (goldenText ()).toUTF8.data then throw (IO.userError s!"device-end-floor-dirty golden differs: {goldenPath}")
  IO.println s!"device-end-floor-dirty golden: up to date ({(goldenLines ()).length} lines)"

def writeRepo : IO Unit := IO.FS.writeFile goldenPath (goldenText ())

end Fw.Device.EndFloorDirty
