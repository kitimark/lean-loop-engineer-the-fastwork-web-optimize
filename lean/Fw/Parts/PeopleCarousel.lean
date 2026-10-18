/-!
# people.carousel: the avatar carousel of the community pill (`faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, read independently of the TS part:

* 11263-11275 and 11289-11322: the loop. While the section is active (the engine's visibility signal) it waits
  $800$ ms (`f(800)`), then, if still active, shows the swap template for $220$ ms (`f(220)`), then, if still active,
  advances the index $x \leftarrow (x+1) \bmod n$ and hides the swap template; if it lost the activity in the 220 ms it
  hides the template without advancing, and if it lost it in the first 800 ms it waits for the activity again.
  Under reduced motion the loop never runs;
* 11330-11356 and 11415-11447: the rest template shows the 4 avatars $E(0..3)$; the swap template shows 5 avatars
  $E(0..4)$, the first with class `is-exit` and the last with `is-enter`; $E(k) = \mathit{avatars}[(x+k) \bmod n]$
  with $n = 6$ avatars (the six professions in showcase order);
* CSS `assets/2.gBuqKVzi.css` 2866-2915: the carousel box is $104 \times 32$ px, `overflow: hidden`, each avatar is
  `flex: 0 0 32px` with `margin-right: -8px` except the last child; `avatars-exit` (0.22 s) takes the width from 32 to 0
  and the margin from $-8$ to $0$; `avatars-pop` (0.22 s) takes opacity and scale to 1.

Times are whole milliseconds (`Nat`); nothing here is a float.
-/
namespace Fw.Parts.PeopleCarousel

/-! ## Constants -/

/-- Wait before a swap in ms (JS 11291 `f(800)`). $$R = 800$$ How long the row rests. -/
def restMs : Nat := 800

/-- Duration of the swap template in ms (JS 11295 `f(220)`, CSS `0.22s`). $$S = 220$$ How long the swap shows. -/
def swapMs : Nat := 220

/-- One full cycle in ms. $$P = R + S = 1020$$ From one index step to the next while the section stays active. -/
def periodMs : Nat := restMs + swapMs

/-- Number of avatars in the ring (the six professions). $$n = 6$$ The ring size. -/
def ringSize : Nat := 6

/-- Avatars shown at rest. $$m = 4$$ The window size. -/
def shown : Nat := 4

/-- Avatar diameter in px (CSS 2884). $$d = 32$$ The slot width. -/
def avatarPx : Nat := 32

/-- Overlap between neighbours in px (CSS 2888, `margin-right: -8px`). $$o = 8$$ The negative margin. -/
def overlapPx : Nat := 8

/-- The cycle is 1020 ms. $$P = 1020$$ -/
theorem period_eq : periodMs = 1020 := by decide

/-! ## Layout -/

/-- Width in px of a row of $k \ge 1$ avatars with the overlap.

$$W(k) = k\,d - (k-1)\,o$$

The row of the last child has no negative margin. -/
def rowPx (k : Nat) : Nat := k * avatarPx - (k - 1) * overlapPx

/-- **The box fits the rest row exactly.**

$$W(4) = 4 \cdot 32 - 3 \cdot 8 = 104$$

The carousel box is 104 px wide, so the rest row fills it without a gap. -/
theorem rest_row_fills_box : rowPx shown = 104 := by decide

/-- During the swap the row is wider than the box, so the entering avatar is clipped.

$$W(5) = 128 > 104$$

`overflow: hidden` hides the extra 24 px until the exit avatar has collapsed. -/
theorem swap_row_overflows : rowPx (shown + 1) = 128 ∧ 104 < rowPx (shown + 1) := by decide

/-- **Layout continuity.** When the exit avatar has collapsed (width 0, margin 0) the remaining four avatars have the
rest width.

$$4\,d - 3\,o = W(4) = 104$$

The next rest frame has the same layout as the last swap frame. -/
theorem swap_end_is_rest : 4 * avatarPx - 3 * overlapPx = rowPx shown := by decide

/-! ## The ring -/

/-- Index of the avatar at slot $k$ when the head is $x$.

$$E_x(k) = (x + k) \bmod n$$ -/
def slot (x k : Nat) : Nat := (x + k) % ringSize

/-- The rest window. $$\mathrm{rest}(x) = [E_x(0), E_x(1), E_x(2), E_x(3)]$$ -/
def restWindow (x : Nat) : List Nat := (List.range shown).map (slot x)

/-- The swap window (the exit avatar first, the enter avatar last).
$$\mathrm{swap}(x) = [E_x(0), \dots, E_x(4)]$$ -/
def swapWindow (x : Nat) : List Nat := (List.range (shown + 1)).map (slot x)

/-- The slot only depends on the head modulo the ring size. $$\forall x, k:\ E_{x \bmod n}(k) = E_x(k)$$ -/
theorem slot_mod (x k : Nat) : slot (x % ringSize) k = slot x k := by
  simp only [slot, ringSize]; omega

/-- Swap windows only depend on the head modulo the ring size. $$\mathrm{swap}(x \bmod n) = \mathrm{swap}(x)$$ -/
theorem swapWindow_mod (x : Nat) : swapWindow (x % ringSize) = swapWindow x := by
  have : slot (x % ringSize) = slot x := funext (slot_mod x)
  simp only [swapWindow, this]

/-- Rest windows only depend on the head modulo the ring size. $$\mathrm{rest}(x \bmod n) = \mathrm{rest}(x)$$ -/
theorem restWindow_mod (x : Nat) : restWindow (x % ringSize) = restWindow x := by
  have : slot (x % ringSize) = slot x := funext (slot_mod x)
  simp only [restWindow, this]

/-- **The swap lands on the next rest window.** Dropping the exit avatar from the swap window gives the rest window
of the next index.

$$\forall x:\ \mathrm{drop}_1(\mathrm{swap}(x)) = \mathrm{rest}((x+1) \bmod n)$$

What the user sees at the end of the 220 ms is exactly the rest row one step later. -/
theorem swap_drop_is_next_rest (x : Nat) : (swapWindow x).drop 1 = restWindow ((x + 1) % ringSize) := by
  have h : ∀ y : Fin ringSize, (swapWindow y).drop 1 = restWindow ((y + 1) % ringSize) := by decide
  have := h ⟨x % ringSize, Nat.mod_lt _ (by decide)⟩
  simp only [swapWindow_mod] at this
  rw [this]
  have e : (x % ringSize + 1) % ringSize = (x + 1) % ringSize := by simp only [ringSize]; omega
  rw [e]

/-- **The five slots of a swap are distinct.** With six avatars no face appears twice in the swap row.

$$\forall x:\ \text{the entries of } \mathrm{swap}(x) \text{ are pairwise different}$$

So the entering avatar is never one already on screen. -/
theorem swap_window_nodup (x : Nat) : (swapWindow x).Nodup := by
  have h : ∀ y : Fin ringSize, (swapWindow y).Nodup := by decide
  have := h ⟨x % ringSize, Nat.mod_lt _ (by decide)⟩
  simpa [swapWindow_mod] using this

/-! ## The loop as a state machine -/

/-- Loop state: the head index and whether the swap template shows.
$$s = (x, w) \in \mathbb{N} \times \{\top, \bot\}$$ -/
structure State where
  x : Nat
  swapping : Bool
deriving Repr, BEq, DecidableEq

/-- Start state. $$s_0 = (0, \bot)$$ The index is 0 and the rest template shows. -/
def start : State := ⟨0, false⟩

/-- What the loop does when the 800 ms rest timer ends (JS 11291-11296).

$$\mathrm{afterRest}(s, a) = \begin{cases} (x, \top) & a \\ s & \lnot a \end{cases}$$

If the section is active the swap template shows (and a 220 ms timer starts); otherwise nothing changes and the loop
waits for the activity again. -/
def afterRest (s : State) (active : Bool) : State := if active then { s with swapping := true } else s

/-- What the loop does when the 220 ms swap timer ends (JS 11297-11302).

$$\mathrm{afterSwap}(s, a) = \begin{cases} ((x+1) \bmod n, \bot) & a \\ (x, \bot) & \lnot a \end{cases}$$

If still active the index advances; either way the swap template is hidden. -/
def afterSwap (s : State) (active : Bool) : State :=
  if active then ⟨(s.x + 1) % ringSize, false⟩ else { s with swapping := false }

/-- One uninterrupted cycle (active throughout). $$\mathrm{cycle}(s) = \mathrm{afterSwap}(\mathrm{afterRest}(s, \top), \top)$$ -/
def cycle (s : State) : State := afterSwap (afterRest s true) true

/-- Cycles from the start. $$\mathrm{run}_0 = s_0,\quad \mathrm{run}_{k+1} = \mathrm{cycle}(\mathrm{run}_k)$$ -/
def run : Nat → State
  | 0 => start
  | k + 1 => cycle (run k)

/-- **Closed form of an uninterrupted run.**

$$\mathrm{run}_k = (k \bmod n,\ \bot)$$

After $k$ cycles ($1020\,k$ ms of continuous activity plus the 800 ms start wait) the head is $k \bmod 6$. -/
theorem run_closed (k : Nat) : run k = ⟨k % ringSize, false⟩ := by
  induction k with
  | zero => rfl
  | succ k ih =>
    simp only [run, ih, cycle, afterSwap, afterRest, ite_true]
    simp [Nat.add_mod, ringSize]

/-- **The ring returns after $n$ cycles.**

$$\mathrm{run}_{n} = s_0$$

The carousel is periodic with period $n \cdot 1020 = 6120$ ms. -/
theorem run_period : run ringSize = start := by decide

/-- **Index at a time.** For the continuously active loop, the head $t$ ms after the 800 ms start wait has elapsed
(when the first cycle begins) and the swap flag.

$$x(t) = \lfloor t / 1020 \rfloor \bmod n,\qquad w(t) = \big[\,800 \le t \bmod 1020\,\big]$$

The state at any instant is a function of time alone. -/
def stateAt (t : Nat) : State := ⟨(t / periodMs) % ringSize, restMs ≤ t % periodMs⟩

/-- At each cycle boundary the closed form agrees with the loop.

$$\mathrm{stateAt}(1020\,k) = \mathrm{run}_k$$ -/
theorem stateAt_boundary (k : Nat) : stateAt (periodMs * k) = run k := by
  rw [run_closed]
  have h1 : periodMs * k / periodMs = k := Nat.mul_div_cancel_left _ (by decide)
  have h2 : periodMs * k % periodMs = 0 := Nat.mul_mod_right _ _
  simp [stateAt, h1, h2, restMs]

/-- **The swap window is 220 ms of every 1020.**

$$w(t) \iff t \bmod 1020 \in [800, 1020)$$

The swap template shows for exactly the last $S$ ms of each cycle. -/
theorem swap_phase (t : Nat) : (stateAt t).swapping = true ↔ restMs ≤ t % periodMs := by
  simp [stateAt]

/-- A lost activity during the rest wait never advances the index.
$$\mathrm{afterRest}(s, \bot) = s$$ -/
theorem afterRest_inactive (s : State) : afterRest s false = s := rfl

/-- A lost activity during the swap never advances the index and hides the swap template.
$$\mathrm{afterSwap}(s, \bot) = (x, \bot)$$ -/
theorem afterSwap_inactive (s : State) : afterSwap s false = ⟨s.x, false⟩ := rfl

/-- The index always stays inside the ring.
$$\forall s,\ a:\ x \lt n \Rightarrow \mathrm{afterSwap}(s, a).x \lt n$$ -/
theorem afterSwap_lt (s : State) (a : Bool) (h : s.x < ringSize) : (afterSwap s a).x < ringSize := by
  unfold afterSwap
  cases a <;> simp [h]
  exact Nat.mod_lt _ (by decide)

end Fw.Parts.PeopleCarousel
