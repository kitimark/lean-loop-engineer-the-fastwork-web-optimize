# Fable: does CI need revising for the Lego concept?

Checked against `main@3600b283` (inventory cites 90337d4c; nothing cited moved). Read-only.

## Answer

- **No CI revision before C3.** Every lane the plan needs to C3 (2 whole-page gates, combined counts per profile, base
  refreeze, Lean lane for Compose/Contract) is a plain dispatch of a workflow that exists today. Nothing on the critical
  path waits on a workflow edit.
- **One small edit, for the part-page pilot only (after C3 by the plan's own timing):** `chromium-counts.yml` plan job
  builds the query from `preset`+`fw` and rejects any other character (line 129: `[A-Za-z0-9.:@,_-]`), so
  `?only=<id>&stage=...` cannot pass. Add one optional `only` input (or a validated raw `search`), rewrite target only.
  ~15 lines of YAML, no new workflow. CONFIRMED.
- **Drop from the plan:** `RunMeta.only`, the `runKey_inj`/`golden_base_unique` re-proof, matrix cap 6, and the "per-part
  gate saves nothing (528 vs 517 s)" premise. See (3).
- **Land checks need no part-aware selection change:** selection is already glob-based and Lean-decided
  (`landSpeed.select`, `land.ts:143-144`). What a part edit costs is `check.sh` (it declares `apps/site/src/parts/**`,
  `land.ts:148`, because `Fw.Preset.Gen` reads every `part.json`, `Gen.lean:6,210`). That is a Lean-golden granularity
  item, after C3.

## (1) Required before C3: nothing in CI

| plan lane | CI today | edit |
|---|---|---|
| compose-lean, contract-lean (Compose, Contract, gen JSONs) | `lean` lane runs on every ci/* tip (default lane, `intent.jsonl`) | one `--check` line per generated JSON in `lean/scripts/check.sh`; no workflow |
| 2 whole-page gates per wave | `breakpoint-gate.yml` inputs `fw`, `parts`, `runs`, `free` | none |
| combined counts per profile | `chromium-counts.yml` inputs `profile`, `preset`, `fw`, `target=rewrite` (16-41, 131-134) | none |
| base refreeze on one image | `image_run` (36, 270-279) | none |
| G2 run, faithful re-run | same dispatches with `fw`/`preset` | none |

Lean already decides the CI shape these lanes use: push triggers and guard `if:` (`Fw.Ci.Trigger`, `triggers.jsonl`,
`intent.jsonl`, enforced by `scripts/ci-paths.mjs --check`), gate job split and probe scope (`Fw.Gate.ScopeGen`,
`scope.gen.json`), run keys (`Fw.Engine.Keys`). No new theorem is on the critical path.

## (2) Worth it, after C3 (none shortens the critical path)

| change | files | Lean piece that decides it | cost (free-runner min) | risk |
|---|---|---|---|---|
| `only`/`search` input for part pages | `chromium-counts.yml` plan job (129-134); `ci-paths --check` stays green (it checks `on.push`, guard, groups, Lake rows, not inputs) | none needed: `runKey` appends the whole search (Keys.lean:37-38); `runKey_inj` needs only `NoPlus target` (96-97), so `rewrite+?only=X&stage=...` is already distinct from every whole-page key. Add one part-page run to `goldenRuns` (169-176) as the golden vector | 0 extra; a 1-scenario, 3-run pilot = 6 setup + 3 counts jobs ≈ 7.5 min wall idle pool (run 39140973547) | a part page under `swipe-v1` borrows whole-page frozen classes (`engine-check.ts:87,110-112`: classes by profile id). State as premise or freeze part-page classes |
| scenario profiles | `packages/measure-chromium/profiles/<scenario>.json` (plan job does `test -f`, line 125) | `Fw.Parts.Contract.scenariosFor` generates `scenarios.gen.json`; profile files generated from it, one `--check` line | 0 | only `fixture-rest`, `swipe-v1`, `swipe-touch-v1`, `swipe-wheel-v1`, `engine-premise-cr` exist today; "push" and "group span" scenarios do not |
| several searches per dispatch | counts matrix `{search, run}`; artifact name (418) and classify loop (482) keyed by search index | a Lean `countsMatrix : List Search → Nat → List Job` with $$\forall s \in S, r \le n:\ (s,r) \in \mathrm{matrix}(S,n) \ \wedge\ |\mathrm{matrix}| = |S| \cdot n$$ and a distinct-artifact-name theorem; golden-checked in the plan job | saves 6 setup jobs (~5 job-min) per extra search | optional: the plan already collapses per-flag runs into one combined run |
| engine-check `--zones-by-part`, `--compose` (F6) | `apps/runner/src/engine-check.ts`, fwcore op | `Fw.Measure.Compose` F6 verdict, unit (part, stage, zone); `EngineCheck.verdict` | 0 (local tool) | not CI; needed only to judge the pilot |
| part-aware `check.sh` | `lean/scripts/check.sh`, `land.ts:148` | split `checkShReads` into per-check read sets in `Fw.Console.LandSpeed` (`select` theorem already covers globs); `Fw.Preset.Gen` gets a `--check <part>` mode | local only; saves the lake build on a pure part edit | changes a land input declaration (`land-inputs.test.ts` guards it) |
| per-part gate trigger / WebKit part lane | `breakpoint-gate.yml` dispatch already takes `parts`; webkit-sim parked | `Fw.Gate.Exit.runExit` (narrowed exits 1) | narrowed hero.exit 10.8 vs 34.6 job-min (merge 78b850a2) | evidence only, never the gate of record (`cli.mjs:60`) |
| Lake/apt caching, path filters | none: Lean `Fw.Ci.Cancel.wf_level_loses`, `Fw.Ops.LakeCache` already fix the shape | existing | — | reopening a settled design |

## (3) Not needed or refuted

| plan item | verdict | why |
|---|---|---|
| `Fw.Engine.Keys.RunMeta.only` + re-proof of `runKey_inj`, `golden_base_unique` | not needed | `RunMeta = (target, search)`, search any string (Keys.lean:20-22); `only` rides in `search`. `answers` matches exact key or the hidden-pause alias only (51-60), so a part-page run never answers a whole-page row by accident. INFERRED from the definitions; one golden run makes it checked |
| matrix cap 6 ("12 fanned runs took 39-50 min") | refuted as a cap | the 39-50 min was queue: run 39130874266 counts jobs ran ~2 min but started at +37.6 min in a 13-counts + 2-faithful + 4-gate burst on the 20-job pool. Idle pool: 7.5 min wall. Cap concurrency of dispatches (≤ 3) in §E, not the matrix |
| "scoping the gate to one part saves nothing (528 vs 517 s)" (§A, §F) | stale | predates gate-probe-scope; CI job-min 10.8 vs 34.6 (78b850a2). Two whole-page gates stay right for the other reason: the original is one page and a narrowed run exits 1 by proof (`narrowed_never_zero`) |
| new workflow for part pages | not needed | site build (`build.mjs:15-17` repeatable `--config`), server and harness (`host.mjs:28,48`) pass any search through; only the plan job's charset blocks it |
| per-part Lean/test jobs on CI | not needed | `lean` lane median 4.9 min, runs in parallel with landings; a split would add guard jobs to the pool |

## What stays whole-page, and why

- **Breakpoint gate (both engines, 124 probes):** rewrite vs original; the original is one page. `runExit` makes a
  `--parts` run exit 1 whatever its verdicts, so it can only be evidence.
- **Faithful bands R vs A and the frozen classes:** keyed by profile id over whole-page frames (`classes.frozen.json`
  `.profiles`); a part page has no whole-page counterpart to be faithful to.
- **F3/F4 base refreeze:** after content fill, PaintImage/DecodeImage change for the page, not a part.
- **Passes-type wins:** `passes_not_compositional`; a page-level verdict needs the whole frame.

## Land checks (local CI)

- Selection is already part-aware by glob and Lean-decided; nothing to add before C3.
- Costs today: a workflow edit runs `check.sh` + apps/runner tests (`ci-triggers.test.ts`, `ci-paths --check`); a part
  edit runs `check.sh` (lake build + ~20 goldens), apps/site and gate-breakpoints tests. The after-C3 item is finer read
  sets for `check.sh`, not a selector change.

## Edits to the plan (for plan-rev11)

- §C glue: replace "`chromium-counts.yml` inputs `only`, `scenario`, matrix cap 6; `RunMeta.only` with `runKey_inj`
  re-proved" by "one optional `only`/`search` input (rewrite only) + one part-page run in `goldenRuns`; scenario profile
  files generated from `scenarios.gen.json`".
- §D/§G risk: drop "key collision"; add "part page measured under whole-page frozen classes: premise or freeze".
- §A/§F: correct 528/517 to the 78b850a2 numbers; keep two whole-page gates.
- §E budget: ≤ 3 counts dispatches at once, none overlapping a gate (~10 jobs: guard, site, 7 gate, merge; run
  39142015714). Idle-pool costs: counts 7.5 min wall / 9 jobs; gate 16 min wall; lean 4.9 min median.

## Adversarial check (reviewer, same night)

- Holds: the charset block at chromium-counts.yml:129; gate inputs; `runKey_inj` covers any search (Keys.lean:37-38, 96-97); frozen classes borrowed by part pages (engine-check.ts:87,110-112); only 5 profiles exist (no `push` profile); free ubuntu-24.04-arm runners.
- Wrong: "no CI revision before C3" holds only if the part-page pilot leaves the C3 path (plan §G puts it there). Lead decision: the pilot stays on the C3 path only if part-stage lands by 18:00; counts-only is rescoped to the one input plus a goldenRuns vector.
- Blurred: 528 vs 517 s is gate wall time, 10.8 vs 34.6 is job-minutes (78b850a2); both stand, two whole-page gates stay. Lean lane budget at p90 15.2 min, 19 of 53 runs failed. Gate run 39142015714 merge job failed (verdict job, not a land condition).
