import Fw.Wire
import Fw.Ops.Golden
/-!
# Golden vectors and replay fixtures of the GitHub request budget (`ci.budget.*`)

Files under `packages/contracts/golden/ci-budget/`, generated from Lean, never by hand:
- `limits.json`: the limits `Fw.Ci.Budget.defaults` with both shares per window (TS reads them here or through
  `ci.budget.limits` and never restates them);
- `wire.jsonl`: one line per case, `{"name", "request", "response"}` (`request` carries its `op`; `response` is what
  `fwcore` replies, without the `id`);
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
  ("step: expire drops a watch older than the longest workflow timeout, with an incident", "ci.budget.step",
    lit "{\"now\":100000,\"state\":{\"now\":100000,\"watched\":[{\"runId\":1000000000838323,\"createdAt\":90000},{\"runId\":7,\"createdAt\":99000}]},\"event\":{\"expire\":true}}"),
  ("step: a list without the run counts a miss, the third drops it as unseen", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":950,\"misses\":2},{\"runId\":8,\"createdAt\":960}]},\"event\":{\"listed\":{\"rows\":[{\"runId\":8,\"createdAt\":960}],\"full\":false}}}"),
  ("step: a full list drops the run it cannot cover as uncovered, keeps a sentinel", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"watched\":[{\"runId\":7,\"createdAt\":900},{\"runId\":1000000000000001,\"createdAt\":900},{\"runId\":9,\"createdAt\":990}]},\"event\":{\"listed\":{\"rows\":[{\"runId\":10,\"createdAt\":980},{\"runId\":9,\"createdAt\":990}],\"full\":true}}}"),
  ("step: ack removes the logged incidents", "ci.budget.step",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"incidents\":[{\"runId\":7,\"time\":900,\"why\":\"unseen\"},{\"runId\":8,\"time\":990,\"why\":\"expired\"}]},\"event\":{\"ack\":1}}"),
  ("next: 11 pages asked for, 10 read, the tick costs the per-minute tick share 20", "ci.budget.next",
    lit "{\"now\":1000,\"state\":{\"now\":990,\"pages\":11,\"watched\":[{\"runId\":7,\"createdAt\":950}]}}"),
  ("status: window sums, interval and guards", "ci.budget.status",
    lit "{\"now\":1000,\"state\":{\"now\":1000,\"ledger\":[{\"time\":980,\"cost\":2,\"kind\":\"tick\",\"charged\":true},{\"time\":980,\"cost\":1,\"kind\":\"tick\",\"charged\":false},{\"time\":100,\"cost\":1,\"kind\":\"oneoff\",\"charged\":true}],\"watched\":[{\"runId\":7,\"createdAt\":950}]}}"),
  ("limits", "ci.budget.limits", lit "{}")]

/-! ## Replay fixtures (format: `FwTest.CiBudget`) -/

/-- A scenario line. -/
def scenario (name : String) (waiters seconds oneoffEvery : Nat) (extra : List (String × Json)) : Json :=
  Json.mkObj [("scenario", Json.mkObj ([("name", .str name), ("waiters", toJson waiters), ("start", toJson t0),
    ("seconds", toJson seconds), ("oneoffEvery", toJson oneoffEvery), ("oneoffCost", toJson (1 : Nat))] ++ extra))]

/-- An issue-count expectation: issues of `kind` (`tick`, `oneoff` or `any`) with time in $[t_0 + a, t_0 + b)$
number between `lo` and `hi`. -/
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

/-! ## Files -/

/-- The text of `wire.jsonl`. -/
def wireText (_ : Unit := ()) : String :=
  String.join (cases.map fun (name, op, req) =>
    (Json.mkObj [("name", .str name), ("request", withOp op req), ("response", respond op req)]).compress ++ "\n")

/-- The text of `limits.json`. -/
def limitsText : String := (Fw.Wire.Ci.limitsJson Fw.Ci.Budget.defaults).compress ++ "\n"

/-- Every file: (path relative to the golden directory, text). -/
def files (_ : Unit := ()) : List (System.FilePath × String) :=
  [(("limits.json" : System.FilePath), limitsText), (("wire.jsonl" : System.FilePath), wireText)] ++
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
  IO.println s!"ci-budget golden: {files.length} files, {cases.length} wire cases, {stale} stale"
  return stale

#guard cases.length = 38
#guard fixtures.length = 7

end Fw.Wire.Ci.Golden
