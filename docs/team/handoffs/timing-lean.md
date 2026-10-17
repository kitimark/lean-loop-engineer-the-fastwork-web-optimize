# timing-lean handoff

State: `lean/Fw/Obs/Timing.lean` (+ import in `lean/Fw.lean`) and `packages/contracts/golden/obs/timing.jsonl`
(11 cases), committed on the worktree branch of task timing-lean. `sh lean/scripts/check.sh` green, no new mathview warnings.

Model (read the module doc first):
- Sample (tool, step, durMs, host local|ci, load = floor of 1-min load avg); key = (tool, step, host).
- Local samples with load > loadMax (default 16 = 2 x 8 cores) are `noisy`: own verdict, never in a window. CI never noisy.
- Window = last N non-noisy same-key samples *before* the sample; baseline = nearest-rank p90 via counting (`ord`, `rank90 n = (9n+9)/10`).
- Code, first match: noBaseline (|w| < nMin), noisy, slow (d > B and kDen*d > kNum*b), ok. Budget: first per-tool override, else budgetMs (30 s).
- Structural: Stage = list of Groups (a group = keys of one job, e.g. matrix legs). Group baseline = max of its keys' final
  baselines, defined only when every key has one. Structural iff every sibling group has a baseline c with 2c < b.
- Entry point: `timingVerdicts p ss` = one SampleVerdict per sample in order, then StructVerdicts.

Theorems: slow_iff, no_alert_within_budget(_list), slow_mono_dur, noBaseline_iff, noBaseline_below_nmin, deterministic
(verdict depends only on same-key history), timingVerdicts_total, ord_le_iff, ord_interlace, ord_between,
outlier_between (new p90 between old p90 and y), outlier_bound (n >= 10: ord(r-2) <= p90' <= ord(r)), outlier_shift,
structural_iff, mem_structural. For windows < 10 values p90 = max, so only outlier_between bounds an outlier.

Golden: rendered by `Fw.Wire.Obs.Timing.goldenText` (end of Timing.lean). Regenerate from `lean/` with a script
`import Fw.Obs.Timing` + `def main : IO Unit := Fw.Wire.Obs.Timing.writeGolden` via `lake env lean --run`;
`checkGolden` compares. Gate case: real job durations of run 39067656223, one key per job, nMin 1 -> all samples
noBaseline; structural: stage breakpoint-gate:test, group sweeps, baseline 345000, siblingMax 147000.

Open for timing-alert: wire op `obs.timing` in Fw/Wire/Obs.lean (JSON shape = `caseJson`; add a decoder), move the golden
script to lean/scripts and the check into `lake test`, map timings.jsonl job names to keys/stages, tune loadMax/budgets.
wt-prep note: a long-lived `lean --server` in the main lean dir makes wt-prep skip the clone; `lake build` was still 2 s
from the artifact cache.
