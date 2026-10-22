# census-load-variance handoff (final)

Branch: worktree-wf_105a3643-a4a-1 (CI branch ci/census-load-variance). Worktree: .claude/worktrees/wf_105a3643-a4a-1
Last pushed commit: 1a8f396e (CI). Main merged locally (clean); check.sh, measure-webkit tests, ci-paths, land-inputs green; dry land green.

## CI runs (webkit-sim, 1 VM, 1 session, 2 passes each)
| run | arm | state / pass-2-vs-pass-1 verdict |
|---|---|---|
| 39760288475, 39763719675 | original, rewrite before fix | complete, refused (morph/nav layers only in pass 1) |
| 39775833487 | original 5db37d95 | failed: Simulator seek stalled 741 s |
| 39775866606 | rewrite 5db37d95 (dispatch 1) | complete, refused on `samples` (maxY 5231 vs 5267) |
| 39785816004, 39791097329 | original 2107815b | complete, accepted |
| 39785868145 | rewrite 2107815b (dispatch 2) | complete, accepted |
| 39794304091 | rewrite 2107815b (dispatch 3) | complete, refused on typing avatar (re-eval with the stem: accepted) |
| 39795650433 | original d8ae1db5 | complete, refused on commission section, fee visual (re-eval: accepted) |
| 39807770579 | original 6fe61cb5 | refused on hero feed body (re-eval accepted) |
| 39812409397 | original 1a8f396e (final list) | complete, accepted |

## Verified
- Lean Census.lean green; golden regenerated (64 lines); check.sh green at the final commit.
- Dispatches used: 3 of 3 (all rewrite). Original arm runs are pushes.
## Open
- Allowlist is not closed: each original run so far exposed one more animated box. Follow-up: declare them (data-fw ids) or drive from a second layer-list read.
- Out-of-list edits: census-check.mjs, census-check.test.mjs, cli.mjs (pinStates).
- Design file layer-composer/design-checked.md is lead scratch; the S1 amendment is in research/notes/2026/10-2x-census-load-variance.md.
- Shared scratchpad collision: another agent also writes scratchpad/*.log; use scratchpad/census-lv/ only.
## Read first
research/notes/2026/10-2x-census-load-variance.md, lean/Fw/Measure/Census.lean (stable, runnerStems).
