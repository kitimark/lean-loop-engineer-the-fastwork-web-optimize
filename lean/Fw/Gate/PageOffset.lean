/-!
# Page-offset check of the breakpoint gate (`fix-page-offset`; proposal, not yet wired into `page.mjs`/`run.mjs`)

**The gap.** The gate compares each part's geometry relative to the part (its own boxes), so a block that sits in
the document flow in the rewrite but not in the original moves every later part down by the same amount and no cell
fails. Found by `fix-pain-notes`: the placeholder page carried the morph countdown (`margin-top 32px` + 120 px clock,
152 px of flow) in `<main>`, while the original keeps it inside the fixed nav panel, so `people`, `pain`,
`commission` and `platform` all sat 152 px lower and the 16 remaining Chromium `pain.notes` probes failed.

**The check.** For one probe load, take each part's root box top in document coordinates ($y_{\text{rect}} +
\text{scrollY}$) in both arms. One cell per part: $\text{pass} \iff |t^{\text{ours}} - t^{\text{orig}}| \le \tau$.
A part absent from one arm fails its cell (an unmatched part is a difference, not a skip).

What is proved: equal tops pass (`pageCells_self`), and a uniform shift larger than the tolerance fails every cell
(`pageCells_shift_all_fail`), so at least one (`shift_fails_some`); `flow_shift` shows where such a shift comes
from: an in-flow block moves every later top by its height, an out-of-flow one by nothing.
-/
namespace Fw.Gate.PageOffset

/-! ## Cause: which blocks take flow space -/

/-- CSS `position` classes that matter for flow.

$$\mathrm{Pos} = \{\mathrm{static}, \mathrm{relative}, \mathrm{sticky}, \mathrm{absolute}, \mathrm{fixed}\}$$ -/
inductive Pos | static | relative | sticky | absolute | fixed
  deriving DecidableEq, Repr

/-- Out-of-flow boxes (`absolute`, `fixed`) take no space in their parent's block flow.

$$\operatorname{inFlow}(p) = [\,p \notin \{\mathrm{absolute}, \mathrm{fixed}\}\,]$$ -/
def inFlow : Pos → Bool
  | .absolute => false
  | .fixed => false
  | _ => true

/-- Top of the block that follows `blocks` in a stack that starts at `y0`: the sum of the in-flow heights.

$$\operatorname{next}(y_0, [(p_i, h_i)]) = y_0 + \sum_{i:\ p_i \text{ in flow}} h_i$$ -/
def next (y0 : Rat) : List (Pos × Rat) → Rat
  | [] => y0
  | (p, h) :: t => next (y0 + if inFlow p then h else 0) t

/-- Sum of the in-flow heights.

$$\operatorname{flowSum}([(p_i, h_i)]) = \sum_{i:\ p_i \text{ in flow}} h_i$$ -/
def flowSum : List (Pos × Rat) → Rat
  | [] => 0
  | (p, h) :: t => (if inFlow p then h else 0) + flowSum t

/-- The next top is the start plus the in-flow sum.

$$\operatorname{next}(y_0, bs) = y_0 + \operatorname{flowSum}(bs)$$ -/
theorem next_eq (bs : List (Pos × Rat)) (y0 : Rat) : next y0 bs = y0 + flowSum bs := by
  induction bs generalizing y0 with
  | nil => simp [next, flowSum, Rat.add_zero]
  | cons b t ih =>
    obtain ⟨p, h⟩ := b
    simp only [next, flowSum]
    rw [ih, Rat.add_assoc]

/-- An in-flow block of height $h$ in front moves every later top by exactly $h$.

$$p \text{ in flow} \Rightarrow \operatorname{next}(y_0, (p, h) :: bs) = \operatorname{next}(y_0, bs) + h$$ -/
theorem flow_shift (p : Pos) (h y0 : Rat) (bs : List (Pos × Rat)) (hp : inFlow p = true) :
    next y0 ((p, h) :: bs) = next y0 bs + h := by
  rw [next_eq, next_eq]
  simp [flowSum, hp]
  rw [Rat.add_comm h, Rat.add_assoc]

/-- An out-of-flow block (a fixed panel, an absolute stage) moves nothing.

$$p \in \{\mathrm{absolute}, \mathrm{fixed}\} \Rightarrow \operatorname{next}(y_0, (p, h) :: bs) = \operatorname{next}(y_0, bs)$$ -/
theorem outOfFlow_noShift (p : Pos) (h y0 : Rat) (bs : List (Pos × Rat)) (hp : inFlow p = false) :
    next y0 ((p, h) :: bs) = next y0 bs := by
  rw [next_eq, next_eq]
  simp [flowSum, hp, Rat.zero_add]

/-- The case found: a static 152 px block (32 px margin + 120 px clock) in front moves the tops by 152, a fixed one by 0. -/
example : next 1800 [(.static, 152)] = next 1800 [(.fixed, 152)] + 152 := by decide +kernel

/-! ## The check: one cell per part -/

/-- Tolerance in px: any rational (the type has no sign constraint; theorems that need $\tau \ge 0$ assume it).

$$\tau \in \mathbb{Q}$$ -/
abbrev Tol := Rat

/-- One probed part: its id and the document top of its root box in each arm (`none` = no box).

$$\mathrm{PartTop} = (\mathrm{part},\ t^{o} \in \mathbb{Q}_{\bot},\ t^{r} \in \mathbb{Q}_{\bot})$$ -/
structure PartTop where
  part : String
  orig : Option Rat
  ours : Option Rat
  deriving Repr

/-- The cell passes iff both boxes exist and $|t^{\text{ours}} - t^{\text{orig}}| \le \tau$.

$$\text{cell}(t^{o}, t^{r}, \tau) = \begin{cases} [\,t^{r} - t^{o} \le \tau \ \wedge\ t^{o} - t^{r} \le \tau\,] & t^{o} \ne \bot \wedge t^{r} \ne \bot \\ \text{false} & \text{otherwise} \end{cases}$$ -/
def cellPass (τ : Tol) (p : PartTop) : Bool :=
  match p.orig, p.ours with
  | some o, some r => decide (r - o ≤ τ ∧ o - r ≤ τ)
  | _, _ => false

/-- The cells of a probe load, in part order.

$$\operatorname{pageCells}(\tau, [p_i]) = [\operatorname{cell}(p_i, \tau)]_i$$ -/
def pageCells (τ : Tol) (ps : List PartTop) : List Bool := ps.map (cellPass τ)

/-- Equal tops pass for $\tau \ge 0$.

$$0 \le \tau \Rightarrow \operatorname{cell}(t, t, \tau) = \text{true}$$ -/
theorem pageCells_self (τ : Tol) (hτ : 0 ≤ τ) (id : String) (t : Rat) :
    cellPass τ ⟨id, some t, some t⟩ = true := by
  simp only [cellPass, decide_eq_true_eq]
  rw [Rat.sub_self]
  exact ⟨hτ, hτ⟩

/-- A shift $d$ with $\tau < d$ fails the cell.

$$\tau < d \Rightarrow \operatorname{cell}(t, t + d, \tau) = \text{false}$$ -/
theorem cell_shift_fail_pos (τ d t : Rat) (id : String) (hd : τ < d) :
    cellPass τ ⟨id, some t, some (t + d)⟩ = false := by
  simp only [cellPass]
  have : ¬ (t + d - t ≤ τ ∧ t - (t + d) ≤ τ) := by
    intro ⟨h, _⟩
    have e : t + d - t = d := by rw [Rat.add_comm t d, Rat.sub_eq_add_neg, Rat.add_assoc, Rat.add_neg_cancel, Rat.add_zero]
    rw [e] at h
    exact Rat.not_le.mpr hd h
  simpa using this

/-- Same for a shift upward.

$$\tau < d \Rightarrow \operatorname{cell}(t, t - d, \tau) = \text{false}$$ -/
theorem cell_shift_fail_neg (τ d t : Rat) (id : String) (hd : τ < d) :
    cellPass τ ⟨id, some t, some (t - d)⟩ = false := by
  simp only [cellPass]
  have : ¬ (t - d - t ≤ τ ∧ t - (t - d) ≤ τ) := by
    intro ⟨_, h⟩
    have e : t - (t - d) = d := by
      rw [Rat.sub_eq_add_neg, Rat.neg_sub, Rat.sub_eq_add_neg, Rat.add_comm t, Rat.add_assoc,
        Rat.neg_add_cancel, Rat.add_zero]
    rw [e] at h
    exact Rat.not_le.mpr hd h
  simpa using this

/-- Every part shifted by $d > \tau$ in the second arm: every cell fails.

$$\tau < d \Rightarrow \forall i,\ \operatorname{cell}(t_i, t_i + d, \tau) = \text{false}$$ -/
theorem pageCells_shift_all_fail (τ d : Rat) (hd : τ < d) (xs : List (String × Rat)) :
    (pageCells τ (xs.map fun x => ⟨x.1, some x.2, some (x.2 + d)⟩)).all (· = false) = true := by
  induction xs with
  | nil => rfl
  | cons x t ih =>
    simp only [pageCells, List.map_cons, List.all_cons, Bool.and_eq_true] at ih ⊢
    refine ⟨?_, ih⟩
    rw [cell_shift_fail_pos τ d x.2 x.1 hd]
    rfl

/-- The page-level gap closes: with at least one part, a uniform page offset $d > \tau$ makes at least one cell fail
(the existing part-local cells would all stay green).

$$xs \ne [\,] \wedge \tau < d \Rightarrow \text{false} \in \operatorname{pageCells}(\tau, xs \text{ shifted by } d)$$ -/
theorem shift_fails_some (τ d : Rat) (hd : τ < d) (xs : List (String × Rat)) (hne : xs ≠ []) :
    false ∈ pageCells τ (xs.map fun x => ⟨x.1, some x.2, some (x.2 + d)⟩) := by
  cases xs with
  | nil => exact absurd rfl hne
  | cons x t =>
    simp only [pageCells, List.map_cons, List.mem_cons]
    left
    exact (cell_shift_fail_pos τ d x.2 x.1 hd).symm

/-- A part with no box in one arm fails: a missing part is a difference.

$$\operatorname{cell}(o, \bot, \tau) = \operatorname{cell}(\bot, o, \tau) = \text{false}$$ -/
theorem missing_fails (τ : Tol) (id : String) (o : Option Rat) :
    cellPass τ ⟨id, o, none⟩ = false ∧ cellPass τ ⟨id, none, o⟩ = false := by
  cases o <;> simp [cellPass]

/-- The verdict of a load: all cells pass.

$$\operatorname{pagePass}(\tau, ps) = \bigwedge_i \operatorname{cell}_i$$ -/
def pagePass (τ : Tol) (ps : List PartTop) : Bool := (pageCells τ ps).all id

/-- The 152 px case: people at 901 in the original, 1053 in the rewrite, tolerance 1 px, fails.

$\tau = 1,\ t^o = 901,\ t^r = 1053 \Rightarrow \text{pass} = \text{false}$ -/
example : pagePass 1 [⟨"people", some 901, some 1053⟩, ⟨"pain", some (4085 + 1/5), some (4237 + 1/5)⟩] = false := by
  decide +kernel

end Fw.Gate.PageOffset
