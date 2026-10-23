# people-title-crash-fix: handoff

Branch: worktree-wf_c7f678ea-d01-1 (CI branch ci/people-title-crash-fix)
Worktree: .claude/worktrees/wf_c7f678ea-d01-1
Last commit: see `git log -1` (CI tip b3a92c3a1 held the change as default; final tip carries the flag)

## CI runs
| run | what | state |
|---|---|---|
| 39889621434 | chromium-counts people-title-crash, rewrite, fw=people.o:block | done: all >860 variants crash (block o refuted) |
| 39889660302 | same, no fw (control) | done: identical rows |
| 39890158715 | chromium-counts people-title-bisect (20 css variants) | done: only wrap / zero-width / abs o stop the crash |
| 39891744638 | chromium-counts people-title-crash at b3a92c3 (wrap applied) | done: ok at 861, 1100, 1280, 1440 (3 builds), 860, 390 |
| 39891679733 | breakpoint-gate push at b3a92c3 (wrap as default) | done: fail, only title text-wrap-style (111 chromium, 105 webkit) |
| 39889281962 | breakpoint-gate dispatch fw=people.o:block | done: people.o FAIL 30/30 display, grid-template-columns, transition-property |
| 39891679693 | trajectory-probe push at b3a92c3 | done: pass |
| 39891109938 | visual-diff dispatch base, webkit, people.card 861/1100 | done: both fail vs original (3503 / 8178 changed), settled |
| 39891679931 | visual-diff push at b3a92c3 | done: success, but people.card unsettled at desk-861/1100 (no verdict) |

Dispatches used: 6 of 6 (gate, counts x2, bisect, visual-diff base, stock load).

## State
Fix = flag `people.card:title-wrap` (default stays `balance` so the gate is green); Lean `PeopleTitleWrap.lean` (fits_one_line,
same_when_fits); `PeopleOBlock.lean` kept as the refuted option. Note `research/notes/2026/10-2x-people-title-crash-fix.md`.
Open: CI pixel compare base vs flag (dispatch visual-diff, WebKit, parts people.card, probes desk-861,desk-1100, fw people.card:title-wrap);
stock load with the flag on (`pnpm -s fw run --target rewrite --engines chromium --profile people-title-crash --runs 2 --fw people.card:title-wrap`;
needs the probe copied to profiles/ on the ci branch); gate with the flag (`pnpm -s fw run --gate --engines both --fw people.card:title-wrap`).
