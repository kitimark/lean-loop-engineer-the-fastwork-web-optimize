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

/-- Why a unit is not compared: no sample of the rewrite fell on a unit that needs none (a hold, a bucket outside 1 to 9,
a hero step the rewrite did not record). -/
inductive Skip where
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
    if vs.any (· == .pass) then .pass else .skip .noSample

/-- All elements of a node: counts must match, then each element on its own, combined. -/
def judgeEls (k : Kind) (win : List (List Val)) (r : List Val) : Verdict :=
  if win.isEmpty then .skip .noSample
  else if win.any (·.length != r.length) then .fail .count
  else combine ((List.range r.length).map fun i => judgeVal k (win.map (·.getD i .absent)) (r.getD i .absent))

/-- A sample of one (node, property) at one instant: the morph value times 10000, the ms since the last class change of
the nav (`none`: no change happened), the elements, the pass (`rep`) it was read in, the nav classes that were on
(`cls`), the index of the phase it was read in (`ph`), and the number of earlier epochs of its pass with the same classes
(`ord`, set by `annotate`).

The probe walks the morph path several times (`--reps`) and keeps every row. A morph value rises or falls within one pass
only, so two samples of different passes are not neighbours in time and no window may pair them. -/
structure Samp where
  m : Option Int
  since : Option Nat
  els : List Val
  rep : Nat
  cls : List String
  ph : Nat
  ord : Nat
  deriving DecidableEq, Repr

/-- A sample with a morph value, in pass 0, no class change. -/
def sm (m : Int) (els : List Val) : Samp := ⟨some m, none, els, 0, [], 0, 0⟩

/-- A sample with a morph value, in pass `rep`, no class change. -/
def smr (rep : Nat) (m : Int) (els : List Val) : Samp := ⟨some m, none, els, rep, [], 0, 0⟩

/-- A sample without a morph value, in pass 0, no class change. -/
def s0 (els : List Val) : Samp := ⟨none, none, els, 0, [], 0, 0⟩

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

/-- A rule of `apps/site/src/parts/nav/nav.module.css` that sets `transition` or `transition-delay`.

`line` is the line of its selector. The rule applies to `node` when every class of `on` is on the nav and none of `off`
is, the viewport is wider than `minW`, and the rule is not one for reduced motion (`reduce`); the probe runs with no
motion preference. `spec` is the specificity of the selector in classes. `set` lists the transitions of a `transition`
declaration as (CSS property, duration, delay) in ms: `none` when the rule declares no `transition`, `[]` for
`transition: none`. `delay` is a `transition-delay` that replaces every delay of the transitions in force. -/
structure Rule where
  line : Nat
  node : String
  on : List String
  off : List String
  minW : Option Nat
  reduce : Bool
  spec : Nat
  set : Option (List (String × Nat × Nat))
  delay : Option Nat
  deriving DecidableEq, Repr

/-- The rules of `apps/site/src/parts/nav/nav.module.css` that set a transition, in source order.

`trajectory.test.mjs` parses the CSS file and requires this list exactly. The rules at lines 294 and 295 are the two
selectors of one rule, each at its own line. -/
def rules : List Rule := [
  ⟨6, "nav", [], [], none, false, 1, some [("opacity", 280, 0), ("transform", 320, 0), ("visibility", 0, 320)], none⟩,
  ⟨41, "nav", [], ["is-morphing"], none, false, 2,
    some [("background", 700, 0), ("opacity", 280, 0), ("transform", 320, 0), ("visibility", 0, 320), ("width", 680, 0)],
    none⟩,
  ⟨63, "nav", ["is-scroll-hidden"], [], none, false, 2,
    some [("opacity", 280, 0), ("transform", 320, 0), ("visibility", 0, 320)], none⟩,
  ⟨73, "nav", [], ["is-scroll-hidden"], none, false, 2, none, some 0⟩,
  ⟨78, "nav", ["is-hero-pill"], ["is-hero-chrome-ready"], some 600, false, 3, some [], none⟩,
  ⟨83, "nav", ["is-hero-pill", "is-hero-chrome-ready"], [], some 600, false, 3,
    some [("background", 700, 0), ("opacity", 700, 0), ("transform", 320, 0), ("width", 680, 0)], none⟩,
  ⟨106, "logo", [], [], none, false, 1, some [("color", 240, 0)], none⟩,
  ⟨128, "actions", [], [], none, false, 1, some [("gap", 680, 0)], none⟩,
  ⟨141, "actions", ["is-morphing"], [], none, false, 3, some [], none⟩,
  ⟨167, "earn", [], [], none, false, 2,
    some [("max-width", 680, 0), ("opacity", 320, 120), ("padding-inline", 680, 0)], none⟩,
  ⟨189, "earn", ["is-hero-pill"], [], none, false, 4,
    some [("max-width", 680, 0), ("opacity", 200, 0), ("padding-inline", 680, 0)], none⟩,
  ⟨287, "nav", [], ["is-morphing"], none, true, 2,
    some [("background", 320, 0), ("opacity", 280, 0), ("transform", 320, 0), ("visibility", 0, 320)], none⟩,
  ⟨294, "nav", ["is-morphing"], [], none, true, 2, some [], none⟩,
  ⟨295, "earn", [], [], none, true, 2, some [], none⟩]

/-- The CSS properties whose transitions move a property the probe reads; `[]` when no transition moves it.

`nav.rect` is the nav's box, which `width` and `transform` move; `background-color` moves with the `background`
shorthand. -/
def cssOf (node prop : String) : List String :=
  match node, prop with
  | "nav", "visibility" => ["visibility"]
  | "nav", "rect" => ["width", "transform"]
  | "nav", "background-color" => ["background", "background-color"]
  | "nav", "opacity" => ["opacity"]
  | "nav", "transform.lin" => ["transform"]
  | "nav", "transform.shift" => ["transform"]
  | "logo", "color" => ["color"]
  | "actions", "gap" => ["gap", "column-gap"]
  | "earn", "opacity" => ["opacity"]
  | "earn", "max-width" => ["max-width"]
  | _, _ => []

/-- The nav class under which the site's script sets the morph's styles on every frame. -/
def driver : String := "is-morphing"

/-- Rule `r` applies to `node` at viewport `width` with the nav classes `cls` on. -/
def applies (r : Rule) (node : String) (width : Nat) (cls : List String) : Bool :=
  r.node == node && r.on.all cls.contains && !r.off.any cls.contains &&
    (match r.minW with | none => true | some w => decide (w < width)) && !r.reduce

/-- Rule `a` comes before rule `b` in the cascade: lower specificity, or equal specificity and an earlier line. -/
def before (a b : Rule) : Bool := a.spec < b.spec || (a.spec == b.spec && a.line < b.line)

/-- The rule of `rs` that comes last in the cascade; the first of two that tie. -/
def lastBy (rs : List Rule) : Option Rule :=
  rs.foldl (fun acc r => match acc with | none => some r | some a => if before a r then some r else some a) none

/-- The transitions in force on `node`: those of the last applying rule with a `transition`, each delay replaced by the
`transition-delay` of the last applying rule after it, if any. -/
def transitionsOf (node : String) (width : Nat) (cls : List String) : List (String × Nat × Nat) :=
  let rs := rules.filter (applies · node width cls)
  let top := lastBy (rs.filter (·.set.isSome))
  let base := (top.bind (·.set)).getD []
  let late := rs.filter fun r => r.delay.isSome && (match top with | none => true | some t => before t r)
  match (lastBy late).bind (·.delay) with
  | some l => base.map fun (p, d, _) => (p, d, l)
  | none => base

/-- **The transition of a probe property under a class set**, in ms: the longest delay plus duration of the transitions
in force on its CSS properties. `none` when the morph's script drives the nav (`driver`) or no transition runs. -/
def durOf (node prop : String) (width : Nat) (cls : List String) : Option Nat :=
  if cls.contains driver then none
  else
    let t := ((transitionsOf node width cls).filter fun (p, _, _) => (cssOf node prop).contains p).foldl
      (fun a (_, d, l) => max a (d + l)) 0
    if t = 0 then none else some t

/-- Milliseconds a transition may start after the class change that triggers it.

It starts at the next style update after the change, which a busy main thread delays; the stored runs read
mid-transition colours up to 140 ms past the declared 700 (MEASURED, `docs/team/tools/trajectory-probe.md`). -/
def startLag : Nat := 200

/-- A sample was read while a transition of its property may run: less than `d cls + startLag` ms after the last class
change of the nav, `d` giving the transition under the sample's classes. No transition, or no class change, is never in
flight. -/
def inFlight (d : List String → Option Nat) (s : Samp) : Bool :=
  match d s.cls, s.since with
  | some t, some x => decide (x < t + startLag)
  | _, _ => false

/-- A sample starts an epoch of its pass: the first sample, a change of the nav classes, or a `since` that went down (the
classes changed and changed back between two samples). -/
def restarts (p : Option Samp) (s : Samp) : Bool :=
  match p with
  | none => true
  | some p => p.cls != s.cls ||
    match s.since, p.since with
    | some a, some b => decide (a < b)
    | some _, none => true
    | none, _ => false

/-- The `ord` of each sample of one pass, in order: the number of earlier epochs of the pass with the sample's classes.
`seen` holds the classes of the epochs so far, `o` the `ord` of the current one. -/
def ordsOf : Option Samp → List (List String) → Nat → List Samp → List Nat
  | _, _, _, [] => []
  | p, seen, o, s :: rest =>
    if restarts p s then seen.count s.cls :: ordsOf (some s) (seen ++ [s.cls]) (seen.count s.cls) rest
    else o :: ordsOf (some s) seen o rest

/-- The samples with their `ord`, each computed within its pass; the order is kept.

An epoch is identified across the two arms by its pass, its classes and its `ord`: the third time pass 2 turns the
morph off is the same epoch in both arms, whatever the number of samples before it. -/
def annotate (seg : List Samp) : List Samp :=
  seg.mapIdx fun i s => { s with ord := ((ordsOf none [] 0 (passOf (seg.take (i + 1)) s.rep)).getLast?).getD 0 }

/-- Sample `o` is in the epoch of `r`: the same pass, classes and `ord`. -/
def inEpoch (r o : Samp) : Bool := o.rep == r.rep && o.cls == r.cls && o.ord == r.ord

/-- Sample `o` is read at about the time `r` is in its transition: the same epoch and phase, and `since` within
`startLag` of `r`'s. -/
def isCore (r o : Samp) : Bool :=
  inEpoch r o && o.ph == r.ph &&
    match o.since, r.since with
    | some a, some b => decide (((a : Int) - b).natAbs ≤ startLag)
    | _, _ => false

/-- **The original's samples of the transition a rewrite sample `r` is in.** `seg` is the original's whole path.

The core is every sample of `r`'s pass that `isCore` keeps. The window is the samples of the epoch from the first to one
past the last of the core, and the sample just before the core (the value the transition starts from, read in the
epoch before). Empty when the original has no sample in the core. -/
def flightWindow (seg : List Samp) (r : Samp) : List Samp :=
  let p := passOf seg r.rep
  let core := (List.range p.length).filter fun i => (p[i]?.map (isCore r)).getD false
  if core.isEmpty then []
  else (List.range p.length).filterMap fun i => p[i]?.bind fun o =>
    if (core.contains (i + 1) && core.all fun c => decide (i + 1 ≤ c)) ||
        (inEpoch r o && core.any (fun a => decide (a ≤ i)) && core.any fun b => decide (i ≤ b + 1))
    then some o else none

/-- The last sample of `w`'s epoch in `seg`. -/
def endOf (seg : List Samp) (w : Samp) : Option Samp := (seg.filter (inEpoch w)).getLast?

/-- The settled reading a window sample `w` stands for: `w` when it is not in flight, else the last sample of its epoch
when that one is not; `none` when the epoch never settled. -/
def settledRef (d : List String → Option Nat) (seg : List Samp) (w : Samp) : Option Samp :=
  if !inFlight d w then some w
  else match endOf seg w with
    | some e => if inFlight d e then none else some e
    | none => none

/-- A verdict is a failure. -/
def isFail : Verdict → Bool
  | .fail _ => true
  | _ => false

/-- The red, green and blue channels of a colour reading. -/
def Val.chan : Val → Val
  | .num xs => .num (xs.take 3)
  | v => v

/-- The alpha of a colour reading. -/
def Val.alpha : Val → Val
  | .num xs => .num (xs.drop 3)
  | v => v

/-- A pass when `r` matches one reading of `win` on its own, else the first failure. -/
def matchOne (k : Kind) (win : List (List Val)) (r : List Val) : Verdict :=
  let vs := win.map fun w => judgeEls k [w] r
  if vs.any fun v => !isFail v then .pass else combine vs

/-- An in-flight colour: its channels match one reading of the core (`core`), its alpha lies in the band of the
transition's window (`fw`).

The kit serialises a colour in flight in another colour space than a colour at rest, so channels are compared reading
by reading and never in a band that spans both. -/
def judgeColour (core fw : List Samp) (r : Samp) : Verdict :=
  combine [matchOne .colour (core.map fun s => s.els.map Val.chan) (r.els.map Val.chan),
    judgeEls .colour (fw.map fun s => s.els.map Val.alpha) (r.els.map Val.alpha)]

/-- **One rewrite sample.** `d` gives the property's transition per class set, `seg` is the original's whole path and
`win` the window of `r`'s morph value or step (`none`: no counterpart).

A sample in flight is judged against `flightWindow`, a colour by `judgeColour`; with no original sample in that
transition, against `win`. A sample at rest is judged against the settled readings `win` stands for (`settledRef`). -/
def judgeUnit (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp)) (r : Samp) :
    Verdict :=
  if inFlight d r then
    let fw := flightWindow seg r
    if fw.isEmpty then
      match win with
      | none => .fail .coverage
      | some w => judgeEls k (w.map (·.els)) r.els
    else if k == .colour then judgeColour (fw.filter (isCore r)) fw r
    else judgeEls k (fw.map (·.els)) r.els
  else
    match win with
    | none => .fail .coverage
    | some w =>
      let ref := w.filterMap (settledRef d seg)
      if ref.isEmpty then .fail .coverage else judgeEls k (ref.map (·.els)) r.els

#guard (rules.filter (applies · "nav" 1280 ["is-hero-pill"])).map (·.line) == [6, 41, 73, 78]
#guard (rules.filter (applies · "nav" 390 ["is-hero-pill"])).map (·.line) == [6, 41, 73]
#guard (rules.filter (applies · "earn" 1280 [])).map (·.line) == [167]
#guard (lastBy (rules.filter (applies · "nav" 1280 ["is-scroll-hidden"]))).map (·.line) == some 63
#guard transitionsOf "nav" 1280 [] ==
  [("background", 700, 0), ("opacity", 280, 0), ("transform", 320, 0), ("visibility", 0, 0), ("width", 680, 0)]
#guard transitionsOf "nav" 1280 ["is-hero-pill"] == []
#guard durOf "nav" "rect" 1280 [] == some 680 && durOf "nav" "rect" 1280 [driver] == none
#guard durOf "nav" "visibility" 1280 [] == none && durOf "nav" "visibility" 1280 ["is-scroll-hidden"] == some 320
#guard inFlight (fun _ => some 680) ⟨none, some 879, [], 0, [], 0, 0⟩ &&
  !inFlight (fun _ => some 680) ⟨none, some 880, [], 0, [], 0, 0⟩ &&
  !inFlight (fun _ => none) ⟨none, some 0, [], 0, [], 0, 0⟩ && !inFlight (fun _ => some 680) ⟨none, none, [], 0, [], 0, 0⟩
#guard restarts none ⟨none, none, [], 0, [], 0, 0⟩ &&
  restarts (some ⟨none, some 5, [], 0, [], 0, 0⟩) ⟨none, some 5, [], 0, [driver], 0, 0⟩ &&
  restarts (some ⟨none, some 50, [], 0, [], 0, 0⟩) ⟨none, some 5, [], 0, [], 0, 0⟩ &&
  !restarts (some ⟨none, some 5, [], 0, [], 0, 0⟩) ⟨none, some 50, [], 0, [], 0, 0⟩
#guard (annotate [⟨none, some 0, [], 0, [], 0, 0⟩, ⟨none, some 0, [], 0, [driver], 0, 0⟩, ⟨none, some 0, [], 1, [], 0, 0⟩,
    ⟨none, some 0, [], 0, [], 0, 0⟩]).map (·.ord) == [0, 0, 0, 1]
#guard inEpoch ⟨none, none, [], 0, [], 0, 1⟩ ⟨none, none, [], 0, [], 3, 1⟩ &&
  !inEpoch ⟨none, none, [], 0, [], 0, 1⟩ ⟨none, none, [], 0, [], 0, 0⟩
#guard isCore ⟨none, some 300, [], 0, [], 0, 0⟩ ⟨none, some 500, [], 0, [], 0, 0⟩ &&
  !isCore ⟨none, some 300, [], 0, [], 0, 0⟩ ⟨none, some 501, [], 0, [], 0, 0⟩ &&
  !isCore ⟨none, some 300, [], 0, [], 0, 0⟩ ⟨none, some 300, [], 0, [], 1, 0⟩
#guard (flightWindow [⟨none, some 900, [.num [0]], 0, [], 0, 0⟩, ⟨none, some 0, [.num [1]], 0, [], 0, 1⟩,
    ⟨none, some 400, [.num [2]], 0, [], 0, 1⟩, ⟨none, some 800, [.num [3]], 0, [], 0, 1⟩]
    ⟨none, some 100, [], 0, [], 0, 1⟩).map (·.els) == [[.num [0]], [.num [1]], [.num [2]]]
#guard flightWindow [⟨none, some 100, [], 1, [], 0, 0⟩] ⟨none, some 100, [], 0, [], 0, 0⟩ == []
#guard endOf [⟨none, some 0, [.num [1]], 0, [], 0, 0⟩, ⟨none, some 900, [.num [2]], 0, [], 0, 0⟩]
    ⟨none, some 0, [], 0, [], 0, 0⟩ == some ⟨none, some 900, [.num [2]], 0, [], 0, 0⟩
#guard settledRef (fun _ => some 700) [⟨none, some 5000, [.num [2]], 0, [], 0, 0⟩] ⟨none, some 0, [.num [1]], 0, [], 0, 0⟩ ==
    some ⟨none, some 5000, [.num [2]], 0, [], 0, 0⟩ &&
  settledRef (fun _ => some 700) [⟨none, some 10, [.num [2]], 0, [], 0, 0⟩] ⟨none, some 0, [.num [1]], 0, [], 0, 0⟩ ==
    none &&
  settledRef (fun _ => none) [] ⟨none, some 0, [.num [1]], 0, [], 0, 0⟩ == some ⟨none, some 0, [.num [1]], 0, [], 0, 0⟩
#guard Val.chan (.num [1, 2, 3, 4]) == .num [1, 2, 3] && Val.alpha (.num [1, 2, 3, 4]) == .num [4] &&
  Val.chan (.str "a") == .str "a"
#guard matchOne .colour [[.num [0]], [.num [10000]]] [.num [10000]] == .pass &&
  matchOne .colour [[.num [0]], [.num [10000]]] [.num [5000]] == .fail .apart
#guard judgeColour [⟨none, some 0, [.num [1000, 0, 0, 50000]], 0, [], 0, 0⟩]
    [⟨none, some 0, [.num [1000, 0, 0, 50000]], 0, [], 0, 0⟩, ⟨none, some 0, [.num [9, 9, 9, 90000]], 0, [], 0, 0⟩]
    ⟨none, some 0, [.num [1000, 0, 0, 70000]], 0, [], 0, 0⟩ == .pass
#guard judgeColour [⟨none, some 0, [.num [1000, 0, 0, 50000]], 0, [], 0, 0⟩] [⟨none, some 0, [.num [1000, 0, 0, 50000]], 0, [], 0, 0⟩]
    ⟨none, some 0, [.num [255000, 0, 0, 50000]], 0, [], 0, 0⟩ == .fail .apart
#guard judgeUnit .unit (fun _ => some 700) [] none ⟨none, some 0, [.num [1]], 0, [], 0, 0⟩ == .fail .coverage &&
  judgeUnit .unit (fun _ => some 700) [] (some [⟨none, some 0, [.num [1]], 0, [], 0, 0⟩])
    ⟨none, some 0, [.num [1]], 0, [], 0, 0⟩ == .pass &&
  judgeUnit .unit (fun _ => some 700) [] (some [⟨none, some 0, [.num [1]], 0, [], 0, 0⟩])
    ⟨none, some 5000, [.num [1]], 0, [], 0, 0⟩ == .fail .coverage &&
  judgeUnit .unit (fun _ => none) [] (some [⟨none, some 0, [.num [1]], 0, [], 0, 0⟩]) ⟨none, some 5000, [.num [1]], 0, [], 0, 0⟩ ==
    .pass

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

/-- The verdict of bucket `b`: the rewrite samples in it, each judged on its own (`judgeUnit`), combined.

A bucket of a push that needs a sample and has none is `fail coverage`; elsewhere an empty bucket is a skip. -/
def bucketVerdict (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig rew : List Samp) (b : Nat) : Verdict :=
  match rew.filter (fun r => bucket r.m == b) with
  | [] => if ph == .push && needsSample b then .fail .coverage else .skip .noSample
  | rs => combine (rs.map fun r => judgeUnit k d seg (windowOf orig r.m) r)

/-- The verdicts of one (node, property) along phase `p` of the morph path, one per bucket 0 to 11. `oSeg` and `wSeg` are
the two arms' whole paths, every phase in order, and `ph` says whether phase `p` is a push or a hold.

A bucket is decided by the rewrite samples of phase `p` in it, each against its window of the original's samples of that
phase. In a push, an empty bucket 1 to 9, a rewrite sample without a morph value and a sample with no counterpart in the
original are `fail coverage`: a lane that skips what it cannot see passes a rewrite that does not move. -/
def byM (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (oSeg wSeg : List Samp) :
    List (Nat × Verdict) :=
  let seg := annotate oSeg
  let orig := seg.filter (·.ph == p)
  let rew := (annotate wSeg).filter (·.ph == p)
  (List.range 12).map fun b => (b, bucketVerdict ph k d seg orig rew b)

/-- The verdicts of one (node, property) along a path of steps, one per step of the original.

Each arm's steps in order are one pass. A step's window is the original's sample of that step; a step the rewrite did
not record is a skip. -/
def byStep (k : Kind) (d : List String → Option Nat) (orig rew : List (String × Samp)) : List (String × Verdict) :=
  let seg := annotate (orig.map (·.2))
  let rs := (rew.map (·.1)).zip (annotate (rew.map (·.2)))
  ((orig.map (·.1)).zip seg).map fun (s, o) =>
    match rs.find? (·.1 == s) with
    | some (_, r) => (s, judgeUnit k d seg (some [o]) r)
    | none => (s, .skip .noSample)

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
theorem combine_pass : combine [.skip .noSample, .pass] = .pass := by decide

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
    windowOf [⟨some 0, none, [.num [0]], 0, [], 0, 0⟩, ⟨some 1500, none, [.num [0]], 0, [], 0, 0⟩] (some 9800) = none := by decide

/-- Branch beyond reach, below: the same on the low side. -/
theorem windowOf_beyond_low :
    windowOf [⟨some 6000, none, [.num [0]], 0, [], 0, 0⟩, ⟨some 9000, none, [.num [0]], 0, [], 0, 0⟩] (some 0) = none := by decide

/-- Branch within reach: the nearest sample (and one frame before it) is the window. -/
theorem windowOf_within_reach :
    ((windowOf [⟨some 0, none, [.num [0]], 0, [], 0, 0⟩, ⟨some 9000, none, [.num [0]], 0, [], 0, 0⟩] (some 9800)).map List.length) = some 2 := by
  decide

/-- Branch no morph value in the rewrite sample: no window. -/
theorem windowOf_rewrite_no_m : windowOf [⟨some 0, none, [.num [0]], 0, [], 0, 0⟩] none = none := by decide

/-- Branch no morph value in an original sample: no window, whatever the rewrite's value. -/
theorem windowOf_orig_no_m :
    windowOf [⟨some 0, none, [.num [0]], 0, [], 0, 0⟩, ⟨none, none, [.num [0]], 0, [], 0, 0⟩] (some 0) = none := by decide

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
    ((windowOf ([⟨none, none, [.num [0]], 0, [], 0, 0⟩] ++ ramp 1) (some 4000)).getD []).map (·.rep) = [1, 1, 1, 1, 1] := by
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

/-- No transition under any class set: every sample is at rest. -/
def atRest : List String → Option Nat := fun _ => none

/-- The unit of a morph value: tenths, clamped. -/
theorem bucket_values :
    bucket (some 0) = 0 ∧ bucket (some 499) = 0 ∧ bucket (some 500) = 1 ∧ bucket (some 10000) = 10 ∧
    bucket (some 12000) = 10 ∧ bucket (some (-300)) = 0 ∧ bucket none = 11 := by decide

/-- One frame of slack at a threshold: the rewrite shows `on` at a morph value the original flips at.

The original reads `off` at 0.90 and `on` at 0.93; the rewrite reads `on` at 0.92 and passes. -/
theorem byM_threshold_slack :
    (byM .push 0 .discrete atRest [⟨some 9000, none, [.str "off"], 0, [], 0, 0⟩, ⟨some 9300, none, [.str "on"], 0, [], 0, 0⟩]
        [⟨some 9200, none, [.str "on"], 0, [], 0, 0⟩]).getD 9 (9, .skip .noSample) = (9, .pass) := by decide

/-- Bug B: a class that stays `off` through the tween is a failure at the buckets where the original has `on`.

The original reads `on` from 0.93; the rewrite (waapi) sets the class only at the end, so at 0.95 it is still `off`. -/
theorem byM_stale_class :
    (byM .push 0 .discrete atRest [sm 8000 [.str "off"], sm 8500 [.str "off"], sm 9000 [.str "off"], sm 9300 [.str "on"],
        sm 9400 [.str "on"], sm 9500 [.str "on"], sm 9600 [.str "on"], sm 9700 [.str "on"], sm 9900 [.str "on"]]
      [sm 9500 [.str "off"]]).getD 10 (10, .skip .noSample) = (10, .fail .differs) := by decide

/-- Branch empty bucket in a push, the whole of 1 to 9: no rewrite sample is `fail coverage`, never a skip or a pass. -/
theorem bucketVerdict_push_empty (k : Kind) (d : List String → Option Nat) (seg orig rew : List Samp) (b : Nat) (hb : needsSample b = true)
    (h : ∀ r ∈ rew, bucket r.m ≠ b) : bucketVerdict .push k d seg orig rew b = .fail .coverage := by
  have hf : rew.filter (fun r => bucket r.m == b) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro r hr
    simpa using h r hr
  simp [bucketVerdict, hf, hb]

/-- Branch empty bucket in a hold: a skip. A hold waits at an end of the morph, so its interior buckets are empty by design. -/
theorem bucketVerdict_hold_empty (k : Kind) (d : List String → Option Nat) (seg orig rew : List Samp) (b : Nat)
    (h : ∀ r ∈ rew, bucket r.m ≠ b) : bucketVerdict .hold k d seg orig rew b = .skip .noSample := by
  have hf : rew.filter (fun r => bucket r.m == b) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro r hr
    simpa using h r hr
  simp [bucketVerdict, hf]

/-- Branch empty end bucket in a push: buckets 0, 10 and 11 need no sample (the tween is only crossing them). -/
theorem bucketVerdict_push_empty_ends (k : Kind) (d : List String → Option Nat) (seg orig : List Samp) :
    bucketVerdict .push k d seg orig [] 0 = .skip .noSample ∧ bucketVerdict .push k d seg orig [] 10 = .skip .noSample ∧
    bucketVerdict .push k d seg orig [] 11 = .skip .noSample := by
  simp [bucketVerdict, needsSample]

/-- The edges of the interior: buckets 1 and 9 need a sample, 0 and 10 do not. -/
theorem needsSample_edges :
    needsSample 0 = false ∧ needsSample 1 = true ∧ needsSample 9 = true ∧ needsSample 10 = false ∧
    needsSample 11 = false := by decide

/-- No pass without a sample: a bucket with no rewrite sample is never a pass. -/
theorem bucketVerdict_empty_not_pass (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig rew : List Samp) (b : Nat)
    (h : ∀ r ∈ rew, bucket r.m ≠ b) : bucketVerdict ph k d seg orig rew b ≠ .pass := by
  have hf : rew.filter (fun r => bucket r.m == b) = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro r hr
    simpa using h r hr
  cases ph <;> simp only [bucketVerdict, hf] <;> split <;> simp

/-- Branch no morph value in a push: a rewrite sample the probe could not place on the morph fails in bucket 11. -/
theorem byM_push_no_m :
    (byM .push 0 .discrete atRest [sm 0 [.str "on"], sm 10000 [.str "on"]] [s0 [.str "on"]]).getD 11 (11, .pass) =
      (11, .fail .coverage) := by decide

/-- Branch no morph value in the original: the phases cannot be aligned, every rewrite sample fails. -/
theorem byM_orig_no_m :
    (byM .push 0 .discrete atRest [s0 [.str "on"]] [sm 5000 [.str "on"]]).getD 5 (5, .pass) = (5, .fail .coverage) := by decide

/-- Branch beyond reach: the rewrite at 0.98 against an original sampled over 0 to 0.15 is `fail coverage` (it was a skip). -/
theorem byM_beyond :
    (byM .push 0 .geometry atRest [sm 0 [.num [0]], sm 1500 [.num [3000]]] [sm 9800 [.num [10000]]]).getD 10 (10, .pass) =
      (10, .fail .coverage) := by decide

/-- Branch hold, beyond reach: the same rule holds in a hold. -/
theorem byM_hold_beyond :
    (byM .hold 0 .geometry atRest [sm 0 [.num [0]], sm 1500 [.num [3000]]] [sm 9800 [.num [10000]]]).getD 10 (10, .pass) =
      (10, .fail .coverage) := by decide

/-- Branch hold, a sample at the end: an empty interior bucket stays a skip. -/
theorem byM_hold_interior :
    (byM .hold 0 .discrete atRest [sm 10000 [.str "on"]] [sm 10000 [.str "on"]]).getD 5 (5, .pass) = (5, .skip .noSample) := by
  decide

/-- Branch pooled passes, the stuck rewrite: three passes of a ramp against a rewrite that stays at 0 fail at 0.5.

Over the concatenation of the passes the window of 0.5 held the 0 end of the phase and this passed. -/
theorem byM_pooled_stuck :
    (byM .push 0 .discrete atRest (ramp 0 ++ ramp 1 ++ ramp 2) [smr 0 5000 [.num [0]]]).getD 5 (5, .pass) = (5, .fail .differs) := by
  decide

/-- Branch pooled passes, a ramping rewrite: a rewrite that follows the ramp passes in its bucket. -/
theorem byM_pooled_ramp :
    (byM .push 0 .discrete atRest (ramp 0 ++ ramp 1 ++ ramp 2) [smr 0 4000 [.num [4000]]]).getD 4 (4, .fail .differs) = (4, .pass) := by
  decide

/-- Every bucket 0 to 11 gets its own verdict: twelve per phase, in order. -/
theorem byM_length (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (oSeg wSeg : List Samp) :
    (byM ph p k d oSeg wSeg).length = 12 := by
  simp [byM]

/-- The verdict of a bucket reads only the rewrite samples in that bucket and the original's samples.

A rewrite sample of another bucket cannot change it (unit independence). -/
theorem bucketVerdict_independent (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig rew : List Samp) (b : Nat) (r : Samp)
    (hb : bucket r.m ≠ b) : bucketVerdict ph k d seg orig (r :: rew) b = bucketVerdict ph k d seg orig rew b := by
  simp [bucketVerdict, hb]

/-- A step the original has and the rewrite lacks is a skip. -/
theorem byStep_missing :
    byStep .unit atRest [("s25", ⟨none, none, [.num [750]], 0, [], 0, 0⟩)] [] = [("s25", .skip .noSample)] := by decide

/-- A step is decided by that step's two samples only. -/
theorem byStep_pair :
    byStep .unit atRest [("s25", ⟨none, none, [.num [750]], 0, [], 0, 0⟩), ("s50", ⟨none, none, [.num [500]], 0, [], 0, 0⟩)]
      [("s25", ⟨none, none, [.num [1000]], 0, [], 0, 0⟩), ("s50", ⟨none, none, [.num [500]], 0, [], 0, 0⟩)] =
    [("s25", .fail .apart), ("s50", .pass)] := by decide

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

#guard (⟨none, none, [.absent, .str "a", .num [1, 2]], 0, [], 0, 0⟩ : Samp).form == [.absent, .str, .num 2]

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

/-- A sample in flight has a `since`. -/
theorem inFlight_iff (d : List String → Option Nat) (s : Samp) :
    inFlight d s = true ↔ ∃ t x, d s.cls = some t ∧ s.since = some x ∧ x < t + startLag := by
  unfold inFlight
  split <;> simp_all

/-- Branch no transition: a sample whose classes select no transition is never in flight. -/
theorem inFlight_no_transition (d : List String → Option Nat) (s : Samp) (h : d s.cls = none) :
    inFlight d s = false := by
  simp [inFlight, h]

/-- Branch no class change: a sample read before any class change of the nav is never in flight. -/
theorem inFlight_no_change (d : List String → Option Nat) (s : Samp) (h : s.since = none) : inFlight d s = false := by
  unfold inFlight
  split <;> simp_all

/-- A sample is in its own epoch. -/
theorem inEpoch_self (r : Samp) : inEpoch r r = true := by simp [inEpoch]

/-- A sample with a `since` is in its own core. -/
theorem isCore_self (r : Samp) (h : r.since.isSome) : isCore r r = true := by
  obtain ⟨x, hx⟩ := Option.isSome_iff_exists.mp h
  simp [isCore, inEpoch_self, hx]

/-- The window of a transition holds only samples of the original, of the rewrite sample's pass. -/
theorem flightWindow_sub (seg : List Samp) (r x : Samp) (h : x ∈ flightWindow seg r) : x ∈ seg ∧ x.rep = r.rep := by
  unfold flightWindow at h
  simp only at h
  split at h
  · simp at h
  · simp only [List.mem_filterMap] at h
    obtain ⟨i, _, hi⟩ := h
    cases hp : (passOf seg r.rep)[i]? with
    | none => simp [hp] at hi
    | some o =>
      simp only [hp, Option.bind_some] at hi
      split at hi
      · cases hi
        have := List.mem_of_getElem? hp
        simp only [passOf, List.mem_filter, beq_iff_eq] at this
        exact this
      · simp at hi

/-- A sample of the original with a `since` is in the window of its own transition. -/
theorem mem_flightWindow_self (seg : List Samp) (r : Samp) (hr : r ∈ seg) (hs : r.since.isSome) :
    r ∈ flightWindow seg r := by
  have hp : r ∈ passOf seg r.rep := by simp [passOf, hr]
  obtain ⟨i, hi, hpi⟩ := List.mem_iff_getElem.mp hp
  have hc : isCore r r = true := isCore_self r hs
  have hcore : i ∈ (List.range (passOf seg r.rep).length).filter
      (fun i => ((passOf seg r.rep)[i]?.map (isCore r)).getD false) := by
    simp [hi, hpi, hc]
  unfold flightWindow
  simp only
  split
  · rename_i he
    exact absurd hcore (by rw [List.isEmpty_iff.mp he]; simp)
  · simp only [List.mem_filterMap, List.mem_range]
    refine ⟨i, hi, ?_⟩
    simp only [List.getElem?_eq_getElem hi, hpi, Option.bind_some]
    have hor : ((((List.range (passOf seg r.rep).length).filter
        (fun i => ((passOf seg r.rep)[i]?.map (isCore r)).getD false)).contains (i + 1) &&
        ((List.range (passOf seg r.rep).length).filter
        (fun i => ((passOf seg r.rep)[i]?.map (isCore r)).getD false)).all fun c => decide (i + 1 ≤ c)) ||
        (inEpoch r r && ((List.range (passOf seg r.rep).length).filter
        (fun i => ((passOf seg r.rep)[i]?.map (isCore r)).getD false)).any (fun a => decide (a ≤ i)) &&
        ((List.range (passOf seg r.rep).length).filter
        (fun i => ((passOf seg r.rep)[i]?.map (isCore r)).getD false)).any fun b => decide (i ≤ b + 1))) = true := by
      rw [Bool.or_eq_true]
      right
      simp only [inEpoch_self, Bool.true_and, Bool.and_eq_true, List.any_eq_true, decide_eq_true_eq]
      exact ⟨⟨i, hcore, Nat.le_refl _⟩, ⟨i, hcore, Nat.le_succ _⟩⟩
    split
    · rfl
    · rename_i hn; exact absurd hor hn

/-- The settled reading of a window sample is not in flight. -/
theorem settledRef_settled (d : List String → Option Nat) (seg : List Samp) (w e : Samp)
    (h : settledRef d seg w = some e) : inFlight d e = false := by
  unfold settledRef at h
  split at h
  · rename_i hc; cases h; simpa using hc
  · split at h
    · split at h
      · simp at h
      · rename_i hc; cases h; simpa using hc
    · simp at h

/-- The settled reading of a window sample is the sample itself, or a sample of the original in its epoch: the epoch's
last. -/
theorem settledRef_mem (d : List String → Option Nat) (seg : List Samp) (w e : Samp)
    (h : settledRef d seg w = some e) : e = w ∨ (e ∈ seg ∧ inEpoch w e = true) := by
  unfold settledRef at h
  split at h
  · cases h; left; rfl
  · split at h
    · rename_i e' he
      split at h
      · simp at h
      · cases h
        right
        have := List.mem_of_getLast? he
        simpa using this
    · simp at h

/-- A window sample at rest is its own settled reading. -/
theorem settledRef_rest (d : List String → Option Nat) (seg : List Samp) (w : Samp) (h : inFlight d w = false) :
    settledRef d seg w = some w := by
  simp [settledRef, h]

/-- Dropping the channels keeps two readings of one form of one form. -/
theorem map_alpha_form (a b : List Val) (h : a.map Val.form = b.map Val.form) :
    (a.map Val.alpha).map Val.form = (b.map Val.alpha).map Val.form := by
  induction a generalizing b with
  | nil => cases b <;> simp_all
  | cons x xs ih =>
    cases b with
    | nil => simp at h
    | cons y ys =>
      simp only [List.map_cons, List.cons.injEq] at h ⊢
      refine ⟨?_, ih ys h.2⟩
      have h1 := h.1
      cases x <;> cases y <;> simp_all [Val.alpha, Val.form]

/-- **(a) for a colour in flight.** A rewrite sample that is a sample of the core and of the window, all of whose
samples share its form, never fails. -/
theorem judgeColour_self (core fw : List Samp) (r : Samp) (hc : r ∈ core) (hw : r ∈ fw)
    (hf : ∀ x ∈ fw, x.form = r.form) : isFail (judgeColour core fw r) = false := by
  unfold judgeColour
  apply combine_no_fail
  intro v hv
  simp only [List.mem_cons, List.not_mem_nil, or_false] at hv
  rcases hv with rfl | rfl
  · unfold matchOne
    have hany : ((core.map fun s => s.els.map Val.chan).map fun w => judgeEls .colour [w] (r.els.map Val.chan)).any
        (fun v => !isFail v) = true := by
      rw [List.any_eq_true]
      refine ⟨judgeEls .colour [r.els.map Val.chan] (r.els.map Val.chan), ?_, ?_⟩
      · exact List.mem_map.mpr ⟨r.els.map Val.chan, List.mem_map.mpr ⟨r, hc, rfl⟩, rfl⟩
      · have := judgeEls_self .colour [r.els.map Val.chan] (r.els.map Val.chan) (List.mem_singleton_self _)
          (by simp)
        simp [this]
    dsimp only
    rw [hany]
    rfl
  · apply judgeEls_self
    · exact List.mem_map.mpr ⟨r, hw, rfl⟩
    · intro e he
      simp only [List.mem_map] at he
      obtain ⟨x, hx, rfl⟩ := he
      exact map_alpha_form _ _ (hf x hx)

/-- **(a) One unit.** A rewrite sample that is a sample of the original, in its own window `w` of samples of the original,
never fails, in flight or not, when every sample of the original shares its form. -/
theorem judgeUnit_self (k : Kind) (d : List String → Option Nat) (seg w : List Samp) (r : Samp) (hr : r ∈ seg)
    (hrw : r ∈ w) (hw : ∀ x ∈ w, x ∈ seg) (hf : ∀ x ∈ seg, x.form = r.form) :
    isFail (judgeUnit k d seg (some w) r) = false := by
  unfold judgeUnit
  split
  · rename_i hfl
    have hs : r.since.isSome := by
      obtain ⟨_, x, _, hx, _⟩ := (inFlight_iff d r).1 hfl
      simp [hx]
    have hin := mem_flightWindow_self seg r hr hs
    have hne : (flightWindow seg r).isEmpty = false := by
      cases h : flightWindow seg r with
      | nil => simp [h] at hin
      | cons _ _ => rfl
    have hsub : ∀ x ∈ flightWindow seg r, x.form = r.form := fun x hx => hf x (flightWindow_sub seg r x hx).1
    simp only [hne, Bool.false_eq_true, ↓reduceIte]
    split
    · exact judgeColour_self _ _ r (List.mem_filter.mpr ⟨hin, isCore_self r hs⟩) hin hsub
    · apply judgeEls_self
      · exact List.mem_map.mpr ⟨r, hin, rfl⟩
      · intro e he
        simp only [List.mem_map] at he
        obtain ⟨x, hx, rfl⟩ := he
        exact hsub x hx
  · rename_i hfl
    have hfl' : inFlight d r = false := by simpa using hfl
    have hr' : r ∈ w.filterMap (settledRef d seg) :=
      List.mem_filterMap.mpr ⟨r, hrw, settledRef_rest d seg r hfl'⟩
    have hne : (w.filterMap (settledRef d seg)).isEmpty = false := by
      cases h : w.filterMap (settledRef d seg) with
      | nil => simp [h] at hr'
      | cons _ _ => rfl
    simp only [hne, Bool.false_eq_true, ↓reduceIte]
    apply judgeEls_self
    · exact List.mem_map.mpr ⟨r, hr', rfl⟩
    · intro e he
      simp only [List.mem_map, List.mem_filterMap] at he
      obtain ⟨x, ⟨y, hy, hxy⟩, rfl⟩ := he
      apply hf
      rcases settledRef_mem d seg y x hxy with h1 | h1
      · rw [h1]; exact hw y hy
      · exact h1.1

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

/-- Annotating keeps the number of samples. -/
theorem annotate_length (seg : List Samp) : (annotate seg).length = seg.length := by
  simp [annotate]

/-- An annotated sample is a sample of the list with its `ord` set. -/
theorem annotate_mem (seg : List Samp) (x : Samp) (h : x ∈ annotate seg) : ∃ s ∈ seg, ∃ o, x = { s with ord := o } := by
  simp only [annotate, List.mem_mapIdx] at h
  obtain ⟨i, hi, rfl⟩ := h
  exact ⟨seg[i], List.getElem_mem hi, _, rfl⟩

/-- Every sample of the list is in its annotation, with its `ord` set. -/
theorem mem_annotate (seg : List Samp) (s : Samp) (h : s ∈ seg) : ∃ o, { s with ord := o } ∈ annotate seg := by
  obtain ⟨i, hi, rfl⟩ := List.mem_iff_getElem.mp h
  exact ⟨_, List.mem_mapIdx.mpr ⟨i, hi, rfl⟩⟩

/-- **(a) on a path of steps.** An arm whose samples are the original's, step for step, never fails a step, in flight or
not, when the original's steps are distinct and its samples share a form. -/
theorem byStep_self (k : Kind) (d : List String → Option Nat) (orig : List (String × Samp))
    (hn : (orig.map (·.1)).Nodup) (hf : ∀ a ∈ orig, ∀ b ∈ orig, a.2.form = b.2.form) :
    ∀ v ∈ byStep k d orig orig, isFail v.2 = false := by
  intro v hv
  have hlen : (orig.map (·.1)).length ≤ (annotate (orig.map (·.2))).length := by simp [annotate_length]
  have hn' : (((orig.map (·.1)).zip (annotate (orig.map (·.2)))).map (·.1)).Nodup := by
    rw [List.map_fst_zip hlen]; exact hn
  simp only [byStep, List.mem_map] at hv
  obtain ⟨⟨s, o⟩, hmem, rfl⟩ := hv
  simp only [find_step _ hn' s o hmem]
  have ho := (List.of_mem_zip hmem).2
  have hform : ∀ x ∈ annotate (orig.map (·.2)), ∃ a ∈ orig, x.form = a.2.form := by
    intro x hx
    obtain ⟨t, ht, _, rfl⟩ := annotate_mem _ x hx
    simp only [List.mem_map] at ht
    obtain ⟨a, ha, rfl⟩ := ht
    exact ⟨a, ha, rfl⟩
  apply judgeUnit_self k d _ [o] o ho (List.mem_singleton_self _)
  · intro x hx; rw [List.mem_singleton.mp hx]; exact ho
  · intro x hx
    obtain ⟨a, ha, hxa⟩ := hform x hx
    obtain ⟨b, hb, hob⟩ := hform o ho
    rw [hxa, hob]
    exact hf a ha b hb

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

/-- **(a) on the morph path.** An arm whose samples are the original's never fails a bucket it has a sample in, in flight
or not, when every sample of the original has a morph value, the phase's samples are samples of the whole path, and the
path's samples share a form. -/
theorem bucketVerdict_self (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig : List Samp) (b : Nat)
    (hm : ∀ s ∈ orig, s.m.isSome) (ho : ∀ s ∈ orig, s ∈ seg) (hf : ∀ a ∈ seg, ∀ c ∈ seg, a.form = c.form)
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
    rw [hw]
    apply judgeUnit_self k d seg w r (ho r hro) hrw
    · intro x hx
      have hx' : x ∈ (windowOf orig r.m).getD [] := by simp [hw, hx]
      have := windowOne_sub _ _ _ ((windowOf_pass_iff orig r.m x).mp hx')
      simp only [passOf, List.mem_filter] at this
      exact ho x this.1
    · intro x hx
      exact hf x hx r (ho r hro)

/-- **(a) on a phase.** An arm whose path is the original's never fails a bucket of a phase the original has a sample in,
in flight or not, when every sample has a morph value and all share a form. -/
theorem byM_self (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (oSeg : List Samp)
    (hm : ∀ s ∈ oSeg, s.m.isSome) (hf : ∀ a ∈ oSeg, ∀ c ∈ oSeg, a.form = c.form) (v : Nat × Verdict)
    (hv : v ∈ byM ph p k d oSeg oSeg) (hb : ∃ s ∈ oSeg, s.ph = p ∧ bucket s.m = v.1) : isFail v.2 = false := by
  simp only [byM, List.mem_map] at hv
  obtain ⟨b, _, rfl⟩ := hv
  apply bucketVerdict_self
  · intro s hs
    obtain ⟨t, ht, _, rfl⟩ := annotate_mem _ s (List.mem_filter.mp hs).1
    exact hm t ht
  · intro s hs; exact (List.mem_filter.mp hs).1
  · intro a ha c hc
    obtain ⟨t, ht, _, rfl⟩ := annotate_mem _ a ha
    obtain ⟨u, hu, _, rfl⟩ := annotate_mem _ c hc
    exact hf t ht u hu
  · obtain ⟨s, hs, hp, hsb⟩ := hb
    obtain ⟨o, ho⟩ := mem_annotate oSeg s hs
    exact ⟨_, List.mem_filter.mpr ⟨ho, by simp [hp]⟩, hsb⟩

/-! ## Transitions in flight -/

/-- No rule for reduced motion applies: the probe runs with no motion preference. -/
theorem applies_reduce (r : Rule) (node : String) (width : Nat) (cls : List String) (h : r.reduce = true) :
    applies r node width cls = false := by
  simp [applies, h]

/-- Branch driver: while the morph's script drives the nav, no property has a transition. -/
theorem durOf_driver (node prop : String) (width : Nat) (cls : List String) (h : cls.contains driver = true) :
    durOf node prop width cls = none := by
  have : driver ∈ cls := by simpa using h
  simp [durOf, this]

/-- The transitions of the table under their class sets.

At rest the nav's box moves for 680 ms and its background for 700. Visibility switches with no delay unless the nav
hides on scroll. A hero pill that is not ready has no transition; a ready one fades in 700 ms when wider than 600 px,
280 below. The earn button fades in 440 ms (120 of delay), 200 in the hero pill. The gap has none while the morph runs. -/
theorem durOf_values :
    durOf "nav" "rect" 1280 [] = some 680 ∧ durOf "nav" "background-color" 1280 [] = some 700 ∧
    durOf "nav" "visibility" 1280 [] = none ∧ durOf "nav" "visibility" 1280 ["is-scroll-hidden"] = some 320 ∧
    durOf "nav" "opacity" 1280 ["is-hero-pill", "is-hero-chrome-ready"] = some 700 ∧
    durOf "nav" "opacity" 390 ["is-hero-pill", "is-hero-chrome-ready"] = some 280 ∧
    durOf "nav" "opacity" 1280 ["is-hero-pill"] = none ∧
    durOf "earn" "opacity" 1280 [] = some 440 ∧ durOf "earn" "opacity" 1280 ["is-hero-pill"] = some 200 ∧
    durOf "actions" "gap" 1280 [] = some 680 ∧ durOf "actions" "gap" 1280 ["is-morphing"] = none ∧
    durOf "logo" "color" 1280 [] = some 240 ∧ durOf "nav" "border-radius" 1280 [] = none := by decide

/-- Branch in flight, no original sample in the transition, no counterpart: `fail coverage`. -/
theorem judgeUnit_flight_uncovered (k : Kind) (d : List String → Option Nat) (seg : List Samp) (r : Samp)
    (hfl : inFlight d r = true) (he : flightWindow seg r = []) : judgeUnit k d seg none r = .fail .coverage := by
  simp [judgeUnit, hfl, he]

/-- Branch in flight, no original sample in the transition: the rewrite sample is judged against its window `w`. -/
theorem judgeUnit_flight_fallback (k : Kind) (d : List String → Option Nat) (seg w : List Samp) (r : Samp)
    (hfl : inFlight d r = true) (he : flightWindow seg r = []) :
    judgeUnit k d seg (some w) r = judgeEls k (w.map (·.els)) r.els := by
  simp [judgeUnit, hfl, he]

/-- Branch in flight, a colour: the channels against the core, the alpha against the transition's window. -/
theorem judgeUnit_flight_colour (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp)) (r : Samp)
    (hfl : inFlight d r = true) (hne : flightWindow seg r ≠ []) :
    judgeUnit .colour d seg win r = judgeColour ((flightWindow seg r).filter (isCore r)) (flightWindow seg r) r := by
  have : (flightWindow seg r).isEmpty = false := by cases h : flightWindow seg r <;> simp_all
  simp [judgeUnit, hfl, this]

/-- Branch in flight, not a colour: the rewrite sample against the original's samples of the same transition. -/
theorem judgeUnit_flight_els (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (hk : k ≠ .colour) (hfl : inFlight d r = true) (hne : flightWindow seg r ≠ []) :
    judgeUnit k d seg win r = judgeEls k ((flightWindow seg r).map (·.els)) r.els := by
  have : (flightWindow seg r).isEmpty = false := by cases h : flightWindow seg r <;> simp_all
  simp [judgeUnit, hfl, this, hk]

/-- Branch at rest, no counterpart: `fail coverage`. -/
theorem judgeUnit_settled_uncovered (k : Kind) (d : List String → Option Nat) (seg : List Samp) (r : Samp)
    (hfl : inFlight d r = false) : judgeUnit k d seg none r = .fail .coverage := by
  simp [judgeUnit, hfl]

/-- **(b) A settled rewrite sample.** At rest, the rewrite sample is judged against the settled readings its window
stands for, whatever the original's samples are; `fail coverage` when the original never settled there. Each of those
readings is at rest (`settledRef_settled`) and is the window's sample or the end of its epoch (`settledRef_mem`). -/
theorem judgeUnit_settled (k : Kind) (d : List String → Option Nat) (seg w : List Samp) (r : Samp)
    (hfl : inFlight d r = false) :
    judgeUnit k d seg (some w) r =
      if (w.filterMap (settledRef d seg)).isEmpty then .fail .coverage
      else judgeEls k ((w.filterMap (settledRef d seg)).map (·.els)) r.els := by
  simp [judgeUnit, hfl]

/-- The transition of the nav's background at 1280 px, by class set. -/
def bgDur : List String → Option Nat := durOf "nav" "background-color" 1280

/-- The transition of the nav's visibility at 1280 px, by class set. -/
def visDur : List String → Option Nat := durOf "nav" "visibility" 1280

/-- **(b) on steps.** A settled rewrite reading pure red, then pure green, fails against a white the original reads in
flight at the first step and settled at the second. -/
theorem byStep_settled_red_green :
    byStep .colour bgDur
      [("a6", ⟨none, some 100, [.num [1000, 0, 0, 33340]], 0, [], 0, 0⟩),
        ("a7", ⟨none, some 5000, [.num [255000, 255000, 255000, 26000]], 0, [], 0, 0⟩)]
      [("a6", ⟨none, some 5000, [.num [255000, 0, 0, 100000]], 0, [], 0, 0⟩),
        ("a7", ⟨none, some 5100, [.num [0, 255000, 0, 26000]], 0, [], 0, 0⟩)] =
    [("a6", .fail .apart), ("a7", .fail .apart)] := by decide

/-- A settled rewrite reading the end value passes where the original was in flight. -/
theorem byStep_settled_end :
    byStep .colour bgDur
      [("a6", ⟨none, some 100, [.num [1000, 0, 0, 33340]], 0, [], 0, 0⟩),
        ("a7", ⟨none, some 5000, [.num [255000, 255000, 255000, 26000]], 0, [], 0, 0⟩)]
      [("a6", ⟨none, some 5000, [.num [255000, 255000, 255000, 26000]], 0, [], 0, 0⟩)] =
    [("a6", .pass), ("a7", .skip .noSample)] := by decide

/-- A settled rewrite step against an original that never settled in that epoch is `fail coverage`, never a pass. -/
theorem byStep_settled_unsettled :
    byStep .discrete visDur [("s2", ⟨none, some 100, [.str "visible"], 0, ["is-scroll-hidden"], 0, 0⟩)]
      [("s2", ⟨none, some 9000, [.str "hidden"], 0, ["is-scroll-hidden"], 0, 0⟩)] = [("s2", .fail .coverage)] := by
  decide

/-- The transition of the nav's box at 1280 px, by class set. -/
def rectDur : List String → Option Nat := durOf "nav" "rect" 1280

/-- A push of the nav's box in flight: the morph value `m` at `since` = `m` / 12.5 ms, the box `[0, 0, w, 64000]` with
`w` from 400 to 800 px. -/
def rectRamp (rev : Bool) : List Samp :=
  [0, 2000, 4000, 6000, 8000, 10000].map fun m =>
    ⟨some m, some (m / 25 * 2).toNat, [.num [0, 0, 400000 + 40 * (if rev then 10000 - m else m), 64000]], 0, [], 0, 0⟩

/-- **The reversed curve fails in flight.** A rewrite whose box at `m` is the original's at `1 - m` fails at 0.2, though
every sample is within the transition of the class change. -/
theorem byM_reversed_in_flight :
    (byM .push 0 .geometry rectDur (rectRamp false) (rectRamp true)).getD 2 (2, .pass) = (2, .fail .apart) := by
  decide

/-- Component `j` of element `i` lies more than `t` beyond every reading of `win` on one side of the number `x`, every
reading having `n` elements and its element `i` being `len` numbers. -/
def Outside (t : Int) (i j n len : Nat) (x : Int) (win : List (List Val)) : Prop :=
  (∀ w ∈ win, w.length = n ∧ ∃ ys, w.getD i .absent = .num ys ∧ ys.length = len) ∧
    ((∀ w ∈ win, ∀ ys, w.getD i .absent = .num ys → ys.getD j 0 + t < x) ∨
      (∀ w ∈ win, ∀ ys, w.getD i .absent = .num ys → x + t < ys.getD j 0))

/-- The numbers a window yields are readings of the window. -/
theorem numsOf_mem (win : List Val) (ns : List (List Int)) (h : numsOf win = some ns) (ys : List Int) (hy : ys ∈ ns) :
    Val.num ys ∈ win := by
  induction win generalizing ns with
  | nil => simp [numsOf] at h; subst h; simp at hy
  | cons v rest ih =>
    cases v with
    | num xs =>
      simp only [numsOf] at h
      cases hr : numsOf rest with
      | none => simp [hr] at h
      | some ns' =>
        simp only [hr, Option.map_some, Option.some.injEq] at h
        subst h
        rcases List.mem_cons.mp hy with h1 | h1
        · subst h1; exact List.mem_cons_self ..
        · exact List.mem_cons_of_mem _ (ih ns' hr h1)
    | absent => simp [numsOf] at h
    | str _ => simp [numsOf] at h

/-- Verdicts one of which fails combine to a failure. -/
theorem combine_fail_of_mem (vs : List Verdict) (h : ∃ v ∈ vs, isFail v = true) : isFail (combine vs) = true := by
  obtain ⟨v, hv, hf⟩ := h
  unfold combine
  cases hfind : vs.find? (fun v => match v with | .fail _ => true | _ => false) with
  | some f =>
    have := List.find?_some hfind
    cases f <;> simp_all [isFail]
  | none =>
    rw [List.find?_eq_none] at hfind
    have := hfind v hv
    cases v <;> simp_all [isFail]

/-- A number whose component `j` lies more than the tolerance beyond every reading of the window, on one side, fails. -/
theorem judgeVal_outside (k : Kind) (win : List Val) (xs : List Int) (j : Nat) (hj : j < xs.length) (hne : win ≠ [])
    (hw : ∀ v ∈ win, ∃ ys, v = .num ys ∧ ys.length = xs.length)
    (hout : (∀ ys, Val.num ys ∈ win → ys.getD j 0 + tol k < xs.getD j 0) ∨
      (∀ ys, Val.num ys ∈ win → xs.getD j 0 + tol k < ys.getD j 0)) :
    isFail (judgeVal k win (.num xs)) = true := by
  have he : win.isEmpty = false := by cases win <;> simp_all
  have hab : win.any (· == .absent) = false := by
    rw [List.any_eq_false]; intro v hv; obtain ⟨ys, rfl, _⟩ := hw v hv; simp
  obtain ⟨ns, hns, hall, hl⟩ :=
    numsOf_all win xs.length (fun v hv => by obtain ⟨ys, rfl, hy⟩ := hw v hv; simp [Val.form, hy])
  have hlen : ns.any (·.length != xs.length) = false := by
    rw [List.any_eq_false]; intro ys hy; simp [hl ys hy]
  have hmem := numsOf_mem win ns hns
  obtain ⟨v0, hv0⟩ := List.exists_mem_of_ne_nil win hne
  obtain ⟨y0, rfl, _⟩ := hw v0 hv0
  have hy0 := hall y0 hv0
  have ht := tol_nonneg k
  simp only [judgeVal, he, hab, hns, hlen, Bool.false_eq_true, ↓reduceIte]
  split
  · have hc : xs ∉ ns := by
      intro hx
      rcases hout with h | h <;> (have := h xs (hmem xs hx); omega)
    simp [hc, isFail]
  · have hb : inBand (tol k) ns xs = false := by
      unfold inBand
      rw [List.all_eq_false]
      refine ⟨j, List.mem_range.mpr hj, ?_⟩
      have hc : y0.getD j 0 ∈ ns.map (·.getD j 0) := List.mem_map_of_mem hy0
      obtain ⟨lo, hlo⟩ := Option.isSome_iff_exists.mp (List.isSome_min?_of_mem hc)
      obtain ⟨hi, hhi⟩ := Option.isSome_iff_exists.mp (List.isSome_max?_of_mem hc)
      have hlo' := (List.min?_eq_some_iff.1 hlo).1
      have hhi' := (List.max?_eq_some_iff.1 hhi).1
      simp only [List.mem_map] at hlo' hhi'
      obtain ⟨a, ha, hla⟩ := hlo'
      obtain ⟨b, hb, hhb⟩ := hhi'
      simp only [hlo, hhi, Bool.and_eq_true, decide_eq_true_eq]
      rcases hout with h | h
      · have := h b (hmem b hb); omega
      · have := h a (hmem a ha); omega
    simp [hb, isFail]

/-- **(c) A sample outside the band fails**, for readings of any number of elements and components: when component `j`
of element `i` lies more than the tolerance beyond every reading of the window on one side. -/
theorem judgeEls_outside (k : Kind) (win : List (List Val)) (r : List Val) (i j : Nat) (xs : List Int)
    (hi : i < r.length) (hr : r.getD i .absent = .num xs) (hj : j < xs.length) (hne : win ≠ [])
    (ho : Outside (tol k) i j r.length xs.length (xs.getD j 0) win) : isFail (judgeEls k win r) = true := by
  have he : win.isEmpty = false := by cases win <;> simp_all
  have hl : win.any (·.length != r.length) = false := by
    rw [List.any_eq_false]; intro w hw; simp [(ho.1 w hw).1]
  simp only [judgeEls, he, hl, Bool.false_eq_true, ↓reduceIte]
  apply combine_fail_of_mem
  refine ⟨judgeVal k (win.map (·.getD i .absent)) (r.getD i .absent), List.mem_map.mpr ⟨i, List.mem_range.mpr hi, rfl⟩,
    ?_⟩
  rw [hr]
  apply judgeVal_outside k _ xs j hj (by simpa using hne)
  · intro v hv
    simp only [List.mem_map] at hv
    obtain ⟨w, hw, rfl⟩ := hv
    obtain ⟨_, ys, h1, h2⟩ := ho.1 w hw
    exact ⟨ys, h1, h2⟩
  · rcases ho.2 with h | h
    · left; intro ys hy
      simp only [List.mem_map] at hy
      obtain ⟨w, hw, hwy⟩ := hy
      exact h w hw ys hwy
    · right; intro ys hy
      simp only [List.mem_map] at hy
      obtain ⟨w, hw, hwy⟩ := hy
      exact h w hw ys hwy

/-- **(c) in flight**, not a colour: outside the band of the original's samples of the same transition fails. -/
theorem judgeUnit_flight_outside (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (i j : Nat) (xs : List Int) (hk : k ≠ .colour) (hfl : inFlight d r = true)
    (hne : flightWindow seg r ≠ []) (hi : i < r.els.length) (hr : r.els.getD i .absent = .num xs) (hj : j < xs.length)
    (ho : Outside (tol k) i j r.els.length xs.length (xs.getD j 0) ((flightWindow seg r).map (·.els))) :
    isFail (judgeUnit k d seg win r) = true := by
  rw [judgeUnit_flight_els k d seg win r hk hfl hne]
  exact judgeEls_outside k _ r.els i j xs hi hr hj (by simpa using hne) ho

/-- **(c) at rest**: outside the band of the settled readings the window stands for fails, a colour too. -/
theorem judgeUnit_settled_outside (k : Kind) (d : List String → Option Nat) (seg w : List Samp) (r : Samp)
    (i j : Nat) (xs : List Int) (hfl : inFlight d r = false) (hne : w.filterMap (settledRef d seg) ≠ [])
    (hi : i < r.els.length) (hr : r.els.getD i .absent = .num xs) (hj : j < xs.length)
    (ho : Outside (tol k) i j r.els.length xs.length (xs.getD j 0) ((w.filterMap (settledRef d seg)).map (·.els))) :
    isFail (judgeUnit k d seg (some w) r) = true := by
  have he : (w.filterMap (settledRef d seg)).isEmpty = false := by
    cases h : w.filterMap (settledRef d seg) <;> simp_all
  rw [judgeUnit_settled k d seg w r hfl, he]
  exact judgeEls_outside k _ r.els i j xs hi hr hj (by simpa using hne) ho

/-- Element `i` of a list of readings, each mapped by `f` that keeps `absent`. -/
theorem getD_map_absent (f : Val → Val) (hf : f .absent = .absent) (l : List Val) (i : Nat) :
    (l.map f).getD i .absent = f (l.getD i .absent) := by
  simp only [List.getD_eq_getElem?_getD, List.getElem?_map]
  cases l[i]? <;> simp [hf]

/-- **(c) for a colour in flight, a channel**: red, green or blue outside the band of every core sample fails. -/
theorem judgeUnit_colour_chan_outside (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (i j : Nat) (xs : List Int) (hfl : inFlight d r = true) (hc : ∃ o ∈ flightWindow seg r, isCore r o)
    (hi : i < r.els.length) (hr : r.els.getD i .absent = .num xs) (hj : j < 3) (hjx : j < xs.length)
    (ho : Outside (tol .colour) i j r.els.length xs.length (xs.getD j 0)
      (((flightWindow seg r).filter (isCore r)).map (·.els))) :
    isFail (judgeUnit .colour d seg win r) = true := by
  obtain ⟨o0, ho0, hc0⟩ := hc
  have hne : flightWindow seg r ≠ [] := by intro h; simp [h] at ho0
  rw [judgeUnit_flight_colour d seg win r hfl hne]
  unfold judgeColour
  apply combine_fail_of_mem
  refine ⟨_, List.mem_cons_self .., ?_⟩
  have htake : ∀ ys : List Int, (ys.take 3).getD j 0 = ys.getD j 0 := by
    intro ys; simp [List.getD_eq_getElem?_getD, hj]
  have hall : ∀ w ∈ ((flightWindow seg r).filter (isCore r)).map fun s => s.els.map Val.chan,
      isFail (judgeEls .colour [w] (r.els.map Val.chan)) = true := by
    intro w hw
    simp only [List.mem_map] at hw
    obtain ⟨s, hs, rfl⟩ := hw
    have hs' : s.els ∈ ((flightWindow seg r).filter (isCore r)).map (·.els) := List.mem_map_of_mem hs
    obtain ⟨hlen, ys, hys, hyl⟩ := ho.1 _ hs'
    apply judgeEls_outside .colour _ _ i j (xs.take 3) (by simpa using hi)
      (by rw [getD_map_absent _ rfl, hr]; rfl) (by simp; omega) (by simp)
    refine ⟨?_, ?_⟩
    · intro w hw
      rw [List.mem_singleton.mp hw]
      refine ⟨by simp [hlen], ys.take 3, by rw [getD_map_absent _ rfl, hys]; rfl, by simp [hyl]⟩
    · rw [htake]
      rcases ho.2 with h | h
      · left; intro w hw zs hz
        rw [List.mem_singleton.mp hw, getD_map_absent _ rfl, hys] at hz
        cases hz
        rw [htake]; exact h _ hs' ys hys
      · right; intro w hw zs hz
        rw [List.mem_singleton.mp hw, getD_map_absent _ rfl, hys] at hz
        cases hz
        rw [htake]; exact h _ hs' ys hys
  unfold matchOne
  dsimp only
  have hany : ((((flightWindow seg r).filter (isCore r)).map fun s => s.els.map Val.chan).map
      fun w => judgeEls .colour [w] (r.els.map Val.chan)).any (fun v => !isFail v) = false := by
    rw [List.any_eq_false]
    intro v hv
    simp only [List.mem_map] at hv
    obtain ⟨w, hw, rfl⟩ := hv
    have := hall w (List.mem_map.mpr hw)
    simp [this]
  simp only [hany, Bool.false_eq_true, ↓reduceIte]
  apply combine_fail_of_mem
  have hcore : o0 ∈ (flightWindow seg r).filter (isCore r) := List.mem_filter.mpr ⟨ho0, hc0⟩
  exact ⟨_, List.mem_map_of_mem (List.mem_map_of_mem hcore), hall _ (List.mem_map_of_mem hcore)⟩

/-- **(c) for a colour in flight, the alpha**: an alpha outside the band of the transition's window fails. -/
theorem judgeUnit_colour_alpha_outside (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (i : Nat) (xs : List Int) (hfl : inFlight d r = true) (hne : flightWindow seg r ≠ [])
    (hi : i < r.els.length) (hr : r.els.getD i .absent = .num xs) (hx : 3 < xs.length)
    (ho : Outside (tol .colour) i 3 r.els.length xs.length (xs.getD 3 0) ((flightWindow seg r).map (·.els))) :
    isFail (judgeUnit .colour d seg win r) = true := by
  rw [judgeUnit_flight_colour d seg win r hfl hne]
  unfold judgeColour
  apply combine_fail_of_mem
  refine ⟨_, List.mem_cons_of_mem _ (List.mem_cons_self ..), ?_⟩
  have hdrop : ∀ ys : List Int, (ys.drop 3).getD 0 0 = ys.getD 3 0 := by
    intro ys; simp [List.getD_eq_getElem?_getD, List.getElem?_drop]
  apply judgeEls_outside .colour _ _ i 0 (xs.drop 3) (by simpa using hi)
    (by rw [getD_map_absent _ rfl, hr]; rfl) (by simp; omega) (by simpa using hne)
  refine ⟨?_, ?_⟩
  · intro w hw
    simp only [List.mem_map] at hw
    obtain ⟨s, hs, rfl⟩ := hw
    obtain ⟨hlen, ys, hys, hyl⟩ := ho.1 _ (List.mem_map_of_mem hs)
    exact ⟨by simp [hlen], ys.drop 3, by rw [getD_map_absent _ rfl, hys]; rfl, by simp [hyl]⟩
  · rw [hdrop]
    rcases ho.2 with h | h
    · left; intro w hw zs hz
      simp only [List.mem_map] at hw
      obtain ⟨s, hs, rfl⟩ := hw
      obtain ⟨_, ys, hys, _⟩ := ho.1 _ (List.mem_map_of_mem hs)
      rw [getD_map_absent _ rfl, hys] at hz
      cases hz
      rw [hdrop]; exact h _ (List.mem_map_of_mem hs) ys hys
    · right; intro w hw zs hz
      simp only [List.mem_map] at hw
      obtain ⟨s, hs, rfl⟩ := hw
      obtain ⟨_, ys, hys, _⟩ := ho.1 _ (List.mem_map_of_mem hs)
      rw [getD_map_absent _ rfl, hys] at hz
      cases hz
      rw [hdrop]; exact h _ (List.mem_map_of_mem hs) ys hys

/-- The lane fails when one unit fails, and only then. -/
theorem laneFails_iff (vs : List Verdict) : laneFails vs = true ↔ ∃ v ∈ vs, isFail v = true := by
  simp [laneFails]

/-- A lane of passes and skips does not fail. -/
theorem laneFails_none : laneFails [.pass, .skip .noSample] = false := by decide

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
theorem rel_skip_cleared : rel (.skip .noSample) (.fail .differs) = .cleared := by decide

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
  | .skip .noSample => "skip:noSample"

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
    ("since", match s.since with | none => Json.null | some t => toJson t), ("els", Json.arr (s.els.map Val.json).toArray),
    ("rep", toJson s.rep), ("cls", Json.arr (s.cls.map Json.str).toArray), ("ph", toJson s.ph), ("ord", toJson s.ord)]

/-- The transition a golden case names: the table's for (node, property, width), or none under any class set. -/
def durFn : Option (String × String × Nat) → List String → Option Nat
  | none => atRest
  | some (n, p, w) => durOf n p w

/-- The transition a golden case names, as JSON: null, or its node, property and width. -/
def durJson : Option (String × String × Nat) → Json
  | none => Json.null
  | some (n, p, w) => Json.mkObj [("node", n), ("prop", p), ("width", toJson w)]

/-- The nav classes the probe reads, in the order of the registry. -/
def navClasses : List String :=
  ["is-hero-pill", "is-hero-chrome-ready", "is-morphing", "is-expanded", "is-on-dark", "is-scroll-hidden"]

/-- The class set of mask `k`: class `i` of `navClasses` is on when bit `i` of `k` is. -/
def maskCls (k : Nat) : List String :=
  (List.range navClasses.length).filterMap fun i => if k.testBit i then navClasses[i]? else none

#guard maskCls 0 == [] && maskCls 5 == ["is-hero-pill", "is-morphing"] && maskCls 63 == navClasses

/-- A rule as JSON. -/
def Rule.json (r : Rule) : Json :=
  Json.mkObj [("line", toJson r.line), ("node", r.node), ("on", Json.arr (r.on.map Json.str).toArray),
    ("off", Json.arr (r.off.map Json.str).toArray), ("minW", match r.minW with | none => Json.null | some w => toJson w),
    ("reduce", Json.bool r.reduce), ("spec", toJson r.spec),
    ("set", match r.set with
      | none => Json.null
      | some ts => Json.arr (ts.map fun (p, d, l) => Json.arr #[Json.str p, toJson d, toJson l]).toArray),
    ("delay", match r.delay with | none => Json.null | some l => toJson l)]

/-- One golden line. -/
inductive Case where
  | judge (name : String) (k : Kind) (win : List Samp) (r : Samp)
  | bracket (name : String) (ms : List Int) (m : Int)
  | tenth (name : String) (m : Option Int)
  | phase (name : String) (ph : Phase) (p : Nat) (k : Kind) (dur : Option (String × String × Nat))
      (oSeg wSeg : List Samp)
  | unit (name : String) (k : Kind) (dur : Option (String × String × Nat)) (seg : List Samp)
      (win : Option (List Samp)) (r : Samp)
  | rule (r : Rule)
  | durs (node prop : String) (width : Nat)
  | ann (name : String) (seg : List Samp)
  | versus (name : String) (cand base : Verdict)
  | quant (name : String) (xs : List Nat) (p : Nat)
  | dominate (name : String) (readP50 gapP50 : Nat)
  | armOf (name : String) (a : ArmRead)
  | runOf (name : String) (arms : List ArmRead)
  | path (name : String) (k : Kind) (dur : Option (String × String × Nat)) (orig rew : List (String × Samp))
  | picks (name : String) (input : String)
  | planOf (name : String) (engines widths : String)

/-- The golden cases of the window judgement (`judgeEls` per kind and per branch). Two constants, not one, so that each stays
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
  .phase "threshold slack" .push 0 .discrete none [sm 9000 [.str "off"], sm 9300 [.str "on"]] [sm 9200 [.str "on"]],
  .phase "stale class" .push 0 .discrete none
    [sm 8000 [.str "off"], sm 8500 [.str "off"], sm 9000 [.str "off"], sm 9300 [.str "on"], sm 9400 [.str "on"],
      sm 9500 [.str "on"], sm 9600 [.str "on"], sm 9700 [.str "on"], sm 9900 [.str "on"]] [sm 9500 [.str "off"]],
  .phase "ramp ok" .push 0 .geometry none [sm 0 [.num [0]], sm 5000 [.num [5000]], sm 10000 [.num [10000]]]
    [sm 2000 [.num [2000]], sm 7000 [.num [7000]]],
  .phase "ramp stuck" .push 0 .geometry none [sm 0 [.num [0]], sm 5000 [.num [5000]], sm 10000 [.num [10000]]]
    [sm 2000 [.num [0]], sm 7000 [.num [0]]],
  .phase "ramp every bucket" .push 0 .geometry none [sm 0 [.num [0]], sm 5000 [.num [5000]], sm 10000 [.num [10000]]]
    [sm 0 [.num [0]], sm 1000 [.num [1000]], sm 2000 [.num [2000]], sm 3000 [.num [3000]], sm 4000 [.num [4000]],
      sm 5000 [.num [5000]], sm 6000 [.num [6000]], sm 7000 [.num [7000]], sm 8000 [.num [8000]], sm 9000 [.num [9000]],
      sm 10000 [.num [10000]]],
  .phase "push first bucket only" .push 0 .geometry none [sm 0 [.num [0]], sm 10000 [.num [10000]]] [sm 1000 [.num [1000]]],
  .phase "push no rewrite sample" .push 0 .discrete none [sm 0 [.str "off"], sm 10000 [.str "on"]] [],
  .phase "hold colour" .hold 0 .colour none [⟨some 10000, some 0, [.num [43000]], 0, [], 0, 0⟩, ⟨some 10000, none, [.num [255000]], 0, [], 0, 0⟩]
    [⟨some 10000, some 0, [.num [43000]], 0, [], 0, 0⟩, ⟨some 10000, none, [.num [43000]], 0, [], 0, 0⟩],
  .phase "hold interior empty" .hold 0 .discrete none [sm 10000 [.str "on"]] [sm 10000 [.str "on"]],
  .phase "hold no rewrite sample" .hold 0 .discrete none [sm 10000 [.str "on"]] [],
  .phase "push no morph value" .push 0 .discrete none [s0 [.str "on"]] [s0 [.str "on"]],
  .phase "push rewrite no morph value" .push 0 .discrete none [sm 0 [.str "on"], sm 10000 [.str "on"]] [s0 [.str "on"]],
  .phase "hold no morph value" .hold 0 .discrete none [s0 [.str "on"]] [s0 [.str "on"]],
  .phase "beyond reach" .push 0 .geometry none [sm 0 [.num [0]], sm 1500 [.num [3000]]] [sm 9800 [.num [10000]]],
  .phase "hold beyond reach" .hold 0 .geometry none [sm 0 [.num [0]], sm 1500 [.num [3000]]] [sm 9800 [.num [10000]]],
  .phase "within reach" .push 0 .geometry none [sm 0 [.num [0]], sm 9000 [.num [9000]]] [sm 9800 [.num [9800]]],
  .phase "pooled ramp original, static rewrite" .push 0 .discrete none (ramp 0 ++ ramp 1 ++ ramp 2) [smr 0 5000 [.num [0]]],
  .phase "pooled ramp original, ramping rewrite" .push 0 .discrete none (ramp 0 ++ ramp 1 ++ ramp 2)
    [smr 0 2000 [.num [2000]], smr 0 4000 [.num [4000]], smr 1 6000 [.num [6000]], smr 2 8000 [.num [8000]]],
  .phase "pooled ramp original, stuck class" .push 0 .discrete none (ramp 0 ++ ramp 1)
    [smr 0 9000 [.num [0]], smr 1 9000 [.num [0]]],
  .phase "pooled slow pass" .push 0 .discrete none ([0, 2000, 4000].map (fun m => smr 0 m [.num [m]]) ++ ramp 1)
    [smr 1 9800 [.num [10000]]],
  .phase "pooled all passes beyond" .push 0 .discrete none ([0, 1500].map (fun m => smr 0 m [.num [m]]) ++ [0, 1500].map (fun m => smr 1 m [.num [m]]))
    [smr 0 9800 [.num [10000]]],
  .phase "pooled pass without morph value" .push 0 .discrete none ([⟨none, none, [.num [0]], 0, [], 0, 0⟩] ++ ramp 1) [smr 1 4000 [.num [4000]]],
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
  .versus "cleared" .pass (.fail .apart), .versus "skip cleared" (.skip .noSample) (.fail .differs), .versus "ok" .pass .pass,
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

/-- A sample of pass `rep` and phase `ph` with the nav classes `cls`, at morph value `m`, read `t` ms after the last class
change, in epoch `ord`. -/
def sc (rep ph : Nat) (cls : List String) (m : Option Int) (t : Nat) (ord : Nat) (els : List Val) : Samp :=
  ⟨m, some t, els, rep, cls, ph, ord⟩

/-- A sample with no morph value, read `t` ms after the last class change. -/
def st (t : Nat) (els : List Val) : Samp := ⟨none, some t, els, 0, [], 0, 0⟩

/-- The nav's box `[0, 0, w, 64000]` along a push, `w` from 400 to 800 px: at morph value `m`, `t` = `m` / 12.5 ms after the
class change; reversed (`rev`), the box at `m` is the forward one at `1 - m`. -/
def boxRamp (rev : Bool) (cls : List String) : List Samp :=
  (List.range 11).map fun (i : Nat) =>
    let m : Int := 1000 * i
    sc 0 0 cls (some m) (80 * i) 0 [.num [0, 0, 400000 + 40 * (if rev then 10000 - m else m), 64000]]

/-- The nav's box in flight under no class, read every 100 ms from 0 to 800. -/
def boxSeg : List Samp :=
  (List.range 9).map fun i => sc 0 0 [] none (100 * i) 0 [.num [0, 0, 400000 + 50000 * i, 64000]]

/-- The transition of the nav's box at 1280 px. -/
def boxDur : Option (String × String × Nat) := some ("nav", "rect", 1280)

/-- The transition of the nav's background at 1280 px. -/
def bgDurOf : Option (String × String × Nat) := some ("nav", "background-color", 1280)

/-- A background fading from white to an alpha of 26000 in the kit's colour space in flight: before the change, three
readings in flight, and the end. -/
def bgSeg : List Samp :=
  [sc 0 0 [] none 5000 0 [.num [255000, 255000, 255000, 122400]], sc 0 0 [] none 100 1 [.num [1000, 0, 0, 90000]],
    sc 0 0 [] none 300 1 [.num [1000, 0, 0, 50000]], sc 0 0 [] none 500 1 [.num [1000, 0, 0, 30000]],
    sc 0 0 [] none 5000 1 [.num [255000, 255000, 255000, 26000]]]

/-- The golden cases of transitions in flight: the table, epochs, each branch of `judgeUnit`, the reversed curve, and the
morph and step paths. -/
def casesFlight : List Case :=
  rules.map .rule ++
  ([("nav", "visibility"), ("nav", "rect"), ("nav", "background-color"), ("nav", "opacity"), ("nav", "transform.lin"),
      ("nav", "transform.shift"), ("logo", "color"), ("actions", "gap"), ("earn", "opacity"), ("earn", "max-width"),
      ("nav", "filter")].flatMap fun (n, p) => [390, 600, 601, 1280].map (.durs n p)) ++ [
  .ann "one epoch" [sc 0 0 [] none 0 0 [], sc 0 0 [] none 100 0 [], sc 0 0 [] none 200 0 []],
  .ann "class change and back" [sc 0 0 [] none 0 0 [], sc 0 0 [] none 100 0 [], sc 0 0 [driver] none 0 0 [],
    sc 0 0 [driver] none 50 0 [], sc 0 0 [] none 0 0 [], sc 0 0 [] none 100 0 []],
  .ann "since drops" [sc 0 0 [] none 500 0 [], sc 0 0 [] none 20 0 []],
  .ann "per pass" [sc 0 0 [] none 0 0 [], sc 1 0 [] none 0 0 [], sc 0 0 ["is-on-dark"] none 0 0 [], sc 0 0 [] none 0 0 []],
  .ann "no since after since" [sc 0 0 [] none 10 0 [], ⟨none, none, [], 0, [], 0, 0⟩],
  .ann "since after no since" [⟨none, none, [], 0, [], 0, 0⟩, sc 0 0 [] none 5 0 []],
  .unit "in flight, inside" .geometry boxDur boxSeg none (sc 0 0 [] none 300 0 [.num [0, 0, 560000, 64000]]),
  .unit "in flight, outside" .geometry boxDur boxSeg none (sc 0 0 [] none 300 0 [.num [0, 0, 760000, 64000]]),
  .unit "in flight, reversed value" .geometry boxDur boxSeg none (sc 0 0 [] none 100 0 [.num [0, 0, 750000, 64000]]),
  .unit "in flight, other pass" .geometry boxDur boxSeg (some [sc 1 0 [] none 300 0 [.num [0, 0, 760000, 64000]]])
    (sc 1 0 [] none 300 0 [.num [0, 0, 760000, 64000]]),
  .unit "in flight, other pass, no counterpart" .geometry boxDur boxSeg none
    (sc 1 0 [] none 300 0 [.num [0, 0, 550000, 64000]]),
  .unit "in flight, other phase" .geometry boxDur boxSeg (some [sc 0 2 [] none 300 0 [.num [0, 0, 760000, 64000]]])
    (sc 0 2 [] none 300 0 [.num [0, 0, 550000, 64000]]),
  .unit "in flight, other epoch" .geometry boxDur boxSeg (some [sc 0 0 [] none 300 1 [.num [0, 0, 760000, 64000]]])
    (sc 0 0 [] none 300 1 [.num [0, 0, 550000, 64000]]),
  .unit "in flight, other classes" .geometry boxDur boxSeg (some [sc 0 0 ["is-on-dark"] none 300 0 [.num [0, 0, 1, 1]]])
    (sc 0 0 ["is-on-dark"] none 300 0 [.num [0, 0, 550000, 64000]]),
  .unit "lag edge in flight" .geometry boxDur boxSeg none (sc 0 0 [] none 879 0 [.num [0, 0, 300000, 64000]]),
  .unit "lag edge settled" .geometry boxDur boxSeg (some [sc 0 0 [] none 880 0 [.num [0, 0, 300000, 64000]]])
    (sc 0 0 [] none 880 0 [.num [0, 0, 300000, 64000]]),
  .unit "driver, no transition" .geometry boxDur boxSeg (some [sc 0 0 [driver] none 10 0 [.num [0, 0, 400000, 64000]]])
    (sc 0 0 [driver] none 10 0 [.num [0, 0, 800000, 64000]]),
  .unit "colour in flight, one core reading" .colour bgDurOf bgSeg none (sc 0 0 [] none 300 1 [.num [1000, 0, 0, 45000]]),
  .unit "colour in flight, pure red" .colour bgDurOf bgSeg none (sc 0 0 [] none 300 1 [.num [255000, 0, 0, 50000]]),
  .unit "colour in flight, pure green" .colour bgDurOf bgSeg none (sc 0 0 [] none 300 1 [.num [0, 255000, 0, 50000]]),
  .unit "colour in flight, colour space" .colour bgDurOf bgSeg none
    (sc 0 0 [] none 500 1 [.num [255000, 255000, 255000, 30000]]),
  .unit "colour in flight, alpha outside" .colour bgDurOf bgSeg none (sc 0 0 [] none 300 1 [.num [1000, 0, 0, 200000]]),
  .unit "colour in flight, alpha of the start" .colour bgDurOf bgSeg none (sc 0 0 [] none 100 1 [.num [1000, 0, 0, 122400]]),
  .unit "settled at the end value" .colour bgDurOf bgSeg (some [sc 0 0 [] none 300 1 [.num [1000, 0, 0, 50000]]])
    (sc 0 0 [] none 5000 1 [.num [255000, 255000, 255000, 26000]]),
  .unit "settled red" .colour bgDurOf bgSeg (some [sc 0 0 [] none 300 1 [.num [1000, 0, 0, 50000]]])
    (sc 0 0 [] none 5000 1 [.num [255000, 0, 0, 26000]]),
  .unit "settled green" .colour bgDurOf bgSeg (some [sc 0 0 [] none 300 1 [.num [1000, 0, 0, 50000]]])
    (sc 0 0 [] none 5000 1 [.num [0, 255000, 0, 26000]]),
  .unit "settled, original never settled" .discrete (some ("nav", "visibility", 1280))
    [sc 0 0 ["is-scroll-hidden"] none 100 0 [.str "visible"]]
    (some [sc 0 0 ["is-scroll-hidden"] none 100 0 [.str "visible"]]) (sc 0 0 ["is-scroll-hidden"] none 9000 0 [.str "hidden"]),
  .unit "settled, no counterpart" .colour bgDurOf bgSeg none (sc 0 0 [] none 5000 1 [.num [255000, 255000, 255000, 26000]]),
  .phase "reversed curve in flight" .push 0 .geometry boxDur (boxRamp false []) (boxRamp true []),
  .phase "same curve in flight" .push 0 .geometry boxDur (boxRamp false []) (boxRamp false []),
  .phase "reversed morph, script driven" .push 0 .geometry boxDur (boxRamp false [driver]) (boxRamp true [driver]),
  .path "steps in flight" .colour bgDurOf
    [("a5", st 2222 [.num [255000, 255000, 255000, 122400]]), ("a6", st 481 [.num [1000, 0, 0, 33340]]),
      ("a7", st 1134 [.num [255000, 255000, 255000, 26000]])]
    [("a5", st 1271 [.num [255000, 255000, 255000, 122400]]), ("a6", st 327 [.num [1000, 0, 0, 51667]]),
      ("a7", st 703 [.num [1000, 0, 0, 26029]])],
  .path "steps settled red and green" .colour bgDurOf
    [("a6", st 100 [.num [1000, 0, 0, 33340]]), ("a7", st 5000 [.num [255000, 255000, 255000, 26000]])]
    [("a6", st 5000 [.num [255000, 0, 0, 100000]]), ("a7", st 5100 [.num [0, 255000, 0, 26000]])],
  .path "step settled differs" .unit none [("a1", st 5000 [.num [255000]]), ("a2", st 5000 [.num [9000]])]
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
    Json.mkObj [("op", "els"), ("name", n), ("kind", k.name),
      ("win", Json.arr (win.map fun s => Json.arr (s.els.map Val.json).toArray).toArray),
      ("r", Json.arr (r.els.map Val.json).toArray), ("verdict", (judgeEls k (win.map (·.els)) r.els).name)]
  | .bracket n ms m =>
    Json.mkObj [("op", "window"), ("name", n), ("ms", Json.arr (ms.map fun x => toJson x).toArray), ("m", toJson m),
      ("idx", Json.arr ((window ms m).map fun i => toJson i).toArray)]
  | .tenth n m =>
    Json.mkObj [("op", "bucket"), ("name", n), ("m", match m with | none => Json.null | some m => toJson m),
      ("bucket", toJson (bucket m))]
  | .phase n ph p k dur o w =>
    Json.mkObj [("op", "byM"), ("name", n), ("phase", ph.name), ("p", toJson p), ("kind", k.name), ("dur", durJson dur),
      ("oSeg", Json.arr (o.map Samp.json).toArray), ("wSeg", Json.arr (w.map Samp.json).toArray),
      ("verdicts", Json.arr ((byM ph p k (durFn dur) o w).map fun (_, v) => Json.str v.name).toArray)]
  | .unit n k dur seg win r =>
    Json.mkObj [("op", "unit"), ("name", n), ("kind", k.name), ("dur", durJson dur),
      ("seg", Json.arr (seg.map Samp.json).toArray),
      ("win", match win with | none => Json.null | some w => Json.arr (w.map Samp.json).toArray), ("r", r.json),
      ("verdict", (judgeUnit k (durFn dur) seg win r).name)]
  | .rule r => Json.mkObj [("op", "rule"), ("name", s!"line {r.line} {r.node}"), ("rule", r.json)]
  | .durs node prop w =>
    Json.mkObj [("op", "dur"), ("name", s!"{node} {prop} {w}"), ("node", node), ("prop", prop), ("width", toJson w),
      ("classes", Json.arr (navClasses.map Json.str).toArray), ("lag", toJson startLag),
      ("durs", Json.arr ((List.range 64).map fun k => optNat (durOf node prop w (maskCls k))).toArray)]
  | .ann n seg =>
    Json.mkObj [("op", "annotate"), ("name", n), ("seg", Json.arr (seg.map Samp.json).toArray),
      ("ords", Json.arr ((annotate seg).map fun s => toJson s.ord).toArray)]
  | .path n k dur o r =>
    let side := fun (xs : List (String × Samp)) =>
      Json.arr (xs.map fun (s, x) => Json.mkObj [("step", s), ("s", x.json)]).toArray
    Json.mkObj [("op", "byStep"), ("name", n), ("kind", k.name), ("dur", durJson dur), ("orig", side o), ("rew", side r),
      ("verdicts",
        Json.arr ((byStep k (durFn dur) o r).map fun (s, v) => Json.mkObj [("step", s), ("verdict", v.name)]).toArray)]
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
