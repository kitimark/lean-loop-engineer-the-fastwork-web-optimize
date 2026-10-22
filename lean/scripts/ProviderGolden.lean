import Lean.Data.Json
import Fw.Ci.Provider

/-! Write (or with `--check`, verify) `packages/contracts/golden/ci/provider.jsonl`: one line per case,
`{"op", "name", "request", "response"}`, from `Fw.Ci.Provider`. Consumer: `scripts/circleci.mjs`, checked by
`node --test scripts/circleci.test.mjs`. Run from `lean/`: `lake env lean --run scripts/ProviderGolden.lean [--check]`. -/

open Lean Fw.Ci.Provider

def platformName : Platform → String
  | .linuxArm => "linux-arm"
  | .macos => "macos"

def providerName : Provider → String
  | .github => "github"
  | .circleci => "circleci"

def conclusionName : Conclusion → String
  | .pass => "pass"
  | .fail => "fail"
  | .notRun => "not-run"

def mismatchName : Mismatch → String
  | .providers => "providers"
  | .job => "job"
  | .sha => "sha"
  | .digest => "digest"

def keyVerdictName : KeyVerdict → String
  | .ok => "ok"
  | .missing => "missing"
  | .unknown => "unknown"

def optBool : Option Bool → Json
  | some b => Json.bool b
  | none => Json.null

def stopName : Stop → String
  | .cap => "cap"
  | .queue => "queue"
  | .storage => "storage"

def poolName : Pool → String
  | .oss => "oss"
  | .base => "base"

def optNat : Option Nat → Json
  | some n => toJson n
  | none => Json.null

def optStr : Option String → Json
  | some s => .str s
  | none => Json.null

def runJson (r : Run) : Json :=
  Json.mkObj [("provider", .str (providerName r.provider)), ("job", .str r.job), ("sha", .str r.sha),
    ("conclusion", .str (conclusionName r.conclusion)), ("digest", optStr r.digest), ("class", .str r.cls),
    ("queueMs", toJson r.queueMs), ("durMs", toJson r.durMs)]

def comparisonJson : Except Mismatch Comparison → Json
  | .error m => Json.mkObj [("comparable", .bool false), ("reason", .str (mismatchName m))]
  | .ok k => Json.mkObj [("comparable", .bool true), ("finding", .bool k.finding), ("ratioPermille", optNat k.ratioPermille),
      ("queueGithubMs", toJson k.queueGithubMs), ("queueCircleMs", toJson k.queueCircleMs), ("credits", optNat k.credits)]

def stopInputJson (i : StopInput) : Json :=
  Json.mkObj [("durMs", toJson i.durMs), ("queueMs", toJson i.queueMs), ("storageMilli", toJson i.storageMilli)]

def routeInputJson (i : RouteInput) : Json :=
  Json.mkObj [("lane", .str i.lane), ("platform", .str (platformName i.platform)), ("class", .str i.cls),
    ("allow", .arr (i.allow.map Json.str).toArray), ("ghDegraded", .bool i.ghDegraded), ("estMs", toJson i.estMs),
    ("creditsLeft", toJson i.creditsLeft)]

def line (op name : String) (request response : Json) : String :=
  (Json.mkObj [("op", .str op), ("name", .str name), ("request", request), ("response", response)]).compress ++ "\n"

def rateJson (r : Rate) : Json :=
  Json.mkObj [("class", .str r.cls), ("platform", .str (platformName r.platform)), ("pool", .str (poolName r.pool)),
    ("creditsPerMin", toJson r.creditsPerMin), ("free", .bool r.free), ("source", .str r.source)]

def ghNameJson : GhName → Json
  | .exact n => Json.mkObj [("exact", .str n)]
  | .matrix p vm => Json.mkObj [("prefix", .str p), ("vm", .str vm), ("suffix", .str (vmSuffix vm))]

def tables : List String := [
  line "rates" "the price list the pilot meets" (Json.mkObj [])
    (Json.mkObj [("rates", .arr (rates.map rateJson).toArray),
      ("pools", Json.mkObj [("oss", toJson (poolCredits .oss)), ("base", toJson (poolCredits .base))])]),
  line "constants" "the stop-rule limits" (Json.mkObj [])
    (Json.mkObj [("capMs", toJson capMs), ("queueMaxMs", toJson queueMaxMs), ("storageStopMilli", toJson storageStopMilli), ("storageAllowMilli", toJson storageAllowMilli),
      ("overageCreditsPerGbMonth", toJson overageCreditsPerGbMonth), ("windowMs", toJson windowMs),
      ("retentionDays", Json.mkObj [("cache", toJson (retentionDays .cache)), ("workspace", toJson (retentionDays .workspace)),
        ("artifact", toJson (retentionDays .artifact))]), ("ownSaveMilli", toJson ownSaveMilli)]),
  line "jobMap" "GitHub job against CircleCI job" (Json.mkObj [])
    (Json.mkObj [("jobs", .arr (jobMap.map fun r =>
      Json.mkObj [("lane", .str r.lane), ("github", ghNameJson r.gh), ("circleci", .str r.circleci), ("digest", .bool r.digest), ("savesCache", .bool r.savesCache)]).toArray),
      ("landJobs", .arr (landJobs.map Json.str).toArray)])]

def creditCases : List (String × String × Nat) := [
  ("one minute of arm.medium.gen2 costs its rate", "arm.medium.gen2", 60000),
  ("one minute of arm.large.gen2 costs its rate", "arm.large.gen2", 60000),
  ("a minute and a half of arm.large.gen2 rounds up to 18", "arm.large.gen2", 90000),
  ("one millisecond costs one credit (rounded up)", "arm.medium.gen2", 1),
  ("zero time costs nothing", "m4pro.medium", 0),
  ("ten minutes of m4pro.medium", "m4pro.medium", 600000),
  ("a class outside the price list has no credits", "arm.small", 1000)]

def storageCases : List (String × Nat × Nat) := [
  ("one Lake cache entry kept 15 days", 1030000000, 15),
  ("nothing stored", 0, 15),
  ("exactly one GB for 30 days", 1000000000, 30),
  ("one byte for one day rounds up", 1, 1)]

def rowJson (r : LedgerRow) : Json :=
  Json.mkObj [("at", optNat r.atMs), ("cache", toJson r.cache), ("workspace", toJson r.workspace), ("artifacts", toJson r.artifacts)]

def storageNowCases : List (String × List LedgerRow × Nat) := [
  ("the ledger of 2026-10-21 as totals: 650", [ledger20261021], 1792592506000),
  ("a cache GB fetched now: 15 days count half", [⟨some 0, 1000000000, 0, 0⟩], 0),
  ("an artifact GB counts its 30 days", [⟨some 0, 0, 0, 1000000000⟩], 0),
  ("a workspace GB counts 15 days", [⟨some 0, 0, 1000000000, 0⟩], 0),
  ("at the window's end the row still counts", [⟨some 0, 1000000000, 0, 0⟩], windowMs),
  ("one ms past the window the row counts 0", [⟨some 0, 1000000000, 0, 0⟩], windowMs + 1),
  ("a row with no time always counts", [⟨none, 1000000000, 0, 0⟩], windowMs + 1),
  ("one old row, one recent row", [⟨some 0, 1000000000, 0, 0⟩, ⟨some 5000000000, 400000000, 73728, 1668534⟩], 5000000000),
  ("rounding is once over the sum", [⟨some 0, 1, 0, 0⟩, ⟨some 0, 0, 1, 0⟩, ⟨some 0, 0, 0, 1⟩], 0),
  ("no row", [], 0)]

def storageCreditCases : List (String × Nat) := [
  ("nothing stored", 0), ("at the allowance", 2000), ("one thousandth over rounds up to a credit", 2001),
  ("one GB-month over: 420", 3000), ("the 2026-10-21 count plus one own save", 885), ("ten GB-months", 10000)]

def saveJson : CacheSave → Json
  | .absent => Json.mkObj [("kind", .str "absent")]
  | .skipped => Json.mkObj [("kind", .str "skipped")]
  | .stored t => Json.mkObj [("kind", .str "stored"), ("tenthsMiB", toJson t)]

def cacheSaveCases : List (String × CacheSave) := [
  ("no save step ran (the restored cache was current)", .absent),
  ("the step found the key stored and uploaded nothing", .skipped),
  ("the 9.3 MiB archive of the first Arm pipeline", .stored 93),
  ("a zero-size archive still counts one tenth", .stored 0),
  ("one MiB", .stored 10)]

def cachePipelineCases : List (String × List CacheSave) := [
  ("a pipeline on an unchanged lockfile (hit, then skipped)", [.absent, .skipped]),
  ("a pipeline on a new lockfile (one job stores, one finds the key locked)", [.stored 93, .skipped]),
  ("both jobs store", [.stored 93, .stored 93]),
  ("no job", [])]

def mk (provider : Provider) (job sha : String) (c : Conclusion) (d : Option String) (cls : String) (q t : Nat) : Run :=
  ⟨provider, job, sha, c, d, cls, q, t⟩

def gh (job : String := "engine-chromium") (sha : String := "abc1234") (c : Conclusion := .pass)
    (d : Option String := some "d1") (q : Nat := 4000) (t : Nat := 100000) : Run :=
  mk .github job sha c d "ubuntu-24.04-arm" q t

def cc (job : String := "engine-chromium") (sha : String := "abc1234") (c : Conclusion := .pass)
    (d : Option String := some "d1") (cls : String := "arm.medium.gen2") (q : Nat := 9000) (t : Nat := 150000) : Run :=
  mk .circleci job sha c d cls q t

def compareCases : List (String × Run × Run) := [
  ("equal digests: no finding, ratio 1500, credits of 2.5 minutes", gh, cc),
  ("same duration: ratio exactly 1000", gh (t := 100000), cc (t := 100000)),
  ("CircleCI faster: ratio below 1000", gh (t := 100000), cc (t := 40000)),
  ("ratio rounds down", gh (t := 3), cc (t := 4)),
  ("GitHub took no time: no ratio", gh (t := 0), cc),
  ("digest job: conclusions differ, digests equal: no finding (the step conclusion is not the verdict)", gh, cc (c := .fail)),
  ("digest job: pass against not-run with equal digests: no finding", gh, cc (c := .notRun)),
  ("digest job: digest differs: a finding", gh, cc (d := some "d2")),
  ("digest job: digest differs although both pass: a finding", gh (c := .pass), cc (c := .pass) (d := some "d3")),
  ("digest job: GitHub digest missing: not a pair", gh (d := none), cc (d := some "d2")),
  ("digest job: CircleCI digest missing: not a pair", gh, cc (d := none)),
  ("digest job: both digests missing: not a pair", gh (d := none), cc (d := none)),
  ("second engine job is judged by its digest too", gh (job := "engine-playwright-webkit"), cc (job := "engine-playwright-webkit") (d := some "d9")),
  ("sha is checked before the digest", gh (d := none), cc (sha := "def5678")),
  ("verdict job: equal conclusions, no digests: no finding", gh (job := "verdict") (d := none), cc (job := "verdict") (d := none)),
  ("verdict job: conclusion differs: a finding", gh (job := "verdict") (d := none), cc (job := "verdict") (c := .fail) (d := none)),
  ("verdict job: pass against not-run: a finding", gh (job := "verdict") (d := none), cc (job := "verdict") (c := .notRun) (d := none)),
  ("verdict job: both fail: no finding", gh (job := "verdict") (c := .fail) (d := none), cc (job := "verdict") (c := .fail) (d := none)),
  ("verdict job: both digests present and different: a finding", gh (job := "verdict"), cc (job := "verdict") (d := some "d2")),
  ("verdict job: one side has no digest: digests are not compared", gh (job := "verdict") (d := none), cc (job := "verdict") (d := some "d2")),
  ("unknown CircleCI class: no credits", gh, cc (cls := "arm.small")),
  ("m4pro.medium: credits at 200 a minute", gh (job := "webkit-sim") (d := none) (t := 1200000),
    cc (job := "webkit-sim") (d := none) (cls := "m4pro.medium") (t := 600000)),
  ("queue times are carried over", gh (q := 0), cc (q := 700000)),
  ("different job: not a pair", gh, cc (job := "verdict")),
  ("different commit: not a pair", gh, cc (sha := "def5678")),
  ("two GitHub runs: not a pair", gh, { gh with provider := .github }),
  ("sides swapped: not a pair", cc, gh),
  ("providers are checked before the job", gh, { cc with provider := .github, job := "verdict" })]

def stopCases : List (String × StopInput) := [
  ("all within the limits", ⟨1800000, 60000, 515⟩),
  ("a job at the 1 h cap stops", ⟨3600000, 0, 0⟩),
  ("a job one ms under the cap goes on", ⟨3599999, 0, 0⟩),
  ("a queue wait of exactly 10 min goes on", ⟨0, 600000, 0⟩),
  ("a queue wait over 10 min stops", ⟨0, 600001, 0⟩),
  ("storage of exactly 1 GB-month goes on", ⟨0, 0, 1000⟩),
  ("storage over 1 GB-month stops", ⟨0, 0, 1001⟩),
  ("all three reasons are listed in order", ⟨3700000, 700000, 2000⟩),
  ("queue and storage without the cap", ⟨10, 700000, 2000⟩)]

def landStopCases : List (String × StopInput) := [
  ("all within the limits", ⟨1800000, 60000, 515⟩),
  ("a job at the 1 h cap stops", ⟨3600000, 0, 0⟩),
  ("a job one ms under the cap goes on", ⟨3599999, 0, 0⟩),
  ("a queue wait of exactly 10 min goes on", ⟨0, 600000, 0⟩),
  ("a queue wait over 10 min stops", ⟨0, 600001, 0⟩),
  ("storage over 1 GB-month goes on", ⟨0, 0, 1001⟩),
  ("a ledger at 1297 goes on", ⟨1800000, 60000, 1297⟩),
  ("cap and queue are listed in order, storage never", ⟨3700000, 700000, 2000⟩),
  ("queue without the cap, storage never", ⟨10, 700000, 100000⟩)]

def routeCases : List (String × RouteInput) := [
  ("allowlisted Linux lane, free class, credits left: CircleCI",
    ⟨"premise-tests", .linuxArm, "arm.medium.gen2", ["premise-tests"], false, 600000, 100⟩),
  ("a lane outside the allowlist stays on GitHub",
    ⟨"lean", .linuxArm, "arm.medium.gen2", ["premise-tests"], false, 600000, 100⟩),
  ("an empty allowlist stays on GitHub",
    ⟨"premise-tests", .linuxArm, "arm.medium.gen2", [], false, 600000, 100⟩),
  ("a Linux lane does not need GitHub to be degraded",
    ⟨"premise-tests", .linuxArm, "arm.large.gen2", ["premise-tests", "chromium-counts"], true, 600000, 120⟩),
  ("credits left exactly the estimate: CircleCI",
    ⟨"premise-tests", .linuxArm, "arm.medium.gen2", ["premise-tests"], false, 600000, 60⟩),
  ("credits left one short: GitHub",
    ⟨"premise-tests", .linuxArm, "arm.medium.gen2", ["premise-tests"], false, 600000, 59⟩),
  ("macOS lane while GitHub is healthy: GitHub",
    ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], false, 600000, 30000⟩),
  ("macOS lane while GitHub is degraded and credits remain: CircleCI",
    ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], true, 600000, 30000⟩),
  ("macOS lane while degraded but the free minutes are used up: GitHub",
    ⟨"webkit-sim", .macos, "m4pro.medium", ["webkit-sim"], true, 600000, 1999⟩),
  ("macOS lane on a paid class: GitHub",
    ⟨"webkit-sim", .macos, "m4pro.large", ["webkit-sim"], true, 600000, 30000⟩),
  ("a Linux lane on a macOS class: GitHub",
    ⟨"premise-tests", .linuxArm, "m4pro.medium", ["premise-tests"], true, 600000, 30000⟩),
  ("a macOS lane on an Arm class: GitHub",
    ⟨"webkit-sim", .macos, "arm.medium.gen2", ["webkit-sim"], true, 600000, 400000⟩),
  ("a class outside the price list: GitHub",
    ⟨"premise-tests", .linuxArm, "arm.small", ["premise-tests"], false, 600000, 400000⟩)]

def circleStatuses : List String := ["success", "failed", "infrastructure_fail", "timedout", "error", "failing", "unauthorized",
  "canceled", "not_run", "queued", "running", "on_hold", "terminated-unknown", ""]

/-- Names of a job's resource class as the API reports them (the first four MEASURED on real jobs' `executor.resource_class`), and as the config writes them. -/
def apiClasses : List String := ["arm-medium-gen2", "arm-large-gen2", "arm-medium", "arm-large", "m4pro-medium", "arm.medium.gen2", ""]

def githubConclusions : List String := ["success", "failure", "timed_out", "startup_failure", "action_required", "cancelled",
  "skipped", "neutral", "stale", ""]

def waitCases : List (String × WaitInput) := [
  ("every workflow passed", ⟨["success"], 10, 300, 3600⟩),
  ("two workflows passed", ⟨["success", "success"], 10, 300, 3600⟩),
  ("one failed, one passed: exit 1", ⟨["success", "failed"], 10, 300, 3600⟩),
  ("an infrastructure failure is exit 1", ⟨["infrastructure_fail"], 10, 300, 3600⟩),
  ("a timed-out workflow is exit 1", ⟨["timedout"], 10, 300, 3600⟩),
  ("an unauthorized workflow is exit 1", ⟨["unauthorized"], 10, 300, 3600⟩),
  ("a cancelled workflow is not a pass: exit 4", ⟨["canceled"], 10, 300, 3600⟩),
  ("passed and cancelled is exit 4", ⟨["success", "canceled"], 10, 300, 3600⟩),
  ("a workflow that did not run is exit 4", ⟨["not_run"], 10, 300, 3600⟩),
  ("failed beats cancelled", ⟨["canceled", "failed"], 10, 300, 3600⟩),
  ("a running workflow goes on", ⟨["running"], 10, 300, 3600⟩),
  ("passed and still running goes on", ⟨["success", "running"], 10, 300, 3600⟩),
  ("a workflow on hold goes on", ⟨["on_hold"], 10, 300, 3600⟩),
  ("failing (not yet final) goes on", ⟨["failing"], 10, 300, 3600⟩),
  ("no workflow yet, inside the grace time: goes on", ⟨[], 299, 300, 3600⟩),
  ("no workflow at the grace time: exit 4", ⟨[], 300, 300, 3600⟩),
  ("no workflow at the timeout: grace is checked first, exit 4", ⟨[], 3600, 300, 3600⟩),
  ("no workflow, timeout before grace: exit 3", ⟨[], 200, 300, 200⟩),
  ("a running workflow at the timeout: exit 3", ⟨["running"], 3600, 300, 3600⟩),
  ("a running workflow one second before the timeout goes on", ⟨["running"], 3599, 300, 3600⟩),
  ("final workflows decide even past the timeout", ⟨["success"], 4000, 300, 3600⟩)]

def keyCases : List (String × KeyInput) := [
  ("a listed key: ok", ⟨some 1, none⟩),
  ("two listed keys: ok", ⟨some 2, some false⟩),
  ("an empty key list: missing", ⟨some 0, none⟩),
  ("an empty key list beats a clone that worked", ⟨some 0, some true⟩),
  ("an unreadable list, last clone worked: ok", ⟨none, some true⟩),
  ("an unreadable list, last clone failed: missing", ⟨none, some false⟩),
  ("an unreadable list, no clone seen: unknown", ⟨none, none⟩)]

def keyKinds : List String := ["deploy-key", "github-user-key", "github-oauth-key", "", "Deploy-Key"]

def checkoutStatuses : List String := ["success", "failed", "running", "not_run", "canceled", "infrastructure_fail", ""]

def ghJobNames : List String := [
  "engine (chromium)", "engine (playwright-webkit)", "verdict", "engine (chromium) again", "engine", "",
  "sim (original, 430, 1, 40a8d4c1deadbeef, v1)", "sim (original, 390, 2, 40a8d4c1deadbeef, v1)",
  "sim (original, 430, 1, 40a8d4c1deadbeef, v2)", "sim (rewrite, 430, 1, 40a8d4c1deadbeef, v1)",
  "sim (original, v1)", "sim (original,, v1)", "sim (original, 430, 1, 40a8d4c1deadbeef, v1) extra", "plan", "guard"]

def text : String :=
  String.join (tables
    ++ creditCases.map (fun (n, c, d) =>
      line "credits" n (Json.mkObj [("class", .str c), ("durMs", toJson d)])
        (Json.mkObj [("credits", optNat (credits c d))]))
    ++ storageCases.map (fun (n, b, d) =>
      line "storage" n (Json.mkObj [("bytes", toJson b), ("days", toJson d)])
        (Json.mkObj [("milli", toJson (storageMilli b d))]))
    ++ storageNowCases.map (fun (n, rows, now) =>
      line "storageNow" n (Json.mkObj [("rows", .arr (rows.map rowJson).toArray), ("now", toJson now)])
        (Json.mkObj [("milli", toJson (storageNow rows now))]))
    ++ storageCreditCases.map (fun (n, m) =>
      line "storageCredits" n (Json.mkObj [("milli", toJson m)]) (Json.mkObj [("credits", toJson (storageCredits m))]))
    ++ cacheSaveCases.map (fun (n, c) =>
      line "cacheSaved" n (Json.mkObj [("save", saveJson c)]) (Json.mkObj [("bytes", toJson (cacheSavedBytes c))]))
    ++ cachePipelineCases.map (fun (n, cs) =>
      line "cachePipeline" n (Json.mkObj [("saves", .arr (cs.map saveJson).toArray)])
        (Json.mkObj [("bytes", toJson (cachePipelineBytes cs))]))
    ++ circleStatuses.map (fun st =>
      line "circleStatus" st (Json.mkObj [("status", .str st)]) (Json.mkObj [("conclusion", .str (conclusionName (ofCircleStatus st)))]))
    ++ githubConclusions.map (fun st =>
      line "githubConclusion" st (Json.mkObj [("conclusion", .str st)]) (Json.mkObj [("result", .str (conclusionName (ofGithubConclusion st)))]))
    ++ apiClasses.map (fun a =>
      line "classOfApi" a (Json.mkObj [("name", .str a)]) (Json.mkObj [("class", .str (classOfApi a))]))
    ++ waitCases.map (fun (n, i) =>
      line "wait" n (Json.mkObj [("statuses", .arr (i.statuses.map Json.str).toArray), ("waitedS", toJson i.waitedS),
        ("noWorkflowS", toJson i.noWorkflowS), ("timeoutS", toJson i.timeoutS)])
        (Json.mkObj [("exit", optNat (waitStep i))]))
    ++ ghJobNames.map (fun n =>
      line "ghJob" n (Json.mkObj [("name", .str n)])
        (Json.mkObj [("circleci", optStr ((jobOfGithub n).map (·.circleci))), ("lane", optStr ((jobOfGithub n).map (·.lane))),
          ("digest", ((jobOfGithub n).map fun (r : JobRow) => Json.bool r.digest).getD Json.null)]))
    ++ compareCases.map (fun (n, g, c) =>
      line "compare" n (Json.mkObj [("github", runJson g), ("circleci", runJson c)]) (comparisonJson (compare g c)))
    ++ stopCases.map (fun (n, i) =>
      line "stop" n (stopInputJson i)
        (Json.mkObj [("stop", .bool (stop i)), ("reasons", .arr ((stops i).map fun s => Json.str (stopName s)).toArray)]))
    ++ landStopCases.map (fun (n, i) =>
      line "landStop" n (stopInputJson i)
        (Json.mkObj [("reasons", .arr ((landStops i).map fun s => Json.str (stopName s)).toArray)]))
    ++ routeCases.map (fun (n, i) =>
      line "route" n (routeInputJson i) (Json.mkObj [("provider", .str (providerName (route i)))]))
    ++ keyCases.map (fun (n, i) =>
      line "keyCheck" n (Json.mkObj [("keys", optNat i.keys), ("checkout", optBool i.checkout)])
        (Json.mkObj [("verdict", .str (keyVerdictName (keyVerdict i))), ("proceed", .bool (keyProceed i))]))
    ++ keyKinds.map (fun k =>
      line "keyKind" k (Json.mkObj [("kind", .str k)]) (Json.mkObj [("usable", .bool (usableKeyKind k))]))
    ++ checkoutStatuses.map (fun st =>
      line "checkoutStatus" st (Json.mkObj [("status", .str st)]) (Json.mkObj [("clone", optBool (checkoutOfStatus st))])))

def main (args : List String) : IO UInt32 := do
  let p : System.FilePath := ".." / "packages" / "contracts" / "golden" / "ci" / "provider.jsonl"
  let n := (text.splitOn "\n").length - 1
  if args.contains "--check" then
    let cur ← try IO.FS.readFile p catch _ => pure ""
    if cur != text then
      IO.println s!"provider golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/ProviderGolden.lean)"
      return 1
    IO.println s!"provider golden: {n} lines, up to date"
    return 0
  IO.FS.writeFile p text
  IO.println s!"provider golden: {n} lines written"
  return 0
