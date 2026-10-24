# Offscreen counts lane

Counts the rendering work of the rewrite while `#platform` is offscreen, so an offscreen-pause brick (`platform.sweep:offscreen-pause`,
`platform.glint:offscreen-pause`) can show its gain. Chromium only; WebKit is a named follow-up (WKTR runs the original only).

## Run it

Push a `ci/<task>` branch whose head commit message carries both the trigger and the lane line:

```
[ci:chromium-counts] [counts profile=offscreen-v1 runs=3 target=both arms=platform.sweep:offscreen-pause|platform.glint:offscreen-pause]
```

`chromium-counts.yml` (plan job) reads the line with `offscreen.mjs line`. Arms are labelled `original`, `rewrite` (base), `f1`, `f2`
(up to 4, flag sets split by `|`). Every (arm, run) is its own job and VM; each extra arm is prerendered as a `--config` page. The
`offscreen` job downloads the per-run `offscreen.json` and writes `offscreen-summary` (`summary.json`, `summary.md`, also in the step
summary). Raw traces (zstd, 14 days) stay in `offscreen-trace-<arm>-<run>` for an offline re-reduce.

## What is counted

Profile `profiles/offscreen-v1.json`: segments `top` (120 frames), `near` (60, `#platform` at the viewport top), `back` (120). The
card probe records the `#platform` rect per frame. A frame is hidden when the rect has no overlap with the viewport
(`Fw.Measure.Offscreen.Rec.hidden`); the window drops the first `settle = 3` frames of each hidden run (`steady`), so a pause that
takes a few frames to engage does not count as a gain. Per run the lane sums, over the steady hidden frames, `metric.RecalcStyleCount`,
`metric.LayoutCount`, `trace.UpdateLayoutTree/Layout/PrePaint/Paint/Commit`, `trace.cc.Draw`, `trace.cc.BeginMainFrame`,
`trace.cc.NeedsTick`, `trace.cc.TickAnimations`, `trace.FireAnimationFrame` (animation ticks of cc and Blink). The offscreen runs set
`FW_NO_LAYERS=1` (no layer snapshots; `census.*` keys absent).

## Verdict (Lean, `lean/Fw/Measure/Offscreen.lean`)

Per flag against `rewrite`, each flag on its own: `gain` when no counter is more and at least one is less; `noGain` when a counter is
more or none is less; `noData` when fewer than `minRuns = 3` runs, a different window length, or an empty window. Counter compare:
`less`/`same`/`more` with the range of the repeats as the noise bound (`slack = 0`). `original` is a per-frame mean reference only.
Golden `packages/contracts/golden/measure/offscreen.jsonl`, replayed by `packages/measure-chromium/test/offscreen.test.mjs`.

## TS stand-ins (no Lean golden)

`extraTraceCounts` (trace-event attribution of `BeginMainFrame`, animation ticks, `RunTask`), `reduceRun` (record schema
`fw.offscreen/1`), `groupRuns`, `summarize`, `markdown`, `parseLine` and the CLI (`reduce`, `summarize`, `line`). The decision
functions (`hidden`, `steady`, `windowVec`, `cmp`, `verdict`) are the golden-checked twins.

## Limits

Counts are engine work, not felt smoothness. Trace names (`AnimationHost::TickAnimations`, `NeedsTickAnimations`, ...) come from the
pinned Chromium source; `seen` totals in `offscreen.json` show an absent name. The `counts (<arm>, r<n>)` job names of `f1..f4` are
not shards for `Fw.Store.Ci.shardOfJob`, so telemetry skips them. Sections other than `#platform` are follow-ups.
