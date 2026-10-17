import Fw.Parts.PlatformSweep
/-!
# platform.marquee: the 90 s review marquee (P5 port, `faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`:

* 6484-6496 and 7497: `@keyframes` left $\mathrm{translateX}(0) \to \mathrm{translateX}(-50\%)$, right
  $\mathrm{translateX}(-50\%) \to \mathrm{translateX}(0)$, `90s linear infinite`, on a `width: max-content` track that holds
  two identical sets, so $-50\%$ is exactly one set;
* 6500-6510 (`prefers-reduced-motion: reduce`): the animation is off and the cards sit at rest;
* the dead 56 s `secure-fx-marquee` (CSS 6617) is not ported.

All values `Rat`. `w` is the track width in px.
-/
namespace Fw.Parts.PlatformMarquee
open Fw.Parts.PlatformSweep (frac frac_mem frac_add_one)

/-- Length of a pass in ms (`90s linear infinite`). $$T = 90000$$ -/
def period : Rat := 90000

/-- Cycle fraction at time $t$ ms. $$\varphi(t) = \operatorname{frac}(t / T)$$ -/
def phase (t : Rat) : Rat := frac (t / period)

/-- `translateX` in px of the left-running track of width $w$.

$$x_L(w, t) = -\tfrac w2\,\varphi(t)$$ -/
def offsetLeft (w t : Rat) : Rat := -(w / 2) * phase t

/-- `translateX` in px of the right-running track. $$x_R(w, t) = -\tfrac w2\,(1 - \varphi(t))$$ -/
def offsetRight (w t : Rat) : Rat := -(w / 2) * (1 - phase t)

/-- The cycle fraction is in $[0, 1)$. $$0 \le \varphi(t) < 1$$ -/
theorem phase_mem (t : Rat) : 0 ≤ phase t ∧ phase t < 1 := frac_mem _

/-- The marquee is 90 s periodic. $$\varphi(t + 90000) = \varphi(t)$$ -/
theorem phase_periodic (t : Rat) : phase (t + period) = phase t := by
  unfold phase
  have h : (t + period) / period = t / period + 1 := by unfold period; grind
  rw [h, frac_add_one]

/-- The left track moves from $0$ towards $-w/2$ and never past it.

$$w \ge 0 \Rightarrow -\tfrac w2 < x_L(w, t) \le 0$$ -/
theorem left_range (w t : Rat) (hw : 0 ≤ w) : -(w / 2) ≤ offsetLeft w t ∧ offsetLeft w t ≤ 0 := by
  have h := phase_mem t
  unfold offsetLeft
  have h1 := Rat.mul_nonneg (show 0 ≤ w / 2 by grind) h.1
  have h2 := Rat.mul_le_mul_of_nonneg_left (show phase t ≤ 1 by grind) (show 0 ≤ w / 2 by grind)
  grind

/-- The right track mirrors the left one inside the same range.

$$w \ge 0 \Rightarrow -\tfrac w2 \le x_R(w, t) \le 0$$ -/
theorem right_range (w t : Rat) (hw : 0 ≤ w) : -(w / 2) ≤ offsetRight w t ∧ offsetRight w t ≤ 0 := by
  have h := phase_mem t
  unfold offsetRight
  have h1 := Rat.mul_nonneg (show 0 ≤ w / 2 by grind) (show 0 ≤ 1 - phase t by grind)
  have h2 := Rat.mul_le_mul_of_nonneg_left (show 1 - phase t ≤ 1 by grind) (show 0 ≤ w / 2 by grind)
  grind

/-- Left plus right is one set width. $$x_L(w, t) + x_R(w, t) = -\tfrac w2$$ The two tracks are mirror images. -/
theorem left_add_right (w t : Rat) : offsetLeft w t + offsetRight w t = -(w / 2) := by
  unfold offsetLeft offsetRight; grind

/-- The offset at phase 1 (the limit of a pass) is exactly one set to the left of the start.

$$x_L\big|_{\varphi = 1} = -\tfrac w2 = x_L\big|_{\varphi = 0} - \tfrac w2$$

With two identical sets of width $w/2$, the picture at the end of a pass equals the picture at its start, so the jump
back is invisible. -/
theorem seam (w : Rat) : -(w / 2) * 1 = -(w / 2) * 0 - w / 2 := by grind

/-- Speed in px per ms of the left track within one pass. $$v_L = -\frac{w}{2T} = -\frac{w}{180000}$$ -/
def speed (w : Rat) : Rat := -(w / 2) / period

/-- Speed times a full pass is one set. $$v_L \cdot T = -\tfrac w2$$ -/
theorem speed_pass (w : Rat) : speed w * period = -(w / 2) := by
  unfold speed period; grind

/-- The animation runs only when motion is allowed. $$\operatorname{running}(\mathit{reduce}) = \lnot\,\mathit{reduce}$$ -/
def running (reduce : Bool) : Bool := !reduce

#guard offsetLeft 1000 0 == 0
#guard offsetLeft 1000 45000 == -250
#guard offsetRight 1000 0 == -500
#guard offsetRight 1000 45000 == -250
#guard offsetLeft 1000 90000 == 0

end Fw.Parts.PlatformMarquee
