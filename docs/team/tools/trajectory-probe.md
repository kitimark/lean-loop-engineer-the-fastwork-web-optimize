# trajectory-probe: does the rewrite move like the original?

The gate compares rest states and the counts compare class names. Neither watches the path between two rest states, so
three bugs of the motion itself passed them (hero copy and cards stale in WebKit, nav classes stale during the morph,
`is-on-dark` never re-evaluated on a push). The probe walks the original and the rewrite along the same scroll path with
native `requestAnimationFrame`, reads `getComputedStyle` (no screenshot, no animation seeking) and lets Lean decide.

Code: `packages/gate-breakpoints/src/trajectory/` (`run.mjs` walk, `kit.mjs` in-page reads, `registry.mjs` what is read,
`reduce.mjs` the TS twin of the Lean verdicts, `cli.mjs`). Lean: `lean/Fw/Gate/Trajectory.lean`, golden
`packages/contracts/golden/gate/trajectory.jsonl` (regenerate: `cd lean && lake env lean --run scripts/TrajectoryGolden.lean`).
Workflow: `.github/workflows/trajectory-probe.yml`. The probe is the admission gate of `v2-proved` (see Admission below).

## Run it

    pnpm -s fw run --trajectory --ref ci/<branch> [--fw hero.exit:scoped | --preset v2-proved] [--engines both|chromium|playwright-webkit] [--widths 390,641]

Push the branch first (`git branch -f ci/<name> HEAD`, then `git push origin ci/<name>`). Artifacts: `trajectory-chromium`,
`trajectory-playwright-webkit` (Linux arm), and `trajectory-apple` (macos-26, see below). Each holds `raw-<engine>.json` (all
readings plus what each arm's page reported), `units-<engine>.json` and `summary-<engine>.md`. Re-reduce raw files offline:
`node src/trajectory/cli.mjs summary --out <dir>`. A local run is a debug run, never a result.

## The three checks that make a run count

1. **Arm identity (refuses the run).** Each arm records its resolved config hash and `fwMode`. Lean `armCheck` allows only:
   rewrite arm = the hash of its search (from `configs.json` `bySearch`), non-empty, and `fwMode` is `hydrate`; original arm
   = no `window.__fw`. Anything else is `refused:config`: exit 2, no verdict, never a pass. (A page loaded at `/` with no
   search client-renders the default config; an earlier round measured that for every run. Incident
   `inc-variant-gate-flags-off`.) The faithful arm (rewrite, default config) is loaded from its own server for the same reason.
2. **Coverage is a verdict.** In a push phase (open, close) an empty bucket 1-9 (a tenth of the morph value `m`), a missing
   morph value or a `beyond` window is `fail:coverage`, never skip. Hold phases may skip an empty bucket. The tween is driven
   by time, so one push lands about two frames per tenth (Chromium, 17 ms frames) and sometimes none; `--reps N` (1 to 5,
   default 3) walks the morph path on N fresh pages and keeps the rows of each phase (each row carries its `rep`; every
   rep's arm identity is checked). Windows are per pass: a rewrite sample is compared with the union of the windows of the
   original's passes, each aligned on its own (Lean `windowOf`, `windowOf_pass_iff`: pooling never widens a window); a pair of
   neighbours never crosses a pass boundary. (Round 2 concatenated the passes, every window became the whole phase and a stuck
   rewrite passed; incident `inc-trajectory-pooled-window`.) Linux WebKit renders a frame every 150 ms or more, so its push coverage fails by
   construction there (see the research note): report a Linux WebKit push cell as "no verdict: coverage" on the units where the
   faithful arm fails coverage, and read its hero rows as usable.
3. **Per-unit baseline.** A unit is (width, path, phase, node, property, step), decided on its own. The faithful arm is
   judged against the original by the same Lean code, so each unit is `new` (fails here, passes faithful), `both` (baseline
   red), `unmeasured` (fails on content here, on coverage in the faithful arm: no verdict), `cleared` or `ok`. The lane is RED iff some unit is `new` (`laneRed`; no pooled aggregate). The summary splits the
   `new` count into content (apart, differs, ...) and coverage. A coverage-only RED is sampling noise (a default-vs-default
   run turns RED from one empty bucket); the signal is the content-new groups. Steps at `close@0` (the first sample of a
   push) and `a*` (approach) also flicker; read a group only when it repeats across widths or runs.

## Read timing

`kit.mjs` stamps `t0`/`t1` around each sample's reads. Read cost is `t1-t0`; the frame time is the gap between consecutive
`t0`. Quantiles are nearest-rank over integer tenths of ms (Lean `quantile`); `readsDominate` is `0 < gap <= 2*read`. The
summary prints p50/p90 per arm and phase (Playwright WebKit's timer is whole milliseconds). Measured: reads do not
dominate anywhere (Chromium read 0.4 ms against a 17 ms frame; Linux WebKit read 1 ms against a 150 ms frame). If they ever do,
set `READS: lean` in the workflow (or `--reads lean`; not run on CI yet): during pushes only the discrete properties, `m`, the logo rect and the hero copy/cards opacity and transform are read; the full set
is read at rest. The setting is in the artifact header.

## Apple witness

Job `probe-apple` (workflow dispatch only, never on a push) runs the same lane with Playwright WebKit on a free standard
`macos-26` runner: hero path only, the dispatched search against the original, `max-parallel: 1` (5 macOS slots are shared by
all lanes). It runs only when the dispatch's search contains `hero.exit` (the witness is for bug A; every other search would
spend one of the shared macOS slots on a path it cannot change; a preset that holds `hero.exit` is dispatched as `--fw`) and
includes `playwright-webkit`. Its verdict is
the separate artifact `trajectory-apple`; it is the closest engine CI has to Safari, still not Safari.

## Admission

No flag enters `v2-proved` without a stored pass in Chromium and in WebKit on both paths (Lean `member_needs_trajectory`,
`lean/Fw/Preset/V2Proved.lean`). The stored runs live in `packages/contracts/golden/preset/v2-proved.trajectory.jsonl`, one
line per (run, engine, path); only the recorder writes it. After a run, from `lean/`:

    gh run download <id> -D <new empty dir>
    git show <sha>:apps/site/src/registry/presets/v2-proved.json > <scratch>/preset.json   # only for a ?preset= search
    printf 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.record ["<id>", "<sha>", "<scratch>/preset.json or -", "<dir>/trajectory-chromium", "<dir>/trajectory-playwright-webkit"]\n' | lake env lean --stdin
    printf 'import Fw.Preset.Gen\n#eval Fw.Preset.Gen.run []\n' | lake env lean --stdin

A stored run's outcome (Lean `outcome`, `lean/Fw/Gate/Trajectory.lean`), in order: no verdict (coverage) when the engine
cannot decide the path (Linux WebKit on morph), no verdict (widths) when a lane width is missing, fail when a node property
has content `new` units at 2 or more widths, no verdict (coverage) when it has coverage `new` units at 2 or more widths, else
pass. In the default-vs-default run 39409003529 (Chromium) the content `new` units of each node property sat at one width,
and so did its coverage `new` units (MEASURED), so one width alone does not fail a run.

A cell (flag, engine family, path): a failing run of the flag alone fails it; else a passing run of the flag alone passes
it; else a failing shared run (a preset) leaves it pending, because it does not say which flag regressed; else a passing
shared run passes it; else it is pending. A flag is `falsified: trajectory` when a cell fails, admitted when all four cells
pass, else `pending: trajectory`. The decision rows (`v2-proved.decisions.jsonl`, field `trajectory`) show each cell and the
runs it read. The WebKit morph cell needs `mac-webkit` (`member_needs_mac_morph`), and `probe-apple` walks only the hero path,
so until it walks morph every flag stays pending.

## Limits

Touch input, the WebKit 325900 engine-premise test, stale anchor exclusions and Mobile Safari in the iOS Simulator are
follow-ups. Linux WebKit is WPE/GTK, not Safari.
