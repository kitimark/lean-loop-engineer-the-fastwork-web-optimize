/-!
# Which attempt of a run a fact belongs to (task `ci-wait-lag`)

`gh run rerun --failed` starts a new attempt of the same run id. Everything `fw ci wait` keeps per run id (the jobs
of a finished run, a run's list row) was read at one attempt. After a rerun, `fw ci wait <id>` returned the failure
of attempt 1 while attempt 2 was still running (run 39363764375). Here the verdict is keyed on the attempt: a recorded
fact answers for a run only while the run is still on the attempt it was recorded at.

Five rules, each decided here and called through fwcore's op `ci.attempt` (`Fw.Wire.Ci`):
- `reuse`: a cached fact is reused when it and the live run name the same attempt;
- `settled`: jobs fetched for a listed row decide when the row names no attempt (a file written before the list carried
  it) or the same attempt as the jobs view;
- `current`: a row is current when its attempt is at least the newest attempt a view has shown for the run;
- `fresh`: a finished row kept in the meta cache answers only for waiters that start together with the view that
  read it (`freshS` seconds); a later wait reads the run again, since a rerun may have started since.
- `trusted` (task `gh-budget-fresh-inflight`): a cached row answers by its own rule: a finished row by `fresh`, a row
  that is still queued or in progress only within `inflightS` of its view, so a row read hours ago never keeps a wait
  pending on a run that has long finished (incident 2026-10-26: 47 such rows held `fw ci wait` to its 4 h cap);
- `uncoveredExit`: a run whose watch the poller dropped as `uncovered` (older than its list window) twice ends the
  wait with exit code `uncoveredCode` instead of polling to the cap.
- `jobsSettled` (task `macos-telemetry`): a jobs view decides only when every job has a conclusion, or the run finished
  `jobsGraceS` ago. GitHub sets the conclusion of a matrix job a moment after the run is marked completed; a view in that
  moment read an open job as `""`, which the verdict folds to failure, and the facts were cached for good
  (run 39629760037 printed `success -> fail`: MEASURED from the cached jobs file, 1 of 10 jobs open).
-/
namespace Fw.Ci.Attempt

/-- A cached fact is reused only when both the record and the live run name an attempt and it is the same one. -/
def reuse (recorded live : Option Nat) : Bool :=
  match recorded, live with
  | some a, some b => a == b
  | _, _ => false

/-- A jobs view settles a listed row when the row names no attempt, or the view names the same one. -/
def settled (row : Option Nat) (view : Nat) : Bool :=
  match row with
  | none => true
  | some r => r == view

/-- A row is current when its attempt is at least the floor (the newest attempt any view showed); a row naming no
attempt is current only while the floor is still 0 (no view has shown an attempt). -/
def current (floor : Nat) (row : Option Nat) : Bool :=
  match row with
  | none => floor == 0
  | some r => decide (floor ≤ r)

/-- Seconds a finished row stays valid in the meta cache: waiters started together share one view, a later wait
reads the run again (a rerun starts new attempts minutes after the failure, not within this window of a view). -/
def freshS : Nat := 30

/-- A finished row read at `read` is still shared at `now`. -/
def fresh (read now : Nat) : Bool := decide (now ≤ read + freshS)

/-- Seconds a row that is still queued or in progress may be trusted after the view that read it (INFERRED: a run's state
changes within minutes; a waiter that starts later reads the run again, one charged view). -/
def inflightS : Nat := 300

/-- Whether a cached row answers a wait: a finished row by `fresh`, an unfinished row for `inflightS` seconds. -/
def trusted (completed : Bool) (read now : Nat) : Bool :=
  if completed then fresh read now else decide (now ≤ read + inflightS)

/-- **A finished row keeps its rule**: `trusted` is `fresh`. -/
theorem trusted_completed (r t : Nat) : trusted true r t = fresh r t := rfl

/-- **An unfinished row is trusted inside its bound.** -/
theorem trusted_inflight_young (r t : Nat) (h : t ≤ r + inflightS) : trusted false r t = true := by
  simp [trusted]; omega

/-- **An unfinished row older than its bound is never trusted**: the wait reads the run again. -/
theorem trusted_inflight_stale (r t : Nat) (h : r + inflightS < t) : trusted false r t = false := by
  simp [trusted]; omega

/-- **No row is trusted past the longer of the two windows.** -/
theorem trusted_old_never (c : Bool) (r t : Nat) (h : r + inflightS < t) : trusted c r t = false := by
  cases c
  · exact trusted_inflight_stale r t h
  · have h' : r + freshS < t := by simp [freshS, inflightS] at *; omega
    simp only [trusted, fresh]; simp; omega

/-- Incidents of one run (`uncovered`, written by the poller) that end a wait; one can be a passing window edge. -/
def uncoveredMax : Nat := 2

/-- The exit code of a wait ended by repeated `uncovered` incidents (3 is a timeout or a budget stop, 5 is gh unavailable for the land lanes). -/
def uncoveredCode : Nat := 6

/-- A wait ends when `n` `uncovered` incidents of its run were logged since the wait began. -/
def uncoveredExit (n : Nat) : Bool := decide (uncoveredMax ≤ n)

/-- **One `uncovered` incident does not end a wait.** -/
theorem uncovered_once_waits : uncoveredExit 1 = false := rfl

/-- **A repeated `uncovered` incident ends the wait.** -/
theorem uncovered_repeated_exits (n : Nat) (h : 2 ≤ n) : uncoveredExit n = true := by
  exact decide_eq_true (by simpa [uncoveredMax] using h)

/-- **The exit code is neither the timeout code nor the gh-unavailable code**: a caller can tell them apart. -/
theorem uncoveredCode_ne_timeout : uncoveredCode ≠ 3 ∧ uncoveredCode ≠ 5 := by decide

/-- Seconds after a run finished within which an open job conclusion is lag, not a fact (INFERRED: the lag seen was seconds). -/
def jobsGraceS : Nat := 300

/-- A jobs view decides when no job is open (no conclusion yet) or the run finished more than `jobsGraceS` s ago. -/
def jobsSettled (openJobs ago : Nat) : Bool := openJobs == 0 || decide (jobsGraceS < ago)

/-- **A view with every conclusion present always decides.** -/
theorem jobsSettled_closed (ago : Nat) : jobsSettled 0 ago = true := rfl

/-- **An open job right after the finish does not decide**: the view is read again, never cached. -/
theorem jobsSettled_open_young (n ago : Nat) (hn : n ≠ 0) (ha : ago ≤ jobsGraceS) : jobsSettled n ago = false := by
  simp [jobsSettled, hn]; omega

/-- **An open job long after the finish decides** (the run is as it is; the old behaviour). -/
theorem jobsSettled_open_old (n ago : Nat) (ha : jobsGraceS < ago) : jobsSettled n ago = true := by
  simp [jobsSettled, ha]

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

#guard trusted false 100 400 == true
#guard trusted false 100 401 == false
#guard trusted true 100 130 == true
#guard trusted true 100 131 == false
#guard uncoveredExit 1 == false
#guard uncoveredExit 2 == true

#guard jobsSettled 0 0 == true
#guard jobsSettled 1 0 == false
#guard jobsSettled 1 300 == false
#guard jobsSettled 1 301 == true
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
