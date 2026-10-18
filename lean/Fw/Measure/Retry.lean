/-!
# Retry policy for transient simulator errors (task sim-transient-retry)

A `simctl` call on a loaded CI runner can fail for a reason that has nothing to do with the page: it
times out (`ETIMEDOUT`, the call was killed after its deadline), the Simulator is still booting
("Unable to boot device"), the device is busy, or the CoreSimulator service connection drops. Run
39068024107 (step-align, WebKit Simulator) lost more than an hour to one such timeout that was never
asked again. Any other failure (a bad device id, a missing runtime, an unknown app) will fail the
same way each time, so asking again only wastes the runner's minutes.

The policy, decided here and used by the TypeScript glue through goldens (`measure.retry`,
`measure.retryPlan`):

* an error message is **transient** when, ignoring ASCII case, it contains one of the markers in
  `transientMarkers`; every other message is **permanent**;
* after the `a`-th attempt failed (`a ≥ 1`) with a limit of `n` attempts, ask again iff the error is
  transient and `a < n`;
* the wait before the next attempt is `min(cap, base · 2^(a-1))` ms: doubling, never above `cap`.

Proved: every failure sequence stops (`retry_terminates`: at most `n - a` further attempts, whatever
the errors), a permanent error is never retried and ends a plan at once (`permanent_never_retried`,
`plan_permanent`), a run of transient errors uses the whole budget and no more
(`plan_transient_exact`), and every wait is between `base` and `cap` (`delay_le_cap`, `delay_ge_base`),
so the total wait is below `n · cap` (`plan_wait_le`).
-/
namespace Fw.Measure.Retry

/-! ## Classification -/

/-- The class of an error message.

$$\mathrm{ErrClass} = \{\mathrm{transient},\ \mathrm{permanent}\}$$
-/
inductive ErrClass where
  | transient
  | permanent
  deriving DecidableEq, Repr

/-- Lower-case substrings (ASCII) that mark an error as transient: the exit state of `simctl` when its
deadline passed (`ETIMEDOUT`, `timed out`), a device that is not ready yet (`unable to boot`, `device
busy`, `resource temporarily unavailable`, `eagain`, `ebusy`), and a lost CoreSimulator connection
(`connection invalid`, `connection interrupted`, `coresimulatorservice`).

$$M = \{\texttt{etimedout},\ \texttt{timed out},\ \texttt{unable to boot},\ \dots\}$$
-/
def transientMarkers : List String :=
  ["etimedout", "timed out", "unable to boot", "device busy", "device is busy",
   "temporarily unavailable", "eagain", "ebusy", "connection invalid", "connection interrupted",
   "coresimulatorservice"]

/-- Substring search on character lists.

$$\mathrm{infixOf}(p, s) \iff \exists u, v:\ s = u \cdot p \cdot v$$
-/
def infixOf (p : List Char) : List Char → Bool
  | [] => p.isEmpty
  | c :: cs => p.isPrefixOf (c :: cs) || infixOf p cs

/-- The message has a transient marker, ignoring ASCII case.

$$\mathrm{hasMarker}(e) \iff \exists m \in M:\ m \ne \texttt{""} \land \mathrm{infixOf}(m, \mathrm{lower}(e))$$
-/
def hasMarker (e : String) : Bool :=
  let l := e.toLower.toList
  transientMarkers.any fun m => !m.isEmpty && infixOf m.toList l

/-- The class of an error message.

$$\mathrm{classify}(e) = \begin{cases} \mathrm{transient} & \mathrm{hasMarker}(e) \\ \mathrm{permanent} & \text{otherwise}\end{cases}$$
-/
def classify (e : String) : ErrClass := if hasMarker e then .transient else .permanent

#guard classify "ETIMEDOUT" == .transient
#guard classify "simctl bootstatus failed: Unable to boot device in current state: Booted" == .transient
#guard classify "Invalid device: nope" == .permanent
#guard classify "" == .permanent

/-! ## Decision and backoff -/

/-- Ask again: the error is transient and fewer than `n` attempts were made. `a` = attempts made so
far (the one that just failed included), `n` = the limit.

$$\mathrm{shouldRetry}(c, a, n) \iff c = \mathrm{transient} \land a < n$$
-/
def shouldRetry (c : ErrClass) (a n : Nat) : Bool := decide (c = .transient) && decide (a < n)

/-- Wait in ms before attempt `a + 1`: doubling from `base`, never above `cap`.

$$\mathrm{delay}(a) = \min\!\big(\mathit{cap},\ \mathit{base} \cdot 2^{\max(a,1) - 1}\big)$$
-/
def delay (base cap a : Nat) : Nat := min cap (base * 2 ^ (a - 1))

/-- Wait in ms for attempt `a` under the shipped constants: base 2,000, cap 30,000.

$$\mathrm{wait}(a) = \mathrm{delay}(2000,\ 30000,\ a)$$
-/
def wait (a : Nat) : Nat := delay 2000 30000 a

#guard wait 1 == 2000
#guard wait 2 == 4000
#guard wait 5 == 30000
#guard wait 40 == 30000

/-! ## The retry plan of a failure sequence -/

/-- How a plan ended: the sequence of errors ended before the policy stopped (the next attempt worked),
the limit was reached with a transient error, or a permanent error stopped it.

$$\mathrm{Outcome} = \{\mathrm{succeeded},\ \mathrm{exhausted},\ \mathrm{permanent}\}$$
-/
inductive Outcome where
  | succeeded
  | exhausted
  | permanent
  deriving DecidableEq, Repr

/-- The waits taken, one per retry, when attempt `a, a+1, …` fail with the errors `cs` (the attempt
after the last error succeeds). Structural in `cs`, hence total.

$$\mathrm{plan}(n, c_a \ldots c_k, a) = \begin{cases} \mathrm{wait}(a) :: \mathrm{plan}(n, c_{a+1} \ldots, a+1) & \mathrm{shouldRetry}(c_a, a, n) \\ [\,] & \text{otherwise} \end{cases}$$
-/
def plan (n : Nat) : List ErrClass → Nat → List Nat
  | [], _ => []
  | c :: cs, a => if shouldRetry c a n then wait a :: plan n cs (a + 1) else []

/-- How the plan ends: `succeeded` when the errors ran out while being retried, else the reason the
policy stopped.

$$\mathrm{outcome}(n, c_a \ldots, a)\ \text{follows the same recursion as } \mathrm{plan}$$
-/
def outcome (n : Nat) : List ErrClass → Nat → Outcome
  | [], _ => .succeeded
  | c :: cs, a => if shouldRetry c a n then outcome n cs (a + 1) else
      (if c = .transient then .exhausted else .permanent)

#guard plan 3 [.transient, .transient, .transient] 1 == [2000, 4000]
#guard outcome 3 [.transient, .transient, .transient] 1 == .exhausted
#guard outcome 3 [.transient] 1 == .succeeded
#guard plan 3 [.permanent, .transient] 1 == []
#guard outcome 3 [.permanent] 1 == .permanent

/-! ## Theorems -/

/-- A permanent error is never retried, for any attempt count and limit.

$$\forall a, n \in \mathbb{N}:\ \mathrm{shouldRetry}(\mathrm{permanent}, a, n) = \mathrm{false}$$
-/
theorem permanent_never_retried (a n : Nat) : shouldRetry .permanent a n = false := by
  simp [shouldRetry]

/-- A plan whose first error is permanent takes no wait and ends as `permanent`.

$$\forall n, a, cs:\ \mathrm{plan}(n, \mathrm{permanent} :: cs, a) = [\,] \ \land\ \mathrm{outcome}(n, \mathrm{permanent} :: cs, a) = \mathrm{permanent}$$
-/
theorem plan_permanent (n a : Nat) (cs : List ErrClass) :
    plan n (.permanent :: cs) a = [] ∧ outcome n (.permanent :: cs) a = .permanent := by
  simp [plan, outcome, permanent_never_retried]

/-- A retry needs a transient error and attempts left.

$$\mathrm{shouldRetry}(c, a, n) = \mathrm{true} \iff c = \mathrm{transient} \land a < n$$
-/
theorem shouldRetry_iff (c : ErrClass) (a n : Nat) :
    shouldRetry c a n = true ↔ c = .transient ∧ a < n := by
  simp [shouldRetry]

/-- Every failure sequence stops: from attempt `a` with limit `n`, whatever the errors, the number of
retries is at most `n - a` (zero when `a ≥ n`), so the total number of attempts is at most
`max(a, n)`.

$$\forall n, a, cs:\ |\mathrm{plan}(n, cs, a)| \le n - a \ \land\ a + |\mathrm{plan}(n, cs, a)| \le \max(a, n)$$
-/
theorem retry_terminates (n : Nat) (cs : List ErrClass) (a : Nat) :
    (plan n cs a).length ≤ n - a ∧ a + (plan n cs a).length ≤ max a n := by
  induction cs generalizing a with
  | nil => simp [plan]; omega
  | cons c cs ih =>
    unfold plan
    by_cases h : shouldRetry c a n = true
    · have ha : a < n := ((shouldRetry_iff c a n).1 h).2
      have := ih (a + 1)
      simp [h]
      omega
    · simp [h]
      omega

/-- A run of transient errors uses the whole budget and no more: `k` transient errors from attempt `a`
give `min(k, n - a)` retries.

$$\forall n, a, k:\ |\mathrm{plan}(n, \mathrm{transient}^k, a)| = \min(k,\ n - a)$$
-/
theorem plan_transient_exact (n a k : Nat) :
    (plan n (List.replicate k .transient) a).length = min k (n - a) := by
  induction k generalizing a with
  | zero => simp [plan]
  | succ k ih =>
    simp only [List.replicate_succ, plan]
    by_cases h : a < n
    · have hs : shouldRetry .transient a n = true := by simp [shouldRetry, h]
      simp [hs, ih]
      omega
    · have hs : shouldRetry .transient a n = false := by simp [shouldRetry, h]
      simp [hs]
      omega

/-- Every wait is at most the cap.

$$\forall \mathit{base}, \mathit{cap}, a:\ \mathrm{delay}(\mathit{base}, \mathit{cap}, a) \le \mathit{cap}$$
-/
theorem delay_le_cap (base cap a : Nat) : delay base cap a ≤ cap := by
  exact Nat.min_le_left _ _

/-- Every wait is at least the base, when the cap allows.

$$\forall \mathit{base} \le \mathit{cap}, a:\ \mathit{base} \le \mathrm{delay}(\mathit{base}, \mathit{cap}, a)$$
-/
theorem delay_ge_base (base cap a : Nat) (h : base ≤ cap) : base ≤ delay base cap a := by
  have : 1 ≤ 2 ^ (a - 1) := Nat.one_le_two_pow
  have : base ≤ base * 2 ^ (a - 1) := Nat.le_mul_of_pos_right base this
  simp [delay]
  omega

/-- The wait never shrinks as the attempts go on.

$$\forall a \le b:\ \mathrm{delay}(\mathit{base}, \mathit{cap}, a) \le \mathrm{delay}(\mathit{base}, \mathit{cap}, b)$$
-/
theorem delay_mono (base cap : Nat) {a b : Nat} (h : a ≤ b) : delay base cap a ≤ delay base cap b := by
  unfold delay
  have : 2 ^ (a - 1) ≤ 2 ^ (b - 1) := Nat.pow_le_pow_right (by decide) (by omega)
  have h2 := Nat.mul_le_mul_left base this
  omega

/-- Each wait of a plan is at most the shipped cap, so the total wait is below `n · 30,000` ms.

$$\forall n, a, cs:\ \sum \mathrm{plan}(n, cs, a) \le 30000 \cdot (n - a)$$
-/
theorem plan_wait_le (n : Nat) (cs : List ErrClass) (a : Nat) :
    (plan n cs a).sum ≤ 30000 * (n - a) := by
  induction cs generalizing a with
  | nil => simp [plan]
  | cons c cs ih =>
    unfold plan
    by_cases h : shouldRetry c a n = true
    · have ha : a < n := ((shouldRetry_iff c a n).1 h).2
      have h1 := ih (a + 1)
      have h2 : wait a ≤ 30000 := delay_le_cap 2000 30000 a
      simp [h]
      omega
    · simp [h]

/-- A message with no marker is permanent, and one with a marker is transient.

$$\mathrm{classify}(e) = \mathrm{transient} \iff \mathrm{hasMarker}(e)$$
-/
theorem classify_transient_iff (e : String) : classify e = .transient ↔ hasMarker e = true := by
  unfold classify
  by_cases h : hasMarker e = true <;> simp [h]

end Fw.Measure.Retry
