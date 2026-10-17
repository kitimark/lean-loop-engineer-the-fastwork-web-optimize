import Fw.Gate.Rule
/-!
# Value comparisons of the breakpoint gate (PLAN 6.6, PL1 and PL2)

Port of `styleValueEq`, `boxEq`, `countStatus`, `styleStatus` and `boxStatus` from
`packages/gate-breakpoints/src/verdict.mjs`.

* A computed-style value is compared as a string first; failing that, every number in it is
  replaced by a hole (`#`) and the two skeletons must be equal, with the same count of numbers and
  each pair within $10^{-3}$ (PL2). The numbers are the matches of the JS regex
  `-?(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?` (flags `gi`), scanned left to right (`scan`); their values are
  exact decimals (`Dec.val`), so the tolerance is exact, where the JS code compared doubles.
* A box dimension (CSS px) is equal within $\tfrac12$ (PL1), exactly.
* An element count is `missing` when both arms have none.

A value that is absent on either arm (`none`) is never equal: its status is `missing`.
-/
namespace Fw.Gate

/-! ## Numbers inside a computed-style value -/

/-- A number token: sign, decimal mantissa and power of ten, as JS `Number` reads the matched text.

$$\operatorname{val}(n, m, e) = (-1)^{n} \cdot m \cdot 10^{e} \in \mathbb Q, \qquad n \in \mathbb B,\ m \in \mathbb N,\ e \in \mathbb Z$$

The exact value of one number found in a style value. -/
structure Dec where
  neg : Bool
  mant : Nat
  exp : Int
  deriving DecidableEq, Repr, Inhabited

/-- Exact powers of ten with an integer exponent.

$$\operatorname{pow10}(e) = 10^{e} \in \mathbb Q \quad (e \in \mathbb Z)$$

Ten to an integer power, as a fraction. -/
def pow10 (e : Int) : Rat :=
  if 0 ≤ e then ((10 ^ e.toNat : Nat) : Rat) else 1 / ((10 ^ (-e).toNat : Nat) : Rat)

/-- The exact value of a number token.

$$\operatorname{val}(n, m, e) = (-1)^{n} \cdot m \cdot 10^{e}$$

What the token's text denotes. -/
def Dec.val (d : Dec) : Rat :=
  (if d.neg then -(d.mant : Rat) else (d.mant : Rat)) * pow10 d.exp

/-- Split off the longest prefix of ASCII digits (`\d` without the `u` flag is `[0-9]`).

$$\operatorname{takeDigits}(cs) = (p, r), \quad cs = p \mathbin{+\!\!+} r,\ p \in [0\text{-}9]^*,\ r = [\,] \vee \operatorname{head}(r) \notin [0\text{-}9]$$

The greedy `\d*` of the regex. -/
def takeDigits : List Char → List Char × List Char
  | c :: cs => if c.isDigit then ((c :: (takeDigits cs).1), (takeDigits cs).2) else ([], c :: cs)
  | [] => ([], [])

/-- The natural number written by a list of decimal digits.

$$\operatorname{digitsVal}(c_1 \dots c_k) = \sum_{i=1}^{k} (\operatorname{code}(c_i) \mathbin{\dot-} \operatorname{code}(\texttt{0})) \cdot 10^{k-i}$$

with truncated subtraction $\dot-$ on character codes, for any characters; for decimal digits this is the digit value.
Digits to their value. -/
def digitsVal (ds : List Char) : Nat :=
  ds.foldl (fun n c => 10 * n + (c.toNat - '0'.toNat)) 0

/-- The optional sign of an exponent: whether it is `-`, and the rest.

$$\operatorname{signSplit}(cs) = \begin{cases} (1, r) & cs = \texttt{-}\,r \\ (0, r) & cs = \texttt{+}\,r \\ (0, cs) & \text{otherwise} \end{cases}$$

The `[+-]?` of the exponent. -/
def signSplit : List Char → Bool × List Char
  | '+' :: r => (false, r)
  | '-' :: r => (true, r)
  | r => (false, r)

/-- The sign never lengthens the input.

$$\forall cs,\quad |\operatorname{signSplit}(cs).r| \le |cs|$$

Reading a sign never moves backwards. -/
theorem signSplit_len (cs : List Char) : (signSplit cs).2.length ≤ cs.length := by
  unfold signSplit; split <;> simp

/-- The optional exponent `(?:e[+-]?\d+)` (the `i` flag also allows `E`): its value and the rest.

$$\operatorname{expPart}(cs) = \begin{cases} ((-1)^{\sigma} \cdot \operatorname{digitsVal}(d),\ r) & cs = c :: cs',\ c \in \{\texttt{e}, \texttt{E}\},\ (\sigma, u) = \operatorname{signSplit}(cs'),\ (d, r) = \operatorname{takeDigits}(u),\ d \ne [\,] \\ \bot & \text{otherwise} \end{cases}$$

(the sign is optional and the digit run is maximal). An exponent is taken only when at least one digit follows the `e` and its sign. -/
def expPart : List Char → Option (Int × List Char)
  | c :: rest =>
    if c = 'e' ∨ c = 'E' then
      let sr := signSplit rest
      let ds := (takeDigits sr.2).1
      if ds.isEmpty then none
      else some (if sr.1 then -(digitsVal ds : Int) else (digitsVal ds : Int), (takeDigits sr.2).2)
    else none
  | [] => none

/-- `takeDigits` splits its input.

$$\forall cs,\quad |\operatorname{takeDigits}(cs).p| + |\operatorname{takeDigits}(cs).r| = |cs|$$

The digits and the rest together are the input. -/
theorem takeDigits_len (cs : List Char) :
    (takeDigits cs).1.length + (takeDigits cs).2.length = cs.length := by
  induction cs with
  | nil => rfl
  | cons c cs ih =>
    unfold takeDigits
    split <;> simp_all <;> omega

/-- An exponent consumes at least its `e`.

$$\forall cs,\ x,\ r,\quad \operatorname{expPart}(cs) = (x, r) \implies |r| < |cs|$$

Reading an exponent always moves forward. -/
theorem expPart_lt {cs : List Char} {x : Int} {r : List Char} (h : expPart cs = some (x, r)) :
    r.length < cs.length := by
  match cs with
  | [] => simp [expPart] at h
  | c :: rest =>
    simp only [expPart] at h
    by_cases he : c = 'e' ∨ c = 'E'
    · simp only [he, ite_true] at h
      by_cases hd : (takeDigits (signSplit rest).2).1.isEmpty = true
      · simp [hd] at h
      · simp only [hd, Bool.false_eq_true, ite_false, Option.some.injEq, Prod.mk.injEq] at h
        obtain ⟨-, rfl⟩ := h
        have h1 := takeDigits_len (signSplit rest).2
        have h2 := signSplit_len rest
        simp only [List.length_cons]
        omega
    · simp [he] at h

/-- Attach the optional exponent to a mantissa read so far.

$$\operatorname{withExp}(m, e, r) = \begin{cases} (m, e + x, r') & \operatorname{expPart}(r) = (x, r') \\ (m, e, r) & \text{otherwise} \end{cases}$$

The exponent group is greedy but optional. -/
def withExp (p : Nat × Int × List Char) : Nat × Int × List Char :=
  match expPart p.2.2 with
  | some (x, r') => (p.1, p.2.1 + x, r')
  | none => p

/-- An unsigned number `(?:\d+\.?\d*|\.\d+)(?:e[+-]?\d+)?` at the start of the input: mantissa,
power of ten and the rest of the input.

$$\operatorname{unsigned}(cs) = \begin{cases} \operatorname{withExp}(\operatorname{digitsVal}(d_1 \mathbin{+\!\!+} d_2), -|d_2|, r) & r_1 = \texttt{.} :: r_2,\ (d_2, r) = \operatorname{takeDigits}(r_2),\ d_1 \mathbin{+\!\!+} d_2 \ne [\,] \\ \bot & r_1 = \texttt{.} :: r_2,\ d_1 = [\,],\ (d_2, r) = \operatorname{takeDigits}(r_2),\ d_2 = [\,] \\ \operatorname{withExp}(\operatorname{digitsVal}(d_1), 0, r_1) & \operatorname{head}(r_1) \ne \texttt{.}\ (\text{or } r_1 = [\,]),\ d_1 \ne [\,] \\ \bot & \text{otherwise} \end{cases}$$

where $(d_1, r_1) = \operatorname{takeDigits}(cs)$ (both digit runs are maximal). Digits with an optional dot and fraction, or a dot with at least one digit. -/
def unsignedNum (cs : List Char) : Option (Nat × Int × List Char) :=
  let d1 := (takeDigits cs).1
  let r1 := (takeDigits cs).2
  let core : Option (Nat × Int × List Char) :=
    match r1 with
    | '.' :: r2 =>
      let d2 := (takeDigits r2).1
      if d1.isEmpty && d2.isEmpty then none
      else some (digitsVal (d1 ++ d2), -(d2.length : Int), (takeDigits r2).2)
    | _ => if d1.isEmpty then none else some (digitsVal d1, 0, r1)
  core.map withExp

/-- A number `-?(...)` at the start of the input. A `-` not followed by a number starts none.

$$\operatorname{numAt}(cs) = \begin{cases} ((1, m, e), r) & cs = \texttt{-} :: cs',\ \operatorname{unsigned}(cs') = (m, e, r) \\ ((0, m, e), r) & cs \ne \texttt{-} :: cs' \text{ for every } cs',\ \operatorname{unsigned}(cs) = (m, e, r) \\ \bot & \text{otherwise} \end{cases}$$

(the cases do not overlap; $cs = [\,]$ falls in the second or third). The regex's optional minus sign. -/
def numAt (cs : List Char) : Option (Dec × List Char) :=
  match cs with
  | '-' :: r => (unsignedNum r).map fun p => (⟨true, p.1, p.2.1⟩, p.2.2)
  | _ => (unsignedNum cs).map fun p => (⟨false, p.1, p.2.1⟩, p.2.2)

/-- The rest after an optional exponent is no longer than before.

$$\forall p = (m, e, r) \in \mathbb N \times \mathbb Z \times \mathrm{Char}^{*},\quad |\operatorname{withExp}(p).r| \le |r|$$

Attaching an exponent never moves backwards. -/
theorem withExp_len (p : Nat × Int × List Char) : (withExp p).2.2.length ≤ p.2.2.length := by
  unfold withExp
  split
  · rename_i x r' h
    have := expPart_lt h
    simp only
    omega
  · exact Nat.le_refl _

/-- Every number token consumes at least one character.

$$\forall cs,\ d,\ r,\quad \operatorname{numAt}(cs) = (d, r) \implies |r| < |cs|$$

So the left-to-right scan terminates. -/
theorem numAt_lt {cs : List Char} {d : Dec} {r : List Char} (h : numAt cs = some (d, r)) :
    r.length < cs.length := by
  have key : ∀ (xs : List Char) (p : Nat × Int × List Char), unsignedNum xs = some p →
      p.2.2.length < xs.length := by
    intro xs p hp
    unfold unsignedNum at hp
    simp only [Option.map_eq_some_iff] at hp
    obtain ⟨q, hq, rfl⟩ := hp
    have hl := takeDigits_len xs
    have hw := withExp_len q
    split at hq
    · rename_i r2 heq
      split at hq
      · cases hq
      · simp only [Option.some.injEq] at hq
        subst hq
        have := takeDigits_len r2
        rw [heq] at hl
        simp only [List.length_cons] at hl
        simp only at hw
        omega
    · split at hq
      · cases hq
      · rename_i hne
        simp only [Option.some.injEq] at hq
        subst hq
        simp only at hw
        have : (takeDigits xs).1.length ≠ 0 := by
          intro h0; exact hne (List.isEmpty_iff.mpr (List.length_eq_zero_iff.mp h0))
        omega
  unfold numAt at h
  split at h
  · rename_i r0
    simp only [Option.map_eq_some_iff] at h
    obtain ⟨p, hp, hpe⟩ := h
    simp only [Prod.mk.injEq] at hpe
    obtain ⟨-, rfl⟩ := hpe
    have := key r0 p hp
    simp only [List.length_cons]
    omega
  · simp only [Option.map_eq_some_iff] at h
    obtain ⟨p, hp, hpe⟩ := h
    simp only [Prod.mk.injEq] at hpe
    obtain ⟨-, rfl⟩ := hpe
    exact key cs p hp

/-- Left-to-right scan of a value: the skeleton (each number replaced by `#`) and the numbers, as
`String.replace(NUM, '#')` and `String.match(NUM)` do.

$$\operatorname{scan}(cs) = \begin{cases} ([\,], [\,]) & cs = [\,] \\ (\texttt{\#} :: s, d :: ns) & \operatorname{numAt}(cs) = (d, r),\ \operatorname{scan}(r) = (s, ns) \\ (c :: s, ns) & \operatorname{numAt}(cs) = \bot,\ cs = c :: cs',\ \operatorname{scan}(cs') = (s, ns) \end{cases}$$

Numbers are found where they start, longest first; other characters are kept. -/
def scan (cs : List Char) : List Char × List Dec :=
  match _h : numAt cs with
  | some (d, rest) => ('#' :: (scan rest).1, d :: (scan rest).2)
  | none =>
    match cs with
    | [] => ([], [])
    | c :: cs' => (c :: (scan cs').1, (scan cs').2)
termination_by cs.length
decreasing_by
  all_goals first
    | exact numAt_lt _h
    | simp

/-! ## The three comparisons -/

/-- Within a tolerance, both ways.

$$\operatorname{near}_t(x, y) \iff x - y \le t \wedge y - x \le t \iff |x - y| \le t$$

Two numbers at most `t` apart. -/
def near (t x y : Rat) : Bool := decide (x - y ≤ t) && decide (y - x ≤ t)

/-- The tolerance for numbers inside a computed-style value (PL2).

$$t_{\mathrm{style}} = 10^{-3}$$

Style numbers may differ by a thousandth. -/
def tolStyle : Rat := 1 / 1000

/-- The tolerance for box dimensions in CSS px (PL1).

$$t_{\mathrm{box}} = \tfrac12$$

Boxes may differ by half a CSS pixel. -/
def tolBox : Rat := 1 / 2

/-- Computed-style values are equal: the same string, or the same skeleton with as many numbers,
each pair within $10^{-3}$. Absent on either side is never equal.

$$\operatorname{styleEq}(a, b) \iff a, b \ne \bot \wedge \Bigl(a = b \ \vee\ \bigl(\operatorname{skel}(a) = \operatorname{skel}(b) \wedge |\operatorname{nums}(a)| = |\operatorname{nums}(b)| \wedge \forall i < |\operatorname{nums}(a)|,\ |\operatorname{val}(\operatorname{nums}(a)_i) - \operatorname{val}(\operatorname{nums}(b)_i)| \le 10^{-3}\bigr)\Bigr)$$

where $(\operatorname{skel}(s), \operatorname{nums}(s)) = \operatorname{scan}(\operatorname{chars}(s))$ for a present string $s$. Style values agree as text, up to a thousandth in each number. -/
def styleValueEq : Option String → Option String → Bool
  | some a, some b =>
    a == b ||
      (let sa := scan a.toList
       let sb := scan b.toList
       sa.1 == sb.1 && sa.2.length == sb.2.length &&
         (sa.2.zip sb.2).all fun p => near tolStyle p.1.val p.2.val)
  | _, _ => false

/-- Status of a compared computed-style value: `missing` if absent on either arm.

$$\operatorname{styleStatus}(a, b) = \begin{cases} \mathrm{missing} & a = \bot \vee b = \bot \\ \mathrm{equal} & \operatorname{styleEq}(a, b) \\ \mathrm{differ} & \text{otherwise} \end{cases}$$

A style item is equal, differs, or is missing on one side. -/
def styleStatus (a b : Option String) : Status :=
  match a, b with
  | some _, some _ => if styleValueEq a b then .equal else .differ
  | _, _ => .missing

/-- Status of a compared box dimension: `equal` within half a CSS px.

$$\operatorname{boxStatus}(a, b) = \begin{cases} \mathrm{missing} & a = \bot \vee b = \bot \\ \mathrm{equal} & |a - b| \le \tfrac12 \\ \mathrm{differ} & \text{otherwise} \end{cases}$$

A box item is equal within half a pixel. -/
def boxStatus (a b : Option Rat) : Status :=
  match a, b with
  | some x, some y => if near tolBox x y then .equal else .differ
  | _, _ => .missing

/-- Status of an element count: both zero means the anchor is absent from both arms.

$$\operatorname{countStatus}(a, b) = \begin{cases} \mathrm{missing} & a = 0 \wedge b = 0 \\ \mathrm{equal} & a = b \ne 0 \\ \mathrm{differ} & a \ne b \end{cases} \qquad (a, b \in \mathbb N)$$

Counts must be equal and positive. -/
def countStatus (a b : Nat) : Status :=
  if a = 0 ∧ b = 0 then .missing else if a = b then .equal else .differ

/-! ## Properties -/

/-- Boolean equality is symmetric for a lawful `==`.

$$\forall \alpha \text{ with a lawful } {==},\ \forall a, b \in \alpha,\quad (a == b) = (b == a)$$

A lawful `==` is true exactly on equal values. Equality tests do not care about order. -/
theorem beq_swap {α : Type} [BEq α] [LawfulBEq α] (a b : α) : (a == b) = (b == a) := by
  by_cases h : a = b
  · subst h; rfl
  · have h1 : (a == b) = false := by simpa using h
    have h2 : (b == a) = false := by simpa using Ne.symm h
    rw [h1, h2]

/-- `near` is symmetric.

$$\forall t, x, y \in \mathbb Q,\quad \operatorname{near}_t(x, y) = \operatorname{near}_t(y, x)$$

Closeness does not depend on which arm is first. -/
theorem near_comm (t x y : Rat) : near t x y = near t y x := by
  unfold near; rw [Bool.and_comm]

/-- Style equality is symmetric.

$$\forall a, b \in \mathrm{String}_\bot,\quad \operatorname{styleEq}(a, b) = \operatorname{styleEq}(b, a)$$

Swapping the original and the rewrite never changes a style comparison. -/
theorem styleValueEq_comm (a b : Option String) : styleValueEq a b = styleValueEq b a := by
  cases a <;> cases b <;> simp only [styleValueEq]
  rename_i x y
  have zs : ∀ (l1 l2 : List Dec),
      ((l1.zip l2).all fun p => near tolStyle p.1.val p.2.val) =
      ((l2.zip l1).all fun p => near tolStyle p.1.val p.2.val) := by
    intro l1 l2
    induction l1 generalizing l2 with
    | nil => cases l2 <;> rfl
    | cons h t ih =>
      cases l2 with
      | nil => rfl
      | cons h' t' => simp only [List.zip_cons_cons, List.all_cons, ih t', near_comm]
  rw [zs, beq_swap x y, beq_swap (scan x.toList).1, beq_swap (scan x.toList).2.length]

/-- A present value equals itself.

$$\forall s \in \mathrm{String},\quad \operatorname{styleEq}(s, s)$$

Identical computed values always pass. -/
theorem styleValueEq_refl (s : String) : styleValueEq (some s) (some s) = true := by
  simp [styleValueEq]

/-- Absent is never equal.

$$\forall b \in \mathrm{String}_\bot,\quad \neg\operatorname{styleEq}(\bot, b) \wedge \neg\operatorname{styleEq}(b, \bot)$$

A property missing on one arm never counts as equal. -/
theorem styleValueEq_none (b : Option String) :
    styleValueEq none b = false ∧ styleValueEq b none = false := by
  cases b <;> simp [styleValueEq]

/-- A box dimension is equal exactly when both are present and at most half a pixel apart.

$$\forall a, b \in \mathbb Q_\bot,\quad \operatorname{boxStatus}(a, b) = \mathrm{equal} \iff \exists x, y \in \mathbb Q,\ a = x \wedge b = y \wedge x - y \le \tfrac12 \wedge y - x \le \tfrac12$$

PL1: boxes agree within half a CSS pixel. -/
theorem boxStatus_equal_iff (a b : Option Rat) :
    boxStatus a b = .equal ↔ ∃ x y, a = some x ∧ b = some y ∧ x - y ≤ 1 / 2 ∧ y - x ≤ 1 / 2 := by
  constructor
  · intro h
    cases a <;> cases b <;> simp only [boxStatus] at h <;> try cases h
    rename_i x y
    refine ⟨x, y, rfl, rfl, ?_⟩
    unfold near tolBox at h
    split at h
    · rename_i hn
      simp only [Bool.and_eq_true, decide_eq_true_eq] at hn
      exact hn
    · cases h
  · rintro ⟨x, y, rfl, rfl, h1, h2⟩
    simp [boxStatus, near, tolBox, h1, h2]

/-- The three comparisons are symmetric.

$$\forall a, b \in \mathrm{String}_\bot,\ x, y \in \mathbb Q_\bot,\ m, n \in \mathbb N,\quad \operatorname{styleStatus}(a, b) = \operatorname{styleStatus}(b, a) \wedge \operatorname{boxStatus}(x, y) = \operatorname{boxStatus}(y, x) \wedge \operatorname{countStatus}(m, n) = \operatorname{countStatus}(n, m)$$

Neither arm is privileged. -/
theorem status_comm (a b : Option String) (x y : Option Rat) (m n : Nat) :
    styleStatus a b = styleStatus b a ∧ boxStatus x y = boxStatus y x ∧
      countStatus m n = countStatus n m := by
  refine ⟨?_, ?_, ?_⟩
  · cases a <;> cases b <;> simp only [styleStatus]
    rw [styleValueEq_comm]
  · cases x <;> cases y <;> simp only [boxStatus]
    rw [near_comm]
  · unfold countStatus
    by_cases h1 : m = 0 ∧ n = 0
    · have : n = 0 ∧ m = 0 := ⟨h1.2, h1.1⟩
      simp [h1]
    · have : ¬ (n = 0 ∧ m = 0) := fun h => h1 ⟨h.2, h.1⟩
      simp only [h1, this, ite_false]
      by_cases h : m = n
      · subst h; simp
      · simp [h, Ne.symm h]

/-- No comparison is ever `na`: every compared item takes part in its verdict.

$$\forall a, b, x, y, m, n,\quad \operatorname{styleStatus}(a, b) \ne \mathrm{na} \wedge \operatorname{boxStatus}(x, y) \ne \mathrm{na} \wedge \operatorname{countStatus}(m, n) \ne \mathrm{na}$$

Only information items and unachieved Lean checks are left out of a verdict. -/
theorem status_ne_na (a b : Option String) (x y : Option Rat) (m n : Nat) :
    styleStatus a b ≠ .na ∧ boxStatus x y ≠ .na ∧ countStatus m n ≠ .na := by
  refine ⟨?_, ?_, ?_⟩
  · cases a <;> cases b <;> simp only [styleStatus] <;> (try split) <;> decide
  · cases x <;> cases y <;> simp only [boxStatus] <;> (try split) <;> decide
  · unfold countStatus; split
    · decide
    · split <;> decide

#guard styleValueEq (some "120px") (some "120px")
#guard styleValueEq (some "120px") (some "120.0009px")
#guard !styleValueEq (some "120px") (some "120.002px")
#guard !styleValueEq (some "120px") (some "120em")
#guard styleValueEq (some "matrix(1, 0, 0, 1, -5, 0)") (some "matrix(1, 0, 0, 1, -5.0005, 0)")
#guard !styleValueEq (some "rgb(0, 0, 0)") (some "rgb(0, 0, 1)")
#guard !styleValueEq (some "auto") none
#guard !styleValueEq (some "auto") (some "0px")
-- exact decimals: 0.3 vs 0.301 is within 1e-3 (the JS doubles said 0.0010000000000000009 > 0.001)
#guard styleValueEq (some "0.3") (some "0.301")
-- exponents, a lone minus, a lone dot, and a dangling e
#guard styleValueEq (some "1e3px") (some "1000.0005px")
#guard (scan "a-b".toList).2.length == 0
#guard (scan "1.e5".toList).2.map Dec.val == [100000]
#guard (scan "-.5e-1x".toList) == ("#x".toList, [⟨true, 5, -2⟩])
#guard (scan "1e-.5".toList) == ("#e#".toList, [⟨false, 1, 0⟩, ⟨true, 5, -1⟩])
#guard (scan "#1".toList).1 == (scan "1#".toList).1
#guard !styleValueEq (some "#") (some "1")
#guard boxStatus (some 10) (some (21 / 2)) == .equal
#guard boxStatus (some 10) (some (1051 / 100)) == .differ
#guard boxStatus none (some 1) == .missing
#guard countStatus 4 4 == .equal
#guard countStatus 4 3 == .differ
#guard countStatus 0 0 == .missing
#guard styleStatus none (some "a") == .missing

end Fw.Gate
