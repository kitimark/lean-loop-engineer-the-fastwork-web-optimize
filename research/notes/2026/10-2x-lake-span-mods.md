# Lake spans carry the rebuilt-module class, so a rebuild is not judged against no-op builds

Status: CONFIRMED (code, spans, Lean proofs), the 51 s and 37 s samples MEASURED.

## Answer

- The two `timing.slow` alerts were false: a rebuild after a main merge (new Lean modules) was judged against cached
  no-op builds because the two spans had no `lake` member, so their samples had no `mods` work dimension.
- Spans that carried `lake.built` before this task (MEASURED in `.fw-console/timings.jsonl`, 512 lines): `fw polish commit`
  (77, `stagedSpan` runs the lake build command itself) and `fw land dry lake` (435, `noteSpan` with the count summed
  over the land's check outputs). Spans that did not: `lean/check` `lake build` (a shell span in `lean/scripts/check.sh`,
  p50 799 ms over 1859 samples, the 2026-10-24 sample took 51053 ms at commit d5babdb) and the dry land's check span
  `dry sh -c cd lean && ... (lake_slot .. lake build) >&2 && sh scripts/axiom-check.sh` (37430 ms at 8517344 against a
  p50 of 3182 ms). Both ran real rebuilds; `land dry lake` is only the sum, the per-check span had no member.
- Both now record it: `fwcore-build.sh` copies lake's stdout through `tee` and `lake_built_member` (awk,
  `scripts/lake-slot-lib.sh`) turns it into `,"lake":{"built":N}` for `check.sh`, which puts it in `span_more`;
  `land.ts` ends each check span with `lakeMember(stdout+stderr)` when the check exited 0.
- Lean `Fw.Obs.Timing`: `judgeQ_rebuild_noBaseline` (a sample of mods class above 0 whose earlier samples are all class 0
  has no baseline, never `slow`) and `incident_not_slow` (both incident samples, any class-0 history, default
  parameters). Both build on the existing `judgeQ_other_mods` (a sample is judged only against its own mods class).
- The golden reproduces the false alarm: the same samples without the class are `slow`, with it
  `noBaseline` (`golden/obs/timing.jsonl`, 4 new rows, replayed by `timing-alert.test.ts` through fwcore).

## How the count is parsed

CONFIRMED: `lake build` logs to stdout (Lake/CLI/Main.lean:984 `out := .stdout`, lean4 v4.35.0, eb6cafb) and prints every built job only when stdout is not a terminal (Lake/Build/Run.lean:127, :225); on a TTY it prints only jobs with output. The tee in `fwcore-build.sh` and the land pipes make stdout a pipe, so every built module is printed. The lines are `✔ [i/n] Built <Module> (<time>)`, and `Build completed successfully (N jobs).` last. A
module counts when its line has exactly one `] Built `, a `[i/n]` counter right before it and a name without `:` after it
(`Fw.Obs.Timing:c.o` and `fwcore:exe` are facets, not modules; `Replayed` lines are cache hits). The rule is
`Fw.Obs.Timing.builtLine`/`lakeBuilt?`; the member is written when the output has a Built line or the closing line, so a
no-op build records class 0 and quiet or failed output records none. MEASURED on this repo (2026-10-25): an edit of
`Fw.Obs.Timing` gave a build with 34 Built lines; the golden row `real output of lake build on this repo` is a verbatim
excerpt of it with 8 modules, warnings, a facet object and the exe. The three twins are checked against `golden/obs/timing-lake.jsonl` (`timing-work.test.ts`).

## Accepted limits

- Old samples without a mods dimension stay unkeyed; `unkeyedLate` already withholds a verdict from an unkeyed sample
  once keyed history exists (INFERRED effect: the old alerts stop with the first keyed samples).
- A land check that is not a lake build but prints lake output (for example `sh lean/scripts/check.sh`, which runs
  `fwcore-build.sh`) gets a `lake` member.
- The CI lake spans (`host ci`) follow because CI runs the same `check.sh`; no CI dispatch was run for this task.
- The retry-alone check span (`land.ts:802`, "retry alone: timed out under load") ends without a member and stays unkeyed; its step name is separate, so it does not mix with keyed samples.
- A build with zero jobs prints `Nothing to build.` (Lake/Build/Run.lean:312), no Built line and no closing line: no member, unkeyed.
- The 51053 ms and 37430 ms samples have no recorded module count; the golden assumes 24 and `incident_not_slow` holds for every count b > 0.
- `lake build -q` prints no closing line: no member, the span stays unkeyed.
