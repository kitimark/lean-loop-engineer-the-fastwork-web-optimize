## trajectory playwright-webkit (WebKit 27.2 (playwright-core 1.64.1)) search=?fw=people.carousel:crop reads=full paths=hero reps=5 CLEAN

arms: 12, all with the config hash of their search and fwMode hydrate (rewrite) or no window.__fw (original)

units 4000: pass 4000, fail 0, skip 0; coverage failures 0

| against the faithful arm | units |
|---|---|
| new (fails here, not in the faithful arm) | 0 (content 0, coverage 0) |
| both (fails in both: baseline red) | 0 |
| unmeasured (fails on content here, on coverage in the faithful arm: no verdict) | 0 |
| cleared (fails only in the faithful arm) | 0 |
| ok | 4000 |

- note: width 640 orig: 1 hero steps did not settle

| arm | phase | samples | read p50 | read p90 | gap p50 | gap p90 | reads dominate |
|---|---|---|---|---|---|---|---|
| orig | hero | 168 | 2 | 5 | - | - | no |
| base | hero | 168 | 1 | 2 | - | - | no |
| cand | hero | 168 | 1 | 2 | - | - | no |
