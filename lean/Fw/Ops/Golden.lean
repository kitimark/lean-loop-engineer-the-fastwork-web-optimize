import Fw.Wire
import Fw.Console.PreviewTable
/-!
# Golden vectors of the `ops.*` ops

`packages/contracts/golden/ops/<op>.jsonl`: one line per case, `{"name", "request", "response"}`,
where `request` carries its `op` and `response` is what `fwcore` replies (without the `id`).
The same format, from `extra`: `golden/plan/plan.trailers.jsonl` (reconciler `git.ts`) and
`golden/console/console.{landReadiness,actor}.jsonl` (console-api's own actors), `golden/lint/lint.context.jsonl`
(`scripts/context-lint.mjs`).
Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/OpsGolden.lean           # write the files
cd lean && lake env lean --run scripts/OpsGolden.lean --check   # fail if a file is stale
```

`lake test` runs the same check. Consumers: the hooks agent (`emit.mjs`, `spawn-guard.mjs`:
`ops.hook`, `ops.spawn`; `cap.mjs`: `ops.actor`, `ops.cap`), console-api's capability door (`cap.ts`
`actorFor`: `ops.actor`; `openDoor`: `ops.door`), the land agent (`fw land`: `ops.pathCheck`) and console-api's usage
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

/-- An `ops.wait` request for one Bash command, with optional `caps` (a JSON text). -/
def wait' (cmd : String) (caps : String) : Json :=
  Json.mkObj [("cmd", .str cmd), ("caps", lit caps)]

/-- An `ops.wait` request for one Bash command. -/
def wait (cmd : String) : Json := Json.mkObj [("cmd", .str cmd)]

/-- The cases, per op file: (file stem, [(name, request without op)]). -/
def cases : List (String × List (String × Json)) := [
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
    ("fractional duration is refused", lit "{\"lines\":[{\"hook_event_name\":\"PostToolUse\",\"duration_ms\":1.5}]}")]),
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
    ("until loop with a clock deadline: allow", wait "end=$((SECONDS+60)); until [ $SECONDS -ge $end ]; do sleep 2; done"),
    ("until loop wrapped in timeout: allow", wait "timeout 60 until grep -q x f; do sleep 1; done"),
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
    ("missing cmd is refused", lit "{}")])]

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
  ("CLAUDE.md: over 5000 bytes is over budget even with slop; at 5000 a dated note is slop",
    lintFiles [lintFile "CLAUDE.md" 5001 ["Rule (user decision 2026-10-17)."],
      lintFile "CLAUDE.md" 5000 ["Rule (user decision 2026-10-17)."]]),
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
def extra : List (String × String × List (String × Json)) := [
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
    ("missing main is refused", lit "{\"facts\":[]}")] ++ Fw.Console.PreviewTable.goldenCases),
  ("console", "console.previewAdmit", [
    ("the user starts the first preview: the two lowest ports", lit "{\"preview\":\"n\",\"task\":\"port-hero\",\"now\":5000,\"diskMb\":9000,\"hasTarget\":true,\"secret\":false,\"cookie\":true,\"origin\":true,\"live\":[]}"),
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
  ("console", "console.previewReap", [
    ("everything recorded is killed", lit "{\"live\":[{\"id\":\"a\",\"task\":\"port-nav\",\"rp\":47100,\"op\":47101,\"started\":0},{\"id\":\"b\",\"task\":\"fix-nav\",\"rp\":47102,\"op\":47103,\"started\":1000}]}"),
    ("empty table", lit "{\"live\":[]}")]),
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
