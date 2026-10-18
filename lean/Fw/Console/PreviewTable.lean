import Fw.Console.Preview
import Lean.Data.Json
/-!
# The preview target of the 25 `port-` / `fix-` tasks, checked against the investigation

`task-preview` round 2. The investigation (a read of the repository and the handoffs, 2026-10-18) names, for each of the
25 `port-` / `fix-` tasks of `docs/team/work-graph.json`, the commit a preview should show. This file holds the
repository facts the glue gathered for each task (`apps/console-api/src/preview/facts.ts`, candidates in priority order;
the integration refs newest first: `origin/ci/integrate-ports-3` b35b541, `integrate-ports-2` 26e5f53,
`origin/ci/integrate-ports-2` 14ca720, `origin/ci/integrate-ports` 30734ae; main 25d9402) and the investigation's answer, and
proves that the Lean rule `Fw.Console.Preview.headOf` returns it for every row (`table_matches`). The same rows
are the golden `console.previewTarget.jsonl`, which the TypeScript glue is checked against.
-/
namespace Fw.Console.PreviewTable
open Fw.Console.Preview Lean

/-- The integration refs of the investigation, newest first: name, tip.

$$I = [(\mathit{ref}_1, t_1), \dots, (\mathit{ref}_4, t_4)]$$ -/
def integ : List (String × String) :=
  [("origin/ci/integrate-ports-3", "b35b541"), ("integrate-ports-2", "26e5f53"),
   ("origin/ci/integrate-ports-2", "14ca720"), ("origin/ci/integrate-ports", "30734ae")]

/-- The newest integration ref.

$$\mathit{r}_3 = I_1$$ -/
def r3 : String := "origin/ci/integrate-ports-3"
/-- The second integration ref.

$$\mathit{r}_2 = I_2$$ -/
def r2 : String := "integrate-ports-2"
/-- The third integration ref.

$$\mathit{r}_{2o} = I_3$$ -/
def r2o : String := "origin/ci/integrate-ports-2"
/-- The oldest integration ref.

$$\mathit{r}_1 = I_4$$ -/
def r1 : String := "origin/ci/integrate-ports"

/-- A head candidate with the refs that contain it.

$$\mathit{contains}(c) \iff c.\mathit{ref} \in \mathit{holders}$$ -/
def mk (src sha : String) (onMain noCode : Bool) (holders : List String) : Fact :=
  { src, sha, onMain, noCode, cands := integ.map fun (r, s) => { ref := r, sha := s, contains := holders.contains r } }

/-- One task of the table: its facts, its sub-tasks' facts (umbrella), the investigation's target.

$$r = (\mathit{task}, \mathit{facts}, \mathit{kids}, \mathit{expect})$$ -/
structure Row where
  task : String
  facts : List Fact
  kids : List (List Fact)
  expect : Target

/-- The 25 rows.

$$|\mathrm{rows}| = 25$$ -/
def rows : List Row := [
  { task := "port-parts", facts := [],
    kids := [],
    expect := .none },
  { task := "port-morph", facts := [],
    kids := [[mk "originCi" "1f3e0f6" true false [r3, r2, r2o, r1], mk "merge" "7ba0436" true false [r3, r2, r2o, r1], mk "handoffCommit" "7ba0436" true false [r3, r2, r2o, r1]],
      [mk "originCi" "67c7afe" true false [r3, r2, r2o, r1], mk "merge" "67c7afe" true false [r3, r2, r2o, r1], mk "handoffCommit" "67c7afe" true false [r3, r2, r2o, r1]],
      [mk "originCi" "64857cb" false false [r3, r2, r2o, r1], mk "merge" "64857cb" false false [r3, r2, r2o, r1], mk "handoffCommit" "86d744c" false false [r3, r2, r2o, r1]],
      [mk "originCi" "43380c6" true false [r3, r2, r2o, r1], mk "merge" "43380c6" true false [r3, r2, r2o, r1], mk "handoffCommit" "43380c6" true false [r3, r2, r2o, r1]],
      [mk "originCi" "5c4d3bf" true false [r3, r2, r2o, r1], mk "merge" "66cbb13" true false [r3, r2, r2o, r1], mk "handoffCommit" "66cbb13" true false [r3, r2, r2o, r1]]],
    expect := .integration r3 "b35b541" },
  { task := "port-morph-mount", facts := [mk "originCi" "1f3e0f6" true false [r3, r2, r2o, r1],
      mk "merge" "7ba0436" true false [r3, r2, r2o, r1],
      mk "handoffCommit" "7ba0436" true false [r3, r2, r2o, r1]],
    kids := [],
    expect := .main "25d9402" },
  { task := "port-morph-tween", facts := [mk "originCi" "67c7afe" true false [r3, r2, r2o, r1],
      mk "merge" "67c7afe" true false [r3, r2, r2o, r1],
      mk "handoffCommit" "67c7afe" true false [r3, r2, r2o, r1]],
    kids := [],
    expect := .main "25d9402" },
  { task := "port-morph-panel", facts := [mk "originCi" "64857cb" false false [r3, r2, r2o, r1],
      mk "merge" "64857cb" false false [r3, r2, r2o, r1],
      mk "handoffCommit" "86d744c" false false [r3, r2, r2o, r1]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "port-morph-countdown", facts := [mk "originCi" "43380c6" true false [r3, r2, r2o, r1],
      mk "merge" "43380c6" true false [r3, r2, r2o, r1],
      mk "handoffCommit" "43380c6" true false [r3, r2, r2o, r1]],
    kids := [],
    expect := .main "25d9402" },
  { task := "port-morph-columns", facts := [mk "originCi" "5c4d3bf" true false [r3, r2, r2o, r1],
      mk "merge" "66cbb13" true false [r3, r2, r2o, r1],
      mk "handoffCommit" "66cbb13" true false [r3, r2, r2o, r1]],
    kids := [],
    expect := .main "25d9402" },
  { task := "port-nav", facts := [mk "originCi" "5bb3268" false false [r3, r2, r2o, r1],
      mk "merge" "5e277bd" false false [r3, r2, r2o, r1],
      mk "handoffCommit" "5e277bd" false false [r3, r2, r2o, r1]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "port-hero", facts := [mk "originCi" "4d26f44" false false [r3, r2, r2o, r1],
      mk "merge" "4d26f44" false false [r3, r2, r2o, r1],
      mk "handoffCommit" "eef94e6" false false [r3, r2, r2o, r1]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "port-people", facts := [mk "originCi" "8f83990" false false [r3, r2, r2o, r1],
      mk "merge" "103f4c0" false false [r3, r2, r2o, r1],
      mk "handoffCommit" "103f4c0" false false [r3, r2, r2o, r1]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "port-pain", facts := [mk "originCi" "5d7f00b" false false [r3, r2, r2o, r1],
      mk "merge" "5d7f00b" false false [r3, r2, r2o, r1],
      mk "handoffCommit" "5d7f00b" false false [r3, r2, r2o, r1]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "port-commission", facts := [mk "originCi" "66debaa" false false [r3, r2, r2o, r1],
      mk "merge" "66debaa" false false [r3, r2, r2o, r1],
      mk "handoffCommit" "66debaa" false false [r3, r2, r2o, r1]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "port-platform", facts := [mk "originCi" "5b50ad0" true false [r3, r2, r2o, r1],
      mk "merge" "b2e5ff1" true false [r3, r2, r2o, r1],
      mk "handoffCommit" "72971b8" true false [r3, r2, r2o, r1]],
    kids := [],
    expect := .main "25d9402" },
  { task := "port-overlays", facts := [mk "originCi" "7aad851" false false [r3, r2, r2o, r1],
      mk "merge" "7aad851" false false [r3, r2, r2o, r1],
      mk "handoffCommit" "7aad851" false false [r3, r2, r2o, r1]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "fix-nav", facts := [mk "originCi" "b8c380c" false false [r3, r2, r2o],
      mk "merge" "b00ef68" false false [r3, r2, r2o],
      mk "handoffCommit" "b00ef68" false false [r3, r2, r2o]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "fix-commission", facts := [mk "handoff" "3ed01af" false false [r3, r2, r2o],
      mk "originCi" "60a1d48" false false [r3, r2, r2o],
      mk "merge" "3ed01af" false false [r3, r2, r2o],
      mk "handoffCommit" "3ed01af" false false [r3, r2, r2o]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "fix-misc", facts := [mk "named" "ef1774f" false true [],
      mk "handoffCommit" "ef1774f" false true []],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "fix-people-webkit", facts := [mk "handoffCommit" "0f5cdb7" false true []],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "fix-proofs", facts := [],
    kids := [],
    expect := .none },
  { task := "fix-stagebg-webkit", facts := [mk "handoff" "f007b85" false false [r3, r2, r2o],
      mk "originCi" "4a9465f" false false [r3, r2, r2o],
      mk "merge" "f007b85" false false [r3, r2, r2o],
      mk "handoffCommit" "f007b85" false false [r3, r2, r2o]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "fix-orbit", facts := [mk "originCi" "26e5f53" false false [r3, r2]],
    kids := [],
    expect := .integration r2 "26e5f53" },
  { task := "fix-pain-notes", facts := [mk "originCi" "031dcd4" false false [r3],
      mk "handoffCommit" "3bcfa3a" false false [r3]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "fix-nav-hittest", facts := [mk "handoff" "ad919a4" false true [],
      mk "originCi" "26e5f53" false false [r3, r2],
      mk "handoffCommit" "ad919a4" false true []],
    kids := [],
    expect := .integration r2 "26e5f53" },
  { task := "fix-commission-margin", facts := [mk "handoff" "3301169" false false [r3],
      mk "originCi" "3130c08" false false [r3],
      mk "merge" "3301169" false false [r3],
      mk "handoffCommit" "068ea30" false false [r3]],
    kids := [],
    expect := .integration r3 "b35b541" },
  { task := "fix-page-offset", facts := [mk "originCi" "cb23d2b" false false [r3],
      mk "handoffCommit" "23c0821" false false [r3]],
    kids := [],
    expect := .integration r3 "b35b541" }]

/-- The main sha of the investigation.

$$m = \mathtt{25d9402}$$ -/
def mainSha : String := "25d9402"

/-- **The Lean rule returns the investigation's commit for all 25 tasks.**

$$\forall r \in \mathrm{rows}:\ \operatorname{headOf}(m, r.\mathit{facts}, r.\mathit{kids}).2 = r.\mathit{expect}$$ -/
theorem table_matches : rows.all (fun r => (headOf mainSha r.facts r.kids).2 == r.expect) = true := by decide +kernel

/-- **There are 25 rows.**

$$|\mathrm{rows}| = 25$$ -/
theorem table_size : rows.length = 25 := by decide +kernel

/-- A candidate as the wire JSON.

$$\operatorname{factJson}(f) = \{\mathit{src}, \mathit{sha}, \mathit{onMain}, \mathit{noCode}, \mathit{cands}\}$$ -/
def factJson (f : Fact) : Json :=
  Json.mkObj [("src", .str f.src), ("sha", .str f.sha), ("onMain", .bool f.onMain), ("noCode", .bool f.noCode),
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
