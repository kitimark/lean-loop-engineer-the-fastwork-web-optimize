import Fw.Serve
import Fw.Plan.Workflow
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
* `workflow.jsonl`: `Fw.Plan.wfAllEvents` vectors, one per line `{name, ids, scripts, runs, events}`: the
  agent events of workflow runs from the file names of the session's `workflows/` dir (task
  `workflow-claim`). Checked byte for byte.
* `sync.jsonl`: `Fw.Plan.syncFrom` vectors, one per line `{name, main, refs, last, from}`, for the
  reconciler's plan sync (which commit to read the work graph from). Checked byte for byte.

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
    (writes devices : List String := []) (evidence : Option String := none)
    (needs : List String := []) (cut : Bool := false) (live : List String := [])
    (onMain : Option Bool := none) :
    List (String × Json) :=
  [("task", .str task), ("title", .str s!"Task {task}"), ("stream", .str "lean"),
   ("milestone", ostr milestone), ("deps", strsJson deps), ("owner", .str "lean-prover"),
   ("writes", strsJson writes), ("devices", strsJson devices)]
  ++ (if needs.isEmpty then [] else [("needs", strsJson needs)]) ++ [("evidence", ostr evidence)]
  ++ (if cut then [("cut", .bool true)] else []) ++ (if live.isEmpty then [] else [("live", strsJson live)])
  ++ (match onMain with | some b => [("evidenceOnMain", .bool b)] | none => [])

/-- A `task.define` by the lead (key `d:<task>` unless given). -/
def define (task : String) (deps : List String) (milestone : Option String := none)
    (writes devices : List String := []) (evidence : Option String := none)
    (key : String := s!"d:{task}") (actor : String := "lead") (needs : List String := [])
    (cut : Bool := false) (live : List String := []) (onMain : Option Bool := none) : Json :=
  apply key actor "task.define" (defFields task deps milestone writes devices evidence needs cut live onMain)

/-- The synthetic cases: (name, requests). -/
def cases : List (String × List Json) := [
  ("define: two tasks and a milestone, then the board plan", [
    apply "m:M0" "lead" "milestone.define" [("milestone", .str "M0"), ("title", .str "Start")],
    define "a" [] (some "M0"),
    define "b" ["a"] (some "M0"),
    query]),
  ("define: upsert keeps the claim and landed evidence, replaces the definition", [
    define "a" [],
    apply "c:a" "hook" "task.claim" [("task", .str "a"), ("agent", .str "agent-1")],
    define "a" [] (some "M9") ["lean/A/**"] (key := "d2:a"),
    define "l" [],
    apply "f:l" "git" "task.done" [("task", .str "l"), ("evidence", .str "abc1234")],
    define "l" [] (key := "d2:l"),
    query]),
  ("evidence on main: off-main commit evidence refused, state kept; on main accepted", [
    define "a" [],
    define "b" ["a"],
    define "a" [] (evidence := some "9a5c552") (onMain := some false) (key := "d2:a"),
    query,
    define "a" [] (evidence := some "9a5c552") (onMain := some true) (key := "d3:a"),
    query]),
  ("evidence on main: other kinds are not checked; a define without evidence takes back unlanded evidence", [
    define "r" [] (evidence := some "39053169745") (onMain := some false),
    define "u" [] (evidence := some "user: ship it") (onMain := some false),
    define "c" [] (evidence := some "abc1234") (onMain := some true),
    define "d" ["c"],
    query,
    define "c" [] (key := "d2:c"),
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
    define "n" [] (needs := (List.range 9).map fun i => s!"need{i}"),
    query]),
  ("lanes: needs device puts a task in the device lane, out of the parallel-safe groups", [
    define "base" [] (evidence := some "0000001"),
    define "a" ["base"] none ["lean/A/**"],
    define "p" [] (needs := ["device"]),
    define "q" ["base"] none ["research/q.md"] ["phone"] (needs := ["other", "device"]),
    define "w" ["a"] (needs := ["device"]),
    define "x" [] (needs := ["other"]),
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
    query]),
  ("late define: a live agent named like the task claims it; another live agent does not", [
    define "a" [] (live := ["a", "x"]),
    define "b" [] (live := ["x"]),
    define "c" [],
    apply "c:c" "hook" "task.claim" [("task", .str "c"), ("agent", .str "lead-1")],
    define "c" [] (some "M1") (key := "d2:c") (live := ["z"]),
    define "b" [] (some "M1") (key := "d2:b") (live := ["b"]),
    query]),
  ("cut: never ready, not grouped, not on the critical path, not counted; done still wins", [
    apply "m:M0" "lead" "milestone.define" [("milestone", .str "M0"), ("title", .str "Zero")],
    apply "m:MX" "lead" "milestone.define" [("milestone", .str "MX"), ("title", .str "Cut")],
    define "a" [] (some "M0") ["x/**"],
    define "b" ["a"] (some "M0"),
    define "c" [] (some "MX") ["y/**"] (cut := true),
    define "d" ["c"] (some "MX") (cut := true),
    define "e" [] (some "MX") (evidence := some "abc1234") (cut := true),
    define "f" [] (some "MX") ["z/**"] (needs := ["device"]) (cut := true),
    apply "c:c" "hook" "task.claim" [("task", .str "c"), ("agent", .str "agent-c")],
    query]),
  ("spawn race (obs-next-lean): define then spawn binds the agent", [
    define "obs-next-lean" [] (key := "plan:d:obs-next-lean"),
    apply "spawn:t1" "hook" "agent.spawn" [("agent", .str "obs-next-lean")],
    query]),
  ("spawn race (obs-next-lean): spawn then define binds the same agent", [
    apply "spawn:t1" "hook" "agent.spawn" [("agent", .str "obs-next-lean")],
    define "obs-next-lean" [] (key := "plan:d:obs-next-lean"),
    query]),
  ("stop before define: the agent ended before its task existed, the task is ready", [
    apply "spawn:t1" "hook" "agent.spawn" [("agent", .str "a")],
    apply "stop:a1" "hook" "agent.stop" [("agent", .str "a")],
    define "a" [],
    query]),
  ("stop and respawn: a stop unbinds an undone task, a done task keeps its agent, a respawn binds again", [
    define "a" [],
    define "b" [],
    apply "spawn:t1" "hook" "agent.spawn" [("agent", .str "a")],
    apply "spawn:t2" "hook" "agent.spawn" [("agent", .str "b")],
    apply "t:b" "git" "task.done" [("task", .str "b"), ("evidence", .str "abc1234")],
    apply "stop:a1" "hook" "agent.stop" [("agent", .str "a")],
    apply "stop:b1" "hook" "agent.stop" [("agent", .str "b")],
    query,
    apply "spawn:t3" "hook" "agent.spawn" [("agent", .str "a")],
    query]),
  ("claim and spawn: an explicit claim wins; when its agent stops the name match takes over", [
    define "a" [],
    apply "spawn:t1" "hook" "agent.spawn" [("agent", .str "a")],
    apply "c:a" "lead" "task.claim" [("task", .str "a"), ("agent", .str "lead-1")],
    query,
    apply "stop:l1" "hook" "agent.stop" [("agent", .str "lead-1")],
    query]),
  ("authority: agent.spawn by hook, script and lead; refused for owner; a seen key is a duplicate", [
    apply "spawn:t1" "owner" "agent.spawn" [("agent", .str "a")],
    apply "spawn:t1" "hook" "agent.spawn" [("agent", .str "a")],
    apply "spawn:t1" "hook" "agent.spawn" [("agent", .str "a")],
    apply "spawn:t2" "script" "agent.spawn" [("agent", .str "b")],
    apply "stop:x" "lead" "agent.stop" [("agent", .str "b")]])]

/-- The plan-sync vectors (`Fw.Plan.syncFrom`): name, main's ref name, the refs, the last synced
commit, and the commit to sync from (or none). -/
def syncCases : List (String × String × List (String × String) × Option String) := [
  ("first pass: main's head is synced", "main", [("ci/x", "c1"), ("main", "m1")], none),
  ("same head: skipped", "main", [("main", "m1")], some "m1"),
  ("main moved: synced", "main", [("ci/x", "c1"), ("main", "m2")], some "m1"),
  ("no main ref: skipped", "main", [("ci/x", "c1")], some "m1"),
  ("no refs: skipped", "main", [], none),
  ("a worktree branch never syncs", "main", [("worktree-agent-x", "w1")], none),
  ("duplicate main: the first one", "main", [("main", "m1"), ("main", "m2")], none)]

/-- One sync line: `{name, main, refs: [[name, sha]], last, from}`. -/
def syncLine (c : String × String × List (String × String) × Option String) : String :=
  let (n, m, refs, last) := c
  (Json.mkObj [("name", .str n), ("main", .str m),
    ("refs", .arr (refs.toArray.map fun (r, h) => .arr #[.str r, .str h])), ("last", ostr last),
    ("from", ostr (Fw.Plan.syncFrom m refs last))]).compress

/-- The text of `sync.jsonl`. -/
def syncText : String := String.join (syncCases.map fun c => syncLine c ++ "\n")

/-- A journal line vector. -/
def jl (run id : String) (started : Bool) (label : String) : Fw.Plan.JLine := { run, id, started, label }

/-- The workflow vectors (`Fw.Plan.wfAllEvents`): name, task ids, script file names, run file names, journal lines. -/
def wfCases : List (String × List String × List String × List String × List Fw.Plan.JLine) := [
  ("a running workflow named like a task spawns it", ["mistake-retro", "x"],
    ["mistake-retro-wf_b3d4e643-ace.js"], [], []),
  ("its run file adds the stop", ["mistake-retro"],
    ["mistake-retro-wf_b3d4e643-ace.js"], ["wf_b3d4e643-ace.json"], []),
  ("a name that is no task id gives nothing", ["x"],
    ["agent-bottlenecks-wf_05e58d40-de0.js", "x-y-wf_05e58d40-de0.js"], [], []),
  ("hyphens in the name; two runs; the run file of another run stops only that one", ["wave-next-builders", "a"],
    ["wave-next-builders-wf_eaf1cd1e-ed1.js", "a-wf_c2b8a932-977.js"], ["wf_c2b8a932-977.json"], []),
  ("the same script twice is one run", ["a"], ["a-wf_c2b8a932-977.js", "a-wf_c2b8a932-977.js"], [], []),
  ("malformed file names are ignored", ["a"],
    ["a-wf_c2b8a932-977.json", "-wf_c2b8a932-977.js", "a-wf_C2b8a932-977.js", "a-wf_c2b8a932-97.js", "a.js", "a-wf_c2b8a932-977.js.bak"],
    ["wf_c2b8a932-977.js", "wf_zz.json", "notes.json"], []),
  ("a label <phase>:<task> binds that task while the agent runs; a result line ends it", ["engine-model-fix", "integrate-ports", "x"],
    ["integrate-and-engine-fix-wf_b37180a7-494.js"], [],
    [jl "wf_b37180a7-494" "a1" true "build:engine-model-fix", jl "wf_b37180a7-494" "a2" true "build:integrate-ports",
     jl "wf_b37180a7-494" "a1" false "", jl "wf_b37180a7-494" "a3" true "review", jl "wf_b37180a7-494" "a4" true "verify:nope"]),
  ("the run file ends every agent of the run; the meta.name binding is kept", ["guard", "w", "v"],
    ["guard-wf_b37180a7-494.js"], ["wf_b37180a7-494.json"],
    [jl "wf_b37180a7-494" "a1" true "fix:w", jl "wf_b37180a7-494" "a1" true "fix:w", jl "wf_b37180a7-494" "a2" true "x:y:v",
     jl "wf_b37180a7-494" "a3" true "w:", jl "wf_b37180a7-494" "a5" false "fix:v", jl "bad" "a6" true "fix:v"])]

/-- One workflow line: `{name, ids, scripts, runs, [journal: [{run, id, started, label}]], events: [{key, type, agent}]}` (`Fw.Plan.wfAllEvents`; no `journal` field = none). -/
def wfLine (c : String × List String × List String × List String × List Fw.Plan.JLine) : String :=
  let (n, ids, ss, rs, js) := c
  let jsJson : List (String × Json) := if js.isEmpty then [] else
    [("journal", .arr (js.toArray.map fun j => Json.mkObj [("run", .str j.run), ("id", .str j.id),
      ("started", .bool j.started), ("label", .str j.label)]))]
  (Json.mkObj ([("name", .str n), ("ids", strsJson ids), ("scripts", strsJson ss), ("runs", strsJson rs),
    ("events", .arr ((Fw.Plan.wfAllEvents ids ss rs js).toArray.map fun (k, t, a) =>
      Json.mkObj [("key", .str k), ("type", .str t), ("agent", .str a)]))] ++ jsJson)).compress

/-- The text of `workflow.jsonl`. -/
def wfText : String := String.join (wfCases.map fun c => wfLine c ++ "\n")

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

/-- A title as `fw plan sync` sends it: at most 200 characters, a longer one clipped to 199 plus `…`
(the contract's cap; the file keeps the full text). -/
def clip : Json → Json
  | .str s => .str (if s.length ≤ 200 then s else String.ofList (s.toList.take 199) ++ "…")
  | j => j

#guard clip (.str "ab") == .str "ab"
#guard clip (.str (String.ofList (List.replicate 201 'x'))) ==
  .str (String.ofList (List.replicate 199 'x') ++ "…")

/-- The requests for the work graph: every milestone, every task (dependency order), a query. -/
def workGraphRequests (wg : Json) : List Json :=
  let ms := (wg.getObjValAs? (Array Json) "milestones").toOption.getD #[]
  let ts := (wg.getObjValAs? (Array Json) "tasks").toOption.getD #[]
  let s (j : Json) (k : String) : Json := j.getObjValD k
  let l (j : Json) (k : String) : Json := match j.getObjValD k with | .null => .arr #[] | v => v
  ms.toList.map (fun m => apply s!"m:{(s m "id").compress}" "lead" "milestone.define"
      [("milestone", s m "id"), ("title", s m "title")])
  ++ (topo ts.toList).map (fun t => apply s!"d:{(s t "id").compress}" "lead" "task.define"
      ([("task", s t "id"), ("title", clip (s t "title")), ("stream", s t "stream"),
       ("milestone", s t "milestone"), ("deps", l t "deps"), ("owner", s t "owner"),
       ("writes", l t "writes"), ("devices", l t "devices"), ("needs", l t "needs"), ("evidence", s t "evidence")]
      ++ (match t.getObjValD "cut" with
          | .bool true => [("cut", Json.bool true)] | _ => ([] : List (String × Json)))))
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
  let yp := d / "sync.jsonl"
  if write then
    IO.FS.createDirAll d
    IO.FS.writeFile sp serveText
    IO.FS.writeFile yp syncText
    IO.FS.writeFile (d / "workflow.jsonl") wfText
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
  let ycur ← try IO.FS.readFile yp catch _ => pure ""
  if ycur != syncText then
    IO.println s!"plan golden: {yp} is stale (regenerate: cd lean && lake test -- --write-plan-golden)"
    bad := bad + 1
  let wcur ← try IO.FS.readFile (d / "workflow.jsonl") catch _ => pure ""
  if wcur != wfText then
    IO.println s!"plan golden: {d / "workflow.jsonl"} is stale (regenerate: cd lean && lake test -- --write-plan-golden)"
    bad := bad + 1
  bad := bad + (← replayFile sp) + (← replayFile wp)
  IO.println s!"plan golden: {cases.length} cases + work graph, {bad} failing"
  return bad

end Fw.Wire.Plan.Golden
