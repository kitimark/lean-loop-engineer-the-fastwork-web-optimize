/-!
# A counts run must measure the profile viewport (task page-root-clip)

Under mobile emulation Chromium enlarges the layout viewport when the page content is wider than the
device width: `innerWidth` and `innerHeight` then exceed the profile viewport (run 39130842058 measured a
645 x 1398 layout viewport instead of 430 x 932). Scroll range, hit areas and the touch gesture all
depend on that size, so such a run is not a measurement of the profile and is refused, never counted.

`viewportFaithful` decides it from two size pairs: the profile viewport and the one the page reports
after load. The TypeScript glue (`packages/measure-chromium/src/viewport.mjs`) is checked against the
golden vectors of `measure.viewport`.
-/
namespace Fw.Measure.Viewport

/-- The width and height in CSS pixels of a viewport.

$$s = (s_w, s_h) \in \mathbb{N} \times \mathbb{N}$$
-/
structure Size where
  w : Nat
  h : Nat
  deriving DecidableEq, Repr

/-- The run keeps the profile viewport exactly.

$$\mathrm{faithful}(p, o) = \mathrm{true} \iff o_w = p_w \land o_h = p_h$$
-/
def viewportFaithful (profile observed : Size) : Bool :=
  decide (observed.w = profile.w) && decide (observed.h = profile.h)

/-- The run is refused exactly when the width or the height differs.

$$\mathrm{faithful}(p, o) = \mathrm{false} \iff o_w \ne p_w \lor o_h \ne p_h$$
-/
theorem refuses_iff (p o : Size) :
    viewportFaithful p o = false ↔ o.w ≠ p.w ∨ o.h ≠ p.h := by
  unfold viewportFaithful
  by_cases hw : o.w = p.w <;> by_cases hh : o.h = p.h <;> simp [hw, hh]

/-- A run on the profile viewport is accepted.

$$\forall p:\ \mathrm{faithful}(p, p) = \mathrm{true}$$
-/
theorem accepts_self (p : Size) : viewportFaithful p p = true := by
  simp [viewportFaithful]

/-- A page whose layout viewport grew in width is refused.

$$o_w \ne p_w \Rightarrow \mathrm{faithful}(p, o) = \mathrm{false}$$
-/
theorem refuses_width (p o : Size) (h : o.w ≠ p.w) : viewportFaithful p o = false :=
  (refuses_iff p o).2 (Or.inl h)

/-- A page whose layout viewport grew in height is refused.

$$o_h \ne p_h \Rightarrow \mathrm{faithful}(p, o) = \mathrm{false}$$
-/
theorem refuses_height (p o : Size) (h : o.h ≠ p.h) : viewportFaithful p o = false :=
  (refuses_iff p o).2 (Or.inr h)

/-- The accepted observation is the profile viewport itself.

$$\mathrm{faithful}(p, o) = \mathrm{true} \iff o = p$$
-/
theorem accepts_iff (p o : Size) : viewportFaithful p o = true ↔ o = p := by
  unfold viewportFaithful
  cases p
  cases o
  simp

#guard viewportFaithful ⟨430, 932⟩ ⟨430, 932⟩
#guard !viewportFaithful ⟨430, 932⟩ ⟨645, 1398⟩
#guard !viewportFaithful ⟨430, 932⟩ ⟨430, 1398⟩
#guard !viewportFaithful ⟨430, 932⟩ ⟨645, 932⟩

end Fw.Measure.Viewport
