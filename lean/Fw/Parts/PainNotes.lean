import Fw.Parts.MorphTween
import Fw.Parts.Pain
/-!
# pain.notes: the sticky notes of the Pain section (P3 `faithful` port)

Restated (not copied) from the original snapshot:

* `snapshot/site-pretty/_app/immutable/nodes/2.DyWL8TcE.js`
  * 4416-4417 palette `c` (7 colours) and rotations `u` (16 values); 4418-4421 text pool `d`;
  * 4422-4464 the five desktop base notes `v` and their sizes `p`, `m`, `h`; 4425 `g` (centre offset);
  * 4488-4504 clamp `L`, overlap `te`; 4505-4510 `re` (the box kept clear around the copy);
  * 4511-4534 `ie` (scored placement, canvas width 1100 px and up, `Fw.Parts.Pain.scored_iff`); 4535-4548 `ae` (jittered
    placement below it); 4549-4554 `oe` (text pick); 4555-4589 `ce` (base layout, desktop and narrow; the stage `x` is the canvas `.pain-canvas`, JS 4751);
  * 4590-4646 `le` (the 3 s tick: guards, clear rule, add); 4647-4688 `W`, `ue` (drag and keyboard);
  * 4698-4703 the intersection rule (`threshold 0.12`), 4696 `setInterval(le, 3e3)`;
* `snapshot/site-pretty/_app/immutable/assets/2.gBuqKVzi.css` 2273-2277, 2293-2298 `pain-note-stick` (0.56 s,
  `cubic-bezier(0.33, 1, 0.68, 1)`, `opacity 0 -> 1`, `scale 1.14 -> 1`).

The original draws with `Math.random()` (and shuffles with a random comparator). The faithful port draws from a
seeded `mulberry32` stream instead (PLAN section 4.3: otherwise no two captures match) and shuffles by drawing
without replacement. Everything else is the original's rule. All numbers are `Rat` (percent of the stage, px).
-/
namespace Fw.Parts.PainNotes
open Fw.Parts.MorphTween (ease ease_mem)

/-! ## Constants -/

/-- Side of a note in px (JS 4569, 4584, 4638). $$a = 240$$ Width and height of every note. -/
def noteSize : Rat := 240

/-- Extra notes shown at most (JS 4594). $$N_{\max} = 12$$ The tick stops adding at 12. -/
def maxExtras : Nat := 12

/-- Period of the add tick in ms (JS 4696). $$T = 3000$$ -/
def intervalMs : Nat := 3000

/-- Share of the section that must show for the tick to run (JS 4700). $$\rho = 0.12 = \tfrac{3}{25}$$ -/
def visibleRatio : Rat := 3 / 25

/-- The commission card clears the extras once its top is above this share of the viewport (JS 4600).
$$\kappa = 0.995 = \tfrac{199}{200}$$ -/
def cardCut : Rat := 199 / 200

/-- Smallest stage side the layout accepts, px (JS 4558, 4605). $$\mu = 8$$ -/
def minStage : Rat := 8

/-- Jitter span in percent (JS 4541). $$J = 3.5 = \tfrac{7}{2}$$ A start point moves by $(r - \tfrac12) J$. -/
def jitterSpan : Rat := 7 / 2

/-- Keyboard step in percent (JS 4672). $$k = 1.5 = \tfrac{3}{2}$$ -/
def keyStep : Rat := 3 / 2

/-- Colours of the extras (JS 4416). $$P = [\#b3efbd, \#ffe299, \#b3f4ef, \#d3bdff, \#e6e6e6, \#ffafa3, \#ffd3a8]$$ -/
def palette : List String := ["#b3efbd", "#ffe299", "#b3f4ef", "#d3bdff", "#e6e6e6", "#ffafa3", "#ffd3a8"]

/-- Rotations of the extras in degrees (JS 4417). $$R = [-9,-7,-5,-3,-2,2,3,4,5,6,8,-8,7,-4,9,-6]$$ -/
def rotations : List Int := [-9, -7, -5, -3, -2, 2, 3, 4, 5, 6, 8, -8, 7, -4, 9, -6]

/-- Keys of the text pool (JS 4418): indices into the dictionary's `pain.notes`.
$$D = [15,21,16,12,17,13,22,14,18,20,19,23]$$ -/
def textPool : List Nat := [15, 21, 16, 12, 17, 13, 22, 14, 18, 20, 19, 23]

#guard palette.length == 7
#guard rotations.length == 16
#guard textPool.length == 12

/-- Rotation of the $j$-th extra (JS 4634). $$\operatorname{rot}(j) = R[j \bmod 16]$$ -/
def rotation (j : Nat) : Int := rotations.getD (j % 16) (-4)

/-- Every rotation is within 9 degrees. $$\forall j:\ |\operatorname{rot}(j)| \le 9$$ -/
theorem rotation_bound (j : Nat) : -9 ≤ rotation j ∧ rotation j ≤ 9 := by
  have key : ∀ i : Fin 16, -9 ≤ rotations.getD i (-4) ∧ rotations.getD i (-4) ≤ 9 := by decide
  exact key ⟨j % 16, Nat.mod_lt _ (by omega)⟩

/-! ## Clamp, boxes, overlap -/

/-- JS 4488 `L`. $$\operatorname{clamp}(x; l, h) = \min(h, \max(l, x))$$ Hold $x$ in $[l, h]$ (the upper bound wins if $h < l$). -/
def clampTo (x lo hi : Rat) : Rat := min hi (max lo x)

/-- The clamp never exceeds the upper bound. $$\operatorname{clamp}(x; l, h) \le h$$ -/
theorem clampTo_le (x lo hi : Rat) : clampTo x lo hi ≤ hi := by unfold clampTo; grind

/-- The clamp reaches the lower bound when the interval is not empty. $$l \le h \Rightarrow l \le \operatorname{clamp}(x; l, h)$$ -/
theorem clampTo_ge (x lo hi : Rat) (h : lo ≤ hi) : lo ≤ clampTo x lo hi := by unfold clampTo; grind

/-- A rectangle in percent of the stage. $$B = (\ell, t, w, h) \in \mathbb{Q}^4$$ Left, top, width, height. -/
structure Box where
  left : Rat
  top : Rat
  width : Rat
  height : Rat
deriving Repr, BEq, DecidableEq

/-- JS 4491 `te`: the rectangles come within `gap` of each other.

$$\operatorname{overlap}_g(a, b) \iff \lnot\big(a_\ell + a_w + g \le b_\ell \lor b_\ell + b_w + g \le a_\ell \lor a_t + a_h + g \le b_t \lor b_t + b_h + g \le a_t\big)$$ -/
def overlaps (a b : Box) (gap : Rat) : Bool :=
  !(decide (a.left + a.width + gap ≤ b.left) || decide (b.left + b.width + gap ≤ a.left) ||
    decide (a.top + a.height + gap ≤ b.top) || decide (b.top + b.height + gap ≤ a.top))

#guard overlaps ⟨0, 0, 10, 10⟩ ⟨5, 5, 10, 10⟩ 0 == true
#guard overlaps ⟨0, 0, 10, 10⟩ ⟨10, 0, 10, 10⟩ 0 == false
#guard overlaps ⟨0, 0, 10, 10⟩ ⟨10, 0, 10, 10⟩ (1 / 2) == true
#guard overlaps ⟨0, 0, 10, 10⟩ ⟨10.2, 0, 10, 10⟩ 1 == true

/-- Overlap is symmetric. $$\operatorname{overlap}_g(a, b) = \operatorname{overlap}_g(b, a)$$ -/
theorem overlaps_symm (a b : Box) (g : Rat) : overlaps a b g = overlaps b a g := by
  apply Bool.eq_iff_iff.mpr
  simp only [overlaps, Bool.not_eq_true', Bool.or_eq_false_iff, decide_eq_false_iff_not]
  grind

/-- A larger gap only adds overlaps. $$0 \le g \le g' \land \operatorname{overlap}_g(a, b) \Rightarrow \operatorname{overlap}_{g'}(a, b)$$ -/
theorem overlaps_gap_mono (a b : Box) (g g' : Rat) (h : g ≤ g') (o : overlaps a b g = true) :
    overlaps a b g' = true := by
  simp only [overlaps, Bool.not_eq_eq_eq_not, Bool.not_true, Bool.or_eq_false_iff, decide_eq_false_iff_not] at o ⊢
  grind

/-- Boxes that stand side by side do not overlap at gap 0.
$$a_\ell + a_w \le b_\ell \Rightarrow \lnot\operatorname{overlap}_0(a, b)$$ -/
theorem overlaps_apart_x (a b : Box) (h : a.left + a.width ≤ b.left) : overlaps a b 0 = false := by
  unfold overlaps
  simp only [Bool.not_eq_eq_eq_not, Bool.not_false, Bool.or_eq_true, decide_eq_true_eq]
  grind

/-- JS 4505 `re`: the box kept clear around the copy block, in percent of the stage.

$$n = \tfrac{c_t - s_t - 36}{s_h}\cdot 100,\quad r = \tfrac{c_h + 72}{s_h}\cdot 100,\quad i = \max(0, n),\quad
  \operatorname{avoid} = (0,\ i,\ 100,\ \min(100 - i,\ r))$$

with $c$ the copy rect and $s$ the stage rect. -/
def avoidBox (copyTop copyH stageTop stageH : Rat) : Box :=
  let n := (copyTop - stageTop - 36) / stageH * 100
  let r := (copyH + 72) / stageH * 100
  let i := max 0 n
  ⟨0, i, 100, min (100 - i) r⟩

#guard avoidBox 100 100 0 500 == ⟨0, 12.8, 100, min 87.2 34.4⟩

/-- The avoid box spans the whole stage width and starts at the top or below.
$$\operatorname{avoid}_\ell = 0 \land \operatorname{avoid}_w = 100 \land \operatorname{avoid}_t \ge 0$$ -/
theorem avoidBox_shape (a b c d : Rat) :
    (avoidBox a b c d).left = 0 ∧ (avoidBox a b c d).width = 100 ∧ 0 ≤ (avoidBox a b c d).top := by
  unfold avoidBox
  simp only
  grind

/-! ## Base layout -/

/-- Size class of a base note (JS 4422-4424).

$$K = \{p, m, h\},\quad p = (255.878, 252.167),\ m = (248.09, 244.232),\ h = (263.354, 259.794)$$ -/
inductive Kind where
  | p | m | h
deriving Repr, BEq, DecidableEq

/-- Width and height in px of a size class.

$$\operatorname{size}(k) = (w_k, h_k) \in \mathbb{Q}^2$$ -/
def Kind.size : Kind → Rat × Rat
  | .p => (255878 / 1000, 252167 / 1000)
  | .m => (24809 / 100, 244232 / 1000)
  | .h => (263354 / 1000, 259794 / 1000)

/-- A base note of the desktop layout (JS 4428-4464).

$$b = (x, y, k, \mathit{text}, \mathit{bg}, \theta, z)$$

Position in px of the original design canvas ($x, y$ before the `g` offset), size class, text key, colour, rotation, z-index. -/
structure Base where
  x : Rat
  y : Rat
  kind : Kind
  text : Nat
  bg : String
  rotate : Int
  z : Nat
deriving Repr, BEq

/-- The five desktop base notes, in z order (JS 4428-4464).

$$\mathrm{base} = [b_1, \dots, b_5],\quad z(b_i) = i$$ -/
def baseNotes : List Base :=
  [⟨330, 2927411193847656 / 10000000000000, .p, 12, "#b3efbd", -4, 1⟩,
   ⟨799, 2663758850097656 / 10000000000000, .m, 14, "#ffafa3", -2, 2⟩,
   ⟨560462890625 / 1000000000, 3139999084472656 / 10000000000000, .p, 13, "#d3bdff", 4, 3⟩,
   ⟨677, 4797415466308594 / 10000000000000, .p, 15, "#b3f4ef", -4, 4⟩,
   ⟨4304625244140625 / 10000000000000, 499, .p, 16, "#ffe299", 4, 5⟩]

/-- JS 4426 `g`: top-left of a note's box so that its centre sits at the design point, in px.

$$\ell_{px} = x + \tfrac{w}{2} - 120,\qquad t_{px} = y + \tfrac{h}{2} - 120$$ -/
def Base.leftPx (b : Base) : Rat := b.x + b.kind.size.1 / 2 - 120

/-- See `leftPx`. $$t_{px} = y + \tfrac{h}{2} - 120$$ -/
def Base.topPx (b : Base) : Rat := b.y + b.kind.size.2 / 2 - 120

/-- JS 4582-4583: left in percent of the stage, the 1440 x 868 design canvas centred on it.

$$\operatorname{left}(W_s, \ell_{px}) = \frac{(W_s - 1440)/2 + \ell_{px}}{W_s}\cdot 100$$ -/
def baseLeft (stageW leftPx : Rat) : Rat := ((stageW - 1440) / 2 + leftPx) / stageW * 100

/-- JS 4583: top in percent. $$\operatorname{top}(H_s, t_{px}) = \frac{(H_s - 868)/2 + t_{px}}{H_s}\cdot 100$$ -/
def baseTop (stageH topPx : Rat) : Rat := ((stageH - 868) / 2 + topPx) / stageH * 100

#guard baseLeft 1440 100 == 100 / 1440 * 100
#guard baseTop 868 0 == 0

/-- On a stage exactly as large as the design canvas the percent is the design px over the canvas.
$$\operatorname{left}(1440, \ell) = \tfrac{\ell}{1440} \cdot 100$$ -/
theorem baseLeft_design (l : Rat) : baseLeft 1440 l = l / 1440 * 100 := by
  unfold baseLeft; grind

/-- The layout of one base note at stage size $(W_s, H_s)$ px.

$$\operatorname{place}(b) = \big(\operatorname{left}(W_s, \ell_{px}(b)),\ \operatorname{top}(H_s, t_{px}(b))\big)$$ -/
def Base.place (b : Base) (stageW stageH : Rat) : Rat × Rat :=
  (baseLeft stageW b.leftPx, baseTop stageH b.topPx)

/-- The eleven notes of the narrow layout, in z order (JS 4465-4477).

$$\mathrm{narrow} = [b'_1, \dots, b'_{11}],\quad z(b'_i) = i$$ -/
def narrowNotes : List Base :=
  [⟨218, 353, .p, 15, "#b3f4ef", -4, 1⟩, ⟨15, 437, .h, 21, "#e6e6e6", -6, 2⟩, ⟨392, 401, .p, 16, "#ffe299", 4, 3⟩,
   ⟨218, 479, .p, 12, "#b3efbd", -4, 4⟩, ⟨604, 460, .p, 17, "#e6e6e6", 4, 5⟩, ⟨413, 496, .p, 13, "#d3bdff", 4, 6⟩,
   ⟨36, 588, .p, 22, "#d3bdff", 4, 7⟩, ⟨303, 578, .m, 14, "#ffafa3", -2, 8⟩, ⟨215, 675, .p, 18, "#ffd3a8", -4, 9⟩,
   ⟨566, 591, .m, 20, "#b3efbd", -2, 10⟩, ⟨390, 664, .p, 19, "#ffe299", 4, 11⟩]

/-- JS 4566: left in percent in the narrow layout, the 860 px design canvas centred on the stage.

$$\operatorname{leftN}(W_s, \ell_{px}) = \frac{(W_s - 860)/2 + \ell_{px}}{W_s}\cdot 100$$ -/
def narrowLeft (stageW leftPx : Rat) : Rat := ((stageW - 860) / 2 + leftPx) / stageW * 100

/-- JS 4567: top in percent in the narrow layout, 16 px up.

$$\operatorname{topN}(H_s, t_{px}) = \frac{t_{px} - 16}{H_s}\cdot 100$$ -/
def narrowTop (stageH topPx : Rat) : Rat := (topPx - 16) / stageH * 100

/-! ## The tick -/

/-- What one tick does. $$\mathrm{skip} \mid \mathrm{clear} \mid \mathrm{add}$$ -/
inductive Tick where
  | skip | clear | add
deriving Repr, BEq, DecidableEq

/-- The guard at the top of `le` (JS 4591-4598), true when the tick goes on.

$$\operatorname{go} = \mathrm{visible} \land \lnot\mathrm{dragging} \land n_x < 12 \land \lnot\mathrm{narrow} \land \lnot\mathrm{reduced}$$

`narrow` is `(width<=860px)`, `reduced` is `(prefers-reduced-motion: reduce)`, `n_x` the number of extras. -/
def go (visible dragging : Bool) (extras : Nat) (narrow reduced : Bool) : Bool :=
  visible && !dragging && decide (extras < maxExtras) && !narrow && !reduced

/-- JS 4590-4646 `le`, the decision before any randomness.

$$\operatorname{tick} = \begin{cases} \mathrm{skip} & \lnot\operatorname{go} \\ \mathrm{clear} & \operatorname{go} \land \exists c:\ c < 0.995 v \\ \mathrm{skip} & \operatorname{go} \land (W_s < 8 \lor H_s < 8) \\ \mathrm{add} & \text{otherwise} \end{cases}$$

`cardTop` is the top of `.commission-card` when it exists, `v` the viewport height. -/
def tick (visible dragging : Bool) (extras : Nat) (narrow reduced : Bool) (cardTop : Option Rat) (vh stageW stageH : Rat) : Tick :=
  if !go visible dragging extras narrow reduced then .skip
  else if (cardTop.map fun t => decide (t < vh * cardCut)).getD false then .clear
  else if decide (stageW < minStage) || decide (stageH < minStage) then .skip
  else .add

#guard tick true false 0 false false none 900 780 528 == .add
#guard tick true false 12 false false none 900 780 528 == .skip
#guard tick true false 3 false false (some 800) 900 780 528 == .clear
#guard tick true false 3 false false (some 900) 900 780 528 == .add
#guard tick true false 3 true false none 900 780 528 == .skip

/-- At 12 extras the tick adds nothing. $$n_x \ge 12 \Rightarrow \operatorname{tick} = \mathrm{skip}$$ -/
theorem tick_full (vis drag : Bool) (n : Nat) (nar red : Bool) (c : Option Rat) (v w h : Rat) (hn : maxExtras ≤ n) :
    tick vis drag n nar red c v w h = .skip := by
  unfold tick go
  have : ¬ n < maxExtras := by omega
  simp [this]

/-- While a note is being dragged the tick does nothing. $$\mathrm{dragging} \Rightarrow \operatorname{tick} = \mathrm{skip}$$ -/
theorem tick_dragging (vis : Bool) (n : Nat) (nar red : Bool) (c : Option Rat) (v w h : Rat) :
    tick vis true n nar red c v w h = .skip := by
  simp [tick, go]

/-- Under reduced motion the tick does nothing. $$\mathrm{reduced} \Rightarrow \operatorname{tick} = \mathrm{skip}$$ -/
theorem tick_reduced (vis drag : Bool) (n : Nat) (nar : Bool) (c : Option Rat) (v w h : Rat) :
    tick vis drag n nar true c v w h = .skip := by
  simp [tick, go]

/-- Narrow layout: the tick does nothing. $$\mathrm{narrow} \Rightarrow \operatorname{tick} = \mathrm{skip}$$ -/
theorem tick_narrow (vis drag : Bool) (n : Nat) (red : Bool) (c : Option Rat) (v w h : Rat) :
    tick vis drag n true red c v w h = .skip := by
  simp [tick, go]

/-- When the tick adds, there was room: fewer than 12 extras, so there are at most 12 afterwards.
$$\operatorname{tick} = \mathrm{add} \Rightarrow n_x < 12$$ -/
theorem tick_add_room (vis drag : Bool) (n : Nat) (nar red : Bool) (c : Option Rat) (v w h : Rat)
    (h' : tick vis drag n nar red c v w h = .add) : n < maxExtras := by
  cases Nat.lt_or_ge n maxExtras with
  | inl hn => exact hn
  | inr hn =>
    have := tick_full vis drag n nar red c v w h hn
    rw [this] at h'
    cases h'

/-- The intersection rule (JS 4700): the tick runs while the section shows at least 12 %.
$$\operatorname{visible}(i, r) \iff i \land r \ge 0.12$$ -/
def visible (intersecting : Bool) (ratio : Rat) : Bool := intersecting && decide (visibleRatio ≤ ratio)

/-! ## Randomness -/

/-- A 32-bit word as a number in the half-open unit interval. $$u(o) = o / 2^{32}$$ -/
def unit (o : UInt32) : Rat := (o.toNat : Rat) / 4294967296

/-- A scaled 32-bit word lies in the unit interval. $$0 \le u(o) < 1$$ -/
theorem unit_range (o : UInt32) : 0 ≤ unit o ∧ unit o < 1 := by
  unfold unit
  have h := UInt32.toNat_lt o
  have h0 : (0 : Rat) ≤ (o.toNat : Rat) := by exact_mod_cast Nat.zero_le _
  have h1 : (o.toNat : Rat) < 4294967296 := by exact_mod_cast h
  constructor
  · grind
  · rw [Rat.div_lt_iff (by decide)]; grind

/-- Seeded stream (`mulberry32`), the spec of the port's replacement for `Math.random()`.

$$a' = a + \mathtt{0x6D2B79F5} \pmod{2^{32}},\ t_1 = (a' \oplus a'\!\gg\!15)\cdot(a' \mathbin{|} 1),\
t_2 = t_1 + (t_1 \oplus t_1\!\gg\!7)\cdot(t_1 \mathbin{|} 61) \oplus t_1,\ \mathrm{out} = (t_2 \oplus t_2\!\gg\!14)/2^{32}$$

all in unsigned 32-bit arithmetic (wrapping). Returns the new state and the draw. -/
def mulberry (s : UInt32) : UInt32 × Rat :=
  let a := s + 0x6D2B79F5
  let t := (a ^^^ (a >>> 15)) * (a ||| 1)
  let t := (t + (t ^^^ (t >>> 7)) * (t ||| 61)) ^^^ t
  let o := t ^^^ (t >>> 14)
  (a, unit o)

/-- Every draw lies in $[0, 1)$. $$0 \le r < 1$$ -/
theorem mulberry_range (s : UInt32) : 0 ≤ (mulberry s).2 ∧ (mulberry s).2 < 1 := by
  unfold mulberry
  exact unit_range _

/-- The monad of the stream: its state is the 32-bit generator word.

$$\mathrm{Rng}(\alpha) = \mathbb{N}_{<2^{32}} \to \alpha \times \mathbb{N}_{<2^{32}}$$ -/
abbrev Rng := StateM UInt32

/-- Draw a value in the unit interval and advance the stream.

$$\operatorname{draw}(s) = (u(\mathrm{out}(s')),\ s'),\quad s' = s + \mathtt{0x6D2B79F5}$$ -/
def draw : Rng Rat := do
  let s ← get
  let (s', r) := mulberry s
  set s'
  pure r

/-- Index of a draw in a list of length $n$ (the original's `Math.floor(Math.random() * n)`).
$$\operatorname{idx}(r, n) = \lfloor r \cdot n \rfloor$$ -/
def idx (r : Rat) (n : Nat) : Nat := (r * n).floor.toNat

/-- A draw in $[0,1)$ indexes inside a non-empty list. $$0 \le r < 1,\ n > 0 \Rightarrow \operatorname{idx}(r, n) < n$$ -/
theorem idx_lt (r : Rat) (n : Nat) (h0 : 0 ≤ r) (h1 : r < 1) (hn : 0 < n) : idx r n < n := by
  unfold idx
  have hnq : (0 : Rat) < n := by exact_mod_cast hn
  have a : r * n < n := by
    have := Rat.mul_lt_mul_of_pos_right h1 hnq
    grind
  have b : (r * n).floor < (n : Int) := Rat.floor_lt_iff.mpr (by exact_mod_cast a)
  have c : 0 ≤ (r * n).floor := Rat.le_floor_iff.mpr (by
    have : (0 : Rat) ≤ r * n := Rat.mul_nonneg h0 (Rat.le_of_lt hnq)
    simpa using this)
  omega

/-- Draw without replacement: the permutation of `xs` driven by the draws `rs` (one per element).

$$\operatorname{perm}(r{::}rs, xs) = xs[\operatorname{idx}(r, |xs|)] \mathbin{::} \operatorname{perm}(rs, xs \setminus \text{that one})$$

Stands in for the original's `[...e].sort(() => Math.random() - 0.5)` (JS 4537), which has no fixed spec. -/
def permute {α : Type} : List Rat → List α → List α
  | [], xs => xs
  | r :: rs, xs =>
    match xs[idx r xs.length]? with
    | some x => x :: permute rs (xs.eraseIdx (idx r xs.length))
    | none => xs

/-- A permutation keeps the length when there is a draw per element and every draw is in $[0,1)$.
$$|xs| \le |rs| \land \forall r \in rs,\ r \in [0,1) \Rightarrow |\operatorname{perm}(rs, xs)| = |xs|$$ -/
theorem permute_length {α : Type} (rs : List Rat) (xs : List α) (hr : ∀ r ∈ rs, 0 ≤ r ∧ r < 1)
    (hl : xs.length ≤ rs.length) : (permute rs xs).length = xs.length := by
  induction rs generalizing xs with
  | nil =>
    simp at hl
    simp [permute, List.length_eq_zero_iff.mpr hl]
  | cons r rs ih =>
    unfold permute
    by_cases hx : xs = []
    · subst hx; simp
    · have hpos : 0 < xs.length := List.length_pos_iff.mpr hx
      have hi := idx_lt r xs.length (hr r (by simp)).1 (hr r (by simp)).2 hpos
      have hsome : xs[idx r xs.length]? = some xs[idx r xs.length] := List.getElem?_eq_getElem hi
      rw [hsome]
      simp only [List.length_cons]
      have := ih (xs.eraseIdx (idx r xs.length)) (fun q hq => hr q (by simp [hq]))
        (by simp [List.length_eraseIdx, hi]; simp at hl; omega)
      rw [this]
      simp [List.length_eraseIdx, hi]
      omega

/-- `n` draws in a row.

$$\operatorname{draws}(n) = [r_1, \dots, r_n],\quad r_i = \text{the } i\text{-th draw}$$ -/
def draws : Nat → Rng (List Rat)
  | 0 => pure []
  | n + 1 => do
    let r ← draw
    let rs ← draws n
    pure (r :: rs)

/-! ## Placement -/

/-- One jittered start (JS 4541-4542): the candidate's coordinate plus $(r - \tfrac12) \cdot 3.5$, held in $[0, \max(0, 100 - s)]$.

$$\operatorname{jit}(c, r, s) = \operatorname{clamp}\big(c + (r - \tfrac12)\tfrac72;\ 0,\ \max(0, 100 - s)\big)$$ -/
def jit (c r s : Rat) : Rat := clampTo (c + (r - 1 / 2) * jitterSpan) 0 (max 0 (100 - s))

/-- A jittered start stays inside the stage. $$0 \le \operatorname{jit}(c, r, s) \le \max(0, 100 - s)$$ -/
theorem jit_mem (c r s : Rat) : 0 ≤ jit c r s ∧ jit c r s ≤ max 0 (100 - s) := by
  unfold jit clampTo
  grind

/-- The fallback (JS 4546-4547): the first candidate, held inside the stage without jitter.
$$\operatorname{fb}(c) = (\operatorname{clamp}(c_\ell; 0, \max(0, 100 - w)),\ \operatorname{clamp}(c_t; 0, \max(0, 100 - h)))$$ -/
def fallback (c : Box) (w h : Rat) : Rat × Rat :=
  (clampTo c.left 0 (max 0 (100 - w)), clampTo c.top 0 (max 0 (100 - h)))

/-- Try the shuffled candidates in order (JS 4540-4545).

$$\operatorname{try}(c{::}cs) = \begin{cases} (\ell, t) & \text{no avoid box overlaps } (\ell, t, w, h) \\ \operatorname{try}(cs) & \text{otherwise} \end{cases},\quad \ell = \operatorname{jit}(c_\ell, r_1, w),\ t = \operatorname{jit}(c_t, r_2, h)$$

Each candidate consumes two draws, left then top; the first jittered box that does not overlap the avoid boxes at gap 0 wins; `none` when all collide. -/
def tryCands (w h : Rat) (avoid : List Box) : List Box → Rng (Option (Rat × Rat))
  | [] => pure none
  | c :: cs => do
    let r1 ← draw
    let r2 ← draw
    let l := jit c.left r1 w
    let t := jit c.top r2 h
    if avoid.any (fun a => overlaps ⟨l, t, w, h⟩ a 0) then tryCands w h avoid cs else pure (some (l, t))

/-- JS 4535 `ae`: place a new note near an existing one.

$$\operatorname{place}(C) = \begin{cases} \bot & C = \emptyset \\ p & \operatorname{try}(\operatorname{perm}(C)) = p \\ \operatorname{fb}(\operatorname{perm}(C)_0) & \text{otherwise} \end{cases}$$

No candidates: `none`. Otherwise shuffle the candidates, try each, else the fallback of the first shuffled. -/
def place (cands : List Box) (w h : Rat) (avoid : List Box) : Rng (Option (Rat × Rat)) := do
  if cands.isEmpty then pure none
  else
    let rs ← draws cands.length
    let order := permute rs cands
    match ← tryCands w h avoid order with
    | some p => pure (some p)
    | none => pure (order.head?.map fun c => fallback c w h)

/-- A rational as a double (the scored placement is a floating-point rule in the original).
$$\operatorname{f}(q) = \mathrm{num}(q) / \mathrm{den}(q)$$ -/
def ratF (q : Rat) : Float := Float.ofInt q.num / Float.ofNat q.den

/-- Distance between box centres (JS 4499 `B`, with `sqrt` of the sum of squares).

$$\operatorname{dist}(a, b) = \sqrt{(a_c^x - b_c^x)^2 + (a_c^y - b_c^y)^2},\quad a_c = (a_\ell + a_w/2,\ a_t + a_h/2)$$ -/
def dist (a b : Box) : Float :=
  let dx := ratF (a.left + a.width / 2 - (b.left + b.width / 2))
  let dy := ratF (a.top + a.height / 2 - (b.top + b.height / 2))
  Float.sqrt (dx * dx + dy * dy)

/-- A scored candidate. $$c = (\ell, t, \sigma)$$ Position in percent and its score. -/
structure Cand where
  left : Rat
  top : Rat
  score : Float

/-- The smaller of two doubles. $$\min(x, y)$$ -/
def fmin (x y : Float) : Float := if x < y then x else y

/-- One scored candidate (JS 4517-4532), after its two position draws and the avoid test.

$$\sigma = -600 f - 220 p - 180 g + 0.9 m + 2.4 h + 8 r,\quad f, p = \#\text{close base / extra boxes (gap } 1.2),\ g = [h < 0.85 \max(w, h_n)]$$

with $m$ the nearest base centre, $h$ the nearest extra centre ($80$ when there is none). -/
def scoreCand (d : Box) (base extras : List Box) (w hN : Rat) (r : Rat) : Float × Nat × Nat :=
  let f := (base.filter fun e => overlaps d e (6 / 5)).length
  let p := (extras.filter fun e => overlaps d e (6 / 5)).length
  let inf := 1.0 / 0.0
  let m := base.foldl (fun acc e => fmin acc (dist d e)) inf
  let h0 := extras.foldl (fun acc e => fmin acc (dist d e)) inf
  let h := if h0 == inf then 80.0 else h0
  let g : Float := if h < ratF (max w hN) * 0.85 then 1.0 else 0.0
  (-(Float.ofNat f) * 600.0 - Float.ofNat p * 220.0 - g * 180.0 + m * 0.9 + h * 2.4 + ratF r * 8.0, f, p)

/-- The 120 tries of the scored placement (JS 4516-4532): two position draws, skip when the box meets an avoid box,
else one more draw for the jitter term; keep the best clean candidate (no close box) and the best of all.

$$(s, c) = \operatorname{loop}_n(s_0, c_0),\quad s' = \arg\max\{\sigma : f = p = 0\},\ c' = \arg\max\{\sigma\}$$ -/
def scoredLoop (w h : Rat) (base avoid extras : List Box) (a o : Rat) :
    Nat → Option Cand → Option Cand → Rng (Option Cand × Option Cand)
  | 0, s, c => pure (s, c)
  | n + 1, s, c => do
    let l := (← draw) * a
    let u := (← draw) * o
    let d : Box := ⟨l, u, w, h⟩
    if avoid.any (fun e => overlaps d e 0) then scoredLoop w h base avoid extras a o n s c
    else
      let r ← draw
      let (sc, f, p) := scoreCand d base extras w h r
      let cand : Cand := ⟨l, u, sc⟩
      let s' := if f == 0 && p == 0 && (match s with | none => true | some b => b.score < sc) then some cand else s
      let c' := if (match c with | none => true | some b => b.score < sc) then some cand else c
      scoredLoop w h base avoid extras a o n s' c'

/-- JS 4511 `ie`: the scored placement used on a canvas of 1100 px or more.

$$\operatorname{scoredPlace} = s \mathbin{??} c,\quad (s, c) = \operatorname{loop}_{120}$$

with $a = \max(0, 100 - w)$ and $o = \max(0, 100 - h)$ the room for the corner. -/
def scoredPlace (w h : Rat) (base avoid extras : List Box) : Rng (Option (Rat × Rat)) := do
  let (s, c) ← scoredLoop w h base avoid extras (max 0 (100 - w)) (max 0 (100 - h)) 120 none none
  pure ((s <|> c).map fun b => (b.left, b.top))

/-- The key a draw selects in a pool.

$$\operatorname{pickIn}(P, r) = P[\lfloor r|P| \rfloor]$$

(15 only if the index were out of range, which a draw in $[0,1)$ never gives, `idx_lt`.) -/
def pickIn (pool : List Nat) (r : Rat) : Nat :=
  match pool[idx r pool.length]? with
  | some k => k
  | none => 15

/-- With a draw in $[0,1)$ the selected key is in a non-empty pool.
$$0 \le r < 1,\ P \ne \emptyset \Rightarrow \operatorname{pickIn}(P, r) \in P$$ -/
theorem pickIn_mem (pool : List Nat) (r : Rat) (h0 : 0 ≤ r) (h1 : r < 1) (hp : pool ≠ []) : pickIn pool r ∈ pool := by
  have hpos : 0 < pool.length := List.length_pos_iff.mpr hp
  have hi := idx_lt r pool.length h0 h1 hpos
  unfold pickIn
  rw [List.getElem?_eq_getElem hi]
  exact List.getElem_mem hi

/-- JS 4549 `oe`: the text key of a new note: a random key not used on the stage, else any.

$$\operatorname{pick}(U, r) = \begin{cases} F[\lfloor r|F| \rfloor] & F = D \setminus U \ne \emptyset \\ D[\lfloor r|D| \rfloor] & \text{otherwise} \end{cases}$$ -/
def pickText (used : List Nat) (r : Rat) : Nat :=
  let free := textPool.filter fun k => !used.contains k
  pickIn (if free.isEmpty then textPool else free) r

/-- The pick is a key of the pool for a draw in $[0,1)$. $$0 \le r < 1 \Rightarrow \operatorname{pick}(U, r) \in D$$ -/
theorem pickText_mem (used : List Nat) (r : Rat) (h0 : 0 ≤ r) (h1 : r < 1) : pickText used r ∈ textPool := by
  unfold pickText
  simp only
  cases hf : (textPool.filter fun k => !used.contains k).isEmpty
  · have hp : (textPool.filter fun k => !used.contains k) ≠ [] := by
      intro e; rw [e] at hf; simp at hf
    simp only [Bool.false_eq_true, ite_false]
    exact (List.mem_filter.mp (pickIn_mem _ r h0 h1 hp)).1
  · simp only [ite_true]
    exact pickIn_mem _ r h0 h1 (by decide)

/-- A key not yet used is taken whenever one is left and the draw is in $[0,1)$.
$$r \in [0,1),\ \exists k \in D \setminus U \Rightarrow \operatorname{pick}(U, r) \notin U$$ -/
theorem pickText_fresh (used : List Nat) (r : Rat) (h0 : 0 ≤ r) (h1 : r < 1)
    (hex : ∃ k ∈ textPool, k ∉ used) : pickText used r ∉ used := by
  obtain ⟨k, hk, hku⟩ := hex
  have hne : (textPool.filter fun k => !used.contains k).isEmpty = false := by
    rw [List.isEmpty_eq_false_iff_exists_mem]
    exact ⟨k, List.mem_filter.mpr ⟨hk, by simpa using hku⟩⟩
  have hp : (textPool.filter fun k => !used.contains k) ≠ [] := by
    intro e; rw [e] at hne; simp at hne
  unfold pickText
  simp only [hne, Bool.false_eq_true, ite_false]
  have := (List.mem_filter.mp (pickIn_mem _ r h0 h1 hp)).2
  simpa using this

/-! ## Adding a note -/

/-- A note on the stage (JS 4626-4642 and 4428-4464).

$$n = (\mathit{id}, \mathit{text}, \mathit{bg}, \theta, \ell, t, z, \mathit{extra})$$

Position in percent of the stage, size 240 px. -/
structure Note where
  /-- `base-i` or `extra-j` -/
  id : String
  text : Nat
  bg : String
  rotate : Int
  left : Rat
  top : Rat
  z : Nat
  extra : Bool
deriving Repr, BEq

/-- The percent box of a note on a stage of $(W_s, H_s)$ px (JS 4608-4613).
$$\left(\ell,\ t,\ \tfrac{240}{W_s}\cdot 100,\ \tfrac{240}{H_s}\cdot 100\right)$$ -/
def Note.box (n : Note) (stageW stageH : Rat) : Box :=
  ⟨n.left, n.top, noteSize / stageW * 100, noteSize / stageH * 100⟩

/-- The base notes as placed on a stage of $(W_s, H_s)$ px (JS 4555-4588).

$$\operatorname{layout}(\nu, W_s, H_s) = \begin{cases} [(\operatorname{leftN}, \operatorname{topN})(b'_i)]_{i < 11} & \nu \\ [(\operatorname{left}, \operatorname{top})(b_i)]_{i < 5} & \lnot\nu \end{cases}$$

`narrow` is `(width<=860px)`; ids are `base-i`. -/
def baseLayout (narrow : Bool) (stageW stageH : Rat) : List Note :=
  if narrow then
    (narrowNotes.zipIdx).map fun (b, i) =>
      ⟨s!"base-{i}", b.text, b.bg, b.rotate, narrowLeft stageW b.leftPx, narrowTop stageH b.topPx, b.z, false⟩
  else
    (baseNotes.zipIdx).map fun (b, i) =>
      let (l, t) := b.place stageW stageH
      ⟨s!"base-{i}", b.text, b.bg, b.rotate, l, t, b.z, false⟩

/-- JS 4590-4646 `le` after the guards: place, pick, colour. Draw order: below 1100 px the shuffle (one draw per
candidate) then two per tried candidate; from 1100 px the scored loop; then one draw for the text and one for the colour.
`j` is the running extra counter. Returns the new note, or `none` when nothing fits.

$$z = 10 + |E|,\quad \mathrm{rotate} = R[j \bmod 16],\quad \mathrm{bg} = P[\lfloor r\,7 \rfloor],\quad \mathrm{id} = \texttt{extra-}j$$

with $E$ the extras already on the stage. -/
def addExtra (stageW stageH : Rat) (base extras : List Note) (avoid : List Box) (j : Nat) : Rng (Option Note) := do
  let w := noteSize / stageW * 100
  let h := noteSize / stageH * 100
  let bb := base.map fun n => n.box stageW stageH
  let eb := extras.map fun n => n.box stageW stageH
  let pos ← if stageW < Fw.Parts.Pain.containerSplit then place (bb ++ eb) w h avoid else scoredPlace w h bb avoid eb
  match pos with
  | none => pure none
  | some (l, t) =>
    let r1 ← draw
    let r2 ← draw
    pure (some ⟨s!"extra-{j}", pickText ((base ++ extras).map (·.text)) r1,
      palette.getD (idx r2 palette.length) "#b3efbd", rotation j, l, t, 10 + extras.length, true⟩)

/-- Run the stream from a seed. $$\operatorname{run}(m, s) = m(s).1$$ The value only, for the golden vectors. -/
def runFrom {α : Type} (m : Rng α) (seed : UInt32) : α := (m.run seed).1

/-! ## Drag and keys -/

/-- JS 4650-4654: whether a pointer-down starts a drag. Not on the narrow/touch condition `mq.c860`, and a mouse must
use the primary button.

$$\operatorname{drag}(c, b, m) = \lnot c \land \lnot(b \ne 0 \land m)$$ -/
def dragAllowed (c860 : Bool) (button : Nat) (mouse : Bool) : Bool := !c860 && !(decide (button ≠ 0) && mouse)

/-- JS 4712-4713: position while dragging, percent, held inside the stage.

$$\operatorname{drag}(o, x_0, x, S, w) = \operatorname{clamp}\!\big(o + \tfrac{x - x_0}{S}\cdot 100;\ 0,\ 100 - w\big)$$

($o$ the origin percent, $x_0$ the pointer start, $x$ the pointer now, $S$ the stage size in px, $w$ the note size in percent.) -/
def dragPos (origin start cur container sizePct : Rat) : Rat :=
  clampTo (origin + (cur - start) / container * 100) 0 (100 - sizePct)

/-- The drag position never leaves the stage. $$w \le 100 \Rightarrow 0 \le \operatorname{drag} \le 100 - w$$ -/
theorem dragPos_mem (o s c k w : Rat) (h : w ≤ 100) : 0 ≤ dragPos o s c k w ∧ dragPos o s c k w ≤ 100 - w := by
  unfold dragPos clampTo
  grind

/-- JS 4672: arrow-key step in percent for (dx, dy); other keys: none.

$$\operatorname{keyDelta}(\mathrm{Left}) = (-\tfrac32, 0),\ \operatorname{keyDelta}(\mathrm{Right}) = (\tfrac32, 0),\ \operatorname{keyDelta}(\mathrm{Up}) = (0, -\tfrac32),\ \operatorname{keyDelta}(\mathrm{Down}) = (0, \tfrac32)$$ -/
def keyDelta : String → Option (Rat × Rat)
  | "ArrowLeft" => some (-keyStep, 0)
  | "ArrowRight" => some (keyStep, 0)
  | "ArrowUp" => some (0, -keyStep)
  | "ArrowDown" => some (0, keyStep)
  | _ => none

/-- JS 4676-4677: position after a key step, held inside the stage.
$$\operatorname{key}(p, d, w) = \operatorname{clamp}(p + d;\ 0,\ 100 - w)$$ -/
def keyPos (pos delta sizePct : Rat) : Rat := clampTo (pos + delta) 0 (100 - sizePct)

/-- The key step never leaves the stage. $$w \le 100 \Rightarrow 0 \le \operatorname{key}(p, d, w) \le 100 - w$$ -/
theorem keyPos_mem (p d w : Rat) (h : w ≤ 100) : 0 ≤ keyPos p d w ∧ keyPos p d w ≤ 100 - w := by
  unfold keyPos clampTo
  grind

/-! ## The stick animation -/

/-- Duration of `pain-note-stick` in ms (CSS 2277). $$D = 560$$ -/
def stickMs : Rat := 560

/-- Scale the note starts from (CSS 2275). $$s_0 = 1.14 = \tfrac{57}{50}$$ -/
def stickScale0 : Rat := 57 / 50

/-- The abscissa of the timing curve `cubic-bezier(0.33, 1, 0.68, 1)`.

$$X(s) = 3(1-s)^2 s \cdot 0.33 + 3(1-s)s^2 \cdot 0.68 + s^3$$

(the ordinate is $Y(s) = 3(1-s)^2 s + 3(1-s)s^2 + s^3 = 1 - (1-s)^3$, the ease-out cubic of `MorphTween.ease`). -/
def bezX (s : Rat) : Rat :=
  3 * (1 - s) * (1 - s) * s * (33 / 100) + 3 * (1 - s) * s * s * (68 / 100) + s * s * s

#guard bezX 0 == 0
#guard bezX 1 == 1

/-- The ordinate is the ease-out cubic. $$Y(s) = 1 - (1 - s)^3$$ (control ordinates 1 and 1). -/
def bezY (s : Rat) : Rat := 3 * (1 - s) * (1 - s) * s + 3 * (1 - s) * s * s + s * s * s

/-- $Y$ equals `MorphTween.ease` on $[0,1]$. $$\forall s \in [0,1]:\ Y(s) = \operatorname{ease}(s)$$ -/
theorem bezY_eq_ease (s : Rat) (h0 : 0 ≤ s) (h1 : s ≤ 1) : bezY s = ease s := by
  unfold bezY Fw.Parts.MorphTween.ease Fw.Parts.MorphTween.clamp01
  have a : max 0 s = s := by grind
  have b : min 1 s = s := by grind
  rw [a, b]
  grind

/-- Bisection for $X(s) = p$: `n` halvings of $[l, h]$, then the midpoint.

$$\operatorname{bis}_{n+1}(p, l, h) = \begin{cases} \operatorname{bis}_n(p, m, h) & X(m) < p \\ \operatorname{bis}_n(p, l, m) & \text{otherwise} \end{cases},\quad m = \tfrac{l + h}{2},\ \operatorname{bis}_0(p, l, h) = m$$ -/
def bisect (p : Rat) : Nat → Rat → Rat → Rat
  | 0, lo, hi => (lo + hi) / 2
  | n + 1, lo, hi => if bezX ((lo + hi) / 2) < p then bisect p n ((lo + hi) / 2) hi else bisect p n lo ((lo + hi) / 2)

/-- The bisection stays inside its interval. $$l \le h \Rightarrow l \le \operatorname{bis}_n(p, l, h) \le h$$ -/
theorem bisect_mem (p : Rat) (n : Nat) : ∀ lo hi : Rat, lo ≤ hi → lo ≤ bisect p n lo hi ∧ bisect p n lo hi ≤ hi := by
  induction n with
  | zero => intro lo hi h; unfold bisect; grind
  | succ n ih =>
    intro lo hi h
    unfold bisect
    split
    · have := ih ((lo + hi) / 2) hi (by grind); grind
    · have := ih lo ((lo + hi) / 2) (by grind); grind

/-- Position along the curve at time $t$ ms: $\operatorname{stick}(t) = Y(X^{-1}(t/560))$, with $X^{-1}$ by 40 halvings;
exactly 0 up to the start and exactly 1 from the end (`forwards`).

$$\operatorname{stick}(t) = \begin{cases} 0 & t \le 0 \\ 1 & t \ge 560 \\ Y\big(X^{-1}(t/560)\big) & \text{otherwise} \end{cases}$$

The note's opacity is $\operatorname{stick}(t)$ and its scale $1.14 - 0.14\,\operatorname{stick}(t)$. -/
def stick (t : Rat) : Rat :=
  if t ≤ 0 then 0 else if stickMs ≤ t then 1 else bezY (bisect (t / stickMs) 40 0 1)

/-- Scale at time $t$: $$\operatorname{scale}(t) = 1.14 - 0.14\,\operatorname{stick}(t)$$ -/
def stickScale (t : Rat) : Rat := stickScale0 - (stickScale0 - 1) * stick t

#guard stick 0 == 0
#guard stick 560 == 1
#guard stickScale 0 == 57 / 50
#guard stickScale 560 == 1

/-- The animation starts invisible at full scale and ends opaque at scale 1.
$$\operatorname{stick}(0) = 0,\ \operatorname{stick}(560) = 1,\ \operatorname{scale}(0) = 1.14,\ \operatorname{scale}(560) = 1$$ -/
theorem stick_ends : stick 0 = 0 ∧ stick 560 = 1 ∧ stickScale 0 = 57 / 50 ∧ stickScale 560 = 1 := by
  refine ⟨?_, ?_, ?_, ?_⟩ <;> decide +kernel

/-- The opacity stays in $[0,1]$. $$\forall t:\ 0 \le \operatorname{stick}(t) \le 1$$ -/
theorem stick_mem (t : Rat) : 0 ≤ stick t ∧ stick t ≤ 1 := by
  unfold stick
  split
  · grind
  · split
    · grind
    · have b := bisect_mem (t / stickMs) 40 0 1 (by grind)
      rw [bezY_eq_ease _ (by grind) (by grind)]
      exact ease_mem _

/-- The scale stays between 1 and 1.14. $$\forall t:\ 1 \le \operatorname{scale}(t) \le 1.14$$ -/
theorem stickScale_mem (t : Rat) : 1 ≤ stickScale t ∧ stickScale t ≤ stickScale0 := by
  have := stick_mem t
  unfold stickScale stickScale0
  grind

end Fw.Parts.PainNotes
