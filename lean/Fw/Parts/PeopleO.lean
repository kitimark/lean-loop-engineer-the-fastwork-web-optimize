import Fw.Engine.Core
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

/-- **Opening gap.** In the normal case ($\mathit{rm} = \mathit{sa} = \bot$) the stack shows at $a = 1300$ but not at
1299, and the row expands at $a + b = 1420$ but not at 1419.

$$\mathrm{phase}(\bot, \bot, 1300).1 = \top \wedge \mathrm{phase}(\bot, \bot, 1299).1 = \bot \wedge \mathrm{phase}(\bot, \bot, 1420).2 = \top \wedge \mathrm{phase}(\bot, \bot, 1419).2 = \bot$$

The row opens 120 ms after the stack shows. -/
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

/-- **The card keeps 12 px from the top** when the face bottom $z$ is not above the viewport top.

$$\forall h_v, y, z \in \mathbb{Q}:\ 12 \le z + 12 \Rightarrow 12 \le T(h_v, y, z)$$ -/
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

/-! ## The FLIP variant's work inside the transition (ledger n=18)

The original opens the `o` by a 0.92 s CSS transition of `grid-template-columns` and `height`: every frame strictly
inside the transition carries one main-thread size change `oc` and no script. The FLIP variant (people-gpu) sets the
final size once and moves the parts with $m$ compositor translate animations, so a frame inside the motion carries no
main-thread change and no script, only the $m$ running animations. Both frames are stated over any engine `E` of
`Fw.Engine.Core`; the premises on `E` are hypotheses, not a table lookup.

Not covered: the first and last frames (where FLIP pays the size change and the cleanup), resident layers (the
spans' transient composited layers, ledger `claim_ne_dominates_of_layers`) and pixels (class L). -/

section Flip

open Fw.Engine (Stage Change FrameIn Engine Work frameWork touched stageUnits forcedPasses)

/-- Length of the open transition in ms (CSS 2450, `0.92s`). $$T = 920$$ -/
def openMs : Nat := 920

/-- The original's frame strictly inside the transition: one main-thread change `oc` (the animated grid size), no
script, no forced passes, no hit tests, no compositor animation.

$$o(\mathit{oc}) = (0, 0, 0, 0, [\mathit{oc}], 0)$$ -/
def origMid {P : Type} (oc : Change P) : FrameIn P := ⟨0, 0, 0, 0, [oc], 0⟩

/-- The FLIP variant's frame strictly inside the motion: no main-thread change, no script, $m$ running compositor
animations (the translated parts).

$$v(m) = (0, 0, 0, 0, [\,], m)$$ -/
def flipMid {P : Type} (m : Nat) : FrameIn P := ⟨0, 0, 0, 0, [], m⟩

/-- **The FLIP frame pays only the compositor-animation stages.** Its passes are one on each stage of
$E.\mathrm{compStages}$ when an animation runs, its units are $m$ on those stages, zero elsewhere, and no hit tests.

$$\forall E,\ \forall m \in \mathbb{N},\ \forall s \in \mathrm{Stage}:\ W_E(v(m)).\mathrm{passes}(s) = [\,0 < m \land s \in E.\mathrm{compStages}\,] \ \land\ W_E(v(m)).\mathrm{units}(s) = [\,s \in E.\mathrm{compStages}\,]\cdot m \ \land\ W_E(v(m)).\mathrm{hits} = 0$$

Nothing runs on the main thread while the parts slide. -/
theorem flipMid_work {P M : Type} (E : Engine P M) (m : Nat) (s : Stage) :
    (frameWork E (flipMid (P := P) m)).passes s = (if 0 < m ∧ s ∈ E.compStages then 1 else 0) ∧
      (frameWork E (flipMid (P := P) m)).units s = (if s ∈ E.compStages then m else 0) ∧
      (frameWork E (flipMid (P := P) m)).hits = 0 := by
  refine ⟨?_, ?_, rfl⟩
  · simp only [frameWork, touched, flipMid, FrameIn.updates, forcedPasses]
    by_cases hm : 0 < m <;> by_cases hs : s ∈ E.compStages <;> cases s <;> simp_all
  · simp only [frameWork, stageUnits, flipMid]
    cases s <;> simp

/-- **The original frame pays the size change's stages and the base stages.** One pass on each stage the change
dirties or the engine pays per updating frame, one unit on each stage the change dirties, no hit tests.

$$\forall E,\ \forall \mathit{oc},\ \forall s \in \mathrm{Stage}:\ W_E(o(\mathit{oc})).\mathrm{passes}(s) = [\,s \in E.\mathrm{stagesOf}(\mathit{oc}) \lor s \in E.\mathrm{base}\,] \ \land\ W_E(o(\mathit{oc})).\mathrm{units}(s) = [\,s \in E.\mathrm{stagesOf}(\mathit{oc})\,] \ \land\ W_E(o(\mathit{oc})).\mathrm{hits} = 0$$

The grid transition runs style, layout and everything after it each frame. -/
theorem origMid_work {P M : Type} (E : Engine P M) (oc : Change P) (s : Stage) :
    (frameWork E (origMid oc)).passes s = (if s ∈ E.stagesOf oc ∨ s ∈ E.base then 1 else 0) ∧
      (frameWork E (origMid oc)).units s = (if s ∈ E.stagesOf oc then 1 else 0) ∧
      (frameWork E (origMid oc)).hits = 0 := by
  refine ⟨?_, ?_, rfl⟩
  · simp only [frameWork, touched, origMid, FrameIn.updates, forcedPasses]
    cases s <;> simp
  · simp only [frameWork, stageUnits, origMid]
    cases s <;> simp [List.countP_cons]

/-- **Main-thread work falls inside the motion.** On every stage outside the compositor-animation stages the FLIP
frame does at most the original's passes and units (it does none), and when `layout` is dirtied by the size change but
is not a compositor-animation stage, the FLIP frame has strictly fewer layout passes.

$$\forall E,\ \forall \mathit{oc},\ \forall m \in \mathbb{N}:\ \mathrm{layout} \in E.\mathrm{stagesOf}(\mathit{oc}) \land \mathrm{layout} \notin E.\mathrm{compStages} \Rightarrow \Big(\forall s \notin E.\mathrm{compStages}:\ W_E(v(m)).\mathrm{passes}(s) \le W_E(o(\mathit{oc})).\mathrm{passes}(s) \land W_E(v(m)).\mathrm{units}(s) \le W_E(o(\mathit{oc})).\mathrm{units}(s)\Big) \land W_E(v(m)).\mathrm{passes}(\mathrm{layout}) = 0 < 1 = W_E(o(\mathit{oc})).\mathrm{passes}(\mathrm{layout})$$

Layout leaves every frame strictly inside the transition. -/
theorem flip_main_lt {P M : Type} (E : Engine P M) (oc : Change P) (m : Nat)
    (hL : Stage.layout ∈ E.stagesOf oc) (hLc : Stage.layout ∉ E.compStages) :
    (∀ s, s ∉ E.compStages →
      (frameWork E (flipMid (P := P) m)).passes s ≤ (frameWork E (origMid oc)).passes s ∧
      (frameWork E (flipMid (P := P) m)).units s ≤ (frameWork E (origMid oc)).units s) ∧
    (frameWork E (flipMid (P := P) m)).passes .layout = 0 ∧ (frameWork E (origMid oc)).passes .layout = 1 := by
  refine ⟨fun s hs => ?_, ?_, ?_⟩
  · obtain ⟨v1, v2, -⟩ := flipMid_work (P := P) E m s
    rw [v1, v2]
    simp [hs]
  · rw [(flipMid_work (P := P) E m .layout).1]
    simp [hLc]
  · rw [(origMid_work E oc .layout).1]
    simp [hL]

/-- **FLIP is not below the original in Core's order (a trade).** If an animation runs and some compositor-animation
stage is neither dirtied by the size change nor a base stage, the FLIP frame is not $\preceq$ the original frame:
it pays a pass there that the original does not.

$$\forall E,\ \forall \mathit{oc},\ \forall m \in \mathbb{N},\ \forall s \in \mathrm{Stage}:\ 0 < m \land s \in E.\mathrm{compStages} \land s \notin E.\mathrm{stagesOf}(\mathit{oc}) \land s \notin E.\mathrm{base} \Rightarrow \lnot\big(W_E(v(m)) \preceq W_E(o(\mathit{oc}))\big)$$

Both engine tables have such a stage (`comp`), so `flip_work_lt` as $\prec$ is false there; the variant trades
compositor work for main-thread work. -/
theorem flip_not_le {P M : Type} (E : Engine P M) (oc : Change P) (m : Nat) (s : Stage) (hm : 0 < m)
    (hs : s ∈ E.compStages) (hso : s ∉ E.stagesOf oc) (hsb : s ∉ E.base) :
    ¬ (frameWork E (flipMid (P := P) m)).le (frameWork E (origMid oc)) := by
  intro h
  have h1 := (h.1 s).1
  rw [(flipMid_work (P := P) E m s).1, (origMid_work E oc s).1] at h1
  simp [hm, hs, hso, hsb] at h1

/-- **When FLIP is strictly below.** If every compositor-animation stage is dirtied by the size change, at most one
animation runs, and `layout` is dirtied by the size change but is not a compositor-animation stage, the FLIP frame is
$\prec$ the original frame.

$$\forall E,\ \forall \mathit{oc},\ \forall m \in \mathbb{N}:\ m \le 1 \land E.\mathrm{compStages} \subseteq E.\mathrm{stagesOf}(\mathit{oc}) \land \mathrm{layout} \in E.\mathrm{stagesOf}(\mathit{oc}) \land \mathrm{layout} \notin E.\mathrm{compStages} \Rightarrow W_E(v(m)) \prec W_E(o(\mathit{oc}))$$

These are the conditions the ledger's `flip_work_lt` needs. -/
theorem flip_lt_of_comp_sub {P M : Type} (E : Engine P M) (oc : Change P) (m : Nat) (hm : m ≤ 1)
    (hc : ∀ s ∈ E.compStages, s ∈ E.stagesOf oc) (hL : Stage.layout ∈ E.stagesOf oc)
    (hLc : Stage.layout ∉ E.compStages) :
    (frameWork E (flipMid (P := P) m)).lt (frameWork E (origMid oc)) := by
  refine ⟨⟨fun s => ?_, Nat.zero_le _⟩, ?_⟩
  · obtain ⟨v1, v2, -⟩ := flipMid_work (P := P) E m s
    obtain ⟨o1, o2, -⟩ := origMid_work E oc s
    rw [v1, v2, o1, o2]
    by_cases hs : s ∈ E.compStages
    · have := hc s hs
      by_cases h0 : 0 < m <;> simp [hs, this, h0] <;> omega
    · simp [hs]
  · refine Or.inl ⟨.layout, Or.inl ?_⟩
    rw [(flipMid_work (P := P) E m .layout).1, (origMid_work E oc .layout).1]
    simp [hL, hLc]

/-- A stage table restating the Chromium `layoutFull` row with one compositor stage `comp` and base `props`, for the
examples below. $$E_0 = \big((),\ \_ \mapsto [\mathrm{style}, \mathrm{layout}, \mathrm{props}, \mathrm{paint}, \mathrm{raster}, \mathrm{commit}],\ [\mathrm{comp}],\ [\mathrm{props}]\big)$$ -/
def layoutTable : Engine Unit Unit :=
  ⟨(), fun _ => [.style, .layout, .props, .paint, .raster, .commit], [.comp], [.props]⟩

/-- The example size change. $$\mathit{oc}_0 = (0, (), \mathrm{none})$$ -/
def oc0 : Change Unit := ⟨0, (), .none⟩

#guard (frameWork layoutTable (flipMid (P := Unit) 3)).passes .layout == 0
#guard (frameWork layoutTable (origMid oc0)).passes .layout == 1
#guard (frameWork layoutTable (flipMid (P := Unit) 3)).units .comp == 3
#guard (frameWork layoutTable (origMid oc0)).passes .comp == 0
#guard !(frameWork layoutTable (flipMid (P := Unit) 1)).leb (frameWork layoutTable (origMid oc0))
#guard (frameWork layoutTable (flipMid (P := Unit) 0)).ltb (frameWork layoutTable (origMid oc0))

end Flip

end Fw.Parts.PeopleO
