import Fw.Wire
import Fw.Console.PreviewTable
import Fw.Ops.LeanFirstSearch
/-!
# Golden vectors of the `ops.*` ops

`packages/contracts/golden/ops/<op>.jsonl`: one line per case, `{"name", "request", "response"}`,
where `request` carries its `op` and `response` is what `fwcore` replies (without the `id`).
The same format, from `extra`: `golden/plan/plan.trailers.jsonl` (reconciler `git.ts`) and
`golden/console/console.{landReadiness,actor}.jsonl` (console-api's own actors), `golden/lint/lint.context.jsonl`
(`scripts/context-lint.mjs`). From `named` (file stem not the op): `golden/ops/lean-first.jsonl` (`ops.leanFirst`,
the lean-first land gate over the single faults of the grid of `Fw.Ops.LeanFirstSearch`, at the deployed stage).
Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/OpsGolden.lean           # write the files
cd lean && lake env lean --run scripts/OpsGolden.lean --check   # fail if a file is stale
```

`lake test` runs the same check. Consumers: the hooks agent (`emit.mjs`, `spawn-guard.mjs`:
`ops.hook`, `ops.spawn`; `cap.mjs`: `ops.actor`, `ops.cap`), console-api's capability door (`cap.ts`
`actorFor`: `ops.actor`; `openDoor`: `ops.door`), the land agent (`fw land`: `ops.pathCheck`) and console-api's usage
meter (`ops.usage`, `ops.meter`), `fw watch` (`ops.watchDiff`, `ops.watchKeep`).
-/
namespace Fw.Wire.Ops.Golden
open Lean

/-- Parse a literal request (a parse error becomes a visible bad case). -/
def lit (s : String) : Json := (Json.parse s).toOption.getD (Json.mkObj [("unparsable", .str s)])

/-- Registry facts for the `console.buildsSearch` and `console.buildsOpen` cases: the shape of the site registry, with the parts and
variants the long search uses, one `requires` (the site's own) and one `conflicts` (synthetic: the site has none yet), and presets with
`extends`, a cycle and an `@impl` entry. -/
def searchRegistry : Json := lit "{\"parts\":[{\"id\":\"hero.countdown\",\"variants\":[\"faithful\",\"strip\",\"hidden-pause\",\"one-chain\"],\"impls\":[\"mui\",\"plain\"]},{\"id\":\"hero.exit\",\"variants\":[\"faithful\",\"scoped\"],\"impls\":[\"plain\"]},{\"id\":\"morph.countdown\",\"variants\":[\"faithful\",\"strip\",\"hidden-pause\"],\"impls\":[\"mui\",\"plain\"],\"requires\":{\"morph.countdown:strip\":[\"hero.countdown:strip\"]}},{\"id\":\"morph.mount\",\"variants\":[\"faithful\",\"shift\",\"shift-dormant\"],\"impls\":[\"mui\",\"plain\"]},{\"id\":\"morph.tween\",\"variants\":[\"faithful\",\"waapi\",\"waapi-scoped\"],\"impls\":[\"mui\",\"plain\"]},{\"id\":\"pain.notes\",\"variants\":[\"faithful\",\"visible\",\"visible-idem\"],\"impls\":[\"plain\"]},{\"id\":\"engine.scroll\",\"variants\":[\"faithful\",\"batched\"],\"impls\":[\"mui\",\"plain\"]},{\"id\":\"nav.hitTest\",\"variants\":[\"faithful\",\"hit-skip\",\"elements-skip\"],\"impls\":[\"mui\",\"plain\"],\"requires\":{},\"conflicts\":{\"nav.hitTest:hit-skip\":[\"engine.scroll:batched\"]}}],\"presets\":[{\"name\":\"original\",\"fw\":{}},{\"name\":\"strip-demo\",\"extends\":\"original\",\"fw\":{\"hero.countdown\":\"strip\"}},{\"name\":\"v2-proved\",\"extends\":\"original\",\"fw\":{\"engine.scroll\":\"batched\",\"morph.mount\":\"shift\",\"morph.tween\":\"waapi\",\"pain.notes\":\"visible\"}},{\"name\":\"loop-a\",\"extends\":\"loop-b\",\"fw\":{}},{\"name\":\"loop-b\",\"extends\":\"loop-a\",\"fw\":{}},{\"name\":\"plain-impl\",\"fw\":{\"hero.countdown\":\"one-chain@plain\"}},{\"name\":\"bad-impl\",\"fw\":{\"hero.exit\":\"scoped@mui\"}}]}"

/-- A `console.buildsSearch` request. -/
def srch (s : String) : Json := Json.mkObj [("registry", searchRegistry), ("search", .str s)]

/-- A `console.buildsOpen` request in search mode, with extra top-level fields from a JSON object text. -/
def openS (s extra : String) : Json :=
  let base := Json.mkObj [("mode", "search"), ("main", "m9"), ("search", .str s), ("registry", searchRegistry)]
  match lit extra with
  | .obj kvs => kvs.toList.foldl (fun j kv => j.setObjVal! kv.1 kv.2) base
  | _ => base

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

/-- An `ops.wait` request for one Bash command, with optional `caps` (a JSON text). -/
def wait' (cmd : String) (caps : String) : Json :=
  Json.mkObj [("cmd", .str cmd), ("caps", lit caps)]

/-- An `ops.wait` request for one Bash command. -/
def wait (cmd : String) : Json := Json.mkObj [("cmd", .str cmd)]

/-- The cases, per op file: (file stem, [(name, request without op)]). -/
def cases (_ : Unit := ()) : List (String × List (String × Json)) := [
  ("ops.spawn", [
    ("named worktree subagent with isolation: allow", spawn "[]" "" "{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"isolation\":\"worktree\",\"spawner\":\"lead\",\"depth\":0}"),
    ("worktree role without isolation becomes a teammate: deny (I-272 trap)", spawn "[]" "" "{\"name\":\"lean-ops\",\"role\":\"lean-prover\",\"spawner\":\"lead\",\"depth\":0}"),
    ("teammate role with worktree isolation: allow (shadow-log false positive)", spawn "[]" "" "{\"name\":\"res-1\",\"role\":\"researcher\",\"isolation\":\"worktree\"}"),
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
  ("ops.cap", [
    ("lead mints for pnpm fw status", lit "{\"tokens\":[\"pnpm\",\"fw\",\"status\"]}"),
    ("lead: agent_type ignored", lit "{\"agent_id\":null,\"agent_type\":\"main\",\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\",\"--task\",\"t\"]}"),
    ("agent mints as owner", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"lean-prover\",\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\"]}"),
    ("reviewer role mints as reviewer", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"Math-REVIEWER\",\"tokens\":[\"pnpm\",\"fw\",\"card\",\"review\"]}"),
    ("bare pnpm fw mints an empty argv", lit "{\"tokens\":[\"pnpm\",\"fw\"]}"),
    ("leading cd: notFwPrefix", lit "{\"tokens\":[\"cd\",\"apps/runner\"]}"),
    ("pnpm -s fw: notFwPrefix", lit "{\"tokens\":[\"pnpm\",\"-s\",\"fw\",\"land\",\"--dry\",\"b\"]}"),
    ("pnpm --filter x fw: notFwPrefix", lit "{\"tokens\":[\"pnpm\",\"--filter\",\"x\",\"fw\",\"status\"]}"),
    ("empty command: notFwPrefix", lit "{\"tokens\":[]}"),
    ("pnpm alone: notFwPrefix", lit "{\"tokens\":[\"pnpm\"]}"),
    ("a different program: notFwPrefix", lit "{\"tokens\":[\"echo\",\"pnpm\",\"fw\"]}"),
    ("2>&1 then a filter pipe mints for the bare command", lit "{\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\",{\"redir\":\"2>&1\"},{\"stop\":\"|\"},\"tail\",\"-5\"]}"),
    ("redirect to a file is dropped", lit "{\"tokens\":[\"pnpm\",\"fw\",\"status\",{\"redir\":\">out.txt\"}]}"),
    ("append redirect and 2>/dev/null are dropped", lit "{\"tokens\":[\"pnpm\",\"fw\",\"status\",{\"redir\":\">>log\"},{\"redir\":\"2>/dev/null\"}]}"),
    ("input redirect is dropped", lit "{\"tokens\":[\"pnpm\",\"fw\",\"send\",{\"redir\":\"<in\"}]}"),
    ("redirect between words is dropped", lit "{\"tokens\":[\"pnpm\",\"fw\",{\"redir\":\"2>&1\"},\"land\",\"b\"]}"),
    ("a pipe ends the command (grep filter)", lit "{\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\",{\"stop\":\"|\"},\"grep\",\"VERDICT\"]}"),
    ("&& ends the command", lit "{\"tokens\":[\"pnpm\",\"fw\",\"status\",{\"stop\":\"&&\"},\"echo\",\"done\"]}"),
    ("a lone number is an argument, not a redirect", lit "{\"tokens\":[\"pnpm\",\"fw\",\"land\",\"b\",\"2\"]}"),
    ("a pipe before pnpm fw: notFwPrefix", lit "{\"tokens\":[\"echo\",{\"stop\":\"|\"},\"pnpm\",\"fw\",\"status\"]}"),
    ("unknown actor stays refused through a pipe", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\",\"tokens\":[\"pnpm\",\"fw\",\"land\",{\"redir\":\"2>&1\"},{\"stop\":\"|\"},\"tail\"]}"),
    ("forked agent: unknownActor", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\",\"tokens\":[\"pnpm\",\"fw\",\"status\"]}"),
    ("agent_id without agent_type: unknownActor", lit "{\"agent_id\":\"a0123456789abcdef\",\"tokens\":[\"pnpm\",\"fw\",\"status\"]}"),
    ("empty agent_id: unknownActor", lit "{\"agent_id\":\"\",\"agent_type\":\"lean-prover\",\"tokens\":[\"pnpm\",\"fw\",\"status\"]}"),
    ("prefix wins over unknown actor", lit "{\"agent_id\":\"a0123456789abcdef\",\"agent_type\":\"\",\"tokens\":[\"cd\",\"x\"]}"),
    ("non-string token is refused", lit "{\"tokens\":[\"pnpm\",7]}"),
    ("non-string agent_id is refused", lit "{\"agent_id\":7,\"tokens\":[\"pnpm\",\"fw\"]}")]),
  ("ops.door", [
    ("user (the web UI) passes without the secret", lit "{\"actor\":\"user\"}"),
    ("script, git and hook pass without the secret", lit "{\"actor\":\"script\"}"),
    ("git passes", lit "{\"actor\":\"git\"}"),
    ("hook passes", lit "{\"actor\":\"hook\"}"),
    ("lead is refused without the secret", lit "{\"actor\":\"lead\"}"),
    ("owner is refused without the secret", lit "{\"actor\":\"owner\"}"),
    ("reviewer is refused without the secret", lit "{\"actor\":\"reviewer\",\"secret\":false}"),
    ("lead passes with the secret", lit "{\"actor\":\"lead\",\"secret\":true}"),
    ("owner passes with the secret", lit "{\"actor\":\"owner\",\"secret\":true}"),
    ("unknown actor name is refused", lit "{\"actor\":\"root\"}"),
    ("missing actor is refused", lit "{}")]),
  ("ops.obs", [
    ("keys: tool_use_id joins; without it the timestamp; no agent_id is main", lit "{\"records\":[{\"agent_id\":\"a1\",\"hook_event_name\":\"PostToolUse\",\"tool_use_id\":\"toolu_1\",\"ts\":5},{\"agent_id\":null,\"hook_event_name\":\"Stop\",\"tool_use_id\":null,\"ts\":7},{\"hook_event_name\":\"Notification\",\"ts\":9}]}"),
    ("keys: an empty agent_id stays empty (only null or missing is main)", lit "{\"records\":[{\"agent_id\":\"\",\"hook_event_name\":\"X\",\"tool_use_id\":\"\",\"ts\":7}]}"),
    ("summary: calls, errors and summed duration per (agent type, tool), first-seen order", lit "{\"lines\":[{\"key\":\"k1\",\"hook_event_name\":\"PostToolUse\",\"agent_type\":\"b\",\"tool_name\":\"Bash\",\"is_error\":false,\"duration_ms\":100,\"ts\":1},{\"hook_event_name\":\"Stop\",\"agent_type\":\"b\"},{\"hook_event_name\":\"PostToolUse\"},{\"hook_event_name\":\"PostToolUseFailure\",\"agent_type\":\"b\",\"tool_name\":\"Bash\",\"is_error\":true,\"duration_ms\":50}]}"),
    ("summary: null fields count as main, ?, no error and 0 ms", lit "{\"lines\":[{\"hook_event_name\":\"PostToolUse\",\"agent_type\":null,\"tool_name\":null,\"is_error\":null,\"duration_ms\":null}]}"),
    ("empty request: no keys, no rows", lit "{}"),
    ("record without ts is refused", lit "{\"records\":[{\"hook_event_name\":\"Stop\"}]}"),
    ("fractional duration is refused", lit "{\"lines\":[{\"hook_event_name\":\"PostToolUse\",\"duration_ms\":1.5}]}"),
    ("admission (task-state-truth): only decision fields reject; soft fields become null with a note; unknown fields are named; every rejection, note and unknown field is an issue",
      lit "{\"raw\":[\"{\\\"agent_id\\\":\\\"a1\\\",\\\"agent_type\\\":\\\"\\\",\\\"hook_event_name\\\":\\\"SubagentStop\\\",\\\"tool_name\\\":null,\\\"tool_use_id\\\":null,\\\"duration_ms\\\":null,\\\"is_error\\\":null,\\\"verb\\\":null,\\\"ts\\\":5,\\\"background_tasks\\\":20}\",\"{\\\"agent_id\\\":\\\"a1\\\",\\\"agent_type\\\":7,\\\"hook_event_name\\\":\\\"PostToolUse\\\",\\\"tool_name\\\":\\\"Bash\\\",\\\"tool_use_id\\\":\\\"t1\\\",\\\"duration_ms\\\":-1,\\\"is_error\\\":false,\\\"ts\\\":6,\\\"future\\\":1}\",\"{\\\"agent_id\\\":\\\"\\\",\\\"hook_event_name\\\":\\\"Stop\\\",\\\"ts\\\":7}\",\"not json\"]}"),
    ("life (task-state-truth): start and stop by id only (a name is never a life key), any other event is a heartbeat of the id, a named spawn guard spawns and labels its obs key",
      lit "{\"life\":[{\"event\":\"SubagentStart\",\"agent_id\":\"a1\",\"key\":\"k1\",\"ts\":1},{\"event\":\"SubagentStop\",\"agent_id\":\"a1\",\"key\":\"k2\",\"ts\":2},{\"event\":\"SubagentStop\",\"agent_id\":\"a2\",\"key\":\"k3\",\"ts\":3},{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k4\",\"ts\":1200000,\"epoch\":2},{\"event\":\"SpawnGuard\",\"agent_id\":\"lead\",\"agent_name\":\"fix-nav\",\"key\":\"k5\",\"ts\":9},{\"event\":\"Stop\",\"key\":\"k6\",\"ts\":9}]}"),
    ("life (alert-rules-fix): a heartbeat counts only while no stop was sent (epoch 0); after a stop (epoch > 0) only a start revives",
      lit "{\"life\":[{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k1\",\"ts\":1200000,\"epoch\":0},{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k2\",\"ts\":1200002,\"epoch\":1200000},{\"event\":\"SubagentStart\",\"agent_id\":\"a1\",\"key\":\"k3\",\"ts\":1300000,\"epoch\":1200000}]}"),
    ("life (alert-rules-fix, resume): stop, then a newer start, then a tool call heartbeats again; an older start resets nothing; the epochs are the drain's state after each record",
      lit "{\"life\":[{\"event\":\"SubagentStop\",\"agent_id\":\"a1\",\"key\":\"k1\",\"ts\":1200000,\"epoch\":0},{\"event\":\"SubagentStart\",\"agent_id\":\"a1\",\"key\":\"k2\",\"ts\":1100000,\"epoch\":1200000},{\"event\":\"SubagentStart\",\"agent_id\":\"a1\",\"key\":\"k3\",\"ts\":1300000,\"epoch\":1200000},{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k4\",\"ts\":2200000,\"epoch\":0},{\"event\":\"PostToolUse\",\"agent_id\":\"a1\",\"key\":\"k5\",\"ts\":2200001,\"epoch\":1200000}]}"),
    ("resume (alert-rules-fix): a StructuredOutput call 2 ms after the stop is not a resume (spool of a workflow subagent, 2026-10-19)",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":1445654},{\"event\":\"SubagentStop\",\"ts\":1454982},{\"event\":\"PostToolUse\",\"ts\":1454984}]}]}"),
    ("resume (alert-rules-fix): the same shape, 86 s agent",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":72892},{\"event\":\"SubagentStop\",\"ts\":86059},{\"event\":\"PostToolUse\",\"ts\":86062}]}]}"),
    ("resume (alert-rules-fix): the same shape, 57 s agent",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":50570},{\"event\":\"SubagentStop\",\"ts\":56823},{\"event\":\"PostToolUse\",\"ts\":56829}]}]}"),
    ("resume (alert-rules-fix): a SubagentHandback call after a second stop is not a resume",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":3049},{\"event\":\"PostToolUse\",\"ts\":5748},{\"event\":\"SubagentStop\",\"ts\":12670},{\"event\":\"SubagentStop\",\"ts\":18446},{\"event\":\"PostToolUse\",\"ts\":18450}]}]}"),
    ("resume (alert-rules-fix): a SubagentStart after the stop resumes",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":3941},{\"event\":\"PostToolUse\",\"ts\":9378545},{\"event\":\"PostToolUse\",\"ts\":9382232},{\"event\":\"SubagentStop\",\"ts\":9382453},{\"event\":\"SubagentStart\",\"ts\":20229172},{\"event\":\"PostToolUse\",\"ts\":20238537}]}]}"),
    ("resume (alert-rules-fix): a start at the stop time is not after it",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"SubagentStop\",\"ts\":10},{\"event\":\"SubagentStart\",\"ts\":10}]}]}"),
    ("resume (alert-rules-fix): records out of order, the newest stop wins and a start between two stops is old",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStop\",\"ts\":10},{\"event\":\"SubagentStart\",\"ts\":5},{\"event\":\"SubagentStop\",\"ts\":20}]}]}"),
    ("resume (alert-rules-fix): no stop, no stop time",
      lit "{\"resume\":[{\"hooks\":[{\"event\":\"SubagentStart\",\"ts\":0},{\"event\":\"PostToolUse\",\"ts\":3}]}]}"),
    ("resume (alert-rules-fix): an empty spool",
      lit "{\"resume\":[{\"hooks\":[]}]}"),
    ("labels (task-state-truth): a usable name labels the id; an empty name does not",
      lit "{\"labels\":[{\"id\":\"a1\",\"name\":\"fix-nav\"},{\"id\":\"a2\",\"name\":\"\"}]}"),
    ("spool alert (task-state-truth): issues with counts, none while a spool alert is open",
      lit "{\"fieldAlert\":{\"now\":5,\"open\":[],\"issues\":[{\"issue\":\"rejected:json\",\"count\":2},{\"issue\":\"lifeOf:error\",\"count\":1}]}}"),
    ("spool alert (task-state-truth): an open spool alert holds the next one",
      lit "{\"fieldAlert\":{\"now\":6,\"open\":[\"alert-spool-5\"],\"issues\":[{\"issue\":\"rejected:json\",\"count\":1}]}}"),
    ("spool alert (alert-rules-fix): only caught fwcore throws get the throw title, not the emit.mjs one",
      lit "{\"fieldAlert\":{\"now\":7,\"open\":[],\"issues\":[{\"issue\":\"sweep:lifeOf\",\"count\":3}]}}"),
    ("spool alert (alert-rules-fix): a throw and a rejected line together keep the spool title",
      lit "{\"fieldAlert\":{\"now\":8,\"open\":[],\"issues\":[{\"issue\":\"sweep:drain\",\"count\":1},{\"issue\":\"rejected:json\",\"count\":1}]}}")]),
  ("ops.wait", [
    ("fw watch with a trailing &: deny bgLong fwWatch", wait "pnpm fw watch --until-alert &"),
    ("fw watch in the foreground: allow", wait "pnpm fw watch --until-alert"),
    ("fw watch behind && and &: the whole list is backgrounded: deny", wait "cd x && node apps/runner/fw.mjs watch &"),
    ("test run sent to the background with a log: allow (not long-running)", wait "pnpm test > log.txt 2>&1 &"),
    ("2>&1 and &> are redirects, not background: allow", wait "pnpm vitest run 2>&1 | tail -5; cmd &> out.log"),
    ("& inside quotes is text: allow", wait "echo 'pnpm fw watch &' \"a & b\""),
    ("until loop with &: deny bgLong loop", wait "until grep -q done out.txt; do sleep 5; done &"),
    ("until loop in the foreground with no bound: deny unboundedLoop", wait "until grep -q done out.txt; do sleep 5; done"),
    ("while loop in the foreground with no bound: deny unboundedLoop", wait "while true; do sleep 60; done"),
    ("until loop with a counter test: allow", wait "i=0; until [ $i -gt 5 ]; do sleep 5; i=$((i+1)); done"),
    ("until loop with a clock deadline: allow", wait "until [ $SECONDS -ge 60 ]; do sleep 2; done"),
    ("timeout before until runs a command named until, no loop is parsed: allow", wait "timeout 60 until grep -q x f; do sleep 1; done"),
    ("loop inside timeout N bash -c: bounded by timeout: allow", wait "timeout 600 bash -c 'until gh run view 1 --exit-status; do sleep 30; done'"),
    ("for loop backgrounded around fw watch: deny bgLong fwWatch", wait "for f in a b; do pnpm fw watch; done &"),
    ("long sleep with &: deny bgLong longSleep", wait "sleep 600 &"),
    ("sleep with a minute suffix behind &&: deny", wait "sleep 2m && echo hi &"),
    ("short sleep with &: allow", wait "sleep 5 &"),
    ("sleep over the cap set by caps: deny", wait' "sleep 10 &" "{\"maxSleepSec\":5}"),
    ("dev server with &: deny bgLong server", wait "pnpm dev &"),
    ("node server script with &: deny bgLong server", wait "node apps/console-api/server.mjs & sleep 1; curl localhost"),
    ("tail -f with &: deny bgLong tail", wait "tail -f x.log &"),
    ("only the unit before & counts: a later foreground fw watch is allowed", wait "echo hi & pnpm fw watch"),
    ("newline continues an and-or list: the backgrounded list is long: deny", wait "a &&\n pnpm dev &"),
    ("comment is ignored: allow", wait "echo hi # pnpm fw watch &"),
    ("empty command: allow", wait ""),
    ("while-read loop over a file redirect: bounded by its input: allow", wait "while IFS= read -r line; do echo \"$line\"; done < list.txt"),
    ("while-read loop fed by a finite pipe: allow", wait "git ls-files | while read -r f; do wc -l \"$f\"; done | sort"),
    ("while-read loop over a here-string: allow", wait "while read -r a b; do echo $a; done <<< \"$pairs\""),
    ("here-document body is data, not commands: allow", wait "cat > f.py <<'EOF'\nwhile True:\n    pass\nEOF\npython3 f.py"),
    ("<<- here-document with a tab-indented delimiter: allow", wait "cat <<-EOF > x.sh\n\twhile true; do sleep 1; done\n\tEOF\necho ok"),
    ("nested read loops, both over finite input: allow", wait "find . -type f | while read f; do while read l; do echo $l; done < \"$f\"; done"),
    ("while-read loop on the tool's stdin: deny unboundedLoop", wait "while read l; do echo $l; done"),
    ("while-read loop fed by tail -f: deny unboundedLoop", wait "tail -f x.log | while read l; do echo $l; done"),
    ("while-read loop over a process substitution: deny unboundedLoop", wait "while read l; do echo $l; done < <(tail -f x.log)"),
    ("read with its own redirect re-reads line 1 forever: deny unboundedLoop", wait "while read l < f; do echo $l; done"),
    ("loop after do is still seen: deny unboundedLoop", wait "for f in a b; do while true; do sleep 1; done; done"),
    ("loop after a closed here-document is code again: deny unboundedLoop", wait "cat <<EOF > f\nx\nEOF\nwhile true; do sleep 1; done"),
    ("CI poll with no counter: deny unboundedLoop", wait "until [ \"$(gh run view 1 --json status -q .status)\" = completed ]; do sleep 150; done"),
    ("finite read loop with &: still a backgrounded loop: deny bgLong loop", wait "ls | while read f; do echo $f; done &"),
    ("read condition extended by || true never fails: deny unboundedLoop", wait "while read l || true; do sleep 1; done < f"),
    ("read condition extended by || : never fails: deny unboundedLoop", wait "while read l || :; do sleep 1; done < f"),
    ("read condition followed by another command before do: deny unboundedLoop", wait "while read l; [ 1 ]; do sleep 1; done < f"),
    ("read loop over a process substitution of an allowlisted producer: allow", wait "while read -r f; do echo $f; done < <(git diff --name-only main)"),
    ("read loop over a process substitution of ping: deny unboundedLoop", wait "while read l; do echo $l; done < <(ping x)"),
    ("producer outside the allowlist (ping): deny unboundedLoop", wait "ping x | while read l; do echo $l; done"),
    ("tail -fn is a follow: deny unboundedLoop", wait "tail -fn 10 log | while read l; do echo $l; done"),
    ("tail --follow=name is a follow: deny unboundedLoop", wait "tail --follow=name log | while read l; do echo $l; done"),
    ("cat of a device: deny unboundedLoop", wait "cat /dev/urandom | while read l; do echo $l; done"),
    ("cat - reads stdin: deny unboundedLoop", wait "cat - | while read l; do echo $l; done"),
    ("cat -u: deny unboundedLoop", wait "cat -u f | while read l; do echo $l; done"),
    ("log stream never ends: deny unboundedLoop", wait "log stream | while read l; do echo $l; done"),
    ("sleep infinity: deny unboundedLoop", wait "sleep infinity | while read l; do echo $l; done"),
    ("a filter after an endless producer: deny unboundedLoop", wait "tail -f log | grep x | while read l; do echo $l; done"),
    ("an allowlisted filter after a finite producer: allow", wait "git ls-files | grep lean | while read -r f; do wc -l \"$f\"; done"),
    ("a done redirect overrides the pipe: deny unboundedLoop", wait "ls | while read l; do echo $l; done < /dev/zero"),
    ("double-quoted <<EOF is text, the loop after it is code: deny unboundedLoop", wait "echo \"<<EOF\"\nuntil false; do sleep 5; done"),
    ("single-quoted <<EOF is text, the loop after it is code: deny unboundedLoop", wait "echo '<<EOF'\nuntil false; do sleep 5; done"),
    ("server smoke test with & and kill: deny bgLong server", wait "node server.mjs & pid=$!; sleep 1; curl -s localhost:3000; kill $pid"),
    ("r3: arithmetic in the body does not bound an endless read loop: deny", wait "tail -f log | while read l; do echo $((n+1)); done"),
    ("r3: date in the body does not bound a read loop over yes: deny", wait "yes | while read l; do echo; date; done"),
    ("r3: date in the body does not bound while true: deny", wait "while true; do date; sleep 1; done"),
    ("r3: date in the body does not bound a CI poll: deny", wait "until gh run view 1 --exit-status; do date; sleep 120; done"),
    ("r3: the word deadline is not a bound: deny", wait "until false; do sleep 1; echo deadline; done"),
    ("r3: $SECONDS not compared to a limit is not a bound: deny", wait "while [ \"$SECONDS\" ]; do sleep 1; done"),
    ("r3: a constant comparison is not a bound: deny", wait "while [ 1 -lt 2 ]; do sleep 1; done"),
    ("r3: a break in the body is not a bound: deny", wait "i=0; while :; do [ $i -lt 5 ] || break; i=$((i+1)); done"),
    ("r3: a counter test cannot clear a read of an endless input: deny", wait "i=0; tail -f log | while read l && [ $i -lt 9 ]; do i=$((i+1)); done"),
    ("r3: while with test || true never fails: deny", wait "i=0; while [ $i -lt 9 ] || true; do sleep 1; done"),
    ("r3: counter and an until-loop test in the condition: allow", wait "i=0; until gh run view 1 --exit-status || [ $i -ge 10 ]; do sleep 30; i=$((i+1)); done"),
    ("r3: file test and counter joined by &&: allow", wait "i=0; while [ ! -s \"$F\" ] && [ $i -lt 55 ]; do sleep 10; i=$((i+1)); done"),
    ("r3: arithmetic counter test: allow", wait "i=0; while (( i < 10 )); do i=$((i+1)); done"),
    ("r3: sed and awk filters after a finite producer: allow", wait "git log --oneline | sed 's/a/b/' | awk '{print $1}' | while read h; do echo $h; done"),
    ("r3: awk with a loop is not a finite filter: deny", wait "git log | awk '{while(1)print}' | while read h; do echo $h; done"),
    ("r3: xargs running echo over a finite input: allow", wait "ls | xargs -n 1 echo | while read l; do echo $l; done"),
    ("r3: gh pr list as a producer: allow", wait "gh pr list --json number -q '.[].number' | while read n; do gh pr view $n; done"),
    ("r3: read -d $'\\0' over find -print0: allow", wait "find . -name '*.json' -print0 | while IFS= read -r -d $'\\0' f; do echo \"$f\"; done"),
    ("r3: a repo node script is a finite producer: allow", wait "node scripts/list.mjs | while read l; do echo $l; done"),
    ("r3: pnpm is not a known finite producer: deny", wait "pnpm -s fw list | while read l; do echo $l; done"),
    ("r3: //dev/zero is a device: deny", wait "while read l; do echo $l; done < //dev/zero"),
    ("r3: ./../../dev/zero is a device: deny", wait "cat ./../../dev/zero | while read l; do echo $l; done"),
    ("r3: here-string running yes: deny", wait "while read l; do echo $l; done <<< \"$(yes)\""),
    ("r3: here-string running a finite producer: allow", wait "while read -r f; do echo $f; done <<< \"$(git diff --name-only)\""),
    ("r3: git reflog piped into a read loop: allow", wait "git reflog show main | head -12 | while read h rest; do echo $h; done"),
    ("r4: gh poll by command substitution compared with a number: deny", wait "until [ \"$(gh run list -b ci/x --json status -q length)\" -ge 1 ]; do sleep 120; done"),
    ("r4: ls count by command substitution: deny", wait "until [ \"$(ls out/*.json 2>/dev/null | wc -l)\" -gt 0 ]; do sleep 30; done"),
    ("r4: pgrep count by command substitution: deny", wait "while [ \"$(pgrep -c node)\" -gt 0 ]; do sleep 5; done"),
    ("r4: backquote substitution: deny", wait "while [ `echo 0` -lt 1 ]; do sleep 1; done"),
    ("r4: $$ is not a counter: deny", wait "while [ $$ -gt 0 ]; do sleep 1; done"),
    ("r4: $# is not a counter: deny", wait "while [ $# -ge 0 ]; do sleep 1; done"),
    ("r4: $RANDOM is not a counter: deny", wait "while [ $RANDOM -ge 0 ]; do sleep 1; done"),
    ("r4: ${x:-0} default expansion: deny", wait "while [ \"${x:-0}\" -lt 1 ]; do sleep 1; done"),
    ("r4: $((0)) arithmetic expansion: deny", wait "while [ $((0)) -lt 1 ]; do sleep 1; done"),
    ("r4: limit held in a variable ($end) is not a literal: deny", wait "end=$((SECONDS+60)); until [ $SECONDS -ge $end ]; do sleep 2; done"),
    ("r4: while with SECONDS growing away from the exit: deny", wait "while [ $SECONDS -ge 0 ]; do sleep 1; done"),
    ("r4: until with SECONDS growing away from the exit: deny", wait "until [ $SECONDS -lt 0 ]; do sleep 1; done"),
    ("r4: (( SECONDS >= 0 )) in a while: deny", wait "while (( SECONDS >= 0 )); do sleep 1; done"),
    ("r4: negated test is outside the grammar: deny", wait "while ! [ $SECONDS -lt 60 ]; do sleep 1; done"),
    ("r4: comma in (( )): deny", wait "i=0; while (( i < 10 , 1 )); do sleep 1; done"),
    ("r4: ternary in (( )): deny", wait "i=0; while (( i < 10 ? 1 : 1 )); do sleep 1; done"),
    ("r4: hex literal in (( )): deny", wait "while (( 0x0 < 1 )); do sleep 1; done"),
    ("r4: octal literal in (( )): deny", wait "while (( 010 < i )); do sleep 1; done"),
    ("r4: RANDOM in (( )): deny", wait "while (( RANDOM >= 0 )); do sleep 1; done"),
    ("r4: string order < in [[ ]]: deny", wait "i=0; while [[ $i < 10 ]]; do i=$((i+1)); done"),
    ("r4: read -n 0 reads nothing and never hits EOF: deny", wait "while read -n 0 x; do :; done < f.txt"),
    ("r4: read -t 0 only polls: deny", wait "while read -t 0; do :; done < f.txt"),
    ("r4: backslash-newline joins a keyword: deny", wait "whi\\\nle true; do sleep 1; done"),
    ("r4: while with SECONDS below a literal: allow", wait "while [ $SECONDS -lt 600 ]; do sleep 5; done"),
    ("r4: until with quoted SECONDS at a literal or a poll: allow", wait "until [ \"$SECONDS\" -ge 600 ] || gh run view 1 --exit-status; do sleep 30; done"),
    ("r4: until (( SECONDS > N )): allow", wait "until (( SECONDS > 600 )); do sleep 5; done"),
    ("r4: [[ ${i} -le 3 ]]: allow", wait "i=0; while [[ ${i} -le 3 ]]; do i=$((i+1)); done"),
    ("r4: producer with 2>/dev/null: allow", wait "ls -t a*.jsonl 2>/dev/null | head -3 | while read f; do echo $f; done"),
    ("r4: git worktree list piped into a read loop: allow", wait "git worktree list --porcelain | awk '/^worktree /{print $2}' | while read p; do echo $p; done"),
    ("r5: EPOCHSECONDS may be unset in zsh, never a bound: deny", wait "until [ $EPOCHSECONDS -ge 1760800000 ]; do sleep 1; done"),
    ("r5: a 23-digit literal is not a number: deny", wait "i=0; while [ $i -lt 12345678901234567890123 ]; do i=$((i+1)); done"),
    ("r5: $_ is reset by every command: deny", wait "while [ $_ -lt 10 ]; do sleep 1; done"),
    ("r6: BASH_MONOSECONDS in [ ] (unset in zsh and bash < 5.3): deny", wait "until [ $BASH_MONOSECONDS -ge 1 ]; do sleep 0.2; done"),
    ("r6: BASH_MONOSECONDS in (( )): deny", wait "until (( BASH_MONOSECONDS >= 1 )); do sleep 0.2; done"),
    ("r6: PIPESTATUS is reset by the shell: deny", wait "until [ $PIPESTATUS -ge 3 ]; do PIPESTATUS=$((PIPESTATUS+1)); done"),
    ("r6: GROUPS is fixed by the shell: deny", wait "until [ $GROUPS -ge 999999 ]; do GROUPS=$((GROUPS+1)); done"),
    ("r6: BASH_LINENO is set by the shell: deny", wait "until [ $BASH_LINENO -ge 3 ]; do BASH_LINENO=$((BASH_LINENO+1)); done"),
    ("r6: BASH_ARGV is set by the shell: deny", wait "until [ $BASH_ARGV -ge 3 ]; do BASH_ARGV=$((BASH_ARGV+1)); done"),
    ("r6: zsh status is reset by every command: deny", wait "while [ $status -lt 3 ]; do sleep 0.1; done"),
    ("r6: zsh status even when assigned first: deny", wait "status=0; while [ $status -lt 3 ]; do sleep 0.1; done"),
    ("r6: zsh TTYIDLE: deny", wait "while [ $TTYIDLE -lt 3 ]; do sleep 0.1; done"),
    ("r6: SECONDS against an epoch literal: deny", wait "while [ $SECONDS -lt 1792312012 ]; do sleep 1; done"),
    ("r6: an uppercase counter, even assigned: deny", wait "N=0; while [ $N -lt 5 ]; do N=$((N+1)); done"),
    ("r6: a counter never set by the command: deny", wait "while [ $i -lt 5 ]; do i=$((i+1)); done"),
    ("r6: a counter set only after && (may not run): deny", wait "true && i=0; until [ $i -ge 5 ]; do i=$((i+1)); done"),
    ("r6: lowercase counter set to a literal first: allow", wait "i=0; while [ $i -lt 5 ]; do echo $i; i=$((i+1)); done"),
    ("r6: SECONDS at the one-day cap: allow", wait "while [ $SECONDS -lt 86400 ]; do sleep 5; done"),
    ("missing cmd is refused", lit "{}")]),
  ("ops.watchDiff", [
    ("first check opens every alert, one line per key (first detail)", lit "{\"now\":[{\"code\":\"proc.long\",\"subject\":\"node#7\",\"detail\":\"31m\"},{\"code\":\"proc.long\",\"subject\":\"node#7\",\"detail\":\"32m\"},{\"code\":\"ci.slow\",\"subject\":\"run-1\"}]}"),
    ("open alerts stay quiet, a gone one closes, a new one opens", lit "{\"prev\":[{\"code\":\"proc.long\",\"subject\":\"node#7\"},{\"code\":\"ci.slow\",\"subject\":\"run-1\"}],\"now\":[{\"code\":\"ci.slow\",\"subject\":\"run-1\",\"detail\":\"x\"},{\"code\":\"agent.gone\",\"subject\":\"a1\",\"detail\":\"y\"}]}"),
    ("same code, other subject is another key", lit "{\"prev\":[{\"code\":\"proc.long\",\"subject\":\"node#7\"}],\"now\":[{\"code\":\"proc.long\",\"subject\":\"node#8\",\"detail\":\"\"}]}"),
    ("no alerts closes all, a repeated open key closes once", lit "{\"prev\":[{\"code\":\"a\",\"subject\":\"1\"},{\"code\":\"a\",\"subject\":\"1\"}],\"now\":[]}"),
    ("missing now is refused", lit "{\"prev\":[]}")]),
  ("ops.watchKeep", [
    ("same pid and start: live and kept", lit "{\"entries\":[{\"pid\":7,\"start\":1792300000}],\"rows\":[{\"pid\":7,\"start\":1792300000,\"args\":\"caffeinate -i\"}]}"),
    ("reused pid (other start): dropped, not kept", lit "{\"entries\":[{\"pid\":7,\"start\":1792300000}],\"rows\":[{\"pid\":7,\"start\":1792300001,\"args\":\"python\"}]}"),
    ("gone process: dropped", lit "{\"entries\":[{\"pid\":7,\"start\":1792300000},{\"pid\":8,\"start\":5}],\"rows\":[{\"pid\":8,\"start\":5,\"args\":\"x\"}]}"),
    ("the lead Monitor stream is kept without a declaration; other intervals are not", lit "{\"rows\":[{\"pid\":9,\"start\":1,\"args\":\"node apps/runner/src/fw.ts watch --interval 300 --stream\"},{\"pid\":10,\"start\":1,\"args\":\"node apps/runner/src/fw.ts watch --interval 60 --stream\"}]}"),
    ("a non-integer start is refused", lit "{\"entries\":[{\"pid\":7,\"start\":1.5}]}")])]

/-- One file of a `lint.context` request. -/
def lintFile (path : String) (bytes : Nat) (lines : List String) : Json :=
  Json.mkObj [("path", .str path), ("bytes", toJson bytes), ("lines", .arr (lines.toArray.map .str))]

/-- A `lint.context` request for these files. -/
def lintFiles (fs : List Json) : Json := Json.mkObj [("files", .arr fs.toArray)]

/-- `n` numbered lines. -/
def numbered (n : Nat) : List String := (List.range n).map fun k => s!"line {k}"

/-- The `lint.context` cases (Fw.Lint.Context); consumer `scripts/context-lint.mjs`. -/
def lintCases : List (String × Json) := [
  ("handoff: 30 lines is ok, 31 is over the line budget",
    lintFiles [lintFile "docs/team/handoffs/a.md" 300 (numbered 30), lintFile "docs/team/handoffs/b.md" 310 (numbered 31)]),
  ("CLAUDE.md: over 5600 bytes is over budget even with slop; at 5600 a dated note is slop",
    lintFiles [lintFile "CLAUDE.md" 5601 ["Rule (user decision 2026-10-17)."],
      lintFile "CLAUDE.md" 5600 ["Rule (user decision 2026-10-17)."]]),
  ("agent: a SHA in the body is slop; the description budget is 300 bytes",
    lintFiles [lintFile ".claude/agents/a.md" 200 ["---", "name: a", "description: short", "---", "Read src at 5b3d632."],
      lintFile ".claude/agents/b.md" 400 ["---", "name: b", "description: " ++ "".pushn 'x' 301, "---", "Body."]]),
  ("team doc: a heading named after a task is slop; a plain heading is ok",
    lintFiles [lintFile "docs/team/tools/land.md" 100 ["# land", "## Output (task land-dry)"],
      lintFile "docs/team/tools/x.md" 100 ["# x", "## Output (JSON)"]]),
  ("skill: an AI tell (em dash, inflated word, filler) is slop, the first hit's line is reported",
    lintFiles [lintFile ".claude/skills/s/SKILL.md" 100 ["---", "description: d", "---", "Plain line.", "We leverage — it."]]),
  ("handoffs and other files get no SHA or date check; other files have no budget",
    lintFiles [lintFile "docs/team/handoffs/c.md" 50 ["state: 5b3d632 on 2026-10-17"],
      lintFile "research/notes/n.md" 999999 ["delve"]]),
  ("no files: zero counts", lintFiles []),
  ("files missing: refused", Json.mkObj []),
  ("a file without lines: refused",
    Json.mkObj [("files", .arr #[Json.mkObj [("path", .str "CLAUDE.md"), ("bytes", toJson 1)]])])]

/-- Golden files outside `ops/`: (directory under `packages/contracts/golden`, op, cases). -/
def extra (_ : Unit := ()) : List (String × String × List (String × Json)) := [
  ("lint", "lint.context", lintCases),
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
  ("console", "console.landScope", [
    ("writes, own handoff, generated and registration files land", lit "{\"writes\":[\"apps/runner/src/land.ts\",\"apps/runner/test/land*.ts\"],\"names\":[\"pa-land\"],\"paths\":[\"apps/runner/src/land.ts\",\"apps/runner/test/land-x.ts\",\"docs/team/handoffs/pa-land.md\",\"packages/contracts/golden/ops/a.jsonl\",\"lean/Fw.lean\"]}"),
    ("a file outside every glob is refused", lit "{\"writes\":[\"apps/runner/src/land.ts\"],\"names\":[\"pa-land\"],\"paths\":[\"apps/runner/src/land.ts\",\"apps/site/x.tsx\",\"docs/team/handoffs/other.md\"]}"),
    ("no writes and no allow: refused with the reason", lit "{\"writes\":[],\"names\":[\"t\"],\"paths\":[\"a.md\"]}"),
    ("--allow admits its glob only", lit "{\"writes\":[],\"allow\":[\"notes/**\"],\"paths\":[\"notes/a.md\",\"x.md\"]}"),
    ("protected paths are refused even under **", lit "{\"writes\":[\"**\"],\"paths\":[\".git/config\",\".fw-console/events.jsonl\",\".claude/settings.json\",\"lean/.lake/x\",\"a.md\"]}"),
    ("names with a slash or star make no handoff glob", lit "{\"writes\":[\"a/**\"],\"names\":[\"../x\",\"b/*\"],\"paths\":[\"docs/team/handoffs/../x.md\",\"docs/team/handoffs/b/c.md\"]}"),
    ("missing paths is refused", lit "{\"writes\":[]}"),
    ("a port task lands its registration files (registry, App, shells, Gate/Scope, Parts/Golden, anchors, its Lean part)", lit "{\"writes\":[\"apps/site/src/parts/platform/**\"],\"names\":[\"port-platform\"],\"task\":\"port-platform\",\"stream\":\"parts\",\"paths\":[\"apps/site/src/registry/index.ts\",\"apps/site/src/App.tsx\",\"apps/site/scripts/gen-shells.mjs\",\"lean/Fw/Gate/Scope.lean\",\"lean/Fw/Parts/Golden.lean\",\"lean/Fw/Parts/PlatformSweep.lean\",\"packages/gate-breakpoints/src/anchors.json\",\"packages/gate-breakpoints/src/scope.gen.json\",\"apps/site/src/parts/platform/x.tsx\"]}"),
    ("a port task does not land another part's Lean module", lit "{\"writes\":[\"apps/site/src/parts/platform/**\"],\"task\":\"port-platform\",\"stream\":\"parts\",\"paths\":[\"lean/Fw/Parts/HeroExit.lean\"]}"),
    ("the same registration files are refused for a task of no known kind", lit "{\"writes\":[\"apps/site/src/parts/platform/**\"],\"task\":\"land-hardening\",\"stream\":\"console\",\"paths\":[\"apps/site/src/App.tsx\"]}"),
    ("a measurement task lands its package and baselines", lit "{\"writes\":[\"research/notes/x.md\"],\"task\":\"zone-baselines-webkit\",\"stream\":\"measure\",\"paths\":[\"packages/measure-webkit/src/a.ts\",\"packages/measure-webkit/test/a.test.ts\",\"results/baselines/webkit/a.json\"]}"),
    ("baselines are refused for a task outside the measure stream", lit "{\"writes\":[\"research/notes/x.md\"],\"task\":\"t\",\"stream\":\"console\",\"paths\":[\"results/baselines/a.json\"]}"),
    ("a proof task lands its Lean part files and engine golden", lit "{\"writes\":[\"lean/Fw/Parts/HiddenPause.lean\"],\"task\":\"proof-hidden-pause\",\"stream\":\"lean\",\"paths\":[\"lean/Fw/Parts/HiddenPause.lean\",\"lean/Fw/Parts/HiddenPauseOpt.lean\",\"packages/contracts/golden/engine/hidden-pause.jsonl\"]}"),
    ("protected paths stay refused for a port task even with --allow **", lit "{\"writes\":[\"a/**\"],\"allow\":[\"**\"],\"task\":\"port-x\",\"stream\":\"parts\",\"paths\":[\".git/config\",\"lean/.lake/x\",\".claude/settings.json\",\".fw-console/events.jsonl\"]}")]),
  ("console", "console.landLock", [
    ("no lock file: free", lit "{\"held\":false}"),
    ("a live pid holds it: busy", lit "{\"held\":true,\"alive\":true}"),
    ("a dead pid holds it: stale, reported", lit "{\"held\":true,\"alive\":false}"),
    ("missing held is refused", lit "{}")]),
  ("console", "console.landGuard", [
    ("no lock: any commit is allowed", lit "{\"held\":false}"),
    ("lock held by a live land: another commit is refused", lit "{\"held\":true,\"alive\":true,\"here\":true,\"own\":false}"),
    ("the land's own commit goes through", lit "{\"held\":true,\"alive\":true,\"here\":true,\"own\":true}"),
    ("a commit in another checkout is allowed", lit "{\"held\":true,\"alive\":true,\"here\":false,\"own\":false}"),
    ("dead pid: stale, refused and reported", lit "{\"held\":true,\"alive\":false,\"here\":true,\"own\":false}"),
    ("missing held is refused", lit "{}")]),
  ("console", "console.landCommit", [
    ("locked, merge open, head unchanged: commit", lit "{\"locked\":true,\"mergeHead\":\"b1\",\"head\":\"m0\",\"pre\":\"m0\"}"),
    ("no lock", lit "{\"locked\":false,\"mergeHead\":\"b1\",\"head\":\"m0\",\"pre\":\"m0\"}"),
    ("MERGE_HEAD gone: refuse, do not reset", lit "{\"locked\":true,\"mergeHead\":null,\"head\":\"m0\",\"pre\":\"m0\"}"),
    ("HEAD moved by another commit: refuse", lit "{\"locked\":true,\"mergeHead\":\"b1\",\"head\":\"x9\",\"pre\":\"m0\"}"),
    ("missing pre is refused", lit "{\"locked\":true,\"head\":\"m0\"}")]),
  ("console", "console.landPick", [
    ("the given branch has commits: keep it", lit "{\"givenAhead\":true,\"others\":[{\"name\":\"ci/t\",\"ahead\":true,\"contains\":true}]}"),
    ("nothing to land and no candidate", lit "{\"givenAhead\":false,\"others\":[]}"),
    ("the agent's ci branch is the one candidate", lit "{\"givenAhead\":false,\"others\":[{\"name\":\"ci/t\",\"ahead\":true,\"contains\":true},{\"name\":\"w\",\"ahead\":false,\"contains\":true}]}"),
    ("a candidate that does not contain the given branch is no candidate", lit "{\"givenAhead\":false,\"others\":[{\"name\":\"ci/t\",\"ahead\":true,\"contains\":false}]}"),
    ("two different candidates: ambiguous, refuse", lit "{\"givenAhead\":false,\"others\":[{\"name\":\"ci/t\",\"ahead\":true,\"contains\":true},{\"name\":\"w\",\"ahead\":true,\"contains\":true}]}"),
    ("missing givenAhead is refused", lit "{\"others\":[]}")]),
  ("console", "console.landPool", [
    ("idle machine: all cores", lit "{\"cores\":8,\"load\":0}"),
    ("light load: the free cores", lit "{\"cores\":8,\"load\":3}"),
    ("load at half the cores: half", lit "{\"cores\":8,\"load\":5}"),
    ("saturated: the fair-share floor, not one", lit "{\"cores\":8,\"load\":20}"),
    ("odd core count", lit "{\"cores\":10,\"load\":23}"),
    ("one core: one", lit "{\"cores\":1,\"load\":9}"),
    ("zero cores: still one", lit "{\"cores\":0,\"load\":0}"),
    ("missing load is refused", lit "{\"cores\":8}")]),
  ("console", "console.landRetry", [
    ("passed: no re-run", lit "{\"passed\":true,\"loadFailure\":false}"),
    ("passed with a timeout word in the log: no re-run", lit "{\"passed\":true,\"loadFailure\":true}"),
    ("failed by the code: final", lit "{\"passed\":false,\"loadFailure\":false}"),
    ("timed out under load: re-run alone", lit "{\"passed\":false,\"loadFailure\":true}"),
    ("missing loadFailure is refused", lit "{\"passed\":false}")]),
  ("console", "console.previewTarget", [
    ("landed on main: main", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"7ba0436\",\"onMain\":true,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("integrated only: the newest integration ref that contains it", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"4d26f44\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("an older ref when the newest does not contain it", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"4d26f44\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("the head is exactly an integration tip: that ref, not a newer one", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"26e5f53\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("a documentation-only handoff commit does not hide the commit the gate ran", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"handoff\",\"sha\":\"ad919a4\",\"onMain\":false,\"noCode\":true,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]},{\"src\":\"ci\",\"sha\":\"26e5f53\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}],\"children\":[]}"),
    ("a head with no code that nothing holds: the newest integration ref", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"named\",\"sha\":\"ef1774f\",\"onMain\":false,\"noCode\":true,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]}],\"children\":[]}"),
    ("a head with code that nothing holds: its own head", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"named\",\"sha\":\"0f5cdb7\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]}],\"children\":[]}"),
    ("no integration ref at all and no code: its own head", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"named\",\"sha\":\"0f5cdb7\",\"onMain\":false,\"noCode\":true,\"cands\":[]}],\"children\":[]}"),
    ("no head and no sub-task: no preview", lit "{\"main\":\"25d9402\",\"facts\":[],\"children\":[]}"),
    ("an umbrella whose sub-tasks are all on main: main", lit "{\"main\":\"25d9402\",\"facts\":[],\"children\":[{\"facts\":[{\"src\":\"ci\",\"sha\":\"a1\",\"onMain\":true,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}]},{\"facts\":[{\"src\":\"ci\",\"sha\":\"a2\",\"onMain\":true,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}]}]}"),
    ("an umbrella with one sub-task only integrated: the first ref that holds all", lit "{\"main\":\"25d9402\",\"facts\":[],\"children\":[{\"facts\":[{\"src\":\"ci\",\"sha\":\"a1\",\"onMain\":true,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}]},{\"facts\":[{\"src\":\"ci\",\"sha\":\"a2\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]}]}]}"),
    ("an umbrella whose sub-tasks share no ref: no preview", lit "{\"main\":\"25d9402\",\"facts\":[],\"children\":[{\"facts\":[{\"src\":\"ci\",\"sha\":\"a1\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":true},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":false}]}]},{\"facts\":[{\"src\":\"ci\",\"sha\":\"a2\",\"onMain\":false,\"noCode\":false,\"cands\":[{\"ref\":\"origin/ci/integrate-ports-3\",\"sha\":\"b35b541\",\"contains\":false},{\"ref\":\"integrate-ports-2\",\"sha\":\"26e5f53\",\"contains\":true}]}]}]}"),
    ("a head that is a direct commit on main's first-parent line is its own land commit", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"d1d1d1d\",\"onMain\":true,\"noCode\":false,\"fpLine\":true,\"path\":[],\"cands\":[]}],\"children\":[]}"),
    ("a landed head previews the first line commit whose second parent holds it", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"ci\",\"sha\":\"a1a1a1a\",\"onMain\":true,\"noCode\":false,\"fpLine\":false,\"path\":[{\"sha\":\"b2b2b2b\",\"p2Has\":false},{\"sha\":\"c3c3c3c\",\"p2Has\":true},{\"sha\":\"e5e5e5e\",\"p2Has\":true}],\"cands\":[]}],\"children\":[]}"),
    ("a merge whose second parent does not hold the task's work is never the head", lit "{\"main\":\"25d9402\",\"facts\":[{\"src\":\"merge\",\"sha\":\"f6f6f6f\",\"onMain\":true,\"noCode\":false,\"fpLine\":true,\"ownWork\":false,\"path\":[],\"cands\":[]},{\"src\":\"originCi\",\"sha\":\"5b50ad0\",\"onMain\":true,\"noCode\":false,\"fpLine\":false,\"path\":[{\"sha\":\"6e968ba\",\"p2Has\":true}],\"cands\":[]},{\"src\":\"handoffCommit\",\"sha\":\"72971b8\",\"onMain\":true,\"noCode\":false,\"behind\":true,\"fpLine\":false,\"path\":[{\"sha\":\"6e968ba\",\"p2Has\":true}],\"cands\":[]}],\"children\":[]}"),
    ("missing main is refused", lit "{\"facts\":[]}")] ++ Fw.Console.PreviewTable.goldenCases),
  ("console", "console.previewAdmit", [
    ("the user starts the first preview: the two lowest ports", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[]}"),
    ("a test range: the base moves both ports, the production range is not touched", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"portBase\":47300,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47300,\"op\":47301,\"started\":0}]}"),
    ("a base whose backend ports would leave the port space is refused noPorts", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"portBase\":64600,\"live\":[]}"),
    ("the highest base that fits is admitted", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"portBase\":64496,\"live\":[]}"),
    ("the second preview takes the next two", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a freed port pair is reused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("a third preview is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("the same task twice is refused", lit "{\"preview\":\"n\",\"task\":\"port-nav\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the same id twice is refused", lit "{\"preview\":\"a\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("low disk is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":100,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[]}"),
    ("no target is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":false,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[]}"),
    ("the console secret is refused even with cookie and origin", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":true,\"cookie\":true,\"origin\":true,\"live\":[]}"),
    ("no owner cookie is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":false,\"origin\":true,\"live\":[]}"),
    ("no same-origin Origin is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":false,\"live\":[]}"),
    ("neither cookie nor origin is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":false,\"origin\":false,\"live\":[]}"),
    ("a missing proof field is refused", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"live\":[]}"),
    ("missing now is refused", lit "{\"secret\":false,\"cookie\":true,\"origin\":true,\"preview\":\"n\",\"task\":\"t\",\"diskMb\":9000,\"hasTarget\":true,\"live\":[]}")]),
  ("console", "console.previewTick", [
    ("nothing live", lit "{\"now\":10,\"live\":[]}"),
    ("both inside the TTL", lit "{\"now\":3000000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("the older one is past its deadline", lit "{\"now\":3600000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("both past", lit "{\"now\":3700000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}")]),
  ("console", "console.previewStop", [
    ("the user stops a recorded preview", lit "{\"secret\":false,\"cookie\":true,\"origin\":true,\"preview\":\"a\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("an id that is not in the table kills nothing", lit "{\"secret\":false,\"cookie\":true,\"origin\":true,\"preview\":\"zzz\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("a request without the owner cookie is refused", lit "{\"secret\":false,\"cookie\":false,\"origin\":true,\"preview\":\"a\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}")]),
  ("console", "console.previewFail", [
    ("a failed build leaves the table", lit "{\"preview\":\"a\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("an id that is not in the table changes nothing", lit "{\"preview\":\"zzz\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("missing live is fine: empty table", lit "{\"preview\":\"a\"}")]),
  ("console", "console.previewLink", [
    ("a terminal: the link goes to the tty, the only allowed sink", lit "{\"hasTty\":true}"),
    ("no terminal: no link is printed", lit "{\"hasTty\":false}"),
    ("a first reissue is allowed", lit "{\"hasTty\":true,\"now\":5000}"),
    ("a reissue 59.999 s after the last link is refused", lit "{\"hasTty\":true,\"now\":70000,\"last\":10001}"),
    ("a reissue a minute after the last link is allowed", lit "{\"hasTty\":true,\"now\":70000,\"last\":10000}")]),
  ("console", "console.previewReap", [
    ("everything recorded is killed", lit "{\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("empty table", lit "{\"live\":[]}")]),
  ("console", "console.ownerLogin", [
    ("a fresh address with the right passphrase gets in", lit "{\"enabled\":true,\"correct\":true,\"now\":1000}"),
    ("a wrong passphrase is recorded at the address and globally", lit "{\"enabled\":true,\"correct\":false,\"now\":1000}"),
    ("the fifth failure inside the window locks the address for 10 minutes", lit "{\"enabled\":true,\"correct\":false,\"now\":5000,\"fails\":[1000,2000,3000,4000]}"),
    ("failures older than the window are forgotten", lit "{\"enabled\":true,\"correct\":false,\"now\":700000,\"fails\":[1000,2000,3000,4000]}"),
    ("a locked address is refused even with the right passphrase", lit "{\"enabled\":true,\"correct\":true,\"now\":5001,\"lockUntil\":605000}"),
    ("the lock ends at its end time", lit "{\"enabled\":true,\"correct\":true,\"now\":605000,\"lockUntil\":605000}"),
    ("a console without a passphrase refuses the login", lit "{\"enabled\":false,\"correct\":true,\"now\":1000}"),
    ("a missing correct field is refused", lit "{\"enabled\":true,\"now\":1000}"),
    ("the twentieth global failure locks every address, a fresh one included", lit "{\"enabled\":true,\"correct\":false,\"now\":20000,\"gFails\":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19]}"),
    ("a global lock refuses a fresh address with the right passphrase", lit "{\"enabled\":true,\"correct\":true,\"now\":20001,\"gLockUntil\":620000}"),
    ("a global lock that ended lets a correct passphrase in", lit "{\"enabled\":true,\"correct\":true,\"now\":620000,\"gLockUntil\":620000}"),
    ("a wrong passphrase adds to the global failures", lit "{\"enabled\":true,\"correct\":false,\"now\":3000,\"gFails\":[1000,2000]}"),
    ("global failures older than the window are forgotten", lit "{\"enabled\":true,\"correct\":false,\"now\":700000,\"gFails\":[1000,2000,3000]}")]),
  ("console", "console.previewCache", [
    ("a manifest name is immutable", lit "{\"path\":\"/assets/index-BxK3a9Qz.js\",\"manifest\":[\"/assets/index-BxK3a9Qz.js\"]}"),
    ("the same name outside the manifest revalidates", lit "{\"path\":\"/assets/index-BxK3a9Qz.js\"}"),
    ("a manifest css name is immutable", lit "{\"path\":\"/assets/entry-client-CQgE-Jzo.css\",\"manifest\":[\"/assets/entry-client-BrkKyAS_.js\",\"/assets/entry-client-CQgE-Jzo.css\"]}"),
    ("hashed font under _app/immutable: immutable, not compressed", lit "{\"path\":\"/_app/immutable/assets/google-sans-latin-normal.BbZhqv4U.woff2\"}"),
    ("anything under _app/immutable is immutable", lit "{\"path\":\"/_app/immutable/chunks/x.js\"}"),
    ("mui.<sha8>.css is immutable", lit "{\"path\":\"/mui.b3bea9d9.css\"}"),
    ("a mui css name with a capital is not", lit "{\"path\":\"/mui.B3bea9d9.css\"}"),
    ("a mui css name below a directory is not", lit "{\"path\":\"/x/mui.b3bea9d9.css\"}"),
    ("html revalidates", lit "{\"path\":\"/index.html\"}"),
    ("a manifest html name still revalidates", lit "{\"path\":\"/assets/index-BxK3a9Qz.html\",\"manifest\":[\"/assets/index-BxK3a9Qz.html\"]}"),
    ("a root path revalidates", lit "{\"path\":\"/\"}"),
    ("an unhashed font revalidates", lit "{\"path\":\"/selling/fonts/playpen-sans-latin.woff2\"}"),
    ("Roboto-SemiBold looks hashed but is not listed: other", lit "{\"path\":\"/fonts/Roboto-SemiBold.woff2\"}"),
    ("og-1200x630 looks hashed but is not listed: other", lit "{\"path\":\"/img/og-1200x630.png\"}"),
    ("icon-darkMode looks hashed but is not listed: other", lit "{\"path\":\"/icons/icon-darkMode.svg\"}"),
    ("a hash-looking name beside a manifest that lacks it: other", lit "{\"path\":\"/assets/app.4f3a9c1d.css\",\"manifest\":[\"/assets/x.js\"]}"),
    ("svg is compressed, png is not", lit "{\"path\":\"/selling/a.svg\"}"),
    ("png revalidates, not compressed", lit "{\"path\":\"/selling/a.png\"}"),
    ("a manifest that is not an array of strings is refused", lit "{\"path\":\"/a.js\",\"manifest\":[1]}"),
    ("missing path is refused", lit "{}")]),
  ("console", "console.builds", [
    ("landed port and fix tasks, newest first; one row per task at its newest land commit; unknown and non-port tasks left out", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"c5\",\"time\":500,\"body\":\"land hero\\n\\nTask: port-hero\\n\"},{\"sha\":\"c4\",\"time\":400,\"body\":\"graph: x\\n\\nTask: proof-lean\\n\"},{\"sha\":\"c3\",\"time\":300,\"body\":\"land nav fix\\n\\nTask: fix-nav\\n\"},{\"sha\":\"c2\",\"time\":350,\"body\":\"re-land hero\\n\\nTask: port-hero\\n\"},{\"sha\":\"c1\",\"time\":100,\"body\":\"land ghost\\n\\nTask: port-ghost\\n\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"flags\":[],\"presets\":[]}"),
    ("no landings: no port rows", lit "{\"main\":\"m9\",\"log\":[],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"flags\":[],\"presets\":[]}"),
    ("a commit with two trailers gives two rows", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"d1\",\"time\":10,\"body\":\"both\\n\\nTask: port-hero\\nTask: fix-nav\\n\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"flags\":[],\"presets\":[]}"),
    ("flag and preset rows: status from the v2-proved preset, C3 flag out, faithful baseline, requires in the search, target is main", lit "{\"main\":\"m9\",\"log\":[],\"known\":[],\"flags\":[{\"part\":\"hero.countdown\",\"variant\":\"faithful\",\"kind\":\"faithful\"},{\"part\":\"hero.countdown\",\"variant\":\"strip\",\"kind\":\"optimized\"},{\"part\":\"engine.scroll\",\"variant\":\"batched\",\"kind\":\"optimized\"},{\"part\":\"nav.hitTest\",\"variant\":\"elements-skip\",\"kind\":\"optimized\"},{\"part\":\"morph.countdown\",\"variant\":\"strip\",\"kind\":\"optimized\",\"requires\":[\"hero.countdown:strip\"]}],\"presets\":[{\"name\":\"original\",\"fw\":{}},{\"name\":\"v2-proved\",\"fw\":{\"engine.scroll\":\"batched\",\"hero.countdown\":\"strip\"}}]}"),
    ("no v2-proved preset: nothing is proved, C3 stays out", lit "{\"main\":\"m9\",\"log\":[],\"known\":[],\"flags\":[{\"part\":\"hero.countdown\",\"variant\":\"faithful\",\"kind\":\"faithful\"},{\"part\":\"hero.countdown\",\"variant\":\"strip\",\"kind\":\"optimized\"},{\"part\":\"engine.scroll\",\"variant\":\"batched\",\"kind\":\"optimized\"},{\"part\":\"nav.hitTest\",\"variant\":\"elements-skip\",\"kind\":\"optimized\"},{\"part\":\"morph.countdown\",\"variant\":\"strip\",\"kind\":\"optimized\",\"requires\":[\"hero.countdown:strip\"]}],\"presets\":[{\"name\":\"original\",\"fw\":{}}]}"),
    ("evidence only: a task without a trailer gets a row at its evidence land commit with its own land slot", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"e3\",\"time\":300,\"body\":\"land nav\\n\\nTask: fix-nav\\n\"},{\"sha\":\"e2\",\"time\":200,\"body\":\"merge old hero work\"},{\"sha\":\"e1\",\"time\":100,\"body\":\"root\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"evidence\":[{\"task\":\"port-hero\",\"sha\":\"e2\"}],\"flags\":[],\"presets\":[]}"),
    ("a trailer landing wins over an evidence fact of the same task", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"t3\",\"time\":300,\"body\":\"land hero\\n\\nTask: port-hero\\n\"},{\"sha\":\"t2\",\"time\":200,\"body\":\"merge old hero work\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"evidence\":[{\"task\":\"port-hero\",\"sha\":\"t2\"}],\"flags\":[],\"presets\":[]}"),
    ("evidence whose land commit is not in the log, and evidence of a non-port task, give no row", lit "{\"main\":\"m9\",\"log\":[{\"sha\":\"n2\",\"time\":200,\"body\":\"merge\"}],\"known\":[{\"id\":\"port-hero\",\"title\":\"Hero port\"},{\"id\":\"fix-nav\",\"title\":\"Nav fix\"},{\"id\":\"proof-lean\",\"title\":\"A proof\"},{\"id\":\"port-later\",\"title\":\"Not landed yet\"}],\"evidence\":[{\"task\":\"port-hero\",\"sha\":\"zz\"},{\"task\":\"proof-lean\",\"sha\":\"n2\"},{\"task\":\"port-ghost\",\"sha\":\"n2\"}],\"flags\":[],\"presets\":[]}"),
    ("a preset that extends another: the glue passes the resolved fw, so an inherited variant is v2-proved", lit "{\"main\":\"m9\",\"log\":[],\"known\":[],\"evidence\":[],\"flags\":[{\"part\":\"engine.scroll\",\"variant\":\"batched\",\"kind\":\"optimized\"},{\"part\":\"nav.hitTest\",\"variant\":\"elements-skip\",\"kind\":\"optimized\"}],\"presets\":[{\"name\":\"original\",\"fw\":{\"engine.scroll\":\"batched\"}},{\"name\":\"v2-proved\",\"fw\":{\"engine.scroll\":\"batched\",\"nav.hitTest\":\"elements-skip\"}}]}"),
    ("a malformed flag is refused", lit "{\"main\":\"m9\",\"log\":[],\"known\":[],\"flags\":[{\"part\":\"a\"}],\"presets\":[]}"),
    ("missing main is refused", lit "{\"log\":[],\"known\":[],\"flags\":[],\"presets\":[]}")]),
  ("console", "console.buildsSearch", [
    ("the long search: v2-proved, then five flags; accepted, canonical form unchanged", srch "?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped"),
    ("v2-proved alone", srch "?preset=v2-proved"),
    ("the empty search is the default page", srch ""),
    ("a lone question mark is the default page", srch "?"),
    ("no leading question mark is read the same", srch "preset=v2-proved"),
    ("a preset that extends another", srch "?preset=strip-demo"),
    ("the fw entries of several fw parameters are joined in order", srch "?fw=hero.exit:scoped&fw=pain.notes:visible"),
    ("the preset comes first in the canonical form, whatever the order given", srch "?fw=hero.exit:scoped&preset=v2-proved"),
    ("a later fw entry overrides the preset", srch "?preset=v2-proved&fw=morph.mount:shift-dormant"),
    ("empty fw entries and unknown parameters are dropped", srch "?utm=1&fw=,hero.exit:scoped,&fw="),
    ("an impl the part has", srch "?fw=hero.countdown:strip@plain"),
    ("an impl from a preset", srch "?preset=plain-impl"),
    ("an unknown part", srch "?fw=hero.nothing:strip"),
    ("an unknown variant", srch "?fw=hero.exit:nope"),
    ("an unknown impl", srch "?fw=hero.exit:scoped@mui"),
    ("an unknown impl in a preset", srch "?preset=bad-impl"),
    ("two presets", srch "?preset=original&preset=v2-proved"),
    ("an unknown preset", srch "?preset=nope"),
    ("an empty preset name", srch "?preset="),
    ("a preset cycle", srch "?preset=loop-a"),
    ("a requires violation", srch "?fw=morph.countdown:strip"),
    ("the requirement chosen too: accepted", srch "?fw=hero.countdown:strip,morph.countdown:strip"),
    ("a conflicts violation", srch "?fw=nav.hitTest:hit-skip,engine.scroll:batched"),
    ("a conflicts violation across a preset and an fw entry", srch "?preset=v2-proved&fw=nav.hitTest:hit-skip"),
    ("an entry without a variant", srch "?fw=hero.exit"),
    ("an entry with two colons", srch "?fw=hero.exit:scoped:x"),
    ("several errors are all reported, in the site's order", srch "?preset=original&preset=nope&fw=a:b,hero.exit:nope,zzz"),
    ("a percent escape is refused", srch "?fw=hero.exit:scoped%20x"),
    ("angle brackets are refused", srch "?fw=<script>"),
    ("a space is refused", srch "?fw=hero.exit:scoped hero.countdown:strip"),
    ("a second question mark is refused", srch "??fw=hero.exit:scoped"),
    ("a fragment is refused", srch "?fw=hero.exit:scoped#x"),
    ("a search over 2000 characters is refused", srch ("?fw=" ++ "".pushn 'a' 2001)),
    ("a missing registry is refused", Json.mkObj [("search", "?preset=original")])]),
  ("console", "console.buildsOpen", [
    ("a row reuses a serving preview of its commit and opens the rewrite arm", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p1\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a row reuses a serving preview of another slot at the same commit", lit "{\"mode\":\"row\",\"slot\":\"opt-flag-x\",\"sha\":\"m9\",\"search\":\"?fw=a:b\",\"previews\":[{\"id\":\"p2\",\"slot\":\"land-port-hero\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("the compare arm", lit "{\"mode\":\"row\",\"arm\":\"compare\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p1\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a port row opens at the default page", lit "{\"mode\":\"row\",\"slot\":\"land-port-hero\",\"sha\":\"c5\",\"search\":\"\",\"previews\":[{\"id\":\"p3\",\"slot\":\"land-port-hero\",\"sha\":\"c5\",\"serving\":true}],\"port\":47001}"),
    ("a building preview of the commit: wait for it, start nothing", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p4\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"serving\":false}],\"port\":47001}"),
    ("a serving preview wins over a building one of the same commit", lit "{\"mode\":\"row\",\"slot\":\"s\",\"sha\":\"m9\",\"search\":\"\",\"previews\":[{\"id\":\"b\",\"slot\":\"s\",\"sha\":\"m9\",\"serving\":false},{\"id\":\"a\",\"slot\":\"t\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("the slot holds a preview of an older commit: rebuild", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p5\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m1\",\"serving\":true}],\"port\":47001}"),
    ("a preview of another commit in another slot: start", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p6\",\"slot\":\"land-port-hero\",\"sha\":\"m1\",\"serving\":true}],\"port\":47001}"),
    ("no preview at all: start", lit "{\"mode\":\"row\",\"slot\":\"opt-preset-v2-proved\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[]}"),
    ("LAN on with an address: the link uses it", lit "{\"mode\":\"row\",\"slot\":\"s\",\"sha\":\"m9\",\"search\":\"?preset=v2-proved\",\"previews\":[{\"id\":\"p1\",\"slot\":\"s\",\"sha\":\"m9\",\"serving\":true}],\"lan\":true,\"lanAddr\":\"192.0.2.10\",\"port\":47001}"),
    ("LAN on but no address known: loopback", lit "{\"mode\":\"row\",\"slot\":\"s\",\"sha\":\"m9\",\"search\":\"\",\"previews\":[{\"id\":\"p1\",\"slot\":\"s\",\"sha\":\"m9\",\"serving\":true}],\"lan\":true,\"port\":47001}"),
    ("LAN off: loopback even when an address is given", lit "{\"mode\":\"row\",\"slot\":\"s\",\"sha\":\"m9\",\"search\":\"\",\"previews\":[{\"id\":\"p1\",\"slot\":\"s\",\"sha\":\"m9\",\"serving\":true}],\"lan\":false,\"lanAddr\":\"192.0.2.10\",\"port\":47001}"),
    ("a valid pasted search reuses the main build", openS "?preset=v2-proved&fw=hero.exit:scoped" "{\"previews\":[{\"id\":\"p1\",\"slot\":\"opt-preset-original\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a pasted search is opened in canonical form", openS "?fw=hero.exit:scoped&preset=v2-proved" "{\"previews\":[{\"id\":\"p1\",\"slot\":\"x\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a pasted search with no main preview starts the main slot", openS "?preset=v2-proved" "{\"previews\":[{\"id\":\"p1\",\"slot\":\"x\",\"sha\":\"m1\",\"serving\":true}]}"),
    ("the main slot holds an older main: rebuild", openS "?preset=v2-proved" "{\"previews\":[{\"id\":\"p7\",\"slot\":\"open-main\",\"sha\":\"m1\",\"serving\":true}]}"),
    ("a refused search opens nothing even when a preview serves", openS "?preset=original&preset=v2-proved" "{\"previews\":[{\"id\":\"p1\",\"slot\":\"x\",\"sha\":\"m9\",\"serving\":true}],\"port\":47001}"),
    ("a bad charset opens nothing", openS "?fw=hero.exit:scoped%20x" "{\"previews\":[]}"),
    ("an unknown arm is refused", lit "{\"mode\":\"row\",\"arm\":\"x\",\"slot\":\"s\",\"sha\":\"m9\",\"previews\":[]}"),
    ("an unknown mode is refused", lit "{\"mode\":\"x\",\"previews\":[]}")]),
  ("console", "console.buildsPicker", [
    ("keys of a build: default first, then presets, then flags, each in key order", lit "{\"keys\":[\"?fw=hero.countdown:strip\",\"?preset=v2-proved\",\"\",\"?fw=a:b,c:d\",\"?preset=original\"],\"current\":\"?fw=a:b,c:d\"}"),
    ("an unknown current search falls back to the default", lit "{\"keys\":[\"\",\"?preset=original\"],\"current\":\"?fw=zzz\"}"),
    ("a current search that is not prerendered is not offered even when well formed", lit "{\"keys\":[\"\",\"?preset=original\"],\"current\":\"?preset=v2-proved\"}"),
    ("a key outside the alphabets is never offered", lit "{\"keys\":[\"\",\"?fw=a\\\"b\",\"?preset=<x>\",\"?other=1\",\"?fw=\",\"?preset=\"],\"current\":\"?preset=<x>\"}"),
    ("no current search: the default", lit "{\"keys\":[\"\",\"?preset=original\"]}"),
    ("a build without the default key: the current search that is offered stays", lit "{\"keys\":[\"?preset=original\"],\"current\":\"?preset=original\"}"),
    ("missing keys: an empty picker", lit "{\"current\":\"\"}")]),
  ("console", "console.ownerGate", [
    ("LAN, no session: the login page", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/owner/login\"}"),
    ("LAN, no token: the shell (the built console web) is served", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/\"}"),
    ("LAN, no token: a static asset is shell", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/assets/index.js\"}"),
    ("LAN, no token: the owner link route is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/owner\"}"),
    ("LAN, no token: logout is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/owner/logout\"}"),
    ("LAN, no token, foreign Host: the shell is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":false,\"path\":\"/\"}"),
    ("LAN, no session: the API is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/api/board\"}"),
    ("LAN, no session: a preview path is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/r/\"}"),
    ("LAN, no session: another spelling of the login path is refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/owner/login/\"}"),
    ("LAN with a session: the console web", lit "{\"lan\":true,\"session\":true,\"hostOk\":true,\"path\":\"/\"}"),
    ("LAN with a session: the console port never serves a preview path", lit "{\"lan\":true,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/r/\"}"),
    ("LAN with a session but a foreign Host is refused", lit "{\"lan\":true,\"session\":true,\"hostOk\":false,\"path\":\"/\"}"),
    ("loopback keeps today's rules: no session needed", lit "{\"lan\":false,\"session\":false,\"hostOk\":false,\"path\":\"/api/board\"}"),
    ("loopback: the console port never serves a preview path", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/o/\"}"),
    ("preview port, no preview cookie: refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/r/\",\"port\":\"preview\"}"),
    ("preview port, preview cookie: served", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/r/\",\"port\":\"preview\"}"),
    ("preview port, LAN, preview cookie, foreign Host: refused", lit "{\"lan\":true,\"session\":true,\"hostOk\":false,\"path\":\"/preview/a/r/\",\"port\":\"preview\"}"),
    ("preview port, LAN, preview cookie, right Host: served", lit "{\"lan\":true,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/r/\",\"port\":\"preview\"}"),
    ("preview port, live grant cookie: a preview path is served", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, live grant cookie, LAN host: a preview path is served", lit "{\"lan\":true,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant cookie, LAN, foreign Host: refused", lit "{\"lan\":true,\"session\":false,\"hostOk\":false,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant cookie 60 minutes old: refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":3601000}"),
    ("preview port, grant cookie just inside 60 minutes: served", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":3600999}"),
    ("preview port, grant cookie unknown to the console: refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":false,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: /api is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/api/tasks\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: /owner is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/owner/logout\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: the login page is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/owner/login\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: a root-absolute script path is no preview path (no Referer reading), refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/_app/immutable/entry/start.js\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: a root-absolute path without a preview Referer is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/_app/immutable/entry/start.js\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, grant: the shell root is refused", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"path\":\"/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":1000,\"now\":2000}"),
    ("preview port, session cookie still serves, reported as the session", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"path\":\"/preview/a/o/\",\"port\":\"preview\",\"grant\":true,\"grantStarted\":0,\"now\":99999999}"),
    ("an unknown port is refused", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"path\":\"/\",\"port\":\"x\"}")]),
  ("console", "console.previewArm", [
    ("task arm, session cookie: its root-absolute module path goes to its backend unchanged", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47100,\"path\":\"/_app/immutable/entry/start.js\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("original arm of the same preview", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47101,\"path\":\"/_app/immutable/entry/start.js\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("second preview, task arm: another backend, never the first preview", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47102,\"path\":\"/selling/x.png?v=1\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("second preview, original arm", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47103,\"path\":\"/\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("a port no arm listens on is refused by route", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47104,\"path\":\"/\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("no cookie and no grant: not allowed", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"port\":47100,\"path\":\"/\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("grant cookie, inside 60 minutes: allowed by grant", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"port\":47100,\"path\":\"/_app/x.js\",\"grant\":true,\"grantStarted\":1000,\"now\":2000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("grant cookie 60 minutes old: not allowed", lit "{\"lan\":false,\"session\":false,\"hostOk\":true,\"port\":47100,\"path\":\"/\",\"grant\":true,\"grantStarted\":1000,\"now\":3601000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("LAN, session cookie, foreign Host: not allowed", lit "{\"lan\":true,\"session\":true,\"hostOk\":false,\"port\":47100,\"path\":\"/\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("LAN, session cookie, right Host: allowed", lit "{\"lan\":true,\"session\":true,\"hostOk\":true,\"port\":47101,\"path\":\"/index.html\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("an api path on an arm origin is just that arm's file path", lit "{\"lan\":false,\"session\":true,\"hostOk\":true,\"port\":47100,\"path\":\"/api/board\",\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}")]),
  ("console", "console.loginReturn", [
    ("an HTML request to a live arm keeps its exact path and query", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the original arm of the preview", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47101,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("an API request stays refused", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":false,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a port no live preview owns is sent to the login without a return", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47999,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the console port is never a return target", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47000,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a protocol-relative path is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"//evil.example/x\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a path that is not a path is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"javascript:alert(1)\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("an encoded CRLF is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/%0d%0aSet-Cookie:x=1\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a backslash is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/\\\\evil.example\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a fragment is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/x#y\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a path over 2000 characters is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a host with userinfo is refused", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"evil@192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a host with a path is refused", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"evil.example/x\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a short nonce is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"abc\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a live preview path on the preview port is kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47001,\"path\":\"/preview/a/compare\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a stopped preview path on the preview port is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47001,\"path\":\"/preview/zz/compare\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the preview port without a preview path is not kept", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47001,\"path\":\"/__grant?t=x\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("the loopback name works", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"127.0.0.1\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a held link that is still live is the destination, on the login host", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}"),
    ("a stopped preview goes to the Builds tab", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}"),
    ("nothing held goes home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("an expired reference goes home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":700000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}"),
    ("a bad host goes home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"evil@192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}"),
    ("a held path outside the allowlist goes home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"//evil.example\",\"issuedAt\":500}}"),
    ("a stopped preview-port link goes to the Builds tab", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[],\"held\":{\"port\":47001,\"path\":\"/preview/a/compare\",\"issuedAt\":500}}"),
    ("a live preview-port link is the destination", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"192.0.2.9\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47001,\"path\":\"/preview/a/compare\",\"issuedAt\":500}}"),
    ("a well-formed foreign host is refused", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"evil.example\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("HEAD is not sent to the login", lit "{\"kind\":\"redirect\",\"method\":\"HEAD\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":0,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a full store logs in plain", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":256,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("one below the cap still keeps the link", lit "{\"kind\":\"redirect\",\"method\":\"GET\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"heldCount\":255,\"html\":true,\"host\":\"192.0.2.9\",\"nonce\":\"n0nceN0nceN0nce12345\",\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}"),
    ("a well-formed foreign host lands home", lit "{\"kind\":\"land\",\"hosts\":[\"127.0.0.1\",\"192.0.2.9\"],\"host\":\"evil.example\",\"now\":1000,\"consolePort\":47000,\"previewPort\":47001,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}],\"held\":{\"port\":47100,\"path\":\"/?preset=v2-proved&fw=morph.mount:shift-dormant,morph.tween:waapi-scoped,pain.notes:visible-idem,hero.countdown:one-chain,hero.exit:scoped\",\"issuedAt\":500}}")]),
  ("console", "console.previewGrant", [
    ("issue from loopback is allowed", lit "{\"kind\":\"issue\",\"lan\":false}"),
    ("issue from a LAN address is refused", lit "{\"kind\":\"issue\",\"lan\":true}"),
    ("redeem: loopback, known, unused, inside ten minutes", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":true,\"used\":false,\"issuedAt\":1000,\"now\":2000}"),
    ("redeem: the last millisecond of the ten minutes", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":true,\"used\":false,\"issuedAt\":1000,\"now\":600999}"),
    ("redeem: ten minutes are over", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":true,\"used\":false,\"issuedAt\":1000,\"now\":601000}"),
    ("redeem: a second use is refused", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":true,\"used\":true,\"issuedAt\":1000,\"now\":2000}"),
    ("redeem: a token this console never issued", lit "{\"kind\":\"redeem\",\"lan\":false,\"known\":false,\"used\":false,\"issuedAt\":0,\"now\":2000}"),
    ("redeem: from a LAN address is refused even with a good token", lit "{\"kind\":\"redeem\",\"lan\":true,\"known\":true,\"used\":false,\"issuedAt\":1000,\"now\":2000}"),
    ("an unknown kind is refused", lit "{\"kind\":\"x\",\"lan\":false}")]),
  ("console", "console.ownerAction", [
    ("owner action: bearer token and the console origin (own Host)", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("owner action from a preview page (the preview origin) is refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47001},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("the preview port is not the console port plus one: its origin is still refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":51234},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":51234}"),
    ("an extra origin on the preview port is dropped from the trusted list", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"localhost\",\"port\":47001},\"host\":{\"host\":\"127.0.0.1\",\"port\":47000},\"extra\":[{\"host\":\"localhost\",\"port\":47001},{\"host\":\"localhost\",\"port\":5173}],\"previewPort\":47001}"),
    ("an extra web origin (the dev server) is trusted", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"localhost\",\"port\":5173},\"host\":{\"host\":\"127.0.0.1\",\"port\":47000},\"extra\":[{\"host\":\"localhost\",\"port\":5173}],\"previewPort\":47001}"),
    ("the preview port unset: nothing is trusted, the owner action is refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[]}"),
    ("owner action without an Origin header is refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("owner action with a null Origin is refused", lit "{\"kind\":\"owner\",\"bearer\":true,\"origin\":null,\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("owner action without the bearer token is refused", lit "{\"kind\":\"owner\",\"bearer\":false,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a command from the console origin", lit "{\"kind\":\"command\",\"bearer\":false,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a command from a preview page is refused", lit "{\"kind\":\"command\",\"bearer\":true,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47001},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a command with no Origin (command-line tool) is accepted", lit "{\"kind\":\"command\",\"bearer\":false,\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a login from the console origin", lit "{\"kind\":\"login\",\"bearer\":false,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47000},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a login from a preview page is refused", lit "{\"kind\":\"login\",\"bearer\":false,\"origin\":{\"host\":\"192.0.2.7\",\"port\":47001},\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("a login without an Origin is refused", lit "{\"kind\":\"login\",\"bearer\":false,\"host\":{\"host\":\"192.0.2.7\",\"port\":47000},\"extra\":[],\"previewPort\":47001}"),
    ("an unknown kind is refused", lit "{\"kind\":\"x\",\"bearer\":true,\"extra\":[]}")]),
  ("console", "console.lanStart", [
    ("not asked for", lit "{\"want\":false,\"hasAddr\":true,\"hasPass\":true,\"passLen\":20}"),
    ("no private address", lit "{\"want\":true,\"hasAddr\":false,\"hasPass\":true,\"passLen\":20}"),
    ("no passphrase in the keychain", lit "{\"want\":true,\"hasAddr\":true,\"hasPass\":false,\"passLen\":0}"),
    ("eleven characters is too short", lit "{\"want\":true,\"hasAddr\":true,\"hasPass\":true,\"passLen\":11}"),
    ("twelve characters starts", lit "{\"want\":true,\"hasAddr\":true,\"hasPass\":true,\"passLen\":12}")]),
  ("console", "console.daemon", [
    ("start with nothing recorded is allowed", lit "{\"kind\":\"start\"}"),
    ("start with a recorded pid that does not answer is allowed (stale file)", lit "{\"kind\":\"start\",\"recorded\":4242}"),
    ("start while the recorded pid answers is refused", lit "{\"kind\":\"start\",\"recorded\":4242,\"answered\":4242}"),
    ("start when another pid answers on the recorded port is allowed", lit "{\"kind\":\"start\",\"recorded\":4242,\"answered\":9999}"),
    ("pid 1 is never a console", lit "{\"kind\":\"start\",\"recorded\":1,\"answered\":1}"),
    ("start is refused when the recorded pid is alive but did not answer", lit "{\"kind\":\"start\",\"recorded\":4242,\"alive\":true}"),
    ("a recorded pid that is not alive does not block start", lit "{\"kind\":\"start\",\"recorded\":4242,\"alive\":false}"),
    ("pid 1 alive and silent blocks nothing", lit "{\"kind\":\"start\",\"recorded\":1,\"alive\":true}"),
    ("a different pid answered while the recorded one is alive: allowed", lit "{\"kind\":\"start\",\"recorded\":4242,\"answered\":9999,\"alive\":true}"),
    ("stop signals the verified pid", lit "{\"kind\":\"stop\",\"recorded\":4242,\"answered\":4242}"),
    ("stop signals nothing when nothing answers", lit "{\"kind\":\"stop\",\"recorded\":4242,\"answered\":null}"),
    ("stop signals nothing on a pid mismatch", lit "{\"kind\":\"stop\",\"recorded\":4242,\"answered\":9999}"),
    ("stop signals nothing when nothing is recorded", lit "{\"kind\":\"stop\",\"answered\":4242}"),
    ("restart of a verified console stops then starts", lit "{\"kind\":\"restart\",\"recorded\":4242,\"answered\":4242}"),
    ("restart with no verified console only starts", lit "{\"kind\":\"restart\",\"recorded\":4242}"),
    ("a log below the default limit is kept", lit "{\"kind\":\"rotate\",\"size\":5242879}"),
    ("a log at the default limit is rotated", lit "{\"kind\":\"rotate\",\"size\":5242880}"),
    ("a log of exactly 50 MiB draws no warning", lit "{\"kind\":\"rotate\",\"size\":52428800}"),
    ("a log above 50 MiB draws the warning", lit "{\"kind\":\"rotate\",\"size\":52428801}"),
    ("a custom limit", lit "{\"kind\":\"rotate\",\"size\":100,\"limit\":100}"),
    ("an unknown kind is refused", lit "{\"kind\":\"x\"}")]),
  ("console", "console.previewSweep", [
    ("nothing live", lit "{\"now\":10,\"live\":[]}"),
    ("a fresh and a busy preview stay", lit "{\"now\":1000000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0,\"seen\":500000},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":900000}]}"),
    ("15 minutes without a request stops it (idle)", lit "{\"now\":1400000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0,\"seen\":500000}]}"),
    ("14 min 59.999 s without a request stays", lit "{\"now\":1399999,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0,\"seen\":500000}]}"),
    ("the TTL stops a preview that is in use", lit "{\"now\":3600000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0,\"seen\":3599000}]}"),
    ("a preview never used since it started is idle after 15 minutes", lit "{\"now\":900000,\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0}]}")]),
  ("console", "console.actor", [
    ("all sources", lit "{}"),
    ("the alert source writes as script", lit "{\"source\":\"alert\"}"),
    ("unknown source is refused", lit "{\"source\":\"lead\"}")])]

open Fw.Ops.LeanFirst in
/-- An `ops.leanFirst` request: the encoded facts. -/
def leanFirstReq (F : Facts) : Json := lfFactsJson F

/-- A JSON object with one more field (other JSON unchanged). -/
def withField (k : String) (v : Json) : Json → Json
  | .obj kvs => .obj (kvs.insert k v)
  | j => j

open Fw.Ops.LeanFirst in
/-- The constructor name of a fault of the lean-first grid. -/
def faultName (f : Fault) : String := ((reprStr f).splitOn ".").getLastD ""

open Fw.Ops.LeanFirst in
/-- The `ops.leanFirst` cases, all judged at the deployed constant `stage` (a request cannot choose it): the base
facts (all rules met), each single fault of the grid, the binding, decision-path and read-at-main cases, a request
`stage` field (ignored), and the decoder edge cases. -/
def leanFirstCases (_ : Unit := ()) : List (String × Json) :=
  let at_ := s!"at the deployed stage {stage.name}"
  [(s!"all rules met {at_}", leanFirstReq base)] ++
  Fault.all.map (fun f => (s!"fault {faultName f} {at_}", leanFirstReq (factsOf [f]))) ++
  [(s!"two reason faults (stub implementation, no kill): both reasons, the verdict names the first {at_}",
     leanFirstReq (factsOf [.stub, .noKill])),
   (s!"stub: the property's own implementation is unreached though a lemma of the land is reached {at_}",
     leanFirstReq (factsOf [.stub])),
   (s!"directory glob apps/runner/** over decision code with no property: no-props {at_}",
     leanFirstReq (factsOf [.dirGlob])),
   (s!"globs only under docs/ and research/ with no property: not decision code {at_}",
     leanFirstReq (factsOf [.docsGlob])),
   (s!"a candidate theorem without reachFromWire: missing reach {at_}", leanFirstReq (factsOf [.reachUnknown])),
   (s!"exempt.tsv and killOf read at branch commit b, not main m: missing exempt-main {at_}",
     leanFirstReq (factsOf [.exemptBranch])),
   (s!"exempt.tsv and killOf never read (no exemptAt): missing exempt-main {at_}",
     withField "exemptAt" .null (leanFirstReq base)),
   (s!"request stage field ratchet is ignored: same reply as all rules met {at_}",
     withField "stage" (.str "ratchet") (leanFirstReq base)),
   (s!"request stage field ratchet is ignored on a stub {at_}",
     withField "stage" (.str "ratchet") (leanFirstReq (factsOf [.stub]))),
   (s!"unknown stage name is ignored, not refused {at_}", lit "{\"stage\":\"strict\"}"),
   (s!"untested premise shared with the property: WARN line {at_}", leanFirstReq (factsOf [.untestedShared])),
   (s!"a line break in a theorem name is printed as a space {at_}", leanFirstReq (factsOf [.newlineName, .noKill])),
   (s!"empty request: every source missing {at_}", lit "{}"),
   ("unknown sign-off role is refused",
     lit "{\"signoffs\":[{\"decl\":\"P\",\"stmtHash\":\"h\",\"role\":\"lead\",\"agree\":true}]}"),
   ("registry row without a status is refused", lit "{\"registry\":[{\"id\":\"p\"}]}")]

/-- Golden files whose name is not their op: (directory under `packages/contracts/golden`, file stem, op, cases). -/
def named (_ : Unit := ()) : List (String × String × String × List (String × Json)) := [
  ("ops", "lean-first", "ops.leanFirst", leanFirstCases)]

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
  for (sub, stem, op, cs) in cases.map (fun (op, cs) => ("ops", op, op, cs)) ++
      extra.map (fun (sub, op, cs) => (sub, op, op, cs)) ++ named do
    let p := root / ".." / "packages" / "contracts" / "golden" / sub / s!"{stem}.jsonl"
    if write then IO.FS.createDirAll (root / ".." / "packages" / "contracts" / "golden" / sub)
    let text := fileText op cs
    if write then
      IO.FS.writeFile p text
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != text then
        IO.println s!"ops golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/OpsGolden.lean)"
        stale := stale + 1
  let n := cases.foldl (fun a c => a + c.2.length) 0 + extra.foldl (fun a c => a + c.2.2.length) 0 +
    named.foldl (fun a c => a + c.2.2.2.length) 0
  IO.println s!"ops golden: {cases.length + extra.length + named.length} files, {n} cases, {if write then "written" else s!"{stale} stale"}"
  return stale

end Fw.Wire.Ops.Golden
