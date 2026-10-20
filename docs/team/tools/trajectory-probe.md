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
`trajectory-playwright-webkit` (Linux arm), and `trajectory-apple` (macos-26, see below). Each engine runs as width legs in
parallel (see Legs and paths); a merge job joins the legs of an engine into the artifact above, so what the recorder reads is
unchanged. Each holds `raw-<engine>.json` (all
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
   run turns RED from one empty bucket); the signal is the content-new groups. Reads at `close@0` (the first sample of a
   push) and `a*` (approach) taken mid-transition are judged as in Transitions in flight below. Read a group only when it
   repeats across widths or runs.

## Legs and paths

Lean decides which jobs a dispatch has (`Fw.Gate.Trajectory`: `enginesOf`, `legs`, `walks`, `plan`; golden rows `op: plan` in
`packages/contracts/golden/gate/trajectory.jsonl`; node twin `src/trajectory/plan.mjs`, checked against the golden). The `site` job
runs the twin and hands the matrix rows (engine, widths, paths) to the jobs.

- **Paths.** An engine walks the paths it can decide (`walks`): Chromium and macOS WebKit hero and morph, Linux WebKit hero only
  (`walks_linux_webkit`; its morph pushes had no verdict anyway).
- **Legs.** Linux: one job per (engine, width), four legs. macOS: two legs (390+641 and 640+1280; the macOS slots are shared, so
  it is not four). `legs_mem`, `legs_nodup`, `legs_ne_nil`: a picked width is in exactly one leg, no leg is empty.
- **Engines.** `enginesOf`: `both` and `playwright-webkit` include macOS WebKit (`enginesOf_webkit_pair`), so `probe-apple` runs for
  every dispatched search, not only a `hero.exit` one (`plan_mac_morph`: a macOS leg walks the morph path).
- **Merge.** Each leg uploads `trajectory-leg-<engine>-<leg>` (`trajectory-leg-apple-<leg>` on macOS). Job `merge` / `merge-apple`
  runs `cli.mjs merge`: the legs must agree on search, hashes, reads, reps and paths (else it throws), the runs are joined in width
  order and reduced as one run. A missing leg leaves its width missing, and Lean `outcome` gives no verdict (widths). The merge
  is glue, a TS stand-in without a Lean spec.
- **Reps.** The workflow sets `--reps 5` (the CLI default is still 3): one empty tenth-bucket in a push is `fail:coverage`; more passes
  fill it.

## Read timing

`kit.mjs` stamps `t0`/`t1` around each sample's reads. Read cost is `t1-t0`; the frame time is the gap between consecutive
`t0`. Quantiles are nearest-rank over integer tenths of ms (Lean `quantile`); `readsDominate` is `0 < gap <= 2*read`. The
summary prints p50/p90 per arm and phase (Playwright WebKit's timer is whole milliseconds). Measured: reads do not
dominate anywhere (Chromium read 0.4 ms against a 17 ms frame; Linux WebKit read 1 ms against a 150 ms frame). If they ever do,
set `READS: lean` in the workflow (or `--reads lean`; not run on CI yet): during pushes only the discrete properties, `m`, the logo rect and the hero copy/cards opacity and transform are read; the full set
is read at rest. The setting is in the artifact header.

## Apple witness

Job `probe-apple` (workflow dispatch only, never on a push) runs the same lane with Playwright WebKit on a free standard
`macos-26` runner: hero and morph paths, the dispatched search against the original, two width legs with `max-parallel: 2` (5
macOS slots are shared by all lanes). It runs for every dispatch whose engines include `playwright-webkit`: a flag enters
`v2-proved` only with a macOS morph pass, so the witness is no longer limited to `hero.exit` searches. Its verdict is
the separate artifact `trajectory-apple`; it is the closest engine CI has to Safari, still not Safari.

## Transitions in flight (task trajectory-transition-window)

Arms start a CSS transition at different frames, so a property read mid-transition differs between an arm and itself.
MEASURED in the stored runs: macOS WebKit `nav.background-color` approach steps a3/a7/a8/a11 at 641 and 1280 (runs
39453181962, 39455284967) and Chromium `earn` max-width/opacity at close@0 (runs 39453764374, 39457063232, A/A run
39409003529). Every such read had `since` (ms since the last nav class change) below the transition's length plus 140 ms.

The judge (Lean `judgeUnit`, TS twin `judgeUnit` in `reduce.mjs`) decides each unit on its own:

- `rules`: every rule of `apps/site/src/parts/nav/nav.module.css` that sets `transition` or `transition-delay`, one per
  selector, keyed by node, the nav classes it needs on and off, its media condition and its line. `trajectory.test.mjs`
  parses the CSS file and requires this list exactly. `durOf node prop width cls` is the longest delay plus duration of
  the property under the last applying rule (specificity, then line); under `is-morphing` the judge treats every sample
  as at rest; rules 6 and 167 still run transitions driven by `--morph` (nav transform/opacity, earn
  max-width/opacity/padding), which are judged strictly against the m-window.
- `inFlight d s`: the sample's own class set selects a transition `t` and `since < t + startLag`, `startLag` = 200 ms.
- A rewrite sample in flight is judged against the original's samples of the same transition only: the same rep, phase
  and epoch (a run of samples with no class change), within 200 ms of its `since` (`isCore`), plus the epoch's sample
  before them and one after. A colour must match one core reading on r, g, b (rgb readings only; see Limits for WebKit
  in flight) and the band on alpha. No core sample: the
  m-window as before.
- A rewrite sample at rest is judged against the original's settled end value: the window sample if at rest, else the
  last sample of its epoch if that one is at rest, else coverage.

Proved: an arm whose samples are the original's never fails (`judgeUnit_self`, `byM_self`, `byStep_self`); a rewrite
sample at rest is judged only against settled values, whatever the original's state (`judgeUnit_settled`, golden: pure
red and pure green at rest fail, `byStep_settled_red_green`); a reading with one component outside every reading of the
window fails, for any number of components (`judgeEls_outside`, `judgeUnit_flight_outside`, `judgeUnit_settled_outside`,
colours `judgeUnit_colour_chan_outside`, `judgeUnit_colour_alpha_outside`); a reversed rect curve in flight fails
(`byM_reversed_in_flight`). Each branch of `judgeUnit` has its own theorem (`judgeUnit_flight_*`, `judgeUnit_settled_*`).

In flight, MEASURED over all arms and the 10 properties with a CSS transition (morph phases; approach steps):

| engine | runs | phases in flight | approach in flight |
|---|---|---|---|
| Chromium | 6 runs | 20.5 to 20.8% | 8.4 to 16.3% |
| Linux WebKit | 4 runs | 10.4 to 12.2% | 0.7 to 1.9% |
| macOS WebKit | 39453181962, 39455284967 | 22.1, 22.5% | 14.3, 14.9% |

About 66 to 70% of morph phase samples carry `is-morphing` and are never in flight. Mutation (MEASURED): the candidate's
nav.rect curve reversed inside each phase and rep gives 77 content `new` nav.rect units at all 4 widths on macOS raw
39453181962 and 86 on Chromium raw 39457063232 (round 1 judge: 0).

Limits of the in-flight rule, for that fraction of samples:
- ±200 ms slack: a reading counts as the original's if it equals any core reading within 200 ms of `since`, so a
  transition lagged or shortened by less than that passes; in a mirrored ramp the middle buckets 4 to 6 pass (golden
  `reversed curve in flight`).
- `since` sees only nav class changes; a transition started by something else is read as at rest.
- `startLag` = 200 ms is a measured bound on the 140 ms overrun, not a proved one.
- No core sample in the original: the unit falls back to the m-window of the original's samples.
- The kit reads a WebKit mid-transition colour as oklab `[L×1000, a, b, α]` and a settled one as rgb. A colour read in
  oklab on one arm and rgb on the other fails `apart`; that is the kit-colour-space task (owner of `kit.mjs`), not widened
  here.
- Until the kit normalises colour space (task kit-colour-space), WebKit in-flight colour channels are unchecked (oklab L
  in 0..1000 lies inside the rgb tolerance 2000); only alpha is judged; after normalisation
  `judgeUnit_colour_chan_outside` applies.
- `--morph`-driven transitions under `is-morphing` are judged at rest. MEASURED residual: raw 39457063232, 641
  `earn.max-width` close@0, one width (content `new` 1; main gave 2). Follow-up: `morph-driven-transitions`.

Re-recorded with this judge (stored runs 39442517769, 39453181962, 39455284967, all `?preset=` runs of 8 flags):

| cell | 39442517769 | 39453181962 | 39455284967 |
|---|---|---|---|
| chromium hero, morph | pass, pass | pass, pass | pass, pass |
| linux-webkit hero, morph | pass, no verdict: coverage | pass, - | pass, - |
| mac-webkit hero, morph | - | pass, fail | pass, no verdict: coverage |

Per flag (engine.scene:hidden-pause, engine.scroll:batched, morph.columns:hidden-pause, morph.countdown:hidden-pause,
morph.mount:shift, nav.hitTest:elements-skip, pain.notes:visible, people.card:mq): Chromium hero and morph pass, WebKit
hero passes, WebKit morph is pending (a failing shared run names no flag). All stay `pending: trajectory`; `v2-proved` is
empty. The 39453181962 mac morph fail: `nav.background-color` content `new` at 640 and 1280 close@0, both arms in oklab, so
not the colour space. MEASURED: candidate rep 4 starts at alpha 0.296, outside the original's start range across reps
0.261 to 0.281; whether a flag causes it is unknown (INFERRED timing), so it stays pending until a flag-alone run. Its 641 a8/a11 and 1280 a7 units are the
colour-space case. The 39455284967 mac morph colour units (641 a7, a11) are colour space at one width and do not decide it.

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
and so did its coverage `new` units (MEASURED in that one A/A run; that one width alone never fails a correct flag is INFERRED from
it). Only a single-flag `?fw=` page or a `?preset=` page is prerendered, so several pending candidates are dispatched together as
`--preset v2-proved` on a ref whose commit holds `apps/site/src/registry/presets/v2-proved.json` with those flags (restore
it from the recorded verdicts afterwards: the recorder and `Gen.run` rewrite the file; an empty preset walks the default config). Limits: a stored pass is not re-checked when the flag's part changes later (`Stored.sha` is not read yet). A read in flight
is judged as described in Transitions in flight above.

A cell (flag, engine family, path): a failing run of the flag alone fails it; else a passing run of the flag alone passes
it; else a failing shared run (a preset) leaves it pending, because it does not say which flag regressed; else a passing
shared run passes it; else it is pending. A flag is `falsified: trajectory` when a cell fails, admitted when all four cells
pass, else `pending: trajectory`. The decision rows (`v2-proved.decisions.jsonl`, field `trajectory`) show each cell and the
runs it read. The WebKit morph cell needs `mac-webkit` (`member_needs_mac_morph`); `probe-apple` walks hero and morph for every
WebKit dispatch (Lean `plan_mac_morph`).

## Measured (task trajectory-probe-speed)

Dispatch of the 8 pending candidates as one preset, runs 39453181962 and 39455284967 (ref `ci/trajectory-probe-speed`):

| cell | run 1 | run 2 |
|---|---|---|
| chromium hero, morph | pass, pass | pass, pass |
| linux-webkit hero | pass | pass |
| mac-webkit hero | pass | pass |
| mac-webkit morph | fail | fail |

The mac morph fail is the same in both runs: content `new` units of `nav.background-color` at 641 and 1280 (steps a3, a7, a8,
a11: approach). The colour is a CSS transition that the page starts when `is-on-dark` flips; a sample lands mid-transition at
a different point each time. The original shows the same mid-transition values at the same scroll steps (e.g. 32132 alpha
at a4 in one run, settled at 26000 in another), the faithful arm too; only the rewrite arm happens to be red at two widths
in both runs, which `outcome` reads as `fail`. INFERRED: approach timing noise, not a regression (no flag-alone run exists to
separate them). A failing shared run leaves a cell pending, so all 8 flags stay `pending: trajectory` and `v2-proved` is
empty. These verdicts came from the judge before task trajectory-transition-window; the re-recorded ones are in
Transitions in flight above.

Reps 5 (Chromium morph, one coverage-new width per run in runs 1 and 2, none in the reps 3 run 39442517769) did not remove the
one-empty-bucket coverage red: it stays at one width and so does not decide an outcome (the 2-widths rule). Three runs are too
few to say reps 5 helps or hurts (the widths now run on separate runners).

Wall time per cell (CI, one dispatch, start of the first job to the end of its merge):

| lane | before (one job, 4 widths, run 39442517769, reps 3) | after (width legs, reps 5) |
|---|---|---|
| chromium | 12.1 min | legs 4.5 to 5.5 min, 6 min with merge (run 39455284967) |
| linux-webkit | 26.6 min (hero plus morph) | legs 2.2 to 3.3 min (hero only) |
| mac-webkit | no baseline for hero plus morph (hero only: 3.1 and 3.8 min) | two legs 9.1 / 11.3 and 9.2 / 10.9 min |

The Linux WebKit drop is mostly the removed morph walk (a cell that lane cannot decide), not the width legs; Chromium walks the same paths in both columns and shows the leg gain (reps 3 to 5 also changed).

Cap of `probe-apple` (Lean `Fw.Ci.Pool.Caps`, `capMin`): 4 successes (9.1, 9.2, 10.9, 11.3 min), linear p90 11.2 min, cap 15 min,
`thin` until 10 successes (the cap is re-derived then).

## Limits

Touch input, the WebKit 325900 engine-premise test, stale anchor exclusions and Mobile Safari in the iOS Simulator are
follow-ups. Linux WebKit is WPE/GTK, not Safari.
