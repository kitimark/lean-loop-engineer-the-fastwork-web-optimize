import Fw.Oracle.Core
import Fw.Oracle.Redact
/-!
# Fw.Oracle.Send: whether one oracle question goes out (replay, refuse or send)

Before any network call the client asks `pre` (the `oracle.pre` op): an answer already in the answer log (keyed by
the hash of the exact request: question, redacted state, pinned model) is replayed with no call; a state that is not
redacted is refused; the per-day call cap and, for a calibration run, the per-run cap refuse with `overBudget`.
Only then may the client read the key and send. `pre_send` lists what a send certifies.
-/
namespace Fw.Oracle

/-- The spend guard: calls per UTC day, and calls per calibration run.

$$\mathrm{Budget} = (\mathit{daily}, \mathit{run}) \in \mathbb{N}^2, \text{ default } (200, 60)$$ -/
structure Budget where
  dailyCap : Nat := 200
  runCap : Nat := 60
deriving Repr, DecidableEq

/-- The default spend guard: 200 calls a day, 60 per calibration run.

$$\mathrm{budget}_0 = (200, 60)$$ -/
def defaultBudget : Budget := {}

/-- The calls already made on day `today`, counted from the answer log's call dates.

$$\mathrm{callsOn}(t, D) = |[\, d \in D : d = t \,]|$$ -/
def callsOn (today : String) (days : List String) : Nat := (days.filter (· == today)).length

/-- The send decision: replay a logged answer, refuse with a failure, or send.

$$\mathrm{Pre} ::= \mathrm{replay} \mid \mathrm{refuse}(f) \mid \mathrm{send}$$ -/
inductive Pre where
  | replay
  | refuse (f : Failure)
  | send
deriving Repr, DecidableEq

/-- **The send gate.** Logged: replay. Not redacted: refuse. Daily cap reached: refuse over budget. In a calibration
run (`run = some c`) with `c` calls made: refuse over budget once `c` reaches the run cap. Otherwise send.

$$\mathrm{pre}(b, N, S, \ell, t, D, \rho) = \begin{cases} \mathrm{replay} & \ell \\ \mathrm{refuse}(\mathrm{unredacted}) & \lnot\ell,\ \lnot\mathrm{isRedacted}(N, S) \\ \mathrm{refuse}(\mathrm{overBudget}) & \lnot\ell,\ \mathrm{isRedacted}(N, S),\ b.\mathit{daily} \le \mathrm{callsOn}(t, D) \\ \mathrm{refuse}(\mathrm{overBudget}) & \ldots,\ \mathrm{callsOn}(t, D) < b.\mathit{daily},\ \rho = c,\ b.\mathit{run} \le c \\ \mathrm{send} & \text{otherwise} \end{cases}$$ -/
def pre (b : Budget) (names : List String) (st : State) (logged : Bool) (today : String) (days : List String)
    (run : Option Nat) : Pre :=
  if logged then .replay
  else if !isRedacted names st then .refuse .unredacted
  else if b.dailyCap ≤ callsOn today days then .refuse .overBudget
  else match run with
    | some c => if b.runCap ≤ c then .refuse .overBudget else .send
    | none => .send

/-- **A logged question is replayed exactly, with no call.**

$$\forall b, N, S, t, D, \rho:\ \mathrm{pre}(b, N, S, \top, t, D, \rho) = \mathrm{replay}$$ -/
theorem pre_logged (b : Budget) (names : List String) (st : State) (today : String) (days : List String)
    (run : Option Nat) : pre b names st true today days run = .replay := rfl

/-- **What a send certifies**: not logged, the state redacted (so no line holds a home path, `redacted_no_home`),
under the daily cap, and under the run cap of a calibration run.

$$\forall b, N, S, \ell, t, D, \rho:\ \mathrm{pre}(b, N, S, \ell, t, D, \rho) = \mathrm{send} \Rightarrow \lnot\ell \land \mathrm{isRedacted}(N, S) \land \mathrm{callsOn}(t, D) < b.\mathit{daily} \land \forall c:\ \rho = c \Rightarrow c < b.\mathit{run}$$ -/
theorem pre_send (b : Budget) (names : List String) (st : State) (logged : Bool) (today : String)
    (days : List String) (run : Option Nat) (h : pre b names st logged today days run = .send) :
    logged = false ∧ isRedacted names st = true ∧ callsOn today days < b.dailyCap ∧
      ∀ c, run = some c → c < b.runCap := by
  unfold pre at h
  cases logged with
  | true => simp at h
  | false =>
    by_cases hr : isRedacted names st = true
    · by_cases hd : b.dailyCap ≤ callsOn today days
      · simp [hr, hd] at h
      · cases run with
        | none => exact ⟨rfl, hr, Nat.lt_of_not_le hd, fun _ hc => by simp at hc⟩
        | some c =>
          by_cases hc : b.runCap ≤ c
          · simp [hr, hd, hc] at h
          · exact ⟨rfl, hr, Nat.lt_of_not_le hd, fun c' hc' => by
              simp at hc'; subst hc'; exact Nat.lt_of_not_le hc⟩
    · simp [hr] at h

/-- **A sent state holds no home path** in any line.

$$\forall b, N, S, \ell, t, D, \rho:\ \mathrm{pre}(b, N, S, \ell, t, D, \rho) = \mathrm{send} \Rightarrow \forall (k, L) \in S:\ \forall x \in L:\ \forall u, v:\ x \ne u \mathbin{+\!\!+} \texttt{/Users/} \mathbin{+\!\!+} v$$ -/
theorem send_no_home (b : Budget) (names : List String) (st : State) (logged : Bool) (today : String)
    (days : List String) (run : Option Nat) (h : pre b names st logged today days run = .send) :
    ∀ kl ∈ st, ∀ x ∈ kl.2, ∀ u v : List Char, x.toList ≠ u ++ "/Users/".toList ++ v :=
  fun kl hkl x hx u v => (redacted_no_home names st (pre_send b names st logged today days run h).2.1 kl hkl x hx u v).1

#guard pre defaultBudget [] [("log", ["/Users/x/y"])] false "2026-10-18" [] none == .refuse .unredacted
#guard pre defaultBudget [] [("log", ["~/x"])] false "2026-10-18" [] none == .send
#guard pre defaultBudget [] [("log", ["/Users/x/y"])] true "2026-10-18" [] none == .replay
#guard pre { dailyCap := 2 } [] [] false "d" ["d", "e", "d"] none == .refuse .overBudget
#guard pre { dailyCap := 3 } [] [] false "d" ["d", "e", "d"] none == .send
#guard pre defaultBudget [] [] false "d" [] (some 60) == .refuse .overBudget
#guard pre defaultBudget [] [] false "d" [] (some 59) == .send

end Fw.Oracle
