# timing-slot-width handoff

- Branch `worktree-wf_d90cdaa9-b87-1`, worktree `.claude/worktrees/wf_d90cdaa9-b87-1`; last work commit in `git log -1`.
- CI runs: none (all checks local through `fw slot`; no CI push needed).

## State
- Lean `lean/Fw/Obs/Timing.lean`: `Sample.work` / `Key.work` (work dimensions, part of the history key); `slotWork width jobs`
  is the rule (width only; none without a width). Theorems: `slotWork_some`, `slotWork_none`, `slotWork_jobs`,
  `slotWork_width_ne`, `windowOf_filter_key`, `judgeQ_filter_key`, `judgeQ_same_work`, `judgeQ_other_work`,
  `windowOf_unworked` (no-work samples: the old four-field window), `judgeQ_unworked`.
- Golden: 5 `slot width:` rows in `packages/contracts/golden/obs/timing.jsonl`; new reader golden
  `packages/contracts/golden/obs/timing-work.jsonl` (span line to work), written and checked by `scripts/TimingGolden.lean`.
- Writer: `lean/scripts/check.sh` sets `span_more` with `"slot":{"width":$LAKE_SLOT_WIDTH,"jobs":$n}` for the parallel
  group; `scripts/span.sh` appends `span_more` to the line and clears it. A real run wrote `"slot":{"width":1,"jobs":97}`.
- Reader: `slotWork` in `apps/runner/src/timing.ts`, used by `parseSamples` (`apps/runner/src/watch-collect.ts`);
  `apps/runner/test/timing-work.test.ts` checks it against `timing-work.jsonl`. Wire decode `workOf` in `lean/Fw/Wire/Obs.lean`.
- `Fw.Wire.Obs.Timing.cases` takes `Unit` (init-cost bound: it reached 11270 allocations as a constant).

## Re-judge (offline, widths inferred from job spans: summed job time / group wall = 1.00 or 1.99)
- fw watch view (last 3000 spans) at 3d0d68a: old rule 3d0d68a `slow` (94 437 ms vs p50 49 426), 046ff5f `ok`;
  with width: both `noBaseline` (4 width-1 and 3 width-2 groups before them, n_min 5).
- Full history: with width both `ok` (width-1 p50 92 957 ms, width-2 p50 47 579 ms).

## Open / follow-ups
- Outside the graph writes: `scripts/span.sh`, `apps/runner/src/watch-collect.ts`, `lean/Fw/Wire/Obs.lean`.
- `Fw.Obs.Next.sameKey` ignores work: a later sample of another width hides an earlier slow one from `obs.slow`.
- timing-work-dims (work class of a polish commit) adds a dimension to `work`; old spans keep `work = []`.
