import Fw.Spec.Frames
import Fw.Spec.Cost
/-!
# Study set A: from a math statement to Lean (foundations, levels 1-5)

A companion to the lessons "math to Lean, set A". Each section re-states one real declaration of
the sketch (`research/kickoff/05-lean-sketch/Fw/Spec/*.lean`) with `#check` / `#eval` lines you can
run, then proves the answer of the lesson's exercise. No `sorry`, no Mathlib.

Run it from `research/kickoff/05-lean-sketch`:

    lake build Fw && lake env lean ../12-math-to-lean/StudyA.lean

In VS Code, hover any name or put the cursor after a `#check` / `#eval` to see its output in the
Lean Infoview.
-/

open Fw.Frames Fw.Cost

namespace StudyA

/-! ## Lesson 1 (level 1): a definition is a function

`Fw/Spec/Frames.lean:20`:  `def tick (dt : Nat) : Nat := (dt * 240 + 1000000) / 2000000`

$$\operatorname{tick}(dt) = \left\lfloor \frac{240\,dt + 10^{6}}{2 \cdot 10^{6}} \right\rfloor$$
-/

#check @tick            -- tick : Nat → Nat   (a function from ℕ to ℕ)
#print tick             -- shows the body: fun dt => (dt * 240 + 1000000) / 2000000
#eval tick 4166         -- 0
#eval tick 4167         -- 1
#eval tick 37500        -- 5
#eval (7 : Nat) / 2     -- 3   : `/` on Nat is floor division, so ⌊·⌋ is free
#eval (7 : Nat) / 0     -- 0   : division by zero is defined, and it is 0

/-- Exercise 1 answer: rounding $n/2$ half up, $\operatorname{roundHalf}(n) = \lfloor (n+1)/2 \rfloor$.

$$\forall n \in \mathbb{N}:\quad \operatorname{roundHalf}(n) = \left\lfloor \frac{n + 1}{2} \right\rfloor$$

Halve a natural number, rounding halves up. -/
def roundHalf (n : Nat) : Nat := (n + 1) / 2

#guard roundHalf 0 == 0 && roundHalf 1 == 1 && roundHalf 2 == 1 && roundHalf 3 == 2

/-- Floor division really floors: $\lfloor 7/2 \rfloor = 3$, and $7/0 = 0$ in Lean's $\mathbb{N}$.

$$\lfloor 7/2 \rfloor = 3 \ \land\ 7 / 0 = 0$$

Nat division rounds down and dividing by zero gives zero. -/
theorem nat_div_facts : (7 : Nat) / 2 = 3 ∧ (7 : Nat) / 0 = 0 := by decide

/-! ## Lesson 2 (level 2): "for all a, b: a ≤ b implies ..."

`Fw/Spec/Frames.lean:46-47`:

    theorem tick_mono {a b : Nat} (h : a ≤ b) : tick a ≤ tick b := by
      unfold tick; exact Nat.div_le_div_right (by omega)

$$\forall a, b \in \mathbb{N}:\quad a \le b \;\Rightarrow\; \operatorname{tick}(a) \le \operatorname{tick}(b)$$
-/

#check @tick_mono       -- ∀ {a b : Nat}, a ≤ b → tick a ≤ tick b
#check @Nat.div_le_div_right   -- the library lemma: a ≤ b → a / c ≤ b / c

-- Using the theorem: `a`, `b` are implicit, Lean reads them off the proof of `37500 ≤ 54167`.
example : tick 37500 ≤ tick 54167 := tick_mono (by decide)

/-- Exercise 2 answer, form A: arguments explicit, hypothesis as an arrow.

$$\forall a, b \in \mathbb{N}:\quad a \le b \Rightarrow 2a \le 2b$$

Doubling preserves order. -/
theorem double_mono_A (a b : Nat) : a ≤ b → 2 * a ≤ 2 * b := by
  intro h
  omega

/-- Exercise 2 answer, form B: arguments implicit, hypothesis named `h` before the colon.

$$\forall a, b \in \mathbb{N}:\quad a \le b \Rightarrow 2a \le 2b$$

Doubling preserves order (same statement as form A, different packaging). -/
theorem double_mono_B {a b : Nat} (h : a ≤ b) : 2 * a ≤ 2 * b := by
  omega

-- The two forms prove each other: they are the same mathematical statement.
example : (∀ a b : Nat, a ≤ b → 2 * a ≤ 2 * b) := fun a b h => double_mono_B (a := a) (b := b) h
example {a b : Nat} (h : a ≤ b) : 2 * a ≤ 2 * b := double_mono_A a b h

/-- Exercise 2, the wrong form C uses $\land$ instead of $\Rightarrow$ and is false (take $a = 1$, $b = 0$).

$$\neg\big(\forall a, b \in \mathbb{N}:\ a \le b \ \land\ 2a \le 2b\big)$$

"For all a, b: a ≤ b and 2a ≤ 2b" fails already at a = 1, b = 0. -/
theorem double_wrong_C : ¬ (∀ a b : Nat, a ≤ b ∧ 2 * a ≤ 2 * b) := by
  intro h
  have := (h 1 0).1
  omega

/-- The trap of lesson 2: the strict version is false, because rounding merges nearby frames
($0 < 4166$ but $\operatorname{tick}(0) = \operatorname{tick}(4166) = 0$).

$$\neg\big(\forall a, b \in \mathbb{N}:\ a < b \Rightarrow \operatorname{tick}(a) < \operatorname{tick}(b)\big)$$

tick is monotone but not strictly monotone. -/
theorem tick_not_strict_mono : ¬ (∀ a b : Nat, a < b → tick a < tick b) :=
  fun h => absurd (h 0 4166 (by decide)) (by decide)

/-! ## Lesson 3 (level 3): "if and only if"

`Fw/Spec/Frames.lean:31-32`:

    theorem tick_ge5_iff (dt : Nat) : 5 ≤ tick dt ↔ 37500 ≤ dt := by
      unfold tick; constructor <;> intro h <;> omega

$$\forall dt \in \mathbb{N}:\quad 5 \le \operatorname{tick}(dt) \iff 37\,500 \le dt$$
-/

#check @tick_ge5_iff    -- ∀ (dt : Nat), 5 ≤ tick dt ↔ 37500 ≤ dt
#check (tick_ge5_iff 40000).mp   -- 5 ≤ tick 40000 → 37500 ≤ 40000   (the ⇒ half)
#check (tick_ge5_iff 40000).mpr  -- 37500 ≤ 40000 → 5 ≤ tick 40000   (the ⇐ half)
#eval (tick 37499, tick 37500)   -- (4, 5): the boundary sits exactly at 37 500
#eval 37_500 == 37500            -- true: `_` digit separators are allowed in literals

-- Using the ⇐ half: 37 500 ≤ 40 000, hence 5 ≤ tick 40 000.
example : 5 ≤ tick 40000 := (tick_ge5_iff 40000).mpr (by decide)

/-- Exercise 3 answer: $\forall n \in \mathbb{N}:\ 2 \le \lfloor n/3 \rfloor \iff 6 \le n$.

$$\forall n \in \mathbb{N}:\quad 2 \le \left\lfloor \frac{n}{3} \right\rfloor \iff 6 \le n$$

A third of n, rounded down, is at least 2 exactly when n is at least 6. -/
theorem third_ge2_iff (n : Nat) : 2 ≤ n / 3 ↔ 6 ≤ n := by
  constructor <;> intro h <;> omega

/-! ## Lesson 4 (level 3): a count as a sum, without `Finset`

`Fw/Spec/Frames.lean:55`:

    def countAbove (t : Nat) (xs : List Nat) : Nat := (xs.filter (fun x => decide (t < x))).length

$$\operatorname{countAbove}(t, xs) = \#\{\, i : x_i > t \,\} = \sum_{i=1}^{n} [\,x_i > t\,]$$
-/

#check @countAbove                    -- Nat → List Nat → Nat
#eval countAbove 10 [11, 11, 10, 5]   -- 2  (repeats count; 10 is not > 10)
#eval [11, 11, 10, 5].filter (fun x => decide (10 < x))   -- [11, 11]
#eval ([11, 11, 10, 5].map (fun x => if 10 < x then 1 else 0)).sum   -- 2 : the Σ form

/-- The filter-length form equals the literal sum of Iverson brackets
$\sum_i [x_i > t]$ (the second form in the docstring of `countAbove`).

$$\forall t \in \mathbb{N},\ \forall xs = [x_1, \dots, x_n] \in \mathbb{N}^{*}:\quad \operatorname{countAbove}(t, xs) = \sum_{i=1}^{n} [\,x_i > t\,]$$

Counting the frames above t is the same as adding 1 for each frame above t and 0 otherwise. -/
theorem countAbove_eq_sum (t : Nat) (xs : List Nat) :
    countAbove t xs = (xs.map (fun x => if t < x then 1 else 0)).sum := by
  induction xs with
  | nil => simp [countAbove]
  | cons x xs ih =>
    simp only [countAbove] at ih
    by_cases h : t < x
    · simp [countAbove, h, ih]; omega
    · simp [countAbove, h, ih]

/-- Exercise 4 answer: $\operatorname{countAtMost}(t, xs) = \#\{\, i : x_i \le t \,\}$.

$$\forall t \in \mathbb{N},\ \forall xs = [x_1, \dots, x_n] \in \mathbb{N}^{*}:\quad \operatorname{countAtMost}(t, xs) = \#\{\, i : x_i \le t \,\}$$

The number of frames of at most t µs, repeats counted. -/
def countAtMost (t : Nat) (xs : List Nat) : Nat := (xs.filter (fun x => decide (x ≤ t))).length

#guard countAtMost 10 [11, 11, 10, 5] == 2
#guard countAtMost 0 [] == 0

/-- Exercise 4, check: every frame is either above $t$ or at most $t$.

$$\forall t \in \mathbb{N},\ \forall xs \in \mathbb{N}^{*}:\quad \operatorname{countAbove}(t, xs) + \operatorname{countAtMost}(t, xs) = |xs|$$

The two counts split the list. -/
theorem countAbove_add_countAtMost (t : Nat) (xs : List Nat) :
    countAbove t xs + countAtMost t xs = xs.length := by
  induction xs with
  | nil => simp [countAbove, countAtMost]
  | cons x xs ih =>
    simp only [countAbove, countAtMost] at ih ⊢
    by_cases h : t < x
    · have h' : ¬ x ≤ t := by omega
      simp [h, h']; omega
    · have h' : x ≤ t := by omega
      simp [h, h']; omega

/-! ## Lesson 5 (level 4): `Bool` (computed) versus `Prop` (stated)

`Fw/Spec/Cost.lean:89` defines the test as a `Bool`:

    def onTime (u : UnitCost) (budgetUs : Nat) (w : Work) : Bool := decide (mainUs u w ≤ budgetUs)

`Fw/Spec/Cost.lean:99-102`:

    theorem onTime_of_le (u : UnitCost) (budgetUs : Nat) {a b : Work} (h : a.le b)
        (hb : onTime u budgetUs b = true) : onTime u budgetUs a = true := by
      simp only [onTime, decide_eq_true_eq] at *
      exact Nat.le_trans (mainUs_mono u h) hb

$$\forall u, B, a, b:\quad a \preceq b \ \land\ \operatorname{onTime}(u, B, b) \;\Rightarrow\; \operatorname{onTime}(u, B, a)$$
-/

#check @onTime_of_le
#check (decide (3 ≤ 5) : Bool)          -- a Bool you can compute
#check (3 ≤ 5 : Prop)                   -- a Prop you prove
#check @decide_eq_true_eq               -- (decide p = true) = p : the bridge
#eval onTime ⟨1, 1, 1⟩ 10 ⟨4, 2, 2, 2⟩  -- true  (4 + 2 + 2 + 2 = 10 ≤ 10)
#eval onTime ⟨1, 1, 1⟩ 9 ⟨4, 2, 2, 2⟩   -- false (10 > 9)
#print Work.le                          -- the ∧ of four ≤ (a Prop, not a Bool)

-- A `Work.le` hypothesis is a 4-fold ∧; build one with ⟨_, _, _, _⟩.
example : Work.le ⟨1, 1, 1, 1⟩ ⟨4, 2, 2, 2⟩ := ⟨by decide, by decide, by decide, by decide⟩

-- The theorem used on concrete data: the smaller work fits because the bigger one does.
example : onTime ⟨1, 1, 1⟩ 10 ⟨1, 1, 1, 1⟩ = true :=
  onTime_of_le ⟨1, 1, 1⟩ 10 (b := ⟨4, 2, 2, 2⟩) ⟨by decide, by decide, by decide, by decide⟩ rfl

/-- Exercise 5 answer: a Bool budget test on one number.

$$\forall n, B \in \mathbb{N}:\quad \operatorname{fits}(n, B) = \mathrm{true} \iff n \le B$$

Return true when n is at most the budget B. -/
def fits (n B : Nat) : Bool := decide (n ≤ B)

#guard fits 10 10 && !fits 11 10

/-- Exercise 5 answer, the bridge: the Bool test means the Prop.

$$\forall n, B \in \mathbb{N}:\quad \operatorname{fits}(n, B) = \mathrm{true} \iff n \le B$$

The computed test is true exactly when the inequality holds. -/
theorem fits_iff (n B : Nat) : fits n B = true ↔ n ≤ B := by
  simp [fits]

-- Exercise 5, the three candidate statements as Lean elaborates them:
-- (A) a Bool used where a Prop is expected is coerced to `_ = true`, so A *is* B.
theorem fits_iff_A (n B : Nat) : fits n B ↔ n ≤ B := by simp [fits]
#check @fits_iff_A   -- ∀ (n B : Nat), fits n B = true ↔ n ≤ B
-- (C) `= True` (capital T, the Prop) gets a double coercion: true, but not what was meant.
theorem fits_iff_C (n B : Nat) : fits n B = True ↔ n ≤ B := by simp [fits]
#check @fits_iff_C   -- ∀ (n B : Nat), (fits n B = true) = True ↔ n ≤ B

/-! ## Lesson 6 (level 5): truncated subtraction on ℕ

`Fw/Spec/Frames.lean:102-113`, `countAbove34_sub_tick5`:

$$\operatorname{countAbove}(34\,000, xs) \mathbin{\dot-} \#\{\, i : 5 \le \operatorname{tick}(x_i) \,\} = \#\{\, i : 34\,000 < x_i \le 37\,499 \,\}$$
-/

#check @countAbove34_sub_tick5
#eval (3 : Nat) - 5          -- 0, not -2: Nat subtraction stops at 0 ("monus", ∸)
#eval (3 : Int) - 5          -- -2: Int subtraction is the usual one
-- A concrete run: frames of 30, 35, 36, 38 and 60 ms (in µs).
#eval countAbove 34000 [30000, 35000, 36000, 38000, 60000]                    -- 4
#eval ([30000, 35000, 36000, 38000, 60000].filter (5 ≤ tick ·)).length        -- 2
#eval ([30000, 35000, 36000, 38000, 60000].filter
        (fun x => 34000 < x ∧ x ≤ 37499)).length                              -- 2 = 4 - 2

-- The theorem on that run (Lean evaluates both sides).
example : countAbove 34000 [30000, 35000, 36000, 38000, 60000]
      - ([30000, 35000, 36000, 38000, 60000].filter (5 ≤ tick ·)).length
    = ([30000, 35000, 36000, 38000, 60000].filter (fun x => 34000 < x ∧ x ≤ 37499)).length :=
  countAbove34_sub_tick5 _

/-- Exercise 6 answer, part 1: "$(a - b) + b = a$" is false on $\mathbb{N}$ in Lean, e.g. $a = 0$, $b = 1$.

$$(0 \mathbin{\dot-} 1) + 1 \ne 0$$

With truncated subtraction, subtracting then adding back can overshoot. -/
theorem sub_add_counterexample : (0 : Nat) - 1 + 1 ≠ 0 := by decide

/-- Exercise 6 answer, part 2: the repaired statement needs the hypothesis $b \le a$.

$$\forall a, b \in \mathbb{N}:\quad b \le a \;\Rightarrow\; (a \mathbin{\dot-} b) + b = a$$

Subtracting b and adding it back returns a whenever b is at most a. -/
theorem sub_add_of_le {a b : Nat} (h : b ≤ a) : a - b + b = a := by
  omega

/-- Exercise 6, the same statement in $\mathbb{Z}$ needs no hypothesis.

$$\forall a, b \in \mathbb{Z}:\quad (a - b) + b = a$$

In the integers subtraction never truncates. -/
theorem int_sub_add (a b : Int) : a - b + b = a := by
  omega

end StudyA

-- Only the standard axioms (propext, Classical.choice, Quot.sound) may appear here.
#print axioms StudyA.countAbove_eq_sum
#print axioms StudyA.countAbove_add_countAtMost
#print axioms StudyA.fits_iff
#print axioms StudyA.sub_add_of_le
#print axioms StudyA.double_wrong_C
