import Fw.Parts.MorphMount
import Fw.Parts.MorphTween

/-! `morph.mount:touch-first` and `morph.mount:open-once`: the push is decided per touch gesture, not per touchmove; the other toolbar candidates as premises.

WebKit premises, `file:line@862f17d`: the first `touchmove` is cancelable because the native pan waits for it
(`WKContentViewInteraction.mm:1368`, `:2562`); once the pan began, `preventDefault` no longer stops it (`:4239-4245`);
during an interactive obscured-insets change every visible-rect update waits 100 ms (`WKWebViewIOS.mm:143`, `:3256-3268`);
a main-thread progress-based scroll-driven animation lifts that wait (`AnimationTimelinesController.cpp:267-279`). -/
namespace Fw.Parts.MorphMountToolbar

open Fw.Parts.MorphMount (takes armed Rect)

def partId : String := "morph.mount"
def firstId : String := "touch-first"
def onceId : String := "open-once"

/-! ## Candidate (e) and (a): one decision per gesture -/

/-- Where a touch gesture stands: before its first move, native (the pan is the browser's), pushing, or spent. -/
inductive G where
  | fresh | native | pushing | spent
  deriving DecidableEq, Repr

def G.name : G → String
  | .fresh => "fresh" | .native => "native" | .pushing => "pushing" | .spent => "spent"

/-- `first`: decide on the first move. `once`: a gesture opens the morph at most once. -/
structure Opt where
  first : Bool
  once : Bool
  deriving DecidableEq, Repr

def firstOnly : Opt := ⟨true, false⟩
def onceOnly : Opt := ⟨false, true⟩
def orig : Opt := ⟨false, false⟩

/-- One touchmove: whether the push is taken, and the gesture after it.
`cancelable` is the event's flag: false once the pan began. -/
def step (o : Opt) (g : G) (act : Bool) (d : Rat) (geom cancelable : Bool) : Bool × G :=
  match g with
  | .fresh =>
    let t := if o.first && !cancelable then act else takes act d geom
    (t, if t then .pushing else if o.first then .native else .fresh)
  | .native => (act, if act then .pushing else .native)
  | .pushing =>
    if o.once && !act then (false, .spent) else (takes act d geom, .pushing)
  | .spent => (act, if act then .pushing else .spent)

def take (o : Opt) (g : G) (act : Bool) (d : Rat) (geom cancelable : Bool) : Bool := (step o g act d geom cancelable).1

/-- The first move of `native`, never starts a push: nothing pins after the pan began. -/
theorem native_no_start (o : Opt) (d : Rat) (geom c : Bool) : take o .native false d geom c = false := by
  simp [take, step]

/-- Whatever the options, a push is never taken that the original would not take. -/
theorem take_le_orig (o : Opt) (g : G) (act : Bool) (d : Rat) (geom c : Bool)
    (h : take o g act d geom c = true) : takes act d geom = true := by
  cases g <;> simp only [take, step] at h
  · split at h <;> simp_all [takes]
  · simp_all [takes]
  · split at h <;> simp_all
  · simp_all [takes]

/-- An active morph keeps every push, in every gesture state. -/
theorem active_taken (o : Opt) (g : G) (d : Rat) (geom c : Bool) : take o g true d geom c = true := by
  cases g <;> simp [take, step, takes]

/-- `touch-first` decides the first move as the original does, when the browser lets the page cancel it. -/
theorem first_same_first_move (d : Rat) (geom : Bool) (act : Bool) :
    take firstOnly .fresh act d geom true = takes act d geom := by
  simp [take, step, firstOnly]

/-- A first move the page cannot cancel is not taken: the pan is already the browser's. -/
theorem first_uncancelable (d : Rat) (geom : Bool) : take firstOnly .fresh false d geom false = false := by
  simp [take, step, firstOnly]

/-- `touch-first` after an untaken first move: the gesture is native, whatever the geometry becomes. -/
theorem first_then_native (d : Rat) (h : takes false d false = false) :
    (step firstOnly .fresh false d false true).2 = .native := by
  simp [step, firstOnly, h]

/-- The original (no option) is the plain rule on every move. -/
theorem orig_plain (g : G) (act : Bool) (d : Rat) (geom c : Bool) (hg : g = .fresh ∨ g = .pushing) :
    take orig g act d geom c = takes act d geom := by
  rcases hg with rfl | rfl <;> simp [take, step, orig]

/-- An opening move: the morph is idle and the push is taken. -/
def opens (o : Opt) : G → List (Bool × Rat × Bool × Bool) → Nat
  | _, [] => 0
  | g, (act, d, geom, c) :: rest =>
    let r := step o g act d geom c
    (if !act && r.1 then 1 else 0) + opens o r.2 rest

/-- Open-once: after a gesture's first move, no later move of it opens the morph. -/
theorem once_no_open (o : Opt) (ho : o.once = true) (l : List (Bool × Rat × Bool × Bool)) :
    ∀ g, g ≠ .fresh → opens o g l = 0 := by
  induction l with
  | nil => intro g _; simp [opens]
  | cons x rest ih =>
    obtain ⟨act, d, geom, c⟩ := x
    intro g hg
    cases g with
    | fresh => exact absurd rfl hg
    | native => by_cases ha : act = true <;> simp_all [opens, step]
    | pushing => by_cases ha : act = true <;> simp_all [opens, step]
    | spent => by_cases ha : act = true <;> simp_all [opens, step]

/-- Open-once: a gesture opens the morph at most once. -/
theorem once_at_most_one (o : Opt) (ho : o.once = true) (l : List (Bool × Rat × Bool × Bool)) :
    opens o .fresh l ≤ 1 := by
  induction l with
  | nil => simp [opens]
  | cons x rest ih =>
    obtain ⟨act, d, geom, c⟩ := x
    have nf := once_no_open o ho rest
    unfold opens
    generalize hr : step o .fresh act d geom c = r
    obtain ⟨t, g'⟩ := r
    simp only [step] at hr
    by_cases g1 : g' = .fresh
    · have : t = false := by
        simp only [Prod.mk.injEq] at hr
        obtain ⟨h1, h2⟩ := hr
        subst h1
        revert h2; split <;> split <;> simp_all
      subst g1; subst this; simpa using ih
    · show (if (!act && t) = true then 1 else 0) + opens o g' rest ≤ 1
      rw [nf g' g1]; split <;> omega

/-- The original reopens on every forward move of an idle, armed page: no bound. -/
theorem orig_reopens (n : Nat) : opens orig .fresh (List.replicate n (false, 1, true, true)) = n := by
  have h01 : (0 : Rat) < 1 := by decide
  have h : ∀ n, opens orig .pushing (List.replicate n (false, 1, true, true)) = n := by
    intro n
    induction n with
    | zero => simp [opens]
    | succ n ih =>
      simp only [orig] at ih
      simp [List.replicate_succ, opens, step, orig, takes, h01, ih, Nat.add_comm]
  cases n with
  | zero => simp [opens]
  | succ n =>
    have := h n
    simp only [orig] at this
    simp [List.replicate_succ, opens, step, orig, takes, h01, this, Nat.add_comm]

#guard opens onceOnly .fresh (List.replicate 3 (false, 1, true, true)) == 1
#guard opens orig .fresh (List.replicate 3 (false, 1, true, true)) == 3

/-! ## Candidate (b): the arm decision under a toolbar step

With the viewport `vh` the toolbar's height `t` larger, the decision differs for a platform whose bottom lies in
`(vh + 8, vh + t + 8]`: a toolbar-free read cannot reproduce it. Outside that band, and while the fill test is equal, it
agrees. -/
-- hf: the fill test (45 %) gives the same answer for both heights.

theorem armed_same_outside_band (h b vh t : Rat) (ht : 0 ≤ t)
    (hb : b ≤ vh + 8 ∨ vh + t + 8 < b) (hf : vh * 45 / 100 ≤ h ↔ (vh + t) * 45 / 100 ≤ h) :
    armed ⟨h, b⟩ vh = armed ⟨h, b⟩ (vh + t) := by
  unfold armed
  by_cases h1 : b ≤ vh + 8 <;> by_cases h2 : b ≤ vh + t + 8 <;> simp [h1, h2, hf] <;> grind

theorem armed_differs_in_band : armed ⟨450, 845⟩ 800 ≠ armed ⟨450, 845⟩ 840 := by decide +kernel

/-! ## Candidate (f): what unthrottle costs

Every visible-rect update that changes the layout viewport height forces a layout and invalidates every element that uses a
viewport unit, `vh` included (`LocalFrameView.cpp:1956-1957`, `StyleScope.cpp:779-784@862f17d`). The throttle allows one
update per 100 ms; unthrottle one per frame. -/

def throttleMs : Rat := 100
def frameMs : Rat := 1000 / 60

def updates (periodMs windowMs : Rat) : Rat := windowMs / periodMs

/-- A 600 ms toolbar change: 6 throttled updates, 36 at 60 Hz: six times the forced layouts and unit invalidations. -/
theorem unthrottle_costs_six_fold : updates frameMs 600 = 6 * updates throttleMs 600 := by
  unfold updates frameMs throttleMs
  decide +kernel

/-! ## Candidate (c): what a threaded animation can and cannot do -/

inductive Timeline where
  | timeBased | mainThreadProgress | threadedProgress
  deriving DecidableEq, Repr

/-- Only a main-thread progress-based scroll-driven animation lifts the 100 ms wait. -/
def liftsThrottle : Timeline → Bool
  | .mainThreadProgress => true
  | _ => false

/-- Compositor-run properties (`Style::Interpolation::isAccelerated`, StyleInterpolation.cpp:256-266 via `CSSProperty::animationIsAccelerated`@862f17d). -/
def accelerated : List String := ["opacity", "transform", "translate", "scale", "rotate", "filter", "backdrop-filter"]

def morphProps : List String := ["width", "height", "bottom", "border-radius", "background", "box-shadow"]

theorem morph_props_not_accelerated : ∀ p ∈ morphProps, p ∉ accelerated := by decide

theorem threaded_does_not_lift : liftsThrottle .threadedProgress = false ∧ liftsThrottle .mainThreadProgress = true := by
  decide

/-! ## Candidate (g), look change: `overscroll-behavior-y: none` while armed

Root `overscroll-behavior` becomes the main scroll view's `bounces` (`WKWebViewIOS.mm:1084-1087@862f17d`): no rubber band
at the page end while the lock holds. That changes the look, so the flag `morph.mount:overscroll-lock` is a proposal for the
user's visual review. The rule: lock while the platform is near and armed, or the morph is active. -/

def lockId : String := "overscroll-lock"

def lockWanted (near geom act : Bool) : Bool := (near && geom) || act

inductive LockOp where
  | set | clear | none
  deriving DecidableEq, Repr

def LockOp.name : LockOp → String
  | .set => "set" | .clear => "clear" | .none => "none"

/-- Write the style only when the wish changes. -/
def lockOp (cur want : Bool) : LockOp := if cur == want then .none else if want then .set else .clear

/-- Far from the platform the lock is never on, so the page keeps its rubber band everywhere else. -/
theorem lock_off_when_far (geom : Bool) : lockWanted false geom false = false := by simp [lockWanted]

/-- An active morph is always locked. -/
theorem lock_when_active (near geom : Bool) : lockWanted near geom true = true := by simp [lockWanted]

/-- Writing the op yields the wish. -/
theorem lockOp_reaches (cur want : Bool) : (match lockOp cur want with | .set => true | .clear => false | .none => cur) = want := by
  cases cur <;> cases want <;> rfl

theorem lockOp_idem (b : Bool) : lockOp b b = .none := by cases b <;> rfl

end Fw.Parts.MorphMountToolbar
