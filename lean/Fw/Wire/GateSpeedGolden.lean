import Fw.Gate.Schedule
import Fw.Ops.Cache
import Lean.Data.Json
/-!
# Golden vectors of the gate job split and of the cache keys (task `gate-speed-ci`)

* `packages/contracts/golden/gate/schedule.jsonl`: the Lean split of `Fw.Gate.Schedule` (`choose`) for
  three time sets (`base`, `cached`, `reduced`) and 1, 2, 3 concurrent runs, with the jobs, the Graham
  bound and the simulated makespan. `.github/scripts/gate-jobs.mjs` builds the workflow matrix from
  these lines, and its test re-checks every line (coverage of probes and sweeps, the bound).
* `packages/contracts/golden/ops/cache.jsonl`: the declared inputs of every cache of the gate and the
  canonical key string `Fw.Ops.Cache.key` gives for example worlds (`key_complete`: changing one
  declared input changes it; `key_congr`: changing an undeclared one does not), plus a replayed
  `runAll` trace (hit or miss per run). `.github/scripts/cache-key.mjs` computes the same strings.

Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/GateSpeedGolden.lean           # write the files
cd lean && lake env lean --run scripts/GateSpeedGolden.lean --check   # fail if a file is stale
```
-/
namespace Fw.Wire.GateSpeed.Golden
open Lean Fw.Gate.Schedule

/-- The shared pool of the free plan: 20 concurrent jobs for the whole account. -/
def poolM : Nat := 20

def engName : Eng → String
  | .chromium => "chromium"
  | .webkit => "playwright-webkit"

def swName : Sw → String
  | .desktop => "desktop"
  | .phone => "phone"
  | .touch => "touch"
  | .pain => "pain"

def modeName : Mode → String
  | .sep => "sep"
  | .deskSep => "deskSep"
  | .inline => "inline"

def cfgJson (c : Cfg) : Json :=
  Json.mkObj [("k", (c.k : Json)), ("mode", Json.str (modeName c.md))]

def epJson (p : EngParams) : Json :=
  Json.mkObj [("setup", (p.setup : Json)), ("perProbe", (p.perProbe : Json)),
    ("sweeps", Json.mkObj [("desktop", (p.desktop : Json)), ("phone", (p.phone : Json)),
      ("touch", (p.touch : Json)), ("pain", (p.pain : Json))])]

/-- The jobs of a plan with the engine-local slot of each (probe job `i` takes the probes whose matrix index is
`≡ i mod k`; the extra sweep job has slot `k` and no probes). -/
def jobsJson (P : Params) (pl : Plan) : Json :=
  let one (e : Eng) (c : Cfg) : List Json :=
    (jobsOf e probesPerEngine c.k c.md).zipIdx.map fun (j, i) =>
      Json.mkObj [("engine", Json.str (engName e)), ("slot", (i : Json)), ("k", (c.k : Json)),
        ("probes", (j.probes : Json)), ("sweeps", Json.arr ((j.sweeps.map swName).map Json.str).toArray),
        ("ms", (j.dur P : Json))]
  Json.arr ((one .chromium pl.1 ++ one .webkit pl.2).toArray)

/-- The runners free for the run: the 20 of the pool minus what other runs hold. -/
def freeRunners : List Nat := [4, 8, 12, 20]

/-- The job before the gate (plan folded into the site job) and the job after (one merge job, both engines). -/
def preMs : Nat := noteFixed.plan + noteFixed.site
def postMs : Nat := noteFixed.mergeSetup + noteFixed.fwcore + 2 * noteFixed.summary

/-- One summary of a plan under `P`, `m` free runners, `r` runs: the jobs, `Σ d`, `max d`, the Graham numerator, the
simulated makespan of `r` copies of the job list, and the wall time `wall` with its two bounds (`wall_lower`,
`wall_upper`). -/
def planJson (P : Params) (m r : Nat) (pl : Plan) : Json :=
  let ds := durs P pl
  let mk := makespan m (copies r ds)
  let w := wall preMs postMs m r ds
  let wLo := preMs + postMs + max (lmax ds) ((r * ds.sum + m - 1) / m)
  Json.mkObj [
    ("plan", Json.mkObj [("chromium", cfgJson pl.1), ("webkit", cfgJson pl.2)]),
    ("jobs", jobsJson P pl), ("jobCount", (ds.length : Json)),
    ("sum", (ds.sum : Json)), ("max", (lmax ds : Json)),
    ("bound", (bound P m r pl : Json)), ("makespan", (mk : Json)),
    ("grahamOk", Json.bool (decide (m * mk ≤ bound P m r pl))),
    ("wall", (w : Json)), ("wallLo", (wLo : Json)),
    ("wallOk", Json.bool (decide (wLo ≤ w ∧ m * w ≤ m * (preMs + postMs) + bound P m r pl)))]

def paramSets : List (String × Params) := [("base", noteBase), ("cached", noteCached), ("reduced", noteReduced)]

/-- The fixed jobs around the gate before and after folding the plan into the site job and merging once. -/
def fixedJson : Json :=
  let F := noteFixed
  Json.mkObj [
    ("plan", (F.plan : Json)), ("site", (F.site : Json)), ("mergeSetup", (F.mergeSetup : Json)),
    ("fwcore", (F.fwcore : Json)), ("summary", (F.summary : Json)),
    ("oldJobs", Json.arr (F.oldJobs.map fun (x : Nat) => Json.num x).toArray), ("newJobs", Json.arr (F.newJobs.map fun (x : Nat) => Json.num x).toArray),
    ("oldWork", (F.oldJobs.sum : Json)), ("newWork", (F.newJobs.sum : Json)),
    ("pre", (preMs : Json)), ("post", (postMs : Json))]

/-- The cases of `schedule.jsonl`: time set x free runners x concurrent runs. -/
def scheduleCases : List Json :=
  paramSets.flatMap fun (nm, P) => freeRunners.flatMap fun m => [1, 2, 3].map fun r =>
    let c := choose P m r
    Json.mkObj [
      ("name", Json.str s!"{nm} r={r} m={m}"), ("params", Json.str nm), ("m", (m : Json)), ("r", (r : Json)),
      ("times", Json.mkObj [("chromium", epJson P.chromium), ("playwright-webkit", epJson P.webkit)]),
      ("fixed", fixedJson),
      ("chosen", planJson P m r c), ("current", planJson P m r current),
      ("neverWorse", Json.bool (decide (bound P m r c ≤ bound P m r current)))]

/-! ## Cache keys -/

open Fw.Ops.Cache

/-- The canonical serialisation of a declared-input vector (the string `cache-key.mjs` hashes with SHA-256).
No name contains `=` and no name or value contains a newline (`cache-key.mjs` rejects them), so the vector is
recovered by splitting each line at its first `=`: the serialisation is injective (for a fixed list of names). -/
def canon (v : List (String × String)) : String :=
  "\n".intercalate (v.map fun (n, x) => n ++ "=" ++ x)

/-- A world given as an association list (unlisted names are the empty string). -/
def envOf (kvs : List (String × String)) : Env := fun n => (kvs.lookup n).getD ""

structure CacheDef where
  name : String
  prefixOf : String
  decl : List String
  base : List (String × String)
  /-- an undeclared name that varies between runs -/
  noise : List (String × String)
deriving Inhabited

def baseWorld : List (String × String) :=
  [("playwright", "1.64.1"), ("os", "ubuntu24"), ("image", "20261012.1"), ("arch", "ARM64"), ("engine", "playwright-webkit"),
   ("hsVersion", "156.0.8078.4"), ("hsSha256", "81ab9d4d3c301dc5fdfb6c541b9e6632b16fc819a6a854460f40a76fe2b2c476")]

/-- The caches of the gate-engine action: their declared inputs. The runner image version (`ImageVersion`) is not declared (task
land-legs-followups): the fleet runs two image versions at once, so a key naming it made `main`'s seed miss for the runs on the
other one (MEASURED, run ids in docs/team/handoffs/land-legs-followups.md). The Ubuntu release (`ImageOS`, `os`) stays declared:
playwright-core downloads a different WebKit build per Ubuntu release (`webkit-ubuntu-22.04-arm64.zip` vs `-24.04-`, coreBundle.js
in 1.64.1) into a directory named by revision only. Premises: the browser directory depends on the Playwright version, the
architecture, the engine and the Ubuntu release; the apt cache holds `.deb` files that apt checks against its index (version and
hash), so a file of another image version is ignored, never installed. -/
def caches : List CacheDef := [
  { name := "browsers", prefixOf := "gate-pw-browsers", decl := ["playwright", "os", "arch", "engine"],
    base := baseWorld, noise := [("runId", "39070000001"), ("branch", "ci/other"), ("image", "20261101.1")] },
  { name := "apt-debs", prefixOf := "gate-apt-debs", decl := ["playwright", "os", "arch", "engine"],
    base := baseWorld, noise := [("runId", "39070000002"), ("image", "20261101.1")] },
  { name := "hs-zip", prefixOf := "gate-hs-zip", decl := ["hsVersion", "hsSha256", "arch"],
    base := baseWorld, noise := [("runId", "39070000003"), ("engine", "chromium")] }]

def setKv (kvs : List (String × String)) (n x : String) : List (String × String) :=
  (n, x) :: kvs.filter (·.1 != n)

def cacheLine (nm : String) (c : CacheDef) (kvs : List (String × String)) (extra : List (String × Json)) : Json :=
  let e := envOf kvs
  Json.mkObj ([("name", Json.str nm), ("cache", Json.str c.name), ("prefix", Json.str c.prefixOf),
    ("decl", Json.arr (c.decl.map Json.str).toArray),
    ("env", Json.mkObj (kvs.map fun (n, x) => (n, Json.str x))),
    ("canonical", Json.str (canon (declared c.decl e)))] ++ extra)

/-- Cases per cache: the base world, one world per declared input that differs only there (the canonical string
differs: `key_complete`), and one with undeclared inputs changed (the string is equal: `key_congr`). -/
def cacheCases : List Json :=
  caches.flatMap fun c =>
    let b := cacheLine s!"{c.name}: base world" c c.base [("role", Json.str "base")]
    let ds := c.decl.map fun n =>
      cacheLine s!"{c.name}: {n} changes" c (setKv c.base n (s!"changed-{n}"))
        [("role", Json.str "declaredChange"), ("changed", Json.str n)]
    let nz := cacheLine s!"{c.name}: undeclared inputs change" c (c.noise.foldl (fun a (n, x) => setKv a n x) c.base)
      [("role", Json.str "undeclaredChange")]
    b :: ds ++ [nz]

/-- A run replayed through one cache: the worlds of five workflow runs of the browsers cache (playwright bumped
once, the runner image once, then the old world again) and what `runAll` does. The result of a check is
the triple (playwright, os, arch) it ran in; the image version is not declared, so a bumped image is a hit. -/
def traceWorlds : List (String × List (String × String)) :=
  let b := baseWorld
  [("run 1: empty cache, miss", b),
   ("run 2: same world, hit", setKv b "runId" "2"),
   ("run 3: playwright bumped, miss", setKv b "playwright" "1.65.0"),
   ("run 4: runner image bumped, still a hit", setKv b "image" "20261101.1"),
   ("run 5: back to the first world, hit", setKv b "runId" "5"),
   ("run 6: Ubuntu release changed, miss", setKv b "os" "ubuntu26")]

def traceLines : List Json :=
  let c := caches.headD default
  let run : Env → String := fun e => e "playwright" ++ "@" ++ e "os" ++ "@" ++ e "arch"
  let h : List (String × String) → String := canon
  let step := fun (acc : Cache String String × List Json) (w : String × List (String × String)) =>
    let e := envOf w.2
    let (r, c') := getOrRun h c.decl run acc.1 e
    let hit := c'.length == acc.1.length
    (c', acc.2 ++ [Json.mkObj [("name", Json.str w.1), ("cache", Json.str c.name), ("role", Json.str "trace"),
      ("env", Json.mkObj (w.2.map fun (n, x) => (n, Json.str x))), ("hit", Json.bool hit), ("result", Json.str r),
      ("fresh", Json.str (run e)), ("entries", (c'.length : Json))]])
  (traceWorlds.foldl step ([], [])).2

/-- The text of one golden file. -/
def lines (cs : List Json) : String := String.join (cs.map fun j => j.compress ++ "\n")

def files : List (String × String × List Json) :=
  [("gate", "schedule", scheduleCases), ("ops", "cache", cacheCases ++ traceLines)]

def dir : System.FilePath := ".." / "packages" / "contracts" / "golden"

/-- Compare (or write) both golden files; returns the number of stale files. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let mut stale := 0
  for (sub, stem, cs) in files do
    let d := root / dir / sub
    let p := d / s!"{stem}.jsonl"
    let text := lines cs
    if write then
      IO.FS.createDirAll d
      IO.FS.writeFile p text
    else
      let cur ← try IO.FS.readFile p catch _ => pure ""
      if cur != text then
        IO.println s!"gate-speed golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/GateSpeedGolden.lean)"
        stale := stale + 1
  let n := files.foldl (fun a c => a + c.2.2.length) 0
  IO.println s!"gate-speed golden: {files.length} files, {n} cases, {if write then "written" else s!"{stale} stale"}"
  return stale

end Fw.Wire.GateSpeed.Golden
