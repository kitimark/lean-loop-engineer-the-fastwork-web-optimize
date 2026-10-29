# land-push-lane: fw land's own ci push through the pre-push hook

## Finding (CONFIRMED)

On the land of phone-feel-kit (2026-10-29) the CircleCI leg failed with `git push origin ci/land-phone-feel-kit-ff48bd9`
refused by our pre-push hook: "the tip message names no lane whose inputs changed". When every leg goes to CircleCI,
`markerMessage` (apps/runner/src/land-remote.ts) writes `land <task> <sha7>` with no `[ci:land]` token, so on GitHub only
the seeder lane (lean) would start, and Lean `Fw.Ci.Intent.reasonOf` answers `noMeasuring`. The hook runs inside the
land's own `git push`, so every land lost its CircleCI legs and fell back to GitHub (`-again` branch).

## Design

Threat model: the hook must still refuse a hand push to any `ci/*` branch (also one named `ci/land-...`) that runs no
measuring lane; it must admit the push `fw land` itself makes. It need not stop someone who forges both the record and the
process tree.

Identity, not name: before `git push`, the land's pusher (`makePusher`) writes a record `<git common dir>/fw-land-intent/<marker>.json`
(task, merge, again, marker, pid, legs) and removes it after the push. The hook admits a `ci/*` ref only when Lean
`landCheck` passes on that record and the facts read from git and `ps`:

| check | holds when |
| --- | --- |
| branch | the ref is `refs/heads/` + `landBranch task merge again` |
| marker | the pushed commit is the record's marker |
| parent | its only parent is the merge commit |
| tree | its tree is the merge commit's tree |
| message | its message is `markerMessage task merge legs` |
| lanes | the message requests no lane but `land` |
| process | the land process (`pid`) is an ancestor of the hook |

Without a record the verdict is the old one (`no_intent_unchanged`).

## Lean (lean/Fw/Ci/Intent.lean, section "The land intent")

- `plain_no_measuring_refused`: a covered ref with no intent and no measuring lane is refused; `refuse_no_measuring` is unchanged.
- `admitted_iff`: on a covered ref the lane rule refuses, the push goes iff an intent is given and `landCheck = ok`.
- `land_admitted`, `landCheck_ok_iff`, one refusal theorem per check (`other_branch_refused`, `other_commit_refused`,
  `other_parent_refused`, `other_tree_refused`, `other_message_refused`, `other_lane_refused`, `foreign_process_refused`).
- `land_runs_only_land`: an admitted push starts no lane but `land` and `lean`.

Golden: `packages/contracts/golden/ci/pushlane.jsonl` rows `landBranch`, `marker`, `landCheck` (every check tag occurs);
`apps/runner/test/ci-push-lane-check.test.ts` replays them against `landBranch`, `markerMessage` and the hook's `landCheck`,
and pushes through the real hook: the land's pusher passes, the same commit pushed by hand is refused, a record with a
foreign pid or another branch is refused with the failed check named.

## Accepted limits

No CI push of our own: the next real land exercises the CircleCI path. CircleCI availability is out of scope. The render
guard and the other ci-push rules are unchanged.
