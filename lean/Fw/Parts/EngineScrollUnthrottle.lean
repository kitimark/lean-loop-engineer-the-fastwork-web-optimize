import Lean.Data.Json
import Fw.Engine.Visual

/-!
# engine.scroll:unthrottle
WebKit @862f17d: WKWebViewIOS.mm:3256-3268, WebPageCocoa.mm:2357, AnimationTimelinesController.cpp:267-279, KeyframeEffect.cpp:1736-1769, StyleInterpolation.cpp:256-266.
-/
namespace Fw.Parts.EngineScrollUnthrottle

open Lean Fw.Engine

inductive PropKind where
  | accelerated
  | layout
  | custom
deriving Repr, DecidableEq

def PropKind.isAccelerated : PropKind → Bool
  | .accelerated => true
  | _ => false

inductive AccState where
  | none
  | some
  | all
deriving Repr, DecidableEq

def accState (ps : List PropKind) : AccState :=
  if !(ps.any PropKind.isAccelerated) then .none
  else if ps.any (fun p => !p.isAccelerated) then .some
  else .all

def completelyAccelerated (ps : List PropKind) : Bool := accState ps == .all

/-- One entry of `timeline->relevantAnimations()` (AnimationTimeline.h:59, `m_animations` filled at AnimationTimeline.cpp:62): any attached animation, whatever its play state. -/
structure Anim where
  progressBased : Bool
  props : List PropKind
deriving Repr, DecidableEq

def hasProgressBasedScrollDriven (as : List Anim) : Bool :=
  as.any fun a => a.progressBased && !completelyAccelerated a.props

structure Page where
  timelineSupported : Bool
  anims : List Anim
deriving Repr, DecidableEq

def Page.effective (p : Page) : List Anim :=
  p.anims.map fun a => { a with progressBased := a.progressBased && p.timelineSupported }

def Page.reported (p : Page) : Bool := hasProgressBasedScrollDriven p.effective

def throttled (interactiveInsets : Bool) (p : Page) : Bool := interactiveInsets && !p.reported

inductive Engine where
  | webkitIos
  | webkitOther
  | chromium
deriving Repr, DecidableEq

def Engine.throttles : Engine → Bool
  | .webkitIos => true
  | _ => false

def throttledOn (e : Engine) (interactiveInsets : Bool) (p : Page) : Bool := e.throttles && throttled interactiveInsets p

def liftAnim : Anim := ⟨true, [.custom]⟩

def Page.withLift (p : Page) : Page := { p with anims := liftAnim :: p.anims }

theorem custom_not_accelerated : PropKind.isAccelerated .custom = false := rfl

theorem custom_effect_not_complete (n : Nat) : completelyAccelerated (List.replicate n .custom) = false := by
  induction n with
  | zero => rfl
  | succ n ih => simp [completelyAccelerated, accState, PropKind.isAccelerated, List.replicate_succ]

theorem liftAnim_not_complete : completelyAccelerated liftAnim.props = false := rfl

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

theorem reported_iff (p : Page) :
    p.reported = true ↔ ∃ a ∈ p.anims, (a.progressBased = true ∧ p.timelineSupported = true) ∧ completelyAccelerated a.props = false := by
  simp [Page.reported, hasProgressBasedScrollDriven, Page.effective, List.any_map, Function.comp_def]

theorem lifted_when_supported (p : Page) (hs : p.timelineSupported = true) (i : Bool) :
    throttled i p.withLift = false := by
  simp [throttled, Page.reported, hasProgressBasedScrollDriven, Page.effective, Page.withLift, liftAnim, hs,
    completelyAccelerated, accState, PropKind.isAccelerated]

theorem no_effect_without_support (p : Page) (hs : p.timelineSupported = false) (i : Bool) :
    throttled i p.withLift = throttled i p := by
  simp [throttled, Page.reported, hasProgressBasedScrollDriven, Page.effective, Page.withLift, liftAnim, hs,
    completelyAccelerated, accState, PropKind.isAccelerated]

theorem no_throttle_when_idle (p : Page) : throttled false p = false := rfl

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

theorem chromium_never_throttled (i : Bool) (p : Page) : throttledOn .chromium i p = false := rfl

theorem lift_effect (e : Engine) (p : Page) (hs : p.timelineSupported = true) :
    throttledOn e true p.withLift = false := by
  cases e <;> simp [throttledOn, Engine.throttles, lifted_when_supported p hs]

/-- The `position` of the element. -/
inductive Position where
  | static
  | fixed
  | absolute
deriving Repr, DecidableEq

def Position.outOfFlow : Position → Bool
  | .static => false
  | _ => true

def Position.css : Position → String
  | .static => "static"
  | .fixed => "fixed"
  | .absolute => "absolute"

structure FlagStyle where
  position : Position
  widthPx : Nat
  heightPx : Nat
  opacity0 : Bool
  pointerEventsNone : Bool
  ariaHidden : Bool
  inherits : Bool
  animated : List PropKind
  readByStyle : Bool
deriving Repr, DecidableEq

def flag : FlagStyle :=
  ⟨.absolute, 1, 1, true, true, true, false, [.custom], false⟩

def flagBox : BoxVis :=
  ⟨⟨0, 0, flag.widthPx, flag.heightPx⟩, ⟨0, 0, flag.widthPx, flag.heightPx⟩, [], ⟨1, 0, 0, 1, 0, 0⟩,
    if flag.opacity0 then 0 else 1, none, [], 0⟩

def withFlag (s : Scene) : Scene := s ++ [("fw-unthrottle", flagBox)]

theorem visible_withFlag (vp : Rect) (s : Scene) : visible vp (withFlag s) = visible vp s := by
  simp [visible, withFlag, List.filter_append, flagBox, flag, BoxVis.drop]

theorem render_withFlag {α : Type} (R : Scene → α) (vp : Rect) (s : Scene) :
    R (visible vp (withFlag s)) = R (visible vp s) := by rw [visible_withFlag]

theorem Q_withFlag (vp : Rect) (s : Scene) : Q (visible vp (withFlag s)) (visible vp s) := by
  rw [visible_withFlag]; exact Q_refl _

structure El where
  inFlow : Bool
  hittable : Bool
  exposed : Bool
deriving Repr, DecidableEq

def flagEl : El := ⟨!flag.position.outOfFlow, !flag.pointerEventsNone, !flag.ariaHidden⟩

def flowOf (es : List El) : List El := es.filter (·.inFlow)

def hitOf (es : List El) : List El := es.filter (·.hittable)

def a11yOf (es : List El) : List El := es.filter (·.exposed)

theorem same_layout_hit_a11y (es : List El) :
    flowOf (es ++ [flagEl]) = flowOf es ∧ hitOf (es ++ [flagEl]) = hitOf es ∧ a11yOf (es ++ [flagEl]) = a11yOf es := by
  simp [flowOf, hitOf, a11yOf, flagEl, flag, Position.outOfFlow, List.filter_append]

theorem flag_animates_custom_only : flag.animated.all (fun p => p == .custom) = true := rfl

theorem flag_value_unread : flag.readByStyle = false := rfl

theorem flag_is_liftAnim : (⟨true, flag.animated⟩ : Anim) = liftAnim := rfl

theorem lift_anim_position_free (f : FlagStyle) (h : f.animated = [.custom]) : (⟨true, f.animated⟩ : Anim) = liftAnim := by
  simp [h, liftAnim]

theorem same_layout_out_of_flow (f : FlagStyle) (ho : f.position.outOfFlow = true) (hp : f.pointerEventsNone = true)
    (ha : f.ariaHidden = true) (es : List El) :
    flowOf (es ++ [⟨!f.position.outOfFlow, !f.pointerEventsNone, !f.ariaHidden⟩]) = flowOf es ∧
    hitOf (es ++ [⟨!f.position.outOfFlow, !f.pointerEventsNone, !f.ariaHidden⟩]) = hitOf es ∧
    a11yOf (es ++ [⟨!f.position.outOfFlow, !f.pointerEventsNone, !f.ariaHidden⟩]) = a11yOf es := by
  simp [flowOf, hitOf, a11yOf, List.filter_append, ho, hp, ha]

theorem fixed_same_look : Position.outOfFlow .fixed = Position.outOfFlow .absolute := rfl

/-! ## The `(pointer: coarse)` guard -/

structure Env where
  engine : Engine
  coarse : Bool
deriving Repr, DecidableEq

/-- An iPhone reports a coarse primary pointer: WebPageIOS.mm:4243-4246, MediaQueryFeatures.cpp:527-538; only the sites of Quirks.cpp:3194-3203 hide it. -/
def Env.valid (e : Env) : Bool := e.engine != .webkitIos || e.coarse

def Env.iphone : Env := ⟨.webkitIos, true⟩

theorem iphone_valid : Env.iphone.valid = true := rfl

def Page.withLiftOn (coarse : Bool) (p : Page) : Page := if coarse then p.withLift else p

def Env.pageOf (e : Env) (p : Page) : Page := p.withLiftOn e.coarse

def Env.throttled (e : Env) (i : Bool) (p : Page) : Bool := throttledOn e.engine i (e.pageOf p)

theorem guard_keeps_ios (e : Env) (hv : e.valid = true) (hi : e.engine = .webkitIos) (p : Page) :
    e.pageOf p = p.withLift := by
  have hc : e.coarse = true := by simpa [Env.valid, hi] using hv
  simp [Env.pageOf, Page.withLiftOn, hc]

theorem guard_keeps_ios_throttle (e : Env) (hv : e.valid = true) (hi : e.engine = .webkitIos) (i : Bool) (p : Page) :
    e.throttled i p = throttledOn .webkitIos i p.withLift := by
  rw [Env.throttled, guard_keeps_ios e hv hi p, hi]

theorem guard_lifts_ios (e : Env) (hv : e.valid = true) (hi : e.engine = .webkitIos) (p : Page)
    (hs : p.timelineSupported = true) : e.throttled true p = false := by
  rw [guard_keeps_ios_throttle e hv hi]
  exact lift_effect .webkitIos p hs

theorem guard_fine_noop (e : Env) (hf : e.coarse = false) (p : Page) : e.pageOf p = p := by
  simp [Env.pageOf, Page.withLiftOn, hf]

theorem guard_fine_throttle (e : Env) (hf : e.coarse = false) (i : Bool) (p : Page) :
    e.throttled i p = throttledOn e.engine i p := by
  rw [Env.throttled, guard_fine_noop e hf]

def restyled (f : FlagStyle) (subtree : Nat) : Nat := 1 + if f.inherits then subtree else 0

def laidOut (f : FlagStyle) (reflowed : Nat) : Nat := if f.readByStyle then reflowed else 0

theorem restyled_flag (subtree : Nat) : restyled flag subtree = 1 := rfl

/-- Elements restyled per scroll frame: none unless the pointer is coarse. -/
def Env.restyled (e : Env) (subtree : Nat) : Nat :=
  if e.coarse then _root_.Fw.Parts.EngineScrollUnthrottle.restyled flag subtree else 0

theorem guard_fine_cost (e : Env) (hf : e.coarse = false) (subtree : Nat) : e.restyled subtree = 0 := by
  simp [Env.restyled, hf]

theorem guard_coarse_cost (e : Env) (hc : e.coarse = true) (subtree : Nat) : e.restyled subtree = 1 := by
  simp [Env.restyled, hc, restyled_flag]

theorem laidOut_flag (reflowed : Nat) : laidOut flag reflowed = 0 := rfl

def extraRecalc (moved : List Bool) : Nat := (moved.filter id).length

theorem extraRecalc_le (moved : List Bool) : extraRecalc moved ≤ moved.length := List.length_filter_le _ _

theorem extraRecalc_idle (n : Nat) : extraRecalc (List.replicate n false) = 0 := by
  simp [extraRecalc]

theorem extraRecalc_scroll (n : Nat) : extraRecalc (List.replicate n true) = n := by
  simp [extraRecalc]

def attr : String := "data-fw-unthrottle"

def css : String :=
  String.intercalate "\n"
    ["@property --fw-ut { syntax: \"<number>\"; inherits: " ++ (if flag.inherits then "true" else "false") ++ "; initial-value: 0; }",
     "@keyframes fw-ut { from { --fw-ut: 0; } to { --fw-ut: 1; } }",
     "@supports (animation-timeline: scroll()) {",
     "@media (pointer: coarse) {",
     s!"[{attr}] \{ position: {flag.position.css}; left: 0; top: 0; width: {flag.widthPx}px; height: {flag.heightPx}px; opacity: {if flag.opacity0 then "0" else "1"}; pointer-events: {if flag.pointerEventsNone then "none" else "auto"};",
     " animation: fw-ut 1s linear both; animation-duration: auto; animation-timeline: scroll(root block); }",
     "}",
     "}"]

def attrs : List (String × String) :=
  [(attr, "")] ++ (if flag.ariaHidden then [("aria-hidden", "true")] else [])

private def okCases : List (Bool × Bool × Bool) :=
  [(true, true, true), (true, true, false), (true, false, true), (false, true, true), (true, false, false),
   (false, false, true), (false, true, false), (false, false, false)]

private def pageOf (supported progress accelerated : Bool) (lift : Bool) : Page :=
  let base : Page := ⟨supported, [⟨progress, [if accelerated then .accelerated else .layout]⟩]⟩
  if lift then base.withLift else base

def goldenLines (_ : Unit) : List String :=
  let decision := okCases.flatMap fun ((s, pr, ac) : Bool × Bool × Bool) =>
    ([true, false] : List Bool).flatMap fun (lift : Bool) =>
      ([true, false] : List Bool).map fun (ins : Bool) =>
        (Json.mkObj [("fn", "throttled"), ("in", Json.mkObj [("timelineSupported", s), ("progressBased", pr),
          ("accelerated", ac), ("lift", lift), ("interactiveInsets", ins)]),
          ("out", throttled ins (pageOf s pr ac lift))]).compress
  let guard := ([true, false] : List Bool).flatMap fun (coarse : Bool) =>
    ([true, false] : List Bool).map fun (ins : Bool) =>
      (Json.mkObj [("fn", "guarded"), ("in", Json.mkObj [("coarse", coarse), ("interactiveInsets", ins)]),
        ("out", Json.mkObj [("throttledIos", (Env.mk .webkitIos coarse).throttled ins (pageOf true false false false)),
          ("restyled", (Env.mk .webkitIos coarse).restyled 1000)])]).compress
  [(Json.mkObj [("fn", "css"), ("out", css)]).compress,
   (Json.mkObj [("fn", "attrs"), ("out", Json.mkObj (attrs.map fun (k, v) => (k, Json.str v)))]).compress,
   (Json.mkObj [("fn", "cost"), ("out", Json.mkObj [("restyled", restyled flag 1000), ("laidOut", laidOut flag 1000),
     ("paintsNothing", flagBox.alpha == 0)])]).compress] ++ decision ++ guard

def goldenText (_ : Unit) : String := String.intercalate "\n" (goldenLines ()) ++ "\n"

def goldenPath : System.FilePath := ".." / "packages" / "contracts" / "golden" / "parts" / "engine.scroll.unthrottle.jsonl"

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
