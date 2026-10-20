/-!
# `Fw.Obs.Backoff`: what console-api does when an fwcore call times out

Observed (INFERRED from `svc.sweepError` = 61 caught throws at load 110-120): under machine load a drain or replay
call to fwcore misses its per-call deadline although the child is working. Killing the child then forces a restart
and a full log replay, which adds load and makes the next call time out too (a restart storm).

The rule, decided here and run by console-api from the golden vectors of this file (a TS stand-in until the
timeout path can ask a second fwcore): the deadline of a call is stretched when the machine is loaded, and the child is
killed only when the stretched deadline has passed. A machine is loaded when its 1-min load average, floored, is at least
its core count: that many runnable tasks leave no core free for the child. Not loaded, the rule is the plain one: kill at
the first deadline. The threshold follows the machine (a fixed 50 never fired on 8 cores at load 10-15, where a log
replay of 14 s still timed out).

* `cores`: the number of CPU cores of the machine (a count of 0 is read as 1).
* `extra`: how many more base deadlines a call may wait when loaded (the total is `(1 + extra)` base deadlines).
-/

namespace Fw.Obs.Backoff

/-- The parameter of the rule: `e ∈ ℕ`, with default `e = 2`. -/
structure Params where
  extra    : Nat := 2
deriving DecidableEq, Repr

/-- What the caller does at a deadline: kill the child and restart it (replaying the log), or keep waiting `ms` more. -/
inductive Decision where
  | restart
  | wait (ms : Nat)
deriving DecidableEq, Repr

/-- The machine is loaded: the floor of its 1-min load average `λ` is at least its core count `c` (at least 1). -/
def loaded (cores load : Nat) : Bool := decide (max 1 cores ≤ load)

/-- The total time a call of base deadline `b` may wait at load `λ` on `c` cores: `b` when the machine is not loaded,
`(1 + e) b` when it is.
-/
def totalMs (p : Params) (cores load base : Nat) : Nat :=
  if loaded cores load then (1 + p.extra) * base else base

/-- The decision at a deadline that fired after `waited` ms: wait for the rest of the total when `waited` is short of it,
else restart.
-/
def onTimeout (p : Params) (cores load base waited : Nat) : Decision :=
  if waited < totalMs p cores load base then .wait (totalMs p cores load base - waited) else .restart

/-- The total wait is never below the base deadline. -/
theorem base_le_total (p : Params) (cores load base : Nat) : base ≤ totalMs p cores load base := by
  unfold totalMs
  split
  · exact Nat.le_mul_of_pos_left base (by omega)
  · exact Nat.le_refl _

/-- A heavier load never shortens the total wait. -/
theorem total_mono (p : Params) (cores : Nat) (base : Nat) {l1 l2 : Nat} (h : l1 ≤ l2) :
    totalMs p cores l1 base ≤ totalMs p cores l2 base := by
  unfold totalMs loaded
  by_cases h1 : max 1 cores ≤ l1
  · have h2 : max 1 cores ≤ l2 := Nat.le_trans h1 h
    simp [h1, h2]
  · by_cases h2 : max 1 cores ≤ l2
    · simp only [h1, h2, decide_true, decide_false, ite_true]
      exact Nat.le_mul_of_pos_left base (by omega)
    · simp [h1, h2]

/-- A machine with more cores is loaded later: the total wait never shrinks as cores are added. -/
theorem total_mono_cores (p : Params) (load base : Nat) {c1 c2 : Nat} (h : c1 ≤ c2) :
    totalMs p c2 load base ≤ totalMs p c1 load base := by
  unfold totalMs loaded
  by_cases h1 : max 1 c1 ≤ load
  · by_cases h2 : max 1 c2 ≤ load
    · simp [h1, h2]
    · simp only [h2, decide_false, h1, decide_true, ite_true]
      exact Nat.le_mul_of_pos_left base (by omega)
  · have h2 : ¬ max 1 c2 ≤ load := by omega
    simp [h1, h2]

/-- **Not loaded: the plain rule.** With fewer runnable tasks than cores the child is restarted at the first deadline (the
call has waited its base deadline).
-/
theorem restart_when_not_loaded (p : Params) (cores load base waited : Nat) (hl : load < max 1 cores)
    (hw : base ≤ waited) : onTimeout p cores load base waited = .restart := by
  have : loaded cores load = false := by simp [loaded]; omega
  simp [onTimeout, totalMs, this, Nat.not_lt.2 hw]

/-- **Loaded: wait, do not kill.** At `cores` runnable tasks or more, a call that has waited less than the stretched total
gets the rest of it.
-/
theorem wait_when_loaded (p : Params) (cores load base waited : Nat) (hl : max 1 cores ≤ load)
    (hw : waited < (1 + p.extra) * base) :
    onTimeout p cores load base waited = .wait ((1 + p.extra) * base - waited) := by
  have : loaded cores load = true := by simp [loaded, hl]
  simp [onTimeout, totalMs, this, hw]

/-- **A hung child is still killed.** Once the call has waited the total, the decision is restart, at any load. -/
theorem restart_after_total (p : Params) (cores load base waited : Nat) (h : totalMs p cores load base ≤ waited) :
    onTimeout p cores load base waited = .restart := by
  simp [onTimeout, Nat.not_lt.2 h]

/-- **Never killed before its base deadline.** A call that has waited less than its base deadline is not restarted. -/
theorem no_restart_early (p : Params) (cores load base waited : Nat) (h : waited < base) :
    onTimeout p cores load base waited ≠ .restart := by
  have := base_le_total p cores load base
  simp [onTimeout, Nat.lt_of_lt_of_le h this]

/-- **A wait ends in a restart.** When the decision is to wait `m` ms, firing again after those `m` ms (same load)
restarts: at most one wait per call.
-/
theorem wait_then_restart (p : Params) (cores load base waited m : Nat)
    (h : onTimeout p cores load base waited = .wait m) : onTimeout p cores load base (waited + m) = .restart := by
  unfold onTimeout at h ⊢
  split at h
  · rename_i hlt
    simp only [Decision.wait.injEq] at h
    apply restart_after_total
    omega
  · cases h

/-- **A wait is positive.** The ms to wait are never 0 (no immediate re-fire loop). -/
theorem wait_pos (p : Params) (cores load base waited m : Nat) (h : onTimeout p cores load base waited = .wait m) :
    0 < m := by
  unfold onTimeout at h
  split at h
  · rename_i hlt
    simp only [Decision.wait.injEq] at h
    omega
  · cases h

/-- **The 2026-10-20 incident.** On 8 cores at load 10 a call that missed its 10 s deadline waits (the old fixed
threshold of 50 would have killed the child). -/
theorem incident_8_cores : onTimeout {} 8 10 10000 10000 = .wait 20000 := by decide

#guard onTimeout {} 8 3 10000 10000 == .restart
#guard onTimeout {} 8 7 10000 10000 == .restart
#guard onTimeout {} 8 8 10000 10000 == .wait 20000
#guard onTimeout {} 8 12 10000 10000 == .wait 20000
#guard onTimeout {} 8 12 10000 30000 == .restart
#guard onTimeout {} 8 12 10000 29999 == .wait 1
#guard onTimeout {} 8 3 10000 30000 == .restart
#guard onTimeout { extra := 0 } 8 12 10000 10000 == .restart
#guard onTimeout { extra := 5 } 2 2 1000 1000 == .wait 5000
#guard onTimeout {} 0 1 10000 10000 == .wait 20000
#guard onTimeout {} 0 0 10000 10000 == .restart

end Fw.Obs.Backoff
