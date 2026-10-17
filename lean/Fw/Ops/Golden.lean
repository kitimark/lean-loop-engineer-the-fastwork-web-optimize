import Fw.Wire
/-!
# Golden vectors of the `ops.*` ops

`packages/contracts/golden/ops/<op>.jsonl`: one line per case, `{"name", "request", "response"}`,
where `request` carries its `op` and `response` is what `fwcore` replies (without the `id`).
The same format, from `extra`: `golden/plan/plan.trailers.jsonl` (reconciler `git.ts`) and
`golden/console/console.{landReadiness,actor}.jsonl` (console-api's own actors).
Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/OpsGolden.lean           # write the files
cd lean && lake env lean --run scripts/OpsGolden.lean --check   # fail if a file is stale
```

`lake test` runs the same check. Consumers: the hooks agent (`emit.mjs`, `spawn-guard.mjs`:
`ops.hook`, `ops.spawn`; `cap.mjs`: `ops.actor`), console-api's capability door (`cap.ts`
`actorFor`: `ops.actor`), the land agent (`fw land`: `ops.pathCheck`) and console-api's usage
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
    ("missing payloads is refused", lit "{}"),
    ("identity: forked internal agent (empty agent_type) is unknown, never the lead", lit "{\"payloads\":[{\"session_id\":\"s1\",\"hook_event_name\":\"SubagentStop\",\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\"},{\"session_id\":\"s1\",\"hook_event_name\":\"Stop\"}]}")]),
  ("ops.actor", [
    ("lead: no agent_id, no agent_type", lit "{}"),
    ("lead: null agent_id", lit "{\"agent_id\":null,\"agent_type\":null}"),
    ("lead: no agent_id, agent_type set (main session started with an agent)", lit "{\"agent_type\":\"lean-prover\"}"),
    ("lead: the caps.jsonl lead record", lit "{\"agent_id\":null,\"agent_type\":\"main\"}"),
    ("subagent role: owner", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"lean-prover\"}"),
    ("reviewer role", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"reviewer\"}"),
    ("review in the type, any ASCII case", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"Math-REVIEWER\"}"),
    ("near miss: revie is an owner", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"revie-w\"}"),
    ("agent typed main is an owner, never the lead", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"main\"}"),
    ("teammate: agent_type is its name (role unresolved, SPK-c open)", lit "{\"agent_id\":\"aeng-webkit-0123456789abcdef\",\"agent_type\":\"eng-webkit\"}"),
    ("forked internal agent: empty agent_type is unknown", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\"}"),
    ("agent_id without agent_type is unknown", lit "{\"agent_id\":\"a0123456789abcdef\"}"),
    ("agent_id with null agent_type is unknown", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":null}"),
    ("empty agent_id is unknown", lit "{\"agent_id\":\"\",\"agent_type\":\"lean-prover\"}"),
    ("non-string agent_id is refused", lit "{\"agent_id\":7,\"agent_type\":\"lean-prover\"}"),
    ("non-string agent_type is refused", lit "{\"agent_id\":\"a1\",\"agent_type\":true}")]),
  ("ops.obs", [
    ("keys: tool_use_id joins; without it the timestamp; no agent_id is main", lit "{\"records\":[{\"agent_id\":\"a1\",\"hook_event_name\":\"PostToolUse\",\"tool_use_id\":\"toolu_1\",\"ts\":5},{\"agent_id\":null,\"hook_event_name\":\"Stop\",\"tool_use_id\":null,\"ts\":7},{\"hook_event_name\":\"Notification\",\"ts\":9}]}"),
    ("keys: an empty agent_id stays empty (only null or missing is main)", lit "{\"records\":[{\"agent_id\":\"\",\"hook_event_name\":\"X\",\"tool_use_id\":\"\",\"ts\":7}]}"),
    ("summary: calls, errors and summed duration per (agent type, tool), first-seen order", lit "{\"lines\":[{\"key\":\"k1\",\"hook_event_name\":\"PostToolUse\",\"agent_type\":\"b\",\"tool_name\":\"Bash\",\"is_error\":false,\"duration_ms\":100,\"ts\":1},{\"hook_event_name\":\"Stop\",\"agent_type\":\"b\"},{\"hook_event_name\":\"PostToolUse\"},{\"hook_event_name\":\"PostToolUseFailure\",\"agent_type\":\"b\",\"tool_name\":\"Bash\",\"is_error\":true,\"duration_ms\":50}]}"),
    ("summary: null fields count as main, ?, no error and 0 ms", lit "{\"lines\":[{\"hook_event_name\":\"PostToolUse\",\"agent_type\":null,\"tool_name\":null,\"is_error\":null,\"duration_ms\":null}]}"),
    ("empty request: no keys, no rows", lit "{}"),
    ("record without ts is refused", lit "{\"records\":[{\"hook_event_name\":\"Stop\"}]}"),
    ("fractional duration is refused", lit "{\"lines\":[{\"hook_event_name\":\"PostToolUse\",\"duration_ms\":1.5}]}")])]

/-- Golden files outside `ops/`: (directory under `packages/contracts/golden`, op, cases). -/
def extra : List (String × String × List (String × Json)) := [
  ("plan", "plan.trailers", [
    ("oldest trailer marks done; later ones are duplicates; done and unknown ids are reported", lit "{\"commits\":[{\"sha\":\"s3\",\"body\":\"merge x\\n\\nTask: a\\nTask: c\"},{\"sha\":\"s2\",\"body\":\"Task: b\"},{\"sha\":\"s1\",\"body\":\"subject\\n\\nTask: a\"}],\"tasks\":[{\"id\":\"a\",\"state\":\"claimed\"},{\"id\":\"b\",\"state\":\"done\"}]}"),
    ("trailer syntax: line start, blanks around the id, id chars only, CRLF ok", lit "{\"commits\":[{\"sha\":\"s1\",\"body\":\"Task:  t-1.x_2 \\r\\nTask: t 2\\n task: t3\\nTask:\\nxTask: t4\\nTask:t5\"}],\"tasks\":[{\"id\":\"t-1.x_2\",\"state\":\"open\"},{\"id\":\"t5\",\"state\":\"open\"}]}"),
    ("two trailers of one task in one commit: the first is done, the second a duplicate", lit "{\"commits\":[{\"sha\":\"s1\",\"body\":\"Task: a\\nTask: a\"}],\"tasks\":[{\"id\":\"a\",\"state\":\"open\"}]}"),
    ("no commits", lit "{\"commits\":[],\"tasks\":[{\"id\":\"a\",\"state\":\"open\"}]}"),
    ("missing tasks is refused", lit "{\"commits\":[]}")]),
  ("console", "console.landReadiness", [
    ("new card needs everything (device too)", lit "{\"card\":{\"id\":\"c\",\"needsDevice\":true},\"sha\":\"h\"}"),
    ("ready at head", lit "{\"card\":{\"id\":\"c\",\"owner\":\"o\",\"needsDevice\":false,\"approved\":true,\"head\":\"h\",\"screenAt\":\"h\",\"reviewAt\":\"h\"},\"sha\":\"h\"}"),
    ("ready, but the request names an older sha", lit "{\"card\":{\"id\":\"c\",\"needsDevice\":false,\"approved\":true,\"head\":\"h\",\"screenAt\":\"h\",\"reviewAt\":\"h\"},\"sha\":\"g\"}"),
    ("review at an old head; device missing", lit "{\"card\":{\"id\":\"c\",\"needsDevice\":true,\"approved\":true,\"head\":\"h\",\"screenAt\":\"h\",\"reviewAt\":\"g\",\"deviceAt\":null},\"sha\":\"h\"}"),
    ("landed card", lit "{\"card\":{\"id\":\"c\",\"needsDevice\":false,\"approved\":true,\"head\":\"h\",\"screenAt\":\"h\",\"reviewAt\":\"h\",\"landed\":true},\"sha\":\"h\"}"),
    ("missing needsDevice is refused", lit "{\"card\":{\"id\":\"c\"},\"sha\":\"h\"}")]),
  ("console", "console.alert", [
    ("permission prompt of an agent: names agent, kind and tool", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"tool_name\":\"Bash\",\"notification_type\":\"permission_prompt\",\"ts\":10}}"),
    ("needs input", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"notification_type\":\"agent_needs_input\",\"ts\":10}}"),
    ("the lead's own Notification is no alert", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"tool_name\":\"Bash\",\"ts\":10}}"),
    ("no agent_id: attributed to the single agent with a tool in flight", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"tool_name\":\"Bash\",\"ts\":10},\"flights\":[{\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"tool_name\":\"Bash\"},{\"tool_name\":\"Agent\"}]}"),
    ("no agent_id, two agents in flight: not attributable", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"ts\":10},\"flights\":[{\"agent_id\":\"a1\"},{\"agent_id\":\"a2\"}]}"),
    ("no agent_id, the lead has a tool of its own in flight: its prompt", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"ts\":10},\"flights\":[{\"agent_id\":\"a1\"},{\"tool_name\":\"Bash\"}]}"),
    ("an agent with an open alert gets no second one", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"ts\":12},\"open\":[\"alert-a1-10\"]}"),
    ("idle prompt is no alert", lit "{\"event\":{\"hook_event_name\":\"Notification\",\"agent_id\":\"a1\",\"notification_type\":\"idle_prompt\",\"ts\":10}}"),
    ("StopFailure of an agent", lit "{\"event\":{\"hook_event_name\":\"StopFailure\",\"agent_id\":\"a1\",\"agent_type\":\"builder\",\"ts\":4}}"),
    ("the agent's next tool result closes its earlier alerts only", lit "{\"event\":{\"hook_event_name\":\"PostToolUse\",\"agent_id\":\"a1\",\"tool_name\":\"Bash\",\"ts\":11},\"open\":[\"alert-a1-10\",\"alert-a2-10\",\"alert-a1-11\",\"alert-0123456789ab\"]}"),
    ("the lead's next tool result closes the lead's alert", lit "{\"event\":{\"hook_event_name\":\"PostToolUse\",\"ts\":11},\"open\":[\"alert-main-10\"]}"),
    ("SubagentStop closes", lit "{\"event\":{\"hook_event_name\":\"SubagentStop\",\"agent_id\":\"a1\",\"ts\":12},\"open\":[\"alert-a1-10\"]}"),
    ("missing ts is refused", lit "{\"event\":{\"hook_event_name\":\"Stop\"}}")]),
  ("console", "console.actor", [
    ("all sources", lit "{}"),
    ("the alert source writes as script", lit "{\"source\":\"alert\"}"),
    ("unknown source is refused", lit "{\"source\":\"lead\"}")])]

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
  let mut stale := 0
  for (sub, op, cs) in cases.map (fun (op, cs) => ("ops", op, cs)) ++ extra do
    let p := root / ".." / "packages" / "contracts" / "golden" / sub / s!"{op}.jsonl"
    if write then IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / sub)
    let text := fileText op cs
    if write then
      IO.FS.writeFile p text
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != text then
        IO.println s!"ops golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/OpsGolden.lean)"
        stale := stale + 1
  let n := cases.foldl (fun a c => a + c.2.length) 0 + extra.foldl (fun a c => a + c.2.2.length) 0
  IO.println s!"ops golden: {cases.length + extra.length} files, {n} cases, {if write then "written" else s!"{stale} stale"}"
  return stale

end Fw.Wire.Ops.Golden
