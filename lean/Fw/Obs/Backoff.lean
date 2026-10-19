/-!
# `Fw.Obs.Backoff`: what console-api does when an fwcore call times out

Observed (INFERRED from `svc.sweepError` = 61 caught throws at load 110-120): under machine load a drain or replay
call to fwcore misses its per-call deadline although the child is working. Killing the child then forces a restart
and a full log replay, which adds load and makes the next call time out too (a restart storm).

The rule, decided here and run by console-api from the golden vectors of this file (a TS stand-in until the
timeout path can ask a second fwcore): the deadline of a call is stretched when the machine is loaded, and the child is
killed only when the stretched deadline has passed. At low load the rule is today's: kill at the first deadline.

* `loadHigh`: the floor of the 1-min load average from which the machine counts as loaded.
* `extra`: how many more base deadlines a call may wait when loaded (the total is `(1 + extra)` base deadlines).
-/

namespace Fw.Obs.Backoff

/-- The thresholds of the rule: `(L, e) ∈ ℕ × ℕ`, with defaults `L = 50`, `e = 2`. -/
structure Params where
  loadHigh : Nat := 50
  extra    : Nat := 2
deriving DecidableEq, Repr

/-- What the caller does at a deadline: kill the child and restart it (replaying the log), or keep waiting `ms` more. -/
inductive Decision where
  | restart
  | wait (ms : Nat)
deriving DecidableEq, Repr

/-- The total time a call of base deadline `b` may wait at load `λ`: `b` when the machine is not loaded,
`(1 + e) b` when it is.
-/
def totalMs (p : Params) (load base : Nat) : Nat :=
  if p.loadHigh ≤ load then (1 + p.extra) * base else base

/-- The decision at a deadline that fired after `waited` ms: wait for the rest of the total when `waited` is short of it,
else restart.
-/
def onTimeout (p : Params) (load base waited : Nat) : Decision :=
  if waited < totalMs p load base then .wait (totalMs p load base - waited) else .restart

/-- The total wait is never below the base deadline. -/
theorem base_le_total (p : Params) (load base : Nat) : base ≤ totalMs p load base := by
  unfold totalMs
  split
  · exact Nat.le_mul_of_pos_left base (by omega)
  · exact Nat.le_refl _

/-- A heavier load never shortens the total wait. -/
theorem total_mono (p : Params) (base : Nat) {l1 l2 : Nat} (h : l1 ≤ l2) :
    totalMs p l1 base ≤ totalMs p l2 base := by
  unfold totalMs
  by_cases h1 : p.loadHigh ≤ l1
  · have h2 : p.loadHigh ≤ l2 := Nat.le_trans h1 h
    simp [h1, h2]
  · by_cases h2 : p.loadHigh ≤ l2
    · simp only [h1, h2, ite_true, ite_false]
      exact Nat.le_mul_of_pos_left base (by omega)
    · simp [h1, h2]

/-- **Not loaded: today's rule.** Below `loadHigh` the child is restarted at the first deadline (the call has waited its
base deadline).
-/
theorem restart_when_not_loaded (p : Params) (load base waited : Nat) (hl : load < p.loadHigh)
    (hw : base ≤ waited) : onTimeout p load base waited = .restart := by
  have : ¬ p.loadHigh ≤ load := by omega
  simp [onTimeout, totalMs, this, Nat.not_lt.2 hw]

/-- **Loaded: wait, do not kill.** At `loadHigh` or above, a call that has waited less than the stretched total gets the
rest of it.
-/
theorem wait_when_loaded (p : Params) (load base waited : Nat) (hl : p.loadHigh ≤ load)
    (hw : waited < (1 + p.extra) * base) :
    onTimeout p load base waited = .wait ((1 + p.extra) * base - waited) := by
  simp [onTimeout, totalMs, hl, hw]

/-- **A hung child is still killed.** Once the call has waited the total, the decision is restart, at any load. -/
theorem restart_after_total (p : Params) (load base waited : Nat) (h : totalMs p load base ≤ waited) :
    onTimeout p load base waited = .restart := by
  simp [onTimeout, Nat.not_lt.2 h]

/-- **Never killed before its base deadline.** A call that has waited less than its base deadline is not restarted. -/
theorem no_restart_early (p : Params) (load base waited : Nat) (h : waited < base) :
    onTimeout p load base waited ≠ .restart := by
  have := base_le_total p load base
  simp [onTimeout, Nat.lt_of_lt_of_le h this]

/-- **A wait ends in a restart.** When the decision is to wait `m` ms, firing again after those `m` ms (same load)
restarts: at most one wait per call.
-/
theorem wait_then_restart (p : Params) (load base waited m : Nat) (h : onTimeout p load base waited = .wait m) :
    onTimeout p load base (waited + m) = .restart := by
  unfold onTimeout at h ⊢
  split at h
  · rename_i hlt
    simp only [Decision.wait.injEq] at h
    apply restart_after_total
    omega
  · cases h

/-- **A wait is positive.** The ms to wait are never 0 (no immediate re-fire loop). -/
theorem wait_pos (p : Params) (load base waited m : Nat) (h : onTimeout p load base waited = .wait m) : 0 < m := by
  unfold onTimeout at h
  split at h
  · rename_i hlt
    simp only [Decision.wait.injEq] at h
    omega
  · cases h

#guard onTimeout {} 0 10000 10000 == .restart
#guard onTimeout {} 49 10000 10000 == .restart
#guard onTimeout {} 50 10000 10000 == .wait 20000
#guard onTimeout {} 115 10000 10000 == .wait 20000
#guard onTimeout {} 115 10000 30000 == .restart
#guard onTimeout {} 115 10000 29999 == .wait 1
#guard onTimeout {} 3 10000 30000 == .restart
#guard onTimeout { extra := 0 } 115 10000 10000 == .restart
#guard onTimeout { loadHigh := 10, extra := 5 } 10 1000 1000 == .wait 5000

end Fw.Obs.Backoff
