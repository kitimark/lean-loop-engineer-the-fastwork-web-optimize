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
strings differ, or two numbers are further apart than the tolerance. `coverage` is not a difference between the arms: the
probe has nothing to compare the rewrite's sample with (or no sample at all where a push must have one), and a unit it
cannot judge fails instead of passing by silence. -/
inductive Why where
  | count
  | missing
  | type
  | shape
  | differs
  | apart
  | coverage
  deriving DecidableEq, Repr

/-- Why a unit is not compared.

A colour is read while a transition may still run, or no sample of the rewrite fell on a unit that needs none (a hold, a
bucket outside 1 to 9, a hero step the rewrite did not record). -/
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

/-- A sample of one (node, property) at one instant: the morph value times 10000, the ms since the last class change of
the nav (`none`: no change happened), the elements, and the pass (`rep`) it was read in.

The probe walks the morph path several times (`--reps`) and keeps every row. A morph value rises or falls within one pass
only, so two samples of different passes are not neighbours in time and no window may pair them. -/
structure Samp where
  m : Option Int
  since : Option Nat
  els : List Val
  rep : Nat
  deriving DecidableEq, Repr

/-- The sample was read `quietMs` or more after the last class change of the nav. -/
def Samp.quiet (s : Samp) : Bool := isQuiet s.since

/-- A sample with a morph value, quiet, in pass 0. -/
def sm (m : Int) (els : List Val) : Samp := ⟨some m, none, els, 0⟩

/-- A sample with a morph value, quiet, in pass `rep`. -/
def smr (rep : Nat) (m : Int) (els : List Val) : Samp := ⟨some m, none, els, rep⟩

/-- A sample without a morph value, quiet, in pass 0. -/
def s0 (els : List Val) : Samp := ⟨none, none, els, 0⟩

/-- A sample without a morph value, read at a class change, in pass 0. -/
def sq (els : List Val) : Samp := ⟨none, some 0, els, 0⟩

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

/-- How far, in morph units (x 10000), a rewrite sample may lie outside the range the original was sampled over and still
have a counterpart: one bucket (a tenth of the morph). -/
def reach : Int := 1000

/-- `m` lies farther than `reach` below every sample of `ms`, or farther than `reach` above every one. -/
def beyond (ms : List Int) (m : Int) : Bool :=
  ms.all (fun x => x + reach < m) || ms.all (fun x => m + reach < x)

/-- The original's samples of one pass that a rewrite sample at morph value `m` is compared with, or none when there is
nothing to compare with.

`orig` is one monotone pass. No window (`none`) when the rewrite sample has no morph value, when any original sample has
none (the pass cannot be aligned), or when `m` is farther than `reach` outside the range the pass was sampled over (a slow
frame can leave a pass with a few samples, and the rewrite's 0.98 must not be judged against the original's 0.15). -/
def windowOne (orig : List Samp) (m : Option Int) : Option (List Samp) :=
  match m with
  | none => none
  | some m =>
    if orig.any (·.m.isNone) then none
    else
      let ms := orig.map (·.m.getD 0)
      if beyond ms m then none else some ((window ms m).filterMap fun i => orig[i]?)

/-- The passes of a pooled list of samples, each once, in order of first appearance. -/
def repsOf (orig : List Samp) : List Nat := (orig.map (·.rep)).eraseDups

/-- The samples of pass `r`, in order. -/
def passOf (orig : List Samp) (r : Nat) : List Samp := orig.filter (·.rep == r)

/-- The original's samples a rewrite sample at morph value `m` is compared with, or none when there is nothing to compare with.

`orig` pools the passes of `--reps`. Each pass is aligned on its own (`windowOne` of the samples of that pass); the window
is the union of the windows of the passes that have one, and none only when no pass has one. A pair of neighbours never
crosses a pass boundary: the last sample of a pass (m = 1.0) and the first of the next (m = 0) would enclose every `m` and
put both ends of the phase into every window, so a stuck class passed. Each of the rules of `windowOne` is decided per
pass (`windowOf_pass_iff`, `windowOf_none_iff`). -/
def windowOf (orig : List Samp) (m : Option Int) : Option (List Samp) :=
  match (repsOf orig).filterMap fun r => windowOne (passOf orig r) m with
  | [] => none
  | ws => some ws.flatten

/-- The transitions the part CSS declares on the properties the probe reads, as (node, property, ms): the longest delay
plus duration over the rules of `apps/site/src/parts/nav/nav.module.css`, which restates the original's stylesheet.

`nav.visibility` is `visibility 0s linear 0.32s`; `nav.rect` follows `width 0.68s`; `nav.opacity` is 0.28s, and 0.7s once
the hero pill's chrome is ready; `nav.transform.*` is `transform 0.32s`; `earn.opacity` is 0.32s after a delay of 0.12s.
A property not listed has no transition, and the probe reads it as at rest. -/
def settleTable : List (String × String × Nat) := [
  ("nav", "visibility", 320), ("nav", "rect", 680), ("nav", "background-color", 700), ("nav", "opacity", 700),
  ("nav", "transform.lin", 320), ("nav", "transform.shift", 320), ("logo", "color", 240), ("actions", "gap", 680),
  ("earn", "opacity", 440), ("earn", "max-width", 680)]

/-- The declared transition of a node's property, in ms; `none` when the part CSS declares none. -/
def settleOf (node prop : String) : Option Nat :=
  (settleTable.find? fun (n, p, _) => n == node && p == prop).map (·.2.2)

/-- Milliseconds a transition may start after the class change that triggers it.

It starts at the next style update after the change, which a busy main thread delays; the stored runs read
mid-transition colours up to 140 ms past the declared 700 (MEASURED, `docs/team/tools/trajectory-probe.md`). -/
def startLag : Nat := 200

/-- A sample was read while a transition of `d` ms may still run: less than `d + startLag` after the last class change
of the nav. No declared transition, or no class change, is never in flight. -/
def inFlight (d : Option Nat) (s : Samp) : Bool :=
  match d, s.since with
  | some d, some t => decide (t < d + startLag)
  | _, _ => false

/-- The samples of one pass that are in flight or next to one in flight: the readings a transition passes through, with
the values it starts from and arrives at. -/
def crossedPass (d : Option Nat) (p : List Samp) : List Samp :=
  ((List.range p.length).filter fun i =>
    (List.range p.length).any fun j => ((p[j]?).map (inFlight d)).getD false && i ≤ j + 1 && j ≤ i + 1).filterMap
    fun i => p[i]?

/-- The readings the original passes through in its transitions: `crossedPass` of each pass of the segment `seg`. -/
def crossed (d : Option Nat) (seg : List Samp) : List Samp :=
  (repsOf seg).flatMap fun r => crossedPass d (passOf seg r)

/-- **One rewrite sample against its window, transitions included.** `d` is the property's declared transition and `seg`
the original's samples of the whole path the window was cut from.

A unit is in flight when the rewrite's sample or a sample of its window was read in flight. The arms start a transition at
different frames, so an in-flight reading is judged against the window plus every reading the original passes through in
its transitions (`crossed`), and is never skipped. A unit with no sample in flight is judged as before (`judgeAgainst`). -/
def judgeFlight (k : Kind) (d : Option Nat) (seg win : List Samp) (r : Samp) : Verdict :=
  if inFlight d r || win.any (inFlight d) then judgeEls k ((win ++ crossed d seg).map (·.els)) r.els
  else judgeAgainst k win r

/-- A rewrite sample against its window of the original's samples; no window is a coverage failure, never a skip. -/
def judgeIn (k : Kind) (d : Option Nat) (seg : List Samp) (win : Option (List Samp)) (r : Samp) : Verdict :=
  match win with
  | none => .fail .coverage
  | some w => judgeFlight k d seg w r

/-- The unit a morph value falls in: tenths of the morph, 0 to 10, and 11 for no morph value. -/
def bucket (m : Option Int) : Nat :=
  match m with
  | none => 11
  | some m => min 10 ((m + 500) / 1000).toNat

/-- A phase of the end-of-page path: a push moves the morph (a wheel delta, the tween runs); a hold waits at an end. -/
inductive Phase where
  | push
  | hold
  deriving DecidableEq, Repr

/-- The buckets a push must have a rewrite sample in: 1 to 9, the interior of the tween. -/
def needsSample (b : Nat) : Bool := decide (1 ≤ b) && decide (b ≤ 9)

/-- The verdict of bucket `b`: the rewrite samples in it, each against its window of original samples, combined.

A bucket of a push that needs a sample and has none is `fail coverage`; elsewhere an empty bucket is a skip. -/
def bucketVerdict (ph : Phase) (k : Kind) (d : Option Nat) (seg orig rew : List Samp) (b : Nat) : Verdict :=
  match rew.filter (fun r => bucket r.m == b) with
  | [] => if ph == .push && needsSample b then .fail .coverage else .skip .noSample
  | rs => combine (rs.map fun r => judgeIn k d seg (windowOf orig r.m) r)

/-- The verdicts of one (node, property) along one phase of the morph path, one per bucket 0 to 11.

A bucket is decided by the rewrite samples in it, each against its window of original samples. In a push, an empty bucket
1 to 9, a rewrite sample without a morph value and a sample with no counterpart in the original are `fail coverage`:
before, they were skips, and a lane that skips what it cannot see passes a rewrite that does not move. -/
def byM (ph : Phase) (k : Kind) (d : Option Nat) (seg orig rew : List Samp) : List (Nat × Verdict) :=
  (List.range 12).map fun b => (b, bucketVerdict ph k d seg orig rew b)

/-- The verdicts of one (node, property) along a path of steps, one per step of the original.

A step's window is the original's sample of that step, and the original's steps in order are the segment its transitions
are cut from. A step the rewrite did not record is a skip. -/
def byStep (k : Kind) (d : Option Nat) (orig rew : List (String × Samp)) : List (String × Verdict) :=
  orig.map fun (s, o) =>
    match rew.find? (·.1 == s) with
    | some (_, r) => (s, judgeFlight k d (orig.map (·.2)) [o] r)
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
    judgeAgainst .colour [⟨none, none, [.num [255000]], 0⟩] ⟨none, some 0, [.num [0]], 0⟩ = .skip .transient := by decide

/-- A colour reading after `quietMs` is compared. -/
theorem judgeAgainst_quiet :
    judgeAgainst .colour [⟨none, none, [.num [255000]], 0⟩] ⟨none, none, [.num [0]], 0⟩ = .fail .apart := by decide

/-- A window sample that is not quiet still bounds a quiet colour. -/
theorem judgeAgainst_window_not_quiet :
    judgeAgainst .colour [⟨none, some 0, [.num [255000]], 0⟩] ⟨none, none, [.num [0]], 0⟩ = .fail .apart := by decide

/-- A window sample that is not quiet passes a colour inside its band. -/
theorem judgeAgainst_window_not_quiet_pass :
    judgeAgainst .colour [⟨none, some 0, [.num [255000]], 0⟩] ⟨none, none, [.num [255000]], 0⟩ = .pass := by decide

/-- A non-colour kind ignores quiet. -/
theorem judgeAgainst_other_kind :
    judgeAgainst .unit [⟨none, none, [.num [1000]], 0⟩] ⟨none, some 0, [.num [0]], 0⟩ = .fail .apart := by decide

-- Alignment ---------------------------------------------------------------------------------------------------------

/-- An exact hit on an interior sample takes the two enclosing pairs and one frame beyond. -/
theorem window_interior : window [0, 2000, 4000, 6000, 8000] 4000 = [0, 1, 2, 3, 4] := by decide

/-- A value between two samples takes that pair and one frame on each side. -/
theorem window_between : window [0, 2000, 4000, 6000, 8000, 10000] 5000 = [1, 2, 3, 4] := by decide

/-- A closing phase (falling values) aligns the same way. -/
theorem window_falling : window [10000, 8000, 6000, 4000, 2000] 7000 = [0, 1, 2, 3] := by decide

/-- A value beyond the range takes the nearest sample and one frame before it. -/
theorem window_outside : window [0, 2000, 4000] 9000 = [1, 2] := by decide

/-- Branch beyond reach: a morph value more than one bucket outside the original's range has no window.

The original was sampled over 0 to 0.15 only; the rewrite's 0.98 is not judged against it. -/
theorem windowOf_beyond :
    windowOf [⟨some 0, none, [.num [0]], 0⟩, ⟨some 1500, none, [.num [0]], 0⟩] (some 9800) = none := by decide

/-- Branch beyond reach, below: the same on the low side. -/
theorem windowOf_beyond_low :
    windowOf [⟨some 6000, none, [.num [0]], 0⟩, ⟨some 9000, none, [.num [0]], 0⟩] (some 0) = none := by decide

/-- Branch within reach: the nearest sample (and one frame before it) is the window. -/
theorem windowOf_within_reach :
    ((windowOf [⟨some 0, none, [.num [0]], 0⟩, ⟨some 9000, none, [.num [0]], 0⟩] (some 9800)).map List.length) = some 2 := by
  decide

/-- Branch no morph value in the rewrite sample: no window. -/
theorem windowOf_rewrite_no_m : windowOf [⟨some 0, none, [.num [0]], 0⟩] none = none := by decide

/-- Branch no morph value in an original sample: no window, whatever the rewrite's value. -/
theorem windowOf_orig_no_m :
    windowOf [⟨some 0, none, [.num [0]], 0⟩, ⟨none, none, [.num [0]], 0⟩] (some 0) = none := by decide

/-- Branch no original sample: no window. -/
theorem windowOf_orig_empty (m : Option Int) : windowOf [] m = none := by
  simp [windowOf, repsOf]

/-- The ramp of a pass: morph values 0 to 1 in steps of 0.2, each sample reading its own value. -/
def ramp (rep : Nat) : List Samp :=
  [0, 2000, 4000, 6000, 8000, 10000].map fun m => smr rep m [.num [m]]

/-- Why the passes are not concatenated: the last sample of pass 0 (m = 1) and the first of pass 1 (m = 0) are neighbours in
a list, and that pair encloses every `m`. Over the concatenation, the window of m = 0.4 holds the 1.0 end (index 5) and the 0.0
start (index 6) of the phase, and every sample but the last. -/
theorem window_concat_whole_phase :
    window [0, 2000, 4000, 6000, 8000, 10000, 0, 2000, 4000, 6000, 8000, 10000] 4000 = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10] := by
  decide

/-- Branch pooled: each pass is aligned on its own. Two passes of the ramp give the window of m = 0.4 from each pass (the
samples 0 to 0.8 of both), never the 1.0 end. -/
theorem windowOf_pooled_ramp :
    ((windowOf (ramp 0 ++ ramp 1) (some 4000)).getD []).map (fun s => (s.rep, s.m)) =
      [(0, some 0), (0, some 2000), (0, some 4000), (0, some 6000), (0, some 8000),
       (1, some 0), (1, some 2000), (1, some 4000), (1, some 6000), (1, some 8000)] := by
  decide

/-- Branch pooled, one pass slow: a rewrite sample at 0.98 is beyond the reach of a pass that stopped at 0.4 and has the
window of the pass that reached 1.0. -/
theorem windowOf_union_has_pass :
    ((windowOf ([0, 2000, 4000].map (fun m => smr 0 m [.num [m]]) ++ ramp 1) (some 9800)).getD []).map (·.rep) = [1, 1, 1] := by
  decide

/-- Branch pooled, no pass has a window: none. -/
theorem windowOf_pooled_beyond :
    windowOf ([0, 1500].map (fun m => smr 0 m [.num [m]]) ++ [0, 1500].map (fun m => smr 1 m [.num [m]])) (some 9800) = none := by
  decide

/-- Branch pooled, a pass without morph values: the other passes still align. -/
theorem windowOf_pooled_one_pass_no_m :
    ((windowOf ([⟨none, none, [.num [0]], 0⟩] ++ ramp 1) (some 4000)).getD []).map (·.rep) = [1, 1, 1, 1, 1] := by
  decide

/-- Every sample of a window of one pass is a sample of that pass's input. -/
theorem windowOne_sub (orig : List Samp) (m : Option Int) (x : Samp) (h : x ∈ (windowOne orig m).getD []) : x ∈ orig := by
  unfold windowOne at h
  cases m with
  | none => simp at h
  | some m =>
    simp only at h
    split at h
    · simp at h
    · split at h
      · simp at h
      · simp only [Option.getD_some, List.mem_filterMap] at h
        obtain ⟨i, _, hi⟩ := h
        exact List.mem_of_getElem? hi

/-- The window of a pooled list is the windows of its passes side by side. -/
theorem windowOf_getD (orig : List Samp) (m : Option Int) :
    (windowOf orig m).getD [] = ((repsOf orig).filterMap fun r => windowOne (passOf orig r) m).flatten := by
  unfold windowOf
  split <;> simp_all

/-- Pooling never widens a window: a sample is in the window of the pooled list exactly when it is in the window of its own
pass alone. No window mixes the samples of two passes. -/
theorem windowOf_pass_iff (orig : List Samp) (m : Option Int) (x : Samp) :
    x ∈ (windowOf orig m).getD [] ↔ x ∈ (windowOne (passOf orig x.rep) m).getD [] := by
  rw [windowOf_getD]
  constructor
  · intro h
    simp only [List.mem_flatten, List.mem_filterMap] at h
    obtain ⟨w, ⟨r, _, hr⟩, hx⟩ := h
    have hw : w = (windowOne (passOf orig r) m).getD [] := by simp [hr]
    rw [hw] at hx
    have hmem := windowOne_sub _ _ _ hx
    simp only [passOf, List.mem_filter, beq_iff_eq] at hmem
    have : r = x.rep := hmem.2.symm
    subst this
    exact hx
  · intro h
    have hmem := windowOne_sub _ _ _ h
    simp only [passOf, List.mem_filter, beq_iff_eq] at hmem
    simp only [List.mem_flatten, List.mem_filterMap]
    refine ⟨(windowOne (passOf orig x.rep) m).getD [], ⟨x.rep, ?_, ?_⟩, h⟩
    · simp only [repsOf, List.mem_eraseDups, List.mem_map]
      exact ⟨x, hmem.1, rfl⟩
    · cases hw : windowOne (passOf orig x.rep) m with
      | none => simp [hw] at h
      | some w => rfl

/-- Branch pooled, no window: the pooled list has none exactly when no pass has one. -/
theorem windowOf_none_iff (orig : List Samp) (m : Option Int) :
    windowOf orig m = none ↔ ∀ r ∈ repsOf orig, windowOne (passOf orig r) m = none := by
  unfold windowOf
  constructor
  · intro h r hr
    split at h
    · rename_i hnil
      have := List.filterMap_eq_nil_iff.mp hnil
      exact this r hr
    · simp at h
  · intro h
    have : (repsOf orig).filterMap (fun r => windowOne (passOf orig r) m) = [] :=
      List.filterMap_eq_nil_iff.mpr h
    simp [this]

/-- The ends of the reach: exactly one bucket outside still has a window; one unit more has none. -/
theorem beyond_edge : beyond [0, 2000] 3000 = false ∧ beyond [0, 2000] 3001 = true := by decide

/-- A phase with no samples has every morph value beyond reach. -/
theorem beyond_empty (m : Int) : beyond [] m = true := by simp [beyond]

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
    (byM .push .discrete none [] [⟨some 9000, none, [.str "off"], 0⟩, ⟨some 9300, none, [.str "on"], 0⟩]
        [⟨some 9200, none, [.str "on"], 0⟩]).getD 9 (9, .skip .noSample) = (9, .pass) := by decide

/-- Bug B: a class that stays `off` through the tween is a failure at the buckets where the original has `on`.

The original reads `on` from 0.93; the rewrite (waapi) sets the class only at the end, so at 0.95 it is still `off`. -/
theorem byM_stale_class :
    (byM .push .discrete none [] [sm 8000 [.str "off"], sm 8500 [.str "off"], sm 9000 [.str "off"], sm 9300 [.str "on"],
        sm 9400 [.str "on"], sm 9500 [.str "on"], sm 9600 [.str "on"], sm 9700 [.str "on"], sm 9900 [.str "on"]]
      [sm 9500 [.str "off"]]).getD 10 (10, .skip .noSample) = (10, .fail .differs) := by decide

/-- Branch empty bucket in a push, the whole of 1 to 9: no rewrite sample is `fail coverage`, never a skip or a pass. -/
theorem bucketVerdict_push_empty (k : Kind) (d : Option Nat) (seg orig rew : List Samp) (b : Nat) (hb : needsSample b = true)
    (h : ∀ r ∈ rew, bucket r.m ≠ b) : bucketVerdict .push k d seg orig rew b = .fail .coverage := by
  have hf : rew.filter (fun r => bucket r.m == b) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro r hr
    simpa using h r hr
  simp [bucketVerdict, hf, hb]

/-- Branch empty bucket in a hold: a skip. A hold waits at an end of the morph, so its interior buckets are empty by design. -/
theorem bucketVerdict_hold_empty (k : Kind) (d : Option Nat) (seg orig rew : List Samp) (b : Nat)
    (h : ∀ r ∈ rew, bucket r.m ≠ b) : bucketVerdict .hold k d seg orig rew b = .skip .noSample := by
  have hf : rew.filter (fun r => bucket r.m == b) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro r hr
    simpa using h r hr
  simp [bucketVerdict, hf]

/-- Branch empty end bucket in a push: buckets 0, 10 and 11 need no sample (the tween is only crossing them). -/
theorem bucketVerdict_push_empty_ends (k : Kind) (d : Option Nat) (seg orig : List Samp) :
    bucketVerdict .push k d seg orig [] 0 = .skip .noSample ∧ bucketVerdict .push k d seg orig [] 10 = .skip .noSample ∧
    bucketVerdict .push k d seg orig [] 11 = .skip .noSample := by
  simp [bucketVerdict, needsSample]

/-- The edges of the interior: buckets 1 and 9 need a sample, 0 and 10 do not. -/
theorem needsSample_edges :
    needsSample 0 = false ∧ needsSample 1 = true ∧ needsSample 9 = true ∧ needsSample 10 = false ∧
    needsSample 11 = false := by decide

/-- No pass without a sample: a bucket with no rewrite sample is never a pass. -/
theorem bucketVerdict_empty_not_pass (ph : Phase) (k : Kind) (d : Option Nat) (seg orig rew : List Samp) (b : Nat)
    (h : ∀ r ∈ rew, bucket r.m ≠ b) : bucketVerdict ph k d seg orig rew b ≠ .pass := by
  have hf : rew.filter (fun r => bucket r.m == b) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro r hr
    simpa using h r hr
  cases ph <;> simp only [bucketVerdict, hf] <;> split <;> simp

/-- Branch no morph value in a push: a rewrite sample the probe could not place on the morph fails in bucket 11. -/
theorem byM_push_no_m :
    (byM .push .discrete none [] [sm 0 [.str "on"], sm 10000 [.str "on"]] [s0 [.str "on"]]).getD 11 (11, .pass) =
      (11, .fail .coverage) := by decide

/-- Branch no morph value in the original: the phases cannot be aligned, every rewrite sample fails. -/
theorem byM_orig_no_m :
    (byM .push .discrete none [] [s0 [.str "on"]] [sm 5000 [.str "on"]]).getD 5 (5, .pass) = (5, .fail .coverage) := by decide

/-- Branch beyond reach: the rewrite at 0.98 against an original sampled over 0 to 0.15 is `fail coverage` (it was a skip). -/
theorem byM_beyond :
    (byM .push .geometry none [] [sm 0 [.num [0]], sm 1500 [.num [3000]]] [sm 9800 [.num [10000]]]).getD 10 (10, .pass) =
      (10, .fail .coverage) := by decide

/-- Branch hold, beyond reach: the same rule holds in a hold. -/
theorem byM_hold_beyond :
    (byM .hold .geometry none [] [sm 0 [.num [0]], sm 1500 [.num [3000]]] [sm 9800 [.num [10000]]]).getD 10 (10, .pass) =
      (10, .fail .coverage) := by decide

/-- Branch hold, a sample at the end: an empty interior bucket stays a skip. -/
theorem byM_hold_interior :
    (byM .hold .discrete none [] [sm 10000 [.str "on"]] [sm 10000 [.str "on"]]).getD 5 (5, .pass) = (5, .skip .noSample) := by
  decide

/-- Branch pooled passes, the stuck rewrite: three passes of a ramp against a rewrite that stays at 0 fail at 0.5.

Over the concatenation of the passes the window of 0.5 held the 0 end of the phase and this passed. -/
theorem byM_pooled_stuck :
    (byM .push .discrete none [] (ramp 0 ++ ramp 1 ++ ramp 2) [smr 0 5000 [.num [0]]]).getD 5 (5, .pass) = (5, .fail .differs) := by
  decide

/-- Branch pooled passes, a ramping rewrite: a rewrite that follows the ramp passes in its bucket. -/
theorem byM_pooled_ramp :
    (byM .push .discrete none [] (ramp 0 ++ ramp 1 ++ ramp 2) [smr 0 4000 [.num [4000]]]).getD 4 (4, .fail .differs) = (4, .pass) := by
  decide

/-- Every bucket 0 to 11 gets its own verdict: twelve per phase, in order. -/
theorem byM_length (ph : Phase) (k : Kind) (d : Option Nat) (seg orig rew : List Samp) : (byM ph k d seg orig rew).length = 12 := by
  simp [byM]

/-- The verdict of a bucket reads only the rewrite samples in that bucket and the original's samples.

A rewrite sample of another bucket cannot change it (unit independence). -/
theorem bucketVerdict_independent (ph : Phase) (k : Kind) (d : Option Nat) (seg orig rew : List Samp) (b : Nat) (r : Samp)
    (hb : bucket r.m ≠ b) : bucketVerdict ph k d seg orig (r :: rew) b = bucketVerdict ph k d seg orig rew b := by
  simp [bucketVerdict, hb]

/-- A step the original has and the rewrite lacks is a skip. -/
theorem byStep_missing :
    byStep .unit none [("s25", ⟨none, none, [.num [750]], 0⟩)] [] = [("s25", .skip .noSample)] := by decide

/-- A step is decided by that step's two samples only. -/
theorem byStep_pair :
    byStep .unit none [("s25", ⟨none, none, [.num [750]], 0⟩), ("s50", ⟨none, none, [.num [500]], 0⟩)]
      [("s25", ⟨none, none, [.num [1000]], 0⟩), ("s50", ⟨none, none, [.num [500]], 0⟩)] =
    [("s25", .fail .apart), ("s50", .pass)] := by decide

/-! ## Transitions in flight

A property with a declared transition is read at uncontrolled times while it runs, and the two arms start it at different
frames, so a reading can lie anywhere on the original's curve. The theorems below fix what the window of such a reading
may do: (a) a rewrite whose samples are the original's never fails (`judgeFlight_self`, `byStep_self`,
`bucketVerdict_self`); (b) a unit with no sample in flight is judged exactly as before (`judgeFlight_settled`,
`byStep_settled_differs`); (c) an in-flight reading outside every reading of the window and the transitions still fails
(`judgeFlight_outside`). -/

#guard settleOf "nav" "background-color" == some 700
#guard settleOf "earn" "opacity" == some 440
#guard settleOf "nav" "border-radius" == none
#guard settleOf "logo" "background-color" == none
#guard inFlight (some 700) ⟨none, some 899, [], 0⟩
#guard !inFlight (some 700) ⟨none, some 900, [], 0⟩
#guard !inFlight none ⟨none, some 0, [], 0⟩
#guard !inFlight (some 700) ⟨none, none, [], 0⟩
#guard (crossedPass (some 700) [s0 [.num [0]], ⟨none, some 1000, [.num [1]], 0⟩, ⟨none, some 100, [.num [2]], 0⟩,
  ⟨none, some 1000, [.num [3]], 0⟩, ⟨none, some 2000, [.num [4]], 0⟩]).map (·.els) = [[.num [1]], [.num [2]], [.num [3]]]
#guard crossed none [⟨none, some 0, [.num [0]], 0⟩] == []
#guard crossed (some 700) [⟨none, some 0, [.num [0]], 0⟩, ⟨none, some 0, [.num [1]], 1⟩] ==
  [⟨none, some 0, [.num [0]], 0⟩, ⟨none, some 0, [.num [1]], 1⟩]
#guard judgeFlight .colour (some 700) [s0 [.num [0]], ⟨none, some 100, [.num [5000]], 0⟩, s0 [.num [9000]]]
  [s0 [.num [9000]]] ⟨none, some 100, [.num [4000]], 0⟩ == .pass
#guard judgeFlight .colour (some 700) [s0 [.num [0]], ⟨none, some 100, [.num [5000]], 0⟩, s0 [.num [9000]]]
  [s0 [.num [9000]]] ⟨none, some 100, [.num [12000]], 0⟩ == .fail .apart
#guard judgeFlight .colour (some 700) [] [s0 [.num [9000]]] ⟨none, some 1000, [.num [0]], 0⟩ == .fail .apart
#guard judgeFlight .colour none [] [s0 [.num [9000]]] ⟨none, some 100, [.num [0]], 0⟩ == .skip .transient

/-- The table's three properties the stored runs failed against themselves, with the part CSS's values. -/
theorem settleOf_values : settleOf "nav" "background-color" = some 700 ∧ settleOf "earn" "max-width" = some 680 ∧
    settleOf "earn" "opacity" = some 440 := by decide

/-- A property the part CSS declares no transition on has none. -/
theorem settleOf_unlisted : settleOf "nav" "border-radius" = none := by decide

/-- Branch no declared transition: never in flight. -/
theorem inFlight_no_settle (s : Samp) : inFlight none s = false := by simp [inFlight]

/-- Branch no class change: never in flight. -/
theorem inFlight_no_change (d : Option Nat) (s : Samp) (h : s.since = none) : inFlight d s = false := by
  cases d <;> simp [inFlight, h]

/-- Branch both known: in flight exactly before the declared time plus the start lag. -/
theorem inFlight_iff (d t : Nat) (s : Samp) (h : s.since = some t) : inFlight (some d) s = true ↔ t < d + startLag := by
  simp [inFlight, h]

/-- Every sample `crossedPass` keeps is a sample of the pass. -/
theorem crossedPass_sub (d : Option Nat) (p : List Samp) (x : Samp) (h : x ∈ crossedPass d p) : x ∈ p := by
  simp only [crossedPass, List.mem_filterMap] at h
  obtain ⟨i, _, hi⟩ := h
  exact List.mem_of_getElem? hi

/-- A sample of a pass read in flight is kept. -/
theorem mem_crossedPass (d : Option Nat) (p : List Samp) (x : Samp) (hx : x ∈ p) (hf : inFlight d x = true) :
    x ∈ crossedPass d p := by
  obtain ⟨i, hi, rfl⟩ := List.mem_iff_getElem.mp hx
  simp only [crossedPass, List.mem_filterMap, List.mem_filter, List.mem_range, List.any_eq_true, Bool.and_eq_true,
    decide_eq_true_eq]
  refine ⟨i, ⟨hi, i, hi, ⟨?_, Nat.le_succ _⟩, Nat.le_succ _⟩, List.getElem?_eq_getElem hi⟩
  simp [List.getElem?_eq_getElem hi, hf]

/-- Every sample `crossed` keeps is a sample of the segment. -/
theorem crossed_sub (d : Option Nat) (seg : List Samp) (x : Samp) (h : x ∈ crossed d seg) : x ∈ seg := by
  simp only [crossed, List.mem_flatMap] at h
  obtain ⟨r, _, hx⟩ := h
  have := crossedPass_sub d _ x hx
  simp only [passOf, List.mem_filter] at this
  exact this.1

/-- A sample of the segment read in flight is kept: a reading the original took during a transition bounds the window. -/
theorem mem_crossed (d : Option Nat) (seg : List Samp) (x : Samp) (hx : x ∈ seg) (hf : inFlight d x = true) :
    x ∈ crossed d seg := by
  simp only [crossed, List.mem_flatMap]
  refine ⟨x.rep, ?_, mem_crossedPass d _ x ?_ hf⟩
  · simp only [repsOf, List.mem_eraseDups, List.mem_map]
    exact ⟨x, hx, rfl⟩
  · simp [passOf, hx]

/-- Without a declared transition nothing is crossed. -/
theorem crossed_no_settle (seg : List Samp) : crossed none seg = [] := by
  have h : inFlight none = fun _ => false := funext inFlight_no_settle
  simp only [crossed, crossedPass, h, List.flatMap_eq_nil_iff, List.filterMap_eq_nil_iff]
  intro r _ i hi
  simp only [List.mem_filter, List.mem_range, List.any_eq_true, Bool.and_eq_true, decide_eq_true_eq] at hi
  obtain ⟨_, j, _, ⟨hj, _⟩, _⟩ := hi
  cases hp : (passOf seg r)[j]? <;> simp [hp] at hj

/-- No declared transition is the judgement before transitions: `judgeAgainst`. -/
theorem judgeFlight_no_settle (k : Kind) (seg win : List Samp) (r : Samp) :
    judgeFlight k none seg win r = judgeAgainst k win r := by
  simp [judgeFlight, inFlight]

/-- Branch rewrite in flight: the window plus the original's transitions, by `judgeEls`. -/
theorem judgeFlight_rewrite (k : Kind) (d : Option Nat) (seg win : List Samp) (r : Samp) (h : inFlight d r = true) :
    judgeFlight k d seg win r = judgeEls k ((win ++ crossed d seg).map (·.els)) r.els := by
  simp [judgeFlight, h]

/-- Branch window in flight: the same, also when the rewrite's own sample is at rest. -/
theorem judgeFlight_window (k : Kind) (d : Option Nat) (seg win : List Samp) (r : Samp) (w : Samp) (hw : w ∈ win)
    (h : inFlight d w = true) : judgeFlight k d seg win r = judgeEls k ((win ++ crossed d seg).map (·.els)) r.els := by
  have : win.any (inFlight d) = true := List.any_eq_true.mpr ⟨w, hw, h⟩
  simp [judgeFlight, this]

/-- **(b) A settled unit is judged as before.** No sample in flight: the verdict is `judgeAgainst`, so a settled step
that differs fails exactly as it did. -/
theorem judgeFlight_settled (k : Kind) (d : Option Nat) (seg win : List Samp) (r : Samp) (hr : inFlight d r = false)
    (hw : ∀ w ∈ win, inFlight d w = false) : judgeFlight k d seg win r = judgeAgainst k win r := by
  have : win.any (inFlight d) = false := by
    rw [List.any_eq_false]; intro w h; simp [hw w h]
  simp [judgeFlight, hr, this]

/-- (b) on a step: a background read 1000 ms after the class change (past 700 + `startLag`) that differs still fails,
also with the original in flight one step earlier. -/
theorem byStep_settled_differs :
    byStep .colour (some 700) [("a6", ⟨none, some 100, [.num [1000, 0, 0, 33000]], 0⟩),
        ("a7", ⟨none, some 1000, [.num [255000, 255000, 255000, 26000]], 0⟩)]
      [("a6", ⟨none, some 100, [.num [1000, 0, 0, 33000]], 0⟩),
        ("a7", ⟨none, some 1000, [.num [1000, 0, 0, 26000]], 0⟩)] =
      [("a6", .pass), ("a7", .fail .apart)] := by decide

/-- A step in flight on the probe's curve (Chromium, 1280 px, run 39455284967): the original settles at a7 while the
baseline arm, started a few ms later, still runs its transition there and at a6. Both readings lie on the original's
curve from a5 to a7, so both pass. -/
theorem byStep_inflight_passes :
    byStep .colour (some 700) [("a5", ⟨none, some 2222, [.num [255000, 255000, 255000, 122400]], 0⟩),
        ("a6", ⟨none, some 481, [.num [1000, 0, 0, 33340]], 0⟩),
        ("a7", ⟨none, some 1134, [.num [255000, 255000, 255000, 26000]], 0⟩)]
      [("a5", ⟨none, some 1271, [.num [255000, 255000, 255000, 122400]], 0⟩),
        ("a6", ⟨none, some 327, [.num [1000, 0, 0, 51667]], 0⟩),
        ("a7", ⟨none, some 703, [.num [1000, 0, 0, 26029]], 0⟩)] =
      [("a5", .pass), ("a6", .pass), ("a7", .pass)] := by decide

/-- The numbers of a list of one-number readings are those numbers. -/
theorem numsOf_singles (ys : List Int) : numsOf (ys.map fun y => Val.num [y]) = some (ys.map fun y => [y]) := by
  induction ys with
  | nil => rfl
  | cons y ys ih => simp [numsOf, ih]

/-- A one-number reading beyond every number of a non-empty band, by more than the tolerance, is outside it. -/
theorem inBand_single_out (t : Int) (ys : List Int) (hne : ys ≠ []) (x : Int)
    (hx : (∀ y ∈ ys, y + t < x) ∨ (∀ y ∈ ys, x + t < y)) : inBand t (ys.map fun y => [y]) [x] = false := by
  have hc : (ys.map fun y => [y]).map (·.getD 0 0) = ys := by
    rw [List.map_map]; exact List.map_id'' (fun _ => rfl) ys
  obtain ⟨lo, hlo⟩ := Option.isSome_iff_exists.mp (List.isSome_min?_of_ne_nil hne)
  obtain ⟨hi, hhi⟩ := Option.isSome_iff_exists.mp (List.isSome_max?_of_ne_nil hne)
  simp only [inBand, List.length_singleton, List.range_one, List.all_cons, List.all_nil, Bool.and_true, hc, hlo, hhi,
    List.getD_cons_zero, Bool.and_eq_false_iff, decide_eq_false_iff_not]
  rcases hx with h | h
  · right; have := h hi (List.max?_mem hhi); omega
  · left; have := h lo (List.min?_mem hlo); omega

/-- **(c) A value outside the window still fails.** A one-number reading in flight that lies beyond every reading of
the window and of the original's transitions, by more than the tolerance, fails `apart`; the start lag widens only which
readings are compared with the transitions, never how far a reading may lie from them. -/
theorem judgeFlight_outside (k : Kind) (hk : k ≠ .discrete) (d : Option Nat) (seg win : List Samp) (r : Samp)
    (hf : inFlight d r = true ∨ ∃ w ∈ win, inFlight d w = true) (ys : List Int)
    (hW : (win ++ crossed d seg).map (·.els) = ys.map fun y => [Val.num [y]]) (hne : ys ≠ []) (x : Int)
    (hr : r.els = [.num [x]]) (hx : (∀ y ∈ ys, y + tol k < x) ∨ (∀ y ∈ ys, x + tol k < y)) :
    judgeFlight k d seg win r = .fail .apart := by
  have heq : judgeFlight k d seg win r = judgeEls k ((win ++ crossed d seg).map (·.els)) r.els := by
    rcases hf with h | ⟨w, hw, h⟩
    · exact judgeFlight_rewrite k d seg win r h
    · exact judgeFlight_window k d seg win r w hw h
  have hcol : (ys.map fun y => [Val.num [y]]).map (·.getD 0 .absent) = ys.map fun y => Val.num [y] := by
    rw [List.map_map]; rfl
  have hval : judgeVal k (ys.map fun y => Val.num [y]) (.num [x]) = .fail .apart := by
    have hk' : (k == .discrete) = false := by cases k <;> simp_all
    have habs : (ys.map fun y => Val.num [y]).any (· == .absent) = false := by simp
    have hlen : (ys.map fun y => [y]).any (·.length != [x].length) = false := by simp
    simp only [judgeVal, List.isEmpty_iff, List.map_eq_nil_iff, hne, habs, numsOf_singles, hlen, hk',
      inBand_single_out (tol k) ys hne x hx, Bool.false_eq_true, ↓reduceIte]
  rw [heq, hW, hr]
  have hany : ((ys.map fun y => [Val.num [y]]).any fun x => x.length != 1) = false := by simp
  simp only [judgeEls, List.isEmpty_iff, List.map_eq_nil_iff, hne, hany, Bool.false_eq_true, ↓reduceIte,
    List.length_singleton, List.range_one, List.map_cons, List.map_nil, List.getD_cons_zero, hcol, hval]
  rfl

/-- The form of a reading: absent, a string, or a number of `n` components. Two readings of one property in one arm
share it unless an element appears or disappears. -/
inductive Form where
  | absent
  | str
  | num (n : Nat)
  deriving DecidableEq, Repr

/-- The form of a reading. -/
def Val.form : Val → Form
  | .absent => .absent
  | .str _ => .str
  | .num xs => .num xs.length

/-- The forms of a sample's elements. -/
def Samp.form (s : Samp) : List Form := s.els.map Val.form

#guard (⟨none, none, [.absent, .str "a", .num [1, 2]], 0⟩ : Samp).form == [.absent, .str, .num 2]

/-- Verdicts none of which fails combine to one that does not fail. -/
theorem combine_no_fail (vs : List Verdict) (h : ∀ v ∈ vs, isFail v = false) : isFail (combine vs) = false := by
  have hn : vs.find? (fun v => match v with | .fail _ => true | _ => false) = none := by
    rw [List.find?_eq_none]
    intro v hv
    have := h v hv
    cases v <;> simp_all [isFail]
  simp only [combine, hn]
  split <;> (try split) <;> rfl

/-- A strings window has its strings. -/
theorem strsOf_all (win : List Val) (h : ∀ v ∈ win, v.form = .str) :
    ∃ ss, strsOf win = some ss ∧ ∀ s, Val.str s ∈ win → s ∈ ss := by
  induction win with
  | nil => exact ⟨[], rfl, by simp⟩
  | cons v rest ih =>
    obtain ⟨ss, hss, hm⟩ := ih (fun w hw => h w (List.mem_cons_of_mem _ hw))
    cases v with
    | str t =>
      refine ⟨t :: ss, by simp [strsOf, hss], ?_⟩
      intro s hs
      rcases List.mem_cons.mp hs with h1 | h1
      · cases h1; exact List.mem_cons_self ..
      · exact List.mem_cons_of_mem _ (hm s h1)
    | absent => simp [Val.form] at h
    | num _ => simp [Val.form] at h

/-- A numbers window of one length has its numbers, all of that length. -/
theorem numsOf_all (win : List Val) (n : Nat) (h : ∀ v ∈ win, v.form = .num n) :
    ∃ ns, numsOf win = some ns ∧ (∀ xs, Val.num xs ∈ win → xs ∈ ns) ∧ ∀ ys ∈ ns, ys.length = n := by
  induction win with
  | nil => exact ⟨[], rfl, by simp, by simp⟩
  | cons v rest ih =>
    obtain ⟨ns, hns, hm, hl⟩ := ih (fun w hw => h w (List.mem_cons_of_mem _ hw))
    cases v with
    | num ys =>
      have hy : ys.length = n := by have := h (.num ys) (List.mem_cons_self ..); simpa [Val.form] using this
      refine ⟨ys :: ns, by simp [numsOf, hns], ?_, ?_⟩
      · intro xs hxs
        rcases List.mem_cons.mp hxs with h1 | h1
        · cases h1; exact List.mem_cons_self ..
        · exact List.mem_cons_of_mem _ (hm xs h1)
      · intro zs hz
        rcases List.mem_cons.mp hz with h1 | h1
        · rw [h1]; exact hy
        · exact hl zs h1
    | absent => simp [Val.form] at h
    | str _ => simp [Val.form] at h

/-- A reading of the window lies in its band. -/
theorem inBand_mem (t : Int) (ht : 0 ≤ t) (win : List (List Int)) (xs : List Int) (h : xs ∈ win) :
    inBand t win xs = true := by
  unfold inBand
  rw [List.all_eq_true]
  intro j _
  have hx : xs.getD j 0 ∈ win.map (·.getD j 0) := List.mem_map_of_mem h
  obtain ⟨lo, hlo⟩ := Option.isSome_iff_exists.mp (List.isSome_min?_of_mem hx)
  obtain ⟨hi, hhi⟩ := Option.isSome_iff_exists.mp (List.isSome_max?_of_mem hx)
  have h1 := (List.min?_eq_some_iff.1 hlo).2 _ hx
  have h2 := (List.max?_eq_some_iff.1 hhi).2 _ hx
  simp only [hlo, hhi, Bool.and_eq_true, decide_eq_true_eq]
  omega

/-- Every tolerance is at least zero. -/
theorem tol_nonneg (k : Kind) : 0 ≤ tol k := by cases k <;> decide

/-- A reading of the window, of the form of all the window's readings, never fails against it. -/
theorem judgeVal_self (k : Kind) (win : List Val) (r : Val) (hr : r ∈ win) (hf : ∀ v ∈ win, v.form = r.form) :
    isFail (judgeVal k win r) = false := by
  have hne : win.isEmpty = false := by cases win <;> simp_all
  cases r with
  | absent =>
    have hall : win.all (· == .absent) = true := by
      rw [List.all_eq_true]; intro v hv; have := hf v hv; cases v <;> simp_all [Val.form]
    simp [judgeVal, hne, hall, isFail]
  | str s =>
    have hab : win.any (· == .absent) = false := by
      rw [List.any_eq_false]; intro v hv; have := hf v hv; cases v <;> simp_all [Val.form]
    obtain ⟨ss, hss, hm⟩ := strsOf_all win (fun v hv => by simpa [Val.form] using hf v hv)
    simp [judgeVal, hne, hab, hss, hm s hr, isFail]
  | num xs =>
    have hab : win.any (· == .absent) = false := by
      rw [List.any_eq_false]; intro v hv; have := hf v hv; cases v <;> simp_all [Val.form]
    obtain ⟨ns, hns, hm, hl⟩ := numsOf_all win xs.length (fun v hv => by simpa [Val.form] using hf v hv)
    have hx := hm xs hr
    have hlen : ns.any (·.length != xs.length) = false := by
      rw [List.any_eq_false]; intro ys hy; simp [hl ys hy]
    have hc : ns.contains xs = true := by simpa using hx
    have hb := inBand_mem (tol k) (tol_nonneg k) ns xs hx
    simp only [judgeVal, hne, hab, hns, hlen, hc, hb, Bool.false_eq_true, ↓reduceIte]
    split <;> rfl

/-- The `i`th element of two samples of one form has one form. -/
theorem form_getD (a b : List Val) (h : a.map Val.form = b.map Val.form) (i : Nat) :
    (a.getD i .absent).form = (b.getD i .absent).form := by
  have := congrArg (·[i]?) h
  simp only [List.getElem?_map] at this
  simp only [List.getD_eq_getElem?_getD]
  cases ha : a[i]? <;> cases hb : b[i]? <;> simp_all [Val.form]

/-- A sample of the window, of the form of all the window's samples, never fails against it. -/
theorem judgeEls_self (k : Kind) (win : List (List Val)) (r : List Val) (hr : r ∈ win)
    (hf : ∀ w ∈ win, w.map Val.form = r.map Val.form) : isFail (judgeEls k win r) = false := by
  have hne : win.isEmpty = false := by cases win <;> simp_all
  have hlen : win.any (·.length != r.length) = false := by
    rw [List.any_eq_false]; intro w hw
    have := congrArg List.length (hf w hw)
    simp only [List.length_map] at this
    simp [this]
  simp only [judgeEls, hne, hlen, Bool.false_eq_true, ↓reduceIte]
  apply combine_no_fail
  intro v hv
  simp only [List.mem_map, List.mem_range] at hv
  obtain ⟨i, _, rfl⟩ := hv
  apply judgeVal_self
  · exact List.mem_map_of_mem hr
  · intro v hv
    simp only [List.mem_map] at hv
    obtain ⟨w, hw, rfl⟩ := hv
    exact form_getD w r (hf w hw) i

/-- **(a) A reading the original took is never failed.** A rewrite sample that is one of its window's samples, of the
form of the window and of the original's transitions, never fails, in flight or not. -/
theorem judgeFlight_self (k : Kind) (d : Option Nat) (seg win : List Samp) (r : Samp) (hr : r ∈ win)
    (hf : ∀ s ∈ win ++ crossed d seg, s.form = r.form) : isFail (judgeFlight k d seg win r) = false := by
  unfold judgeFlight
  split
  · apply judgeEls_self
    · exact List.mem_map_of_mem (List.mem_append_left _ hr)
    · intro w hw
      simp only [List.mem_map] at hw
      obtain ⟨s, hs, rfl⟩ := hw
      exact hf s hs
  · unfold judgeAgainst
    split
    · rfl
    · apply judgeEls_self
      · exact List.mem_map_of_mem hr
      · intro w hw
        simp only [List.mem_map] at hw
        obtain ⟨s, hs, rfl⟩ := hw
        exact hf s (List.mem_append_left _ hs)

/-- A step of a list with distinct steps is found at its own entry. -/
theorem find_step (orig : List (String × Samp)) (hn : (orig.map (·.1)).Nodup) (s : String) (o : Samp)
    (h : (s, o) ∈ orig) : orig.find? (·.1 == s) = some (s, o) := by
  induction orig with
  | nil => simp at h
  | cons a rest ih =>
    simp only [List.map_cons, List.nodup_cons, List.mem_map] at hn
    rcases List.mem_cons.mp h with h1 | h1
    · subst h1; simp
    · have hne : a.1 ≠ s := by
        intro he; exact hn.1 ⟨(s, o), h1, he.symm⟩
      simp [hne, ih hn.2 h1]

/-- **(a) on a path of steps.** An arm whose samples are the original's, step for step, never fails a step, in flight or
not, when the original's steps are distinct and its samples share a form. -/
theorem byStep_self (k : Kind) (d : Option Nat) (orig : List (String × Samp)) (hn : (orig.map (·.1)).Nodup)
    (hf : ∀ a ∈ orig, ∀ b ∈ orig, a.2.form = b.2.form) : ∀ v ∈ byStep k d orig orig, isFail v.2 = false := by
  intro v hv
  simp only [byStep, List.mem_map] at hv
  obtain ⟨⟨s, o⟩, hmem, rfl⟩ := hv
  simp only [find_step orig hn s o hmem]
  apply judgeFlight_self k d _ [o] o (List.mem_singleton_self _)
  intro x hx
  rcases List.mem_append.mp hx with h1 | h1
  · rw [List.mem_singleton.mp h1]
  · have := crossed_sub d _ x h1
    simp only [List.mem_map] at this
    obtain ⟨a, ha, rfl⟩ := this
    exact hf a ha (s, o) hmem

/-- A sample's own morph value aligns it to itself: its index is in the window of its value. -/
theorem window_self (ms : List Int) (m : Int) (j : Nat) (hj : j < ms.length) (hm : ms.getD j 0 = m) :
    j ∈ window ms m := by
  have hne : ms ≠ [] := by intro h; simp [h] at hj
  have hn : ms.isEmpty = false := by cases ms <;> simp_all
  have hcore : coreIdx ms m j = true := by
    by_cases h2 : 2 ≤ ms.length
    · have hp : pairHit ms m j = true := by
        unfold pairHit between
        rw [hm]
        by_cases hj1 : j + 1 < ms.length
        · simp [hj1, Int.min_le_left, Int.le_max_left]
        · have : 0 < j := by omega
          simp [this, Int.min_le_right, Int.le_max_right]
      have hh : hasPair ms m = true := List.any_eq_true.mpr ⟨j, List.mem_range.mpr hj, hp⟩
      simp [coreIdx, hh, hp]
    · have hj0 : j = 0 := by omega
      have hl : ms.length = 1 := by omega
      have hh : hasPair ms m = false := by
        simp [hasPair, hl, pairHit]
      have := nearest_lt ms m hne
      simp [coreIdx, hh, hj0]
      omega
  unfold window
  simp only [hn, Bool.false_eq_true, ↓reduceIte, List.mem_filter, List.mem_range, List.any_eq_true, Bool.and_eq_true,
    decide_eq_true_eq]
  exact ⟨hj, j, hj, ⟨hcore, Nat.le_succ _⟩, Nat.le_succ _⟩

/-- A sample of a pass whose samples all have a morph value is in the window of its own value. -/
theorem windowOne_self (p : List Samp) (r : Samp) (hr : r ∈ p) (hm : ∀ s ∈ p, s.m.isSome) :
    r ∈ (windowOne p r.m).getD [] := by
  obtain ⟨m, hrm⟩ := Option.isSome_iff_exists.mp (hm r hr)
  obtain ⟨j, hj, hpj⟩ := List.mem_iff_getElem.mp hr
  have hnone : p.any (·.m.isNone) = false := by
    rw [List.any_eq_false]; intro s hs; simp [Option.isSome_iff_ne_none.mp (hm s hs)]
  have hget : (p.map (·.m.getD 0)).getD j 0 = m := by
    simp [List.getD_eq_getElem?_getD, hj, hpj, hrm]
  have hmem : m ∈ p.map (·.m.getD 0) := List.mem_map.mpr ⟨r, hr, by simp [hrm]⟩
  have hbey : beyond (p.map (·.m.getD 0)) m = false := by
    unfold beyond
    have h1 : (p.map (·.m.getD 0)).all (fun x => x + reach < m) = false :=
      List.all_eq_false.mpr ⟨m, hmem, by unfold reach; simp only [decide_eq_true_eq]; omega⟩
    have h2 : (p.map (·.m.getD 0)).all (fun x => m + reach < x) = false :=
      List.all_eq_false.mpr ⟨m, hmem, by unfold reach; simp only [decide_eq_true_eq]; omega⟩
    simp [h1, h2]
  rw [hrm]
  simp only [windowOne, hnone, hbey, Bool.false_eq_true, ↓reduceIte, Option.getD_some, List.mem_filterMap]
  exact ⟨j, window_self _ m j (by simpa using hj) hget, by simp [hj, hpj]⟩

/-- A sample of a pooled original whose samples all have a morph value has a window, and is in it. -/
theorem windowOf_self (orig : List Samp) (r : Samp) (hr : r ∈ orig) (hm : ∀ s ∈ orig, s.m.isSome) :
    ∃ w, windowOf orig r.m = some w ∧ r ∈ w := by
  have hp : r ∈ passOf orig r.rep := by simp [passOf, hr]
  have h1 := windowOne_self (passOf orig r.rep) r hp
    (fun s hs => hm s (by simp only [passOf, List.mem_filter] at hs; exact hs.1))
  have h2 := (windowOf_pass_iff orig r.m r).mpr h1
  cases hw : windowOf orig r.m with
  | none => simp [hw] at h2
  | some w => exact ⟨w, rfl, by simpa [hw] using h2⟩

/-- **(a) on the morph path.** An arm whose samples are the original's, at every pass, never fails a bucket it has a
sample in, in flight or not, when every sample of the original has a morph value and the original's samples and its
transition path share a form. -/
theorem bucketVerdict_self (ph : Phase) (k : Kind) (d : Option Nat) (seg orig : List Samp) (b : Nat)
    (hm : ∀ s ∈ orig, s.m.isSome) (hf : ∀ a ∈ orig ++ seg, ∀ c ∈ orig ++ seg, a.form = c.form)
    (hb : ∃ s ∈ orig, bucket s.m = b) : isFail (bucketVerdict ph k d seg orig orig b) = false := by
  obtain ⟨s0, hs0, hsb⟩ := hb
  have hin : s0 ∈ orig.filter (fun r => bucket r.m == b) := List.mem_filter.mpr ⟨hs0, by simp [hsb]⟩
  unfold bucketVerdict
  cases hfl : orig.filter (fun r => bucket r.m == b) with
  | nil => simp [hfl] at hin
  | cons r0 rs =>
    apply combine_no_fail
    intro v hv
    simp only [List.mem_map] at hv
    obtain ⟨r, hr, rfl⟩ := hv
    have hro : r ∈ orig := by rw [← hfl] at hr; exact (List.mem_filter.mp hr).1
    obtain ⟨w, hw, hrw⟩ := windowOf_self orig r hro hm
    simp only [judgeIn, hw]
    apply judgeFlight_self k d seg w r hrw
    intro x hx
    apply hf x _ r (List.mem_append_left _ hro)
    rcases List.mem_append.mp hx with h1 | h1
    · have hx' : x ∈ (windowOf orig r.m).getD [] := by simp [hw, h1]
      have := windowOne_sub _ _ _ ((windowOf_pass_iff orig r.m x).mp hx')
      simp only [passOf, List.mem_filter] at this
      exact List.mem_append_left _ this.1
    · exact List.mem_append_right _ (crossed_sub d seg x h1)

/-- The lane fails when one unit fails, and only then. -/
theorem laneFails_iff (vs : List Verdict) : laneFails vs = true ↔ ∃ v ∈ vs, isFail v = true := by
  simp [laneFails]

/-- A lane of passes and skips does not fail. -/
theorem laneFails_none : laneFails [.pass, .skip .noSample, .skip .transient] = false := by decide

-- Against the faithful arm ------------------------------------------------------------------------------------------

/-- What one unit says relative to the same unit of the faithful arm (the default config against the original).

`new` fails here and passes (or is not compared) there; `both` fails in both, so the candidate did not cause it; `cleared`
fails only there; `ok` fails in neither. `unmeasured`: the candidate fails on content (a difference) where the faithful arm
fails on coverage, so the faithful arm was not measured there and the unit has no verdict either way. -/
inductive Rel where
  | ok
  | both
  | cleared
  | new
  | unmeasured
  deriving DecidableEq, Repr

/-- The failure is a coverage failure (nothing to compare with), not a difference between the arms. -/
def isCoverage : Verdict → Bool
  | .fail .coverage => true
  | _ => false

/-- One unit against the same unit of the baseline. A unit the baseline does not have is a skip there, so a failure is `new`.

Both fail: `unmeasured` when the candidate's failure is a difference and the baseline's is coverage (the faithful arm has no
sample to compare, so the candidate's difference is not shown to be shared); else `both`. -/
def rel (cand base : Verdict) : Rel :=
  match isFail cand, isFail base with
  | true, true => if isCoverage base && !isCoverage cand then .unmeasured else .both
  | true, false => .new
  | false, true => .cleared
  | false, false => .ok

/-- The candidate is red when any unit is `new`. -/
def laneRed (rs : List Rel) : Bool := rs.any (· == .new)

/-- Branch fails here, passes there: new. -/
theorem rel_new : rel (.fail .apart) .pass = .new := by decide

/-- Branch fails here, is not compared there: new (no evidence that the faithful arm fails). -/
theorem rel_new_skip : rel (.fail .differs) (.skip .noSample) = .new := by decide

/-- Branch fails in both, same kind of reason: not new. -/
theorem rel_both : rel (.fail .apart) (.fail .apart) = .both := by decide

/-- Branch fails in both, the baseline for a different content reason: still `both`. -/
theorem rel_both_content : rel (.fail .apart) (.fail .differs) = .both := by decide

/-- Branch both fail coverage: `both` (neither arm was measured, the candidate adds nothing). -/
theorem rel_both_coverage : rel (.fail .coverage) (.fail .coverage) = .both := by decide

/-- Branch the candidate fails coverage, the baseline on content: `both`. -/
theorem rel_both_cand_coverage : rel (.fail .coverage) (.fail .apart) = .both := by decide

/-- Branch the candidate fails on content, the baseline on coverage: `unmeasured`, never `both` and never `new`. -/
theorem rel_unmeasured : rel (.fail .apart) (.fail .coverage) = .unmeasured := by decide

/-- Branch fails only in the baseline: cleared. -/
theorem rel_cleared : rel .pass (.fail .apart) = .cleared := by decide

/-- Branch a skip against a failing baseline is cleared, never `new`. -/
theorem rel_skip_cleared : rel (.skip .transient) (.fail .differs) = .cleared := by decide

/-- Branch passes in both: ok. -/
theorem rel_ok : rel .pass .pass = .ok ∧ rel (.skip .noSample) .pass = .ok := by decide

/-- A unit is new exactly when it fails in the candidate and not in the baseline. -/
theorem rel_new_iff (c b : Verdict) : rel c b = .new ↔ isFail c = true ∧ isFail b = false := by
  unfold rel
  cases hc : isFail c <;> cases hb : isFail b <;> simp <;> split <;> simp

/-- The candidate is red exactly when some unit is new. -/
theorem laneRed_iff (rs : List Rel) : laneRed rs = true ↔ Rel.new ∈ rs := by
  simp [laneRed]

/-- A candidate whose every unit fails where the baseline fails is not red: the baseline's red does not count. -/
theorem laneRed_baseline_red : laneRed [rel (.fail .apart) (.fail .apart), rel (.fail .coverage) (.fail .apart)] = false := by
  decide

/-- An unmeasured unit is not new: the lane does not go red on it, and the report lists it apart. -/
theorem laneRed_unmeasured : laneRed [rel (.fail .apart) (.fail .coverage)] = false := by decide

-- Which arm was measured --------------------------------------------------------------------------------------------

/-- The two arms of the lane. -/
inductive Site where
  | orig
  | rewrite
  deriving DecidableEq, Repr

/-- What an arm's page reported after it loaded: the config hash and the mode the rewrite's own `window.__fw` holds
(`none` when the page has no such object), and the config hash its search names in the build (`want`, from `configs.json`). -/
structure ArmRead where
  site : Site
  want : Option String
  config : Option String
  mode : Option String
  deriving DecidableEq, Repr

/-- The verdict on the arm: measured as asked, or refused. A refused run is never a pass. -/
inductive ArmVerdict where
  | ok
  | refusedConfig
  deriving DecidableEq, Repr

/-- The allowlist: the rewrite arm is measured iff its page resolved exactly the prerendered config of its search and
hydrated it; the original arm iff its page has no `window.__fw` (it is not the rewrite). Everything else is refused.

A rewrite loaded at `/` without the search client-renders the default config (the hash differs from the flagged page's),
which measures the rewrite with its flags off. -/
def armCheck (a : ArmRead) : ArmVerdict :=
  match a.site with
  | .orig => if a.config.isNone && a.mode.isNone then .ok else .refusedConfig
  | .rewrite =>
    match a.want, a.config, a.mode with
    | some w, some c, some m => if !w.isEmpty && c == w && m == "hydrate" then .ok else .refusedConfig
    | _, _, _ => .refusedConfig

/-- A run is measured as asked iff it has arms and every arm is. -/
def runCheck (arms : List ArmRead) : ArmVerdict :=
  if !arms.isEmpty && arms.all (fun a => armCheck a == .ok) then .ok else .refusedConfig

/-- Branch rewrite as asked: the search's hash, hydrated. -/
theorem armCheck_rewrite_ok : armCheck ⟨.rewrite, some "ab12", some "ab12", some "hydrate"⟩ = .ok := by decide

/-- Branch flags off: the page resolved another config than the search names (incident inc-variant-gate-flags-off). -/
theorem armCheck_flags_off : armCheck ⟨.rewrite, some "ab12", some "cd34", some "client-render"⟩ = .refusedConfig := by decide

/-- Branch client render: the hash matches but the page was rendered on the client, not hydrated. -/
theorem armCheck_client_render : armCheck ⟨.rewrite, some "ab12", some "ab12", some "client-render"⟩ = .refusedConfig := by
  decide

/-- Branch hash differs, hydrated: refused all the same. -/
theorem armCheck_hash_differs : armCheck ⟨.rewrite, some "ab12", some "cd34", some "hydrate"⟩ = .refusedConfig := by decide

/-- Branch no config reported: refused. -/
theorem armCheck_no_config : armCheck ⟨.rewrite, some "ab12", none, some "hydrate"⟩ = .refusedConfig := by decide

/-- Branch no mode reported: refused. -/
theorem armCheck_no_mode : armCheck ⟨.rewrite, some "ab12", some "ab12", none⟩ = .refusedConfig := by decide

/-- Branch the search names no prerendered config: refused. -/
theorem armCheck_no_want : armCheck ⟨.rewrite, none, some "ab12", some "hydrate"⟩ = .refusedConfig := by decide

/-- Branch an empty wanted hash: refused, even when the page reports an empty one. -/
theorem armCheck_empty_want : armCheck ⟨.rewrite, some "", some "", some "hydrate"⟩ = .refusedConfig := by decide

/-- Branch the original as asked: its page has no `window.__fw`. -/
theorem armCheck_orig_ok : armCheck ⟨.orig, none, none, none⟩ = .ok := by decide

/-- Branch the original page reports a config: it is not the original. -/
theorem armCheck_orig_foreign : armCheck ⟨.orig, none, some "ab12", some "hydrate"⟩ = .refusedConfig := by decide

/-- Branch a run with no arm: refused, no evidence. -/
theorem runCheck_empty : runCheck [] = .refusedConfig := by decide

/-- A run is measured as asked exactly when it has arms and each arm is. -/
theorem runCheck_ok_iff (arms : List ArmRead) :
    runCheck arms = .ok ↔ arms ≠ [] ∧ ∀ a ∈ arms, armCheck a = .ok := by
  unfold runCheck
  cases arms with
  | nil => simp
  | cons a rest => simp

/-- One refused arm refuses the run: a good original does not rescue a rewrite with its flags off. -/
theorem runCheck_one_bad :
    runCheck [⟨.orig, none, none, none⟩, ⟨.rewrite, some "ab12", some "cd34", some "client-render"⟩] = .refusedConfig := by
  decide

-- Timing of the samples ---------------------------------------------------------------------------------------------

/-- Insert into an ascending list. -/
def insertSorted (x : Nat) : List Nat → List Nat
  | [] => [x]
  | y :: ys => if x ≤ y then x :: y :: ys else y :: insertSorted x ys

/-- Ascending order of a list of milliseconds. -/
def sortNat (xs : List Nat) : List Nat := xs.foldr insertSorted []

/-- The nearest-rank quantile of a list of milliseconds: the `ceil(p n / 100)`-th smallest, `p` from 1 to 100 (none for an
empty list). 50 is the median and 90 the value nine tenths of the samples do not exceed. -/
def quantile (xs : List Nat) (p : Nat) : Option Nat :=
  let s := sortNat xs
  s[min ((p * s.length + 99) / 100 - 1) (s.length - 1)]?

/-- The reads dominate the frame when the median read takes at least half the median gap between two samples.

A sample is the reads of one frame plus the wait for the next frame; if the reads alone fill half of it, the browser is
slow at `getComputedStyle`, not at drawing, and a lighter read set samples faster. -/
def readsDominate (readP50 gapP50 : Nat) : Bool := decide (0 < gapP50) && decide (gapP50 ≤ 2 * readP50)

/-- Branch empty: no samples, no quantile. -/
theorem quantile_empty (p : Nat) : quantile [] p = none := by simp [quantile, sortNat]

/-- Branch median: the middle of five. -/
theorem quantile_median : quantile [50, 10, 40, 20, 30] 50 = some 30 := by decide

/-- Branch p90: nearest rank, the ninth of ten. -/
theorem quantile_p90 : quantile [10, 20, 30, 40, 50, 60, 70, 80, 90, 100] 90 = some 90 := by decide

/-- Branch one sample: every quantile is that sample. -/
theorem quantile_one : quantile [7] 50 = some 7 ∧ quantile [7] 90 = some 7 := by decide

/-- Branch unsorted input: the order of the samples does not matter. -/
theorem quantile_order : quantile [3, 1, 2] 90 = quantile [1, 2, 3] 90 := by decide

/-- Branch reads dominate: a 90 ms read in a 150 ms gap. -/
theorem readsDominate_yes : readsDominate 90 150 = true := by decide

/-- Branch reads do not dominate: a 5 ms read in a 18 ms gap. -/
theorem readsDominate_no : readsDominate 5 18 = false := by decide

/-- Branch no gap: nothing to compare with, not dominating. -/
theorem readsDominate_no_gap : readsDominate 5 0 = false := by decide

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

-- Stored runs: the cells of preset admission -------------------------------------------------------------------------

/-- The engine of a stored run: Chromium, Playwright WebKit on Linux, or Playwright WebKit on macOS (job `probe-apple`). -/
inductive Engine where
  | chromium
  | linuxWebkit
  | macWebkit
  deriving DecidableEq, Repr

/-- The engine families a preset member must pass in. -/
inductive Family where
  | chromium
  | webkit
  deriving DecidableEq, Repr

/-- The family of an engine. -/
def Engine.family : Engine → Family
  | .chromium => .chromium
  | .linuxWebkit => .webkit
  | .macWebkit => .webkit

/-- A scroll path of the probe. -/
inductive Walk where
  | hero
  | morph
  deriving DecidableEq, Repr

/-- Whether the engine can decide the path: Linux WebKit's 150 ms frames fail morph push coverage by construction. -/
def covers : Engine → Walk → Bool
  | .linuxWebkit, .morph => false
  | _, _ => true

/-- The paths the probe walks for an engine: those it can decide. -/
def walks (e : Engine) : List Walk := [Walk.hero, .morph].filter (covers e)

/-- A path is walked exactly when the engine decides it. -/
theorem mem_walks_iff (e : Engine) (w : Walk) : w ∈ walks e ↔ covers e w = true := by
  cases e <;> cases w <;> simp [walks, covers]

/-- Chromium walks both paths. -/
theorem walks_chromium : walks .chromium = [.hero, .morph] := by decide

/-- Linux WebKit walks the hero path only: its morph pushes cannot be decided. -/
theorem walks_linux_webkit : walks .linuxWebkit = [.hero] := by decide

/-- macOS WebKit walks both paths, so it gives the morph cell Linux WebKit cannot. -/
theorem walks_mac_webkit : walks .macWebkit = [.hero, .morph] := by decide

/-- The width legs of an engine's job, run in parallel: one width per Linux leg; the macOS job has two legs because its
slots are shared. -/
def legTable : Engine → List (List Nat)
  | .macWebkit => [[390, 641], [640, 1280]]
  | _ => [[390], [640], [641], [1280]]

/-- The legs of a run over the picked widths: each table leg cut to the picked widths, empty legs dropped. -/
def legs (e : Engine) (ws : List Nat) : List (List Nat) :=
  ((legTable e).map (·.filter ws.contains)).filter fun l => !l.isEmpty

/-- The legs of every engine deal the allowed widths out: each width in one leg. -/
theorem legTable_perm (e : Engine) : (legTable e).flatten.Perm allowedWidths := by
  cases e <;> decide

/-- All widths picked: the legs are the table. -/
theorem legs_default (e : Engine) : legs e allowedWidths = legTable e := by
  cases e <;> decide

/-- No leg is empty (an empty leg would be a job with nothing to walk). -/
theorem legs_ne_nil (e : Engine) (ws : List Nat) : ∀ l ∈ legs e ws, l ≠ [] := by
  intro l hl
  simp only [legs, List.mem_filter, Bool.not_eq_true'] at hl
  intro h; subst h; simp at hl

/-- The legs, flattened, are the picked widths of the table. -/
theorem legs_flatten (e : Engine) (ws : List Nat) :
    (legs e ws).flatten = (legTable e).flatten.filter ws.contains := by
  rw [List.filter_flatten]
  unfold legs
  rw [List.flatten_filter_not_isEmpty]

/-- A width is in some leg exactly when it was picked and is allowed. -/
theorem legs_mem (e : Engine) (ws : List Nat) (w : Nat) :
    w ∈ (legs e ws).flatten ↔ w ∈ ws ∧ w ∈ allowedWidths := by
  rw [legs_flatten, List.mem_filter, (legTable_perm e).mem_iff]
  simp [and_comm]

/-- No width is in two legs: no cell is walked twice. -/
theorem legs_nodup (e : Engine) (ws : List Nat) : (legs e ws).flatten.Nodup := by
  rw [legs_flatten]
  exact ((legTable_perm e).nodup_iff.2 (by decide)).filter _

/-- The engines a dispatch runs for its `engines` input: macOS WebKit runs with every WebKit; other inputs are refused. -/
def enginesOf : String → Option (List Engine)
  | "both" => some [.chromium, .linuxWebkit, .macWebkit]
  | "chromium" => some [.chromium]
  | "playwright-webkit" => some [.linuxWebkit, .macWebkit]
  | _ => none

/-- Linux WebKit and macOS WebKit run together: the Apple witness runs for any search, not only a `hero.exit` one. -/
theorem enginesOf_webkit_pair (s : String) (es : List Engine) (h : enginesOf s = some es) :
    Engine.linuxWebkit ∈ es ↔ Engine.macWebkit ∈ es := by
  unfold enginesOf at h
  split at h <;> simp at h <;> subst h <;> simp

/-- One leg of a dispatch: the engine, the widths it walks and the paths. -/
structure Leg where
  engine : Engine
  widths : List Nat
  walks : List Walk
  deriving DecidableEq, Repr

/-- The legs of a dispatch from its `engines` and `widths` inputs; none when either is refused. -/
def plan (enginesIn widthsIn : String) : Option (List Leg) :=
  match enginesOf enginesIn, pickWidths widthsIn with
  | some es, .list ws => some (es.flatMap fun e => (legs e ws).map fun l => ⟨e, l, walks e⟩)
  | _, _ => none

/-- Every leg walks the paths its engine decides, no more and no fewer. -/
theorem plan_walks (a b : String) (ls : List Leg) (h : plan a b = some ls) : ∀ l ∈ ls, l.walks = walks l.engine := by
  unfold plan at h
  split at h
  · simp only [Option.some.injEq] at h
    subst h
    intro l hl
    simp only [List.mem_flatMap, List.mem_map] at hl
    obtain ⟨e, _, x, _, rfl⟩ := hl
    rfl
  · simp at h

/-- A macOS leg walks the morph path, whatever the search. -/
theorem plan_mac_morph (a b : String) (ls : List Leg) (h : plan a b = some ls) :
    ∀ l ∈ ls, l.engine = .macWebkit → Walk.morph ∈ l.walks := by
  intro l hl he
  rw [plan_walks a b ls h l hl, he]
  decide

/-- A WebKit dispatch over all widths has macOS legs: the widths of 390 and 641, and of 640 and 1280. -/
theorem plan_webkit_apple : ((plan "playwright-webkit" "").getD []).filter (·.engine == .macWebkit) =
    [⟨.macWebkit, [390, 641], [.hero, .morph]⟩, ⟨.macWebkit, [640, 1280], [.hero, .morph]⟩] := by decide

/-- A Chromium dispatch has no macOS leg. -/
theorem plan_chromium_no_apple : ((plan "chromium" "").getD []).filter (·.engine == .macWebkit) = [] := by decide

/-- A node property with `new` units in a run: the widths of its content and of its coverage `new` units. -/
structure Group where
  node : String
  prop : String
  content : List Nat
  coverage : List Nat
  deriving DecidableEq, Repr

/-- The stored result of one engine of one run on one path, with the flag set of the run's search. -/
structure Stored where
  run : String
  sha : String
  search : String
  flags : List String
  engine : Engine
  walk : Walk
  widths : List Nat
  groups : List Group
  deriving DecidableEq, Repr

/-- Why a stored cell has no verdict. -/
inductive Unjudged where
  | coverage
  | widths
  deriving DecidableEq, Repr

/-- The verdict of a stored cell. -/
inductive Outcome where
  | pass
  | fail
  | unjudged (why : Unjudged)
  deriving DecidableEq, Repr

/-- A group repeats when its `new` units fall at two or more widths. -/
def repeats (ws : List Nat) : Bool := decide (2 ≤ ws.eraseDups.length)

/-- **The verdict of a stored run**: none if undecidable or short of a width, fail on a content repeat, none on a coverage one. -/
def outcome (s : Stored) : Outcome :=
  if !covers s.engine s.walk then .unjudged .coverage
  else if !allowedWidths.all s.widths.contains then .unjudged .widths
  else if s.groups.any (repeats ·.content) then .fail
  else if s.groups.any (repeats ·.coverage) then .unjudged .coverage
  else .pass

/-- An engine that cannot decide the path gives no verdict. -/
theorem outcome_uncovered (s : Stored) (h : covers s.engine s.walk = false) : outcome s = .unjudged .coverage := by
  simp [outcome, h]

/-- A run that missed a lane width gives no verdict. -/
theorem outcome_widths (s : Stored) (hc : covers s.engine s.walk = true) (w : Nat) (hw : w ∈ allowedWidths)
    (hm : w ∉ s.widths) : outcome s = .unjudged .widths := by
  have : allowedWidths.all s.widths.contains = false := by
    rw [List.all_eq_false]
    exact ⟨w, hw, by simpa using hm⟩
  simp [outcome, hc, this]

/-- The verdict of a stored cell as four tests in order: covered, all widths, a content repeat, a coverage repeat. -/
theorem outcome_cases (s : Stored) :
    outcome s = (if covers s.engine s.walk = false then .unjudged .coverage
      else if allowedWidths.all s.widths.contains = false then .unjudged .widths
      else if s.groups.any (repeats ·.content) = true then .fail
      else if s.groups.any (repeats ·.coverage) = true then .unjudged .coverage else .pass) := by
  unfold outcome
  generalize covers s.engine s.walk = a
  generalize allowedWidths.all s.widths.contains = b
  generalize s.groups.any (repeats ·.content) = c
  generalize s.groups.any (repeats ·.coverage) = d
  cases a <;> cases b <;> cases c <;> cases d <;> simp

/-- A covered run of all lane widths fails exactly when some group repeats on content. -/
theorem outcome_fail_iff (s : Stored) :
    outcome s = .fail ↔ covers s.engine s.walk = true ∧ allowedWidths.all s.widths.contains = true ∧
      ∃ g ∈ s.groups, repeats g.content = true := by
  have e : (∃ g ∈ s.groups, repeats g.content = true) ↔ s.groups.any (repeats ·.content) = true := by simp
  rw [e, outcome_cases]
  generalize covers s.engine s.walk = a
  generalize allowedWidths.all s.widths.contains = b
  generalize s.groups.any (repeats ·.content) = c
  generalize s.groups.any (repeats ·.coverage) = d
  cases a <;> cases b <;> cases c <;> cases d <;> simp

/-- Coverage `new` units repeated across widths, with no content repeat, give no verdict, never a pass. -/
theorem outcome_coverage_repeat (s : Stored) (hc : covers s.engine s.walk = true)
    (hw : allowedWidths.all s.widths.contains = true) (hn : ∀ g ∈ s.groups, repeats g.content = false)
    (g : Group) (hg : g ∈ s.groups) (hr : repeats g.coverage = true) :
    outcome s = .unjudged .coverage := by
  have h1 : s.groups.any (repeats ·.content) = false := by
    rw [List.any_eq_false]; intro x hx; simp [hn x hx]
  have h2 : s.groups.any (repeats ·.coverage) = true := List.any_eq_true.2 ⟨g, hg, hr⟩
  rw [outcome_cases]
  simp [hc, hw, h1, h2]

/-- **A pass, characterised**: a decidable path, every lane width walked, and no group repeating on either side. -/
theorem outcome_pass_iff (s : Stored) :
    outcome s = .pass ↔ covers s.engine s.walk = true ∧ (∀ w ∈ allowedWidths, w ∈ s.widths) ∧
      ∀ g ∈ s.groups, repeats g.content = false ∧ repeats g.coverage = false := by
  have hw : (∀ w ∈ allowedWidths, w ∈ s.widths) ↔ allowedWidths.all s.widths.contains = true := by simp
  have hg : (∀ g ∈ s.groups, repeats g.content = false ∧ repeats g.coverage = false) ↔
      s.groups.any (repeats ·.content) = false ∧ s.groups.any (repeats ·.coverage) = false := by
    simp only [List.any_eq_false, Bool.not_eq_true]
    exact ⟨fun h => ⟨fun x hx => (h x hx).1, fun x hx => (h x hx).2⟩, fun h x hx => ⟨h.1 x hx, h.2 x hx⟩⟩
  rw [hw, hg, outcome_cases]
  generalize covers s.engine s.walk = a
  generalize allowedWidths.all s.widths.contains = b
  generalize s.groups.any (repeats ·.content) = c
  generalize s.groups.any (repeats ·.coverage) = d
  cases a <;> cases b <;> cases c <;> cases d <;> simp

/-- A pass comes only from an engine that decides the path. -/
theorem outcome_pass_covers (s : Stored) (h : outcome s = .pass) : covers s.engine s.walk = true :=
  ((outcome_pass_iff s).1 h).1

/-- A unit of `units-<engine>.json` as the recorder reads it; `coverage` is verdict `fail:coverage`, `isNew` is rel `new`. -/
structure UnitRow where
  width : Nat
  walk : String
  node : String
  prop : String
  coverage : Bool
  isNew : Bool
  deriving DecidableEq, Repr

/-- Append a width unless it is present. -/
def addWidth (w : Nat) (ws : List Nat) : List Nat := if ws.contains w then ws else ws ++ [w]

/-- The widths list a unit lands in: coverage or content. -/
def Group.side (g : Group) (cov : Bool) : List Nat := if cov then g.coverage else g.content

/-- The group is the unit's node property. -/
def Group.same (g : Group) (u : UnitRow) : Bool := g.node == u.node && g.prop == u.prop

/-- The group with the unit's width added to the unit's side. -/
def Group.put (g : Group) (u : UnitRow) : Group :=
  if u.coverage then { g with coverage := addWidth u.width g.coverage } else { g with content := addWidth u.width g.content }

/-- Add one `new` unit to its group, opening the group at the end when it is the first unit of its node property. -/
def addUnit (gs : List Group) (u : UnitRow) : List Group :=
  if gs.any (·.same u) then gs.map fun g => if g.same u then g.put u else g
  else gs ++ [Group.put ⟨u.node, u.prop, [], []⟩ u]

/-- The groups of a path: the `new` units on it, grouped by node property in first-seen order. -/
def groupsOf (walk : String) (us : List UnitRow) : List Group :=
  (us.filter fun u => u.isNew && u.walk == walk).foldl addUnit []

/-- The widths a path was walked at, in first-seen order. -/
def widthsOf (walk : String) (us : List UnitRow) : List Nat :=
  (us.filter (·.walk == walk)).foldl (fun ws u => addWidth u.width ws) []

/-- A width is in `addWidth w ws` exactly when it is `w` or in `ws`. -/
theorem mem_addWidth (x w : Nat) (ws : List Nat) : x ∈ addWidth w ws ↔ x = w ∨ x ∈ ws := by
  unfold addWidth
  by_cases h : ws.contains w = true
  · simp only [h, ite_true]
    constructor
    · exact Or.inr
    · rintro (rfl | hx)
      · simpa using h
      · exact hx
  · simp only [Bool.not_eq_true] at h
    simp only [h, Bool.false_eq_true, ite_false, List.mem_append, List.mem_singleton]
    exact Or.comm

/-- Putting a unit keeps the node and property. -/
theorem put_key (g : Group) (u : UnitRow) : (g.put u).node = g.node ∧ (g.put u).prop = g.prop := by
  unfold Group.put; split <;> exact ⟨rfl, rfl⟩

/-- Putting a unit keeps every width of either side. -/
theorem side_put (g : Group) (u : UnitRow) (cov : Bool) (x : Nat) (h : x ∈ g.side cov) : x ∈ (g.put u).side cov := by
  unfold Group.put Group.side at *
  cases hu : u.coverage <;> cases cov <;> simp_all [mem_addWidth]

/-- Putting a unit adds its width to its side. -/
theorem side_put_self (g : Group) (u : UnitRow) : u.width ∈ (g.put u).side u.coverage := by
  unfold Group.put Group.side
  cases hu : u.coverage <;> simp [mem_addWidth]

/-- The unit `v` is held by some group of `gs`: one of its node property whose side of `v` has `v`'s width. -/
def Holds (gs : List Group) (v : UnitRow) : Prop :=
  ∃ g ∈ gs, g.node = v.node ∧ g.prop = v.prop ∧ v.width ∈ g.side v.coverage

/-- Adding a unit keeps every unit already held. -/
theorem holds_addUnit_old (gs : List Group) (u v : UnitRow) (h : Holds gs v) : Holds (addUnit gs u) v := by
  obtain ⟨g, hg, hn, hp, hw⟩ := h
  unfold addUnit
  by_cases ha : gs.any (·.same u) = true
  · simp only [ha, ↓reduceIte]
    by_cases hs : g.same u = true
    · refine ⟨g.put u, List.mem_map.2 ⟨g, hg, by simp [hs]⟩, ?_⟩
      exact ⟨(put_key g u).1.trans hn, (put_key g u).2.trans hp, side_put g u _ _ hw⟩
    · exact ⟨g, List.mem_map.2 ⟨g, hg, by simp [hs]⟩, hn, hp, hw⟩
  · simp only [ha]
    exact ⟨g, List.mem_append_left _ hg, hn, hp, hw⟩

/-- Adding a unit holds it. -/
theorem holds_addUnit_new (gs : List Group) (u : UnitRow) : Holds (addUnit gs u) u := by
  unfold addUnit
  by_cases ha : gs.any (·.same u) = true
  · simp only [ha, ↓reduceIte]
    obtain ⟨g, hg, hs⟩ := List.any_eq_true.1 ha
    have hk : g.node = u.node ∧ g.prop = u.prop := by simpa [Group.same] using hs
    refine ⟨g.put u, List.mem_map.2 ⟨g, hg, by simp [hs]⟩, ?_⟩
    exact ⟨(put_key g u).1.trans hk.1, (put_key g u).2.trans hk.2, side_put_self g u⟩
  · simp only [ha]
    refine ⟨_, List.mem_append_right _ (List.mem_singleton.2 rfl), ?_⟩
    exact ⟨(put_key _ u).1, (put_key _ u).2, side_put_self _ u⟩

/-- Folding units in holds every unit held before and every unit folded. -/
theorem holds_foldl (us : List UnitRow) (gs : List Group) (v : UnitRow) (h : Holds gs v ∨ v ∈ us) :
    Holds (us.foldl addUnit gs) v := by
  induction us generalizing gs with
  | nil =>
    rcases h with h | h
    · exact h
    · cases h
  | cons u t ih =>
    apply ih
    rcases h with h | h
    · exact Or.inl (holds_addUnit_old gs u v h)
    · rcases List.mem_cons.1 h with rfl | h
      · exact Or.inl (holds_addUnit_new gs v)
      · exact Or.inr h

/-- **The recorder drops no `new` unit**: each is held by its node property's group, at its width, on its side. -/
theorem groupsOf_complete (walk : String) (us : List UnitRow) (u : UnitRow) (hu : u ∈ us) (hn : u.isNew = true)
    (hw : u.walk = walk) : Holds (groupsOf walk us) u :=
  holds_foldl _ [] u (Or.inr (List.mem_filter.2 ⟨hu, by simp [hn, hw]⟩))

private def urow (w : Nat) (node : String) (cov isNew : Bool) : UnitRow := ⟨w, "morph", node, "p", cov, isNew⟩
private def stored (gs : List Group) : Stored := ⟨"1", "s", "?fw=a:b", ["a:b"], .chromium, .morph, allowedWidths, gs⟩

#guard repeats [390, 390, 390] == false
#guard repeats [390, 1280]
#guard groupsOf "morph" [urow 390 "nav" false true, urow 641 "nav" true true, urow 641 "nav" false true,
  urow 1280 "logo" false false, ⟨390, "hero", "nav", "p", false, true⟩] == [⟨"nav", "p", [390, 641], [641]⟩]
#guard widthsOf "morph" [urow 390 "nav" false true, urow 390 "nav" false false, urow 1280 "logo" false false] == [390, 1280]
#guard outcome (stored []) == .pass
#guard outcome (stored [⟨"nav", "p", [1280], [390]⟩]) == .pass
#guard outcome (stored [⟨"nav", "p", [390, 640, 641, 1280], []⟩]) == .fail
#guard outcome (stored [⟨"nav", "p", [], [390, 641]⟩]) == .unjudged .coverage
#guard outcome (stored [⟨"nav", "p", [390, 641], [390, 641]⟩]) == .fail
#guard outcome { stored [] with widths := [390, 640, 641] } == .unjudged .widths
#guard outcome { stored [] with engine := .linuxWebkit } == .unjudged .coverage
#guard outcome { stored [] with engine := .linuxWebkit, walk := .hero } == .pass
#guard outcome { stored [] with engine := .macWebkit } == .pass

-- Golden ------------------------------------------------------------------------------------------------------------

/-- The name of a kind in the golden file. -/
def Kind.name : Kind → String
  | .discrete => "discrete" | .geometry => "geometry" | .unit => "unit" | .colour => "colour"

/-- A verdict as `pass`, `fail:<why>` or `skip:<why>`. -/
def Verdict.name : Verdict → String
  | .pass => "pass"
  | .fail .count => "fail:count" | .fail .missing => "fail:missing" | .fail .type => "fail:type"
  | .fail .shape => "fail:shape" | .fail .differs => "fail:differs" | .fail .apart => "fail:apart"
  | .fail .coverage => "fail:coverage"
  | .skip .transient => "skip:transient" | .skip .noSample => "skip:noSample"

/-- The name of a phase in the golden file. -/
def Phase.name : Phase → String
  | .push => "push" | .hold => "hold"

/-- The name of a relative verdict in the golden file. -/
def Rel.name : Rel → String
  | .ok => "ok" | .both => "both" | .cleared => "cleared" | .new => "new"
  | .unmeasured => "unmeasured"

/-- The name of an arm verdict in the golden file. -/
def ArmVerdict.name : ArmVerdict → String
  | .ok => "ok" | .refusedConfig => "refused:config"

/-- An arm's reading as JSON. -/
def ArmRead.json (a : ArmRead) : Json :=
  let o : Option String → Json := fun x => match x with | none => Json.null | some v => Json.str v
  Json.mkObj [("site", match a.site with | .orig => "orig" | .rewrite => "rewrite"), ("want", o a.want),
    ("config", o a.config), ("mode", o a.mode)]

/-- A reading as JSON: null, an array of integers or a string. -/
def Val.json : Val → Json
  | .absent => Json.null
  | .num xs => Json.arr (xs.map fun x => toJson x).toArray
  | .str s => Json.str s

/-- A sample as JSON. -/
def Samp.json (s : Samp) : Json :=
  Json.mkObj [("m", match s.m with | none => Json.null | some m => toJson m),
    ("since", match s.since with | none => Json.null | some t => toJson t), ("els", Json.arr (s.els.map Val.json).toArray), ("rep", toJson s.rep)]

/-- One golden line. -/
inductive Case where
  | judge (name : String) (k : Kind) (win : List Samp) (r : Samp)
  | bracket (name : String) (ms : List Int) (m : Int)
  | tenth (name : String) (m : Option Int)
  | phase (name : String) (ph : Phase) (k : Kind) (d : Option Nat) (seg orig rew : List Samp)
  | flight (name : String) (k : Kind) (d : Option Nat) (seg win : List Samp) (r : Samp)
  | settle (name : String) (node prop : String)
  | versus (name : String) (cand base : Verdict)
  | quant (name : String) (xs : List Nat) (p : Nat)
  | dominate (name : String) (readP50 gapP50 : Nat)
  | armOf (name : String) (a : ArmRead)
  | runOf (name : String) (arms : List ArmRead)
  | path (name : String) (k : Kind) (d : Option Nat) (orig rew : List (String × Samp))
  | picks (name : String) (input : String)
  | planOf (name : String) (engines widths : String)

/-- The golden cases of the window judgement (`judgeIn` per kind and per branch). Two constants, not one, so that each stays
under the start-cost bound (`Fw.Lint.InitCost.bound`). -/
def casesJudge : List Case := [
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
  ]

/-- The golden cases of the rest: windows, buckets, coverage, the baseline relation, arm identity and read timing. -/
def casesRest : List Case := [
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
  .phase "threshold slack" .push .discrete none [] [sm 9000 [.str "off"], sm 9300 [.str "on"]] [sm 9200 [.str "on"]],
  .phase "stale class" .push .discrete none []
    [sm 8000 [.str "off"], sm 8500 [.str "off"], sm 9000 [.str "off"], sm 9300 [.str "on"], sm 9400 [.str "on"],
      sm 9500 [.str "on"], sm 9600 [.str "on"], sm 9700 [.str "on"], sm 9900 [.str "on"]] [sm 9500 [.str "off"]],
  .phase "ramp ok" .push .geometry none [] [sm 0 [.num [0]], sm 5000 [.num [5000]], sm 10000 [.num [10000]]]
    [sm 2000 [.num [2000]], sm 7000 [.num [7000]]],
  .phase "ramp stuck" .push .geometry none [] [sm 0 [.num [0]], sm 5000 [.num [5000]], sm 10000 [.num [10000]]]
    [sm 2000 [.num [0]], sm 7000 [.num [0]]],
  .phase "ramp every bucket" .push .geometry none [] [sm 0 [.num [0]], sm 5000 [.num [5000]], sm 10000 [.num [10000]]]
    [sm 0 [.num [0]], sm 1000 [.num [1000]], sm 2000 [.num [2000]], sm 3000 [.num [3000]], sm 4000 [.num [4000]],
      sm 5000 [.num [5000]], sm 6000 [.num [6000]], sm 7000 [.num [7000]], sm 8000 [.num [8000]], sm 9000 [.num [9000]],
      sm 10000 [.num [10000]]],
  .phase "push first bucket only" .push .geometry none [] [sm 0 [.num [0]], sm 10000 [.num [10000]]] [sm 1000 [.num [1000]]],
  .phase "push no rewrite sample" .push .discrete none [] [sm 0 [.str "off"], sm 10000 [.str "on"]] [],
  .phase "hold colour" .hold .colour none [] [⟨some 10000, some 0, [.num [43000]], 0⟩, ⟨some 10000, none, [.num [255000]], 0⟩]
    [⟨some 10000, some 0, [.num [43000]], 0⟩, ⟨some 10000, none, [.num [43000]], 0⟩],
  .phase "hold interior empty" .hold .discrete none [] [sm 10000 [.str "on"]] [sm 10000 [.str "on"]],
  .phase "hold no rewrite sample" .hold .discrete none [] [sm 10000 [.str "on"]] [],
  .phase "push no morph value" .push .discrete none [] [s0 [.str "on"]] [s0 [.str "on"]],
  .phase "push rewrite no morph value" .push .discrete none [] [sm 0 [.str "on"], sm 10000 [.str "on"]] [s0 [.str "on"]],
  .phase "hold no morph value" .hold .discrete none [] [s0 [.str "on"]] [s0 [.str "on"]],
  .phase "beyond reach" .push .geometry none [] [sm 0 [.num [0]], sm 1500 [.num [3000]]] [sm 9800 [.num [10000]]],
  .phase "hold beyond reach" .hold .geometry none [] [sm 0 [.num [0]], sm 1500 [.num [3000]]] [sm 9800 [.num [10000]]],
  .phase "within reach" .push .geometry none [] [sm 0 [.num [0]], sm 9000 [.num [9000]]] [sm 9800 [.num [9800]]],
  .phase "pooled ramp original, static rewrite" .push .discrete none [] (ramp 0 ++ ramp 1 ++ ramp 2) [smr 0 5000 [.num [0]]],
  .phase "pooled ramp original, ramping rewrite" .push .discrete none [] (ramp 0 ++ ramp 1 ++ ramp 2)
    [smr 0 2000 [.num [2000]], smr 0 4000 [.num [4000]], smr 1 6000 [.num [6000]], smr 2 8000 [.num [8000]]],
  .phase "pooled ramp original, stuck class" .push .discrete none [] (ramp 0 ++ ramp 1)
    [smr 0 9000 [.num [0]], smr 1 9000 [.num [0]]],
  .phase "pooled slow pass" .push .discrete none [] ([0, 2000, 4000].map (fun m => smr 0 m [.num [m]]) ++ ramp 1)
    [smr 1 9800 [.num [10000]]],
  .phase "pooled all passes beyond" .push .discrete none [] ([0, 1500].map (fun m => smr 0 m [.num [m]]) ++ [0, 1500].map (fun m => smr 1 m [.num [m]]))
    [smr 0 9800 [.num [10000]]],
  .phase "pooled pass without morph value" .push .discrete none [] ([⟨none, none, [.num [0]], 0⟩] ++ ramp 1) [smr 1 4000 [.num [4000]]],
  .path "missing step" .unit none [("s25", s0 [.num [750]])] [],
  .path "pair" .unit none [("s25", s0 [.num [750]]), ("s50", s0 [.num [500]])]
    [("s25", s0 [.num [1000]]), ("s50", s0 [.num [500]])],
  .picks "default" "", .picks "subset" "1280,390", .picks "unknown" "390,500", .picks "repeat" "390,390",
  .picks "junk" "390,wide", .picks "gap" "390,,640", .picks "all" "390,640,641,1280", .picks "space" "390, 640",
  .quant "median" [50, 10, 40, 20, 30] 50, .quant "p90" [10, 20, 30, 40, 50, 60, 70, 80, 90, 100] 90, .quant "empty" [] 50,
  .quant "one" [7] 90, .quant "p100" [3, 1, 2] 100, .quant "unsorted" [3, 1, 2] 90,
  .dominate "yes" 90 150, .dominate "edge" 50 100, .dominate "no" 5 18, .dominate "no gap" 5 0,
  .versus "new" (.fail .apart) .pass, .versus "new skip" (.fail .differs) (.skip .noSample), .versus "both" (.fail .apart) (.fail .apart),
  .versus "both content" (.fail .apart) (.fail .differs), .versus "both coverage" (.fail .coverage) (.fail .coverage),
  .versus "both cand coverage" (.fail .coverage) (.fail .apart), .versus "unmeasured" (.fail .apart) (.fail .coverage),
  .versus "cleared" .pass (.fail .apart), .versus "skip cleared" (.skip .transient) (.fail .differs), .versus "ok" .pass .pass,
  .versus "ok skip" (.skip .noSample) .pass, .versus "coverage new" (.fail .coverage) .pass,
  .armOf "rewrite ok" ⟨.rewrite, some "ab12", some "ab12", some "hydrate"⟩,
  .armOf "flags off" ⟨.rewrite, some "ab12", some "cd34", some "client-render"⟩,
  .armOf "client render" ⟨.rewrite, some "ab12", some "ab12", some "client-render"⟩,
  .armOf "hash differs" ⟨.rewrite, some "ab12", some "cd34", some "hydrate"⟩,
  .armOf "no config" ⟨.rewrite, some "ab12", none, some "hydrate"⟩,
  .armOf "no mode" ⟨.rewrite, some "ab12", some "ab12", none⟩,
  .armOf "no want" ⟨.rewrite, none, some "ab12", some "hydrate"⟩,
  .armOf "empty want" ⟨.rewrite, some "", some "", some "hydrate"⟩,
  .armOf "orig ok" ⟨.orig, none, none, none⟩,
  .armOf "orig foreign" ⟨.orig, none, some "ab12", some "hydrate"⟩,
  .runOf "run ok" [⟨.orig, none, none, none⟩, ⟨.rewrite, some "ab12", some "ab12", some "hydrate"⟩],
  .runOf "run one bad" [⟨.orig, none, none, none⟩, ⟨.rewrite, some "ab12", some "cd34", some "client-render"⟩],
  .runOf "run empty" []]

/-- The golden cases of the dispatch plan (engines, legs, paths): every engines input, a subset and refusals. -/
def casesPlan : List Case := [
  .planOf "both, all widths" "both" "", .planOf "webkit, all widths" "playwright-webkit" "",
  .planOf "chromium, all widths" "chromium" "", .planOf "webkit, one width" "playwright-webkit" "640",
  .planOf "both, a subset" "both" "1280,390", .planOf "unknown engines" "safari" "", .planOf "refused widths" "both" "390,500"]

/-- A sample of pass `rep` at morph value `m`, read `t` ms after the last class change. -/
def smt (rep : Nat) (m : Int) (t : Nat) (els : List Val) : Samp := ⟨some m, some t, els, rep⟩

/-- A sample with no morph value, read `t` ms after the last class change. -/
def st (t : Nat) (els : List Val) : Samp := ⟨none, some t, els, 0⟩

/-- The golden cases of transitions in flight: the settle table, each branch of `judgeFlight`, the start-lag boundary, and
the morph and step paths with a settle time. -/
def casesFlight : List Case := [
  .settle "nav visibility" "nav" "visibility", .settle "nav rect" "nav" "rect",
  .settle "nav background" "nav" "background-color", .settle "nav opacity" "nav" "opacity",
  .settle "nav lin" "nav" "transform.lin", .settle "nav shift" "nav" "transform.shift", .settle "logo colour" "logo" "color",
  .settle "actions gap" "actions" "gap", .settle "earn opacity" "earn" "opacity", .settle "earn max-width" "earn" "max-width",
  .settle "unlisted" "nav" "filter", .settle "unlisted node" "pill" "opacity",
  .flight "rewrite in flight, inside crossed" .colour (some 700) [st 5000 [.num [0]], st 100 [.num [5000]], st 5000 [.num [9000]]]
    [st 5000 [.num [9000]]] (st 100 [.num [4000]]),
  .flight "rewrite in flight, outside" .colour (some 700) [st 5000 [.num [0]], st 100 [.num [5000]], st 5000 [.num [9000]]]
    [st 5000 [.num [9000]]] (st 100 [.num [12000]]),
  .flight "window in flight" .unit (some 440) [st 5000 [.num [0]], st 200 [.num [500]], st 5000 [.num [1000]]]
    [st 200 [.num [500]]] (st 5000 [.num [1000]]),
  .flight "settled differs" .colour (some 700) [st 100 [.num [5000]]] [st 5000 [.num [9000]]] (st 5000 [.num [0]]),
  .flight "settled same" .colour (some 700) [] [st 5000 [.num [9000]]] (st 5000 [.num [9000]]),
  .flight "lag edge in flight" .unit (some 700) [st 5000 [.num [0]], st 100 [.num [500]], st 5000 [.num [1000]]]
    [st 5000 [.num [1000]]] (st 899 [.num [0]]),
  .flight "lag edge settled" .unit (some 700) [st 5000 [.num [0]], st 100 [.num [500]], st 5000 [.num [1000]]]
    [st 5000 [.num [1000]]] (st 900 [.num [0]]),
  .flight "no settle colour" .colour none [st 100 [.num [0]]] [st 5000 [.num [9000]]] (st 100 [.num [0]]),
  .flight "no settle unit" .unit none [st 100 [.num [0]]] [st 5000 [.num [1000]]] (st 100 [.num [0]]),
  .flight "no class change" .unit (some 700) [] [s0 [.num [1000]]] (s0 [.num [0]]),
  .flight "crossed per pass" .unit (some 440)
    [⟨none, some 5000, [.num [0]], 0⟩, ⟨none, some 5000, [.num [200]], 0⟩, ⟨none, some 100, [.num [600]], 1⟩,
      ⟨none, some 5000, [.num [1000]], 1⟩]
    [st 100 [.num [1000]]] (st 100 [.num [200]]),
  .flight "discrete in flight" .discrete (some 320) [st 5000 [.str "hidden"], st 100 [.str "visible"]]
    [st 100 [.str "visible"]] (st 100 [.str "hidden"]),
  .phase "morph in flight" .push .colour (some 700)
    [smt 0 0 5000 [.num [0]], smt 0 5000 100 [.num [5000]], smt 0 10000 5000 [.num [9000]]]
    [smt 0 0 5000 [.num [0]], smt 0 5000 100 [.num [5000]], smt 0 10000 5000 [.num [9000]]]
    [smt 0 4000 150 [.num [2000]], smt 0 6000 150 [.num [7000]]],
  .phase "morph settled differs" .push .colour (some 700)
    [smt 0 0 5000 [.num [0]], smt 0 5000 100 [.num [5000]], smt 0 10000 5000 [.num [9000]]]
    [smt 0 0 5000 [.num [0]], smt 0 10000 5000 [.num [9000]]] [smt 0 9500 5000 [.num [0]]],
  .path "steps in flight" .colour (some 700)
    [("a5", st 2222 [.num [255000, 255000, 255000, 122400]]), ("a6", st 481 [.num [1000, 0, 0, 33340]]),
      ("a7", st 1134 [.num [255000, 255000, 255000, 26000]])]
    [("a5", st 1271 [.num [255000, 255000, 255000, 122400]]), ("a6", st 327 [.num [1000, 0, 0, 51667]]),
      ("a7", st 703 [.num [1000, 0, 0, 26029]])],
  .path "step settled differs" .colour (some 700) [("a1", st 5000 [.num [255000]]), ("a2", st 5000 [.num [9000]])]
    [("a1", st 5000 [.num [255000]]), ("a2", st 5000 [.num [0]])]]

/-- The golden cases: every branch above, per kind where the kind matters. -/
def cases : List Case := casesJudge ++ casesRest ++ casesPlan ++ casesFlight

/-- A widths pick as JSON. -/
def Widths.json : Widths → Json
  | .list ws => Json.mkObj [("ok", Json.bool true), ("widths", Json.arr (ws.map fun w => toJson w).toArray)]
  | .refused => Json.mkObj [("ok", Json.bool false)]

/-- The word of an engine in the plan golden. -/
def Engine.word : Engine → String
  | .chromium => "chromium"
  | .linuxWebkit => "linux-webkit"
  | .macWebkit => "mac-webkit"

/-- The word of a path in the plan golden. -/
def Walk.word : Walk → String
  | .hero => "hero"
  | .morph => "morph"

/-- A leg as JSON. -/
def Leg.json (l : Leg) : Json :=
  Json.mkObj [("engine", l.engine.word), ("widths", Json.arr (l.widths.map fun w => toJson w).toArray),
    ("walks", Json.arr (l.walks.map fun w => Json.str w.word).toArray)]

/-- An optional count as JSON: null or the number. -/
def optNat : Option Nat → Json
  | none => Json.null
  | some x => toJson x

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
  | .phase n ph k d seg o r =>
    Json.mkObj [("op", "byM"), ("name", n), ("phase", ph.name), ("kind", k.name), ("settle", optNat d),
      ("seg", Json.arr (seg.map Samp.json).toArray), ("orig", Json.arr (o.map Samp.json).toArray),
      ("rew", Json.arr (r.map Samp.json).toArray),
      ("verdicts", Json.arr ((byM ph k d seg o r).map fun (_, v) => Json.str v.name).toArray)]
  | .flight n k d seg win r =>
    Json.mkObj [("op", "flight"), ("name", n), ("kind", k.name), ("settle", optNat d),
      ("seg", Json.arr (seg.map Samp.json).toArray), ("win", Json.arr (win.map Samp.json).toArray), ("r", r.json),
      ("verdict", (judgeFlight k d seg win r).name)]
  | .settle n node prop =>
    Json.mkObj [("op", "settle"), ("name", n), ("node", node), ("prop", prop), ("settle", optNat (settleOf node prop)),
      ("lag", toJson startLag)]
  | .path n k d o r =>
    let side := fun (xs : List (String × Samp)) =>
      Json.arr (xs.map fun (s, x) => Json.mkObj [("step", s), ("s", x.json)]).toArray
    Json.mkObj [("op", "byStep"), ("name", n), ("kind", k.name), ("settle", optNat d), ("orig", side o), ("rew", side r),
      ("verdicts", Json.arr ((byStep k d o r).map fun (s, v) => Json.mkObj [("step", s), ("verdict", v.name)]).toArray)]
  | .versus n c b =>
    Json.mkObj [("op", "rel"), ("name", n), ("cand", c.name), ("base", b.name), ("rel", (rel c b).name)]
  | .quant n xs p =>
    Json.mkObj [("op", "quantile"), ("name", n), ("xs", Json.arr (xs.map fun x => toJson x).toArray), ("p", toJson p),
      ("q", match quantile xs p with | none => Json.null | some q => toJson q)]
  | .dominate n r g =>
    Json.mkObj [("op", "dominate"), ("name", n), ("read", toJson r), ("gap", toJson g), ("dominates", Json.bool (readsDominate r g))]
  | .armOf n a => Json.mkObj [("op", "arm"), ("name", n), ("arm", a.json), ("verdict", (armCheck a).name)]
  | .runOf n arms =>
    Json.mkObj [("op", "run"), ("name", n), ("arms", Json.arr (arms.map ArmRead.json).toArray), ("verdict", (runCheck arms).name)]
  | .picks n i => Json.mkObj [("op", "widths"), ("name", n), ("input", i), ("pick", (pickWidths i).json)]
  | .planOf n e w =>
    Json.mkObj [("op", "plan"), ("name", n), ("engines", e), ("widths", w),
      ("legs", match plan e w with | none => Json.null | some ls => Json.arr (ls.map Leg.json).toArray)]

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
