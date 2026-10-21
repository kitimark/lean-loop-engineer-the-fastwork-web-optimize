# Land: why `fwcore build` takes 220 s on some lean changes

Task fwcore-rebuild-fanout. In run 39526074627 the land step `fwcore build` took 217 to 233 s in every leg on a small
lean change, although `setup-lean` restores the newest Lake cache entry. Status: cause CONFIRMED, fix TESTED (see the
last section).

## Per-land rebuild sets (MEASURED, CI logs of the suites-a leg, free arm runners)

`restored` is the cache key suffix the land restored and the main commit whose `lean.yml` writer saved it. `built` is
the number of modules Lake built in the leg (the `✔ [i/n] Built M` lines). `critical` is the longest import chain of
the built modules weighted by their CI times (`Fw.Ops.Rebuild.critical`).

| run | land | fwcore per leg | restored | changed | built | Fw.Wire.Obs | critical |
|---|---|---|---|---|---|---|---|
| 39527170212 | scoped-gap-did | 216 to 232 s | 2657fd21 (005142a1) | 11 | 49 | 174 s | 215 s |
| 39526074627 | graph-check-lean | 217 to 233 s | 2657fd21 (005142a1) | 10 | 48 | 182 s | 229 s |
| 39525208990 | ci-push-probe-inputs | 212 to 222 s | 2657fd21 (005142a1) | 9 | 47 | 176 s | 219 s |
| 39524537607 | run-cite-check | 20 to 23 s | 2657fd21 (005142a1) | 5 | 31 | no | 18 s |
| 39521836949 | spawn-write-overlap | 0 to 11 s | exact key | 0 | 0 | no | 0 s |
| 39517374255 | scoped-close-start-cause | 55 to 60 s | 05d10bb7 (4494ed9c) | 6 | 47 | no | 55 s |
| 39505889802 | land-phase1-slow | 33 to 34 s | ca3085ca (a145b9c9) | 5 | 36 | no | 32 s |
| 39481093650 | exit-scoped-inline | 230 to 245 s | 6fa0cd5b (3aa12c09) | 19 | 65 | 176 s | 223 s |
| 39542326806 | probe, control (no split) | 208 to 218 s | 9707e387 (5f856c49) | 1 | 39 | 173 s | 214 s |
| 39542291992 | probe, split | 41 to 45 s | 1be8291f (7237be53) | 1 | 38 | no | 41 s |

`changed` is the number of modules of the fwcore closure whose source differs between the restored entry's main commit
and the land's change commit. The two probe rows restored an entry saved by `lean.yml` on their own branch (last
section), so their `changed` is the probe edit only. The full rows, with Lake's import graph of each tree, are in
`packages/contracts/golden/ops/rebuild-facts.jsonl`; the Lean output is `rebuild.jsonl` next to it.

## Mechanism

1. Lake mixes into a module's trace its source (`Lake/Build/Module.lean:620@eb6cafb`) and, for each import of a file
   without the `module` keyword, the import's transitive trace and artifact hashes (`Module.lean:320-349`, used at
   `Module.lean:603`). No file in `lean/` uses `module`, so a changed olean changes the trace of every transitive
   importer. CONFIRMED.
2. `fetchCore` (`Module.lean:1063-1114`) rebuilds a module when its trace hash is neither the saved trace nor an entry
   of the artifact cache. CONFIRMED.
3. A land branch `ci/land-<task>-<sha7>` is new on every land, so `actions/cache` restores the newest entry of `main`
   (restore-keys prefix). Only `lean.yml` on a `main` push saves that entry. Every land until the next main push
   re-pays the whole diff since the entry was saved, not only its own change. MEASURED: 3 consecutive lands restored
   2657fd21 and each rebuilt `Fw.Wire.Obs` although none of their own diffs touched its cone.
4. The rebuild set is the import cone of `Main` intersected with the importers of the changed modules. `Fw.Ops.Rebuild`
   computes it on Lake's own graph (`lake query --json +M:imports`), and it equals the built set of all 8 lands and
   both probe runs. MEASURED (`rebuild golden check` in `lean/scripts/check.sh` fails on a difference).
5. The fan-out root of the fwcore closure is `Fw` (`Fw.lean`, 208 direct imports): `FwTest/Lease`, `FwTest/Golden` and
   `FwTest/Serve` import `Fw`, `FwTestMain` imports them, and `Main` imports `FwTestMain`. The closure is 308 of the
   project's modules.
6. The step time is the critical path, not the module count: one module, `Fw.Wire.Obs`, takes 174 to 182 s (its JSON
   round-trip theorems; a local profile put about 300 s in `refine` and `eqRefl`). `Fw.Wire.Obs` imports
   `Fw.Wire.Sched` for six JSON helpers, and `Fw.Wire.Sched` imports `Fw.Measure.Wire`, `Fw.Measure.SimPlan` and
   `Fw.Store.Layout`. A change in any of those puts `Fw.Wire.Obs` on the critical path. Its import cone was 55
   modules; it is 24 after the split below. MEASURED (critical path 215 to 229 s against steps of 212 to 245 s).

## Lean

`lean/Fw/Ops/Rebuild.lean`:

- `rebuildSet?_spec`: a computed set holds exactly the modules in the cone of the targets that import a changed module.
- `lake_rebuilds_in_changed_cone`: with traces built by the rule of point 1, a module rebuilt from an entry saved on
  another tree imports a module whose source changed (reuses `Fw.Ops.Cache.Rebuilds` and `afterBuild`).
- `trace_changes`: with a collision-free mix, a module above a changed source has a new trace.
- `critical_le_makespan`: no schedule that respects imports finishes the rebuild set before its critical path.

## The split

`Fw.Wire.SchedJson` holds the six helpers (`optS`, `strsD`, `ok_bind`, `mapM_rt`, `arrD_arr`, `strsD_rt`) and imports
only `Fw.Ops.Wire`. `Fw.Wire.Obs` imports it instead of `Fw.Wire.Sched`. On the 8 sampled lands the Lean model puts
`Fw.Wire.Obs` out of every rebuild set, and the critical path of the 4 slow lands falls from 215 to 229 s to 41 to
65 s (golden field `split`). The CI probe below MEASURED it on one pair of land runs.

## CI probe (MEASURED, one pair of land runs, free arm runners)

Both branches got the same edit in `Fw.Store.Layout` (one added theorem), in the cone of `Fw.Wire.Sched`, as in the
3 slow lands. Each branch was first pushed without the edit, so `lean.yml` saved an entry of that tree in the branch's
cache scope; the land run of the edit then restored that entry (`actions/cache` searches the branch scope before the
default branch). The control branch differs from the split branch only in `Fw.Wire.Obs` importing `Fw.Wire.Sched`.

| branch | seed run (entry saved) | land run | restored | built | `fwcore build` per leg | run wall |
|---|---|---|---|---|---|---|
| `ci/land-fanout-ctl` | 39541703711 | 39542326806 | 9707e387 | 39, `Fw.Wire.Obs` 173 s | 208 to 218 s | 493 s |
| `ci/land-fanout-split` | 39541692940 | 39542291992 | 1be8291f | 38, no `Fw.Wire.Obs` | 41 to 45 s | 305 s |

The Lean model matches both: the computed rebuild set equals the modules CI built in each run (golden rows
`probe-*`, `match: true`), and its `split` field for the control row (38 modules, critical path 40.5 s) predicts the
measured split run (38 modules, critical path 41.2 s). The step falls by 167 to 173 s per leg and the run by 188 s.

Accepted limits: one pair of runs; one kind of edit (a module in the `Fw.Wire.Sched` cone). An edit outside that cone
never rebuilt `Fw.Wire.Obs` and gains nothing. The first land after the split restores a `main` entry saved before it,
so it rebuilds `Fw.Wire.Obs` once (its imports changed); lands after the next `lean/`-changing `main` push gain.
The probe branches stay on origin as evidence; their edit commits are not for `main`.

## Follow-ups

- The proofs in `Fw.Wire.Obs` stay in the fwcore closure while `FwTest/{Lease,Golden,Serve}` import all of `Fw`.
  Narrowing those imports or moving the round-trip theorems to a proof-only module outside `Main`'s closure keeps
  them out of every land.
- A fresher main entry shrinks the cumulative diff: every main push that changes `lean/` saves one.
- `Fw.Ci.Telemetry` still imports `Fw.Wire.Sched` only for three of the helpers; it can import `Fw.Wire.SchedJson`.
- `lean/scripts/check-partial.sh` lists `Fw/Wire/Sched.lean` but not `Fw/Wire/SchedJson.lean`.
- The Lean module system (`module`) would let Lake stop at an unchanged interface (early cutoff, `Module.lean:336-344`).
