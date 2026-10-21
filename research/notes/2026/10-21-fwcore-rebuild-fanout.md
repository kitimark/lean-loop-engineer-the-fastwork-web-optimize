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

`changed` is the number of modules of the fwcore closure whose source differs between the restored entry's main commit
and the land's change commit. The full rows, with Lake's import graph of each tree, are in
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
   computes it on Lake's own graph (`lake query --json +M:imports`), and it equals the built set of all 8 lands.
   MEASURED (`rebuild golden check` in `lean/scripts/check.sh` fails on a difference).
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
65 s (golden field `split`). INFERRED until the CI probe below.

CI probe: PENDING.

## Follow-ups

- The proofs in `Fw.Wire.Obs` stay in the fwcore closure while `FwTest/{Lease,Golden,Serve}` import all of `Fw`.
  Narrowing those imports or moving the round-trip theorems to a proof-only module outside `Main`'s closure keeps
  them out of every land.
- A fresher main entry shrinks the cumulative diff: every main push that changes `lean/` saves one.
- `Fw.Ci.Telemetry` still imports `Fw.Wire.Sched` only for three of the helpers; it can import `Fw.Wire.SchedJson`.
- `lean/scripts/check-partial.sh` lists `Fw/Wire/Sched.lean` but not `Fw/Wire/SchedJson.lean`.
- The Lean module system (`module`) would let Lake stop at an unchanged interface (early cutoff, `Module.lean:336-344`).
