# census-load-variance handoff (checkpoint 2)

Branch: worktree-wf_105a3643-a4a-1 (CI branch ci/census-load-variance). Worktree: .claude/worktrees/wf_105a3643-a4a-1
Last pushed commit: 5db37d95. Local work after it is uncommitted until the golden is regenerated.

## CI runs
| run | what | state |
|---|---|---|
| 39760288475 | original, before fix (diagnosis) | complete |
| 39763719675 | rewrite, before fix (diagnosis) | complete |
| 39775833487 | push, original arm with atTop fix | failed: seek stalled 741 s on the Simulator after pass 1 census (scroll after load 0, 5 census states read) |
| 39775866606 | dispatch, rewrite arm with atTop fix (dispatch 1 of 3) | complete: both loads at scroll 0, morph/nav layers gone; refused only for `samples` (maxY 5231 vs 5267, docH 6006 vs 6042) and `#document` root height at y=0 |

## Verified
- Cause 1 (deep load) fixed by atTop; cause 3 (page height differs per load) found: fix pinStates + `#document` stem (uncommitted, golden not yet regenerated: the slot was held by a sim lease).
- Local node --test of the two test files pass; `pnpm --filter @fw/measure-webkit test` passed once at 5db37d95.
## Open
- Regenerate golden (lake build Fw.Measure.Census, then CensusGolden.lean > census.jsonl), commit, push, rerun original and rewrite for 3 runs per arm, accepted base-vs-base pair.
- check.sh, merge main, dry land, review ready.
- Out-of-list edits: census-check.mjs, census-check.test.mjs, cli.mjs (pinStates).
- Design file layer-composer/design-checked.md is lead scratch; the S1 amendment is in research/notes/2026/10-2x-census-load-variance.md.
## Read first
research/notes/2026/10-2x-census-load-variance.md, lean/Fw/Measure/Census.lean (stable, runnerStems).
