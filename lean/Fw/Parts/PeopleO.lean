/-!
# people.o: the "o" of "people" that opens into a row of faces (`faithful`)

Restated (not copied) from `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`, read independently of the TS part:

* 6214-6245 (`a`, `i`): when the heading enters the viewport (an `IntersectionObserver`, threshold $0.35$, JS 6252)
  the part sets `stack` after 1300 ms and `expanded` 120 ms after that; the `standalone` option (not used on the home
  page, kept for faithfulness) sets `stack` at once and `expanded` after 120 ms. Leaving the viewport clears both,
  unless reduced motion is on, in which case both are set at once, on entering and on leaving;
* 6190-6213 (`j`, `A`, `P`): hovering or focusing a face (only once `expanded`, and only wider than 860 px) opens a
  preview card at a position computed from the face's rect: width $\min(320, w_v - 24)$, left centred and clamped into
  $[12, w_v - w - 12]$, top $12$ px below the face, or $12$ px above the 440 px card when it would not fit;
* CSS `assets/2.gBuqKVzi.css` 2429-2540: the `o` box is a one-column grid, $0.6042$ em wide and $1.0417$ em high,
  growing to $5.25$ em and $1.0833$ em when expanded (0.92 s); six faces of $1$ em with margin-right $-1/6$ em stack in
  a box $5.1667$ em wide; the face with index $i$ enters with a delay of $0.17\,i$ s when stacked but not expanded.

Times are whole ms (`Nat`); lengths are `Rat`.
-/
namespace Fw.Parts.PeopleO

/-! ## Timeline -/

/-- Delay from entering the viewport to the stack, in ms (JS 6236). $$a = 1300$$ -/
def stackDelay : Nat := 1300

/-- Delay from the stack to the expansion, in ms (JS 6229, 6238). $$b = 120$$ -/
def expandDelay : Nat := 120

/-- Visibility threshold of the observer (JS 6252). $$\tau = 0.35 = \tfrac{7}{20}$$ -/
def threshold : Rat := 7 / 20

/-- The two flags `(stack, expanded)` $t$ ms after the heading entered the viewport.

$$\mathrm{phase}(\mathit{rm}, \mathit{sa}, t) = \begin{cases} (\top, \top) & \mathit{rm} \\ (\top,\ t \ge 120) & \lnot\mathit{rm} \land \mathit{sa} \\ (t \ge 1300,\ t \ge 1420) & \text{otherwise} \end{cases}$$

Reduced motion shows the opened row at once. -/
def phase (reduced standalone : Bool) (t : Nat) : Bool × Bool :=
  if reduced then (true, true)
  else if standalone then (true, decide (expandDelay ≤ t))
  else (decide (stackDelay ≤ t), decide (stackDelay + expandDelay ≤ t))

/-- `decide` of a Nat comparison is true iff the comparison holds. $$\operatorname{decide}(a \le t) = \top \iff a \le t$$ -/
theorem dle {a t : Nat} : decide (a ≤ t) = true ↔ a ≤ t := decide_eq_true_iff

#guard phase false false 0 == (false, false)
#guard phase false false 1299 == (false, false)
#guard phase false false 1300 == (true, false)
#guard phase false false 1419 == (true, false)
#guard phase false false 1420 == (true, true)
#guard phase false true 0 == (true, false)
#guard phase false true 120 == (true, true)
#guard phase true false 0 == (true, true)

/-- **Expanded implies stacked.** The faces never open before the stack shows.

$$\forall \mathit{rm}, \mathit{sa}, t:\ \mathrm{expanded}(t) \Rightarrow \mathrm{stack}(t)$$ -/
theorem expanded_imp_stack (rm sa : Bool) (t : Nat) : (phase rm sa t).2 = true → (phase rm sa t).1 = true := by
  unfold phase
  split
  · simp
  · split <;> dsimp only <;> (try simp only [dle]) <;> (try simp only [stackDelay, expandDelay]) <;> first | omega | simp

/-- **Both flags are monotone in time.** Once on, they stay on until the heading leaves the viewport.

$$t \le t' \Rightarrow (\mathrm{stack}(t) \Rightarrow \mathrm{stack}(t')) \land (\mathrm{expanded}(t) \Rightarrow \mathrm{expanded}(t'))$$ -/
theorem phase_mono (rm sa : Bool) (t t' : Nat) (h : t ≤ t') :
    ((phase rm sa t).1 = true → (phase rm sa t').1 = true) ∧
    ((phase rm sa t).2 = true → (phase rm sa t').2 = true) := by
  unfold phase
  split
  · simp
  · split <;> dsimp only <;> refine ⟨?_, ?_⟩ <;> (try simp only [dle]) <;> (try simp only [stackDelay, expandDelay]) <;> first | omega | simp

/-- **Opening gap.** In the normal case the row opens exactly $b = 120$ ms after the stack shows.

$$\min\{t : \mathrm{expanded}(t)\} - \min\{t : \mathrm{stack}(t)\} = 120$$

(stated as: the stack shows at 1300, the expansion at 1420, and neither earlier). -/
theorem opening_gap :
    (phase false false stackDelay).1 = true ∧ (phase false false (stackDelay - 1)).1 = false ∧
    (phase false false (stackDelay + expandDelay)).2 = true ∧
    (phase false false (stackDelay + expandDelay - 1)).2 = false := by decide

/-- Leaving the viewport restores the closed row (normal motion): at time $0$ of the next entry both flags are off.

$$\lnot\mathit{rm} \land \lnot\mathit{sa} \Rightarrow \mathrm{phase}(0) = (\bot, \bot)$$ -/
theorem reenter_closed : phase false false 0 = (false, false) := by decide

/-- Under reduced motion the row is open at every instant.

$$\forall \mathit{sa}, t:\ \mathrm{phase}(\top, \mathit{sa}, t) = (\top, \top)$$ -/
theorem reduced_open (sa : Bool) (t : Nat) : phase true sa t = (true, true) := by simp [phase]

/-! ## Geometry (em) -/

/-- Width of the closed `o` in em (CSS 2434). $$c_0 = 0.6042 = \tfrac{3021}{5000}$$ -/
def closedWidth : Rat := 3021 / 5000

/-- Width of the opened `o` in em (CSS 2450). $$c_1 = 5.25 = \tfrac{21}{4}$$ -/
def openWidth : Rat := 21 / 4

/-- Height of the closed `o` in em (CSS 2436). $$h_0 = 1.0417 = \tfrac{10417}{10000}$$ -/
def closedHeight : Rat := 10417 / 10000

/-- Height of the opened `o` in em (CSS 2451). $$h_1 = 1.0833 = \tfrac{10833}{10000}$$ -/
def openHeight : Rat := 10833 / 10000

/-- Face diameter in em (CSS 2530). $$f = 1$$ -/
def faceSize : Rat := 1

/-- Negative overlap between faces in em (CSS 2535). $$g = \tfrac{1}{6} = 0.1667$$ -/
def faceOverlap : Rat := 1 / 6

/-- Number of faces (the six professions). $$k = 6$$ -/
def faces : Nat := 6

/-- Offset of the stack inside the stage in em (CSS 2512). $$\ell = 0.0417 = \tfrac{417}{10000}$$ -/
def stackLeft : Rat := 417 / 10000

/-- Width of the stack of faces in em: $k$ faces, the last without the negative margin.

$$w_s = k f - (k-1) g = 6 - \tfrac{5}{6} = \tfrac{31}{6} \approx 5.1667$$ -/
def stackWidth : Rat := faces * faceSize - (faces - 1) * faceOverlap

/-- **The stack is 5.1667 em wide.** The CSS declares `width: 5.1667em` for the stack.

$$\tfrac{31}{6} = 5.16\overline{6} \ \text{ and } \ |\tfrac{31}{6} - 5.1667| < 10^{-4}$$ -/
theorem stack_width_value : stackWidth = 31 / 6 ∧ stackWidth - 51667 / 10000 < 1 / 10000 ∧ 51667 / 10000 - stackWidth < 1 / 10000 := by
  unfold stackWidth faces faceSize faceOverlap
  grind

/-- **The opened row fits its grid column.** The stack plus its left offset is inside the $5.25$ em column.

$$\ell + w_s \le c_1$$

So the faces are never clipped once expanded. -/
theorem stack_fits_open : stackLeft + stackWidth ≤ openWidth := by
  unfold stackLeft stackWidth openWidth faces faceSize faceOverlap
  grind

/-- Opening makes the box wider and taller.
$$c_0 < c_1 \ \land\ h_0 < h_1$$ -/
theorem opens_larger : closedWidth < openWidth ∧ closedHeight < openHeight := by
  unfold closedWidth openWidth closedHeight openHeight
  grind

/-- Entry delay of face $i$ when stacked but not expanded, in ms (CSS 2551). $$\delta_i = 170\,i$$ -/
def faceDelay (i : Nat) : Nat := 170 * i

/-- Last face's delay. $$\delta_5 = 850$$ ms: the faces appear one after another over 0.85 s. -/
theorem last_face_delay : faceDelay (faces - 1) = 850 := by decide

/-! ## Preview card position -/

/-- Card width for a viewport of width $w_v$ (JS 6192). $$w = \min(320, w_v - 24)$$ -/
def cardWidth (vw : Rat) : Rat := min 320 (vw - 24)

/-- Card height used for the flip test, in px (JS 6196). $$H = 440$$ -/
def cardHeight : Rat := 440

/-- Card left edge for a face rect with left $x$ and width $s$ (JS 6193-6194).

$$L = \max\!\big(12,\ \min(x + s/2 - w/2,\ w_v - w - 12)\big)$$ -/
def cardLeft (vw x s : Rat) : Rat :=
  max 12 (min (x + s / 2 - cardWidth vw / 2) (vw - cardWidth vw - 12))

/-- Card top for a face rect with top $y$ and bottom $z$ (JS 6195-6197).

$$T = \begin{cases} \max(12,\ y - 12 - 440) & z + 12 + 440 > h_v - 12 \\ z + 12 & \text{otherwise} \end{cases}$$ -/
def cardTop (vh y z : Rat) : Rat :=
  if vh - 12 < z + 12 + cardHeight then max 12 (y - 12 - cardHeight) else z + 12

/-- **The card stays inside the viewport horizontally.** For any face position the card keeps 12 px from both sides.

$$12 \le L \ \land\ L + w \le w_v - 12$$ -/
theorem card_inside_x (vw x s : Rat) :
    12 ≤ cardLeft vw x s ∧ cardLeft vw x s + cardWidth vw ≤ vw - 12 := by
  unfold cardLeft cardWidth
  constructor
  · grind
  · grind

/-- **The card keeps 12 px from the top.** $$T \ge 12$$ -/
theorem card_top_ge (vh y z : Rat) (h : 12 ≤ z + 12) : 12 ≤ cardTop vh y z := by
  unfold cardTop
  split <;> grind

/-- **Below when it fits.** If the card fits under the face it opens 12 px under it.
$$z + 12 + 440 \le h_v - 12 \Rightarrow T = z + 12$$ -/
theorem card_below (vh y z : Rat) (h : z + 12 + cardHeight ≤ vh - 12) : cardTop vh y z = z + 12 := by
  unfold cardTop
  grind

#guard cardLeft 1280 400 56 == 400 + 28 - 160
#guard cardLeft 1280 0 56 == 12
#guard cardLeft 1280 1270 56 == 1280 - 320 - 12
#guard cardTop 900 50 90 == 102
#guard cardTop 900 600 640 == 600 - 12 - 440

end Fw.Parts.PeopleO
