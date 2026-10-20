# trajectory-probe: does the rewrite move like the original?

The gate compares rest states and the counts compare class names. Neither watches the path between two rest states, so
three bugs of the motion itself passed them (hero copy and cards stale in WebKit, nav classes stale during the morph,
`is-on-dark` never re-evaluated on a push). The probe walks the original and the rewrite along the same scroll path with
native `requestAnimationFrame`, reads `getComputedStyle` (no screenshot, no animation seeking) and lets Lean decide.

Code: `packages/gate-breakpoints/src/trajectory/` (`run.mjs` walk, `kit.mjs` in-page reads, `registry.mjs` what is read,
`reduce.mjs` the TS twin of the Lean verdicts, `cli.mjs`). Lean: `lean/Fw/Gate/Trajectory.lean`, golden
`packages/contracts/golden/gate/trajectory.jsonl` (regenerate: `cd lean && lake env lean --run scripts/TrajectoryGolden.lean`).
Workflow: `.github/workflows/trajectory-probe.yml`. The probe is not a gate stage and no preset reads it (follow-up).

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
   default 3) walks the morph path on N fresh pages and pools the rows of each phase (each row carries its `rep`; every
   rep's arm identity is checked). Linux WebKit renders a frame every 150 ms or more, so its push coverage fails by
   construction there (see the research note); read its morph rows as "not measurable", and its hero rows as usable.
3. **Per-unit baseline.** A unit is (width, path, phase, node, property, step), decided on its own. The faithful arm is
   judged against the original by the same Lean code, so each unit is `new` (fails here, passes faithful), `both` (baseline
   red), `cleared` or `ok`. The lane is RED iff some unit is `new` (`laneRed`; no pooled aggregate). The summary splits the
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
all lanes). It runs when the dispatch names a search (`--fw` or `--preset`) and includes `playwright-webkit`. Its verdict is
the separate artifact `trajectory-apple`; it is the closest engine CI has to Safari, still not Safari.

## Limits

Touch input, the WebKit 325900 engine-premise test, stale anchor exclusions and Mobile Safari in the iOS Simulator are
follow-ups. Linux WebKit is WPE/GTK, not Safari.
