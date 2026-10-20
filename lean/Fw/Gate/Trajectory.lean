import Lean.Data.Json
/-!
# Trajectory probe: does the rewrite move like the original along a scroll path?

The breakpoint gate compares rest states, the counts compare class names, and neither watches the path between two rest
states. Three bugs of the optimized site passed all of them: the hero cards stale in WebKit (`hero.exit:scoped`), the
nav classes stale during the morph (`morph.tween:waapi`), and `is-on-dark` never re-evaluated on a morph push.

The probe (`packages/gate-breakpoints/src/trajectory/`) walks both arms along the same path with native rAF and reads
computed styles. This file decides, for one unit (a node, a property, a step), whether the rewrite's reading matches the
original's. A unit is decided on its own: no unit's verdict reads another's. `trajectory/reduce.mjs` is its TypeScript
twin, checked against `packages/contracts/golden/gate/trajectory.jsonl`.

Values are measured numbers times 1000 (integers), a string, or absent (the node's element is missing).

```
cd lean && lake env lean --run scripts/TrajectoryGolden.lean           # write the file
cd lean && lake env lean --run scripts/TrajectoryGolden.lean --check   # fail if it is stale
```
-/
namespace Fw.Gate.Trajectory
open Lean

/-- The kind of a property, which picks its tolerance.

Discrete values (a class on or off, an attribute) are equal or not; geometry is in px; a unit is an opacity, a filter
number or a scale; a colour is a channel value. -/
inductive Kind where
  | discrete
  | geometry
  | unit
  | colour
  deriving DecidableEq, Repr

/-- One reading of one element of a node.

Numbers are times 1000. A string is a computed value that is no number (a class state, a mask of a filter function). -/
inductive Val where
  | absent
  | num (xs : List Int)
  | str (s : String)
  deriving DecidableEq, Repr

/-- Why a unit fails.

Element counts differ, an element is missing on one side, a number meets a string, two numbers differ in length, two
strings differ, or two numbers are further apart than the tolerance. -/
inductive Why where
  | count
  | missing
  | type
  | shape
  | differs
  | apart
  deriving DecidableEq, Repr

/-- Why a unit is not compared.

A colour is read while a transition may still run, or no sample of the rewrite fell on the unit. -/
inductive Skip where
  | transient
  | noSample
  deriving DecidableEq, Repr

/-- The verdict of one unit. -/
inductive Verdict where
  | pass
  | fail (w : Why)
  | skip (s : Skip)
  deriving DecidableEq, Repr

/-- The tolerance of a kind, in thousandths.

Discrete none, geometry 1 px, a unit 0.01, a colour 2 of 255 channel levels. -/
def tol : Kind → Int
  | .discrete => 0
  | .geometry => 1000
  | .unit => 10
  | .colour => 2000

/-- Milliseconds a colour of the rewrite must have been quiet before it is compared.

A colour can follow a CSS transition, which the two arms start at different frames; after this time it has arrived. -/
def quietMs : Nat := 300

/-- A reading is quiet when no class of the nav changed for `quietMs` (or none ever did). -/
def isQuiet (sinceMs : Option Nat) : Bool :=
  match sinceMs with
  | none => true
  | some s => quietMs ≤ s

/-- Every component of `xs` lies between the smallest and the largest of the window's samples, widened by `t`. -/
def inBand (t : Int) (win : List (List Int)) (xs : List Int) : Bool :=
  (List.range xs.length).all fun j =>
    let c := win.map (·.getD j 0)
    let x := xs.getD j 0
    match c.min?, c.max? with
    | some lo, some hi => lo - t ≤ x && x ≤ hi + t
    | _, _ => false

/-- The numbers of every reading in a window, or none when one is not a number. -/
def numsOf : List Val → Option (List (List Int))
  | [] => some []
  | .num xs :: rest => (numsOf rest).map (xs :: ·)
  | _ :: _ => none

/-- The strings of every reading in a window, or none when one is not a string. -/
def strsOf : List Val → Option (List String)
  | [] => some []
  | .str s :: rest => (strsOf rest).map (s :: ·)
  | _ :: _ => none

/-- One element: the rewrite's reading `r` against the window of the original's readings.

A window of one reading is a plain comparison. A window of several (the frames around a threshold) accepts a discrete
reading equal to any of them and a continuous reading inside their band. -/
def judgeVal (k : Kind) (win : List Val) (r : Val) : Verdict :=
  if win.isEmpty then .skip .noSample
  else match r with
    | .absent => if win.all (· == .absent) then .pass else .fail .missing
    | .str s =>
      if win.any (· == .absent) then .fail .missing
      else match strsOf win with
        | some ss => if ss.contains s then .pass else .fail .differs
        | none => .fail .type
    | .num xs =>
      if win.any (· == .absent) then .fail .missing
      else match numsOf win with
        | none => .fail .type
        | some ns =>
          if ns.any (·.length != xs.length) then .fail .shape
          else if k == .discrete then (if ns.contains xs then .pass else .fail .differs)
          else if inBand (tol k) ns xs then .pass else .fail .apart

/-- Several verdicts as one: the first failure, else a pass if any passed, else a skip.

Used inside one unit (the elements of a node, the samples of a bucket); never across units. -/
def combine (vs : List Verdict) : Verdict :=
  match vs.find? (fun v => match v with | .fail _ => true | _ => false) with
  | some f => f
  | none =>
    if vs.any (· == .pass) then .pass
    else if vs.any (· == .skip .transient) then .skip .transient else .skip .noSample

/-- All elements of a node: counts must match, then each element on its own, combined. -/
def judgeEls (k : Kind) (win : List (List Val)) (r : List Val) : Verdict :=
  if win.isEmpty then .skip .noSample
  else if win.any (·.length != r.length) then .fail .count
  else combine ((List.range r.length).map fun i => judgeVal k (win.map (·.getD i .absent)) (r.getD i .absent))

/-- A sample of one (node, property) at one instant: the morph value times 10000, whether it is quiet, the elements. -/
structure Samp where
  m : Option Int
  quiet : Bool
  els : List Val
  deriving DecidableEq, Repr

/-- A sample with a morph value, quiet. -/
def sm (m : Int) (els : List Val) : Samp := ⟨some m, true, els⟩

/-- A sample without a morph value, quiet. -/
def s0 (els : List Val) : Samp := ⟨none, true, els⟩

/-- A sample without a morph value, not quiet. -/
def sq (els : List Val) : Samp := ⟨none, false, els⟩

/-- The rewrite's sample against a window of the original's samples.

A colour is compared only when the rewrite's own sample is quiet. The original's window keeps its non-quiet samples: its
colours follow the morph value, so dropping them would leave a window far from `m` and fail a colour that is right. -/
def judgeAgainst (k : Kind) (win : List Samp) (r : Samp) : Verdict :=
  if k == .colour && !r.quiet then .skip .transient
  else judgeEls k (win.map (·.els)) r.els

/-- A value `m` lies between `a` and `b`, ends included. -/
def between (a b m : Int) : Bool := min a b ≤ m && m ≤ max a b

/-- The index of the sample whose morph value is nearest `m`, the first on a tie. -/
def nearest (ms : List Int) (m : Int) : Nat :=
  (List.range ms.length).foldl
    (fun best k => if (ms.getD k 0 - m).natAbs < (ms.getD best 0 - m).natAbs then k else best) 0

/-- Sample `j` is an end of a pair of neighbouring samples whose morph values enclose `m`. -/
def pairHit (ms : List Int) (m : Int) (j : Nat) : Bool :=
  (j + 1 < ms.length && between (ms.getD j 0) (ms.getD (j + 1) 0) m) ||
    (0 < j && between (ms.getD (j - 1) 0) (ms.getD j 0) m)

/-- Some pair of neighbouring samples encloses `m`. -/
def hasPair (ms : List Int) (m : Int) : Bool := (List.range ms.length).any (pairHit ms m)

/-- The samples a morph value is aligned to: the ends of the enclosing pairs, else the nearest sample. -/
def coreIdx (ms : List Int) (m : Int) (j : Nat) : Bool :=
  if hasPair ms m then pairHit ms m j else j == nearest ms m

/-- The original's samples aligned to a morph value `m`, with one frame of slack.

The core is every end of a pair of neighbouring samples whose values enclose `m` (a value outside the original's range
has the nearest sample). The window is the core plus the one sample before and the one after it, so a rewrite that runs a
frame early or late still meets the original's reading. All samples of a hold (all values equal) are in the window of
that value. -/
def window (ms : List Int) (m : Int) : List Nat :=
  if ms.isEmpty then []
  else (List.range ms.length).filter fun i => (List.range ms.length).any fun j => coreIdx ms m j && i ≤ j + 1 && j ≤ i + 1

/-- The original's samples a rewrite sample at morph value `m` is compared with.

No morph value on either side means no alignment: the whole phase. -/
def windowOf (orig : List Samp) (m : Option Int) : List Samp :=
  match m with
  | none => orig
  | some m =>
    if orig.any (·.m.isNone) then orig
    else (window (orig.map (·.m.getD 0)) m).filterMap fun i => orig[i]?

/-- The unit a morph value falls in: tenths of the morph, 0 to 10, and 11 for no morph value. -/
def bucket (m : Option Int) : Nat :=
  match m with
  | none => 11
  | some m => min 10 ((m + 500) / 1000).toNat

/-- The verdict of bucket `b`: the rewrite samples in it, each against its window of original samples, combined. -/
def bucketVerdict (k : Kind) (orig rew : List Samp) (b : Nat) : Verdict :=
  combine ((rew.filter fun r => bucket r.m == b).map fun r => judgeAgainst k (windowOf orig r.m) r)

/-- The verdicts of one (node, property) along one phase of the morph path, one per bucket 0 to 11.

A bucket is decided by the rewrite samples in it, each against its window of original samples. A bucket without a
rewrite sample is a skip, never a pass. -/
def byM (k : Kind) (orig rew : List Samp) : List (Nat × Verdict) :=
  (List.range 12).map fun b => (b, bucketVerdict k orig rew b)

/-- The verdicts of one (node, property) along a path of steps, one per step of the original.

A step the rewrite did not record is a skip. -/
def byStep (k : Kind) (orig rew : List (String × Samp)) : List (String × Verdict) :=
  orig.map fun (s, o) =>
    match rew.find? (·.1 == s) with
    | some (_, r) => (s, judgeAgainst k [o] r)
    | none => (s, .skip .noSample)

/-- A verdict is a failure. -/
def isFail : Verdict → Bool
  | .fail _ => true
  | _ => false

/-- The lane fails when any unit fails. -/
def laneFails (vs : List Verdict) : Bool := vs.any isFail

/-- The widths the lane may run, an allowlist. -/
def allowedWidths : List Nat := [390, 640, 641, 1280]

/-- The widths input: the default, a list, or a refusal. -/
inductive Widths where
  | list (ws : List Nat)
  | refused
  deriving DecidableEq, Repr

/-- A comma list split into its entries, an empty entry kept. -/
def splitComma : List Char → List (List Char)
  | [] => [[]]
  | c :: cs =>
    match splitComma cs with
    | r :: rs => if c == ',' then [] :: r :: rs else (c :: r) :: rs
    | [] => [[c]]

/-- A width written in digits: non-empty, digits only. -/
def parseWidth (cs : List Char) : Option Nat :=
  if cs.isEmpty || !cs.all Char.isDigit then none
  else some (cs.foldl (fun n c => n * 10 + (c.toNat - '0'.toNat)) 0)

/-- The widths of a run from the comma list of the `widths` input.

Empty means all four. Otherwise each entry must be an allowed width, with no repeat. -/
def pickWidths (s : String) : Widths :=
  if s.isEmpty then .list allowedWidths
  else
    let ws := (splitComma s.toList).map parseWidth
    if ws.any Option.isNone then .refused
    else
      let ns := ws.filterMap id
      if ns.all allowedWidths.contains && ns.eraseDups.length == ns.length then .list ns else .refused

-- Branches of the unit verdict ---------------------------------------------------------------------------------------

/-- Branch empty window.

No original sample to compare with is a skip, not a pass. -/
theorem judgeVal_empty (k : Kind) (r : Val) : judgeVal k [] r = .skip .noSample := by
  simp [judgeVal]

/-- Branch both absent.

An element missing on both sides is equal. -/
theorem judgeVal_absent_absent (k : Kind) : judgeVal k [.absent] .absent = .pass := by
  cases k <;> decide

/-- Branch absent in the rewrite.

An element the original has and the rewrite lacks fails. -/
theorem judgeVal_rewrite_absent : judgeVal .unit [.num [1000]] .absent = .fail .missing := by decide

/-- Branch absent in the original.

An element the rewrite has and the original lacks fails. -/
theorem judgeVal_orig_absent : judgeVal .unit [.absent] (.num [1000]) = .fail .missing := by decide

/-- Branch string equal.

Two equal strings pass in every kind. -/
theorem judgeVal_str_pass (k : Kind) : judgeVal k [.str "on"] (.str "on") = .pass := by
  cases k <;> decide

/-- Branch string differs.

A class on in the original and off in the rewrite fails in every kind. -/
theorem judgeVal_str_fail (k : Kind) : judgeVal k [.str "on"] (.str "off") = .fail .differs := by
  cases k <;> decide

/-- Branch type.

A number against a string fails. -/
theorem judgeVal_type : judgeVal .unit [.str "on"] (.num [1000]) = .fail .type := by decide

/-- Branch shape.

Two numbers of different length (a matrix against a shorter reading) fail. -/
theorem judgeVal_shape : judgeVal .geometry [.num [1000, 0]] (.num [1000]) = .fail .shape := by decide

/-- Branch discrete numbers equal. -/
theorem judgeVal_discrete_pass : judgeVal .discrete [.num [5000]] (.num [5000]) = .pass := by decide

/-- Branch discrete numbers differ.

A discrete number has no tolerance: one thousandth apart fails. -/
theorem judgeVal_discrete_fail : judgeVal .discrete [.num [5000]] (.num [5001]) = .fail .differs := by decide

/-- Branch inside the tolerance, geometry.

One px apart passes. -/
theorem judgeVal_geometry_edge : judgeVal .geometry [.num [5000]] (.num [6000]) = .pass := by decide

/-- Branch outside the tolerance, geometry.

One thousandth over one px fails. -/
theorem judgeVal_geometry_over : judgeVal .geometry [.num [5000]] (.num [6001]) = .fail .apart := by decide

/-- Branch inside the tolerance, unit.

0.01 apart passes. -/
theorem judgeVal_unit_edge : judgeVal .unit [.num [750]] (.num [760]) = .pass := by decide

/-- Branch outside the tolerance, unit.

Bug A: the hero copy at a quarter of the viewport has opacity 0.75; the stale WebKit style still says 1. -/
theorem judgeVal_unit_over : judgeVal .unit [.num [750]] (.num [1000]) = .fail .apart := by decide

/-- Branch inside the tolerance, colour.

Two channel levels apart passes. -/
theorem judgeVal_colour_edge :
    judgeVal .colour [.num [255000, 255000, 255000, 255000]] (.num [253000, 255000, 255000, 255000]) = .pass := by decide

/-- Branch outside the tolerance, colour.

Bug C: the logo is white on the dark panel in the original and still dark in the rewrite. -/
theorem judgeVal_colour_over :
    judgeVal .colour [.num [255000, 255000, 255000, 255000]] (.num [43000, 49000, 59000, 255000]) = .fail .apart := by
  decide

/-- Branch window, discrete.

At a threshold the window holds both states and the rewrite may show either. -/
theorem judgeVal_window_discrete :
    judgeVal .discrete [.str "off", .str "on"] (.str "on") = .pass ∧
    judgeVal .discrete [.str "off", .str "on"] (.str "off") = .pass := by decide

/-- Branch window, continuous.

A reading between the two samples of the window passes; one beyond the band widened by the tolerance fails. -/
theorem judgeVal_window_band :
    judgeVal .geometry [.num [0], .num [10000]] (.num [4000]) = .pass ∧
    judgeVal .geometry [.num [0], .num [10000]] (.num [11001]) = .fail .apart := by decide

/-- The tolerance of every kind, in thousandths. -/
theorem tol_values : tol .discrete = 0 ∧ tol .geometry = 1000 ∧ tol .unit = 10 ∧ tol .colour = 2000 := by decide

-- Elements, samples, units ------------------------------------------------------------------------------------------

/-- Branch element count.

A node with a different number of elements in the two arms fails, whatever its elements hold. -/
theorem judgeEls_count : judgeEls .unit [[.num [1000]]] [.num [1000], .num [1000]] = .fail .count := by decide

/-- Branch elements.

Each element is judged on its own; one failing element fails the node. -/
theorem judgeEls_one_bad :
    judgeEls .unit [[.num [1000], .num [500]]] [.num [1000], .num [900]] = .fail .apart := by decide

/-- A node with no elements on either side compares nothing. -/
theorem judgeEls_nothing : judgeEls .unit [[]] [] = .skip .noSample := by decide

/-- A failure inside `combine` is never hidden by a pass. -/
theorem combine_fail (w : Why) (vs : List Verdict) : combine (.pass :: .fail w :: vs) = .fail w := by
  simp [combine, List.find?]

/-- No sample is a skip. -/
theorem combine_empty : combine [] = .skip .noSample := by decide

/-- Passes and skips without a failure pass. -/
theorem combine_pass : combine [.skip .transient, .pass] = .pass := by decide

/-- Only skips stay a skip; a transient one is remembered. -/
theorem combine_skips : combine [.skip .noSample, .skip .transient] = .skip .transient := by decide

/-- A colour reading before `quietMs` is not compared. -/
theorem judgeAgainst_transient :
    judgeAgainst .colour [⟨none, true, [.num [255000]]⟩] ⟨none, false, [.num [0]]⟩ = .skip .transient := by decide

/-- A colour reading after `quietMs` is compared. -/
theorem judgeAgainst_quiet :
    judgeAgainst .colour [⟨none, true, [.num [255000]]⟩] ⟨none, true, [.num [0]]⟩ = .fail .apart := by decide

/-- A window sample that is not quiet still bounds a quiet colour. -/
theorem judgeAgainst_window_not_quiet :
    judgeAgainst .colour [⟨none, false, [.num [255000]]⟩] ⟨none, true, [.num [0]]⟩ = .fail .apart := by decide

/-- A window sample that is not quiet passes a colour inside its band. -/
theorem judgeAgainst_window_not_quiet_pass :
    judgeAgainst .colour [⟨none, false, [.num [255000]]⟩] ⟨none, true, [.num [255000]]⟩ = .pass := by decide

/-- A non-colour kind ignores quiet. -/
theorem judgeAgainst_other_kind :
    judgeAgainst .unit [⟨none, true, [.num [1000]]⟩] ⟨none, false, [.num [0]]⟩ = .fail .apart := by decide

-- Alignment ---------------------------------------------------------------------------------------------------------

/-- An exact hit on an interior sample takes the two enclosing pairs and one frame beyond. -/
theorem window_interior : window [0, 2000, 4000, 6000, 8000] 4000 = [0, 1, 2, 3, 4] := by decide

/-- A value between two samples takes that pair and one frame on each side. -/
theorem window_between : window [0, 2000, 4000, 6000, 8000, 10000] 5000 = [1, 2, 3, 4] := by decide

/-- A closing phase (falling values) aligns the same way. -/
theorem window_falling : window [10000, 8000, 6000, 4000, 2000] 7000 = [0, 1, 2, 3] := by decide

/-- A value beyond the range takes the nearest sample and one frame before it. -/
theorem window_outside : window [0, 2000, 4000] 9000 = [1, 2] := by decide

/-- A hold (all values equal) puts every sample of the hold in the window. -/
theorem window_hold : window [10000, 10000, 10000] 10000 = [0, 1, 2] := by decide

/-- A phase with no samples has an empty window. -/
theorem window_empty (m : Int) : window [] m = [] := by simp [window]

/-- Every index in a window is a sample of the phase. -/
theorem window_lt (ms : List Int) (m : Int) (i : Nat) (h : i ∈ window ms m) : i < ms.length := by
  unfold window at h
  split at h
  · simp at h
  · simp only [List.mem_filter, List.mem_range] at h
    exact h.1

/-- The nearest sample is a sample of the phase. -/
theorem nearest_lt (ms : List Int) (m : Int) (h : ms ≠ []) : nearest ms m < ms.length := by
  have hn : 0 < ms.length := List.length_pos_iff.mpr h
  unfold nearest
  have key : ∀ (l : List Nat) (b : Nat), (∀ x ∈ l, x < ms.length) → b < ms.length →
      l.foldl (fun best k => if (ms.getD k 0 - m).natAbs < (ms.getD best 0 - m).natAbs then k else best) b < ms.length := by
    intro l
    induction l with
    | nil => intro b _ hb; exact hb
    | cons x xs ih =>
      intro b hl hb
      apply ih
      · exact fun y hy => hl y (List.mem_cons_of_mem _ hy)
      · simp only
        split
        · exact hl x (List.mem_cons_self ..)
        · exact hb
  exact key _ 0 (fun x hx => List.mem_range.mp hx) hn

/-- Every window of a non-empty phase is non-empty: each rewrite sample has something to be compared with. -/
theorem window_nonempty (ms : List Int) (m : Int) (h : ms ≠ []) : window ms m ≠ [] := by
  have hn : ms.isEmpty = false := by cases ms <;> simp_all
  have hlen : 0 < ms.length := List.length_pos_iff.mpr h
  have hcore : ∃ j, j < ms.length ∧ coreIdx ms m j = true := by
    by_cases hp : hasPair ms m = true
    · obtain ⟨j, hj, hjp⟩ := List.any_eq_true.mp (show (List.range ms.length).any (pairHit ms m) = true from hp)
      exact ⟨j, List.mem_range.mp hj, by simp [coreIdx, hp, hjp]⟩
    · refine ⟨nearest ms m, nearest_lt ms m h, ?_⟩
      simp [coreIdx, hp]
  obtain ⟨j, hj, hc⟩ := hcore
  apply List.ne_nil_of_mem (a := j)
  unfold window
  simp only [hn]
  simp only [Bool.false_eq_true, ↓reduceIte, List.mem_filter, List.mem_range, List.any_eq_true, Bool.and_eq_true,
    decide_eq_true_eq]
  exact ⟨hj, j, hj, ⟨hc, Nat.le_succ _⟩, Nat.le_succ _⟩

/-- The unit of a morph value: tenths, clamped. -/
theorem bucket_values :
    bucket (some 0) = 0 ∧ bucket (some 499) = 0 ∧ bucket (some 500) = 1 ∧ bucket (some 10000) = 10 ∧
    bucket (some 12000) = 10 ∧ bucket (some (-300)) = 0 ∧ bucket none = 11 := by decide

/-- One frame of slack at a threshold: the rewrite shows `on` at a morph value the original flips at.

The original reads `off` at 0.90 and `on` at 0.93; the rewrite reads `on` at 0.92 and passes. -/
theorem byM_threshold_slack :
    (byM .discrete [⟨some 9000, true, [.str "off"]⟩, ⟨some 9300, true, [.str "on"]⟩]
        [⟨some 9200, true, [.str "on"]⟩]).getD 9 (9, .skip .noSample) = (9, .pass) := by decide

/-- Bug B: a class that stays `off` through the tween is a failure at the buckets where the original has `on`.

The original reads `on` from 0.93; the rewrite (waapi) sets the class only at the end, so at 0.95 it is still `off`. -/
theorem byM_stale_class :
    (byM .discrete [sm 8000 [.str "off"], sm 8500 [.str "off"], sm 9000 [.str "off"], sm 9300 [.str "on"],
        sm 9400 [.str "on"], sm 9500 [.str "on"], sm 9600 [.str "on"], sm 9700 [.str "on"], sm 9900 [.str "on"]]
      [sm 9500 [.str "off"]]).getD 10 (10, .skip .noSample) = (10, .fail .differs) := by decide

/-- A bucket the rewrite has no sample in is a skip, not a pass. -/
theorem byM_no_sample :
    (byM .discrete [⟨some 0, true, [.str "off"]⟩] [⟨some 0, true, [.str "off"]⟩]).getD 5 (5, .pass) = (5, .skip .noSample) := by
  decide

/-- Every bucket 0 to 11 gets its own verdict: twelve per phase, in order. -/
theorem byM_length (k : Kind) (orig rew : List Samp) : (byM k orig rew).length = 12 := by
  simp [byM]

/-- The verdict of a bucket reads only the rewrite samples in that bucket and the original's samples.

A rewrite sample of another bucket cannot change it (unit independence). -/
theorem bucketVerdict_independent (k : Kind) (orig rew : List Samp) (b : Nat) (r : Samp) (hb : bucket r.m ≠ b) :
    bucketVerdict k orig (r :: rew) b = bucketVerdict k orig rew b := by
  simp [bucketVerdict, hb]

/-- A step the original has and the rewrite lacks is a skip. -/
theorem byStep_missing :
    byStep .unit [("s25", ⟨none, true, [.num [750]]⟩)] [] = [("s25", .skip .noSample)] := by decide

/-- A step is decided by that step's two samples only. -/
theorem byStep_pair :
    byStep .unit [("s25", ⟨none, true, [.num [750]]⟩), ("s50", ⟨none, true, [.num [500]]⟩)]
      [("s25", ⟨none, true, [.num [1000]]⟩), ("s50", ⟨none, true, [.num [500]]⟩)] =
    [("s25", .fail .apart), ("s50", .pass)] := by decide

/-- The lane fails when one unit fails, and only then. -/
theorem laneFails_iff (vs : List Verdict) : laneFails vs = true ↔ ∃ v ∈ vs, isFail v = true := by
  simp [laneFails]

/-- A lane of passes and skips does not fail. -/
theorem laneFails_none : laneFails [.pass, .skip .noSample, .skip .transient] = false := by decide

/-- Widths: empty means all four, in order. -/
theorem pickWidths_default : pickWidths "" = .list [390, 640, 641, 1280] := by decide

/-- Widths: a subset keeps the given order. -/
theorem pickWidths_subset : pickWidths "1280,390" = .list [1280, 390] := by decide

/-- Widths: a width outside the allowlist is refused. -/
theorem pickWidths_unknown : pickWidths "390,500" = .refused := by decide

/-- Widths: a repeat is refused. -/
theorem pickWidths_repeat : pickWidths "390,390" = .refused := by decide

/-- Widths: a non-number is refused. -/
theorem pickWidths_junk : pickWidths "390,wide" = .refused := by decide

/-- Widths: an empty entry is refused. -/
theorem pickWidths_gap : pickWidths "390,,640" = .refused := by decide

-- Golden ------------------------------------------------------------------------------------------------------------

/-- The name of a kind in the golden file. -/
def Kind.name : Kind → String
  | .discrete => "discrete" | .geometry => "geometry" | .unit => "unit" | .colour => "colour"

/-- A verdict as `pass`, `fail:<why>` or `skip:<why>`. -/
def Verdict.name : Verdict → String
  | .pass => "pass"
  | .fail .count => "fail:count" | .fail .missing => "fail:missing" | .fail .type => "fail:type"
  | .fail .shape => "fail:shape" | .fail .differs => "fail:differs" | .fail .apart => "fail:apart"
  | .skip .transient => "skip:transient" | .skip .noSample => "skip:noSample"

/-- A reading as JSON: null, an array of integers or a string. -/
def Val.json : Val → Json
  | .absent => Json.null
  | .num xs => Json.arr (xs.map fun x => toJson x).toArray
  | .str s => Json.str s

/-- A sample as JSON. -/
def Samp.json (s : Samp) : Json :=
  Json.mkObj [("m", match s.m with | none => Json.null | some m => toJson m), ("quiet", Json.bool s.quiet),
    ("els", Json.arr (s.els.map Val.json).toArray)]

/-- One golden line. -/
inductive Case where
  | judge (name : String) (k : Kind) (win : List Samp) (r : Samp)
  | bracket (name : String) (ms : List Int) (m : Int)
  | tenth (name : String) (m : Option Int)
  | phase (name : String) (k : Kind) (orig rew : List Samp)
  | path (name : String) (k : Kind) (orig rew : List (String × Samp))
  | picks (name : String) (input : String)

/-- The golden cases: every branch above, per kind where the kind matters. -/
def cases : List Case := [
  .judge "empty window" .unit [] (s0 [.num [1000]]),
  .judge "absent both" .discrete [s0 [.absent]] (s0 [.absent]),
  .judge "absent rewrite" .unit [s0 [.num [1000]]] (s0 [.absent]),
  .judge "absent orig" .unit [s0 [.absent]] (s0 [.num [1000]]),
  .judge "str equal" .discrete [s0 [.str "on"]] (s0 [.str "on"]),
  .judge "str differs" .discrete [s0 [.str "on"]] (s0 [.str "off"]),
  .judge "str differs unit" .unit [s0 [.str "blur(#px)"]] (s0 [.str "none"]),
  .judge "type" .unit [s0 [.str "on"]] (s0 [.num [1000]]),
  .judge "shape" .geometry [s0 [.num [1000, 0]]] (s0 [.num [1000]]),
  .judge "discrete num equal" .discrete [s0 [.num [5000]]] (s0 [.num [5000]]),
  .judge "discrete num differs" .discrete [s0 [.num [5000]]] (s0 [.num [5001]]),
  .judge "geometry edge" .geometry [s0 [.num [5000]]] (s0 [.num [6000]]),
  .judge "geometry over" .geometry [s0 [.num [5000]]] (s0 [.num [6001]]),
  .judge "geometry under" .geometry [s0 [.num [5000]]] (s0 [.num [4000]]),
  .judge "unit edge" .unit [s0 [.num [750]]] (s0 [.num [760]]),
  .judge "unit over" .unit [s0 [.num [750]]] (s0 [.num [761]]),
  .judge "bug A copy opacity" .unit [s0 [.num [750]]] (s0 [.num [1000]]),
  .judge "colour edge" .colour [s0 [.num [255000, 255000, 255000, 255000]]] (s0 [.num [253000, 255000, 255000, 255000]]),
  .judge "colour over" .colour [s0 [.num [255000, 255000, 255000, 255000]]] (s0 [.num [252999, 255000, 255000, 255000]]),
  .judge "bug C logo colour" .colour [s0 [.num [255000, 255000, 255000, 255000]]] (s0 [.num [43000, 49000, 59000, 255000]]),
  .judge "colour transient" .colour [s0 [.num [255000]]] (sq [.num [0]]),
  .judge "colour window not quiet" .colour [sq [.num [255000]]] (s0 [.num [0]]),
  .judge "colour window not quiet pass" .colour [sq [.num [255000]]] (s0 [.num [255000]]),
  .judge "unit ignores quiet" .unit [s0 [.num [1000]]] (sq [.num [0]]),
  .judge "window discrete" .discrete [s0 [.str "off"], s0 [.str "on"]] (s0 [.str "on"]),
  .judge "window band inside" .geometry [s0 [.num [0]], s0 [.num [10000]]] (s0 [.num [4000]]),
  .judge "window band outside" .geometry [s0 [.num [0]], s0 [.num [10000]]] (s0 [.num [11001]]),
  .judge "count" .unit [s0 [.num [1000]]] (s0 [.num [1000], .num [1000]]),
  .judge "one element bad" .unit [s0 [.num [1000], .num [500]]] (s0 [.num [1000], .num [900]]),
  .judge "no elements" .unit [s0 []] (s0 []),
  .bracket "interior hit" [0, 2000, 4000, 6000] 4000,
  .bracket "between" [0, 2000, 4000, 6000] 3000,
  .bracket "falling" [10000, 8000, 6000] 7000,
  .bracket "outside" [0, 2000] 9000,
  .bracket "outside low" [4000, 6000] 0,
  .bracket "hold" [10000, 10000, 10000] 10000,
  .bracket "one sample" [3000] 3000,
  .bracket "empty" [] 3000,
  .tenth "zero" (some 0), .tenth "below half" (some 499), .tenth "half" (some 500), .tenth "one" (some 1000),
  .tenth "end" (some 10000), .tenth "beyond" (some 12000), .tenth "negative" (some (-300)), .tenth "none" none,
  .phase "threshold slack" .discrete [sm 9000 [.str "off"], sm 9300 [.str "on"]] [sm 9200 [.str "on"]],
  .phase "stale class" .discrete
    [sm 8000 [.str "off"], sm 8500 [.str "off"], sm 9000 [.str "off"], sm 9300 [.str "on"], sm 9400 [.str "on"],
      sm 9500 [.str "on"], sm 9600 [.str "on"], sm 9700 [.str "on"], sm 9900 [.str "on"]] [sm 9500 [.str "off"]],
  .phase "ramp ok" .geometry [sm 0 [.num [0]], sm 5000 [.num [5000]], sm 10000 [.num [10000]]]
    [sm 2000 [.num [2000]], sm 7000 [.num [7000]]],
  .phase "ramp stuck" .geometry [sm 0 [.num [0]], sm 5000 [.num [5000]], sm 10000 [.num [10000]]]
    [sm 2000 [.num [0]], sm 7000 [.num [0]]],
  .phase "hold colour" .colour [⟨some 10000, false, [.num [43000]]⟩, ⟨some 10000, true, [.num [255000]]⟩]
    [⟨some 10000, false, [.num [43000]]⟩, ⟨some 10000, true, [.num [43000]]⟩],
  .phase "no morph value" .discrete [s0 [.str "on"]] [s0 [.str "on"]],
  .path "missing step" .unit [("s25", s0 [.num [750]])] [],
  .path "pair" .unit [("s25", s0 [.num [750]]), ("s50", s0 [.num [500]])]
    [("s25", s0 [.num [1000]]), ("s50", s0 [.num [500]])],
  .picks "default" "", .picks "subset" "1280,390", .picks "unknown" "390,500", .picks "repeat" "390,390",
  .picks "junk" "390,wide", .picks "gap" "390,,640", .picks "all" "390,640,641,1280", .picks "space" "390, 640"]

/-- A widths pick as JSON. -/
def Widths.json : Widths → Json
  | .list ws => Json.mkObj [("ok", Json.bool true), ("widths", Json.arr (ws.map fun w => toJson w).toArray)]
  | .refused => Json.mkObj [("ok", Json.bool false)]

/-- One golden line. -/
def Case.line : Case → Json
  | .judge n k win r =>
    Json.mkObj [("op", "against"), ("name", n), ("kind", k.name), ("win", Json.arr (win.map Samp.json).toArray),
      ("r", r.json), ("verdict", (judgeAgainst k win r).name)]
  | .bracket n ms m =>
    Json.mkObj [("op", "window"), ("name", n), ("ms", Json.arr (ms.map fun x => toJson x).toArray), ("m", toJson m),
      ("idx", Json.arr ((window ms m).map fun i => toJson i).toArray)]
  | .tenth n m =>
    Json.mkObj [("op", "bucket"), ("name", n), ("m", match m with | none => Json.null | some m => toJson m),
      ("bucket", toJson (bucket m))]
  | .phase n k o r =>
    Json.mkObj [("op", "byM"), ("name", n), ("kind", k.name), ("orig", Json.arr (o.map Samp.json).toArray),
      ("rew", Json.arr (r.map Samp.json).toArray),
      ("verdicts", Json.arr ((byM k o r).map fun (_, v) => Json.str v.name).toArray)]
  | .path n k o r =>
    let side := fun (xs : List (String × Samp)) =>
      Json.arr (xs.map fun (s, x) => Json.mkObj [("step", s), ("s", x.json)]).toArray
    Json.mkObj [("op", "byStep"), ("name", n), ("kind", k.name), ("orig", side o), ("rew", side r),
      ("verdicts", Json.arr ((byStep k o r).map fun (s, v) => Json.mkObj [("step", s), ("verdict", v.name)]).toArray)]
  | .picks n i => Json.mkObj [("op", "widths"), ("name", n), ("input", i), ("pick", (pickWidths i).json)]

/-- Where the golden lives, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/gate/trajectory.jsonl"

/-- Write, or with `--check` verify, the golden file.

Exit 1 when the checked-in file is stale. -/
def run (args : List String) : IO UInt32 := do
  let text := String.join (cases.map fun c => c.line.compress ++ "\n")
  if !args.contains "--check" then
    IO.FS.writeFile goldenPath text
    IO.println s!"trajectory golden: {cases.length} lines written"
    return 0
  let cur ← try IO.FS.readFile goldenPath catch _ => pure ""
  if cur != text then
    IO.println s!"trajectory golden: {goldenPath} is stale (regenerate: cd lean && lake env lean --run scripts/TrajectoryGolden.lean)"
    return 1
  IO.println s!"trajectory golden: {cases.length} lines, up to date"
  return 0

end Fw.Gate.Trajectory
