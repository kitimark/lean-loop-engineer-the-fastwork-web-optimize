import Fw.Console.PreviewOwner

/-!
# The console as a background process (console-daemon)

`fw console start|stop|restart|status|logs` runs console-api detached, with no terminal. This module decides what the
commands may do; the process spawn, the signals, the health request and the file append are I/O glue in `apps/runner`.

Three rules are proved. (1) A console is *verified* only when `.fw-console/api.json` names a pid and the port in that file
answers `GET /api/health` with the same pid in `x-fw-console-pid`; start is refused exactly when one is verified, and the
only pid `stop` may signal is the verified one. (2) The log file takes no line that can carry the owner link, an owner
token, the passphrase or a keychain value; the owner signs in with the passphrase at `/owner/login`, which Lean already
admits from loopback and from the LAN. (3) The log is rotated when it reaches its size limit.

Not proved: that the child really ignores its terminal, the health request, the signal delivery, a same-UID process that
writes to the log by itself.
-/

namespace Fw.Console.Daemon

/-! ## 1. Verified console, start, stop, restart -/

/-- The pid of a console that is running, or none. `recorded` is the pid in `api.json`; `answered` is the pid the port in
that file reports in `x-fw-console-pid` (none: nothing answered). Pid 0 and 1 are never a console.

$$\operatorname{verified}(r, a) = \begin{cases}\mathrm{some}(r) & r = a \wedge 1 < r\\ \bot & \text{otherwise}\end{cases}$$ -/
def verified (recorded answered : Option Nat) : Option Nat :=
  match recorded, answered with
  | some r, some a => if r = a ∧ 1 < r then some r else none
  | _, _ => none

/-- Start is allowed iff no console is verified.

$$\operatorname{startAllowed}(r, a) \iff \operatorname{verified}(r, a) = \bot$$ -/
def startAllowed (recorded answered : Option Nat) : Bool := (verified recorded answered).isNone

/-- The one pid `stop` may signal.

$$\operatorname{stopTarget}(r, a) = \operatorname{verified}(r, a)$$ -/
def stopTarget (recorded answered : Option Nat) : Option Nat := verified recorded answered

/-- One step of a restart. -/
inductive Step where
  | stop (pid : Nat)
  | start
deriving Repr, DecidableEq

/-- Restart: stop the verified console if there is one, then start.

$$\operatorname{restart}(v) = [\mathrm{stop}(p), \mathrm{start}] \text{ if } v = \mathrm{some}(p), \text{ else } [\mathrm{start}]$$ -/
def restartPlan (v : Option Nat) : List Step :=
  match v with
  | some p => [.stop p, .start]
  | none => [.start]

/-- A verified pid is the recorded one, the answered one, and above 1.

$$\operatorname{verified}(r, a) = \mathrm{some}(p) \Rightarrow r = \mathrm{some}(p) \wedge a = \mathrm{some}(p) \wedge 1 < p$$ -/
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

/-- **Start is refused when a console is verified.**

$$\operatorname{verified}(r, a) = \mathrm{some}(p) \Rightarrow \operatorname{startAllowed}(r, a) = \mathrm{false}$$ -/
theorem start_refused_when_verified (r a : Option Nat) (p : Nat) (h : verified r a = some p) :
    startAllowed r a = false := by
  simp [startAllowed, h]

/-- **Start is allowed when no console is verified** (no file, no answer, another pid answered).

$$\operatorname{verified}(r, a) = \bot \Rightarrow \operatorname{startAllowed}(r, a) = \mathrm{true}$$ -/
theorem start_allowed_when_none (r a : Option Nat) (h : verified r a = none) : startAllowed r a = true := by
  simp [startAllowed, h]

/-- **Stop signals only the verified pid.** A pid it may signal is the recorded one, the one that answered the health
request, and above 1.

$$\operatorname{stopTarget}(r, a) = \mathrm{some}(p) \Rightarrow r = \mathrm{some}(p) \wedge a = \mathrm{some}(p) \wedge 1 < p$$ -/
theorem stop_only_verified (r a : Option Nat) (p : Nat) (h : stopTarget r a = some p) :
    r = some p ∧ a = some p ∧ 1 < p := verified_some r a p h

/-- Nothing answered: nothing is signalled (a stale `api.json`, a crashed console).

$$\operatorname{stopTarget}(r, \bot) = \bot$$ -/
theorem stop_unanswered (r : Option Nat) : stopTarget r none = none := by
  cases r <;> simp [stopTarget, verified]

/-- A different pid answered on the recorded port (the pid was reused): nothing is signalled.

$$x \ne y \Rightarrow \operatorname{stopTarget}(\mathrm{some}(x), \mathrm{some}(y)) = \bot$$ -/
theorem stop_pid_mismatch (x y : Nat) (h : x ≠ y) : stopTarget (some x) (some y) = none := by
  simp [stopTarget, verified, h]

/-- Nothing recorded: nothing is signalled.

$$\operatorname{stopTarget}(\bot, a) = \bot$$ -/
theorem stop_unrecorded (a : Option Nat) : stopTarget none a = none := by
  cases a <;> simp [stopTarget, verified]

/-- **A restart ends in a start.**

$$\operatorname{restart}(v) \text{ ends with } \mathrm{start}$$ -/
theorem restart_ends_with_start (v : Option Nat) : (restartPlan v).getLast? = some .start := by
  cases v <;> simp [restartPlan]

/-- **A restart stops only the verified pid.** Every stop step names the pid of the verified console.

$$s \in \operatorname{restart}(v) \wedge s = \mathrm{stop}(p) \Rightarrow v = \mathrm{some}(p)$$ -/
theorem restart_stops_only_verified (v : Option Nat) (p : Nat) (h : Step.stop p ∈ restartPlan v) : v = some p := by
  cases v <;> simp_all [restartPlan]

/-- With no verified console a restart is a plain start: it signals nothing.

$$\operatorname{restart}(\bot) = [\mathrm{start}]$$ -/
theorem restart_unverified (r a : Option Nat) (h : verified r a = none) : restartPlan (verified r a) = [.start] := by
  simp [h, restartPlan]

/-! ## 2. The log takes no secret-bearing line -/

/-- The kinds of line a console writes. The last four can carry a secret.

$$\mathrm{Line} = \mathrm{banner} \mid \mathrm{listening} \mid \mathrm{health} \mid \mathrm{exit} \mid \mathrm{error} \mid \mathrm{access} \mid \mathrm{ownerLink} \mid \mathrm{ownerToken} \mid \mathrm{passphrase} \mid \mathrm{keychain}$$ -/
inductive Line where
  | banner | listening | health | exit | error | access | ownerLink | ownerToken | passphrase | keychain
deriving Repr, DecidableEq

/-- Whether a line of this kind can carry a secret.

$$\operatorname{secret}(k) \iff k \in \{\mathrm{ownerLink}, \mathrm{ownerToken}, \mathrm{passphrase}, \mathrm{keychain}\}$$ -/
def Line.secret : Line → Bool
  | .ownerLink | .ownerToken | .passphrase | .keychain => true
  | _ => false

/-- The name of a line kind on the wire. -/
def Line.name : Line → String
  | .banner => "banner" | .listening => "listening" | .health => "health" | .exit => "exit" | .error => "error"
  | .access => "access" | .ownerLink => "ownerLink" | .ownerToken => "ownerToken" | .passphrase => "passphrase"
  | .keychain => "keychain"

/-- The line kind of a wire name. -/
def Line.ofName? (s : String) : Option Line :=
  [Line.banner, .listening, .health, .exit, .error, .access, .ownerLink, .ownerToken, .passphrase, .keychain].find? (·.name == s)

/-- The log file admits a line kind iff it carries no secret.

$$\operatorname{logAdmits}(k) \iff \neg\operatorname{secret}(k)$$ -/
def logAdmits (k : Line) : Bool := !k.secret

/-- The owner link is never logged.

$$\operatorname{logAdmits}(\mathrm{ownerLink}) = \mathrm{false}$$ -/
theorem log_refuses_owner_link : logAdmits .ownerLink = false := rfl

/-- An owner token is never logged.

$$\operatorname{logAdmits}(\mathrm{ownerToken}) = \mathrm{false}$$ -/
theorem log_refuses_owner_token : logAdmits .ownerToken = false := rfl

/-- The passphrase is never logged.

$$\operatorname{logAdmits}(\mathrm{passphrase}) = \mathrm{false}$$ -/
theorem log_refuses_passphrase : logAdmits .passphrase = false := rfl

/-- A keychain value is never logged.

$$\operatorname{logAdmits}(\mathrm{keychain}) = \mathrm{false}$$ -/
theorem log_refuses_keychain : logAdmits .keychain = false := rfl

/-- **The log admits no secret-bearing line kind.**

$$\operatorname{logAdmits}(k) \Rightarrow \neg\operatorname{secret}(k)$$ -/
theorem log_admits_no_secret (k : Line) (h : logAdmits k = true) : k.secret = false := by
  cases k <;> simp_all [logAdmits, Line.secret]

/-- The link sink rule and the log rule agree: the owner link may go to a terminal only, and the log is not one.

$$\operatorname{linkSink}(\mathrm{log}) = \mathrm{false} \wedge \operatorname{logAdmits}(\mathrm{ownerLink}) = \mathrm{false}$$ -/
theorem log_agrees_with_link_sink :
    Fw.Console.Preview.linkSink .log = false ∧ logAdmits .ownerLink = false := ⟨rfl, rfl⟩

/-! ## 3. Sign-in without a terminal -/

/-- **The passphrase login is open from loopback.** Whatever the token and Host, the login class is admitted at loopback,
so the owner of a detached console signs in at `http://127.0.0.1:<port>/owner/login`.

$$\operatorname{allow}(\mathrm{false}, b, h, \mathrm{login}) = \mathrm{true}$$ -/
theorem login_loopback (bearer hostOk : Bool) :
    Fw.Console.Preview.Owner.allow false bearer hostOk .login = true := by
  simp [Fw.Console.Preview.Owner.allow]

/-- The login is also open from the LAN with the right Host (`Owner.login_reachable`), so both paths work with no terminal.

$$\operatorname{allow}(\ell, b, \mathrm{true}, \mathrm{login}) = \mathrm{true}$$ -/
theorem login_lan_or_loopback (lan bearer : Bool) :
    Fw.Console.Preview.Owner.allow lan bearer true .login = true :=
  Fw.Console.Preview.Owner.login_reachable lan bearer

/-! ## 4. Log rotation -/

/-- The log size at which the file is rotated (bytes): 5 MiB.

$$\mathit{logLimit} = 5242880$$ -/
def logLimit : Nat := 5242880

/-- The log is rotated (the file moved to `console.log.1`, a new one started) when its size has reached the limit.

$$\operatorname{rotate}(s, m) \iff m \le s$$ -/
def rotate (size limit : Nat) : Bool := decide (limit ≤ size)

/-- A log below its limit is kept.

$$s < m \Rightarrow \operatorname{rotate}(s, m) = \mathrm{false}$$ -/
theorem rotate_below (s m : Nat) (h : s < m) : rotate s m = false := by
  simp [rotate]; omega

/-- A log at its limit is rotated.

$$\operatorname{rotate}(m, m) = \mathrm{true}$$ -/
theorem rotate_at_limit (m : Nat) : rotate m m = true := by
  simp [rotate]

end Fw.Console.Daemon
