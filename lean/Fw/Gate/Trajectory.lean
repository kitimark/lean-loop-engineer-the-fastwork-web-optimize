import Lean.Data.Json
import Fw.Parts.Bezier
import Fw.Parts.Nav
import Fw.Parts.HeroExitCloseStart
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

inductive Skip where
  | noSample
  | origEmpty
  deriving DecidableEq, Repr

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
(`cls`), the index of the phase it was read in (`ph`), the number of earlier epochs of its pass with the same classes
(`ord`, set by `annotate`), and the ms its reads started at, rounded (`t0`; `none`: not recorded).

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
  t0 : Option Nat
  deriving DecidableEq, Repr

/-- A sample with a morph value, in pass 0, no class change. -/
def sm (m : Int) (els : List Val) : Samp := ⟨some m, none, els, 0, [], 0, 0, none⟩

/-- A sample with a morph value, in pass `rep`, no class change. -/
def smr (rep : Nat) (m : Int) (els : List Val) : Samp := ⟨some m, none, els, rep, [], 0, 0, none⟩

/-- A sample without a morph value, in pass 0, no class change. -/
def s0 (els : List Val) : Samp := ⟨none, none, els, 0, [], 0, 0, none⟩

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

`trajectory.test.mjs` parses the CSS file and requires this list exactly. The rules at lines 297 and 298 are the two
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
  ⟨201, "earn", ["is-earn-still"], [], none, false, 4, some [], none⟩,
  ⟨290, "nav", [], ["is-morphing"], none, true, 2,
    some [("background", 320, 0), ("opacity", 280, 0), ("transform", 320, 0), ("visibility", 0, 320)], none⟩,
  ⟨297, "nav", ["is-morphing"], [], none, true, 2, some [], none⟩,
  ⟨298, "earn", [], [], none, true, 2, some [], none⟩]

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

/-- The nav class under which the site's script sets the morph's styles on every frame. Under it the judge treats every
sample as at rest; rules 6 and 167 still run transitions driven by `--morph` (nav transform/opacity, earn
max-width/opacity/padding), which are judged strictly against the m-window. -/
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
in force on its CSS properties. `none` when no transition runs, and under `driver` (a strict at-rest convention: the
CSS does still run `--morph`-driven transitions there). -/
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

/-- Sample `o` is in the core of `r`'s transition read in `o`'s own pass. -/
def isCoreIn (r o : Samp) : Bool := isCore { r with rep := o.rep } o

/-- The `flightWindow` of `r`'s epoch read in every pass of `seg`, in order of the passes. -/
def envelope (seg : List Samp) (r : Samp) : List Samp :=
  (repsOf seg).flatMap fun q => flightWindow seg { r with rep := q }

/-- One rewrite sample `r` against the original's samples `fw` of its transition, `core` marking their core, and against
`win` at rest or when `fw` is empty. -/
def judgeWith (k : Kind) (d : List String → Option Nat) (seg fw : List Samp) (core : Samp → Bool)
    (win : Option (List Samp)) (r : Samp) : Verdict :=
  if inFlight d r then
    if fw.isEmpty then
      match win with
      | none => .fail .coverage
      | some w => judgeEls k (w.map (·.els)) r.els
    else if k == .colour then judgeColour (fw.filter core) fw r
    else judgeEls k (fw.map (·.els)) r.els
  else
    match win with
    | none => .fail .coverage
    | some w =>
      let ref := w.filterMap (settledRef d seg)
      if ref.isEmpty then .fail .coverage else judgeEls k (ref.map (·.els)) r.els

/-- **One rewrite sample**: in flight against the `envelope` of its transition, at rest against the settled readings of
`win`. -/
def judgeUnit (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp)) (r : Samp) :
    Verdict :=
  judgeWith k d seg (envelope seg r) (isCoreIn r) win r

/-- One rewrite sample, in flight against the `flightWindow` of its own pass only. -/
def judgeOwn (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp)) (r : Samp) :
    Verdict :=
  judgeWith k d seg (flightWindow seg r) (isCore r) win r

/-- The first sample of `r`'s epoch in the original's path `seg`. -/
def startOf (seg : List Samp) (r : Samp) : Option Samp := seg.find? (inEpoch r)

/-- Rewrite sample `r` is read within `startLag` of the first sample of its epoch in the original's pass. -/
def atStart (seg : List Samp) (r : Samp) : Bool :=
  match (startOf seg r).bind (·.since), r.since with
  | some a, some b => decide (((a : Int) - b).natAbs ≤ startLag)
  | _, _ => false

/-- The rejected scope of the envelope: `judgeUnit` at the start of a transition, `judgeOwn` after it. -/
def judgeScoped (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp)) (r : Samp) :
    Verdict :=
  if atStart seg r then judgeUnit k d seg win r else judgeOwn k d seg win r

#guard (rules.filter (applies · "nav" 1280 ["is-hero-pill"])).map (·.line) == [6, 41, 73, 78]
#guard (rules.filter (applies · "nav" 390 ["is-hero-pill"])).map (·.line) == [6, 41, 73]
#guard (rules.filter (applies · "earn" 1280 [])).map (·.line) == [167]
#guard (lastBy (rules.filter (applies · "nav" 1280 ["is-scroll-hidden"]))).map (·.line) == some 63
#guard transitionsOf "nav" 1280 [] ==
  [("background", 700, 0), ("opacity", 280, 0), ("transform", 320, 0), ("visibility", 0, 0), ("width", 680, 0)]
#guard transitionsOf "nav" 1280 ["is-hero-pill"] == []
#guard durOf "nav" "rect" 1280 [] == some 680 && durOf "nav" "rect" 1280 [driver] == none
#guard durOf "nav" "visibility" 1280 [] == none && durOf "nav" "visibility" 1280 ["is-scroll-hidden"] == some 320
#guard inFlight (fun _ => some 680) ⟨none, some 879, [], 0, [], 0, 0, none⟩ &&
  !inFlight (fun _ => some 680) ⟨none, some 880, [], 0, [], 0, 0, none⟩ &&
  !inFlight (fun _ => none) ⟨none, some 0, [], 0, [], 0, 0, none⟩ && !inFlight (fun _ => some 680) ⟨none, none, [], 0, [], 0, 0, none⟩
#guard restarts none ⟨none, none, [], 0, [], 0, 0, none⟩ &&
  restarts (some ⟨none, some 5, [], 0, [], 0, 0, none⟩) ⟨none, some 5, [], 0, [driver], 0, 0, none⟩ &&
  restarts (some ⟨none, some 50, [], 0, [], 0, 0, none⟩) ⟨none, some 5, [], 0, [], 0, 0, none⟩ &&
  !restarts (some ⟨none, some 5, [], 0, [], 0, 0, none⟩) ⟨none, some 50, [], 0, [], 0, 0, none⟩
#guard (annotate [⟨none, some 0, [], 0, [], 0, 0, none⟩, ⟨none, some 0, [], 0, [driver], 0, 0, none⟩, ⟨none, some 0, [], 1, [], 0, 0, none⟩,
    ⟨none, some 0, [], 0, [], 0, 0, none⟩]).map (·.ord) == [0, 0, 0, 1]
#guard inEpoch ⟨none, none, [], 0, [], 0, 1, none⟩ ⟨none, none, [], 0, [], 3, 1, none⟩ &&
  !inEpoch ⟨none, none, [], 0, [], 0, 1, none⟩ ⟨none, none, [], 0, [], 0, 0, none⟩
#guard isCore ⟨none, some 300, [], 0, [], 0, 0, none⟩ ⟨none, some 500, [], 0, [], 0, 0, none⟩ &&
  !isCore ⟨none, some 300, [], 0, [], 0, 0, none⟩ ⟨none, some 501, [], 0, [], 0, 0, none⟩ &&
  !isCore ⟨none, some 300, [], 0, [], 0, 0, none⟩ ⟨none, some 300, [], 0, [], 1, 0, none⟩
#guard (flightWindow [⟨none, some 900, [.num [0]], 0, [], 0, 0, none⟩, ⟨none, some 0, [.num [1]], 0, [], 0, 1, none⟩,
    ⟨none, some 400, [.num [2]], 0, [], 0, 1, none⟩, ⟨none, some 800, [.num [3]], 0, [], 0, 1, none⟩]
    ⟨none, some 100, [], 0, [], 0, 1, none⟩).map (·.els) == [[.num [0]], [.num [1]], [.num [2]]]
#guard flightWindow [⟨none, some 100, [], 1, [], 0, 0, none⟩] ⟨none, some 100, [], 0, [], 0, 0, none⟩ == []
#guard endOf [⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩, ⟨none, some 900, [.num [2]], 0, [], 0, 0, none⟩]
    ⟨none, some 0, [], 0, [], 0, 0, none⟩ == some ⟨none, some 900, [.num [2]], 0, [], 0, 0, none⟩
#guard settledRef (fun _ => some 700) [⟨none, some 5000, [.num [2]], 0, [], 0, 0, none⟩] ⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩ ==
    some ⟨none, some 5000, [.num [2]], 0, [], 0, 0, none⟩ &&
  settledRef (fun _ => some 700) [⟨none, some 10, [.num [2]], 0, [], 0, 0, none⟩] ⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩ ==
    none &&
  settledRef (fun _ => none) [] ⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩ == some ⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩
#guard Val.chan (.num [1, 2, 3, 4]) == .num [1, 2, 3] && Val.alpha (.num [1, 2, 3, 4]) == .num [4] &&
  Val.chan (.str "a") == .str "a"
#guard matchOne .colour [[.num [0]], [.num [10000]]] [.num [10000]] == .pass &&
  matchOne .colour [[.num [0]], [.num [10000]]] [.num [5000]] == .fail .apart
#guard judgeColour [⟨none, some 0, [.num [1000, 0, 0, 50000]], 0, [], 0, 0, none⟩]
    [⟨none, some 0, [.num [1000, 0, 0, 50000]], 0, [], 0, 0, none⟩, ⟨none, some 0, [.num [9, 9, 9, 90000]], 0, [], 0, 0, none⟩]
    ⟨none, some 0, [.num [1000, 0, 0, 70000]], 0, [], 0, 0, none⟩ == .pass
#guard judgeColour [⟨none, some 0, [.num [1000, 0, 0, 50000]], 0, [], 0, 0, none⟩] [⟨none, some 0, [.num [1000, 0, 0, 50000]], 0, [], 0, 0, none⟩]
    ⟨none, some 0, [.num [255000, 0, 0, 50000]], 0, [], 0, 0, none⟩ == .fail .apart
#guard judgeUnit .unit (fun _ => some 700) [] none ⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩ == .fail .coverage &&
  judgeUnit .unit (fun _ => some 700) [] (some [⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩])
    ⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩ == .pass &&
  judgeUnit .unit (fun _ => some 700) [] (some [⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩])
    ⟨none, some 5000, [.num [1]], 0, [], 0, 0, none⟩ == .fail .coverage &&
  judgeUnit .unit (fun _ => none) [] (some [⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩]) ⟨none, some 5000, [.num [1]], 0, [], 0, 0, none⟩ ==
    .pass
#guard isCoreIn ⟨none, some 100, [], 0, [], 0, 1, none⟩ ⟨none, some 0, [], 1, [], 0, 1, none⟩ &&
  !isCore ⟨none, some 100, [], 0, [], 0, 1, none⟩ ⟨none, some 0, [], 1, [], 0, 1, none⟩ &&
  !isCoreIn ⟨none, some 100, [], 0, [], 0, 1, none⟩ ⟨none, some 0, [], 1, [], 0, 0, none⟩
#guard (envelope [⟨none, some 900, [.num [0]], 0, [], 0, 0, none⟩, ⟨none, some 0, [.num [1]], 0, [], 0, 1, none⟩,
    ⟨none, some 900, [.num [5]], 1, [], 0, 0, none⟩, ⟨none, some 0, [.num [6]], 1, [], 0, 1, none⟩]
    ⟨none, some 100, [], 0, [], 0, 1, none⟩).map (·.els) == [[.num [0]], [.num [1]], [.num [5]], [.num [6]]]
#guard judgeUnit .unit (fun _ => some 700) [⟨none, some 900, [.num [0]], 0, [], 0, 0, none⟩, ⟨none, some 0, [.num [1000]], 0, [], 0, 1, none⟩,
    ⟨none, some 900, [.num [5000]], 1, [], 0, 0, none⟩, ⟨none, some 0, [.num [6000]], 1, [], 0, 1, none⟩] none
    ⟨none, some 100, [.num [6000]], 0, [], 0, 1, none⟩ == .pass &&
  judgeOwn .unit (fun _ => some 700) [⟨none, some 900, [.num [0]], 0, [], 0, 0, none⟩, ⟨none, some 0, [.num [1000]], 0, [], 0, 1, none⟩,
    ⟨none, some 900, [.num [5000]], 1, [], 0, 0, none⟩, ⟨none, some 0, [.num [6000]], 1, [], 0, 1, none⟩] none
    ⟨none, some 100, [.num [6000]], 0, [], 0, 1, none⟩ == .fail .apart &&
  judgeUnit .unit (fun _ => some 700) [⟨none, some 900, [.num [0]], 0, [], 0, 0, none⟩, ⟨none, some 0, [.num [1000]], 0, [], 0, 1, none⟩,
    ⟨none, some 900, [.num [5000]], 1, [], 0, 0, none⟩, ⟨none, some 0, [.num [6000]], 1, [], 0, 1, none⟩] none
    ⟨none, some 100, [.num [9000]], 0, [], 0, 1, none⟩ == .fail .apart
#guard judgeWith .unit (fun _ => some 700) [] [⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩] (fun _ => true) none
    ⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩ == .pass &&
  judgeWith .unit (fun _ => some 700) [] [] (fun _ => true) none ⟨none, some 0, [.num [1]], 0, [], 0, 0, none⟩ == .fail .coverage
#guard startOf [⟨none, some 900, [], 0, [], 0, 0, none⟩, ⟨none, some 40, [], 0, [], 0, 1, none⟩, ⟨none, some 90, [], 0, [], 0, 1, none⟩]
    ⟨none, some 300, [], 0, [], 0, 1, none⟩ == some ⟨none, some 40, [], 0, [], 0, 1, none⟩ &&
  startOf [⟨none, some 40, [], 1, [], 0, 1, none⟩] ⟨none, some 300, [], 0, [], 0, 1, none⟩ == none
#guard atStart [⟨none, some 40, [], 0, [], 0, 1, none⟩] ⟨none, some 240, [], 0, [], 0, 1, none⟩ &&
  !atStart [⟨none, some 40, [], 0, [], 0, 1, none⟩] ⟨none, some 241, [], 0, [], 0, 1, none⟩ &&
  !atStart [⟨none, some 40, [], 1, [], 0, 1, none⟩] ⟨none, some 40, [], 0, [], 0, 1, none⟩ &&
  !atStart [⟨none, none, [], 0, [], 0, 1, none⟩] ⟨none, some 40, [], 0, [], 0, 1, none⟩
#guard judgeScoped .unit (fun _ => some 700) [⟨none, some 0, [.num [1000]], 0, [], 0, 1, none⟩,
    ⟨none, some 0, [.num [6000]], 1, [], 0, 1, none⟩] none ⟨none, some 100, [.num [6000]], 0, [], 0, 1, none⟩ == .pass &&
  judgeScoped .unit (fun _ => some 700) [⟨none, some 0, [.num [1000]], 0, [], 0, 1, none⟩, ⟨none, some 300, [.num [1000]], 0, [], 0, 1, none⟩,
    ⟨none, some 300, [.num [6000]], 1, [], 0, 1, none⟩] none ⟨none, some 300, [.num [6000]], 0, [], 0, 1, none⟩ == .fail .apart

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

/-- The first sample of pass `q` in phase `p + 1` of `seg`. -/
def headOf (seg : List Samp) (q p : Nat) : Option Samp := seg.find? fun o => o.rep == q && o.ph == p + 1

/-- The window of `r` in pass `q` of a push: the next hold's first row when `r` is settled, has that row's morph value
and the push never sampled that value, else `windowOne`. -/
def windowPass (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) (q : Nat) : Option (List Samp) :=
  match headOf seg q r.ph with
  | some h =>
    if r.m.isSome && !inFlight d r && h.m == r.m && !(passOf orig q).any (·.m == r.m) then some [h]
    else windowOne (passOf orig q) r.m
  | none => windowOne (passOf orig q) r.m

/-- The window of rewrite sample `r` in phase `orig` of `seg`: per pass by `windowPass` in a push, `windowOf` in a hold. -/
def windowAt (ph : Phase) (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) : Option (List Samp) :=
  if ph == .push then
    match (repsOf orig).filterMap (windowPass d seg orig r) with
    | [] => none
    | ws => some ws.flatten
  else windowOf orig r.m

/-- The verdict of bucket `b`: the rewrite samples in it, each judged on its own against its `windowAt`, combined; an
empty bucket is `fail coverage` in a push that needs a sample, else a skip. -/
def bucketVerdict (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig rew : List Samp) (b : Nat) : Verdict :=
  match rew.filter (fun r => bucket r.m == b) with
  | [] => if ph == .push && needsSample b then .fail .coverage else .skip .noSample
  | rs => combine (rs.map fun r => judgeUnit k d seg (windowAt ph d seg orig r) r)

#guard headOf [⟨some 100, none, [], 0, [], 0, 0, none⟩, ⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩] 0 0 ==
    some ⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩ &&
  headOf [⟨some 100, none, [], 0, [], 0, 0, none⟩, ⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩] 1 0 == none
#guard windowPass (fun _ => none) [⟨some 100, none, [], 0, [], 0, 0, none⟩, ⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩]
    [⟨some 100, none, [], 0, [], 0, 0, none⟩] ⟨some 0, none, [], 0, [], 0, 0, none⟩ 0 == some [⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩] &&
  windowPass (fun _ => some 700) [⟨some 100, none, [], 0, [], 0, 0, none⟩, ⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩]
    [⟨some 100, none, [], 0, [], 0, 0, none⟩] ⟨some 0, some 0, [], 0, [], 0, 0, none⟩ 0 == some [⟨some 100, none, [], 0, [], 0, 0, none⟩] &&
  windowPass (fun _ => none) [⟨some 0, none, [], 0, [], 0, 0, none⟩, ⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩]
    [⟨some 0, none, [], 0, [], 0, 0, none⟩] ⟨some 0, none, [], 0, [], 0, 0, none⟩ 0 == some [⟨some 0, none, [], 0, [], 0, 0, none⟩] &&
  windowPass (fun _ => none) [⟨some 100, none, [], 0, [], 0, 0, none⟩, ⟨some 50, none, [.num [1]], 0, [], 1, 0, none⟩]
    [⟨some 100, none, [], 0, [], 0, 0, none⟩] ⟨some 0, none, [], 0, [], 0, 0, none⟩ 0 == some [⟨some 100, none, [], 0, [], 0, 0, none⟩]
#guard windowAt .push (fun _ => none) [⟨some 100, none, [], 0, [], 0, 0, none⟩, ⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩]
    [⟨some 100, none, [], 0, [], 0, 0, none⟩] ⟨some 0, none, [], 0, [], 0, 0, none⟩ == some [⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩] &&
  windowAt .hold (fun _ => none) [⟨some 100, none, [], 0, [], 0, 0, none⟩, ⟨some 0, none, [.num [1]], 0, [], 1, 0, none⟩]
    [⟨some 100, none, [], 0, [], 0, 0, none⟩] ⟨some 0, none, [], 0, [], 0, 0, none⟩ == some [⟨some 100, none, [], 0, [], 0, 0, none⟩] &&
  windowAt .push (fun _ => none) [] [] ⟨some 0, none, [], 0, [], 0, 0, none⟩ == none

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
    windowOf [⟨some 0, none, [.num [0]], 0, [], 0, 0, none⟩, ⟨some 1500, none, [.num [0]], 0, [], 0, 0, none⟩] (some 9800) = none := by decide

/-- Branch beyond reach, below: the same on the low side. -/
theorem windowOf_beyond_low :
    windowOf [⟨some 6000, none, [.num [0]], 0, [], 0, 0, none⟩, ⟨some 9000, none, [.num [0]], 0, [], 0, 0, none⟩] (some 0) = none := by decide

/-- Branch within reach: the nearest sample (and one frame before it) is the window. -/
theorem windowOf_within_reach :
    ((windowOf [⟨some 0, none, [.num [0]], 0, [], 0, 0, none⟩, ⟨some 9000, none, [.num [0]], 0, [], 0, 0, none⟩] (some 9800)).map List.length) = some 2 := by
  decide

/-- Branch no morph value in the rewrite sample: no window. -/
theorem windowOf_rewrite_no_m : windowOf [⟨some 0, none, [.num [0]], 0, [], 0, 0, none⟩] none = none := by decide

/-- Branch no morph value in an original sample: no window, whatever the rewrite's value. -/
theorem windowOf_orig_no_m :
    windowOf [⟨some 0, none, [.num [0]], 0, [], 0, 0, none⟩, ⟨none, none, [.num [0]], 0, [], 0, 0, none⟩] (some 0) = none := by decide

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
    ((windowOf ([⟨none, none, [.num [0]], 0, [], 0, 0, none⟩] ++ ramp 1) (some 4000)).getD []).map (·.rep) = [1, 1, 1, 1, 1] := by
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
    (byM .push 0 .discrete atRest [⟨some 9000, none, [.str "off"], 0, [], 0, 0, none⟩, ⟨some 9300, none, [.str "on"], 0, [], 0, 0, none⟩]
        [⟨some 9200, none, [.str "on"], 0, [], 0, 0, none⟩]).getD 9 (9, .skip .noSample) = (9, .pass) := by decide

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
    byStep .unit atRest [("s25", ⟨none, none, [.num [750]], 0, [], 0, 0, none⟩)] [] = [("s25", .skip .noSample)] := by decide

/-- A step is decided by that step's two samples only. -/
theorem byStep_pair :
    byStep .unit atRest [("s25", ⟨none, none, [.num [750]], 0, [], 0, 0, none⟩), ("s50", ⟨none, none, [.num [500]], 0, [], 0, 0, none⟩)]
      [("s25", ⟨none, none, [.num [1000]], 0, [], 0, 0, none⟩), ("s50", ⟨none, none, [.num [500]], 0, [], 0, 0, none⟩)] =
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

#guard (⟨none, none, [.absent, .str "a", .num [1, 2]], 0, [], 0, 0, none⟩ : Samp).form == [.absent, .str, .num 2]

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

/-- The strings of a strings window are its readings. -/
theorem strsOf_some_mem (w : List Val) (ss : List String) (h : strsOf w = some ss) (s : String) :
    s ∈ ss ↔ Val.str s ∈ w := by
  induction w generalizing ss with
  | nil => simp [strsOf] at h; subst h; simp
  | cons v rest ih =>
    cases v with
    | str t =>
      cases hr : strsOf rest with
      | none => simp [strsOf, hr] at h
      | some ts =>
        simp [strsOf, hr] at h; subst h; simp [ih ts hr]
    | absent => simp [strsOf] at h
    | num _ => simp [strsOf] at h

/-- A window has no strings exactly when one reading is not a string. -/
theorem strsOf_none_iff (w : List Val) : strsOf w = none ↔ ∃ v ∈ w, ∀ s, v ≠ .str s := by
  induction w with
  | nil => simp [strsOf]
  | cons v rest ih =>
    cases v with
    | str t => simp [strsOf, ih]
    | absent => simp [strsOf]
    | num xs => simp [strsOf]

/-- The numbers of a numbers window are its readings. -/
theorem numsOf_some_mem (w : List Val) (ns : List (List Int)) (h : numsOf w = some ns) (xs : List Int) :
    xs ∈ ns ↔ Val.num xs ∈ w := by
  induction w generalizing ns with
  | nil => simp [numsOf] at h; subst h; simp
  | cons v rest ih =>
    cases v with
    | num ys =>
      cases hr : numsOf rest with
      | none => simp [numsOf, hr] at h
      | some ts =>
        simp [numsOf, hr] at h; subst h; simp [ih ts hr]
    | absent => simp [numsOf] at h
    | str _ => simp [numsOf] at h

/-- A window has no numbers exactly when one reading is not numbers. -/
theorem numsOf_none_iff (w : List Val) : numsOf w = none ↔ ∃ v ∈ w, ∀ xs, v ≠ .num xs := by
  induction w with
  | nil => simp [numsOf]
  | cons v rest ih =>
    cases v with
    | num ys => simp [numsOf, ih]
    | absent => simp [numsOf]
    | str _ => simp [numsOf]

/-- Lists with the same members have the same least member. -/
theorem min?_congr (a b : List Int) (h : ∀ x, x ∈ a ↔ x ∈ b) : a.min? = b.min? := by
  cases ha : a.min? with
  | none =>
    have : a = [] := List.min?_eq_none_iff.mp ha
    subst this
    have : b = [] := List.eq_nil_iff_forall_not_mem.mpr fun x hx => by simpa using (h x).2 hx
    simp [this]
  | some m =>
    obtain ⟨h1, h2⟩ := List.min?_eq_some_iff.1 ha
    exact (List.min?_eq_some_iff.2 ⟨(h m).1 h1, fun y hy => h2 y ((h y).2 hy)⟩).symm

/-- Lists with the same members have the same greatest member. -/
theorem max?_congr (a b : List Int) (h : ∀ x, x ∈ a ↔ x ∈ b) : a.max? = b.max? := by
  cases ha : a.max? with
  | none =>
    have : a = [] := List.max?_eq_none_iff.mp ha
    subst this
    have : b = [] := List.eq_nil_iff_forall_not_mem.mpr fun x hx => by simpa using (h x).2 hx
    simp [this]
  | some m =>
    obtain ⟨h1, h2⟩ := List.max?_eq_some_iff.1 ha
    exact (List.max?_eq_some_iff.2 ⟨(h m).1 h1, fun y hy => h2 y ((h y).2 hy)⟩).symm

/-- A band depends on the window's members only. -/
theorem inBand_congr (t : Int) (a b : List (List Int)) (xs : List Int) (h : ∀ x, x ∈ a ↔ x ∈ b) :
    inBand t a xs = inBand t b xs := by
  unfold inBand
  congr 1
  funext j
  have hc : ∀ x, x ∈ a.map (·.getD j 0) ↔ x ∈ b.map (·.getD j 0) := by
    intro x; simp only [List.mem_map]; constructor
    · rintro ⟨y, hy, rfl⟩; exact ⟨y, (h y).1 hy, rfl⟩
    · rintro ⟨y, hy, rfl⟩; exact ⟨y, (h y).2 hy, rfl⟩
  simp only [min?_congr _ _ hc, max?_congr _ _ hc]

/-- `all` depends on the list's members only. -/
theorem all_congr_mem {α} (a b : List α) (h : ∀ x, x ∈ a ↔ x ∈ b) (p : α → Bool) : a.all p = b.all p :=
  Bool.eq_iff_iff.mpr (by simp only [List.all_eq_true, h])

/-- `any` depends on the list's members only. -/
theorem any_congr_mem {α} (a b : List α) (h : ∀ x, x ∈ a ↔ x ∈ b) (p : α → Bool) : a.any p = b.any p :=
  Bool.eq_iff_iff.mpr (by simp only [List.any_eq_true, h])

/-- Lists with the same members are both empty or both not. -/
theorem isEmpty_congr_mem {α} (a b : List α) (h : ∀ x, x ∈ a ↔ x ∈ b) : a.isEmpty = b.isEmpty := by
  cases a <;> cases b
  · rfl
  · rename_i y _; simpa using (h y).2 (List.mem_cons_self ..)
  · rename_i y _; simpa using (h y).1 (List.mem_cons_self ..)
  · rfl

/-- One element's verdict depends on the window's members only. -/
theorem judgeVal_congr (k : Kind) (a b : List Val) (r : Val) (h : ∀ x, x ∈ a ↔ x ∈ b) :
    judgeVal k a r = judgeVal k b r := by
  unfold judgeVal
  rw [isEmpty_congr_mem a b h]
  cases r with
  | absent => rw [all_congr_mem a b h]
  | str s =>
    rw [any_congr_mem a b h]
    cases ha : strsOf a <;> cases hb : strsOf b
    · rfl
    · obtain ⟨v, hv, hn⟩ := (strsOf_none_iff a).1 ha
      have := (strsOf_none_iff b).2 ⟨v, (h v).1 hv, hn⟩
      simp [this] at hb
    · obtain ⟨v, hv, hn⟩ := (strsOf_none_iff b).1 hb
      have := (strsOf_none_iff a).2 ⟨v, (h v).2 hv, hn⟩
      simp [this] at ha
    · rename_i ss ts
      have : ss.contains s = ts.contains s := Bool.eq_iff_iff.mpr (by
        simp only [List.contains_iff_mem, strsOf_some_mem a ss ha, strsOf_some_mem b ts hb, h])
      simp only [this]
  | num xs =>
    rw [any_congr_mem a b h]
    cases ha : numsOf a <;> cases hb : numsOf b
    · rfl
    · obtain ⟨v, hv, hn⟩ := (numsOf_none_iff a).1 ha
      have := (numsOf_none_iff b).2 ⟨v, (h v).1 hv, hn⟩
      simp [this] at hb
    · obtain ⟨v, hv, hn⟩ := (numsOf_none_iff b).1 hb
      have := (numsOf_none_iff a).2 ⟨v, (h v).2 hv, hn⟩
      simp [this] at ha
    · rename_i ss ts
      have hm : ∀ x, x ∈ ss ↔ x ∈ ts := fun x => by
        rw [numsOf_some_mem a ss ha, numsOf_some_mem b ts hb, h]
      have hc : ss.contains xs = ts.contains xs := Bool.eq_iff_iff.mpr (by
        simp only [List.contains_iff_mem, hm])
      simp only [any_congr_mem ss ts hm, hc, inBand_congr _ ss ts xs hm]

/-- A node's verdict depends on the window's members only. -/
theorem judgeEls_congr (k : Kind) (a b : List (List Val)) (r : List Val) (h : ∀ x, x ∈ a ↔ x ∈ b) :
    judgeEls k a r = judgeEls k b r := by
  unfold judgeEls
  rw [isEmpty_congr_mem a b h, any_congr_mem a b h]
  congr 3
  apply List.map_congr_left
  intro i _
  apply judgeVal_congr
  intro x; simp only [List.mem_map]; constructor
  · rintro ⟨y, hy, rfl⟩; exact ⟨y, (h y).1 hy, rfl⟩
  · rintro ⟨y, hy, rfl⟩; exact ⟨y, (h y).2 hy, rfl⟩

/-- Appending verdicts already in the list keeps the combined verdict. -/
theorem combine_append_sub (vs ws : List Verdict) (h : ∀ w ∈ ws, w ∈ vs) : combine (vs ++ ws) = combine vs := by
  unfold combine
  rw [List.find?_append]
  cases hf : vs.find? (fun v => match v with | .fail _ => true | _ => false) with
  | some f => rfl
  | none =>
    have hw : ws.find? (fun v => match v with | .fail _ => true | _ => false) = none := by
      rw [List.find?_eq_none] at hf ⊢
      exact fun w hw => hf w (h w hw)
    have : (vs ++ ws).any (· == .pass) = vs.any (· == .pass) :=
      any_congr_mem _ _ (fun x => by simp only [List.mem_append]; exact ⟨fun h' => h'.elim id (h x), Or.inl⟩) _
    simp only [Option.none_or, this]
    split
    · rename_i f hfw
      rw [List.find?_eq_none] at hw
      have := List.mem_of_find?_eq_some hfw
      have := List.find?_some hfw
      have := hw f (by assumption)
      contradiction
    · rfl

/-- Appending readings already in the list keeps `matchOne`'s verdict. -/
theorem matchOne_append_sub (k : Kind) (a b : List (List Val)) (r : List Val) (h : ∀ x ∈ b, x ∈ a) :
    matchOne k (a ++ b) r = matchOne k a r := by
  unfold matchOne
  simp only [List.map_append]
  have hs : ∀ w ∈ b.map (fun w => judgeEls k [w] r), w ∈ a.map (fun w => judgeEls k [w] r) := by
    intro w hw; simp only [List.mem_map] at hw ⊢; obtain ⟨x, hx, rfl⟩ := hw; exact ⟨x, h x hx, rfl⟩
  rw [combine_append_sub _ _ hs,
    any_congr_mem _ (a.map fun w => judgeEls k [w] r) (fun x => by
      simp only [List.mem_append]; exact ⟨fun h' => h'.elim id (hs x), Or.inl⟩)]

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

/-- `r` moved to its own pass is `r`. -/
theorem with_rep_self (r : Samp) : { r with rep := r.rep } = r := rfl

/-- A sample of the envelope is a sample of the window of `r`'s transition in the sample's own pass, and back. -/
theorem mem_envelope (seg : List Samp) (r x : Samp) :
    x ∈ envelope seg r ↔ x ∈ flightWindow seg { r with rep := x.rep } := by
  unfold envelope
  simp only [List.mem_flatMap]
  constructor
  · rintro ⟨q, _, hx⟩
    have hq := (flightWindow_sub seg _ x hx).2
    simp only at hq
    rw [hq]; exact hx
  · intro hx
    refine ⟨x.rep, ?_, hx⟩
    have := (flightWindow_sub seg _ x hx).1
    simp only [repsOf, List.mem_eraseDups, List.mem_map]
    exact ⟨x, this, rfl⟩

/-- The envelope holds only samples of the original. -/
theorem envelope_sub (seg : List Samp) (r x : Samp) (h : x ∈ envelope seg r) : x ∈ seg :=
  (flightWindow_sub seg _ x ((mem_envelope seg r x).1 h)).1

/-- A sample of the original with a `since` is in the envelope of its own transition. -/
theorem mem_envelope_self (seg : List Samp) (r : Samp) (hr : r ∈ seg) (hs : r.since.isSome) : r ∈ envelope seg r :=
  (mem_envelope seg r r).2 (mem_flightWindow_self seg r hr hs)

/-- On its own pass `isCoreIn` is `isCore`. -/
theorem isCoreIn_own (r o : Samp) (h : o.rep = r.rep) : isCoreIn r o = isCore r o := by
  unfold isCoreIn; rw [h]

/-- **(a) One rewrite sample, for any transition window.** A sample of the original, in its own window `w` and, when in
flight, in `fw` and its `core`, never fails when `fw`, `w` and the original share its form. -/
theorem judgeWith_self (k : Kind) (d : List String → Option Nat) (seg fw : List Samp) (core : Samp → Bool)
    (w : List Samp) (r : Samp) (hfw : inFlight d r = true → r ∈ fw ∧ core r = true) (hsub : ∀ x ∈ fw, x ∈ seg)
    (hrw : r ∈ w) (hw : ∀ x ∈ w, x ∈ seg) (hf : ∀ x ∈ seg, x.form = r.form) :
    isFail (judgeWith k d seg fw core (some w) r) = false := by
  unfold judgeWith
  split
  · rename_i hfl
    obtain ⟨hin, hc⟩ := hfw hfl
    have hne : fw.isEmpty = false := by
      cases h : fw with
      | nil => simp [h] at hin
      | cons _ _ => rfl
    have hsub : ∀ x ∈ fw, x.form = r.form := fun x hx => hf x (hsub x hx)
    simp only [hne, Bool.false_eq_true, ↓reduceIte]
    split
    · exact judgeColour_self _ _ r (List.mem_filter.mpr ⟨hin, hc⟩) hin hsub
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

/-- **(a) One unit.** A rewrite sample that is a sample of the original, in its own window `w` of samples of the original,
never fails, in flight or not, when every sample of the original shares its form. -/
theorem judgeUnit_self (k : Kind) (d : List String → Option Nat) (seg w : List Samp) (r : Samp) (hr : r ∈ seg)
    (hrw : r ∈ w) (hw : ∀ x ∈ w, x ∈ seg) (hf : ∀ x ∈ seg, x.form = r.form) :
    isFail (judgeUnit k d seg (some w) r) = false := by
  apply judgeWith_self k d seg _ _ w r _ (envelope_sub seg r) hrw hw hf
  intro hfl
  have hs : r.since.isSome := by
    obtain ⟨_, x, _, hx, _⟩ := (inFlight_iff d r).1 hfl
    simp [hx]
  exact ⟨mem_envelope_self seg r hr hs, by rw [isCoreIn_own r r rfl]; exact isCore_self r hs⟩

/-- A list of copies of `L`, one per member of a non-empty `qs`, has the members of `L`. -/
theorem mem_flatMap_const {α β} (qs : List α) (L : List β) (hq : qs ≠ []) (x : β) :
    x ∈ qs.flatMap (fun _ => L) ↔ x ∈ L := by
  cases qs with
  | nil => exact absurd rfl hq
  | cons q qs => simp only [List.mem_flatMap, List.mem_cons]; exact ⟨fun ⟨_, _, h⟩ => h, fun h => ⟨q, Or.inl rfl, h⟩⟩

/-- **The old rule as the agreeing case.** When every pass's window of `r`'s transition reads, sample for sample, the
readings and core of `r`'s own pass, the envelope judges `r` as its own pass does. -/
theorem judgeUnit_agree (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp)) (r : Samp)
    (h : ∀ q ∈ repsOf seg, (flightWindow seg { r with rep := q }).map (fun o => (o.els, isCoreIn r o)) =
      (flightWindow seg r).map (fun o => (o.els, isCoreIn r o))) :
    judgeUnit k d seg win r = judgeOwn k d seg win r := by
  let g : Samp → List Val × Bool := fun o => (o.els, isCoreIn r o)
  have hA : (envelope seg r).map g = (repsOf seg).flatMap (fun _ => (flightWindow seg r).map g) := by
    unfold envelope
    rw [List.map_flatMap]
    generalize repsOf seg = qs at h ⊢
    induction qs with
    | nil => rfl
    | cons q qs ih =>
      simp only [List.flatMap_cons]
      rw [h q (List.mem_cons_self ..), ih (fun q' h' => h q' (List.mem_cons_of_mem _ h'))]
  have hcore : ((flightWindow seg r).filter (isCore r)) = (flightWindow seg r).filter (isCoreIn r) :=
    List.filter_congr fun o ho => (isCoreIn_own r o (flightWindow_sub seg r o ho).2).symm
  have hview : ∀ (l : List Samp) (f : List Val → List Val),
      (l.filter (isCoreIn r)).map (fun s => f s.els) = ((l.map g).filter (·.2)).map (fun p => f p.1) := by
    intro l f
    simp only [List.filter_map, List.map_map]
    rfl
  have hels : ∀ (l : List Samp) (f : List Val → List Val), l.map (fun s => f s.els) = (l.map g).map (fun p => f p.1) := by
    intro l f; simp [g]
  unfold judgeUnit judgeOwn judgeWith
  by_cases hfl : inFlight d r
  · simp only [hfl, ↓reduceIte]
    by_cases hown : flightWindow seg r = []
    · have he : envelope seg r = [] := by
        have : (envelope seg r).map g = [] := by rw [hA, hown]; simp
        simpa using this
      simp [hown, he]
    · obtain ⟨o, ho⟩ := List.exists_mem_of_ne_nil _ hown
      have hq : repsOf seg ≠ [] := by
        intro hq
        have := (flightWindow_sub seg r o ho).1
        have h2 : o.rep ∈ repsOf seg := by simp only [repsOf, List.mem_eraseDups, List.mem_map]; exact ⟨o, this, rfl⟩
        simp [hq] at h2
      have hmem : ∀ x, x ∈ (envelope seg r).map g ↔ x ∈ (flightWindow seg r).map g := by
        intro x; rw [hA]; exact mem_flatMap_const _ _ hq x
      have he : envelope seg r ≠ [] := by
        intro he
        have := (hmem (g o)).2 (List.mem_map_of_mem ho)
        simp [he] at this
      have he1 : (envelope seg r).isEmpty = false := by simpa using he
      have he2 : (flightWindow seg r).isEmpty = false := by simpa using hown
      have hmapf : ∀ f : List Val → List Val, ∀ x,
          x ∈ (envelope seg r).map (fun s => f s.els) ↔ x ∈ (flightWindow seg r).map (fun s => f s.els) := by
        intro f x
        rw [hels, hels]
        constructor
        · intro hx; obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hx; exact List.mem_map.2 ⟨p, (hmem p).1 hp, rfl⟩
        · intro hx; obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hx; exact List.mem_map.2 ⟨p, (hmem p).2 hp, rfl⟩
      simp only [he1, he2, Bool.false_eq_true, ↓reduceIte]
      split
      · unfold judgeColour
        have ha : judgeEls .colour ((envelope seg r).map fun s => s.els.map Val.alpha) (r.els.map Val.alpha) =
            judgeEls .colour ((flightWindow seg r).map fun s => s.els.map Val.alpha) (r.els.map Val.alpha) :=
          judgeEls_congr _ _ _ _ (hmapf _)
        have hc : matchOne .colour (((envelope seg r).filter (isCoreIn r)).map fun s => s.els.map Val.chan)
              (r.els.map Val.chan) =
            matchOne .colour (((flightWindow seg r).filter (isCore r)).map fun s => s.els.map Val.chan)
              (r.els.map Val.chan) := by
          rw [hview, hcore, hview, hA]
          obtain ⟨q0, qs, hqs⟩ : ∃ q0 qs, repsOf seg = q0 :: qs := by
            cases hr : repsOf seg with
            | nil => exact absurd hr hq
            | cons q0 qs => exact ⟨q0, qs, rfl⟩
          rw [hqs, List.flatMap_cons, List.filter_append, List.map_append]
          apply matchOne_append_sub
          intro x hx
          obtain ⟨p, hp, rfl⟩ := List.mem_map.1 hx
          obtain ⟨hp1, hp2⟩ := List.mem_filter.1 hp
          obtain ⟨_, _, hp3⟩ := List.mem_flatMap.1 hp1
          exact List.mem_map.2 ⟨p, List.mem_filter.2 ⟨hp3, hp2⟩, rfl⟩
        rw [ha, hc]
      · rw [show (envelope seg r).map (·.els) = (envelope seg r).map (fun s => id s.els) from rfl,
          show (flightWindow seg r).map (·.els) = (flightWindow seg r).map (fun s => id s.els) from rfl]
        exact judgeEls_congr _ _ _ _ (hmapf id)
  · simp [hfl]

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

/-- The next hold's first row of pass `q` is a sample of the path, of pass `q`, in phase `p + 1`. -/
theorem headOf_mem (seg : List Samp) (q p : Nat) (h : Samp) (hh : headOf seg q p = some h) :
    h ∈ seg ∧ h.rep = q ∧ h.ph = p + 1 := by
  unfold headOf at hh
  have h1 := List.mem_of_find?_eq_some hh
  have h2 := List.find?_some hh
  simp only [Bool.and_eq_true, beq_iff_eq] at h2
  exact ⟨h1, h2.1, h2.2⟩

/-- Branch head: a settled value the push of pass `q` never sampled that the next hold's first row has is judged
against that row. -/
theorem windowPass_head (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) (q : Nat) (h : Samp) (hh : headOf seg q r.ph = some h)
    (hm : r.m.isSome) (hd : inFlight d r = false) (he : h.m = r.m) (hn : (passOf orig q).any (·.m == r.m) = false) :
    windowPass d seg orig r q = some [h] := by
  simp [windowPass, hh, hm, hd, he, hn]

/-- Branch sampled: a value the push of pass `q` sampled is aligned by `windowOne`. -/
theorem windowPass_sampled (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) (q : Nat) (hs : (passOf orig q).any (·.m == r.m) = true) :
    windowPass d seg orig r q = windowOne (passOf orig q) r.m := by
  unfold windowPass; split <;> simp [hs]

/-- Branch other value: a value the next hold's first row does not have is aligned by `windowOne`. -/
theorem windowPass_other (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) (q : Nat) (h : Samp) (hh : headOf seg q r.ph = some h)
    (he : h.m ≠ r.m) : windowPass d seg orig r q = windowOne (passOf orig q) r.m := by
  simp [windowPass, hh, he]

/-- Branch in flight: a value in flight is aligned by `windowOne`. -/
theorem windowPass_in_flight (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) (q : Nat) (hd : inFlight d r = true) :
    windowPass d seg orig r q = windowOne (passOf orig q) r.m := by
  unfold windowPass; split <;> simp [hd]

/-- Branch no hold: with no next hold in pass `q`, the value is aligned by `windowOne`. -/
theorem windowPass_no_head (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) (q : Nat) (hh : headOf seg q r.ph = none) :
    windowPass d seg orig r q = windowOne (passOf orig q) r.m := by
  simp [windowPass, hh]

/-- A hold keeps `windowOf`. -/
theorem windowAt_hold (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) : windowAt .hold d seg orig r = windowOf orig r.m := by
  simp [windowAt]

/-- **The old window as a case.** When no pass takes the head branch, a push's window is `windowOf`. -/
theorem windowAt_old (ph : Phase) (d : List String → Option Nat) (seg orig : List Samp) (r : Samp)
    (h : ∀ q ∈ repsOf orig, windowPass d seg orig r q = windowOne (passOf orig q) r.m) :
    windowAt ph d seg orig r = windowOf orig r.m := by
  unfold windowAt windowOf
  have hf : (repsOf orig).filterMap (windowPass d seg orig r) =
      (repsOf orig).filterMap (fun q => windowOne (passOf orig q) r.m) := by
    generalize repsOf orig = qs at h ⊢
    induction qs with
    | nil => rfl
    | cons q qs ih =>
      simp only [List.filterMap_cons]
      rw [h q (List.mem_cons_self ..), ih (fun q' h' => h q' (List.mem_cons_of_mem _ h'))]
  cases ph <;> simp [hf]

/-- A window holds only samples of the phase or of the path. -/
theorem windowAt_sub (ph : Phase) (d : List String → Option Nat) (seg orig : List Samp) (r x : Samp) (h : x ∈ (windowAt ph d seg orig r).getD []) :
    x ∈ orig ∨ x ∈ seg := by
  unfold windowAt at h
  cases ph with
  | hold =>
    left
    have := windowOne_sub _ _ _ ((windowOf_pass_iff orig r.m x).mp (by simpa using h))
    exact (List.mem_filter.mp this).1
  | push =>
    simp only [↓reduceIte, beq_self_eq_true] at h
    split at h
    · simp at h
    · simp only [Option.getD_some, List.mem_flatten] at h
      obtain ⟨w, hw, hxw⟩ := h
      obtain ⟨q, _, hq⟩ := List.mem_filterMap.mp hw
      unfold windowPass at hq
      split at hq
      · rename_i hd hhd
        split at hq
        · cases hq
          right
          exact (headOf_mem seg q r.ph hd hhd).1 |> fun h' => by simpa [List.mem_singleton.mp hxw] using h'
        · left
          have := windowOne_sub _ _ _ (by rw [hq]; exact hxw)
          exact (List.mem_filter.mp this).1
      · left
        have := windowOne_sub _ _ _ (by rw [hq]; exact hxw)
        exact (List.mem_filter.mp this).1

/-- A sample of a phase whose samples all have a morph value has a window, and is in it. -/
theorem windowAt_self (ph : Phase) (d : List String → Option Nat) (seg orig : List Samp) (r : Samp) (hr : r ∈ orig) (hm : ∀ s ∈ orig, s.m.isSome) :
    ∃ w, windowAt ph d seg orig r = some w ∧ r ∈ w := by
  cases ph with
  | hold => rw [windowAt_hold]; exact windowOf_self orig r hr hm
  | push =>
    have hp : r ∈ passOf orig r.rep := by simp [passOf, hr]
    have hs : (passOf orig r.rep).any (·.m == r.m) = true := List.any_eq_true.mpr ⟨r, hp, by simp⟩
    have h1 := windowOne_self (passOf orig r.rep) r hp
      (fun s hs' => hm s (by simp only [passOf, List.mem_filter] at hs'; exact hs'.1))
    obtain ⟨w, hw, hrw⟩ : ∃ w, windowOne (passOf orig r.rep) r.m = some w ∧ r ∈ w := by
      cases hw : windowOne (passOf orig r.rep) r.m with
      | none => simp [hw] at h1
      | some w => exact ⟨w, rfl, by simpa [hw] using h1⟩
    have hq : r.rep ∈ repsOf orig := by simp only [repsOf, List.mem_eraseDups, List.mem_map]; exact ⟨r, hr, rfl⟩
    have hin : w ∈ (repsOf orig).filterMap (windowPass d seg orig r) :=
      List.mem_filterMap.mpr ⟨r.rep, hq, by rw [windowPass_sampled d seg orig r r.rep hs, hw]⟩
    unfold windowAt
    simp only [beq_self_eq_true, ↓reduceIte]
    split
    · rename_i hn; rw [hn] at hin; simp at hin
    · exact ⟨_, rfl, List.mem_flatten.mpr ⟨w, hin, hrw⟩⟩

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
    obtain ⟨w, hw, hrw⟩ := windowAt_self ph d seg orig r hro hm
    rw [hw]
    apply judgeUnit_self k d seg w r (ho r hro) hrw
    · intro x hx
      have hx' : x ∈ (windowAt ph d seg orig r).getD [] := by simp [hw, hx]
      exact (windowAt_sub ph d seg orig r x hx').elim (ho x) id
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

/-- Branch in flight, no original sample in the transition in any pass, no counterpart: `fail coverage`. -/
theorem judgeUnit_flight_uncovered (k : Kind) (d : List String → Option Nat) (seg : List Samp) (r : Samp)
    (hfl : inFlight d r = true) (he : envelope seg r = []) : judgeUnit k d seg none r = .fail .coverage := by
  simp [judgeUnit, judgeWith, hfl, he]

/-- Branch in flight, no original sample in the transition in any pass: the rewrite sample is judged against `w`. -/
theorem judgeUnit_flight_fallback (k : Kind) (d : List String → Option Nat) (seg w : List Samp) (r : Samp)
    (hfl : inFlight d r = true) (he : envelope seg r = []) :
    judgeUnit k d seg (some w) r = judgeEls k (w.map (·.els)) r.els := by
  simp [judgeUnit, judgeWith, hfl, he]

/-- Branch in flight, a colour: the channels against the envelope's core, the alpha against the envelope. -/
theorem judgeUnit_flight_colour (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp)) (r : Samp)
    (hfl : inFlight d r = true) (hne : envelope seg r ≠ []) :
    judgeUnit .colour d seg win r = judgeColour ((envelope seg r).filter (isCoreIn r)) (envelope seg r) r := by
  have : (envelope seg r).isEmpty = false := by cases h : envelope seg r <;> simp_all
  simp [judgeUnit, judgeWith, hfl, this]

/-- Branch in flight, not a colour: the rewrite sample against the envelope of its transition. -/
theorem judgeUnit_flight_els (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (hk : k ≠ .colour) (hfl : inFlight d r = true) (hne : envelope seg r ≠ []) :
    judgeUnit k d seg win r = judgeEls k ((envelope seg r).map (·.els)) r.els := by
  have : (envelope seg r).isEmpty = false := by cases h : envelope seg r <;> simp_all
  simp [judgeUnit, judgeWith, hfl, this, hk]

/-- Branch at rest, no counterpart: `fail coverage`. -/
theorem judgeUnit_settled_uncovered (k : Kind) (d : List String → Option Nat) (seg : List Samp) (r : Samp)
    (hfl : inFlight d r = false) : judgeUnit k d seg none r = .fail .coverage := by
  simp [judgeUnit, judgeWith, hfl]

/-- **(b) A settled rewrite sample.** At rest, the rewrite sample is judged against the settled readings its window
stands for, whatever the original's samples are; `fail coverage` when the original never settled there. Each of those
readings is at rest (`settledRef_settled`) and is the window's sample or the end of its epoch (`settledRef_mem`). -/
theorem judgeUnit_settled (k : Kind) (d : List String → Option Nat) (seg w : List Samp) (r : Samp)
    (hfl : inFlight d r = false) :
    judgeUnit k d seg (some w) r =
      if (w.filterMap (settledRef d seg)).isEmpty then .fail .coverage
      else judgeEls k ((w.filterMap (settledRef d seg)).map (·.els)) r.els := by
  simp [judgeUnit, judgeWith, hfl]

/-- Branch at the start of the transition: `judgeScoped` is `judgeUnit`. -/
theorem judgeScoped_start (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (h : atStart seg r = true) : judgeScoped k d seg win r = judgeUnit k d seg win r := by
  simp [judgeScoped, h]

/-- Branch after the start of the transition: `judgeScoped` is `judgeOwn`. -/
theorem judgeScoped_later (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (h : atStart seg r = false) : judgeScoped k d seg win r = judgeOwn k d seg win r := by
  simp [judgeScoped, h]
/-- The transition of the nav's background at 1280 px, by class set. -/
def bgDur : List String → Option Nat := durOf "nav" "background-color" 1280

/-- The transition of the nav's visibility at 1280 px, by class set. -/
def visDur : List String → Option Nat := durOf "nav" "visibility" 1280

/-- **(b) on steps.** A settled rewrite reading pure red, then pure green, fails against a white the original reads in
flight at the first step and settled at the second. -/
theorem byStep_settled_red_green :
    byStep .colour bgDur
      [("a6", ⟨none, some 100, [.num [1000, 0, 0, 33340]], 0, [], 0, 0, none⟩),
        ("a7", ⟨none, some 5000, [.num [255000, 255000, 255000, 26000]], 0, [], 0, 0, none⟩)]
      [("a6", ⟨none, some 5000, [.num [255000, 0, 0, 100000]], 0, [], 0, 0, none⟩),
        ("a7", ⟨none, some 5100, [.num [0, 255000, 0, 26000]], 0, [], 0, 0, none⟩)] =
    [("a6", .fail .apart), ("a7", .fail .apart)] := by decide

/-- A settled rewrite reading the end value passes where the original was in flight. -/
theorem byStep_settled_end :
    byStep .colour bgDur
      [("a6", ⟨none, some 100, [.num [1000, 0, 0, 33340]], 0, [], 0, 0, none⟩),
        ("a7", ⟨none, some 5000, [.num [255000, 255000, 255000, 26000]], 0, [], 0, 0, none⟩)]
      [("a6", ⟨none, some 5000, [.num [255000, 255000, 255000, 26000]], 0, [], 0, 0, none⟩)] =
    [("a6", .pass), ("a7", .skip .noSample)] := by decide

/-- A settled rewrite step against an original that never settled in that epoch is `fail coverage`, never a pass. -/
theorem byStep_settled_unsettled :
    byStep .discrete visDur [("s2", ⟨none, some 100, [.str "visible"], 0, ["is-scroll-hidden"], 0, 0, none⟩)]
      [("s2", ⟨none, some 9000, [.str "hidden"], 0, ["is-scroll-hidden"], 0, 0, none⟩)] = [("s2", .fail .coverage)] := by
  decide

/-- The transition of the nav's box at 1280 px, by class set. -/
def rectDur : List String → Option Nat := durOf "nav" "rect" 1280

/-- A push of the nav's box in flight: the morph value `m` at `since` = `m` / 12.5 ms, the box `[0, 0, w, 64000]` with
`w` from 400 to 800 px. -/
def rectRamp (rev : Bool) : List Samp :=
  [0, 2000, 4000, 6000, 8000, 10000].map fun m =>
    ⟨some m, some (m / 25 * 2).toNat, [.num [0, 0, 400000 + 40 * (if rev then 10000 - m else m), 64000]], 0, [], 0, 0, none⟩

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

/-- **(c) in flight**, not a colour: beyond the samples of the transition in every pass of the original
(`mem_envelope`) fails. -/
theorem judgeUnit_flight_outside (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (i j : Nat) (xs : List Int) (hk : k ≠ .colour) (hfl : inFlight d r = true)
    (hne : envelope seg r ≠ []) (hi : i < r.els.length) (hr : r.els.getD i .absent = .num xs) (hj : j < xs.length)
    (ho : Outside (tol k) i j r.els.length xs.length (xs.getD j 0) ((envelope seg r).map (·.els))) :
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

/-- **(c) for a colour in flight, a channel**: red, green or blue outside the band of every core sample of every
pass fails. -/
theorem judgeUnit_colour_chan_outside (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (i j : Nat) (xs : List Int) (hfl : inFlight d r = true) (hc : ∃ o ∈ envelope seg r, isCoreIn r o)
    (hi : i < r.els.length) (hr : r.els.getD i .absent = .num xs) (hj : j < 3) (hjx : j < xs.length)
    (ho : Outside (tol .colour) i j r.els.length xs.length (xs.getD j 0)
      (((envelope seg r).filter (isCoreIn r)).map (·.els))) :
    isFail (judgeUnit .colour d seg win r) = true := by
  obtain ⟨o0, ho0, hc0⟩ := hc
  have hne : envelope seg r ≠ [] := by intro h; simp [h] at ho0
  rw [judgeUnit_flight_colour d seg win r hfl hne]
  unfold judgeColour
  apply combine_fail_of_mem
  refine ⟨_, List.mem_cons_self .., ?_⟩
  have htake : ∀ ys : List Int, (ys.take 3).getD j 0 = ys.getD j 0 := by
    intro ys; simp [List.getD_eq_getElem?_getD, hj]
  have hall : ∀ w ∈ ((envelope seg r).filter (isCoreIn r)).map fun s => s.els.map Val.chan,
      isFail (judgeEls .colour [w] (r.els.map Val.chan)) = true := by
    intro w hw
    simp only [List.mem_map] at hw
    obtain ⟨s, hs, rfl⟩ := hw
    have hs' : s.els ∈ ((envelope seg r).filter (isCoreIn r)).map (·.els) := List.mem_map_of_mem hs
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
  have hany : ((((envelope seg r).filter (isCoreIn r)).map fun s => s.els.map Val.chan).map
      fun w => judgeEls .colour [w] (r.els.map Val.chan)).any (fun v => !isFail v) = false := by
    rw [List.any_eq_false]
    intro v hv
    simp only [List.mem_map] at hv
    obtain ⟨w, hw, rfl⟩ := hv
    have := hall w (List.mem_map.mpr hw)
    simp [this]
  simp only [hany, Bool.false_eq_true, ↓reduceIte]
  apply combine_fail_of_mem
  have hcore : o0 ∈ (envelope seg r).filter (isCoreIn r) := List.mem_filter.mpr ⟨ho0, hc0⟩
  exact ⟨_, List.mem_map_of_mem (List.mem_map_of_mem hcore), hall _ (List.mem_map_of_mem hcore)⟩

/-- **(c) for a colour in flight, the alpha**: an alpha beyond the transition's samples in every pass fails. -/
theorem judgeUnit_colour_alpha_outside (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (i : Nat) (xs : List Int) (hfl : inFlight d r = true) (hne : envelope seg r ≠ [])
    (hi : i < r.els.length) (hr : r.els.getD i .absent = .num xs) (hx : 3 < xs.length)
    (ho : Outside (tol .colour) i 3 r.els.length xs.length (xs.getD 3 0) ((envelope seg r).map (·.els))) :
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

/-- `Outside` a window is `Outside` every part of it. -/
theorem Outside.sub {t : Int} {i j n len : Nat} {x : Int} {win win' : List (List Val)}
    (h : Outside t i j n len x win) (hs : ∀ w ∈ win', w ∈ win) : Outside t i j n len x win' := by
  refine ⟨fun w hw => h.1 w (hs w hw), ?_⟩
  rcases h.2 with h2 | h2
  · exact Or.inl fun w hw => h2 w (hs w hw)
  · exact Or.inr fun w hw => h2 w (hs w hw)

/-- `Outside` the readings of `seg` is `Outside` the readings of any samples of `seg`. -/
theorem Outside.samps {t : Int} {i j n len : Nat} {x : Int} {seg : List Samp}
    (h : Outside t i j n len x (seg.map (·.els))) (L : List Samp) (hL : ∀ s ∈ L, s ∈ seg) :
    Outside t i j n len x (L.map (·.els)) :=
  h.sub fun w hw => by
    obtain ⟨s, hs, rfl⟩ := List.mem_map.mp hw
    exact List.mem_map_of_mem (hL s hs)

/-- A component `Outside` the window never passes; an empty window is a skip. -/
theorem judgeEls_outside_not_pass (k : Kind) (win : List (List Val)) (r : List Val) (i j : Nat) (xs : List Int)
    (hi : i < r.length) (hr : r.getD i .absent = .num xs) (hj : j < xs.length)
    (ho : Outside (tol k) i j r.length xs.length (xs.getD j 0) win) : judgeEls k win r ≠ .pass := by
  cases win with
  | nil => simp [judgeEls]
  | cons w ws =>
    have := judgeEls_outside k (w :: ws) r i j xs hi hr hj (by simp) ho
    intro h; rw [h] at this; simp [isFail] at this

/-- A core sample of `r`'s pass is in the window of `r`'s transition. -/
theorem mem_flightWindow_core (seg : List Samp) (r o : Samp) (ho : o ∈ seg) (hrep : o.rep = r.rep)
    (hc : isCore r o = true) : o ∈ flightWindow seg r := by
  have hp : o ∈ passOf seg r.rep := by simp [passOf, ho, hrep]
  obtain ⟨i, hi, hpi⟩ := List.mem_iff_getElem.mp hp
  have hcore : i ∈ (List.range (passOf seg r.rep).length).filter
      (fun i => ((passOf seg r.rep)[i]?.map (isCore r)).getD false) := by
    simp [hi, hpi, hc]
  have hep : inEpoch r o = true := by simp only [isCore, Bool.and_eq_true] at hc; exact hc.1.1
  unfold flightWindow
  simp only
  split
  · rename_i he
    exact absurd hcore (by rw [List.isEmpty_iff.mp he]; simp)
  · simp only [List.mem_filterMap, List.mem_range]
    refine ⟨i, hi, ?_⟩
    simp only [List.getElem?_eq_getElem hi, hpi, Option.bind_some]
    split
    · rfl
    · rename_i hn
      refine absurd ?_ hn
      rw [Bool.or_eq_true]; right
      simp only [hep, Bool.true_and, Bool.and_eq_true, List.any_eq_true, decide_eq_true_eq]
      exact ⟨⟨i, hcore, Nat.le_refl _⟩, ⟨i, hcore, Nat.le_succ _⟩⟩

/-- A non-empty transition window has a core sample. -/
theorem flightWindow_core (seg : List Samp) (r : Samp) (hne : flightWindow seg r ≠ []) :
    ∃ o ∈ flightWindow seg r, isCore r o = true := by
  unfold flightWindow at hne
  simp only at hne
  split at hne
  · exact absurd rfl hne
  · rename_i hce
    obtain ⟨c, hcl, hcc⟩ : ∃ x, x < (passOf seg r.rep).length ∧
        (Option.map (isCore r) (passOf seg r.rep)[x]?).getD false = true := by simpa using hce
    rw [List.getElem?_eq_getElem hcl] at hcc
    simp only [Option.map_some, Option.getD_some] at hcc
    have hm := List.getElem_mem hcl
    simp only [passOf, List.mem_filter, beq_iff_eq] at hm
    exact ⟨_, mem_flightWindow_core seg r _ hm.1 hm.2 hcc, hcc⟩

/-- A non-empty envelope has a core sample in its own pass. -/
theorem envelope_core (seg : List Samp) (r : Samp) (hne : envelope seg r ≠ []) :
    ∃ o ∈ envelope seg r, isCoreIn r o = true := by
  obtain ⟨x, hx⟩ := List.exists_mem_of_ne_nil _ hne
  have hx' := (mem_envelope seg r x).1 hx
  obtain ⟨o, ho, hc⟩ := flightWindow_core seg _ (List.ne_nil_of_mem hx')
  have hrep : o.rep = x.rep := (flightWindow_sub seg _ o ho).2
  refine ⟨o, (mem_envelope seg r o).2 (by rw [hrep]; exact ho), ?_⟩
  unfold isCoreIn; rw [hrep]; exact hc

/-- **Soundness.** A component more than the tolerance beyond every reading of the original's whole path `seg` never
passes, when the window `win` holds samples of `seg` (as `windowAt` does, `windowAt_sub`); for a colour, a channel or
the alpha. -/
theorem judgeUnit_sound (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (r : Samp) (i j : Nat) (xs : List Int) (hk : k = .colour → j ≤ 3) (hw : ∀ w, win = some w → ∀ x ∈ w, x ∈ seg)
    (hi : i < r.els.length) (hr : r.els.getD i .absent = .num xs) (hj : j < xs.length)
    (ho : Outside (tol k) i j r.els.length xs.length (xs.getD j 0) (seg.map (·.els))) :
    judgeUnit k d seg win r ≠ .pass := by
  have hnp : ∀ v, isFail v = true → v ≠ .pass := by intro v h e; subst e; simp [isFail] at h
  cases hfl : inFlight d r
  · cases win with
    | none => rw [judgeUnit_settled_uncovered k d seg r hfl]; simp
    | some w =>
      by_cases he : w.filterMap (settledRef d seg) = []
      · rw [judgeUnit_settled k d seg w r hfl]; simp [he]
      · refine hnp _ (judgeUnit_settled_outside k d seg w r i j xs hfl he hi hr hj (ho.samps _ ?_))
        intro s hs
        obtain ⟨w0, hw0, he0⟩ := List.mem_filterMap.mp hs
        rcases settledRef_mem d seg w0 s he0 with rfl | ⟨h, _⟩
        · exact hw w rfl _ hw0
        · exact h
  · by_cases he : envelope seg r = []
    · cases win with
      | none => rw [judgeUnit_flight_uncovered k d seg r hfl he]; simp
      | some w =>
        rw [judgeUnit_flight_fallback k d seg w r hfl he]
        exact judgeEls_outside_not_pass k _ r.els i j xs hi hr hj (ho.samps w (hw w rfl))
    · by_cases hc : k = .colour
      · subst hc
        rcases Nat.lt_or_eq_of_le (hk rfl) with hj3 | hj3
        · exact hnp _ (judgeUnit_colour_chan_outside d seg win r i j xs hfl (envelope_core seg r he) hi hr hj3 hj
            (ho.samps _ fun s hs => envelope_sub seg r s (List.mem_filter.mp hs).1))
        · subst hj3
          exact hnp _ (judgeUnit_colour_alpha_outside d seg win r i xs hfl he hi hr hj
            (ho.samps _ (envelope_sub seg r)))
      · exact hnp _ (judgeUnit_flight_outside k d seg win r i j xs hc hfl he hi hr hj (ho.samps _ (envelope_sub seg r)))

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

section CloseStart
open Fw.Parts

/-! ## The earn button at the end of a close -/

/-- The timing curve of every earn transition, `cubic-bezier(0.33, 0, 0.2, 1)` (`nav.module.css` rule 167). -/
def earnCurve : Bezier.Bez := ⟨33 / 100, 0, 1 / 5, 1⟩

/-- The (node, property) units the close rule judges. -/
def startOn (node prop : String) : Bool := node == "earn" && (prop == "opacity" || prop == "max-width")

/-- The (duration, delay) in ms of the transition that moves a probe property under a class set, `driver` included. -/
def startTr (node prop : String) (width : Nat) (cls : List String) : Option (Nat × Nat) :=
  ((transitionsOf node width cls).find? fun (p, _, _) => (cssOf node prop).contains p).map fun (_, d, l) => (d, l)

/-- The earn button's value at rest past the hero, times 1000: opacity `Nav.expand false`, max-width `Nav.earnMaxW` at
morph value 0 (`Nav.lean` 266-269, 274; snapshot CSS 11480, 11483, 11485, 11594-11596). -/
def fullOf (prop : String) (width : Nat) : Rat :=
  if prop == "opacity" then Nav.expand false * 1000 else Nav.earnMaxW ⟨width, 0⟩ false 0 * 1000

/-- The close rule of an earn unit at one width: the transition under a class set, and the value at rest. -/
structure EarnRule where
  tr : List String → Option (Nat × Nat)
  full : Rat

/-- The close rule of a (node, property) at a width: for the units of `startOn`, `startTr` and `fullOf`; else none. -/
def startFor (node prop : String) (width : Nat) : Option EarnRule :=
  if startOn node prop then some ⟨startTr node prop width, fullOf prop width⟩ else none

/-- The index of the close in the morph path (`PHASES` in `reduce.mjs`). -/
def closePh : Nat := 2

/-- Ms a transition's clock may run off the difference of two read times (MEASURED, `trajectory-probe.md`). -/
def startJitter : Nat := 80

/-- The earn collapse `--earn-out` at morph value `m` times 10000. -/
def collapse (m : Int) : Rat := Nav.earnOut ((m : Rat) / 10000)

/-- The value `x` ms after its trigger of an earn transition from `s` to `t`. -/
def along (dur delay : Nat) (s t : Rat) (x : Int) : Rat :=
  s + (t - s) * Bezier.ease earnCurve (((x : Rat) - delay) / dur)

/-- The number of a reading of one element with one number. -/
def oneNum : List Val → Option Int
  | [.num [x]] => some x
  | _ => none

/-- Two neighbouring samples differ in their earn collapse. -/
def retargets (a b : Samp) : Bool :=
  match a.m, b.m with
  | some x, some y => collapse x != collapse y
  | _, _ => false

/-- The triggers of `ps`: each sample whose collapse differs from the one before. -/
def triggersOf (ps : List Samp) : List Samp :=
  ((ps.zip ps.tail).filter fun (a, b) => retargets a b).map (·.2)

/-- The original's first trigger in the pass and phase of `r`. -/
def origFirst (seg : List Samp) (r : Samp) : Option Samp :=
  (triggersOf ((passOf seg r.rep).filter (·.ph == r.ph))).head?

/-- How far `w` lies outside `[lo, hi]`; 0 inside. -/
def excess (lo hi : Rat) (w : Int) : Rat :=
  if (w : Rat) < lo then lo - w else if hi < w then w - hi else 0

/-- Rewrite sample `r` of the close's bucket 0 after the earlier samples `prior` of its pass. Anchor: the reading `w` at
the pass's first trigger lies within `tol k` of `s`, the reading at the original's first trigger. Range: `r`'s reading
lies in `[s - tol k, full + tol k]`. `none`: no trigger up to `r`, no original trigger, or a reading that is not one
number. -/
def startCheck (k : Kind) (full : Rat) (seg prior : List Samp) (r : Samp) : Option Bool :=
  match (triggersOf (prior ++ [r])).head?, origFirst seg r with
  | some q, some o =>
    match oneNum o.els, oneNum q.els, oneNum r.els with
    | some s, some w, some x => some (decide (excess s s w ≤ tol k) && decide (excess s full x ≤ tol k))
    | _, _, _ => none
  | _, _ => none

/-- One rewrite sample of the close's bucket 0: `startCheck` when it decides, else `judgeUnit`. -/
def judgeStart (k : Kind) (d : List String → Option Nat) (full : Rat) (seg : List Samp) (win : Option (List Samp))
    (prior : List Samp) (r : Samp) : Verdict :=
  match startCheck k full seg prior r with
  | some true => .pass
  | some false => .fail .apart
  | none => judgeUnit k d seg win r

/-- Bucket 0 of a push, each rewrite sample by `judgeStart` with its pass's earlier samples of the phase. -/
def startBucket (k : Kind) (d : List String → Option Nat) (full : Rat) (seg orig rew : List Samp) : Verdict :=
  match (rew.mapIdx fun i r => (passOf (rew.take i) r.rep, r)).filter (fun x => bucket x.2.m == 0) with
  | [] => .skip .noSample
  | rs => combine (rs.map fun (ps, r) => judgeStart k d full seg (windowAt .push d seg orig r) ps r)

/-- The samples of `r`'s pass in the close and the close-hold, in order. -/
def closeOf (seg : List Samp) (r : Samp) : List Samp :=
  (passOf seg r.rep).filter fun s => s.ph == closePh || s.ph == closePh + 1

/-- The ms after a trigger from which its transition `(dur, delay)` has ended, with `startJitter` to spare. -/
def settleAt (dur delay : Nat) : Nat := dur + delay + startJitter

/-- Rewrite sample `r` of the close-hold, `seg` the rewrite's path: read `settleAt` or more ms after the last trigger of
its pass's close and close-hold, it lies within `tol k` of `e.full`. `none`: read earlier, or a part missing. -/
def settleCheck (k : Kind) (e : EarnRule) (seg : List Samp) (r : Samp) : Option Bool :=
  match (triggersOf (closeOf seg r)).getLast? with
  | some q =>
    match e.tr q.cls, q.t0, r.t0, oneNum r.els with
    | some (dur, delay), some a, some b, some x =>
      if (settleAt dur delay : Int) ≤ (b : Int) - a then some (decide (excess e.full e.full x ≤ tol k)) else none
    | _, _, _, _ => none
  | none => none

/-- A bucket's `byM` verdict `v` with the settle checks `cs` of its samples: `fail apart` when `v` passes and a check
refuses, else `v`. -/
def settleAnd (v : Verdict) (cs : List (Option Bool)) : Verdict :=
  if v == .pass && cs.contains (some false) then .fail .apart else v

/-- Bucket `x` of phase `p` with `settleAnd` over the settle checks of the rewrite samples `ws` in it. -/
def settleBucket (k : Kind) (e : EarnRule) (ws : List Samp) (p : Nat) (x : Nat × Verdict) : Nat × Verdict :=
  (x.1, settleAnd x.2 (((ws.filter (·.ph == p)).filter fun r => bucket r.m == x.1).map (settleCheck k e ws)))

/-- `byM`, with the rule `e` of an earn unit: bucket 0 of the close by `startBucket`, each bucket of the close-hold by
`settleBucket`. -/
def byMStart (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (e : Option EarnRule)
    (oSeg wSeg : List Samp) : List (Nat × Verdict) :=
  match e with
  | some e =>
    if ph == .push && p == closePh then
      let seg := annotate oSeg
      (byM ph p k d oSeg wSeg).map fun (b, v) =>
        if b == 0 then (b, startBucket k d e.full seg (seg.filter (·.ph == p)) ((annotate wSeg).filter (·.ph == p)))
        else (b, v)
    else if ph == .hold && p == closePh + 1 then
      (byM ph p k d oSeg wSeg).map (settleBucket k e (annotate wSeg) p)
    else byM ph p k d oSeg wSeg
  | none => byM ph p k d oSeg wSeg

#guard startOn "earn" "opacity" && startOn "earn" "max-width" && !startOn "earn" "padding-inline" &&
  !startOn "nav" "opacity"
#guard startTr "earn" "opacity" 390 [] == some (320, 120) && startTr "earn" "opacity" 390 ["is-hero-pill"] == some (200, 0) &&
  startTr "earn" "max-width" 1280 ["is-morphing"] == some (680, 0) && startTr "nav" "rect" 1280 ["is-morphing"] == some (320, 0) &&
  startTr "earn" "gap" 390 [] == none
#guard fullOf "opacity" 390 == 1000 && fullOf "max-width" 390 == 152000 && fullOf "max-width" 640 == 152000 &&
  fullOf "max-width" 641 == 176000 && fullOf "max-width" 1280 == 176000
#guard (startFor "earn" "opacity" 390).map (·.full) == some 1000 && (startFor "nav" "opacity" 390).isNone
#guard collapse 0 == 0 && collapse 1000 == 1 / 2 && collapse 2000 == 1 && collapse 9000 == 1
#guard oneNum [.num [5]] == some 5 && oneNum [.num [5, 6]] == none && oneNum [] == none && oneNum [.str "a"] == none
#guard along 320 120 0 1000 100 == 0 && along 320 120 0 1000 440 == 1000 && along 680 0 1000 0 680 == 0

/-- An earn close sample of pass 0 at morph value `m` reading `x`, its reads started at `t` ms. -/
def ec (m : Int) (t : Nat) (x : Int) : Samp := ⟨some m, none, [.num [x]], 0, [], 2, 0, some t⟩

/-- An earn close-hold sample of pass 0 reading `x`, its reads started at `t` ms. -/
def eh (t : Nat) (x : Int) : Samp := ⟨some 0, none, [.num [x]], 0, [], 3, 0, some t⟩

#guard retargets (ec 3000 0 0) (ec 2500 0 0) == false && retargets (ec 2500 0 0) (ec 1500 0 0) &&
  retargets (ec 0 0 0) (s0 []) == false
#guard triggersOf [ec 6540 0 0, ec 1230 100 0, ec 0 200 5, ec 0 300 6] == [ec 1230 100 0, ec 0 200 5] &&
  triggersOf [ec 6540 0 0, ec 3000 100 0] == [] && triggersOf [] == []
#guard origFirst [ec 6540 0 0, ec 1230 100 4, ec 0 200 5] (ec 0 0 0) == some (ec 1230 100 4) &&
  origFirst [ec 6540 0 0, ec 3000 100 4] (ec 0 0 0) == none
#guard excess 0 10 5 == 0 && excess 0 10 (-3) == 3 && excess 0 10 14 == 4 && excess 7 7 7 == 0 && excess 7 7 16 == 9
#guard settleAt 320 120 == 520 && settleAt 680 0 == 760
#guard closeOf [ec 6540 0 0, eh 900 1000, ⟨some 0, none, [], 0, [], 4, 0, none⟩, ⟨some 0, none, [], 1, [], 3, 0, none⟩]
    (eh 0 0) == [ec 6540 0 0, eh 900 1000]

/-- The earn opacity rule at 390 px. -/
def eo : EarnRule := ⟨startTr "earn" "opacity" 390, 1000⟩

#guard startCheck .unit 1000 [ec 6540 0 0, ec 0 100 0] [ec 6540 0 0, ec 0 100 0] (ec 0 400 852) == some true &&
  startCheck .unit 1000 [ec 6540 0 0, ec 0 100 0] [ec 6540 0 0] (ec 0 100 11) == some false &&
  startCheck .unit 1000 [ec 6540 0 0, ec 0 100 0] [ec 6540 0 0, ec 0 100 0] (ec 0 400 1011) == some false &&
  startCheck .unit 1000 [ec 6540 0 0, ec 0 100 600] [ec 6540 0 0, ec 0 100 600] (ec 0 400 591) == some true &&
  startCheck .unit 1000 [ec 6540 0 0, ec 0 100 600] [ec 6540 0 0, ec 0 100 600] (ec 0 400 589) == some false &&
  startCheck .unit 1000 [ec 6540 0 0, ec 0 100 0] [ec 6540 0 0] (ec 6540 50 0) == none &&
  startCheck .unit 1000 [] [ec 6540 0 0, ec 0 100 0] (ec 0 400 852) == none
#guard settleCheck .unit eo [ec 6540 0 0, ec 0 100 0, eh 620 990] (eh 620 990) == some true &&
  settleCheck .unit eo [ec 6540 0 0, ec 0 100 0, eh 620 989] (eh 620 989) == some false &&
  settleCheck .unit eo [ec 6540 0 0, ec 0 100 0, eh 619 900] (eh 619 900) == none &&
  settleCheck .unit eo [ec 6540 0 0, ec 0 100 0, ec 1000 200 0, ec 0 300 0, eh 700 900] (eh 700 900) == none &&
  settleCheck .unit eo [ec 6540 0 0, ec 0 100 0, ec 1000 200 0, ec 0 300 0, eh 820 900] (eh 820 900) == some false &&
  settleCheck .unit eo [ec 0 0 0, eh 900 900] (eh 900 900) == none
#guard settleAnd .pass [some true, none] == .pass && settleAnd .pass [some true, some false] == .fail .apart &&
  settleAnd (.fail .count) [some false] == .fail .count && settleAnd (.skip .noSample) [] == .skip .noSample

/-- `excess` is never negative. -/
theorem excess_nonneg (lo hi : Rat) (w : Int) : 0 ≤ excess lo hi w := by
  unfold excess
  split
  · grind
  · split <;> grind

/-- For `lo ≤ hi` and `0 ≤ t`, `excess` is at most `t` exactly when `w` lies in `[lo - t, hi + t]`. -/
theorem excess_le_iff (lo hi t : Rat) (w : Int) (hl : lo ≤ hi) (ht : 0 ≤ t) :
    excess lo hi w ≤ t ↔ lo - t ≤ w ∧ (w : Rat) ≤ hi + t := by
  unfold excess
  split
  · grind
  · split <;> grind

/-- A reading inside `[lo, hi]` has no excess. -/
theorem excess_zero (lo hi : Rat) (w : Int) (h1 : lo ≤ w) (h2 : (w : Rat) ≤ hi) : excess lo hi w = 0 := by
  unfold excess
  split
  · grind
  · split <;> grind

/-- Branch opacity of `startOn`. -/
theorem startOn_opacity : startOn "earn" "opacity" = true := by decide

/-- Branch max-width of `startOn`. -/
theorem startOn_maxWidth : startOn "earn" "max-width" = true := by decide

/-- Off `startOn` the rule is off. -/
theorem startFor_off (node prop : String) (width : Nat) (h : startOn node prop = false) :
    startFor node prop width = none := by
  simp [startFor, h]

/-- The earn opacity at rest is 1. -/
theorem fullOf_opacity (width : Nat) : fullOf "opacity" width = 1000 := by
  simp [fullOf, Nav.expand]

/-- The earn max-width at rest on a phone is 9.5rem, 152 px. -/
theorem fullOf_phone (width : Nat) (h : width ≤ 640) : fullOf "max-width" width = 152000 := by
  have hp : Nav.phone (width : Rat) = true := by simp [Nav.phone]; exact_mod_cast h
  simp [fullOf, Nav.earnMaxW, Nav.earnLayout, Nav.earnOut, Nav.expand, hp, MorphTween.clamp01]
  decide +kernel

/-- The earn max-width at rest above a phone is 11rem, 176 px. -/
theorem fullOf_wide (width : Nat) (h : 640 < width) : fullOf "max-width" width = 176000 := by
  have hp : Nav.phone (width : Rat) = false := by
    have : ¬ (width : Rat) ≤ 640 := by exact_mod_cast Nat.not_le.mpr h
    simpa [Nav.phone] using this
  simp [fullOf, Nav.earnMaxW, Nav.earnLayout, Nav.earnOut, Nav.expand, hp, MorphTween.clamp01]
  decide +kernel

/-- With every part found, `startCheck` is the anchor and the range. -/
theorem startCheck_found (k : Kind) (full : Rat) (seg prior : List Samp) (r q o : Samp) (s w x : Int)
    (hq : (triggersOf (prior ++ [r])).head? = some q) (ho : origFirst seg r = some o) (hs : oneNum o.els = some s)
    (hw : oneNum q.els = some w) (hx : oneNum r.els = some x) :
    startCheck k full seg prior r = some (decide (excess s s w ≤ tol k) && decide (excess s full x ≤ tol k)) := by
  simp [startCheck, hq, ho, hs, hw, hx]

/-- Branch no trigger: before its pass's first trigger a sample is undecided. -/
theorem startCheck_no_trigger (k : Kind) (full : Rat) (seg prior : List Samp) (r : Samp)
    (hq : (triggersOf (prior ++ [r])).head? = none) : startCheck k full seg prior r = none := by
  simp [startCheck, hq]

/-- Branch no original trigger: a pass whose original never retargets is undecided. -/
theorem startCheck_no_orig (k : Kind) (full : Rat) (seg prior : List Samp) (r : Samp) (ho : origFirst seg r = none) :
    startCheck k full seg prior r = none := by
  unfold startCheck
  split <;> simp_all

/-- Branch no reading: a reading that is not one number leaves a sample undecided. -/
theorem startCheck_no_reading (k : Kind) (full : Rat) (seg prior : List Samp) (r q o : Samp)
    (hq : (triggersOf (prior ++ [r])).head? = some q) (ho : origFirst seg r = some o)
    (h : oneNum o.els = none ∨ oneNum q.els = none ∨ oneNum r.els = none) : startCheck k full seg prior r = none := by
  rcases h with h | h | h <;> simp only [startCheck, hq, ho, h] <;> split <;> simp_all

/-- With every part found and `s ≤ full`, a sample passes exactly when the trigger reads within `tol k` of `s` and the
sample reads in `[s - tol k, full + tol k]`. -/
theorem startCheck_pass_iff (k : Kind) (full : Rat) (seg prior : List Samp) (r q o : Samp) (s w x : Int)
    (hq : (triggersOf (prior ++ [r])).head? = some q) (ho : origFirst seg r = some o) (hs : oneNum o.els = some s)
    (hw : oneNum q.els = some w) (hx : oneNum r.els = some x) (hsf : (s : Rat) ≤ full) :
    startCheck k full seg prior r = some true ↔
      (s - tol k ≤ w ∧ w ≤ s + tol k) ∧ ((s : Rat) - tol k ≤ x ∧ (x : Rat) ≤ full + tol k) := by
  have ht : (0 : Rat) ≤ tol k := by exact_mod_cast tol_nonneg k
  rw [startCheck_found k full seg prior r q o s w x hq ho hs hw hx]
  simp only [Option.some.injEq, Bool.and_eq_true, decide_eq_true_eq]
  rw [excess_le_iff _ _ _ _ (Rat.le_refl) ht, excess_le_iff _ _ _ _ hsf ht]
  constructor
  · intro ⟨⟨a, b⟩, c⟩
    exact ⟨⟨by exact_mod_cast a, by exact_mod_cast b⟩, c⟩
  · intro ⟨⟨a, b⟩, c⟩
    have a' : ((s - tol k : Int) : Rat) ≤ w := by exact_mod_cast a
    have b' : (w : Rat) ≤ ((s + tol k : Int) : Rat) := by exact_mod_cast b
    push_cast at a' b'
    exact ⟨⟨a', b'⟩, c⟩

/-- Branch on: a sample the check passes passes. -/
theorem judgeStart_on (k : Kind) (d : List String → Option Nat) (full : Rat) (seg : List Samp)
    (win : Option (List Samp)) (prior : List Samp) (r : Samp) (h : startCheck k full seg prior r = some true) :
    judgeStart k d full seg win prior r = .pass := by
  simp [judgeStart, h]

/-- Branch off: a sample the check refuses is `fail apart`, whatever the window says. -/
theorem judgeStart_off (k : Kind) (d : List String → Option Nat) (full : Rat) (seg : List Samp)
    (win : Option (List Samp)) (prior : List Samp) (r : Samp) (h : startCheck k full seg prior r = some false) :
    judgeStart k d full seg win prior r = .fail .apart := by
  simp [judgeStart, h]

/-- Branch undecided: the current judge decides a sample the check does not. -/
theorem judgeStart_undecided (k : Kind) (d : List String → Option Nat) (full : Rat) (seg : List Samp)
    (win : Option (List Samp)) (prior : List Samp) (r : Samp) (h : startCheck k full seg prior r = none) :
    judgeStart k d full seg win prior r = judgeUnit k d seg win r := by
  simp [judgeStart, h]

/-- With every part found and read `settleAt` or more ms after the last trigger, `settleCheck` compares with `e.full`. -/
theorem settleCheck_found (k : Kind) (e : EarnRule) (seg : List Samp) (r q : Samp) (dur delay a b : Nat) (x : Int)
    (hq : (triggersOf (closeOf seg r)).getLast? = some q) (htr : e.tr q.cls = some (dur, delay))
    (ha : q.t0 = some a) (hb : r.t0 = some b) (hx : oneNum r.els = some x)
    (hl : (settleAt dur delay : Int) ≤ (b : Int) - a) :
    settleCheck k e seg r = some (decide (excess e.full e.full x ≤ tol k)) := by
  simp [settleCheck, hq, htr, ha, hb, hx, hl]

/-- Branch early: a sample read before `settleAt` ms after the last trigger is undecided. -/
theorem settleCheck_early (k : Kind) (e : EarnRule) (seg : List Samp) (r q : Samp) (dur delay a b : Nat) (x : Int)
    (hq : (triggersOf (closeOf seg r)).getLast? = some q) (htr : e.tr q.cls = some (dur, delay))
    (ha : q.t0 = some a) (hb : r.t0 = some b) (hx : oneNum r.els = some x)
    (hl : (b : Int) - a < settleAt dur delay) : settleCheck k e seg r = none := by
  have : ¬ ((settleAt dur delay : Int) ≤ (b : Int) - a) := by omega
  simp [settleCheck, hq, htr, ha, hb, hx, this]

/-- Branch no trigger: a pass whose close never retargets is undecided. -/
theorem settleCheck_no_trigger (k : Kind) (e : EarnRule) (seg : List Samp) (r : Samp)
    (hq : (triggersOf (closeOf seg r)).getLast? = none) : settleCheck k e seg r = none := by
  simp [settleCheck, hq]

/-- Branch missing part: no transition, no read time or a reading that is not one number leaves a sample undecided. -/
theorem settleCheck_no_part (k : Kind) (e : EarnRule) (seg : List Samp) (r q : Samp)
    (hq : (triggersOf (closeOf seg r)).getLast? = some q)
    (h : e.tr q.cls = none ∨ q.t0 = none ∨ r.t0 = none ∨ oneNum r.els = none) : settleCheck k e seg r = none := by
  rcases h with h | h | h | h <;> simp only [settleCheck, hq, h] <;> split <;> simp_all

/-- With every part found and read late enough, a sample passes exactly when it reads within `tol k` of `e.full`. -/
theorem settleCheck_pass_iff (k : Kind) (e : EarnRule) (seg : List Samp) (r q : Samp) (dur delay a b : Nat) (x : Int)
    (hq : (triggersOf (closeOf seg r)).getLast? = some q) (htr : e.tr q.cls = some (dur, delay))
    (ha : q.t0 = some a) (hb : r.t0 = some b) (hx : oneNum r.els = some x)
    (hl : (settleAt dur delay : Int) ≤ (b : Int) - a) :
    settleCheck k e seg r = some true ↔ e.full - tol k ≤ x ∧ (x : Rat) ≤ e.full + tol k := by
  rw [settleCheck_found k e seg r q dur delay a b x hq htr ha hb hx hl]
  simp only [Option.some.injEq, decide_eq_true_eq]
  exact excess_le_iff _ _ _ _ (Rat.le_refl) (by exact_mod_cast tol_nonneg k)

/-- Branch keep: with no refusing check a bucket keeps its verdict. -/
theorem settleAnd_keep (v : Verdict) (cs : List (Option Bool)) (h : some false ∉ cs) : settleAnd v cs = v := by
  simp [settleAnd, h]

/-- Branch refuse: a passing bucket with a refusing check is `fail apart`. -/
theorem settleAnd_refuse (cs : List (Option Bool)) (h : some false ∈ cs) : settleAnd .pass cs = .fail .apart := by
  simp [settleAnd]
  exact h

/-- Branch not pass: a bucket that does not pass keeps its verdict. -/
theorem settleAnd_other (v : Verdict) (cs : List (Option Bool)) (h : v ≠ .pass) : settleAnd v cs = v := by
  have hb : (v == .pass) = false := by simpa using h
  simp [settleAnd, hb]

/-- `settleAnd` passes only what passed. -/
theorem settleAnd_pass (v : Verdict) (cs : List (Option Bool)) (h : settleAnd v cs = .pass) : v = .pass := by
  by_cases hv : v = .pass
  · exact hv
  · rw [settleAnd_other v cs hv] at h; exact h

/-- A bucket list under `settleBucket` passes a bucket only where the list did. -/
theorem lookup_settleBucket (k : Kind) (e : EarnRule) (ws : List Samp) (p : Nat) (l : List (Nat × Verdict)) (b : Nat)
    (h : (l.map (settleBucket k e ws p)).lookup b = some .pass) : l.lookup b = some .pass := by
  induction l with
  | nil => simp at h
  | cons x xs ih =>
    obtain ⟨c, v⟩ := x
    simp only [List.map_cons, settleBucket, List.lookup_cons] at h ⊢
    cases hb : b == c
    · simp only [hb] at h ⊢; exact ih h
    · simp only [hb, Option.some.injEq] at h ⊢; exact settleAnd_pass _ _ h

/-- A bucket list under `settleBucket` with no refusing check is the list. -/
theorem map_settleBucket (k : Kind) (e : EarnRule) (ws : List Samp) (p : Nat) (l : List (Nat × Verdict))
    (h : ∀ r, settleCheck k e ws r ≠ some false) : l.map (settleBucket k e ws p) = l := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    obtain ⟨c, v⟩ := x
    have hk : some false ∉ ((ws.filter (·.ph == p)).filter fun r => bucket r.m == c).map (settleCheck k e ws) := by
      simp only [List.mem_map, not_exists, not_and]
      intro r _ hr
      exact h r hr
    simp only [List.map_cons, settleBucket, settleAnd_keep v _ hk, ih]

/-- Settle only refuses: a close-hold bucket `byMStart` passes, `byM` passes. -/
theorem byMSettle (k : Kind) (d : List String → Option Nat) (e : EarnRule) (oSeg wSeg : List Samp) (b : Nat)
    (h : (byMStart .hold (closePh + 1) k d (some e) oSeg wSeg).lookup b = some .pass) :
    (byM .hold (closePh + 1) k d oSeg wSeg).lookup b = some .pass := by
  have h1 : (Phase.hold == Phase.push && closePh + 1 == closePh) = false := by decide
  have h2 : (Phase.hold == Phase.hold && closePh + 1 == closePh + 1) = true := by decide
  simp only [byMStart, h1, h2] at h
  exact lookup_settleBucket k e _ _ _ b h

/-- A close-hold with no refusing settle check, among them a pass with no sample read late enough, is `byM`. -/
theorem byMSettle_keep (k : Kind) (d : List String → Option Nat) (e : EarnRule) (oSeg wSeg : List Samp)
    (h : ∀ r, settleCheck k e (annotate wSeg) r ≠ some false) :
    byMStart .hold (closePh + 1) k d (some e) oSeg wSeg = byM .hold (closePh + 1) k d oSeg wSeg := by
  have h1 : (Phase.hold == Phase.push && closePh + 1 == closePh) = false := by decide
  have h2 : (Phase.hold == Phase.hold && closePh + 1 == closePh + 1) = true := by decide
  simp only [byMStart, h1, h2]
  exact map_settleBucket k e _ _ _ h

/-- Without the rule `byMStart` is `byM`. -/
theorem byMStart_none (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (oSeg wSeg : List Samp) :
    byMStart ph p k d none oSeg wSeg = byM ph p k d oSeg wSeg := rfl

/-- Outside the close's push and the close-hold the rule changes nothing. -/
theorem byMStart_other (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (e : Option EarnRule)
    (oSeg wSeg : List Samp) (h1 : (ph == .push && p == closePh) = false)
    (h2 : (ph == .hold && p == closePh + 1) = false) :
    byMStart ph p k d e oSeg wSeg = byM ph p k d oSeg wSeg := by
  cases e <;> simp [byMStart, h1, h2]

/-- In the close's push the rule changes no bucket but 0. -/
theorem byMStart_keeps (k : Kind) (d : List String → Option Nat) (e : Option EarnRule) (oSeg wSeg : List Samp) :
    (byMStart .push closePh k d e oSeg wSeg).filter (·.1 != 0) = (byM .push closePh k d oSeg wSeg).filter (·.1 != 0) := by
  cases e with
  | none => rfl
  | some f =>
    simp only [byMStart]
    generalize byM .push closePh k d oSeg wSeg = v
    induction v with
    | nil => rfl
    | cons x xs ih =>
      obtain ⟨b, w⟩ := x
      by_cases hb : b = 0 <;> simp_all

/-- Under the rule, bucket 0 of the close's push is `startBucket` over the close's samples of both arms. -/
theorem byMStart_bucket0 (k : Kind) (d : List String → Option Nat) (e : EarnRule) (oSeg wSeg : List Samp) :
    (byMStart .push closePh k d (some e) oSeg wSeg).lookup 0 =
      some (startBucket k d e.full (annotate oSeg) ((annotate oSeg).filter (·.ph == closePh))
        ((annotate wSeg).filter (·.ph == closePh))) := by
  simp [byMStart, byM, List.range_succ_eq_map]

/-- Bisection is monotone in its target. -/
theorem bisect_le_bisect (c : Bezier.Bez) (t u : Rat) (h : t ≤ u) (n : Nat) :
    ∀ lo hi : Rat, lo ≤ hi → Bezier.bisect c t n lo hi ≤ Bezier.bisect c u n lo hi := by
  induction n with
  | zero => intro lo hi _; simp only [Bezier.bisect]; grind
  | succ n ih =>
    intro lo hi hle
    simp only [Bezier.bisect]
    split <;> split
    · exact ih _ _ (by grind)
    · grind
    · have h1 := Bezier.bisect_mem c t n lo ((lo + hi) / 2) (by grind)
      have h2 := Bezier.bisect_mem c u n ((lo + hi) / 2) hi (by grind)
      grind
    · exact ih _ _ (by grind)

/-- The value coordinate of a curve with `y1 = 0`, `y2 = 1` rises on `[0, 1]`. -/
theorem rise_le (a b : Rat) (h0 : 0 ≤ a) (hab : a ≤ b) (h1 : b ≤ 1) : Bezier.coord 0 1 a ≤ Bezier.coord 0 1 b := by
  unfold Bezier.coord
  have e1 : a * a ≤ a := by have := Rat.mul_le_mul_of_nonneg_left (by grind : a ≤ 1) h0; grind
  have e2 : b * b ≤ b := by have := Rat.mul_le_mul_of_nonneg_left h1 (by grind : 0 ≤ b); grind
  have e3 : a * b ≤ a := by have := Rat.mul_le_mul_of_nonneg_left h1 h0; grind
  have e4 : a * b ≤ b := by have := Rat.mul_le_mul_of_nonneg_right (by grind : a ≤ 1) (by grind : 0 ≤ b); grind
  have k : 0 ≤ (b - a) * (3 * (a + b) - 2 * (a * a + a * b + b * b)) := Rat.mul_nonneg (by grind) (by grind)
  grind

/-- The earn curve rises. -/
theorem ease_earn_le (t u : Rat) (h : t ≤ u) : Bezier.ease earnCurve t ≤ Bezier.ease earnCurve u := by
  have mt := Bezier.ease_mem earnCurve t (by decide) (by decide) (by decide) (by decide)
  have mu := Bezier.ease_mem earnCurve u (by decide) (by decide) (by decide) (by decide)
  by_cases ht : t ≤ 0
  · rw [Bezier.ease_nonpos _ _ ht]; exact mu.1
  by_cases hu : 1 ≤ u
  · rw [Bezier.ease_ge_one _ _ hu]; exact mt.2
  have ht' : ¬ 1 ≤ t := by grind
  have hu' : ¬ u ≤ 0 := by grind
  simp only [Bezier.ease, ht, ht', hu, hu', ite_false]
  have bt := Bezier.bisect_mem earnCurve t Bezier.steps 0 1 (by decide)
  have bu := Bezier.bisect_mem earnCurve u Bezier.steps 0 1 (by decide)
  exact rise_le _ _ bt.1 (bisect_le_bisect earnCurve t u h _ 0 1 (by decide)) bu.2

/-- The inverse of a positive rational is nonnegative. -/
theorem inv_nonneg_of_pos (d : Rat) (hd : 0 < d) : 0 ≤ d⁻¹ := by
  apply Classical.byContradiction
  intro hn
  have h1 := Rat.mul_le_mul_of_nonneg_left (show d⁻¹ ≤ 0 by grind) (show 0 ≤ d by grind)
  have h2 := Rat.mul_inv_cancel d (by grind)
  grind

/-- `a / c ≤ a / b` for `0 ≤ a` and `0 < b ≤ c`. -/
theorem div_le_div_left (a b c : Rat) (ha : 0 ≤ a) (hb : 0 < b) (hbc : b ≤ c) : a / c ≤ a / b := by
  have hc : 0 < c := by grind
  have ib := Rat.mul_inv_cancel b (by grind)
  have ic := Rat.mul_inv_cancel c (by grind)
  have key : c⁻¹ ≤ b⁻¹ := by
    have h1 := Rat.mul_le_mul_of_nonneg_left hbc
      (Rat.mul_nonneg (inv_nonneg_of_pos b hb) (inv_nonneg_of_pos c hc))
    have e1 : b⁻¹ * c⁻¹ * b = c⁻¹ * (b * b⁻¹) := by rw [Rat.mul_comm b⁻¹ c⁻¹, Rat.mul_assoc, Rat.mul_comm b⁻¹ b]
    have e2 : b⁻¹ * c⁻¹ * c = b⁻¹ * (c * c⁻¹) := by rw [Rat.mul_assoc, Rat.mul_comm c⁻¹ c]
    rw [e1, e2, ib, ic, Rat.mul_one, Rat.mul_one] at h1
    exact h1
  rw [Rat.div_def, Rat.div_def]
  exact Rat.mul_le_mul_of_nonneg_left key ha

/-- After its delay, a rise from 0 is lower on a longer transition. -/
theorem along_dur_le (b c delay : Nat) (hb : 0 < b) (hbc : b ≤ c) (full : Rat) (hf : 0 ≤ full) (x : Int)
    (hx : (delay : Int) ≤ x) : along c delay 0 full x ≤ along b delay 0 full x := by
  unfold along
  have hx' : (delay : Rat) ≤ x := by exact_mod_cast hx
  have h1 := ease_earn_le _ _ (div_le_div_left ((x : Rat) - delay) b c (by grind) (by exact_mod_cast hb)
    (by exact_mod_cast hbc))
  have := Rat.mul_le_mul_of_nonneg_left h1 (by grind : (0 : Rat) ≤ full - 0)
  grind

/-- A rise from 0 is lower with a longer delay. -/
theorem along_delay_le (dur a b : Nat) (hd : 0 < dur) (hab : a ≤ b) (full : Rat) (hf : 0 ≤ full) (x : Int) :
    along dur b 0 full x ≤ along dur a 0 full x := by
  unfold along
  have hab' : (a : Rat) ≤ b := by exact_mod_cast hab
  have h1 : ((x : Rat) - b) / dur ≤ ((x : Rat) - a) / dur := by
    rw [Rat.div_def, Rat.div_def]
    exact Rat.mul_le_mul_of_nonneg_right (by grind) (inv_nonneg_of_pos _ (by exact_mod_cast hd))
  have := Rat.mul_le_mul_of_nonneg_left (ease_earn_le _ _ h1) (by grind : (0 : Rat) ≤ full - 0)
  grind

/-- A reading of `q` rounded half up, as `kit.mjs` rounds, lies within `t` of `full ≥ q` exactly when
`full - t - 1/2 ≤ q`. -/
theorem rounded_iff (full t : Int) (ht : 0 ≤ t) (q : Rat) (hq : q ≤ full) :
    excess full full (q + 1 / 2).floor ≤ t ↔ ((full - t : Int) : Rat) - 1 / 2 ≤ q := by
  rw [excess_le_iff _ _ _ _ (Rat.le_refl) (by exact_mod_cast ht)]
  have hup : (q + 1 / 2).floor ≤ full := by
    have : (q + 1 / 2).floor < full + 1 := by
      rw [Rat.floor_lt_iff]; push_cast; grind
    omega
  constructor
  · intro ⟨h1, _⟩
    have : full - t ≤ (q + 1 / 2).floor := by
      have : ((full - t : Int) : Rat) ≤ (q + 1 / 2).floor := by push_cast; exact h1
      exact_mod_cast this
    rw [Rat.le_floor_iff] at this
    grind
  · intro h
    have : full - t ≤ (q + 1 / 2).floor := by rw [Rat.le_floor_iff]; grind
    constructor
    · have : ((full - t : Int) : Rat) ≤ (q + 1 / 2).floor := by exact_mod_cast this
      push_cast at this; exact this
    · have : ((q + 1 / 2).floor : Rat) ≤ full := by exact_mod_cast hup
      have : (0 : Rat) ≤ t := by exact_mod_cast ht
      grind

/-- The settle reading of a rise from 0 to `full`, read `x` ms after its trigger on transition `(dur, delay)`, rounded
half up as `kit.mjs` rounds (`q`, line 43). -/
def readRise (dur delay : Nat) (full : Int) (x : Int) : Int := (along dur delay 0 full x + 1 / 2).floor

/-- With the reference duration `dur0` ending by `x`, a reading on duration `dur ≥ dur0` lies within `t` of `full`
exactly when `dur < b`, given the two boundary values. -/
theorem settle_dur_iff (dur0 b delay : Nat) (full t x : Int) (h0 : 0 < dur0) (hf : 0 ≤ full) (ht : 0 ≤ t)
    (hx : (delay : Int) ≤ x) (hfull : along dur0 delay 0 full x = full)
    (hpass : ((full - t : Int) : Rat) - 1 / 2 ≤ along (b - 1) delay 0 full x)
    (hfail : along b delay 0 full x < ((full - t : Int) : Rat) - 1 / 2) (hb : dur0 < b) (dur : Nat) (hd : dur0 ≤ dur) :
    excess full full (readRise dur delay full x) ≤ t ↔ dur < b := by
  have hf' : (0 : Rat) ≤ full := by exact_mod_cast hf
  have hle := along_dur_le dur0 dur delay h0 hd full hf' x hx
  rw [readRise, rounded_iff full t ht _ (by grind)]
  constructor
  · intro h
    apply Classical.byContradiction
    intro hn
    have := along_dur_le b dur delay (by omega) (by omega) full hf' x hx
    grind
  · intro h
    have := along_dur_le dur (b - 1) delay (by omega) (by omega) full hf' x hx
    grind

/-- With the reference delay `l0` ending by `x`, a reading on delay `l ≥ l0` lies within `t` of `full` exactly when
`l < b`, given the two boundary values. -/
theorem settle_delay_iff (dur l0 b : Nat) (full t x : Int) (hd : 0 < dur) (hf : 0 ≤ full) (ht : 0 ≤ t)
    (hfull : along dur l0 0 full x = full)
    (hpass : ((full - t : Int) : Rat) - 1 / 2 ≤ along dur (b - 1) 0 full x)
    (hfail : along dur b 0 full x < ((full - t : Int) : Rat) - 1 / 2) (hb : l0 < b) (l : Nat) (hl : l0 ≤ l) :
    excess full full (readRise dur l full x) ≤ t ↔ l < b := by
  have hf' : (0 : Rat) ≤ full := by exact_mod_cast hf
  have hle := along_delay_le dur l0 l hd hl full hf' x
  rw [readRise, rounded_iff full t ht _ (by grind)]
  constructor
  · intro h
    apply Classical.byContradiction
    intro hn
    have := along_delay_le dur b l hd (by omega) full hf' x
    grind
  · intro h
    have := along_delay_le dur l (b - 1) hd (by omega) full hf' x
    grind

/-- Mutation duration, opacity: read exactly `settleAt` after its trigger, a rise on duration `dur ≥ 320` instead of 320
passes the close-hold settle check exactly when `dur < 463`; the smallest refused increase is 143 ms. -/
theorem settle_opacity_duration (dur : Nat) (h : 320 ≤ dur) :
    excess 1000 1000 (readRise dur 120 1000 (settleAt 320 120)) ≤ tol .unit ↔ dur < 463 :=
  settle_dur_iff 320 463 120 1000 10 520 (by decide) (by decide) (by decide) (by decide) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide) dur h

/-- Mutation delay, opacity: a delay `l ≥ 120` passes the settle check exactly when `l < 244`; the smallest refused
increase is 124 ms. -/
theorem settle_opacity_delay (l : Nat) (h : 120 ≤ l) :
    excess 1000 1000 (readRise 320 l 1000 (settleAt 320 120)) ≤ tol .unit ↔ l < 244 :=
  settle_delay_iff 320 120 244 1000 10 520 (by decide) (by decide) (by decide) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide) l h

/-- Mutation duration, max-width above a phone (176 px): a duration `dur ≥ 680` passes exactly when `dur < 846`; the
smallest refused increase is 166 ms. -/
theorem settle_wide_duration (dur : Nat) (h : 680 ≤ dur) :
    excess 176000 176000 (readRise dur 0 176000 (settleAt 680 0)) ≤ tol .geometry ↔ dur < 846 :=
  settle_dur_iff 680 846 0 176000 1000 760 (by decide) (by decide) (by decide) (by decide) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide) dur h

/-- Mutation delay, max-width above a phone: a delay `l` passes exactly when `l < 149`. -/
theorem settle_wide_delay (l : Nat) :
    excess 176000 176000 (readRise 680 l 176000 (settleAt 680 0)) ≤ tol .geometry ↔ l < 149 :=
  settle_delay_iff 680 0 149 176000 1000 760 (by decide) (by decide) (by decide) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide) l (Nat.zero_le l)

/-- Mutation duration, max-width on a phone (152 px): a duration `dur ≥ 680` passes exactly when `dur < 853`. -/
theorem settle_phone_duration (dur : Nat) (h : 680 ≤ dur) :
    excess 152000 152000 (readRise dur 0 152000 (settleAt 680 0)) ≤ tol .geometry ↔ dur < 853 :=
  settle_dur_iff 680 853 0 152000 1000 760 (by decide) (by decide) (by decide) (by decide) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide) dur h

/-- Mutation delay, max-width on a phone: a delay `l` passes exactly when `l < 154`. -/
theorem settle_phone_delay (l : Nat) :
    excess 152000 152000 (readRise 680 l 152000 (settleAt 680 0)) ≤ tol .geometry ↔ l < 154 :=
  settle_delay_iff 680 0 154 152000 1000 760 (by decide) (by decide) (by decide) (by decide +kernel)
    (by decide +kernel) (by decide +kernel) (by decide) l (Nat.zero_le l)

/-- An original earn opacity close at 390 px: collapsed, the trigger at 100 ms, 852 at 400 ms, at rest at 900. -/
def earnSeg : List Samp := [ec 6540 0 0, ec 0 100 0, ec 0 400 852, eh 900 1000]

/-- `earnSeg` with a close-hold sample read in flight, 895 at 420 ms. -/
def holdSeg : List Samp := [ec 6540 0 0, ec 0 100 0, ec 0 400 852, eh 420 895, eh 900 1000]

/-- `earnSeg` rewritten with a stale start: its trigger reads 600. -/
def staleRew : List Samp := [ec 6540 0 0, ec 0 100 600, ec 0 400 940, eh 900 1000]

/-- `earnSeg` rewritten reversed: from 1000 at the trigger towards 0. -/
def reversedRew : List Samp := [ec 6540 0 1000, ec 0 100 1000, ec 0 400 148, eh 900 0]

/-- `earnSeg` rewritten to stay collapsed. -/
def collapsedRew : List Samp := [ec 6540 0 0, ec 0 100 0, ec 0 400 0, eh 900 0]

/-- `holdSeg` rewritten towards 0.9 of the value at rest: in flight like the original, at rest at 900. -/
def targetRew : List Samp := [ec 6540 0 0, ec 0 100 0, ec 0 400 767, eh 420 895, eh 900 900]

/-- `earnSeg` rewritten on a 463 ms opacity transition, read `settleAt 320 120` ms after its trigger. -/
def slowRew : List Samp := [ec 6540 0 0, ec 0 100 0, ec 0 400 (readRise 463 120 1000 300), eh 620 (readRise 463 120 1000 520)]

/-- The verdicts of the earn opacity at 390 px in phase `p` of `ph`, `o` against `w`. -/
def earnAt (ph : Phase) (p : Nat) (o w : List Samp) : List (Nat × Verdict) :=
  byMStart ph p .unit (durOf "earn" "opacity" 390) (startFor "earn" "opacity" 390) o w

/-- Mutation stale start, refused at close@0 (push of phase 2, bucket 0) by the anchor. -/
theorem byMStart_stale : (earnAt .push 2 earnSeg staleRew).lookup 0 = some (.fail .apart) := by decide +kernel

/-- Mutation reversed, refused at close@0 by the anchor and at close-hold@0 (hold of phase 3, bucket 0) by settle. -/
theorem byMStart_reversed :
    (earnAt .push 2 earnSeg reversedRew).lookup 0 = some (.fail .apart) ∧
      (earnAt .hold 3 earnSeg reversedRew).lookup 0 = some (.fail .apart) := by decide +kernel

/-- Mutation stays collapsed: inside the range at close@0, refused at close-hold@0 by settle. -/
theorem byMStart_collapsed :
    (earnAt .push 2 earnSeg collapsedRew).lookup 0 = some .pass ∧
      (earnAt .hold 3 earnSeg collapsedRew).lookup 0 = some (.fail .apart) := by decide +kernel

/-- Mutation target 0.9: `byM` passes close-hold@0 against the original's in-flight 895, settle refuses it. -/
theorem byMStart_target :
    (byM .hold 3 .unit (durOf "earn" "opacity" 390) holdSeg targetRew).lookup 0 = some .pass ∧
      (earnAt .hold 3 holdSeg targetRew).lookup 0 = some (.fail .apart) := by decide +kernel

/-- Mutation duration at judge level: the 463 ms rise reads 989 at settle time, refused at close-hold@0. -/
theorem byMStart_duration :
    readRise 463 120 1000 520 = 989 ∧ (earnAt .hold 3 earnSeg slowRew).lookup 0 = some (.fail .apart) := by
  decide +kernel

/-- An earn opacity close at 390 px with three triggers 30 ms apart inside the 120 ms delay, each reading 0. -/
def driftOrig : List Samp := [ec 6540 0 0, ec 400 100 0, ec 300 130 0, ec 0 160 0, eh 900 1000]

/-- `driftOrig` rewritten to drift: each trigger reads `tol .unit - 1` = 9 more than the one before. -/
def driftRew : List Samp := [ec 6540 0 0, ec 400 100 9, ec 300 130 18, ec 0 160 27, eh 900 1000]

/-- An earn opacity close whose triggers fall while it moves. -/
def movingOrig : List Samp := [ec 6540 0 0, ec 400 100 0, ec 300 300 252, ec 0 500 700, eh 900 1000]

/-- `movingOrig` rewritten 9, 18 and 27 above it at its triggers. -/
def movingRew : List Samp := [ec 6540 0 0, ec 400 100 9, ec 300 300 270, ec 0 500 727, eh 900 1000]

/-- Limit drift: a drift inside the range passes close@0 and close-hold@0, at rest and in flight. -/
theorem byMStart_drift :
    (earnAt .push 2 driftOrig driftRew).lookup 0 = some .pass ∧ (earnAt .hold 3 driftOrig driftRew).lookup 0 = some .pass ∧
      (earnAt .push 2 movingOrig movingRew).lookup 0 = some .pass ∧
      (earnAt .hold 3 movingOrig movingRew).lookup 0 = some .pass := by decide +kernel

/-- An earn sample of pass 0 in phase `ph` under classes `cls` at morph value `m` reading `x`, read at `t` ms. -/
def ecl (ph : Nat) (cls : List String) (m : Int) (t : Nat) (x : Int) : Samp := ⟨some m, none, [.num [x]], 0, cls, ph, 0, some t⟩

/-- An original earn max-width close at 390 px while morphing: the trigger at 0 ms, 120271 at 340 ms, at rest 152000. -/
def mwOrig : List Samp :=
  [ecl 2 [driver] 6540 0 0, ecl 2 [driver] 0 0 0, ecl 2 [driver] 0 340 120271, ecl 3 [] 0 900 152000]

/-- `mwOrig` rewritten linear: 76000 at 340 ms. -/
def linearRew : List Samp :=
  [ecl 2 [driver] 6540 0 0, ecl 2 [driver] 0 0 0, ecl 2 [driver] 0 340 76000, ecl 3 [] 0 900 152000]

/-- An original earn opacity close at 390 px in `is-hero-pill`: the 200 ms transition, 960 at 150 ms, at rest 1000. -/
def pillOrig : List Samp :=
  [ecl 2 ["is-hero-pill"] 6540 0 0, ecl 2 ["is-hero-pill"] 0 0 0, ecl 2 ["is-hero-pill"] 0 150 960,
    ecl 3 ["is-hero-pill"] 0 900 1000]

/-- `pillOrig` rewritten on the 320 ms transition: 300 at 150 ms. -/
def pillSlowRew : List Samp :=
  [ecl 2 ["is-hero-pill"] 6540 0 0, ecl 2 ["is-hero-pill"] 0 0 0, ecl 2 ["is-hero-pill"] 0 150 300,
    ecl 3 ["is-hero-pill"] 0 900 1000]

/-- Limit curve: another curve or a duration that ends by settle time passes close@0. -/
theorem byMStart_curve :
    (byMStart .push 2 .geometry (durOf "earn" "max-width" 390) (startFor "earn" "max-width" 390) mwOrig linearRew).lookup 0 =
      some .pass ∧ (earnAt .push 2 pillOrig pillSlowRew).lookup 0 = some .pass := by decide +kernel

/-- Original against original, run 39508421419 (apple, 641 px, close of passes 0 and 3): the earn opacity at each
trigger. -/
def ooOpacity : List Int × List Int := ([0, 0, 0, 0, 0, 0], [0, 0, 67, 73])

/-- Original against original, run 39508421419 (apple, 641 px, close of passes 1 and 3): the earn max-width at each
trigger. -/
def ooMaxWidth : List Int × List Int := ([0, 475, 1414, 2285, 5490, 6686, 27033, 30068], [0, 5319, 45377, 69491])

#guard ooOpacity.1.head? == ooOpacity.2.head? &&
  ((ooOpacity.1.zip ooOpacity.2).map fun (a, b) => (a - b).natAbs) == [0, 0, 67, 73] && 73 > tol .unit
#guard ooMaxWidth.1.head? == ooMaxWidth.2.head? &&
  ((ooMaxWidth.1.zip ooMaxWidth.2).map fun (a, b) => (a - b).natAbs) == [0, 4844, 43963, 67206] && 67206 > tol .geometry

end CloseStart

section CloseIdentity
open Fw.Parts HeroExitCloseStart

/-- The unit the close-start identity decides: the nav's background colour. -/
def idOn (node prop : String) : Bool := node == "nav" && prop == "background-color"

/-- `Nav.morphingCut` in the probe's units of the morph value (times 10000). -/
def cutM : Int := 10

/-- A morph value as the probe stores it: times 10000, rounded half up. -/
def roundM (v : Rat) : Int := (v * 10000 + 1 / 2).floor

/-- Red and alpha (0 to 255) of the colour the nav background mixes from at morph value 0 (`#ffffff1a`; snapshot site-pretty
`2.gBuqKVzi.css` 11336-11340, ported `nav.module.css` 22-26). -/
def mixFrom : Int × Int := (255, 26)

/-- Red and alpha (0 to 255) of the colour the nav background mixes to at morph value 1 (`#131922`; snapshot site-pretty
`2.gBuqKVzi.css` 11336-11340, ported `nav.module.css` 22-26). -/
def mixTo : Int × Int := (19, 255)

/-- `2550000 * bgAlpha (m / 10000)` (`idDen_eq`). -/
def idDen (m : Int) : Int := mixFrom.2 * (10000 - m) + mixTo.2 * m

/-- `1000 * bgRed (m / 10000) * idDen m` (`idNum_eq`). -/
def idNum (m : Int) : Int := 1000 * (mixFrom.1 * mixFrom.2 * (10000 - m) + mixTo.1 * mixTo.2 * m)

/-- Red reading `x` (times 1000) within half a level of `bgRed (m / 10000)` (`redOk_iff`). -/
def redOk (m x : Int) : Bool :=
  decide (idNum m - 500 * idDen m ≤ x * idDen m) && decide (x * idDen m ≤ idNum m + 500 * idDen m)

/-- Alpha reading `a` (times 1000) within half a level of `255 * bgAlpha (m / 10000)` (`alphaOk_iff`). -/
def alphaOk (m a : Int) : Bool := decide (idDen m - 5000 ≤ 10 * a) && decide (10 * a ≤ idDen m + 5000)

/-- The sample was read with the nav's `is-morphing` class on. -/
def hasDriver (s : Samp) : Bool := s.cls.contains driver

/-- Red and alpha of a reading of one colour. -/
def redAlpha : List Val → Option (Int × Int)
  | [.num [x, _, _, a]] => some (x, a)
  | _ => none

/-- The sample was read at most `startLag` ms after the last class change of the nav. -/
def idFresh (s : Samp) : Bool :=
  match s.since with
  | some x => decide (x ≤ startLag)
  | none => false

/-- `r` after `q` in its pass, `q` with `is-morphing` and `r` without it, in flight and fresh: `q`'s morph value is at
least `cutM`, `r`'s at most, and `r` reads the colour of `q`'s; `none` for any other pair or a missing part. -/
def idCheck (d : List String → Option Nat) (q : Option Samp) (r : Samp) : Option Bool :=
  match q with
  | some q =>
    if hasDriver q && !hasDriver r && inFlight d r && idFresh r then
      match q.m, r.m, redAlpha r.els with
      | some mi, some mj, some (x, a) =>
        some (decide (cutM ≤ mi) && decide (mj ≤ cutM) && redOk mi x && alphaOk mi a)
      | _, _, _ => none
    else none
  | none => none

/-- One rewrite sample after `q`: `idCheck` when it decides, else `judgeUnit`. -/
def idJudge (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (q : Option Samp) (r : Samp) : Verdict :=
  match idCheck d q r with
  | some true => .pass
  | some false => .fail .apart
  | none => judgeUnit k d seg win r

/-- Each sample with the sample before it in its pass. -/
def withPrev (ws : List Samp) : List (Option Samp × Samp) :=
  ws.mapIdx fun i r => ((passOf (ws.take i) r.rep).getLast?, r)

/-- `bucketVerdict` of bucket `b` of phase `p`, each sample of the rewrite's annotated path `ws` by `idJudge`. -/
def idBucket (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig ws : List Samp) (p b : Nat) : Verdict :=
  match (withPrev ws).filter (fun x => x.2.ph == p && bucket x.2.m == b) with
  | [] => if ph == .push && needsSample b then .fail .coverage else .skip .noSample
  | rs => combine (rs.map fun x => idJudge k d seg (windowAt ph d seg orig x.2) x.1 x.2)

/-- `byM` with each bucket by `idBucket`. -/
def byMId (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (oSeg wSeg : List Samp) :
    List (Nat × Verdict) :=
  let seg := annotate oSeg
  (List.range 12).map fun b => (b, idBucket ph k d seg (seg.filter (·.ph == p)) (annotate wSeg) p b)

/-- The judge of a morph unit: `byMId` when `id`, else `byMStart`. -/
def byMRule (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (e : Option EarnRule) (id : Bool)
    (oSeg wSeg : List Samp) : List (Nat × Verdict) :=
  if id then byMId ph p k d oSeg wSeg else byMStart ph p k d e oSeg wSeg

/-- A nav background sample of pass 0 in the close. -/
def nb (cls : List String) (m : Int) (since : Option Nat) (x a : Int) : Samp :=
  ⟨some m, since, [.num [x, 0, 0, a]], 0, cls, 2, 0, none⟩

/-- Red of morph value `m` times 1000, rounded down. -/
def fRed (m : Int) : Int := idNum m / idDen m

/-- Alpha of morph value `m` times 1000, rounded down. -/
def fAlpha (m : Int) : Int := idDen m / 10

/-- A sample with `is-morphing` at `m`, reading the colour of `m`. -/
def nbOn (m : Int) : Samp := nb [driver] m (some 0) (fRed m) (fAlpha m)

/-- A sample without `is-morphing` at `m`, `since` ms after the class change. -/
def nbOff (m : Int) (since : Nat) (x a : Int) : Samp := nb [] m (some since) x a

/-- Nav background width 390 transitions. -/
def navBg : List String → Option Nat := durOf "nav" "background-color" 390

#guard idOn "nav" "background-color" && !idOn "nav" "opacity" && !idOn "earn" "background-color"
#guard roundM (1 / 1000) == 10 && roundM (1049 / 1000000) == 10 && roundM (1050 / 1000000) == 11 && roundM 0 == 0
#guard idDen 0 == 260000 && idNum 0 == 255000 * 260000 && fRed 0 == 255000 && fAlpha 0 == 26000 &&
  fRed 10000 == 19000 && fAlpha 10000 == 255000
#guard redOk 0 255500 && !redOk 0 255501 && redOk 0 254500 && !redOk 0 254499 && redOk 20 (fRed 20) && !redOk 20 255000
#guard alphaOk 0 26500 && !alphaOk 0 26501 && alphaOk 0 25500 && !alphaOk 0 25499
#guard redAlpha [.num [1, 2, 3, 4]] == some (1, 4) && redAlpha [.num [1, 2, 3]] == none && redAlpha [] == none
#guard hasDriver (nbOn 20) && !hasDriver (nbOff 0 4 0 0)
#guard idFresh (nbOff 0 200 0 0) && !idFresh (nbOff 0 201 0 0) && !idFresh (nb [] 0 none 0 0)
#guard idCheck navBg (some (nbOn 20)) (nbOff 0 4 (fRed 20) (fAlpha 20)) == some true &&
  idCheck navBg (some (nbOn 20)) (nbOff 0 4 255000 (fAlpha 20)) == some false &&
  idCheck navBg (some (nbOn 9)) (nbOff 0 4 (fRed 9) (fAlpha 9)) == some false &&
  idCheck navBg (some (nbOn 600)) (nbOff 300 4 (fRed 600) (fAlpha 600)) == some false &&
  idCheck navBg none (nbOff 0 4 (fRed 20) (fAlpha 20)) == none &&
  idCheck navBg (some (nbOff 0 4 0 0)) (nbOff 0 4 (fRed 20) (fAlpha 20)) == none &&
  idCheck navBg (some (nbOn 20)) (nbOff 0 4000 (fRed 20) (fAlpha 20)) == none &&
  idCheck navBg (some (nbOn 1174)) (nbOff 0 694 253656 26113) == none &&
  idCheck navBg (some (nbOn 20)) ⟨some 0, some 4, [.str "x"], 0, [], 2, 0, none⟩ == none &&
  idCheck navBg (some (nbOn 20)) ⟨none, some 4, [.num [0, 0, 0, 0]], 0, [], 2, 0, none⟩ == none
#guard withPrev [smr 0 1 [], smr 1 2 [], smr 0 3 []] == [(none, smr 0 1 []), (none, smr 1 2 []), (some (smr 0 1 []), smr 0 3 [])]
#guard idJudge .colour navBg [] none (some (nbOn 20)) (nbOff 0 4 (fRed 20) (fAlpha 20)) == .pass &&
  idJudge .colour navBg [] none (some (nbOn 20)) (nbOff 0 4 255000 (fAlpha 20)) == .fail .apart &&
  idJudge .colour navBg [] none none (nbOff 0 4 255000 (fAlpha 20)) == .fail .coverage
#guard (byMRule .push 2 .colour navBg none true [nbOn 20] [nbOn 20]).lookup 0 == some .pass &&
  byMRule .push 2 .unit (durOf "earn" "opacity" 390) (startFor "earn" "opacity" 390) false earnSeg staleRew ==
    byMStart .push 2 .unit (durOf "earn" "opacity" 390) (startFor "earn" "opacity" 390) earnSeg staleRew

/-- The cut in the probe's units is `Nav.morphingCut`. -/
theorem cutM_eq : (cutM : Rat) = Nav.morphingCut * 10000 := by
  unfold cutM Nav.morphingCut
  decide +kernel

/-- A morph value above the cut (the class is on) is stored as at least `cutM`. -/
theorem roundM_above (v : Rat) (h : Nav.morphingCut < v) : cutM ≤ roundM v := by
  unfold roundM cutM
  unfold Nav.morphingCut at h
  have h1 : ((10 : Int) : Rat) ≤ v * 10000 + 1 / 2 := by push_cast; grind
  have := Rat.floor_monotone h1
  rw [Rat.floor_intCast] at this
  exact this

/-- A morph value at or below the cut (the class is off) is stored as at most `cutM`. -/
theorem roundM_below (v : Rat) (h : v ≤ Nav.morphingCut) : roundM v ≤ cutM := by
  unfold roundM cutM
  unfold Nav.morphingCut at h
  have h1 : v * 10000 + 1 / 2 ≤ 21 / 2 := by grind
  have := Rat.floor_monotone h1
  have e : (21 / 2 : Rat).floor = 10 := by decide +kernel
  rw [e] at this
  exact this

/-- Limit: the cut itself (class off) and a value above it (class on) are both stored as `cutM`. -/
theorem roundM_tie : roundM Nav.morphingCut = cutM ∧ Nav.morphingCut < 1049 / 1000000 ∧ roundM (1049 / 1000000) = cutM := by
  unfold roundM cutM Nav.morphingCut
  decide +kernel

/-- `idDen` is `bgAlpha` restated. -/
theorem idDen_eq (m : Int) : bgAlpha ((m : Rat) / 10000) * 2550000 = (idDen m : Rat) := by
  unfold bgAlpha idDen mixFrom mixTo
  push_cast
  grind

/-- `idNum` is `bgRed` restated. -/
theorem idNum_eq (m : Int) (h : 0 ≤ m) : bgRed ((m : Rat) / 10000) * (idDen m : Rat) * 1000 = (idNum m : Rat) := by
  have h0 : (0 : Rat) ≤ (m : Rat) / 10000 := by
    have : (0 : Rat) ≤ m := Rat.intCast_nonneg.mpr h
    grind
  have e := bgRed_mul _ h0
  have n : (idNum m : Rat) = 1000 * (6630 * (10000 - (m : Rat)) + 4845 * m) := by
    unfold idNum mixFrom mixTo
    push_cast
    grind
  rw [← idDen_eq m, n]
  grind

/-- `P - D/2 ≤ x D` over 1000 is `R - 1/2 ≤ x/1000` when `R D 1000 = P`. -/
theorem id_lo_iff (R : Rat) (P D x : Int) (hd : 0 < D) (e : R * D * 1000 = P) :
    (P - 500 * D ≤ x * D) ↔ R - 1 / 2 ≤ (x : Rat) / 1000 := by
  have hd' : (0 : Rat) < (D : Rat) := Rat.intCast_pos.mpr hd
  rw [← Rat.intCast_le_intCast]
  push_cast
  rw [← e]
  constructor
  · intro k
    refine Classical.byContradiction fun hc => ?_
    have hc' : (x : Rat) / 1000 < R - 1 / 2 := by grind
    have := Rat.mul_lt_mul_of_pos_right hc' hd'
    grind
  · intro k
    have := Rat.mul_le_mul_of_nonneg_right k (Rat.le_of_lt hd')
    grind

/-- `x D ≤ P + D/2` over 1000 is `x/1000 ≤ R + 1/2` when `R D 1000 = P`. -/
theorem id_hi_iff (R : Rat) (P D x : Int) (hd : 0 < D) (e : R * D * 1000 = P) :
    (x * D ≤ P + 500 * D) ↔ (x : Rat) / 1000 ≤ R + 1 / 2 := by
  have hd' : (0 : Rat) < (D : Rat) := Rat.intCast_pos.mpr hd
  rw [← Rat.intCast_le_intCast]
  push_cast
  rw [← e]
  constructor
  · intro k
    refine Classical.byContradiction fun hc => ?_
    have hc' : R + 1 / 2 < (x : Rat) / 1000 := by grind
    have := Rat.mul_lt_mul_of_pos_right hc' hd'
    grind
  · intro k
    have := Rat.mul_le_mul_of_nonneg_right k (Rat.le_of_lt hd')
    grind

/-- `redOk` is `closeStartOk` (half a red level of `bgRed`) on the probe's units. -/
theorem redOk_iff (m x : Int) (h : 0 ≤ m) : redOk m x = closeStartOk ((x : Rat) / 1000) ((m : Rat) / 10000) := by
  have hd : 0 < idDen m := by unfold idDen mixFrom mixTo; simp only; omega
  have e := idNum_eq m h
  unfold redOk closeStartOk
  rw [Bool.decide_and]
  congr 1
  · exact decide_eq_decide.mpr (id_lo_iff _ _ _ x hd e)
  · exact decide_eq_decide.mpr (id_hi_iff _ _ _ x hd e)

/-- `alphaOk` is half a level of `255 * bgAlpha` on the probe's units. -/
theorem alphaOk_iff (m a : Int) :
    alphaOk m a = decide (255 * bgAlpha ((m : Rat) / 10000) - 1 / 2 ≤ (a : Rat) / 1000 ∧
      (a : Rat) / 1000 ≤ 255 * bgAlpha ((m : Rat) / 10000) + 1 / 2) := by
  have e := idDen_eq m
  unfold alphaOk
  rw [Bool.decide_and]
  congr 1
  · apply decide_eq_decide.mpr
    rw [← Rat.intCast_le_intCast]
    push_cast
    rw [← e]
    grind
  · apply decide_eq_decide.mpr
    rw [← Rat.intCast_le_intCast]
    push_cast
    rw [← e]
    grind

/-- With every part found, `idCheck` is the cut on both morph values and half a level of `bgRed` and `bgAlpha`. -/
theorem idCheck_css (d : List String → Option Nat) (q r : Samp) (mi mj x a : Int) (h0 : 0 ≤ mi)
    (hq : hasDriver q = true) (hr : hasDriver r = false) (hf : inFlight d r = true) (hs : idFresh r = true)
    (hmi : q.m = some mi) (hmj : r.m = some mj) (hx : redAlpha r.els = some (x, a)) :
    idCheck d (some q) r = some (decide (cutM ≤ mi) && decide (mj ≤ cutM) &&
      closeStartOk ((x : Rat) / 1000) ((mi : Rat) / 10000) &&
      decide (255 * bgAlpha ((mi : Rat) / 10000) - 1 / 2 ≤ (a : Rat) / 1000 ∧
        (a : Rat) / 1000 ≤ 255 * bgAlpha ((mi : Rat) / 10000) + 1 / 2)) := by
  simp [idCheck, hq, hr, hf, hs, hmi, hmj, hx, ← redOk_iff mi x h0, ← alphaOk_iff mi a]

/-- `idCheck` decides only the first sample without `is-morphing` after one with it, in flight and fresh. -/
theorem idCheck_some (d : List String → Option Nat) (q : Option Samp) (r : Samp) (c : Bool) (h : idCheck d q r = some c) :
    ∃ q', q = some q' ∧ hasDriver q' = true ∧ hasDriver r = false ∧ inFlight d r = true ∧ idFresh r = true := by
  unfold idCheck at h
  cases q with
  | none => simp at h
  | some q' =>
    refine ⟨q', rfl, ?_⟩
    by_cases hc : (hasDriver q' && !hasDriver r && inFlight d r && idFresh r) = true
    · simp only [Bool.and_eq_true, Bool.not_eq_true'] at hc
      exact ⟨hc.1.1.1, hc.1.1.2, hc.1.2, hc.2⟩
    · simp [hc] at h

/-- A sample read more than `startLag` ms after the class change is not decided: it is `judgeUnit`'s. -/
theorem idCheck_late (d : List String → Option Nat) (q : Option Samp) (r : Samp) (x : Nat) (hx : r.since = some x)
    (hl : startLag < x) : idCheck d q r = none := by
  cases h : idCheck d q r with
  | none => rfl
  | some c =>
    obtain ⟨_, _, _, _, _, hs⟩ := idCheck_some d q r c h
    simp [idFresh, hx] at hs
    omega

/-- Without a sample before it in its pass, `idCheck` does not decide. -/
theorem idCheck_no_prev (d : List String → Option Nat) (r : Samp) : idCheck d none r = none := rfl

/-- `idCheck` reads no time stamp: a longer gap between the two samples changes nothing. -/
theorem idCheck_t0 (d : List String → Option Nat) (q r : Samp) (a b : Option Nat) :
    idCheck d (some { q with t0 := a }) { r with t0 := b } = idCheck d (some q) r := by
  simp [idCheck, hasDriver, inFlight, idFresh]

/-- An undecided sample is `judgeUnit`'s. -/
theorem idJudge_undecided (k : Kind) (d : List String → Option Nat) (seg : List Samp) (win : Option (List Samp))
    (q : Option Samp) (r : Samp) (h : idCheck d q r = none) : idJudge k d seg win q r = judgeUnit k d seg win r := by
  simp [idJudge, h]

/-- The samples of `withPrev ws` are `ws`. -/
theorem withPrev_snd (ws : List Samp) : (withPrev ws).map (·.2) = ws := by
  unfold withPrev
  apply List.ext_getElem
  · simp
  · intro i h1 h2
    simp

/-- A verdict list with a failure combines to a failure. -/
theorem combine_has_fail (vs : List Verdict) (v : Verdict) (hv : v ∈ vs) (hf : isFail v = true) :
    isFail (combine vs) = true := by
  unfold combine
  cases hfind : vs.find? (fun v => match v with | .fail _ => true | _ => false) with
  | some f =>
    have := List.find?_some hfind
    cases f <;> simp_all [isFail]
  | none =>
    rw [List.find?_eq_none] at hfind
    have := hfind v hv
    cases v <;> simp_all [isFail]

/-- The rewrite samples of bucket `b` of phase `p`, as `bucketVerdict` takes them. -/
theorem idBucket_samples (ws : List Samp) (p b : Nat) :
    ((withPrev ws).filter (fun x => x.2.ph == p && bucket x.2.m == b)).map (·.2) =
      (ws.filter (·.ph == p)).filter (fun r => bucket r.m == b) := by
  rw [List.filter_filter]
  conv => rhs; rw [← withPrev_snd ws]
  rw [List.filter_map]
  congr 1
  apply List.filter_congr
  intro x _
  simp [Bool.and_comm]

/-- With no sample decided, `idBucket` is `bucketVerdict`. -/
theorem idBucket_keep (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig ws : List Samp) (p b : Nat)
    (h : ∀ x ∈ withPrev ws, idCheck d x.1 x.2 = none) :
    idBucket ph k d seg orig ws p b = bucketVerdict ph k d seg orig (ws.filter (·.ph == p)) b := by
  unfold idBucket bucketVerdict
  rw [← idBucket_samples]
  have hm : ∀ x ∈ (withPrev ws).filter (fun x => x.2.ph == p && bucket x.2.m == b),
      idJudge k d seg (windowAt ph d seg orig x.2) x.1 x.2 = judgeUnit k d seg (windowAt ph d seg orig x.2) x.2 :=
    fun x hx => idJudge_undecided k d seg _ x.1 x.2 (h x (List.mem_filter.mp hx).1)
  generalize (withPrev ws).filter (fun x => x.2.ph == p && bucket x.2.m == b) = rs at hm ⊢
  cases rs with
  | nil => rfl
  | cons y ys =>
    simp only [List.map_cons, List.map_map]
    rw [hm y List.mem_cons_self, List.map_congr_left (fun x hx => hm x (List.mem_cons_of_mem _ hx))]
    rfl

/-- With no sample decided, `byMId` is `byM`. -/
theorem byMId_keep (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (oSeg wSeg : List Samp)
    (h : ∀ x ∈ withPrev (annotate wSeg), idCheck d x.1 x.2 = none) : byMId ph p k d oSeg wSeg = byM ph p k d oSeg wSeg := by
  simp only [byMId, byM, idBucket_keep _ _ _ _ _ _ _ _ h]

/-- A sample `idJudge` fails fails its bucket. -/
theorem idBucket_fail (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig ws : List Samp) (p b : Nat)
    (x : Option Samp × Samp) (hx : x ∈ withPrev ws) (hp : x.2.ph = p) (hb : bucket x.2.m = b)
    (hf : isFail (idJudge k d seg (windowAt ph d seg orig x.2) x.1 x.2) = true) :
    isFail (idBucket ph k d seg orig ws p b) = true := by
  have hm : x ∈ (withPrev ws).filter (fun x => x.2.ph == p && bucket x.2.m == b) := by
    rw [List.mem_filter]
    exact ⟨hx, by simp [hp, hb]⟩
  unfold idBucket
  generalize (withPrev ws).filter (fun x => x.2.ph == p && bucket x.2.m == b) = rs at hm ⊢
  cases rs with
  | nil => simp at hm
  | cons y ys => exact combine_has_fail _ _ (List.mem_map_of_mem hm) hf

/-- Never more lenient on what it does not decide: an undecided sample `judgeUnit` fails fails its bucket. -/
theorem idBucket_fail_undecided (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig ws : List Samp)
    (p b : Nat) (x : Option Samp × Samp) (hx : x ∈ withPrev ws) (hp : x.2.ph = p) (hb : bucket x.2.m = b)
    (hn : idCheck d x.1 x.2 = none) (hf : isFail (judgeUnit k d seg (windowAt ph d seg orig x.2) x.2) = true) :
    isFail (idBucket ph k d seg orig ws p b) = true :=
  idBucket_fail ph k d seg orig ws p b x hx hp hb (by rw [idJudge_undecided _ _ _ _ _ _ hn]; exact hf)

/-- A sample `idCheck` refuses fails its bucket. -/
theorem idBucket_refuse (ph : Phase) (k : Kind) (d : List String → Option Nat) (seg orig ws : List Samp)
    (p b : Nat) (x : Option Samp × Samp) (hx : x ∈ withPrev ws) (hp : x.2.ph = p) (hb : bucket x.2.m = b)
    (hn : idCheck d x.1 x.2 = some false) : isFail (idBucket ph k d seg orig ws p b) = true :=
  idBucket_fail ph k d seg orig ws p b x hx hp hb (by simp [idJudge, hn, isFail])

/-- Off the nav background `byMRule` is `byMStart`. -/
theorem byMRule_off (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (e : Option EarnRule)
    (oSeg wSeg : List Samp) : byMRule ph p k d e false oSeg wSeg = byMStart ph p k d e oSeg wSeg := rfl

/-- On the nav background `byMRule` is `byMId`. -/
theorem byMRule_on (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (e : Option EarnRule)
    (oSeg wSeg : List Samp) : byMRule ph p k d e true oSeg wSeg = byMId ph p k d oSeg wSeg := rfl

/-- A close at 390 px: `is-morphing` down to 0.002, removed at 0, then the transition to the target in flight. -/
def idSeg : List Samp := [nbOn 3000, nbOn 40, nbOn 20, nbOff 0 4 (fRed 20) (fAlpha 20), nbOff 0 300 252000 (fAlpha 20)]

/-- The rewrite of `idSeg` with the sample after the removal reading `x` and `a`. -/
def idRew (x a : Int) : List Samp := [nbOn 3000, nbOn 40, nbOn 20, nbOff 0 4 x a, nbOff 0 300 252000 (fAlpha 20)]

/-- Mutation early removal: the class goes at 0.03, above the cut. -/
def earlyRew : List Samp :=
  [nbOn 3000, nbOn 600, nbOff 300 4 (fRed 600) (fAlpha 600), nbOff 0 300 252000 (fAlpha 20)]

/-- Mutation late removal: the class stays on at 0, below the cut. -/
def lateRew : List Samp :=
  [nbOn 3000, nbOn 40, nbOn 0, nbOff 0 4 (fRed 0) (fAlpha 0), nbOff 0 300 252000 (fAlpha 20)]

/-- The verdicts of the nav background at 390 px in the close, `o` against `w`. -/
def navAt (o w : List Samp) : List (Nat × Verdict) := byMRule .push 2 .colour navBg none true o w

/-- The original passes against itself at close@0. -/
theorem byMId_self : (navAt idSeg idSeg).lookup 0 = some .pass := by decide +kernel

/-- Mutation early removal, refused at close@0 (`mj ≤ cutM`). -/
theorem byMId_early : (navAt idSeg earlyRew).lookup 0 = some (.fail .apart) := by decide +kernel

/-- Mutation late removal, refused at close@0 (`cutM ≤ mi`). -/
theorem byMId_late : (navAt idSeg lateRew).lookup 0 = some (.fail .apart) := by decide +kernel

/-- Mutation stale reading, the target (red 255), refused at close@0. -/
theorem byMId_stale_target : (navAt idSeg (idRew 255000 (fAlpha 20))).lookup 0 = some (.fail .apart) := by decide +kernel

/-- Mutation stale reading, the frame before the last (0.004), refused at close@0. -/
theorem byMId_stale_frame : (navAt idSeg (idRew (fRed 40) (fAlpha 40))).lookup 0 = some (.fail .apart) := by
  decide +kernel

/-- Mutation wrong f, the mix without premultiplied alpha (red `255 - 236 m`), refused at close@0. -/
theorem byMId_wrong_f : (navAt idSeg (idRew (255000 - 236 * 20 / 10) (fAlpha 20))).lookup 0 = some (.fail .apart) := by
  decide +kernel

/-- Mutation wrong alpha (the target's), refused at close@0. -/
theorem byMId_wrong_alpha : (navAt idSeg (idRew (fRed 20) 255000)).lookup 0 = some (.fail .apart) := by decide +kernel

/-- Limit: the reading must be the transition's start; one red level along it is refused. -/
theorem byMId_progress : (navAt idSeg (idRew (fRed 20 + 1000) (fAlpha 20))).lookup 0 = some (.fail .apart) := by
  decide +kernel

/-- Limit: half a level off the start passes. -/
theorem byMId_half : (navAt idSeg (idRew (fRed 20 + 499) (fAlpha 20 - 499))).lookup 0 = some .pass := by decide +kernel

/-- A rewrite whose first sample without the class is read after `startLag`. -/
def lateReadRew : List Samp := [nbOn 3000, nbOn 40, nbOn 20, nbOff 0 300 255000 (fAlpha 20)]

/-- Limit: a reading taken more than `startLag` ms after the removal is judged by `byM` alone. -/
theorem byMId_read_late : (navAt idSeg lateReadRew).lookup 0 = (byM .push 2 .colour navBg idSeg lateReadRew).lookup 0 := by
  decide +kernel

end CloseIdentity

section FirstFrame

def openPh : Nat := 0

def firstFrame (ph : Phase) (p b : Nat) : Bool := ph == .push && p == openPh && b == 1

def hasBucket (seg : List Samp) (p b : Nat) : Bool := seg.any fun s => s.ph == p && bucket s.m == b

def firstVerdict (ph : Phase) (p b : Nat) (oSeg wSeg : List Samp) (v : Verdict) : Verdict :=
  if firstFrame ph p b && !hasBucket oSeg p b && !hasBucket wSeg p b && v == .fail .coverage
  then .skip .origEmpty else v

def byMFirst (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (e : Option EarnRule) (id : Bool)
    (oSeg wSeg : List Samp) : List (Nat × Verdict) :=
  (byMRule ph p k d e id oSeg wSeg).map fun (b, v) => (b, firstVerdict ph p b oSeg wSeg v)

theorem firstVerdict_both_empty (ph : Phase) (p b : Nat) (oSeg wSeg : List Samp) (hf : firstFrame ph p b = true)
    (ho : hasBucket oSeg p b = false) (hw : hasBucket wSeg p b = false) :
    firstVerdict ph p b oSeg wSeg (.fail .coverage) = .skip .origEmpty := by
  simp [firstVerdict, hf, ho, hw]

theorem firstVerdict_orig_sampled (ph : Phase) (p b : Nat) (oSeg wSeg : List Samp) (v : Verdict)
    (ho : hasBucket oSeg p b = true) : firstVerdict ph p b oSeg wSeg v = v := by
  simp [firstVerdict, ho]

theorem firstVerdict_rew_sampled (ph : Phase) (p b : Nat) (oSeg wSeg : List Samp) (v : Verdict)
    (hw : hasBucket wSeg p b = true) : firstVerdict ph p b oSeg wSeg v = v := by
  simp [firstVerdict, hw]

theorem firstVerdict_not_first (ph : Phase) (p b : Nat) (oSeg wSeg : List Samp) (v : Verdict)
    (hf : firstFrame ph p b = false) : firstVerdict ph p b oSeg wSeg v = v := by
  simp [firstVerdict, hf]

theorem firstVerdict_content (ph : Phase) (p b : Nat) (oSeg wSeg : List Samp) (v : Verdict)
    (hv : v ≠ .fail .coverage) : firstVerdict ph p b oSeg wSeg v = v := by
  have h : (v == Verdict.fail .coverage) = false := by simpa using hv
  simp [firstVerdict, h]

theorem firstVerdict_cases (ph : Phase) (p b : Nat) (oSeg wSeg : List Samp) (v : Verdict) :
    firstVerdict ph p b oSeg wSeg v = v ∨
      (firstFrame ph p b = true ∧ v = .fail .coverage ∧ firstVerdict ph p b oSeg wSeg v = .skip .origEmpty) := by
  unfold firstVerdict
  split
  · rename_i h
    right
    simp only [Bool.and_eq_true, beq_iff_eq] at h
    obtain ⟨⟨⟨hf, _⟩, _⟩, hv⟩ := h
    exact ⟨hf, hv, rfl⟩
  · left; rfl

theorem byMFirst_mem (ph : Phase) (p : Nat) (k : Kind) (d : List String → Option Nat) (e : Option EarnRule) (id : Bool)
    (oSeg wSeg : List Samp) (x : Nat × Verdict) (hx : x ∈ byMFirst ph p k d e id oSeg wSeg) :
    ∃ y ∈ byMRule ph p k d e id oSeg wSeg, x = (y.1, firstVerdict ph p y.1 oSeg wSeg y.2) := by
  unfold byMFirst at hx
  obtain ⟨y, hy, rfl⟩ := List.mem_map.1 hx
  exact ⟨y, hy, rfl⟩

theorem rel_origEmpty_not_new (base : Verdict) : rel (.skip .origEmpty) base ≠ .new := by
  intro h
  have := (rel_new_iff _ _).1 h
  simp [isFail] at this

theorem rel_first_frame_before_after :
    rel (.fail .coverage) .pass = .new ∧ rel (.skip .origEmpty) .pass = .ok := by decide

theorem laneRed_origEmpty : laneRed [rel (.skip .origEmpty) .pass, rel (.skip .origEmpty) (.fail .coverage)] = false := by
  decide

def rampSans (b : Nat) : List Samp :=
  ((List.range 11).filter (· != b)).map fun i => sm ((i * 1000 : Nat) : Int) [.num [((i * 1000 : Nat) : Int)]]

def firstAt (p : Nat) (o w : List Samp) : List (Nat × Verdict) := byMFirst .push p .geometry atRest none false o w

theorem first_neither : (firstAt 0 (rampSans 1) (rampSans 1)).lookup 1 = some (.skip .origEmpty) ∧
    (firstAt 0 (rampSans 1) (rampSans 1)).lookup 5 = some .pass := by decide +kernel

theorem first_orig_only : (firstAt 0 (rampSans 99) (rampSans 1)).lookup 1 = some (.fail .coverage) := by decide +kernel

theorem first_rew_only : (firstAt 0 (rampSans 1) (rampSans 99)).lookup 1 = some .pass := by decide +kernel

theorem first_both : (firstAt 0 (rampSans 99) (rampSans 99)).lookup 1 = some .pass := by decide +kernel

theorem second_neither : (firstAt 0 (rampSans 2) (rampSans 2)).lookup 2 = some (.fail .coverage) ∧
    (firstAt 0 (rampSans 2) (rampSans 2)).lookup 1 = some .pass := by decide +kernel

theorem first_stuck : (firstAt 0 (rampSans 1) []).lookup 1 = some (.skip .origEmpty) ∧
    (firstAt 0 (rampSans 1) []).lookup 5 = some (.fail .coverage) := by decide +kernel

theorem close_neither :
    (firstAt 2 ((rampSans 1).map ({ · with ph := 2 })) ((rampSans 1).map ({ · with ph := 2 }))).lookup 1 =
      some (.fail .coverage) := by decide +kernel

end FirstFrame



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
  | .skip .origEmpty => "skip:origEmpty"

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
    ("rep", toJson s.rep), ("cls", Json.arr (s.cls.map Json.str).toArray), ("ph", toJson s.ph), ("ord", toJson s.ord),
    ("t0", match s.t0 with | none => Json.null | some t => toJson t)]

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
  | start (name : String) (ph : Phase) (p : Nat) (k : Kind) (node prop : String) (width : Nat) (oSeg wSeg : List Samp)
  | startTrs (node prop : String) (width : Nat)
  | checkAt (name : String) (k : Kind) (full : Int) (oSeg prior : List Samp) (r : Samp)
  | settleOn (name : String) (k : Kind) (node prop : String) (width : Nat) (wSeg : List Samp) (r : Samp)
  | curve
  | idRule (name : String) (ph : Phase) (p : Nat) (k : Kind) (node prop : String) (width : Nat) (oSeg wSeg : List Samp)
  | idAt (name : String) (width : Nat) (q : Option Samp) (r : Samp)
  | idConst
  | first (name : String) (ph : Phase) (p : Nat) (k : Kind) (node prop : String) (width : Nat) (oSeg wSeg : List Samp)

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
  .phase "hold colour" .hold 0 .colour none [⟨some 10000, some 0, [.num [43000]], 0, [], 0, 0, none⟩, ⟨some 10000, none, [.num [255000]], 0, [], 0, 0, none⟩]
    [⟨some 10000, some 0, [.num [43000]], 0, [], 0, 0, none⟩, ⟨some 10000, none, [.num [43000]], 0, [], 0, 0, none⟩],
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
  .phase "pooled pass without morph value" .push 0 .discrete none ([⟨none, none, [.num [0]], 0, [], 0, 0, none⟩] ++ ramp 1) [smr 1 4000 [.num [4000]]],
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
  ⟨m, some t, els, rep, cls, ph, ord, none⟩

/-- A sample with no morph value, read `t` ms after the last class change. -/
def st (t : Nat) (els : List Val) : Samp := ⟨none, some t, els, 0, [], 0, 0, none⟩

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

/-- `bgSeg` and a second pass whose transition starts from another red, `[5000, 0, 0]`. -/
def bgSeg2 : List Samp :=
  bgSeg ++ [sc 1 0 [] none 5000 0 [.num [255000, 255000, 255000, 122400]], sc 1 0 [] none 100 1 [.num [5000, 0, 0, 90000]],
    sc 1 0 [] none 300 1 [.num [5000, 0, 0, 50000]], sc 1 0 [] none 5000 1 [.num [255000, 255000, 255000, 26000]]]

/-- **Every pass's start.** A rewrite in pass 0 that starts where the original's pass 1 started passes, and fails
against pass 0 alone. -/
theorem judgeUnit_other_start :
    judgeUnit .colour (durFn bgDurOf) bgSeg2 none (sc 0 0 [] none 100 1 [.num [5000, 0, 0, 90000]]) = .pass ∧
      judgeOwn .colour (durFn bgDurOf) bgSeg2 none (sc 0 0 [] none 100 1 [.num [5000, 0, 0, 90000]]) = .fail .apart := by
  decide

/-- **Pure colour over two passes.** Pure red in flight fails against the envelope of both passes. -/
theorem judgeUnit_red_two_passes :
    judgeUnit .colour (durFn bgDurOf) bgSeg2 none (sc 0 0 [] none 300 1 [.num [255000, 0, 0, 50000]]) = .fail .apart := by
  decide

/-- `boxRamp` read in passes 0 and 1. -/
def boxRamp2 (rev : Bool) : List Samp := boxRamp rev [] ++ (boxRamp rev []).map fun s => { s with rep := 1 }

/-- **The reversed curve over two passes fails in flight.** -/
theorem byM_reversed_two_passes :
    (byM .push 0 .geometry (durFn boxDur) (boxRamp2 false) (boxRamp2 true)).getD 2 (2, .pass) = (2, .fail .apart) := by
  decide

/-- `boxSeg` read in a hold, at morph value 0. -/
def boxHold : List Samp := boxSeg.map fun s => { s with ph := 1, m := some 0 }

/-- A rewrite sample of pass 1, a pass `boxHold` lacks, still at the start box 400 ms into the transition. -/
def stuckHold : Samp := sc 1 1 [] (some 0) 400 0 [.num [0, 0, 400000, 64000]]

/-- **Scope rejected: a stuck value.** Past the start `judgeScoped` falls back to the hold's pooled window and passes a
box stuck at its start value; the envelope fails it. -/
theorem judgeScoped_stuck_hold :
    judgeScoped .geometry (durFn boxDur) boxHold (windowAt .hold (durFn boxDur) boxHold boxHold stuckHold) stuckHold =
      .pass ∧
    judgeUnit .geometry (durFn boxDur) boxHold (windowAt .hold (durFn boxDur) boxHold boxHold stuckHold) stuckHold =
      .fail .apart := by
  decide

/-- A rewrite sample of pass 0 on the curve of `bgSeg2`'s pass 1, 500 ms into the transition. -/
def otherCurve : Samp := sc 0 0 [] none 500 1 [.num [5000, 0, 0, 30000]]

/-- **Scope rejected: start jitter.** A pass that keeps another pass's start red passes the envelope and fails
`judgeScoped`, which judges it against its own pass past the start. -/
theorem judgeScoped_other_curve :
    judgeUnit .colour (durFn bgDurOf) bgSeg2 none otherCurve = .pass ∧
      judgeScoped .colour (durFn bgDurOf) bgSeg2 none otherCurve = .fail .apart := by
  decide

/-- **The mutations fail under the envelope**: pure red and pure green in flight over two passes, the reversed curve at
the start and late in the transition over two passes and in one, a stale class, a stuck value pooled over passes in a
push and stuck in a hold. -/
theorem judgeUnit_mutations :
    judgeUnit .colour (durFn bgDurOf) bgSeg2 none (sc 0 0 [] none 300 1 [.num [255000, 0, 0, 50000]]) = .fail .apart ∧
    judgeUnit .colour (durFn bgDurOf) bgSeg2 none (sc 0 0 [] none 300 1 [.num [0, 255000, 0, 50000]]) = .fail .apart ∧
    (byM .push 0 .geometry (durFn boxDur) (boxRamp2 false) (boxRamp2 true)).getD 2 (2, .pass) = (2, .fail .apart) ∧
    (byM .push 0 .geometry (durFn boxDur) (boxRamp2 false) (boxRamp2 true)).getD 7 (7, .pass) = (7, .fail .apart) ∧
    (byM .push 0 .geometry rectDur (rectRamp false) (rectRamp true)).getD 2 (2, .pass) = (2, .fail .apart) ∧
    (byM .push 0 .discrete atRest [sm 8000 [.str "off"], sm 8500 [.str "off"], sm 9000 [.str "off"], sm 9300 [.str "on"],
        sm 9400 [.str "on"], sm 9500 [.str "on"], sm 9600 [.str "on"], sm 9700 [.str "on"], sm 9900 [.str "on"]]
      [sm 9500 [.str "off"]]).getD 10 (10, .skip .noSample) = (10, .fail .differs) ∧
    (byM .push 0 .discrete atRest (ramp 0 ++ ramp 1 ++ ramp 2) [smr 0 5000 [.num [0]]]).getD 5 (5, .pass) =
      (5, .fail .differs) ∧
    judgeUnit .geometry (durFn boxDur) boxHold (windowAt .hold (durFn boxDur) boxHold boxHold stuckHold) stuckHold =
      .fail .apart :=
  ⟨judgeUnit_red_two_passes, by decide, byM_reversed_two_passes, by decide, byM_reversed_in_flight, byM_stale_class,
    byM_pooled_stuck, judgeScoped_stuck_hold.2⟩

/-- A push of a class from 1.0 to `last`, reading `on` until the last sample, which reads `v`. -/
def endPush (last : Int) (v : String) : List Samp :=
  ((List.range 10).map fun (i : Nat) => sm (10000 - 1000 * i) [.str "on"]) ++ [sm last [.str v]]

/-- The hold after `endPush`: two rows at 0 reading `off`. -/
def endHold : List Samp := [⟨some 0, none, [.str "off"], 0, [], 1, 0, none⟩, ⟨some 0, none, [.str "off"], 0, [], 1, 0, none⟩]

/-- **(b) A settled end of a push.** A rewrite reading `off` at 0, a value the original's push never sampled, passes
against the hold's first row; reading `on` there fails. -/
theorem byM_settled_push_end :
    (byM .push 0 .discrete atRest (endPush 140 "on" ++ endHold) (endPush 0 "off" ++ endHold)).getD 0 (0, .skip .noSample) =
      (0, .pass) ∧
    (byM .push 0 .discrete atRest (endPush 140 "on" ++ endHold) (endPush 0 "on" ++ endHold)).getD 0 (0, .skip .noSample) =
      (0, .fail .differs) := by
  decide

/-- A push that sampled 0 keeps its own window there. -/
theorem byM_sampled_push_end :
    (byM .push 0 .discrete atRest (endPush 0 "on" ++ endHold) (endPush 0 "off" ++ endHold)).getD 0 (0, .skip .noSample) =
      (0, .fail .differs) := by
  decide

/-- `endPush` whose last sample, at 0, reads `v` 100 ms into its transition. -/
def endPushIn (v : String) : List Samp := (endPush 140 "on").dropLast ++ [⟨some 0, some 100, [.str v], 0, [], 0, 0, none⟩]

/-- A rewrite sample in flight at the end of a push keeps `windowOne`: reading `on` passes, reading `off` fails. -/
theorem byM_in_flight_push_end :
    (byM .push 0 .discrete (durFn bgDurOf) (endPush 140 "on" ++ endHold) (endPushIn "on" ++ endHold)).getD 0
        (0, .skip .noSample) = (0, .pass) ∧
    (byM .push 0 .discrete (durFn bgDurOf) (endPush 140 "on" ++ endHold) (endPushIn "off" ++ endHold)).getD 0
        (0, .skip .noSample) = (0, .fail .differs) := by
  decide

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
  .ann "no since after since" [sc 0 0 [] none 10 0 [], ⟨none, none, [], 0, [], 0, 0, none⟩],
  .ann "since after no since" [⟨none, none, [], 0, [], 0, 0, none⟩, sc 0 0 [] none 5 0 []],
  .unit "in flight, inside" .geometry boxDur boxSeg none (sc 0 0 [] none 300 0 [.num [0, 0, 560000, 64000]]),
  .unit "in flight, outside" .geometry boxDur boxSeg none (sc 0 0 [] none 300 0 [.num [0, 0, 760000, 64000]]),
  .unit "in flight, reversed value" .geometry boxDur boxSeg none (sc 0 0 [] none 100 0 [.num [0, 0, 750000, 64000]]),
  .unit "in flight, a pass the original lacks, beyond pass 0" .geometry boxDur boxSeg
    (some [sc 1 0 [] none 300 0 [.num [0, 0, 760000, 64000]]])
    (sc 1 0 [] none 300 0 [.num [0, 0, 760000, 64000]]),
  .unit "in flight, a pass the original lacks, inside pass 0" .geometry boxDur boxSeg none
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

/-- The golden cases of the envelope over passes and the settled end of a push. -/
def casesClose : List Case := [
  .unit "envelope, another pass's start" .colour bgDurOf bgSeg2 none (sc 0 0 [] none 100 1 [.num [5000, 0, 0, 90000]]),
  .unit "envelope, pure red" .colour bgDurOf bgSeg2 none (sc 0 0 [] none 300 1 [.num [255000, 0, 0, 50000]]),
  .unit "envelope, alpha beyond every pass" .colour bgDurOf bgSeg2 none
    (sc 0 0 [] none 300 1 [.num [5000, 0, 0, 200000]]),
  .unit "envelope, pure green" .colour bgDurOf bgSeg2 none (sc 0 0 [] none 300 1 [.num [0, 255000, 0, 50000]]),
  .unit "envelope, another pass's curve past the start" .colour bgDurOf bgSeg2 none otherCurve,
  .unit "envelope, stuck in a hold of a pass the original lacks" .geometry boxDur boxHold
    (windowAt .hold (durFn boxDur) boxHold boxHold stuckHold) stuckHold,
  .phase "reversed curve in flight, two passes" .push 0 .geometry boxDur (boxRamp2 false) (boxRamp2 true),
  .phase "settled push end, hold head" .push 0 .discrete none (endPush 140 "on" ++ endHold) (endPush 0 "off" ++ endHold),
  .phase "settled push end, stuck class" .push 0 .discrete none (endPush 140 "on" ++ endHold)
    (endPush 0 "on" ++ endHold),
  .phase "push sampled its end" .push 0 .discrete none (endPush 0 "on" ++ endHold) (endPush 0 "off" ++ endHold),
  .phase "push end in flight" .push 0 .discrete bgDurOf (endPush 140 "on" ++ endHold) (endPushIn "off" ++ endHold)]

/-- An earn sample reading `x` at morph value `m`, `t` ms after the class change and `5000 + t` ms after the walk began. -/
def es (rep ph : Nat) (cls : List String) (m : Int) (t : Nat) (x : Int) : Samp :=
  ⟨some m, some t, [.num [x]], rep, cls, ph, 0, some (t + 5000)⟩

/-- An earn opacity close at 390 px over two passes, each settling at 1000 from a trigger at 100 ms. -/
def opSeg : List Samp :=
  [es 0 2 [] 6540 0 0, es 0 2 [] 2500 50 0, es 0 2 [] 0 100 0, es 0 2 [] 0 250 544, es 0 2 [] 0 400 852,
    es 0 3 [] 0 900 1000, es 1 2 [] 6540 0 0, es 1 2 [] 0 100 0, es 1 2 [] 0 400 852, es 1 3 [] 0 900 1000]

/-- `opSeg` with the second pass's last close sample read `x` at `t` ms. -/
def opRew (t : Nat) (x : Int) : List Samp :=
  opSeg.take 8 ++ [es 1 2 [] 0 t x, es 1 3 [] 0 900 1000]

/-- An earn max-width close at 1280 px while morphing, settling at 176000 from a trigger at 0 ms, read `x` at 340 ms. -/
def mwSeg (x : Int) : List Samp :=
  [es 0 2 [driver] 6540 0 0, es 0 2 [driver] 0 0 0, es 0 2 [driver] 0 340 x, es 0 3 [] 0 900 176000]

/-- A one-pass earn opacity close with classes `cls` and its trigger at morph value `m`, read `x` at `t` ms. -/
def opOne (cls : List String) (m : Int) (t : Nat) (x : Int) : List Samp :=
  [es 0 2 cls 6540 0 0, es 0 2 cls m 0 0, es 0 2 cls m t x, es 0 3 cls m 900 1000]

/-- A one-pass earn opacity close whose trigger at 50 ms takes the morph from 6540 to `m`, read `x` at 300 ms at 300. -/
def opMid (m : Int) (x : Int) : List Samp :=
  [es 0 2 [] 6540 0 0, es 0 2 [] m 50 0, es 0 2 [] 300 300 x, es 0 3 [] 300 900 1000]

/-- The (property, width) pairs whose value at rest the golden lists: both sides of the phone cut. -/
def fullRows : List (String × Nat) :=
  [("opacity", 390), ("opacity", 1280), ("max-width", 390), ("max-width", 640), ("max-width", 641), ("max-width", 1280)]

/-- The golden cases of the close rule. -/
def casesStart : List Case :=
  [.curve, .startTrs "earn" "opacity" 390, .startTrs "earn" "max-width" 1280, .startTrs "earn" "max-width" 390,
    .startTrs "nav" "opacity" 390,
    .start "self" .push 2 .unit "earn" "opacity" 390 opSeg opSeg,
    .start "in flight" .push 2 .unit "earn" "opacity" 390 opSeg (opRew 400 852),
    .start "in flight, read late" .push 2 .unit "earn" "opacity" 390 opSeg (opRew 480 979),
    .start "in flight, low" .push 2 .unit "earn" "opacity" 390 opSeg (opRew 400 147),
    .start "below the anchor" .push 2 .unit "earn" "opacity" 390 opSeg (opRew 400 (-11)),
    .start "above the value at rest" .push 2 .unit "earn" "opacity" 390 opSeg (opRew 400 1011),
    .start "no trigger" .push 2 .unit "earn" "opacity" 390 opSeg (opSeg.take 6 ++ [es 1 2 [] 0 400 147]),
    .start "a fifth collapsed" .push 2 .unit "earn" "opacity" 390 (opOne [] 400 300 682) (opOne [] 400 300 682),
    .start "pill" .push 2 .unit "earn" "opacity" 390 (opOne ["is-hero-pill"] 0 150 960)
      (opOne ["is-hero-pill"] 0 150 960),
    .start "max-width self" .push 2 .geometry "earn" "max-width" 1280 (mwSeg 120271) (mwSeg 120271),
    .start "not an earn unit" .push 2 .unit "nav" "opacity" 390 opSeg (opRew 400 147),
    .start "another phase" .push 3 .unit "earn" "opacity" 390 opSeg (opRew 400 147),
    .start "a hold of the close's phase" .hold 2 .unit "earn" "opacity" 390 opSeg (opRew 400 147),
    .start "stale start" .push 2 .unit "earn" "opacity" 390 earnSeg staleRew,
    .start "reversed" .push 2 .unit "earn" "opacity" 390 earnSeg reversedRew,
    .start "stays collapsed" .push 2 .unit "earn" "opacity" 390 earnSeg collapsedRew,
    .start "max-width linear" .push 2 .geometry "earn" "max-width" 390 mwOrig linearRew,
    .start "pill on the 320 ms transition" .push 2 .unit "earn" "opacity" 390 pillOrig pillSlowRew,
    .start "trigger at 1000" .push 2 .unit "earn" "opacity" 390 (opMid 1000 331) (opMid 1000 662),
    .start "trigger at 2000, no change of collapse" .push 2 .unit "earn" "opacity" 390 (opMid 2000 331)
      (opMid 2000 662),
    .start "drift" .push 2 .unit "earn" "opacity" 390 driftOrig driftRew,
    .start "moving drift" .push 2 .unit "earn" "opacity" 390 movingOrig movingRew,
    .start "settle self" .hold 3 .unit "earn" "opacity" 390 opSeg opSeg,
    .start "settle, at rest early" .hold 3 .unit "earn" "opacity" 390 opSeg (opSeg.take 9 ++ [es 1 3 [] 0 400 1000]),
    .start "settle reversed" .hold 3 .unit "earn" "opacity" 390 earnSeg reversedRew,
    .start "settle stays collapsed" .hold 3 .unit "earn" "opacity" 390 earnSeg collapsedRew,
    .start "settle towards 0.9" .hold 3 .unit "earn" "opacity" 390 holdSeg targetRew,
    .start "settle on a 463 ms transition" .hold 3 .unit "earn" "opacity" 390 earnSeg slowRew,
    .start "settle drift" .hold 3 .unit "earn" "opacity" 390 driftOrig driftRew,
    .start "max-width settle self" .hold 3 .geometry "earn" "max-width" 1280 (mwSeg 120271) (mwSeg 120271),
    .start "max-width settle at 152 px above a phone" .hold 3 .geometry "earn" "max-width" 1280 (mwSeg 120271)
      ((mwSeg 120271).take 3 ++ [es 0 3 [] 0 900 152000]),
    .start "settle, not an earn unit" .hold 3 .unit "nav" "opacity" 390 earnSeg reversedRew,
    .start "settle, a push of the close-hold" .push 3 .unit "earn" "opacity" 390 earnSeg reversedRew,
    .checkAt "anchor" .unit 1000 earnSeg [ec 6540 0 0] (ec 0 100 0),
    .checkAt "anchor off" .unit 1000 earnSeg [ec 6540 0 0] (ec 0 100 11),
    .checkAt "range" .unit 1000 earnSeg [ec 6540 0 0, ec 0 100 0] (ec 0 400 852),
    .checkAt "range top" .unit 1000 earnSeg [ec 6540 0 0, ec 0 100 0] (ec 0 400 1010),
    .checkAt "above the range" .unit 1000 earnSeg [ec 6540 0 0, ec 0 100 0] (ec 0 400 1011),
    .checkAt "range bottom, anchor 600" .unit 1000 [ec 6540 0 0, ec 0 100 600] [ec 6540 0 0, ec 0 100 600] (ec 0 400 590),
    .checkAt "below the range" .unit 1000 [ec 6540 0 0, ec 0 100 600] [ec 6540 0 0, ec 0 100 600] (ec 0 400 589),
    .checkAt "no trigger yet" .unit 1000 earnSeg [] (ec 6540 0 0),
    .checkAt "no original trigger" .unit 1000 [] [ec 6540 0 0] (ec 0 100 0),
    .checkAt "a reading of two numbers" .unit 1000 earnSeg [ec 6540 0 0] ⟨some 0, none, [.num [0, 1]], 0, [], 2, 0, some 100⟩,
    .settleOn "at rest" .unit "earn" "opacity" 390 [ec 6540 0 0, ec 0 100 0, eh 620 990] (eh 620 990),
    .settleOn "off" .unit "earn" "opacity" 390 [ec 6540 0 0, ec 0 100 0, eh 620 989] (eh 620 989),
    .settleOn "early" .unit "earn" "opacity" 390 [ec 6540 0 0, ec 0 100 0, eh 619 900] (eh 619 900),
    .settleOn "early after the last trigger" .unit "earn" "opacity" 390
      [ec 6540 0 0, ec 0 100 0, ec 1000 200 0, ec 0 300 0, eh 700 900] (eh 700 900),
    .settleOn "late after the last trigger" .unit "earn" "opacity" 390
      [ec 6540 0 0, ec 0 100 0, ec 1000 200 0, ec 0 300 0, eh 820 900] (eh 820 900),
    .settleOn "no trigger" .unit "earn" "opacity" 390 [ec 0 0 0, eh 900 900] (eh 900 900),
    .settleOn "no read time" .unit "earn" "opacity" 390 [ec 6540 0 0, ec 0 100 0, ⟨some 0, none, [.num [0]], 0, [], 3, 0, none⟩]
      ⟨some 0, none, [.num [0]], 0, [], 3, 0, none⟩,
    .settleOn "pill" .unit "earn" "opacity" 390
      [ecl 2 ["is-hero-pill"] 6540 0 0, ecl 2 ["is-hero-pill"] 0 0 0, ecl 3 ["is-hero-pill"] 0 280 989]
      (ecl 3 ["is-hero-pill"] 0 280 989),
    .settleOn "max-width at 1280" .geometry "earn" "max-width" 1280
      [ecl 2 [driver] 6540 0 0, ecl 2 [driver] 0 0 0, ecl 3 [] 0 760 175000] (ecl 3 [] 0 760 175000),
    .settleOn "max-width at 1280, 152 px" .geometry "earn" "max-width" 1280
      [ecl 2 [driver] 6540 0 0, ecl 2 [driver] 0 0 0, ecl 3 [] 0 760 152000] (ecl 3 [] 0 760 152000),
    .settleOn "max-width at 390" .geometry "earn" "max-width" 390
      [ecl 2 [driver] 6540 0 0, ecl 2 [driver] 0 0 0, ecl 3 [] 0 760 152000] (ecl 3 [] 0 760 152000),
    .settleOn "not an earn unit" .unit "nav" "opacity" 390 [ec 6540 0 0, ec 0 100 0, eh 620 0] (eh 620 0)]

/-- The golden cases of the close-start identity. -/
def casesId : List Case :=
  [.idConst,
    .idRule "self" .push 2 .colour "nav" "background-color" 390 idSeg idSeg,
    .idRule "early removal" .push 2 .colour "nav" "background-color" 390 idSeg earlyRew,
    .idRule "late removal" .push 2 .colour "nav" "background-color" 390 idSeg lateRew,
    .idRule "stale target" .push 2 .colour "nav" "background-color" 390 idSeg (idRew 255000 (fAlpha 20)),
    .idRule "stale frame" .push 2 .colour "nav" "background-color" 390 idSeg (idRew (fRed 40) (fAlpha 40)),
    .idRule "wrong f" .push 2 .colour "nav" "background-color" 390 idSeg (idRew (255000 - 236 * 20 / 10) (fAlpha 20)),
    .idRule "wrong alpha" .push 2 .colour "nav" "background-color" 390 idSeg (idRew (fRed 20) 255000),
    .idRule "one level along" .push 2 .colour "nav" "background-color" 390 idSeg (idRew (fRed 20 + 1000) (fAlpha 20)),
    .idRule "half a level off" .push 2 .colour "nav" "background-color" 390 idSeg (idRew (fRed 20 + 499) (fAlpha 20 - 499)),
    .idRule "close-hold" .hold 3 .colour "nav" "background-color" 390 idSeg earlyRew,
    .idRule "two passes" .push 2 .colour "nav" "background-color" 1280 (idSeg ++ idSeg.map ({ · with rep := 1 }))
      (idSeg ++ (idRew 255000 (fAlpha 20)).map ({ · with rep := 1 })),
    .idRule "not the nav background" .push 2 .unit "earn" "opacity" 390 earnSeg staleRew,
    .idAt "faithful" 390 (some (nbOn 20)) (nbOff 0 4 (fRed 20) (fAlpha 20)),
    .idAt "target" 390 (some (nbOn 20)) (nbOff 0 4 255000 (fAlpha 20)),
    .idAt "class on at 9" 390 (some (nbOn 9)) (nbOff 0 4 (fRed 9) (fAlpha 9)),
    .idAt "class on at the cut" 390 (some (nbOn 10)) (nbOff 10 4 (fRed 10) (fAlpha 10)),
    .idAt "class off above the cut" 390 (some (nbOn 600)) (nbOff 11 4 (fRed 600) (fAlpha 600)),
    .idAt "no sample before" 390 none (nbOff 0 4 (fRed 20) (fAlpha 20)),
    .idAt "both off" 390 (some (nbOff 0 4 0 0)) (nbOff 0 4 (fRed 20) (fAlpha 20)),
    .idAt "both on" 390 (some (nbOn 30)) (nbOn 20),
    .idAt "settled" 390 (some (nbOn 20)) (nbOff 0 900 (fRed 20) (fAlpha 20)),
    .idAt "at the start lag" 390 (some (nbOn 20)) (nbOff 0 200 (fRed 20) (fAlpha 20)),
    .idAt "after the start lag" 390 (some (nbOn 20)) (nbOff 0 201 (fRed 20) (fAlpha 20)),
    .idAt "read late, near the end" 390 (some (nbOn 1174)) (nbOff 0 694 253656 26113),
    .idAt "no class change" 390 (some (nbOn 20)) (nb [] 0 none (fRed 20) (fAlpha 20)),
    .idAt "a string" 390 (some (nbOn 20)) ⟨some 0, some 4, [.str "x"], 0, [], 2, 0, none⟩,
    .idAt "three numbers" 390 (some (nbOn 20)) ⟨some 0, some 4, [.num [1, 2, 3]], 0, [], 2, 0, none⟩,
    .idAt "no morph value" 390 (some (nbOn 20)) ⟨none, some 4, [.num [fRed 20, 0, 0, fAlpha 20]], 0, [], 2, 0, none⟩,
    .idAt "no morph value before" 390 (some ⟨none, some 0, [], 0, [driver], 2, 0, none⟩) (nbOff 0 4 (fRed 20) (fAlpha 20))]

/-- Golden `(m, red, alpha)` rows of `redOk` and `alphaOk`, on both sides of each bound. -/
def idRows : List (Int × Int × Int) :=
  [(0, 255500, 26500), (0, 255501, 26501), (0, 254500, 25500), (0, 254499, 25499), (20, fRed 20, fAlpha 20),
    (20, fRed 20 - 499, fAlpha 20 + 500), (20, fRed 20 - 500, fAlpha 20 + 501), (20, fRed 20 + 500, fAlpha 20 - 500),
    (20, fRed 20 + 501, fAlpha 20 - 501), (138, 226520, 29760), (138, 227010, 29760), (138, 226030, 29760),
    (10000, 19500, 255500), (10000, 19501, 255501), (10000, 18500, 254500), (10000, 18499, 254499)]

def casesFirst : List Case :=
  let earn := fun (ph : Phase) (p : Nat) (n : String) (o w : List Samp) =>
    Case.first n ph p .geometry "earn" "max-width" 390 o w
  [earn .push 0 "first frame, neither arm" (rampSans 1) (rampSans 1),
    earn .push 0 "first frame, original only" (rampSans 99) (rampSans 1),
    earn .push 0 "first frame, rewrite only" (rampSans 1) (rampSans 99),
    earn .push 0 "first frame, both" (rampSans 99) (rampSans 99),
    earn .push 0 "first frame, rewrite wrong" (rampSans 1) (sm 1000 [.num [9000]] :: rampSans 99),
    earn .push 0 "second bucket, neither arm" (rampSans 2) (rampSans 2),
    earn .push 0 "first frame, stuck rewrite" (rampSans 1) [],
    earn .push 2 "close push, neither arm" ((rampSans 1).map ({ · with ph := 2 })) ((rampSans 1).map ({ · with ph := 2 })),
    earn .hold 1 "hold, neither arm" ((rampSans 1).map ({ · with ph := 1 })) ((rampSans 1).map ({ · with ph := 1 })),
    .first "nav background, neither arm" .push 0 .colour "nav" "background-color" 390 (rampSans 1) (rampSans 1)]

def cases : List Case :=
  casesJudge ++ casesRest ++ casesPlan ++ casesFlight ++ casesClose ++ casesStart ++ casesId ++ casesFirst

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

/-- A rational as JSON: its numerator and denominator as decimal strings. -/
def ratJson (q : Rat) : Json := Json.mkObj [("num", toString q.num), ("den", toString q.den)]

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
  | .start n ph p k node prop w o s =>
    Json.mkObj [("op", "byMStart"), ("name", n), ("phase", ph.name), ("p", toJson p), ("kind", k.name),
      ("node", node), ("prop", prop), ("width", toJson w), ("oSeg", Json.arr (o.map Samp.json).toArray),
      ("wSeg", Json.arr (s.map Samp.json).toArray),
      ("verdicts", Json.arr ((byMStart ph p k (durOf node prop w) (startFor node prop w) o s).map fun (_, v) =>
        Json.str v.name).toArray)]
  | .startTrs node prop w =>
    Json.mkObj [("op", "start"), ("name", s!"{node} {prop} {w}"), ("node", node), ("prop", prop), ("width", toJson w),
      ("on", Json.bool (startOn node prop)), ("classes", Json.arr (navClasses.map Json.str).toArray),
      ("trs", Json.arr ((List.range 64).map fun k => match startTr node prop w (maskCls k) with
        | none => Json.null
        | some (d, l) => Json.arr #[toJson d, toJson l]).toArray)]
  | .checkAt n k full o prior r =>
    Json.mkObj [("op", "startCheck"), ("name", n), ("kind", k.name), ("full", toJson full),
      ("oSeg", Json.arr (o.map Samp.json).toArray), ("prior", Json.arr (prior.map Samp.json).toArray), ("r", r.json),
      ("check", match startCheck k full o prior r with | none => Json.null | some b => Json.bool b)]
  | .settleOn n k node prop w seg r =>
    Json.mkObj [("op", "settleCheck"), ("name", n), ("kind", k.name), ("node", node), ("prop", prop),
      ("width", toJson w), ("seg", Json.arr (seg.map Samp.json).toArray), ("r", r.json),
      ("check", match startFor node prop w with
        | none => Json.null
        | some e => match settleCheck k e seg r with | none => Json.null | some b => Json.bool b)]
  | .curve =>
    Json.mkObj [("op", "curve"), ("name", "earn"), ("jitter", toJson startJitter), ("close", toJson closePh),
      ("darkCut", ratJson (Fw.Parts.Nav.darkCut * 10000)),
      ("bez", Json.arr #[ratJson earnCurve.x1, ratJson earnCurve.y1, ratJson earnCurve.x2, ratJson earnCurve.y2]),
      ("full", Json.arr (fullRows.map fun (p, w) => Json.arr #[Json.str p, toJson w, ratJson (fullOf p w)]).toArray)]
  | .idRule n ph p k node prop w o s =>
    Json.mkObj [("op", "byMRule"), ("name", n), ("phase", ph.name), ("p", toJson p), ("kind", k.name),
      ("node", node), ("prop", prop), ("width", toJson w), ("id", Json.bool (idOn node prop)),
      ("oSeg", Json.arr (o.map Samp.json).toArray), ("wSeg", Json.arr (s.map Samp.json).toArray),
      ("verdicts", Json.arr ((byMRule ph p k (durOf node prop w) (startFor node prop w) (idOn node prop) o s).map
        fun (_, v) => Json.str v.name).toArray)]
  | .first n ph p k node prop w o s =>
    Json.mkObj [("op", "byMFirst"), ("name", n), ("phase", ph.name), ("p", toJson p), ("kind", k.name),
      ("node", node), ("prop", prop), ("width", toJson w), ("id", Json.bool (idOn node prop)),
      ("oSeg", Json.arr (o.map Samp.json).toArray), ("wSeg", Json.arr (s.map Samp.json).toArray),
      ("verdicts", Json.arr ((byMFirst ph p k (durOf node prop w) (startFor node prop w) (idOn node prop) o s).map
        fun (_, v) => Json.str v.name).toArray)]
  | .idAt n w q r =>
    Json.mkObj [("op", "idCheck"), ("name", n), ("width", toJson w),
      ("q", match q with | none => Json.null | some q => q.json), ("r", r.json),
      ("check", match idCheck (durOf "nav" "background-color" w) q r with | none => Json.null | some b => Json.bool b)]
  | .idConst =>
    Json.mkObj [("op", "identity"), ("name", "nav background"), ("cut", toJson cutM),
      ("cutRat", ratJson (Fw.Parts.Nav.morphingCut * 10000)),
      ("from", Json.arr #[toJson mixFrom.1, toJson mixFrom.2]), ("to", Json.arr #[toJson mixTo.1, toJson mixTo.2]),
      ("rows", Json.arr (idRows.map fun (m, x, a) =>
        Json.arr #[toJson m, toJson x, toJson a, Json.bool (redOk m x), Json.bool (alphaOk m a)]).toArray)]

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
