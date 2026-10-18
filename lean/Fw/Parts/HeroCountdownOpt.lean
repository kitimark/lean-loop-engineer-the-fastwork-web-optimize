import Fw.Engine
import Fw.Parts.HeroCountdown
import Fw.Parts.EndFlags

/-!
# hero.countdown and morph.countdown, variant `strip`: same picture, fewer layers (CD-W, PLAN rev 10)

The `strip` variant replaces the 10 `.face` spans of each digit (each `will-change: transform`, moved by
`translateY(faceDelta(k, a) · c)`) by one 12-entry strip per digit (`will-change: transform`, moved by
`translateY(stripOffsetCells(a) · c)`). morph.countdown renders the same component (`MorphCountdown` →
`HeroCountdown inverse`, `apps/site/src/parts/morph.countdown/index.tsx:18-21`), so every theorem here covers both
clocks. Design: `research/notes/2026/10-18-engine-proof-design.md` §2-§3 and §4.2 rank 5.

* **Visual** (`strip_visSame`): `VisSame E` for every environment (every width band, touch, hover, DPR) and every
  instant, from `HeroCountdown.strip_shows_same`. The scene lists glyph boxes, named by the digit slot and the glyph
  they show (strip entries 0 and 10 both show 9, entries 1 and 11 both show 0; at most one of each pair is ever kept).
  The strip container and the digit wrapper paint nothing of their own and are not scene entries; glyphs of one
  digit share the digit's paint order (they sit whole cells apart, so they never overlap with positive area).
* **Per-frame work** (`strip_passes_eq`, `strip_units`, over any engine whose stages for the transform write do not
  depend on the element; instances `cr_*` for `chromiumAt m` and `wk_*` for `webkitAt m`): every stage runs exactly
  as often (`=o`, the counts CI measures), the units drop from $10r$ to $r$ for $r$ rolling digits. So Core's
  `claim` is **not** a resident-only label: with a rolling digit the screen says `dominates` (via units), and
  `run_claim` gives `dominates` or `trade` by the resident order (`strip_claim`); with no rolling digit the runs are
  equal and `claim` is `noClaim`.
* **Resident** (`strip_layers_lt`, `hero_layers`): layers $10n \to n$ per clock of $n$ digits; $n = 8$ while the
  days have two digits, so 80 → 8. 80 is `layerBudget` of `faithful` (`part.json`), 16 the `layerBudget` of `strip`:
  a bound (8 ≤ 16), not the model's count. Backing area, under the full-layer rule (each composited layer backs its
  whole border box, INFERRED), grows from 10 to 12 cells per digit (`strip_backing_gt`), so Core's label is
  **trade**, not dominates (`strip_label_fullLayer`).
* **WebKit** (`wk_owns`): the faces' `translateY` is a static 2D transform and never composites
  (`WebKit.static2D_not_own`); the 80 layers come only from `will-change`, which composites under the Normal policy
  (Safari default) and is dropped under Conservative. Under Conservative both variants have 0 clock layers: no
  resident difference (`wk_conservative_same`). The paused morph panel (`will-change: auto !important`,
  `morph.module.css:14-17`) has 0 clock layers on both engines (`paused_same`).

Sources: `apps/site/src/parts/hero.countdown/index.tsx:24-50` (10 faces or one 12-entry strip per digit),
`hero.module.css:71-86` (`will-change: transform` on `.face` and `.strip`), `driver.ts:62-69` (one transform per
face, or one per strip, per frame of a rolling digit); Chromium `compositing_reason_finder.cc:76-137`@f842f52
(`will-change: transform` is a direct reason) and `:535-546` (a transform composites only with a 3D operation),
CONFIRMED; WebKit as in `Fw.Engine.WebKit.composites`.

The TS `strip` also moves the clock from the original's `setInterval(1000)` plus one rAF chain per digit to one
shared-loop subscriber (`index.tsx:103-108`, `driver.ts:43-47`), which moves roll starts across frames. That
scheduling delta is not modelled here (both variants get the same frame inputs), so the golden rows predict only the
layer census (`goldenJsonl`, base `rewrite`, whose census class is deterministic, so a frame-exact `<o` is usable);
per-frame det rows would test the scheduling delta, not this theorem.
-/
namespace Fw.Parts.HeroCountdownOpt

open Fw.Engine
open Fw.Parts.HeroCountdown

/-! ## Visual: glyph scenes -/

/-- Geometry of one digit window in viewport px: its slot (identity), top-left corner, cell width and height, and
its paint order.

$$\mathrm{DigitGeo} = \underbrace{\mathbb{N}}_{\mathrm{slot}} \times \underbrace{\mathbb{Q}}_{x} \times \underbrace{\mathbb{Q}}_{y} \times \underbrace{\mathbb{Q}}_{w} \times \underbrace{\mathbb{Q}}_{c} \times \underbrace{\mathbb{N}}_{\mathrm{order}}$$

Where one digit of the clock sits on screen and how big its cell is. -/
structure DigitGeo where
  slot  : Nat
  x     : Rat
  y     : Rat
  w     : Rat
  c     : Rat
  order : Nat
deriving Repr, DecidableEq

/-- One glyph box: digit `k` drawn `o` cells below the window (negative: above). Box and ink are the cell; the
transform moves it to the window plus $o \cdot c$; the clip is the window in the glyph's local coordinates.

$$\operatorname{glyph}(g, k, o) = \big(\mathrm{box} = (0, 0, w, c),\ \mathrm{ink} = (0, 0, w, c),\ \mathrm{paint} = [(\texttt{text}, \operatorname{toString}(k))],\ \mathrm{xf} = (1, 0, 0, 1, x, y + o c),\ \alpha = 1,\ \mathrm{clip} = \mathrm{rect}(0, -o c, w, c),\ \mathrm{filter} = [\,],\ \mathrm{order}\big)$$

The cell that shows digit `k` at offset `o`, as the renderer gets it. -/
def glyph (g : DigitGeo) (k : Int) (o : Rat) : BoxVis where
  box := ⟨0, 0, g.w, g.c⟩
  ink := ⟨0, 0, g.w, g.c⟩
  paint := [("text", toString k)]
  xf := ⟨1, 0, 0, 1, g.x, g.y + o * g.c⟩
  alpha := 1
  clip := some (.rect ⟨0, -(o * g.c), g.w, g.c⟩)
  filter := []
  order := g.order

/-- The scene id of a glyph: the digit slot and the glyph shown.

$$\operatorname{gid}(g, k) = \texttt{"cd"} \Vert g.\mathrm{slot} \Vert \texttt{".g"} \Vert k$$

A name for "digit `k` in this window", shared by both variants. -/
def glyphId (g : DigitGeo) (k : Int) : BoxId := s!"cd{g.slot}.g{k}"

/-- **Faithful digit**: face $k = 0..9$ at offset $\operatorname{faceDelta}(k, a)$.

$$\operatorname{faces}(g, a) = \big[(\operatorname{gid}(g, k), \operatorname{glyph}(g, k, \operatorname{faceDelta}(k, a)))\big]_{k = 0}^{9}$$

The ten faces of one digit when its spring is at `a`. -/
def facesDigit (g : DigitGeo) (a : Rat) : Scene :=
  (List.range 10).map fun (k : Nat) => (glyphId g k, glyph g k (faceDelta k a))

/-- The strip entries that show digit `k` (entries $0..11$ read $9, 0, 1, \dots, 9, 0$).

$$\operatorname{entries}(k) = \begin{cases} [1, 11] & k = 0 \\ [0, 10] & k = 9 \\ [k + 1] & \text{otherwise} \end{cases}$$

Where digit `k` is printed on the strip; 0 and 9 are printed twice. -/
def stripEntries (k : Int) : List Int := if k = 0 then [1, 11] else if k = 9 then [0, 10] else [k + 1]

#guard (List.range 10).all fun (k : Nat) =>
  stripEntries k == ((List.range 12).map Int.ofNat).filter (fun j => stripEntryDigit j == k)

/-- The entries of digit `k` are exactly the strip positions printing `k`.

$$\forall k \in \{0..9\},\ \forall j \in \mathbb{Z}:\quad j \in \operatorname{entries}(k) \iff 0 \le j < 12 \land \operatorname{stripEntryDigit}(j) = k$$

The list names every place on the strip where the digit is printed, and no other. -/
theorem mem_stripEntries (k j : Int) (hk0 : 0 ≤ k) (hk1 : k < 10) :
    j ∈ stripEntries k ↔ 0 ≤ j ∧ j < 12 ∧ stripEntryDigit j = k := by
  unfold stripEntries stripEntryDigit
  by_cases h0 : k = 0 <;> by_cases h9 : k = 9 <;> simp [h0, h9] <;> omega

/-- **Strip digit**: for each glyph $k = 0..9$, its strip entries $j$ at offset $j + \operatorname{stripOffsetCells}(a)$.

$$\operatorname{strip}(g, a) = \mathop{\Vert}_{k = 0}^{9} \big[(\operatorname{gid}(g, k), \operatorname{glyph}(g, k, j + \operatorname{stripOffsetCells}(a)))\big]_{j \in \operatorname{entries}(k)}$$

The twelve strip cells of one digit when its spring is at `a`, listed by the glyph they show. -/
def stripDigit (g : DigitGeo) (a : Rat) : Scene :=
  (List.range 10).flatMap fun (k : Nat) =>
    (stripEntries k).map fun (j : Int) => (glyphId g k, glyph g k ((j : Rat) + stripOffsetCells a))

/-- The faithful clock: every digit's faces, digit by digit.

$$\operatorname{facesClock}(D) = \mathop{\Vert}_{(g, a) \in D} \operatorname{faces}(g, a)$$

All faces of all digits. -/
def facesClock (ds : List (DigitGeo × Rat)) : Scene := ds.flatMap fun d => facesDigit d.1 d.2

/-- The strip clock: every digit's strip, digit by digit.

$$\operatorname{stripClock}(D) = \mathop{\Vert}_{(g, a) \in D} \operatorname{strip}(g, a)$$

All strip cells of all digits. -/
def stripClock (ds : List (DigitGeo × Rat)) : Scene := ds.flatMap fun d => stripDigit d.1 d.2

/-- A kept glyph is inside the window: its offset lies strictly between $-1$ and $1$ cell.

$$\forall \mathit{vp}, g, k, o:\quad \neg\operatorname{drop}_{\mathit{vp}}(\operatorname{glyph}(g, k, o)) \Rightarrow -1 < o < 1$$

Only a glyph that overlaps the digit window can survive `visible`. -/
theorem glyph_kept_window (vp : Rect) (g : DigitGeo) (k : Int) (o : Rat)
    (h : (glyph g k o).drop vp = false) : -1 < o ∧ o < 1 := by
  simp only [BoxVis.drop, glyph, Rect.meets, Bool.or_eq_false_iff, Bool.not_eq_false',
    Bool.and_eq_true, decide_eq_true_eq] at h
  obtain ⟨⟨⟨_, _⟩, ⟨⟨⟨⟨⟨⟨⟨_, _⟩, _⟩, _⟩, hc⟩, _⟩, h1⟩, h2⟩⟩, _⟩ := h
  constructor
  · apply Classical.byContradiction
    intro hn
    have hn' : 0 ≤ -(1 + o) := by grind
    have := Rat.mul_nonneg hn' (Rat.le_of_lt hc)
    grind
  · apply Classical.byContradiction
    intro hn
    have hn' : 0 ≤ o - 1 := by grind
    have := Rat.mul_nonneg hn' (Rat.le_of_lt hc)
    grind

/-- A filter-of-map lemma: if every kept image is `b`, `b` kept has a preimage, and no two elements are both kept,
the filtered images are the filtered singleton.

$$\forall P : \beta \to \mathbb{B},\ \forall f : \alpha \to \beta,\ \forall b \in \beta,\ \forall L \in \alpha^{*}:\quad \big(\forall x \in L:\ P(f x) \Rightarrow f x = b\big) \Rightarrow \big(P(b) \Rightarrow \exists x \in L:\ f x = b\big) \Rightarrow \big(\forall i < j < |L|:\ P(f L_i) \Rightarrow \neg P(f L_j)\big) \Rightarrow \operatorname{filter}_P(\operatorname{map}_f L) = \operatorname{filter}_P([b])$$

At most one element survives, and it is `b`, exactly when `b` survives. -/
theorem filter_map_unique {α β : Type} (P : β → Bool) (f : α → β) (b : β) :
    ∀ (L : List α), (∀ x ∈ L, P (f x) = true → f x = b) → (P b = true → ∃ x ∈ L, f x = b) →
      L.Pairwise (fun x y => P (f x) = true → P (f y) = false) →
      (L.map f).filter P = [b].filter P
  | [], _, h2, _ => by
    cases hb : P b
    · simp [hb]
    · obtain ⟨x, hx, _⟩ := h2 hb; cases hx
  | x :: xs, h1, h2, h3 => by
    rw [List.pairwise_cons] at h3
    cases hx : P (f x)
    · have ih := filter_map_unique P f b xs (fun y hy => h1 y (List.mem_cons_of_mem _ hy))
        (fun hb => by
          obtain ⟨y, hy, hyb⟩ := h2 hb
          rcases List.mem_cons.mp hy with rfl | hy'
          · rw [hyb, hb] at hx; cases hx
          · exact ⟨y, hy', hyb⟩)
        h3.2
      simp [List.filter_cons, hx, ih]
    · have hxb := h1 x (List.mem_cons_self) hx
      have hnil : (xs.map f).filter P = [] := by
        rw [List.filter_eq_nil_iff]
        intro y hy
        obtain ⟨z, hz, rfl⟩ := List.mem_map.mp hy
        simp [h3.1 z hz hx]
      rw [← hxb]
      simp [hx, hnil]

/-- **One glyph, both variants.** For glyph $k \in \{0..9\}$ of one digit, the kept strip entries are the kept
faithful face.

$$\forall \mathit{vp}, g, a,\ \forall k \in \mathbb{Z}:\quad 0 \le k < 10 \Rightarrow \big[e \in [(\operatorname{gid}(g, k), \operatorname{glyph}(g, k, j + \operatorname{stripOffsetCells}(a)))]_{j \in \operatorname{entries}(k)} \mid \neg\operatorname{drop}_{\mathit{vp}}(e)\big] = \big[e \in [(\operatorname{gid}(g, k), \operatorname{glyph}(g, k, \operatorname{faceDelta}(k, a)))] \mid \neg\operatorname{drop}_{\mathit{vp}}(e)\big]$$

Whatever the viewport, digit `k` is visible in the strip exactly where, and only where, the face `k` is. -/
theorem strip_glyph_same (vp : Rect) (g : DigitGeo) (a : Rat) (k : Int) (hk0 : 0 ≤ k) (hk1 : k < 10) :
    ((stripEntries k).map fun (j : Int) => (glyphId g k, glyph g k ((j : Rat) + stripOffsetCells a))).filter
        (fun e => !(e.2.drop vp)) =
      [(glyphId g k, glyph g k (faceDelta k a))].filter (fun e => !(e.2.drop vp)) := by
  apply filter_map_unique
  · intro j hj hkeep
    have hw := glyph_kept_window vp g k _ (by simpa using hkeep)
    have hm := (mem_stripEntries k j hk0 hk1).mp hj
    have := (strip_shows_same a k hk0 hk1 _ hw.1 hw.2).mp ⟨j, hm.1, hm.2.1, hm.2.2, rfl⟩
    rw [this]
  · intro hkeep
    have hw := glyph_kept_window vp g k _ (by simpa using hkeep)
    obtain ⟨j, hj0, hj1, hjd, hjo⟩ := (strip_shows_same a k hk0 hk1 _ hw.1 hw.2).mpr rfl
    exact ⟨j, (mem_stripEntries k j hk0 hk1).mpr ⟨hj0, hj1, hjd⟩, by rw [hjo]⟩
  · unfold stripEntries
    by_cases h0 : k = 0
    · rw [ite_eq_left_of_eq_true _ _ (eq_true h0)]
      refine List.Pairwise.cons ?_ (List.Pairwise.cons (by simp) List.Pairwise.nil)
      intro j hj hkeep
      rw [List.mem_singleton] at hj
      subst hj
      apply Bool.eq_false_iff.mpr
      intro h11
      have w1 := glyph_kept_window vp g k _ (by simpa using hkeep)
      have w11 := glyph_kept_window vp g k _ (by simpa using h11)
      grind
    · by_cases h9 : k = 9
      · rw [ite_eq_right_of_eq_false _ _ (eq_false h0), ite_eq_left_of_eq_true _ _ (eq_true h9)]
        refine List.Pairwise.cons ?_ (List.Pairwise.cons (by simp) List.Pairwise.nil)
        intro j hj hkeep
        rw [List.mem_singleton] at hj
        subst hj
        apply Bool.eq_false_iff.mpr
        intro h10
        have w0 := glyph_kept_window vp g k _ (by simpa using hkeep)
        have w10 := glyph_kept_window vp g k _ (by simpa using h10)
        grind
      · rw [ite_eq_right_of_eq_false _ _ (eq_false h0), ite_eq_right_of_eq_false _ _ (eq_false h9)]
        exact List.pairwise_singleton _ _

/-- `flatMap` respects pointwise equality on the list's members.

$$\forall L, f, g:\quad \big(\forall x \in L:\ f(x) = g(x)\big) \Rightarrow \mathop{\Vert}_{x \in L} f(x) = \mathop{\Vert}_{x \in L} g(x)$$

Equal pieces give equal concatenations. -/
theorem flatMap_congr' {α β : Type} {l : List α} {f g : α → List β} (h : ∀ x ∈ l, f x = g x) :
    l.flatMap f = l.flatMap g := by
  induction l with
  | nil => rfl
  | cons x xs ih =>
    rw [List.flatMap_cons, List.flatMap_cons, h x List.mem_cons_self,
      ih (fun y hy => h y (List.mem_cons_of_mem _ hy))]

/-- **One digit, both variants.** The visible part of a strip digit is the visible part of the faithful digit.

$$\forall \mathit{vp} \in \mathrm{Rect},\ \forall g \in \mathrm{DigitGeo},\ \forall a \in \mathbb{Q}:\quad \operatorname{visible}_{\mathit{vp}}(\operatorname{strip}(g, a)) = \operatorname{visible}_{\mathit{vp}}(\operatorname{faces}(g, a))$$

For any spring value, window geometry and viewport, the strip and the ten faces show the same boxes. -/
theorem strip_digit_same (vp : Rect) (g : DigitGeo) (a : Rat) :
    visible vp (stripDigit g a) = visible vp (facesDigit g a) := by
  have hf : facesDigit g a =
      (List.range 10).flatMap fun (k : Nat) => [(glyphId g k, glyph g k (faceDelta k a))] := by
    unfold facesDigit
    generalize List.range 10 = l
    induction l with
    | nil => rfl
    | cons x xs ih => simp [ih]
  rw [hf]
  unfold stripDigit visible
  rw [List.filter_flatMap, List.filter_flatMap]
  apply flatMap_congr'
  intro k hk
  have hk' := List.mem_range.mp hk
  exact strip_glyph_same vp g a k (by omega) (by omega)

/-- **`strip_visSame`: the strip shows the same picture, class E, for every environment and instant.** The page
around the clock (`pre`, `post`) and the digit windows and spring values (`ds`) are arbitrary functions of the
environment (every width band, touch, hover, DPR) and of time; both variants share them.

$$\forall \mathit{Env}, T,\ \forall \mathit{vp} : \mathit{Env} \to \mathrm{Rect},\ \forall \mathit{pre}, \mathit{post} : \mathit{Env} \to T \to \mathrm{Scene},\ \forall D : \mathit{Env} \to T \to (\mathrm{DigitGeo} \times \mathbb{Q})^{*}:\quad \operatorname{VisSame}_{\mathrm{E}}\Big(\mathit{vp},\ (\mathit{env}, t) \mapsto \mathit{pre}(\mathit{env}, t) \mathbin{+\!\!+} \operatorname{facesClock}(D(\mathit{env}, t)) \mathbin{+\!\!+} \mathit{post}(\mathit{env}, t),\ (\mathit{env}, t) \mapsto \mathit{pre}(\mathit{env}, t) \mathbin{+\!\!+} \operatorname{stripClock}(D(\mathit{env}, t)) \mathbin{+\!\!+} \mathit{post}(\mathit{env}, t)\Big)$$

At every width and every moment the visible scene with strips equals the visible scene with faces. -/
theorem strip_visSame {Env T : Type} (vp : Env → Rect) (pre post : Env → T → Scene)
    (ds : Env → T → List (DigitGeo × Rat)) :
    VisSame E vp (fun env t => pre env t ++ facesClock (ds env t) ++ post env t)
      (fun env t => pre env t ++ stripClock (ds env t) ++ post env t) := by
  intro env t
  unfold E visible facesClock stripClock
  simp only [List.filter_append, List.filter_flatMap]
  congr 2
  apply flatMap_congr'
  intro d _
  exact (strip_digit_same (vp env) d.1 d.2).symm

/-! ## Per-frame work -/

section Work
variable {P M : Type}

/-- The faithful writes of one frame: for every rolling digit slot $d$, one transform write on each of its 10 faces.

$$\operatorname{faceWrites}(p, \ell, D) = \big[(10 d + k,\ p,\ \ell)\big]_{d \in D,\ k = 0..9}$$

What the original's springs write in a frame where the digits `ds` roll. -/
def faceWrites (p : P) (ℓ : LayerState) (ds : List Nat) : List (Change P) :=
  ds.flatMap fun d => (List.range 10).map fun k => ⟨10 * d + k, p, ℓ⟩

/-- The strip writes of one frame: for every rolling digit slot $d$, one transform write on its strip.

$$\operatorname{stripWrites}(p, \ell, D) = \big[(10 d,\ p,\ \ell)\big]_{d \in D}$$

What the strip variant writes in the same frame. -/
def stripWrites (p : P) (ℓ : LayerState) (ds : List Nat) : List (Change P) :=
  ds.map fun d => ⟨10 * d, p, ℓ⟩

/-- A frame of the page with the clock's writes appended; everything else (script callbacks, forced passes, hits,
other changes, compositor animations) is the shared frame `f`.

$$\operatorname{withWrites}(f, W) = f\ \text{with}\ \mathrm{changes} := f.\mathrm{changes} \mathbin{+\!\!+} W$$

The same page frame, plus the digit writes of one variant. -/
def withWrites (f : FrameIn P) (ws : List (Change P)) : FrameIn P := { f with changes := f.changes ++ ws }

/-- Stages of the face writes: those of the transform write when a digit rolls, none otherwise.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall D, s:\ s \in \bigcup_{c \in \operatorname{faceWrites}(p, \ell, D)} E.\mathrm{stagesOf}(c) \iff D \ne [\,] \land s \in S$$
-/
theorem faceWrites_stages (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (ds : List Nat) (s : Stage) :
    s ∈ (faceWrites p ℓ ds).flatMap E.stagesOf ↔ ds ≠ [] ∧ s ∈ S := by
  unfold faceWrites
  simp only [List.mem_flatMap, List.mem_map, List.mem_range]
  constructor
  · rintro ⟨c, ⟨d, hd, k, _, rfl⟩, hs⟩
    rw [hS] at hs
    exact ⟨List.ne_nil_of_mem hd, hs⟩
  · rintro ⟨hne, hs⟩
    obtain ⟨d, hd⟩ := List.exists_mem_of_ne_nil ds hne
    exact ⟨_, ⟨d, hd, 0, by omega, rfl⟩, by rw [hS]; exact hs⟩

/-- Stages of the strip writes: those of the transform write when a digit rolls, none otherwise.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall D, s:\ s \in \bigcup_{c \in \operatorname{stripWrites}(p, \ell, D)} E.\mathrm{stagesOf}(c) \iff D \ne [\,] \land s \in S$$
-/
theorem stripWrites_stages (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (ds : List Nat) (s : Stage) :
    s ∈ (stripWrites p ℓ ds).flatMap E.stagesOf ↔ ds ≠ [] ∧ s ∈ S := by
  unfold stripWrites
  simp only [List.mem_flatMap, List.mem_map]
  constructor
  · rintro ⟨c, ⟨d, hd, rfl⟩, hs⟩
    rw [hS] at hs
    exact ⟨List.ne_nil_of_mem hd, hs⟩
  · rintro ⟨hne, hs⟩
    obtain ⟨d, hd⟩ := List.exists_mem_of_ne_nil ds hne
    exact ⟨_, ⟨d, hd, rfl⟩, by rw [hS]; exact hs⟩

/-- The face writes are empty exactly when no digit rolls.

$$\forall p, \ell, D:\quad \operatorname{faceWrites}(p, \ell, D) = [\,] \iff D = [\,]$$
-/
theorem faceWrites_isEmpty (p : P) (ℓ : LayerState) (ds : List Nat) :
    (faceWrites p ℓ ds).isEmpty = ds.isEmpty := by
  cases ds <;> simp [faceWrites, List.range_succ]

/-- The strip writes are empty exactly when no digit rolls.

$$\forall p, \ell, D:\quad \operatorname{stripWrites}(p, \ell, D) = [\,] \iff D = [\,]$$
-/
theorem stripWrites_isEmpty (p : P) (ℓ : LayerState) (ds : List Nat) :
    (stripWrites p ℓ ds).isEmpty = ds.isEmpty := by
  cases ds <;> simp [stripWrites]

/-- Every stage of the write counts 10 face writes per rolling digit, any other stage none.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall D, s:\ \big|[\,c \in \operatorname{faceWrites}(p, \ell, D) \mid s \in E.\mathrm{stagesOf}(c)\,]\big| = 10\,|D| \cdot \begin{cases} 1 & s \in S \\ 0 & s \notin S \end{cases}$$
-/
theorem faceWrites_count (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (ds : List Nat) (s : Stage) :
    (faceWrites p ℓ ds).countP (fun c => decide (s ∈ E.stagesOf c)) =
      10 * ds.length * (if s ∈ S then 1 else 0) := by
  induction ds with
  | nil => simp [faceWrites]
  | cons d ds ih =>
    unfold faceWrites at ih ⊢
    rw [List.flatMap_cons, List.countP_append, ih]
    simp only [List.countP_map, Function.comp_def, hS, List.length_cons]
    by_cases h : s ∈ S <;> simp [h] <;> grind

/-- Every stage of the write counts 1 strip write per rolling digit, any other stage none.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall D, s:\ \big|[\,c \in \operatorname{stripWrites}(p, \ell, D) \mid s \in E.\mathrm{stagesOf}(c)\,]\big| = |D| \cdot \begin{cases} 1 & s \in S \\ 0 & s \notin S \end{cases}$$
-/
theorem stripWrites_count (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (ds : List Nat) (s : Stage) :
    (stripWrites p ℓ ds).countP (fun c => decide (s ∈ E.stagesOf c)) = ds.length * (if s ∈ S then 1 else 0) := by
  unfold stripWrites
  simp only [List.countP_map, Function.comp_def, hS]
  by_cases h : s ∈ S <;> simp [h]

/-- Touching is decided by the writes' stage union and emptiness: two write lists with the same both give the same
touched stages.

$$\forall E, f, W_1, W_2:\quad \big(\forall s:\ s \in \textstyle\bigcup_{c \in W_1} E.\mathrm{stagesOf}(c) \iff s \in \bigcup_{c \in W_2} E.\mathrm{stagesOf}(c)\big) \land \big(W_1 = [\,] \iff W_2 = [\,]\big) \Rightarrow \forall s:\ s \in \operatorname{touched}_E(\operatorname{withWrites}(f, W_1)) \iff s \in \operatorname{touched}_E(\operatorname{withWrites}(f, W_2))$$
-/
theorem touched_congr (E : Engine P M) (f : FrameIn P) (w1 w2 : List (Change P))
    (hs : ∀ s, s ∈ w1.flatMap E.stagesOf ↔ s ∈ w2.flatMap E.stagesOf) (he : w1.isEmpty = w2.isEmpty)
    (s : Stage) : s ∈ touched E (withWrites f w1) ↔ s ∈ touched E (withWrites f w2) := by
  have hu : (withWrites f w1).updates = (withWrites f w2).updates := by
    have he' : (f.changes ++ w1).isEmpty = (f.changes ++ w2).isEmpty := by
      cases f.changes <;> simp [he]
    simp only [FrameIn.updates, withWrites]; rw [he']; rfl
  unfold touched
  rw [hu]
  simp only [withWrites, List.flatMap_append, List.mem_append, hs s]; exact Iff.rfl

/-- **Per-frame passes are equal (`=o`).** For an engine whose stages for the clock's transform write do not depend
on the element, every stage runs equally often with strips as with faces, in every frame.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall f, D, s:\ \operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{stripWrites}(p, \ell, D))).\mathrm{passes}(s) = \operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{faceWrites}(p, \ell, D))).\mathrm{passes}(s)$$

Strips never add or remove a pipeline pass. -/
theorem strip_passes_eq (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (f : FrameIn P) (ds : List Nat) (s : Stage) :
    (frameWork E (withWrites f (stripWrites p ℓ ds))).passes s =
      (frameWork E (withWrites f (faceWrites p ℓ ds))).passes s := by
  have h := touched_congr E f (stripWrites p ℓ ds) (faceWrites p ℓ ds)
    (fun s => by rw [stripWrites_stages E p ℓ S hS, faceWrites_stages E p ℓ S hS])
    (by rw [stripWrites_isEmpty, faceWrites_isEmpty]) s
  simp only [frameWork, forcedPasses, withWrites] at h ⊢
  by_cases ht : s ∈ touched E { f with changes := f.changes ++ faceWrites p ℓ ds } <;>
    simp_all

/-- **Per-frame units: faces cost $9r$ more on every stage of the write**, for $r$ rolling digits.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall f, D, s:\ \operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{faceWrites}(p, \ell, D))).\mathrm{units}(s) = \operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{stripWrites}(p, \ell, D))).\mathrm{units}(s) + 9\,|D| \cdot \begin{cases} 1 & s \in S \\ 0 & s \notin S \end{cases}$$

Ten writes per rolling digit become one. -/
theorem strip_units (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (f : FrameIn P) (ds : List Nat) (s : Stage) :
    (frameWork E (withWrites f (faceWrites p ℓ ds))).units s =
      (frameWork E (withWrites f (stripWrites p ℓ ds))).units s + 9 * ds.length * (if s ∈ S then 1 else 0) := by
  simp only [frameWork, stageUnits, withWrites, List.countP_append,
    faceWrites_count E p ℓ S hS, stripWrites_count E p ℓ S hS]
  by_cases h : s ∈ S <;> simp [h] <;> omega

/-- **Frame order.** Every frame with strips is at most the same frame with faces.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall f, D:\ \operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{stripWrites}(p, \ell, D))) \preceq \operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{faceWrites}(p, \ell, D)))$$
-/
theorem strip_frame_le (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (f : FrameIn P) (ds : List Nat) :
    (frameWork E (withWrites f (stripWrites p ℓ ds))).le (frameWork E (withWrites f (faceWrites p ℓ ds))) := by
  refine ⟨fun s => ⟨?_, ?_⟩, Nat.le_refl _⟩
  · rw [strip_passes_eq E p ℓ S hS]; exact Nat.le_refl _
  · rw [strip_units E p ℓ S hS]; exact Nat.le_add_right _ _

/-- **Strict in a rolling frame.** If some digit rolls and the write touches some stage, the strip frame is strictly
below the faces frame (in units).

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \land S \ne [\,] \Rightarrow \forall f, D \ne [\,]:\ \operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{stripWrites}(p, \ell, D))) \prec \operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{faceWrites}(p, \ell, D)))$$
-/
theorem strip_frame_lt (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (hS0 : S ≠ []) (f : FrameIn P) (ds : List Nat) (hd : ds ≠ []) :
    (frameWork E (withWrites f (stripWrites p ℓ ds))).lt (frameWork E (withWrites f (faceWrites p ℓ ds))) := by
  refine ⟨strip_frame_le E p ℓ S hS f ds, Or.inl ?_⟩
  obtain ⟨s, hs⟩ := List.exists_mem_of_ne_nil S hS0
  refine ⟨s, Or.inr ?_⟩
  rw [strip_units E p ℓ S hS]
  have : 0 < ds.length := List.length_pos_iff.mpr hd
  simp [hs]; omega

/-- The faithful run: one work value per frame, each frame being a shared page frame and its rolling digit slots.

$$\operatorname{facesRun}_E(p, \ell, F) = \big[\operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{faceWrites}(p, \ell, D)))\big]_{(f, D) \in F}$$
-/
def facesRun (E : Engine P M) (p : P) (ℓ : LayerState) (fs : List (FrameIn P × List Nat)) : List Work :=
  fs.map fun x => frameWork E (withWrites x.1 (faceWrites p ℓ x.2))

/-- The strip run over the same frames.

$$\operatorname{stripRun}_E(p, \ell, F) = \big[\operatorname{frameWork}_E(\operatorname{withWrites}(f, \operatorname{stripWrites}(p, \ell, D)))\big]_{(f, D) \in F}$$
-/
def stripRun (E : Engine P M) (p : P) (ℓ : LayerState) (fs : List (FrameIn P × List Nat)) : List Work :=
  fs.map fun x => frameWork E (withWrites x.1 (stripWrites p ℓ x.2))

/-- Some frame of the run has a rolling digit.

$$\operatorname{rolls}(F) \iff \exists (f, D) \in F:\ D \ne [\,]$$
-/
def rolls (fs : List (FrameIn P × List Nat)) : Bool := fs.any fun x => !x.2.isEmpty

/-- Every strip frame is at most its faces frame.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall F:\ \operatorname{leAll}(\operatorname{stripRun}_E(p, \ell, F), \operatorname{facesRun}_E(p, \ell, F)) = \mathrm{true}$$
-/
theorem strip_leAll (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) :
    ∀ fs : List (FrameIn P × List Nat), leAll (stripRun E p ℓ fs) (facesRun E p ℓ fs) = true
  | [] => rfl
  | x :: xs => by
    simp only [stripRun, facesRun, List.map_cons, leAll, Bool.and_eq_true]
    exact ⟨(Work.leb_iff _ _).mpr (strip_frame_le E p ℓ S hS x.1 x.2), strip_leAll E p ℓ S hS xs⟩

/-- A run with a rolling frame has a strictly cheaper strip frame.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \land S \ne [\,] \Rightarrow \forall F:\ \operatorname{rolls}(F) \Rightarrow \operatorname{someLt}(\operatorname{stripRun}_E(p, \ell, F), \operatorname{facesRun}_E(p, \ell, F)) = \mathrm{true}$$
-/
theorem strip_someLt (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (hS0 : S ≠ []) :
    ∀ fs : List (FrameIn P × List Nat), rolls fs = true → someLt (stripRun E p ℓ fs) (facesRun E p ℓ fs) = true
  | [], h => by cases h
  | x :: xs, h => by
    simp only [rolls, List.any_cons, Bool.or_eq_true, Bool.not_eq_true', List.isEmpty_eq_false_iff] at h
    simp only [someLt, stripRun, facesRun, List.map_cons, List.zip_cons_cons, List.any_cons, Bool.or_eq_true]
    rcases h with h | h
    · left
      exact (Work.ltb_iff _ _).mpr (strip_frame_lt E p ℓ S hS hS0 x.1 x.2 h)
    · right
      exact strip_someLt E p ℓ S hS hS0 xs h

/-- With no rolling digit the two runs are the same list.

$$\forall E, p, \ell, F:\quad \neg\operatorname{rolls}(F) \Rightarrow \operatorname{stripRun}_E(p, \ell, F) = \operatorname{facesRun}_E(p, \ell, F)$$
-/
theorem strip_run_eq_of_still (E : Engine P M) (p : P) (ℓ : LayerState) :
    ∀ fs : List (FrameIn P × List Nat), rolls fs = false → stripRun E p ℓ fs = facesRun E p ℓ fs
  | [], _ => rfl
  | x :: xs, h => by
    simp only [rolls, List.any_cons, Bool.or_eq_false_iff, Bool.not_eq_false', List.isEmpty_iff] at h
    simp only [stripRun, facesRun, List.map_cons] at *
    rw [h.1]
    congr 1
    exact strip_run_eq_of_still E p ℓ xs h.2

/-- **`strip_claim`: Core's label for the strip, exactly.** With a rolling digit somewhere in the run, the screen
says "dominates" (through units) and the claim is `dominates` or `trade` by the resident order; with no rolling digit
the runs are equal, the screen says "equal" and the claim is `noClaim`.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \land S \ne [\,] \Rightarrow \forall F, r_v, r_o:\ \operatorname{claim}\big(\operatorname{screen}(\operatorname{toRun}(\operatorname{facesRun}_E(p, \ell, F)), \operatorname{toRun}(\operatorname{stripRun}_E(p, \ell, F))), r_v, r_o\big) = \begin{cases} \mathrm{dominates} & \operatorname{rolls}(F) \land r_v \preceq r_o \\ \mathrm{trade} & \operatorname{rolls}(F) \land r_v \not\preceq r_o \\ \mathrm{noClaim} & \neg\operatorname{rolls}(F) \end{cases}$$

A per-frame win exists only while a digit rolls; the resident state then decides between dominates and trade. -/
theorem strip_claim (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (hS0 : S ≠ []) (fs : List (FrameIn P × List Nat)) (rv ro : Resident) :
    claim (Screen.screen (toRun (facesRun E p ℓ fs)) (toRun (stripRun E p ℓ fs))) rv ro =
      if rolls fs then (if rv.le ro then .dominates else .trade) else .noClaim := by
  cases hr : rolls fs
  · rw [strip_run_eq_of_still E p ℓ fs hr]
    simp [Screen.screen, Screen.shapeEq, claim]
  · simp only [ite_true]
    exact run_claim rv ro (strip_leAll E p ℓ S hS fs) (strip_someLt E p ℓ S hS hS0 fs hr)

end Work

/-! ## The two engine instances -/

open Fw.Engine.Chromium in
/-- **Chromium: passes `=o`, and Core's claim label** (the units win is `strip_units`), in every run mode and layer state. The transform write
dirties the same stages on every element (`crStagesOf` reads only the property and the layer state), and at least one.

$$\forall m, \ell, F, r_v, r_o:\ \operatorname{claim}\big(\operatorname{screen}(\operatorname{toRun}(\operatorname{facesRun}_{\operatorname{chromiumAt}(m)}(\mathrm{css}(\mathrm{transform}), \ell, F)), \operatorname{toRun}(\operatorname{stripRun}_{\operatorname{chromiumAt}(m)}(\mathrm{css}(\mathrm{transform}), \ell, F))), r_v, r_o\big) = \begin{cases} \mathrm{dominates} & \operatorname{rolls}(F) \land r_v \preceq r_o \\ \mathrm{trade} & \operatorname{rolls}(F) \land r_v \not\preceq r_o \\ \mathrm{noClaim} & \neg\operatorname{rolls}(F) \end{cases} \;\land\; \forall f, D, s:\ \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(\operatorname{withWrites}(f, \operatorname{stripWrites}(\mathrm{css}(\mathrm{transform}), \ell, D))).\mathrm{passes}(s) = \operatorname{frameWork}_{\operatorname{chromiumAt}(m)}(\operatorname{withWrites}(f, \operatorname{faceWrites}(\mathrm{css}(\mathrm{transform}), \ell, D))).\mathrm{passes}(s)$$

The Chromium instance of `strip_claim` and `strip_passes_eq`. -/
theorem cr_strip (m : CrMode) (ℓ : LayerState) (fs : List (FrameIn CrProp × List Nat)) (rv ro : Resident) :
    claim (Screen.screen (toRun (facesRun (chromiumAt m) (.css .transform) ℓ fs))
        (toRun (stripRun (chromiumAt m) (.css .transform) ℓ fs))) rv ro =
      (if rolls fs then (if rv.le ro then .dominates else .trade) else .noClaim) ∧
    ∀ (f : FrameIn CrProp) (ds : List Nat) (s : Stage),
      (frameWork (chromiumAt m) (withWrites f (stripWrites (.css .transform) ℓ ds))).passes s =
        (frameWork (chromiumAt m) (withWrites f (faceWrites (.css .transform) ℓ ds))).passes s := by
  have hS : ∀ e, (chromiumAt m).stagesOf ⟨e, .css .transform, ℓ⟩ =
      (chromiumAt m).stagesOf ⟨0, .css .transform, ℓ⟩ := fun _ => rfl
  have hS0 : (chromiumAt m).stagesOf ⟨0, .css .transform, ℓ⟩ ≠ [] := by
    cases ℓ <;> simp [chromiumAt, crStagesOf, crLevel, keyLevel, CrLevel.stages, CrProp.extra]
  exact ⟨strip_claim _ _ _ _ hS hS0 fs rv ro, strip_passes_eq _ _ _ _ hS⟩

open Fw.Engine.WebKit in
/-- **WebKit: passes `=o`, and Core's claim label** (the units win is `strip_units`), in every mode and layer state. `wkDiff` reads only the
property and the layer state, and a transform write dirties at least one stage (own: recomposite; paint layer:
overflow; none: layout).

$$\forall m, \ell, F, r_v, r_o:\ \operatorname{claim}\big(\operatorname{screen}(\operatorname{toRun}(\operatorname{facesRun}_{\operatorname{webkitAt}(m)}(\mathrm{transform}, \ell, F)), \operatorname{toRun}(\operatorname{stripRun}_{\operatorname{webkitAt}(m)}(\mathrm{transform}, \ell, F))), r_v, r_o\big) = \begin{cases} \mathrm{dominates} & \operatorname{rolls}(F) \land r_v \preceq r_o \\ \mathrm{trade} & \operatorname{rolls}(F) \land r_v \not\preceq r_o \\ \mathrm{noClaim} & \neg\operatorname{rolls}(F) \end{cases} \;\land\; \forall f, D, s:\ \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{withWrites}(f, \operatorname{stripWrites}(\mathrm{transform}, \ell, D))).\mathrm{passes}(s) = \operatorname{frameWork}_{\operatorname{webkitAt}(m)}(\operatorname{withWrites}(f, \operatorname{faceWrites}(\mathrm{transform}, \ell, D))).\mathrm{passes}(s)$$

The WebKit instance of `strip_claim` and `strip_passes_eq`. -/
theorem wk_strip (m : WkMode) (ℓ : LayerState) (fs : List (FrameIn WkProp × List Nat)) (rv ro : Resident) :
    claim (Screen.screen (toRun (facesRun (webkitAt m) .transform ℓ fs))
        (toRun (stripRun (webkitAt m) .transform ℓ fs))) rv ro =
      (if rolls fs then (if rv.le ro then .dominates else .trade) else .noClaim) ∧
    ∀ (f : FrameIn WkProp) (ds : List Nat) (s : Stage),
      (frameWork (webkitAt m) (withWrites f (stripWrites .transform ℓ ds))).passes s =
        (frameWork (webkitAt m) (withWrites f (faceWrites .transform ℓ ds))).passes s := by
  have hS : ∀ e, (webkitAt m).stagesOf ⟨e, .transform, ℓ⟩ = (webkitAt m).stagesOf ⟨0, .transform, ℓ⟩ :=
    fun _ => rfl
  have hS0 : (webkitAt m).stagesOf ⟨0, .transform, ℓ⟩ ≠ [] := by
    simp only [webkitAt]
    cases ℓ <;> decide
  exact ⟨strip_claim _ _ _ _ hS hS0 fs rv ro, strip_passes_eq _ _ _ _ hS⟩

/-! ## Resident state: layers and backing per clock -/

/-- The engine (and WebKit's compositing policy) a clock is composited by.

$$\mathrm{Host} = \{\mathrm{chromium}\} \cup \{\mathrm{webkit}(p) \mid p \in \mathrm{Policy}\}$$
-/
inductive Host where
  | chromium
  | webkit (pol : WebKit.Policy)
deriving Repr, DecidableEq

/-- Whether a face (or strip) box owns a composited layer. Its reasons are a static 2D `translateY` (always) and
`will-change: transform` (unless the panel is paused). Chromium: `will-change: transform` is a direct reason
(`compositing_reason_finder.cc:116-119`@f842f52), a transform only with a 3D operation (`:535-546`), CONFIRMED.
WebKit: `composites` of either reason (`Fw.Engine.WebKit`).

$$\operatorname{owns}(h, \mathit{wc}) = \begin{cases} \mathit{wc} & h = \mathrm{chromium} \\ (\mathit{wc} \land \operatorname{composites}(p, \mathrm{willChange})) \lor \operatorname{composites}(p, \mathrm{transform2D}) & h = \mathrm{webkit}(p) \end{cases}$$

Whether one moving box of the clock gets its own layer. -/
def owns : Host → Bool → Bool
  | .chromium, wc => wc
  | .webkit pol, wc => (wc && WebKit.composites pol .willChange) || WebKit.composites pol .transform2D

/-- **WebKit: the layers exist only through `will-change`, and only under Normal.** The `translateY` alone never
composites (`static2D_not_own`).

$$\forall p \in \mathrm{Policy},\ \forall \mathit{wc} \in \mathbb{B}:\quad \operatorname{owns}(\mathrm{webkit}(p), \mathit{wc}) = (\mathit{wc} \land p = \mathrm{normal})$$

On Safari's default policy the faces are layers, as in Chromium; under memory pressure neither variant has any. -/
theorem wk_owns (pol : WebKit.Policy) (wc : Bool) :
    owns (.webkit pol) wc = (wc && decide (pol = .normal)) := by
  cases pol <;> cases wc <;> simp [owns, WebKit.composites]

/-- Resident state of a faithful clock with `n` digits: 10 boxes per digit, each one cell (`a` kpx of backing) under
the full-layer rule (a composited layer backs its whole border box, INFERRED for small untiled layers).

$$\operatorname{facesRes}(h, \mathit{wc}, n, a) = \begin{cases} (10 n,\ 10 n a) & \operatorname{owns}(h, \mathit{wc}) \\ (0, 0) & \text{otherwise} \end{cases}$$
-/
def facesResident (h : Host) (wc : Bool) (n a : Nat) : Resident :=
  if owns h wc then ⟨10 * n, 10 * n * a⟩ else ⟨0, 0⟩

/-- Resident state of a strip clock with `n` digits: 1 box per digit, 12 cells tall, under the same rule.

$$\operatorname{stripRes}(h, \mathit{wc}, n, a) = \begin{cases} (n,\ 12 n a) & \operatorname{owns}(h, \mathit{wc}) \\ (0, 0) & \text{otherwise} \end{cases}$$
-/
def stripResident (h : Host) (wc : Bool) (n a : Nat) : Resident :=
  if owns h wc then ⟨n, 12 * n * a⟩ else ⟨0, 0⟩

/-- Digits shown by one clock `secs` seconds before the target: days unpadded, hours, minutes and seconds padded
to 2 (`index.tsx:63`, `HeroCountdown.digitPlaces`).

$$\operatorname{clockDigits}(s) = \sum_{i = 0}^{3} \big|\operatorname{digitPlaces}((u_i : \mathbb{Q}), i > 0)\big|,\qquad [u_0, \dots, u_3] = \operatorname{unitsFromSeconds}(s)$$
-/
def clockDigits (secs : Nat) : Nat :=
  ((unitsFromSeconds secs).zipIdx.map fun x => (digitPlaces (x.1 : Rat) (decide (0 < x.2))).length).sum

-- 2026-10-18T00:00Z: 15 days left, 8 digits; 2026-10-30T00:00Z: 3 days left, 7 digits.
#guard clockDigits (remainingSeconds 1792281600000 targetMs) == 8
#guard clockDigits (remainingSeconds 1793318400000 targetMs) == 7
#guard clockDigits (10 * 86400) == 8 && clockDigits (99 * 86400 + 86399) == 8 && clockDigits (100 * 86400) == 9
#guard clockDigits 0 == 7

/-- **Layers: $10n \to n$ per clock.** With the boxes composited, the strip has a tenth of the layers.

$$\forall h, \mathit{wc}, n, a:\quad \operatorname{owns}(h, \mathit{wc}) \land 0 < n \Rightarrow \operatorname{stripRes}(h, \mathit{wc}, n, a).\mathrm{layers} = n < 10 n = \operatorname{facesRes}(h, \mathit{wc}, n, a).\mathrm{layers}$$
-/
theorem strip_layers_lt (h : Host) (wc : Bool) (n a : Nat) (ho : owns h wc = true) (hn : 0 < n) :
    (stripResident h wc n a).layers = n ∧ n < 10 * n ∧ (facesResident h wc n a).layers = 10 * n := by
  simp [stripResident, facesResident, ho]; omega

/-- **The hero clock's numbers: 80 → 8, inside both budgets.** With 8 digits (days 10-99) on a composited host:
80 face layers (`layerBudget` 80 of `faithful`) and 8 strip layers, below the strip's `layerBudget` 16.

$$\forall h, \mathit{wc}, a:\quad \operatorname{owns}(h, \mathit{wc}) \Rightarrow \operatorname{facesRes}(h, \mathit{wc}, 8, a).\mathrm{layers} = 80 \land \operatorname{stripRes}(h, \mathit{wc}, 8, a).\mathrm{layers} = 8 \le 16$$
-/
theorem hero_layers (h : Host) (wc : Bool) (a : Nat) (ho : owns h wc = true) :
    (facesResident h wc 8 a).layers = 80 ∧ (stripResident h wc 8 a).layers = 8 ∧
      (stripResident h wc 8 a).layers ≤ 16 := by
  simp [stripResident, facesResident, ho]

/-- **Backing grows: 10 cells → 12 cells per digit** under the full-layer rule, whenever the boxes are composited and
a cell has area.

$$\forall h, \mathit{wc}, n, a:\quad \operatorname{owns}(h, \mathit{wc}) \land 0 < n \land 0 < a \Rightarrow \operatorname{facesRes}(h, \mathit{wc}, n, a).\mathrm{backingKpx} = 10 n a < 12 n a = \operatorname{stripRes}(h, \mathit{wc}, n, a).\mathrm{backingKpx}$$
-/
theorem strip_backing_gt (h : Host) (wc : Bool) (n a : Nat) (ho : owns h wc = true) (hn : 0 < n) (ha : 0 < a) :
    (facesResident h wc n a).backingKpx = 10 * n * a ∧ 10 * n * a < 12 * n * a ∧
      (stripResident h wc n a).backingKpx = 12 * n * a := by
  simp only [stripResident, facesResident, ho, ite_true, true_and, and_true]
  have : 0 < n * a := Nat.mul_pos hn ha
  rw [Nat.mul_assoc, Nat.mul_assoc]; omega

/-- **Core's label under the full-layer rule is `trade`.** Fewer layers, but more backing area, so the strip's
resident state is not below the faces'; with a rolling digit `claim` says `trade` on both engines (via `cr_strip`,
`wk_strip`).

$$\forall h, \mathit{wc}, n, a:\quad \operatorname{owns}(h, \mathit{wc}) \land 0 < n \land 0 < a \Rightarrow \operatorname{stripRes}(h, \mathit{wc}, n, a) \not\preceq \operatorname{facesRes}(h, \mathit{wc}, n, a) \land \operatorname{claim}(\mathrm{ok}(\mathrm{dominates}), \operatorname{stripRes}, \operatorname{facesRes}) = \mathrm{trade}$$
-/
theorem strip_label_fullLayer (h : Host) (wc : Bool) (n a : Nat) (ho : owns h wc = true) (hn : 0 < n)
    (ha : 0 < a) :
    ¬ (stripResident h wc n a).le (facesResident h wc n a) ∧
      claim (.ok .dominates) (stripResident h wc n a) (facesResident h wc n a) = .trade := by
  have hb := strip_backing_gt h wc n a ho hn ha
  have hnle : ¬ (stripResident h wc n a).le (facesResident h wc n a) := by
    intro hle; have := hle.2; omega
  exact ⟨hnle, by simp [claim, hnle]⟩

/-- **Not composited, no resident difference.** WebKit under Conservative, or the paused morph panel
(`will-change: auto`) on either engine: both variants have no clock layer, so the resident states are equal and a
rolling run is labelled `dominates` (by units alone).

$$\forall h, \mathit{wc}, n, a:\quad \neg\operatorname{owns}(h, \mathit{wc}) \Rightarrow \operatorname{stripRes}(h, \mathit{wc}, n, a) = (0, 0) = \operatorname{facesRes}(h, \mathit{wc}, n, a) \land \operatorname{claim}(\mathrm{ok}(\mathrm{dominates}), \operatorname{stripRes}, \operatorname{facesRes}) = \mathrm{dominates}$$
-/
theorem uncomposited_same (h : Host) (wc : Bool) (n a : Nat) (ho : owns h wc = false) :
    stripResident h wc n a = ⟨0, 0⟩ ∧ facesResident h wc n a = ⟨0, 0⟩ ∧
      claim (.ok .dominates) (stripResident h wc n a) (facesResident h wc n a) = .dominates := by
  simp [stripResident, facesResident, ho, claim, Resident.le]

/-- WebKit under Conservative: no clock layers in either variant, so no resident win to claim there.

$$\forall \mathit{wc}, n, a:\quad \operatorname{stripRes}(\mathrm{webkit}(\mathrm{conservative}), \mathit{wc}, n, a) = (0, 0) = \operatorname{facesRes}(\mathrm{webkit}(\mathrm{conservative}), \mathit{wc}, n, a)$$
-/
theorem wk_conservative_same (wc : Bool) (n a : Nat) :
    stripResident (.webkit .conservative) wc n a = ⟨0, 0⟩ ∧
      facesResident (.webkit .conservative) wc n a = ⟨0, 0⟩ :=
  let h := uncomposited_same (.webkit .conservative) wc n a (by rw [wk_owns]; simp)
  ⟨h.1, h.2.1⟩

/-- The paused morph panel (`will-change: auto !important`): no clock layers on any host.

$$\forall h, n, a:\quad \operatorname{stripRes}(h, \mathrm{false}, n, a) = (0, 0) = \operatorname{facesRes}(h, \mathrm{false}, n, a)$$
-/
theorem paused_same (h : Host) (n a : Nat) :
    stripResident h false n a = ⟨0, 0⟩ ∧ facesResident h false n a = ⟨0, 0⟩ := by
  have ho : owns h false = false := by
    cases h with
    | chromium => rfl
    | webkit pol => rw [wk_owns]; simp
  exact ⟨(uncomposited_same h false n a ho).1, (uncomposited_same h false n a ho).2.1⟩

/-- On Safari's default policy the faces are 80 layers (8 digits), as the v1 Simulator census saw
(`fixes/cd-strip/README.md:369` in the v1 repo, MEASURED there), and the strip has 8.

$$\forall a:\quad \operatorname{facesRes}(\mathrm{webkit}(\mathrm{normal}), \mathrm{true}, 8, a).\mathrm{layers} = 80 \land \operatorname{stripRes}(\mathrm{webkit}(\mathrm{normal}), \mathrm{true}, 8, a).\mathrm{layers} = 8$$
-/
theorem wk_normal_layers (a : Nat) :
    (facesResident (.webkit .normal) true 8 a).layers = 80 ∧
      (stripResident (.webkit .normal) true 8 a).layers = 8 := by
  have := hero_layers (.webkit .normal) true a (by rw [wk_owns]; rfl)
  exact ⟨this.1, this.2.1⟩

/-! ## Golden rows for `pnpm fw engine-check` -/

/-- The prediction for the layer census from the two layer counts: `<o` when the strip has fewer, `=o` when equal,
`any` otherwise.

$$\operatorname{layersPred}(v, o) = \begin{cases} \texttt{<o} & v < o \\ \texttt{=o} & v = o \\ \texttt{any} & \text{otherwise} \end{cases}$$
-/
def layersPred (v o : Nat) : String := if v < o then "<o" else if v = o then "=o" else "any"

#guard layersPred 8 80 == "<o" && layersPred 0 0 == "=o" && layersPred 12 10 == "any"

/-- The variant and base names of a run (`engine-check.ts:67-74`: `target+search`; default variant of a part is the
head of its `variants`, i.e. `faithful`).

$$\mathrm{variant} = \texttt{rewrite+?fw=hero.countdown:strip,morph.countdown:strip},\qquad \mathrm{base} = \texttt{rewrite}$$
-/
def variantName : String := "rewrite+?fw=hero.countdown:strip,morph.countdown:strip"

/-- One golden row, keys sorted.

$$\operatorname{row}(\mathit{sc}) = \{\mathrm{base}: \texttt{rewrite}, \mathrm{countType}: \texttt{census.layers}, \mathrm{engine}: \texttt{chromium}, \mathrm{prediction}: \operatorname{layersPred}(\operatorname{stripRes}(\mathrm{chromium}, \mathrm{true}, 8, 1).\mathrm{layers}, \operatorname{facesRes}(\mathrm{chromium}, \mathrm{true}, 8, 1).\mathrm{layers}) = \operatorname{layersPred}(8, 80), \mathrm{scenario}: \mathit{sc}, \mathrm{stage}: \texttt{comp}, \mathrm{variant}: \operatorname{variantName}\}$$
-/
def goldenRow (scenario : String) : String :=
  "{\"base\":\"rewrite\",\"countType\":\"census.layers\",\"engine\":\"chromium\",\"prediction\":\"" ++
    layersPred (stripResident .chromium true 8 1).layers (facesResident .chromium true 8 1).layers ++
    "\",\"scenario\":\"" ++ scenario ++ "\",\"stage\":\"comp\",\"variant\":\"" ++ variantName ++ "\"}"

/-- The golden file `packages/contracts/golden/engine/countdown-strip.jsonl`: one row per Chromium profile.

$$\operatorname{goldenJsonl} = \operatorname{row}(\texttt{swipe-v1}) \Vert \texttt{\textbackslash n} \Vert \operatorname{row}(\texttt{swipe-touch-v1}) \Vert \texttt{\textbackslash n}$$
-/
def goldenJsonl : String := goldenRow "swipe-v1" ++ "\n" ++ goldenRow "swipe-touch-v1" ++ "\n"

#guard (goldenJsonl.splitOn "\n").length == 3
#guard (goldenRow "swipe-v1").startsWith "{\"base\":\"rewrite\",\"countType\":\"census.layers\""
#guard ((goldenRow "swipe-v1").splitOn "\"prediction\":\"<o\"").length == 2

/-! ## Under the frame-end pass (`frameWorkE`, ledger n=1)

Strips and faces write the same stages at the same point of the same frame and add no read, so the stage flags end
the same way under both: one common end-flag assignment `e`. The verdicts carry over unchanged (`=o` passes, fewer
units). -/

section EndPass

open Fw.Parts.EndFlags

/-- **Frame order under `frameWorkE`.** For every common end-flag assignment, strips are at most faces.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \Rightarrow \forall f, D,\ \forall \epsilon : \mathrm{Stage} \to \mathbb{B}:\ \operatorname{frameWork}^{\epsilon}_E(\operatorname{withWrites}(f, \operatorname{stripWrites}(p, \ell, D))) \preceq \operatorname{frameWork}^{\epsilon}_E(\operatorname{withWrites}(f, \operatorname{faceWrites}(p, \ell, D)))$$

The end pass is paid the same way by both. -/
theorem strip_frame_leE {P M : Type} (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (f : FrameIn P) (ds : List Nat) (e : Stage → Bool) :
    (frameWorkE E (withWrites f (stripWrites p ℓ ds)) e).le (frameWorkE E (withWrites f (faceWrites p ℓ ds)) e) :=
  frameE_le_of_same_forced E e (fun s => by cases s <;> rfl) (strip_frame_le E p ℓ S hS f ds)

/-- **Strict under `frameWorkE`.** If some digit rolls and the write touches some stage, strips stay strictly below
faces for every common end-flag assignment.

$$\forall E, p, \ell, S:\ \big(\forall e:\ E.\mathrm{stagesOf}(e, p, \ell) = S\big) \land S \ne [\,] \Rightarrow \forall f,\ \forall D \ne [\,],\ \forall \epsilon:\ \operatorname{frameWork}^{\epsilon}_E(\operatorname{withWrites}(f, \operatorname{stripWrites}(p, \ell, D))) \prec \operatorname{frameWork}^{\epsilon}_E(\operatorname{withWrites}(f, \operatorname{faceWrites}(p, \ell, D)))$$

The saved units do not depend on end flags. -/
theorem strip_frame_ltE {P M : Type} (E : Engine P M) (p : P) (ℓ : LayerState) (S : List Stage)
    (hS : ∀ e, E.stagesOf ⟨e, p, ℓ⟩ = S) (hS0 : S ≠ []) (f : FrameIn P) (ds : List Nat) (hd : ds ≠ [])
    (e : Stage → Bool) :
    (frameWorkE E (withWrites f (stripWrites p ℓ ds)) e).lt (frameWorkE E (withWrites f (faceWrites p ℓ ds)) e) := by
  refine frameE_lt_mono E e e (fun s => by cases s <;> rfl) (strip_frame_le E p ℓ S hS f ds)
    (fun _ _ h => h) (Or.inl ?_)
  obtain ⟨s, hs⟩ := List.exists_mem_of_ne_nil S hS0
  refine ⟨s, ?_⟩
  have h := strip_units E p ℓ S hS f ds s
  have : 0 < ds.length := List.length_pos_iff.mpr hd
  simp only [frameWork, hs, ite_true] at h
  show stageUnits E _ s < stageUnits E _ s
  omega

end EndPass

/-! ## Scheduling: a per-frame subscriber is worse (ledger n=7, n=8)

The TS strip first ran its springs from a shared per-frame loop. That loop calls back in every frame, also in the
frames where no digit rolls, where the original runs nothing. One extra callback is one extra `script` unit, so
those frames are not `⪯` the original's, whatever the end flags, and the run cannot dominate: the confound, not the
strip, decides the screen. The aimed timer (n=8) runs one callback per second, as the original's interval does, so
both arms have the same run and Core's claim is `noClaim`. -/

section Schedule

/-- A frame with $k$ extra script callbacks.

$$\operatorname{addScript}(f, k) = f\ \text{with}\ \mathrm{script} := f.\mathrm{script} + k$$

The page frame plus a subscriber's callbacks. -/
def addScript {P : Type} (f : FrameIn P) (k : Nat) : FrameIn P := { f with script := f.script + k }

/-- **A still frame with a subscriber is not `⪯` the original's**, in every engine and for all end flags.

$$\forall E, p, \ell, f,\ \forall k > 0,\ \forall e_v, e_o:\ \neg\Big(\operatorname{frameWork}^{e_v}_E\big(\operatorname{withWrites}(\operatorname{addScript}(f, k), \operatorname{stripWrites}(p, \ell, [\,]))\big) \preceq \operatorname{frameWork}^{e_o}_E\big(\operatorname{withWrites}(f, \operatorname{faceWrites}(p, \ell, [\,]))\big)\Big)$$

The callback costs a script unit the original does not pay. -/
theorem sub_still_not_le {P M : Type} (E : Engine P M) (p : P) (ℓ : LayerState) (f : FrameIn P) (k : Nat)
    (hk : 0 < k) (ev eo : Stage → Bool) :
    ¬ (frameWorkE E (withWrites (addScript f k) (stripWrites p ℓ [])) ev).le
        (frameWorkE E (withWrites f (faceWrites p ℓ [])) eo) := by
  intro h
  have hu := (h.1 .script).2
  simp only [frameWorkE, stageUnits, withWrites, addScript, stripWrites, faceWrites, List.map_nil,
    List.flatMap_nil, List.append_nil, ↓reduceIte] at hu
  omega

/-- **The aimed timer has no claim.** Two arms with the same per-frame work get `noClaim`, for every resident state.

$$\forall W \in \mathrm{Work}^{*},\ \forall r_v, r_o:\ \operatorname{claim}\big(\operatorname{screen}(\operatorname{toRun}(W), \operatorname{toRun}(W)), r_v, r_o\big) = \mathrm{noClaim}$$

One callback per second against one callback per second is no work order (Lesson `resident_only_noClaim`). -/
theorem same_run_noClaim (ws : List Work) (rv ro : Resident) :
    claim (Screen.screen (toRun ws) (toRun ws)) rv ro = .noClaim :=
  resident_only_noClaim ws ws rv ro rfl

end Schedule

end Fw.Parts.HeroCountdownOpt
