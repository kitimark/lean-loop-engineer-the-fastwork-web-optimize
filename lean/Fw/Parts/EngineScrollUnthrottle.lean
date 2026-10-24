import Lean.Data.Json
import Fw.Engine.Visual

/-!
# engine.scroll:unthrottle: lifting Mobile Safari's toolbar-collapse throttle with one invisible scroll-driven animation

Pinned source (WebKit tag WebKit-7625.1.29.10.29 at `862f17d`, the iOS 27.0 Simulator runtime):

* `Source/WebKit/UIProcess/API/ios/WKWebViewIOS.mm:3256-3268` (`-[WKWebView _updateVisibleContentRects:]`): while the toolbar
  collapses under a finger (`_isChangingObscuredInsetsInteractively`) and the page reports no main-thread scroll-driven
  animation, a visible-content-rect update waits until 100 ms (`:143`) have passed since the last one;
* `Source/WebKit/WebProcess/WebPage/Cocoa/WebPageCocoa.mm:2357`: the web process reports
  `hasMainThreadScrollDrivenAnimations = document->hasProgressBasedScrollDrivenAnimation()`;
* `Source/WebCore/animation/AnimationTimelinesController.cpp:267-279`: that is true iff some progress-based timeline holds an
  animation whose keyframe effect is not completely accelerated;
* `Source/WebCore/animation/KeyframeEffect.cpp:1736-1769` and `Source/WebCore/style/StyleInterpolation.cpp:256-266`: an effect
  is completely accelerated iff it animates properties and every one is accelerated; a custom property never is.

History (WebKit bugs, via `gh search commits`): the throttle is bug 307463 (commit `de6e12d23e`, 2026-02-25, "up to 2%
power"; the first attempt, `c45540108d`, was reverted by `cab43568d0` for frozen fixed elements); bug 319523 (commit
`b07ce30ae0`, 2026-07-17, "scroll-driven animation is jittery") added the exemption this file uses.

Chromium has no such throttle: its compositor takes scroll offsets without a 100 ms visible-rect handshake with a native
UI process (INFERRED from the absence of an equivalent in `.cache/upstream/chromium`; the Chromium counts lane is the check).
-/
namespace Fw.Parts.EngineScrollUnthrottle

open Lean Fw.Engine

/-! ## 1. The WebKit condition chain -/

/-- The animatable property kinds that matter: those the compositor can run, and a registered custom property. -/
inductive PropKind where
  | accelerated
  | layout
  | custom
deriving Repr, DecidableEq

/-- Whether the compositor can run an animation of the property (`Style::Interpolation::isAccelerated`). -/
def PropKind.isAccelerated : PropKind → Bool
  | .accelerated => true
  | _ => false

/-- The accelerated-properties state of a keyframe effect (`KeyframeEffect::computeAcceleratedPropertiesState`). -/
inductive AccState where
  | none
  | some
  | all
deriving Repr, DecidableEq

/-- `none` when no animated property is accelerated (also when there are no properties), `all` when every one is,
else `some`. -/
def accState (ps : List PropKind) : AccState :=
  if !(ps.any PropKind.isAccelerated) then .none
  else if ps.any (fun p => !p.isAccelerated) then .some
  else .all

/-- The effect is completely accelerated (`KeyframeEffect::isCompletelyAccelerated`). -/
def completelyAccelerated (ps : List PropKind) : Bool := accState ps == .all

/-- An animation on a timeline: whether the timeline is progress-based (a scroll or view timeline, not the document
clock) and the properties its effect animates. -/
structure Anim where
  progressBased : Bool
  props : List PropKind
deriving Repr, DecidableEq

/-- `AnimationTimelinesController::hasProgressBasedScrollDrivenAnimation`. -/
def hasProgressBasedScrollDriven (as : List Anim) : Bool :=
  as.any fun a => a.progressBased && !completelyAccelerated a.props

/-- The page state the decision reads. `timelineSupported`: the engine parses `animation-timeline` (without it the
declaration is dropped and an animation is time-based). -/
structure Page where
  timelineSupported : Bool
  anims : List Anim
deriving Repr, DecidableEq

/-- The animations the engine really has on a progress-based timeline: when `animation-timeline` is not supported the
declaration is dropped, so the same rule makes a time-based animation. -/
def Page.effective (p : Page) : List Anim :=
  p.anims.map fun a => { a with progressBased := a.progressBased && p.timelineSupported }

/-- `WebPage` reports main-thread scroll-driven animations to the UI process (`WebPageCocoa.mm:2357`). -/
def Page.reported (p : Page) : Bool := hasProgressBasedScrollDriven p.effective

/-- The UI process throttles visible-rect updates to one per 100 ms (`WKWebViewIOS.mm:3259`). -/
def throttled (interactiveInsets : Bool) (p : Page) : Bool := interactiveInsets && !p.reported

/-- The engines compared. Only WebKit on iOS has the native toolbar handshake. -/
inductive Engine where
  | webkitIos
  | webkitOther
  | chromium
deriving Repr, DecidableEq

/-- Whether the engine throttles visible-rect updates during a toolbar collapse. -/
def Engine.throttles : Engine → Bool
  | .webkitIos => true
  | _ => false

/-- The throttle in force on an engine. -/
def throttledOn (e : Engine) (interactiveInsets : Bool) (p : Page) : Bool := e.throttles && throttled interactiveInsets p

/-- The animation the unthrottle element carries: scroll-driven, animating one custom property. -/
def liftAnim : Anim := ⟨true, [.custom]⟩

/-- A page with the unthrottle element installed. -/
def Page.withLift (p : Page) : Page := { p with anims := liftAnim :: p.anims }

/-- A custom property is not accelerated. -/
theorem custom_not_accelerated : PropKind.isAccelerated .custom = false := rfl

/-- An effect of custom properties only is not completely accelerated. -/
theorem custom_effect_not_complete (n : Nat) : completelyAccelerated (List.replicate n .custom) = false := by
  induction n with
  | zero => rfl
  | succ n ih => simp [completelyAccelerated, accState, PropKind.isAccelerated, List.replicate_succ]

/-- The unthrottle animation is not completely accelerated. -/
theorem liftAnim_not_complete : completelyAccelerated liftAnim.props = false := rfl

/-- A completely accelerated effect needs at least one property and all of them accelerated. -/
theorem complete_iff (ps : List PropKind) :
    completelyAccelerated ps = true ↔ ps ≠ [] ∧ ∀ p ∈ ps, p.isAccelerated = true := by
  unfold completelyAccelerated accState
  constructor
  · intro h
    by_cases h1 : (ps.any PropKind.isAccelerated) = true
    · by_cases h2 : (ps.any (fun p => !p.isAccelerated)) = true
      · simp [h1, h2] at h
      · refine ⟨?_, ?_⟩
        · rintro rfl; simp at h1
        · intro p hp
          have : ¬ (ps.any (fun p => !p.isAccelerated)) = true := h2
          simp only [List.any_eq_true, not_exists, not_and, Bool.not_eq_true'] at this
          have := this p hp
          simpa using this
    · simp [h1] at h
  · rintro ⟨hne, hall⟩
    have h1 : (ps.any PropKind.isAccelerated) = true := by
      cases ps with
      | nil => exact absurd rfl hne
      | cons p ps => simp [hall p (by simp)]
    have h2 : (ps.any (fun p => !p.isAccelerated)) = false := by
      simp only [List.any_eq_false]
      intro p hp; simp [hall p hp]
    simp [h1, h2]

/-- The report is true iff some animation is on a progress-based timeline and is not completely accelerated. -/
theorem reported_iff (p : Page) :
    p.reported = true ↔ ∃ a ∈ p.anims, (a.progressBased = true ∧ p.timelineSupported = true) ∧ completelyAccelerated a.props = false := by
  simp [Page.reported, hasProgressBasedScrollDriven, Page.effective, List.any_map, Function.comp_def]

/-- Branch 1: with `animation-timeline` supported, the element lifts the throttle, whatever else the page has. -/
theorem lifted_when_supported (p : Page) (hs : p.timelineSupported = true) (i : Bool) :
    throttled i p.withLift = false := by
  simp [throttled, Page.reported, hasProgressBasedScrollDriven, Page.effective, Page.withLift, liftAnim, hs,
    completelyAccelerated, accState, PropKind.isAccelerated]

/-- Branch 2: without `animation-timeline` support the element changes nothing about the throttle. -/
theorem no_effect_without_support (p : Page) (hs : p.timelineSupported = false) (i : Bool) :
    throttled i p.withLift = throttled i p := by
  simp [throttled, Page.reported, hasProgressBasedScrollDriven, Page.effective, Page.withLift, liftAnim, hs,
    completelyAccelerated, accState, PropKind.isAccelerated]

/-- Branch 3: with no toolbar collapse in progress there is no throttle, with or without the element. -/
theorem no_throttle_when_idle (p : Page) : throttled false p = false := rfl

/-- Branch 4: a page whose only animations are completely accelerated or time-based is throttled during a collapse. -/
theorem compositable_does_not_lift (p : Page)
    (h : ∀ a ∈ p.anims, a.progressBased = false ∨ completelyAccelerated a.props = true) :
    throttled true p = true := by
  simp only [throttled, Page.reported, hasProgressBasedScrollDriven, Page.effective, Bool.true_and]
  have : (p.anims.map fun a => { a with progressBased := a.progressBased && p.timelineSupported }).any
      (fun a => a.progressBased && !completelyAccelerated a.props) = false := by
    simp only [List.any_eq_false, List.mem_map]
    rintro a ⟨b, hb, rfl⟩
    rcases h b hb with h1 | h1 <;> simp [h1]
  simp [this]

/-- Branch 5: Chromium never throttles, so the element changes nothing there. -/
theorem chromium_never_throttled (i : Bool) (p : Page) : throttledOn .chromium i p = false := rfl

/-- The element lifts exactly where there is a throttle to lift: on iOS WebKit with the timeline supported. -/
theorem lift_effect (e : Engine) (p : Page) (hs : p.timelineSupported = true) :
    throttledOn e true p.withLift = false := by
  cases e <;> simp [throttledOn, Engine.throttles, lifted_when_supported p hs]

/-! ## 2. The same look -/

/-- The unthrottle element, as typed styles. All other style values are initial. -/
structure FlagStyle where
  fixedPosition : Bool
  widthPx : Nat
  heightPx : Nat
  opacity0 : Bool
  pointerEventsNone : Bool
  ariaHidden : Bool
  /-- `@property` `inherits`. -/
  inherits : Bool
  /-- The properties the keyframes animate. -/
  animated : List PropKind
  /-- Whether any painted or layout declaration reads the animated property. -/
  readByStyle : Bool
deriving Repr, DecidableEq

/-- The shipped element. -/
def flag : FlagStyle :=
  ⟨true, 1, 1, true, true, true, false, [.custom], false⟩

/-- Its scene entry: a 1 px box at the origin, effective opacity 0. -/
def flagBox : BoxVis :=
  ⟨⟨0, 0, flag.widthPx, flag.heightPx⟩, ⟨0, 0, flag.widthPx, flag.heightPx⟩, [], ⟨1, 0, 0, 1, 0, 0⟩,
    if flag.opacity0 then 0 else 1, none, [], 0⟩

/-- The scene with the element appended. -/
def withFlag (s : Scene) : Scene := s ++ [("fw-unthrottle", flagBox)]

/-- The element paints nothing: its opacity is 0, so the visible scene is the page's own, for every viewport and scene. -/
theorem visible_withFlag (vp : Rect) (s : Scene) : visible vp (withFlag s) = visible vp s := by
  simp [visible, withFlag, List.filter_append, flagBox, flag, BoxVis.drop]

/-- Hence any renderer of the visible scene gives the same result. -/
theorem render_withFlag {α : Type} (R : Scene → α) (vp : Rect) (s : Scene) :
    R (visible vp (withFlag s)) = R (visible vp s) := by rw [visible_withFlag]

/-- Equal visible scenes are related by the gate's closeness `Q`. -/
theorem Q_withFlag (vp : Rect) (s : Scene) : Q (visible vp (withFlag s)) (visible vp s) := by
  rw [visible_withFlag]; exact Q_refl _

/-- A page element for the flow, hit-test and accessibility models. -/
structure El where
  inFlow : Bool
  hittable : Bool
  exposed : Bool
deriving Repr, DecidableEq

/-- The element's own entry: out of flow when fixed, not hittable when `pointer-events: none`, not exposed when
`aria-hidden`. -/
def flagEl : El := ⟨!flag.fixedPosition, !flag.pointerEventsNone, !flag.ariaHidden⟩

/-- The in-flow elements (what layout positions). -/
def flowOf (es : List El) : List El := es.filter (·.inFlow)

/-- The elements a pointer can hit. -/
def hitOf (es : List El) : List El := es.filter (·.hittable)

/-- The elements assistive technology exposes. -/
def a11yOf (es : List El) : List El := es.filter (·.exposed)

/-- The element changes no layout, no hit target and no accessible content. -/
theorem same_layout_hit_a11y (es : List El) :
    flowOf (es ++ [flagEl]) = flowOf es ∧ hitOf (es ++ [flagEl]) = hitOf es ∧ a11yOf (es ++ [flagEl]) = a11yOf es := by
  simp [flowOf, hitOf, a11yOf, flagEl, flag, List.filter_append]

/-- The keyframes animate only the custom property: no accelerated property, so no compositor layer is made for it. -/
theorem flag_animates_custom_only : flag.animated.all (fun p => p == .custom) = true := rfl

/-- The animated property is read by no declaration, so the animation changes no painted or layout value. -/
theorem flag_value_unread : flag.readByStyle = false := rfl

/-- The element's animation is the one the throttle chain looks for. -/
theorem flag_is_liftAnim : (⟨true, flag.animated⟩ : Anim) = liftAnim := rfl

/-! ## 3. Its own cost -/

/-- Elements restyled for one animation tick: the target, plus its subtree when the registered property inherits. -/
def restyled (f : FlagStyle) (subtree : Nat) : Nat := 1 + if f.inherits then subtree else 0

/-- Elements laid out for one tick: the target (and so its ancestors) only when a layout declaration reads the property. -/
def laidOut (f : FlagStyle) (reflowed : Nat) : Nat := if f.readByStyle then reflowed else 0

/-- Whatever the page holds, one tick restyles one element. -/
theorem restyled_flag (subtree : Nat) : restyled flag subtree = 1 := rfl

/-- And lays out nothing. -/
theorem laidOut_flag (reflowed : Nat) : laidOut flag reflowed = 0 := rfl

/-- Extra style recalculations over a run of frames; the animation advances only in frames where the scroll offset moved. -/
def extraRecalc (moved : List Bool) : Nat := (moved.filter id).length

/-- A run of frames costs at most one extra element restyle per frame. -/
theorem extraRecalc_le (moved : List Bool) : extraRecalc moved ≤ moved.length := List.length_filter_le _ _

/-- A run without scrolling costs nothing. -/
theorem extraRecalc_idle (n : Nat) : extraRecalc (List.replicate n false) = 0 := by
  simp [extraRecalc]

/-- A scrolling run of `n` frames costs exactly `n`. -/
theorem extraRecalc_scroll (n : Nat) : extraRecalc (List.replicate n true) = n := by
  simp [extraRecalc]

/-! ## 4. The CSS, generated from the typed style -/

/-- The attribute marking the element. -/
def attr : String := "data-fw-unthrottle"

/-- The style text. The element block sits inside `@supports (animation-timeline: scroll())`, so an engine without the
property sees no animation at all (theorem `no_effect_without_support`, in text form). -/
def css : String :=
  String.intercalate "\n"
    ["@property --fw-ut { syntax: \"<number>\"; inherits: " ++ (if flag.inherits then "true" else "false") ++ "; initial-value: 0; }",
     "@keyframes fw-ut { from { --fw-ut: 0; } to { --fw-ut: 1; } }",
     "@supports (animation-timeline: scroll()) {",
     s!"[{attr}] \{ position: {if flag.fixedPosition then "fixed" else "static"}; left: 0; top: 0; width: {flag.widthPx}px; height: {flag.heightPx}px; opacity: {if flag.opacity0 then "0" else "1"}; pointer-events: {if flag.pointerEventsNone then "none" else "auto"};",
     " animation: fw-ut 1s linear both; animation-duration: auto; animation-timeline: scroll(root block); }",
     "}"]

/-- The element's attributes. -/
def attrs : List (String × String) :=
  [(attr, "")] ++ (if flag.ariaHidden then [("aria-hidden", "true")] else [])

/-! ## Golden -/

private def okCases : List (Bool × Bool × Bool) :=
  [(true, true, true), (true, true, false), (true, false, true), (false, true, true), (true, false, false),
   (false, false, true), (false, true, false), (false, false, false)]

private def pageOf (supported progress accelerated : Bool) (lift : Bool) : Page :=
  let base : Page := ⟨supported, [⟨progress, [if accelerated then .accelerated else .layout]⟩]⟩
  if lift then base.withLift else base

/-- The golden lines: the CSS text and attributes the TS part is checked against, and the decision table. -/
def goldenLines (_ : Unit) : List String :=
  let decision := okCases.flatMap fun ((s, pr, ac) : Bool × Bool × Bool) =>
    ([true, false] : List Bool).flatMap fun (lift : Bool) =>
      ([true, false] : List Bool).map fun (ins : Bool) =>
        (Json.mkObj [("fn", "throttled"), ("in", Json.mkObj [("timelineSupported", s), ("progressBased", pr),
          ("accelerated", ac), ("lift", lift), ("interactiveInsets", ins)]),
          ("out", throttled ins (pageOf s pr ac lift))]).compress
  [(Json.mkObj [("fn", "css"), ("out", css)]).compress,
   (Json.mkObj [("fn", "attrs"), ("out", Json.mkObj (attrs.map fun (k, v) => (k, Json.str v)))]).compress,
   (Json.mkObj [("fn", "cost"), ("out", Json.mkObj [("restyled", restyled flag 1000), ("laidOut", laidOut flag 1000),
     ("paintsNothing", flagBox.alpha == 0)])]).compress] ++ decision

/-- The golden file text. -/
def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "parts" / "engine.scroll.unthrottle.jsonl"

/-- Print the golden, or with `--check` fail unless `goldenPath` equals it. -/
def run (args : List String) : IO Unit := do
  match args with
  | "--check" :: _ =>
    let path := goldenPath
    let cur ← IO.FS.readBinFile path
    if cur.data == (goldenText ()).toUTF8.data then
      IO.eprintln s!"engine.scroll unthrottle golden: {path} is up to date ({(goldenLines ()).length} lines)"
    else
      throw (IO.userError s!"{path} differs from Fw.Parts.EngineScrollUnthrottle.goldenText")
  | _ => IO.print (goldenText ())

#guard throttled true (pageOf true true true false) == true
#guard throttled true (pageOf true true false false) == false
#guard throttled true (pageOf true true false true) == false
#guard throttled true (pageOf false true false true) == true
#guard throttledOn .chromium true (pageOf true true true false) == false

end Fw.Parts.EngineScrollUnthrottle
