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
frames whose probed boxes did not change; `hoverInside`: the pointer is inside a hover-reactive probed target (always false in an environment that cannot hover: `:hover` can match there after a touch, but no hover rule applies);
`t`: milliseconds since the wait began. -/
structure Obs where
  running : Nat
  frames : Nat
  stable : Nat
  hoverInside : Bool
  t : Nat
  deriving DecidableEq, Repr

/-- The wait policy.

$$\pi = (m_f, m_s, \varepsilon, T, F) \in \mathbb{N}^5$$

`minFrames`: real frames required after the last resize; `minStable`: quiet frames required in a row; `eps`: the quiet
threshold in millionths of a unit (px, or a unitless value such as a scale); `timeoutMs`: the time bound of the wait;
`maxFrames`: the frame budget of the wait (gate-shard-balance): an observation after more than `F` real frames ends the
wait as `unsettled`, as one after more than `T` milliseconds does. -/
structure Policy where
  minFrames : Nat
  minStable : Nat
  eps : Nat
  timeoutMs : Nat
  maxFrames : Nat
  deriving DecidableEq, Repr

/-- The policy the gate uses: two frames after each resize (a `ResizeObserver` notification, then the callback it
schedules), three quiet frames in a row, quiet meaning every probed value moved by at most 0.0001, 30000 ms (the CI WebKit paints this page at 0.3 to 1.7 frames per second, MEASURED in run 39078493093, so three frames can take 10 s),
and at most 60 real frames. The frame budget is gate-shard-balance's fix of run 39101532038 (MEASURED from its 7 job logs):
every wait that settled did so within 25 real frames (Chromium at most 25, WebKit at most 20), and every wait that did not
settle ran to the 30 s timeout after at least 78 frames. A 60-frame budget gives a wait that settles within 60 frames the
same outcome (`wait_budget_keeps`) and a page that never settles the same `unsettled` (`wait_unsettled_of_never`); an
unsettled wait on Chromium (60 frames per second) then ends after about 1 s instead of 30 s.

$$\pi_{\mathrm{gate}} = (2, 3, 100, 30000, 60)$$ -/
def gatePolicy : Policy := { minFrames := 2, minStable := 3, eps := 100, timeoutMs := 30000, maxFrames := 60 }

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

`settled i`: observation `i` (0-based) was the first settled one inside the budget; `unsettled`: the budget (time or
frames) ran out first. -/
inductive Outcome where
  | settled (at_ : Nat)
  | unsettled
  deriving DecidableEq, Repr

/-- The budget is spent at an observation: more than `T` milliseconds or more than `F` real frames since the wait began.

$$\operatorname{spent}_\pi(o) \iff T < t(o) \;\vee\; F < \mathit{fr}(o)$$ -/
def spent (p : Policy) (o : Obs) : Bool := decide (p.timeoutMs < o.t) || decide (p.maxFrames < o.frames)

/-- The scan behind `wait`: from observation `i`, with `fuel` observations left.

$$\operatorname{scan}(i, f+1) = \begin{cases}\mathrm{unsettled} & \operatorname{spent}_\pi(o_i)\\ \mathrm{settled}(i) & \neg\operatorname{spent}_\pi(o_i) \wedge \operatorname{settled}_\pi(o_i)\\ \operatorname{scan}(i+1, f) & \text{otherwise}\end{cases}\qquad \operatorname{scan}(i,0) = \mathrm{unsettled}$$ -/
def scan (p : Policy) (o : Nat → Obs) : Nat → Nat → Outcome
  | _, 0 => .unsettled
  | i, f + 1 =>
    if spent p (o i) then .unsettled
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

/-- The budget is not spent exactly when both the time and the frame count are inside it.

$$\forall \pi\, o,\quad \neg\operatorname{spent}_\pi(o) \iff t(o) \le T \wedge \mathit{fr}(o) \le F$$ -/
theorem spent_false_iff (p : Policy) (o : Obs) :
    spent p o = false ↔ o.t ≤ p.timeoutMs ∧ o.frames ≤ p.maxFrames := by
  simp only [spent, Bool.or_eq_false_iff, decide_eq_false_iff_not, Nat.not_lt]

/-- The scan answers `settled k` only for a settled observation inside the budget, at or after where it started.

$$\forall f\, i\, k,\quad \operatorname{scan}(i, f) = \mathrm{settled}(k) \Rightarrow \operatorname{settled}_\pi(o_k) \wedge t(o_k) \le T \wedge \mathit{fr}(o_k) \le F \wedge i \le k$$ -/
theorem scan_sound (p : Policy) (o : Nat → Obs) :
    ∀ f i k, scan p o i f = .settled k →
      settled p (o k) = true ∧ (o k).t ≤ p.timeoutMs ∧ (o k).frames ≤ p.maxFrames ∧ i ≤ k := by
  intro f
  induction f with
  | zero => intro i k h; simp [scan] at h
  | succ f ih =>
    intro i k h
    simp only [scan] at h
    cases h1 : spent p (o i)
    · have hb := (spent_false_iff p (o i)).1 h1
      by_cases h2 : settled p (o i) = true
      · simp [h1, h2] at h
        subst h
        exact ⟨h2, hb.1, hb.2, Nat.le_refl _⟩
      · simp [h1, h2] at h
        obtain ⟨a, b, c, d⟩ := ih (i + 1) k h
        exact ⟨a, b, c, by omega⟩
    · simp [h1] at h

/-- A settled answer is a settled observation inside the budget.

$$\forall \pi\, o\, k,\quad \operatorname{wait}_\pi(o) = \mathrm{settled}(k) \;\Longrightarrow\; \operatorname{settled}_\pi(o_k) \wedge t(o_k) \le T \wedge \mathit{fr}(o_k) \le F$$

The wait never reports a settled sample it did not see, and never one after the timeout or the frame budget. -/
theorem wait_sound (p : Policy) (o : Nat → Obs) (k : Nat) (h : wait p o = .settled k) :
    settled p (o k) = true ∧ (o k).t ≤ p.timeoutMs ∧ (o k).frames ≤ p.maxFrames := by
  obtain ⟨a, b, c, _⟩ := scan_sound p o _ _ _ h
  exact ⟨a, b, c⟩

/-- A scan over observations none of which is settled is `unsettled`.

$$\left(\forall i,\ \neg\operatorname{settled}_\pi(o_i)\right) \Rightarrow \forall f\, i,\ \operatorname{scan}(i, f) = \mathrm{unsettled}$$ -/
theorem scan_unsettled_of_never (p : Policy) (o : Nat → Obs) (never : ∀ i, settled p (o i) = false) :
    ∀ f i, scan p o i f = .unsettled := by
  intro f
  induction f with
  | zero => intro i; simp [scan]
  | succ f ih =>
    intro i
    simp only [scan]
    cases h1 : spent p (o i)
    · simp [never i]
      exact ih (i + 1)
    · simp

/-- A page that never settles ends the wait as `unsettled` (the time and frame budgets are the bound; there is no silent
success).

$$\forall \pi\, o,\quad \left(\forall i,\ \neg\operatorname{settled}_\pi(o_i)\right) \Longrightarrow \operatorname{wait}_\pi(o) = \mathrm{unsettled}$$ -/
theorem wait_unsettled_of_never (p : Policy) (o : Nat → Obs) (never : ∀ i, settled p (o i) = false) :
    wait p o = .unsettled :=
  scan_unsettled_of_never p o never _ _

/-- A non-decreasing sequence is bounded by its later values.

$$\left(\forall n,\ g(n) \le g(n+1)\right) \Rightarrow \forall i\, j,\ i \le j \Rightarrow g(i) \le g(j)$$ -/
theorem mono_le (g : Nat → Nat) (h : ∀ n, g n ≤ g (n + 1)) (i j : Nat) (hij : i ≤ j) : g i ≤ g j := by
  have : ∀ d, g i ≤ g (i + d) := by
    intro d
    induction d with
    | zero => exact Nat.le_refl _
    | succ d ihd => exact Nat.le_trans ihd (h (i + d))
  have h2 := this (j - i)
  rwa [show i + (j - i) = j by omega] at h2

/-- A scan with enough fuel that reaches a settled observation inside the budget (time and frames non-decreasing) finds
one no later.

$$\left(\forall n,\ t(o_n)\le t(o_{n+1}) \wedge \mathit{fr}(o_n)\le \mathit{fr}(o_{n+1})\right) \Rightarrow \forall f\, i\, j,\ i \le j < i + f \wedge \operatorname{settled}_\pi(o_j) \wedge t(o_j) \le T \wedge \mathit{fr}(o_j) \le F \Rightarrow \exists k,\ \operatorname{scan}(i, f) = \mathrm{settled}(k) \wedge i \le k \le j$$ -/
theorem scan_complete (p : Policy) (o : Nat → Obs) (tmono : ∀ n, (o n).t ≤ (o (n + 1)).t)
    (fmono : ∀ n, (o n).frames ≤ (o (n + 1)).frames) :
    ∀ f i j, i ≤ j → j < i + f → settled p (o j) = true → (o j).t ≤ p.timeoutMs → (o j).frames ≤ p.maxFrames →
      ∃ k, scan p o i f = .settled k ∧ i ≤ k ∧ k ≤ j := by
  intro f
  induction f with
  | zero => intro i j _ hj; omega
  | succ f ih =>
    intro i j hij hjf hs ht hfr
    simp only [scan]
    have hti := mono_le (fun n => (o n).t) tmono i j hij
    have hfi := mono_le (fun n => (o n).frames) fmono i j hij
    have h1 : spent p (o i) = false := (spent_false_iff p (o i)).2 ⟨by omega, by omega⟩
    by_cases h2 : settled p (o i) = true
    · exact ⟨i, by simp [h1, h2], Nat.le_refl _, hij⟩
    · by_cases hji : j = i
      · subst hji; exact absurd hs h2
      · obtain ⟨k, hk, hk1, hk2⟩ := ih (i + 1) j (by omega) (by omega) hs ht hfr
        exact ⟨k, by simp [h1, h2, hk], by omega, hk2⟩

/-- If time and frames are non-decreasing and some observation `j` is settled inside both budgets, the wait finds a
settled observation no later than `j`: a page that settles in time is not reported `unsettled`.

$$\left(\forall n,\ t(o_n)\le t(o_{n+1}) \wedge \mathit{fr}(o_n)\le \mathit{fr}(o_{n+1})\right) \wedge j \le T \wedge \operatorname{settled}_\pi(o_j) \wedge t(o_j)\le T \wedge \mathit{fr}(o_j) \le F \;\Longrightarrow\; \exists k\le j,\ \operatorname{wait}_\pi(o) = \mathrm{settled}(k)$$

(The bound `j ≤ T` says one observation per millisecond at most: the scan covers `T + 1` of them.) -/
theorem wait_complete (p : Policy) (o : Nat → Obs) (tmono : ∀ n, (o n).t ≤ (o (n + 1)).t)
    (fmono : ∀ n, (o n).frames ≤ (o (n + 1)).frames) (j : Nat)
    (hj : j ≤ p.timeoutMs) (hs : settled p (o j) = true) (ht : (o j).t ≤ p.timeoutMs) (hf : (o j).frames ≤ p.maxFrames) :
    ∃ k, wait p o = .settled k ∧ k ≤ j := by
  obtain ⟨k, hk, _, hk2⟩ := scan_complete p o tmono fmono (p.timeoutMs + 1) 0 j (by omega) (by omega) hs ht hf
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
-- the frame budget (gate-shard-balance): it only ends waits sooner, and keeps every outcome inside it
-- ---------------------------------------------------------------------------------------------------------------

/-- The policy `π` with frame budget `F` instead of its own.

$$\pi[F] = (m_f, m_s, \varepsilon, T, F)$$ -/
def withBudget (p : Policy) (F : Nat) : Policy := { p with maxFrames := F }

/-- The settled decision does not read the frame budget.

$$\forall \pi\, F\, o,\quad \operatorname{settled}_{\pi[F]}(o) = \operatorname{settled}_\pi(o)$$ -/
theorem settled_withBudget (p : Policy) (F : Nat) (o : Obs) : settled (withBudget p F) o = settled p o := rfl

/-- A smaller frame budget either changes nothing or turns the scan's answer into `unsettled`: it never invents a settled
answer.

$$\forall \pi\, o\, F,\quad F \le F_\pi \Rightarrow \forall f\, i,\ \operatorname{scan}_{\pi[F]}(i, f) = \operatorname{scan}_\pi(i, f) \;\vee\; \operatorname{scan}_{\pi[F]}(i, f) = \mathrm{unsettled}$$ -/
theorem scan_budget_cases (p : Policy) (o : Nat → Obs) (F : Nat) (hF : F ≤ p.maxFrames) :
    ∀ f i, scan (withBudget p F) o i f = scan p o i f ∨ scan (withBudget p F) o i f = .unsettled := by
  intro f
  induction f with
  | zero => intro i; simp [scan]
  | succ f ih =>
    intro i
    simp only [scan, settled_withBudget]
    by_cases h1 : spent (withBudget p F) (o i) = true
    · simp [h1]
    · have hb := (spent_false_iff _ (o i)).1 (by simpa using h1)
      have h0 : spent p (o i) = false := (spent_false_iff p (o i)).2 ⟨hb.1, Nat.le_trans hb.2 hF⟩
      by_cases h2 : settled p (o i) = true
      · simp [h1, h0, h2]
      · have h1' : spent (withBudget p F) (o i) = false := by simpa using h1
        simp only [h1', h0, h2, Bool.false_eq_true, ite_false]
        exact ih (i + 1)

/-- A smaller frame budget never invents a settled wait: the answer is the old one or `unsettled`.

$$\forall \pi\, o\, F,\quad F \le F_\pi \Longrightarrow \operatorname{wait}_{\pi[F]}(o) = \operatorname{wait}_\pi(o) \;\vee\; \operatorname{wait}_{\pi[F]}(o) = \mathrm{unsettled}$$ -/
theorem wait_budget_cases (p : Policy) (o : Nat → Obs) (F : Nat) (hF : F ≤ p.maxFrames) :
    wait (withBudget p F) o = wait p o ∨ wait (withBudget p F) o = .unsettled :=
  scan_budget_cases p o F hF _ _

/-- A scan that settles at observation `k` within `F` frames (frames non-decreasing) gives the same answer under the
budget `F`.

$$\forall \pi\, o\, F,\quad \left(\forall n,\ \mathit{fr}(o_n)\le \mathit{fr}(o_{n+1})\right) \Rightarrow \forall f\, i\, k,\ \operatorname{scan}_\pi(i, f) = \mathrm{settled}(k) \wedge \mathit{fr}(o_k) \le F \Rightarrow \operatorname{scan}_{\pi[F]}(i, f) = \mathrm{settled}(k)$$ -/
theorem scan_budget_keeps (p : Policy) (o : Nat → Obs) (F : Nat) (fmono : ∀ n, (o n).frames ≤ (o (n + 1)).frames) :
    ∀ f i k, scan p o i f = .settled k → (o k).frames ≤ F → scan (withBudget p F) o i f = .settled k := by
  intro f
  induction f with
  | zero => intro i k h; simp [scan] at h
  | succ f ih =>
    intro i k h hk
    have hik := (scan_sound p o (f + 1) i k h).2.2.2
    have hfi := mono_le (fun n => (o n).frames) fmono i k hik
    simp only [scan, settled_withBudget] at h ⊢
    by_cases h1 : spent p (o i) = true
    · simp [h1] at h
    · have h1' : spent p (o i) = false := by simpa using h1
      have hb := (spent_false_iff p (o i)).1 h1'
      have h0 : spent (withBudget p F) (o i) = false :=
        (spent_false_iff (withBudget p F) (o i)).2 ⟨hb.1, Nat.le_trans hfi hk⟩
      by_cases h2 : settled p (o i) = true
      · simp only [h1', h2, Bool.false_eq_true, ite_false, ite_true] at h
        simp only [h0, h2, Bool.false_eq_true, ite_false, ite_true]
        exact h
      · simp only [h1', h2, Bool.false_eq_true, ite_false] at h
        simp only [h0, h2, Bool.false_eq_true, ite_false]
        exact ih (i + 1) k h hk

/-- The frame budget keeps every wait that settles within it: if the wait without the budget settles at observation `k`
after at most `F` real frames (frames non-decreasing), the wait with budget `F` settles at the same `k`.

$$\forall \pi\, o\, F\, k,\quad \left(\forall n,\ \mathit{fr}(o_n)\le \mathit{fr}(o_{n+1})\right) \wedge \operatorname{wait}_\pi(o) = \mathrm{settled}(k) \wedge \mathit{fr}(o_k) \le F \;\Longrightarrow\; \operatorname{wait}_{\pi[F]}(o) = \mathrm{settled}(k)$$ -/
theorem wait_budget_keeps (p : Policy) (o : Nat → Obs) (F k : Nat) (fmono : ∀ n, (o n).frames ≤ (o (n + 1)).frames)
    (h : wait p o = .settled k) (hk : (o k).frames ≤ F) : wait (withBudget p F) o = .settled k :=
  scan_budget_keeps p o F fmono _ _ _ h hk

/-- The cell report under a smaller frame budget is the old report or `unsettled`: the budget never creates a pass or a
fail that the wait without it would not give.

$$\forall \pi\, F\, a\, b\, e,\quad F \le F_\pi \Rightarrow \operatorname{report}(\operatorname{wait}_{\pi[F]}(a), \operatorname{wait}_{\pi[F]}(b), e) \in \{\operatorname{report}(\operatorname{wait}_\pi(a), \operatorname{wait}_\pi(b), e),\ \mathrm{unsettled}\}$$ -/
theorem report_budget (p : Policy) (F : Nat) (hF : F ≤ p.maxFrames) (oa ob : Nat → Obs) (e : Bool) :
    report (wait (withBudget p F) oa) (wait (withBudget p F) ob) e = report (wait p oa) (wait p ob) e ∨
      report (wait (withBudget p F) oa) (wait (withBudget p F) ob) e = .unsettled := by
  rcases wait_budget_cases p oa F hF with ha | ha <;> rcases wait_budget_cases p ob F hF with hb | hb
  · exact Or.inl (by rw [ha, hb])
  · exact Or.inr (unsettled_never_fail _ _ e (Or.inr hb))
  · exact Or.inr (unsettled_never_fail _ _ e (Or.inl ha))
  · exact Or.inr (unsettled_never_fail _ _ e (Or.inl ha))

/-- The scan's answer depends on no observation past the first one whose budget is spent: if two observation sequences
agree up to index `n` and the budget is spent at `n`, the scans agree. So the page loop may stop at `n` (and with the
frame budget, `n ≤ F + 1` when every observation is a real frame: `wait_stops_by_frames`; Fw.Gate.Freeze.wait_frozen_agree states it for the frozen clock).

$$\forall \pi\, o\, o'\, n,\quad \operatorname{spent}_\pi(o_n) \Rightarrow \forall f\, i,\ i \le n \wedge \left(\forall m,\ i \le m \le n \Rightarrow o_m = o'_m\right) \Rightarrow \operatorname{scan}_\pi(o)(i, f) = \operatorname{scan}_\pi(o')(i, f)$$ -/
theorem scan_decided_by (p : Policy) (o o' : Nat → Obs) (n : Nat) (hs : spent p (o n) = true) :
    ∀ f i, i ≤ n → (∀ m, i ≤ m → m ≤ n → o m = o' m) → scan p o i f = scan p o' i f := by
  intro f
  induction f with
  | zero => intro i _ _; simp [scan]
  | succ f ih =>
    intro i hi hag
    have he : o i = o' i := hag i (Nat.le_refl _) hi
    by_cases hin : i = n
    · subst hin
      have h' : spent p (o' i) = true := he ▸ hs
      simp [scan, hs, h']
    · have hr := ih (i + 1) (by omega) (fun m h1 h2 => hag m (by omega) h2)
      simp only [scan, he, hr]

/-- When every observation of the wait is a real frame (`i ≤ fr(o_i)`), the budget $F_\pi$ is spent by observation $F_\pi + 1$, so
the wait reads at most $F_\pi + 2$ observations: whatever comes after does not change its answer.

$$\forall \pi\, o\, o',\quad \left(\forall i,\ i \le \mathit{fr}(o_i)\right) \wedge \left(\forall m \le F_\pi + 1,\ o_m = o'_m\right) \Longrightarrow \operatorname{wait}_\pi(o) = \operatorname{wait}_\pi(o')$$ -/
theorem wait_stops_by_frames (p : Policy) (o o' : Nat → Obs) (hfr : ∀ i, i ≤ (o i).frames)
    (hag : ∀ m, m ≤ p.maxFrames + 1 → o m = o' m) : wait p o = wait p o' := by
  have hs : spent p (o (p.maxFrames + 1)) = true := by
    have := hfr (p.maxFrames + 1)
    simp only [spent, Bool.or_eq_true, decide_eq_true_eq]
    exact Or.inr (by omega)
  exact scan_decided_by p o o' (p.maxFrames + 1) hs _ 0 (by omega) (fun m _ h => hag m h)


-- ---------------------------------------------------------------------------------------------------------------
-- the mount stage's idle wait and the sample's fold (gate-shard-balance)
-- ---------------------------------------------------------------------------------------------------------------

/-- The policy of the mount stage's idle wait (`prepareInPage` stage `ready`, after the mount steps scrolled the page and
back): it ends when no finite animation of the document runs, with no frame or quiet minimum, under the arm's time cap
`c` and the gate's frame budget. Before gate-shard-balance this wait had only the time cap (20 s for the original), and in
run 39101532038 it ran to that cap at each of the 29 desktop-sweep stops from 400 px back up to 1512 px (about 21 s per
stop, MEASURED), whose main settle waits were all unsettled anyway.

$$\pi_{\mathrm{idle}}(\pi, c) = (0, 0, \varepsilon, c, F)$$ -/
def idlePolicy (p : Policy) (c : Nat) : Policy := { p with minFrames := 0, minStable := 0, timeoutMs := c }

/-- Under the idle policy an observation is settled exactly when nothing runs and the pointer is not inside a target (the
idle observations always say `false` there).

$$\forall \pi\, c\, o,\quad \operatorname{settled}_{\pi_{\mathrm{idle}}(\pi, c)}(o) \iff \mathit{run}(o) = 0 \wedge \neg\mathit{hov}(o)$$ -/
theorem idle_settled_iff (p : Policy) (c : Nat) (o : Obs) :
    settled (idlePolicy p c) o = true ↔ o.running = 0 ∧ o.hoverInside = false := by
  simp [settled, idlePolicy]

/-- One step of the sample's fold: `unsettled` when either outcome is, else the first.

$$\operatorname{fold}_1(a, w) = \begin{cases}\mathrm{unsettled} & a = \mathrm{unsettled} \vee w = \mathrm{unsettled}\\ a & \text{otherwise}\end{cases}$$ -/
def fold1 (a w : Outcome) : Outcome := if a = .unsettled ∨ w = .unsettled then .unsettled else a

/-- The outcome of a sample: its first (main) wait folded with the later waits it made (overlays opened, parts brought into
view, the mount stage's idle wait), left to right (`run.mjs` `foldSettle`).

$$\operatorname{fold}(a, [w_1, \dots, w_n]) = \operatorname{fold}_1(\cdots\operatorname{fold}_1(a, w_1)\cdots, w_n)$$ -/
def fold (first : Outcome) (extra : List Outcome) : Outcome := extra.foldl fold1 first

/-- An unsettled start stays unsettled through the fold.

$$\forall\, ws,\quad \operatorname{fold}(\mathrm{unsettled}, ws) = \mathrm{unsettled}$$ -/
theorem fold_unsettled_start : ∀ ws : List Outcome, fold .unsettled ws = .unsettled := by
  intro ws
  induction ws with
  | nil => rfl
  | cons w ws ih => simpa [fold, List.foldl, fold1] using ih

/-- The sample is unsettled when any of its waits is: the first one or a later one.

$$\forall a\, ws,\quad a = \mathrm{unsettled} \vee \mathrm{unsettled} \in ws \;\Longrightarrow\; \operatorname{fold}(a, ws) = \mathrm{unsettled}$$ -/
theorem fold_unsettled (a : Outcome) (ws : List Outcome) (h : a = .unsettled ∨ Outcome.unsettled ∈ ws) :
    fold a ws = .unsettled := by
  induction ws generalizing a with
  | nil =>
    rcases h with h | h
    · subst h; rfl
    · simp at h
  | cons w ws ih =>
    simp only [fold, List.foldl]
    rcases h with h | h
    · subst h; exact fold_unsettled_start (w :: ws)
    · rcases List.mem_cons.1 h with h | h
      · subst h
        have h1 : fold1 a .unsettled = .unsettled := by simp [fold1]
        rw [h1]; exact fold_unsettled_start ws
      · exact ih (fold1 a w) (Or.inr h)

/-- When every wait of the sample settled, the sample's outcome is its first wait's.

$$\forall a\, ws,\quad a \ne \mathrm{unsettled} \wedge \mathrm{unsettled} \notin ws \;\Longrightarrow\; \operatorname{fold}(a, ws) = a$$ -/
theorem fold_settled (a : Outcome) (ws : List Outcome) (ha : a ≠ .unsettled) (h : Outcome.unsettled ∉ ws) :
    fold a ws = a := by
  induction ws with
  | nil => rfl
  | cons w ws ih =>
    simp only [fold, List.foldl]
    have hw : w ≠ .unsettled := fun e => h (e ▸ List.mem_cons_self ..)
    have h1 : fold1 a w = a := by simp [fold1, ha, hw]
    rw [h1]
    exact ih (fun e => h (List.mem_cons_of_mem _ e))

/-- A sample one of whose waits (the main settle, an overlay, a brought part or the mount stage's idle wait) is unsettled
never gives a pass, whatever the other arm and the values.

$$\forall a\, ws\, b\, e,\quad \mathrm{unsettled} \in ws \;\Longrightarrow\; \operatorname{report}(\operatorname{fold}(a, ws), b, e) \ne \mathrm{pass}$$ -/
theorem fold_unsettled_never_pass (a : Outcome) (ws : List Outcome) (b : Outcome) (e : Bool)
    (h : Outcome.unsettled ∈ ws) : report (fold a ws) b e ≠ .pass :=
  unsettled_never_pass _ _ e (Or.inl (fold_unsettled a ws (Or.inr h)))

#guard fold (.settled 2) [.settled 0, .settled 5] == .settled 2
#guard fold (.settled 2) [.settled 0, .unsettled] == .unsettled
#guard fold .unsettled [] == .unsettled
#guard settled (idlePolicy gatePolicy 20000) { running := 0, frames := 0, stable := 0, hoverInside := false, t := 0 } == true
#guard settled (idlePolicy gatePolicy 20000) { running := 2, frames := 9, stable := 9, hoverInside := false, t := 10 } == false

-- ---------------------------------------------------------------------------------------------------------------
-- a probe on a node that is not rendered has no verdict (fix-commission: inner/rows margin-inline at pain-1440 #0)
-- ---------------------------------------------------------------------------------------------------------------

/-- A node counts as rendered when no element on its ancestor chain (itself included) is flagged by the caller as unrendered.
The flags are an INPUT: this module proves what a flagged probe means (no verdict), not when a flag is right. The gate (probes only; on in the Chromium probes and off in WebKit: `viewFor`; see `viewCell`) flags a node the engine has skipped under `content-visibility:auto` (premise `cv.skip-flag`: `checkVisibility()` true and the
`contentVisibilityAuto` form false) and, before a flag takes effect, brings the part into view and reads again (`view`,
`viewCell` below), so only a node still skipped after that is `notRendered`. Premise-tests (run 39076735134) refuted the
earlier idea that a skipped node reports an unresolved `auto`: `getComputedStyle` returns the resolved length there.

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

/-- Only `pass` is a passing cell: `fail`, `unsettled` and `notRendered` are not.

$$\forall c,\ \operatorname{passes}(c) = \top \iff c = \mathrm{pass}$$ -/
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
-- a node in a skipped subtree is brought into view and read again (fix-commission)
-- ---------------------------------------------------------------------------------------------------------------

/-- One arm's reading of one node: whether the engine had the node's subtree skipped (`content-visibility:auto`, off screen)
at the read, and the value read.

$$\mathrm{Reading}_\alpha = \{\ \mathit{skipped} \in \{0,1\},\ \mathit{val} \in \alpha\ \}$$ -/
structure Reading (α : Type) where
  skipped : Bool
  val : α
  deriving Repr

/-- The reading the gate keeps for a node. `bring` says that the gate brought the node's part into view (`scrollIntoView`),
settled and read again; then the kept reading is the second one, and the first (possibly stale) value is dropped. Without
`bring` the first reading is kept.

$$\operatorname{view}(b, f, g) = \begin{cases} g & b \\ f & \neg b\end{cases}$$ -/
def view {α : Type} (bring : Bool) (first again : Reading α) : Reading α := if bring then again else first

/-- The gate brings a part into view whenever one of its nodes was read in a skipped subtree, so every skipped first reading is covered.

$$\operatorname{Covered}(b, f) \iff (f.\mathit{skipped} \Rightarrow b)$$ -/
def Covered {α : Type} (bring : Bool) (first : Reading α) : Prop := first.skipped = true → bring = true

/-- The cell of one node from the two arms' first and second readings: the kept readings decide which arm renders the node and
whether the values are equal; `a`, `b` are the arms' settle outcomes.

$$\operatorname{viewCell}(b_o, b_r, f_o, g_o, f_r, g_r, a, b) = \operatorname{cell}\big(\neg\operatorname{view}(b_o, f_o, g_o).\mathit{skipped},\ \neg\operatorname{view}(b_r, f_r, g_r).\mathit{skipped},\ a,\ b,\ [\operatorname{view}(b_o, f_o, g_o).\mathit{val} = \operatorname{view}(b_r, f_r, g_r).\mathit{val}]\big)$$ -/
def viewCell {α : Type} [DecidableEq α] (bo br : Bool) (fo go fr gr : Reading α) (a b : Outcome) : Cell :=
  cell (!(view bo fo go).skipped) (!(view br fr gr).skipped) a b (decide ((view bo fo go).val = (view br fr gr).val))

/-- A brought node's stale first value never reaches the cell: the kept reading is the second one.

$$\operatorname{view}(\top, f, g) = g$$ -/
theorem view_bring {α : Type} (f g : Reading α) : view true f g = g := by simp [view]

/-- With nothing brought into view the rule is inert: the first reading is kept, so a gate run without a skipped node is unchanged.

$$\operatorname{viewCell}(\bot, \bot, f_o, g_o, f_r, g_r, a, b) = \operatorname{cell}(\neg f_o.\mathit{skipped}, \neg f_r.\mathit{skipped}, a, b, [f_o.\mathit{val} = f_r.\mathit{val}]),\quad v = \operatorname{viewFor}(\bot, \texttt{playwright-webkit})$$ -/
theorem viewCell_inert {α : Type} [DecidableEq α] (fo go fr gr : Reading α) (a b : Outcome) :
    viewCell false false fo go fr gr a b = cell (!fo.skipped) (!fr.skipped) a b (decide (fo.val = fr.val)) := by
  simp [viewCell, view]

/-- A node is `notRendered` only when the kept reading of one arm is still skipped.

$$\operatorname{viewCell}(\dots) = \mathrm{notRendered} \iff \operatorname{view}(b_o, f_o, g_o).\mathit{skipped} \vee \operatorname{view}(b_r, f_r, g_r).\mathit{skipped}$$ -/
theorem viewCell_notRendered_iff {α : Type} [DecidableEq α] (bo br : Bool) (fo go fr gr : Reading α) (a b : Outcome) :
    viewCell bo br fo go fr gr a b = .notRendered ↔ (view bo fo go).skipped = true ∨ (view br fr gr).skipped = true := by
  unfold viewCell cell
  rcases h1 : (view bo fo go).skipped <;> rcases h2 : (view br fr gr).skipped <;> simp <;>
    cases report a b _ <;> simp

/-- A node reads as skipped after the rule only if the gate brought it into view and the engine still reported it skipped on
the second reading: a skipped node is never given up before it was brought into view.

$$\operatorname{Covered}(b, f) \wedge \operatorname{view}(b, f, g).\mathit{skipped} \Longrightarrow b \wedge g.\mathit{skipped}$$ -/
theorem skipped_after_view_only_if_brought {α : Type} (bring : Bool) (f g : Reading α) (hc : Covered bring f)
    (h : (view bring f g).skipped = true) : bring = true ∧ g.skipped = true := by
  cases bring
  · exact absurd (hc (by simpa [view] using h)) (by simp)
  · exact ⟨rfl, by simpa [view] using h⟩

/-- The rule never hides a rendered difference: when both kept readings are of rendered nodes, both arms settled and the kept
values differ, the cell is `fail`.

$$\neg k_o.\mathit{skipped} \wedge \neg k_r.\mathit{skipped} \wedge k_o.\mathit{val} \ne k_r.\mathit{val} \Longrightarrow \operatorname{viewCell}(\dots, \mathrm{settled}(i), \mathrm{settled}(j)) = \mathrm{fail}$$ -/
theorem viewCell_fail_of_rendered_diff {α : Type} [DecidableEq α] (bo br : Bool) (fo go fr gr : Reading α) (i j : Nat)
    (ho : (view bo fo go).skipped = false) (hr : (view br fr gr).skipped = false)
    (hd : (view bo fo go).val ≠ (view br fr gr).val) :
    viewCell bo br fo go fr gr (.settled i) (.settled j) = .fail := by
  simp [viewCell, cell, ho, hr, hd, report]

/-- The rule never invents a pass: a pass needs both kept readings of rendered nodes, equal values and both arms settled.

$$\operatorname{viewCell}(\dots) = \mathrm{pass} \Longrightarrow \neg k_o.\mathit{skipped} \wedge \neg k_r.\mathit{skipped} \wedge k_o.\mathit{val} = k_r.\mathit{val} \wedge \exists i\, j,\ a = \mathrm{settled}(i) \wedge b = \mathrm{settled}(j)$$ -/
theorem viewCell_pass_sound {α : Type} [DecidableEq α] (bo br : Bool) (fo go fr gr : Reading α) (a b : Outcome)
    (h : viewCell bo br fo go fr gr a b = .pass) :
    (view bo fo go).skipped = false ∧ (view br fr gr).skipped = false ∧ (view bo fo go).val = (view br fr gr).val
      ∧ ∃ i j, a = .settled i ∧ b = .settled j := by
  obtain ⟨h1, h2, i, j, ha, hb⟩ := cell_decided _ _ a b _ (Or.inl h)
  have h1' : (view bo fo go).skipped = false := by simpa using h1
  have h2' : (view br fr gr).skipped = false := by simpa using h2
  subst ha hb
  refine ⟨h1', h2', ?_, i, j, rfl, rfl⟩
  cases hd : decide ((view bo fo go).val = (view br fr gr).val)
  · simp [viewCell, cell, report, h1', h2', hd] at h
  · simpa using hd

-- ---------------------------------------------------------------------------------------------------------------
-- which engine reads a skipped part again (the bring flag as a function of the engine)
-- ---------------------------------------------------------------------------------------------------------------

/-- The engines the gate runs, by the launcher name the runner records (`engines.mjs` `name`).

$$E = \{\mathrm{chromium}, \mathrm{webkit}\}$$ -/
inductive ViewEngine where
  | chromium
  | webkit
  deriving DecidableEq, Repr

/-- The launcher name of an engine as `run.mjs` knows it (`chromium`, `playwright-webkit`).

$$\operatorname{engineOf}(n) = \begin{cases} \mathrm{chromium} & n = \texttt{chromium} \\ \mathrm{webkit} & n = \texttt{playwright-webkit} \\ \bot & \text{otherwise} \end{cases}$$ -/
def engineOf (n : String) : Option ViewEngine :=
  if n = "chromium" then some .chromium else if n = "playwright-webkit" then some .webkit else none

/-- Whether the probes of an engine bring a skipped part into view and read it again. Chromium needs it: its `getComputedStyle`
returns a stale used `auto` margin inside a `content-visibility:auto` subtree it skipped (run 39101532038: commission
`margin-inline` 869.5 against 869 at one probe). WebKit does not and breaks with it: the scroll flips the commission
scene's `content-visibility` and `--commission-shrink` in one arm only (run 39105279831: 11 probes).

$$\operatorname{viewOn}(\mathrm{chromium}) = \top \qquad \operatorname{viewOn}(\mathrm{webkit}) = \bot$$ -/
def viewOn : ViewEngine → Bool
  | .chromium => true
  | .webkit => false

/-- The bring flag of a run: the debug switch `FW_GATE_VIEW` (`1` on, `0` off, anything else or absent: the engine's own policy),
and an engine name the runner does not know reads nothing again.

$$\operatorname{viewFor}(s, n) = \begin{cases} \top & s = \texttt{1} \\ \bot & s = \texttt{0} \\ \operatorname{viewOn}(e) & s \notin \{\texttt{1}, \texttt{0}\} \wedge \operatorname{engineOf}(n) = \mathrm{some}(e) \\ \bot & s \notin \{\texttt{1}, \texttt{0}\} \wedge \operatorname{engineOf}(n) = \bot \end{cases}$$ -/
def viewFor (s : Option String) (n : String) : Bool :=
  match s with
  | some "1" => true
  | some "0" => false
  | _ => (engineOf n).any viewOn

/-- With no switch set, Chromium reads again and WebKit does not.

$$\operatorname{viewFor}(\bot, \texttt{chromium}) = \top \wedge \operatorname{viewFor}(\bot, \texttt{playwright-webkit}) = \bot$$ -/
theorem viewFor_default : viewFor none "chromium" = true ∧ viewFor none "playwright-webkit" = false := by
  decide

/-- The switch overrides the engine's policy in both directions.

$$\forall n,\ \operatorname{viewFor}(\texttt{1}, n) = \top \wedge \operatorname{viewFor}(\texttt{0}, n) = \bot$$ -/
theorem viewFor_switch (n : String) : viewFor (some "1") n = true ∧ viewFor (some "0") n = false := by
  simp [viewFor]

/-- Any other switch value is no switch.

$$\forall s, n,\ s \notin \{\texttt{1}, \texttt{0}\} \implies \operatorname{viewFor}(\mathrm{some}(s), n) = \operatorname{viewFor}(\bot, n)$$ -/
theorem viewFor_other (s n : String) (h1 : s ≠ "1") (h0 : s ≠ "0") : viewFor (some s) n = viewFor none n := by
  simp [viewFor, h1, h0]

/-- An unknown engine name never brings a part into view.

$$\operatorname{engineOf}(n) = \bot \implies \operatorname{viewFor}(\bot, n) = \bot$$ -/
theorem viewFor_unknown (n : String) (h : engineOf n = none) : viewFor none n = false := by
  simp [viewFor, h]

/-- Where the engine does not bring parts (WebKit by default), the cell is the first reading's, whatever the second reading holds.

$$\forall f_o, g_o, f_r, g_r, a, b,\quad \operatorname{viewCell}(v, v, f_o, g_o, f_r, g_r, a, b) = \operatorname{cell}(\neg f_o.\mathit{skipped}, \neg f_r.\mathit{skipped}, a, b, [f_o.\mathit{val} = f_r.\mathit{val}]),\quad v = \operatorname{viewFor}(\bot, \texttt{playwright-webkit})$$ -/
theorem viewCell_webkit_default {α : Type} [DecidableEq α] (fo go fr gr : Reading α) (a b : Outcome) :
    viewCell (viewFor none "playwright-webkit") (viewFor none "playwright-webkit") fo go fr gr a b =
      cell (!fo.skipped) (!fr.skipped) a b (decide (fo.val = fr.val)) := by
  rw [viewFor_default.2]
  exact viewCell_inert fo go fr gr a b

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
frames is unsettled.

$$\mathit{fr}(o) < m_f \;\Longrightarrow\; \neg\operatorname{settled}_\pi(o)$$ -/
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

$$\forall a\,A\,\mathit{fr}\,\mathit{st}\,\mathit{hov}\,t,\quad a \in A \wedge \mathit{elapsed}(a) < \mathit{dur}(a) \;\Longrightarrow\; \neg\operatorname{settled}_\pi\bigl(\operatorname{runCount}(A), \mathit{fr}, \mathit{st}, \mathit{hov}, t\bigr)$$ -/
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

$$\pi \mapsto \{m_f, m_s, \varepsilon, T, F\}$$ -/
def policyJson (p : Policy) : Json :=
  Json.mkObj [("minFrames", toJson p.minFrames), ("minStable", toJson p.minStable), ("eps", toJson p.eps), ("timeoutMs", toJson p.timeoutMs),
    ("maxFrames", toJson p.maxFrames)]

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
      gatePolicy, [ob 1 1 0 false 16, ob 1 2 0 false 1500, ob 1 3 0 false 29900, ob 0 4 1 false 30100, ob 0 5 2 false 30116]),
    ("settles only after the budget",
      gatePolicy, [ob 0 1 0 false 1000, ob 0 2 3 false 30001, ob 0 3 4 false 30017]),
    ("settles exactly at the budget",
      gatePolicy, [ob 0 1 0 false 1000, ob 0 2 3 false 30000]),
    ("no frame ever (requestAnimationFrame never fires)",
      gatePolicy, [ob 0 0 0 false 250, ob 0 0 0 false 1000, ob 0 0 0 false 30000]),
    ("pointer stays inside a hover target",
      gatePolicy, [ob 0 2 2 true 16, ob 0 3 3 true 33, ob 0 4 4 true 50]),
    ("empty trace", gatePolicy, []),
    ("a stricter policy needs more frames",
      { minFrames := 4, minStable := 2, eps := 100, timeoutMs := 100, maxFrames := 60 }, [ob 0 2 2 false 16, ob 0 3 3 false 33, ob 0 4 4 false 50]),
    ("a lerp that never stops spends the frame budget long before the timeout",
      gatePolicy, [ob 0 1 0 false 16, ob 0 30 0 false 500, ob 0 60 0 false 1000, ob 0 61 0 false 1016, ob 0 62 3 false 1033]),
    ("settles exactly at the frame budget",
      gatePolicy, [ob 1 1 0 false 16, ob 0 58 1 false 966, ob 0 60 3 false 1000]),
    ("settles one frame after the frame budget",
      gatePolicy, [ob 1 1 0 false 16, ob 0 59 1 false 983, ob 0 61 3 false 1016]),
    ("slow frames: the timeout comes before the frame budget",
      gatePolicy, [ob 1 1 0 false 3000, ob 1 40 0 false 29000, ob 1 41 0 false 30001]),
    ("idle: nothing runs at once",
      idlePolicy gatePolicy 20000, [ob 0 0 0 false 0]),
    ("idle: animations finish after some frames",
      idlePolicy gatePolicy 20000, [ob 2 0 0 false 0, ob 1 10 0 false 170, ob 0 20 0 false 340]),
    ("idle: timers keep restarting animations past the frame budget",
      idlePolicy gatePolicy 20000, [ob 3 0 0 false 0, ob 2 60 0 false 1000, ob 4 61 0 false 1016, ob 0 70 0 false 1200]),
    ("idle: the cap comes first on slow frames",
      idlePolicy gatePolicy 15000, [ob 1 0 0 false 0, ob 1 20 0 false 14000, ob 1 21 0 false 15001]) ]

/-- Sample folds: (name, first wait, later waits).

$$\text{foldCases} = [(n_k, a_k, ws_k)]_k$$ -/
def foldCases : List (String × Outcome × List Outcome) :=
  [ ("no later waits", .settled 3, []),
    ("all settled", .settled 3, [.settled 0, .settled 7]),
    ("an overlay did not settle", .settled 3, [.settled 0, .unsettled]),
    ("the main wait did not settle", .unsettled, [.settled 0]),
    ("the idle wait did not settle", .settled 1, [.unsettled]) ]

/-- Cell reports: (name, arm a, arm b, equal).

$$\text{reportCases} = [(n_k, a_k, b_k, e_k)]_k$$ -/
def reportCases : List (String × Outcome × Outcome × Bool) :=
  [ ("both settled and equal", .settled 2, .settled 0, true),
    ("both settled and different", .settled 2, .settled 5, false),
    ("original unsettled, values equal", .unsettled, .settled 1, true),
    ("rewrite unsettled, values different", .settled 1, .unsettled, false),
    ("both unsettled", .unsettled, .unsettled, true) ]

/-- The bring flag: (name, value of `FW_GATE_VIEW` or none, launcher name).

$$\text{viewForCases} = [(n_k, s_k, e_k)]_k$$ -/
def viewForCases : List (String × Option String × String) :=
  [ ("chromium, no switch", none, "chromium"),
    ("webkit, no switch", none, "playwright-webkit"),
    ("webkit forced on", some "1", "playwright-webkit"),
    ("chromium forced off", some "0", "chromium"),
    ("chromium, empty switch", some "", "chromium"),
    ("webkit, other switch value", some "yes", "playwright-webkit"),
    ("unknown engine, no switch", none, "firefox"),
    ("unknown engine forced on", some "1", "firefox") ]

/-- Probe cells: (name, arm a rendered, arm b rendered, outcome a, outcome b, equal).

$$\text{cellCases} = [(n_k, r_a, r_b, a_k, b_k, e_k)]_k$$ -/
def cellCases : List (String × Bool × Bool × Outcome × Outcome × Bool) :=
  [ ("both rendered, equal", true, true, .settled 1, .settled 2, true),
    ("both rendered, different", true, true, .settled 1, .settled 2, false),
    ("both rendered, one unsettled", true, true, .unsettled, .settled 2, true),
    ("original flagged unrendered, values different", false, true, .settled 1, .settled 2, false),
    ("rewrite not rendered, values equal", true, false, .settled 1, .settled 2, true),
    ("neither rendered, both unsettled", false, false, .unsettled, .unsettled, false) ]

/-- View cells: (name, original brought, rewrite brought, original first and second reading, rewrite first and second reading,
outcome a, outcome b). A reading is (skipped, value).

$$\text{viewCases} = [(n_k, b_o, b_r, f_o, g_o, f_r, g_r, a_k, b_k)]_k$$ -/
def viewCases : List (String × Bool × Bool × (Bool × Nat) × (Bool × Nat) × (Bool × Nat) × (Bool × Nat) × Outcome × Outcome) :=
  [ ("nothing skipped, equal", false, false, (false, 132), (false, 0), (false, 132), (false, 0), .settled 1, .settled 2),
    ("nothing skipped, different", false, false, (false, 132), (false, 0), (false, 0), (false, 0), .settled 1, .settled 2),
    ("commission: stale first margin 0, fresh after view equal", false, true, (false, 132), (false, 0), (true, 0), (false, 132), .settled 1, .settled 2),
    ("stale first margin 0, fresh after view different", false, true, (false, 132), (false, 0), (true, 0), (false, 7), .settled 1, .settled 2),
    ("still skipped after view", false, true, (false, 132), (false, 0), (true, 0), (true, 0), .settled 1, .settled 2),
    ("both skipped, both brought, equal fresh values", true, true, (true, 1), (false, 9), (true, 2), (false, 9), .settled 1, .settled 2),
    ("rendered difference is not hidden by a brought node elsewhere", true, true, (true, 1), (false, 9), (true, 2), (false, 8), .settled 1, .settled 2),
    ("rendered, one arm unsettled", false, true, (false, 5), (false, 0), (true, 0), (false, 5), .settled 1, .unsettled) ]

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

/-- One golden line per case, in the order of the nine case lists: observation, wait, quiet, rendered, cell, view, fold, report, viewFor.

$$\text{lines} = [\ell_{\mathrm{obs}}(c)]_{c \in \mathrm{obsCases}} \mathbin{+\!\!+} [\ell_{\mathrm{wait}}(c)]_{c \in \mathrm{waitCases}} \mathbin{+\!\!+} [\ell_{\mathrm{quiet}}(c)]_{c \in \mathrm{quietCases}} \mathbin{+\!\!+} [\ell_{\mathrm{rendered}}(c)]_{c \in \mathrm{renderedCases}} \mathbin{+\!\!+} [\ell_{\mathrm{cell}}(c)]_{c \in \mathrm{cellCases}} \mathbin{+\!\!+} [\ell_{\mathrm{view}}(c)]_{c \in \mathrm{viewCases}} \mathbin{+\!\!+} [\ell_{\mathrm{fold}}(c)]_{c \in \mathrm{foldCases}} \mathbin{+\!\!+} [\ell_{\mathrm{report}}(c)]_{c \in \mathrm{reportCases}} \mathbin{+\!\!+} [\ell_{\mathrm{viewFor}}(c)]_{c \in \mathrm{viewForCases}}$$ -/
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
  ++ viewCases.map (fun (n, bo, br, fo, go, fr, gr, a, b) =>
    let rd (x : Bool × Nat) : Json := Json.mkObj [("skipped", toJson x.1), ("val", toJson x.2)]
    let mk (x : Bool × Nat) : Reading Nat := { skipped := x.1, val := x.2 }
    (Json.mkObj [("kind", "view"), ("name", toJson n), ("bringO", toJson bo), ("bringR", toJson br),
      ("firstO", rd fo), ("againO", rd go), ("firstR", rd fr), ("againR", rd gr),
      ("a", toJson (outcomeText a)), ("b", toJson (outcomeText b)),
      ("cell", toJson (cellText (viewCell bo br (mk fo) (mk go) (mk fr) (mk gr) a b)))]).compress)
  ++ foldCases.map (fun (n, a, ws) =>
    (Json.mkObj [("kind", "fold"), ("name", toJson n), ("first", toJson (outcomeText a)),
      ("extra", toJson (ws.map outcomeText)), ("outcome", toJson (outcomeText (fold a ws)))]).compress)
  ++ reportCases.map (fun (n, a, b, e) =>
    (Json.mkObj [("kind", "report"), ("name", toJson n), ("a", toJson (outcomeText a)), ("b", toJson (outcomeText b)),
      ("equal", toJson e), ("report", toJson (reportText (report a b e)))]).compress)
  ++ viewForCases.map (fun (n, s, e) =>
    (Json.mkObj [("kind", "viewFor"), ("name", toJson n), ("switch", toJson s), ("engine", toJson e),
      ("view", toJson (viewFor s e))]).compress)

/-- The exact bytes of `packages/contracts/golden/gate/settle.jsonl`: the lines, each newline-terminated.

$$\text{goldenText} = \mathbin{+\!\!+}_{\ell \in \text{goldenLines}} (\ell \mathbin{+\!\!+} \texttt{newline})$$ -/
def goldenText : String := String.intercalate "" (goldenLines.map (· ++ "\n"))

/-- The value after the first occurrence of `flag` that has a successor in an argument list.

$$\operatorname{argAfter}(xs, f) = \begin{cases} \mathrm{some}(xs_{i+1}) & i = \min\{\, i \mid xs_i = f \wedge i + 1 < |xs| \,\} \text{ exists} \\ \mathrm{none} & \text{otherwise} \end{cases}$$ -/
def argAfter : List String → String → Option String
  | a :: b :: rest, flag => if a == flag then some b else argAfter (b :: rest) flag
  | _, _ => none

/-- Command-line driver: print the golden text, or with `--check <file>` exit 0 when the file holds exactly these bytes and 1 otherwise.

$$\operatorname{run}(\texttt{--check}\ f) = 0 \iff \operatorname{bytes}(f) = \operatorname{goldenText}$$

Print mode returns 0. -/
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
#guard waitList gatePolicy [ob 0 1 0 false 1000, ob 0 2 3 false 30001, ob 0 3 4 false 30017] == .unsettled
#guard waitList gatePolicy [] == .unsettled
#guard waitList gatePolicy [ob 0 60 3 false 1000] == .settled 0
#guard waitList gatePolicy [ob 0 61 3 false 1000] == .unsettled
#guard spent gatePolicy (ob 0 61 0 false 10) == true
#guard spent gatePolicy (ob 0 60 0 false 30000) == false
#guard cell false true (.settled 1) (.settled 2) false == .notRendered
#guard cell true true (.settled 1) (.settled 2) false == .fail
#guard rendered [false, true, false] == false
#guard viewCell true false (α := Nat) ⟨true, 0⟩ ⟨false, 132⟩ ⟨false, 132⟩ ⟨false, 0⟩ (.settled 1) (.settled 2) == .pass
#guard viewCell false true (α := Nat) ⟨false, 132⟩ ⟨false, 0⟩ ⟨true, 0⟩ ⟨false, 7⟩ (.settled 1) (.settled 2) == .fail
#guard viewCell false true (α := Nat) ⟨false, 132⟩ ⟨false, 0⟩ ⟨true, 0⟩ ⟨true, 0⟩ (.settled 1) (.settled 2) == .notRendered

end Fw.Gate.Settle
