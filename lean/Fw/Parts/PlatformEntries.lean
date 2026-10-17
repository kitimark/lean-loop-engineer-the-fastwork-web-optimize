import Fw.Parts.PlatformSweep
/-!
# platform.entries: entry animations, count-up and the search typing of the stage visuals (P5 port, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`: the keyframes and `animation:` shorthands
  `start-selling-cred-card-in` (6516-6522, 7517), `profile-phone-in` (7512-7525), the six `secure-network-*-in` (7045-7101,
  7104-7170), `invoice-card-in` / `invoice-i-row-in` / `orders-card-in` (8580-8610, 8700-8720, 8846-8855),
  `agents-ask-in` / `-out` (9074-9115, 9129-9145). Every one is a two-keyframe `from -> to` run with `both` fill and
  `cubic-bezier(0.16, 1, 0.3, 1)`.
* `.../nodes/2.DyWL8TcE.js` 11996-12040: the profile count-up (180 ms delay, 1080 ms, ease-out cubic, `Math.round`);
  11659-11700 (`b(() => ...)`): the search typing schedule (700 ms lead, 32 ms per typed char, 280 ms first reveal and
  700 ms swap, 3000 ms hold, 18 ms per erased char).

All values `Rat`. No `Float`. This is the exact "original" an optimized version is compared against.
-/
namespace Fw.Parts.PlatformEntries
open Fw.Parts.PlatformSweep (frac frac_mem)

/-! ## The easing curve -/

/-- A CSS cubic-bezier with control points $(x_1, y_1), (x_2, y_2)$.

$$b = ((x_1, y_1), (x_2, y_2)) \in \mathbb{Q}^4$$

$$b = ((x_1, y_1), (x_2, y_2)) \in \mathbb{Q}^4$$

$$b = ((x_1, y_1), (x_2, y_2)) \in \mathbb{Q}^4$$ -/
structure Bez where
  x1 : Rat
  y1 : Rat
  x2 : Rat
  y2 : Rat
deriving Repr

/-- The curve every entry uses. $$\mathrm{cubic\text{-}bezier}(0.16,\ 1,\ 0.3,\ 1)$$ -/
def spring : Bez := ⟨4 / 25, 1, 3 / 10, 1⟩

/-- The $x$ coordinate at curve parameter $u$.

$$B_x(u) = 3(1-u)^2 u\,x_1 + 3(1-u)u^2\,x_2 + u^3$$ -/
def bx (b : Bez) (u : Rat) : Rat :=
  3 * (1 - u) * (1 - u) * u * b.x1 + 3 * (1 - u) * u * u * b.x2 + u * u * u

/-- The $y$ coordinate at curve parameter $u$.

$$B_y(u) = 3(1-u)^2 u\,y_1 + 3(1-u)u^2\,y_2 + u^3$$ -/
def by' (b : Bez) (u : Rat) : Rat :=
  3 * (1 - u) * (1 - u) * u * b.y1 + 3 * (1 - u) * u * u * b.y2 + u * u * u

/-- Bisection on $B_x(u) = x$, `n` halvings of $[lo, hi]$.

$$\begin{aligned} \forall b, x, lo, hi:\quad &\operatorname{bis}_{b,x}(0, (lo, hi)) = (lo, hi), \\ \forall n \in \mathbb N:\quad &\operatorname{bis}_{b,x}(n+1, (lo, hi)) = \begin{cases} \operatorname{bis}_{b,x}(n, (m, hi)) & B_x(m) < x \\ \operatorname{bis}_{b,x}(n, (lo, m)) & B_x(m) \ge x \end{cases},\quad m = \tfrac{lo + hi}{2} \end{aligned}$$ -/
def bis (b : Bez) (x : Rat) : Nat → Rat × Rat → Rat × Rat
  | 0, p => p
  | n + 1, (lo, hi) => if bx b ((lo + hi) / 2) < x then bis b x n ((lo + hi) / 2, hi) else bis b x n (lo, (lo + hi) / 2)

/-- Number of halvings (resolution $2^{-24}$). $$N = 24$$ -/
def steps : Nat := 24

/-- The parameter whose $x$ is closest to $x$ after $N$ halvings, mid-point.

$$\forall b, x:\quad u_b(x) = \tfrac{lo_N + hi_N}{2},\quad (lo_N, hi_N) = \operatorname{bis}_{b,x}(N, (0, 1)),\ N = 24$$ -/
def solve (b : Bez) (x : Rat) : Rat :=
  let p := bis b x steps (0, 1)
  (p.1 + p.2) / 2

/-- The eased progress for a linear progress $x$.

$$\operatorname{ease}(x) = \begin{cases} 0 & x \le 0 \\ 1 & x \ge 1 \\ B_y(u(x)) & \text{otherwise} \end{cases}$$ -/
def ease (b : Bez) (x : Rat) : Rat := if x ≤ 0 then 0 else if 1 ≤ x then 1 else by' b (solve b x)

/-- The bisection keeps its interval inside $[0, 1]$ and ordered.

$$0 \le lo \le hi \le 1 \Rightarrow 0 \le lo_n \le hi_n \le 1$$ -/
theorem bis_inv (b : Bez) (x : Rat) (n : Nat) :
    ∀ lo hi : Rat, 0 ≤ lo → lo ≤ hi → hi ≤ 1 →
      0 ≤ (bis b x n (lo, hi)).1 ∧ (bis b x n (lo, hi)).1 ≤ (bis b x n (lo, hi)).2 ∧ (bis b x n (lo, hi)).2 ≤ 1 := by
  induction n with
  | zero => intro lo hi h0 h1 h2; simp [bis]; grind
  | succ n ih =>
    intro lo hi h0 h1 h2
    simp only [bis]
    split
    · exact ih _ _ (by grind) (by grind) h2
    · exact ih _ _ h0 (by grind) (by grind)

/-- The solved parameter lies in $[0, 1]$. $$0 \le u(x) \le 1$$ -/
theorem solve_mem (b : Bez) (x : Rat) : 0 ≤ solve b x ∧ solve b x ≤ 1 := by
  have := bis_inv b x steps 0 1 (by grind) (by grind) (by grind)
  unfold solve
  grind

/-- For the spring curve ($y_1 = y_2 = 1$) the $y$ coordinate is $1 - (1-u)^3$.

$$\forall u \in \mathbb{Q}:\quad B_y^{\mathrm{spring}}(u) = 1 - (1 - u)^3$$ -/
theorem spring_by (u : Rat) : by' spring u = 1 - (1 - u) * (1 - u) * (1 - u) := by
  unfold by' spring; grind

/-- The spring ease stays in $[0, 1]$. $$\forall x \in \mathbb{Q}:\ 0 \le \operatorname{ease}_{\mathrm{spring}}(x) \le 1$$ Entries never overshoot. -/
theorem ease_mem (x : Rat) : 0 ≤ ease spring x ∧ ease spring x ≤ 1 := by
  unfold ease
  split
  · grind
  split
  · grind
  · have hu := solve_mem spring x
    rw [spring_by]
    generalize solve spring x = u at *
    have h0 : 0 ≤ 1 - u := by grind
    have h1 : 1 - u ≤ 1 := by grind
    have h2 : (1 - u) * (1 - u) ≤ 1 := by
      have := Rat.mul_le_mul_of_nonneg_left h1 h0
      grind
    have h3 : 0 ≤ (1 - u) * (1 - u) := Rat.mul_nonneg h0 h0
    have h4 : (1 - u) * (1 - u) * (1 - u) ≤ 1 := by
      have := Rat.mul_le_mul_of_nonneg_right h2 h0
      grind
    have h5 : 0 ≤ (1 - u) * (1 - u) * (1 - u) := Rat.mul_nonneg h3 h0
    grind

/-- The spring ease starts at 0 and ends at 1. $$\operatorname{ease}_{\mathrm{spring}}(0) = 0 \land \operatorname{ease}_{\mathrm{spring}}(1) = 1$$ -/
theorem ease_ends : ease spring 0 = 0 ∧ ease spring 1 = 1 := by
  constructor <;> decide +kernel

/-- A quotient with a non-positive numerator is non-positive. $$a \le 0,\ d > 0 \Rightarrow a/d \le 0$$ -/
theorem div_nonpos' (a d : Rat) (hd : 0 < d) (h : a ≤ 0) : a / d ≤ 0 := by
  by_cases hc : a / d ≤ 0
  · exact hc
  · have hq : 0 < a / d := by grind
    have := Rat.mul_pos hq hd
    have e : a / d * d = a := Rat.div_mul_cancel (by grind)
    grind

/-- A quotient of a number at least the divisor is at least 1. $$d > 0,\ d \le a \Rightarrow 1 \le a/d$$ -/
theorem one_le_div' (a d : Rat) (hd : 0 < d) (h : d ≤ a) : 1 ≤ a / d := by
  by_cases hc : 1 ≤ a / d
  · exact hc
  · have e : a / d * d = a := Rat.div_mul_cancel (by grind)
    have h2 : 0 < (1 - a / d) * d := Rat.mul_pos (by grind) hd
    grind

/-! ## Entries -/

/-- One animated property: from-value, to-value. $$(k, a, b)$$ `key` names `opacity`, `translateX`, `translateY`, `scale`, `scaleX` or `blur` (px). -/
structure Tr where
  key : String
  a : Rat
  b : Rat
deriving Repr

/-- One entry animation: keyframe name, duration and delay in ms, the properties.

$$e = (\mathit{name}, D, d, \mathit{props})$$ -/
structure Entry where
  name : String
  dur : Rat
  delay : Rat
  trs : List Tr
deriving Repr

/-- Fade + lift + blur used by the credibility cards and the profile phone. $$\text{opacity } 0\to1,\ \text{translateY } 18\to0,\ \text{scale } 0.96\to1,\ \text{blur } 8\to0$$ -/
def liftBlur : List Tr :=
  [⟨"opacity", 0, 1⟩, ⟨"translateY", 18, 0⟩, ⟨"scale", 24 / 25, 1⟩, ⟨"blur", 8, 0⟩]

/-- Credibility card $i$ (delay $70 i$ ms, `--cred-enter-delay`). $$\forall i \in \mathbb N:\quad \operatorname{credCard}(i) = (\texttt{cred-card-in}, 420, 70i, \mathrm{liftBlur})$$ -/
def credCard (i : Nat) : Entry := ⟨"cred-card-in", 420, 70 * i, liftBlur⟩

/-- Profile phone. $$\mathrm{profilePhone} = (\texttt{profile-phone-in}, 620, 0, \mathrm{liftBlur})$$ -/
def profilePhone : Entry := ⟨"profile-phone-in", 620, 0, liftBlur⟩

/-- Secure-network rings. $$\mathrm{rings} = (\texttt{secure-network-rings-in}, 480, 0, [(\texttt{opacity}, 0, 1),\ (\texttt{scale}, 1.04, 1)])$$ -/
def rings : Entry := ⟨"secure-network-rings-in", 480, 0, [⟨"opacity", 0, 1⟩, ⟨"scale", 26 / 25, 1⟩]⟩

/-- Left face. $$\mathrm{faceLeft} = (\texttt{secure-network-face-left-in}, 320, 0, [(\texttt{opacity}, 0, 1),\ (\texttt{translateX}, -8, 0)])$$ -/
def faceLeft : Entry := ⟨"secure-network-face-left-in", 320, 0, [⟨"opacity", 0, 1⟩, ⟨"translateX", -8, 0⟩]⟩

/-- Right face. $$\mathrm{faceRight} = (\texttt{secure-network-face-right-in}, 320, 0, [(\texttt{opacity}, 0, 1),\ (\texttt{translateX}, 8, 0)])$$ -/
def faceRight : Entry := ⟨"secure-network-face-right-in", 320, 0, [⟨"opacity", 0, 1⟩, ⟨"translateX", 8, 0⟩]⟩

/-- Dash. $$\mathrm{dash} = (\texttt{secure-network-dash-in}, 260, 60, [(\texttt{opacity}, 0, 1),\ (\texttt{scaleX}, 0, 1)])$$ -/
def dash : Entry := ⟨"secure-network-dash-in", 260, 60, [⟨"opacity", 0, 1⟩, ⟨"scaleX", 0, 1⟩]⟩

/-- Shield. $$\mathrm{shield} = (\texttt{secure-network-shield-in}, 420, 180, [(\texttt{opacity}, 0, 1),\ (\texttt{scale}, 0.88, 1)])$$ -/
def shield : Entry := ⟨"secure-network-shield-in", 420, 180, [⟨"opacity", 0, 1⟩, ⟨"scale", 22 / 25, 1⟩]⟩

/-- Logo mark. $$\mathrm{logo} = (\texttt{secure-network-logo-in}, 280, 680, [(\texttt{opacity}, 0, 1),\ (\texttt{scale}, 0.7, 1)])$$ -/
def logo : Entry := ⟨"secure-network-logo-in", 280, 680, [⟨"opacity", 0, 1⟩, ⟨"scale", 7 / 10, 1⟩]⟩

/-- Delay of flag number $k$ (1-based child index): 600, 560, 520, 520, 560, 600 ms; every other $k$
(including $k = 0$) gets 600.

$$\forall k \in \mathbb N:\quad d(k) = \begin{cases} 560 & k \in \{2, 5\} \\ 520 & k \in \{3, 4\} \\ 600 & k \notin \{2, 3, 4, 5\} \ (k = 0,\ k = 1 \text{ or } k \ge 6) \end{cases}$$ -/
def flagDelay : Nat → Rat
  | 1 => 600 | 2 => 560 | 3 => 520 | 4 => 520 | 5 => 560 | _ => 600

/-- Flag $k$. $$\forall k \in \mathbb N:\quad \operatorname{flag}(k) = (\texttt{secure-network-flag-in}, 280, \operatorname{flagDelay}(k), [(\texttt{opacity}, 0, 1),\ (\texttt{scale}, 0.82, 1)])$$ -/
def flag (k : Nat) : Entry := ⟨"secure-network-flag-in", 280, flagDelay k, [⟨"opacity", 0, 1⟩, ⟨"scale", 41 / 50, 1⟩]⟩

/-- Invoice card (the `invoice-i` variant of the last row). $$\mathrm{invoiceCard} = (\texttt{invoice-card-in}, 560, 620, [(\texttt{opacity}, 0, 1),\ (\texttt{translateY}, 22, 0),\ (\texttt{scale}, 0.94, 1)])$$ -/
def invoiceCard : Entry := ⟨"invoice-card-in", 560, 620, [⟨"opacity", 0, 1⟩, ⟨"translateY", 22, 0⟩, ⟨"scale", 47 / 50, 1⟩]⟩

/-- Orders row $i$ (delay $140 i$ ms, `--orders-card-delay`). $$\forall i \in \mathbb N:\quad \operatorname{orderRow}(i) = (\texttt{invoice-i-row-in}, 620, 140i, [(\texttt{opacity}, 0, 1),\ (\texttt{translateX}, 20, 0)])$$ -/
def orderRow (i : Nat) : Entry := ⟨"invoice-i-row-in", 620, 140 * i, [⟨"opacity", 0, 1⟩, ⟨"translateX", 20, 0⟩]⟩

/-- Search title, field and service $i$ entering (delay $140 i$ ms). $$\forall i \in \mathbb N:\quad \operatorname{askIn}(i) = (\texttt{agents-ask-in}, 560, 140i, [(\texttt{opacity}, 0, 1),\ (\texttt{translateY}, 10, 0)])$$ -/
def askIn (i : Nat) : Entry := ⟨"agents-ask-in", 560, 140 * i, [⟨"opacity", 0, 1⟩, ⟨"translateY", 10, 0⟩]⟩

/-- Search service $i$ leaving. $$\forall i \in \mathbb N:\quad \operatorname{askOut}(i) = (\texttt{agents-ask-out}, 560, 140i, [(\texttt{opacity}, 1, 0),\ (\texttt{translateY}, 0, 10)])$$ -/
def askOut (i : Nat) : Entry := ⟨"agents-ask-out", 560, 140 * i, [⟨"opacity", 1, 0⟩, ⟨"translateY", 0, 10⟩]⟩

/-- Linear progress of an entry $t$ ms after its animation was started (`both` fill).

$$x(t) = \frac{t - d}{D}$$ -/
def lin (e : Entry) (t : Rat) : Rat := (t - e.delay) / e.dur

/-- Eased progress on the spring curve. $$\forall e, \forall t \in \mathbb{Q}:\quad p_e(t) = \operatorname{ease}_{\mathrm{spring}}(x_e(t)) = \operatorname{ease}_{\mathrm{spring}}\!\left(\tfrac{t - d}{D}\right)$$ -/
def progress (e : Entry) (t : Rat) : Rat := ease spring (lin e t)

/-- A property's value $t$ ms in. $$v(t) = a + (b - a)\,p(t)$$ -/
def value (e : Entry) (tr : Tr) (t : Rat) : Rat := tr.a + (tr.b - tr.a) * progress e t

/-- Before the delay the entry sits on its first keyframe (fill `both`). $$\forall e = (\mathit{name}, D, d, \mathit{props}),\ \forall t \in \mathbb{Q}:\quad D > 0 \land t \le d \Rightarrow p_e(t) = 0$$ -/
theorem progress_before (e : Entry) (t : Rat) (hD : 0 < e.dur) (h : t ≤ e.delay) : progress e t = 0 := by
  unfold progress lin ease
  have : (t - e.delay) / e.dur ≤ 0 := div_nonpos' _ _ hD (by grind)
  simp [this]

/-- After delay plus duration it sits on its last keyframe. $$\forall e = (\mathit{name}, D, d, \mathit{props}),\ \forall t \in \mathbb{Q}:\quad D > 0 \land t \ge d + D \Rightarrow p_e(t) = 1$$ -/
theorem progress_after (e : Entry) (t : Rat) (hD : 0 < e.dur) (h : e.delay + e.dur ≤ t) : progress e t = 1 := by
  unfold progress lin ease
  have h1 : 1 ≤ (t - e.delay) / e.dur := one_le_div' _ _ hD (by grind)
  have h2 : ¬ (t - e.delay) / e.dur ≤ 0 := by grind
  simp [h1, h2]

/-- The progress stays in $[0, 1]$. $$0 \le p(t) \le 1$$ -/
theorem progress_mem (e : Entry) (t : Rat) : 0 ≤ progress e t ∧ progress e t ≤ 1 := ease_mem _

/-- A property stays between its two keyframe values. $$\min(a, b) \le v(t) \le \max(a, b)$$ -/
theorem value_between (e : Entry) (tr : Tr) (t : Rat) :
    min tr.a tr.b ≤ value e tr t ∧ value e tr t ≤ max tr.a tr.b := by
  have hm := progress_mem e t
  unfold value
  generalize progress e t = k at *
  by_cases hs : tr.a ≤ tr.b
  · have := Rat.mul_nonneg (show 0 ≤ tr.b - tr.a by grind) hm.1
    have := Rat.mul_le_mul_of_nonneg_left hm.2 (show 0 ≤ tr.b - tr.a by grind)
    grind
  · have := Rat.mul_nonneg (show 0 ≤ tr.a - tr.b by grind) hm.1
    have := Rat.mul_le_mul_of_nonneg_left hm.2 (show 0 ≤ tr.a - tr.b by grind)
    grind

/-- The entries only run when not static (reduced motion shows the end state at once).

$$\operatorname{play}(\mathit{visible}, \mathit{reduce}) = \mathit{visible} \land \lnot\,\mathit{reduce}$$ -/
def play (visible reduce : Bool) : Bool := visible && !reduce

/-! ## Count-up of the profile stats -/

/-- Delay before the count starts (ms). $$d_c = 180$$ -/
def countDelay : Rat := 180

/-- Length of the count (ms). $$D_c = 1080$$ -/
def countDur : Rat := 1080

/-- Ease-out cubic of the count. $$\operatorname{eo}(x) = 1 - (1 - x)^3$$ -/
def easeOut (x : Rat) : Rat := 1 - (1 - x) * (1 - x) * (1 - x)

/-- JS `Math.round`. $$\operatorname{round}(x) = \lfloor x + \tfrac12 \rfloor$$ Half rounds up. -/
def jsRound (x : Rat) : Int := (x + 1 / 2).floor

/-- The shown number for target $n$, $t$ ms after the stage became visible.

$$c(n, t) = \begin{cases} 0 & t < 180 \\ \operatorname{round}\big(n \cdot \operatorname{eo}(\min(1, (t - 180)/1080))\big) & \text{otherwise} \end{cases}$$ -/
def countAt (n : Nat) (t : Rat) : Int :=
  if t < countDelay then 0 else jsRound ((n : Rat) * easeOut (min 1 ((t - countDelay) / countDur)))

#guard countAt 240 0 == 0
#guard countAt 240 1260 == 240
#guard countAt 48 9999 == 48
#guard countAt 5 (180 + 540) == 4

/-- After the count the target is shown exactly. $$t \ge 1260 \Rightarrow c(n, t) = n$$ -/
theorem count_done (n : Nat) (t : Rat) (h : 1260 ≤ t) : countAt n t = n := by
  unfold countAt
  have h1 : ¬ t < countDelay := by unfold countDelay; grind
  have h2 : min 1 ((t - countDelay) / countDur) = 1 := by
    have : 1 ≤ (t - countDelay) / countDur := by
      apply one_le_div' _ _ (by unfold countDur; decide)
      unfold countDelay countDur; grind
    grind
  simp only [h1, h2, ite_false]
  unfold easeOut jsRound
  have e1 : (n : Rat) * (1 - (1 - 1) * (1 - 1) * (1 - 1)) + 1 / 2 = 1 / 2 + ((n : Int) : Rat) := by push_cast; grind
  rw [e1, Rat.floor_add_intCast]
  have : (1/2 : Rat).floor = 0 := by decide +kernel
  grind

/-! ## Search typing -/

/-- Delay from becoming visible to the first typed character (ms). $$700$$ -/
def askLead : Rat := 700
/-- Ms per typed character. $$32$$ -/
def typeStep : Rat := 32
/-- Ms per erased character. $$18$$ -/
def eraseStep : Rat := 18
/-- Ms the finished query is held. $$3000$$ -/
def holdMs : Rat := 3000
/-- First reveal wait (ms): the results appear 280 ms after the first query is typed. $$280$$ -/
def firstReveal : Rat := 280
/-- Swap wait (ms) of every later topic (the old list leaves for this long). $$700$$ -/
def swapMs : Rat := 700

/-- Duration of one topic with a query of $L$ characters. $$D(L, r) = 32L + r + 3000 + 18L$$ -/
def topicDur (L : Nat) (reveal : Rat) : Rat := typeStep * L + reveal + holdMs + eraseStep * L

/-- Result of the view: shown query length, query topic, topic of the visible list, list leaving, results visible, caret visible.

$$v = (\ell, i, s, a, r, c) \in \mathbb{N}^3 \times \mathbb{B}^3$$

$$v = (\ell, i, s, a, r, c) \in \mathbb{N}^3 \times \mathbb{B}^3$$

$$v = (\ell, i, s, a, r, c) \in \mathbb{N}^3 \times \mathbb{B}^3$$ -/
structure View where
  len : Nat
  topic : Nat
  shown : Nat
  leaving : Bool
  results : Bool
  caret : Bool
deriving Repr, DecidableEq

/-- Floor to a natural number. $$\lfloor x \rfloor_{\mathbb N} = \max(0, \lfloor x \rfloor)$$ -/
def fl (x : Rat) : Nat := x.floor.toNat

/-- The query length $\tau$ ms into a topic of length $L$ whose reveal wait is $r$ ($\lfloor\cdot\rfloor_{\mathbb N}$ is
`fl`, $\dot-$ truncated subtraction).

$$\forall L \in \mathbb N,\ \forall r, \tau \in \mathbb{Q}:\quad \ell_{L,r}(\tau) = \begin{cases} \min(L,\ \lfloor \tau/32 \rfloor_{\mathbb N} + 1) & \tau < 32L \\ L & 32L \le \tau < 32L + r + 3000 \\ L \mathbin{\dot-} \big(\lfloor (\tau - (32L + r + 3000))/18 \rfloor_{\mathbb N} + 1\big) & \tau \ge 32L + r + 3000 \end{cases}$$ -/
def lenAt (L : Nat) (reveal τ : Rat) : Nat :=
  if τ < typeStep * L then min L (fl (τ / typeStep) + 1)
  else if τ < typeStep * L + reveal + holdMs then L
  else L - (fl ((τ - (typeStep * L + reveal + holdMs)) / eraseStep) + 1)

/-- One topic's view. `prev` is the topic whose list was shown before; `first` picks the 280 ms reveal, else the
700 ms swap.

$$\begin{aligned} \forall i, p, L \in \mathbb N,\ \forall f \in \mathbb B,\ \forall \tau \in \mathbb{Q}:\quad \operatorname{topicView}(i, p, L, f, \tau) = \big(&\ell_{L,r}(\tau),\ i,\ (32L \le \tau\ ?\ i : p),\ \lnot f \land 32L \le \tau < 32L + 700, \\ &\lnot f \lor 32L + 280 \le \tau,\ \top\big),\quad r = (f\ ?\ 280 : 700) \end{aligned}$$ -/
def topicView (idx prev L : Nat) (first : Bool) (τ : Rat) : View :=
  let reveal := if first then firstReveal else swapMs
  let typed := typeStep * L
  { len := lenAt L reveal τ, topic := idx,
    shown := if typed ≤ τ then idx else prev,
    leaving := !first && typed ≤ τ && τ < typed + swapMs,
    results := !first || typed + firstReveal ≤ τ,
    caret := true }

/-- Walk the topic list: the first entry whose duration holds $r$, with $r$ made relative to that entry.

$$\forall r \in \mathbb{Q}:\quad \operatorname{locate}([\,], r) = \bot,\qquad \operatorname{locate}((i, L) :: R, r) = \begin{cases} (i, L, r) & r < 50L + 3700 \\ \operatorname{locate}(R,\ r - (50L + 3700)) & r \ge 50L + 3700 \end{cases}$$ -/
def locate : List (Nat × Nat) → Rat → Option (Nat × Nat × Rat)
  | [], _ => none
  | (i, L) :: rest, r => if r < topicDur L swapMs then some (i, L, r) else locate rest (r - topicDur L swapMs)

/-- Cycle length: all topics except the first run in turn, then the first again with the swap wait.

$$P = \sum_k (50 L_k + 3700)$$ -/
def cycleLen (xs : List (Nat × Nat)) : Rat := (xs.map fun p => topicDur p.2 swapMs).sum

/-- Wrap $r$ into $[0, P)$. $$\operatorname{wrap}(r) = r - P \lfloor r / P \rfloor$$ -/
def wrap (P r : Rat) : Rat := r - P * (r / P).floor

/-- The rotation after the first topic: topics $1, \dots, n-1$, then $0$ again, each with its query length.

$$\operatorname{rot}([\,]) = [\,],\qquad \forall n \ge 1:\ \operatorname{rot}([L_0, L_1, \dots, L_{n-1}]) = [\,(k, L_k) \mid k = 1, \dots, n-1\,] \mathbin{+\!\!+} [(0, L_0)]$$ -/
def rotation (lens : List Nat) : List (Nat × Nat) :=
  match lens with
  | [] => []
  | L0 :: rest => (rest.zipIdx 1).map (fun p => (p.2, p.1)) ++ [(0, L0)]

/-- The repeating part, $r$ ms after the first topic ended: wrap into the rotation, then locate the topic.
The list shown before topic $i$ is the one of the previous topic in the rotation ($n - 1$ before topic 0).

$$\begin{aligned} \forall \mathit{lens}, \forall r \in \mathbb{Q}:\quad \operatorname{cyc}_{\mathit{lens}}(r) = {} &\begin{cases} \operatorname{topicView}(i,\ (i = 0\ ?\ n \mathbin{\dot-} 1 : i - 1),\ L,\ \bot,\ \tau) & \operatorname{locate}(\operatorname{rot}(\mathit{lens}), \operatorname{wrap}_P(r)) = (i, L, \tau) \\ (0, 0, 0, \bot, \bot, \bot) & \operatorname{locate}(\operatorname{rot}(\mathit{lens}), \operatorname{wrap}_P(r)) = \bot \end{cases} \\ \text{with } n = {} &|\mathit{lens}|,\ P = \operatorname{cycleLen}(\operatorname{rot}(\mathit{lens})) \end{aligned}$$ -/
def cycView (lens : List Nat) (r : Rat) : View :=
  match locate (rotation lens) (wrap (cycleLen (rotation lens)) r) with
  | some (i, L, τ) => topicView i (if i = 0 then (lens.length - 1) else i - 1) L false τ
  | none => ⟨0, 0, 0, false, false, false⟩

/-- The view at time $t$ after the stage became visible. `lens` are the query lengths in topic order.
Before $700$ ms: empty. Then topic 0 once with the 280 ms reveal; then the rotation $1, 2, \dots, n-1, 0$ with the
700 ms swap, repeating.

$$\begin{aligned} \forall t \in \mathbb{Q}:\quad &\operatorname{ask}_{\mathit{lens}}(t) = (0, 0, 0, \bot, \bot, \bot) \quad \text{if } t < 700 \lor \mathit{lens} = [\,], \\ \text{else, for } \mathit{lens} = L_0 :: R:\quad &\operatorname{ask}_{\mathit{lens}}(t) = \begin{cases} \operatorname{topicView}(0, 0, L_0, \top, t - 700) & t - 700 < D_0 \\ \operatorname{cyc}_{\mathit{lens}}(t - 700 - D_0) & t - 700 \ge D_0 \end{cases},\quad D_0 = 50L_0 + 3280 \end{aligned}$$ -/
def askView (lens : List Nat) (t : Rat) : View :=
  if t < askLead then ⟨0, 0, 0, false, false, false⟩
  else
    match lens with
    | [] => ⟨0, 0, 0, false, false, false⟩
    | L0 :: rest =>
      let τ0 := t - askLead
      if τ0 < topicDur L0 firstReveal then topicView 0 0 L0 true τ0
      else cycView (L0 :: rest) (τ0 - topicDur L0 firstReveal)

/-- Wrapping by a whole cycle changes nothing. $$P > 0 \Rightarrow \operatorname{wrap}(r + P) = \operatorname{wrap}(r)$$ -/
theorem wrap_periodic (P r : Rat) (hP : 0 < P) : wrap P (r + P) = wrap P r := by
  unfold wrap
  have h : (r + P) / P = r / P + 1 := by
    have e := Rat.mul_inv_cancel P (by grind)
    rw [Rat.div_def, Rat.div_def]
    grind
  rw [h, Rat.floor_add_one]
  push_cast
  grind

/-- The repeating part is periodic in the rotation length.

$$P = \sum_k (50L_k + 3700) > 0 \Rightarrow \operatorname{cyc}(r + P) = \operatorname{cyc}(r)$$ -/
theorem cycView_periodic (lens : List Nat) (r : Rat) (hP : 0 < cycleLen (rotation lens)) :
    cycView lens (r + cycleLen (rotation lens)) = cycView lens r := by
  unfold cycView
  rw [wrap_periodic _ _ hP]

/-- A view never shows more characters than the topic's query. $$\ell \le L$$ -/
theorem lenAt_le (L : Nat) (reveal τ : Rat) : lenAt L reveal τ ≤ L := by
  unfold lenAt
  split
  · exact Nat.min_le_left _ _
  split
  · exact Nat.le_refl _
  · omega

/-- Nothing is typed before the 700 ms lead. $$t < 700 \Rightarrow \text{len} = 0$$ -/
theorem before_lead (lens : List Nat) (t : Rat) (h : t < askLead) : (askView lens t).len = 0 := by
  unfold askView
  simp [h]

#guard (askView [23, 25, 22, 20] 0).len == 0
#guard (askView [23, 25, 22, 20] 700).len == 1
#guard (askView [23, 25, 22, 20] 732).len == 2
#guard (askView [23, 25, 22, 20] (700 + 32 * 23)).len == 23
#guard (askView [23, 25, 22, 20] (700 + 32 * 23 + 280)).results == true
#guard (askView [23, 25, 22, 20] (700 + 32 * 23 + 279)).results == false

end Fw.Parts.PlatformEntries
