Branch: worktree-wf_825e6ce6-888-1 (CI branch ci/people-o-followups)
Worktree: .claude/worktrees/wf_825e6ce6-888-1
Last commit: see `git log -1`. Dispatches used: 6 of 6 (none left).

## CI runs (chromium-counts, profile people-o-hover, 3 runs per dispatch)
| run | what | state |
|---|---|---|
| 39878167282 | base, profile key `probe` | failed: host.mjs reads `profile.probe` as the crash probe (renamed `cardProbe`) |
| 39878174234 | flag, same | failed, same cause |
| 39879309834 | base, scenario v1 (hover 12 frames, 10 px, anchor 140) | complete, 55 Layout in the scroll phase |
| 39879313255 | flag, scenario v1 | complete, 55, identical (flag never engaged) |
| 39881189724 | base, scenario v2 | complete, scroll-phase Layout 67 |
| 39881193403 | flag `people.o:preview-translate`, scenario v2 | complete, scroll-phase Layout 28 |

## Verified (MEASURED unless marked)
- v2 (hover 60 frames, scroll 3 px, anchor 250, text-wrap workaround): trace.Layout over 40 scroll frames 67 base vs 28 flag; UpdateLayoutTree 191, PrePaint 120, UpdateLayer 1070 and invalidation area equal. Series identical across the 3 runs of each arm.
- Probe: flag took translate on 49 frames; card rect equal in 3 of 3 pairs; card pixels equal in 2 of 3 pairs. Flag run 3 differs from the five other runs (card left 0.92 px off from hover frame 121, before any scroll; INFERRED not the flag).
- Whole-viewport PNG hash is noise (50 differing frames base vs flag, 49 base vs base); the card-region hash is deterministic.
- FW_LOAD_TRACE gates the load diagnostics (test in packages/measure-chromium/test/profile.test.mjs). snapDev case dropped (preview.golden.test.ts).
- Ledger row n 53: chromium `win` with the run ids; webkit stays unknown.

## Open
- Files outside the task writes: packages/measure-chromium/src/host.mjs (FW_LOAD_TRACE passthrough), packages/measure-chromium/src/png-region.mjs (new).
- TS stand-ins: results/people-o-preview-translate/probe-compare.mjs, phase-sums.mjs, png-region.mjs decode.
- Follow-ups: second Layout source from scroll frame 15 (not the card); base card rect moves 6 px per frame vs face 3 px (not diagnosed); flag run 3 pixel outlier.
- Accepted limits: text-wrap workaround premise, desktop only, Safari on a Mac is gpu-safari-lane.

## Read first
research/notes/2026/10-2x-people-o-preview-translate.md (Measured section), results/people-o-preview-translate/followups.json, packages/measure-chromium/src/run.mjs (cardProbe pass).
