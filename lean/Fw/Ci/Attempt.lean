/-!
# Which attempt of a run a fact belongs to (task `ci-wait-lag`)

`gh run rerun --failed` starts a new attempt of the same run id. Everything `fw ci wait` keeps per run id (the jobs
of a finished run, a run's list row) was read at one attempt. After a rerun, `fw ci wait <id>` returned the failure
of attempt 1 while attempt 2 was still running (run 39363764375). Here the verdict is keyed on the attempt: a recorded
fact answers for a run only while the run is still on the attempt it was recorded at.

Three rules, each decided here and called through fwcore's op `ci.attempt` (`Fw.Wire.Ci`):
- `reuse`: a cached fact is reused when it and the live run name the same attempt;
- `settled`: jobs fetched for a listed row decide when the row names no attempt (a file written before the list carried
  it) or the same attempt as the jobs view;
- `current`: a row is current when its attempt is at least the newest attempt a view has shown for the run;
- `fresh`: a finished row kept in the meta cache answers only for waiters that start together with the view that
  read it (`freshS` seconds); a later wait reads the run again, since a rerun may have started since.
-/
namespace Fw.Ci.Attempt

/-- A cached fact is reused only when both the record and the live run name an attempt and it is the same one.
$$\forall a, b:\ \operatorname{reuse}(a, b) \iff \exists n:\ a = \mathrm{some}(n) \land b = \mathrm{some}(n)$$ -/
def reuse (recorded live : Option Nat) : Bool :=
  match recorded, live with
  | some a, some b => a == b
  | _, _ => false

/-- A jobs view settles a listed row when the row names no attempt, or the view names the same one.
$$\forall r, v:\ \operatorname{settled}(r, v) \iff r = \mathrm{none} \lor r = \mathrm{some}(v)$$ -/
def settled (row : Option Nat) (view : Nat) : Bool :=
  match row with
  | none => true
  | some r => r == view

/-- A row is current when its attempt is at least the floor (the newest attempt any view showed); a row naming no
attempt is current only while the floor is still 0 (no view has shown an attempt).
$$\forall f, r:\ \operatorname{current}(f, r) \iff \exists n:\ r = \mathrm{some}(n) \land f \le n,\ \text{or}\ r = \mathrm{none} \land f = 0$$ -/
def current (floor : Nat) (row : Option Nat) : Bool :=
  match row with
  | none => floor == 0
  | some r => decide (floor ≤ r)

/-- Seconds a finished row stays valid in the meta cache: waiters started together share one view, a later wait
reads the run again (a rerun starts new attempts minutes after the failure, not within this window of a view). -/
def freshS : Nat := 30

/-- A finished row read at `read` is still shared at `now`.
$$\forall r, t:\ \operatorname{fresh}(r, t) \iff t \le r + 30$$ -/
def fresh (read now : Nat) : Bool := decide (now ≤ read + freshS)

/-- **A cache from another attempt is never reused.** -/
theorem reuse_other_attempt (a b : Nat) (h : a ≠ b) : reuse (some a) (some b) = false := by
  simp [reuse, h]

/-- **A cache with no recorded attempt is never reused.** -/
theorem reuse_unrecorded (live : Option Nat) : reuse none live = false := by
  cases live <;> rfl

/-- **A cache is reused only for the attempt it was recorded at.** -/
theorem reuse_iff (a : Option Nat) (b : Option Nat) :
    reuse a b = true ↔ ∃ n, a = some n ∧ b = some n := by
  cases a <;> cases b <;> simp [reuse] <;> exact eq_comm

/-- **A newer attempt unsettles the row.** If the view names an attempt other than the row's, the row does not settle. -/
theorem newer_attempt_unsettles (r v : Nat) (h : r ≠ v) : settled (some r) v = false := by
  simp [settled, h]

/-- **An unnumbered row settles** (a status file written before the list carried the attempt). -/
theorem unnumbered_settles (v : Nat) : settled none v = true := rfl

/-- **A row under the floor is not current**: a finished attempt 1 is not the verdict once attempt 2 was seen. -/
theorem below_floor_not_current (f r : Nat) (h : r < f) : current f (some r) = false := by
  simp [current]; omega

/-- **Nothing seen, nothing refused**: with the floor at 0 every row is current. -/
theorem floor_zero_current (r : Option Nat) : current 0 r = true := by
  cases r <;> simp [current]

/-- **A finished row is shared at the moment of the view.** -/
theorem fresh_at_read (r : Nat) : fresh r r = true := by
  simp [fresh]

/-- **A finished row is not shared after the window.** -/
theorem stale_after_window (r t : Nat) (h : r + freshS < t) : fresh r t = false := by
  simp [fresh]; omega

#guard fresh 100 130 == true
#guard fresh 100 131 == false
#guard reuse (some 1) (some 1) == true
#guard reuse (some 1) (some 2) == false
#guard reuse none (some 1) == false
#guard reuse (some 1) none == false
#guard settled none 2 == true
#guard settled (some 1) 2 == false
#guard settled (some 2) 2 == true
#guard current 2 (some 1) == false
#guard current 2 (some 2) == true
#guard current 2 none == false
#guard current 0 none == true

end Fw.Ci.Attempt
