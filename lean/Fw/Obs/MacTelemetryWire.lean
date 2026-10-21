import Lean.Data.Json
import Fw.Obs.MacTelemetry
import Fw.Ops.Wire
/-!
# macOS telemetry wire (task `macos-telemetry`): ops `obs.macSample`, `obs.macReduce`, `obs.macMatched`, `obs.macIs`

Glue between `fwcore`'s JSON lines and `Fw.Obs.MacTelemetry` (namespace `Fw.Wire.Obs.MacTelemetry`, wire code to the math
view). Total decoders only. Times are epoch ms.

| op | request | reply |
|---|---|---|
| `obs.macSample` | `cap`, `minRunMs`, `runs` [{wf, id, event, createdMs, startMs, endMs, concl}] | `ids` (the runs whose jobs are read, at most `cap`), `strata` [{key, candidates, picked}] |
| `obs.macReduce` | `fromMs`, `toMs`, `minRunMs`, `cap`, `runs` (as above), `jobs` [{prov, wf, run, name, runner?, event, createdMs, startMs, endMs, concl, steps? [{name, startMs, endMs}]}] | `windowMs`, `statedMs`, `tables` {runs, jobs, providers, classes, steps, cuts}, `cuts` [{id, title, savedMs, bound}] (ranked), `md` |
| `obs.macMatched` | `wallMs`, `steps` [{name, startMs, endMs}] | `matchedMs`, `unmatchedMs` |
| `obs.macIs` | `rows` [{wf, name}] | `mac` [bool, one per row] |
-/
namespace Fw.Wire.Obs.MacTelemetry
open Lean Fw.Wire.Ops Fw.Obs.MacTelemetry

/-- A step from `{name, startMs, endMs}`. -/
def stepOf (j : Json) : Except String Step := do
  pure { name := ← str j "name", startMs := ← nat j "startMs", endMs := ← nat j "endMs" }

/-- A step as `{name, startMs, endMs}`. -/
def stepJson (s : Step) : Json :=
  Json.mkObj [("name", .str s.name), ("startMs", toJson s.startMs), ("endMs", toJson s.endMs)]

/-- A run row. -/
def runOf (j : Json) : Except String Run := do
  pure { wf := ← str j "wf", id := ← str j "id", event := ← strD j "event" "", createdMs := ← nat j "createdMs",
         startMs := ← nat j "startMs", endMs := ← nat j "endMs", concl := ← strD j "concl" "" }

/-- A run row as JSON. -/
def runJson (r : Run) : Json :=
  Json.mkObj [("wf", .str r.wf), ("id", .str r.id), ("event", .str r.event), ("createdMs", toJson r.createdMs),
    ("startMs", toJson r.startMs), ("endMs", toJson r.endMs), ("concl", .str r.concl)]

/-- A job row. -/
def jobOf (j : Json) : Except String Job := do
  let p ← str j "prov"
  let some prov := Prov.ofTag p | throw s!"field prov: unknown provider {p}"
  let ss ← match opt j "steps" with
    | none => pure []
    | some v => (← asArr "steps" v).toList.mapM stepOf
  pure { prov, wf := ← str j "wf", run := ← str j "run", name := ← str j "name", runner := ← strD j "runner" "",
         event := ← strD j "event" "", createdMs := ← nat j "createdMs", startMs := ← nat j "startMs", endMs := ← nat j "endMs",
         concl := ← strD j "concl" "", steps := ss }

/-- A job row as JSON. -/
def jobJson (j : Job) : Json :=
  Json.mkObj [("prov", .str j.prov.tag), ("wf", .str j.wf), ("run", .str j.run), ("name", .str j.name), ("runner", .str j.runner),
    ("event", .str j.event), ("createdMs", toJson j.createdMs), ("startMs", toJson j.startMs), ("endMs", toJson j.endMs),
    ("concl", .str j.concl), ("steps", Json.arr (j.steps.map stepJson).toArray)]

/-- The window and rows of a reduce request. -/
def inputOf (req : Json) : Except String Input := do
  pure { fromMs := ← nat req "fromMs", toMs := ← nat req "toMs", minRunMs := ← natD req "minRunMs" 120000,
         cap := ← natD req "cap" 200, runs := (← (← arr req "runs").toList.mapM runOf),
         jobs := (← (← arr req "jobs").toList.mapM jobOf) }

/-- The `<!-- mt:begin -->` block of one table: the text the note embeds verbatim. -/
def block (name table : String) : String := s!"<!-- mt:begin {name} -->\n{table}\n<!-- mt:end {name} -->"

/-- The cut as JSON. -/
def cutJson (x : Cut) : Json :=
  Json.mkObj [("id", .str x.id), ("title", .str x.title), ("savedMs", toJson x.savedMs), ("bound", .str x.bound)]

/-- `obs.macReduce`. -/
def opReduce (req : Json) : Except String Reply := do
  let i ← inputOf req
  let c := Ctx.of i
  let ts := tables i
  pure [("windowMs", toJson i.winMs), ("statedMs", toJson (i.toMs - i.fromMs)),
        ("tables", Json.mkObj (ts.map fun (n, t) => (n, Json.str t))),
        ("cuts", Json.arr ((rankCuts c.cuts).map cutJson).toArray),
        ("md", .str ("\n\n".intercalate (ts.map fun (n, t) => block n t)))]

/-- `obs.macSample`. -/
def opSample (req : Json) : Except String Reply := do
  let cap ← natD req "cap" 200
  let minMs ← natD req "minRunMs" 120000
  let runs ← (← arr req "runs").toList.mapM runOf
  let ss := strataOf minMs runs
  let ids := pick cap ss
  pure [("ids", Json.arr (ids.map Json.str).toArray),
        ("strata", Json.arr (ss.map fun (k, xs) =>
          Json.mkObj [("key", .str k), ("candidates", toJson xs.length), ("picked", toJson (xs.filter (ids.contains ·)).length)]).toArray)]

/-- `obs.macMatched`. -/
def opMatched (req : Json) : Except String Reply := do
  let wall ← nat req "wallMs"
  let ss ← (← arr req "steps").toList.mapM stepOf
  pure [("matchedMs", toJson (matchedMs wall ss)), ("unmatchedMs", toJson (unmatchedMs ss))]

/-- `obs.macIs`. -/
def opIs (req : Json) : Except String Reply := do
  let rows ← (← arr req "rows").toList.mapM fun r => do pure (isMacJob (← str r "wf") (← str r "name"))
  pure [("mac", Json.arr (rows.map Json.bool).toArray)]

/-- The ops of this module. -/
def ops : List String := ["obs.macSample", "obs.macReduce", "obs.macMatched", "obs.macIs"]

/-- Dispatch one of the ops (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "obs.macSample" => some (opSample req)
  | "obs.macReduce" => some (opReduce req)
  | "obs.macMatched" => some (opMatched req)
  | "obs.macIs" => some (opIs req)
  | _ => none

/-! ## Golden cases -/

/-- The base time of the cases: 2025-10-09 08:53:20 UTC in ms. -/
def t0 : Nat := 1760000000000

/-- A step row. -/
def stp (name : String) (s e : Nat) : Step := { name, startMs := s, endMs := e }

/-- The steps of a sim job from `s` on: the given (name, seconds) one after the other. -/
def stepsFrom (s : Nat) : List (String × Nat) → List Step
  | [] => []
  | (n, d) :: rest => stp n s (s + d * 1000) :: stepsFrom (s + d * 1000) rest

/-- The steps of a typical sim job. -/
def simSteps : List (String × Nat) :=
  [("Set up job", 5), ("Run actions/checkout@abc", 10), ("Boot the Simulator (kept booted for the whole job)", 60),
   ("Determinism sessions", 300), ("Run actions/upload-artifact@abc", 8), ("Run ./.github/actions/telemetry", 20),
   ("Delete the Simulator device", 15), ("Post Run actions/checkout@abc", 3), ("Complete job", 1)]

/-- A GitHub run of workflow `wf`, created at `c`, started at `c + 1 s`, `d` s long. -/
def runRow (wf id event concl : String) (c d : Nat) : Run :=
  { wf, id, event, createdMs := c, startMs := c + 1000, endMs := c + 1000 + d * 1000, concl }

/-- A GitHub job. -/
def ghJob (wf run name event concl : String) (created s e : Nat) (ss : List Step := []) : Job :=
  { prov := .github, wf, run, name, runner := "", event, createdMs := created, startMs := s, endMs := e, concl, steps := ss }

/-- The rows of a webkit-sim run: a 20 s `plan` job, then `sim` for the steps (or `simS` seconds with no step). -/
def simRun (id event concl : String) (c : Nat) (sim : List (String × Nat)) : List Job :=
  let s := c + 31000
  let ss := stepsFrom s sim
  let e := (ss.getLast?.map (·.endMs)).getD (s + 1000)
  [ghJob "webkit-sim" id "plan" event "success" c (c + 1000) (c + 21000), ghJob "webkit-sim" id "sim" event concl c s e ss]

/-- Steps of the sim of a failing run: the sim steps then a long hang in the measure step. -/
def hangSteps : List (String × Nat) :=
  [("Set up job", 5), ("Boot the Simulator (kept booted for the whole job)", 60), ("Determinism sessions", 1200)]

/-- Three good sim runs and one failing run, one short run: all in the first hours of the day. -/
def rowsA : List Run × List Job :=
  let c1 := t0
  let c2 := t0 + 7200000
  let c3 := t0 + 10800000
  let c4 := t0 + 14400000
  ([runRow "webkit-sim" "r1" "workflow_dispatch" "success" c1 440, runRow "webkit-sim" "r2" "push" "success" c2 440,
    runRow "webkit-sim" "r3" "push" "success" c3 450, runRow "webkit-sim" "r4" "push" "failure" c4 1300,
    runRow "webkit-sim" "r5" "push" "success" (t0 + 18000000) 30],
   simRun "r1" "workflow_dispatch" "success" c1 simSteps ++ simRun "r2" "push" "success" c2 simSteps ++
   simRun "r3" "push" "success" c3 simSteps ++ simRun "r4" "push" "failure" c4 hangSteps)

/-- A Codemagic build and a CircleCI job of the same day. -/
def otherRows : List Job :=
  [{ prov := .codemagic, wf := "webkit-sim", run := "cm1", name := "sim", runner := "mac_mini_m2", event := "push",
     createdMs := t0 + 20000000, startMs := t0 + 20030000, endMs := t0 + 20030000 + 240000, concl := "finished",
     steps := stepsFrom (t0 + 20030000) [("Preparing build machine", 20), ("Fetching app sources", 10),
       ("Boot the Simulator", 40), ("determinism sessions", 150), ("Publishing", 5), ("Cleaning up", 3)] },
   { prov := .circleci, wf := "webkit-sim", run := "cc1", name := "sim", runner := "m4pro.medium", event := "push",
     createdMs := t0 + 21000000, startMs := t0 + 21010000, endMs := t0 + 21010000 + 200000, concl := "success",
     steps := stepsFrom (t0 + 21010000) [("Spin up environment", 10), ("Checkout code", 5), ("boot the Simulator", 40),
       ("determinism session", 120), ("Uploading artifacts", 4)] }]

/-- A reduce request. -/
def reduceReq (fromMs toMs : Nat) (runs : List Run) (jobs : List Job) (cap : Nat := 200) : Json :=
  Json.mkObj [("op", .str "obs.macReduce"), ("fromMs", toJson fromMs), ("toMs", toJson toMs), ("minRunMs", toJson 120000),
    ("cap", toJson cap), ("runs", Json.arr (runs.map runJson).toArray), ("jobs", Json.arr (jobs.map jobJson).toArray)]

/-- A sample request: `n` push runs and `d` dispatched runs of a workflow, 5 minutes apart, all 300 s long. -/
def sampleReq (cap n d : Nat) : Json :=
  let mk (e : String) (k : Nat) := runRow "wktr" s!"{e}{k}" e "success" (t0 + k * 300000) 300
  Json.mkObj [("op", .str "obs.macSample"), ("cap", toJson cap), ("minRunMs", toJson 120000),
    ("runs", Json.arr (((List.range n).map (mk "push") ++ (List.range d).map (mk "workflow_dispatch")).map runJson).toArray)]

/-- The cases: name, request. -/
def cases (_ : Unit := ()) : List (String × Json) :=
  let (runsA, jobsA) := rowsA
  [("three good sim runs and a failing one, Linux plan jobs, a short run, a window of one day: all candidates read, weight 1000",
      reduceReq t0 (t0 + 86400000) runsA jobsA),
   ("the same rows with Codemagic and CircleCI jobs: the provider and class tables fill",
      reduceReq t0 (t0 + 86400000) runsA (jobsA ++ otherRows)),
   ("the data starts two hours into the stated window: the window is the first row to the end",
      reduceReq (t0 - 7200000) (t0 + 86400000) runsA jobsA),
   ("a cap of 2 over 20 push and 4 dispatched runs: both strata get a pick, at most 2 in all",
      sampleReq 2 20 4),
   ("a cap of 10 over 6 push and 2 dispatched runs: all 8 are read", sampleReq 10 6 2),
   ("a cap of 12 over 40 push and 4 dispatched runs: the dispatched stratum is not starved",
      sampleReq 12 40 4),
   ("matched time: a 100 s job with 10 s upload, 20 s telemetry and 5 s post steps is 65 s matched",
      Json.mkObj [("op", .str "obs.macMatched"), ("wallMs", toJson 100000),
        ("steps", Json.arr ((stepsFrom t0 [("Run actions/upload-artifact@x", 10), ("Run ./.github/actions/telemetry", 20),
          ("Post Run actions/checkout@x", 5), ("Determinism sessions", 60)]).map stepJson).toArray)]),
   ("matched time: steps longer than the wall time leave 0 matched, not a wrap-around",
      Json.mkObj [("op", .str "obs.macMatched"), ("wallMs", toJson 10000),
        ("steps", Json.arr ((stepsFrom t0 [("Run actions/upload-artifact@x", 30)]).map stepJson).toArray)]),
   ("which GitHub jobs run on macOS",
      Json.mkObj [("op", .str "obs.macIs"), ("rows", Json.arr #[
        Json.mkObj [("wf", .str "webkit-sim"), ("name", .str "sim")],
        Json.mkObj [("wf", .str "webkit-sim"), ("name", .str "guard")],
        Json.mkObj [("wf", .str "trajectory-probe"), ("name", .str "probe apple")],
        Json.mkObj [("wf", .str "trajectory-probe"), ("name", .str "probe chromium 390")],
        Json.mkObj [("wf", .str "wktr"), ("name", .str "wktr")]])]),
   ("a job from an unknown provider is refused",
      Json.mkObj [("op", .str "obs.macReduce"), ("fromMs", toJson t0), ("toMs", toJson (t0 + 1000)), ("runs", Json.arr #[]),
        ("jobs", Json.arr #[Json.mkObj [("prov", .str "jenkins"), ("wf", .str "x"), ("run", .str "1"), ("name", .str "a"),
          ("createdMs", toJson 0), ("startMs", toJson 0), ("endMs", toJson 0)]])])]

/-- The reply of one request: the op's reply fields, or its error. -/
def replyJson (req : Json) : Json :=
  let op := (req.getObjValAs? String "op").toOption.getD ""
  match handle op req with
  | some (.ok f) => Json.mkObj f
  | some (.error e) => Json.mkObj [("error", .str e)]
  | none => Json.mkObj [("error", .str s!"unknown op {op}")]

/-- The golden file text: one `{name, request, response}` line per case. -/
def goldenText (_ : Unit := ()) : String :=
  String.join (cases.map fun (n, rq) => (Json.mkObj [("name", .str n), ("request", rq), ("response", replyJson rq)]).compress ++ "\n")

/-- Where the golden lives, relative to `lean/`. -/
def goldenPath : System.FilePath := "../packages/contracts/golden/obs/mactelemetry.jsonl"

/-- Write the golden. -/
def writeGolden : IO Unit := do
  IO.FS.createDirAll "../packages/contracts/golden/obs"
  IO.FS.writeFile goldenPath goldenText

/-- The collected window: one `{kind: window}` line, then `{kind: run}` and `{kind: job}` lines. -/
def datasetPath : System.FilePath := "../packages/contracts/golden/obs/mactelemetry-window-input.jsonl"

/-- The reduced window (the tables and cuts of the dataset). -/
def reportPath : System.FilePath := "../packages/contracts/golden/obs/mactelemetry-window-report.json"

/-- The reduce request of a dataset text. -/
def datasetReq (text : String) : Except String Json := do
  let lines := (text.splitOn "\n").filter (· != "")
  let rows ← lines.mapM fun l => Json.parse l
  let kind (r : Json) : String := (r.getObjValAs? String "kind").toOption.getD ""
  let win ← match rows.find? (kind · == "window") with
    | some w => pure w
    | none => throw "no window line"
  let pick (k : String) := rows.filter (kind · == k)
  pure (Json.mkObj [("op", .str "obs.macReduce"), ("fromMs", ← field win "fromMs"), ("toMs", ← field win "toMs"),
    ("minRunMs", ← field win "minRunMs"), ("cap", ← field win "cap"), ("runs", Json.arr (pick "run").toArray),
    ("jobs", Json.arr (pick "job").toArray)])

/-- The report text of a dataset text: the reduce reply without the Markdown (the tables are in it). -/
def reportText (text : String) : Except String String := do
  let req ← datasetReq text
  let f ← opReduce req
  pure ((Json.mkObj (f.filter fun kv => kv.1 != "md")).compress ++ "\n")

/-- Write the report of the committed dataset. -/
def writeReport : IO Unit := do
  match reportText (← IO.FS.readFile datasetPath) with
  | .ok t => IO.FS.writeFile reportPath t
  | .error e => throw (IO.userError e)

/-- Whether the golden file is the Lean output, and (when the dataset is committed) the report is the reduction of it. -/
def checkGolden : IO Bool := do
  let g := (← IO.FS.readFile goldenPath) == goldenText
  if !(← datasetPath.pathExists) then return g
  match reportText (← IO.FS.readFile datasetPath) with
  | .ok t => return g && (← reportPath.pathExists) && (← IO.FS.readFile reportPath) == t
  | .error _ => return false

private def fieldOf (r : Json) (k : String) : Json := (r.getObjVal? k).toOption.getD .null

private def caseReply (i : Nat) : Json := replyJson (cases[i]!).2

-- reduce: a window of one day from the first run, so a per-day number is the total
#guard fieldOf (caseReply 0) "windowMs" == toJson 86400000
#guard fieldOf (caseReply 0) "statedMs" == toJson 86400000
-- the window opens at the first row when the stated start is earlier: 2 h earlier than the data, the data is 1 day long
#guard fieldOf (caseReply 2) "windowMs" == toJson 86400000
#guard fieldOf (caseReply 2) "statedMs" == toJson (86400000 + 7200000)
-- the cap of 2: two picks, one per stratum
#guard (fieldOf (caseReply 3) "ids").compress == "[\"push0\",\"workflow_dispatch0\"]"
-- a cap that covers all candidates reads all of them
#guard (match fieldOf (caseReply 4) "ids" with | .arr a => a.size == 8 | _ => false)
-- the dispatched stratum is not starved at cap 12
#guard (match fieldOf (caseReply 5) "ids" with
  | .arr a => a.size ≤ 12 && a.any (fun j => j == Json.str "workflow_dispatch0") | _ => false)
-- matched time
#guard fieldOf (caseReply 6) "matchedMs" == toJson 65000
#guard fieldOf (caseReply 6) "unmatchedMs" == toJson 35000
#guard fieldOf (caseReply 7) "matchedMs" == toJson 0
#guard (fieldOf (caseReply 8) "mac").compress == "[true,false,true,false,true]"
#guard (fieldOf (caseReply 9) "error") == Json.str "field prov: unknown provider jenkins"

end Fw.Wire.Obs.MacTelemetry
