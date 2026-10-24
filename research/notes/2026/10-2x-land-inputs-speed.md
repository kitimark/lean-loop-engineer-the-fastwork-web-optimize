# After land-inputs-growth, the slow dry lands are the lake step on a merge tree nobody built; a pass on record for the same lean/ and golden trees removes it

Status: MEASURED (spans in `.fw-console/timings.jsonl`, local host, exit 0), cause CONFIRMED by the split below, the hit rate INFERRED. CI land-lane times and the watch thresholds are unchanged.

## Cause (CONFIRMED)

Cut at the landing of land-inputs-growth (commit 0fbd5719a, 1792822164000 ms). Medians of `fw land` dry spans:

| step | before (n) | after (n) |
|---|---|---|
| `slot run land ... dry` total | 33.7 s (553) | 25.9 s (98) |
| land-inputs vitest | 24.0 s (545) | 8.0 s (107) |
| lake build + axiom check | 7.0 s (524) | 9.8 s (105) |

The remaining spread is the lake step. The 98 dry lands after the cut, by `lake.built` of the same land's `fw`/`land dry lake` span:

| modules built | n | total | lake step | land-inputs |
|---|---|---|---|---|
| 0 | 37 | 18.0 s | 3.1 s | 8.0 s |
| 1-7 | 39 | 27.7 s | 13.0 s | 8.0 s |
| 8 or more | 20 | 44.4 s | 23.5 s | 8.0 s |

37 of 98 dry lands ran over 30 s; 35 of the 37 built at least one module. Land-inputs is flat (7.95-8.04 s) across the three rows, so the growth is the lake step alone. By load floor the median total is 21.9 s (load < 4), 25.0 s (4-5), 32.0 s (6+); the land-inputs median moves only 7.8 to 8.1 s.

Why modules rebuild: the dry land checks out the merge of the branch with the current `main`; `lake build` in that worktree rebuilds whichever modules differ from its last build (research/notes/2026/10-2x-land-wt-lake-rebuilds.md). The builder's `check.sh` already built and axiom-checked the branch tip, but the dry land cannot know that.

## Change

Lean `Fw.Ops.LandCache` (`lean/Fw/Ops/LandCache.lean`): the key is the `lean/` tree id and the `packages/contracts/golden/` tree id (the only paths outside `lean/` that `include_str` reads; the runner test scans every Lean file and fails on any other). `runLake touchesLean recs key = touchesLean && !hit recs key`; a record counts when it passed and has the same key.

Theorems: `hit_iff`, `hit_split` (a hit is a dry-land record or a check.sh record), `hit_of_dryLint`, `hit_of_checkSh` (one per source branch), `hit_failed` (failed records never skip), `hit_other_key`, `hit_other_lean`, `runLake_untouched`, `runLake_miss`, `runLake_hit`, and `skip_sound`: if every passing record's key passes `lake build` and the axiom check, a skipped step loses no failure. Golden: `packages/contracts/golden/ops/land-cache.jsonl` (nine rows, kept equal to the Lean output by a `#guard` with `include_str` in `LandCacheGolden.lean`), replayed by `apps/runner/test/land-inputs.test.ts` against TS `lakeHit`/`runLake` (TS stand-in for the Lean decision, golden-checked).

Sources of a record (`apps/runner/src/land.ts`, `lakeRecords`): (1) a passing `fw slot run --kind check --cache -- sh lean/scripts/check.sh` on any of the last 12 first-parent commits of the branch (its slot record, found by the slot's own cache key; the test replays a hand-written record through `slotCli` to pin the name) whose `lean/` and golden trees equal the merge tree's; (2) an earlier dry land that ran the lake step on that same pair. The dry land then drops the lake lint from its plan and prints `dry: lake build and axiom check skipped (a pass is on record ...)`. `FW_LAND_LAKE_CACHE=off` switches it off. Only the dry land is touched; the real land still builds.

## Before and after, same head and same main

Head 728ca61 merged with main 6b1e3a3, one dry land each, with the 1-min load average at start in the table. The first is `FW_LAND_LAKE_CACHE=off`; the second ran the lake step with no record and wrote one; the third found it.

| run | load | total | land-inputs | lake step | lake.built |
|---|---|---|---|---|---|
| off (before) | 3.2 | 26.1 s | 9.0 s | 15.3 s | 6 |
| on, no record | 3.4 | 12.2 s | 8.6 s | 2.1 s | 0 |
| on, record found | 6.1 | 10.0 s | 8.4 s | skipped | none |

Before and the third row are the same work; the middle row is a warm rebuild of the same tree. One run per row, so single samples, not medians; the table fits the model above (total = 8.4-9.0 s vitest + lake step + about 1.7 s other). Span name: a skipped step ends as `dry total` instead of `dry total lake`, so its timing baseline is the other key.

## Accepted limits and follow-ups

- A hit needs the branch to carry `main`'s current lean/ and golden trees, or an earlier dry on the same merge. When `main` moved lean/ after the branch's last check.sh, the lake step still runs (this happened twice during this task before the measured runs). The hit rate on later dry lands is read from the `dry: lake build ... skipped` lines and `land dry lake` spans after landing.
- The land-inputs vitest stays about 8 s per dry land.
- `lean/scripts/check.sh` has no row for the golden (the `#guard` checks it at `lake build`); the lead may add a `gen ["--check"]` job. `lean/Fw.lean` imports `Fw.Ops.LandCacheGolden` (outside the task's writes).
