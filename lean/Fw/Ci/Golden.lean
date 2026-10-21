import Fw.Wire
import Fw.Ops.Golden
import Fw.Ci.Lag
/-!
# Golden vectors and replay fixtures of the GitHub request budget (`ci.budget.*`)

Files under `packages/contracts/golden/ci-budget/`, generated from Lean, never by hand:
- `limits.json`: the limits `Fw.Ci.Budget.defaults` with both shares per window (TS reads them here or through
  `ci.budget.limits` and never restates them);
- `wire.jsonl`: one line per case, `{"name", "request", "response"}` (`request` carries its `op`; `response` is what
  `fwcore` replies, without the `id`);
- `lag.jsonl`: the partition of a wait's lag (`Fw.Ci.Lag.parts`), one line per case `{name, marks, prev?, parts, gap?, stale?}`;
- `lag-kind.jsonl`: the kind of a wait (`Fw.Ci.Lag.kind`, lines `{name, op:"kind", lanesMissing, tick?, reg, kind}`) and its critical run
  (`Fw.Ci.Lag.crit`, lines `{name, op:"crit", upds, crit?}`);
- `fixtures/<name>.jsonl`: synthesized header traces for the replay test `FwTest.CiBudget` (format there). A recorded
  trace (`fixtures/recorded-*.jsonl`, same format) is replayed the same way once one exists.

`lake test` checks every file; `lake test -- --write-ci-budget-golden` rewrites them first.
-/
namespace Fw.Wire.Ci.Golden
open Lean
open Fw.Wire.Ops.Golden (lit withOp respond)

/-- The start of every fixture: 2026-10-18 00:00 UTC, in seconds since the epoch. -/
def t0 : Nat := 1792281600

/-- `n` charged one-off entries at time `t`, as a JSON ledger. -/
def oneoffs (n t : Nat) : String :=
  "[" ++ ",".intercalate ((List.range n).map fun _ =>
    s!"\{\"time\":{t},\"cost\":1,\"kind\":\"oneoff\",\"charged\":true}") ++ "]"

/-- The wire cases: (name, op, request without op). -/
def cases : List (String × String × Json) := [
  ("reserve: fresh state, one request goes and is booked", "ci.budget.reserve",
    lit "{\"now\":1000,\"cost\":1}"),
  ("reserve: cost 0 is charged as 1", "ci.budget.reserve", lit "{\"now\":1000,\"cost\":0}"),
  ("reserve: inside retry-after waits until it ends", "ci.budget.reserve",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"retryUntil\":1060},\"cost\":1}"),
  ("reserve: remaining at the floor before the reset waits for the reset", "ci.budget.reserve",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"remaining\":500,\"reset\":1900},\"cost\":1}"),
  ("reserve: remaining above the floor goes", "ci.budget.reserve",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"remaining\":501,\"reset\":1900},\"cost\":1}"),
  ("reserve: remaining 0 after the reset passed goes", "ci.budget.reserve",
    lit "{\"now\":2000,\"state\":{\"now\":990,\"remaining\":0,\"reset\":1900},\"cost\":1}"),
  ("reserve: minute share full (40 one-offs) waits a minute", "ci.budget.reserve",
    lit s!"\{\"now\":1000,\"state\":\{\"now\":1000,\"ledger\":{oneoffs 40 1000}},\"cost\":1}"),
  ("reserve: larger than the one-off minute share stops tooBig", "ci.budget.reserve",
    lit "{\"now\":1000,\"cost\":41}"),
  ("reserve: after 6 failures in a row stops", "ci.budget.reserve",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"fails\":6},\"cost\":1}"),
  ("reserve: the clock never goes back", "ci.budget.reserve",
    lit "{\"now\":900,\"state\":{\"now\":1000},\"cost\":1}"),
  ("next: nothing watched stops idle", "ci.budget.next", lit "{\"now\":1000}"),
  ("next: first tick lists runs created since the oldest watched run", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950},{\"runId\":8,\"createdAt\":900}]}}"),
  ("next: within the interval waits for the last tick plus P", "ci.budget.next",
    lit "{\"now\":1010,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950}],\"lastTick\":1000}}"),
  ("next: P stretches as remaining nears the floor", "ci.budget.next",
    lit "{\"now\":1100,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950}],\"lastTick\":1000,\"remaining\":520,\"reset\":4600}}"),
  ("next: retry-after holds the tick", "ci.budget.next",
    lit "{\"now\":1100,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950}],\"retryUntil\":1200}}"),
  ("next: after 6 failures in a row stops", "ci.budget.next",
    lit "{\"now\":1100,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950}],\"fails\":6}}"),
  ("observe: 200 with rate headers", "ci.budget.observe",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"pending\":{\"kind\":\"oneoff\",\"cost\":1},\"ledger\":[{\"time\":1000,\"cost\":1,\"kind\":\"oneoff\",\"charged\":true}]},\"lines\":[\"HTTP/2.0 200 OK\",\"X-Ratelimit-Remaining: 4321\",\"X-Ratelimit-Reset: 4600\",\"X-Ratelimit-Resource: core\",\"Etag: W/x\"]}"),
  ("observe: rate headers of the graphql bucket leave the remaining count", "ci.budget.observe",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"remaining\":3000,\"reset\":4600},\"lines\":[\"HTTP/2.0 200 OK\",\"X-Ratelimit-Remaining: 4999\",\"X-Ratelimit-Reset: 4700\",\"X-Ratelimit-Resource: graphql\"]}"),
  ("observe: a second core response in the same window cannot raise the remaining count", "ci.budget.observe",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"remaining\":3000,\"reset\":4600},\"lines\":[\"HTTP/2.0 200 OK\",\"X-Ratelimit-Remaining: 3100\",\"X-Ratelimit-Reset: 4600\",\"X-Ratelimit-Resource: core\"]}"),
  ("observe: 403 with retry-after", "ci.budget.observe",
    lit "{\"now\":1000,\"state\":{\"now\":1000},\"lines\":[\"HTTP/2.0 403 Forbidden\",\"Retry-After: 60\"]}"),
  ("observe: 403 with remaining 0 waits for the reset", "ci.budget.observe",
    lit "{\"now\":1000,\"state\":{\"now\":1000},\"lines\":[\"HTTP/2.0 403 Forbidden\",\"X-Ratelimit-Remaining: 0\",\"X-Ratelimit-Reset: 2800\",\"X-Ratelimit-Resource: core\"]}"),
  ("observe: bare 429 backs off 60 s", "ci.budget.observe",
    lit "{\"now\":1000,\"state\":{\"now\":1000},\"lines\":[\"HTTP/2.0 429 Too Many Requests\"]}"),
  ("observe: a call that took 3 responses for a charge of 2 books a correction of 1", "ci.budget.observe",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"pending\":{\"kind\":\"tick\",\"cost\":2},\"ledger\":[{\"time\":1000,\"cost\":2,\"kind\":\"tick\",\"charged\":true}]},\"lines\":[\"< HTTP/2.0 200 OK\",\"< X-Ratelimit-Remaining: 12\",\"< HTTP/2.0 200 OK\",\"< X-Ratelimit-Remaining: 11\",\"< HTTP/2.0 200 OK\",\"< X-Ratelimit-Remaining: 10\"]}"),
  ("step: register a run", "ci.budget.step",
    lit "{\"now\":1000,\"event\":{\"register\":{\"runId\":7,\"createdAt\":950}}}"),
  ("step: registering a watched run again changes nothing", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950}]},\"event\":{\"register\":{\"runId\":7,\"createdAt\":999}}}"),
  ("step: unregister a run", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950},{\"runId\":8,\"createdAt\":960}]},\"event\":{\"unregister\":7}}"),
  ("step: pages of a tick (at least 1)", "ci.budget.step", lit "{\"now\":1000,\"event\":{\"pages\":0}}"),
  ("step: resume clears the failures", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"fails\":6},\"event\":{\"resume\":true}}"),
  ("step: two events in one request is an error", "ci.budget.step",
    lit "{\"now\":1000,\"event\":{\"pages\":2,\"resume\":true}}"),
  ("step: a branch sentinel id registers", "ci.budget.step",
    lit "{\"now\":1000,\"event\":{\"register\":{\"runId\":1000000000838323,\"createdAt\":950}}}"),
  ("step: an id that is no run id and no sentinel is refused", "ci.budget.step",
    lit "{\"now\":1000,\"event\":{\"register\":{\"runId\":5000000000000000,\"createdAt\":950}}}"),
  ("step: a list without the run counts a miss, the third drops it as unseen", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950,\"misses\":2},{\"runId\":8,\"createdAt\":960}]},\"event\":{\"listed\":{\"rows\":[{\"runId\":8,\"createdAt\":960}],\"count\":1,\"pagesRead\":1,\"createdSince\":950}}}"),
  ("step: a full list drops the run it cannot cover as uncovered, keeps a sentinel", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":900},{\"runId\":1000000000000001,\"createdAt\":900},{\"runId\":9,\"createdAt\":990}]},\"event\":{\"listed\":{\"rows\":[{\"runId\":10,\"createdAt\":980},{\"runId\":9,\"createdAt\":990}],\"count\":200,\"pagesRead\":2,\"createdSince\":900}}}"),
  ("step: a list of 200 rows from 3 pages is not cut, so the run it lacks counts a miss", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":900}]},\"event\":{\"listed\":{\"rows\":[{\"runId\":10,\"createdAt\":980}],\"count\":200,\"pagesRead\":3,\"createdSince\":900}}}"),
  ("step: a list of exactly 100 rows from 1 page is cut, so a run older than its oldest row is dropped as uncovered", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950}]},\"event\":{\"listed\":{\"rows\":[{\"runId\":10,\"createdAt\":980}],\"count\":100,\"pagesRead\":1,\"createdSince\":900}}}"),
  ("step: a run created before the list window (registered after the tick began) is not judged", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":900}]},\"event\":{\"listed\":{\"rows\":[{\"runId\":10,\"createdAt\":980}],\"count\":100,\"pagesRead\":1,\"createdSince\":950}}}"),
  ("step: ack removes the logged incidents", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"incidents\":[{\"runId\":7,\"time\":900,\"why\":\"unseen\"},{\"runId\":8,\"time\":990,\"why\":\"uncovered\"}]},\"event\":{\"ack\":1}}"),
  ("next: a stale stored pages of 11 is capped at 10, the tick costs the per-minute tick share 20", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"pages\":11,\"watched\":[{\"runId\":7,\"createdAt\":950}]}}"),
  ("step: a stored watch with an old registeredAt loads; the reply omits the key", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950,\"registeredAt\":10}]},\"event\":{\"resume\":true}}"),
  ("step: sweep drops the watches not in the list (a real run and a sentinel) with orphan incidents", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950},{\"runId\":8,\"createdAt\":960},{\"runId\":1000000000838323,\"createdAt\":900}]},\"event\":{\"sweep\":[8]}}"),
  ("next: markers of a dead pid and a live one: the dead sentinel is swept and does not widen createdSince", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"watched\":[{\"runId\":7,\"createdAt\":950},{\"runId\":1000000000838323,\"createdAt\":900}]},\"markers\":[{\"runId\":7,\"killOk\":true,\"recorded\":\"Tue Oct 20 09:49:39 2026\",\"now\":\"Tue Oct 20 09:49:39 2026\"},{\"runId\":1000000000838323,\"killOk\":false,\"recorded\":\"Tue Oct 20 08:00:00 2026\"}]}"),
  ("next: a reused pid (start time differs) is no waiter: the watch is swept and the poller is idle", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"watched\":[{\"runId\":7,\"createdAt\":950}]},\"markers\":[{\"runId\":7,\"killOk\":true,\"recorded\":\"Tue Oct 20 09:49:39 2026\",\"now\":\"Tue Oct 20 10:15:02 2026\"}]}"),
  ("next: a marker without a recorded token is alive when its pid exists", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"watched\":[{\"runId\":7,\"createdAt\":950}]},\"markers\":[{\"runId\":7,\"killOk\":true,\"now\":\"Tue Oct 20 10:15:02 2026\"}]}"),
  ("next: a recorded token whose pid ps cannot see now is no waiter: the watch is swept", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"watched\":[{\"runId\":7,\"createdAt\":950}]},\"markers\":[{\"runId\":7,\"killOk\":true,\"recorded\":\"Tue Oct 20 09:49:39 2026\"}]}"),
  ("next: without a markers key nothing is swept, the watch is ticked", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"watched\":[{\"runId\":7,\"createdAt\":950}]}}"),
  ("next: an empty marker list sweeps every watch", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"watched\":[{\"runId\":7,\"createdAt\":950}]},\"markers\":[]}"),
  ("status: window sums, interval and guards", "ci.budget.status",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"ledger\":[{\"time\":980,\"cost\":2,\"kind\":\"tick\",\"charged\":true},{\"time\":980,\"cost\":1,\"kind\":\"tick\",\"charged\":false},{\"time\":100,\"cost\":1,\"kind\":\"oneoff\",\"charged\":true}],\"watched\":[{\"runId\":7,\"createdAt\":950}]}}"),
  ("limits", "ci.budget.limits", lit "{}")]

/-- The wire cases of `ci.attempt` (task `ci-wait-lag`), a list of their own so that the start-time allocations of
`cases` stay under the init-cost bound. -/
def attemptCases : List (String × String × Json) := [
  ("attempt reuse: the same attempt", "ci.attempt", lit "{\"recorded\":2,\"live\":2}"),
  ("attempt reuse: a rerun made attempt 2, the cache is attempt 1", "ci.attempt", lit "{\"recorded\":1,\"live\":2}"),
  ("attempt reuse: a cache with no attempt", "ci.attempt", lit "{\"live\":2}"),
  ("attempt settled: a row of attempt 1, the view shows attempt 2", "ci.attempt", lit "{\"row\":1,\"view\":2}"),
  ("attempt settled: a row of attempt 2, the view shows attempt 2", "ci.attempt", lit "{\"row\":2,\"view\":2}"),
  ("attempt settled: a row with no attempt", "ci.attempt", lit "{\"view\":2}"),
  ("attempt current: attempt 1 is below the floor 2", "ci.attempt", lit "{\"floor\":2,\"row\":1}"),
  ("attempt current: attempt 2 meets the floor 2", "ci.attempt", lit "{\"floor\":2,\"row\":2}"),
  ("attempt current: no attempt under floor 0", "ci.attempt", lit "{\"floor\":0}"),
  ("attempt fresh: a finished row read 30 s ago is shared", "ci.attempt", lit "{\"read\":100,\"now\":130}"),
  ("attempt fresh: read 31 s ago, the run is read again", "ci.attempt", lit "{\"read\":100,\"now\":131}"),
  ("attempt jobsSettled: every job has a conclusion", "ci.attempt", lit "{\"open\":0,\"ago\":0}"),
  ("attempt jobsSettled: one job still open right after the finish, read again", "ci.attempt", lit "{\"open\":1,\"ago\":4}"),
  ("attempt jobsSettled: one job open 300 s after the finish, still lag", "ci.attempt", lit "{\"open\":1,\"ago\":300}"),
  ("attempt jobsSettled: one job open 301 s after the finish, a fact", "ci.attempt", lit "{\"open\":1,\"ago\":301}")]

/-! ## Replay fixtures (format: `FwTest.CiBudget`) -/

/-- A scenario line. -/
def scenario (name : String) (waiters seconds oneoffEvery : Nat) (extra : List (String × Json)) : Json :=
  Json.mkObj [("scenario", Json.mkObj ([("name", .str name), ("waiters", toJson waiters), ("start", toJson t0),
    ("seconds", toJson seconds), ("oneoffEvery", toJson oneoffEvery), ("oneoffCost", toJson (1 : Nat))] ++ extra))]

/-- An issue-count expectation: issues of `kind` (`tick`, `oneoff` or `any`) with time `t` in
`t0 + a ≤ t < t0 + b` number between `lo` and `hi`. -/
def count (a b : Nat) (kind : String) (lo hi : Nat) : Json :=
  Json.mkObj [("from", toJson (t0 + a)), ("until", toJson (t0 + b)), ("kind", .str kind), ("min", toJson lo),
    ("max", toJson hi)]

/-- A response override: the first call at or after `t0 + a` gets these header lines. -/
def override (a : Nat) (ls : List String) : Json :=
  Json.mkObj [("at", toJson (t0 + a)), ("lines", .arr (ls.map Json.str).toArray)]

/-- The fixtures: (file stem, lines). -/
def fixtures : List (String × List Json) := [
  ("incident-10-18", [scenario "incident-10-18" 12 7200 120
    [("expect", Json.mkObj [("ticksPerHourMax", toJson (720 : Nat)), ("oldExceeds", toJson (5000 : Nat)),
      ("counts", .arr #[count 0 3600 "tick" 360 360])])]]),
  ("remaining-zero", [scenario "remaining-zero" 3 3600 45
    [("expect", Json.mkObj [("counts", .arr #[count 601 1800 "any" 0 0, count 1800 1801 "tick" 1 1])])],
    override 600 ["HTTP/2.0 403 Forbidden", "X-Ratelimit-Remaining: 0", s!"X-Ratelimit-Reset: {t0 + 1800}", "X-Ratelimit-Resource: core"]]),
  ("retry-after", [scenario "retry-after" 3 1800 45
    [("expect", Json.mkObj [("counts", .arr #[count 301 420 "any" 0 0, count 420 421 "tick" 1 1])])],
    override 300 ["HTTP/2.0 403 Forbidden", "Retry-After: 120"]]),
  ("bare-429", [scenario "bare-429" 3 1800 45
    [("expect", Json.mkObj [("counts", .arr #[count 301 360 "any" 0 0, count 360 361 "tick" 1 1])])],
    override 300 ["HTTP/2.0 429 Too Many Requests"]]),
  ("remaining-floor", [scenario "remaining-floor" 3 5400 45
    [("expect", Json.mkObj [("counts", .arr #[count 946 3600 "any" 0 0, count 3600 3601 "tick" 1 1])])],
    Json.mkObj [("at", toJson (t0 + 900)), ("serverRemaining", toJson (400 : Nat))]]),
  ("n-sweep", [scenario "n-sweep" 1 3600 45 [("sweep", .arr #[toJson (1 : Nat), toJson (12 : Nat), toJson (50 : Nat)])]]),
  ("burst-50", [scenario "burst-50" 50 600 0
    [("burst", toJson (50 : Nat)), ("burstAt", toJson (t0 + 5)),
     ("expect", Json.mkObj [("counts", .arr #[count 5 65 "oneoff" 40 40, count 65 66 "oneoff" 10 10,
       count 0 600 "tick" 60 60])])]])]

/-! ## Lag partition (`Fw.Ci.Lag`) -/

/-- The cases of `lag.jsonl`: (name, marks, previous tick). -/
def lagCases : List (String × Fw.Ci.Lag.Marks × Option Int) := [
  ("in order, previous tick before the finish", ⟨1000, 3000, 3100, 5000, 5010, 5020, 5030, 5230, 5300⟩, some 900),
  ("previous tick after the finish: the list was stale", ⟨1000, 9000, 9100, 9500, 9510, 9520, 9530, 9630, 9700⟩, some 4000),
  ("no previous tick seen", ⟨2000, 2500, 2550, 3000, 3005, 3010, 3020, 3050, 3100⟩, none),
  ("marks out of order (clock skew): the pieces still add up", ⟨5000, 4000, 4500, 4400, 4600, 4700, 4800, 4850, 4900⟩, some 6000)]

/-- The text of `lag.jsonl`. -/
def lagText : String :=
  String.join (lagCases.map fun (name, m, prev) =>
    let p := Fw.Ci.Lag.parts m
    let marks := Json.mkObj [("upd", toJson m.upd), ("tick", toJson m.tick), ("read", toJson m.read), ("viewEnd", toJson m.viewEnd),
      ("done", toJson m.done), ("ret", toJson m.ret), ("i0", toJson m.i0), ("i1", toJson m.i1), ("end", toJson m.stop)]
    let parts := Json.mkObj [("list", toJson p.list), ("pickup", toJson p.pickup), ("view", toJson p.view), ("verdict", toJson p.verdict),
      ("cleanup", toJson p.cleanup), ("ingest", toJson p.ingest), ("exit", toJson p.exit), ("total", toJson p.total)]
    let extra := match prev with
      | none => []
      | some q => [("prev", toJson q), ("gap", toJson (Fw.Ci.Lag.gap m.tick q)), ("stale", toJson (Fw.Ci.Lag.stale q m.upd))]
    (Json.mkObj ([("name", .str name), ("marks", marks), ("parts", parts)] ++ extra)).compress ++ "\n")

/-- The kind cases of `lag-kind.jsonl`: (name, lanes missing, tick, registration). -/
def kindCases : List (String × Bool × Option Int × Int) := [
  ("a lane without a finished run: grace", true, some 9000, 5000),
  ("a lane missing and no tick: grace", true, none, 5000),
  ("a tick before the registration: late", false, some 4000, 5000),
  ("a tick at the registration: done", false, some 5000, 5000),
  ("a tick after the registration: done", false, some 9000, 5000),
  ("no tick seen: done", false, none, 5000)]

/-- The critical-run cases: (name, finish times). -/
def critCases : List (String × List Int) := [
  ("no rows", []), ("one row", [7]), ("the latest finish wins", [3, 9, 4]), ("a tie: the first", [9, 9, 2]), ("the last is latest", [1, 2, 3])]

def kindName : Fw.Ci.Lag.Kind -> String
  | .done => "done" | .late => "late" | .grace => "grace"

/-- The text of `lag-kind.jsonl`. -/
def lagKindText : String :=
  String.join (kindCases.map fun (name, lm, t, reg) =>
    (Json.mkObj ([("name", .str name), ("op", .str "kind"), ("lanesMissing", .bool lm), ("reg", toJson reg),
      ("kind", .str (kindName (Fw.Ci.Lag.kind lm t reg)))] ++ (match t with | none => [] | some x => [("tick", toJson x)]))).compress ++ "\n") ++
  String.join (critCases.map fun (name, us) =>
    (Json.mkObj ([("name", .str name), ("op", .str "crit"), ("upds", toJson us)] ++
      (match Fw.Ci.Lag.crit us with | none => [] | some i => [("crit", toJson i)]))).compress ++ "\n")

/-! ## Files -/

/-- The text of `wire.jsonl`. -/
def wireText (_ : Unit := ()) : String :=
  String.join ((cases ++ attemptCases).map fun (name, op, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

/-- The text of `limits.json`. -/
def limitsText : String := (Fw.Wire.Ci.limitsJson Fw.Ci.Budget.defaults).compress ++ "\n"

/-- Every file: (path relative to the golden directory, text). -/
def files (_ : Unit := ()) : List (System.FilePath × String) :=
  [(("limits.json" : System.FilePath), limitsText), (("wire.jsonl" : System.FilePath), wireText), (("lag.jsonl" : System.FilePath), lagText),
    (("lag-kind.jsonl" : System.FilePath), lagKindText)] ++
  fixtures.map fun (stem, ls) =>
    ((("fixtures" : System.FilePath) / s!"{stem}.jsonl"), String.join (ls.map fun (j : Json) => j.compress ++ "\n"))

/-- The golden directory, from the package root `lean/`. -/
def dir (root : System.FilePath) : System.FilePath := root / ".." / "packages" / "contracts" / "golden" / "ci-budget"

/-- Compare (or write) every file; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let mut stale := 0
  if write then IO.FS.createDirAll (dir root / "fixtures")
  for (p, text) in files do
    let f := dir root / p
    if write then
      IO.FS.writeFile f text
    else
      let cur ← try IO.FS.readFile f catch _ => pure ""
      if cur != text then
        IO.println s!"ci-budget golden: {f} is stale (regenerate: cd lean && lake test -- --write-ci-budget-golden)"
        stale := stale + 1
  IO.println s!"ci-budget golden: {files.length} files, {cases.length + attemptCases.length} wire cases, {stale} stale"
  return stale

#guard cases.length = 48
#guard fixtures.length = 7

end Fw.Wire.Ci.Golden
