/-!
# pain: geometry of the Pain section (P3, `faithful` port)

Restated (not copied) from the original snapshot `snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css`:

* 2166-2176 `.pain`: `margin-top: -100svh`, no padding, `position: relative`;
* 2177-2193 `.pain-sticky`: `min-height: 100svh`, padding `96px 56px 80px`, flex column centre; `.pain-hold`: `height: 200svh`;
* 2201-2212 `.pain-inner`: `max-width: 780px`, `width: 100%`, gap 48 px; 2213-2238 `.pain-copy`: `h2` 48 px / 1.15, gap 16 px, `p` 24 px;
* 2239-2244 `.pain-notes`: `aspect-ratio: 780 / 528`, `width: 100%`, `max-width: 780px`;
* 2305-2357 `@media (width<=860px)`: `.pain-notes { display: none }`, sticky padding 0.

and from the script `nodes/2.DyWL8TcE.js:4592-4645` (`le`) the container test `t.width < 1100` that picks the extra-note
placement. All values `Rat` (viewport widths and heights can be fractional). Pure geometry only; the notes' logic is in
`Fw.Parts.PainNotes`.
-/
namespace Fw.Parts.Pain

/-- Horizontal padding of `.pain-sticky` on the desktop layout (CSS 2185). $$p_x = 56$$ Each side, px. -/
def padX : Rat := 56

/-- Widest the notes stage can be (CSS 2208, 2242). $$m = 780$$ px. -/
def maxInner : Rat := 780

/-- The width where the layout turns to the narrow one (CSS 2305). $$b = 860$$ px; `(width<=860px)` is narrow. -/
def narrowMax : Rat := 860

/-- The width test of the original's placement (JS 4622). $$\theta = 1100$$ px. -/
def containerSplit : Rat := 1100

/-- Aspect of the notes stage (CSS 2240). $$\rho = 528/780$$ Height over width. -/
def aspect : Rat := 528 / 780

/-- Width of `.pain-notes` (the spacer; the notes' canvas is `canvasW`) at a viewport width.

$$\operatorname{boardW}(W) = \begin{cases} 0 & W \le 860 \quad (\texttt{display:none}) \\ \min(780,\ W - 2 \cdot 56) & W > 860 \end{cases}$$

The sticky box is `W` wide with 56 px padding; the inner column fills it up to 780 px. -/
def boardW (W : Rat) : Rat := if W ≤ narrowMax then 0 else min maxInner (W - 2 * padX)

/-- Height of the stage. $$\operatorname{boardH}(W) = \tfrac{528}{780} \cdot \operatorname{boardW}(W)$$ From `aspect-ratio`. -/
def boardH (W : Rat) : Rat := aspect * boardW W

#guard boardW 860 == 0
#guard boardW 861 == 749
#guard boardW 892 == 780
#guard boardW 1440 == 780
#guard boardH 1440 == 528

/-- Width of the canvas the notes live in (`.pain-canvas`, inset 0 over the sticky box; the script's `x`, JS 4751).

$$\operatorname{canvasW}(W) = \max(W, 320)$$

The page is never narrower than 320 px. -/
def canvasW (W : Rat) : Rat := max W 320

/-- The placement the script picks (JS 4622): jittered below a canvas width of 1100 px, scored from 1100 px up.

$$\operatorname{scored}(W) \iff \operatorname{canvasW}(W) \ge 1100$$ -/
def scored (W : Rat) : Bool := decide (containerSplit ≤ canvasW W)

#guard scored 1099 == false
#guard scored 1100 == true
#guard scored 100 == false

/-- The scored placement runs exactly from a viewport width of 1100 px.

$$\operatorname{scored}(W) \iff W \ge 1100$$

So `js.pain-container-1100` is the width edge 1099 / 1100 of the viewport. -/
theorem scored_iff (W : Rat) : scored W = true ↔ 1100 ≤ W := by
  unfold scored canvasW containerSplit
  simp only [decide_eq_true_eq]
  grind

/-- The canvas is wide enough for the layout at every width, narrow or not.

$$\forall W \in \mathbb{Q}:\ \operatorname{canvasW}(W) \ge 8$$

So the narrow base layout (JS 4559-4574) does run; the hidden board spacer is not the script's stage. -/
theorem canvasW_ge (W : Rat) : 8 ≤ canvasW W := by
  unfold canvasW
  grind

/-- The board spacer is hidden up to 860 px.

$$W \le 860 \Rightarrow \operatorname{boardW}(W) = 0$$ -/
theorem boardW_narrow (W : Rat) (h : W ≤ narrowMax) : boardW W = 0 := by
  simp [boardW, h]

/-- Above 860 px the stage is wider than 748 px.

$$W > 860 \Rightarrow 748 < \operatorname{boardW}(W) \le 780$$

So it is always wide enough for the placement to run (`>= 8`). -/
theorem boardW_wide (W : Rat) (h : narrowMax < W) : 748 < boardW W ∧ boardW W ≤ maxInner := by
  unfold narrowMax at h
  have hn : ¬ W ≤ narrowMax := by unfold narrowMax; grind
  unfold boardW
  simp only [hn, ite_false]
  unfold maxInner padX
  grind

/-! ## Section height -/

/-- Height of the content of `.pain-sticky` on the desktop layout (copy + gap + stage + vertical padding).

$$c(W) = 96 + 80 + (\underbrace{48 \cdot 1.15}_{h_2} + 16 + 24) + 48 + \operatorname{boardH}(W)$$

with `h2` one line (55.2 px). -/
def desktopContent (W : Rat) : Rat := 96 + 80 + (48 * 23 / 20 + 16 + 24) + 48 + boardH W

/-- Height of `.pain-sticky`: at least `100svh`, taller when the desktop content is.

$$\operatorname{sticky}(s, W) = \max(s,\ c(W)) \text{ for } W > 860,\qquad s \text{ otherwise}$$

where `s` is the small viewport height in px (the narrow content is far shorter than `s`, so it never wins). -/
def stickyHeight (s W : Rat) : Rat := if W ≤ narrowMax then s else max s (desktopContent W)

/-- Height of the whole section: the sticky box plus `200svh` of hold.

$$H(s, W) = \operatorname{sticky}(s, W) + 2s$$

The scroll length the pin lasts. -/
def sectionHeight (s W : Rat) : Rat := stickyHeight s W + 2 * s

#guard sectionHeight 900 1440 == 2700
#guard sectionHeight 600 1440 == 600 + 2 * 600 + (desktopContent 1440 - 600)

/-- The section is never shorter than `300svh`.

$$\forall s, W:\quad H(s, W) \ge 3s$$ -/
theorem sectionHeight_ge (s W : Rat) : 3 * s ≤ sectionHeight s W := by
  unfold sectionHeight stickyHeight
  split <;> grind

/-- On a viewport tall enough for the content the section is exactly `300svh`.

$$c(W) \le s \Rightarrow H(s, W) = 3s$$ -/
theorem sectionHeight_tall (s W : Rat) (h : desktopContent W ≤ s) : sectionHeight s W = 3 * s := by
  unfold sectionHeight stickyHeight
  split <;> grind

/-- The section's top margin pulls it up over the previous section by one viewport.

$$m_{top} = -s$$ (CSS 2173), so the pin starts when the previous section ends. -/
def marginTop (s : Rat) : Rat := -s

/-- Height of the canvas. $$\operatorname{canvasH}(s, W) = \operatorname{sticky}(s, W)$$ It fills the sticky box. -/
def canvasH (s W : Rat) : Rat := stickyHeight s W

end Fw.Parts.Pain
