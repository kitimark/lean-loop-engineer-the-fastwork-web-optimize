import Fw.Console.PreviewOwner

/-!
# The console as a background process (console-daemon)

`fw console start|stop|restart|status|logs` runs console-api detached, with no terminal. This module decides what the
commands may do; the process spawn, the signals, the health request and the file append are I/O glue in `apps/runner`.

Three rules are proved. (1) A console is *verified* only when `.fw-console/api.json` names a pid and the port in that file
answers `GET /api/health` with the same pid in `x-fw-console-pid`; start is refused when one is verified and when the
recorded pid is alive but did not answer (a busy console), and the only pid `stop` may signal is the verified one. (2) The
owner signs in with the passphrase at `/owner/login`, which Lean already admits from loopback and from the LAN. (3) The log
is rotated when it reaches its size limit.

What keeps the owner link out of the log is not a rule here: `link.ts` never builds the link without a terminal
(`Fw.Console.Preview.no_file_sink`, `no_nontty_sink`), and a daemon test reads the whole log for it.

Accepted limit: rotation runs at `start` only. A console that runs for days appends to `console.log` without a bound;
`fw console status` prints the size and warns above 50 MiB.

Not proved: that the child really ignores its terminal, the health request, the signal delivery, a same-UID process that
writes to the log by itself.
-/

namespace Fw.Console.Daemon

/-! ## 1. Verified console, start, stop, restart -/

/-- The pid of a console that is running, or none. `recorded` is the pid in `api.json`; `answered` is the pid the port in
that file reports in `x-fw-console-pid` (none: nothing answered). Pid 0 and 1 are never a console. -/
def verified (recorded answered : Option Nat) : Option Nat :=
  match recorded, answered with
  | some r, some a => if r = a ∧ 1 < r then some r else none
  | _, _ => none

/-- A console that is alive but did not answer: `api.json` names a pid above 1, that process exists, and the port gave no
answer (a busy event loop). Starting then would run `reapRecorded` on its `.fw-console`. A different pid that answered is
not this case. -/
def unverifiedAlive (recorded answered : Option Nat) (alive : Bool) : Bool :=
  match recorded, answered with
  | some r, none => alive && decide (1 < r)
  | _, _ => false

/-- Start is allowed iff no console is verified and no recorded pid is alive without having answered. -/
def startAllowed (recorded answered : Option Nat) (alive : Bool) : Bool :=
  (verified recorded answered).isNone && !unverifiedAlive recorded answered alive

/-- The one pid `stop` may signal. -/
def stopTarget (recorded answered : Option Nat) : Option Nat := verified recorded answered

/-- One step of a restart. -/
inductive Step where
  | stop (pid : Nat)
  | start
deriving Repr, DecidableEq

/-- Restart: stop the verified console if there is one, then start. -/
def restartPlan (v : Option Nat) : List Step :=
  match v with
  | some p => [.stop p, .start]
  | none => [.start]

/-- A verified pid is the recorded one, the answered one, and above 1. -/
theorem verified_some (r a : Option Nat) (p : Nat) (h : verified r a = some p) :
    r = some p ∧ a = some p ∧ 1 < p := by
  unfold verified at h
  split at h
  · rename_i r' a'
    split at h
    · rename_i hc
      obtain ⟨h1, h2⟩ := hc
      have : r' = p := by simpa using h
      subst this; subst h1
      exact ⟨rfl, rfl, h2⟩
    · simp at h
  · simp at h

/-- **Start is refused when a console is verified.** -/
theorem start_refused_when_verified (r a : Option Nat) (alive : Bool) (p : Nat) (h : verified r a = some p) :
    startAllowed r a alive = false := by
  simp [startAllowed, h]

/-- **Start is refused when the recorded pid is alive and did not answer.** -/
theorem start_refused_unverified_alive (r : Nat) (hr : 1 < r) :
    startAllowed (some r) none true = false := by
  simp [startAllowed, unverifiedAlive, verified, hr]

/-- A recorded pid that is not alive (a stale file) does not block start. -/
theorem start_allowed_stale (r : Option Nat) : startAllowed r none false = true := by
  cases r <;> simp [startAllowed, unverifiedAlive, verified]

/-- Nothing recorded: start is allowed whatever answered, whatever is alive. -/
theorem start_allowed_unrecorded (a : Option Nat) (alive : Bool) : startAllowed none a alive = true := by
  cases a <;> simp [startAllowed, unverifiedAlive, verified]

/-- A different pid answered on the recorded port: start is allowed. -/
theorem start_allowed_other_answered (x y : Nat) (alive : Bool) (h : x ≠ y) : startAllowed (some x) (some y) alive = true := by
  simp [startAllowed, unverifiedAlive, verified, h]

/-- Pid 1 is never a console: it blocks nothing even when it is alive. -/
theorem start_allowed_pid_one (alive : Bool) : startAllowed (some 1) none alive = true := by
  simp [startAllowed, unverifiedAlive, verified]

/-- **Stop signals only the verified pid.** A pid it may signal is the recorded one, the one that answered the health
request, and above 1. -/
theorem stop_only_verified (r a : Option Nat) (p : Nat) (h : stopTarget r a = some p) :
    r = some p ∧ a = some p ∧ 1 < p := verified_some r a p h

/-- Nothing answered: nothing is signalled (a stale `api.json`, a crashed console). -/
theorem stop_unanswered (r : Option Nat) : stopTarget r none = none := by
  cases r <;> simp [stopTarget, verified]

/-- A different pid answered on the recorded port (the pid was reused): nothing is signalled. -/
theorem stop_pid_mismatch (x y : Nat) (h : x ≠ y) : stopTarget (some x) (some y) = none := by
  simp [stopTarget, verified, h]

/-- Nothing recorded: nothing is signalled. -/
theorem stop_unrecorded (a : Option Nat) : stopTarget none a = none := by
  cases a <;> simp [stopTarget, verified]

/-- **A restart ends in a start.** -/
theorem restart_ends_with_start (v : Option Nat) : (restartPlan v).getLast? = some .start := by
  cases v <;> simp [restartPlan]

/-- **A restart stops only the verified pid.** Every stop step names the pid of the verified console. -/
theorem restart_stops_only_verified (v : Option Nat) (p : Nat) (h : Step.stop p ∈ restartPlan v) : v = some p := by
  cases v <;> simp_all [restartPlan]

/-- With no verified console a restart is a plain start: it signals nothing. -/
theorem restart_unverified (r a : Option Nat) (h : verified r a = none) : restartPlan (verified r a) = [.start] := by
  simp [h, restartPlan]

/-! ## 2. Sign-in without a terminal -/

/-- **The passphrase login is open from loopback.** Whatever the token and Host, the login class is admitted at loopback,
so the owner of a detached console signs in at `http://127.0.0.1:<port>/owner/login`. -/
theorem login_loopback (bearer hostOk : Bool) :
    Fw.Console.Preview.Owner.allow false bearer hostOk .login = true := by
  simp [Fw.Console.Preview.Owner.allow]

/-- The login is also open from the LAN with the right Host (`Owner.login_reachable`), so both paths work with no terminal. -/
theorem login_lan_or_loopback (lan bearer : Bool) :
    Fw.Console.Preview.Owner.allow lan bearer true .login = true :=
  Fw.Console.Preview.Owner.login_reachable lan bearer

/-! ## 3. Log rotation -/

/-- The log size at which the file is rotated (bytes): 5 MiB. -/
def logLimit : Nat := 5242880

/-- The log is rotated (the file moved to `console.log.1`, a new one started) when its size has reached the limit. -/
def rotate (size limit : Nat) : Bool := decide (limit ≤ size)

/-- A log below its limit is kept. -/
theorem rotate_below (s m : Nat) (h : s < m) : rotate s m = false := by
  simp [rotate]; omega

/-- A log at its limit is rotated. -/
theorem rotate_at_limit (m : Nat) : rotate m m = true := by
  simp [rotate]

/-- The log size above which `fw console status` warns (bytes): 50 MiB. -/
def logWarnLimit : Nat := 52428800

/-- Status warns when the log is larger than the warning limit. -/
def logWarns (size : Nat) : Bool := decide (logWarnLimit < size)

/-- A log of at most 50 MiB draws no warning. -/
theorem warn_at_limit : logWarns logWarnLimit = false := by
  simp [logWarns]

/-- A log above 50 MiB draws the warning. -/
theorem warn_above_limit (s : Nat) (h : logWarnLimit < s) : logWarns s = true := by
  simp [logWarns, h]

end Fw.Console.Daemon
