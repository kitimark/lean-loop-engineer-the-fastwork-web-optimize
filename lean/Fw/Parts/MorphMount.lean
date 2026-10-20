/-!
# morph.mount: when the end-of-page morph is mounted and armed (M2 `faithful` port)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 13040-13047 `O`: the platform rect is tall enough (`height >= 0.45 * vh`) and sits on the viewport bottom
    (`bottom <= vh + 8`), `vh = visualViewport?.height ?? innerHeight`;
  * 13048 `k`: a push may be taken when the morph is active, or when it is forward (`delta > 0`) and `O` holds;
  * 13049-13058 `A`, `j`, `M`: wheel delta; touch delta = previous y - current y (a finger moving up pushes forward);
  * 13059-13071 `N`, `P`: attach / detach the three capture listeners once each (`d` guards both);
  * 13072 `I`: listeners wanted = observer says near, or the morph is active;
  * 13073-13075 `L`: while active and `scrollY` differs from the pinned y, `scrollTo(top: pin, instant)`;
  * 13076-13086: `IntersectionObserver(rootMargin "200% 0px")` on `.start-selling-platform`; an entry that
    intersects mounts the panel (`z(b, !0)`) and re-evaluates `I`; the first push also mounts it (13015);
  * 12911 `C`: active = target > 0.001 or value > 0.001.
-/
namespace Fw.Parts.MorphMount

/-! ## Arming geometry -/

/-- The platform's viewport rect. Height and bottom edge of `.start-selling-platform`. -/
structure Rect where
  height : Rat
  bottom : Rat
deriving Repr, BEq, DecidableEq

/-- `O` (JS 13040-13047): the platform fills at least 45 % of the viewport and its bottom is within 8 px of it.

Whether a forward push may start the morph. -/
def armed (r : Rect) (vh : Rat) : Bool := decide (r.height ≥ vh * 45 / 100) && decide (r.bottom ≤ vh + 8)

#guard armed ⟨450, 800⟩ 1000 == true
#guard armed ⟨449, 800⟩ 1000 == false
#guard armed ⟨900, 1008⟩ 1000 == true
#guard armed ⟨900, 1009⟩ 1000 == false

/-- A taller platform stays armed. -/
theorem armed_mono_height (h h' b vh : Rat) (hh : h ≤ h') (a : armed ⟨h, b⟩ vh = true) :
    armed ⟨h', b⟩ vh = true := by
  simp only [armed, Bool.and_eq_true, decide_eq_true_eq] at a ⊢
  exact ⟨by grind, a.2⟩

/-- A platform that has scrolled further up (smaller bottom) stays armed. -/
theorem armed_mono_bottom (h b b' vh : Rat) (hb : b' ≤ b) (a : armed ⟨h, b⟩ vh = true) :
    armed ⟨h, b'⟩ vh = true := by
  simp only [armed, Bool.and_eq_true, decide_eq_true_eq] at a ⊢
  exact ⟨a.1, by grind⟩

/-! ## Taking a push -/

/-- `C` (JS 12911): the morph is active.

`w` is the tween target, `m` the current value. -/
def active (target value : Rat) : Bool := decide (target > 1 / 1000) || decide (value > 1 / 1000)

#guard active 0 0 == false
#guard active 1 0 == true
#guard active 0 (1 / 1000) == false
#guard active 0 (1 / 999) == true

/-- `k` (JS 13048): may this push be taken (and its default prevented).

`a` active, `d` the push delta, `g` the arming geometry. -/
def takes (act : Bool) (delta : Rat) (geom : Bool) : Bool := act || (decide (delta > 0) && geom)

/-- Once active, every push is taken, whatever its direction or the geometry. -/
theorem takes_active (d : Rat) (g : Bool) : takes true d g = true := by simp [takes]

/-- When idle, a backward or zero push is never taken. -/
theorem takes_idle_back (d : Rat) (g : Bool) (h : d ≤ 0) : takes false d g = false := by
  simp [takes]; grind

/-- When idle, a forward push is taken exactly when the geometry arms it. -/
theorem takes_idle_fwd (d : Rat) (g : Bool) (h : 0 < d) : takes false d g = g := by
  simp [takes]; grind

/-- Touch delta (JS 13054 `M`): previous y minus current y.

A finger moving up (y shrinks) is a positive, forward push. -/
def touchDelta (prev cur : Rat) : Rat := prev - cur

/-- A finger moving up is a forward push. -/
theorem touchDelta_up (a b : Rat) (h : b < a) : 0 < touchDelta a b := by
  simp [touchDelta]; grind

/-- Viewport height (JS 13043): the visual viewport's when it exists, else `innerHeight`. -/
def viewportHeight (visual : Option Rat) (inner : Rat) : Rat := visual.getD inner

/-! ## Listeners and mount -/

/-- `I` (JS 13072): the capture listeners are wanted while the observer says near, or the morph is active. -/
def wanted (near act : Bool) : Bool := near || act

/-- What `N` / `P` do (JS 13059-13071). -/
inductive Action where
  | attach | detach | none
deriving Repr, BEq, DecidableEq

/-- The listener action given whether they are attached and whether they are wanted (the `d` guard). -/
def action (attached want : Bool) : Action :=
  if want && !attached then .attach else if !want && attached then .detach else .none

/-- Attached state after the action, given the current attached state `d`. -/
def Action.after (d : Bool) : Action → Bool
  | .attach => true | .detach => false | .none => d

/-- After the action the listeners are attached exactly when wanted. -/
theorem action_after (d w : Bool) : (action d w).after d = w := by
  cases d <;> cases w <;> rfl

/-- Re-evaluating with the same wish does nothing (the guard makes `N` and `P` idempotent). -/
theorem action_idem (w : Bool) : action w w = .none := by cases w <;> rfl

/-- The panel is mounted from the first intersecting entry or the first accepted push, and never unmounted. -/
def mountNext (mounted intersecting pushed : Bool) : Bool := mounted || intersecting || pushed

/-- Mounting is monotone. -/
theorem mountNext_mono (i p : Bool) : mountNext true i p = true := by simp [mountNext]

/-- `L` (JS 13073-13075): while active, a scroll position other than the pin is sent back. -/
def repin (act : Bool) (y pin : Rat) : Bool := act && decide (y ≠ pin)

/-- Idle never repins. -/
theorem repin_idle (y p : Rat) : repin false y p = false := by simp [repin]

end Fw.Parts.MorphMount
