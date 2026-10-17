import Fw.Serve
/-!
# Golden vectors of the plan commands (`task.*`, `milestone.define`, the board plan)

`packages/contracts/golden/plan/*.jsonl`: one line per case, `{"name", "requests", "replies"}`.
`requests` are stateful `fwcore` request lines (`console.apply`, `console.replay`, `console.query`)
sent in order to a fresh server; `replies` are its reply lines. Generated from Lean, never by hand:

```
cd lean && lake test -- --write-plan-golden   # write the files, then run every test
cd lean && lake test                          # fail if a file is stale or a case differs
```

* `serve.jsonl`: the synthetic cases below (define, refused cycle, refused drop, claim, done,
  authority, replay, the board plan of a small graph). The check regenerates the file and compares it
  byte for byte, and replays every case.
* `work-graph.jsonl`: `docs/team/work-graph.json` as one case (milestones, then every task as a
  `task.define` in dependency order, then a query). Written from the JSON at generation time; the
  check replays the stored requests and compares the stored replies, so a later edit of the work
  graph does not make it stale (regenerate to refresh it).

`lake test` runs the check. Consumer: con-plan (console-web / console-api plan view).
-/
namespace Fw.Wire.Plan.Golden
open Lean Fw.Serve

/-- The golden directory, relative to the Lean package root. -/
def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "plan"

/-- A `console.apply` request for an event of the given key, actor, type and body fields. -/
def apply (key actor type : String) (fields : List (String × Json)) : Json :=
  Json.mkObj [("op", .str "console.apply"), ("event", Json.mkObj ([("key", .str key),
    ("ts", toJson (0 : Nat)), ("actor", .str actor), ("type", .str type)] ++ fields))]

/-- A `console.query` request. -/
def query : Json := Json.mkObj [("op", .str "console.query"), ("now", toJson (0 : Nat)), ("seq", toJson (0 : Nat))]

/-- The body fields of a `task.define`. -/
def defFields (task : String) (deps : List String) (milestone : Option String := none)
    (writes devices : List String := []) (evidence : Option String := none) : List (String × Json) :=
  [("task", .str task), ("title", .str s!"Task {task}"), ("stream", .str "lean"),
   ("milestone", ostr milestone), ("deps", strsJson deps), ("owner", .str "lean-prover"),
   ("writes", strsJson writes), ("devices", strsJson devices), ("evidence", ostr evidence)]

/-- A `task.define` by the lead (key `d:<task>` unless given). -/
def define (task : String) (deps : List String) (milestone : Option String := none)
    (writes devices : List String := []) (evidence : Option String := none)
    (key : String := s!"d:{task}") (actor : String := "lead") : Json :=
  apply key actor "task.define" (defFields task deps milestone writes devices evidence)

/-- The synthetic cases: (name, requests). -/
def cases : List (String × List Json) := [
  ("define: two tasks and a milestone, then the board plan", [
    apply "m:M0" "lead" "milestone.define" [("milestone", .str "M0"), ("title", .str "Start")],
    define "a" [] (some "M0"),
    define "b" ["a"] (some "M0"),
    query]),
  ("define: upsert keeps the claim and the evidence, replaces the definition", [
    define "a" [],
    apply "c:a" "hook" "task.claim" [("task", .str "a"), ("agent", .str "agent-1")],
    define "a" [] (some "M9") ["lean/A/**"] (key := "d2:a"),
    query]),
  ("refuse: dependency cycle, self dependency, undefined dep", [
    define "a" [],
    define "b" ["a"],
    define "a" ["b"] (key := "d2:a"),
    define "c" ["c"],
    define "d" ["zz"],
    query]),
  ("refuse: limits on title, deps, writes, devices", [
    apply "d:long" "lead" "task.define" ((defFields "long" []).map fun (k, v) =>
      if k == "title" then (k, .str (String.ofList (List.replicate 201 'x'))) else (k, v)),
    define "many" ((List.range 33).map toString),
    define "w" [] none ((List.range 33).map fun i => s!"f{i}"),
    define "v" [] none [] ((List.range 9).map fun i => s!"dev{i}"),
    query]),
  ("drop: refused while an undone task depends on it, refused when done, then allowed", [
    define "a" [],
    define "b" ["a"],
    define "z" [] (evidence := some "abc1234"),
    apply "x:1" "lead" "task.drop" [("task", .str "a")],
    apply "x:2" "lead" "task.drop" [("task", .str "z")],
    apply "x:3" "lead" "task.drop" [("task", .str "nope")],
    apply "x:4" "lead" "task.drop" [("task", .str "b")],
    apply "x:5" "lead" "task.drop" [("task", .str "a")],
    query]),
  ("claim: running with its agent; unknown and done tasks refused", [
    define "a" [],
    define "b" ["a"],
    define "z" [] (evidence := some "abc1234"),
    apply "c:1" "hook" "task.claim" [("task", .str "a"), ("agent", .str "agent-1")],
    apply "c:2" "hook" "task.claim" [("task", .str "nope"), ("agent", .str "agent-1")],
    apply "c:3" "script" "task.claim" [("task", .str "z"), ("agent", .str "agent-2")],
    query]),
  ("done: evidence makes it done and unblocks dependents; done twice refused", [
    define "a" [],
    define "b" ["a"],
    define "c" ["a", "b"],
    apply "f:1" "git" "task.done" [("task", .str "a"), ("evidence", .str "abc1234")],
    apply "f:2" "git" "task.done" [("task", .str "a"), ("evidence", .str "def5678")],
    query]),
  ("authority and duplicates: the actor table, a seen key is a duplicate", [
    define "a" [] (actor := "owner"),
    define "a" [] (actor := "hook"),
    define "a" [],
    define "a" ["x"],
    apply "f:1" "hook" "task.done" [("task", .str "a"), ("evidence", .str "abc1234")],
    apply "c:1" "owner" "task.claim" [("task", .str "a"), ("agent", .str "agent-1")],
    apply "x" "lead" "task.wat" [("task", .str "a")]]),
  ("replay: a plan log in one call, then the board plan", [
    Json.mkObj [("op", .str "console.replay"), ("events", .arr #[
      (apply "m:M1" "lead" "milestone.define" [("milestone", .str "M1"), ("title", .str "One")]).getObjValD "event",
      (define "a" [] (some "M1")).getObjValD "event",
      (define "b" ["a"] (some "M1")).getObjValD "event",
      (define "b" ["b"] (some "M1") (key := "d2:b")).getObjValD "event"])],
    query]),
  ("board plan: states, blockers, milestones, critical path, parallel-safe groups", [
    apply "m:M0" "lead" "milestone.define" [("milestone", .str "M0"), ("title", .str "Zero")],
    apply "m:M1" "lead" "milestone.define" [("milestone", .str "M1"), ("title", .str "One")],
    apply "m:M0b" "user" "milestone.define" [("milestone", .str "M0"), ("title", .str "Zero, renamed")],
    define "base" [] (some "M0") ["lean/Base.lean"] (evidence := some "0000001"),
    define "a" ["base"] (some "M0") ["lean/A/**"],
    define "b" ["base"] (some "M0") ["lean/A/x.lean"],
    define "c" ["a"] (some "M1") ["apps/web/**"],
    define "d" ["b", "c"] (some "M1") ["docs/d.md"],
    define "e" [] (some "M1") ["apps/api/**"] ["phone"],
    define "f" [] none ["research/f.md"] ["phone"],
    define "g" [] none ["lean/Fw/Console*.lean"],
    define "h" [] none ["lean/Fw/Console.lean"],
    define "r" ["a"] none ["lean/R.lean"],
    apply "c:r" "hook" "task.claim" [("task", .str "r"), ("agent", .str "agent-r")],
    query])]

/-- Run requests through `serveLine` from a fresh server; the reply lines. -/
def replies (reqs : List Json) : List String :=
  (reqs.foldl (fun (v, out) r => let (v', o) := Fw.Wire.Serve.serveLine v r.compress; (v', out ++ [o]))
    (init, ([] : List String))).2

/-- Parse a reply line (a parse error becomes a visible bad value). -/
def parsed (s : String) : Json := (Json.parse s).toOption.getD (.str s)

/-- One golden line: the name, the requests and the replies. -/
def caseLine (name : String) (reqs : List Json) : String :=
  (Json.mkObj [("name", .str name), ("requests", .arr reqs.toArray),
    ("replies", .arr ((replies reqs).map parsed).toArray)]).compress

/-- The text of `serve.jsonl`. -/
def serveText : String := String.join (cases.map fun (n, rs) => caseLine n rs ++ "\n")

/-- Order tasks so every dep comes before its dependents (Kahn over the JSON rows, fuel = count);
rows left on a cycle or an undefined dep keep their order at the end (and are refused on replay). -/
def topo (ts : List Json) : List Json :=
  let idOf (t : Json) : String := (t.getObjValAs? String "id").toOption.getD ""
  let depsOf (t : Json) : List String := (t.getObjValAs? (List String) "deps").toOption.getD []
  let rec go : Nat → List String → List Json → List Json → List Json
    | 0, _, acc, rest => acc ++ rest
    | f + 1, placed, acc, rest =>
      match rest.find? (fun t => (depsOf t).all placed.contains) with
      | none => acc ++ rest
      | some t => go f (idOf t :: placed) (acc ++ [t]) (rest.filter fun x => idOf x != idOf t)
  go ts.length [] [] ts

/-- The requests for the work graph: every milestone, every task (dependency order), a query. -/
def workGraphRequests (wg : Json) : List Json :=
  let ms := (wg.getObjValAs? (Array Json) "milestones").toOption.getD #[]
  let ts := (wg.getObjValAs? (Array Json) "tasks").toOption.getD #[]
  let s (j : Json) (k : String) : Json := j.getObjValD k
  let l (j : Json) (k : String) : Json := match j.getObjValD k with | .null => .arr #[] | v => v
  ms.toList.map (fun m => apply s!"m:{(s m "id").compress}" "lead" "milestone.define"
      [("milestone", s m "id"), ("title", s m "title")])
  ++ (topo ts.toList).map (fun t => apply s!"d:{(s t "id").compress}" "lead" "task.define"
      [("task", s t "id"), ("title", s t "title"), ("stream", s t "stream"),
       ("milestone", s t "milestone"), ("deps", l t "deps"), ("owner", s t "owner"),
       ("writes", l t "writes"), ("devices", l t "devices"), ("evidence", s t "evidence")])
  ++ [query]

/-- Check one golden file by replay: every line's requests, sent to a fresh server, give its replies.
Returns the number of failing lines (a missing file counts as one). -/
def replayFile (p : System.FilePath) : IO Nat := do
  let text ← try IO.FS.readFile p catch _ => pure ""
  if text.isEmpty then
    IO.println s!"plan golden: {p} is missing"
    return 1
  let mut bad := 0
  for line in (text.splitOn "\n").filter (· != "") do
    match Json.parse line with
    | .error _ => bad := bad + 1
    | .ok j =>
      let reqs := ((j.getObjValAs? (Array Json) "requests").toOption.getD #[]).toList
      let want := ((j.getObjValAs? (Array Json) "replies").toOption.getD #[]).toList.map (·.compress)
      let got := (replies reqs).map fun r => (parsed r).compress
      if got != want then
        IO.println s!"plan golden: {p}: case {(j.getObjValD "name").compress} differs"
        bad := bad + 1
  return bad

/-- Write (`write = true`) or check the plan goldens under `root` (the Lean package root). Returns the
number of stale or failing files/cases. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / dir
  let sp := d / "serve.jsonl"
  let wp := d / "work-graph.jsonl"
  if write then
    IO.FS.createDirAll d
    IO.FS.writeFile sp serveText
    let wg ← IO.FS.readFile (root / ".." / "docs" / "team" / "work-graph.json")
    match Json.parse wg with
    | .error e => throw (IO.userError s!"plan golden: work-graph.json: {e}")
    | .ok j => IO.FS.writeFile wp (caseLine "docs/team/work-graph.json" (workGraphRequests j) ++ "\n")
    IO.println s!"plan golden: {cases.length} cases + work graph written"
    return 0
  let cur ← try IO.FS.readFile sp catch _ => pure ""
  let mut bad := 0
  if cur != serveText then
    IO.println s!"plan golden: {sp} is stale (regenerate: cd lean && lake test -- --write-plan-golden)"
    bad := bad + 1
  bad := bad + (← replayFile sp) + (← replayFile wp)
  IO.println s!"plan golden: {cases.length} cases + work graph, {bad} failing"
  return bad

end Fw.Wire.Plan.Golden
