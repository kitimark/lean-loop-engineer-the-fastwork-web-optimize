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

def tables : List String := [
  line "rates" "the price list the pilot meets" (Json.mkObj [])
    (Json.mkObj [("rates", .arr (rates.map rateJson).toArray),
      ("pools", Json.mkObj [("oss", toJson (poolCredits .oss)), ("base", toJson (poolCredits .base))])]),
  line "constants" "the stop-rule limits" (Json.mkObj [])
    (Json.mkObj [("capMs", toJson capMs), ("queueMaxMs", toJson queueMaxMs), ("storageMaxMilli", toJson storageMaxMilli)]),
  line "jobMap" "GitHub job against CircleCI job" (Json.mkObj [])
    (Json.mkObj [("jobs", .arr (jobMap.map fun (l, g, c) =>
      Json.mkObj [("lane", .str l), ("github", .str g), ("circleci", .str c)]).toArray)])]

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

def mk (provider : Provider) (job sha : String) (c : Conclusion) (d : Option String) (cls : String) (q t : Nat) : Run :=
  ⟨provider, job, sha, c, d, cls, q, t⟩

def gh (job : String := "engine (chromium)") (sha : String := "abc1234") (c : Conclusion := .pass)
    (d : Option String := some "d1") (q : Nat := 4000) (t : Nat := 100000) : Run :=
  mk .github job sha c d "ubuntu-24.04-arm" q t

def cc (job : String := "engine (chromium)") (sha : String := "abc1234") (c : Conclusion := .pass)
    (d : Option String := some "d1") (cls : String := "arm.medium.gen2") (q : Nat := 9000) (t : Nat := 150000) : Run :=
  mk .circleci job sha c d cls q t

def compareCases : List (String × Run × Run) := [
  ("equal verdicts: no finding, ratio 1500, credits of 2.5 minutes", gh, cc),
  ("same duration: ratio exactly 1000", gh (t := 100000), cc (t := 100000)),
  ("CircleCI faster: ratio below 1000", gh (t := 100000), cc (t := 40000)),
  ("ratio rounds down", gh (t := 3), cc (t := 4)),
  ("GitHub took no time: no ratio", gh (t := 0), cc),
  ("conclusion differs: a finding", gh, cc (c := .fail)),
  ("pass against not-run: a finding", gh, cc (c := .notRun)),
  ("both fail with the same digest: no finding", gh (c := .fail), cc (c := .fail)),
  ("digest differs: a finding", gh, cc (d := some "d2")),
  ("one side has no digest: digests are not compared", gh (d := none), cc (d := some "d2")),
  ("both without digest: conclusions decide", gh (d := none), cc (d := none)),
  ("unknown CircleCI class: no credits", gh, cc (cls := "arm.small")),
  ("m4pro.medium: credits at 200 a minute", gh (job := "sim (original)") (t := 1200000),
    cc (job := "sim (original)") (cls := "m4pro.medium") (t := 600000)),
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

def text : String :=
  String.join (tables
    ++ creditCases.map (fun (n, c, d) =>
      line "credits" n (Json.mkObj [("class", .str c), ("durMs", toJson d)])
        (Json.mkObj [("credits", optNat (credits c d))]))
    ++ storageCases.map (fun (n, b, d) =>
      line "storage" n (Json.mkObj [("bytes", toJson b), ("days", toJson d)])
        (Json.mkObj [("milli", toJson (storageMilli b d))]))
    ++ compareCases.map (fun (n, g, c) =>
      line "compare" n (Json.mkObj [("github", runJson g), ("circleci", runJson c)]) (comparisonJson (compare g c)))
    ++ stopCases.map (fun (n, i) =>
      line "stop" n (stopInputJson i)
        (Json.mkObj [("stop", .bool (stop i)), ("reasons", .arr ((stops i).map fun s => Json.str (stopName s)).toArray)]))
    ++ routeCases.map (fun (n, i) =>
      line "route" n (routeInputJson i) (Json.mkObj [("provider", .str (providerName (route i)))])))

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
