/-!
# hero.countdown: the countdown's pure maths (M2 pilot part)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 3789-3790 spring constants (stiffness 280, damping 18, mass 0.3; 16 ms slices);
  * 3791-3803 `GE` spring integration (semi-implicit Euler, settle test, snap to target);
  * 3804-3808 `KE` signed face distance; 3809-3811 `qE` digit at a place; 3812-3816 `JE` places;
  * 3823-3874 `$E` digit: face `k` gets `translateY(KE(k, a) · c)`, `c` = the spacer's `offsetHeight`,
    faces only rendered while `c > 0`;
  * 3875-3903 `tD` number: one digit per place, `padStart` for every unit but days;
  * 3904-3911 `nD`/`rD`: target `2026-11-02T12:00:00+07:00`, remaining whole seconds, days/hours/min/sec;
  * 3916-3980 `cD`: 1 s `setInterval` + `visibilitychange`, `aria-label` = `"<v> <unit>"` joined by `", "`.
* `assets/2.gBuqKVzi.css` 1397-1506: digit `line-height: 1.3`; unit metrics per band (base, `C1000-nodw`,
  `<=400`).
* English unit labels (JS 1975-2011): `days`, `hours`, `mins`, `seconds`.

All quantities are exact: `Int`/`Nat` for ms, seconds and digits, `Rat` for spring values, face offsets and font
sizes. No `Float`.
-/
namespace Fw.Parts.HeroCountdown

/-! ## Remaining time and units -/

/-- The countdown target, epoch ms: `Date.parse("2026-11-02T12:00:00+07:00")` = 2026-11-02T05:00:00Z (JS 3904).

$$\mathrm{target} = 1\,793\,595\,600\,000\ \text{ms}$$

The instant the original counts down to, in milliseconds since the Unix epoch. -/
def targetMs : Int := 1793595600000

/-- Remaining whole seconds, rounded up, never negative (JS 3906-3907, `rD`).

$$\forall\, \mathit{now}, \mathit{target} \in \mathbb{Z}:\quad
  \operatorname{remainingSeconds}(\mathit{now}, \mathit{target}) =
  \max\!\left(0, \left\lceil \tfrac{\mathit{target} - \mathit{now}}{1000} \right\rceil\right) \in \mathbb{N}$$

Milliseconds left until the target, turned into whole seconds by rounding up, and zero once the target has passed.
The original's non-finite guard (`NaN`/`Infinity` give 0) has no counterpart: `Int` is always finite. -/
def remainingSeconds (nowMs targetMs : Int) : Nat := ((targetMs - nowMs + 999) / 1000).toNat

#guard remainingSeconds 0 1 == 1
#guard remainingSeconds 0 1000 == 1
#guard remainingSeconds 0 1001 == 2
#guard remainingSeconds 5000 1000 == 0
#guard remainingSeconds 1000 1000 == 0
#guard remainingSeconds 1001 1000 == 0
#guard remainingSeconds 999 1000 == 1

/-- `remainingSeconds` is the ceiling: for a future target it is the least $r$ with $1000\,r \ge$ the gap.

$$\forall\, \mathit{now}, \mathit{target} \in \mathbb{Z},\ \mathit{now} < \mathit{target}:\quad
  1000\,(r - 1) < \mathit{target} - \mathit{now} \le 1000\, r,\qquad r = \operatorname{remainingSeconds}(\mathit{now}, \mathit{target})$$

While the target is ahead, the shown seconds are the gap in ms divided by 1000 and rounded up. -/
theorem remainingSeconds_ceil (now target : Int) (h : now < target) :
    1000 * ((remainingSeconds now target : Int) - 1) < target - now ∧
      target - now ≤ 1000 * (remainingSeconds now target : Int) := by
  unfold remainingSeconds
  have : 0 ≤ (target - now + 999) / 1000 := by omega
  rw [Int.toNat_of_nonneg this]
  omega

/-- Zero remaining time: at or after the target the countdown shows 0 seconds.

$$\forall\, \mathit{now}, \mathit{target} \in \mathbb{Z}:\quad \mathit{target} \le \mathit{now} \Rightarrow \operatorname{remainingSeconds}(\mathit{now}, \mathit{target}) = 0$$

Once the target is reached or passed (including any negative gap), the remaining time is exactly zero. -/
theorem remainingSeconds_past (now target : Int) (h : target ≤ now) : remainingSeconds now target = 0 := by
  unfold remainingSeconds; omega

/-- Monotone in time: a later clock never shows more remaining seconds.

$$\forall\, t_1, t_2, \mathit{target} \in \mathbb{Z}:\quad t_1 \le t_2 \Rightarrow
  \operatorname{remainingSeconds}(t_2, \mathit{target}) \le \operatorname{remainingSeconds}(t_1, \mathit{target})$$

As time moves forward the remaining seconds never go up. -/
theorem remainingSeconds_antitone (t1 t2 target : Int) (h : t1 ≤ t2) :
    remainingSeconds t2 target ≤ remainingSeconds t1 target := by
  unfold remainingSeconds
  have : (target - t2 + 999) / 1000 ≤ (target - t1 + 999) / 1000 := Int.ediv_le_ediv (by omega) (by omega)
  omega

/-- Split whole seconds into `[days, hours, minutes, seconds]` (JS 3907).

$$\operatorname{unitsFromSeconds}(n) = \left[\left\lfloor \tfrac{n}{86400} \right\rfloor,\
  \left\lfloor \tfrac{n \bmod 86400}{3600} \right\rfloor,\ \left\lfloor \tfrac{n \bmod 3600}{60} \right\rfloor,\
  n \bmod 60\right],\quad n \in \mathbb{N}$$

The four numbers the clock shows: whole days, then the hours, minutes and seconds left over. -/
def unitsFromSeconds (n : Nat) : List Nat := [n / 86400, n % 86400 / 3600, n % 3600 / 60, n % 60]

#guard unitsFromSeconds 0 == [0, 0, 0, 0]
#guard unitsFromSeconds 86399 == [0, 23, 59, 59]
#guard unitsFromSeconds 86400 == [1, 0, 0, 0]
#guard unitsFromSeconds (86400 + 2 * 3600 + 3 * 60 + 4) == [1, 2, 3, 4]

/-- Range bounds: hours below 24, minutes and seconds below 60.

$$\forall n \in \mathbb{N},\ [d, h, m, s] = \operatorname{unitsFromSeconds}(n):\quad h < 24 \land m < 60 \land s < 60$$

The hour, minute and second fields always stay inside a clock's normal range. -/
theorem unitsFromSeconds_range (n : Nat) :
    n % 86400 / 3600 < 24 ∧ n % 3600 / 60 < 60 ∧ n % 60 < 60 := by
  omega

/-- The units add back up to the total.

$$\forall n \in \mathbb{N},\ [d, h, m, s] = \operatorname{unitsFromSeconds}(n):\quad 86400\,d + 3600\,h + 60\,m + s = n$$

Nothing is lost or double counted when seconds are split into days, hours, minutes and seconds. -/
theorem unitsFromSeconds_sum (n : Nat) :
    86400 * (n / 86400) + 3600 * (n % 86400 / 3600) + 60 * (n % 3600 / 60) + n % 60 = n := by
  omega

/-- Lexicographic order on four-unit tuples (days first).

$$[d,h,m,s] \preceq [d',h',m',s'] \iff d < d' \lor (d = d' \land (h < h' \lor (h = h' \land (m < m' \lor (m = m' \land s \le s'))))),\qquad x \preceq y \text{ is false if } |x| \ne 4 \lor |y| \ne 4$$

(for lists $x, y \in \mathbb{N}^*$).

The order in which a clock reading counts as "no later" than another. -/
def lexLe : List Nat → List Nat → Prop
  | [d, h, m, s], [d', h', m', s'] => d < d' ∨ (d = d' ∧ (h < h' ∨ (h = h' ∧ (m < m' ∨ (m = m' ∧ s ≤ s')))))
  | _, _ => False

/-- Monotone display: fewer remaining seconds give a lexicographically smaller (or equal) reading.

$$\forall a, b \in \mathbb{N}:\quad a \le b \Rightarrow \operatorname{unitsFromSeconds}(a) \preceq \operatorname{unitsFromSeconds}(b)$$

The shown days/hours/minutes/seconds tick down in clock order whenever the remaining seconds go down. -/
theorem unitsFromSeconds_mono (a b : Nat) (h : a ≤ b) : lexLe (unitsFromSeconds a) (unitsFromSeconds b) := by
  simp only [unitsFromSeconds, lexLe]
  omega

/-- Monotonicity in time, end to end: a later clock shows a reading no later in clock order.

$$\forall t_1 \le t_2,\ \mathit{target} \in \mathbb{Z}:\quad
  \operatorname{units}(\operatorname{remainingSeconds}(t_2, \mathit{target})) \preceq \operatorname{units}(\operatorname{remainingSeconds}(t_1, \mathit{target}))$$

As the clock advances, the countdown display never moves backwards. -/
theorem countdown_mono_in_time (t1 t2 target : Int) (h : t1 ≤ t2) :
    lexLe (unitsFromSeconds (remainingSeconds t2 target)) (unitsFromSeconds (remainingSeconds t1 target)) :=
  unitsFromSeconds_mono _ _ (remainingSeconds_antitone t1 t2 target h)

/-! ## Digits -/

/-- Number of decimal digits of `m` (`String(m).length` for $m < 10^{21}$; 1 for 0).

$$\operatorname{digitCount}(m) = \begin{cases} 1 & m < 10 \\ 1 + \operatorname{digitCount}(\lfloor m/10 \rfloor) & m \ge 10 \end{cases}$$

How many characters the number takes when written in base 10. -/
def digitCount (m : Nat) : Nat := if h : m < 10 then 1 else digitCount (m / 10) + 1
termination_by m
decreasing_by omega

#guard (List.range 2000).all fun m => digitCount m == (toString m).length
#guard digitCount 1000000 == 7

/-- Every number is below 10 to the power of its digit count.

$$\forall m \in \mathbb{N}:\quad m < 10^{\operatorname{digitCount}(m)}$$

A number always fits in as many decimal places as it has digits. -/
theorem lt_pow_digitCount (m : Nat) : m < 10 ^ digitCount m := by
  induction m using Nat.strongRecOn with
  | _ m ih =>
    unfold digitCount
    split
    · simp; omega
    · have := ih (m / 10) (by omega)
      rw [Nat.pow_succ]
      omega

/-- Place values, most significant first: $[10^{n-1}, \dots, 10, 1]$.

$$\operatorname{places}(n) = [10^{n-1}, 10^{n-2}, \dots, 10^0]\quad (n \in \mathbb{N};\ [\,] \text{ for } n = 0)$$

The list of place values for a number written with exactly `n` digits. -/
def places : Nat → List Nat
  | 0 => []
  | n + 1 => 10 ^ n :: places n

/-- The integer magnitude the original works with: $|\lfloor v \rfloor|$ (`Math.abs(Math.floor(v))`).

$$\operatorname{mag}(v) = |\lfloor v \rfloor| \in \mathbb{N},\quad v \in \mathbb{Q}$$

The whole-number size of a value, after flooring and dropping the sign. -/
def mag (v : Rat) : Nat := v.floor.natAbs

/-- Places shown for a unit value (JS 3812-3816, `JE`): as many as its digits, at least 2 when `padStart`.

$$\operatorname{digitPlaces}(v, p) = \operatorname{places}(n),\quad
  n = \begin{cases} \max(2, \operatorname{digitCount}(\operatorname{mag} v)) & p \\ \operatorname{digitCount}(\operatorname{mag} v) & \lnot p \end{cases}$$

The place values of the digits a unit shows; hours, minutes and seconds are padded to two digits, days are not. -/
def digitPlaces (value : Rat) (padStart : Bool) : List Nat :=
  let len := digitCount (mag value)
  places (if padStart then max 2 len else len)

#guard digitPlaces 0 false == [1]
#guard digitPlaces 0 true == [10, 1]
#guard digitPlaces 123 true == [100, 10, 1]
#guard digitPlaces (-79/10) true == [10, 1]
#guard digitPlaces 16 false == [10, 1]

/-- The digit at a place (JS 3809-3811, `qE`).

$$\operatorname{digitAt}(v, p) = \left\lfloor \tfrac{\operatorname{mag}(v)}{p} \right\rfloor \bmod 10,\quad p \in \mathbb{N}_{\ge 1}$$

Which digit 0-9 stands at the given place value. For $p = 0$ Lean gives $0$ where the original gives `NaN`;
the original never passes 0. -/
def digitAt (value : Rat) (place : Nat) : Nat := mag value / place % 10

#guard digitAt 1234 100 == 2
#guard digitAt (-12349/10) 1 == 5
#guard digitAt 5 10 == 0

/-- Every shown digit is a decimal digit.

$$\forall v \in \mathbb{Q}, p \in \mathbb{N}:\quad \operatorname{digitAt}(v, p) < 10$$

A digit cell never needs a face outside 0-9. -/
theorem digitAt_lt_ten (v : Rat) (p : Nat) : digitAt v p < 10 := Nat.mod_lt _ (by decide)

/-- Read a digit list in base 10, most significant first.

$$\operatorname{fromDigits}([d_1, \dots, d_n]) = \sum_{i=1}^{n} d_i\, 10^{n-i}$$

The number a row of digits spells out. -/
def fromDigits (ds : List Nat) : Nat := ds.foldl (fun acc d => acc * 10 + d) 0

/-- Reading the digits at the first `n` places from an accumulator. $$\forall m, n, a:\ \operatorname{foldl}(\lambda x\,d.\ 10x + d,\ a,\ [\lfloor m/p \rfloor \bmod 10 \mid p \in \operatorname{places}(n)]) = a \cdot 10^n + (m \bmod 10^n)$$ -/
theorem foldl_places (m n acc : Nat) :
    ((places n).map (fun p => m / p % 10)).foldl (fun acc d => acc * 10 + d) acc
      = acc * 10 ^ n + m % 10 ^ n := by
  induction n generalizing acc with
  | zero => simp [places, Nat.mod_one]
  | succ n ih =>
    simp only [places, List.map_cons, List.foldl_cons]
    rw [ih, Nat.mod_pow_succ, Nat.pow_succ]
    grind

/-- The shown digits spell the value: reading the digit row gives back $|\lfloor v \rfloor|$, padded or not.

$$\forall v \in \mathbb{Q}, p \in \{\top, \bot\}:\quad
  \operatorname{fromDigits}\big([\operatorname{digitAt}(v, q) \mid q \in \operatorname{digitPlaces}(v, p)]\big) = |\lfloor v \rfloor|$$

The digits a unit displays always read back as exactly the unit's value (padding only adds leading zeros). -/
theorem digits_spell_value (v : Rat) (pad : Bool) :
    fromDigits ((digitPlaces v pad).map (digitAt v)) = mag v := by
  unfold fromDigits digitPlaces digitAt
  rw [foldl_places]
  have h1 := lt_pow_digitCount (mag v)
  have h2 : 10 ^ digitCount (mag v) ≤ 10 ^ (if pad then max 2 (digitCount (mag v)) else digitCount (mag v)) := by
    apply Nat.pow_le_pow_right (by decide)
    split <;> omega
  simp only [Nat.zero_mul, Nat.zero_add]
  exact Nat.mod_eq_of_lt (by omega)

/-! ## Faces: faithful (10 faces per digit) and strip -/

/-- Floored remainder mod 10 on rationals (JS `((x % 10) + 10) % 10` for finite `x`).

$$\operatorname{fmod}_{10}(x) = x - 10\left\lfloor \tfrac{x}{10} \right\rfloor \in [0, 10)$$

Where a value lands on a 0-10 dial. -/
def fmod10 (x : Rat) : Rat := x - 10 * ((x / 10).floor : Rat)

/-- The floored remainder lies on the dial. $$\forall x \in \mathbb{Q}:\ 0 \le \operatorname{fmod}_{10}(x) < 10$$ -/
theorem fmod10_bounds (x : Rat) : 0 ≤ fmod10 x ∧ fmod10 x < 10 := by
  have h1 := Rat.floor_le (x / 10)
  have h2 := Rat.lt_floor_add_one (x / 10)
  rw [Rat.intCast_add] at h2
  unfold fmod10
  constructor <;> grind

/-- The floored remainder differs from its argument by whole turns. $$\forall x\ \exists z \in \mathbb{Z}:\ \operatorname{fmod}_{10}(x) = x - 10 z$$ -/
theorem fmod10_eq (x : Rat) : ∃ z : Int, fmod10 x = x - 10 * (z : Rat) := ⟨_, rfl⟩

/-- Signed face distance (JS 3804-3808, `KE`): where face `k` sits, in cells, when the spring is at `a`.

$$\operatorname{faceDelta}(k, a) = \begin{cases} r - 10 & r > 5 \\ r & r \le 5 \end{cases},\quad
  r = \operatorname{fmod}_{10}\big(10 + k - \operatorname{fmod}_{10}(a)\big),\quad k \in \mathbb{Z},\ a \in \mathbb{Q}$$

Face `k` is drawn this many cell heights below the digit window (negative: above). The original's truncated `%`
equals the floored one here because its argument is positive for faces $0 \le k \le 9$. -/
def faceDelta (face : Int) (current : Rat) : Rat :=
  let r := fmod10 (10 + (face : Rat) - fmod10 current)
  if r > 5 then r - 10 else r

#guard faceDelta 3 3 == 0
#guard faceDelta 9 0 == -1
#guard faceDelta 0 9 == 1
#guard faceDelta 5 0 == 5
#guard faceDelta 6 0 == -4
#guard faceDelta 0 (-1/2) == 1/2

/-- Faces lie in the half-open band $(-5, 5]$ cells.

$$\forall k \in \mathbb{Z}, a \in \mathbb{Q}:\quad -5 < \operatorname{faceDelta}(k, a) \le 5$$

Every face is at most five cells from the window, so each face has one position per spring value. -/
theorem faceDelta_bounds (k : Int) (a : Rat) : -5 < faceDelta k a ∧ faceDelta k a ≤ 5 := by
  have := fmod10_bounds (10 + (k : Rat) - fmod10 a)
  unfold faceDelta
  dsimp only
  split <;> constructor <;> grind

/-- Faces are congruent to $k - a$ modulo 10.

$$\forall k \in \mathbb{Z}, a \in \mathbb{Q}\ \exists z \in \mathbb{Z}:\quad \operatorname{faceDelta}(k, a) = k - a + 10 z$$

A face's offset always equals its digit minus the spring value, up to whole turns of the 10-digit dial. -/
theorem faceDelta_congr (k : Int) (a : Rat) : ∃ z : Int, faceDelta k a = (k : Rat) - a + 10 * (z : Rat) := by
  obtain ⟨z0, h0⟩ := fmod10_eq a
  obtain ⟨z1, h1⟩ := fmod10_eq (10 + (k : Rat) - fmod10 a)
  unfold faceDelta
  dsimp only
  split
  · refine ⟨1 + z0 - z1 - 1, ?_⟩
    simp only [Rat.intCast_sub, Rat.intCast_add]
    rw [h1, h0]; simp; grind
  · refine ⟨1 + z0 - z1, ?_⟩
    simp only [Rat.intCast_sub, Rat.intCast_add]
    rw [h1, h0]; simp; grind

/-- An integer strictly between -1 and 1 is 0. $$\forall z \in \mathbb{Z}:\ -1 < z < 1 \Rightarrow z = 0$$ -/
theorem int_eq_zero_of_lt_one (z : Int) (h1 : -1 < (z : Rat)) (h2 : (z : Rat) < 1) : z = 0 := by
  have a : ((-1 : Int) : Rat) < (z : Rat) := by simpa using h1
  have b : (z : Rat) < ((1 : Int) : Rat) := by simpa using h2
  have a' := Rat.intCast_lt_intCast.mp a
  have b' := Rat.intCast_lt_intCast.mp b
  omega

/-- Two values congruent mod 10 inside the same width-10 band are equal. $$x = y + 10z,\ x, y \in (-5, 5],\ z \in \mathbb{Z} \Rightarrow x = y$$ -/
theorem eq_of_congr10 (x y : Rat) (z : Int) (h : x = y + 10 * (z : Rat))
    (hx1 : -5 < x) (hx2 : x ≤ 5) (hy1 : -5 < y) (hy2 : y ≤ 5) : x = y := by
  have : z = 0 := int_eq_zero_of_lt_one z (by grind) (by grind)
  subst this; simp at h; grind

/-- The faithful face transform in px (JS 3862): `translateY(KE(k, a) · c)`.

$$\operatorname{faceOffsetPx}(k, a, c) = \operatorname{faceDelta}(k, a)\cdot c$$

How far face `k` is moved, in pixels, for spring value `a` and cell height `c`. -/
def faceOffsetPx (face : Int) (spring cellPx : Rat) : Rat := faceDelta face spring * cellPx

/-- Strip variant (ours): one strip of 12 entries $[9, 0, 1, \dots, 9, 0]$ moved by $-(1 + \operatorname{fmod}_{10} a)$ cells.

$$\operatorname{stripOffsetCells}(a) = -\big(1 + \operatorname{fmod}_{10}(a)\big)$$

How far the whole digit strip is shifted, in cells, for spring value `a`. -/
def stripOffsetCells (spring : Rat) : Rat := -(1 + fmod10 spring)

/-- The digit printed on strip entry `j` (entries $0..11$ read $9, 0, 1, \dots, 9, 0$).

$$\operatorname{stripEntryDigit}(j) = (j + 9) \bmod 10$$

Which digit the `j`-th cell of the strip shows. -/
def stripEntryDigit (j : Int) : Int := (j + 9) % 10

#guard (List.range 12).map (fun (j : Nat) => stripEntryDigit (Int.ofNat j)) == [9, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 0]
#guard stripOffsetCells 0 == -1
#guard stripOffsetCells (37/2) == -19/2

/-- **Strip shows the same as faithful.** Inside the digit window (offsets strictly between $-1$ and $1$ cell, the
only ones the clip lets through) the strip shows digit `k` at offset `o` exactly when the faithful face `k` sits at
`o`, for every spring value.

$$\forall a \in \mathbb{Q},\ k \in \{0..9\},\ o \in (-1, 1):\quad
  \big(\exists j \in \{0..11\}:\ \operatorname{stripEntryDigit}(j) = k \land j + \operatorname{stripOffsetCells}(a) = o\big)
  \iff \operatorname{faceDelta}(k, a) = o$$

Whatever the spring is doing, the visible part of the strip is the same picture as the visible faces of the
original: same digits at the same positions (multiply by $c > 0$ for pixels). -/
theorem strip_shows_same (a : Rat) (k : Int) (hk0 : 0 ≤ k) (hk1 : k < 10) (o : Rat) (ho1 : -1 < o) (ho2 : o < 1) :
    (∃ j : Int, 0 ≤ j ∧ j < 12 ∧ stripEntryDigit j = k ∧ (j : Rat) + stripOffsetCells a = o)
      ↔ faceDelta k a = o := by
  obtain ⟨z0, h0⟩ := fmod10_eq a
  have hn := fmod10_bounds a
  have hfb := faceDelta_bounds k a
  obtain ⟨zf, hf⟩ := faceDelta_congr k a
  unfold stripOffsetCells stripEntryDigit
  constructor
  · rintro ⟨j, hj0, hj1, hjd, hjo⟩
    have hq : j + 9 = k + 10 * ((j + 9) / 10) := by omega
    have hjr : (j : Rat) + 9 = (k : Rat) + 10 * (((j + 9) / 10 : Int) : Rat) := by
      have := congrArg (fun z : Int => (z : Rat)) hq
      simpa [Rat.intCast_add, Rat.intCast_mul] using this
    apply eq_of_congr10 _ _ (zf - (j + 9) / 10 - z0 + 1) _ hfb.1 hfb.2 (by grind) (by grind)
    have e : ((zf - (j + 9) / 10 - z0 + 1 : Int) : Rat)
        = (zf : Rat) - (((j + 9) / 10 : Int) : Rat) - (z0 : Rat) + 1 := by
      simp [Rat.intCast_add, Rat.intCast_sub]
    rw [e, hf, ← hjo, h0]
    grind
  · intro hfo
    -- w = o + fmod10 a is the integer k + 10 (zf + z0)
    have hw : o + fmod10 a = (((k + 10 * (zf - z0)) : Int) : Rat) := by
      rw [h0, ← hfo, hf]; simp [Rat.intCast_add, Rat.intCast_mul]; grind
    have hlo : ((-1 : Int) : Rat) < (((k + 10 * (zf - z0)) : Int) : Rat) := by rw [← hw]; simp; grind
    have hhi : (((k + 10 * (zf - z0)) : Int) : Rat) < ((11 : Int) : Rat) := by rw [← hw]; simp; grind
    have hlo' := Rat.intCast_lt_intCast.mp hlo
    have hhi' := Rat.intCast_lt_intCast.mp hhi
    refine ⟨k + 10 * (zf - z0) + 1, by omega, by omega, by omega, ?_⟩
    have : ((k + 10 * (zf - z0) + 1 : Int) : Rat) = (((k + 10 * (zf - z0)) : Int) : Rat) + 1 := by
      simp [Rat.intCast_add]
    rw [this, ← hw]
    grind

/-- Settled digits: with the spring at rest on digit `d`, face `d` sits at offset 0 and no other face does.

$$\forall d, k \in \{0..9\}:\quad \operatorname{faceDelta}(k, d) = 0 \iff k = d$$

When the spring has settled, the digit it was told to show is the one face at offset 0. -/
theorem faceDelta_settled (d k : Int) (hd0 : 0 ≤ d) (hd1 : d < 10) (hk0 : 0 ≤ k) (hk1 : k < 10) :
    faceDelta k (d : Rat) = 0 ↔ k = d := by
  obtain ⟨z, hz⟩ := faceDelta_congr k (d : Rat)
  have hb := faceDelta_bounds k (d : Rat)
  constructor
  · intro h0
    rw [h0] at hz
    have hr : (((k - d + 10 * z) : Int) : Rat) = ((0 : Int) : Rat) := by
      simp [Rat.intCast_add, Rat.intCast_sub, Rat.intCast_mul]; grind
    have := Rat.intCast_inj.mp hr
    omega
  · intro hkd
    subst hkd
    apply eq_of_congr10 _ _ z _ hb.1 hb.2 (by grind) (by grind)
    rw [hz]; grind

/-! ## Spring (shared by both variants) -/

/-- One spring state: position (in digits) and velocity (digits per second).

$$s = (x, v) \in \mathbb{Q}^2$$

Where the rolling digit is and how fast it moves. -/
structure Spring where
  value : Rat
  velocity : Rat
deriving Repr, BEq, DecidableEq

/-- One Euler slice of `dt` seconds (JS 3795-3797) with $k = 280$, $c = 18$, $m = 3/10$.

$$a = \frac{-k (x - x^\ast) - c\, v}{m},\quad v' = v + a\,\Delta t,\quad x' = x + v'\,\Delta t$$

A single small time step of the digit's spring toward the target digit $x^\ast$ (velocity first, then position). -/
def springSlice (s : Spring) (target dt : Rat) : Spring :=
  let acc := (-280 * (s.value - target) - 18 * s.velocity) / (3 / 10)
  let v := s.velocity + acc * dt
  { value := s.value + v * dt, velocity := v }

/-- The slice loop (JS 3794-3798): while `left > 0`, step by $\min(\mathit{left}, 16)/1000$ s, then `left -= 16`.

$$\operatorname{loop}(f, s, x^\ast, \ell) = \begin{cases} s & f = 0 \\
  \operatorname{loop}\big(f-1, \operatorname{slice}(s, x^\ast, \min(\ell, 16)/1000), x^\ast, \ell - 16\big) & f > 0 \end{cases}$$

Runs `f` spring slices of at most 16 ms each. -/
def springLoop : Nat → Spring → Rat → Rat → Spring
  | 0, s, _, _ => s
  | f + 1, s, target, left => springLoop f (springSlice s target (min left 16 / 1000)) target (left - 16)

/-- Number of loop iterations for `dtMs`: $\lceil \max(0, \mathit{dt}) / 16 \rceil$.

$$\operatorname{slices}(\mathit{dt}) = \left\lceil \tfrac{\max(0, \mathit{dt})}{16} \right\rceil \in \mathbb{N}$$

How many 16 ms slices the original's `while (left > 0)` loop runs for a frame gap of `dt` ms. -/
def slices (dtMs : Rat) : Nat := (-((-(max 0 dtMs / 16)).floor)).toNat

#guard slices 0 == 0 && slices (-5) == 0 && slices 1 == 1 && slices 16 == 1 && slices 17 == 2 && slices 32 == 2

/-- Absolute value on rationals. $$|x| = \begin{cases} -x & x < 0 \\ x & x \ge 0 \end{cases}$$ The size of `x` without its sign. -/
def ratAbs (x : Rat) : Rat := if x < 0 then -x else x

/-- Result of a spring step: new state and whether it settled.

$$(s', \mathit{done}) \in \mathbb{Q}^2 \times \{\top, \bot\}$$

What one animation frame of the digit spring returns. -/
structure SpringResult where
  state : Spring
  done : Bool
deriving Repr, BEq, DecidableEq

/-- Advance the spring `dtMs` toward `target` (JS 3791-3803, `GE`); settle and snap when slow and close.

$$\operatorname{springStep}(s, x^\ast, \mathit{dt}) = \begin{cases}
  ((x^\ast, 0), \top) & |v'| < \tfrac{1}{100} \land |x' - x^\ast| < \tfrac{1}{1000} \\
  ((x', v'), \bot) & \text{otherwise} \end{cases},\quad (x', v') = \operatorname{loop}(\operatorname{slices}(\mathit{dt}), s, x^\ast, \max(0, \mathit{dt}))$$

One frame of the digit's roll: integrate, then snap exactly onto the target digit once it is slow and close enough. -/
def springStep (s : Spring) (target dtMs : Rat) : SpringResult :=
  let s' := springLoop (slices dtMs) s target (max 0 dtMs)
  if ratAbs s'.velocity < 1 / 100 ∧ ratAbs (s'.value - target) < 1 / 1000 then
    { state := { value := target, velocity := 0 }, done := true }
  else { state := s', done := false }

#guard springStep ⟨3, 0⟩ 3 16 == { state := ⟨3, 0⟩, done := true }
#guard (springStep ⟨4, 0⟩ 3 16).done == false
#guard (springStep ⟨4, 0⟩ 3 16).state == ⟨4 - 280 * (16/1000)^2 / (3/10), -280 * (16/1000) / (3/10)⟩

/-- A settled spring is exactly on target with zero velocity.

$$\forall s, x^\ast, \mathit{dt}:\quad \operatorname{springStep}(s, x^\ast, \mathit{dt}).\mathit{done} \Rightarrow \operatorname{springStep}(s, x^\ast, \mathit{dt}).s = (x^\ast, 0)$$

When the roll ends, the digit sits exactly on its cell, which is why the settled faces land on whole pixels. -/
theorem springStep_done (s : Spring) (target dt : Rat) (h : (springStep s target dt).done = true) :
    (springStep s target dt).state = { value := target, velocity := 0 } := by
  unfold springStep at *
  dsimp only at h ⊢
  split at h <;> simp_all

/-- A non-positive frame gap runs no slice.

$$\forall \mathit{dt} \in \mathbb{Q},\ \mathit{dt} \le 0:\quad \operatorname{slices}(\mathit{dt}) = 0$$

If no time passed, the slice loop runs zero times. -/
theorem slices_nonpos (dt : Rat) (h : dt ≤ 0) : slices dt = 0 := by
  unfold slices
  have : max 0 dt = 0 := by grind
  rw [this]; decide +kernel

/-! ## Label and metrics -/

/-- The timer's `aria-label` (JS 3920-3926): `"<v> <label>"` per unit, joined by `", "`.

$$\operatorname{ariaLabel}([u_i], [\ell_i]) = \mathop{\Vert}_{i}^{\text{", "}} \big(\operatorname{str}(u_i) \Vert \text{" "} \Vert \ell_i\big)$$

The sentence a screen reader hears; a missing label prints `undefined`, as JS string interpolation does. -/
def ariaLabel (units : List Nat) (labels : List String) : String :=
  ", ".intercalate ((units.zipIdx).map fun (u, i) => s!"{u} {labels.getD i "undefined"}")

/-- English unit labels (JS 1975-2011). $$[\text{days}, \text{hours}, \text{mins}, \text{seconds}]$$ The four unit
names on the English page. -/
def labelsEn : List String := ["days", "hours", "mins", "seconds"]

#guard ariaLabel [16, 4, 5, 9] labelsEn == "16 days, 4 hours, 5 mins, 9 seconds"
#guard ariaLabel [] labelsEn == ""

/-- Cell height `c` in px: the digit spacer's `offsetHeight` at `line-height: 1.3`, rounded half up.

$$\operatorname{cellHeight}(f) = \left\lfloor \tfrac{13}{10} f + \tfrac12 \right\rfloor \in \mathbb{Z}$$

The whole-pixel height of one digit cell for font size `f` (24, 28, 40 give 31, 36, 52). -/
def cellHeight (fontPx : Rat) : Int := (fontPx * 13 / 10 + 1 / 2).floor

#guard cellHeight 24 == 31 && cellHeight 28 == 36 && cellHeight 40 == 52

/-- Countdown CSS metrics in px (CSS 1422-1506).

$$(\mathit{font}, c, \mathit{unit}, \mathit{radius}, \mathit{unitGap}, \mathit{rowGap}, \mathit{label}) \in \mathbb{N}^7$$

The sizes of one countdown layout band. -/
structure Metrics where
  fontPx : Nat
  cellPx : Nat
  unitPx : Nat
  unitRadiusPx : Nat
  unitGapPx : Nat
  rowGapPx : Nat
  labelPx : Nat
deriving Repr, BEq, DecidableEq

/-- Metrics per band: `(width<=400px)` wins, else `C1000-nodw` =
`(width<=1000px), (hover: none) and (pointer: coarse) and (width<=1200px)`, else the base rules.

$$\operatorname{metrics}(\ell, c) = \begin{cases} (24, 31, 74, 14, 4, 6, 10) & \ell \\ (28, 36, 88, 16, 6, 8, 11) & \lnot\ell \land c \\ (40, 52, 120, 24, 8, 8, 14) & \text{otherwise} \end{cases}$$

The countdown's sizes for the three layout bands. -/
def countdownMetrics (le400 c1000nodw : Bool) : Metrics :=
  if le400 then ⟨24, 31, 74, 14, 4, 6, 10⟩
  else if c1000nodw then ⟨28, 36, 88, 16, 6, 8, 11⟩
  else ⟨40, 52, 120, 24, 8, 8, 14⟩

#guard (countdownMetrics true true).fontPx == 24 && (countdownMetrics false true).cellPx == 36

/-- The cell heights in the metrics table are `cellHeight` of the band's font.

$$\forall \ell, c:\quad \operatorname{metrics}(\ell, c).c = \operatorname{cellHeight}(\operatorname{metrics}(\ell, c).\mathit{font})$$

The table's `c` column is not a free constant: it is the rounded 1.3 line height. -/
theorem countdownMetrics_cell (le400 c1000nodw : Bool) :
    ((countdownMetrics le400 c1000nodw).cellPx : Int) = cellHeight (countdownMetrics le400 c1000nodw).fontPx := by
  cases le400 <;> cases c1000nodw <;> decide +kernel

/-! ## The spring depends on the frame split (ledger n=8)

Two 8 ms steps from a displaced spring do not land where one 16 ms step lands: the integrator is not
time-consistent. So no keyframe list fixed in advance reproduces the spring at every frame rate; a WAAPI
replacement (E-s) can match it at one fixed cadence only. -/

/-- **spring_split_differs.** Two half steps differ from one full step, from the state $(4, 0)$ toward $3$.

$$\operatorname{springStep}\big(\operatorname{springStep}((4, 0), 3, 8).\mathrm{state},\ 3,\ 8\big).\mathrm{state} \ne \operatorname{springStep}((4, 0), 3, 16).\mathrm{state}$$

Why the spring cannot become one frame-rate-free keyframe list. -/
theorem spring_split_differs :
    (springStep (springStep ⟨4, 0⟩ 3 8).state 3 8).state ≠ (springStep ⟨4, 0⟩ 3 16).state := by
  decide +kernel

/-! ## The spring partition: frames act only through their slices (ledger n=8)

Until it settles, the spring after a list of frames is fixed by the concatenation of the frames' slice lengths, so
every split of time into whole multiples of 16 ms gives the same states, and a fixed cadence gives one fixed state
sequence (the keyframes of cd-roll-ca, consumed by `Fw.Parts.HeroCountdownOpt`). -/

/-- The slice lengths (ms) the loop runs from `left` ms in `f` iterations.

$$\operatorname{durs}(0, \ell) = [\,],\quad \operatorname{durs}(f + 1, \ell) = \min(\ell, 16) :: \operatorname{durs}(f, \ell - 16)$$ -/
def loopDurs : Nat → Rat → List Rat
  | 0, _ => []
  | f + 1, left => min left 16 :: loopDurs f (left - 16)

/-- The slice lengths of one frame of `dtMs` ms.

$$\operatorname{sl}(\mathit{dt}) = \operatorname{durs}(\operatorname{slices}(\mathit{dt}), \max(0, \mathit{dt}))$$ -/
def frameDurs (dtMs : Rat) : List Rat := loopDurs (slices dtMs) (max 0 dtMs)

#guard frameDurs 16 == [16] && frameDurs 8 == [8] && frameDurs 24 == [16, 8] && frameDurs 32 == [16, 16]
#guard frameDurs 0 == [] && frameDurs (-3) == [] && frameDurs (50 / 3) == [16, 2 / 3]

/-- Run slices of the given lengths (ms) toward `target`.

$$\operatorname{run}(s, x^\ast, [\,]) = s,\quad \operatorname{run}(s, x^\ast, d :: ds) = \operatorname{run}(\operatorname{slice}(s, x^\ast, d/1000), x^\ast, ds)$$ -/
def runSlices (s : Spring) (target : Rat) (ds : List Rat) : Spring :=
  ds.foldl (fun s d => springSlice s target (d / 1000)) s

/-- The loop is the run of its slice lengths.

$$\forall f \in \mathbb{N},\ \forall s,\ \forall x^\ast, \ell \in \mathbb{Q}:\ \operatorname{loop}(f, s, x^\ast, \ell) = \operatorname{run}(s, x^\ast, \operatorname{durs}(f, \ell))$$ -/
theorem springLoop_eq_run : ∀ (f : Nat) (s : Spring) (target left : Rat),
    springLoop f s target left = runSlices s target (loopDurs f left)
  | 0, _, _, _ => rfl
  | f + 1, s, target, left => by
    simp only [springLoop, loopDurs, runSlices, List.foldl_cons]
    exact springLoop_eq_run f _ target (left - 16)

/-- The spring integrated over a list of frame gaps (ms), with no settle test.

$$\operatorname{roll}(s, x^\ast, [\,]) = s,\quad \operatorname{roll}(s, x^\ast, \mathit{dt} :: \mathit{dts}) = \operatorname{roll}\big(\operatorname{loop}(\operatorname{slices}(\mathit{dt}), s, x^\ast, \max(0, \mathit{dt})), x^\ast, \mathit{dts}\big)$$ -/
def rollFrames (s : Spring) (target : Rat) (dts : List Rat) : Spring :=
  dts.foldl (fun s dt => springLoop (slices dt) s target (max 0 dt)) s

/-- **The spring partition theorem.** A list of frames integrates exactly the concatenation of its frames' slices.

$$\forall s,\ \forall x^\ast \in \mathbb{Q},\ \forall [\mathit{dt}_1, \ldots, \mathit{dt}_n] \in \mathbb{Q}^{*}:\ \operatorname{roll}(s, x^\ast, [\mathit{dt}_1, \ldots, \mathit{dt}_n]) = \operatorname{run}\big(s, x^\ast, \operatorname{sl}(\mathit{dt}_1) \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \operatorname{sl}(\mathit{dt}_n)\big)$$

How time is split into frames matters only through the slices it produces. -/
theorem rollFrames_eq_run (s : Spring) (target : Rat) (dts : List Rat) :
    rollFrames s target dts = runSlices s target (dts.flatMap frameDurs) := by
  induction dts generalizing s with
  | nil => rfl
  | cons dt dts ih =>
    rw [List.flatMap_cons, runSlices, List.foldl_append]
    show rollFrames (springLoop (slices dt) s target (max 0 dt)) target dts = _
    rw [ih, springLoop_eq_run]
    rfl

/-- Two splits with the same slices leave the spring in the same state.

$$\forall s,\ \forall x^\ast,\ \forall a, b \in \mathbb{Q}^{*}:\ \operatorname{sl}(a_1) \mathbin{+\!\!+} \cdots = \operatorname{sl}(b_1) \mathbin{+\!\!+} \cdots \Rightarrow \operatorname{roll}(s, x^\ast, a) = \operatorname{roll}(s, x^\ast, b)$$ -/
theorem rollFrames_congr (s : Spring) (target : Rat) (a b : List Rat) (h : a.flatMap frameDurs = b.flatMap frameDurs) :
    rollFrames s target a = rollFrames s target b := by
  rw [rollFrames_eq_run, rollFrames_eq_run, h]

/-- From $16k$ ms the loop runs $k$ full slices. $$\forall k \in \mathbb{N}:\ \operatorname{durs}(k, 16k) = [16]^k$$ -/
theorem loopDurs_mul16 : ∀ k : Nat, loopDurs k (16 * (k : Rat)) = List.replicate k 16
  | 0 => rfl
  | k + 1 => by
    have h0 : (0 : Rat) ≤ k := by exact_mod_cast Nat.zero_le k
    have hm : min (16 * ((k + 1 : Nat) : Rat)) 16 = 16 := by push_cast; grind
    have hl : 16 * ((k + 1 : Nat) : Rat) - 16 = 16 * (k : Rat) := by push_cast; grind
    rw [loopDurs, hm, hl, loopDurs_mul16 k, List.replicate_succ]

/-- A frame of $16k$ ms runs $k$ full slices. $$\forall k \in \mathbb{N}:\ \operatorname{sl}(16k) = [16]^k$$ -/
theorem frameDurs_mul16 (k : Nat) : frameDurs (16 * (k : Rat)) = List.replicate k 16 := by
  have h0 : (0 : Rat) ≤ k := by exact_mod_cast Nat.zero_le k
  have hmax : max 0 (16 * (k : Rat)) = 16 * k := by grind
  have hs : slices (16 * (k : Rat)) = k := by
    unfold slices
    rw [hmax, show 16 * (k : Rat) / 16 = ((k : Int) : Rat) by push_cast; grind,
      show -((k : Int) : Rat) = ((-(k : Int) : Int) : Rat) by push_cast; rfl, Rat.floor_intCast]
    simp
  rw [frameDurs, hs, hmax, loopDurs_mul16]

/-- **Whole multiples of 16 ms split freely.** Frames of $16k_1, \ldots, 16k_m$ ms leave the spring where
$k_1 + \cdots + k_m$ frames of 16 ms leave it.

$$\forall s,\ \forall x^\ast,\ \forall [k_1, \ldots, k_m] \in \mathbb{N}^{*}:\ \operatorname{roll}(s, x^\ast, [16k_1, \ldots, 16k_m]) = \operatorname{run}(s, x^\ast, [16]^{k_1 + \cdots + k_m})$$

Frame gaps that are whole multiples of 16 ms (62.5 Hz, 31.25 Hz, or any mix) leave the spring in the state of the
same number of 16 ms frames; 60 Hz (50/3 ms) does not (see #guard). -/
theorem rollFrames_mul16 (s : Spring) (target : Rat) (ks : List Nat) :
    rollFrames s target (ks.map fun (k : Nat) => 16 * (k : Rat)) = runSlices s target (List.replicate ks.sum 16) := by
  rw [rollFrames_eq_run]
  congr 1
  induction ks with
  | nil => rfl
  | cons k ks ih => rw [List.map_cons, List.flatMap_cons, ih, frameDurs_mul16, List.sum_cons, List.replicate_append_replicate]

/-- Whether no frame of the list settles the spring.

$$\operatorname{live}(s, x^\ast, [\,]) = \top,\quad \operatorname{live}(s, x^\ast, \mathit{dt} :: \mathit{dts}) = \lnot\operatorname{step}(s, x^\ast, \mathit{dt}).\mathit{done} \land \operatorname{live}(\operatorname{step}(s, x^\ast, \mathit{dt}).s, x^\ast, \mathit{dts})$$ -/
def live : Spring → Rat → List Rat → Bool
  | _, _, [] => true
  | s, target, dt :: dts => !(springStep s target dt).done && live (springStep s target dt).state target dts

/-- The spring after a list of frames as the original runs it (settle test every frame).

$$\operatorname{steps}(s, x^\ast, [\,]) = s,\quad \operatorname{steps}(s, x^\ast, \mathit{dt} :: \mathit{dts}) = \operatorname{steps}(\operatorname{step}(s, x^\ast, \mathit{dt}).s, x^\ast, \mathit{dts})$$ -/
def stepFrames (s : Spring) (target : Rat) (dts : List Rat) : Spring :=
  dts.foldl (fun s dt => (springStep s target dt).state) s

#guard rollFrames ⟨4, 0⟩ 3 [32] == rollFrames ⟨4, 0⟩ 3 [16, 16]
#guard rollFrames ⟨4, 0⟩ 3 [8, 8] != rollFrames ⟨4, 0⟩ 3 [16]
#guard rollFrames ⟨4, 0⟩ 3 [8, 24] != rollFrames ⟨4, 0⟩ 3 [16, 16]
#guard rollFrames ⟨4, 0⟩ 3 [50 / 3, 50 / 3] != rollFrames ⟨4, 0⟩ 3 [16, 16]
#guard live ⟨4, 0⟩ 3 [16, 16, 16] && !live ⟨3, 0⟩ 3 [16] && live ⟨4, 0⟩ 3 []
#guard stepFrames ⟨4, 0⟩ 3 [16, 32] == rollFrames ⟨4, 0⟩ 3 [16, 16, 16]

/-- A frame that does not settle returns the loop's state. $$\forall s, x^\ast, \mathit{dt}:\ \lnot\operatorname{step}(s, x^\ast, \mathit{dt}).\mathit{done} \Rightarrow \operatorname{step}(s, x^\ast, \mathit{dt}).s = \operatorname{loop}(\operatorname{slices}(\mathit{dt}), s, x^\ast, \max(0, \mathit{dt}))$$ -/
theorem springStep_live (s : Spring) (target dt : Rat) (h : (springStep s target dt).done = false) :
    (springStep s target dt).state = springLoop (slices dt) s target (max 0 dt) := by
  unfold springStep at *
  dsimp only at h ⊢
  split <;> simp_all

/-- **The partition theorem for the original's loop.** While no frame settles, the original's per-frame steps
integrate exactly the concatenated slices.

$$\forall s,\ \forall x^\ast,\ \forall \mathit{dts}:\ \operatorname{live}(s, x^\ast, \mathit{dts}) \Rightarrow \operatorname{steps}(s, x^\ast, \mathit{dts}) = \operatorname{run}\big(s, x^\ast, \operatorname{sl}(\mathit{dt}_1) \mathbin{+\!\!+} \cdots \mathbin{+\!\!+} \operatorname{sl}(\mathit{dt}_n)\big)$$ -/
theorem stepFrames_eq_run (s : Spring) (target : Rat) (dts : List Rat) (h : live s target dts = true) :
    stepFrames s target dts = runSlices s target (dts.flatMap frameDurs) := by
  rw [← rollFrames_eq_run]
  induction dts generalizing s with
  | nil => rfl
  | cons dt dts ih =>
    simp only [live, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
    have e := springStep_live s target dt h.1
    simp only [stepFrames, rollFrames, List.foldl_cons] at ih ⊢
    rw [← e]
    exact ih _ h.2

/-! ## A drifting interval skips a second (ledger n=8)

`setInterval(1000)` fires late by a drift $d_i \ge \delta > 0$ on every tick. The fire times then gain at least
1000 ms more than $n$ whole seconds after $n \ge 1000/\delta$ ticks, so the shown seconds must drop by 2 on some
tick: a digit is skipped. An aimed timeout chain re-aims at each second boundary and shows every second, so the two
arms are not visually equal (the variant is the faithful one), while their work is the same
(`Fw.Parts.HeroCountdownOpt.same_run_noClaim`). -/

/-- One tick moves the ceiling-seconds count by 1 or 2 when the step is in $[1000, 2000)$ ms.

$$\forall x, D \in \mathbb{Z}:\ 1000 \le D < 2000 \Rightarrow \Big\lfloor \tfrac{x + D + 999}{1000} \Big\rfloor - \Big\lfloor \tfrac{x + 999}{1000} \Big\rfloor \in \{1, 2\}$$

A step of one to two seconds crosses one or two second boundaries. -/
private theorem step_drop (x D : Int) (h1 : 1000 ≤ D) (h2 : D < 2000) :
    (x + D + 999) / 1000 - (x + 999) / 1000 = 1 ∨ (x + D + 999) / 1000 - (x + 999) / 1000 = 2 := by
  omega

/-- **drift_skips.** If every tick fires $1000 + d_i$ ms after the previous with $\delta \le d_i < 1000$, $\delta > 0$,
and $n \delta \ge 1000$ with the $n$-th tick not after the target, some tick among the first $n$ drops the shown
seconds by 2.

$$\forall t, d : \mathbb{N} \to \mathbb{Z},\ \forall \delta, T \in \mathbb{Z},\ \forall n \in \mathbb{N}:\ \big(\forall i:\ t_{i+1} = t_i + 1000 + d_i \land \delta \le d_i < 1000\big) \land \delta > 0 \land n\delta \ge 1000 \land t_n \le T \Rightarrow \exists i < n:\ \operatorname{remainingSeconds}(t_i, T) = \operatorname{remainingSeconds}(t_{i+1}, T) + 2$$

Drift accumulates until one tick crosses two second boundaries. -/
theorem drift_skips (t d : Nat → Int) (δ T : Int) (n : Nat) (ht : ∀ i, t (i + 1) = t i + 1000 + d i)
    (hd : ∀ i, δ ≤ d i ∧ d i < 1000) (hδ : 0 < δ) (hn : 1000 ≤ (n : Int) * δ) (hT : t n ≤ T) :
    ∃ i, i < n ∧ remainingSeconds (t i) T = remainingSeconds (t (i + 1)) T + 2 := by
  -- the fire times only grow, so every tick up to `n` is before the target
  have hmono : ∀ i k, t i ≤ t (i + k) := by
    intro i k
    induction k with
    | zero => exact Int.le_refl _
    | succ k ih => have := ht (i + k); have := hd (i + k); rw [← Nat.add_assoc]; omega
  -- the elapsed time after `k` ticks is at least `1000 k + k δ`
  have hgrow : ∀ k, t 0 + 1000 * k + k * δ ≤ t k := by
    intro k
    induction k with
    | zero => simp
    | succ k ih =>
      have := ht k; have := hd k
      push_cast
      rw [Int.add_mul, Int.one_mul]
      omega
  -- if no tick dropped by 2, the count dropped by at most `k` after `k ≤ n` ticks
  apply Classical.byContradiction
  intro hno
  have hle : ∀ k, k ≤ n → (T - t 0 + 999) / 1000 ≤ (T - t k + 999) / 1000 + k := by
    intro k
    induction k with
    | zero => intro _; simp
    | succ k ih =>
      intro hk
      have h1 := ih (by omega)
      have hx : 0 ≤ T - t (k + 1) := by
        have := hmono (k + 1) (n - (k + 1)); rw [show k + 1 + (n - (k + 1)) = n by omega] at this; omega
      have hs := step_drop (T - t (k + 1)) (d k + 1000) (by have := hd k; omega) (by have := hd k; omega)
      have hne : ¬ remainingSeconds (t k) T = remainingSeconds (t (k + 1)) T + 2 := fun h => hno ⟨k, by omega, h⟩
      have htk := ht k
      have e1 : T - t (k + 1) + (d k + 1000) = T - t k := by omega
      rw [e1] at hs
      simp only [remainingSeconds] at hne
      omega
  have h1 := hle n (Nat.le_refl _)
  have h2 := hgrow n
  have hx : 0 ≤ T - t n := by omega
  omega

end Fw.Parts.HeroCountdown
