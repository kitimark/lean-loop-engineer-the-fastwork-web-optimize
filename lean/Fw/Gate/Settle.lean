import Lean.Data.Json
/-!
# When is a gate sample settled? (`gate-settle`)

The breakpoint gate compares a page state of the original against one of the rewrite. A sample taken while the page is
still moving measures the moment, not the page. Run 39067170911 had three such misreads, each with a different cause:

| cell | what moved | observable that says so |
|---|---|---|
| `pain.notes` | the original lays its notes out from a `ResizeObserver` callback and a `requestAnimationFrame` callback, so after a resize it is one layout behind until two rendered frames have passed | `frames < 2` (or no real rAF at all) |
| `hero.orbit` | `z-index` is 1 + the number of `pointerenter` events the parked pointer caused, a count that depends on timing | the pointer is inside a hover-reactive target |
| `overlays.signup` (WebKit touch) | the dialog was sampled mid enter animation (scale 0.9977) | a finite animation or transition still runs under the probed subtree |

The decision is `settled` over an observation `Obs` of the page. The wait policy `wait` looks at observations in order and
stops at the first settled one inside a time budget; past the budget it answers `unsettled`. A cell report
(`report`) is `pass`/`fail` only when both arms settled; otherwise it is `unsettled`, never a silent pass or fail.
`Traj` is the stated monotone-settling model: animations only finish, frames only count up, the pointer stays where it
is, and a settled page does not repaint the probed properties. Under it a settled sample is independent of when it was
taken (`sample_delay_invariant`).

The TypeScript twin is `packages/gate-breakpoints/src/settle.mjs`; `packages/contracts/golden/gate/settle.jsonl` is
generated here (`goldenText`) and the package test replays it.
-/
namespace Fw.Gate.Settle
open Lean

/-- One observation of a page arm while the gate waits.

$$o = (\mathit{run}, \mathit{fr}, \mathit{st}, \mathit{hov}, t) \in \mathbb{N}\times\mathbb{N}\times\mathbb{N}\times\{0,1\}\times\mathbb{N}$$

`running`: finite animations and transitions under the probed subtree that have not finished; `frames`: real
`requestAnimationFrame` callbacks since the wait began (the wait begins after the last resize); `stable`: consecutive
frames whose probed boxes did not change; `hoverInside`: the pointer is inside a hover-reactive probed target;
`t`: milliseconds since the wait began. -/
structure Obs where
  running : Nat
  frames : Nat
  stable : Nat
  hoverInside : Bool
  t : Nat
  deriving DecidableEq, Repr

/-- The wait policy.

$$\pi = (m_f, m_s, \varepsilon, T) \in \mathbb{N}^4$$

`minFrames`: real frames required after the last resize; `minStable`: quiet frames required in a row; `eps`: the quiet
threshold in millionths of a unit (px, or a unitless value such as a scale); `timeoutMs`: the bound of the wait. -/
structure Policy where
  minFrames : Nat
  minStable : Nat
  eps : Nat
  timeoutMs : Nat
  deriving DecidableEq, Repr

/-- The policy the gate uses: two frames after each resize (a `ResizeObserver` notification, then the callback it
schedules), three quiet frames in a row, quiet meaning every probed value moved by at most 0.0001, 3000 ms.

$$\pi_{\mathrm{gate}} = (2, 3, 100, 3000)$$ -/
def gatePolicy : Policy := { minFrames := 2, minStable := 3, eps := 100, timeoutMs := 3000 }

/-- The decision on one observation: nothing animates, enough real frames passed, the boxes were stable, and the pointer
is not inside a hover-reactive target.

$$\operatorname{settled}_\pi(o) \iff \mathit{run}(o) = 0 \;\wedge\; m_f \le \mathit{fr}(o) \;\wedge\; m_s \le \mathit{st}(o) \;\wedge\; \neg\,\mathit{hov}(o)$$ -/
def settled (p : Policy) (o : Obs) : Bool :=
  o.running == 0 && decide (p.minFrames ≤ o.frames) && decide (p.minStable ≤ o.stable) && !o.hoverInside

/-- The sample decision (a sample is good when its observation is settled).

$$\operatorname{sampleOk}_\pi(o) = \operatorname{settled}_\pi(o)$$ -/
def sampleOk (p : Policy) (o : Obs) : Bool := settled p o

/-- How a wait ends.

$$\mathrm{Outcome} = \mathrm{settled}(i) \mid \mathrm{unsettled}, \quad i \in \mathbb{N}$$

`settled i`: observation `i` (0-based) was the first settled one inside the budget; `unsettled`: the budget ran out first. -/
inductive Outcome where
  | settled (at_ : Nat)
  | unsettled
  deriving DecidableEq, Repr

/-- The scan behind `wait`: from observation `i`, with `fuel` observations left.

$$\operatorname{scan}(i, f+1) = \begin{cases}\mathrm{unsettled} & T < t(o_i)\\ \mathrm{settled}(i) & t(o_i)\le T \wedge \operatorname{settled}(o_i)\\ \operatorname{scan}(i+1, f) & \text{otherwise}\end{cases}\qquad \operatorname{scan}(i,0) = \mathrm{unsettled}$$ -/
def scan (p : Policy) (o : Nat → Obs) : Nat → Nat → Outcome
  | _, 0 => .unsettled
  | i, f + 1 =>
    if p.timeoutMs < (o i).t then .unsettled
    else if settled p (o i) then .settled i
    else scan p o (i + 1) f

/-- The wait: the first settled observation inside the time budget, else `unsettled`. One observation per millisecond at
most, so `timeoutMs + 1` observations cover the budget.

$$\operatorname{wait}_\pi(o) = \operatorname{scan}_\pi(o)(0, T + 1)$$ -/
def wait (p : Policy) (o : Nat → Obs) : Outcome := scan p o 0 (p.timeoutMs + 1)

/-- The cell report: three outcomes, no silent one.

$$\mathrm{Report} = \mathrm{pass} \mid \mathrm{fail} \mid \mathrm{unsettled}$$ -/
inductive Report where
  | pass
  | fail
  | unsettled
  deriving DecidableEq, Repr

/-- The report of a cell from the two arms' wait outcomes and whether the values they gave are equal.

$$\operatorname{report}(a, b, e) = \begin{cases}\mathrm{pass} & a = \mathrm{settled}(\cdot) \wedge b = \mathrm{settled}(\cdot) \wedge e\\ \mathrm{fail} & a = \mathrm{settled}(\cdot) \wedge b = \mathrm{settled}(\cdot) \wedge \neg e\\ \mathrm{unsettled} & \text{otherwise}\end{cases}$$ -/
def report : Outcome → Outcome → Bool → Report
  | .settled _, .settled _, true => .pass
  | .settled _, .settled _, false => .fail
  | _, _, _ => .unsettled

-- ---------------------------------------------------------------------------------------------------------------
-- the wait is sound and bounded
-- ---------------------------------------------------------------------------------------------------------------

/-- The scan answers `settled k` only for a settled observation inside the budget.

$$\operatorname{scan}(i, f) = \mathrm{settled}(k) \Rightarrow \operatorname{settled}_\pi(o_k) \wedge t(o_k) \le T$$ -/
theorem scan_sound (p : Policy) (o : Nat → Obs) :
    ∀ f i k, scan p o i f = .settled k → settled p (o k) = true ∧ (o k).t ≤ p.timeoutMs := by
  intro f
  induction f with
  | zero => intro i k h; simp [scan] at h
  | succ f ih =>
    intro i k h
    simp only [scan] at h
    by_cases h1 : p.timeoutMs < (o i).t
    · simp [h1] at h
    · by_cases h2 : settled p (o i) = true
      · simp [h1, h2] at h
        subst h
        exact ⟨h2, by omega⟩
      · simp [h1, h2] at h
        exact ih (i + 1) k h

/-- A settled answer is a settled observation inside the budget.

$$\forall \pi\, o\, k,\quad \operatorname{wait}_\pi(o) = \mathrm{settled}(k) \;\Longrightarrow\; \operatorname{settled}_\pi(o_k) \wedge t(o_k) \le T$$

The wait never reports a settled sample it did not see, and never one after the timeout. -/
theorem wait_sound (p : Policy) (o : Nat → Obs) (k : Nat) (h : wait p o = .settled k) :
    settled p (o k) = true ∧ (o k).t ≤ p.timeoutMs :=
  scan_sound p o _ _ _ h

/-- A scan over observations none of which is settled is `unsettled`.

$$(\forall i,\ \neg\operatorname{settled}_\pi(o_i)) \Rightarrow \operatorname{scan}(i, f) = \mathrm{unsettled}$$ -/
theorem scan_unsettled_of_never (p : Policy) (o : Nat → Obs) (never : ∀ i, settled p (o i) = false) :
    ∀ f i, scan p o i f = .unsettled := by
  intro f
  induction f with
  | zero => intro i; simp [scan]
  | succ f ih =>
    intro i
    simp only [scan]
    by_cases h1 : p.timeoutMs < (o i).t
    · simp [h1]
    · simp [h1, never i]
      exact ih (i + 1)

/-- A page that never settles ends the wait as `unsettled` (the timeout is the bound; there is no silent success).

$$\left(\forall i,\ \neg\operatorname{settled}_\pi(o_i)\right) \Longrightarrow \operatorname{wait}_\pi(o) = \mathrm{unsettled}$$ -/
theorem wait_unsettled_of_never (p : Policy) (o : Nat → Obs) (never : ∀ i, settled p (o i) = false) :
    wait p o = .unsettled :=
  scan_unsettled_of_never p o never _ _

/-- A scan with enough fuel that reaches a settled observation inside the budget (time non-decreasing) finds one no later.

$$i \le j < i + f \wedge \operatorname{settled}_\pi(o_j) \wedge t(o_j) \le T \Rightarrow \exists k,\ \operatorname{scan}(i, f) = \mathrm{settled}(k) \wedge i \le k \le j$$ -/
theorem scan_complete (p : Policy) (o : Nat → Obs) (tmono : ∀ i, (o i).t ≤ (o (i + 1)).t) :
    ∀ f i j, i ≤ j → j < i + f → settled p (o j) = true → (o j).t ≤ p.timeoutMs →
      ∃ k, scan p o i f = .settled k ∧ i ≤ k ∧ k ≤ j := by
  intro f
  induction f with
  | zero => intro i j _ hj; omega
  | succ f ih =>
    intro i j hij hjf hs ht
    simp only [scan]
    have hti : (o i).t ≤ (o j).t := by
      have : ∀ d, (o i).t ≤ (o (i + d)).t := by
        intro d
        induction d with
        | zero => exact Nat.le_refl _
        | succ d ihd => exact Nat.le_trans ihd (tmono (i + d))
      have h := this (j - i)
      rwa [show i + (j - i) = j by omega] at h
    have h1 : ¬ p.timeoutMs < (o i).t := by omega
    by_cases h2 : settled p (o i) = true
    · exact ⟨i, by simp [h1, h2], Nat.le_refl _, hij⟩
    · by_cases hji : j = i
      · subst hji; exact absurd hs h2
      · obtain ⟨k, hk, hk1, hk2⟩ := ih (i + 1) j (by omega) (by omega) hs ht
        exact ⟨k, by simp [h1, h2, hk], by omega, hk2⟩

/-- If time is non-decreasing and some observation `j` is settled inside the budget, the wait finds a settled observation
no later than `j`: a page that settles in time is not reported `unsettled`.

$$\left(\forall i,\ t(o_i)\le t(o_{i+1})\right) \wedge \operatorname{settled}_\pi(o_j) \wedge t(o_j)\le T \wedge j \le T \;\Longrightarrow\; \exists k\le j,\ \operatorname{wait}_\pi(o) = \mathrm{settled}(k)$$

(The bound `j ≤ T` says one observation per millisecond at most: the scan covers `T + 1` of them.) -/
theorem wait_complete (p : Policy) (o : Nat → Obs) (tmono : ∀ i, (o i).t ≤ (o (i + 1)).t) (j : Nat)
    (hj : j ≤ p.timeoutMs) (hs : settled p (o j) = true) (ht : (o j).t ≤ p.timeoutMs) :
    ∃ k, wait p o = .settled k ∧ k ≤ j := by
  obtain ⟨k, hk, _, hk2⟩ := scan_complete p o tmono (p.timeoutMs + 1) 0 j (by omega) (by omega) hs ht
  exact ⟨k, hk, hk2⟩

-- ---------------------------------------------------------------------------------------------------------------
-- the report has no silent outcome
-- ---------------------------------------------------------------------------------------------------------------

/-- An unsettled arm never gives a pass.

$$a = \mathrm{unsettled} \,\vee\, b = \mathrm{unsettled} \;\Longrightarrow\; \operatorname{report}(a, b, e) \ne \mathrm{pass}$$ -/
theorem unsettled_never_pass (a b : Outcome) (e : Bool) (h : a = .unsettled ∨ b = .unsettled) :
    report a b e ≠ .pass := by
  rcases a with _ | _ <;> rcases b with _ | _ <;> cases e <;> simp [report] at h ⊢

/-- An unsettled arm never gives a fail either: the report says `unsettled`.

$$a = \mathrm{unsettled} \,\vee\, b = \mathrm{unsettled} \;\Longrightarrow\; \operatorname{report}(a, b, e) = \mathrm{unsettled}$$ -/
theorem unsettled_never_fail (a b : Outcome) (e : Bool) (h : a = .unsettled ∨ b = .unsettled) :
    report a b e = .unsettled := by
  rcases a with _ | _ <;> rcases b with _ | _ <;> cases e <;> simp [report] at h ⊢

/-- A pass or fail needs both arms to have settled.

$$\operatorname{report}(a, b, e) \ne \mathrm{unsettled} \;\Longrightarrow\; \exists i\, j,\ a = \mathrm{settled}(i) \wedge b = \mathrm{settled}(j)$$ -/
theorem report_decided_settled (a b : Outcome) (e : Bool) (h : report a b e ≠ .unsettled) :
    ∃ i j, a = .settled i ∧ b = .settled j := by
  rcases a with i | _ <;> rcases b with j | _ <;> cases e <;> simp [report] at h ⊢

/-- When both arms settled, the report is the comparison and nothing else.

$$\operatorname{report}(\mathrm{settled}(i), \mathrm{settled}(j), e) = \begin{cases}\mathrm{pass} & e\\ \mathrm{fail} & \neg e\end{cases}$$ -/
theorem report_settled (i j : Nat) (e : Bool) :
    report (.settled i) (.settled j) e = (if e then .pass else .fail) := by
  cases e <;> rfl

-- ---------------------------------------------------------------------------------------------------------------
-- a probe on a node that is not rendered has no verdict (fix-commission: inner/rows margin-inline at pain-1440 #0)
-- ---------------------------------------------------------------------------------------------------------------

/-- A node counts as rendered when no element on its ancestor chain (itself included) is flagged by the caller as unrendered.
The flags are an INPUT: this module proves what a flagged probe means (no verdict), not when a flag is right. The gate supplies
no flag today. Run 39071577161 suggested flagging a node under a `content-visibility` skip (its `inner/rows` auto margin), but
premise-tests (run 39076735134) refuted the premise: `getComputedStyle` returns the resolved length (150px) there on Chromium and
WebKit, so a skip is no reason to drop a probe. A flag needs its own tested premise (for example no layout box at all).

$$\operatorname{rendered}(s_1,\dots,s_n) \iff \forall i,\ s_i = \bot$$

where `s_i` says that the caller flagged ancestor `i` as unrendered. -/
def rendered (skips : List Bool) : Bool := !skips.any id

/-- The classification of one probe in one arm.

$$\mathrm{Verdict} = \mathrm{notRendered} \mid \mathrm{unsettled} \mid \mathrm{ok}$$ -/
inductive Verdict where
  | notRendered
  | unsettled
  | ok
  deriving DecidableEq, Repr

/-- `sampleOk` extended with rendering: a probe the caller flagged as unrendered is `notRendered`, whatever
its observation says; otherwise `ok` exactly when `sampleOk` holds, else `unsettled`.

$$\operatorname{classify}_\pi(r, o) = \begin{cases}\mathrm{notRendered} & \neg r\\ \mathrm{ok} & r \wedge \operatorname{sampleOk}_\pi(o)\\ \mathrm{unsettled} & r \wedge \neg\operatorname{sampleOk}_\pi(o)\end{cases}$$ -/
def classify (p : Policy) (r : Bool) (o : Obs) : Verdict :=
  if r then (if sampleOk p o then .ok else .unsettled) else .notRendered

/-- The report of a probe cell, four outcomes and no silent one.

$$\mathrm{Cell} = \mathrm{pass} \mid \mathrm{fail} \mid \mathrm{unsettled} \mid \mathrm{notRendered}$$ -/
inductive Cell where
  | pass
  | fail
  | unsettled
  | notRendered
  deriving DecidableEq, Repr

/-- The report of a probe from the two arms' rendering, their wait outcomes and whether the values are equal. A node that
is not rendered in either arm gives `notRendered` (before anything else); otherwise the cell is `report`.

$$\operatorname{cell}(r_a, r_b, a, b, e) = \begin{cases}\mathrm{notRendered} & \neg r_a \vee \neg r_b\\ \operatorname{report}(a,b,e) & r_a \wedge r_b\end{cases}$$ -/
def cell (ra rb : Bool) (a b : Outcome) (e : Bool) : Cell :=
  if ra && rb then
    match report a b e with
    | .pass => .pass
    | .fail => .fail
    | .unsettled => .unsettled
  else .notRendered

/-- Whether a cell counts as a pass for an exit decision (`Fw.Gate.Exit` imports `Cell` and this): only `pass` does.

$$\operatorname{passes}(c) = \top \iff c = \mathrm{pass}$$ -/
def Cell.passes : Cell → Bool
  | .pass => true
  | _ => false

/-- `unsettled` and `notRendered` (like `fail`) are never a passing cell.

$$c \in \{\mathrm{fail}, \mathrm{unsettled}, \mathrm{notRendered}\} \;\Longrightarrow\; \operatorname{passes}(c) = \bot$$ -/
theorem Cell.passes_iff (c : Cell) : c.passes = true ↔ c = .pass := by
  cases c <;> simp [Cell.passes]

/-- A probe on a node under a flagged ancestor is `notRendered`, whatever the observation.

$$(\exists i,\ s_i = \top) \;\Longrightarrow\; \operatorname{classify}_\pi(\operatorname{rendered}(s), o) = \mathrm{notRendered}$$ -/
theorem skipped_classified_notRendered (p : Policy) (skips : List Bool) (o : Obs) (h : true ∈ skips) :
    classify p (rendered skips) o = .notRendered := by
  have : (skips.any id) = true := List.any_eq_true.mpr ⟨true, h, rfl⟩
  simp [classify, rendered, this]

/-- For a rendered node the classification is exactly `sampleOk`.

$$\operatorname{classify}_\pi(\top, o) = \mathrm{ok} \iff \operatorname{sampleOk}_\pi(o)$$ -/
theorem classify_rendered_ok (p : Policy) (o : Obs) : classify p true o = .ok ↔ sampleOk p o = true := by
  unfold classify
  by_cases h : sampleOk p o = true <;> simp [h]

/-- A node that is not rendered in either arm never gives a pass.

$$\neg r_a \vee \neg r_b \;\Longrightarrow\; \operatorname{cell}(r_a, r_b, a, b, e) \ne \mathrm{pass}$$ -/
theorem notRendered_never_pass (ra rb : Bool) (a b : Outcome) (e : Bool) (h : ra = false ∨ rb = false) :
    cell ra rb a b e ≠ .pass := by
  rcases h with h | h <;> simp [cell, h]

/-- It never gives a fail either: the cell says `notRendered`.

$$\neg r_a \vee \neg r_b \;\Longrightarrow\; \operatorname{cell}(r_a, r_b, a, b, e) = \mathrm{notRendered}$$ -/
theorem notRendered_never_fail (ra rb : Bool) (a b : Outcome) (e : Bool) (h : ra = false ∨ rb = false) :
    cell ra rb a b e = .notRendered := by
  rcases h with h | h <;> simp [cell, h]

/-- When both nodes are rendered, the cell is the settle report and nothing else.

$$\operatorname{cell}(\top, \top, a, b, e) = \operatorname{report}(a, b, e)$$ (the three outcomes renamed) -/
theorem cell_rendered (a b : Outcome) (e : Bool) :
    (cell true true a b e = .pass ↔ report a b e = .pass) ∧ (cell true true a b e = .fail ↔ report a b e = .fail)
    ∧ (cell true true a b e = .unsettled ↔ report a b e = .unsettled) := by
  cases h : report a b e <;> simp [cell, h]

/-- A pass or fail needs both nodes rendered and both arms settled.

$$\operatorname{cell}(r_a, r_b, a, b, e) \in \{\mathrm{pass}, \mathrm{fail}\} \;\Longrightarrow\; r_a \wedge r_b \wedge \exists i\, j,\ a = \mathrm{settled}(i) \wedge b = \mathrm{settled}(j)$$ -/
theorem cell_decided (ra rb : Bool) (a b : Outcome) (e : Bool) (h : cell ra rb a b e = .pass ∨ cell ra rb a b e = .fail) :
    ra = true ∧ rb = true ∧ ∃ i j, a = .settled i ∧ b = .settled j := by
  rcases ra with _ | _ <;> rcases rb with _ | _ <;> simp [cell] at h ⊢
  rcases a with i | _ <;> rcases b with j | _ <;> cases e <;> simp [report] at h ⊢

-- ---------------------------------------------------------------------------------------------------------------
-- the model: a settled sample does not depend on when it was taken
-- ---------------------------------------------------------------------------------------------------------------

/-- The monotone-settling model of one page arm whose inputs do not change (no resize, no pointer move, no new
animation): a trajectory of observations `obs n` and of the probed properties `props n` (any type `α`) at frame `n`.

$$\begin{aligned}
&\mathit{run}(o_{n+1}) \le \mathit{run}(o_n) \qquad \mathit{fr}(o_{n+1}) = \mathit{fr}(o_n) + 1 \qquad \mathit{hov}(o_{n+1}) = \mathit{hov}(o_n)\\
&P_{n+1} = P_n \Rightarrow \mathit{st}(o_{n+1}) = \mathit{st}(o_n) + 1 \qquad \operatorname{settled}_\pi(o_n) \Rightarrow P_{n+1} = P_n
\end{aligned}$$

The last line is the one empirical premise ("a settled page does not repaint the probed properties"); the others say
animations only finish, frames only count up, and stable frames count the unchanged ones. -/
structure Traj (p : Policy) (α : Type) where
  obs : Nat → Obs
  props : Nat → α
  running_mono : ∀ n, (obs (n + 1)).running ≤ (obs n).running
  frames_succ : ∀ n, (obs (n + 1)).frames = (obs n).frames + 1
  hover_const : ∀ n, (obs (n + 1)).hoverInside = (obs n).hoverInside
  stable_succ : ∀ n, props (n + 1) = props n → (obs (n + 1)).stable = (obs n).stable + 1
  quiet : ∀ n, settled p (obs n) = true → props (n + 1) = props n

/-- One step of a trajectory from a settled observation stays settled and keeps the properties.

$$\operatorname{settled}_\pi(o_n) \Rightarrow \operatorname{settled}_\pi(o_{n+1}) \wedge P_{n+1} = P_n$$ -/
theorem Traj.settled_succ {p : Policy} {α : Type} (T : Traj p α) (n : Nat) (h : settled p (T.obs n) = true) :
    settled p (T.obs (n + 1)) = true ∧ T.props (n + 1) = T.props n := by
  have hq := T.quiet n h
  have hr := T.running_mono n
  have hf := T.frames_succ n
  have hh := T.hover_const n
  have hs := T.stable_succ n hq
  refine ⟨?_, hq⟩
  simp only [settled, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq, Bool.not_eq_true'] at h ⊢
  obtain ⟨⟨⟨h1, h2⟩, h3⟩, h4⟩ := h
  refine ⟨⟨⟨by omega, by omega⟩, by omega⟩, by rw [hh]; exact h4⟩

/-- Settling is absorbing: once settled, every later frame is settled and shows the same properties.

$$\operatorname{settled}_\pi(o_i) \;\Longrightarrow\; \forall k,\ \operatorname{settled}_\pi(o_{i+k}) \wedge P_{i+k} = P_i$$ -/
theorem Traj.settled_after {p : Policy} {α : Type} (T : Traj p α) (i : Nat) (h : settled p (T.obs i) = true) :
    ∀ k, settled p (T.obs (i + k)) = true ∧ T.props (i + k) = T.props i := by
  intro k
  induction k with
  | zero => exact ⟨h, rfl⟩
  | succ k ih =>
    obtain ⟨h1, h2⟩ := T.settled_succ (i + k) ih.1
    exact ⟨h1, h2.trans ih.2⟩

/-- A sample that settled does not depend on the delay at which it was taken: two settled samples of the same arm give the
same probed properties, so the comparison with the other arm does not depend on when each arm was sampled.

$$\operatorname{settled}_\pi(o_i) \wedge \operatorname{settled}_\pi(o_j) \;\Longrightarrow\; P_i = P_j$$ -/
theorem sample_delay_invariant {p : Policy} {α : Type} (T : Traj p α) (i j : Nat)
    (hi : settled p (T.obs i) = true) (hj : settled p (T.obs j) = true) : T.props i = T.props j := by
  rcases Nat.le_total i j with hij | hji
  · obtain ⟨_, h2⟩ := T.settled_after i hi (j - i)
    rw [show i + (j - i) = j by omega] at h2
    exact h2.symm
  · obtain ⟨_, h2⟩ := T.settled_after j hj (i - j)
    rw [show j + (i - j) = i by omega] at h2
    exact h2

-- ---------------------------------------------------------------------------------------------------------------
-- the three misreads of run 39067170911 are unsettled
-- ---------------------------------------------------------------------------------------------------------------

/-- `pain.notes`: the original is one layout behind until two real frames have passed since the resize (a
`ResizeObserver` notification, then the `requestAnimationFrame` callback it schedules). Fewer than `minFrames` real
frames is unsettled; so is a page that never delivers a frame.

$$\mathit{fr}(o) < m_f \;\Longrightarrow\; \neg\operatorname{settled}_\pi(o)\qquad\text{and}\qquad \left(\forall i,\ \mathit{fr}(o_i) < m_f\right) \Longrightarrow \operatorname{wait}_\pi(o) = \mathrm{unsettled}$$ -/
theorem pain_notes_unsettled (p : Policy) (o : Obs) (h : o.frames < p.minFrames) : settled p o = false := by
  simp only [settled]
  have : ¬ p.minFrames ≤ o.frames := by omega
  simp [this]

/-- `pain.notes`, no frame at all: a page whose frames never reach `minFrames` ends the wait as `unsettled`.

$$\left(\forall i,\ \mathit{fr}(o_i) < m_f\right) \Longrightarrow \operatorname{wait}_\pi(o) = \mathrm{unsettled}$$ -/
theorem pain_notes_wait_unsettled (p : Policy) (o : Nat → Obs) (h : ∀ i, (o i).frames < p.minFrames) :
    wait p o = .unsettled :=
  wait_unsettled_of_never p o (fun i => pain_notes_unsettled p (o i) (h i))

/-- `hero.orbit`: `z-index` is `1 +` the `pointerenter` events a pointer inside a hover-reactive target caused. While the
pointer is inside such a target the observation is unsettled, whatever else holds.

$$\mathit{hov}(o) \;\Longrightarrow\; \neg\operatorname{settled}_\pi(o)$$ -/
theorem hero_orbit_unsettled (p : Policy) (o : Obs) (h : o.hoverInside = true) : settled p o = false := by
  simp [settled, h]

/-- Parking the pointer outside every probed hover target.

$$\operatorname{park}(o) = o\ \text{with}\ \mathit{hov} := 0$$ -/
def park (o : Obs) : Obs := { o with hoverInside := false }

/-- After parking, hover is no obstacle: the parked observation is settled exactly when the other three conditions hold.

$$\operatorname{settled}_\pi(\operatorname{park}(o)) \iff \mathit{run}(o) = 0 \wedge m_f \le \mathit{fr}(o) \wedge m_s \le \mathit{st}(o)$$ -/
theorem park_settled_iff (p : Policy) (o : Obs) :
    settled p (park o) = true ↔ (o.running = 0 ∧ p.minFrames ≤ o.frames ∧ p.minStable ≤ o.stable) := by
  unfold settled park
  by_cases h1 : o.running = 0 <;> by_cases h2 : p.minFrames ≤ o.frames <;> by_cases h3 : p.minStable ≤ o.stable <;>
    simp [h1, h2, h3]

/-- A finite animation or transition under the probed subtree: its duration and elapsed time (ms).

$$a = (d, e) \in \mathbb{N}^2,\quad \operatorname{running}(a) \iff e < d$$ -/
structure Anim where
  dur : Nat
  elapsed : Nat
  deriving DecidableEq, Repr

/-- The number of running animations.

$$\operatorname{runCount}(A) = \left|\{a \in A \mid \mathit{elapsed}(a) < \mathit{dur}(a)\}\right|$$ -/
def runCount (as : List Anim) : Nat := (as.filter (fun a => decide (a.elapsed < a.dur))).length

/-- `overlays.signup`: the dialog enter animation (0.4 s) is running at any elapsed time below its duration, so a sample taken
there (scale 0.9977 at the WebKit touch probe) has `running ≥ 1` and is unsettled.

$$e < d \wedge a = (d, e) \wedge a \in A \;\Longrightarrow\; \operatorname{runCount}(A) \ge 1 \;\Longrightarrow\; \neg\operatorname{settled}_\pi\!\left(\mathit{run} := \operatorname{runCount}(A), \ldots\right)$$ -/
theorem signup_unsettled (p : Policy) (as : List Anim) (a : Anim) (ha : a ∈ as) (he : a.elapsed < a.dur)
    (frames stable t : Nat) (hov : Bool) :
    settled p { running := runCount as, frames := frames, stable := stable, hoverInside := hov, t := t } = false := by
  have hpos : 0 < runCount as := by
    unfold runCount
    apply List.length_pos_of_mem (a := a)
    simp [List.mem_filter, ha, he]
  simp only [settled]
  have : ¬ runCount as = 0 := by omega
  simp [this]

/-- The dialog enter animation of the original (duration 400 ms) is finished only from 400 ms on.

$$\operatorname{runCount}([(400, e)]) = 0 \iff 400 \le e$$ -/
theorem signup_enter_finished (e : Nat) : runCount [{ dur := 400, elapsed := e }] = 0 ↔ 400 ≤ e := by
  unfold runCount
  by_cases h : e < 400 <;> simp [h] <;> omega

-- ---------------------------------------------------------------------------------------------------------------
-- values that move without a CSS animation: the quiet condition
-- ---------------------------------------------------------------------------------------------------------------

/-- A frame is quiet when the probed values (boxes, numbers of transforms and opacity) have the same length as the frame
before and each moved by at most `eps` (millionths).

$$\operatorname{quiet}_\varepsilon(u, v) \iff |u| = |v| \;\wedge\; \forall i,\ |u_i - v_i| \le \varepsilon$$

`getAnimations()` does not list a `requestAnimationFrame`-driven value (a per-frame lerp); this does. -/
def quiet (eps : Nat) (u v : List Int) : Bool :=
  u.length == v.length && (List.zipWith (fun a b => decide ((a - b).natAbs ≤ eps)) u v).all id

/-- The run of quiet frames after one more frame.

$$\operatorname{next}_\varepsilon(s, u, v) = \begin{cases} s + 1 & \operatorname{quiet}_\varepsilon(u, v)\\ 0 & \text{otherwise}\end{cases}$$ -/
def nextStable (eps : Nat) (s : Nat) (u v : List Int) : Nat := if quiet eps u v then s + 1 else 0

/-- A frame is quiet against itself.

$$\operatorname{quiet}_\varepsilon(u, u)$$ -/
theorem quiet_refl (eps : Nat) (u : List Int) : quiet eps u u = true := by
  induction u with
  | nil => simp [quiet]
  | cons x xs ih =>
    simp only [quiet, List.length_cons, beq_self_eq_true, Bool.true_and, List.zipWith_cons_cons, List.all_cons] at ih ⊢
    simp

/-- A change in the number of probed values is never quiet.

$$|u| \ne |v| \;\Longrightarrow\; \neg\operatorname{quiet}_\varepsilon(u, v)$$ -/
theorem quiet_length (eps : Nat) (u v : List Int) (h : u.length ≠ v.length) : quiet eps u v = false := by
  simp [quiet, h]

/-- A value that moved by more than `eps` between two frames ends the quiet run.

$$\varepsilon < |x - y| \;\Longrightarrow\; \operatorname{quiet}_\varepsilon([x], [y]) = \bot \;\wedge\; \operatorname{next}_\varepsilon(s, [x], [y]) = 0$$ -/
theorem moving_not_quiet (eps : Nat) (s : Nat) (x y : Int) (h : eps < (x - y).natAbs) :
    quiet eps [x] [y] = false ∧ nextStable eps s [x] [y] = 0 := by
  have : quiet eps [x] [y] = false := by
    simp [quiet]; omega
  exact ⟨this, by simp [nextStable, this]⟩

/-- `people.card` and `people.deck` (WebKit): a value still moving frame to frame (a per-frame lerp read at a fixed wall
time) resets the quiet run, so the observation is unsettled whenever the policy asks for at least one quiet frame.

$$\varepsilon < |x - y| \wedge 1 \le m_s \;\Longrightarrow\; \neg\operatorname{settled}_\pi\!\left(\mathit{st} := \operatorname{next}_\varepsilon(s, [x], [y]), \ldots\right)$$ -/
theorem lerp_moving_unsettled (p : Policy) (s : Nat) (x y : Int) (h : p.eps < (x - y).natAbs) (hm : 1 ≤ p.minStable)
    (running frames t : Nat) (hov : Bool) :
    settled p { running := running, frames := frames, stable := nextStable p.eps s [x] [y], hoverInside := hov, t := t } = false := by
  obtain ⟨_, h2⟩ := moving_not_quiet p.eps s x y h
  simp only [settled]
  rw [h2]
  have : ¬ p.minStable ≤ 0 := by omega
  simp [this]

/-- A per-frame lerp toward a target `T` with rate `a/b` (scaled to integers, `0 < a`): each step covers the fraction
`a/b` of the distance left, so `b (x_{n+1} - x_n) = a (T - x_n)`.

$$b\,(x_{n+1} - x_n) = a\,(T - x_n),\qquad 0 < a$$ -/
structure Lerp where
  x : Nat → Int
  target : Int
  a : Nat
  b : Nat
  pos : 0 < a
  step : ∀ n, (b : Int) * (x (n + 1) - x n) = (a : Int) * (target - x n)

/-- A quiet frame of a lerp is near the target: a step of at most `eps` leaves at most `eps b / a` of distance.

$$|x_{n+1} - x_n| \le \varepsilon \;\Longrightarrow\; a\,|T - x_n| \le \varepsilon\, b$$

So a quiet sample of a lerp is within `eps b / a` of where it ends up, whatever frame it was taken at. -/
theorem Lerp.quiet_near (L : Lerp) (eps n : Nat) (h : (L.x (n + 1) - L.x n).natAbs ≤ eps) :
    L.a * (L.target - L.x n).natAbs ≤ eps * L.b := by
  have h1 := L.step n
  have h2 : (↑L.b * (L.x (n + 1) - L.x n)).natAbs = (↑L.a * (L.target - L.x n)).natAbs := by rw [h1]
  rw [Int.natAbs_mul, Int.natAbs_mul] at h2
  simp only [Int.natAbs_natCast] at h2
  rw [← h2]
  calc L.b * (L.x (n + 1) - L.x n).natAbs ≤ L.b * eps := Nat.mul_le_mul_left _ h
    _ = eps * L.b := Nat.mul_comm _ _

/-- Delay invariance for a lerp: two quiet samples (steps at most `eps`) of the same lerp differ by at most `2 eps b / a`.

$$|x_{i+1} - x_i| \le \varepsilon \wedge |x_{j+1} - x_j| \le \varepsilon \;\Longrightarrow\; a\,|x_i - x_j| \le 2\,\varepsilon\, b$$

With `eps = 0.0001` and a lerp of rate a tenth per frame (`b / a = 10`) the bound is 0.002: inside the gate's 0.5 px
for boxes, above its 0.001 for numbers, so a number-valued lerp that slow needs `eps <= 0.001 a / (2 b)`. -/
theorem Lerp.sample_delay_invariant (L : Lerp) (eps i j : Nat)
    (hi : (L.x (i + 1) - L.x i).natAbs ≤ eps) (hj : (L.x (j + 1) - L.x j).natAbs ≤ eps) :
    L.a * (L.x i - L.x j).natAbs ≤ 2 * (eps * L.b) := by
  have h1 := L.quiet_near eps i hi
  have h2 := L.quiet_near eps j hj
  have h3 : (L.x i - L.x j).natAbs ≤ (L.target - L.x i).natAbs + (L.target - L.x j).natAbs := by omega
  calc L.a * (L.x i - L.x j).natAbs ≤ L.a * ((L.target - L.x i).natAbs + (L.target - L.x j).natAbs) :=
        Nat.mul_le_mul_left _ h3
    _ = L.a * (L.target - L.x i).natAbs + L.a * (L.target - L.x j).natAbs := Nat.mul_add _ _ _
    _ ≤ 2 * (eps * L.b) := by omega

-- ---------------------------------------------------------------------------------------------------------------
-- golden vectors for the TypeScript twin
-- ---------------------------------------------------------------------------------------------------------------

/-- The JSON of an observation (key order as the TypeScript twin writes it).

$$o \mapsto \{\mathit{running}, \mathit{frames}, \mathit{stable}, \mathit{hoverInside}, t\}$$ -/
def obsJson (o : Obs) : Json :=
  Json.mkObj [("running", toJson o.running), ("frames", toJson o.frames), ("stable", toJson o.stable),
    ("hoverInside", toJson o.hoverInside), ("t", toJson o.t)]

/-- The JSON of a policy.

$$\pi \mapsto \{m_f, m_s, \varepsilon, T\}$$ -/
def policyJson (p : Policy) : Json :=
  Json.mkObj [("minFrames", toJson p.minFrames), ("minStable", toJson p.minStable), ("eps", toJson p.eps), ("timeoutMs", toJson p.timeoutMs)]

/-- An outcome as the twin writes it: `"settled@i"` or `"unsettled"`.

$$\mathrm{settled}(i) \mapsto \texttt{settled@}i,\quad \mathrm{unsettled} \mapsto \texttt{unsettled}$$ -/
def outcomeText : Outcome → String
  | .settled i => s!"settled@{i}"
  | .unsettled => "unsettled"

/-- A report as the twin writes it.

$$\mathrm{pass},\mathrm{fail},\mathrm{unsettled} \mapsto \text{their lower-case names}$$ -/
def reportText : Report → String
  | .pass => "pass"
  | .fail => "fail"
  | .unsettled => "unsettled"

/-- A cell as the twin writes it.

$$\mathrm{pass},\mathrm{fail},\mathrm{unsettled},\mathrm{notRendered} \mapsto \text{their names}$$ -/
def cellText : Cell → String
  | .pass => "pass"
  | .fail => "fail"
  | .unsettled => "unsettled"
  | .notRendered => "notRendered"

/-- The observation the wait sees once a finite trace is over: late, so the budget has run out.

$$o_{\mathrm{end}} = (1, 0, 0, \bot, 10^9)$$ -/
def pastEnd : Obs := { running := 1, frames := 0, stable := 0, hoverInside := false, t := 1000000000 }

/-- The wait over a finite trace (what the page returned); beyond its end the budget has run out.

$$\operatorname{waitList}_\pi(\mathit{tr}) = \operatorname{wait}_\pi(i \mapsto \mathit{tr}[i] \text{ or } o_{\mathrm{end}})$$ -/
def waitList (p : Policy) (tr : List Obs) : Outcome := wait p (fun i => tr.getD i pastEnd)

private def ob (running frames stable : Nat) (hov : Bool) (t : Nat) : Obs :=
  { running := running, frames := frames, stable := stable, hoverInside := hov, t := t }

/-- Single observations: (name, observation). Each of the first conditions on its own, then the three misreads.

$$\text{obsCases} = [(n_k, o_k)]_k$$ -/
def obsCases : List (String × Obs) :=
  [ ("all conditions hold", ob 0 2 3 false 100),
    ("exactly at the thresholds", ob 0 2 3 false 0),
    ("an animation runs", ob 1 5 5 false 100),
    ("one frame since the resize", ob 0 1 5 false 100),
    ("no frame at all", ob 0 0 0 false 100),
    ("boxes still changing", ob 0 5 1 false 100),
    ("pointer inside a hover target", ob 0 5 5 true 100),
    ("pain.notes: laid out one resize behind (1 frame)", ob 0 1 1 false 40),
    ("hero.orbit: parked pointer over card 2", ob 0 9 9 true 600),
    ("overlays.signup: dialog enter animation running", ob 1 7 3 false 120),
    ("hero.orbit after parking", park (ob 0 9 9 true 600)) ]

/-- Waits over finite traces: (name, policy, trace).

$$\text{waitCases} = [(n_k, \pi_k, \mathit{tr}_k)]_k$$ -/
def waitCases : List (String × Policy × List Obs) :=
  [ ("settles at the third frame",
      gatePolicy, [ob 1 1 0 false 16, ob 0 2 1 false 33, ob 0 3 3 false 50, ob 0 4 4 false 66]),
    ("settles at once",
      gatePolicy, [ob 0 2 3 false 0, ob 0 3 4 false 16]),
    ("an animation outlasts the budget",
      gatePolicy, [ob 1 1 0 false 16, ob 1 2 0 false 1500, ob 1 3 0 false 2900, ob 0 4 1 false 3100, ob 0 5 2 false 3116]),
    ("settles only after the budget",
      gatePolicy, [ob 0 1 0 false 1000, ob 0 2 3 false 3001, ob 0 3 4 false 3017]),
    ("settles exactly at the budget",
      gatePolicy, [ob 0 1 0 false 1000, ob 0 2 3 false 3000]),
    ("no frame ever (requestAnimationFrame never fires)",
      gatePolicy, [ob 0 0 0 false 250, ob 0 0 0 false 1000, ob 0 0 0 false 3000]),
    ("pointer stays inside a hover target",
      gatePolicy, [ob 0 2 2 true 16, ob 0 3 3 true 33, ob 0 4 4 true 50]),
    ("empty trace", gatePolicy, []),
    ("a stricter policy needs more frames",
      { minFrames := 4, minStable := 2, eps := 100, timeoutMs := 100 }, [ob 0 2 2 false 16, ob 0 3 3 false 33, ob 0 4 4 false 50]) ]

/-- Cell reports: (name, arm a, arm b, equal).

$$\text{reportCases} = [(n_k, a_k, b_k, e_k)]_k$$ -/
def reportCases : List (String × Outcome × Outcome × Bool) :=
  [ ("both settled and equal", .settled 2, .settled 0, true),
    ("both settled and different", .settled 2, .settled 5, false),
    ("original unsettled, values equal", .unsettled, .settled 1, true),
    ("rewrite unsettled, values different", .settled 1, .unsettled, false),
    ("both unsettled", .unsettled, .unsettled, true) ]

/-- Probe cells: (name, arm a rendered, arm b rendered, outcome a, outcome b, equal).

$$\text{cellCases} = [(n_k, r_a, r_b, a_k, b_k, e_k)]_k$$ -/
def cellCases : List (String × Bool × Bool × Outcome × Outcome × Bool) :=
  [ ("both rendered, equal", true, true, .settled 1, .settled 2, true),
    ("both rendered, different", true, true, .settled 1, .settled 2, false),
    ("both rendered, one unsettled", true, true, .unsettled, .settled 2, true),
    ("original flagged unrendered, values different", false, true, .settled 1, .settled 2, false),
    ("rewrite not rendered, values equal", true, false, .settled 1, .settled 2, true),
    ("neither rendered, both unsettled", false, false, .unsettled, .unsettled, false) ]

/-- Ancestor chains: (name, one flag per ancestor, true = it skips its subtree).

$$\text{renderedCases} = [(n_k, s_k)]_k$$ -/
def renderedCases : List (String × List Bool) :=
  [ ("no ancestors", []), ("none skips", [false, false, false]), ("the middle one skips", [false, true, false]),
    ("only the root skips", [true]) ]

/-- Quiet frames: (name, eps, previous values, current values). Values in millionths.

$$\text{quietCases} = [(n_k, \varepsilon_k, u_k, v_k)]_k$$ -/
def quietCases : List (String × Nat × List Int × List Int) :=
  [ ("identical", 100, [1000000, 250000], [1000000, 250000]),
    ("moved exactly eps", 100, [1000000], [1000100]),
    ("moved by more than eps", 100, [1000000], [1000101]),
    ("one of two moved too far", 100, [1000000, 5000], [1000000, 5200]),
    ("a value appeared", 100, [1000000], [1000000, 0]),
    ("negative direction", 100, [-5000], [-5100]),
    ("loose eps", 5000, [0, 0], [4000, -5000]),
    ("no values at all", 100, [], []),
    ("people.deck scale mid lerp", 100, [977000], [979000]) ]

/-- One golden line per case, in the order observation cases, wait cases, quiet cases, report cases.

$$\text{lines} = [\ell_{\mathrm{obs}}(c)]_c \mathbin{+\!\!+} [\ell_{\mathrm{wait}}(c)]_c \mathbin{+\!\!+} [\ell_{\mathrm{report}}(c)]_c$$ -/
def goldenLines : List String :=
  obsCases.map (fun (n, o) =>
    (Json.mkObj [("kind", "settled"), ("name", toJson n), ("policy", policyJson gatePolicy), ("obs", obsJson o),
      ("settled", toJson (settled gatePolicy o))]).compress)
  ++ waitCases.map (fun (n, p, tr) =>
    (Json.mkObj [("kind", "wait"), ("name", toJson n), ("policy", policyJson p), ("trace", Json.arr (tr.map obsJson).toArray),
      ("outcome", toJson (outcomeText (waitList p tr)))]).compress)
  ++ quietCases.map (fun (n, e, u, v) =>
    (Json.mkObj [("kind", "quiet"), ("name", toJson n), ("eps", toJson e), ("prev", toJson u), ("cur", toJson v),
      ("quiet", toJson (quiet e u v)), ("next", toJson (nextStable e 2 u v))]).compress)
  ++ renderedCases.map (fun (n, sk) =>
    (Json.mkObj [("kind", "rendered"), ("name", toJson n), ("skips", toJson sk), ("rendered", toJson (rendered sk))]).compress)
  ++ cellCases.map (fun (n, ra, rb, a, b, e) =>
    (Json.mkObj [("kind", "cell"), ("name", toJson n), ("renderedA", toJson ra), ("renderedB", toJson rb),
      ("a", toJson (outcomeText a)), ("b", toJson (outcomeText b)), ("equal", toJson e),
      ("cell", toJson (cellText (cell ra rb a b e)))]).compress)
  ++ reportCases.map (fun (n, a, b, e) =>
    (Json.mkObj [("kind", "report"), ("name", toJson n), ("a", toJson (outcomeText a)), ("b", toJson (outcomeText b)),
      ("equal", toJson e), ("report", toJson (reportText (report a b e)))]).compress)

/-- The exact bytes of `packages/contracts/golden/gate/settle.jsonl`: the lines, each newline-terminated.

$$\text{goldenText} = \mathbin{+\!\!+}_{\ell \in \text{goldenLines}} (\ell \mathbin{+\!\!+} \texttt{newline})$$ -/
def goldenText : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

/-- The value after `flag` in an argument list.

$$\operatorname{argAfter}([\dots, f, v, \dots], f) = \mathrm{some}(v)$$ -/
def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

/-- Command-line driver: print the golden text, or with `--check <file>` exit 0 when the file holds exactly these bytes and 1 otherwise.

$$\operatorname{run}(\mathit{args}) = 0 \iff \text{no mismatch}$$ -/
def run (args : List String) : IO UInt32 := do
  match argAfter args "--check" with
  | some path =>
    let cur ← IO.FS.readBinFile path
    if cur.data == goldenText.toUTF8.data then
      IO.eprintln s!"settle golden: {path} is up to date ({goldenLines.length} lines)"
      return 0
    IO.eprintln s!"settle golden: {path} differs from the generated bytes"
    return 1
  | none =>
    IO.print goldenText
    return 0

-- sanity of the golden table (the proofs above are the statement; these pin the vectors)
#guard settled gatePolicy (ob 0 2 3 false 100) == true
#guard settled gatePolicy (ob 0 1 5 false 100) == false
#guard waitList gatePolicy [ob 1 1 0 false 16, ob 0 2 1 false 33, ob 0 3 3 false 50] == .settled 2
#guard waitList gatePolicy [ob 0 1 0 false 1000, ob 0 2 3 false 3001, ob 0 3 4 false 3017] == .unsettled
#guard waitList gatePolicy [] == .unsettled
#guard cell false true (.settled 1) (.settled 2) false == .notRendered
#guard cell true true (.settled 1) (.settled 2) false == .fail
#guard rendered [false, true, false] == false

end Fw.Gate.Settle
