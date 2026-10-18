# lean/ — `fwcore` (Mathlib-free Lean core)

The proved decision core of the loop (PLAN §3.2, §5). Toolchain `leanprover/lean4:v4.35.0`
(pinned in `lean-toolchain`; Lean comes from Homebrew's `elan`). No dependencies: core Lean only.

## Build and check

| Command | What it does |
|---|---|
| `lake build` | all `Fw` modules (every proof and `#guard` example runs here), `fwcore`, `mathview`, `breakgen` |
| `fwcore [mathview \| fwtest \| sweepsgen \| partsgolden] <args>` | one executable in place of `fwcore`, `fwtest`, `sweepsgen` and `partsgolden` (task lean-bin-slim, `Fw.Ops.FwCoreRoute`): a first argument naming a former executable runs it on the rest; any other line keeps the old `fwcore` (`--ops` lists the ops, else JSON lines on stdin). `scripts/fwcore-build.sh` strips it |
| `lake test` | `fwcore fwtest` (lakefile `testDriverArgs`): 42 console-apply golden cases, 23 JSON-lines golden lines, `Rat` wire round trips, 2,000 pseudo-random lease traces, the `measure.*` goldens (regenerated and compared byte for byte), a replay timing |
| `lake env lean --run scripts/MeasureGolden.lean [--check]` | writes (or checks) `../packages/contracts/golden/measure/<op>.jsonl` from `Fw/Measure/Golden.lean` |
| `lake exe fwcore partsgolden [<outDir>]` | lean-parts' golden vectors (`Fw/Parts/Golden.lean`) into `<outDir>` (default `../packages/contracts/golden/parts`) |
| `lake exe breakgen [--inventory <json>] [--check <file>]` | prints `Fw/Site/breakpoints.gen.json` to stdout; `--check` exits 1 on a byte diff, `--inventory` on any mismatch with the inventory (see `Fw/Site/README.md`) |
| `lake exe fwcore sweepsgen [--sweeps \| --sweeps-golden \| --scope] [--check <file>]` | the gate generators, split out of breakgen so the site build's breakgen imports only `Fw.Site.BreakpointGen` (`Fw.Site.GenRoute.split_agrees`): `sweeps.gen.json`, `golden/gate/sweeps.jsonl`, `scope.gen.json` |
| `lake exe mathview [--lint]` | JSON export of every `Fw` declaration; `--lint` fails on missing `$$` math or English, `sorryAx`, or an axiom other than `propext`, `Classical.choice`, `Quot.sound`. Each declaration is exported with its own heartbeat budget (`MathView.declBudget`; `autoTex` gets `texBudget`, else `"?"`), and an exception in one declaration becomes a lint failure naming it (`export failed`) instead of crashing the export |
| `scripts/check-partial.sh` | grep gate: no partial ops (bang accessors, `[i]!`, panics) in `Fw/Wire.lean`/`Main.lean`; no `sorry`, `native_decide`, `implemented_by`, `unsafe` anywhere |
| `lake exe mathview [--lint] --out <file>` | also writes the JSON export to `<file>` (the same bytes as stdout), so one run serves the lint and the export |
| `scripts/mathview-cached.sh [--build]` | the lint and the export, computed once per source state: keyed by a SHA-256 of `Fw/**`, `Fw.lean`, `MathView*.lean`, the lakefile, the manifest and `lean-toolchain`; stored in `.lake/mathview-cache/<key>.{json,lint}` (5 newest kept); prints the export path on stdout and the lint text on stderr. A hit runs no Lean. `docs/plan/tools/build-math-view.mjs` reads this export |
| `scripts/check.sh` | all of the above (the lint through `mathview-cached.sh`), plus the real binary on `golden/wire-requests.txt` (diffed against `golden/wire-replies.txt`), `lake test` and the breakgen checks: the land gate |
| `scripts/check-fast.sh` | the inner loop: `check-partial.sh`, incremental `lake build`, `lake test`, the fwcore golden diff, the cached lint; prints seconds per step and, on failure, one line `check-fast: FAILED at <step>` |

`lakefile.toml` sets `enableArtifactCache = true` (Lake `PackageConfig.lean:289@eb6cafb`): build products are
also stored in Lake's local, offline artifact cache for the toolchain and hard-linked back (`Build/Common.lean:489,652`),
so a fresh worktree that is not seeded from another `.lake` rebuilds from the cache.

`Fw` is built with `globs = ["Fw.*"]`, and `mathview` walks the `Fw/` directory, so a new subtree
(for example `Fw/Site/`) is built, exported and linted without editing the lakefile.

## Running `fwcore`

**Always spawn it with `LEAN_ABORT_ON_PANIC=1`.** Without it a Lean panic returns a default value
and the process carries on (lean4 v4.35.0 `src/runtime/object.cpp` l.76-82); with it the process
aborts and the client fails the call. Log any stderr output as an incident.

JSON lines on stdin/stdout, one reply line per input line, in order, flushed after each line:

- The request's `id` (any JSON value) is echoed in the reply; `null` if absent or unreadable.
- Success: `{"id":…, <fields>}`. Failure: `{"id":…, "error":"<reason>"}`.
- A blank line, invalid JSON or a non-object line gets an error reply (`"id":null`), never silence.
- Counts are `Nat`, times integer ns (or the unit in the field name), exact fractions
  `{"num":"<int>","den":"<positive int>"}` (reduced on output; normalized on input). A non-integer
  number is refused. Reply keys come out sorted (compare parsed JSON, not key order).

| op | request fields | reply fields | Lean |
|---|---|---|---|
| `console.apply` | `state`, `event` (the `packages/contracts` `State` / `ReducerEvent`; `seq` ignored) | `state`, `outcome` | `Fw.Console.step` |
| `console.board` | `state`, `now`, `seq` | `board` (contracts `Board`) | `Fw.Console.board` |
| `verdict` | `dir` (`lower`/`higher`), `ctl`, `var` (int lists) | `verdict`, `pNull` (Rat; a proved bound for every m, n, exact for distinct values) | `Fw.Verdict.verdict`, `Fw.Null.pNull` |
| `multiplicity` | `k` and (`m`,`n`) or `p` (Rat) | `p`, `ok` (k·p ≤ 1/20; `p` from `m`,`n` is `pNull`) | `Fw.Null.multOk` |
| `ticks` | `hz`, `dtNs` (nat list), optional `thresholdsNs` | `ticks`, `above` (count per threshold) | `Fw.Frames.tickAt`, `countAbove` |
| `screen` | `base`, `var` (per-frame count vectors) | `screen` (`dominates`/`equal`/`worse`/`mixed`) | `Fw.Screen.screen` |
| `cost` | `unit` {style,layout,paint}, `budgetUs`, `work` {scriptUs,styleElems,layoutObjs,paintKpx} | `mainUs`, `onTime` | `Fw.Cost.mainUs`, `onTime` |
| `flags.resolve` | `registry` {variants:{part:[…]}, rules:[{kind,p,v,q,w}]}, `req` [{part,variant}] | `config` | `Fw.Flags.resolve` |
| `lease.step` | `state`, `cmd` (derived codecs) | `state`, `reply` | `Fw.Lease.step` |
| `breakpoints.gen` | optional `inventory` (the `breakpoints.json` object) | `gen` (the `breakpoints.gen.json` document), `mismatches` | `Fw.Site.BreakpointGen.genJson`, `checkInventory` |
| `measure.zoneSums` | `zoneHeightPx` (≥ 1), `frames` [{n, phase, scrollY, counts}] (fw.counts/1 frames; int counts) | `zones` [{id, frames, scrolledPx, firstFrame, lastFrame, sums}] | `Fw.Measure.zoneSums` |
| `measure.classify` | `mode`: `frames` with `kMax`, `tMax`, `runs` (≥ 2 frame arrays or counts.json objects), optional `pxRel` {num, den ≥ 1} (default 1/1000); `cells` with `tol` {absTol, relTol}, `runs` (≥ 2 int arrays) | `frames`: `classes` {type: {class, k, t}}; pixel-area types (name ends in `AreaPx`) add `unit` and `tBound` = max(tMax, ⌊num · smallest absolute total / den⌋); `cells`: `cls`, `cells`, `differingCells`, `cellsBeyondTolerance`, `maxSpread`, `maxRelSpread`, `k`, `t` | `Fw.Measure.classifyAllU`, `Fw.Measure.WebKit.classifyCells` |
| `measure.noMoreWork` | `types` [{class: {class, k?, t?}, base, var}] | `noMoreWork`, `failing` | `Fw.Measure.noMoreWork` |
| `measure.webkit.tally` / `.reduceSteps` / `.zones` | raw `fw.webkit.records/1` rows (+ `marks`, `endTime`) / `ys`, `perStep`, `perStepPaintArea`, `zonePx` | as `packages/measure-webkit/src/reduce.mjs` | `Fw.Measure.WebKit.tally`, `reduceSteps`, `zones` |
| `measure.symDiff`, `measure.summarize` | `a`, `b` / `rows` [{family, metric, level, cls}] | `symDiff` / `summary` | `Fw.Measure.WebKit.symDiff`, `summarize` |
| `samples` | — | `samples`: one request and reply per op, for zod | — |

`console.apply` is stateless (state in, state out), matching console-api's `lean.ts`; it passes all
42 cases of `packages/contracts/golden/console-apply.jsonl` (copied to `golden/`).

## Modules

| Module | Content |
|---|---|
| `Fw/Spec/Frames` | ticks (µs, and `tickAt` at any rate in ns; 120 Hz equals `tick`, 60 Hz case), threshold counts, the >34 ms vs ≥5-tick gap |
| `Fw/Spec/Verdict` | the v1 verdict and its soundness, swap, direction duality |
| `Fw/Spec/Null` | false-"better" rate through the real `verdict`: `arr k n` has C(k,n) labelings for all k, n; **with ties, at most one labeling wins for any values and any m, n**, so `pAt ≤ 1/C(m+n,n) = pNull`; **for distinct values exactly one wins** (m, n ≥ 3), so `pAt = pNull` and the enumeration equals `pNull` for every m, n (1/20, 1/70, 1/252 at 3v3, 4v4, 5v5); multiplicity gate |
| `Fw/Spec/Screen` | class-W screening: dominates ⇒ no frame costs more under any non-negative coefficients |
| `Fw/Spec/Cost`, `Flags`, `Stage`, `Lease` | seeded from the kickoff sketch (statements unchanged) |
| `Fw/Spec/DeviceQueue`, `ArtifactKey` | ported from the kickoff scratch; DeviceQueue adds aging-based bounded overtaking and the starvation case (a job longer than the window never starts) |
| `Fw/Console`, `Fw/Board` | console reducer (console-mvp contract: cards, steps with kinds, runs, the MAY table) and the board projection |
| `Fw/Measure/Zones` | Chromium `zoneSums`: lookups are filter sums, additivity over concatenation, monotonicity, partition (sums, frames, scroll distance), each zone once |
| `Fw/Measure/Classes` | determinism classes deterministic / stable(k, t) / quarantined, `classify` sound, strictest admissible, monotone in the runs; deterministic iff stable(0, 0) |
| `Fw/Measure/Tolerance` | which classes enter the screen: deterministic frame by frame, stable(k, t) by totals with margin 2t (exact: no smaller margin is sound), quarantined never; `noMoreWork` and its run-cost soundness |
| `Fw/Measure/WebKit` | WebKit `reduce.mjs`: tally, step join (partition, rows conserved), dense zones (partition), cell-spread classes (monotone for relTol ≤ 1, deterministic cells ⇒ deterministic runs), symDiff, summarize |
| `Fw/Wire`, `Fw/Measure/Wire`, `Fw/Measure/Golden`, `Main` | the JSON-lines boundary and golden generator (not in the math view) |

Not proved (stated in `Fw/Spec/Null`): that exchangeable runs make labelings equally likely (the
modeling premise, L3). Every probability above is a share of labelings under that premise.

## Known limits

- `mathview` imports modules without running their initializers (no `unsafe` in the tool), so
  `signature` is printed without notation (`And (Eq …)`); `autoTex` is unaffected.
- `console.apply` carries the whole state per call, so each call is O(state); a long-lived stateful
  `fwcore serve` (PLAN §3.2) would keep it in memory instead.
