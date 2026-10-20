import Fw.Gate.Shard
import Fw.Gate.ShardObs
import Fw.Site.BreakpointMatrix
import Lean.Data.Json
/-!
# Golden vectors of the LPT shard plan (task `gate-shard-balance`)

`packages/contracts/golden/gate/shards.jsonl`: for each number of concurrent runs `r ∈ {1, 2, 3}` and free
runners `m ∈ {4, 8, 12, 20}`, the job counts `Fw.Gate.Shard.chooseK` picks with the measured costs
(`Fw.Gate.ShardCosts.measured`), and every job of `Fw.Gate.Shard.engPlan` with its probe ids, its whole sweeps and
its duration, plus Graham's bound and the simulated makespan of the pool. `.github/scripts/gate-jobs.mjs --params
measured` passes the jobs through unchanged (glue only); its test re-checks coverage and the bound.

Generated from Lean, never by hand:

```
cd lean && lake env lean --run scripts/ShardGolden.lean           # write the file
cd lean && lake env lean --run scripts/ShardGolden.lean --check   # fail if it is stale
```
-/
namespace Fw.Wire.Shard.Golden
open Lean Fw.Gate.Schedule Fw.Gate.Shard

/-- The probe ids of the matrix, in matrix order (124). -/
def ids : List String := Fw.Site.Breakpoints.matrix.map (·.id)

/-- The engine name of the workflow matrix. -/
def engName : Eng → String
  | .chromium => "chromium"
  | .webkit => "playwright-webkit"

/-- The jobs of one engine: engine, slot, job count, probe ids, sweep names, unit names, load and duration. -/
def engJobs (C : Costs) (e : Eng) (k : Nat) : List Json :=
  let T := C.of e
  let names := unitNames ids
  (engPlan T ids k).zipIdx.map fun (b, slot) =>
    let probes := b.filterMap (probeOf ids)
    let sweeps := (b.filterMap (sweepOf ids.length Sw.all)).map swName
    Json.mkObj [("engine", Json.str (engName e)), ("slot", (slot : Json)), ("k", (k : Json)),
      ("probes", Json.arr (probes.map Json.str).toArray), ("sweeps", Json.arr (sweeps.map Json.str).toArray),
      ("units", Json.arr ((b.map fun i => Json.str (names.getD i "")).toArray)),
      ("load", (load (unitCost T ids) b : Json)), ("ms", (T.setup + load (unitCost T ids) b : Json))]

/-- The cost table of one engine as JSON: setup, default and every entry. -/
def tableJson (T : EngCosts) : Json :=
  Json.mkObj [("setup", (T.setup : Json)), ("default", (dflt T.costs : Json)),
    ("costs", Json.mkObj (T.costs.map fun (n, c) => (n, (c : Json))))]

/-- One line: `r` runs on `m` free runners, with the chosen `k`, the jobs, Graham's bound and the simulated
makespan.
-/
def line (C : Costs) (m r : Nat) : Json :=
  let kk := chooseK C ids m r
  let ds := shardDurs C ids kk
  let mk := makespan m (copies r ds)
  Json.mkObj [
    ("name", Json.str s!"measured r={r} m={m}"), ("params", Json.str "measured"), ("m", (m : Json)), ("r", (r : Json)),
    ("k", Json.mkObj [("chromium", (kk.1 : Json)), ("playwright-webkit", (kk.2 : Json))]),
    ("jobs", Json.arr (engJobs C .chromium kk.1 ++ engJobs C .webkit kk.2).toArray),
    ("jobCount", (ds.length : Json)), ("sum", (ds.sum : Json)), ("max", (lmax ds : Json)),
    ("bound", (shardBound C ids m r kk : Json)), ("makespan", (mk : Json)),
    ("grahamOk", Json.bool (decide (m * mk ≤ shardBound C ids m r kk)))]

/-- The free-runner counts of the golden, as in `golden/gate/schedule.jsonl`. -/
def freeRunners : List Nat := [4, 8, 12, 20]

/-- The golden lines: the cost table, then one line per `m ∈ {4, 8, 12, 20}` and `r ∈ {1, 2, 3}`. -/
def cases (_ : Unit := ()) : List Json :=
  let C := Fw.Gate.ShardCosts.measured
  (Json.mkObj [("name", Json.str "costs"), ("source", Json.str Fw.Gate.ShardCosts.source),
      ("chromium", tableJson C.chromium), ("playwright-webkit", tableJson C.webkit)]) ::
    freeRunners.flatMap fun m => [1, 2, 3].map fun r => line C m r

/-- The golden file, relative to `lean/`. -/
def path : System.FilePath := ".." / "packages" / "contracts" / "golden" / "gate" / "shards.jsonl"

/-- Compare (or write) the golden file; returns 1 if it is stale. -/
def run (root : System.FilePath) (write : Bool) : IO Nat := do
  let text := String.join (cases.map fun j => j.compress ++ "\n")
  let p := root / path
  if write then
    IO.FS.writeFile p text
    IO.println s!"shard golden: {cases.length} lines written"
    return 0
  let cur ← try IO.FS.readFile p catch _ => pure ""
  if cur != text then
    IO.println s!"shard golden: {p} is stale (regenerate: cd lean && lake env lean --run scripts/ShardGolden.lean)"
    return 1
  IO.println s!"shard golden: {cases.length} lines, up to date"
  return 0

end Fw.Wire.Shard.Golden
