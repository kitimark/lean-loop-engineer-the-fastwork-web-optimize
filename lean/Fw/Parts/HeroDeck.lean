import Fw.Parts.HeroOrbit
/-!
# hero.deck and hero.cue: the phone deck and the scroll cue (P1, `faithful`)

Both are CSS only in the original (no JS beyond the `--exit-opacity` write owned by hero.exit); this file holds their
numbers as the exact spec a later optimised version is compared against.

Restated (not copied) from `snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`:

* 2053-2127 (`max-width: 600px`): the deck is four absolutely placed cards (`is-a`, `is-b`, `is-d`, `is-e`) with fixed
  sizes, `top` shares and side offsets, scatter vectors in `vw`/`vh`; the ring (`.orbit`) is hidden;
* 1905-1960: the cue's entrance (`copy-in` 0.7 s after 0.2 s at phone width, `copy-from-ring` 0.7 s after 1.14 s above
  600 px) and its float loop (`scroll-float`, 2.2 s, 0 to -8 px and back).
-/
namespace Fw.Parts.HeroDeck

/-- One deck slot: name, width px, height px, `top` in percent ($\tau = 69.2488$ is CSS `top: 69.2488%`), side (left
or right), side offset px, scatter x vw, scatter y vh, z-index.

$$(\mathit{slot}, w, h, \tau, \mathit{left}, o, s_x, s_y, z) \in \Sigma^* \times \mathbb{Q}^3 \times \mathbb{B} \times \mathbb{Q}^3 \times \mathbb{N}$$ -/
structure Slot where
  name : String
  width : Rat
  height : Rat
  topPct : Rat
  left : Bool
  offset : Rat
  sx : Rat
  sy : Rat
  z : Nat
deriving Repr

/-- The four slots (CSS 2085-2125); `offset` is `left: -o` for the left slots and `right: -o` for the right ones.

$$\text{slots}$$ -/
def slots : List Slot := [
  ⟨"is-a", 120, 149416/1000, 692488/10000, true, 69, -42, -12, 1⟩,
  ⟨"is-b", 16092/100, 200, 833333/10000, true, 48, -48, 22, 2⟩,
  ⟨"is-d", 120, 149416/1000, 692488/10000, false, 68, 42, -12, 1⟩,
  ⟨"is-e", 160625/1000, 200, 833333/10000, false, 45, 48, 22, 2⟩]

/-- Four slots. $$|\text{slots}| = 4$$ -/
theorem slots_len : slots.length = 4 := by decide +kernel

/-- The scatter is mirrored: the left slots go left, the right slots go right, by the same vertical amount.

$$[s_x(u) \mid u \in \text{slots}] = [-42, -48, 42, 48] \wedge [s_y(u) \mid u \in \text{slots}] = [-12, 22, -12, 22]$$

The deck leaves the screen symmetrically on exit. -/
theorem scatter_mirrored :
    (slots.map (·.sx)) = [-42, -48, 42, 48] ∧ (slots.map (·.sy)) = [-12, 22, -12, 22] := by
  refine ⟨?_, ?_⟩ <;> decide +kernel

/-- The back cards (`is-a`, `is-d`) are below the front ones (`is-b`, `is-e`) in z-order. $$z = [1, 2, 1, 2]$$ -/
theorem z_order : (slots.map (·.z)) = [1, 2, 1, 2] := by decide +kernel

/-- Heights are within 1 px of $w \cdot 1.2451$ for the back cards (the design aspect). The front cards are 200 px tall.

$$|h - 1.2451\,w| < 1\ \text{for}\ a, d$$ -/
theorem back_aspect : (slots.filter (·.z == 1)).all (fun s => decide (s.height - s.width * 12451 / 10000 < 1 ∧ -1 < s.height - s.width * 12451 / 10000)) = true := by
  decide +kernel

/-! ## The cue -/

/-- The float loop period in ms (CSS `scroll-float` 2.2 s). $$P_c = 2200$$ -/
def floatPeriod : Rat := 2200

/-- The float amplitude in px (CSS keyframe 50%). $$A = 8$$ -/
def floatAmp : Rat := 8

/-- The float at a keyframe stop $f$ (a fraction of the loop): $-A$ at the middle stop $f = \tfrac12$, $0$ at every other
$f$ (so at the start and end stops).

$$\forall f \in \mathbb{Q}:\ y(f) = \begin{cases} -8 & f = \tfrac12 \\ 0 & \text{otherwise} \end{cases}$$

(Between the stops the browser interpolates with `ease-in-out`.) -/
def floatStop (f : Rat) : Rat := if f = 1 / 2 then -floatAmp else 0

/-- The entrance of the cue above 600 px: delay in ms (CSS `copy-from-ring` 1.14 s). $$\delta = 1140$$ -/
def entranceDelay : Rat := 1140

/-- The entrance duration in ms (CSS 0.7 s). $$D_c = 700$$ -/
def entranceDur : Rat := 700

/-- The entrance of the cue at phone width: delay in ms (CSS `copy-in` 0.2 s). $$\delta_m = 200$$ -/
def entranceDelayPhone : Rat := 200

/-- The desktop entrance ends 20 ms after the splash timer.

$$\delta + D_c = 1840 = T + 20,\quad T = 1820$$

At the timer the cue is switched to its final state (`--copy-in: 1`, no animation) while the entrance has 20 ms left. -/
theorem entrance_after_splash : entranceDelay + entranceDur = Fw.Parts.HeroOrbit.splashEnd + 20 := by
  decide +kernel

/-- The phone entrance ends before the desktop splash would. $$200 + 700 = 900 < 1820$$ -/
theorem phone_entrance_early : entranceDelayPhone + entranceDur < Fw.Parts.HeroOrbit.splashEnd := by
  decide +kernel

/-- The cue's blur on exit in px (CSS `blur(scatter * 18px)`) is at most 18. $$0 \le s \le 1 \Rightarrow 0 \le 18 s \le 18$$ -/
theorem cue_blur_le (s : Rat) (h0 : 0 ≤ s) (h1 : s ≤ 1) : 0 ≤ s * 18 ∧ s * 18 ≤ 18 := by
  constructor <;> grind

end Fw.Parts.HeroDeck
