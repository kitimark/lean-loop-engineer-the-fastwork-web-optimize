/-!
# A linear per-frame cost model (the *model* is proved; its fit to an engine is measured)

Work counts come from a trace (Chrome) or a Timeline export (WebKit); unit costs are calibrated
per engine/device. Lean proves properties of the model; whether an engine obeys the model is an
empirical claim checked by calibration runs, never by a theorem.
-/
namespace Fw.Cost

/-- Per-frame main-thread work counts. -/
structure Work where
  scriptUs     : Nat      -- JS time already in µs
  styleElems   : Nat      -- elements whose style was recalculated
  layoutObjs   : Nat      -- layout objects laid out
  paintKpx     : Nat      -- painted area, kilo-pixels (main-thread paint recording)
deriving Repr, DecidableEq

/-- Compositor-thread work (no main-thread cost in this model). -/
structure CompWork where
  layersMoved  : Nat
  rasterKpx    : Nat
deriving Repr, DecidableEq

structure UnitCost where
  style  : Nat   -- µs per element
  layout : Nat   -- µs per layout object
  paint  : Nat   -- µs per kpx
deriving Repr

def Work.le (a b : Work) : Prop :=
  a.scriptUs ≤ b.scriptUs ∧ a.styleElems ≤ b.styleElems ∧ a.layoutObjs ≤ b.layoutObjs ∧ a.paintKpx ≤ b.paintKpx

def mainUs (u : UnitCost) (w : Work) : Nat :=
  w.scriptUs + u.style * w.styleElems + u.layout * w.layoutObjs + u.paint * w.paintKpx

/-- More work never costs less (any non-negative unit costs). -/
theorem mainUs_mono (u : UnitCost) {a b : Work} (h : a.le b) : mainUs u a ≤ mainUs u b := by
  obtain ⟨h1, h2, h3, h4⟩ := h
  unfold mainUs
  have := Nat.mul_le_mul_left u.style h2
  have := Nat.mul_le_mul_left u.layout h3
  have := Nat.mul_le_mul_left u.paint h4
  omega

/-- A frame is one of a variant's: its main-thread work plus compositor-only work. -/
structure Frame where
  main : Work
  comp : CompWork

/-- A compositor-only variant changes only `comp`: its main-thread cost equals the base's. -/
theorem compositorOnly_same_main (u : UnitCost) (base : Frame) (c : CompWork) :
    mainUs u { base with comp := c }.main = mainUs u base.main := rfl

/-- Frame budget: on time iff main-thread cost fits in `budgetUs` (e.g. 16667 at 60 Hz). -/
def onTime (u : UnitCost) (budgetUs : Nat) (w : Work) : Bool := decide (mainUs u w ≤ budgetUs)

/-- If a variant's work is pointwise ≤ the base's, every frame on time in the base stays on time. -/
theorem onTime_of_le (u : UnitCost) (budgetUs : Nat) {a b : Work} (h : a.le b)
    (hb : onTime u budgetUs b = true) : onTime u budgetUs a = true := by
  simp only [onTime, decide_eq_true_eq] at *
  exact Nat.le_trans (mainUs_mono u h) hb

end Fw.Cost
