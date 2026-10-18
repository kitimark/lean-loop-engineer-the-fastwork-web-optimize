/-!
# hero.accent: the hand-drawn word in the headline (P1, `faithful`)

Restated (not copied) from the original snapshot, read independently of the TS part:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 3501-3665 (`RE`): the visible words and their box widths in `em/64` (six after the `hidden` ones are filtered out),
    and the base word "you" (`LE`, width 106);
  * 3672-3678: the cursor step `u` (`-1` is the base word, then the six words, then back to `-1`);
  * 3679-3716 (the effect): a state machine on `setTimeout`: *idle* waits 2200 ms the very first time (cursor $<0$) and
    1250 ms afterwards, *draw-out* waits 900 ms and then steps the cursor, *draw-in* waits 900 ms and returns to idle;
    nothing runs under reduced motion; an `IntersectionObserver` (`rootMargin: 100% 0px`) pauses the chain while the
    word is more than a viewport away;
  * CSS `2.gBuqKVzi.css` 1221-1366: strokes draw for 0.9 s, the idle "boil" shows one of three frames, 0.6 s per loop
    with `step-end` (each frame for 0.2 s).

Times are `Nat` ms since mount (no pause); the pause only shifts the chain and is not modelled.
-/
namespace Fw.Parts.HeroAccent

/-! ## Constants -/

/-- First idle wait in ms (JS 3688). $$a_0 = 2200$$ -/
def firstWait : Nat := 2200

/-- Idle wait after the first one in ms (JS 3688). $$a = 1250$$ -/
def idleWait : Nat := 1250

/-- Draw-out and draw-in wait in ms (JS 3697, 3703). $$d = 900$$ -/
def drawWait : Nat := 900

/-- The number of visible words after the base word. $$n = 6$$ -/
def words : Nat := 6

/-- Box widths of the visible words in $\mathrm{em}/64$ (JS 3501-3665, `hidden` entries removed), in cursor order.

$$[112, 80, 96, 134, 161, 120]$$ -/
def wordWidths : List Nat := [112, 80, 96, 134, 161, 120]

/-- Width of the base word in $\mathrm{em}/64$ (JS 3667). $$w_{-1} = 106$$ -/
def baseWidth : Nat := 106

/-! ## The cursor -/

/-- The cursor step (JS 3672-3678).

$$u(c) = \begin{cases} 0 & c < 0 \\ -1 & c + 1 \ge n \\ c + 1 & \text{otherwise} \end{cases}$$

Base word, then the six words in order, then the base word again. -/
def next (c : Int) : Int := if c < 0 then 0 else if c + 1 ≥ (words : Int) then -1 else c + 1

/-- The cursor after $j$ steps. $$c_j = (j \bmod 7) - 1$$ Where the chain stands after $j$ words changed. -/
def cursorAfter (j : Nat) : Int := ((j % (words + 1) : Nat) : Int) - 1

/-- The cursor after $j + 1$ steps is the step of the cursor after $j$.

$$\forall j:\quad c_{j+1} = u(c_j)$$

The closed form is the iterated step. -/
theorem cursor_step (j : Nat) : cursorAfter (j + 1) = next (cursorAfter j) := by
  unfold cursorAfter next words
  split <;> (try split) <;> omega

/-- The cursor stays in $[-1, 5]$. $$\forall j:\ -1 \le c_j \le n - 1$$ -/
theorem cursor_mem (j : Nat) : -1 ≤ cursorAfter j ∧ cursorAfter j ≤ (words : Int) - 1 := by
  unfold cursorAfter words
  omega

/-- Seven steps return to the base word. $$c_{j+7} = c_j$$ -/
theorem cursor_period (j : Nat) : cursorAfter (j + (words + 1)) = cursorAfter j := by
  unfold cursorAfter words
  omega

/-- The box width in $\mathrm{em}/64$ for a cursor value (JS 3667, 3721-3730).

$$\forall c \in \mathbb{Z}:\ W(c) = \begin{cases} 106 & c < 0 \\ w_c & 0 \le c < 6 \\ 106 & c \ge 6 \end{cases}$$

The accent resizes for each word. -/
def widthOf (c : Int) : Nat :=
  if c < 0 then baseWidth else (wordWidths.getD c.toNat baseWidth)

/-! ## The timeline -/

/-- The length of one word change in ms. $$P = 1250 + 900 + 900 = 3050$$ -/
def period : Nat := idleWait + drawWait + drawWait

/-- The state of the chain. $$\mathrm{idle} \mid \mathrm{drawOut} \mid \mathrm{drawIn}$$ -/
inductive St
  | idle | drawOut | drawIn
deriving Repr, DecidableEq

/-- The chain at $e$ ms after mount (no pause): the state and the cursor value.

$$\operatorname{chainAt}(e) = \begin{cases} (\mathrm{idle}, -1) & e < 2200 \\ (\mathrm{drawOut}, c_k) & r \bmod P < 900 \\ (\mathrm{drawIn}, c_{k+1}) & 900 \le r \bmod P < 1800 \\ (\mathrm{idle}, c_{k+1}) & \text{otherwise} \end{cases},\quad r = e - 2200,\ k = \lfloor r / P \rfloor$$

The cursor changes at the end of the draw-out (JS 3699). -/
def chainAt (e : Nat) : St × Int :=
  if e < firstWait then (.idle, -1)
  else
    let r := e - firstWait
    let k := r / period
    let m := r % period
    if m < drawWait then (.drawOut, cursorAfter k)
    else if m < drawWait + drawWait then (.drawIn, cursorAfter (k + 1))
    else (.idle, cursorAfter (k + 1))

#guard chainAt 0 == (.idle, -1)
#guard chainAt 2199 == (.idle, -1)
#guard chainAt 2200 == (.drawOut, -1)
#guard chainAt 3099 == (.drawOut, -1)
#guard chainAt 3100 == (.drawIn, 0)
#guard chainAt 3999 == (.drawIn, 0)
#guard chainAt 4000 == (.idle, 0)
#guard chainAt 5249 == (.idle, 0)
#guard chainAt 5250 == (.drawOut, 0)

/-- A word cycle is the three waits. $$P = 3050$$ -/
theorem period_eq : period = 3050 := by decide +kernel

/-- Before 2200 ms nothing has changed. $$e < 2200 \Rightarrow \operatorname{chainAt}(e) = (\mathrm{idle}, -1)$$ -/
theorem chainAt_first (e : Nat) (h : e < firstWait) : chainAt e = (.idle, -1) := by
  unfold chainAt; simp [h]

/-- The first change ends at 3100 ms: the cursor is the first word from then on.

$$\operatorname{chainAt}(3100) = (\mathrm{drawIn}, 0)$$

2200 ms idle plus 900 ms draw-out. -/
theorem first_change : chainAt (firstWait + drawWait) = (.drawIn, 0) := by decide +kernel

/-- The chain repeats every 3050 ms after the first wait, with the cursor advanced by one.

$$e \ge 2200 \Rightarrow \operatorname{chainAt}(e + P).\mathrm{state} = \operatorname{chainAt}(e).\mathrm{state}$$

Every word change takes the same time. -/
theorem chainAt_state_period (e : Nat) (h : firstWait ≤ e) : (chainAt (e + period)).1 = (chainAt e).1 := by
  have h' : 2200 ≤ e := h
  unfold chainAt period firstWait drawWait idleWait
  have h1 : ¬ e + (1250 + 900 + 900) < 2200 := by omega
  have h2 : ¬ e < 2200 := by omega
  simp only [h1, h2, ite_false]
  have e1 : (e + (1250 + 900 + 900) - 2200) % (1250 + 900 + 900) = (e - 2200) % (1250 + 900 + 900) := by omega
  rw [e1]
  by_cases a : (e - 2200) % (1250 + 900 + 900) < 900 <;> by_cases b : (e - 2200) % (1250 + 900 + 900) < 900 + 900 <;> simp [a, b]

/-- Seven word changes bring the cursor back to the base word: the whole show repeats every
$7 \cdot 3050 = 21350$ ms. $$\operatorname{chainAt}(e + 7P) = \operatorname{chainAt}(e),\ e \ge 2200$$ -/
theorem chainAt_period (e : Nat) (h : firstWait ≤ e) : chainAt (e + (words + 1) * period) = chainAt e := by
  have h' : 2200 ≤ e := h
  unfold chainAt period firstWait drawWait idleWait words
  have h1 : ¬ e + (6 + 1) * (1250 + 900 + 900) < 2200 := by omega
  have h2 : ¬ e < 2200 := by omega
  simp only [h1, h2, ite_false]
  have e1 : (e + (6 + 1) * (1250 + 900 + 900) - 2200) % (1250 + 900 + 900) = (e - 2200) % (1250 + 900 + 900) := by omega
  have e2 : (e + (6 + 1) * (1250 + 900 + 900) - 2200) / (1250 + 900 + 900) = (e - 2200) / (1250 + 900 + 900) + (6 + 1) := by omega
  simp only [e1, e2]
  have c1 : cursorAfter ((e - 2200) / (1250 + 900 + 900) + (6 + 1)) = cursorAfter ((e - 2200) / (1250 + 900 + 900)) := cursor_period _
  have c2 : cursorAfter ((e - 2200) / (1250 + 900 + 900) + (6 + 1) + 1) = cursorAfter ((e - 2200) / (1250 + 900 + 900) + 1) := by
    have := cursor_period ((e - 2200) / (1250 + 900 + 900) + 1)
    unfold words at this
    rw [show (e - 2200) / (1250 + 900 + 900) + (6 + 1) + 1 = (e - 2200) / (1250 + 900 + 900) + 1 + (6 + 1) by omega]
    exact this
  rw [c1, c2]

/-! ## The idle boil -/

/-- The visible idle frame (0, 1 or 2) at $e$ ms (CSS 1292-1299: 0.6 s `step-end`, thirds).

$$\operatorname{frame}(e) = \lfloor (e \bmod 600) / 200 \rfloor$$

The three frames take turns every 200 ms. -/
def idleFrame (e : Nat) : Nat := (e % 600) / 200

/-- The idle frame is one of three. $$\operatorname{frame}(e) \in \{0, 1, 2\}$$ -/
theorem idleFrame_lt (e : Nat) : idleFrame e < 3 := by unfold idleFrame; omega

/-- The boil repeats every 600 ms. $$\operatorname{frame}(e + 600) = \operatorname{frame}(e)$$ -/
theorem idleFrame_period (e : Nat) : idleFrame (e + 600) = idleFrame e := by unfold idleFrame; omega

end Fw.Parts.HeroAccent
