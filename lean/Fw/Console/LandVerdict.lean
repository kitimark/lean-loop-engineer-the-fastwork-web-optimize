import Lean.Data.Json
/-!
# The verdict of an `fw land`: one machine-readable line and one exit code per kind

Incident rows `inc-land-retry-text-match` (a loose text grep for `busy` matched a Lean warning that named `dispatch_busy`
and the queue retried a finished land) and `inc-land-undeclared-reads` (four refusals that each needed a reading of free
text) share one cause: the outcome of a land was only prose. Here the outcome is a **kind**; `fw land` prints exactly one
line `VERDICT <kind> <task>` and exits with the kind's code, so a script decides from the exit code or from the first
word after `VERDICT`, never from a text match.

* kinds: `busy` `dirty` `scope` `reads` `conflict` `checks` `stale` `unknown` `lint` `rebuild` `install` (refusals); `done` `dry` `queued` `empty` (successes);
* exit code: 0 for every success, a distinct non-zero number for every refusal (`exitCode_inj_refusal`);
* retry: only `busy` and `dirty` are retried (`retryable_iff`): they say that the world, not the branch, is in the way.

Golden vectors: `packages/contracts/golden/console/land-dry.jsonl` (`Fw.Console.LandDry.goldenText`, ops
`landVerdict.kind`, `landDry.verdict`, `landDry.handback`). TS stand-in: `apps/runner/src/land-verdict.ts` (marked for
replacement by an `fwcore` op).
-/
namespace Fw.Console.LandVerdict

/-- The outcome kinds of a land (or of a dry land, or of a queue entry). -/
inductive Kind where
  | busy | dirty | scope | reads | conflict | checks | stale | unknown | done | dry | queued | empty | lint | rebuild | install
deriving DecidableEq, Repr

/-- All kinds, in the order of the golden file. -/
def Kind.all : List Kind := [.busy, .dirty, .scope, .reads, .conflict, .checks, .stale, .unknown, .done, .dry, .queued, .empty, .lint, .rebuild, .install]

/-- The word printed after `VERDICT`. -/
def Kind.name : Kind → String
  | .busy => "busy" | .dirty => "dirty" | .scope => "scope" | .reads => "reads" | .conflict => "conflict"
  | .checks => "checks" | .stale => "stale" | .unknown => "unknown" | .done => "done" | .dry => "dry" | .queued => "queued" | .empty => "empty" | .lint => "lint" | .rebuild => "rebuild" | .install => "install"

/-- Is the kind a success? A finished land, a passing dry land, an accepted queue entry. -/
def Kind.ok : Kind → Bool
  | .done => true | .dry => true | .queued => true | .empty => true | _ => false

/-- The process exit code of a kind: 0 for a success, a distinct number for each refusal (`unknown` is 2, the code `fw land`
always used for a refusal). -/
def Kind.exitCode : Kind → Nat
  | .busy => 10 | .dirty => 11 | .scope => 12 | .reads => 13 | .conflict => 14 | .checks => 15 | .stale => 16
  | .lint => 17 | .rebuild => 18 | .install => 19 | .unknown => 2 | .done => 0 | .dry => 0 | .queued => 0 | .empty => 0

/-- Does a kind justify trying the same land again later? Only `busy` (another land holds the lock) and `dirty` (the main
checkout has uncommitted changes) say that something other than the branch is in the way. -/
def Kind.retryable : Kind → Bool
  | .busy => true | .dirty => true | _ => false

/-- The verdict line: `VERDICT <kind> <task>` (`-` when there is no task). -/
def verdictLine (k : Kind) (task : String) : String :=
  "VERDICT " ++ k.name ++ " " ++ (if task == "" then "-" else task)

/-- Kinds are named apart: two kinds with the same name are the same kind, so the word after `VERDICT` decides. -/
theorem name_inj (k k' : Kind) (h : k.name = k'.name) : k = k' := by
  cases k <;> cases k' <;> simp_all [Kind.name]

/-- **Distinct exit codes.** Two refusal kinds with the same exit code are the same kind. -/
theorem exitCode_inj_refusal (k k' : Kind) (hk : k.ok = false) (hk' : k'.ok = false) (h : k.exitCode = k'.exitCode) :
    k = k' := by
  cases k <;> cases k' <;> simp_all [Kind.ok, Kind.exitCode]

/-- **Exit 0 is exactly success.** -/
theorem exitCode_zero_iff (k : Kind) : k.exitCode = 0 ↔ k.ok = true := by
  cases k <;> simp [Kind.ok, Kind.exitCode]

/-- **Retry only on busy and dirty.** A retryable kind is `busy` or `dirty`, and neither is a success. -/
theorem retryable_iff (k : Kind) : k.retryable = true ↔ k = .busy ∨ k = .dirty := by
  cases k <;> simp [Kind.retryable]

/-- A retried kind is never a success (a finished land is not retried: `inc-land-retry-text-match`). -/
theorem retryable_not_ok (k : Kind) (h : k.retryable = true) : k.ok = false := by
  cases k <;> simp_all [Kind.retryable, Kind.ok]

/-- The line names the kind: the second word is the kind's name, and the task never changes it. -/
theorem verdictLine_prefix (k : Kind) (t : String) :
    ∃ r, verdictLine k t = "VERDICT " ++ k.name ++ " " ++ r :=
  ⟨if t == "" then "-" else t, rfl⟩

/-- Does the land worktree's offline install need the online retry? Only when the offline install failed. -/
def installRunsOnline (offlineOk : Bool) : Bool := !offlineOk

/-- The install step's refusal: `install` when both installs failed, else none. -/
def installKind (offlineOk onlineOk : Bool) : Option Kind :=
  if offlineOk || onlineOk then none else some .install

theorem installKind_offline_ok (onlineOk : Bool) : installKind true onlineOk = none ∧ installRunsOnline true = false := by
  simp [installKind, installRunsOnline]

theorem installKind_online_ok : installKind false true = none ∧ installRunsOnline false = true := by
  simp [installKind, installRunsOnline]

theorem installKind_both_fail : installKind false false = some .install ∧ Kind.exitCode .install = 19 := by
  simp [installKind, Kind.exitCode]

theorem installKind_refusal (a b : Bool) (k : Kind) (h : installKind a b = some k) : k = .install ∧ k.ok = false := by
  cases a <;> cases b <;> simp [installKind] at h
  subst h; exact ⟨rfl, rfl⟩

/-! ### The lockfile stamp

A reused land worktree (`.claude/land-wt/N`) keeps its `node_modules` between lands. Without a stamp it installs only
when the land's own diff touches a lockfile, so a lockfile that main changed in between leaves the checks running on stale
`node_modules` (incident `inc-land-wt-lock-drift`). The stamp is the lockfile hash recorded at the worktree's last
successful install; it lives in `node_modules`, outside git. -/

/-- Does the worktree install before the checks? A new worktree always does; a reused one does when its stamp is missing
or differs from the lockfile hash at the checked-out commit. -/
def installNeeded (known : Bool) (lock : String) (stamp : Option String) : Bool :=
  !known || stamp != some lock

/-- The install step with the stamp: the refusal (if any) and the stamp after the step. `lock` is `none` when the commit has no
lockfile (nothing to install). The stamp is written only after a successful install. -/
def installStep (known : Bool) (lock : Option String) (stamp : Option String) (offlineOk onlineOk : Bool) :
    Option Kind × Option String :=
  match lock with
  | none => (none, stamp)
  | some h =>
    if installNeeded known h stamp then
      (if installKind offlineOk onlineOk = none then (none, some h) else (some .install, stamp))
    else (none, stamp)

/-- **No check runs on a stale stamp.** When the install step does not refuse, the stamp afterwards equals the lockfile hash
(whenever there is a lockfile): the checks run on `node_modules` installed from the checked-out lockfile. -/
theorem installStep_checks_see_current_stamp (known : Bool) (h : String) (stamp : Option String) (a b : Bool)
    (hn : (installStep known (some h) stamp a b).1 = none) : (installStep known (some h) stamp a b).2 = some h := by
  unfold installStep installNeeded at *
  by_cases hk : (!known || stamp != some h) = true
  · simp only [hk, ite_true] at hn ⊢
    by_cases hi : installKind a b = none
    · simp [hi]
    · simp [hi] at hn
  · simp only [Bool.not_eq_true] at hk
    simp only [hk]
    simp only [Bool.or_eq_false_iff, Bool.not_eq_false', bne_eq_false_iff_eq] at hk
    simp [hk.2]

/-- A refusal of the install step is `install`, and the stamp is left as it was (it still differs from the lockfile, so the
next land installs again). -/
theorem installStep_refusal (known : Bool) (h : String) (stamp : Option String) (a b : Bool) (k : Kind)
    (hr : (installStep known (some h) stamp a b).1 = some k) :
    k = .install ∧ (installStep known (some h) stamp a b).2 = stamp := by
  unfold installStep at *
  by_cases hk : installNeeded known h stamp = true
  · simp only [hk, ite_true] at hr ⊢
    cases a <;> cases b <;> simp [installKind] at hr ⊢ <;> simp [hr]
  · simp [hk] at hr

/-- A reused worktree whose stamp equals the lockfile hash does not install. -/
theorem installNeeded_reused_current (h : String) : installNeeded true h (some h) = false := by
  simp [installNeeded]

/-- A reused worktree behind main's lockfile (stamp of an older hash) installs. -/
theorem installNeeded_reused_behind (h s : String) (hne : s ≠ h) : installNeeded true h (some s) = true := by
  simp [installNeeded, hne]

/-- A reused worktree with no stamp installs. -/
theorem installNeeded_reused_unstamped (h : String) : installNeeded true h none = true := by
  simp [installNeeded]

/-- A new worktree installs whatever its stamp. -/
theorem installNeeded_new (h : String) (s : Option String) : installNeeded false h s = true := by
  simp [installNeeded]

/-- Both installs failing on a stale reused worktree refuses with `install`, exit 19, and keeps the old stamp. -/
theorem installStep_behind_both_fail :
    installStep true (some "new") (some "old") false false = (some .install, some "old") := by
  decide

/-- A stale reused worktree whose offline install works ends stamped with the new hash and does not refuse. -/
theorem installStep_behind_offline_ok :
    installStep true (some "new") (some "old") true false = (none, some "new") := by
  decide

#guard Kind.all.length == 15
#guard (Kind.all.map Kind.name).eraseDups.length == 15
#guard ((Kind.all.filter (fun k => !k.ok)).map Kind.exitCode).eraseDups.length == 11
#guard verdictLine .busy "land-dry" == "VERDICT busy land-dry"
#guard verdictLine .scope "" == "VERDICT scope -"

end Fw.Console.LandVerdict
