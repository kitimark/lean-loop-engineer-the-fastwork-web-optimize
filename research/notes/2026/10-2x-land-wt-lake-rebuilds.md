# The dry land's lake step follows modules rebuilt; the pool choice decides which worktree rebuilds

Status: MEASURED (spans), the proxy and the replay INFERRED. Unit of decision: the lake step alone.
Cutoff: dry-land spans in `.fw-console/timings.jsonl` up to start 1792809296017 (16b9c42); the replay uses `dry total`
spans from 1792768665957 to the same cutoff (229 spans, local host).

## Measured

Dry-land `fw`/`land dry lake` spans that carry `lake.built` (212):

| modules built | median lake step | n |
|---|---|---|
| 0 | 3.0 s | 100 |
| 1-7 | 10.7 s | 48 |
| 8 or more | 18.9 s | 56 |

Commit 2e54fbe built 24, 0 and 24 modules in three dry lands (27.7, 2.4, 23.5 s). Each dry land checks out its merge
commit in the first free `.claude/land-wt/<n>` (`claimLandWt`), and each worktree keeps its own `.lake`. The second
2e54fbe land ran in worktree 1, which the first had just built; the third took worktree 0, which had since moved to
another commit.

## Rule (Lean, `lean/Fw/Console/LandWt.lean`)

Among the free worktrees take the one whose last checkout differs least from the commit (count of `*.lean`, `lakefile*`,
`lean-toolchain`, `lake-manifest*` under `lean/` that differ between its HEAD and the commit); a worktree with no `.lake`
is last; ties go to the lower number. Theorems: `pickAux_best` (no free worktree is preferred), `pick_zero` (a
worktree already at the commit is taken), `pick_none_only`, `pick_dist_le`, `pick_tie`, `pick_le_firstFree`
(never farther than today's first free number). Golden: `packages/contracts/golden/console/land-wt.jsonl`, eight rows,
three replayed from the spans above; TS `pickLandWt` is a stand-in checked against it (`apps/runner/test/land-wt.test.ts`).
`claimLandWt` asks the rule for each claim, retries on a lost claim race, and the dry land passes its merge commit.
The real land (second `claimLandWt` call) passes none and keeps the first free number.

## Replay (INFERRED)

Replaying the 229 dry-land intervals through a pool with the old rule and the new one (distance to the branch tip,
two worktrees ever busy together): inputs differing summed 543 under the old rule, 509 under the new; spans at distance 0
75 under the old, 81 under the new. For the third 2e54fbe land the old rule takes worktree 0 (distance 4, measured 24
built), the new rule worktree 1 (distance 0). The proxy is weak: predicted distance 0 matched measured 0 built in
52 of 70 spans, and predicted 1+ matched measured 1+ built in 88 of 140 (the replay measures the branch tip, not the
merge commit, and ignores the real lands that also move a worktree). The gain is bounded by how often two or more
worktrees are free: with two worktrees busy at most, the rule chooses between two.

## Limits

- Local-machine timings; c4f662a's 9.0 s at 0 built stays unexplained.
- The effect is read on later dry lands (`lake.built` of `land dry lake` spans after this lands), not claimed here.
- Main moving ahead between dry lands rebuilds in every worktree; no pool choice avoids that.

## First dry land with the rule

d493e2c (this branch, span `land dry lake`, 39.8 s whole land): lake.built 6. One row is not an effect; the effect is
the table above recomputed over the dry lands after this lands (0-built share and the medians per bucket).
