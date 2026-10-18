import Lean.Data.Json
import Fw.Console.LandVerdict
/-!
# `fw land <branch> --task <id> --dry`: the refusals of a land, found before the land

Incident rows `inc-land-undeclared-reads` (4 lands refused for an undeclared read, each a ~5 min land plus a lead fix) and
`inc-land-scope-stale-base` (a stale merge base carried another task's diff into the scope check). A real land does its
cheap, deterministic stages (scope, merge, the static reads test) first and then runs the long checks; a dry land runs
only those cheap stages, takes no lock and runs no full check, so an agent can learn the refusal before it hands back.

Model. The three stages are functions of the facts a land starts from: the main commit $m$ and the branch tip $b$ (the work
graph and the allow list come from $m$ and the land command). A dry land and the real land evaluate the *same* functions;
the dry land builds the same merge commit (`merge-tree` of $m$ and $b$, plus the task's evidence) and checks the same tree.
The one thing that can differ is $m$: the real land reads it later.

* `landStages` is the real land's first refusal among scope, merge (conflict) and reads, in that order;
* `dryKind` is the dry land's kind: `stale` when the branch lacks `main`, else the same first refusal, else `dry`;
* `dry_pass_land_pass`: dry passes and main has not moved, so the real land passes scope, merge and reads;
* `handback_pass_land_pass`: a hand-back rule "only when the dry land says `dry`" never leaves a scope, reads or conflict
  refusal for the land (unless main moved: `moved_no_guarantee`).

Premises (registry rows in `premises`): the stages are deterministic functions of $(m, b)$ (`land.dryStagesAreLandStages`,
`land.checkDeterministic` of `Fw.Console.LandSpeed`), and `git merge-tree --write-tree` fails exactly when `git merge`
conflicts (`land.mergeTreeReproduces`).

Golden vectors: `packages/contracts/golden/console/land-dry.jsonl` (`goldenText`; ops `landVerdict.kind`, `landDry.verdict`,
`landDry.handback`). Write or check with `lake env lean --run` on a two-line script calling `writeGolden` / `checkGolden`.
-/
namespace Fw.Console.LandDry
open Fw.Console.LandVerdict

/-- The pure stage functions of a land, of the main commit $m$ and the branch tip $b$: the scope check of the diff, the
clean merge, whether `apps/runner` is selected by the change (so the static reads test is part of the real checks), and
that test's verdict on the merge tree, whether the branch has commits of its own, and the fast lints (the math-view lint and
`ci-paths --check`, run on the merge tree) that refused real lands (task `land-dry-full`).
$$W = (\mathit{scope}, \mathit{merges}, \mathit{sel}, \mathit{test}, \mathit{own}, \mathit{lints}) : (M \times B \to \mathbb B)^6$$ -/
structure Stages where
  scope : String → String → Bool
  merges : String → String → Bool
  readsSelected : String → String → Bool
  readsTest : String → String → Bool
  own : String → String → Bool
  lints : String → String → Bool

/-- The reads stage: a check that the change does not select cannot refuse.
$$\operatorname{rd}(m, b) = \lnot\mathit{sel}(m, b) \vee \mathit{test}(m, b)$$ -/
def Stages.reads (w : Stages) (m b : String) : Bool := !(w.readsSelected m b) || w.readsTest m b

/-- The cheap stages of a land, in the order the land runs them.
$$\mathrm{Stage} = \{\mathrm{scope}, \mathrm{conflict}, \mathrm{reads}\}$$ -/
inductive Stage where
  | scope | conflict | reads
deriving DecidableEq, Repr

/-- The verdict kind a refusal at a stage prints.
$$\operatorname{kind}(\mathrm{scope}) = \mathrm{scope},\ \operatorname{kind}(\mathrm{conflict}) = \mathrm{conflict},\ \operatorname{kind}(\mathrm{reads}) = \mathrm{reads}$$ -/
def Stage.kind : Stage → Kind
  | .scope => .scope | .conflict => .conflict | .reads => .reads

/-- The first refusal among the stage verdicts, in land order: scope, then merge, then reads (`none`: all pass).
$$\operatorname{first}(s, g, r) = \begin{cases} \mathrm{scope} & \lnot s \\ \mathrm{conflict} & s \wedge \lnot g \\ \mathrm{reads} & s \wedge g \wedge \lnot r \\ \bot & s \wedge g \wedge r \end{cases}$$ -/
def firstRefusal (s g r : Bool) : Option Stage :=
  if !s then some .scope else if !g then some .conflict else if !r then some .reads else none

/-- The first refusal of the real land's cheap stages, when main is at $h$.
$$\operatorname{land}_W(h, b) = \operatorname{first}(\mathit{scope}(h,b), \mathit{merges}(h,b), \operatorname{rd}(h,b))$$ -/
def landStages (w : Stages) (h b : String) : Option Stage := firstRefusal (w.scope h b) (w.merges h b) (w.reads h b)

/-- The kind of a dry land at main $m_0$: `stale` when the branch does not contain `main`, `empty` when it has no commit of its
own (nothing to land, a success), else the first refusal of the three stages, else `lint` when a fast lint fails, else `dry`.
$$\operatorname{dry}_W(c, m_0, b) = \begin{cases} \mathrm{stale} & \lnot c \\ \mathrm{empty} & c \wedge \lnot\mathit{own}(m_0,b) \\ k & c \wedge \mathit{own} \wedge \operatorname{land}_W(m_0, b) = \mathrm{some}(k) \\ \mathrm{lint} & c \wedge \mathit{own} \wedge \operatorname{land}_W = \bot \wedge \lnot\mathit{lints}(m_0,b) \\ \mathrm{dry} & \text{otherwise} \end{cases}$$ -/
def dryKind (w : Stages) (contains : Bool) (m0 b : String) : Kind :=
  if !contains then .stale else
  if !(w.own m0 b) then .empty else
  match landStages w m0 b with
  | some s => s.kind
  | none => if w.lints m0 b then .dry else .lint

/-- The three stages pass iff each passes.
$$\operatorname{first}(s, g, r) = \bot \iff s \wedge g \wedge r$$ -/
theorem firstRefusal_none_iff (s g r : Bool) : firstRefusal s g r = none ↔ (s = true ∧ g = true ∧ r = true) := by
  cases s <;> cases g <;> cases r <;> simp [firstRefusal]

/-- **A dry pass is a land pass.** If the dry land says `dry` and main has not moved ($h = m_0$), the real land's scope, merge
and reads stages pass.
$$\forall W, c, m_0, h, b:\ \operatorname{dry}_W(c, m_0, b) = \mathrm{dry} \wedge h = m_0 \Rightarrow \operatorname{land}_W(h, b) = \bot$$ -/
theorem dry_pass_land_pass (w : Stages) (c : Bool) (m0 h b : String) (hd : dryKind w c m0 b = .dry) (hh : h = m0) :
    landStages w h b = none := by
  subst hh
  cases c <;> cases ho : w.own h b <;> cases hl : landStages w h b <;> cases hn : w.lints h b <;>
    simp [dryKind, hl, ho, hn] at hd ⊢
  all_goals (rename_i s; cases s <;> simp [Stage.kind] at hd)

/-- **A dry refusal is the land's refusal.** If the dry land refuses with the kind of a stage and main has not moved, the
real land refuses at that stage.
$$\forall W, c, m_0, h, b, s:\ \operatorname{dry}_W(c, m_0, b) = \operatorname{kind}(s) \wedge h = m_0 \Rightarrow \operatorname{land}_W(h, b) = \mathrm{some}(s)$$ -/
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
when the branch has its own commits, the real land's stages pass and the fast lints pass.
$$\forall W, m_0, h, b:\ h = m_0 \Rightarrow (\operatorname{dry}_W(\mathrm{true}, m_0, b) = \mathrm{dry} \iff \mathit{own} \wedge \operatorname{land}_W(h, b) = \bot \wedge \mathit{lints})$$ -/
theorem dry_iff_land_pass (w : Stages) (m0 h b : String) (hh : h = m0) :
    dryKind w true m0 b = .dry ↔ (w.own m0 b = true ∧ landStages w h b = none ∧ w.lints m0 b = true) := by
  subst hh
  cases ho : w.own h b <;> cases hl : landStages w h b <;> cases hn : w.lints h b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

/-- **The dry land passes only if scope, merge, reads and the fast lints pass** (and the branch has commits and contains main).
$$\forall W, c, m_0, b:\ \operatorname{dry}_W(c, m_0, b) = \mathrm{dry} \Rightarrow c \wedge \mathit{own}(m_0,b) \wedge \mathit{scope} \wedge \mathit{merges} \wedge \operatorname{rd} \wedge \mathit{lints}(m_0,b)$$ -/
theorem dry_pass_all (w : Stages) (c : Bool) (m0 b : String) (hd : dryKind w c m0 b = .dry) :
    c = true ∧ w.own m0 b = true ∧ w.scope m0 b = true ∧ w.merges m0 b = true ∧ w.reads m0 b = true ∧ w.lints m0 b = true := by
  have hl := dry_pass_land_pass w c m0 m0 b hd rfl
  have hf := (firstRefusal_none_iff _ _ _).mp (by simpa [landStages] using hl)
  cases c <;> cases ho : w.own m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, ho, hn] at hd ⊢
  all_goals (try cases hl2 : landStages w m0 b <;> simp [hl2] at hd)
  all_goals (try (rename_i s; cases s <;> simp [Stage.kind] at hd))
  all_goals simp_all

/-- A `stale` verdict is given exactly when the branch lacks `main`.
$$\forall W, c, m_0, b:\ \operatorname{dry}_W(c, m_0, b) = \mathrm{stale} \iff \lnot c$$ -/
theorem stale_iff (w : Stages) (c : Bool) (m0 b : String) : dryKind w c m0 b = .stale ↔ c = false := by
  cases c <;> cases ho : w.own m0 b <;> cases hl : landStages w m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

/-- The hand-back rule: an agent may hand back only on a `dry` verdict.
$$\operatorname{hb}(k) \iff k = \mathrm{dry}$$ -/
def handbackAllowed (k : Kind) : Bool := k == .dry

/-- **A hand-back that obeys the rule is not refused at scope, merge or reads.** The agent merged `main` into its branch and
the dry land said `dry`; if main has not moved when the land starts, none of the three stages refuses (the four 2026-10-18
reads refusals and the stale-base scope refusal could not have happened).
$$\forall W, c, m_0, h, b:\ \operatorname{hb}(\operatorname{dry}_W(c, m_0, b)) \wedge h = m_0 \Rightarrow \operatorname{land}_W(h, b) = \bot$$ -/
theorem handback_pass_land_pass (w : Stages) (c : Bool) (m0 h b : String) (ha : handbackAllowed (dryKind w c m0 b) = true)
    (hh : h = m0) : landStages w h b = none := by
  apply dry_pass_land_pass w c m0 h b _ hh
  simpa [handbackAllowed] using ha

/-- **Moved main voids the guarantee.** There are stage functions and commits where the dry land passes at $m_0$ and the real
land refuses at a later $h \ne m_0$ (a land that follows a lead land can still be refused: the dry verdict names the main it
ran against).
$$\exists W, m_0, h, b:\ \operatorname{dry}_W(\mathrm{true}, m_0, b) = \mathrm{dry} \wedge h \ne m_0 \wedge \operatorname{land}_W(h, b) \ne \bot$$ -/
theorem moved_no_guarantee :
    ∃ (w : Stages) (m0 h b : String), dryKind w true m0 b = .dry ∧ h ≠ m0 ∧ landStages w h b ≠ none :=
  ⟨⟨fun m _ => m == "a", fun _ _ => true, fun _ _ => false, fun _ _ => true, fun _ _ => true, fun _ _ => true⟩, "a", "b", "t", by decide, by decide, by decide⟩

/-- **Only stage kinds, stale, empty, lint and dry come out of a dry land**: never `busy`, `dirty`, `checks`, `done`, `queued` or
`unknown` (it takes no lock, runs no full check and does not touch the main checkout).
$$\forall W, c, m_0, b:\ \operatorname{dry}_W(c, m_0, b) \in \{\mathrm{stale}, \mathrm{empty}, \mathrm{scope}, \mathrm{conflict}, \mathrm{reads}, \mathrm{lint}, \mathrm{dry}\}$$ -/
theorem dryKind_cases (w : Stages) (c : Bool) (m0 b : String) :
    dryKind w c m0 b = .stale ∨ dryKind w c m0 b = .empty ∨ dryKind w c m0 b = .scope ∨ dryKind w c m0 b = .conflict ∨
      dryKind w c m0 b = .reads ∨ dryKind w c m0 b = .lint ∨ dryKind w c m0 b = .dry := by
  cases c <;> cases ho : w.own m0 b <;> cases hl : landStages w m0 b <;> cases hn : w.lints m0 b <;> simp [dryKind, hl, ho, hn]
  all_goals (rename_i s; cases s <;> simp [Stage.kind])

/-- The lines a dry land prints on stdout: exactly the verdict line (prose goes to the log lines, which never start with
`VERDICT `).
$$\operatorname{out}(k, t) = [\operatorname{line}(k, t)]$$ -/
def dryOutput (k : Kind) (task : String) : List String := [verdictLine k task]

/-- **Every dry run prints exactly one VERDICT line**, whatever the stages say (a refusal, an empty branch, a pass): the number of
printed lines that start with `VERDICT ` is one.
$$\forall W, c, m_0, b, t:\ \left|\{\ell \in \operatorname{out}(\operatorname{dry}_W(c, m_0, b), t) : \ell \text{ starts with } \texttt{VERDICT }\}\right| = 1$$ -/
theorem dry_prints_one_verdict (w : Stages) (c : Bool) (m0 b t : String) :
    ((dryOutput (dryKind w c m0 b) t).filter (·.startsWith "VERDICT ")).length = 1 := by
  simp [dryOutput, verdictLine]

/-- An empty branch (contains main, no own commits) is a success with exit 0 and prints `VERDICT empty`.
$$\forall W, m_0, b:\ \lnot\mathit{own}(m_0,b) \Rightarrow \operatorname{dry}_W(\mathrm{true}, m_0, b) = \mathrm{empty} \wedge \operatorname{code}(\mathrm{empty}) = 0$$ -/
theorem empty_ok (w : Stages) (m0 b : String) (h : w.own m0 b = false) :
    dryKind w true m0 b = .empty ∧ Kind.exitCode .empty = 0 := by
  simp [dryKind, h, Kind.exitCode]

/-- A premise row: id, statement, the theorems that assume it, and the test that asserts it.
$$p = (\mathit{id},\ \mathit{statement},\ \mathit{theorems},\ \mathit{test})$$ -/
structure PremiseRow where
  id : String
  statement : String
  theorems : List String
  test : String

/-- The premises of this module (2 rows, distinct ids; `land.checkDeterministic` and `land.mergeTreeReproduces` are in
`Fw.Console.LandSpeed.premises`).
$$\mathrm{premises} = [p_1, p_2]$$ -/
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

/-- One golden line: its name, the request object and the response object.
$$\operatorname{line}(n, q, r) = \{\texttt{name}: n,\ \texttt{request}: q,\ \texttt{response}: r\}$$ -/
def line (name : String) (req resp : List (String × Json)) : Json :=
  Json.mkObj [("name", .str name), ("request", Json.mkObj req), ("response", Json.mkObj resp)]

/-- A `landVerdict.kind` case: the reply is the kind's name, exit code, success flag, retry flag and the line for task `t`.
$$\operatorname{kindCase}(k, t) = \operatorname{line}(\ldots, \{k, t\}, \{\operatorname{name}(k), \operatorname{code}(k), \operatorname{ok}(k), \operatorname{retry}(k), \operatorname{line}(k, t)\})$$ -/
def kindCase (k : Kind) (t : String) : Json :=
  line s!"kind {k.name}" [("op", "landVerdict.kind"), ("kind", k.name), ("task", t)]
    [("exit", toJson k.exitCode), ("ok", .bool k.ok), ("retry", .bool k.retryable), ("line", .str (verdictLine k t))]

/-- A `landDry.verdict` case over given stage verdicts: the reply is `dryKind` for a stage table that returns exactly these.
$$\operatorname{dryCase}(n, c, s, g, t, r) = \operatorname{line}(n, \{c, s, g, \mathit{sel}, \mathit{test}\}, \{\operatorname{dry}_W\})$$ -/
def dryCase (name : String) (contains scope merges sel test : Bool) (own lints : Bool := true) : Json :=
  let w : Stages := ⟨fun _ _ => scope, fun _ _ => merges, fun _ _ => sel, fun _ _ => test, fun _ _ => own, fun _ _ => lints⟩
  line name [("op", "landDry.verdict"), ("containsMain", .bool contains), ("scope", .bool scope), ("merges", .bool merges),
      ("readsSelected", .bool sel), ("readsTest", .bool test), ("own", .bool own), ("lints", .bool lints)]
    [("kind", .str (dryKind w contains "m" "b").name)]

/-- A `landDry.handback` case: the reply is `handbackAllowed`.
$$\operatorname{hbCase}(k) = \operatorname{line}(\ldots, \{k\}, \{\operatorname{hb}(k)\})$$ -/
def handbackCase (k : Kind) : Json :=
  line s!"handback {k.name}" [("op", "landDry.handback"), ("kind", k.name)] [("allowed", .bool (handbackAllowed k))]

/-- Every golden case: 13 kinds, one kind without a task, 15 dry-verdict cases, 13 hand-back cases.
$$\mathrm{cases} = \mathrm{kind}_{1..14} \mathbin{+\!\!+} \mathrm{dry}_{1..15} \mathbin{+\!\!+} \mathrm{hb}_{1..13}$$ -/
def cases : List Json :=
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
  Kind.all.map handbackCase

#guard cases.length == 42

/-- The golden file text: one compressed JSON line per case.
$$\mathrm{goldenText} = \operatorname{concat}[\, \operatorname{compress}(c) \mathbin{+\!\!+} \text{"\textbackslash n"} \,]_{c \in \mathrm{cases}}$$ -/
def goldenText : String := String.join (cases.map fun c => c.compress ++ "\n")

/-- The golden file, relative to `lean/`.
$$\mathrm{goldenPath} = \texttt{../packages/contracts/golden/console/land-dry.jsonl}$$ -/
def goldenPath : System.FilePath := "../packages/contracts/golden/console/land-dry.jsonl"

/-- Write the golden file (IO).
$$\mathrm{writeGolden}:\ \mathrm{goldenPath} \leftarrow \mathrm{goldenText}$$ -/
def writeGolden : IO Unit := IO.FS.writeFile goldenPath goldenText

/-- Is the golden file the Lean output? (IO)
$$\mathrm{checkGolden} \iff \operatorname{read}(\mathrm{goldenPath}) = \mathrm{goldenText}$$ -/
def checkGolden : IO Bool := do return (← IO.FS.readFile goldenPath) == goldenText

end Fw.Console.LandDry
