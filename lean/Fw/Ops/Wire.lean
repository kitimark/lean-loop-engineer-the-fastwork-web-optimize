import Lean.Data.Json
import Fw.Ops.SpawnGuard
import Fw.Ops.PathCheck
import Fw.Ops.Usage
import Fw.Ops.Meter
import Fw.Ops.Identity
import Fw.Ops.Obs
import Fw.Ops.Wait
/-!
# JSON codecs and ops of `Fw.Ops` (`ops.*`)

Glue between `fwcore`'s JSON lines and `Fw.Ops` (namespace `Fw.Wire.Ops`, so the math view treats
it as wire code). Total decoders only (`Except String`); no partial operations. Counts and times
are non-negative integers (seconds, tokens, ms); a non-integer number is refused.

| op | request | reply |
|---|---|---|
| `ops.spawn` | `alive` [{name, role, kind}], `roles` [{name, runsAs, edits}], `caps`?, `recent`? [{spawner, at}], `now`, `req` {name?, role, isolation?, model?, spawner?, depth?} | `decision` (`allow`/`needsApproval`/`deny`), `reason` (null or a reason), `want`/`got` (kindMismatch), `role` (capRole), `kind`, `wantKind` (the role's `runsAs`, or null for an unknown role) |
| `ops.pathCheck` | `scope` (globs, `!` excludes), `paths` | `ok`, `violations` |
| `ops.usage` | `table`? [{id, input, cacheRead, cacheCreate, cache5m, cache1h, output}], `records`? (same shape), `lines`? (transcript JSON objects) | `table` (sorted by id), `totals`, `skipped` |
| `ops.meter` | `params`?, `state`? {window, fired [{agent, rule}]}, `now`, `agents` [{agent, ctx, idleSec, ttlSec? or w5m?/w1h?, wakeGapSec?}] | `state`, `alerts` [{agent, rule, window}], `verdicts` [{agent, verdict, ttlSec}] |
| `ops.hook` | `payloads` (raw hook stdin objects) | `hooks` [{sessionId, event, agentId, agentType, who, toolName, toolUseId, durationMs, error, isInterrupt, promptId, teammateName}], `errors` [{index, error}] |
| `ops.obs` | `records`? [{agent_id?, hook_event_name, tool_use_id?, ts}], `lines`? [{hook_event_name, agent_type?, tool_name?, is_error?, duration_ms?}] (extra fields ignored) | `keys` (one obs key per record, in order), `summary` [{agent_type, tool_name, calls, errors, total_ms}] (first-seen group order) |
| `ops.cap` | `agent_id`?, `agent_type`? (as `ops.actor`), `tokens` (the first simple command of a Bash input, split like a shell) | `decision` (`mint`/`noMint`), `actor`, `argv` (when minted), `reason` (`notFwPrefix`/`trailingPipe`/`unknownActor`, when not) |
| `ops.door` | `actor`, `secret`? (bool) | `accept` (the door without capability takes this actor), `agentActor` |
| `ops.wait` | `cmd` (the Bash command text), `caps`? {maxSleepSec?} | `decision` (`allow`/`deny`), `reason` (null, `bgLong` or `unboundedLoop`), `shape` (`bgLong`: `fwWatch`/`loop`/`server`/`tail`/`longSleep`, else null) |
| `ops.actor` | `agent_id`?, `agent_type`? (string or null, as in a hook payload or a `caps.jsonl` record) | `who` (`lead`/`agent`/`unknown`), `role` (the agent type, or null), `actor` (`lead`/`reviewer`/`owner`, or null: mint no capability) |

`kind` / `runsAs`: `teammate`, `subagent`, `worktree`. `isolation`: `"worktree"`, `true`, `false`
or `null`. Rules: `ctxBig`, `idleExpiring`, `coldWake`. Verdicts: `resumeOk`, `resumeCheap`,
`respawn`.
-/
namespace Fw.Wire.Ops
open Lean

/-- The fields of a reply. -/
abbrev Reply := List (String × Json)

/-- A required field. -/
def field (j : Json) (k : String) : Except String Json :=
  match j.getObjVal? k with
  | .ok v => .ok v
  | .error _ => .error s!"missing field {k}"

/-- An optional field (`null` counts as absent). -/
def opt (j : Json) (k : String) : Option Json :=
  match j.getObjVal? k with
  | .ok .null => none
  | .ok v => some v
  | .error _ => none

/-- A JSON value as a string. -/
def asStr (k : String) : Json → Except String String
  | .str s => .ok s
  | _ => .error s!"field {k}: expected a string"

/-- A JSON value as a natural number. -/
def asNat (k : String) (j : Json) : Except String Nat :=
  match j.getNat? with
  | .ok n => .ok n
  | .error _ => .error s!"field {k}: expected a non-negative integer"

/-- A JSON value as a Boolean. -/
def asBool (k : String) : Json → Except String Bool
  | .bool b => .ok b
  | _ => .error s!"field {k}: expected a boolean"

/-- A JSON value as an array. -/
def asArr (k : String) : Json → Except String (Array Json)
  | .arr a => .ok a
  | _ => .error s!"field {k}: expected an array"

/-- A required string field. -/
def str (j : Json) (k : String) : Except String String := do asStr k (← field j k)

/-- A required natural field. -/
def nat (j : Json) (k : String) : Except String Nat := do asNat k (← field j k)

/-- A required array field. -/
def arr (j : Json) (k : String) : Except String (Array Json) := do asArr k (← field j k)

/-- An optional string field with a default. -/
def strD (j : Json) (k : String) (d : String) : Except String String :=
  match opt j k with
  | none => .ok d
  | some v => asStr k v

/-- An optional natural field with a default. -/
def natD (j : Json) (k : String) (d : Nat) : Except String Nat :=
  match opt j k with
  | none => .ok d
  | some v => asNat k v

/-- An optional Boolean field with a default. -/
def boolD (j : Json) (k : String) (d : Bool) : Except String Bool :=
  match opt j k with
  | none => .ok d
  | some v => asBool k v

/-- An optional array field (absent is empty). -/
def arrD (j : Json) (k : String) : Except String (List Json) :=
  match opt j k with
  | none => .ok []
  | some v => do pure (← asArr k v).toList

/-- An optional string as a string or `null`. -/
def ostr : Option String → Json
  | some s => .str s
  | none => .null

/-! ## ops.spawn -/

open Fw.Ops.SpawnGuard in
/-- Kind wire names. -/
def kindName : Kind → String
  | .teammate => "teammate" | .subagent => "subagent" | .worktree => "worktree"

open Fw.Ops.SpawnGuard in
/-- Kind from its wire name. -/
def kindOf (k : String) : String → Except String Kind
  | "teammate" => .ok .teammate | "subagent" => .ok .subagent | "worktree" => .ok .worktree
  | s => .error s!"field {k}: unknown kind {s}"

/-- The isolation field of an `Agent` call: `"worktree"` or `true` is worktree isolation;
absent, `null` or `false` is none. -/
def isolationOf (j : Json) : Except String Bool :=
  match opt j "isolation" with
  | none => .ok false
  | some (.str "worktree") => .ok true
  | some (.bool b) => .ok b
  | some _ => .error "field isolation: expected \"worktree\", a boolean or null"

open Fw.Ops.SpawnGuard in
/-- Decode the caps; every field is optional and defaults to PLAN §8.2. -/
def capsOf (j : Json) : Except String Caps := do
  let d : Caps := {}
  let perRole ← match opt j "perRole" with
    | none => pure d.perRole
    | some (.obj kvs) => kvs.toArray.toList.mapM fun ⟨r, v⟩ => do pure (r, ← asNat s!"perRole.{r}" v)
    | some _ => throw "field perRole: expected an object"
  let ask ← match opt j "askModels" with
    | none => pure d.askModels
    | some v => do (← asArr "askModels" v).toList.mapM (asStr "askModels")
  pure { teammates := ← natD j "teammates" d.teammates, worktrees := ← natD j "worktrees" d.worktrees,
         subagents := ← natD j "subagents" d.subagents, perRole,
         spawnsPerWindow := ← natD j "spawnsPerWindow" d.spawnsPerWindow,
         windowSec := ← natD j "windowSec" d.windowSec, askModels := ask,
         unnamedReadOnly := ← boolD j "unnamedReadOnly" d.unnamedReadOnly }

open Fw.Ops.SpawnGuard in
/-- Reason wire fields. -/
def reasonFields : Reason → Reply
  | .unnamed => [("reason", .str "unnamed")]
  | .nameInUse => [("reason", .str "nameInUse")]
  | .unknownRole => [("reason", .str "unknownRole")]
  | .kindMismatch w g => [("reason", .str "kindMismatch"), ("want", .str (kindName w)), ("got", .str (kindName g))]
  | .nestedEditor => [("reason", .str "nestedEditor")]
  | .rateLimited => [("reason", .str "rateLimited")]
  | .capTeammates => [("reason", .str "capTeammates")]
  | .capWorktrees => [("reason", .str "capWorktrees")]
  | .capSubagents => [("reason", .str "capSubagents")]
  | .capRole r => [("reason", .str "capRole"), ("role", .str r)]

open Fw.Ops.SpawnGuard in
/-- `ops.spawn`: the spawn guard's decision for one `Agent` call. -/
def opSpawn (req : Json) : Except String Reply := do
  let alive ← (← arr req "alive").toList.mapM fun a => do
    pure ({ name := ← str a "name", role := ← str a "role", kind := ← kindOf "alive.kind" (← str a "kind"),
            spawner := ← strD a "spawner" "" } : Agent)
  let roles ← (← arr req "roles").toList.mapM fun r => do
    pure ({ name := ← str r "name", runsAs := ← kindOf "roles.runsAs" (← str r "runsAs"),
            edits := ← boolD r "edits" false } : Role)
  let caps ← match opt req "caps" with
    | none => pure {}
    | some c => capsOf c
  let recent ← (← arrD req "recent").mapM fun r => do pure (← str r "spawner", ← nat r "at")
  let q ← field req "req"
  let rq : Req := { name := ← strD q "name" "", role := ← str q "role", isolation := ← isolationOf q,
                    model := ← strD q "model" "", spawner := ← strD q "spawner" "lead", depth := ← natD q "depth" 0 }
  let i : Input := ⟨alive, roles, caps, recent, ← nat req "now", rq⟩
  let kind := [("kind", Json.str (kindName (effKind rq))), ("wantKind", ostr ((wantKind i).map kindName))]
  pure <| match decide i with
    | .allow => [("decision", .str "allow"), ("reason", .null)] ++ kind
    | .needsApproval => [("decision", .str "needsApproval"), ("reason", .null)] ++ kind
    | .deny r => [("decision", .str "deny")] ++ reasonFields r ++ kind

/-! ## ops.pathCheck -/

/-- `ops.pathCheck`: the changed paths outside the write scope. -/
def opPathCheck (req : Json) : Except String Reply := do
  let scope ← (← arr req "scope").toList.mapM (asStr "scope")
  let paths ← (← arr req "paths").toList.mapM (asStr "paths")
  let v := Fw.Ops.PathCheck.violations scope paths
  pure [("ok", .bool v.isEmpty), ("violations", toJson v)]

/-! ## ops.usage -/

open Fw.Ops.Usage in
/-- A usage record as JSON. -/
def usageJson (u : Usage) : List (String × Json) :=
  [("input", toJson u.input), ("cacheRead", toJson u.cacheRead), ("cacheCreate", toJson u.cacheCreate),
   ("cache5m", toJson u.cache5m), ("cache1h", toJson u.cache1h), ("output", toJson u.output)]

open Fw.Ops.Usage in
/-- A record `{id, input?, cacheRead?, cacheCreate?, cache5m?, cache1h?, output?}` (missing = 0). -/
def recordOf (j : Json) : Except String (String × Usage) := do
  let u : Usage := {
    input := ← natD j "input" 0, cacheRead := ← natD j "cacheRead" 0,
    cacheCreate := ← natD j "cacheCreate" 0, cache5m := ← natD j "cache5m" 0,
    cache1h := ← natD j "cache1h" 0, output := ← natD j "output" 0 }
  pure (← str j "id", u)

open Fw.Ops.Usage in
/-- A transcript line: `message.id` and `message.usage` (Anthropic field names); `none` when the
line carries no usage. Missing counts are 0 (partial lines). -/
def lineOf (j : Json) : Except String (Option (String × Usage)) := do
  let some m := opt j "message" | pure none
  let some (.str id) := opt m "id" | pure none
  let some u := opt m "usage" | pure none
  let cc := (opt u "cache_creation").getD (Json.mkObj [])
  let r : Usage := {
    input := ← natD u "input_tokens" 0, cacheRead := ← natD u "cache_read_input_tokens" 0,
    cacheCreate := ← natD u "cache_creation_input_tokens" 0,
    cache5m := ← natD cc "ephemeral_5m_input_tokens" 0, cache1h := ← natD cc "ephemeral_1h_input_tokens" 0,
    output := ← natD u "output_tokens" 0 }
  pure (some (id, r))

open Fw.Ops.Usage in
/-- `ops.usage`: join the table, records and transcript lines by `message.id` (order-free). -/
def opUsage (req : Json) : Except String Reply := do
  let table ← (← arrD req "table").mapM recordOf
  let records ← (← arrD req "records").mapM recordOf
  let lines ← (← arrD req "lines").mapM lineOf
  let fromLines := lines.filterMap id
  let t := ingest (table ++ records ++ fromLines)
  pure [("table", .arr (t.toArray.map fun (k, u) => Json.mkObj (("id", .str k) :: usageJson u))),
        ("totals", Json.mkObj (usageJson (total t))), ("skipped", toJson (lines.length - fromLines.length))]

/-! ## ops.meter -/

open Fw.Ops.Meter in
/-- Rule wire names. -/
def ruleName : Rule → String
  | .ctxBig => "ctxBig" | .idleExpiring => "idleExpiring" | .coldWake => "coldWake"

open Fw.Ops.Meter in
/-- Rule from its wire name. -/
def ruleOf : String → Except String Rule
  | "ctxBig" => .ok .ctxBig | "idleExpiring" => .ok .idleExpiring | "coldWake" => .ok .coldWake
  | s => .error s!"unknown rule {s}"

open Fw.Ops.Meter in
/-- Verdict wire names. -/
def verdictName : Verdict → String
  | .resumeOk => "resumeOk" | .resumeCheap => "resumeCheap" | .respawn => "respawn"

open Fw.Ops.Meter in
/-- `ops.meter`: one meter tick: alerts (deduped per window), the next state and the verdicts. -/
def opMeter (req : Json) : Except String Reply := do
  let d : Params := {}
  let pj := (opt req "params").getD (Json.mkObj [])
  let p : Params := { ctxMax := ← natD pj "ctxMax" d.ctxMax, leadSec := ← natD pj "leadSec" d.leadSec,
                      windowSec := ← natD pj "windowSec" d.windowSec, respawnCtx := ← natD pj "respawnCtx" d.respawnCtx }
  let sj := (opt req "state").getD (Json.mkObj [])
  let fired ← (← arrD sj "fired").mapM fun f => do pure (← str f "agent", ← ruleOf (← str f "rule"))
  let s : State := ⟨← natD sj "window" 0, fired⟩
  let obs ← (← arr req "agents").toList.mapM fun a => do
    let ttl ← match opt a "ttlSec" with
      | some v => asNat "ttlSec" v
      | none => pure (ttlOf (← natD a "w5m" 0) (← natD a "w1h" 0))
    pure ({ agent := ← str a "agent", ctx := ← nat a "ctx", idleSec := ← nat a "idleSec", ttlSec := ttl,
            wakeGapSec := ← natD a "wakeGapSec" 0 } : Obs)
  let (s', alerts) := step p s (← nat req "now") obs
  pure [("state", Json.mkObj [("window", toJson s'.window),
          ("fired", .arr (s'.fired.toArray.map fun (a, r) => Json.mkObj [("agent", .str a), ("rule", .str (ruleName r))]))]),
        ("alerts", .arr (alerts.toArray.map fun (a, r, w) =>
          Json.mkObj [("agent", .str a), ("rule", .str (ruleName r)), ("window", toJson w)])),
        ("verdicts", .arr (obs.toArray.map fun o =>
          Json.mkObj [("agent", .str o.agent), ("verdict", .str (verdictName (verdict p o))), ("ttlSec", toJson o.ttlSec)]))]

/-! ## ops.hook -/

/-- A decoded hook payload: the fields the observer keeps (tool input and response are dropped). -/
structure Hook where
  sessionId    : String
  event        : String
  agentId      : Option String
  agentType    : Option String
  toolName     : Option String
  toolUseId    : Option String
  durationMs   : Option Nat
  error        : Option String
  isInterrupt  : Option Bool
  promptId     : Option String
  teammateName : Option String

/-- An optional string field of a payload. -/
def optS (j : Json) (k : String) : Except String (Option String) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asStr k v

/-- Decode one hook stdin payload (`session_id` and `hook_event_name` required). -/
def hookOf (j : Json) : Except String Hook := do
  match j with
  | .obj _ => pure ()
  | _ => throw "payload must be a JSON object"
  pure { sessionId := ← str j "session_id", event := ← str j "hook_event_name",
         agentId := ← optS j "agent_id", agentType := ← optS j "agent_type",
         toolName := ← optS j "tool_name", toolUseId := ← optS j "tool_use_id",
         durationMs := ← (match opt j "duration_ms" with
           | none => pure none
           | some v => some <$> asNat "duration_ms" v),
         error := ← optS j "error",
         isInterrupt := ← (match opt j "is_interrupt" with
           | none => pure none
           | some v => some <$> asBool "is_interrupt" v),
         promptId := ← optS j "prompt_id", teammateName := ← optS j "teammate_name" }

open Fw.Ops.Identity in
/-- Wire name of an identity kind. -/
def whoName : Who → String
  | .lead => "lead" | .agent _ => "agent" | .unknown => "unknown"

/-- A decoded hook as JSON (absent fields are `null`; `who` is `Fw.Ops.Identity.who`). -/
def hookJson (h : Hook) : Json := Json.mkObj [
  ("sessionId", .str h.sessionId), ("event", .str h.event), ("agentId", ostr h.agentId),
  ("agentType", ostr h.agentType), ("who", .str (whoName (Fw.Ops.Identity.who h.agentId h.agentType))),
  ("toolName", ostr h.toolName), ("toolUseId", ostr h.toolUseId),
  ("durationMs", match h.durationMs with | some n => toJson n | none => .null), ("error", ostr h.error),
  ("isInterrupt", match h.isInterrupt with | some b => .bool b | none => .null),
  ("promptId", ostr h.promptId), ("teammateName", ostr h.teammateName)]

/-- `ops.hook`: decode a batch of spooled hook payloads; a bad payload is reported by index and
does not stop the batch. -/
def opHook (req : Json) : Except String Reply := do
  let ps ← arr req "payloads"
  let rs := (List.range ps.size).zip (ps.toList.map hookOf)
  let ok := rs.filterMap fun (_, r) => match r with | .ok h => some (hookJson h) | .error _ => none
  let bad := rs.filterMap fun (i, r) => match r with
    | .ok _ => none
    | .error e => some (Json.mkObj [("index", toJson i), ("error", .str e)])
  pure [("hooks", .arr ok.toArray), ("errors", .arr bad.toArray)]

/-! ## ops.actor -/

open Fw.Ops.Identity in
/-- `ops.actor`: the identity and capability actor of one record's `agent_id` / `agent_type`
(`Fw.Ops.Identity.who`, `capActor`); a non-string field is refused. -/
def opActor (req : Json) : Except String Reply := do
  let i ← optS req "agent_id"
  let t ← optS req "agent_type"
  let w := who i t
  pure [("who", .str (whoName w)),
        ("role", match w with | .agent r => .str r | _ => .null),
        ("actor", match actorOf w with | some a => .str a.name | none => .null)]

/-! ## ops.cap, ops.door -/

open Fw.Ops.Identity Fw.Console in
/-- `ops.cap`: the capability decision (`Fw.Ops.Identity.capDecide`) for a record's identity and the tokens of the
first simple command of its Bash input: `mint` with the actor and the argv, or `noMint` with its one reason. -/
def opCap (req : Json) : Except String Reply := do
  let i ← optS req "agent_id"
  let t ← optS req "agent_type"
  let toks ← (← arrD req "tokens").mapM (asStr "tokens")
  pure (match capDecide i t toks with
    | .mint a argv => [("decision", .str "mint"), ("actor", .str a.name),
        ("argv", .arr (argv.toArray.map .str)), ("reason", .null)]
    | .noMint r => [("decision", .str "noMint"), ("actor", .null), ("argv", .null), ("reason", .str r.name)])

open Fw.Ops.Identity Fw.Console in
/-- `ops.door`: whether the door without capability accepts a body that claims `actor`
(`Fw.Ops.Identity.openDoor`; `secret`: the caller showed the console secret, default false). -/
def opDoor (req : Json) : Except String Reply := do
  let a ← str req "actor"
  let secret ← boolD req "secret" false
  let actor ← match a with
    | "user" => pure Actor.user | "lead" => pure Actor.lead | "owner" => pure Actor.owner
    | "reviewer" => pure Actor.reviewer | "script" => pure Actor.script | "git" => pure Actor.git
    | "hook" => pure Actor.hook | other => throw s!"field actor: unknown actor {other}"
  pure [("accept", .bool (openDoor actor secret)), ("agentActor", .bool (isAgentActor actor))]

/-! ## ops.obs -/

/-- An optional nullable natural-number field. -/
def optN (j : Json) (k : String) : Except String (Option Nat) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asNat k v

/-- An optional nullable boolean field. -/
def optB (j : Json) (k : String) : Except String (Option Bool) :=
  match opt j k with
  | none => .ok none
  | some v => some <$> asBool k v

open Fw.Ops.Obs in
/-- A summary row as JSON (snake_case, the contracts `ObsSummaryRow`). -/
def rowJson (r : Row) : Json := Json.mkObj [
  ("agent_type", .str r.agentType), ("tool_name", .str r.toolName), ("calls", toJson r.calls),
  ("errors", toJson r.errors), ("total_ms", toJson r.totalMs)]

open Fw.Ops.Obs in
/-- `ops.obs`: the obs key of each spool record (`Fw.Ops.Obs.obsKey`) and the per (agent type,
tool) summary of obs lines (`Fw.Ops.Obs.summarize`). -/
def opObs (req : Json) : Except String Reply := do
  let keys ← (← arrD req "records").mapM fun r => do
    pure (obsKey (← optS r "agent_id") (← str r "hook_event_name") (← optS r "tool_use_id") (← nat r "ts"))
  let lines ← (← arrD req "lines").mapM fun l => do
    pure ({ event := ← str l "hook_event_name", agentType := ← optS l "agent_type",
            toolName := ← optS l "tool_name", isError := ← optB l "is_error",
            durationMs := ← optN l "duration_ms" } : Line)
  pure [("keys", .arr (keys.toArray.map .str)), ("summary", .arr ((summarize lines).toArray.map rowJson))]

/-! ## Dispatch -/

/-! ## ops.wait -/

open Fw.Ops.Wait in
/-- Shape wire names. -/
def shapeName : Shape → String
  | .fwWatch => "fwWatch" | .loop => "loop" | .server => "server" | .tail => "tail" | .longSleep => "longSleep"

open Fw.Ops.Wait in
/-- `ops.wait`: the wait guard's decision for one `Bash` command (a long-running process started with `&`, or an
unbounded `until`/`while` loop, is refused). -/
def opWait (req : Json) : Except String Reply := do
  let cmd ← str req "cmd"
  let caps : Caps ← match opt req "caps" with
    | none => pure {}
    | some c => do pure { maxSleepSec := ← natD c "maxSleepSec" (({} : Caps).maxSleepSec) }
  pure <| match decideCmd caps cmd with
    | .allow => [("decision", .str "allow"), ("reason", .null), ("shape", .null)]
    | .deny (.bgLong s) => [("decision", .str "deny"), ("reason", .str "bgLong"), ("shape", .str (shapeName s))]
    | .deny .unboundedLoop => [("decision", .str "deny"), ("reason", .str "unboundedLoop"), ("shape", .null)]

/-- The `ops.*` ops. -/
def ops : List String := ["ops.spawn", "ops.pathCheck", "ops.usage", "ops.meter", "ops.hook", "ops.actor", "ops.cap", "ops.door", "ops.obs", "ops.wait"]

/-- Dispatch an `ops.*` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "ops.spawn" => some (opSpawn req)
  | "ops.pathCheck" => some (opPathCheck req)
  | "ops.usage" => some (opUsage req)
  | "ops.meter" => some (opMeter req)
  | "ops.hook" => some (opHook req)
  | "ops.actor" => some (opActor req)
  | "ops.cap" => some (opCap req)
  | "ops.door" => some (opDoor req)
  | "ops.obs" => some (opObs req)
  | "ops.wait" => some (opWait req)
  | _ => none

end Fw.Wire.Ops
