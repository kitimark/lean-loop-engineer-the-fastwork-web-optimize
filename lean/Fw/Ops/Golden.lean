import Fw.Wire
/-!
# Golden vectors of the `ops.*` ops

`packages/contracts/golden/ops/<op>.jsonl`: one line per case, `{"name", "request", "response"}`,
where `request` carries its `op` and `response` is what `fwcore` replies (without the `id`).
Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/OpsGolden.lean           # write the files
cd lean && lake env lean --run scripts/OpsGolden.lean --check   # fail if a file is stale
```

`lake test` runs the same check. Consumers: the hooks agent (`emit.mjs`, `spawn-guard.mjs`:
`ops.hook`, `ops.spawn`), the land agent (`fw land`: `ops.pathCheck`) and console-api's usage
meter (`ops.usage`, `ops.meter`).
-/
namespace Fw.Wire.Ops.Golden
open Lean

/-- Parse a literal request (a parse error becomes a visible bad case). -/
def lit (s : String) : Json := (Json.parse s).toOption.getD (Json.mkObj [("unparsable", .str s)])

/-- The roles table the spawn cases use (a slice of PLAN §8.2). -/
def roles : String :=
  "[{\"name\":\"lean-prover\",\"runsAs\":\"worktree\",\"edits\":true},{\"name\":\"researcher\",\"runsAs\":\"teammate\",\"edits\":true},{\"name\":\"reviewer\",\"runsAs\":\"subagent\",\"edits\":false},{\"name\":\"Explore\",\"runsAs\":\"subagent\",\"edits\":false}]"

/-- A spawn request with the roles above, the given alive list, extra top-level fields and call. -/
def spawn (alive extra call : String) : Json :=
  lit s!"\{\"alive\":{alive},\"roles\":{roles},\"now\":1000{extra},\"req\":{call}}"

/-- `n` alive agents named `<p>0..` of one role and kind. -/
def aliveN (p role kind : String) (n : Nat) : String :=
  "[" ++ ",".intercalate ((List.range n).map fun k =>
    s!"\{\"name\":\"{p}{k}\",\"role\":\"{role}\",\"kind\":\"{kind}\"}") ++ "]"

/-- The cases, per op file: (file stem, [(name, request without op)]). -/
def cases : List (String × List (String × Json)) := [
  ("ops.spawn", [
    ("named worktree subagent with isolation: allow", spawn "[]" "" "{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"spawner\":\"lead\",\"depth\":0}"),
    ("worktree role without isolation becomes a teammate: deny (I-272 trap)", spawn "[]" "" "{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"spawner\":\"lead\",\"depth\":0}"),
    ("teammate role with worktree isolation: deny", spawn "[]" "" "{\"name\":\"res-1\",\"role\":\"researcher\",\"isolation\":\"worktree\"}"),
    ("teammate role, named, no isolation: allow", spawn "[]" "" "{\"name\":\"res-1\",\"role\":\"researcher\",\"isolation\":null}"),
    ("fable per call: needs approval", spawn "[]" "" "{\"name\":\"lean-x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"model\":\"claude-fable-5-1\"}"),
    ("fable but over a cap: deny wins", spawn (aliveN "l" "lean-prover" "worktree" 3) "" "{\"name\":\"lean-x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"model\":\"fable\"}"),
    ("unnamed call: deny", spawn "[]" "" "{\"role\":\"Explore\"}"),
    ("unnamed read-only subagent with unnamedReadOnly: allow", spawn "[]" ",\"caps\":{\"unnamedReadOnly\":true}" "{\"role\":\"Explore\"}"),
    ("name in use: deny", spawn "[{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"kind\":\"worktree\"}]" "" "{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"),
    ("unknown role: deny", spawn "[]" "" "{\"name\":\"x\",\"role\":\"general-purpose\",\"isolation\":\"worktree\"}"),
    ("editing role from a depth-1 spawner: deny", spawn "[]" "" "{\"name\":\"x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"spawner\":\"eng-webkit\",\"depth\":1}"),
    ("read-only helper from a depth-1 spawner: allow", spawn "[]" "" "{\"name\":\"loc-1\",\"role\":\"reviewer\",\"spawner\":\"eng-webkit\",\"depth\":1}"),
    ("6th teammate: deny", spawn (aliveN "t" "researcher" "teammate" 5) "" "{\"name\":\"t9\",\"role\":\"researcher\"}"),
    ("9th worktree subagent: deny", spawn (aliveN "w" "part-builder" "worktree" 8) "" "{\"name\":\"w9\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"),
    ("11th subagent in all: deny", spawn (aliveN "s" "reviewer" "subagent" 10) "" "{\"name\":\"s99\",\"role\":\"reviewer\",\"spawner\":\"eng-webkit\",\"depth\":1}"),
    ("4th lean-prover: deny capRole", spawn (aliveN "l" "lean-prover" "worktree" 3) "" "{\"name\":\"l9\",\"role\":\"lean-prover\",\"isolation\":true}"),
    ("11th spawn in 10 min by one spawner: deny", spawn "[]" ",\"recent\":[{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500},{\"spawner\":\"lead\",\"at\":500}]" "{\"name\":\"x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"),
    ("spawns older than the window do not count: allow", spawn "[]" ",\"recent\":[{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400},{\"spawner\":\"lead\",\"at\":400}]" "{\"name\":\"x\",\"role\":\"lean-prover\",\"isolation\":\"worktree\"}"),
    ("custom caps", spawn (aliveN "t" "researcher" "teammate" 2) ",\"caps\":{\"teammates\":2,\"perRole\":{},\"askModels\":[]}" "{\"name\":\"t9\",\"role\":\"researcher\"}"),
    ("bad kind is refused", spawn "[{\"name\":\"a\",\"role\":\"r\",\"kind\":\"robot\"}]" "" "{\"name\":\"x\",\"role\":\"reviewer\"}"),
    ("bad isolation is refused", spawn "[]" "" "{\"name\":\"x\",\"role\":\"lean-prover\",\"isolation\":\"container\"}")]),
  ("ops.pathCheck", [
    ("lean-prover scope: math.lock excluded, docs outside", lit "{\"scope\":[\"lean/**\",\"!lean/math.lock.json\"],\"paths\":[\"lean/Fw/Ops/Usage.lean\",\"lean/math.lock.json\",\"docs/plan/PLAN.md\"]}"),
    ("all inside", lit "{\"scope\":[\"lean/**\"],\"paths\":[\"lean/Fw.lean\",\"lean/golden/ops-x.txt\"]}"),
    ("dot-dot and empty paths are never in scope; ./ and // normalise", lit "{\"scope\":[\"lean/**\"],\"paths\":[\"lean/../docs/x.md\",\"\",\"./lean//Fw.lean\"]}"),
    ("star inside a segment; directory prefix", lit "{\"scope\":[\"packages/measure-*\",\"apps/console-*/**\"],\"paths\":[\"packages/measure-webkit/src/a.ts\",\"packages/model/x.ts\",\"apps/console-web/src/App.tsx\",\"apps/site/x\"]}"),
    ("part slug is a whole segment", lit "{\"scope\":[\"apps/site/src/parts/hero/**\"],\"paths\":[\"apps/site/src/parts/hero/a.tsx\",\"apps/site/src/parts/heroX/a.tsx\"]}"),
    ("trailing slash is a directory prefix", lit "{\"scope\":[\"research/notes/\",\"refs/**\"],\"paths\":[\"research/notes/2026/a.md\",\"research/decisions/b.md\",\"refs/x\"]}"),
    ("double star in the middle", lit "{\"scope\":[\"docs/**/*.md\"],\"paths\":[\"docs/a.md\",\"docs/x/y/b.md\",\"docs/x/c.html\"]}"),
    ("empty scope: everything is a violation", lit "{\"scope\":[],\"paths\":[\"a\"]}"),
    ("no paths", lit "{\"scope\":[\"lean/**\"],\"paths\":[]}")]),
  ("ops.usage", [
    ("partial lines of one message joined per field; non-usage lines skipped", lit "{\"lines\":[{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":3,\"cache_read_input_tokens\":1000,\"output_tokens\":1}}},{\"type\":\"user\",\"message\":{\"role\":\"user\"}},{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":3,\"cache_read_input_tokens\":1000,\"cache_creation_input_tokens\":200,\"cache_creation\":{\"ephemeral_5m_input_tokens\":200,\"ephemeral_1h_input_tokens\":0},\"output_tokens\":57}}}]}"),
    ("same lines reversed give the same table", lit "{\"lines\":[{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":3,\"cache_read_input_tokens\":1000,\"cache_creation_input_tokens\":200,\"cache_creation\":{\"ephemeral_5m_input_tokens\":200,\"ephemeral_1h_input_tokens\":0},\"output_tokens\":57}}},{\"type\":\"user\",\"message\":{\"role\":\"user\"}},{\"type\":\"assistant\",\"message\":{\"id\":\"msg_1\",\"usage\":{\"input_tokens\":3,\"cache_read_input_tokens\":1000,\"output_tokens\":1}}}]}"),
    ("table plus new records: sorted by id, totals summed", lit "{\"table\":[{\"id\":\"b\",\"input\":1,\"output\":10}],\"records\":[{\"id\":\"a\",\"cache1h\":5},{\"id\":\"b\",\"output\":12},{\"id\":\"b\",\"output\":11}]}"),
    ("duplicates change nothing", lit "{\"records\":[{\"id\":\"a\",\"input\":2},{\"id\":\"a\",\"input\":2}]}"),
    ("empty", lit "{}"),
    ("a non-integer count is refused", lit "{\"records\":[{\"id\":\"a\",\"input\":1.5}]}")]),
  ("ops.meter", [
    ("each rule at its threshold", lit "{\"now\":100,\"agents\":[{\"agent\":\"big\",\"ctx\":200001,\"idleSec\":0,\"ttlSec\":300},{\"agent\":\"edge\",\"ctx\":200000,\"idleSec\":240,\"ttlSec\":300},{\"agent\":\"idle\",\"ctx\":1000,\"idleSec\":241,\"ttlSec\":300},{\"agent\":\"cold\",\"ctx\":50000,\"idleSec\":0,\"ttlSec\":300,\"wakeGapSec\":301}]}"),
    ("already fired in this window: no repeat", lit "{\"now\":200,\"state\":{\"window\":0,\"fired\":[{\"agent\":\"idle\",\"rule\":\"idleExpiring\"}]},\"agents\":[{\"agent\":\"idle\",\"ctx\":1000,\"idleSec\":341,\"ttlSec\":300}]}"),
    ("next window: fires again", lit "{\"now\":3700,\"state\":{\"window\":0,\"fired\":[{\"agent\":\"idle\",\"rule\":\"idleExpiring\"}]},\"agents\":[{\"agent\":\"idle\",\"ctx\":1000,\"idleSec\":3841,\"ttlSec\":300}]}"),
    ("ttl from cache writes; verdicts", lit "{\"now\":0,\"agents\":[{\"agent\":\"h1\",\"ctx\":50000,\"idleSec\":400,\"w5m\":10,\"w1h\":90},{\"agent\":\"m5\",\"ctx\":50000,\"idleSec\":400,\"w5m\":90,\"w1h\":10},{\"agent\":\"small\",\"ctx\":20000,\"idleSec\":400,\"ttlSec\":300}]}"),
    ("custom params", lit "{\"now\":0,\"params\":{\"ctxMax\":100,\"leadSec\":0,\"windowSec\":60,\"respawnCtx\":10},\"agents\":[{\"agent\":\"a\",\"ctx\":101,\"idleSec\":300,\"ttlSec\":300}]}"),
    ("duplicate agents in one tick alert once", lit "{\"now\":0,\"agents\":[{\"agent\":\"a\",\"ctx\":300000,\"idleSec\":0,\"ttlSec\":300},{\"agent\":\"a\",\"ctx\":300000,\"idleSec\":0,\"ttlSec\":300}]}"),
    ("unknown rule in state is refused", lit "{\"now\":0,\"state\":{\"fired\":[{\"agent\":\"a\",\"rule\":\"loud\"}]},\"agents\":[]}")]),
  ("ops.hook", [
    ("PostToolUse from a subagent (tool input and response dropped)", lit "{\"payloads\":[{\"session_id\":\"s1\",\"transcript_path\":\"/x\",\"cwd\":\"/y\",\"hook_event_name\":\"PostToolUse\",\"agent_id\":\"a1\",\"agent_type\":\"lean-prover\",\"tool_name\":\"Bash\",\"tool_use_id\":\"toolu_1\",\"tool_input\":{\"command\":\"ls\"},\"tool_response\":{\"stdout\":\"x\"},\"duration_ms\":412,\"prompt_id\":\"p1\"}]}"),
    ("main thread has no agent_id; failure fields", lit "{\"payloads\":[{\"session_id\":\"s1\",\"hook_event_name\":\"PostToolUseFailure\",\"tool_name\":\"Edit\",\"tool_use_id\":\"toolu_2\",\"error\":\"denied\",\"is_interrupt\":false,\"duration_ms\":3}]}"),
    ("TeammateIdle and SubagentStart", lit "{\"payloads\":[{\"session_id\":\"s1\",\"hook_event_name\":\"TeammateIdle\",\"agent_id\":\"a2\",\"teammate_name\":\"eng-webkit\",\"team_name\":\"t\"},{\"session_id\":\"s1\",\"hook_event_name\":\"SubagentStart\",\"agent_id\":\"a3\",\"agent_type\":\"reviewer\"}]}"),
    ("bad payloads are reported by index, the rest decoded", lit "{\"payloads\":[{\"hook_event_name\":\"PostToolUse\"},{\"session_id\":\"s1\",\"hook_event_name\":\"PostToolUse\",\"duration_ms\":1.5},\"x\",{\"session_id\":\"s1\",\"hook_event_name\":\"Stop\"}]}"),
    ("missing payloads is refused", lit "{}")])]

/-- The request with its `op` field set. -/
def withOp (op : String) : Json → Json
  | .obj kvs => .obj (kvs.insert "op" (.str op))
  | j => j

/-- The reply to a request as a JSON object without the id. -/
def respond (op : String) (req : Json) : Json :=
  match Json.parse (Fw.Wire.handleLine (withOp op req).compress) with
  | .ok (.obj kvs) => .obj (kvs.erase "id")
  | .ok j => j
  | .error e => Json.mkObj [("error", .str s!"reply is not JSON: {e}")]

/-- The text of one golden file. -/
def fileText (op : String) (cs : List (String × Json)) : String :=
  String.join (cs.map fun (name, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

/-- The golden directory, relative to `lean/`. -/
def dir : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ops"

/-- Compare (or write) every golden file; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let d := root / dir
  if write then IO.FS.createDirAll d
  let mut stale := 0
  for (op, cs) in cases do
    let p := d / s!"{op}.jsonl"
    let text := fileText op cs
    if write then
      IO.FS.writeFile p text
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != text then
        IO.println s!"ops golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/OpsGolden.lean)"
        stale := stale + 1
  let n := cases.foldl (fun a c => a + c.2.length) 0
  IO.println s!"ops golden: {cases.length} files, {n} cases, {if write then "written" else s!"{stale} stale"}"
  return stale

end Fw.Wire.Ops.Golden
