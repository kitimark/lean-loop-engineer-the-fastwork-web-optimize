Branch: worktree-wf_825e6ce6-888-1 (CI branch ci/people-o-followups)
Worktree: .claude/worktrees/wf_825e6ce6-888-1
Last commit: see `git log -1` (round 3 code pushed to ci/people-o-followups)
Dispatches used: 4 of 6 (round 3 = the last two).

## CI runs
| run | what | state |
|---|---|---|
| 39878167282 | base, profile key `probe` | failed: host.mjs reads `profile.probe` as the crash probe (renamed `cardProbe`) |
| 39878174234 | flag, same | failed, same cause |
| 39879309834 | base, scenario v1 (hover 12 frames, dy 10, anchor 140) | complete, Layout per scroll frame 55 total |
| 39879313255 | flag, scenario v1 | complete, Layout 55 total, identical to base |

## Verified (MEASURED, round 2)
- Layout per scroll frame is identical base and flag (3 runs each, same 40-frame series 2,2,3,2,...,1).
- The flag never took the keep path: in the probe pass 0 of 22 open-card frames had a `translate`, `top` was rewritten every frame.
  Cause (INFERRED from the card rect): the face still slides in x after the hover (card left 380.906, .734, .594 ... decay 0.8 per frame),
  and `keep` needs equal x; the card also closes after 10 scroll frames (heading under 35% visible), so it was open for 10 of 40 frames.
- Viewport PNG hashes differ between runs of one arm (2 of 183 equal), so a whole-viewport hash is not a probe; round 3 hashes the card region.

## Round 3 (scenario v2)
Hover 60 frames, scroll 3 px per frame, anchor 250, card region PNG hash, face rect, containing-block list in the probe.

## Open
- Round 3 counts and probe, ledger row n 53, note, results, dry land.
