import Fw.Parts.MorphTween
import Fw.Parts.Contract
/-!
# commission.typing: the fee visual's looping timeline (P4 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 2403-2520 (`JT`): the chat bubble types the message `s(o)` one character per 28 ms; the loop is
    `E` (reset, 80 ms) then `D` (420 ms avatar, typing, 180 ms, 480 ms, count-up 1100 ms, 120 ms, count-down 900 ms, 1600 ms,
    scroll-out 900 ms) and then `E` again, for as long as the visual is intersecting (2491-2499);
  * 2433-2437 (`T`): the tween curve $1-(1-s)^3$;
  * 2445-2459 (`S`): a tween runs for `a` ms from the instant it is called and ends exactly at $s = 1$;
  * 2500-2519: the observer (thresholds 0, 0.05, 0.2) flips `e`, bumps the token `r`, cancels every timer and, on entry, starts
    `O` (reduced motion shows the final picture, 2481-2486);
  * `snapshot/.../assets/2.gBuqKVzi.css` 413-425 (`.typing-caret`, `typing-caret` keyframes 583-591, step-end, 0.9 s),
    113-216 (`three-frame-*`, 0.6 s, step-end).

Time is the ms since the loop's first instant (the instant `E` runs). All numbers `Rat`; no `Float`. The idealisation:
timers fire at their exact instants and a tween ends exactly at its duration (the browser adds rAF/timer lateness; the
driver reads the clock instead of counting ticks, so it does not accumulate it).
-/
namespace Fw.Parts.CommissionTyping
open Fw.Parts.MorphTween (ease ease_mem ease_mono)

/-! ## Constants -/

/-- The chat message (the English string of the original's `commission.message`, JS 1225).

$$m = \text{"Hi! I found your profile from Explore."}$$ -/
def message : String := "Hi! I found your profile from Explore."

/-- Its length in characters. $$L = 38$$ How many keystrokes the bubble types. -/
def msgLen : Nat := message.length

#guard msgLen == 38

/-- `E` waits this long (JS 2478). $$t_E = 80$$ The reset blink. -/
def tReset : Nat := 80
/-- The avatar shows, then the bubble waits this long (JS 2482). $$t_A = 420$$ Avatar to bubble. -/
def tAvatar : Nat := 420
/-- One character per this many ms (JS 2488). $$t_c = 28$$ The typing step. -/
def tChar : Nat := 28
/-- After the last character the caret stays this long (JS 2491). $$t_h = 180$$ Caret hold. -/
def tCaretHold : Nat := 180
/-- Then the referral card shows and waits (JS 2493). $$t_R = 480$$ Card to count-up. -/
def tReferral : Nat := 480
/-- The earned count-up runs this long, $0 \to 100$ (JS 2494). $$t_N = 1100$$ Count-up. -/
def tCount : Nat := 1100
/-- Pause between the two tweens (JS 2497). $$t_g = 120$$ The gap. -/
def tGap : Nat := 120
/-- The percentage runs $18 \to 0$ in this long (JS 2498). $$t_P = 900$$ Count-down. -/
def tPct : Nat := 900
/-- Hold on the final picture (JS 2499). $$t_H = 1600$$ Hold. -/
def tHold : Nat := 1600
/-- The scroll-out transition (CSS `.fee-visual-beat`, 0.9 s) is awaited for this long (JS 2501). $$t_O = 900$$ Scroll-out. -/
def tOut : Nat := 900

/-- Where the percentage starts (JS 2407, `c.pct`). $$p_0 = 18$$ -/
def pct0 : Nat := 18
/-- Where the earned amount ends (JS 2494). $$e_1 = 100$$ -/
def earnedMax : Nat := 100

/-! ## Milestones of one cycle -/

/-- The instant the avatar shows, $D$ starts. $$m_0 = t_E = 80$$ -/
def mAvatar : Nat := tReset
/-- The bubble shows, the caret appears, the first character is typed. $$m_1 = m_0 + t_A = 500$$ -/
def mMsg : Nat := mAvatar + tAvatar
/-- The last character was typed one step ago: caret off. $$m_2 = m_1 + L\,t_c = 1564$$ -/
def mTypeEnd : Nat := mMsg + msgLen * tChar
/-- The referral card shows. $$m_3 = m_2 + t_h = 1744$$ -/
def mReferral : Nat := mTypeEnd + tCaretHold
/-- The count-up starts. $$m_4 = m_3 + t_R = 2224$$ -/
def mCountStart : Nat := mReferral + tReferral
/-- The count-up ends. $$m_5 = m_4 + t_N = 3324$$ -/
def mCountEnd : Nat := mCountStart + tCount
/-- The count-down starts. $$m_6 = m_5 + t_g = 3444$$ -/
def mPctStart : Nat := mCountEnd + tGap
/-- The count-down ends. $$m_7 = m_6 + t_P = 4344$$ -/
def mPctEnd : Nat := mPctStart + tPct
/-- The visual scrolls out. $$m_8 = m_7 + t_H = 5944$$ -/
def mOut : Nat := mPctEnd + tHold
/-- The cycle: reset, then the rest, then reset again. $$T = m_8 + t_O = 6844$$ -/
def period : Nat := mOut + tOut

#guard mMsg == 500
#guard mTypeEnd == 1564
#guard mReferral == 1744
#guard mCountStart == 2224
#guard mCountEnd == 3324
#guard mPctStart == 3444
#guard mPctEnd == 4344
#guard mOut == 5944
#guard period == 6844

/-- The cycle is the reset blink plus the body `D`. $$T = t_E + (t_A + L t_c + t_h + t_R + t_N + t_g + t_P + t_H + t_O)$$ A cycle is exactly what the original's `E; D` takes. -/
theorem period_eq : period = tReset + (tAvatar + msgLen * tChar + tCaretHold + tReferral + tCount + tGap + tPct + tHold + tOut) := by
  unfold period mOut mPctEnd mPctStart mCountEnd mCountStart mReferral mTypeEnd mMsg mAvatar
  omega

/-! ## The picture -/

/-- Everything the visual shows at one instant (the Svelte state `y d h g _ v p b x C`).

$$V = (\mathit{resetting}, \mathit{avatar}, \mathit{bubble}, n, \mathit{caret}, \mathit{card}, \mathit{out}, e, q, w)$$ with $n \in [0, L]$ typed characters. -/
structure View where
  resetting : Bool
  avatar : Bool
  bubble : Bool
  chars : Nat
  caret : Bool
  card : Bool
  out : Bool
  earned : Rat
  pct : Rat
  progress : Rat
deriving Repr, BEq, DecidableEq

/-- The blank picture `E` sets (JS 2467-2477). $$V_0 = (\top, \bot, \bot, 0, \bot, \bot, \bot, 0, 18, 0)$$ All hidden, counters at their start. -/
def resetView : View :=
  ⟨true, false, false, 0, false, false, false, 0, pct0, 0⟩

/-- The picture before the first run (the initial state, JS 2407-2417): as the blank one but not resetting. $$V_{\mathrm{init}} = V_0[\mathit{resetting} := \bot]$$ -/
def initialView : View := { resetView with resetting := false }

/-- The picture reduced motion sets (JS 2481-2484). $$V_{\mathrm{rm}} = (\bot, \top, \top, L, \bot, \top, \bot, 100, 0, 1)$$ The finished picture, at once. -/
def finalView : View :=
  ⟨false, true, true, msgLen, false, true, false, earnedMax, 0, 1⟩

/-- A tween from `f` to `t` over `d` ms, `τ` ms after it started (JS 2445-2459).

$$\operatorname{ramp}(f, t, d, \tau) = f + (t - f)\,\operatorname{ease}(\tau/d)$$

The curve is $\operatorname{ease}(x) = 1 - (1 - \operatorname{clamp}(x))^3$ (the original's `T`, the clamp being its `Math.min(1, ...)`). -/
def ramp (f t : Rat) (d : Nat) (τ : Rat) : Rat := f + (t - f) * ease (τ / d)

/-- The number of typed characters at `τ`: the characters whose timer has fired (the $k$-th at $m_1 + k\,t_c$).

$$\operatorname{chars}(\tau) = \#\{k < L \mid m_1 + k\,t_c \le \tau\}$$

The original sets `p = message.slice(0, t)` at those instants (JS 2487-2489). -/
def chars (τ : Rat) : Nat :=
  (List.range msgLen).countP fun k => decide (((mMsg + tChar * k : Nat) : Rat) ≤ τ)

/-- The earned amount at `τ` (JS 2494, `S(e, 0, 100, 1100, ...)`).

$$e(\tau) = \begin{cases} 0 & \tau < m_4 \\ 100\,\operatorname{ease}\big((\tau - m_4)/1100\big) & \tau \ge m_4 \end{cases}$$ -/
def earnedAt (τ : Rat) : Rat :=
  if ((mCountStart : Nat) : Rat) ≤ τ then ramp 0 earnedMax tCount (τ - mCountStart) else 0

/-- The percentage at `τ` (JS 2497, `S(e, 18, 0, 900, ...)`).

$$q(\tau) = \begin{cases} 18 & \tau < m_6 \\ 18\,(1 - \operatorname{ease}\big((\tau - m_6)/900\big)) & \tau \ge m_6 \end{cases}$$ -/
def pctAt (τ : Rat) : Rat :=
  if ((mPctStart : Nat) : Rat) ≤ τ then ramp pct0 0 tPct (τ - mPctStart) else pct0

/-- The picture `τ` ms into a cycle ($0 \le \tau < T$).

$$V(\tau) = \begin{cases} V_0 & \tau < m_0 \\ (\bot,\ \top,\ \tau \ge m_1,\ \operatorname{chars}(\tau),\ m_1 \le \tau < m_2,\ \tau \ge m_3,\ \tau \ge m_8,\ e(\tau),\ q(\tau),\ e(\tau)/100) & \tau \ge m_0 \end{cases}$$

What the screen shows `τ` after the reset began. -/
def viewAt (τ : Rat) : View :=
  if τ < (mAvatar : Nat) then resetView
  else
    ⟨false, true, decide (((mMsg : Nat) : Rat) ≤ τ), chars τ,
     decide (((mMsg : Nat) : Rat) ≤ τ ∧ τ < ((mTypeEnd : Nat) : Rat)),
     decide (((mReferral : Nat) : Rat) ≤ τ), decide (((mOut : Nat) : Rat) ≤ τ),
     earnedAt τ, pctAt τ, earnedAt τ / earnedMax⟩

#guard viewAt 0 == resetView
#guard viewAt 79 == resetView
#guard (viewAt 80).avatar && !(viewAt 80).bubble && !(viewAt 80).resetting
#guard (viewAt 499).chars == 0
#guard (viewAt 500).chars == 1 && (viewAt 500).caret && (viewAt 500).bubble
#guard (viewAt 527).chars == 1
#guard (viewAt 528).chars == 2
#guard (viewAt 1535).chars == 37
#guard (viewAt 1536).chars == 38
#guard (viewAt 1563).caret
#guard !(viewAt 1564).caret
#guard !(viewAt 1743).card
#guard (viewAt 1744).card
#guard (viewAt 2223).earned == 0
#guard (viewAt 3324).earned == 100 && (viewAt 3324).progress == 1
#guard (viewAt 4344).pct == 0
#guard !(viewAt 5943).out
#guard (viewAt 5944).out

/-- Before the first character nothing is typed.

$$\forall \tau < m_1:\ \operatorname{chars}(\tau) = 0$$

The bubble is empty until it is shown. -/
theorem chars_zero (τ : Rat) (h : τ < ((mMsg : Nat) : Rat)) : chars τ = 0 := by
  unfold chars
  rw [List.countP_eq_zero]
  intro k _ hk
  simp only [decide_eq_true_eq] at hk
  have : ((mMsg : Nat) : Rat) ≤ ((mMsg + tChar * k : Nat) : Rat) := by
    exact_mod_cast Nat.le_add_right _ _
  grind

/-- Typed characters never exceed the message.

$$\forall \tau:\ \operatorname{chars}(\tau) \le L$$

The bubble cannot show more text than the message holds. -/
theorem chars_le (τ : Rat) : chars τ ≤ msgLen := by
  unfold chars
  have := @List.countP_le_length _ (fun k => decide (((mMsg + tChar * k : Nat) : Rat) ≤ τ)) (List.range msgLen)
  simpa using this

/-- Typing only moves forward.

$$\forall \sigma \le \tau:\ \operatorname{chars}(\sigma) \le \operatorname{chars}(\tau)$$

No character is ever taken back during a cycle. -/
theorem chars_mono (σ τ : Rat) (h : σ ≤ τ) : chars σ ≤ chars τ := by
  unfold chars
  apply List.countP_mono_left
  intro k _ hk
  simp only [decide_eq_true_eq] at hk ⊢
  grind

/-- After the last keystroke the whole message is shown.

$$\forall \tau \ge m_1 + (L - 1)\,t_c:\ \operatorname{chars}(\tau) = L$$

The final character appears at $m_1 + 37 \cdot 28 = 1536$. -/
theorem chars_full (τ : Rat) (h : ((mMsg + tChar * (msgLen - 1) : Nat) : Rat) ≤ τ) : chars τ = msgLen := by
  unfold chars
  have : ((List.range msgLen).countP fun k => decide (((mMsg + tChar * k : Nat) : Rat) ≤ τ)) = (List.range msgLen).length := by
    rw [List.countP_eq_length]
    intro k hk
    have hk' : k ≤ msgLen - 1 := by
      have := List.mem_range.mp hk
      omega
    have : ((mMsg + tChar * k : Nat) : Rat) ≤ ((mMsg + tChar * (msgLen - 1) : Nat) : Rat) := by
      exact_mod_cast Nat.add_le_add_left (Nat.mul_le_mul_left _ hk') _
    simp only [decide_eq_true_eq]
    grind
  simpa using this

/-- The milestones as rational literals (so the linear solver sees them). $$m_0 = 80,\ m_4 = 2224,\ m_5 = 3324,\ m_6 = 3444,\ t_N = 1100,\ t_P = 900$$ -/
theorem cast_lits :
    ((tCount : Nat) : Rat) = 1100 ∧ ((tPct : Nat) : Rat) = 900 ∧ ((mCountStart : Nat) : Rat) = 2224 ∧
    ((mCountEnd : Nat) : Rat) = 3324 ∧ ((mPctStart : Nat) : Rat) = 3444 ∧ ((mAvatar : Nat) : Rat) = 80 := by
  decide

/-- The earned amount stays in $[0, 100]$.

$$\forall \tau:\ 0 \le e(\tau) \le 100$$

The count-up never overshoots. -/
theorem earned_mem (τ : Rat) : 0 ≤ earnedAt τ ∧ earnedAt τ ≤ 100 := by
  have h := ease_mem ((τ - mCountStart) / tCount)
  unfold earnedAt ramp
  split
  · simp only [earnedMax]
    generalize ease ((τ - mCountStart) / tCount) = k at *
    have e100 : ((100 : Nat) : Rat) = 100 := by decide
    rw [e100]
    have := Rat.mul_nonneg (show (0 : Rat) ≤ 100 - 0 by grind) h.1
    have := Rat.mul_le_mul_of_nonneg_left h.2 (show (0 : Rat) ≤ 100 - 0 by grind)
    grind
  · exact ⟨Rat.le_refl, by decide⟩

/-- The earned amount only grows.

$$\forall \sigma \le \tau:\ e(\sigma) \le e(\tau)$$

The count-up is monotone (its curve is). -/
theorem earned_mono (σ τ : Rat) (h : σ ≤ τ) : earnedAt σ ≤ earnedAt τ := by
  obtain ⟨c1, -⟩ := cast_lits
  have hm := ease_mono ((σ - mCountStart) / tCount) ((τ - mCountStart) / tCount) (by rw [c1]; grind)
  have h0 := ease_mem ((σ - mCountStart) / tCount)
  have h1 := ease_mem ((τ - mCountStart) / tCount)
  have e100 : ((100 : Nat) : Rat) = 100 := by decide
  unfold earnedAt ramp
  by_cases hs : ((mCountStart : Nat) : Rat) ≤ σ
  · have ht : ((mCountStart : Nat) : Rat) ≤ τ := by grind
    simp only [hs, ht, ite_true, earnedMax, e100]
    generalize ease ((σ - mCountStart) / tCount) = a at *
    generalize ease ((τ - mCountStart) / tCount) = b at *
    grind
  · by_cases ht : ((mCountStart : Nat) : Rat) ≤ τ
    · simp only [hs, ht, ite_true, ite_false, earnedMax, e100]
      generalize ease ((τ - mCountStart) / tCount) = b at *
      grind
    · simp only [hs, ht, ite_false]; exact Rat.le_refl

/-- The count-up ends on 100.

$$\forall \tau \ge m_5:\ e(\tau) = 100$$

The bar is full when the count-up has run its 1100 ms. -/
theorem earned_end (τ : Rat) (h : ((mCountEnd : Nat) : Rat) ≤ τ) :
    earnedAt τ = 100 := by
  obtain ⟨c1, -, c4, c5, -⟩ := cast_lits
  have hs : ((mCountStart : Nat) : Rat) ≤ τ := by grind
  have hx : (1 : Rat) ≤ (τ - mCountStart) / tCount := by rw [c1]; grind
  have he : ease ((τ - mCountStart) / tCount) = 1 := by
    unfold ease Fw.Parts.MorphTween.clamp01
    have : min 1 (max 0 ((τ - mCountStart) / tCount)) = 1 := by grind
    rw [this]; grind
  have e100 : ((100 : Nat) : Rat) = 100 := by decide
  unfold earnedAt ramp
  simp only [hs, ite_true, he, earnedMax, e100]
  grind

/-- The percentage stays in $[0, 18]$.

$$\forall \tau:\ 0 \le q(\tau) \le 18$$

The count-down never goes below 0. -/
theorem pct_mem (τ : Rat) : 0 ≤ pctAt τ ∧ pctAt τ ≤ 18 := by
  have h := ease_mem ((τ - mPctStart) / tPct)
  have e18 : ((pct0 : Nat) : Rat) = 18 := by decide
  unfold pctAt ramp
  split
  · rw [e18]
    generalize ease ((τ - mPctStart) / tPct) = k at *
    have := Rat.mul_nonneg (show (0 : Rat) ≤ 18 - 0 by grind) h.1
    have := Rat.mul_le_mul_of_nonneg_left h.2 (show (0 : Rat) ≤ 18 - 0 by grind)
    grind
  · rw [e18]; exact ⟨by decide, Rat.le_refl⟩

/-- The percentage only falls.

$$\forall \sigma \le \tau:\ q(\tau) \le q(\sigma)$$

The count-down is monotone. -/
theorem pct_anti (σ τ : Rat) (h : σ ≤ τ) : pctAt τ ≤ pctAt σ := by
  obtain ⟨-, c2, -⟩ := cast_lits
  have hm := ease_mono ((σ - mPctStart) / tPct) ((τ - mPctStart) / tPct) (by rw [c2]; grind)
  have h0 := ease_mem ((σ - mPctStart) / tPct)
  have h1 := ease_mem ((τ - mPctStart) / tPct)
  have e18 : ((pct0 : Nat) : Rat) = 18 := by decide
  unfold pctAt ramp
  by_cases hs : ((mPctStart : Nat) : Rat) ≤ σ
  · have ht : ((mPctStart : Nat) : Rat) ≤ τ := by grind
    simp only [hs, ht, ite_true, e18]
    generalize ease ((σ - mPctStart) / tPct) = a at *
    generalize ease ((τ - mPctStart) / tPct) = b at *
    have : ((0 : Nat) : Rat) = 0 := by decide
    grind
  · by_cases ht : ((mPctStart : Nat) : Rat) ≤ τ
    · simp only [hs, ht, ite_true, ite_false, e18]
      generalize ease ((τ - mPctStart) / tPct) = b at *
      grind
    · simp only [hs, ht, ite_false]; exact Rat.le_refl

/-- The picture is blank for the whole reset blink.

$$\forall \tau < 80:\ V(\tau) = V_0$$

`E` hides everything and zeroes the counters for 80 ms. -/
theorem viewAt_reset (τ : Rat) (h : τ < ((mAvatar : Nat) : Rat)) : viewAt τ = resetView := by
  unfold viewAt
  simp [h]

/-- From $m_0$ on, the caret is on for exactly $[m_1, m_2)$.

$$\forall \tau \in \mathbb{Q}:\ \tau \ge m_0 \Rightarrow \bigl(\mathrm{caret}(V(\tau)) = \top \iff m_1 \le \tau < m_2\bigr)$$

It is created with the bubble and removed when the last character has waited its 28 ms. -/
theorem caret_iff (τ : Rat) (h : ((mAvatar : Nat) : Rat) ≤ τ) :
    (viewAt τ).caret = true ↔ (((mMsg : Nat) : Rat) ≤ τ ∧ τ < ((mTypeEnd : Nat) : Rat)) := by
  have hn : ¬ τ < ((mAvatar : Nat) : Rat) := by grind
  unfold viewAt
  simp only [hn, ite_false, decide_eq_true_eq]

/-- Every picture's progress is the earned amount over 100.

$$\forall \tau:\ \tau \ge m_0 \Rightarrow \mathrm{progress}(V(\tau)) = e(\tau)/100$$

The bar width is the count (JS 2498: `C = e / 100`). -/
theorem progress_eq (τ : Rat) (h : ((mAvatar : Nat) : Rat) ≤ τ) :
    (viewAt τ).progress = (viewAt τ).earned / earnedMax := by
  have hn : ¬ τ < ((mAvatar : Nat) : Rat) := by grind
  unfold viewAt
  simp only [hn, ite_false]

/-! ## The caret and the boiling frames (CSS, step-end) -/

/-- Reduce an instant modulo a period by subtracting it `fuel` times at most.

$$\operatorname{wrap}_p(0, \tau) = \tau,\quad \operatorname{wrap}_p(n + 1, \tau) = \begin{cases} \tau & \tau < p \\ \operatorname{wrap}_p(n, \tau - p) & \text{otherwise} \end{cases}$$ -/
def wrap (p : Nat) : Nat → Rat → Rat
  | 0, τ => τ
  | n + 1, τ => if τ < (p : Rat) then τ else wrap p n (τ - p)

/-- The phase of an animation of period `p` ms after `age` ms.

$$\operatorname{phase}_p(a) = a \bmod p \quad (a \ge 0)$$

(`wrap` with $\lceil a \rceil$ steps, which is always enough.) -/
def phase (p : Nat) (age : Rat) : Rat := wrap p age.num.natAbs age

/-- The caret blink period (CSS `typing-caret`, 0.9 s). $$B = 900$$ -/
def blink : Nat := 900

/-- The caret is opaque for the first half of each period (keyframes `0%, 49% { opacity: 1 }`, `50%, to { opacity: 0 }`
with `step-end`).

$$\operatorname{caretOpaque}(a) = \big[(a \bmod 900) < 450\big]$$

The caret blinks 450 ms on, 450 ms off, starting on when it is created. -/
def caretOpaque (age : Rat) : Bool := decide (phase blink age < 450)

#guard caretOpaque 0
#guard caretOpaque 449.9
#guard !caretOpaque 450
#guard !caretOpaque 899.9
#guard caretOpaque 900
#guard caretOpaque 1349
#guard !caretOpaque 1350

/-- The first half of a period is on, the second off.

$$\forall a \in [0, 450):\ \mathrm{caretOpaque}(a) \wedge \forall a \in [450, 900):\ \neg\,\mathrm{caretOpaque}(a)$$

One blink cycle. -/
theorem caretOpaque_cycle (a : Rat) (_h0 : 0 ≤ a) (h1 : a < 900) :
    (caretOpaque a = true ↔ a < 450) := by
  unfold caretOpaque phase
  have hw : ∀ n : Nat, wrap blink (n + 1) a = a := by
    intro n
    unfold wrap
    have : a < (blink : Rat) := by unfold blink; exact_mod_cast h1
    simp [this]
  cases hn : a.num.natAbs with
  | zero => simp only [wrap]; exact decide_eq_true_iff
  | succ n => rw [hw n]; simp

/-- The boiling frame shown at `age` (CSS `three-frame-*`, 0.6 s, step-end): frame 0 until 33.33 %, frame 1 until 66.66 %,
frame 2 for the rest.

$$\operatorname{boil}(a) = \begin{cases} 0 & (a \bmod 600) < 199.98 \\ 1 & (a \bmod 600) < 399.96 \\ 2 & \text{otherwise} \end{cases}$$

The hand-drawn wobble of the underline and the zero. -/
def boilFrame (age : Rat) : Nat :=
  let ph := phase 600 age
  if ph < 19998 / 100 then 0 else if ph < 39996 / 100 then 1 else 2

#guard boilFrame 0 == 0
#guard boilFrame 199.9 == 0
#guard boilFrame 199.98 == 1
#guard boilFrame 399.9 == 1
#guard boilFrame 399.96 == 2
#guard boilFrame 599.9 == 2
#guard boilFrame 600 == 0

/-! ## Triggers -/

/-- The observer state (JS 2420-2422, 2500-2506: `e`, `r`, the timers) and the run bookkeeping.

$$S = (\mathit{visible}, \mathit{token}, \mathit{since}, \mathit{frozen}, \mathit{static})$$

`since` is the instant the current run began (none: no run), `frozen` the loop time when the last run was cancelled
(timers stop, the picture stays), `static` whether the run began under reduced motion. -/
structure Trig where
  visible : Bool
  token : Nat
  since : Option Rat
  frozen : Rat
  static : Bool
deriving Repr, BEq, DecidableEq

/-- The state before any observation. $$S_0 = (\bot, 0, \bot, 0, \bot)$$ -/
def trig0 : Trig := ⟨false, 0, none, 0, false⟩

/-- What the observer callback asks for.

$$\mathrm{Act} = \{\mathrm{keep}, \mathrm{cancel}, \mathrm{restart}\}$$ -/
inductive Act where
  | keep | cancel | restart
deriving Repr, BEq, DecidableEq

/-- The observer callback (JS 2500-2506): if `isIntersecting` differs from the stored flag, store it, bump the token,
cancel every timer, and on entry start a run (`O`); otherwise nothing.

$$\operatorname{observe}(S, i, \mathit{now}, \mathit{rm}) = \begin{cases} (S, \mathrm{keep}) & i = S.\mathit{visible} \\ (S', \mathrm{restart}) & i \ne S.\mathit{visible},\ i \\ (S', \mathrm{cancel}) & i \ne S.\mathit{visible},\ \lnot i \end{cases}$$

The new state has token $S.\mathit{token} + 1$, a run starting at $\mathit{now}$ on entry and a freeze at $\mathit{now} - \mathit{since}$ on exit. -/
def observe (s : Trig) (i : Bool) (now : Rat) (rm : Bool) : Trig × Act :=
  if i = s.visible then (s, .keep)
  else
    let frozen := match s.since with | some t => now - t | none => s.frozen
    if i then (⟨true, s.token + 1, some now, 0, rm⟩, .restart)
    else (⟨false, s.token + 1, none, frozen, s.static⟩, .cancel)

/-- The loop time at `now`: running from `since`, else held. $$\tau(S, \mathit{now}) = \mathit{now} - \mathit{since}\ \text{or}\ \mathit{frozen}$$ -/
def elapsed (s : Trig) (now : Rat) : Rat :=
  match s.since with | some t => now - t | none => s.frozen

/-- The loop time reduced into one cycle. $$\tau_c = \tau \bmod T$$ -/
def cycleTime (s : Trig) (now : Rat) : Rat := phase period (elapsed s now)

/-- The picture at `now`: initial before any run, the final one for a reduced-motion run, else the cycle's picture.

$$\mathrm{picture}(S, \mathit{now}) = \begin{cases} V_{\mathrm{init}} & S.\mathit{token} = 0 \\ V_{\mathrm{rm}} & S.\mathit{static} \\ V(\tau \bmod T) & \text{otherwise} \end{cases}$$ -/
def picture (s : Trig) (now : Rat) : View :=
  if s.token = 0 then initialView else if s.static then finalView else viewAt (cycleTime s now)

/-- Nothing changes when the flag does not. $$\forall S, \mathit{now}, \mathit{rm}:\ \operatorname{observe}(S, S.\mathit{visible}, \mathit{now}, \mathit{rm}) = (S, \mathrm{keep})$$ -/
theorem observe_same (s : Trig) (now : Rat) (rm : Bool) : observe s s.visible now rm = (s, .keep) := by
  simp [observe]

/-- The token moves exactly when visibility changes.

$$\forall S, i:\ i \ne S.\mathit{visible} \Rightarrow \operatorname{observe}(S, i, \cdot).\mathit{token} = S.\mathit{token} + 1$$

Every stale timer sees a different token and stops. -/
theorem observe_token (s : Trig) (i : Bool) (now : Rat) (rm : Bool) (h : i ≠ s.visible) :
    (observe s i now rm).1.token = s.token + 1 := by
  unfold observe
  simp only [h, ite_false]
  split <;> simp

/-- Entering view restarts the loop at its first instant.

$$\forall S, \mathit{now}:\ \neg S.\mathit{visible} \Rightarrow \tau\big(\operatorname{observe}(S, \top, \mathit{now}, \mathit{rm}).1,\ \mathit{now}\big) = 0$$

Re-entry starts from the reset blink, whatever the frozen picture was. -/
theorem observe_enter_elapsed (s : Trig) (now : Rat) (rm : Bool) (h : s.visible = false) :
    elapsed (observe s true now rm).1 now = 0 := by
  unfold observe elapsed
  have : (true = s.visible) = False := by simp [h]
  simp only [this, ite_false, ite_true]
  grind

/-- Leaving a visible state keeps the picture: the loop time freezes where it was.

$$\forall S, t, \mathit{now}, \mathit{rm}:\quad S.\mathit{visible} = \top \wedge S.\mathit{since} = \mathrm{some}\ t \Rightarrow \operatorname{observe}(S, \bot, \mathit{now}, \mathit{rm}).1.\mathit{frozen} = \mathit{now} - t$$

Cancelling the timers does not blank the bubble. -/
theorem observe_leave_frozen (s : Trig) (t now : Rat) (rm : Bool) (h : s.visible = true) (hs : s.since = some t) :
    (observe s false now rm).1.frozen = now - t := by
  unfold observe
  have : (false = s.visible) = False := by simp [h]
  simp only [this, ite_false, hs]
  rfl

/-- A cycle's picture at the start is the reset blink. $$V(0) = V_0$$ -/
theorem viewAt_zero : viewAt 0 = resetView := by decide +kernel

/-! ## The visual's scale -/

/-- The fee visual is drawn at 432 px wide and scaled to its column (JS 2511-2518, `--visual-scale`).

$$\mathrm{scale}(w) = \min\!\big(0.8,\ w/432\big)$$

with $w$ the parent's width in px. -/
def visualScale (w : Rat) : Rat := min (4 / 5) (w / 432)

#guard visualScale 300 == 300 / 432
#guard visualScale 345.6 == 4 / 5
#guard visualScale 1000 == 4 / 5

/-- The scale never exceeds 0.8. $$\forall w:\ \mathrm{scale}(w) \le 0.8$$ -/
theorem visualScale_le (w : Rat) : visualScale w ≤ 4 / 5 := by unfold visualScale; grind

/-- From 345.6 px up the scale is 0.8. $$w \ge 345.6 \Rightarrow \mathrm{scale}(w) = 0.8$$ The knee of the CSS `min(100%, 345.6px)`. -/
theorem visualScale_flat (w : Rat) (h : 3456 / 10 ≤ w) : visualScale w = 4 / 5 := by unfold visualScale; grind

/-- Below the knee the scale is proportional. $$\forall w \in \mathbb{Q}:\ w \le 345.6 \Rightarrow \mathrm{scale}(w) = w/432$$ The picture fills its column. -/
theorem visualScale_prop (w : Rat) (h : w ≤ 3456 / 10) : visualScale w = w / 432 := by unfold visualScale; grind

/-! ## The forced-layout variant (ledger n=22): passes in any frame

The variant only drops accesses from the `commission` callback (`Fw.Parts.Contract.commission`), so over the
`Fw.Parts.EngineScroll` flag model it never adds a style or layout pass, forced or total, whatever runs around it.
Not covered: the ResizeObserver delivery after layout, work units per pass, and the script cost of `matchMedia`. -/

section ForcedLayout

open Fw.Engine (FlagOp flagForced flagEnd flagTotal firstFlag flagForced_append flagEnd_append flagTotal_append
  flagTotal_remove_check)
open Fw.Parts.EngineScroll (Access Role forced total flags styleRole layoutRole forced_eq_flagForced)

/-- A dirty start never lowers the forced count and raises it by at most one.

$$\forall as \in \mathrm{FlagOp}^{*}:\ \operatorname{fF}(\bot, as) \le \operatorname{fF}(\top, as) \le \operatorname{fF}(\bot, as) + 1$$ -/
theorem flagForced_start : ∀ as : List FlagOp,
    flagForced false as ≤ flagForced true as ∧ flagForced true as ≤ flagForced false as + 1
  | [] => by simp [flagForced]
  | .check :: as => by simp [flagForced]; omega
  | .dirty :: as => by simp [flagForced]
  | .neutral :: as => by simpa [flagForced] using flagForced_start as

/-- A dirty start never lowers the total and raises it by at most one.

$$\forall as \in \mathrm{FlagOp}^{*}:\ \operatorname{fT}(\bot, as) \le \operatorname{fT}(\top, as) \le \operatorname{fT}(\bot, as) + 1$$ -/
theorem flagTotal_start : ∀ as : List FlagOp,
    flagTotal false as ≤ flagTotal true as ∧ flagTotal true as ≤ flagTotal false as + 1
  | [] => by decide
  | .check :: as => by simp [flagTotal, flagForced, flagEnd]; omega
  | .dirty :: as => by simp [flagTotal, flagForced, flagEnd]
  | .neutral :: as => by simpa [flagTotal, flagForced, flagEnd] using flagTotal_start as

/-- One more access in front never lowers the forced count.

$$\forall o,\ \forall d \in \mathbb{B},\ \forall as:\ \operatorname{fF}(d, as) \le \operatorname{fF}(d, o :: as)$$ -/
theorem flagForced_le_cons (o : FlagOp) (d : Bool) (as : List FlagOp) : flagForced d as ≤ flagForced d (o :: as) := by
  have h := flagForced_start as
  cases o <;> cases d <;> simp [flagForced] <;> omega

/-- One more access in front never lowers the total.

$$\forall o,\ \forall d \in \mathbb{B},\ \forall as:\ \operatorname{fT}(d, as) \le \operatorname{fT}(d, o :: as)$$ -/
theorem flagTotal_le_cons (o : FlagOp) (d : Bool) (as : List FlagOp) : flagTotal d as ≤ flagTotal d (o :: as) := by
  have h := flagTotal_start as
  cases o <;> cases d <;> simp [flagTotal, flagForced, flagEnd] at h ⊢ <;> omega

/-- **Dropping accesses never adds a pass.** For flag sequences $l_1$ a sublist of $l_2$ (same order, some entries
removed), forced and total passes of $l_1$ are at most those of $l_2$.

$$\forall l_1, l_2 \in \mathrm{FlagOp}^{*}:\ l_1 \sqsubseteq l_2 \Rightarrow \forall d \in \mathbb{B}:\ \operatorname{fF}(d, l_1) \le \operatorname{fF}(d, l_2) \land \operatorname{fT}(d, l_1) \le \operatorname{fT}(d, l_2)$$

Removing reads or writes from a frame, anywhere, can only remove passes. -/
theorem flag_sublist {l₁ l₂ : List FlagOp} (h : l₁.Sublist l₂) :
    ∀ d, flagForced d l₁ ≤ flagForced d l₂ ∧ flagTotal d l₁ ≤ flagTotal d l₂ := by
  induction h with
  | slnil => intro d; simp
  | cons o _ ih =>
    intro d
    exact ⟨Nat.le_trans (ih d).1 (flagForced_le_cons o d _), Nat.le_trans (ih d).2 (flagTotal_le_cons o d _)⟩
  | @cons_cons l₁ l₂ o _ ih =>
    intro d
    have e1 : ∀ l, flagForced d (o :: l) = flagForced d [o] + flagForced (flagEnd d [o]) l :=
      fun l => flagForced_append d [o] l
    have e2 : ∀ l, flagTotal d (o :: l) = flagForced d [o] + flagTotal (flagEnd d [o]) l :=
      fun l => flagTotal_append d [o] l
    rw [e1 l₁, e1 l₂, e2 l₁, e2 l₂]
    have := ih (flagEnd d [o])
    omega

/-- **Frame form.** If the variant's callback is a sublist of the original's, then in every frame (accesses $p$ before,
$q$ after, any start flag, any role assignment) its forced and total passes are at most the original's.

$$\forall \rho,\ \forall v, o \in \mathrm{Access}^{*}:\ v \sqsubseteq o \Rightarrow \forall d \in \mathbb{B},\ \forall p, q:\ \operatorname{forced}_\rho(d, p \mathbin{+\!\!+} v \mathbin{+\!\!+} q) \le \operatorname{forced}_\rho(d, p \mathbin{+\!\!+} o \mathbin{+\!\!+} q) \land \operatorname{total}_\rho(d, p \mathbin{+\!\!+} v \mathbin{+\!\!+} q) \le \operatorname{total}_\rho(d, p \mathbin{+\!\!+} o \mathbin{+\!\!+} q)$$

The bound holds in place, so it needs no per-part sum of passes. -/
theorem frame_sublist_le (ρ : Access → Role) {v o : List Access} (h : v.Sublist o) (d : Bool) (p q : List Access) :
    forced ρ d (p ++ v ++ q) ≤ forced ρ d (p ++ o ++ q) ∧ total ρ d (p ++ v ++ q) ≤ total ρ d (p ++ o ++ q) := by
  have hs : (p ++ v ++ q).Sublist (p ++ o ++ q) := ((List.Sublist.refl p).append h).append (List.Sublist.refl q)
  have := flag_sublist (hs.map fun a => (ρ a).toFlag) d
  simpa [forced_eq_flagForced, total, flags] using this

/-- The original callback in one frame: the contract row's accesses, where the line-box read happens only in the
compact band (`compactNow && ...lineBoxes(...)`, apps/site/src/parts/commission/driver.ts:119).

$$O(c) = \begin{cases} [\mathrm{RL}, \mathrm{RL}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WL}, \mathrm{RL}, \mathrm{WS}] & c \\ [\mathrm{RL}, \mathrm{RL}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WL}, \mathrm{WS}] & \lnot c \end{cases}$$ -/
def origFrame (compact : Bool) : List Access :=
  if compact then Fw.Parts.Contract.commission.listAccess else Fw.Parts.Contract.commission.listAccess.eraseIdx 7

/-- The two bands' original callbacks, as lists.

$$O(\top) = [\mathrm{RL}, \mathrm{RL}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WL}, \mathrm{RL}, \mathrm{WS}] \land O(\bot) = [\mathrm{RL}, \mathrm{RL}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WL}, \mathrm{WS}]$$ -/
theorem origFrame_eq :
    origFrame true = [.readLayout, .readLayout, .writeStyle, .writeStyle, .writeStyle, .writeStyle, .writeLayout,
      .readLayout, .writeStyle] ∧
    origFrame false = [.readLayout, .readLayout, .writeStyle, .writeStyle, .writeStyle, .writeStyle, .writeLayout,
      .writeStyle] := by
  decide

/-- Keep the entries whose index (counted from $i$) and value pass $f$.

$$\operatorname{pick}_f(i, [\,]) = [\,],\quad \operatorname{pick}_f(i, a :: as) = \begin{cases} a :: \operatorname{pick}_f(i+1, as) & f(i, a) \\ \operatorname{pick}_f(i+1, as) & \lnot f(i, a) \end{cases}$$ -/
def pick (f : Nat → Access → Bool) : Nat → List Access → List Access
  | _, [] => []
  | i, a :: as => if f i a then a :: pick f (i + 1) as else pick f (i + 1) as

/-- A pick is a sublist. $$\forall f,\ \forall i,\ \forall as:\ \operatorname{pick}_f(i, as) \sqsubseteq as$$ -/
theorem pick_sublist (f : Nat → Access → Bool) : ∀ (i : Nat) (as : List Access), (pick f i as).Sublist as
  | _, [] => List.Sublist.slnil
  | i, a :: as => by
    unfold pick
    split
    · exact (pick_sublist f (i + 1) as).cons_cons a
    · exact (pick_sublist f (i + 1) as).cons a

/-- The variant's callback in one frame. With `ro` the line count comes from a ResizeObserver, so the tail from index 7
(line-box read, title class write) leaves the callback; a write at index $i$ stays only when $k(i)$ (write-on-change
and the compact-band snap decide $k$). `mqGate` caches `matchMedia`, which is no access of the row.

$$V(c, ro, k) = \operatorname{pick}_f(0, O(c)),\quad f(i, a) = \lnot(ro \land 7 \le i) \land (\operatorname{isReadA}(a) \lor k(i))$$ -/
def variantFrame (compact ro : Bool) (keep : Nat → Bool) : List Access :=
  pick (fun i a => !(ro && decide (7 ≤ i)) && (a.isRead || keep i)) 0 (origFrame compact)

#guard variantFrame true true (fun _ => true) ==
  [.readLayout, .readLayout, .writeStyle, .writeStyle, .writeStyle, .writeStyle, .writeLayout]
#guard variantFrame true false (fun _ => true) == origFrame true
#guard variantFrame false false (fun i => i == 6) == [.readLayout, .readLayout, .writeLayout]
#guard variantFrame true true (fun _ => false) == [.readLayout, .readLayout]

/-- **The n=22 total-pass lemma.** For every band, observer choice and write mask, in every frame (any accesses $p$
before and $q$ after the callback, any start flag) and for every role assignment (so for style and for layout), the
variant forces no more passes, runs no more passes in total (forced plus frame end), and makes no more accesses than
the original.

$$\forall c, ro \in \mathbb{B},\ \forall k : \mathbb{N} \to \mathbb{B},\ \forall \rho,\ \forall d \in \mathbb{B},\ \forall p, q \in \mathrm{Access}^{*}:\ \operatorname{forced}_\rho(d, p \mathbin{+\!\!+} V(c, ro, k) \mathbin{+\!\!+} q) \le \operatorname{forced}_\rho(d, p \mathbin{+\!\!+} O(c) \mathbin{+\!\!+} q) \land \operatorname{total}_\rho(d, p \mathbin{+\!\!+} V(c, ro, k) \mathbin{+\!\!+} q) \le \operatorname{total}_\rho(d, p \mathbin{+\!\!+} O(c) \mathbin{+\!\!+} q) \land |V(c, ro, k)| \le |O(c)|$$

Passes of the scroll-list phase only: an observer delivery after layout is a separate phase this does not bound. -/
theorem variant_total_le (compact ro : Bool) (keep : Nat → Bool) (ρ : Access → Role) (d : Bool) (p q : List Access) :
    forced ρ d (p ++ variantFrame compact ro keep ++ q) ≤ forced ρ d (p ++ origFrame compact ++ q) ∧
      total ρ d (p ++ variantFrame compact ro keep ++ q) ≤ total ρ d (p ++ origFrame compact ++ q) ∧
      (variantFrame compact ro keep).length ≤ (origFrame compact).length := by
  have hs := pick_sublist (fun i a => !(ro && decide (7 ≤ i)) && (a.isRead || keep i)) 0 (origFrame compact)
  exact ⟨(frame_sublist_le ρ hs d p q).1, (frame_sublist_le ρ hs d p q).2, hs.length_le⟩

/-- Dropping a write right after the flag is dirty changes no total.

$$\forall d,\ \forall P, Q \in \mathrm{FlagOp}^{*}:\ \operatorname{fE}(d, P) \Rightarrow \operatorname{fT}(d, P \mathbin{+\!\!+} \mathrm{dirty} :: Q) = \operatorname{fT}(d, P \mathbin{+\!\!+} Q)$$ -/
theorem flagTotal_drop_dirty (d : Bool) (P Q : List FlagOp) (h : flagEnd d P = true) :
    flagTotal d (P ++ .dirty :: Q) = flagTotal d (P ++ Q) := by
  rw [flagTotal_append, flagTotal_append, h]
  simp [flagTotal, flagForced, flagEnd]

/-- Dropping a neutral access changes no total.

$$\forall d,\ \forall P, Q \in \mathrm{FlagOp}^{*}:\ \operatorname{fT}(d, P \mathbin{+\!\!+} \mathrm{neutral} :: Q) = \operatorname{fT}(d, P \mathbin{+\!\!+} Q)$$ -/
theorem flagTotal_drop_neutral (d : Bool) (P Q : List FlagOp) :
    flagTotal d (P ++ .neutral :: Q) = flagTotal d (P ++ Q) := by
  rw [flagTotal_append, flagTotal_append]
  simp [flagTotal, flagForced, flagEnd]

/-- The callback that stays with `ro` and every write kept.

$$W = [\mathrm{RL}, \mathrm{RL}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WS}, \mathrm{WL}],\quad O(\top) = W \mathbin{+\!\!+} [\mathrm{RL}, \mathrm{WS}],\quad O(\bot) = W \mathbin{+\!\!+} [\mathrm{WS}],\quad V(c, \top, \lambda\_.\,\top) = W$$ -/
theorem ro_shape :
    origFrame true = [.readLayout, .readLayout, .writeStyle, .writeStyle, .writeStyle, .writeStyle, .writeLayout] ++
      [.readLayout, .writeStyle] ∧
    origFrame false = [.readLayout, .readLayout, .writeStyle, .writeStyle, .writeStyle, .writeStyle, .writeLayout] ++
      [.writeStyle] ∧
    ∀ c, variantFrame c true (fun _ => true) =
      [.readLayout, .readLayout, .writeStyle, .writeStyle, .writeStyle, .writeStyle, .writeLayout] := by
  refine ⟨by decide, by decide, fun c => by cases c <;> decide⟩

/-- After the kept callback both stage flags are dirty, in either band and whatever came before.

$$\forall c, d \in \mathbb{B},\ \forall p \in \mathrm{Access}^{*}:\ \operatorname{fE}(d, \operatorname{flags}_{\rho_S}(p \mathbin{+\!\!+} V(c, \top, \lambda\_.\,\top))) = \top \land \operatorname{fE}(d, \operatorname{flags}_{\rho_L}(p \mathbin{+\!\!+} V(c, \top, \lambda\_.\,\top))) = \top$$ -/
theorem kept_end_dirty (c d : Bool) (p : List Access) :
    flagEnd d (flags styleRole (p ++ variantFrame c true (fun _ => true))) = true ∧
      flagEnd d (flags layoutRole (p ++ variantFrame c true (fun _ => true))) = true := by
  rw [(ro_shape).2.2 c, Fw.Parts.EngineScroll.flags_append, Fw.Parts.EngineScroll.flags_append, flagEnd_append,
    flagEnd_append]
  constructor
  · cases flagEnd d (flags styleRole p) <;> decide
  · cases flagEnd d (flags layoutRole p) <;> decide

/-- **What `ro` saves in the compact band.** With every write kept, taking the line count out of the callback removes
exactly one style pass in every frame, and one layout pass exactly when the next layout access after the callback is a
layout write; otherwise the forced layout only moves to the frame-end pass.

$$\forall d \in \mathbb{B},\ \forall p, q \in \mathrm{Access}^{*}:\ \operatorname{total}_{\rho_S}(d, p \mathbin{+\!\!+} O(\top) \mathbin{+\!\!+} q) = \operatorname{total}_{\rho_S}(d, p \mathbin{+\!\!+} V(\top, \top, \lambda\_.\,\top) \mathbin{+\!\!+} q) + 1 \land \operatorname{total}_{\rho_L}(d, p \mathbin{+\!\!+} O(\top) \mathbin{+\!\!+} q) = \operatorname{total}_{\rho_L}(d, p \mathbin{+\!\!+} V(\top, \top, \lambda\_.\,\top) \mathbin{+\!\!+} q) + [\operatorname{first}(\operatorname{flags}_{\rho_L}(q)) = \mathrm{dirty}]$$ -/
theorem ro_compact_saves (d : Bool) (p q : List Access) :
    total styleRole d (p ++ origFrame true ++ q) =
        total styleRole d (p ++ variantFrame true true (fun _ => true) ++ q) + 1 ∧
      total layoutRole d (p ++ origFrame true ++ q) =
        total layoutRole d (p ++ variantFrame true true (fun _ => true) ++ q) +
          (if firstFlag (flags layoutRole q) = some .dirty then 1 else 0) := by
  obtain ⟨hS, hL⟩ := kept_end_dirty true d p
  have e : p ++ origFrame true ++ q =
      (p ++ variantFrame true true (fun _ => true)) ++ .readLayout :: .writeStyle :: q := by
    rw [(ro_shape).1, (ro_shape).2.2 true]; simp
  rw [e]
  constructor
  · rw [Fw.Parts.EngineScroll.total_remove_read styleRole d _ _ .readLayout rfl]
    have hf : firstFlag (flags styleRole (.writeStyle :: q)) = some .dirty := rfl
    simp only [hS, hf, and_self, ↓reduceIte]
    congr 1
    rw [total, total, Fw.Parts.EngineScroll.flags_append _ _ (.writeStyle :: q),
      Fw.Parts.EngineScroll.flags_append _ _ q]
    exact flagTotal_drop_dirty d _ _ hS
  · rw [Fw.Parts.EngineScroll.total_remove_read layoutRole d _ _ .readLayout rfl]
    have hf : firstFlag (flags layoutRole (.writeStyle :: q)) = firstFlag (flags layoutRole q) := rfl
    rw [hf]
    simp only [hL, true_and]
    congr 1
    rw [total, total, Fw.Parts.EngineScroll.flags_append _ _ (.writeStyle :: q),
      Fw.Parts.EngineScroll.flags_append _ _ q]
    exact flagTotal_drop_neutral d _ _

/-- **`ro` saves nothing in the desktop band.** There the original reads no line boxes, so with every write kept the
variant's style and layout totals equal the original's in every frame.

$$\forall d \in \mathbb{B},\ \forall p, q \in \mathrm{Access}^{*}:\ \operatorname{total}_{\rho_S}(d, p \mathbin{+\!\!+} O(\bot) \mathbin{+\!\!+} q) = \operatorname{total}_{\rho_S}(d, p \mathbin{+\!\!+} V(\bot, \top, \lambda\_.\,\top) \mathbin{+\!\!+} q) \land \operatorname{total}_{\rho_L}(d, p \mathbin{+\!\!+} O(\bot) \mathbin{+\!\!+} q) = \operatorname{total}_{\rho_L}(d, p \mathbin{+\!\!+} V(\bot, \top, \lambda\_.\,\top) \mathbin{+\!\!+} q)$$ -/
theorem ro_desktop_eq (d : Bool) (p q : List Access) :
    total styleRole d (p ++ origFrame false ++ q) =
        total styleRole d (p ++ variantFrame false true (fun _ => true) ++ q) ∧
      total layoutRole d (p ++ origFrame false ++ q) =
        total layoutRole d (p ++ variantFrame false true (fun _ => true) ++ q) := by
  obtain ⟨hS, -⟩ := kept_end_dirty false d p
  have e : p ++ origFrame false ++ q =
      (p ++ variantFrame false true (fun _ => true)) ++ .writeStyle :: q := by
    rw [(ro_shape).2.1, (ro_shape).2.2 false]; simp
  rw [e]
  constructor
  · rw [total, total, Fw.Parts.EngineScroll.flags_append _ _ (.writeStyle :: q),
      Fw.Parts.EngineScroll.flags_append _ _ q]
    exact flagTotal_drop_dirty d _ _ hS
  · rw [total, total, Fw.Parts.EngineScroll.flags_append _ _ (.writeStyle :: q),
      Fw.Parts.EngineScroll.flags_append _ _ q]
    exact flagTotal_drop_neutral d _ _

#guard total styleRole false (origFrame true) == 2 && total styleRole false (variantFrame true true (fun _ => true)) == 1
#guard total layoutRole false (origFrame true) == 1 && total layoutRole false (variantFrame true true (fun _ => true)) == 1
#guard forced layoutRole false (origFrame true) == 1 && forced layoutRole false (variantFrame true true (fun _ => true)) == 0

end ForcedLayout

end Fw.Parts.CommissionTyping
