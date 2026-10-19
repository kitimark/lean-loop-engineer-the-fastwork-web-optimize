# Breakpoint gate on `?fw=hero.countdown:one-chain`, commit 75b08603

MEASURED. Workflow breakpoint-gate, engines both: Chromium 156.0.8078.4 and WebKit 27.2 (playwright-core 1.64.1).
Each run reads config 0b068d6eedfb10ad from the loaded page.

| run | scope | Chromium | WebKit | merged verdict |
|---|---|---|---|---|
| 39313815482 | all parts | hero.countdown passes all 14 columns; 1 failing part (commission, below) | every row passes (UNREACHABLE cells are the Lean reach rule) | fail (commission) |
| 39318057726 | `parts=hero.countdown` | 301 readings pass, 0 fail, 3 excused | 301 pass, 0 fail, 3 excused | refused: 28 cells per engine are `not-run`, outside the narrowed scope |

Failing items of run 39313815482, Chromium only:

| part | role | key | at | orig | rewrite |
|---|---|---|---|---|---|
| commission | inner | margin-inline-end | pain-1440-600-1440#0@1440x900 | "0px" | "96px" |

The rest of that run's commission list has the same form: 4 items, `inner` and `rows`, `margin-inline-start` and
`margin-inline-end`, all at the same stop. Run 39314391342 (ci/exit-scoped-var, flag `hero.exit:scoped`) fails on the
same 4 items with the same values. hero.countdown does not touch commission. The cause is the content-visibility
reading tracked by fix-commission-margin.

Gate tooling: a narrowed run counts the cells outside its scope as `not-run`, so its merged verdict is never pass,
even with 0 failing readings.
