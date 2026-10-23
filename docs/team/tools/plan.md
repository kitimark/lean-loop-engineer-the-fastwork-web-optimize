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
that the lean.yml row globs miss. `node scripts/ci-paths.mjs --check` refuses a row glob outside Lean `rowGlob`
(letters, digits, `._-/*`, one leading `!`), the subset on which the JS matcher and Lean `ghMatches` agree.

## Time

MEASURED (`.fw-console/timings.jsonl`, tool `fw`, step `plan sync`, exit 0; `pnpm fw timings --tool fw`):

| Window | n | p50 | p90 |
|---|---|---|---|
| last 30 runs before the closure check | 30 | 180 ms | 197 ms |
| first run with it | 1 | 642 ms | 642 ms |

MEASURED: `syncClosureRefusal` alone on the live graph, in a worktree, load average 5: 374-404 ms over 5 calls.
INFERRED: the closure check adds about 0.4 s to each sync.
