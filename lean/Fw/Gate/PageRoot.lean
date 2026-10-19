import Fw.Gate.State
/-!
# The page-root anchor of the breakpoint gate: `scrollWidth <= requested width`

The page root clips horizontal overflow (original `.start-selling`, rewrite `[data-fw="page-root"]`: `overflow-x: clip`). Without the
clip, content wider than the viewport widens the layout viewport under mobile emulation (CI run 39130842058: 645 px for a 430 px
profile) and every width-dependent count is measured on another page. The anchor says, on each arm: the document's `scrollWidth`
does not exceed the viewport the engines give for the width the probe **requested**: $\lceil q \rceil$.

**Which viewport: $\lceil q \rceil$.** Both engines take whole CSS px (`packages/gate-breakpoints/src/engines.mjs:37-38`: a request of
600.5 gets a 601 px viewport, MEASURED), so the page's `scrollWidth` is an integer at least the viewport the engine gave. The
first version compared it with $q$ itself and so called every fractional probe an overflow. `fits` uses the viewport the engines
actually give, `viewportOf q = ⌈q⌉` (`#guard viewportOf 600.5 == 601`); for a whole $q$ nothing changes (`viewportOf_int`).

**Why the requested width and not `innerWidth`.** The first model (round 1 of `faithful-checks-rerun`, ledger finding
`gate.pageRoot.fixedInnerWidth`) compared `scrollWidth` with `innerWidth`. In the 645 px run `innerWidth` was 645 too, so the
anchor held for exactly the run it was written to catch. The requested width is an input of the probe (`Requested.width`), not a
reading of the page, so an enlarged layout viewport cannot move it; $\lceil q \rceil$ is a function of that input alone.

**Limit (stated, not proved here).** The item takes the requested width (rounded up) as the width the page has. It does not check
that `innerWidth` equals it. That is the job of the environment check `width` (`Fw.Gate.envChecks`, the `(width: Wpx)` media query),
of `Fw.Measure.Viewport.viewportFaithful` and of `Fw.Faithful.comparable`. An arm whose layout viewport is wider than requested
shows up here as `scrollWidth > ⌈requested⌉` (differ), and there as a deviation. `scrollWidth` is an integer on the pages. The item is a box item of part `engine.scroll`, role `pageRoot`, appended to the part's items, so it rolls
up with `cellVerdict` like every other item.

Proved: each branch of the status has its own theorem (`status_missing_left`, `status_missing_right`, `status_na`,
`status_equal_iff`, `status_differ_iff`); the item alone in a cell (`cell_pass_iff`, `cell_fail_iff`); an equal item changes no
cell that already compared something (`cell_append_equal`); an arm pair that reports nothing adds no item
(`pageRootItems_none`) and then the state is exactly `evalState` (`evalStateRoot_none`); a differing item fails the state
(`evalStateRoot_fail_of_differ`); the clip makes the anchor hold (`clip_fits`, `noclip_overflows`).
-/
namespace Fw.Gate.PageRoot
open Fw.Gate

/-- The viewport the engines give for a requested width: the next whole CSS px (`engines.mjs:37-38`: 600.5 gives 601).

$$\operatorname{viewportOf}(q) = \lceil q \rceil \qquad (q \in \mathbb Q)$$ -/
def viewportOf (req : Rat) : Rat := (Rat.ceil req : Int)

/-- The anchor on one arm: no horizontal overflow beyond the viewport the engines give for the requested width.

$$\operatorname{fits}(q, s) \iff s \le \lceil q \rceil \qquad (s = \texttt{scrollWidth},\ q = \text{requested width};\ s, q \in \mathbb Q)$$ -/
def fits (req s : Rat) : Bool := decide (s ≤ viewportOf req)

/-- The status of the anchor item for one probe: the original is the control, the rewrite is judged.

$$\operatorname{status}_q(o, r) = \begin{cases} \mathrm{missing} & o = \bot \vee r = \bot \\ \mathrm{na} & o \ne \bot \wedge r \ne \bot \wedge \neg\operatorname{fits}(q, o) \\ \mathrm{equal} & \operatorname{fits}(q, o) \wedge \operatorname{fits}(q, r) \\ \mathrm{differ} & \operatorname{fits}(q, o) \wedge \neg\operatorname{fits}(q, r) \end{cases} \qquad (o, r \in \mathbb Q_\bot)$$

An arm that did not report a `scrollWidth` gives `missing`; an original that itself overflows is not a valid control (`na`);
otherwise the rewrite must fit. -/
def status (req : Rat) : Option Rat → Option Rat → Status
  | some o, some r => if !fits req o then .na else if fits req r then .equal else .differ
  | _, _ => .missing

/-- The key of the anchor item.

$$\mathrm{key} = \texttt{scrollWidth<=requestedWidth}$$ -/
def itemKey : String := "scrollWidth<=requestedWidth"

/-- The part the anchor item belongs to.

$$\mathrm{part} = \texttt{engine.scroll}$$ -/
def partId : String := "engine.scroll"

/-- The anchor as a gate item.

$$\operatorname{item}_q(o, r) = (\mathrm{box},\ \texttt{pageRoot},\ 0,\ \texttt{scrollWidth<=requestedWidth},\ \operatorname{status}_q(o, r),\ \mathrm{false})$$ -/
def pageRootItem (req : Rat) (o r : Option Rat) : PItem :=
  ⟨.box, "pageRoot", 0, itemKey, status req o r, false⟩

/-- The items the anchor adds to part `engine.scroll`: none when neither arm reported a `scrollWidth` (a record taken before the
harness read it), else the one item.

$$\operatorname{items}_q(o, r) = \begin{cases} [\,] & o = \bot \wedge r = \bot \\ [\operatorname{item}_q(o, r)] & \text{otherwise} \end{cases}$$ -/
def pageRootItems (req : Rat) (o r : Option Rat) : List PItem :=
  if o.isNone && r.isNone then [] else [pageRootItem req o r]

/-- The part table with the anchor item appended to part `engine.scroll`.

$$\operatorname{add}_q(o, r, \Pi) = [\,(p, I \mathbin{+\!\!+} (p = \texttt{engine.scroll} ? \operatorname{items}_q(o, r) : [\,])) \mid (p, I) \in \Pi\,]$$ -/
def addRoot (req : Rat) (o r : Option Rat) (ps : List (String × List PItem)) : List (String × List PItem) :=
  ps.map fun p => if p.1 == partId then (p.1, p.2 ++ pageRootItems req o r) else p

/-- One state judged with the anchor: `evalState` with the item added to `engine.scroll`, then the rows, the compared counts and
the verdict taken again from the new part table (the truth items and the reach are those of `evalState`).

$$\operatorname{evalRoot}(C, s, o, r) = \operatorname{evalState}(C, s)\ \text{with}\ \Pi' = \operatorname{add}_{s.\mathrm{requested}.\mathrm{width}}(o, r, \Pi),\ \mathit{rows}' = \operatorname{reachRows}(\operatorname{reach}, \operatorname{rowVerdicts}(T, \Pi')),\ \mathit{compared}' = [\,(p, |\{\iota \in I : \iota \text{ is compared}\}|) \mid (p, I) \in \Pi'\,],\ \mathit{verdict}' = \operatorname{rollup}(\mathit{rows}')$$

Here $o, r$ are the `scrollWidth` of the original and the rewrite arm; $\mathit{compared}'$ is recomputed from the new part table $\Pi'$
(an item that compares something raises the count of `engine.scroll` by one), not carried over from $\operatorname{evalState}$. -/
def evalStateRoot (c : Ctx) (s : StateIn) (o r : Option Rat) : StateOut :=
  let e := evalState c s
  let ps := addRoot s.requested.width o r e.parts
  let rows := reachRows e.reach (rowVerdicts e.truth ps)
  { e with parts := ps, rows, compared := ps.map fun p => (p.1, p.2.countP isCompared),
           verdict := rollup (rows.map (·.2)) }

/-! ## The status, branch by branch -/

/-- A fit is exactly a scroll width within the viewport the engines give.

$$\operatorname{fits}(q, s) = \mathrm{true} \iff s \le \lceil q \rceil$$ -/
theorem fits_iff (req s : Rat) : fits req s = true ↔ s ≤ viewportOf req := by
  simp [fits]

/-- The viewport is never narrower than the request.

$$q \le \lceil q \rceil$$ -/
theorem le_viewportOf (req : Rat) : req ≤ viewportOf req := Rat.le_ceil

/-- For a whole requested width the viewport is the request itself: whole widths are judged as before.

$$\forall n \in \mathbb Z,\quad \lceil n \rceil = n$$ -/
theorem viewportOf_int (n : Int) : viewportOf (n : Rat) = n := by
  simp [viewportOf, Rat.ceil_intCast]

/-- A fractional request is judged against the next whole px: a page of that width fits, a page one px wider does not.

$$\lceil 600.5 \rceil = 601 \ \wedge\ \operatorname{fits}(600.5, 601) \ \wedge\ \neg\operatorname{fits}(600.5, 602)$$ -/
theorem fits_fractional_example :
    viewportOf (1201 / 2) = 601 ∧ fits (1201 / 2) 601 = true ∧ fits (1201 / 2) 602 = false := by
  decide +kernel

/-- A scroll width within the request itself fits.

$$s \le q \implies \operatorname{fits}(q, s)$$ -/
theorem fits_of_le (req s : Rat) (h : s ≤ req) : fits req s = true :=
  (fits_iff _ _).mpr (Rat.le_trans h (le_viewportOf req))

/-- An original that was not observed gives `missing`.

$$\operatorname{status}_q(\bot, r) = \mathrm{missing} \qquad (r \in \mathbb Q_\bot)$$ -/
theorem status_missing_left (req : Rat) (r : Option Rat) : status req none r = .missing := by
  cases r <;> rfl

/-- A rewrite that was not observed gives `missing`.

$$\operatorname{status}_q(o, \bot) = \mathrm{missing} \qquad (o \in \mathbb Q_\bot)$$ -/
theorem status_missing_right (req : Rat) (o : Option Rat) : status req o none = .missing := by
  cases o <;> rfl

/-- An overflowing original is never a verdict: the item is `na`, whatever the rewrite does.

$$o > \lceil q \rceil \implies \operatorname{status}_q(o, r) = \mathrm{na} \qquad (o, r \in \mathbb Q)$$ -/
theorem status_na (req o r : Rat) (h : viewportOf req < o) : status req (some o) (some r) = .na := by
  have : fits req o = false := by
    simp [fits, Rat.not_le.mpr h]
  simp [status, this]

/-- Equal exactly when both arms fit.

$$\operatorname{status}_q(o, r) = \mathrm{equal} \iff \operatorname{fits}(q, o) \wedge \operatorname{fits}(q, r) \qquad (o, r \in \mathbb Q)$$ -/
theorem status_equal_iff (req o r : Rat) :
    status req (some o) (some r) = .equal ↔ fits req o = true ∧ fits req r = true := by
  unfold status
  cases ho : fits req o <;> cases hr : fits req r <;> simp [ho, hr]

/-- Differs exactly when the original fits and the rewrite overflows.

$$\operatorname{status}_q(o, r) = \mathrm{differ} \iff \operatorname{fits}(q, o) \wedge \neg\operatorname{fits}(q, r) \qquad (o, r \in \mathbb Q)$$ -/
theorem status_differ_iff (req o r : Rat) :
    status req (some o) (some r) = .differ ↔ fits req o = true ∧ fits req r = false := by
  unfold status
  cases ho : fits req o <;> cases hr : fits req r <;> simp [ho, hr]

/-! ## The item in a cell -/

/-- As the only item of a cell, the anchor passes exactly when both arms fit.

$$\operatorname{cell}([\operatorname{status}_q(o, r)]) = \mathrm{pass} \iff \operatorname{fits}(q, o) \wedge \operatorname{fits}(q, r)$$ -/
theorem cell_pass_iff (req o r : Rat) :
    cellVerdict [status req (some o) (some r)] = .pass ↔ fits req o = true ∧ fits req r = true := by
  unfold status cellVerdict
  cases ho : fits req o <;> cases hr : fits req r <;> simp [ho, hr]

/-- As the only item of a cell, the anchor fails exactly when the original fits and the rewrite overflows.

$$\operatorname{cell}([\operatorname{status}_q(o, r)]) = \mathrm{fail} \iff \operatorname{fits}(q, o) \wedge \neg\operatorname{fits}(q, r)$$ -/
theorem cell_fail_iff (req o r : Rat) :
    cellVerdict [status req (some o) (some r)] = .fail ↔ fits req o = true ∧ fits req r = false := by
  unfold status cellVerdict
  cases ho : fits req o <;> cases hr : fits req r <;> simp [ho, hr]

/-- An equal item changes no cell that already compared something.

$$\left(\exists s \in ss,\ s \ne \mathrm{na}\right) \implies \operatorname{cell}(ss \mathbin{+\!\!+} [\mathrm{equal}]) = \operatorname{cell}(ss)$$

This is why the dispatched run, where the item is equal in both arms, leaves every cell as it was. -/
theorem cell_append_equal (ss : List Status) (h : ∃ s ∈ ss, s ≠ .na) :
    cellVerdict (ss ++ [.equal]) = cellVerdict ss := by
  obtain ⟨s, hs, hna⟩ := h
  have hne : (ss.filter (· != .na)).isEmpty = false := by
    rw [List.isEmpty_eq_false_iff_exists_mem]
    exact ⟨s, List.mem_filter.mpr ⟨hs, by simpa using hna⟩, ⟩
  unfold cellVerdict
  simp [List.filter_append, hne]

/-! ## The items of a state -/

/-- Neither arm reported a `scrollWidth`: no item.

$$\operatorname{items}_q(\bot, \bot) = [\,]$$ -/
theorem pageRootItems_none (req : Rat) : pageRootItems req none none = [] := rfl

/-- At least one arm reported: exactly the one item.

$$o \ne \bot \vee r \ne \bot \implies \operatorname{items}_q(o, r) = [\operatorname{item}_q(o, r)]$$ -/
theorem pageRootItems_some (req : Rat) (o r : Option Rat) (h : o ≠ none ∨ r ≠ none) :
    pageRootItems req o r = [pageRootItem req o r] := by
  unfold pageRootItems
  rcases h with h | h
  · cases o with
    | none => exact absurd rfl h
    | some _ => simp
  · cases r with
    | none => exact absurd rfl h
    | some _ => simp

/-- With nothing reported, the part table is unchanged.

$$\operatorname{add}_q(\bot, \bot, \Pi) = \Pi$$ -/
theorem addRoot_none (req : Rat) (ps : List (String × List PItem)) : addRoot req none none ps = ps := by
  unfold addRoot
  have h : ∀ p : String × List PItem,
      (if (p.1 == partId) = true then (p.1, p.2 ++ pageRootItems req none none) else p) = p := by
    intro p
    simp only [pageRootItems_none, List.append_nil]
    split <;> rfl
  exact (List.map_congr_left fun p _ => h p).trans (List.map_id _)

/-- **Nothing reported, nothing changed.** A state whose arms report no `scrollWidth` is judged exactly as `evalState` does.

$$\operatorname{evalRoot}(C, s, \bot, \bot) = \operatorname{evalState}(C, s)$$

The records of runs taken before the harness read `scrollWidth` keep their verdicts. -/
theorem evalStateRoot_none (c : Ctx) (s : StateIn) : evalStateRoot c s none none = evalState c s := by
  have h := addRoot_none s.requested.width (evalState c s).parts
  unfold evalStateRoot
  simp only [h]
  have hr : reachRows (evalState c s).reach (rowVerdicts (evalState c s).truth (evalState c s).parts) =
      (evalState c s).rows := rfl
  have hc : (evalState c s).parts.map (fun p => (p.1, p.2.countP isCompared)) = (evalState c s).compared := rfl
  have hv : rollup ((evalState c s).rows.map (·.2)) = (evalState c s).verdict := rfl
  simp only [hr, hc, hv]

/-- **A differing anchor fails the state.** On a reachable state with part `engine.scroll` covered, an original that fits and a
rewrite that overflows the requested width give verdict `fail`.

$$\forall C, s,\ \texttt{engine.scroll} \in C.\mathrm{parts} \wedge \operatorname{reach}(C, s) = \bot \wedge o \le \lceil q \rceil \wedge \lceil q \rceil < r \implies \operatorname{evalRoot}(C, s, \mathrm{some}\ o, \mathrm{some}\ r).\mathit{verdict} = \mathrm{fail}$$ -/
theorem evalStateRoot_fail_of_differ (c : Ctx) (s : StateIn) (o r : Rat)
    (hp : ∃ sp ∈ c.parts, sp.id = partId) (h0 : stateReach c s = none)
    (ho : o ≤ viewportOf s.requested.width) (hr : viewportOf s.requested.width < r) :
    (evalStateRoot c s (some o) (some r)).verdict = .fail := by
  obtain ⟨sp, hsp, hid⟩ := hp
  have hdiff : status s.requested.width (some o) (some r) = .differ :=
    (status_differ_iff _ _ _).mpr ⟨by simp [fits, ho], by simp [fits, Rat.not_le.mpr hr]⟩
  have hreach : (evalState c s).reach = none := h0
  let items := partItems c.anchors sp (s.orig.parts.lookup sp.id) (s.rewrite.parts.lookup sp.id)
    ((c.props.lookup sp.id).getD [])
  have hmemP : (sp.id, items ++ [pageRootItem s.requested.width (some o) (some r)]) ∈
      addRoot s.requested.width (some o) (some r) (evalState c s).parts := by
    unfold addRoot
    refine List.mem_map.mpr ⟨(sp.id, items), ?_, ?_⟩
    · show _ ∈ stateParts c s.orig.parts s.rewrite.parts
      unfold stateParts
      exact List.mem_map.mpr ⟨sp, hsp, rfl⟩
    · simp [hid, pageRootItems]
  unfold evalStateRoot
  simp only [rollup_fail_iff, List.mem_map, hreach, reachRows]
  refine ⟨(sp.id, cellVerdict ((items ++ [pageRootItem s.requested.width (some o) (some r)]).map (·.status))), ?_, ?_⟩
  · simp only [rowVerdicts, List.mem_append, List.mem_map]
    right
    exact ⟨_, hmemP, rfl⟩
  · show cellVerdict _ = .fail
    rw [cellVerdict_fail_iff]
    refine ⟨.differ, ?_, by simp, by simp⟩
    simp [pageRootItem, hdiff]

/-! ## Why the clip makes the anchor hold -/

/-- The document's scroll width: the viewport, or the widest content when nothing clips.

$$\operatorname{scrollW}(c, v, W) = \begin{cases} v & c \\ \max(v, W) & \neg c \end{cases} \qquad (c \in \mathbb B,\ v, W \in \mathbb Q)$$

With `overflow-x: clip` on the page root the content's width cannot extend the scrollable area; without it the scroll width is
the content's. The layout viewport itself is not modelled: `v` is the viewport the engines give, `viewportOf q`. -/
def scrollWidthOf (clip : Bool) (viewport content : Rat) : Rat :=
  if clip then viewport else if viewport ≤ content then content else viewport

/-- With the clip, the anchor holds for any content width.

$$\forall q, W \in \mathbb Q,\quad \operatorname{fits}(q, \operatorname{scrollW}(\mathrm{true}, \lceil q \rceil, W))$$ -/
theorem clip_fits (q w : Rat) : fits q (scrollWidthOf true (viewportOf q) w) = true := by
  simp [fits, scrollWidthOf]

/-- Without the clip, content wider than the viewport breaks the anchor.

$$\forall q, W \in \mathbb Q,\quad \lceil q \rceil < W \implies \neg\operatorname{fits}(q, \operatorname{scrollW}(\mathrm{false}, \lceil q \rceil, W))$$ -/
theorem noclip_overflows (q w : Rat) (h : viewportOf q < w) :
    fits q (scrollWidthOf false (viewportOf q) w) = false := by
  simp [fits, scrollWidthOf, Rat.le_of_lt h, Rat.not_le.mpr h]

/-- Without the clip, content no wider than the viewport keeps the anchor.

$$\forall q, W \in \mathbb Q,\quad W \le \lceil q \rceil \implies \operatorname{fits}(q, \operatorname{scrollW}(\mathrm{false}, \lceil q \rceil, W))$$ -/
theorem noclip_fits_of_le (q w : Rat) (h : w ≤ viewportOf q) :
    fits q (scrollWidthOf false (viewportOf q) w) = true := by
  by_cases hv : viewportOf q ≤ w
  · have : w = viewportOf q := Rat.le_antisymm h hv
    simp [fits, scrollWidthOf, this]
  · simp [fits, scrollWidthOf, hv]

/-! ## Examples -/

#guard viewportOf 600.5 == 601
#guard viewportOf 430 == 430
#guard status 600.5 (some 601) (some 601) == .equal
#guard status 600.5 (some 601) (some 602) == .differ
#guard status 600.5 (some 602) (some 601) == .na
#guard status 430 (some 430) (some 430) == .equal
#guard status 430 (some 430) (some 645) == .differ
#guard status 430 (some 645) (some 430) == .na
#guard status 430 (some 430) none == .missing
#guard status 430 none (some 430) == .missing
#guard (pageRootItems 430 none none).isEmpty
#guard pageRootItems 430 (some 430) (some 430) == [⟨.box, "pageRoot", 0, "scrollWidth<=requestedWidth", .equal, false⟩]

end Fw.Gate.PageRoot
