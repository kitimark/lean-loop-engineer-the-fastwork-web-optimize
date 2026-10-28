# ci-push-lane-check: refuse a ci/* push that runs no measuring lane

Incident `inc-ci-push-no-lane` (docs/team/incidents/ledger.json). geom-style-cut spent 3 pushes for one graded run (an empty
commit, then a push without the lane token); geom-look-fade's first push lacked `[ci:breakpoint-gate]`. The guard decides the
lanes from the tip message and the branch diff (Lean `Fw.Ci.Intent.decision`), but the builder saw the result only after the push.

## Decision (CONFIRMED: lean/Fw/Ci/Intent.lean, section "The push lane check")

`reason S msgs diff differs landed` over the commit messages of `origin/main..tip` (tip first), the branch diff and the paths
that already equal main. First match wins:

| reason | when | Lean |
|---|---|---|
| `same-tree` | no branch file differs from main (an empty commit, or a diff main already has) | `refuse_same_tree` |
| `missing` | the branch requires a lane (`[lanes: a, b]` in any of its commits) that the tip does not start | `refuse_missing`, `missing_token_refused` |
| `no-measuring` | nothing is required and every started lane is a seeder (`lean`, `premise-tests`) | `refuse_no_measuring` |
| `ok` | else | `accept_iff` |

`refuse_iff` proves the refusal is exactly these three cases; `main_never_refused` and `pushRefused_only_ci` that only
`refs/heads/ci/**` is decided; `token_lane_runs` (from `tip_starts`) that a tip naming a lane with a changed input starts it;
`started_requested` that a lane other than `lean` starts only when the tip names it; `same_tree_no_measuring` that (a) leaves only
the default lane, which is a seeder.

A push whose tip selects no measuring lane is refused whatever a `[lanes: ...]` trailer says (round 2 of the review): the trailer may add required lanes (case c) but never satisfies case (b). A Lean-only task needs no ci push.

## Identity of the required lanes

One source: a `[lanes: a, b]` trailer in any commit message of `origin/main..tip`. Why: the hook sees only git, a work-graph row
would need a branch-to-task map and a new graph field (the graph is lead-only), and a union over the branch's commits survives
the later `ci: request` commits that `fw ci push` adds. Limit: a builder who never writes the trailer is checked by (a) and
(b) only; the lead can put the trailer in the spawn prompt.

## Wiring

Lean writes `packages/contracts/golden/ci/pushlane.jsonl` (15 cases, every reason) with `lake test -- --write-ci-trigger-golden`.
`apps/runner/src/ci-push.ts` (the hook, via scripts/hooks/pre-push) takes the lane starts from the guard script's `decide`
(golden-checked against intent.jsonl) and the verdict from `laneReason`, a TS stand-in checked against the golden by
`apps/runner/test/ci-push-lane-check.test.ts`. The refusal prints the lanes that would run and the token to add.

Accepted limits: GitHub-side skip reasons beyond the Lean Trigger model are not seen (for example a stale tip); the lane inputs
are read from the checkout that holds the hook, not from the pushed commit; `git push --no-verify` bypasses the hook.
