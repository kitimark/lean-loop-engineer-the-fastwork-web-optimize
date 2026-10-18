import Fw.Console.Preview
import Fw.Console.PreviewFacts
import Lean.Data.Json
/-!
# The preview target of the 25 `port-` / `fix-` tasks, proved over facts extracted from git

`task-preview` round 2. The repository facts of the 25 `port-` / `fix-` tasks of `docs/team/work-graph.json` are
**generated** from git at a pinned state by `apps/console-api/scripts/gen-preview-facts.ts` into `PreviewFacts.lean`
(the console's own glue, `apps/console-api/src/preview/facts.ts`; pin `apps/console-api/golden/preview-facts.pin.json`).
This file holds only what a person types: for each task the target and head a preview should show. `table_matches`
proves that the Lean rule `Fw.Console.Preview.headOf` returns them over the machine-extracted facts. (Round 1 proved
a hand-typed fact table, so a wrong fact and a wrong expectation agreed: port-platform.) The same rows are the golden
`console.previewTarget.jsonl`, which the TypeScript glue is checked against.
-/
namespace Fw.Console.PreviewTable
open Fw.Console.Preview Fw.Console.PreviewFacts Lean

/-- The newest integration ref and its tip, as pinned.

$$r_3 = I_1$$ -/
def r3 : String := integ.head!.1
/-- The tip of the newest integration ref.

$$t_3 = I_1.\mathit{sha}$$ -/
def r3t : String := integ.head!.2
/-- The second integration ref.

$$r_2 = I_2$$ -/
def r2 : String := (integ.drop 1).head!.1

/-- What a preview should show for each task, typed by hand from the investigation and git (the facts are generated:
`PreviewFacts.lean`): the target and the head sha.

$$\mathrm{expects} : \mathit{task} \mapsto (\mathit{target}, \mathit{head})$$ -/
def expects : List (String × Target × Option String) := [
  ("port-parts", .none, none),
  ("port-morph", .integration r3 r3t, none),
  ("port-morph-mount", .main "ce9692e", some "7ba0436"),
  ("port-morph-tween", .main "a35b396", some "67c7afe"),
  ("port-morph-panel", .integration r3 r3t, some "64857cb"),
  ("port-morph-countdown", .main "6626359", some "43380c6"),
  ("port-morph-columns", .main "52a73a3", some "66cbb13"),
  ("port-nav", .integration r3 r3t, some "5e277bd"),
  ("port-hero", .integration r3 r3t, some "4d26f44"),
  ("port-people", .integration r3 r3t, some "103f4c0"),
  ("port-pain", .integration r3 r3t, some "5d7f00b"),
  ("port-commission", .integration r3 r3t, some "66debaa"),
  ("port-platform", .main "6e968ba", some "5b50ad0"),
  ("port-overlays", .integration r3 r3t, some "7aad851"),
  ("fix-nav", .integration r3 r3t, some "b00ef68"),
  ("fix-commission", .integration r3 r3t, some "3ed01af"),
  ("fix-misc", .integration r3 r3t, some "ef1774f"),
  ("fix-people-webkit", .integration r3 r3t, some "0f5cdb7"),
  ("fix-proofs", .none, none),
  ("fix-stagebg-webkit", .integration r3 r3t, some "f007b85"),
  ("fix-orbit", .integration r2 "26e5f53", some "26e5f53"),
  ("fix-pain-notes", .integration r3 r3t, some "3bcfa3a"),
  ("fix-nav-hittest", .integration r2 "26e5f53", some "26e5f53"),
  ("fix-commission-margin", .integration r3 r3t, some "3301169"),
  ("fix-page-offset", .integration r3 r3t, some "23c0821")]

/-- One task of the table: its generated facts, its sub-tasks' facts (umbrella), the expected target and head.

$$r = (\mathit{task}, \mathit{facts}, \mathit{kids}, \mathit{expect})$$ -/
structure Row where
  task : String
  facts : List Fact
  kids : List (List Fact)
  expect : Target
  expectHead : Option String

/-- The 25 rows: the generated facts joined with the typed expectations (a task without an expectation expects nothing,
so the proof fails).

$$|\mathrm{rows}| = 25$$ -/
def rows : List Row := factRows.map fun (t, fs, ks) =>
  let e := (expects.lookup t).getD (.own "no expectation", some "no expectation")
  { task := t, facts := fs, kids := ks, expect := e.1, expectHead := e.2 }

/-- **The Lean rule returns the expected head and target for all 25 tasks**, over the facts extracted from git. A landed
task previews its land commit on main; an unlanded one its newest admissible head.

$$\forall r \in \mathrm{rows}:\ \operatorname{headOf}(m, r.\mathit{facts}, r.\mathit{kids}).2 = r.\mathit{expect} \wedge \operatorname{sha}(\operatorname{headOf}(m, r.\mathit{facts}, r.\mathit{kids}).1) = r.\mathit{expectHead}$$ -/
theorem table_matches : rows.all (fun r =>
    (headOf mainSha r.facts r.kids).2 == r.expect &&
    ((headOf mainSha r.facts r.kids).1.map (·.sha)) == r.expectHead) = true := by
  decide +kernel

/-- **There are 25 rows.**

$$|\mathrm{rows}| = 25$$ -/
theorem table_size : rows.length = 25 := by decide +kernel

/-- **Every row has a typed expectation** (none falls back to the placeholder that cannot match).

$$\forall r \in \mathrm{rows}:\ r.\mathit{task} \in \operatorname{dom}(\mathrm{expects})$$ -/
theorem table_expects_all : rows.all (fun r => (expects.lookup r.task).isSome) = true := by decide +kernel

/-- **Row 13 is port-platform, whose head is the gate's commit and not the "merge main" commit.** The merge candidate
`b2e5ff1` is a main commit (second parent on main's first-parent line); it is inadmissible, and the older handoff commit
is behind `origin/ci/port-platform`.

$$\operatorname{pickHead}(\mathit{platform}.\mathit{facts}) = \mathtt{5b50ad0}$$ -/
theorem platform_head : ((rows.find? (·.task == "port-platform")).bind fun r => (pickHead r.facts).map (·.sha)) = some "5b50ad0" := by
  decide +kernel

/-- **A head that is a direct commit on main is its own land commit.** (A test row of the rule, not a repository fact.)

$$f.\mathit{fpLine} \Rightarrow \operatorname{headOf}(m, [f], [\,]).2 = \mathrm{main}(f.s)$$ -/
theorem direct_commit_lands_itself :
    (headOf "m1" [F "ci" "d1" true false true true false [] []] []).2 = .main "d1" := by decide +kernel

/-- **A merge from main's own line is never picked, even when it is the only held better-ranked candidate.**

$$\operatorname{pickHead}([\mathrm{merge}(\mathit{own}=\bot), \mathrm{originCi}]) = \mathrm{originCi}$$ -/
theorem main_merge_not_head :
    ((pickHead [F "merge" "b1" true false true false false [] [], F "originCi" "c1" true false false true false [] [("l1", true)]]).map (·.sha)) = some "c1" := by
  decide +kernel

/-- A candidate as the wire JSON.

$$\operatorname{factJson}(f) = \{\mathit{src}, \mathit{sha}, \mathit{onMain}, \mathit{noCode}, \mathit{fpLine}, \mathit{ownWork}, \mathit{behind}, \mathit{path}, \mathit{cands}\}$$ -/
def factJson (f : Fact) : Json :=
  Json.mkObj [("src", .str f.src), ("sha", .str f.sha), ("onMain", .bool f.onMain), ("noCode", .bool f.noCode),
    ("fpLine", .bool f.fpLine), ("ownWork", .bool f.ownWork), ("behind", .bool f.behind),
    ("path", .arr (f.path.toArray.map fun p => Json.mkObj [("sha", .str p.sha), ("p2Has", .bool p.p2Has)])),
    ("cands", .arr (f.cands.toArray.map fun c => Json.mkObj [("ref", .str c.ref), ("sha", .str c.sha), ("contains", .bool c.contains)]))]

/-- The `console.previewTarget` request of a row.

$$\operatorname{request}(r) = \{m, \mathit{facts}, \mathit{children}\}$$ -/
def request (r : Row) : Json :=
  Json.mkObj [("main", .str mainSha), ("facts", .arr (r.facts.toArray.map factJson)),
    ("children", .arr (r.kids.toArray.map fun ks => Json.mkObj [("facts", .arr (ks.toArray.map factJson))]))]

/-- The golden cases: one per task.

$$|\mathrm{goldenCases}| = |\mathrm{rows}|$$ -/
def goldenCases : List (String × Json) := rows.map fun r => (s!"{r.task}: the investigation's target", request r)

end Fw.Console.PreviewTable
