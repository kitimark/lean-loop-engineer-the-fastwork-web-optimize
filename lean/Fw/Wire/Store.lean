import Lean.Data.Json
import Fw.Store.Layout
import Fw.Store.Reduce
import Fw.Store.Ci
import Fw.Measure.Wire
import Fw.Ops.Wire
import Fw.Gate.Trajectory
import Fw.Wire.FlagKey
/-!
# JSON codecs and ops of `Fw.Store` (`store.*`)

Glue between `fwcore`'s JSON lines and `Fw.Store.Layout` / `Fw.Store.Reduce` (namespace
`Fw.Wire.Store`, so the math view treats it as wire code). Total decoders only (`Except String`);
no partial operations. Flags are strings `"part:variant"`; digests are lowercase hex strings
(sha256 is computed by the caller).

| op | request | reply |
|---|---|---|
| `store.plan` | `target` (`original` or `rewrite`), `preset`? (default `original`), `fw`? [`part:variant`], `engines` [name], `profile`? (default `swipe-v1`), `runs`? (default 3), `sha`, `images`? {engine: image}, `digests`? {engine: sha256 of the job key}, `present`? [digest] (objects/runs already in the store) | `problems` [string], `fw` (sorted), `jobs` [{engine, workflow, inputs {name: value}, key [[name, value]], image, blocked (string or null), digest?, cache?, manifest?}] |
| `store.gate` | `engines`? (`both`, `chromium` or `playwright-webkit`; default `both`), `preset`? (default empty = none), `fw`? [`part:variant`] | `problems` [string], `fw` (sorted), `job` (`null` when there are problems) {workflow, inputs {name: value}, blocked (string or null)} |
| `store.trajectory` | the `store.gate` fields and `widths`? (comma list of 390, 640, 641, 1280 without repeats; default empty = all four) | as `store.gate`, for `trajectory-probe.yml` (a refused widths list is a problem) |
| `store.manifest` | `manifest` {engine, target, preset, fw [`part:variant`], profile, gitSha, image, runId, entries [{name, digest, bytes}]} | `valid`, `problems`, `key` [[name, value]] (when the engine and the target are known), `paths` [object path per entry] (when valid) |
| `store.objectPath` | `digest` (64 hex) | `path` |
| `store.ciRun` | `run` {runId, workflowName, status, conclusion (null = empty), headSha, jobs [{name, conclusion (null = empty)}]}, `artifacts`? [{name, profile, image, search? (default empty), target?}] (the downloaded shard artifacts with their `counts.json` / `image-id.txt` facts; absent = the check before the download), `classes`? [dir under chromium-classes] (default empty) | `accept`, `refusals` [string], `targets` [{target, classes, shards [{artifact, dir}], meta? {engine, target, preset, fw, profile, gitSha, image, runId}, key? [[name, value]]}] (empty when refused; `meta`, `key` after the download) |
| `store.reduce` | `kMax`, `tMax`, `pxRel`? {num, den}, `arms` [{engine, base (≥ 2 runs), var (≥ 1 run)}], each run an array of frames or an object with `frames` | `noMoreWork`, `arms` [{engine, noMoreWork, failing [type], types [{type, class, ok}]}] |
-/
namespace Fw.Wire.Store
open Lean Fw.Store
open Fw.Wire.Measure (field opt str nat arr strs runFrames objOf)
open Fw.Wire.Ops (asStr natD)
open Fw.Measure

/-- The fields of a reply. -/
abbrev Reply := List (String × Json)

/-- A flag `"part:variant"` with exactly one colon; anything else becomes `("", s)`, which the id check then refuses. -/
def parseFlag (s : String) : String × String :=
  match s.splitOn ":" with
  | [a, b] => (a, b)
  | _ => ("", s)

def flagStr (p : String × String) : String := p.1 ++ ":" ++ p.2

def sortFlags (fw : List (String × String)) : List (String × String) := Fw.Wire.FlagKey.sortFlags fw

/-- A string-to-string object as pairs. -/
def pairsOf (k : String) : Json → Except String (List (String × String))
  | .obj kvs => kvs.toArray.toList.mapM fun ⟨n, v⟩ => do pure (n, ← asStr s!"{k}.{n}" v)
  | _ => .error s!"field {k}: expected an object"

/-- Name–value pairs as a JSON array of two-element arrays. -/
def pairsJson (ps : List (String × String)) : Json := .arr (ps.toArray.map fun p => .arr #[.str p.1, .str p.2])

/-- An optional object of strings (absent = empty). -/
def optPairs (j : Json) (k : String) : Except String (List (String × String)) :=
  match opt j k with
  | none => pure []
  | some v => pairsOf k v

/-- Decode a plan request. -/
def requestOf (req : Json) : Except String Request := do
  let preset ← match opt req "preset" with
    | none => pure defaultPreset
    | some j => asStr "preset" j
  let profile ← match opt req "profile" with
    | none => pure defaultProfile
    | some j => asStr "profile" j
  let fw ← match opt req "fw" with
    | none => pure []
    | some j => (← Fw.Wire.Ops.asArr "fw" j).toList.mapM fun x => do pure (parseFlag (← asStr "fw" x))
  pure { target := ← str req "target", preset := preset, fw := sortFlags fw, engines := ← strs req "engines", profile := profile,
         runs := ← natD req "runs" 3, sha := ← str req "sha", images := ← optPairs req "images" }

/-- Encode a job; `digest` is the hash the caller computed from the job's key (if any). -/
def jobJson (present : List String) (digest : Option String) (j : Job) : Json :=
  let base : Reply := [
    ("engine", .str j.engine.name), ("workflow", .str j.workflow),
    ("inputs", objOf (j.inputs.map fun p => (p.1, Json.str p.2))), ("key", pairsJson j.key),
    ("image", .str ((j.key.find? (·.1 == "image")).map (·.2) |>.getD "")),
    ("blocked", match j.blocked with | none => .null | some b => .str b)]
  let extra : Reply := match digest with
    | none => []
    | some d => [("digest", .str d), ("cache", .str (cacheOf (some d) present)), ("manifest", .str (manifestPath d))]
  Json.mkObj (base ++ extra)

/-- `store.plan`. -/
def opPlan (req : Json) : Except String Reply := do
  let q ← requestOf req
  let digests ← optPairs req "digests"
  let present ← match opt req "present" with
    | none => pure []
    | some j => (← Fw.Wire.Ops.asArr "present" j).toList.mapM (asStr "present")
  let jobs := plan q
  pure [("problems", .arr ((reqProblems q).toArray.map .str)),
        ("fw", .arr (q.fw.toArray.map fun p => .str (flagStr p))),
        ("jobs", .arr (jobs.toArray.map fun j => jobJson present ((digests.find? (·.1 == j.engine.name)).map (·.2)) j))]

/-- Decode a gate request. -/
def gateRequestOf (req : Json) : Except String GateRequest := do
  let engines ← match opt req "engines" with
    | none => pure "both"
    | some j => asStr "engines" j
  let preset ← match opt req "preset" with
    | none => pure ""
    | some j => asStr "preset" j
  let fw ← match opt req "fw" with
    | none => pure []
    | some j => (← Fw.Wire.Ops.asArr "fw" j).toList.mapM fun x => do pure (parseFlag (← asStr "fw" x))
  pure { engines := engines, preset := preset, fw := sortFlags fw }

/-- `store.gate`: the dispatch of the breakpoint-gate workflow. -/
def opGate (req : Json) : Except String Reply := do
  let g ← gateRequestOf req
  let ps := gateProblems g
  let job : Json := if ps.isEmpty then
      Json.mkObj [("workflow", .str Lane.breakpointGate.file),
        ("inputs", objOf (gateDispatchInputs g |>.map fun p => (p.1, Json.str p.2))),
        ("blocked", match gateBlocked g with | none => .null | some b => .str b)]
    else .null
  pure [("problems", .arr (ps.toArray.map .str)), ("fw", .arr (g.fw.toArray.map fun p => .str (flagStr p))), ("job", job)]

/-- `store.trajectory`: the dispatch of the trajectory-probe workflow. -/
def opTrajectory (req : Json) : Except String Reply := do
  let g ← gateRequestOf req
  let widths ← match opt req "widths" with
    | none => pure ""
    | some j => asStr "widths" j
  let ps := gateProblems g ++ (match Fw.Gate.Trajectory.pickWidths widths with
    | .refused => ["widths: not a comma list of 390, 640, 641, 1280 without repeats"]
    | .list _ => [])
  let job : Json := if ps.isEmpty then
      Json.mkObj [("workflow", .str Lane.trajectory.file),
        ("inputs", objOf ((trajectoryDispatchInputs g widths).map fun p => (p.1, Json.str p.2))),
        ("blocked", match trajectoryBlocked g with | none => .null | some b => .str b)]
    else .null
  pure [("problems", .arr (ps.toArray.map .str)), ("fw", .arr (g.fw.toArray.map fun p => .str (flagStr p))), ("job", job)]

/-- Decode a manifest. -/
def manifestOf (j : Json) : Except String Manifest := do
  let fw ← (← arr j "fw").toList.mapM fun x => do pure (parseFlag (← asStr "fw" x))
  let entries ← (← arr j "entries").toList.mapM fun e => do
    pure ({ name := ← str e "name", digest := ← str e "digest", bytes := ← nat e "bytes" } : Fw.Store.Entry)
  pure { engine := ← str j "engine", target := ← str j "target", preset := ← str j "preset", fw := fw, profile := ← str j "profile",
         gitSha := ← str j "gitSha", image := ← str j "image", runId := ← str j "runId", entries := entries }

/-- `store.manifest`. -/
def opManifest (req : Json) : Except String Reply := do
  let m ← manifestOf (← field req "manifest")
  let ps := m.problems
  let key : Reply := match m.req with
    | none => []
    | some r => [("key", pairsJson (keyPairs r))]
  let paths : Reply := if m.valid then [("paths", .arr (m.entries.toArray.map fun e => .str (objectPath e.digest)))] else []
  pure ([("valid", .bool m.valid), ("problems", .arr (ps.toArray.map .str))] ++ key ++ paths)

/-- `store.objectPath`. -/
def opObjectPath (req : Json) : Except String Reply := do
  let d ← str req "digest"
  if !isHex 64 d then throw "digest must be 64 lowercase hex digits"
  pure [("path", .str (objectPath d))]

/-- Encode a class. -/
def classJ : Class → Json
  | .deterministic => Json.mkObj [("class", .str "deterministic")]
  | .stable k t => Json.mkObj [("class", .str "stable"), ("k", toJson k), ("t", toJson t)]
  | .quarantined => Json.mkObj [("class", .str "quarantined")]

/-- `store.reduce`. -/
def opReduce (req : Json) : Except String Reply := do
  let p : Policy := ⟨← nat req "kMax", ← nat req "tMax"⟩
  let q : PxTol ← match opt req "pxRel" with
    | none => pure pxTolDefault
    | some j => pure ⟨← nat j "num", ← nat j "den"⟩
  if q.den = 0 then throw "pxRel.den must be at least 1"
  let arms ← (← arr req "arms").toList.mapM fun a => do
    let base ← (← arr a "base").toList.mapM runFrames
    let var ← (← arr a "var").toList.mapM runFrames
    if base.length < 2 then throw "arm base needs at least two runs"
    if var.isEmpty then throw "arm var needs at least one run"
    pure (← str a "engine", base, var)
  let rows := arms.map fun (e, base, var) =>
    let ok := reduceOk p q base var
    Json.mkObj [("engine", .str e), ("noMoreWork", .bool ok),
      ("failing", .arr ((failing p q base var).toArray.map .str)),
      ("types", .arr ((obsOf p q base var).toArray.map fun (k, o) =>
        Json.mkObj [("type", .str k), ("class", classJ o.cls), ("ok", .bool (typeOk o.cls o.base o.var))]))]
  let oks := arms.map fun (_, base, var) => reduceOk p q base var
  pure [("noMoreWork", .bool (overall oks)), ("arms", .arr rows.toArray)]

/-- A string field where absent or `null` means the empty string (gh reports an unfinished conclusion as `null` or `""`). -/
def strE (j : Json) (k : String) : Except String String :=
  match opt j k with
  | none => pure ""
  | some v => asStr k v

/-- Decode the run metadata of `store.ciRun`. -/
def ciRunOf (j : Json) : Except String CiRun := do
  let jobs ← (← arr j "jobs").toList.mapM fun x => do
    pure ({ name := ← str x "name", conclusion := ← strE x "conclusion" } : CiJob)
  pure { runId := ← str j "runId", workflow := ← str j "workflowName", status := ← str j "status",
         conclusion := ← strE j "conclusion", headSha := ← str j "headSha", jobs := jobs }

/-- Decode the facts of one downloaded shard artifact. -/
def shardFactsOf (j : Json) : Except String ShardFacts := do
  let target ← match opt j "target" with
    | none => pure none
    | some v => some <$> asStr "target" v
  pure { name := ← str j "name", profile := ← str j "profile", image := ← str j "image", search := ← strE j "search",
         target := target }

/-- Encode one store key of `store.ciRun`. -/
def ciTargetJson (r : CiRun) (c : CiTarget) : Json :=
  let base : Reply := [("target", .str c.target.name), ("classes", .str c.target.name),
    ("shards", .arr (c.shards.toArray.map fun s => Json.mkObj [("artifact", .str s.artifact), ("dir", .str s.dir)]))]
  let extra : Reply := match c.req with
    | none => []
    | some q => [
        ("meta", Json.mkObj [("engine", .str q.engine.name), ("target", .str q.target.name), ("preset", .str q.preset),
          ("fw", .arr (q.fw.toArray.map fun p => .str (flagStr p))), ("profile", .str q.profile), ("gitSha", .str q.sha),
          ("image", .str q.image), ("runId", .str r.runId)]),
        ("key", pairsJson (keyPairs q))]
  Json.mkObj (base ++ extra)

/-- `store.ciRun`. -/
def opCiRun (req : Json) : Except String Reply := do
  let r ← ciRunOf (← field req "run")
  let got ← match opt req "artifacts" with
    | none => pure none
    | some a => do
      let arts ← (← Fw.Wire.Ops.asArr "artifacts" a).toList.mapM shardFactsOf
      let classes ← match opt req "classes" with
        | none => pure []
        | some c => (← Fw.Wire.Ops.asArr "classes" c).toList.mapM (asStr "classes")
      pure (some ({ artifacts := arts, classes := classes } : Got))
  let res := ciRun r got
  pure [("accept", .bool res.refusals.isEmpty), ("refusals", .arr (res.refusals.toArray.map .str)),
        ("targets", .arr (res.targets.toArray.map (ciTargetJson r)))]

/-- The `store.*` ops. -/
def ops : List String := ["store.plan", "store.gate", "store.trajectory", "store.manifest", "store.objectPath", "store.reduce", "store.ciRun"]

/-- Dispatch a `store.*` op (`none` when the op is not one of them). -/
def handle (op : String) (req : Json) : Option (Except String Reply) :=
  match op with
  | "store.plan" => some (opPlan req)
  | "store.gate" => some (opGate req)
  | "store.trajectory" => some (opTrajectory req)
  | "store.manifest" => some (opManifest req)
  | "store.objectPath" => some (opObjectPath req)
  | "store.reduce" => some (opReduce req)
  | "store.ciRun" => some (opCiRun req)
  | _ => none

end Fw.Wire.Store
