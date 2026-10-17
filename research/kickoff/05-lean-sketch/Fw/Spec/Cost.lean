/-!
# A linear per-frame cost model (the *model* is proved; its fit to an engine is measured)

Work counts come from a trace (Chrome) or a Timeline export (WebKit); unit costs are calibrated
per engine/device. Lean proves properties of the model; whether an engine obeys the model is an
empirical claim checked by calibration runs, never by a theorem.
-/
namespace Fw.Cost

/-- Per-frame main-thread work counts: script µs, restyled elements, laid-out objects, painted kpx.

$$w = (s, e, \ell, k) \in \mathbb{N}^{4}$$
-/
structure Work where
  scriptUs     : Nat      -- JS time already in µs
  styleElems   : Nat      -- elements whose style was recalculated
  layoutObjs   : Nat      -- layout objects laid out
  paintKpx     : Nat      -- painted area, kilo-pixels (main-thread paint recording)
deriving Repr, DecidableEq

/-- Compositor-thread work: layers moved and rastered kpx (no main-thread cost in this model).

$$\kappa = (m, r) \in \mathbb{N}^{2}$$
-/
structure CompWork where
  layersMoved  : Nat
  rasterKpx    : Nat
deriving Repr, DecidableEq

/-- Unit costs in whole µs per element, per layout object and per kpx (sub-µs costs such as 0.3 µs
per element cannot be expressed; gap G5 of the Lean-to-math note).

$$u = (u_{\mathrm{style}}, u_{\mathrm{layout}}, u_{\mathrm{paint}}) \in \mathbb{N}^{3}$$
-/
structure UnitCost where
  style  : Nat   -- whole µs per element
  layout : Nat   -- whole µs per layout object
  paint  : Nat   -- whole µs per kpx
deriving Repr

/-- Work `a` is componentwise at most work `b` (a partial order: some pairs are incomparable).

$$a \preceq b \iff s_a \le s_b \ \land\ e_a \le e_b \ \land\ \ell_a \le \ell_b \ \land\ k_a \le k_b$$
-/
def Work.le (a b : Work) : Prop :=
  a.scriptUs ≤ b.scriptUs ∧ a.styleElems ≤ b.styleElems ∧ a.layoutObjs ≤ b.layoutObjs ∧ a.paintKpx ≤ b.paintKpx

/-- Main-thread time in µs is a weighted sum of the work counts; compositor work does not appear.

$$\operatorname{mainUs}(u, w) = s + u_{\mathrm{style}}\, e + u_{\mathrm{layout}}\, \ell + u_{\mathrm{paint}}\, k$$
-/
def mainUs (u : UnitCost) (w : Work) : Nat :=
  w.scriptUs + u.style * w.styleElems + u.layout * w.layoutObjs + u.paint * w.paintKpx

/-- More work never costs less, for any unit costs (they are natural numbers, hence non-negative).

$$\forall u \in \mathbb{N}^{3},\ \forall a, b \in \mathbb{N}^{4}:\quad a \preceq b \;\Rightarrow\; \operatorname{mainUs}(u, a) \le \operatorname{mainUs}(u, b)$$
-/
theorem mainUs_mono (u : UnitCost) {a b : Work} (h : a.le b) : mainUs u a ≤ mainUs u b := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  unfold mainUs
  have := Nat.mul_le_mul_left u.style h2
  have := Nat.mul_le_mul_left u.layout h3
  have := Nat.mul_le_mul_left u.paint h4
  omega

/-- A frame is one of a variant's: its main-thread work plus compositor-only work.

$$f = (f.\mathit{main},\ f.\mathit{comp}) \in \mathbb{N}^{4} \times \mathbb{N}^{2}$$
-/
structure Frame where
  main : Work
  comp : CompWork

/-- Changing only a frame's compositor work leaves its main-thread cost unchanged (true by
definition in this model; whether a CSS change is compositor-only in an engine is measured).

$$\forall u \in \mathbb{N}^{3},\ \forall \mathit{base} \in \mathbb{N}^{4} \times \mathbb{N}^{2},\ \forall \kappa \in \mathbb{N}^{2}:\quad \operatorname{mainUs}\big(u,\ (\mathit{base}.\mathit{main}, \kappa).\mathit{main}\big) = \operatorname{mainUs}(u, \mathit{base}.\mathit{main})$$
-/
theorem compositorOnly_same_main (u : UnitCost) (base : Frame) (c : CompWork) :
    mainUs u { base with comp := c }.main = mainUs u base.main := rfl

/-- Frame budget: on time iff the main-thread cost fits in `budgetUs` µs (e.g. 16667 at 60 Hz).

$$\operatorname{onTime}(u, B, w) = \mathrm{true} \iff \operatorname{mainUs}(u, w) \le B$$

Edge: equality counts as on time.
-/
def onTime (u : UnitCost) (budgetUs : Nat) (w : Work) : Bool := decide (mainUs u w ≤ budgetUs)

#guard onTime ⟨1, 1, 1⟩ 10 ⟨4, 2, 2, 2⟩ && !onTime ⟨1, 1, 1⟩ 9 ⟨4, 2, 2, 2⟩

/-- If work `a` is componentwise at most work `b` and `b` fits the budget, then `a` fits the
budget (one pair of work vectors; matching a variant's frames to a base's frames is outside the
theorem and the model).

$$\forall u \in \mathbb{N}^{3},\ \forall B \in \mathbb{N},\ \forall a, b \in \mathbb{N}^{4}:\quad a \preceq b \ \land\ \operatorname{onTime}(u, B, b) \;\Rightarrow\; \operatorname{onTime}(u, B, a)$$
-/
theorem onTime_of_le (u : UnitCost) (budgetUs : Nat) {a b : Work} (h : a.le b)
    (hb : onTime u budgetUs b = true) : onTime u budgetUs a = true := by
  simp only [onTime, decide_eq_true_eq] at *
  exact Nat.le_trans (mainUs_mono u h) hb

end Fw.Cost
