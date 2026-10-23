# fw plan: work graph to board

`pnpm fw plan <sub>` reads `docs/team/work-graph.json`. Code: `apps/runner/src/plan.ts`, `apps/runner/src/plan-closure.ts`.
The writes-closure rule and its proofs are in `lean/Fw/Plan/WritesClosure.lean`.

| Command | Does | Needs |
|---|---|---|
| `fw plan sync <graph>` | refuses outside the main checkout or off `main`, refuses a new writesClosure error, then sends the graph to the console | a built fwcore, the console |
| `fw plan lint <graph>` | prints the fwcore `plan.lint` findings plus the writesClosure findings; exit 1 on an error | a built fwcore |
| `fw plan show` | prints the board's plan | the console |
| `fw plan overlap [<task>]` | asks fwcore `plan.overlap` whether a spawn overlaps running tasks | a built fwcore |

## fwcore dependency of plan sync

`fw plan sync` lints two graphs before it sends anything: the graph file and the last committed version of it that
differs (`previousGraph`, from `git log --first-parent`). It refuses only the writesClosure errors the new graph adds
(Lean `newErrors`). Each lint sends its scope requests in one batch to fwcore (`scopeBatch`). It tries, in order,
`FW_CORE_BIN` and `lean/.lake/build/bin/fwcore` in the current checkout, the main checkout and each worktree
(`coreCandidates`). With none built, sync sends nothing and throws `plan lint: writes closure: fwcore not built: sh scripts/fwcore-build.sh`.

The gaps both lints use come from `scripts/ci-paths.mjs` `leanInputGaps`: every `../` path a `lean/scripts/*.sh` reads
that the lean.yml row globs miss. A read with a `..` segment counts as a non-literal read and is refused (Lean
`readPath`, `dotdot_gap`), so a `**` row glob cannot cover `lean/../x`. `node scripts/ci-paths.mjs --check` refuses a row
glob outside Lean `rowGlob` (letters, digits, `._-/*`, one leading `!`). MEASURED: on that subset the JS `matches` and
Lean `ghMatches` agree on the golden `agree` rows of `packages/contracts/golden/plan/writes-closure.jsonl` (globs built
from `**`, `***`, `**/` and the prefixes of longer patterns, each alone and as `**` minus it, over a path list), replayed by
`apps/runner/test/plan-closure.test.ts`. INFERRED beyond those rows. Limit: a path with a line terminator (`\n`, `\r`,
U+2028, U+2029) can differ, since the JS `.*` stops at it and Lean `**` does not; `git ls-files` lists none.

## Time

<!-- plan-time begin: node scripts/plan-time.mjs -->
MEASURED (`results/plan-sync-time/samples.jsonl`, 2026-10-17 to 2026-10-23: every exit-0 `plan sync` span of the tool `fw`
in the main checkout's `.fw-console/timings.jsonl`, any load; a run is "with it" when its commit contains 9a09d8066):

| Window | n | p50 | p90 | max |
|---|---|---|---|---|
| last 30 runs before the closure check | 30 | 180 ms | 197 ms | 4177 ms |
| every run with it | 7 | 618 ms | 811 ms | 811 ms |

INFERRED: the closure check adds about 438 ms to a sync (p50 with it minus p50 before).
<!-- plan-time end -->
