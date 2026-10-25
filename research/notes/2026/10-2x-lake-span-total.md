# The dry land's outer spans carry the lake member, so a rebuild is not judged against no-op dry lands

Status: CONFIRMED (code, Lean proofs, a real span line), the three incident durations MEASURED (`.fw-console/timings.jsonl`),
the module counts of the 46.3 s and 35.8 s samples INFERRED (not recorded).

## Answer

- The three `timing.slow` alerts of 2026-10-25 (46323 ms at 29bdbda, 35755 ms at 6df9009, 67391 ms at 231d867, each against
  a p50 near 23.3 s) were false: each dry land followed a land that changed `lean/Fw`, so its checks rebuilt modules, but the
  outer spans `fw land` / `dry total lake` and `fw` / `slot run land pnpm fw land dry` had no `lake` member and so no `mods`
  work dimension. Only the inner `land dry lake` span had one (`lake.built` 41 on the 67391 ms land, MEASURED).
- Both outer spans now carry `lake.built`: the sum, over the checks the dry land ran, of the modules each built.
- Lean `Fw.Obs.Timing`: `outerBuilt` (the sum), `outerBuilt_eq_zero`, `maxBuilt_le_outerBuilt`, `outer_rebuild_noBaseline`
  (an outer sample whose checks built a module has a mods class above 0 and, against a class-0 history, is `noBaseline`, never
  `slow`; it reuses `judgeQ_rebuild_noBaseline`) and `incident_outer_not_slow` (the three durations on both outer steps, any
  build list with a positive entry, so every total b > 0, any class-0 history).
- Golden: `golden/obs/timing-outer.jsonl` (sum and class rows, replayed by `timing-work.test.ts`) and three rows in
  `golden/obs/timing.jsonl` (without the class the false alarm is `slow`, with it `noBaseline`).

## Sum, not max

Builds add: two checks that each built 3 modules did 6 modules of work, class 4 as a sum and class 1 as a max
(`timing-outer.jsonl`). The sum is never below the max (`maxBuilt_le_outerBuilt`) and is 0 exactly when every check built 0
(`outerBuilt_eq_zero`), so a no-op land stays class 0 and shares its history.

## How the member reaches each span

- `fw land` / `dry total lake`: `land.ts` collects `builtModules` of each check's output in a list, `outerBuilt` sums it, and
  the total span's end carries `{ lake: { built } }` next to the step rename (CONFIRMED, test `land-dry.test.ts`, real line:
  `{"tool":"fw land","step":"dry total lake","lake":{"built":0},...}` at commit 094bf08, 14469 ms).
- `fw` / `slot run land ...`: the parent cannot see the child's output, so `fw slot run --kind land` sets
  `FW_SLOT_LAKE_FILE` to a fresh temp file; the child dry land writes `{"built":N}` there (`writeLakeHandoff`), the parent reads
  it when the child exits and puts it on the span line (`readLakeHandoff`), then deletes the file. A child that writes nothing
  leaves the span unkeyed. Test: `land-slot-lake.test.ts`.

## Accepted limits

- `apps/runner/src/slot.ts` is outside the graph writes. `fw slot` runs `slot-main` from the main
  checkout (`apps/runner/src/fw.ts`, `slotMainPath`), so the slot span member appears only after this branch lands; the
  real line shown above is the total span.
- Old samples without the member stay unkeyed; `unkeyedLate` withholds a verdict from an unkeyed sample once keyed history
  exists (INFERRED effect: the old alerts stop with the first keyed samples).
- The retry-alone span and `Nothing to build.` builds stay as `lake-span-mods` left them.
- No CI dispatch. The 46.3 s and 35.8 s samples have no recorded count; the theorem holds for every total above 0.
- A retried check counts the first attempt's modules too (`results[i].out` joins both outputs); this only raises the class.
