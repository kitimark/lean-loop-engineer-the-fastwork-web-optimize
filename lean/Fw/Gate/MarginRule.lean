import Fw.Gate.Rule
/-!
# The margin rule of the breakpoint gate (task cmr-margin-rect-rule)

A used margin that depends on layout (auto or a percentage) can read a stale value through `getComputedStyle` inside a skipped subtree.
For such a margin, present on both arms, the cell is the node's rect cell; otherwise it is the style comparison.
-/
namespace Fw.Gate

/-- The margin longhands the rule covers (Typed OM read in the collector).

The four inline-axis longhands of the premise `cv.margin-typed-om`. -/
def marginKeys : List String := ["margin-left", "margin-right", "margin-inline-start", "margin-inline-end"]

/-- The rect cell of a node: its box items' rule as a status.

`equal` when every box item of the node is equal, `differ` when one is not, `na` when the node has no box item. -/
def rectCell (boxes : List Status) : Status := toStatus (cellVerdict boxes)

/-- Whether the rule decides a margin cell by the rect: both arms non-fixed and the node has a rect cell.

Non-fixed means the Typed OM value is not a px length. -/
def byRect (nfO nfR : Bool) (rect : Status) : Bool := nfO && nfR && rect != .na

/-- The status of a margin longhand cell: the rect cell when `byRect`, else the style comparison.

No new status: the result is the style status or the rect status. -/
def marginStatus (nfO nfR : Bool) (style rect : Status) : Status :=
  if byRect nfO nfR rect then rect else style

/-- Identity, original arm fixed: the cell is the style cell.

A fixed margin on the original keeps today's comparison. -/
theorem marginStatus_fixed_o (nfR : Bool) (style rect : Status) :
    marginStatus false nfR style rect = style := by
  simp [marginStatus, byRect]

/-- Identity, rewrite arm fixed: the cell is the style cell.

A fixed margin on the rewrite keeps today's comparison. -/
theorem marginStatus_fixed_r (nfO : Bool) (style rect : Status) :
    marginStatus nfO false style rect = style := by
  simp [marginStatus, byRect]

/-- Identity: when either arm is fixed the cell is the style cell.

Either arm fixed leaves the comparison unchanged. -/
theorem marginStatus_fixed (nfO nfR : Bool) (style rect : Status) (h : nfO = false ∨ nfR = false) :
    marginStatus nfO nfR style rect = style := by
  rcases h with rfl | rfl
  · exact marginStatus_fixed_o nfR style rect
  · exact marginStatus_fixed_r nfO style rect

/-- Identity: a node with no rect cell keeps the style cell, whatever the arms.

Without a box item there is nothing to decide by. -/
theorem marginStatus_no_rect (nfO nfR : Bool) (style : Status) :
    marginStatus nfO nfR style .na = style := by
  simp [marginStatus, byRect]

/-- Both arms non-fixed and a rect cell present: the cell is the rect cell.

The style comparison no longer takes part. -/
theorem marginStatus_rect (style rect : Status) (h : rect ≠ .na) :
    marginStatus true true style rect = rect := by
  simp [marginStatus, byRect, h]

/-- A decided margin cell is never `na`.

The rect cell it takes is `equal` or `differ`. -/
theorem marginStatus_rect_ne_na (nfO nfR : Bool) (style rect : Status) (hr : rect ≠ .na)
    (hb : byRect nfO nfR rect = true) : marginStatus nfO nfR style rect ≠ .na := by
  simp [marginStatus, hb, hr]

/-- Every outcome is the style status or the rect status.

The rule adds no outcome kind. -/
theorem marginStatus_cases (nfO nfR : Bool) (style rect : Status) :
    marginStatus nfO nfR style rect = style ∨ (byRect nfO nfR rect = true ∧ marginStatus nfO nfR style rect = rect) := by
  unfold marginStatus
  by_cases h : byRect nfO nfR rect = true <;> simp [h]

/-- No hidden visual difference: with both arms non-fixed and a rect cell, the margin cell fails exactly when the rect cell fails.

Where the rule decides, the margin cell and the node's boxes agree. -/
theorem marginStatus_fail_iff (boxes : List Status) (style : Status) (h : cellVerdict boxes ≠ .nc) :
    cellVerdict [marginStatus true true style (rectCell boxes)] = .fail ↔ cellVerdict boxes = .fail := by
  have hr : rectCell boxes ≠ .na := by
    intro hna
    apply h
    unfold rectCell at hna
    have hu := cellVerdict_isUnreachable boxes
    cases hv : cellVerdict boxes <;> simp_all [toStatus, Verdict.isUnreachable]
  rw [marginStatus_rect style _ hr]
  unfold rectCell
  have hu := cellVerdict_isUnreachable boxes
  cases hv : cellVerdict boxes <;> simp_all [toStatus, cellVerdict, Verdict.isUnreachable]

/-- Passing: with both arms non-fixed and a rect cell, the margin cell passes exactly when the rect cell passes.

Equal styles do not rescue a failing rect, and differing styles do not fail a passing rect. -/
theorem marginStatus_pass_iff (boxes : List Status) (style : Status) (h : cellVerdict boxes ≠ .nc) :
    cellVerdict [marginStatus true true style (rectCell boxes)] = .pass ↔ cellVerdict boxes = .pass := by
  have hr : rectCell boxes ≠ .na := by
    intro hna
    apply h
    unfold rectCell at hna
    have hu := cellVerdict_isUnreachable boxes
    cases hv : cellVerdict boxes <;> simp_all [toStatus, Verdict.isUnreachable]
  rw [marginStatus_rect style _ hr]
  unfold rectCell
  have hu := cellVerdict_isUnreachable boxes
  cases hv : cellVerdict boxes <;> simp_all [toStatus, cellVerdict, Verdict.isUnreachable]

/-- Never pass over a failing rect: a node whose rect cell fails fails, whatever the margin cell.

The box items stay in the part, so no outcome of the rule lifts a failing rect. -/
theorem marginStatus_never_pass_over_failing_rect (boxes : List Status) (hf : cellVerdict boxes = .fail)
    (nfO nfR : Bool) (style : Status) :
    cellVerdict (boxes ++ [marginStatus nfO nfR style (rectCell boxes)]) = .fail := by
  rw [cellVerdict_fail_iff] at hf ⊢
  obtain ⟨s, hs, h1, h2⟩ := hf
  exact ⟨s, List.mem_append_left _ hs, h1, h2⟩

/-- Never pass over a failing rect, at the cell: when the rule decides by the rect and the rect cell fails, the margin cell does not pass.

A decided cell is never pass where the rect fails. -/
theorem marginStatus_decided_not_pass (boxes : List Status) (hf : cellVerdict boxes = .fail)
    (nfO nfR : Bool) (style : Status) (hd : byRect nfO nfR (rectCell boxes) = true) :
    cellVerdict [marginStatus nfO nfR style (rectCell boxes)] ≠ .pass := by
  have hx : marginStatus nfO nfR style (rectCell boxes) = rectCell boxes := by simp [marginStatus, hd]
  rw [hx]
  have : rectCell boxes = .differ := by simp [rectCell, hf, toStatus]
  rw [this]
  decide

/-- The stale strut: a style difference with a passing rect is no failure.

Both arms non-fixed, styles differ, boxes equal: the cell is equal. -/
theorem marginStatus_strut : marginStatus true true .differ (rectCell [.equal, .equal]) = .equal := by
  decide

#guard marginStatus true true .differ .equal == .equal
#guard marginStatus true true .equal .differ == .differ
#guard marginStatus true false .differ .equal == .differ
#guard marginStatus false true .equal .differ == .equal
#guard marginStatus true true .differ .na == .differ
#guard rectCell [] == .na
#guard rectCell [.equal, .na] == .equal
#guard rectCell [.equal, .missing] == .differ

end Fw.Gate
