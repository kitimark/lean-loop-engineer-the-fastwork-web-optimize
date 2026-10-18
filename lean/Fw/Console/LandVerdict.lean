import Lean.Data.Json
/-!
# The verdict of an `fw land`: one machine-readable line and one exit code per kind

Incident rows `inc-land-retry-text-match` (a loose text grep for `busy` matched a Lean warning that named `dispatch_busy`
and the queue retried a finished land) and `inc-land-undeclared-reads` (four refusals that each needed a reading of free
text) share one cause: the outcome of a land was only prose. Here the outcome is a **kind**; `fw land` prints exactly one
line `VERDICT <kind> <task>` and exits with the kind's code, so a script decides from the exit code or from the first
word after `VERDICT`, never from a text match.

* kinds: `busy` `dirty` `scope` `reads` `conflict` `checks` `stale` `unknown` `lint` (refusals); `done` `dry` `queued` `empty` (successes);
* exit code: 0 for every success, a distinct non-zero number for every refusal (`exitCode_inj_refusal`);
* retry: only `busy` and `dirty` are retried (`retryable_iff`): they say that the world, not the branch, is in the way.

Golden vectors: `packages/contracts/golden/console/land-dry.jsonl` (`Fw.Console.LandDry.goldenText`, ops
`landVerdict.kind`, `landDry.verdict`, `landDry.handback`). TS stand-in: `apps/runner/src/land-verdict.ts` (marked for
replacement by an `fwcore` op).
-/
namespace Fw.Console.LandVerdict

/-- The outcome kinds of a land (or of a dry land, or of a queue entry).
$$K = \{\mathrm{busy}, \mathrm{dirty}, \mathrm{scope}, \mathrm{reads}, \mathrm{conflict}, \mathrm{checks}, \mathrm{stale}, \mathrm{unknown}, \mathrm{done}, \mathrm{dry}, \mathrm{queued}, \mathrm{empty}, \mathrm{lint}\}$$ -/
inductive Kind where
  | busy | dirty | scope | reads | conflict | checks | stale | unknown | done | dry | queued | empty | lint
deriving DecidableEq, Repr

/-- All kinds, in the order of the golden file.
$$\mathrm{all} = [\mathrm{busy}, \mathrm{dirty}, \mathrm{scope}, \mathrm{reads}, \mathrm{conflict}, \mathrm{checks}, \mathrm{stale}, \mathrm{unknown}, \mathrm{done}, \mathrm{dry}, \mathrm{queued}, \mathrm{empty}, \mathrm{lint}]$$ -/
def Kind.all : List Kind := [.busy, .dirty, .scope, .reads, .conflict, .checks, .stale, .unknown, .done, .dry, .queued, .empty, .lint]

/-- The word printed after `VERDICT`.
$$\operatorname{name}(\mathrm{busy}) = \texttt{busy},\ \dots,\ \operatorname{name}(\mathrm{queued}) = \texttt{queued}$$ -/
def Kind.name : Kind → String
  | .busy => "busy" | .dirty => "dirty" | .scope => "scope" | .reads => "reads" | .conflict => "conflict"
  | .checks => "checks" | .stale => "stale" | .unknown => "unknown" | .done => "done" | .dry => "dry" | .queued => "queued" | .empty => "empty" | .lint => "lint"

/-- Is the kind a success? A finished land, a passing dry land, an accepted queue entry.
$$\operatorname{ok}(k) \iff k \in \{\mathrm{done}, \mathrm{dry}, \mathrm{queued}, \mathrm{empty}\}$$ -/
def Kind.ok : Kind → Bool
  | .done => true | .dry => true | .queued => true | .empty => true | _ => false

/-- The process exit code of a kind: 0 for a success, a distinct number for each refusal (`unknown` is 2, the code `fw land`
always used for a refusal).
$$\operatorname{code}(k) = \begin{cases} 0 & \operatorname{ok}(k) \\ 2 & k = \mathrm{unknown} \\ 10,\dots,17 & k = \mathrm{busy},\mathrm{dirty},\mathrm{scope},\mathrm{reads},\mathrm{conflict},\mathrm{checks},\mathrm{stale},\mathrm{lint} \end{cases}$$ -/
def Kind.exitCode : Kind → Nat
  | .busy => 10 | .dirty => 11 | .scope => 12 | .reads => 13 | .conflict => 14 | .checks => 15 | .stale => 16
  | .lint => 17 | .unknown => 2 | .done => 0 | .dry => 0 | .queued => 0 | .empty => 0

/-- Does a kind justify trying the same land again later? Only `busy` (another land holds the lock) and `dirty` (the main
checkout has uncommitted changes) say that something other than the branch is in the way.
$$\operatorname{retry}(k) \iff k \in \{\mathrm{busy}, \mathrm{dirty}\}$$ -/
def Kind.retryable : Kind → Bool
  | .busy => true | .dirty => true | _ => false

/-- The verdict line: `VERDICT <kind> <task>` (`-` when there is no task).
$$\operatorname{line}(k, t) = \texttt{VERDICT } \operatorname{name}(k) \texttt{ } (t \text{ or } \texttt{-})$$ -/
def verdictLine (k : Kind) (task : String) : String :=
  "VERDICT " ++ k.name ++ " " ++ (if task == "" then "-" else task)

/-- Kinds are named apart: two kinds with the same name are the same kind, so the word after `VERDICT` decides.
$$\forall k, k':\ \operatorname{name}(k) = \operatorname{name}(k') \Rightarrow k = k'$$ -/
theorem name_inj (k k' : Kind) (h : k.name = k'.name) : k = k' := by
  cases k <;> cases k' <;> simp_all [Kind.name]

/-- **Distinct exit codes.** Two refusal kinds with the same exit code are the same kind.
$$\forall k, k':\ \lnot\operatorname{ok}(k) \wedge \lnot\operatorname{ok}(k') \wedge \operatorname{code}(k) = \operatorname{code}(k') \Rightarrow k = k'$$ -/
theorem exitCode_inj_refusal (k k' : Kind) (hk : k.ok = false) (hk' : k'.ok = false) (h : k.exitCode = k'.exitCode) :
    k = k' := by
  cases k <;> cases k' <;> simp_all [Kind.ok, Kind.exitCode]

/-- **Exit 0 is exactly success.**
$$\forall k:\ \operatorname{code}(k) = 0 \iff \operatorname{ok}(k)$$ -/
theorem exitCode_zero_iff (k : Kind) : k.exitCode = 0 ↔ k.ok = true := by
  cases k <;> simp [Kind.ok, Kind.exitCode]

/-- **Retry only on busy and dirty.** A retryable kind is `busy` or `dirty`, and neither is a success.
$$\forall k:\ \operatorname{retry}(k) \iff k = \mathrm{busy} \vee k = \mathrm{dirty}$$ -/
theorem retryable_iff (k : Kind) : k.retryable = true ↔ k = .busy ∨ k = .dirty := by
  cases k <;> simp [Kind.retryable]

/-- A retried kind is never a success (a finished land is not retried: `inc-land-retry-text-match`).
$$\forall k:\ \operatorname{retry}(k) \Rightarrow \lnot\operatorname{ok}(k)$$ -/
theorem retryable_not_ok (k : Kind) (h : k.retryable = true) : k.ok = false := by
  cases k <;> simp_all [Kind.retryable, Kind.ok]

/-- The line names the kind: the second word is the kind's name, and the task never changes it.
$$\forall k, t\ \exists r:\ \operatorname{line}(k, t) = \texttt{VERDICT } \operatorname{name}(k) \texttt{ } r$$ -/
theorem verdictLine_prefix (k : Kind) (t : String) :
    ∃ r, verdictLine k t = "VERDICT " ++ k.name ++ " " ++ r :=
  ⟨if t == "" then "-" else t, rfl⟩

#guard Kind.all.length == 13
#guard (Kind.all.map Kind.name).eraseDups.length == 13
#guard ((Kind.all.filter (fun k => !k.ok)).map Kind.exitCode).eraseDups.length == 9
#guard verdictLine .busy "land-dry" == "VERDICT busy land-dry"
#guard verdictLine .scope "" == "VERDICT scope -"

end Fw.Console.LandVerdict
