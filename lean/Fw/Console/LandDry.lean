import Lean.Data.Json
import Fw.Console.LandVerdict
/-!
# `fw land <branch> --task <id> --dry`: the refusals of a land, found before the land

Incident rows `inc-land-undeclared-reads` (4 lands refused for an undeclared read, each a ~5 min land plus a lead fix) and
`inc-land-scope-stale-base` (a stale merge base carried another task's diff into the scope check). A real land does its
cheap, deterministic stages (scope, merge, the static reads test) first and then runs the long checks; a dry land runs
only those cheap stages, takes no lock and runs no full check, so an agent can learn the refusal before it hands back.

Model. The three stages are functions of the facts a land starts from: the main commit `m` and the branch tip `b` (the work
graph and the allow list come from `m` and the land command). A dry land and the real land evaluate the *same* functions;
the dry land builds the same merge commit (`merge-tree` of `m` and `b`, plus the task's evidence) and checks the same tree.
The one thing that can differ is `m`: the real land reads it later.

* `landStages` is the real land's first refusal among scope, merge (conflict) and reads, in that order;
* `dryKind` is the dry land's kind: `stale` when the branch lacks `main`, else the same first refusal, else `dry`;
* `dry_pass_land_pass`: dry passes and main has not moved, so the real land passes scope, merge and reads;
* `dryRun` (task `land-dry-full`): the whole stdout of a dry run as a function of seven stage outcomes (`Outcome`). Proved:
  exactly one `VERDICT` line, last (`dryRun_one_verdict`); the kind is the first failing stage in the fixed order exception, stale,
  empty, scope, conflict, reads, lint (`first_spec`, `kind_spec`); it equals `dryKind` (`kind_ofStages`). `lintPlan` decides which
  lints run; `dry_kind_is_real_kind` links each dry stage's kind to the kind the real land prints for the same failure. NOT proved:
  that the I/O in `land.ts` computes the outcomes truthfully (the premises below and the tests cover that), nor that a real
  lint failure reaches the real land as a `check.sh` stage line (a regex, `failedStages`).
* `handback_pass_land_pass`: a hand-back rule "only when the dry land says `dry`" never leaves a scope, reads or conflict
  refusal for the land (unless main moved: `moved_no_guarantee`).

Premises (registry rows in `premises`): the stages are deterministic functions of `(m, b)` (`land.dryStagesAreLandStages`,
`land.checkDeterministic` of `Fw.Console.LandSpeed`), and `git merge-tree --write-tree` fails exactly when `git merge`
conflicts (`land.mergeTreeReproduces`).

Golden vectors: `packages/contracts/golden/console/land-dry.jsonl` (`goldenText`; ops `landVerdict.kind`, `landDry.verdict`,
`landDry.handback`). Write or check with `lake env lean --run` on a two-line script calling `writeGolden` / `checkGolden`.
-/
namespace Fw.Console.LandDry
open Fw.Console.LandVerdict

/-- The pure stage functions of a land, of the main commit `m` and the branch tip `b`: the scope check of the diff, the
clean merge, whether the change selects the reads-scan check (`LandSpeed.scan_selected`; so the static reads test is part of the real checks), and
that test's verdict on the merge tree, whether the branch has commits of its own, and the fast lints (the axiom check and
`ci-paths --check`, run on the merge tree) that refused real lands (task `land-dry-full`). -/
structure Stages where
  scope : String → String → Bool
  merges : String → String → Bool
  readsSelected : String → String → Bool
  readsTest : String → String → Bool
  own : String → String → Bool
  lints : String → String → Bool

/-- The reads stage: a check that the change does not select cannot refuse. -/
def Stages.reads (w : Stages) (m b : String) : Bool := !(w.readsSelected m b) || w.readsTest m b

/-- The cheap stages of a land, in the order the land runs them. -/
inductive Stage where
  | scope | conflict | reads
deriving DecidableEq, Repr

/-- The verdict kind a refusal at a stage prints. -/
def Stage.kind : Stage → Kind
  | .scope => .scope | .conflict => .conflict | .reads => .reads

/-- The first refusal among the stage verdicts, in land order: scope, then merge, then reads (`none`: all pass). -/
def firstRefusal (s g r : Bool) : Option Stage :=
  if !s then some .scope else if !g then some .conflict else if !r then some .reads else none

/-- The first refusal of the real land's cheap stages, when main is at `h`. -/
def landStages (w : Stages) (h b : String) : Option Stage := firstRefusal (w.scope h b) (w.merges h b) (w.reads h b)

/-- The kind of a dry land at main `m_0`: `stale` when the branch does not contain `main`, `empty` when it has no commit of its
own (nothing to land, a success), else the first refusal of the three stages, else `lint` when a fast lint fails, else `dry`. -/
def dryKind (w : Stages) (contains : Bool) (m0 b : String) : Kind :=
  if !contains then .stale else
  if !(w.own m0 b) then .empty else
  match landStages w m0 b with
  | some s => s.kind
  | none => if w.lints m0 b then .dry else .lint

/-- The three stages pass iff each passes. -/
theorem firstRefusal_none_iff (s g r : Bool) : firstRefusal s g r = none ↔ (s = true ∧ g = true ∧ r = true) := by
  cases s <;> cases g <;> cases r <;> simp [firstRefusal]

/-- **A dry pass is a land pass.** If the dry land says `dry` and main has not moved (`h = m_0`), the real land's scope, merge
and reads stages pass. -/
theorem dry_pass_land_pass (w : Stages) (c : Bool) (m0 h b : String) (hd : dryKind w c m0 b = .dry) (hh : h = m0) :
    landStages w h b = none := by
  subst hh
  cases c <;> cases ho : w.own h b <;> cases hl : landStages w h b <;> cases hn : w.lints h b <;>
    simp [dryKind, hl, ho, hn] at hd ⊢
  all_goals (rename_i s; cases s <;> simp [Stage.kind] at hd)

/-- **A dry refusal is the land's refusal.** If the dry land refuses with the kind of a stage and main has not moved, the
real land refuses at that stage. -/
theorem dry_refusal_is_land_refusal (w : Stages) (c : Bool) (m0 h b : String) (s : Stage)
    (hd : dryKind w c m0 b = s.kind) (hh : h = m0) : landStages w h b = some s := by
  subst hh
  cases c
  · cases s <;> simp [dryKind, Stage.kind] at hd
  · cases ho : w.own h b
    · cases s <;> simp [dryKind, ho, Stage.kind] at hd
    · cases hl : landStages w h b with
      | none => cases hn : w.lints h b <;> cases s <;> simp [dryKind, hl, ho, hn, Stage.kind] at hd
      | some s2 =>
        rw [Option.some.injEq]
        cases s <;> cases s2 <;> simp_all [dryKind, Stage.kind]

/-- **No false alarm from the dry land.** When the branch contains `main` and main has not moved, the dry land passes exactly
when the branch has its own commits, the real land's stages pass and the fast lints pass. -/
theorem dry_iff_land_pass (w : Stages) (m0 h b : String) (hh : h = m0) :
    dryKind w true m0 b = .dry ↔ (w.own m0 b = true ∧ landStages w h b = none ∧ w.lints m0 b = true) := by
  subst hh
  cases ho : w.own h b <;> cases hl : landStages w h b <;> cases hn : w.lints h b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

/-- **The dry land passes only if scope, merge, reads and the fast lints pass** (and the branch has commits and contains main). -/
theorem dry_pass_all (w : Stages) (c : Bool) (m0 b : String) (hd : dryKind w c m0 b = .dry) :
    c = true ∧ w.own m0 b = true ∧ w.scope m0 b = true ∧ w.merges m0 b = true ∧ w.reads m0 b = true ∧ w.lints m0 b = true := by
  have hl := dry_pass_land_pass w c m0 m0 b hd rfl
  have hf := (firstRefusal_none_iff _ _ _).mp (by simpa [landStages] using hl)
  cases c <;> cases ho : w.own m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, ho, hn] at hd ⊢
  all_goals (try cases hl2 : landStages w m0 b <;> simp [hl2] at hd)
  all_goals (try (rename_i s; cases s <;> simp [Stage.kind] at hd))
  all_goals simp_all

/-- A `stale` verdict is given exactly when the branch lacks `main`. -/
theorem stale_iff (w : Stages) (c : Bool) (m0 b : String) : dryKind w c m0 b = .stale ↔ c = false := by
  cases c <;> cases ho : w.own m0 b <;> cases hl : landStages w m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

/-- The hand-back rule: an agent may hand back only on a `dry` verdict. -/
def handbackAllowed (k : Kind) : Bool := k == .dry

/-- **A hand-back that obeys the rule is not refused at scope, merge or reads.** The agent merged `main` into its branch and
the dry land said `dry`; if main has not moved when the land starts, none of the three stages refuses (the four 2026-10-18
reads refusals and the stale-base scope refusal could not have happened). -/
theorem handback_pass_land_pass (w : Stages) (c : Bool) (m0 h b : String) (ha : handbackAllowed (dryKind w c m0 b) = true)
    (hh : h = m0) : landStages w h b = none := by
  apply dry_pass_land_pass w c m0 h b _ hh
  simpa [handbackAllowed] using ha

/-- **Moved main voids the guarantee.** There are stage functions and commits where the dry land passes at `m_0` and the real
land refuses at a later `h ≠ m_0` (a land that follows a lead land can still be refused: the dry verdict names the main it
ran against). -/
theorem moved_no_guarantee :
    ∃ (w : Stages) (m0 h b : String), dryKind w true m0 b = .dry ∧ h ≠ m0 ∧ landStages w h b ≠ none :=
  ⟨⟨fun m _ => m == "a", fun _ _ => true, fun _ _ => false, fun _ _ => true, fun _ _ => true, fun _ _ => true⟩, "a", "b", "t", by decide, by decide, by decide⟩

/-- **Only stage kinds, stale, empty, lint and dry come out of a dry land**: never `busy`, `dirty`, `checks`, `done`, `queued` or
`unknown` (it takes no lock, runs no full check and does not touch the main checkout). -/
theorem dryKind_cases (w : Stages) (c : Bool) (m0 b : String) :
    dryKind w c m0 b = .stale ∨ dryKind w c m0 b = .empty ∨ dryKind w c m0 b = .scope ∨ dryKind w c m0 b = .conflict ∨
      dryKind w c m0 b = .reads ∨ dryKind w c m0 b = .lint ∨ dryKind w c m0 b = .dry := by
  cases c <;> cases ho : w.own m0 b <;> cases hl : landStages w m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

/-! ## The dry run as a function of its stage outcomes (task land-dry-full)

`fw land --dry` computes seven stage outcomes (I/O, in `land.ts`) and prints what `dryRun` returns (glue, in `fw.ts`); the kind,
the log lines, the single `VERDICT` line and the exit code all come from the functions below. -/

/-- The stages of a dry run in their fixed order; `exception` is anything outside the five modelled stages (a thrown exception, a
precondition refusal such as an unknown task, a failed evidence write): it ends the run, so it comes first. -/
inductive DStage where
  | exception | stale | empty | scope | conflict | reads | lint
deriving DecidableEq, Repr

/-- The position of a stage in the fixed order. -/
def DStage.rank : DStage → Nat
  | .exception => 0 | .stale => 1 | .empty => 2 | .scope => 3 | .conflict => 4 | .reads => 5 | .lint => 6

/-- The word in the log line of a stage that passed. -/
def DStage.name : DStage → String
  | .exception => "exception" | .stale => "stale" | .empty => "empty" | .scope => "scope" | .conflict => "conflict"
  | .reads => "reads" | .lint => "lint"

/-- The verdict kind a dry run prints when it stops at a stage. -/
def DStage.kind : DStage → Kind
  | .exception => .unknown | .stale => .stale | .empty => .empty | .scope => .scope | .conflict => .conflict
  | .reads => .reads | .lint => .lint

/-- The outcome of every stage of one dry run. `threw` is true when something outside the modelled stages stopped the run; the other
fields are true when that stage did not stop the run. A stage the run never reached is true: it cannot change the result, since only
the first stopping stage counts (`Outcome.first`). -/
structure Outcome where
  threw : Bool
  fresh : Bool
  own : Bool
  scope : Bool
  merges : Bool
  reads : Bool
  lints : Bool

/-- Does the run get past a stage? -/
def Outcome.passes (o : Outcome) : DStage → Bool
  | .exception => !o.threw | .stale => o.fresh | .empty => o.own | .scope => o.scope | .conflict => o.merges
  | .reads => o.reads | .lint => o.lints

/-- The stages in order. -/
def DStage.order : List DStage := [.exception, .stale, .empty, .scope, .conflict, .reads, .lint]

/-- The first stage that stops the run, in the fixed order (`none`: every stage passed). -/
def Outcome.first (o : Outcome) : Option DStage :=
  if o.threw then some .exception else if !o.fresh then some .stale else if !o.own then some .empty
  else if !o.scope then some .scope else if !o.merges then some .conflict else if !o.reads then some .reads
  else if !o.lints then some .lint else none

/-- The kind a dry run prints: the kind of the first stopping stage, `dry` when none stops. -/
def Outcome.kind (o : Outcome) : Kind := match o.first with | some s => s.kind | none => .dry

/-- The log lines of a dry run: one line `dry: <stage> ok` for each stage before the first stopping one. -/
def Outcome.log (o : Outcome) : List String := (DStage.order.takeWhile o.passes).map fun s => "dry: " ++ s.name ++ " ok"

/-- **The dry run**: every line it prints on stdout, as a function of the stage outcomes and the task: the log lines, then the one
verdict line of `Outcome.kind`. -/
def dryRun (o : Outcome) (task : String) : List String := o.log ++ [verdictLine o.kind task]

/-- The outcome of the three `Stages` functions on `(m_0, b)` with no exception. -/
def Outcome.ofStages (w : Stages) (contains : Bool) (m0 b : String) : Outcome :=
  ⟨false, contains, w.own m0 b, w.scope m0 b, w.merges m0 b, w.reads m0 b, w.lints m0 b⟩

/-- **The first stopping stage is the first failing one.** If the run stops at `s`, `s` fails and every earlier stage passed;
and no stage stops the run exactly when all seven pass. -/
theorem first_spec (o : Outcome) :
    (∀ s, o.first = some s → o.passes s = false ∧ ∀ s', s'.rank < s.rank → o.passes s' = true) ∧
    (o.first = none ↔ ∀ s, o.passes s = true) := by
  obtain ⟨a, b, c, d, e, f, g⟩ := o
  refine ⟨?_, ?_⟩
  · intro s h
    cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> cases g <;> cases s <;>
      simp_all [Outcome.first, Outcome.passes] <;> intro s' <;> cases s' <;> simp_all [DStage.rank]
  · constructor
    · intro h s
      cases a <;> cases b <;> cases c <;> cases d <;> cases e <;> cases f <;> cases g <;> cases s <;>
        simp_all [Outcome.first, Outcome.passes]
    · intro h
      have h0 := h .exception; have h1 := h .stale; have h2 := h .empty; have h3 := h .scope
      have h4 := h .conflict; have h5 := h .reads; have h6 := h .lint
      simp_all [Outcome.passes, Outcome.first]

/-- **Exactly one VERDICT line.** Whatever the stage outcomes (any refusal, an exception, an empty branch, a pass), the lines the
dry run prints contain exactly one that starts with `VERDICT `, it is the last line, and it is the verdict line of the kind. -/
theorem dryRun_one_verdict (o : Outcome) (t : String) :
    ((dryRun o t).filter (·.startsWith "VERDICT ")).length = 1 ∧ (dryRun o t).getLast? = some (verdictLine o.kind t) := by
  have hlog : o.log.filter (·.startsWith "VERDICT ") = [] := by
    apply List.filter_eq_nil_iff.mpr
    intro l hl
    simp only [Outcome.log, List.mem_map] at hl
    obtain ⟨s, _, rfl⟩ := hl
    cases s <;> decide +kernel
  refine ⟨?_, by simp [dryRun]⟩
  simp [dryRun, List.filter_append, hlog, verdictLine]

/-- **The kind is the first failing stage's kind.** For all outcomes: the kind is `dry` exactly when all stages pass, otherwise the
kind of the lowest-ranked failing stage. -/
theorem kind_spec (o : Outcome) (k : Kind) :
    o.kind = k ↔ (k = .dry ∧ ∀ s, o.passes s = true) ∨
      ∃ s, k = s.kind ∧ o.passes s = false ∧ ∀ s', s'.rank < s.rank → o.passes s' = true := by
  have ⟨h1, h2⟩ := first_spec o
  constructor
  · intro h
    cases hf : o.first with
    | none => left; exact ⟨by simpa [Outcome.kind, hf] using h.symm, h2.mp hf⟩
    | some s => right; exact ⟨s, by simpa [Outcome.kind, hf] using h.symm, h1 s hf⟩
  · rintro (⟨rfl, h⟩ | ⟨s, rfl, hs, hb⟩)
    · simp [Outcome.kind, h2.mpr h]
    · cases hf : o.first with
      | none => have := h2.mp hf s; simp_all
      | some s2 =>
        have ⟨a1, a2⟩ := h1 s2 hf
        have : s = s2 := by
          refine Classical.byContradiction fun hne => ?_
          have hr : s.rank ≠ s2.rank := fun h => hne (by cases s <;> cases s2 <;> simp_all [DStage.rank])
          rcases Nat.lt_or_gt_of_ne hr with hl | hl
          · have := a2 s hl; simp_all
          · have := hb s2 hl; simp_all
        subst this; simp [Outcome.kind, hf]

/-- **The model is the dry kind.** For the outcome of the `Stages` functions the run's kind is `dryKind`, so every theorem about
`dryKind` (`dry_pass_land_pass`, `dry_iff_land_pass`, ...) is about the kind the dry run prints. -/
theorem kind_ofStages (w : Stages) (c : Bool) (m0 b : String) : (Outcome.ofStages w c m0 b).kind = dryKind w c m0 b := by
  cases c <;> cases ho : w.own m0 b <;> cases hs : w.scope m0 b <;> cases hm : w.merges m0 b <;> cases hr : w.reads m0 b <;>
    cases hn : w.lints m0 b <;>
    simp [Outcome.kind, Outcome.first, Outcome.ofStages, dryKind, landStages, firstRefusal, hs, hm, hr, ho, hn, DStage.kind, Stage.kind]

/-! ### Which lints a dry run runs -/

/-- The fast lints a dry run can run. -/
inductive Lint where
  | ciPaths | axioms
deriving DecidableEq, Repr

/-- The command of a lint, run in the merge-tree worktree. -/
def Lint.argv : Lint → List String
  | .ciPaths => ["node", "scripts/ci-paths.mjs", "--check"]
  | .axioms => ["sh", "-c", "cd lean && LAKE_SLOT_LIB=1 . ../scripts/lake-slot.sh && (lake_slot .. lake build) >&2 && sh scripts/axiom-check.sh"]

/-- The lints a dry run runs, given the changed paths and whether the tree has each script: `ci-paths` whenever its script exists,
the axiom check when its script exists and some changed path is under `lean/`. -/
def lintPlan (changed : List String) (hasCiPaths hasAxioms : Bool) : List Lint :=
  (if hasCiPaths then [Lint.ciPaths] else []) ++
  (if hasAxioms && changed.any (·.startsWith "lean/") then [Lint.axioms] else [])

/-- **ci-paths runs exactly when its script exists.** -/
theorem ciPaths_mem_plan (P : List String) (a v : Bool) : Lint.ciPaths ∈ lintPlan P a v ↔ a = true := by
  cases a <;> cases v <;> simp [lintPlan]

/-- **The axiom check runs exactly when its script exists and the change touches `lean/`.** -/
theorem axioms_mem_plan (P : List String) (a v : Bool) :
    Lint.axioms ∈ lintPlan P a v ↔ (v = true ∧ ∃ p ∈ P, p.startsWith "lean/" = true) := by
  cases a <;> cases v <;> simp [lintPlan]

/-- A change that touches no path under `lean/` never runs the axiom check. -/
theorem no_axioms_without_lean (P : List String) (a v : Bool) (h : ∀ p ∈ P, p.startsWith "lean/" = false) :
    Lint.axioms ∉ lintPlan P a v := by
  rw [axioms_mem_plan]
  rintro ⟨_, p, hp, hs⟩
  have := h p hp; simp_all

/-- The lint stage passes iff every planned lint passed. -/
def lintsPass (plan : List Lint) (r : Lint → Bool) : Bool := plan.all r

/-- **Lints pass iff each planned lint passes.** -/
theorem lintsPass_iff (plan : List Lint) (r : Lint → Bool) : lintsPass plan r = true ↔ ∀ l ∈ plan, r l = true := by
  simp [lintsPass]

/-! ### The real land prints the same kind for the same failure -/

/-- The stage names of `check.sh` that the dry lint stage runs (its command is `lake build` then the axiom check). -/
def lintStages : List String := ["lake build", "axiom check"]

/-- One failed check of the real land: did its output match the reads test, and which `check.sh` stages did it report failed? -/
abbrev FailedCheck := Bool × List String

/-- The kind of the real land's `checks` refusal from its failed checks: `reads` if any is a reads failure, else `lint` if every
failed check reported failed stages and all of them are lint stages, else `checks`. -/
def checkFailKind (fs : List FailedCheck) : Kind :=
  if fs.any (·.1) then .reads
  else if !fs.isEmpty && fs.all (fun f => !f.2.isEmpty && f.2.all (· ∈ lintStages)) then .lint else .checks

/-- A failure of the real land that a dry stage models. -/
inductive RealFailure where
  | scope | conflict | checks (fs : List FailedCheck)

/-- The kind the real land prints for a failure. -/
def RealFailure.kind : RealFailure → Kind
  | .scope => .scope | .conflict => .conflict | .checks fs => checkFailKind fs

/-- The real failure each refusing dry stage models (`none` for the stages with no real counterpart: an exception, `stale`, `empty`). -/
def DStage.real : DStage → Option RealFailure
  | .scope => some .scope | .conflict => some .conflict | .reads => some (.checks [(true, [])])
  | .lint => some (.checks [(false, lintStages)]) | _ => none

/-- **The dry kind is the real kind for every stage the dry run models.** If a dry stage has a real counterpart, the real land
prints the dry stage's kind for it (so a lint or compile failure is `lint` in both). -/
theorem dry_kind_is_real_kind (s : DStage) (r : RealFailure) (h : s.real = some r) : r.kind = s.kind := by
  cases s <;> simp [DStage.real] at h <;> subst h <;> decide

/-- Any non-empty set of failed lint stages (only `lake build` and `axiom check`) from one check is a `lint` in the real land. -/
theorem lint_stages_are_lint (S : List String) (hne : S ≠ []) (h : ∀ n ∈ S, n ∈ lintStages) :
    checkFailKind [(false, S)] = .lint := by
  have : S.isEmpty = false := by cases S <;> simp_all
  simp [checkFailKind, this]; exact h

/-- A failed check that is neither a reads failure nor only lint stages stays `checks`. -/
theorem other_check_is_checks : checkFailKind [(false, [])] = .checks := by decide

/-- An empty branch (contains main, no own commits) is a success with exit 0 and prints `VERDICT empty`. -/
theorem empty_ok (w : Stages) (m0 b : String) (h : w.own m0 b = false) :
    dryKind w true m0 b = .empty ∧ Kind.exitCode .empty = 0 := by
  simp [dryKind, h, Kind.exitCode]

/-- A premise row: id, statement, the theorems that assume it, and the test that asserts it. -/
structure PremiseRow where
  id : String
  statement : String
  theorems : List String
  test : String

/-- The premises of this module (2 rows, distinct ids; `land.checkDeterministic` and `land.mergeTreeReproduces` are in
`Fw.Console.LandSpeed.premises`). -/
def premises : List PremiseRow := [
  ⟨"land.dryStagesAreLandStages", "the dry land's scope, merge and reads stages are the real land's, on the same commit tree",
    ["dry_pass_land_pass", "dry_refusal_is_land_refusal", "dry_iff_land_pass", "handback_pass_land_pass"],
    "apps/runner/test/land-dry.test.ts: for each of scope, conflict, reads and a pass, a fixture repo gives the dry kind and then the real land the same stage"⟩,
  ⟨"land.dryTakesNoLock", "a dry land creates no lock file, no queue entry and leaves main's HEAD and working tree unchanged",
    ["dryKind_cases"], "apps/runner/test/land-dry.test.ts: main's HEAD and tracked status, the lock file and the queue file are identical before and after"⟩]

#guard premises.length == 2
#guard (premises.map (·.id)).eraseDups.length == premises.length

/-! ## Golden vectors (`packages/contracts/golden/console/land-dry.jsonl`) -/

open Lean

/-- One golden line: its name, the request object and the response object. -/
def line (name : String) (req resp : List (String × Json)) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj req), ("response", Json.mkObj resp)]

/-- A `landVerdict.kind` case: the reply is the kind's name, exit code, success flag, retry flag and the line for task `t`. -/
def kindCase (k : Kind) (t : String) : Json :=
  line s!"kind {k.name}" [("op", "landVerdict.kind"), ("kind", k.name), ("task", t)]
    [("exit", toJson k.exitCode), ("ok", .bool k.ok), ("retry", .bool k.retryable), ("line", .str (verdictLine k t))]

/-- A `landDry.verdict` case over given stage verdicts: the reply is `dryKind` for a stage table that returns exactly these. -/
def dryCase (name : String) (contains scope merges sel test : Bool) (own lints : Bool := true) : Json :=
  let w : Stages := ⟨fun _ _ => scope, fun _ _ => merges, fun _ _ => sel, fun _ _ => test, fun _ _ => own, fun _ _ => lints⟩
  line name [("op", "landDry.verdict"), ("containsMain", .bool contains), ("scope", .bool scope), ("merges", .bool merges),
      ("readsSelected", .bool sel), ("readsTest", .bool test), ("own", .bool own), ("lints", .bool lints)]
    [("kind", .str (dryKind w contains "m" "b").name)]

/-- A `landDry.handback` case: the reply is `handbackAllowed`. -/
def handbackCase (k : Kind) : Json :=
  line s!"handback {k.name}" [("op", "landDry.handback"), ("kind", k.name)] [("allowed", .bool (handbackAllowed k))]

/-- A `landDry.run` case: the stage outcome and task in, every printed line, the kind and the exit code out. -/
def runCase (o : Outcome) (t : String) : Json :=
  line s!"run {o.threw} {o.fresh} {o.own} {o.scope} {o.merges} {o.reads} {o.lints}"
    [("op", "landDry.run"), ("threw", .bool o.threw), ("fresh", .bool o.fresh), ("own", .bool o.own), ("scope", .bool o.scope),
      ("merges", .bool o.merges), ("reads", .bool o.reads), ("lints", .bool o.lints), ("task", t)]
    [("lines", toJson (dryRun o t)), ("kind", .str o.kind.name), ("exit", toJson o.kind.exitCode)]

/-- All `2^7 = 128` stage outcomes, in a fixed order. -/
def outcomes : List Outcome :=
  let bs := [true, false]
  bs.flatMap fun a => bs.flatMap fun b => bs.flatMap fun c => bs.flatMap fun d => bs.flatMap fun e => bs.flatMap fun f =>
    bs.map fun g => ⟨a, b, c, d, e, f, g⟩

/-- A `landDry.lintPlan` case: the argv list of the lints run. -/
def planCase (name : String) (changed : List String) (a v : Bool) : Json :=
  line name [("op", "landDry.lintPlan"), ("changed", toJson changed), ("hasCiPaths", .bool a), ("hasAxioms", .bool v)]
    [("argv", toJson ((lintPlan changed a v).map Lint.argv))]

/-- A `landDry.checkKind` case: the kind of the real land's refusal from its failed checks (each: reads-test match, failed stages). -/
def ckCase (name : String) (fs : List FailedCheck) : Json :=
  line name [("op", "landDry.checkKind"), ("failed", toJson (fs.map fun f => Json.mkObj [("reads", .bool f.1), ("stages", toJson f.2)]))]
    [("kind", .str (checkFailKind fs).name)]

/-- Every golden case: 14 kinds, one kind without a task, 15 dry-verdict cases, 14 hand-back cases, 129 dry-run cases (all 128 stage
outcomes and one without a task), 7 lint-plan cases, 9 real-kind cases. -/
def cases (_ : Unit := ()) : List Json :=
  Kind.all.map (kindCase · "land-dry") ++
  [kindCase .dry "",
   dryCase "all pass" true true true true true,
   dryCase "all pass, reads not selected (test not run)" true true true false true,
   dryCase "scope refuses first" true false false true false,
   dryCase "conflict refuses before reads" true true false true false,
   dryCase "reads refuses" true true true true false,
   dryCase "reads failing but not selected passes" true true true false false,
   dryCase "stale beats scope" false false true true true,
   dryCase "stale though all stages pass" false true true true true,
   dryCase "scope and reads both fail: scope first" true false true true false,
   dryCase "no own commits: empty" true true true true true (own := false),
   dryCase "no own commits beats a failing scope" true false false true false (own := false),
   dryCase "stale beats empty" false true true true true (own := false),
   dryCase "fast lint fails after all stages pass" true true true true true (lints := false),
   dryCase "reads refuses before lint" true true true true false (lints := false),
   dryCase "lint fails though reads not selected" true true true false false (lints := false)] ++
  Kind.all.map handbackCase ++ outcomes.map (runCase · "land-dry") ++ [runCase ⟨false, true, true, true, true, true, true⟩ ""] ++
  [planCase "plan: no lean change" ["apps/x.ts"] true true, planCase "plan: lean change" ["apps/x.ts", "lean/Fw/X.lean"] true true,
   planCase "plan: lean change, no axiom-check script" ["lean/Fw/X.lean"] true false, planCase "plan: no ci-paths script" ["lean/Fw/X.lean"] false true,
   planCase "plan: nothing changed" [] true true, planCase "plan: lean-like prefix is not lean" ["leanx/a", "apps/lean/b"] true true,
   planCase "plan: no scripts" ["lean/a"] false false] ++
  [ckCase "real: reads wins" [(true, ["axiom check"]), (false, [])], ckCase "real: axiom check only" [(false, ["axiom check"])],
   ckCase "real: lake build only" [(false, ["lake build"])], ckCase "real: both lint stages" [(false, ["lake build", "axiom check"])],
   ckCase "real: lint and test" [(false, ["axiom check", "lake test"])], ckCase "real: no stage reported" [(false, [])],
   ckCase "real: lint check and a plain check" [(false, ["axiom check"]), (false, [])], ckCase "real: two lint checks" [(false, ["lake build"]), (false, ["axiom check"])],
   ckCase "real: no failed check" []]

#guard cases.length == 189

/-- The golden file text: one compressed JSON line per case. -/
def goldenText (_ : Unit := ()) : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-dry.jsonl"

/-- Write the golden file (IO). -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output? (IO) -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.LandDry
