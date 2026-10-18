import Fw.Gate.Items
/-!
# The page-root anchor of the breakpoint gate: `scrollWidth <= innerWidth`

The page root clips horizontal overflow (original `.start-selling`, rewrite `[data-fw="page-root"]`: `overflow-x: clip`). Without
the clip, content wider than the viewport widens the layout viewport (CI run 39130842058: 645 px for a 430 px profile) and
every width-dependent count is measured on another page. The anchor says: on each arm the document's `scrollWidth` does not
exceed `innerWidth`. The item has the box-item shape of `Fw.Gate.Items` (`PItem`, class `box`), so it rolls up with
`cellVerdict` like every other item.

The gate collects the width of the root box in both arms (role `pageRoot` of part `engine.scroll` in `anchors.json`, dimension
`w`); the observation of `scrollWidth` itself is the input of `pageRootStatus` and is not collected by `page.mjs` yet.
-/
namespace Fw.Gate.PageRoot

/-- What one arm reports about its page width, in CSS px.

$$o = (s,\ i) \in \mathbb Q^{2},\quad s = \texttt{scrollWidth},\ i = \texttt{innerWidth}$$ -/
structure Obs where
  scrollW : Rat
  innerW : Rat
  deriving DecidableEq, Repr, Inhabited

/-- The anchor on one arm: no horizontal overflow.

$$\operatorname{fits}(s, i) \iff s \le i \qquad (s, i \in \mathbb Q)$$ -/
def fits (o : Obs) : Bool := decide (o.scrollW ≤ o.innerW)

/-- The status of the anchor item for one probe: the original is the control, the rewrite is judged.

$$\operatorname{status}(o, r) = \begin{cases} \mathrm{missing} & o = \bot \vee r = \bot \\ \mathrm{na} & o \ne \bot \wedge r \ne \bot \wedge \neg\operatorname{fits}(o) \\ \mathrm{equal} & \operatorname{fits}(o) \wedge \operatorname{fits}(r) \\ \mathrm{differ} & \operatorname{fits}(o) \wedge \neg\operatorname{fits}(r) \end{cases} \qquad (o, r \in \mathrm{Obs}_\bot)$$

An arm that was not observed gives `missing`; an original that itself overflows is not a valid control (`na`); otherwise the rewrite
must fit. -/
def pageRootStatus : Option Obs → Option Obs → Status
  | some o, some r => if !fits o then .na else if fits r then .equal else .differ
  | _, _ => .missing

/-- The anchor as a gate item of part `engine.scroll`.

$$\operatorname{item}(o, r) = (\mathrm{box},\ \texttt{pageRoot},\ 0,\ \texttt{scrollWidth<=innerWidth},\ \operatorname{status}(o, r),\ \mathrm{false})$$ -/
def pageRootItem (o r : Option Obs) : PItem :=
  ⟨.box, "pageRoot", 0, "scrollWidth<=innerWidth", pageRootStatus o r, false⟩

/-- Equal exactly when both arms fit.

$$\operatorname{status}(\mathrm{some}\ o, \mathrm{some}\ r) = \mathrm{equal} \iff \operatorname{fits}(o) \wedge \operatorname{fits}(r)$$ -/
theorem status_equal_iff (o r : Obs) :
    pageRootStatus (some o) (some r) = .equal ↔ fits o = true ∧ fits r = true := by
  unfold pageRootStatus
  cases ho : fits o <;> cases hr : fits r <;> simp [ho, hr]

/-- Differs exactly when the original fits and the rewrite overflows.

$$\operatorname{status}(\mathrm{some}\ o, \mathrm{some}\ r) = \mathrm{differ} \iff \operatorname{fits}(o) \wedge \neg\operatorname{fits}(r)$$ -/
theorem status_differ_iff (o r : Obs) :
    pageRootStatus (some o) (some r) = .differ ↔ fits o = true ∧ fits r = false := by
  unfold pageRootStatus
  cases ho : fits o <;> cases hr : fits r <;> simp [ho, hr]

/-- An overflowing original is never a verdict: the item is `na`, whatever the rewrite does.

$$\neg\operatorname{fits}(o) \implies \operatorname{status}(\mathrm{some}\ o, \mathrm{some}\ r) = \mathrm{na} \qquad (r \in \mathrm{Obs})$$ -/
theorem status_na_of_orig_overflow (o r : Obs) (h : fits o = false) :
    pageRootStatus (some o) (some r) = .na := by
  simp [pageRootStatus, h]

/-- An arm that was not observed gives `missing`.

$$\operatorname{status}(\bot, r) = \operatorname{status}(o, \bot) = \mathrm{missing} \qquad (o, r \in \mathrm{Obs}_\bot)$$ -/
theorem status_missing (o r : Option Obs) (h : o = none ∨ r = none) :
    pageRootStatus o r = .missing := by
  rcases h with h | h
  · subst h; cases r <;> simp [pageRootStatus]
  · subst h; cases o <;> simp [pageRootStatus]

/-- As the only item of a cell, the anchor passes exactly when both arms fit.

$$\operatorname{cell}([\operatorname{status}(\mathrm{some}\ o, \mathrm{some}\ r)]) = \mathrm{pass} \iff \operatorname{fits}(o) \wedge \operatorname{fits}(r)$$ -/
theorem cell_pass_iff (o r : Obs) :
    cellVerdict [pageRootStatus (some o) (some r)] = .pass ↔ fits o = true ∧ fits r = true := by
  unfold pageRootStatus cellVerdict
  cases ho : fits o <;> cases hr : fits r <;> simp [ho, hr]

/-- As the only item of a cell, the anchor fails exactly when the original fits and the rewrite overflows.

$$\operatorname{cell}([\operatorname{status}(\mathrm{some}\ o, \mathrm{some}\ r)]) = \mathrm{fail} \iff \operatorname{fits}(o) \wedge \neg\operatorname{fits}(r)$$ -/
theorem cell_fail_iff (o r : Obs) :
    cellVerdict [pageRootStatus (some o) (some r)] = .fail ↔ fits o = true ∧ fits r = false := by
  unfold pageRootStatus cellVerdict
  cases ho : fits o <;> cases hr : fits r <;> simp [ho, hr]

/-! ## Why the clip makes the anchor hold -/

/-- The document's scroll width: the viewport, or the widest content when nothing clips.

$$\operatorname{scrollW}(c, v, W) = \begin{cases} v & c \\ \max(v, W) & \neg c \end{cases} \qquad (c \in \mathbb B,\ v, W \in \mathbb Q)$$

With `overflow-x: clip` on the page root the content's width cannot extend the scrollable area. -/
def scrollWidthOf (clip : Bool) (viewport content : Rat) : Rat :=
  if clip then viewport else if viewport ≤ content then content else viewport

/-- With the clip, the anchor holds for any content width.

$$\forall v, W \in \mathbb Q,\quad \operatorname{fits}(\operatorname{scrollW}(\mathrm{true}, v, W),\ v)$$ -/
theorem clip_fits (v w : Rat) : fits ⟨scrollWidthOf true v w, v⟩ = true := by
  simp [fits, scrollWidthOf]

/-- Without the clip, content wider than the viewport breaks the anchor.

$$\forall v, W \in \mathbb Q,\quad v < W \implies \neg\operatorname{fits}(\operatorname{scrollW}(\mathrm{false}, v, W),\ v)$$ -/
theorem noclip_overflows (v w : Rat) (h : v < w) : fits ⟨scrollWidthOf false v w, v⟩ = false := by
  simp [fits, scrollWidthOf, Rat.le_of_lt h, Rat.not_le.mpr h]

/-- Without the clip, content no wider than the viewport keeps the anchor.

$$\forall v, W \in \mathbb Q,\quad W \le v \implies \operatorname{fits}(\operatorname{scrollW}(\mathrm{false}, v, W),\ v)$$ -/
theorem noclip_fits_of_le (v w : Rat) (h : w ≤ v) : fits ⟨scrollWidthOf false v w, v⟩ = true := by
  by_cases hv : v ≤ w
  · have : w = v := Rat.le_antisymm h hv
    simp [fits, scrollWidthOf, this]
  · simp [fits, scrollWidthOf, hv]

#guard pageRootStatus (some ⟨430, 430⟩) (some ⟨430, 430⟩) == .equal
#guard pageRootStatus (some ⟨430, 430⟩) (some ⟨645, 645⟩) == .equal
#guard pageRootStatus (some ⟨430, 430⟩) (some ⟨645, 430⟩) == .differ
#guard pageRootStatus (some ⟨645, 430⟩) (some ⟨430, 430⟩) == .na
#guard pageRootStatus (some ⟨430, 430⟩) none == .missing

end Fw.Gate.PageRoot
