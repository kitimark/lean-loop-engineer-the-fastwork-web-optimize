import Fw.Engine.Chromium
import Fw.Engine.WebKit
import Fw.Ops.Premise
import Lean.Data.Json
/-!
# Engine premise tests (task engine-premise-measure)

The engine goldens (`packages/contracts/golden/engine/**`) predict browser counts from the Lean engine models
`Fw.Engine.Chromium` and `Fw.Engine.WebKit`. Every prediction rests on a *stage rule*: the per-frame count of a
stage's counters is ordered like the model's work of that stage. `Fw.Ops.Premise.untestedPremises` lists the rules
nobody had measured. This module is the spec of the measurement:

* **Cases.** One fixture page per engine holds one element per (property, layer state) member of the model's table
  that a page can realize (`crCases`, `wkCases`). A case is a frame in which one change happens (or a script callback,
  or a hit test); every case is followed by an idle frame (`steps`). Everything the page needs (the element's style,
  the changed property and value, the layer hint) is data generated from here.
* **Expectation.** The expected presence of every observed stage in a frame is *computed from the model*:
  `0 < frameWork(f).passes(s)` (Chromium: with the hit-test PrePaint correction `crWorkH`). For frames
  without forced reads, `passes` is 0 or 1, so presence is all a count of a stage can say; `units` is not observed by
  a presence test, and the registry statements of the moved premises say so.
* **Verdict.** Per (step, stage) the observed presences of all passes of all jobs form a cell: `agree`, `mismatch`
  (every pass off the model), `unstable` (passes disagree) or `missing`. A premise (a stage rule) is `holds` iff
  every cell of its stage agrees, `fails` iff some cell is a mismatch, else `inconclusive`. The TS port is
  `packages/measure-chromium/src/premise-verdict.mjs`, checked against the golden vectors.

The golden `packages/contracts/golden/ops/engine-premises.jsonl` (observers, steps, excluded members, verdict vectors)
is generated, never hand-written:

```
cd lean && lake env lean --run scripts/EnginePremiseGolden.lean           # write
cd lean && lake env lean --run scripts/EnginePremiseGolden.lean --check   # fail if stale
```
-/
namespace Fw.Ops.EnginePremise
open Lean (Json)
open Fw.Engine (Stage LayerState Change FrameIn Work frameWork)
open Fw.Engine.Chromium (CrKey CrProp CrLevel)
open Fw.Engine.WebKit (WkProp)

/-! ## Observers and expectations -/

/-- What a test reads for one stage: the stage's name, the model stage it observes (`none` for the hit-test count,
which is `Work.hits`), and the counters whose sum is the observation (present iff the sum is positive).
-/
structure Observer where
  stage : String
  model : Option Stage
  counters : List String

/-- **Chromium's observers**: one per counted stage the lane can observe per frame (the compositor stage `comp` is
not observed: `census.layers` is positive in every frame).
-/
def crObservers : List Observer :=
  [⟨"script", some .script, ["trace.FireAnimationFrame", "trace.FunctionCall"]⟩,
   ⟨"style", some .style, ["trace.UpdateLayoutTree"]⟩, ⟨"layout", some .layout, ["trace.Layout"]⟩,
   ⟨"props", some .props, ["trace.PrePaint"]⟩, ⟨"paint", some .paint, ["trace.Paint"]⟩,
   ⟨"raster", some .raster, ["trace.RasterTask"]⟩, ⟨"commit", some .commit, ["trace.cc.Commit"]⟩,
   ⟨"hits", none, ["trace.HitTest"]⟩]

/-- **WebKit's observers** (WebKitTestRunner internals counters, per rendering update): the stages that have a
counter. `script` (no `FireAnimationFrame` counter; the harness's own rAF would be circular) and `paint` (no paint
counter) are not observable.
-/
def wkObservers : List Observer :=
  [⟨"style", some .style, ["styleRecalcs"]⟩, ⟨"layout", some .layout, ["layoutUpdates"]⟩,
   ⟨"props", some .props, ["compositingUpdates"]⟩, ⟨"commit", some .commit, ["layerFlushes"]⟩]

/-- The model's expected presence of an observer in a frame with work `w`: the stage ran at least once (hits: at
least one hit test).
-/
def expectOf (w : Work) (o : Observer) : Bool :=
  match o.model with
  | some s => decide (0 < w.passes s)
  | none => decide (0 < w.hits)

/-- The expected presences of all observers `os` in a frame with work `w`, by stage name. -/
def expectAll (os : List Observer) (w : Work) : List (String × Bool) := os.map fun o => (o.stage, expectOf w o)

/-- The stage names expected present, in observer order. -/
def names (e : List (String × Bool)) : List String := (e.filter (·.2)).map (·.1)

/-! ## Cases -/

/-- What the page does in a frame: set one property of the case's element and of each extra element (`set`), run one
rAF callback with no change (`raf`), pass an empty callback to the page's `setTimeout(0)` (`shimTimer`), call
`document.elementFromPoint` (`hit`), or nothing (`idle`). In the Chromium lane the page's `setTimeout` is the virtual
clock shim's (`packages/measure-chromium/src/clock-shim.js:38`), and the driver's `advanceTo` runs the callback as a
plain call (`clock-shim.js:59`) inside the same `Runtime.evaluate` that runs the step (`run.mjs:108`), so `shimTimer`
is not a Chromium timer task.
-/
inductive Act where
  | set | raf | shimTimer | hit | idle
deriving DecidableEq, Repr

/-- The act's name in the golden. -/
def Act.name : Act → String
  | .set => "set" | .raf => "raf" | .shimTimer => "shimTimer" | .hit => "hit" | .idle => "idle"

/-- One measured frame: the member id, the act, the element's inline style before the frame (`style`), the changed
property and its new value (`set` only), the extra elements changed in the same frame (`more`: each one's style,
property and new value; empty for a one-change frame), and the model's expected presence per observed stage.
-/
structure Case where
  id : String
  act : Act
  style : String := ""
  prop : String := ""
  to : String := ""
  more : List (String × String × String) := []
  expect : List (String × Bool)

/-- How a property is changed on a page: its CSS name, the value before and the value after. -/
structure Css where
  prop : String
  v0 : String
  v1 : String

/-- The inline style of an element in layer state `l`: none, a positioned box (a paint layer), or a positioned box with
the will-change hint `h` (its own composited layer).
-/
def layerStyle (l : LayerState) (hint : String) : String :=
  match l with
  | .none => ""
  | .layer => "position:relative;"
  | .own => "position:relative;will-change:" ++ hint ++ ";"

/-- The base style every element of the page shares (a 20 px box with a colour, a gradient, a letter and a border in the text colour, so that a colour change is visible without glyphs); the case's
inline style follows it, so a case's own declarations win.
-/
def baseStyle : String :=
  "width:20px;height:20px;background-color:#ccc;background-image:linear-gradient(#f00,#00f);color:#000;border:2px solid;font:10px/10px monospace;"

/-- The idle frame after every case: no script, no change, no hit test. -/
def idleFrame {P : Type} : FrameIn P := ⟨0, 0, 0, 0, [], 0⟩

/-- The steps of the page: every case, each followed by an idle frame (so a late async stage lands in a frame that
expects nothing, and a mismatch there is visible).

Here `e` is the idle frame's expectation list, passed in by the caller.
-/
def steps (idle : List (String × Bool)) (cs : List Case) : List Case :=
  cs.flatMap fun c => [c, { id := c.id ++ "+idle", act := .idle, expect := idle }]

/-! ## Chromium cases -/

/-- The three layer states, in table order. -/
def layers : List LayerState := [.none, .layer, .own]

/-- **How each Chromium property is changed.** `strokeDashoffset` has no entry: it is an SVG-only property, and an SVG
element's layer states are not those of the page's boxes, so it is not measured.
-/
def crCss : CrKey → Option Css
  | .transform => some ⟨"transform", "translateX(10px)", "translateX(20px)"⟩
  | .transformToggle => some ⟨"transform", "none", "translateX(10px)"⟩
  | .translate => some ⟨"translate", "10px 0px", "20px 0px"⟩
  | .scale => some ⟨"scale", "1.1", "1.2"⟩
  | .rotate => some ⟨"rotate", "5deg", "10deg"⟩
  | .opacity => some ⟨"opacity", "0.5", "0.6"⟩
  | .filter false => some ⟨"filter", "brightness(0.9)", "brightness(0.8)"⟩
  | .filter true => some ⟨"filter", "blur(2px)", "blur(4px)"⟩
  | .backdropFilter => some ⟨"backdrop-filter", "blur(2px)", "blur(4px)"⟩
  | .backgroundPosition => some ⟨"background-position", "0px 0px", "5px 5px"⟩
  | .backgroundImage => some ⟨"background-image", "linear-gradient(#f00,#00f)", "linear-gradient(#00f,#f00)"⟩
  | .backgroundColor => some ⟨"background-color", "#ccc", "#bbb"⟩
  | .color => some ⟨"color", "#000", "#111"⟩
  | .clipPath => some ⟨"clip-path", "inset(0px)", "inset(2px)"⟩
  | .strokeDashoffset => none
  | .visibility => some ⟨"visibility", "visible", "hidden"⟩
  | .zIndex => some ⟨"z-index", "0", "1"⟩
  | .top => some ⟨"top", "0px", "2px"⟩
  | .left => some ⟨"left", "0px", "2px"⟩
  | .width => some ⟨"width", "20px", "24px"⟩
  | .height => some ⟨"height", "20px", "24px"⟩
  | .margin => some ⟨"margin", "0px", "2px"⟩
  | .padding => some ⟨"padding", "0px", "2px"⟩

/-- The will-change hint that gives an element its own composited layer for a property: the property itself for the
compositable ones, `transform` for the rest.
-/
def crHint : CrKey → String
  | .translate => "translate" | .scale => "scale" | .rotate => "rotate" | .opacity => "opacity"
  | .filter _ => "filter" | .backdropFilter => "backdrop-filter" | _ => "transform"

/-- Properties that act only on a positioned box (a positioned box always has a paint layer, so the state `none` does
not exist for them).
-/
def crPositioned : CrKey → Bool
  | .top | .left | .zIndex => true
  | _ => false

/-- A member (property, layer state) of the Chromium table is realizable on a page iff the property has a CSS spelling
here and, for a positioned-only property, the box is not in state `none`.
-/
def crRealizable (k : CrKey) (l : LayerState) : Bool :=
  (crCss k).isSome && !(crPositioned k && l == .none)

/-- All 69 members of the Chromium signature table (23 plain properties times three layer states). -/
def crMembers : List (CrKey × LayerState) := CrKey.all.flatMap fun k => layers.map fun l => (k, l)

/-- The id of a member as `chromium.jsonl` writes it. -/
def memberId (k : CrKey) (l : LayerState) : String := k.name ++ "@" ++ Fw.Engine.Chromium.layerName l

/-- The model's work of a Chromium frame in the lane (with the hit-test PrePaint correction `crWorkH`). -/
def crWork (f : FrameIn CrProp) : Work := Fw.Engine.Chromium.crWorkH Fw.Engine.Chromium.lane f

/-- The frame of a member: one change of the property at the layer state. -/
def crFrame (k : CrKey) (l : LayerState) : FrameIn CrProp := ⟨0, 0, 0, 0, [⟨0, .css k, l⟩], 0⟩

/-- **The Chromium cases**: every realizable member as a `set`, a script-only frame (one rAF callback) and a hit-test
frame.
-/
def crCases : List Case :=
  (crMembers.filterMap fun (k, l) =>
    match crCss k with
    | some c =>
      if crRealizable k l then
        some { id := memberId k l, act := .set, style := layerStyle l (crHint k) ++ c.prop ++ ":" ++ c.v0 ++ ";",
               prop := c.prop, to := c.v1, expect := expectAll crObservers (crWork (crFrame k l)) }
      else none
    | none => none) ++
  [{ id := "script", act := .raf, expect := expectAll crObservers (crWork ⟨1, 0, 0, 0, [], 0⟩) },
   { id := "hit", act := .hit, expect := expectAll crObservers (crWork ⟨0, 0, 0, 1, [], 0⟩) }]

/-- The Chromium table steps (each case of the table and its idle frame), the steps of CI run 39088367495. -/
def crSteps0 : List Case := steps (expectAll crObservers (crWork idleFrame)) crCases

/-! ## Chromium extra cases (task engine-model-fix-2): a clock-shim control, joins, frames with two changes -/

/-- The model's Chromium frame of a list of changes and nothing else. -/
def crFrames (cs : List (Change CrProp)) : FrameIn CrProp := ⟨0, 0, 0, 0, cs, 0⟩

/-- **A join case**: one element on its own layer (will-change `hints`) whose readers `rs` all read the custom property
`--x` (their CSS in `css`); the frame sets `--x` from `0` to `1`, a custom-property change with readers `rs`.

One custom-property write read by several properties of one box. -/
def crJoin (id : String) (rs : List CrKey) (hints css : String) : Case :=
  { id, act := .set, style := layerStyle .own hints ++ "--x:0;" ++ css, prop := "--x", to := "1",
    expect := expectAll crObservers (crWork (crFrames [⟨0, .custom 0 rs, .own⟩])) }

/-- **A two-element case**: the table members `a` and `b` changed in one frame, `a` on the case's box and `b` on an
extra box; `none` if a member has no CSS spelling or is not realizable.

Two boxes changed in the same frame. -/
def crPair (a b : CrKey × LayerState) : Option Case :=
  match crCss a.1, crCss b.1 with
  | some ca, some cb =>
    if crRealizable a.1 a.2 && crRealizable b.1 b.2 then
      some { id := memberId a.1 a.2 ++ "+" ++ memberId b.1 b.2, act := .set,
             style := layerStyle a.2 (crHint a.1) ++ ca.prop ++ ":" ++ ca.v0 ++ ";", prop := ca.prop, to := ca.v1,
             more := [(layerStyle b.2 (crHint b.1) ++ cb.prop ++ ":" ++ cb.v0 ++ ";", cb.prop, cb.v1)],
             expect := expectAll crObservers (crWork (crFrames [⟨0, .css a.1, a.2⟩, ⟨1, .css b.1, b.2⟩])) }
    else none
  | _, _ => none

/-- **The Chromium extra cases**: a harness control `shimTimer` (the clock shim runs its empty callback inside the
driver's evaluate of the step, where the `set` and `hit` steps also run their page calls, and the model counts that
evaluate as no script callback, so it expects an idle frame; it is not a Chromium timer task, see `Act`); three joins
(`top` and `scale`, `top` and `transform`, `background-color` and `opacity` on one own-layer box); three two-element
frames (`top@own` with `scale@own`, `transform@own` with `background-color@none`, `top@own` with `transform@own`); a
pair that is `⊥` is dropped (none is, `extra_counts`).

The frames that test how levels combine, after one harness control. -/
def crExtraCases : List Case :=
  [{ id := "shimTimer", act := .shimTimer, expect := expectAll crObservers (crWork idleFrame) },
   crJoin "custom[top,scale]@own" [.top, .scale] "transform,scale"
     "top:calc(var(--x) * 2px);scale:calc(1.1 + var(--x) * 0.1);",
   crJoin "custom[top,transform]@own" [.top, .transform] "transform"
     "top:calc(var(--x) * 2px);transform:translateX(calc(10px + var(--x) * 10px));",
   crJoin "custom[backgroundColor,opacity]@own" [.backgroundColor, .opacity] "opacity"
     "opacity:calc(0.5 + var(--x) * 0.1);background-color:rgb(calc(200 + var(--x) * 10), 200, 200);"] ++
  ([((CrKey.top, LayerState.own), (CrKey.scale, LayerState.own)),
    ((.transform, .own), (.backgroundColor, .none)), ((.top, .own), (.transform, .own))].filterMap
    fun (a, b) => crPair a b)

/-- The Chromium steps: the table steps, then each extra case and its idle frame. -/
def crSteps : List Case := crSteps0 ++ steps (expectAll crObservers (crWork idleFrame)) crExtraCases

/-- The members the Chromium page does not realize, with the reason. -/
def crExcluded : List (String × String) :=
  crMembers.filterMap fun (k, l) =>
    if crRealizable k l then none
    else some (memberId k l, if (crCss k).isNone then "SVG-only property: not a box of the page" else
      "acts only on a positioned box, which always has a paint layer")

/-! ## WebKit cases -/

/-- **How each WebKit property is changed** (`none`: not measured). Not measured, with the reason: `filterPainted`,
`clipPath`, `clipPathShape` (whether the filter or clip is composited depends on the shape and the layer), `willChange`
(the change moves the layer state itself), `colorCurrent`, `strokeDashoffset` (SVG-only) and `scrollPos` (the scroll
step has its own table, `scrollStep`).
-/
def wkCss : WkProp → Option Css
  | .transform => some ⟨"transform", "translateX(10px)", "translateX(20px)"⟩
  | .transformToggle => some ⟨"transform", "none", "translateX(10px)"⟩
  | .opacity => some ⟨"opacity", "0.5", "0.6"⟩
  | .opacityCross1 => some ⟨"opacity", "1", "0.5"⟩
  | .filter => some ⟨"filter", "blur(2px)", "blur(4px)"⟩
  | .filterToggle => some ⟨"filter", "none", "blur(2px)"⟩
  | .background => some ⟨"background-color", "#ccc", "#bbb"⟩
  | .color => some ⟨"color", "#000", "#111"⟩
  | .mask => some ⟨"mask-image", "linear-gradient(#000,transparent)", "linear-gradient(transparent,#000)"⟩
  | .insetAbs => some ⟨"top", "0px", "2px"⟩
  | .inset => some ⟨"top", "0px", "2px"⟩
  | .size => some ⟨"width", "20px", "24px"⟩
  | _ => none

/-- The WebKit property's name in the cases (the constructor name). -/
def wkName : WkProp → String
  | .transform => "transform" | .transformToggle => "transformToggle" | .opacity => "opacity"
  | .opacityCross1 => "opacityCross1" | .filter => "filter" | .filterPainted => "filterPainted"
  | .filterToggle => "filterToggle" | .clipPath => "clipPath" | .clipPathShape => "clipPathShape"
  | .willChange => "willChange" | .background => "background" | .color => "color" | .colorCurrent => "colorCurrent"
  | .mask => "mask" | .insetAbs => "insetAbs" | .inset => "inset" | .size => "size"
  | .strokeDashoffset => "strokeDashoffset" | .scrollPos => "scrollPos"

/-- All WebKit properties once. -/
def wkAll : List WkProp :=
  [.transform, .transformToggle, .opacity, .opacityCross1, .filter, .filterPainted, .filterToggle, .clipPath,
   .clipPathShape, .willChange, .background, .color, .colorCurrent, .mask, .insetAbs, .inset, .size,
   .strokeDashoffset, .scrollPos]

/-- The will-change hint for an own layer. -/
def wkHint : WkProp → String
  | .opacity | .opacityCross1 => "opacity"
  | .filter | .filterToggle => "filter"
  | _ => "transform"

/-- A property whose very presence gives the box a layer (a transformed, translucent, filtered or masked box has a
layer), so the state `none` does not exist for its value changes; the toggles and crossings are the changes that
create the layer.
-/
def wkMakesLayer : WkProp → Bool
  | .transform | .opacity | .filter | .mask => true
  | _ => false

/-- Positioned-box properties (a positioned box always has a layer, so `none` does not exist for them). -/
def wkPositioned : WkProp → Bool
  | .insetAbs | .inset => true
  | _ => false

/-- The inline layer style of a WebKit member: `insetAbs` uses an absolute box (with the transform hint for an own
layer), every other property the shared `layerStyle` with its own hint.
-/
def wkLayerStyle (p : WkProp) (l : LayerState) : String :=
  match p, l with
  | .insetAbs, .none => ""
  | .insetAbs, .layer => "position:absolute;"
  | .insetAbs, .own => "position:absolute;will-change:transform;"
  | _, _ => layerStyle l (wkHint p)

/-- A WebKit member is realizable iff the property is measured and the state exists for it. -/
def wkRealizable (p : WkProp) (l : LayerState) : Bool :=
  (wkCss p).isSome && !((wkMakesLayer p || wkPositioned p) && l == .none)

/-- All 57 members of the WebKit table. -/
def wkMembers : List (WkProp × LayerState) := wkAll.flatMap fun p => layers.map fun l => (p, l)

/-- The id of a WebKit member. -/
def wkMemberId (p : WkProp) (l : LayerState) : String := wkName p ++ "@" ++ Fw.Engine.Chromium.layerName l

/-- The model's work of a WebKit frame in the page: the harness's own rAF callback runs in every frame (script 1), so a
frame with one change is `jsFrame [c]` and an idle frame `jsFrame []`.
-/
def wkWork (cs : List (Change WkProp)) : Work :=
  frameWork Fw.Engine.WebKit.webkit (Fw.Engine.WebKit.jsFrame cs)

/-- **The WebKit cases**: every realizable member as a `set`. -/
def wkCases : List Case :=
  wkMembers.filterMap fun (p, l) =>
    match wkCss p with
    | some c =>
      if wkRealizable p l then
        some { id := wkMemberId p l, act := .set, style := wkLayerStyle p l ++ c.prop ++ ":" ++ c.v0 ++ ";",
               prop := c.prop, to := c.v1, expect := expectAll wkObservers (wkWork [⟨0, p, l⟩]) }
      else none
    | none => none

/-- The WebKit table steps (each case and its idle frame, which still runs the harness's rAF callback), the steps of
CI run 39088367495.
-/
def wkSteps0 : List Case := steps (expectAll wkObservers (wkWork [])) wkCases

/-- **A WebKit two-element case**: the members `a` and `b` changed in one frame, `a` on the case's box and `b` on an
extra box; `none` if a member has no CSS spelling or is not realizable.

Two boxes changed in the same WebKit frame. -/
def wkPair (a b : WkProp × LayerState) : Option Case :=
  match wkCss a.1, wkCss b.1 with
  | some ca, some cb =>
    if wkRealizable a.1 a.2 && wkRealizable b.1 b.2 then
      some { id := wkMemberId a.1 a.2 ++ "+" ++ wkMemberId b.1 b.2, act := .set,
             style := wkLayerStyle a.1 a.2 ++ ca.prop ++ ":" ++ ca.v0 ++ ";", prop := ca.prop, to := ca.v1,
             more := [(wkLayerStyle b.1 b.2 ++ cb.prop ++ ":" ++ cb.v0 ++ ";", cb.prop, cb.v1)],
             expect := expectAll wkObservers (wkWork [⟨0, a.1, a.2⟩, ⟨1, b.1, b.2⟩]) }
    else none
  | _, _ => none

/-- **The WebKit extra cases** (task engine-model-fix-2): three two-element frames, `opacity@own` with
`background@layer`, `opacity@own` with `size@none`, `transform@own` with `color@own`.

The
WebKit frames that test whether two changes take the union of their stages. -/
def wkExtraCases : List Case :=
  [((WkProp.opacity, LayerState.own), (WkProp.background, LayerState.layer)),
   ((.opacity, .own), (.size, .none)), ((.transform, .own), (.color, .own))].filterMap fun (a, b) => wkPair a b

/-- The WebKit steps: the table steps, then each extra case and its idle frame. -/
def wkSteps : List Case := wkSteps0 ++ steps (expectAll wkObservers (wkWork [])) wkExtraCases

/-! ## Step sets -/

/-- The step set of a step: the property table and its idle frames (`table`), or the extra cases of task
engine-model-fix-2 and their idle frames (`extra`). The lane decides each stage once per step set.
-/
inductive Group where
  | table | extra
deriving DecidableEq, Repr

/-- The step set's name in the golden. -/
def Group.name : Group → String
  | .table => "table" | .extra => "extra"

/-- The Chromium steps with their step set: the table steps are `table`, the extra steps `extra`. -/
def crGrouped : List (Case × Group) :=
  crSteps0.map (·, .table) ++ (steps (expectAll crObservers (crWork idleFrame)) crExtraCases).map (·, .extra)

/-- The WebKit steps with their step set: the table steps are `table`, the extra steps `extra`. -/
def wkGrouped : List (Case × Group) :=
  wkSteps0.map (·, .table) ++ (steps (expectAll wkObservers (wkWork [])) wkExtraCases).map (·, .extra)

/-- The steps of a step set, in order. -/
def stepsOf (gs : List (Case × Group)) (g : Group) : List Case := (gs.filter fun x => decide (x.2 = g)).map (·.1)

#guard (stepsOf [({ id := "a", act := .idle, expect := [] }, .table), ({ id := "b", act := .idle, expect := [] }, .extra)]
  .extra).map (·.id) == ["b"]

/-- The WebKit members the page does not realize, with the reason. -/
def wkExcluded : List (String × String) :=
  wkMembers.filterMap fun (p, l) =>
    if wkRealizable p l then none
    else some (wkMemberId p l, if (wkCss p).isNone then "not measured: the change depends on more than the property and the layer state"
      else "the state does not exist for this property (it gives the box a layer, or needs a positioned box)")

/-! ## Verdict -/

-- `if_pos` and `if_neg` are deprecated in this toolchain but remain the direct rewrite for a Bool condition.
set_option linter.deprecated false

/-- The cell of one (step, stage): the model's expected presence `e` against the observed presences `os` of all
passes. `agree`: at least one pass and all equal `e`; `mismatch`: at least one pass and none equals `e`; `unstable`:
the passes disagree; `missing`: no pass.
-/
inductive Cell where
  | agree | mismatch | unstable | missing
deriving DecidableEq, Repr

/-- The cell's name in the golden. -/
def Cell.name : Cell → String
  | .agree => "agree" | .mismatch => "mismatch" | .unstable => "unstable" | .missing => "missing"

/-- The cell of an expectation against the observations of all passes. -/
def cell (e : Bool) (os : List Bool) : Cell :=
  if os.isEmpty then .missing else if os.all (· == e) then .agree else if os.all (· != e) then .mismatch else .unstable

/-- The verdict on a stage rule: it holds, fails, or the measurement cannot say. -/
inductive Verdict where
  | holds | fails | inconclusive
deriving DecidableEq, Repr

/-- The verdict's name in the golden. -/
def Verdict.name : Verdict → String
  | .holds => "holds" | .fails => "fails" | .inconclusive => "inconclusive"

/-- **The verdict** of a stage rule from the cells of its stage over all steps: `fails` if some cell is a mismatch,
`holds` if there is a cell and all agree, else `inconclusive`.
-/
def verdict (cs : List Cell) : Verdict :=
  if cs.any (· == .mismatch) then .fails else if !cs.isEmpty && cs.all (· == .agree) then .holds else .inconclusive

private theorem all_beq_iff (e : Bool) (os : List Bool) : os.all (· == e) = true ↔ ∀ o ∈ os, o = e := by
  rw [List.all_eq_true]
  exact ⟨fun h o ho => beq_iff_eq.mp (h o ho), fun h o ho => beq_iff_eq.mpr (h o ho)⟩

private theorem all_bne_iff (e : Bool) (os : List Bool) : os.all (· != e) = true ↔ ∀ o ∈ os, o ≠ e := by
  rw [List.all_eq_true]
  exact ⟨fun h o ho => bne_iff_ne.mp (h o ho), fun h o ho => bne_iff_ne.mpr (h o ho)⟩

/-- The cell is `agree` iff there is a pass and every pass equals the expectation. -/
theorem cell_agree_iff (e : Bool) (os : List Bool) : cell e os = .agree ↔ os ≠ [] ∧ ∀ o ∈ os, o = e := by
  unfold cell
  by_cases hE : os.isEmpty = true
  · have : os = [] := List.isEmpty_iff.mp hE
    subst this; simp
  · have hne : os ≠ [] := fun h => hE (by simp [h])
    rw [if_neg hE]
    by_cases hA : os.all (· == e) = true
    · rw [if_pos hA]; exact ⟨fun _ => ⟨hne, (all_beq_iff e os).mp hA⟩, fun _ => rfl⟩
    · rw [if_neg hA]
      split <;>
      · constructor
        · intro h; cases h
        · intro ⟨_, h⟩; exact absurd ((all_beq_iff e os).mpr h) hA

/-- The cell is `mismatch` iff there is a pass and no pass equals the expectation. -/
theorem cell_mismatch_iff (e : Bool) (os : List Bool) : cell e os = .mismatch ↔ os ≠ [] ∧ ∀ o ∈ os, o ≠ e := by
  unfold cell
  by_cases hE : os.isEmpty = true
  · have : os = [] := List.isEmpty_iff.mp hE
    subst this; simp
  · have hne : os ≠ [] := fun h => hE (by simp [h])
    rw [if_neg hE]
    by_cases hA : os.all (· == e) = true
    · rw [if_pos hA]
      constructor
      · intro h; cases h
      · intro ⟨_, hq⟩
        obtain ⟨o, ho⟩ := List.exists_mem_of_ne_nil os hne
        exact absurd ((all_beq_iff e os).mp hA o ho) (hq o ho)
    · rw [if_neg hA]
      by_cases hB : os.all (· != e) = true
      · rw [if_pos hB]; exact ⟨fun _ => ⟨hne, (all_bne_iff e os).mp hB⟩, fun _ => rfl⟩
      · rw [if_neg hB]
        constructor
        · intro h; cases h
        · intro ⟨_, h⟩; exact absurd ((all_bne_iff e os).mpr h) hB

private theorem any_mismatch_iff (cs : List Cell) : cs.any (· == Cell.mismatch) = true ↔ ∃ c ∈ cs, c = .mismatch := by
  rw [List.any_eq_true]
  exact ⟨fun ⟨c, hc, h⟩ => ⟨c, hc, beq_iff_eq.mp h⟩, fun ⟨c, hc, h⟩ => ⟨c, hc, beq_iff_eq.mpr h⟩⟩

private theorem holds_cond_iff (cs : List Cell) :
    (!cs.isEmpty && cs.all (· == Cell.agree)) = true ↔ cs ≠ [] ∧ ∀ c ∈ cs, c = .agree := by
  rw [Bool.and_eq_true, List.all_eq_true]
  constructor
  · intro ⟨h1, h2⟩
    exact ⟨fun h => by simp [h] at h1, fun c hc => beq_iff_eq.mp (h2 c hc)⟩
  · intro ⟨h1, h2⟩
    exact ⟨by cases cs with | nil => exact absurd rfl h1 | cons _ _ => simp, fun c hc => beq_iff_eq.mpr (h2 c hc)⟩

/-- **A stage rule fails iff some cell is a mismatch**: a deterministic disagreement of one step with the model is
enough, whatever the other cells say.
-/
theorem verdict_fails_iff (cs : List Cell) : verdict cs = .fails ↔ ∃ c ∈ cs, c = .mismatch := by
  unfold verdict
  by_cases h : cs.any (· == Cell.mismatch) = true
  · rw [if_pos h]; exact ⟨fun _ => (any_mismatch_iff cs).mp h, fun _ => rfl⟩
  · rw [if_neg h]
    split <;>
    · constructor
      · intro h'; cases h'
      · intro h'; exact absurd ((any_mismatch_iff cs).mpr h') h

/-- **A stage rule holds iff there is a cell and every cell agrees.** -/
theorem verdict_holds_iff (cs : List Cell) : verdict cs = .holds ↔ cs ≠ [] ∧ ∀ c ∈ cs, c = .agree := by
  unfold verdict
  by_cases h : cs.any (· == Cell.mismatch) = true
  · rw [if_pos h]
    constructor
    · intro h'; cases h'
    · intro ⟨_, hall⟩
      obtain ⟨c, hc, he⟩ := (any_mismatch_iff cs).mp h
      exact absurd (he.symm.trans (hall c hc)) (by decide)
  · rw [if_neg h]
    by_cases hb : (!cs.isEmpty && cs.all (· == Cell.agree)) = true
    · rw [if_pos hb]; exact ⟨fun _ => (holds_cond_iff cs).mp hb, fun _ => rfl⟩
    · rw [if_neg hb]
      constructor
      · intro h'; cases h'
      · intro h'; exact absurd ((holds_cond_iff cs).mpr h') hb

/-- **Holds and fails exclude each other.** -/
theorem verdict_holds_ne_fails (cs : List Cell) (h : verdict cs = .holds) : verdict cs ≠ .fails := by
  rw [h]; decide

/-- **One more mismatching cell cannot restore a premise**: adding a cell to a list never turns `fails` into anything
else.
-/
theorem verdict_fails_cons (c : Cell) (cs : List Cell) (h : verdict cs = .fails) : verdict (c :: cs) = .fails := by
  rw [verdict_fails_iff] at h ⊢
  obtain ⟨d, hd, he⟩ := h
  exact ⟨d, List.mem_cons_of_mem _ hd, he⟩

set_option linter.deprecated true

/-! ## The recorded observations (CI run 39088367495)

The engine-premises lane of workflow run 39088367495 (commit `485b013`) observed every step: Chromium in 3 passes,
WebKit in 6. No cell was `unstable` or `missing` (MEASURED, `premise-verdict/chromium.json` and `webkit.json` of that
run), so one presence per (step, stage) records the run. `crRecorded` and `wkRecorded` list, per non-idle case id, the
stages observed present, in observer order; every idle step observed what the model of that run expected of an idle
frame (Chromium: nothing; WebKit: `commit`). Under the model of that run 7 stage rules failed (Chromium layout,
props, paint, raster, hits; WebKit layout, props). `cr_recorded_holds` and `wk_recorded_holds` recompute every cell
from these records against the current model: every stage rule of both engines holds.
-/

/-- **The Chromium record** of CI run 39088367495: per case id, the observed stages (MEASURED, 3 passes, all equal).

The 65 rows, in step order. Below, `k@(x, y, z)` stands for the three rows `(k@none, x), (k@layer, y), (k@own, z)`
and `k@(·, y, z)` for the last two only, with the stage lists
`a = [style, props, raster, commit]`, `b = [style, props, commit]`,
`g = [style, props, paint, raster, commit]`,
`L = [style, layout, props, paint, raster, commit, hits]`,
`L' = [style, layout, props, commit, hits]`.

What the Chromium lane saw in each non-idle frame. -/
def crRecorded : List (String × List String) :=
  [("transform@none", ["style", "props", "raster", "commit"]),
   ("transform@layer", ["style", "props", "raster", "commit"]), ("transform@own", ["style", "props", "commit"]),
   ("transform(none<->some)@none", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("transform(none<->some)@layer", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("transform(none<->some)@own", ["style", "props", "raster", "commit"]),
   ("translate@none", ["style", "props", "raster", "commit"]),
   ("translate@layer", ["style", "props", "raster", "commit"]), ("translate@own", ["style", "props", "commit"]),
   ("scale@none", ["style", "props", "raster", "commit"]),
   ("scale@layer", ["style", "props", "raster", "commit"]), ("scale@own", ["style", "props", "raster", "commit"]),
   ("rotate@none", ["style", "props", "raster", "commit"]),
   ("rotate@layer", ["style", "props", "raster", "commit"]), ("rotate@own", ["style", "props", "commit"]),
   ("opacity@none", ["style", "props", "raster", "commit"]),
   ("opacity@layer", ["style", "props", "raster", "commit"]), ("opacity@own", ["style", "props", "commit"]),
   ("filter@none", ["style", "props", "raster", "commit"]),
   ("filter@layer", ["style", "props", "raster", "commit"]), ("filter@own", ["style", "props", "commit"]),
   ("filter(blur)@none", ["style", "props", "raster", "commit"]),
   ("filter(blur)@layer", ["style", "props", "raster", "commit"]),
   ("filter(blur)@own", ["style", "props", "raster", "commit"]),
   ("backdrop-filter@none", ["style", "props", "commit"]),
   ("backdrop-filter@layer", ["style", "props", "commit"]), ("backdrop-filter@own", ["style", "props", "commit"]),
   ("background-position@none", ["style", "props", "paint", "raster", "commit"]),
   ("background-position@layer", ["style", "props", "paint", "raster", "commit"]),
   ("background-position@own", ["style", "props", "paint", "raster", "commit"]),
   ("background-image@none", ["style", "props", "paint", "raster", "commit"]),
   ("background-image@layer", ["style", "props", "paint", "raster", "commit"]),
   ("background-image@own", ["style", "props", "paint", "raster", "commit"]),
   ("background-color@none", ["style", "props", "paint", "raster", "commit"]),
   ("background-color@layer", ["style", "props", "paint", "raster", "commit"]),
   ("background-color@own", ["style", "props", "paint", "raster", "commit"]),
   ("color@none", ["style", "props", "paint", "raster", "commit"]),
   ("color@layer", ["style", "props", "paint", "raster", "commit"]),
   ("color@own", ["style", "props", "paint", "raster", "commit"]),
   ("clip-path@none", ["style", "props", "paint", "raster", "commit"]),
   ("clip-path@layer", ["style", "props", "paint", "raster", "commit"]),
   ("clip-path@own", ["style", "props", "paint", "raster", "commit"]),
   ("visibility@none", ["style", "props", "paint", "raster", "commit"]),
   ("visibility@layer", ["style", "props", "paint", "raster", "commit"]),
   ("visibility@own", ["style", "props", "paint", "raster", "commit"]),
   ("z-index@layer", ["style", "props", "paint", "raster", "commit"]),
   ("z-index@own", ["style", "props", "paint", "raster", "commit"]),
   ("top@layer", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("top@own", ["style", "layout", "props", "commit", "hits"]),
   ("left@layer", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("left@own", ["style", "layout", "props", "commit", "hits"]),
   ("width@none", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("width@layer", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("width@own", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("height@none", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("height@layer", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("height@own", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("margin@none", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("margin@layer", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("margin@own", ["style", "layout", "props", "commit", "hits"]),
   ("padding@none", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("padding@layer", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("padding@own", ["style", "layout", "props", "paint", "raster", "commit", "hits"]),
   ("script", ["script", "props"]), ("hit", ["props", "hits"])]

/-- **The WebKit record** of CI run 39088367495: per case id, the observed stages (MEASURED, 6 passes, all equal).

The 30 rows, in step order, written as in `crRecorded` (`p@(x, y, z)` for the rows at none, layer, own; `p@(·, y, z)`
for layer and own only), with `T = [style, layout, props, commit]`,
`b = [style, props, commit]`, `c = [style, commit]`.

What the WKTR lane saw in each non-idle rendering update. -/
def wkRecorded : List (String × List String) :=
  [("transform@layer", ["style", "layout", "props", "commit"]), ("transform@own", ["style", "props", "commit"]),
   ("transformToggle@none", ["style", "layout", "props", "commit"]),
   ("transformToggle@layer", ["style", "layout", "props", "commit"]),
   ("transformToggle@own", ["style", "layout", "props", "commit"]),
   ("opacity@layer", ["style", "props", "commit"]), ("opacity@own", ["style", "commit"]),
   ("opacityCross1@none", ["style", "layout", "props", "commit"]),
   ("opacityCross1@layer", ["style", "layout", "props", "commit"]),
   ("opacityCross1@own", ["style", "layout", "props", "commit"]),
   ("filter@layer", ["style", "layout", "props", "commit"]),
   ("filter@own", ["style", "layout", "props", "commit"]),
   ("filterToggle@none", ["style", "layout", "props", "commit"]),
   ("filterToggle@layer", ["style", "layout", "props", "commit"]),
   ("filterToggle@own", ["style", "layout", "props", "commit"]), ("background@none", ["style", "commit"]),
   ("background@layer", ["style", "commit"]), ("background@own", ["style", "props", "commit"]),
   ("color@none", ["style", "commit"]), ("color@layer", ["style", "commit"]),
   ("color@own", ["style", "props", "commit"]), ("mask@layer", ["style", "props", "commit"]),
   ("mask@own", ["style", "props", "commit"]), ("insetAbs@layer", ["style", "layout", "props", "commit"]),
   ("insetAbs@own", ["style", "layout", "props", "commit"]),
   ("inset@layer", ["style", "layout", "props", "commit"]), ("inset@own", ["style", "layout", "props", "commit"]),
   ("size@none", ["style", "layout", "props", "commit"]), ("size@layer", ["style", "layout", "props", "commit"]),
   ("size@own", ["style", "layout", "props", "commit"])]

/-- The observations of a step from a record: an idle step observes the record's idle stages `i`, any other step the
stages recorded for its id, `none` if the record has no row for it.

Which stages a recorded step showed. -/
def recordedObs (idle : List String) (rec : List (String × List String)) (c : Case) : Option (List String) :=
  if c.act = .idle then some idle else rec.lookup c.id

/-- **The cells of a stage from a record**: per step, the model's expectation for stage `s` (absent: `false`)
against `p` passes that each observed the recorded presence; a step without a record has no pass (`missing`).

The cells a verdict reads, rebuilt from a record. -/
def recordedCells (passes : Nat) (idle : List String) (rec : List (String × List String)) (cs : List Case)
    (s : String) : List Cell :=
  cs.map fun c =>
    cell ((c.expect.lookup s).getD false)
      (match recordedObs idle rec c with
       | some o => List.replicate passes (o.contains s)
       | none => [])

#guard recordedCells 2 [] [("a", ["style"])] [{ id := "a", act := .set, expect := [("style", true)] }] "style" ==
  [.agree]
#guard recordedCells 2 [] [("a", ["style"])] [{ id := "b", act := .set, expect := [("style", true)] }] "style" ==
  [.missing]
#guard recordedCells 3 ["commit"] [] [{ id := "a+idle", act := .idle, expect := [("commit", false)] }] "commit" ==
  [.mismatch]
#guard recordedCells 1 [] [("a", [])] [{ id := "a", act := .set, expect := [] }] "layout" == [.agree]

/-- **Every Chromium stage rule holds on the recorded run.** For every Chromium observer, the cells rebuilt from
`crRecorded` (3 passes; idle steps observed nothing) against the current model's table steps all agree.

The fixed Chromium model predicts every cell of CI run 39088367495, the 5 refuted rules included. -/
theorem cr_recorded_holds :
    ∀ o ∈ crObservers, verdict (recordedCells 3 [] crRecorded crSteps0 o.stage) = .holds := by
  decide +kernel

/-- **Every WebKit stage rule holds on the recorded run.** For every WebKit observer, the cells rebuilt from
`wkRecorded` (6 passes; idle steps observed `commit`) against the current model's table steps all agree.

The fixed WebKit model predicts every cell of CI run 39088367495, the 2 refuted rules included. -/
theorem wk_recorded_holds :
    ∀ o ∈ wkObservers, verdict (recordedCells 6 ["commit"] wkRecorded wkSteps0 o.stage) = .holds := by
  decide +kernel

/-- The records cover the run: 65 Chromium and 30 WebKit non-idle steps, one row each.

One recorded row per case. -/
theorem recorded_length : crRecorded.length = crCases.length ∧ crCases.length = 65 ∧
    wkRecorded.length = wkCases.length ∧ wkCases.length = 30 := by
  decide +kernel

/-! ## Facts about the tables -/

/-- The Chromium table has 69 members (23 properties times three layer states), 63 of them realizable. -/
theorem cr_counts : crMembers.length = 69 ∧ crCases.length = 63 + 2 ∧ crExcluded.length = 6 := by
  decide +kernel

/-- Realizable and excluded members partition the table. -/
theorem cr_partition : (crMembers.filter fun (k, l) => crRealizable k l).length + crExcluded.length = crMembers.length := by
  decide +kernel

/-- The WebKit table has 57 members, 30 realizable. -/
theorem wk_counts : wkMembers.length = 57 ∧ wkCases.length = 30 ∧ wkExcluded.length = 27 := by
  decide +kernel

/-- Every step list alternates a case and its idle frame, so it has twice the cases. -/
theorem steps_length (idle : List (String × Bool)) (cs : List Case) : (steps idle cs).length = 2 * cs.length := by
  induction cs with
  | nil => simp [steps]
  | cons c rest ih => simp [steps] at ih ⊢; omega

/-- **The model expects an own-layer transform change to run exactly style, props and commit** (the direct path). -/
theorem cr_direct_names : names (expectAll crObservers (crWork (crFrame .transform .own))) = ["style", "props", "commit"] := by
  decide +kernel

/-- **A width change runs everything but the compositor and script, plus one hit test**: style, layout, props,
paint, raster, commit and hits. Changed since CI run 39088367495: `hits` is new (a frame that lays out pays one hover
hit test, MEASURED, `crWorkH`).

A width change on a box without a layer dirties every main-thread stage but script. -/
theorem cr_width_names : names (expectAll crObservers (crWork (crFrame .width .none))) =
    ["style", "layout", "props", "paint", "raster", "commit", "hits"] := by
  decide +kernel

/-- **An idle Chromium frame expects nothing**: no stage, no hit test. -/
theorem cr_idle_names : names (expectAll crObservers (crWork idleFrame)) = [] := by
  decide +kernel

/-- **The hit-test frame expects the hit test and its PrePaint** (`crWorkH`), nothing else. -/
theorem cr_hit_names : names (expectAll crObservers (crWork ⟨0, 0, 0, 1, [], 0⟩)) = ["props", "hits"] := by
  decide +kernel

/-- **An idle WebKit frame expects only the commit**: the harness's rAF callback is a script, so the frame has a
rendering update, which pays the base `commit` stage ("commit even if nothing changed"). Style, layout and props are
not expected.
-/
theorem wk_idle_names : names (expectAll wkObservers (wkWork [])) = ["commit"] := by
  decide +kernel

/-- **A width change on a box without a layer** runs style, layout, props and commit on WebKit. -/
theorem wk_size_names : names (expectAll wkObservers (wkWork [⟨0, .size, .none⟩])) =
    ["style", "layout", "props", "commit"] := by
  decide +kernel

/-! ## The extra cases (task engine-model-fix-2) -/

/-- The extra cases: 7 Chromium (one clock-shim control, three joins, three two-element frames) and 3 WebKit; no two-element pair is dropped as unrealizable. -/
theorem extra_counts : crExtraCases.length = 7 ∧ wkExtraCases.length = 3 ∧
    crSteps.length = 2 * (65 + 7) ∧ wkSteps.length = 2 * (30 + 3) := by
  decide +kernel

/-- Splitting a list tagged `table` then `extra` by step set gives back both parts. -/
private theorem stepsOf_split (a b : List Case) :
    stepsOf (a.map (·, .table) ++ b.map (·, .extra)) .table = a ∧
    stepsOf (a.map (·, .table) ++ b.map (·, .extra)) .extra = b := by
  constructor <;> induction a <;> simp_all [stepsOf, List.filter_map, Function.comp_def]

/-- **The step sets are the step lists.** Both engines' grouped steps, without the step set, are the steps of the
page in order; the `table` set is exactly the table steps that `cr_recorded_holds` and `wk_recorded_holds` judge,
and the `extra` set is exactly the extra steps.

The lane's per-set verdicts read exactly these steps. -/
theorem grouped_steps :
    crGrouped.map (·.1) = crSteps ∧ stepsOf crGrouped .table = crSteps0 ∧
      stepsOf crGrouped .extra = steps (expectAll crObservers (crWork idleFrame)) crExtraCases ∧
    wkGrouped.map (·.1) = wkSteps ∧ stepsOf wkGrouped .table = wkSteps0 ∧
      stepsOf wkGrouped .extra = steps (expectAll wkObservers (wkWork [])) wkExtraCases := by
  refine ⟨?_, (stepsOf_split _ _).1, (stepsOf_split _ _).2, ?_, (stepsOf_split _ _).1, (stepsOf_split _ _).2⟩ <;>
    simp [crGrouped, crSteps, wkGrouped, wkSteps, Function.comp_def]

/-- **A frame with one script callback and no change expects script, props and nothing else**: the model counts a
timer callback as one script callback, as it counts a `raf` callback, so the frame updates and pays the base `props`
stage. The model only: no lane has run a Chromium timer task (the `shimTimer` step is the clock shim's plain call, not
a timer task; see `Act`), so whether an empty timer task runs `PrePaint` is OPEN.
-/
theorem cr_timer_names : names (expectAll crObservers (crWork ⟨1, 0, 0, 0, [], 0⟩)) = ["script", "props"] := by
  decide +kernel

/-- **The join predicts paint where the union does not.** `top` (`layoutMove`) and `scale` (`raster`) on an own-layer
box are incomparable levels, so a custom property both read joins to `layoutFull`, which paints; the same two
changes on two boxes take the union of their stages, which has no paint.

`join_ne_union_iff` shows the two combining rules differ only on this pair of levels. -/
theorem cr_join_vs_union :
    Fw.Engine.Chromium.crLevel (.custom 0 [.top, .scale]) .own = .layoutFull ∧
    "paint" ∈ names (expectAll crObservers (crWork (crFrames [⟨0, .custom 0 [.top, .scale], .own⟩]))) ∧
    "paint" ∉ names (expectAll crObservers (crWork (crFrames [⟨0, .css .top, .own⟩, ⟨1, .css .scale, .own⟩]))) := by
  decide +kernel

/-- **The join and the union differ only on `layoutMove` with `raster`.** For any two levels, the join `max(a, b)`
has a stage that neither `a` nor `b` has exactly when `{a, b} = {layoutMove, raster}`; such
levels are incomparable. Since every stage of `a` and of `b` is a stage of `max(a, b)` (`CrLevel.le_max_left`,
`le_max_right`), this is exactly when the join's stages differ from the union's.

Among all pairs of levels, only this one makes highest-level-wins predict more than the union. -/
theorem join_ne_union_iff :
    (∀ a ∈ CrLevel.all, ∀ b ∈ CrLevel.all,
      (∃ s ∈ (a.max b).stages, s ∉ a.stages ∧ s ∉ b.stages) ↔
        ((a, b) = (.layoutMove, .raster) ∨ (a, b) = (.raster, .layoutMove))) ∧
    ¬(CrLevel.layoutMove ≤ .raster) ∧ ¬(CrLevel.raster ≤ .layoutMove) := by
  decide +kernel

/-- **For comparable levels the join is the union.** If `a ≤ b` or `b ≤ a`, the stages of `max(a, b)` are
exactly the stages of `a` and of `b` together.

Only incomparable levels make the two rules disagree. -/
theorem max_stages_of_comparable (a b : CrLevel) (h : a ≤ b ∨ b ≤ a) (s : Fw.Engine.Stage) :
    s ∈ (a.max b).stages ↔ s ∈ a.stages ∨ s ∈ b.stages := by
  unfold CrLevel.max
  rcases h with h | h
  · simp only [h, ite_true]
    exact ⟨Or.inr, fun h' => h'.elim (h s) id⟩
  · by_cases hab : a ≤ b
    · simp only [hab, ite_true]
      exact ⟨Or.inr, fun h' => h'.elim (hab s) id⟩
    · simp only [hab, ite_false, h, ite_true]
      exact ⟨Or.inl, fun h' => h'.elim id (h s)⟩

/-- **The recorded Chromium extra steps** (CI run 39124427211, commit 6bf5957, 3 passes, every pass alike): per case,
the stages whose counters ran. The clock-shim control ran nothing, like an idle frame; `top` and `scale` read
through one custom property, and `top@own` with `scale@own` on two boxes, ran layout but neither `Paint` nor
`RasterTask`.

Which counters ran in each extra Chromium step. -/
def crExtraRecorded : List (String × List String) :=
  let l := ["style", "layout", "props", "commit", "hits"]
  let p := ["style", "props", "paint", "raster", "commit"]
  [("shimTimer", []), ("custom[top,scale]@own", l), ("custom[top,transform]@own", l),
   ("custom[backgroundColor,opacity]@own", p), ("top@own+scale@own", l), ("transform@own+background-color@none", p),
   ("top@own+transform@own", l)]

/-- **The recorded WebKit extra steps** (CI run 39124427211, 6 passes, every pass alike): per case, the counters that
ran; the idle frames after them ran only `layerFlushes`.
-/
def wkExtraRecorded : List (String × List String) :=
  [("opacity@own+background@layer", ["style", "commit"]), ("opacity@own+size@none", ["style", "layout", "props", "commit"]),
   ("transform@own+color@own", ["style", "props", "commit"])]

/-- The cells that do not agree: per observer (in observer order), per step (in step order), the case id, the stage
and the cell, for every cell that is not `agree`.

Which cells a record refutes. -/
def offCells (passes : Nat) (idle : List String) (rec : List (String × List String)) (cs : List Case)
    (os : List Observer) : List (String × String × String) :=
  os.flatMap fun o => ((cs.zip (recordedCells passes idle rec cs o.stage)).filter (·.2 != .agree)).map
    fun (c, x) => (c.id, o.stage, x.name)

#guard offCells 1 [] [("a", [])] [{ id := "a", act := .set, expect := [("style", true)] }]
  [⟨"style", some .style, []⟩] == [("a", "style", "mismatch")]

/-- **What the Chromium extra steps measured** (CI run 39124427211): every cell agrees with the model except three
mismatches. The join of `top` and `scale` ran neither `paint` nor `raster` (the join `layoutFull` expects
both), and `top@own` with `scale@own` on two boxes ran no `raster` (the union expects it). The clock-shim control
agrees with an idle frame, and the comparable joins and pairs agree on every stage.

Highest-level-wins and the union are MEASURED only where the levels are comparable; for `layoutMove` with `raster`
both are refuted. -/
theorem cr_extra_cells :
    offCells 3 [] crExtraRecorded (steps (expectAll crObservers (crWork idleFrame)) crExtraCases) crObservers =
      [("custom[top,scale]@own", "paint", "mismatch"), ("custom[top,scale]@own", "raster", "mismatch"),
       ("top@own+scale@own", "raster", "mismatch")] := by
  decide +kernel

/-- **The lane's verdict rows for the Chromium extra steps** (CI run 39124427211): per observer, the verdict over the
`extra` step set alone; `paint` and `raster` fail, every other stage holds. These are the rows `chromium.extra.<stage>` that
`premise-verdict.mjs` prints next to the table rows.

What the extra rows of that run report. -/
theorem cr_extra_verdicts :
    crObservers.map (fun o => (o.stage, verdict (recordedCells 3 [] crExtraRecorded (stepsOf crGrouped .extra) o.stage))) =
      [("script", .holds), ("style", .holds), ("layout", .holds), ("props", .holds), ("paint", .fails),
       ("raster", .fails), ("commit", .holds), ("hits", .holds)] := by
  rw [grouped_steps.2.2.1]
  decide +kernel

/-- **Every WebKit stage rule holds on the extra steps** (CI run 39124427211, 6 passes): two changes on two boxes
in one frame run the union of their stages, for the three measured pairs.

The WebKit union rule, MEASURED on three pairs. -/
theorem wk_extra_holds :
    ∀ o ∈ wkObservers, verdict (recordedCells 6 ["commit"] wkExtraRecorded
      (steps (expectAll wkObservers (wkWork [])) wkExtraCases) o.stage) = .holds := by
  decide +kernel

/-! ## Golden -/

-- A string list as JSON.
private def strs (l : List String) : Json := Json.arr (l.map Json.str).toArray

-- An observer row.
private def observerRow (engine : String) (o : Observer) : Json :=
  Json.mkObj [("kind", "observer"), ("engine", .str engine), ("stage", .str o.stage), ("counters", strs o.counters)]

-- A step row.
private def stepRow (engine : String) (j : Nat) (c : Case) (g : Group) : Json :=
  Json.mkObj <| ([("kind", "step"), ("engine", .str engine), ("step", (j : Json)), ("group", .str g.name), ("case", .str c.id),
    ("act", .str c.act.name), ("style", .str c.style), ("prop", .str c.prop), ("to", .str c.to)] : List (String × Json)) ++
    (if c.more.isEmpty then [] else [("more", Json.arr (c.more.map fun (st, pr, t) =>
      Json.mkObj [("style", .str st), ("prop", .str pr), ("to", .str t)]).toArray)]) ++
    [("expect", Json.mkObj (c.expect.map fun (s, b) => (s, Json.bool b)))]

-- The verdict vectors: expectation, observations per pass, the cell, and a verdict over cells.
private def cellVectors : List (Bool × List Bool) :=
  [(true, []), (true, [true]), (false, [false, false, false]), (true, [false]), (false, [true, true]),
   (true, [true, false]), (false, [false, true, false]), (true, [false, false, true])]

private def verdictVectors : List (String × List Cell) :=
  [("empty", []), ("agree", [.agree, .agree]), ("one-mismatch", [.agree, .mismatch, .agree]),
   ("unstable", [.agree, .unstable]), ("missing", [.missing, .agree]), ("mismatch-and-unstable", [.unstable, .mismatch]),
   ("only-mismatch", [.mismatch])]

/-- The golden rows: the page's base style, observers, steps (each with its step set, from `crGrouped` and
`wkGrouped`) and excluded members per engine, then the cell and verdict vectors.

The step index `j` counts from 0 within each engine's steps.
-/
def goldenRows : List Json :=
  [Json.mkObj [("kind", "page"), ("baseStyle", .str baseStyle)]] ++
  crObservers.map (observerRow "chromium") ++ wkObservers.map (observerRow "webkit") ++
  (crGrouped.zipIdx.map fun ((c, g), j) => stepRow "chromium" j c g) ++
  (wkGrouped.zipIdx.map fun ((c, g), j) => stepRow "webkit" j c g) ++
  crExcluded.map (fun (m, r) => Json.mkObj [("kind", "excluded"), ("engine", "chromium"), ("member", .str m), ("reason", .str r)]) ++
  wkExcluded.map (fun (m, r) => Json.mkObj [("kind", "excluded"), ("engine", "webkit"), ("member", .str m), ("reason", .str r)]) ++
  cellVectors.map (fun (e, os) => Json.mkObj [("kind", "cell"), ("expect", Json.bool e),
    ("observed", Json.arr (os.map Json.bool).toArray), ("cell", .str (cell e os).name)]) ++
  verdictVectors.map (fun (n, cs) => Json.mkObj [("kind", "verdict"), ("name", .str n),
    ("cells", strs (cs.map Cell.name)), ("verdict", .str (verdict cs).name)])

/-- The golden text: one compact JSON object per line. -/
def goldenText : String := String.join (goldenRows.map fun r => r.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops" / "engine-premises.jsonl"

/-- Write the golden (`write`) or compare it; returns 1 when the file is stale, else 0. -/
def goldenRun (root : System.FilePath) (write : Bool) : IO Nat := do
  let p := root / goldenPath
  if write then
    if let some d := p.parent then IO.FS.createDirAll d
    IO.FS.writeFile p goldenText
    IO.println s!"engine-premises golden: {goldenRows.length} rows written to {p}"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur == goldenText then
    IO.println s!"engine-premises golden: {goldenRows.length} rows, up to date"
    return 0
  IO.println s!"engine-premises golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/EnginePremiseGolden.lean)"
  return 1

#guard cell true [] == .missing && cell true [true, true] == .agree && cell true [false] == .mismatch
#guard cell true [true, false] == .unstable
#guard verdict [] == .inconclusive && verdict [.agree] == .holds && verdict [.agree, .unstable] == .inconclusive
#guard verdict [.unstable, .mismatch] == .fails

end Fw.Ops.EnginePremise
