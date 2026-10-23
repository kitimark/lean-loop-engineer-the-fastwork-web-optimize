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

    pnpm -s fw run --trajectory --ref ci/<branch> [--fw hero.exit:scoped | --preset v2-proved] [--engines both|chromium|playwright-webkit] [--widths 390,641 --diagnostic]

A verdict run (the default, stored and judged) walks all four widths, so `--widths` with a subset needs `--diagnostic` (a run read by hand, never judged); the push line takes the word `diagnostic` and the workflow takes the boolean input `diagnostic`, all three from the one Lean rule `Fw.Gate.Trajectory.Dispatch`.

Push the branch first (`git branch -f ci/<name> HEAD`, then `git push origin ci/<name>`). Artifacts: `trajectory-chromium`,
`trajectory-playwright-webkit` (Linux arm), and `trajectory-apple` (macos-26, see below). Each engine runs as width legs in
parallel (see Legs and paths); a merge job joins the legs of an engine into the artifact above, so what the recorder reads is
unchanged. Each holds `raw-<engine>.json` (all
readings plus what each arm's page reported), `units-<engine>.json` and `summary-<engine>.md`. Re-reduce raw files offline:
`node src/trajectory/cli.mjs summary --out <dir>`. A local run is a debug run, never a result.

## Run it from a push, and find a dispatch's run (tasks ci-push-probe-inputs, fw-run-dispatch-pick)

Agents cannot dispatch a workflow (sandbox, incident m195), but they can push. A `ci/*` push whose head commit asks for the lane
runs the probe with the inputs of one message line:

    [ci:trajectory-probe]
    [trajectory fw=hero.exit:scoped,morph.tween:waapi widths=390,1280 engines=both diagnostic]

- The bare word `diagnostic` (no `=`, at most once) marks the run diagnostic; without it `widths` must name all four widths or be absent, else the `site` job fails with the Dispatch text (`widths ... is a subset, and a verdict run (stored, judged) walks all four widths ...`; Lean `Fw.Ci.Trigger.push_verdict_all_widths`). `diagnostic=...` is refused. The rule binds this workflow only (Lean `ProbeLane`, `LANE=trajectory` in the workflow): the smoothness workflow reads the same line with its old widths allowlist (its verdict is at 390,1280; the word `diagnostic` is an unknown token there), and a message with a `[frames:` token is a frames run, exempt (`effLane`). Lean `parseLine_smoothness` proves the smoothness lane equals the pre-task reader.
- Keys `fw` (flag set) or `preset` (exclusive with `fw`), `widths`, `engines`, `debug` (a page recorder, only `nav-transition`; any other value is refused; the workflow sets `FW_DEBUG` from it and the probe loads the rewrite arms with `fw-debug=<name>`, `src/trajectory/debug.mjs`; a push with `debug=` also runs the macOS leg, see Apple witness); each at most once; values from `A-Za-z0-9.:,_@-`; no
  line = the dispatch defaults. Only a line that starts with `[trajectory` counts (prose that quotes it asks for nothing). A line that
  does not parse, or a second line, fails the `site` job with the reason (Lean `Fw.Ci.Trigger.pushProbe`, golden `probe` lines of
  `packages/contracts/golden/ci/triggers.jsonl`, node twin `.github/scripts/trajectory-line.mjs`). A line without `[ci:trajectory-probe]`
  does not start the lane (Lean says `needsLane`). `pnpm fw ci push` reports `needsLane` and a refused line before the push (`probeNotes` in
  `scripts/ci-push.mjs`, the twin of Lean `pushProbe`; a refused line stops the push, exit 2). Accepted limit: a plain `git push origin ci/<x>`
  (the allowed form) reports nothing, so a `[trajectory]` line without the lane token is ignored silently on that route.
- `pnpm fw ci wait --branch ci/<x> --workflow trajectory-probe` waits for the push run of the commit (`--sha`, event `push`); with `--nonce <n>` for
  the dispatch whose run-name carries the nonce (Lean `Fw.Ci.Dispatch.select`, golden `select` lines of `golden/ci/dispatch.jsonl`, TS twin
  `packages/gh-budget/src/want.ts`). Never the newest run. Accepted limit: `--gate` and the count lanes of `fw run` keep the newest-run rule.
- A run with one leg (one engine, one width) merges: each leg file `artifact-name.txt` names its artifact; the merge job moves a single download under
  `legs/<artifact name>/`, so the join sees one directory per leg in every case.
- The run records its inputs: step name `trajectory inputs: engines=.. fw=.. preset=.. widths=.. debug=.. diagnostic=.. (commit-line|defaults|dispatch)` of job
  `site` (`gh run view <id> --json jobs`) and artifact `trajectory-inputs` (`inputs.json`: event, sha, nonce, inputs, source).
- `fw run --trajectory` sends a fresh `nonce` input; the workflow's `run-name` is `trajectory-probe dispatch nonce=<n>`; the command lists
  `workflow_dispatch` runs of the ref and takes the one whose title is exactly that (Lean `Fw.Ci.Dispatch.pick`, golden
  `packages/contracts/golden/ci/dispatch.jsonl`, TS stand-in `apps/runner/src/run-pick.ts`). None yet: it looks again every 120 s
  (5 looks); two: it stops. It never takes "the newest run on the ref" (that was a skipped push run, and the same run for two parallel
  dispatches). The same fix for `--gate` and the count lanes needs a `nonce` input in their workflows (follow-up).

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
   **First frame.** Bucket 1 of the open push is `m` in [500, 1500), elapsed 12 to 35 ms of the 680 ms tween
   (`mAt_first_iff`, `mAt_edges`). At the 17 ms Chromium cadence that is 1 or 2 frame slots depending on the vsync phase, 2 when the first frame lands at 17 ms (`slots_cadence`, `phase_covers`): a pass samples it
   iff its first frame after the push is less than 2 vsyncs late (`sampled_iff`). MEASURED (runs 39926829451 and
   39557718020, 75 open passes): the first nonzero sample is either in bucket 1 (27 passes, gap 22.6-26 ms) or in bucket 2
   (48 passes, gap 54.5-58.7 ms, two vsyncs late); a pass never lands one vsync late. So open@1 coverage is a property of the
   pass count, not of the page: Lean `firstCover no k nw` (`k` of `no` original passes in bucket 1, `nw` rewrite passes,
   none there; `alpha` = 1/20) is `missing` when even with one original hit fewer all `nw` rewrite passes would miss with
   chance at most `alpha`, `late` when with one hit more that chance is above `alpha`, else `undecided`. An empty open@1 of
   the rewrite becomes `fail:coverage`, `skip:firstLate` or `skip:firstOpen` (`coverVerdict`, `firstVerdict_empty`); at
   5 and 5 passes, `k` 0-1 is late, 2-3 undecided, 4-5 missing (`cover_five`). The verdict never flips between
   `fail:coverage` and `skip:firstLate` when one original pass is added, hit or not (`firstCover_extra`), or one
   original miss becomes a hit (`firstCover_step`); concrete check `first_extra_pass`. A unit is `undecided` (`rel`) when
   the candidate's open@1 is `skip:firstOpen` and the faithful arm does not fail, or when the faithful arm's is `skip:firstOpen` and the candidate fails
   (`fail:coverage` or a content failure: the faithful arm was not measured there, as in `unmeasured`). The lane word is
   RED, UNDECIDED or CLEAN (`laneOf`; `summary-<engine>.md` prints the same word and an `undecided` row). The lane never
   moves between RED and CLEAN when the original arm gets one extra pass, hit or miss (`laneOf_extra`): each unit's arm is
   either the `firstCover` fallback or a verdict the extra pass leaves unchanged (`Arm`), and every unit with `k <= no`
   steps to `(no + 1, k)` or `(no + 1, k + 1)`. Content verdicts that move with the extra pass are outside it: they compare
   values. Check `openLane`: original 5 passes 3 hits, candidate 5 passes, faithful 4 passes, both arms empty at open@1,
   is UNDECIDED before and after one more original hit (the old `rel` gave CLEAN, then RED). Timing link:
   `lateRate_delays` proves that when pass `i` of the original is `d_i` vsyncs late, `firstCover`'s late rate
   `(no - k) / no` is the share of passes with `d_i >= 2` (`sampled_iff`). What stays a model assumption: the rewrite's
   passes are independent and as late as the original's (same delay distribution), so `missChance` is a probability only
   under that assumption; `phase_covers` (some frame of the first 3 lands in bucket 1 at every vsync phase) bounds `d` but
   does not give its distribution. Kept
   as before: a sampled open@1 (`firstVerdict_rew_sampled`), a content failure (`firstVerdict_content`), any other bucket
   or phase (`firstVerdict_not_first`, `close_empty`). `verdictLines` prints a `FIRSTFRAME` line with the counts.
   Offline re-reduction (dev check): run 39926829451 stays CLEAN, its 640
   candidate open@1 goes from `skip:origEmpty` to `skip:firstLate`, its 641 faithful open@1 from `fail:coverage` to
   `skip:firstLate` (cleared 43 to 1, undecided 0); run 39557718020 is unchanged (CLEAN). With `laneOf_extra`: run 39926829451 CLEAN (new 0, undecided 0, cleared 1; its
   open@1 `skip:first` units are 42 `skip:firstLate` vs pass and 42 pass vs `skip:firstLate`, no `skip:firstOpen`), run
   39557718020 CLEAN (new 0, undecided 0). Limit: the cadence is Chromium's;
   WebKit's cadence is a follow-up.
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

Job `probe-apple` (every dispatch; on a `ci/*` push only when the commit has the `[frames:` token or its probe line a `debug=` key; Lean decides it, `Fw.Ci.Trigger.appleRuns`, and the workflow reads the plan step output `apple_run`) runs the same lane with Playwright WebKit on a free standard
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
- A rewrite sample in flight is judged against the envelope of the original's samples of the same transition (Lean
  `envelope`): in every pass of the original, the samples of the same phase and epoch (a run of samples with no class
  change) within 200 ms of its `since` (`isCoreIn`), plus that epoch's sample before them and one after, joined over
  the passes. A colour must match one core reading of some pass on r, g, b (rgb readings only; see Limits for WebKit in
  flight) and the band on alpha. No core sample in any pass: the m-window.
- A rewrite sample at rest is judged against the original's settled end value: the window sample if at rest, else the
  last sample of its epoch if that one is at rest, else coverage.
- A rewrite sample at rest at the end of a push, at a morph value a pass of the original never sampled in that push, is
  judged in that pass against the pass's first row of the next hold when that row has the same morph value (Lean
  `windowPass`, `windowAt`); otherwise the pass gives its `windowOne`.

Proved: an arm whose samples are the original's never fails (`judgeUnit_self`, `byM_self`, `byStep_self`); a rewrite
sample at rest is judged only against settled values, whatever the original's state (`judgeUnit_settled`, golden: pure
red and pure green at rest fail, `byStep_settled_red_green`); a reading with one component outside every reading of the
window fails, for any number of components (`judgeEls_outside`, `judgeUnit_flight_outside`, `judgeUnit_settled_outside`,
colours `judgeUnit_colour_chan_outside`, `judgeUnit_colour_alpha_outside`; in flight "every reading" is every reading
of every pass's window); a reversed rect curve in flight fails (`byM_reversed_in_flight`, over two passes
`byM_reversed_two_passes`), pure red over two passes fails (`judgeUnit_red_two_passes`). When every pass of the original
gives the same window as the sample's own pass, the judge is the one-pass rule `judgeOwn` (`judgeUnit_agree`); when no
pass takes the hold-row branch the window is the old `windowOf` (`windowAt_old`). A start that only another pass had
passes and fails against the own pass alone (`judgeUnit_other_start`). Each branch of `judgeUnit` and `windowPass` has
its own theorem (`judgeUnit_flight_*`, `judgeUnit_settled_*`, `windowPass_head`, `windowPass_sampled`,
`windowPass_other`, `windowPass_in_flight`, `windowPass_no_head`); golden `settled push end, hold head`, `settled push
end, stuck class`, `push sampled its end`, `push end in flight`.

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
- No core sample in any pass of the original: the unit falls back to the m-window of the original's samples. A pass
  with no core sample does not fall back on its own: when another pass has one, the envelope decides (kept by
  `judgeScoped_stuck_hold`, section Envelope scope).
- Same-phase core: a hold sample's core holds no reading of its epoch taken in the push before the hold.
- Envelope band: geometry, unit and alpha are judged against the band of every pass's readings, so a value between two
  passes' readings passes though no pass read it; r, g, b must match one core reading of one pass.
- A start outside every pass: a rewrite whose transition starts from a value no pass of the original started from (a
  skipped frame, an interrupted earlier transition) still fails; the envelope widens only by what the original's own
  passes read.
- Hold row at a push end: the pass's next hold's first row stands for the settled end only when the push never sampled
  that morph value; a sample in flight there keeps `windowOne`.
- Colour space (task kit-colour-space): the kit reads every colour (`rgb`, `rgba`, `hsl`, `color(srgb ..)`, `oklab`, `oklch`,
  `lab`, `lch`; engines print a mid-transition colour as `oklab(..)`/`color(srgb ..)`) as sRGB `[r, g, b, α]` × 1000 on the
  0 to 255 scale, so `judgeUnit_colour_chan_outside` judges real channels. Lean `Fw.Gate.Colour` states the error budget
  (`chanErr` 500: an integer rgb channel is 0.5 level off; `alphaErr` 1000: 8 bit rounding plus a 2 decimal print) and proves
  `budget_inside_tol`, twice the budget at most the judge's `tol .colour` = 2000, so the tolerance is unchanged. Golden
  `golden/gate/trajectory-colour.jsonl`, test `kit-colour.test.mjs`. MEASURED worst error: 8 thousandths of a level on
  channels (6 digit print over a 16^3 grid of the cube), 765 on alpha. Accepted limits: a clipped out-of-gamut colour is
  read unclamped, `lab`/`lch` use CSS Color 4's D50 to D65 Bradford and are unchecked against a device, relative colour
  syntax and `calc()` stay strings.
- The stored raw files (runs 39453181962, 39471466367, 39457063232) hold the old numeric tuples, not the colour string,
  so the re-reduction reads the old `oklab` shape back (`colourFromV1`: lightness 0..1000, a and b within 500) and leaves
  every other tuple as stored. MEASURED tuple range over the three runs: L 0.234 to 1.0, a -0.004 to 0, b -0.019 to 0
  (the first tuple of L below 0.3 is one Linux WebKit nav reading, `[234,-4,-19,212479]`). Counts, oklab-shaped tuples of
  all colour reads (of those, with a or b not 0): 39453181962 apple 1321 of 10432 (44), chromium 1629 of 13844 (0);
  39471466367 apple 726 of 9248 (65), chromium 1126 of 14252 (0); 39457063232 playwright-webkit 67 of 1304 (34),
  chromium 1014 of 8764 (10). The shape is not always a = b = 0 (L near 1). Recovery error, MEASURED: the 0.001 rounding of
  the stored tuple gives up to 0.64 level (640 thousandths, at L 0.998, a -0.004, b -0.019, red channel; a grid of every
  0.001 tuple over the range above with the true value at the 8 corners of +-0.0005), outside the Lean `chanErr` 500. A
  recovered reading is within 0.64 + 0.008 level of the truth, so one recovered arm against an `rgb` arm (0.5 level) differs
  by at most 0.64 + 0.5 + 0.008 < 2 levels, inside the judge's 2000; when both arms are recovered, 2 x (0.64 + 0.008) =
  1.296 < 2 levels (arithmetic from the MEASURED error). Ambiguity: an old `color(srgb ..)` reading of a
  near-black non-integer colour (for example `[510,255,255]`) has the same shape and would be read as `oklab`; none is in
  the stored data (every oklab-shaped tuple there has b at most 0). Re-reduced with the same `reduce.mjs` over every
  `raw-<engine>.json` of the three runs (artifacts `trajectory-apple` = Safari on the Mac, `trajectory-playwright-webkit` =
  Linux WebKit, `trajectory-chromium`; `before` = as stored, `after` = oklab-shaped tuples converted, same files). The
  failing colour units of `nav.background-color` and `logo.color` are tabulated for 9 whole-run artifacts (3 runs x
  `trajectory-apple`, `trajectory-playwright-webkit`, `trajectory-chromium`) x 4 widths (390, 640, 641, 1280) = 36 cells,
  every cell present. Each cell is exactly one of three values: (a) `not measured (0 morph runs)`: the artifact's runs have
  no morph phase, so they hold no nav or logo reading and show nothing about colour; (b) `measured (3 morph runs), no
  colour unit before or after`; (c) the failing units before and after. Count over the 36 cells: (a) 12, (b) 3, (c) 21.
  Each cell is checked by re-reducing the one raw file of its artifact (`raw-playwright-webkit.json` in
  `trajectory-apple` and in `trajectory-playwright-webkit`, `raw-chromium.json` in `trajectory-chromium`). Legend for (c):
  `-` = no unit; `*` after a unit = new against the base arm, an unmarked unit fails in the base arm too; a `*` after a
  list or range marks every step in it as new (`close@0,7*` = close@0* close@7*); `aN` approach, `open@b`, `close@b` push
  buckets, `-hold` the hold after a push; ranges `3-9`, lists `3,5`.

| run, artifact | width | cell |
|---|---|---|
| 39453181962 apple | 390 | nav.background-color before `-` after `close@0`; logo.color before `a0 open@7-10 open-hold@10 close@1-10` after `a0 open@7-10 open-hold@10 close@1-10` |
| 39453181962 apple | 640 | nav.background-color before `open@2-4 close@0* close@8` after `open@2-4 close@0,8 close-hold@0*`; logo.color before `open@2-4 close@8` after `open@2-4 close@8` |
| 39453181962 apple | 641 | nav.background-color before `a3 a8* a11* open@2` after `a3 open@2 close@0`; logo.color before `open@2` after `open@2` |
| 39453181962 apple | 1280 | nav.background-color before `a7* open@3,5* close@0*` after `open@3,5* close@0 close-hold@0*`; logo.color before `open@3,5*` after `open@3,5*` |
| 39453181962 playwright-webkit | 390 | not measured (0 morph runs) |
| 39453181962 playwright-webkit | 640 | not measured (0 morph runs) |
| 39453181962 playwright-webkit | 641 | not measured (0 morph runs) |
| 39453181962 playwright-webkit | 1280 | not measured (0 morph runs) |
| 39453181962 chromium | 390 | nav.background-color before `open@1` after `open@1`; logo.color before `a0 open@1,6-10 open-hold@10 close@0-10` after `a0 open@1,6-10 open-hold@10 close@0-10` |
| 39453181962 chromium | 640 | measured (3 morph runs), no colour unit before or after |
| 39453181962 chromium | 641 | nav.background-color before `open@1*` after `open@1*`; logo.color before `open@1*` after `open@1*` |
| 39453181962 chromium | 1280 | nav.background-color before `a7*` after `-`; logo.color before `-` after `-` |
| 39471466367 apple | 390 | nav.background-color before `open@3* close@0* close-hold@0` after `open@3* close@0 close-hold@0`; logo.color before `a0 open@3*` after `a0 open@3*` |
| 39471466367 apple | 640 | nav.background-color before `open@2 close@0,7* close@8 close-hold@0*` after `open@2 close@0,8 close@7*`; logo.color before `open@2 close@7* close@8` after `open@2 close@7* close@8` |
| 39471466367 apple | 641 | nav.background-color before `open@3* open@4 close@0* close@8 close-hold@0*` after `open@3* open@4 close@0,8`; logo.color before `open@3* open@4 close@8` after `open@3* open@4 close@8` |
| 39471466367 apple | 1280 | nav.background-color before `open@2* open@4 close@0 close-hold@0*` after `open@2* open@4 close@0`; logo.color before `open@2* open@4` after `open@2* open@4` |
| 39471466367 playwright-webkit | 390 | not measured (0 morph runs) |
| 39471466367 playwright-webkit | 640 | not measured (0 morph runs) |
| 39471466367 playwright-webkit | 641 | not measured (0 morph runs) |
| 39471466367 playwright-webkit | 1280 | not measured (0 morph runs) |
| 39471466367 chromium | 390 | nav.background-color before `open@1 close@0* close-hold@0*` after `open@1 close@0*`; logo.color before `open@1` after `open@1` |
| 39471466367 chromium | 640 | nav.background-color before `open@1 close@0* close-hold@0*` after `open@1 close@0*`; logo.color before `open@1` after `open@1` |
| 39471466367 chromium | 641 | nav.background-color before `open@2* close@0* close-hold@0*` after `open@2* close@0*`; logo.color before `open@2*` after `open@2*` |
| 39471466367 chromium | 1280 | nav.background-color before `close@0* close-hold@0*` after `close@0*`; logo.color before `-` after `-` |
| 39457063232 apple | 390 | not measured (0 morph runs) |
| 39457063232 apple | 640 | not measured (0 morph runs) |
| 39457063232 apple | 641 | not measured (0 morph runs) |
| 39457063232 apple | 1280 | not measured (0 morph runs) |
| 39457063232 playwright-webkit | 390 | nav.background-color before `open@1,3-9 close@0,3-6,9` after `open@1,3-9 close@0,3-6,9 close-hold@0*`; logo.color before `a0 open@1,3-9 open@10* close@0* close@3-6,9` after `a0 open@1,3-9 open@10* close@0* close@3-6,9` |
| 39457063232 playwright-webkit | 640 | nav.background-color before `open@1,3-9 close@0,1,4,6,8,9 close@3* close-hold@0*` after `open@1,3-9 close@1,4,6,8,9 close@3* close-hold@0`; logo.color before `open@1,3-9 close@1,4,6,8,9 close@3*` after `open@1,3-9 close@1,4,6,8,9 close@3*` |
| 39457063232 playwright-webkit | 641 | nav.background-color before `a3 open@3-8 close@2,3,5-7,9` after `open@3-8 close@0,2,3,5-7,9`; logo.color before `open@3-8 close@2,3,5-7,9` after `open@3-8 close@2,3,5-7,9` |
| 39457063232 playwright-webkit | 1280 | nav.background-color before `open@2-8 close@0* close@1,3-7,9 close-hold@0` after `open@2-8 close@0* close@1,3-7,9 close-hold@0`; logo.color before `open@2-8 close@1,3-7,9` after `open@2-8 close@1,3-7,9` |
| 39457063232 chromium | 390 | measured (3 morph runs), no colour unit before or after |
| 39457063232 chromium | 640 | nav.background-color before `open@1` after `open@1`; logo.color before `open@1` after `open@1` |
| 39457063232 chromium | 641 | measured (3 morph runs), no colour unit before or after |
| 39457063232 chromium | 1280 | nav.background-color before `-` after `close@0*`; logo.color before `-` after `-` |

  Every run in each trajectory-leg-* artifact of 39453181962 and 39471466367 is identical (as parsed JSON) to a run in its
  whole-run artifact (12 of 12 per engine); 39457063232 has no leg artifacts. The leg artifacts are not tabulated again.
  The A/A is the base arm against the original: a unit without `*`
  fails in both, and the long unmarked lists (`open@1,3-9`, `close@1,4,6,8,9`) are not colour-space units and did not
  change. The approach units a7, a8, a11 (new before) were colour space and are gone. `close@0` and `close-hold@0`
  remain, some gained, some lost: both arms are now in sRGB and the candidate's reading differs by 7 to 8 channel levels
  from the original's, outside 2 (MEASURED: 39453181962 Chromium 1280 candidate rep 1 holds `[243.7, 243.9, 244.7]` for
  218 ms from the class change while the original reads `[251.0, 251.0, 251.0]`; Mac 1280 original ramps 244.7 to 255
  over 700 ms where a base rep starts at 252.3). INFERRED: where the colour starts depends on the interrupted earlier
  transition, a timing case (follow-up `trajectory-close-start`), not the colour space. Every new (`*`) unit after
  normalisation, at the start of the close or not, is a marker in the table.
  Coverage fails are not colour units and did not change.
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

### Transition start and settled push end (task trajectory-close-start)

Re-reduced (MEASURED, no new dispatch) with `reduce.mjs` before and after this task over every `raw-<engine>.json` of
runs 39466179818 (`?fw=hero.exit:scoped`), 39472217441 (`?fw=hero.exit:faithful`, the A/A), 39453181962 and 39453764374
(`?preset=` of 8 flags), 39449092483 (`?fw=morph.tween:waapi`) and 39457767229 (`?fw=morph.tween:waapi-scoped`); old
colour tuples converted by `colourFromV1` in both columns. Hero: no unit changed in any artifact. Morph, content `new`
groups (`-` none); coverage `new` groups are the same before and after in every cell:

| run | engine | width | before | after |
|---|---|---|---|---|
| 39466179818 | mac-webkit | 390 | bg close-hold@0; earn.max-width close@0 | bg close@0,close-hold@0; earn.max-width close@0 |
| 39466179818 | mac-webkit | 640 | bg close-hold@0 | bg close-hold@0 |
| 39466179818 | mac-webkit | 641 | bg a7 | bg a7 |
| 39466179818 | mac-webkit | 1280 | nav.rect, nav.transform.shift close@0 | - |
| 39466179818 | chromium | all 4 | - | - |
| 39472217441 | mac-webkit | 390 | bg close-hold@0; earn.opacity, earn.max-width close@0 | bg close@0,close-hold@0 |
| 39472217441 | mac-webkit | 640 | bg close@0 | - |
| 39472217441 | mac-webkit | 1280 | earn.max-width close@0 | - |
| 39472217441 | chromium | 640 | earn.max-width close@0 | - |
| 39453181962 | mac-webkit | 640 | bg close-hold@0 | bg close-hold@0 |
| 39453181962 | mac-webkit | 641 | earn.max-width close@0 | - |
| 39453181962 | mac-webkit | 1280 | nav.rect, bg close-hold@0, nav.transform.shift, actions.gap close@0 | nav.rect, bg close@0,close-hold@0, nav.transform.shift, actions.gap close@0 |
| 39453181962 | chromium | 1280 | - | earn.max-width close@0 |
| 39453764374 | linux-webkit | 390 | nav.rect close@0; bg close@0,close-hold@0; earn.opacity open@10,close@0; earn.max-width close@0,close-hold@0 | bg close@0; earn.opacity open@10 |
| 39453764374 | linux-webkit | 1280 | - | nav.rect close@0; nav.transform.shift close@0,close-hold@0; actions.gap close@0 |
| 39449092483 | chromium | 640 | bg close@0; earn.max-width close@0 | earn.max-width close@0 |
| 39449092483 | chromium | 641 | bg close@0; earn.max-width close@0 | - |
| 39449092483 | linux-webkit | 390 | earn.opacity, earn.max-width open@10 | nav.rect, actions.gap close@0; earn.opacity open@10; earn.max-width open@10,close@0 |
| 39449092483 | linux-webkit | 640 | nav.cls.is-morphing, logo.position, logo.transform-origin, earn.opacity, earn.max-width, panel.attr.data-start-selling-scene close@0 | actions.gap, earn.opacity, earn.max-width close@0 |
| 39449092483 | linux-webkit | 641 | bg a3; earn.max-width close-hold@0 | bg a3 |
| 39449092483 | linux-webkit | 1280 | earn.opacity, earn.max-width open-hold@10,close@10 | nav.rect, nav.transform.shift close@0; earn.opacity, earn.max-width open-hold@10,close@10 |
| 39457767229 | chromium | 390 | bg close@0; earn.max-width close@0 | bg close@0 |
| 39457767229 | chromium | 640 | bg close@0; earn.max-width close@0 | earn.max-width close@0 |
| 39457767229 | chromium | 1280 | - | earn.max-width close@0 |
| 39457767229 | linux-webkit | 390 | 12 groups close@0 (nav, logo, earn, panel) | bg, logo.color, earn.opacity, earn.max-width close@0 |
| 39457767229 | linux-webkit | 640 | bg, earn.opacity, earn.max-width close@0 | nav.backdrop-filter.num, earn.filter.num close@0 |
| 39457767229 | linux-webkit | 641 | bg close-hold@0; earn.opacity close@0; earn.max-width open@10,close@0 | - |
| 39457767229 | linux-webkit | 1280 | nav.rect, bg close@2; nav.transform.shift close-hold@0 | nav.rect, bg close@2 |

`bg` = `nav.background-color`. A morph cell not listed has the same content `new` groups before and after. Lean outcome lines
(`Fw.Preset.Gen.storedOf` and `outcome` over the re-reduced units, nothing stored), before → after:

| run | mac-webkit morph | chromium morph | linux-webkit morph |
|---|---|---|---|
| 39466179818 | fail → fail | pass → pass | - |
| 39472217441 | fail → no verdict: coverage | pass → pass | - |
| 39453181962 | fail → fail | pass → pass | - |
| 39453764374 | - | pass → pass | no verdict: coverage → no verdict: coverage |
| 39449092483 | - | fail → fail | no verdict: coverage → no verdict: coverage |
| 39457767229 | - | fail → fail | no verdict: coverage → no verdict: coverage |

Every hero outcome is `pass` before and after. `hero.exit:scoped` (39466179818) still fails on macOS WebKit morph:
`nav.background-color` is content `new` at 390, 640 and 641. MEASURED at 390 close@0: the candidate's rep 0 reads
`[226.5, 227.1, 228.5]` 29 ms into the close, while every pass of the original starts the close between 249.3 and
252.3, so the envelope cannot pass it (Limits: a start outside every pass). Some units moved from `both` to `new`: the
base arm now passes them while the candidate still fails (39466179818 mac 390 bg close@0, 39453181962 Chromium 1280
earn.max-width close@0). Linux WebKit `ok` to `both` units (39453764374 390 close-hold@0): the sample's own pass has no
core sample, another pass has one, and the reading is outside it (Limits: a pass does not fall back on its own).

Scope (accepted limit, lead sign-off 2026-10-21): the envelope judges every in-flight sample of a transition epoch, not
only its start, and a pass with no core sample of its own no longer falls back on its own m-window. This is stricter
than the old rule in some cells: new failures on Linux WebKit 1280 (39453764374), Linux WebKit 390 and 1280
(39449092483) and Chromium 1280 earn.max-width close@0 (39457767229). A rewrite pass with no counterpart in the
original is now judged against the envelope of the original's passes; the old 'no counterpart' coverage fail is gone
(golden cases 'in flight, other pass' pass to fail:apart, 'in flight, other pass, no counterpart' fail:coverage to
pass; renamed in the next section). The scope is decided, and every changed cell explained, in the next section.

### Envelope scope (task trajectory-envelope-scope)

Decision: the envelope keeps its scope (every in-flight sample of the epoch, no own-pass fallback while another pass
has a core sample). The rejected alternative is Lean `judgeScoped`: the envelope only while `atStart` (the sample is
within `startLag` of the first sample of its epoch in the original's own pass), else `judgeOwn` with its m-window
fallback (`judgeScoped_start`, `judgeScoped_later`). Against the threat model:

- `judgeScoped_stuck_hold`: a box stuck at its start value 400 ms into a hold transition, in a pass the original lacks,
  passes `judgeScoped` (the hold's m-window pools every sample of the hold) and fails the envelope. A pooled stuck
  value must fail, so the fallback cannot come back.
- `judgeScoped_other_curve`: a pass that keeps another pass's start red 500 ms into the transition passes the envelope
  and fails `judgeScoped`. Start jitter need not fail, also after the start.
- `judgeUnit_sound`: a component more than the tolerance beyond every reading of the original's whole path never
  passes, in every branch (in flight, the fallback, at rest; a colour's channel or alpha), when the window holds samples
  of the path (`windowAt_sub`).
- `judgeUnit_mutations`: pure red and pure green over two passes, the reversed curve at buckets 2 and 7 over two passes
  and in one, the stale class, the stuck value pooled over passes, and the stuck hold above all fail.

Re-reduced (MEASURED, the six runs above, 16 artifacts, scratch downloads): the shipped reducer changes no unit against
main. Content failures summed over the 16 artifacts (morph; `new` = candidate content `new`):

| rule | faithful arm fails | candidate fails | candidate `new` |
|---|---|---|---|
| before close-start (own pass, old windows) | 441 | 476 | 71 |
| main = this task (envelope) | 386 | 405 | 52 |
| `judgeScoped` | 406 | 421 | 52 |
| envelope, core of any phase (follow-up) | 381 | 392 | 46 |

`judgeScoped` re-fails 20 faithful-arm units and changes which candidate units are new (5 cleared, 5 added, net 0 over the 16 artifacts). Of the 117 units close-start changed, 29
come from `windowAt` and 88 from the envelope; 18 end `new`. 58 of the 88 clear a failure in one arm or both (to `ok`
or `cleared`): the reading lies inside another pass's transition. One fails the faithful arm (39457767229 Linux WebKit
1280 actions.gap close@0, `ok` to `cleared`): its pass 1 reads 0.04 px 163 ms into the close; the original's pass 1 read
that epoch only in the hold, so it has no same-phase core and only pass 0 (1.35 px at 170 ms) judges the sample. In 13 of the 14 envelope `both` to `new` units the
candidate's `fail:apart` stays (the 14th, 39457767229 Linux WebKit 1280 nav.rect close-hold@0, is below) and the faithful arm's failing samples lie inside the envelope (2 more come from
`windowAt`: 39457767229 Linux WebKit 640 nav.backdrop-filter.num and earn.filter.num close@0). Chromium 39457767229
1280 earn.max-width close@0: the faithful arm's passes start the close at 12.87, 11.23 and 9.98 px (the own-pass rule
failed passes 1 and 2, start jitter); the candidate's pass 0 reads 7.36 px 6 ms in, beyond every pass. The Linux WebKit
close@0 units of 39453764374 and 39449092483 (nav.rect, nav.transform.shift, actions.gap, earn.max-width) are the same
kind of `both` to `new`.

`close-hold@0` cells are in-flight samples judged by the envelope, not by `windowOf`/`settledRef`:

- 39453764374 Linux WebKit 390 (7 groups `ok`/`new` to `both`), 1280 nav.transform.shift (`cleared` to `new`) and
  39449092483 Linux WebKit 640 earn.max-width (`cleared` to `both`): the sample's own pass has no core sample of its
  epoch, so the old rule fell back to the hold's m-window, which pools the start and the settled end. Other passes'
  readings of the epoch at that time may be in the push (phase 2), and the core is same-phase, so the envelope holds
  few samples. At 1280 the candidate reads -492.07 px 210 ms in, settled, where the original's pass 2 still reads
  -596.72 at 119 ms and -495.34 at 537 ms.
- 39466179818 macOS WebKit 640 nav.background-color (`new` in both): the candidate's pass 3 reads 251.3 491 ms in;
  every same-phase core reading within 200 ms is 253.66 or more (tolerance 2). Pass 0 read 252.6 at 310 ms in the push;
  a core of any phase passes it.
- 39472217441 macOS WebKit 390 nav.background-color (A/A, `new` in both): the candidate's pass 4 reads
  `[242.0, 242.3, 243.0]` 412 ms in; every reading of the original within 200 ms, any phase, is 249.97 or more. The pass
  lags beyond the slack; every rule above fails it.
- 39449092483 Linux WebKit 1280 earn.max-width (`unmeasured` to `both`), 39457767229 Linux WebKit 641 nav.bg (`new`)
  and 1280 nav.rect (`both` to `new`): the candidate's first failure in the bucket went from `apart` to `coverage`,
  a sample with no counterpart that failed before too; the earlier sample now passes the envelope.
- 39453764374 Linux WebKit 1280 nav.background-color close-hold@0: unmeasured to both: the faithful arm's in-flight sample now has an envelope and fails apart instead of coverage.

Limit and follow-up: `isCore` keeps the sample's phase, so readings of the same epoch taken in the push before a hold
are no core for a hold sample (row 4 of the table, MEASURED, not adopted here).

Limit: judgeUnit_sound bounds a reading against the range of the whole original path (every phase, epoch and class set) and needs every reading in it to have the same shape (n elements, numeric); one absent or string reading makes it vacuous for that path.

### Earn close start (tasks earn-close-start-rule, earn-close-chain-rule, earn-close-settle-rule)

Mechanism (MEASURED, the four runs below): in close@0 the earn button's `opacity` and `max-width` follow one CSS
transition per trigger. A trigger is a sample whose `--earn-out` (Lean `collapse`, `clamp01(m / darkCut)`, `darkCut` =
0.2) differs from the sample before it in the same pass and phase. Each trigger retargets the transition from the value
in flight, so the reading at a later trigger depends on when the earlier triggers fell. Two passes of the same original
already differ there (MEASURED, 39508421419 macOS WebKit 641 px, the first triggers equal): opacity at trigger 4 reads 0
in pass 0 and 73 in pass 3 (`tol` 10); max-width at trigger 4 reads 2285 in pass 1 and 69491 in pass 3, 67206 apart
(`tol` 1000). Lean `ooOpacity` and `ooMaxWidth` hold the readings, `#guard`s the differences. So no rule can bound a
later trigger by the original's reading there; round 2 (`chainCost`) tried and was closed as a finding.

Rule (Lean `startCheck`, `settleCheck`, `byMStart`; TS twin of the same names in `reduce.mjs`), only the units of
`startOn` (earn `opacity`, earn `max-width`). `full` is the value at rest (`fullOf`, `Nav.lean` 266-269 and 274, which restate the original CSS (snapshot lines 11480, 11483, 11485, 11594-11596), ported in
`apps/site/src/parts/nav/nav.module.css` 170, 173, 176 (opacity) and 285): opacity 1, max-width 11rem = 176 px, 9.5rem = 152 px up to
640 px. Values are times 1000.

- close@0 (push of the close, bucket 0), for a rewrite sample `r` after the earlier samples of its pass:
  - Anchor: the reading at the pass's first trigger lies within `tol` of `s`, the reading at the original's first
    trigger of the same pass and phase (`origFirst`).
  - Range: `r`'s reading lies in `[s - tol, full + tol]`.
  - Both hold: pass; one fails: `fail apart`; no trigger up to `r`, no original trigger or a reading that is not one
    number: `judgeUnit` decides as before. Every other bucket of the close is `byM` (`byMStart_keeps`).
- close-hold, every bucket: `byM`, and in addition each rewrite sample read `settleAt` = duration + delay + 80 ms or
  more after the last trigger of its pass's close and close-hold reads within `tol` of `full`. A refusing sample turns
  a passing bucket into `fail apart` (`settleAnd`); otherwise the bucket keeps `byM`'s verdict.

Proved (`lean/Fw/Gate/Trajectory.lean`, section `CloseStart`):

- `byMSettle`: a close-hold bucket `byMStart` passes, `byM` passes; the settle check is never more lenient than `byM`.
  `byMSettle_keep`: with no refusing settle check the close-hold is `byM`.
- `startCheck_pass_iff`: with every part found and `s ≤ full`, a sample passes exactly when the trigger reads within
  `tol` of `s` and `r` reads in `[s - tol, full + tol]`. `settleCheck_pass_iff`: read late enough, a sample passes
  exactly when it reads within `tol` of `full`. `fullOf_opacity`, `fullOf_phone`, `fullOf_wide`.
- Branches: `startCheck_found`, `_no_trigger`, `_no_orig`, `_no_reading`; `judgeStart_on`, `_off`, `_undecided`;
  `settleCheck_found`, `_early`, `_no_trigger`, `_no_part`; `settleAnd_keep`, `_refuse`, `_other`, `_pass`;
  `byMStart_none`, `_other`, `_keeps`, `_bucket0`; `startOn_opacity`, `startOn_maxWidth`, `startFor_off`.
- Mutations, each refused in a named cell of the judge (`byMStart` at 390 px, opacity):
  - `byMStart_stale` (the trigger reads 600 instead of 0): close@0, anchor.
  - `byMStart_reversed` (1 to 0): close@0 by the anchor and close-hold@0 by settle.
  - `byMStart_collapsed` (stays at 0): passes close@0 (inside the range), refused at close-hold@0.
  - `byMStart_target` (rests at 0.9): `byM` passes close-hold@0 against the original's in-flight 895, settle refuses.
  - `byMStart_duration` (463 ms instead of 320): reads 989 at settle time, refused at close-hold@0.
- Smallest refused change (one trigger, rise from 0), read exactly `settleAt` after the trigger and rounded half up as `kit.mjs` 43 rounds
  (`readRise`, `rounded_iff`, `settle_dur_iff`, `settle_delay_iff`, monotone by `along_dur_le` and `along_delay_le`):

| unit | duration | delay |
|---|---|---|
| opacity (320 ms after 120 ms) | +143 ms (`settle_opacity_duration`) | +124 ms (`settle_opacity_delay`) |
| max-width above 640 px (680 ms) | +166 ms (`settle_wide_duration`) | +149 ms (`settle_wide_delay`) |
| max-width up to 640 px (680 ms) | +173 ms (`settle_phone_duration`) | +154 ms (`settle_phone_delay`) |

Read later than `settleAt`, or from a start above 0 (real last triggers start in flight, up to 73/1000 opacity and tens of
px max-width), the smallest refused increase is larger; read earlier, the check does not decide.

Accepted limits (each a theorem or a measurement):

- (i) Another curve, or a shorter duration, with the same endpoints passes close@0 (`byMStart_curve`: linear max-width
  at 390 px; the 320 ms opacity where `is-hero-pill` runs 200 ms).
- (ii) A close-hold with no refusing settle check is `byM` (`byMSettle_keep`); a pass with no late sample adds only
  undecided checks (`settleCheck_early`).
  MEASURED: 0 of 12280 macOS WebKit and 0 of 19722 Chromium close@0 samples of the four runs are read that late, so the
  settle check never decides in close@0; close-hold samples read that late: macOS WebKit 788 of 1338, 781 of 1396, 742
  of 1284, 765 of 1358 per run.
- (iii) Drift inside the range passes (`byMStart_drift`: 9, 18 and 27 above the original at three triggers, at rest
  and while moving, pass close@0 and close-hold@0). This is the finding of round 2.
- (iv) `startJitter` = 80 ms (MEASURED in round 1), in `settleAt`.
- (v) `tol` 0.01 opacity, 1 px max-width.
- (vi) Any close@0 in-flight reading inside `[anchor - tol, full + tol]` passes.
- (vii) When `startCheck` decides a bucket-0 sample it bypasses `judgeUnit`, including its coverage outcomes (no
  window, no counterpart in the original). Follow-up: run the coverage branch first.
- Wrong `darkCut` (0.25 instead of 0.2) is NOT caught: `byM` judges it in close buckets 1 and 2, and the change there
  (at most 0.9 px; 1.06 px later in bucket 0, inside the range; opacity unmoved) is inside tol 1 px. INFERRED from a
  float simulation of the 39508421419 pass 0 timeline at 1280 px (scratch script, not committed).

Re-reduced (MEASURED, raw artifacts of the four runs reduced by main's reducer at 74fccd34 and by this rule; "stored" is
the run's own units file). Candidate `new` units on macOS WebKit:

| run | search | stored | main | after |
|---|---|---|---|---|
| 39466179818 | hero.exit:scoped | 176 | 173 | 172 |
| 39472217441 | hero.exit:faithful | 130 | 128 | 128 |
| 39508414669 | hero.exit:scoped | 257 | 257 | 253 |
| 39508421419 | hero.exit:faithful | 44 | 44 | 44 |

Chromium (0, 0, 84, 0) and Linux WebKit (0 in all four) keep their counts. Every unit that changes against main is an
earn close@0 unit on macOS WebKit (candidate / base / rel); no close-hold unit changes:

| run | width | property | main | after |
|---|---|---|---|---|
| 39466179818 | 390 | max-width | fail apart / pass / new | pass / pass / ok |
| 39466179818 | 640 | max-width | pass / fail apart / cleared | pass / pass / ok |
| 39472217441 | 640 | opacity | pass / fail apart / cleared | pass / pass / ok |
| 39472217441 | 640 | max-width | fail apart / fail apart / both | pass / pass / ok |
| 39508414669 | 390, 641 | opacity | fail apart / pass / new | pass / pass / ok |
| 39508414669 | 390, 641 | max-width | fail apart / pass / new | pass / pass / ok |
| 39508421419 | 640 | max-width | fail apart / fail apart / both | pass / pass / ok |

Limit: the anchor needs the original's first trigger to read like the rewrite's; a pass whose first trigger falls
mid-transition in one arm only is judged `fail apart`. Admission of the scoped arm is task close-start-identity-rule.

### Close start by identity (task close-start-identity-rule)

Mechanism (CONFIRMED from source, MEASURED in the five runs below): the nav background is
`color-mix(in srgb, #ffffff1a (1 - m), #131922 m)` of `--morph` m (snapshot `site-pretty/_app/immutable/assets/2.gBuqKVzi.css` 11336-11340, ported in
`apps/site/src/parts/nav/nav.module.css` 22-26; Lean `bgRed`, `bgAlpha` in `lean/Fw/Parts/HeroExitCloseStart.lean`).
`is-morphing` is on while m > `Nav.morphingCut` = 1/1000 (`Nav.lean` 35, `logic.ts` 10 and 63). When the class goes, the
background transition starts from the colour of the last morph value with the class, so the first sample without it reads
that colour, and the original need not have read the same start (its pass removes the class at another m).

Rule (Lean section `CloseIdentity`: `idCheck`, `idJudge`, `byMId`, `byMRule`; TS twin of the same names in `reduce.mjs`),
only nav `background-color` (`idOn`), every phase. For a rewrite sample `r` and `q`, the last sample of the same arm and
pass before it (`withPrev`): when `q` has `is-morphing`, `r` has not, `r` is in flight and read at most `startLag` = 200 ms
after the class change (`idFresh`), then with m stored times 10000 (`kit.mjs` 228):

- `cutM` = 10 ≤ m(q) and m(r) ≤ 10 (`cutM_eq`, `roundM_above`, `roundM_below`: `Nav.morphingCut` through the probe's rounding);
- red within 0.5 of `bgRed m(q)` and alpha within 0.5 of `255 bgAlpha m(q)`, 0-255 scale (`redOk_iff`, `alphaOk_iff`,
  cross-multiplied with `mixFrom` = (255, 26) and `mixTo` = (19, 255), the CSS's red and alpha);
- all hold: pass; one fails: `fail apart`. Every other sample is `judgeUnit`'s, and a bucket combines its samples as before.

Proved: `idCheck_css` (the check is the cut and half a level of `bgRed`, `bgAlpha`), `idCheck_some` (it decides only that
first fresh in-flight sample), `idCheck_no_prev`, `idCheck_late`, `idJudge_undecided`, `byMId_keep` (no decided sample:
`byM`), `idBucket_fail_undecided` (never more lenient than `byM` on the samples it does not decide: a sample `byM` fails
there keeps the bucket failing), `idBucket_refuse`, `byMRule_off`, `byMRule_on`. Mutations, each refused in cell
close@0 at 390 px (`navAt`, `(…).lookup 0 = some (.fail .apart)`):

| mutation | theorem | refused by |
|---|---|---|
| early removal: class off at m 0.03 | `byMId_early` | cut on m(r) |
| late removal: class still on at m 0 | `byMId_late` | cut on m(q) |
| stale reading: the target colour at once | `byMId_stale_target` | red |
| stale reading: the colour of an earlier frame (m 0.004 for 0.002) | `byMId_stale_frame` | red |
| wrong f: red not premultiplied | `byMId_wrong_f` | red |
| wrong f: alpha at 1 | `byMId_wrong_alpha` | alpha |
| one level along the transition | `byMId_progress` | red |

The faithful sample passes (`byMId_self`). `main`'s judge passes the faithful sample and the one-level mutation and fails
the others (scratch evaluation, colour tolerance 2 levels).

Accepted limits:

- (i) The rule assumes the probe reads `r` at transition progress 0. MEASURED over every arm of the five runs: the rule
  decides 421 samples (macOS WebKit 120, Chromium 228, Linux WebKit 73) and passes all of them; red is at most 446
  thousandths of a level from `bgRed m(q)`, alpha 11; they are read at most 57, 14 and 195 ms after the change. A sample
  read later than `startLag` is `byM`'s (`idCheck_late`, `byMId_read_late`): 22 Linux WebKit samples, among them two read
  694 and 721 ms after the change (39448209903) that read the end colour and would be refused without the bound.
- (ii) Half a level passes (`byMId_half`); green and blue are not checked: the stored old-kit oklab tuples convert back with
  up to 0.64 level error (`colourFromV1`, TS glue, `kit.mjs` 28), and green and blue are 315 and 502 thousandths off at
  that sample (MEASURED, red 446).
- (iii) Rounding: m 1/1000 and 1049/1000000 both store 10 (`roundM_tie`), so a removal up to 0.000049 early passes.
- (iv) The decided sample passes any gap between `q` and `r` (`idCheck_t0`). Larger gap regressions (above B's minimum
  detectable effect, 0.31 ln g, p 0.492) are caught only by `byM` on later samples of the pass, which is unproved; the
  follow-up rule for those later samples must keep a gap check.
- TS stand-in: `colourFromV1` (old-kit oklab to sRGB, `reduce.mjs`) runs inside `idCheck` in production; Lean has no
  conversion and the golden calls `idCheck` without it.
- (v) Admission retry of hero.exit scoped is a separate task (admit-hero-exit-scoped).

Re-reduced (MEASURED, raw artifacts reduced by main's reducer and by this rule). Every unit that changes (candidate / base /
rel), all Linux WebKit nav `background-color`. No candidate or base verdict goes from pass to fail; one relative verdict goes
from both to new (39452631146 390 close@0), so Linux WebKit `new` rises 58 -> 59:

| run | width | step | main | after |
|---|---|---|---|---|
| 39448209903 | 640 | close@0 | fail apart / fail apart / both | pass / pass / ok |
| 39448209903 | 641 | close@0 | fail apart / pass / new | pass / pass / ok |
| 39452631146 | 390 | close@0 | fail apart / fail apart / both | fail apart / pass / new |
| 39452631146 | 640 | close-hold@0 | fail apart / fail apart / both | pass / pass / ok |
| 39456741492 | 390 | close@0 | fail apart / fail apart / both | pass / fail apart / cleared |
| 39456741492 | 640 | close-hold@0 | pass / fail apart / cleared | pass / pass / ok |

`new` counts, main to after: Linux WebKit 52 to 51 (39448209903), 58 to 59 (39452631146), 171 (39456741492); macOS WebKit
and Chromium keep theirs (172 and 128 macOS WebKit in 39466179818 and A/A 39472217441).

Finding: admission of hero.exit scoped cannot proceed on this rule. The identity check passes every first sample in the
target cells (macOS WebKit close@0 at 390 and 640 px in 39466179818, 390 px in the A/A 39472217441), but the later
in-flight samples of one pass per cell still fail `byM`: passes whose class went at m(q) 133 to 282 (sample gaps), read 60
to 226 ms after the change, move from `bgRed m(q)` while the original's envelope moves from near the cut. Chromium
39448209903 1280 px close@0 fails the same way (m(q) 106). Judging those samples needs the transition from `bgRed m(q)`
(curve and duration of the nav background), a follow-up rule.

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
