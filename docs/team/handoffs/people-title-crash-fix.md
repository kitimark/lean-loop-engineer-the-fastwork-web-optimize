# people-title-crash-fix: handoff

Branch: worktree-wf_c7f678ea-d01-1 (CI branch ci/people-title-crash-fix)
Worktree: .claude/worktrees/wf_c7f678ea-d01-1
Last commit: see `git log -1` (pushed 4e94d2451 = bisect probe)

## CI runs
| run | what | state |
|---|---|---|
| 39889266468 | trajectory-probe push, fw=people.o:block, verdict run | running |
| 39889281962 | breakpoint-gate dispatch, both engines, fw=people.o:block | running |
| 39889621434 | chromium-counts, profile people-title-crash, rewrite, fw=people.o:block | done: every >860 page variant crashes (861, 1100, 1280, 1440; CfT 156.0.8078.4/.47, 157, 158); 860 and 390 ok |
| 39889660302 | same, no fw (control) | done: identical rows |
| (bisect) | chromium-counts, profile people-title-bisect, rewrite | dispatched, running |

## Finding (MEASURED, 39889621434)
The first fix (o as block with width 0.6042em, Lean PeopleOBlock) does NOT stop the crash: min repro `cft4-min-blockw` (block, declared width) crashes.
Earlier "o inline-block ok" had width 0 (grid-template-columns ignored, width auto = 0). So width > 0 of the o matters, not the grid.
Bisect probe `packages/measure-chromium/profiles/people-title-bisect.json` (20 css variants on the rewrite page) is the next step.

## Verified
Lean check.sh green at 87a084d81 (PeopleOBlock), site tests 6498 pass. Local debug (not a result): WebKit base vs flag pixels identical 861..1440.
Open: pick a fix that stops the crash (wrap on the title is in people.card, outside this task's writes), re-prove, re-run gate and a stock load.
