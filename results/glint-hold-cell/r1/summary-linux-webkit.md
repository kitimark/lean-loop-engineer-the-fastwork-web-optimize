## trajectory playwright-webkit (WebKit 27.2 (playwright-core 1.64.1)) search=?fw=platform.glint:hold-freeze reads=full paths=hero reps=5 CLEAN

arms: 12, all with the config hash of their search and fwMode hydrate (rewrite) or no window.__fw (original)

units 4000: pass 3190, fail 0, skip 810; coverage failures 0

| against the faithful arm | units |
|---|---|
| new (fails here, not in the faithful arm) | 0 (content 0, coverage 0) |
| both (fails in both: baseline red) | 0 |
| unmeasured (fails on content here, on coverage in the faithful arm: no verdict) | 0 |
| undecided (open@1 has no rewrite sample and the original's hit rate cannot tell late from missing, or the unit is new without one original pass and not new without another) | 0 (leave-one-out 0) |
| cleared (fails only in the faithful arm) | 0 |
| ok | 4000 |

- note: width 640 orig: 1 hero steps did not settle

| arm | phase | samples | read p50 | read p90 | gap p50 | gap p90 | reads dominate |
|---|---|---|---|---|---|---|---|
| orig | hero | 168 | 2 | 4 | - | - | no |
| base | hero | 168 | 2 | 3 | - | - | no |
| cand | hero | 168 | 2 | 3 | - | - | no |
