## trajectory chromium (156.0.8078.4) search=?fw=nav:clip-box reads=full paths=hero+morph reps=5 RED

arms: 72, all with the config hash of their search and fwMode hydrate (rewrite) or no window.__fw (original)

units 14416: pass 9929, fail 455, skip 4032; coverage failures 168

| against the faithful arm | units |
|---|---|
| new (fails here, not in the faithful arm) | 370 (content 286, coverage 84) |
| both (fails in both: baseline red) | 85 |
| unmeasured (fails on content here, on coverage in the faithful arm: no verdict) | 0 |
| cleared (fails only in the faithful arm) | 0 |
| ok | 13961 |


| width | path | node.property | new units | steps |
|---|---|---|---|---|
| 390 | morph | nav.rect | 19/62 | open@1=apart, open@2=apart, open@3=apart, open@4=apart, open@5=apart, ... |
| 390 | morph | nav.border-radius | 22/62 | open@1=apart, open@2=apart, open@3=apart, open@4=apart, open@5=apart, ... |
| 390 | morph | nav.transform.shift | 14/62 | open@1=apart, open@2=apart, open@3=apart, open@4=apart, open@5=apart, ... |
| 390 | morph | logo.rect-in-nav | 15/62 | open@1=apart, open@2=apart, open@3=apart, open@4=apart, open@5=apart, ... |
| 390 | morph | logo.color | 2/62 | close@0=apart, close@1=apart |
| 640 | morph | nav.rect | 18/62 | open@2=apart, open@3=apart, open@4=apart, open@5=apart, open@6=apart, ... |
| 640 | morph | nav.border-radius | 21/62 | open@2=apart, open@3=apart, open@4=apart, open@5=apart, open@6=apart, ... |
| 640 | morph | nav.background-color | 1/62 | close@0=apart |
| 640 | morph | nav.transform.shift | 11/62 | open@2=apart, open@3=apart, open@4=apart, open@5=apart, open@6=apart, ... |
| 640 | morph | logo.rect-in-nav | 14/62 | open@2=apart, open@3=apart, open@4=apart, open@5=apart, open@6=apart, ... |
| 641 | morph | nav.rect | 21/62 | open@2=apart, open@3=apart, open@4=apart, open@5=apart, open@6=apart, ... |
| 641 | morph | nav.border-radius | 21/62 | open@2=apart, open@3=apart, open@4=apart, open@5=apart, open@6=apart, ... |
| 641 | morph | nav.background-color | 1/62 | close@0=apart |
| 641 | morph | nav.transform.shift | 12/62 | open@2=apart, open@3=apart, open@4=apart, open@5=apart, open@6=apart, ... |
| 641 | morph | logo.rect-in-nav | 18/62 | open@3=apart, open@4=apart, open@5=apart, open@6=apart, open@7=apart, ... |
| 1280 | morph | nav.cls.is-hero-pill | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.cls.is-hero-chrome-ready | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.cls.is-morphing | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.cls.is-expanded | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.cls.is-on-dark | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.cls.is-scroll-hidden | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.visibility | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.rect | 22/62 | open@1=apart, open@2=apart, open@3=apart, open@4=coverage, open@5=apart, ... |
| 1280 | morph | nav.border-radius | 22/62 | open@1=apart, open@2=apart, open@3=apart, open@4=coverage, open@5=apart, ... |
| 1280 | morph | nav.background-color | 3/62 | open@4=coverage, open@7=coverage, close-hold@0=apart |
| 1280 | morph | nav.opacity | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.backdrop-filter.fn | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.backdrop-filter.num | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.transform.lin | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | nav.transform.shift | 18/62 | open@1=apart, open@2=apart, open@3=apart, open@4=coverage, open@5=apart, ... |
| 1280 | morph | logo.position | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | logo.transform-origin | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | logo.rect-in-nav | 21/62 | open@1=apart, open@3=apart, open@4=coverage, open@5=apart, open@6=apart, ... |
| 1280 | morph | logo.color | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | logo.translate | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | logo.scale | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | logo.transform.lin | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | logo.transform.shift | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | actions.gap | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | actions.opacity | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | earn.tabindex | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | earn.attr.aria-hidden | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | earn.opacity | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | earn.filter.fn | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | earn.filter.num | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | earn.max-width | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | earn.transform.lin | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | earn.transform.shift | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.attr.data-start-selling-scene | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.attr.aria-hidden | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.expanded | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.opacity | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.filter.fn | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.filter.num | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.transform.lin | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.transform.shift | 2/62 | open@4=coverage, open@7=coverage |
| 1280 | morph | panel.cta.tabindex | 2/62 | open@4=coverage, open@7=coverage |

| arm | phase | samples | read p50 | read p90 | gap p50 | gap p90 | reads dominate |
|---|---|---|---|---|---|---|---|
| orig | open | 1014 | 0.5 | 0.6 | 17.3 | 32.5 | no |
| orig | open-hold | 179 | 0.5 | 0.6 | 66.7 | 95.4 | no |
| orig | close | 982 | 0.5 | 0.6 | 17 | 35.2 | no |
| orig | close-hold | 183 | 0.5 | 0.8 | 66.7 | 72.7 | no |
| orig | hero | 168 | 1.1 | 1.8 | - | - | no |
| base | open | 1007 | 0.4 | 0.5 | 17.2 | 34.1 | no |
| base | open-hold | 173 | 0.4 | 0.6 | 66.7 | 92.8 | no |
| base | close | 1005 | 0.4 | 0.6 | 17.1 | 33.4 | no |
| base | close-hold | 182 | 0.5 | 0.7 | 66.7 | 73.5 | no |
| base | hero | 168 | 1 | 1.7 | - | - | no |
| cand | open | 915 | 0.4 | 0.6 | 18.3 | 39.8 | no |
| cand | open-hold | 170 | 0.4 | 0.6 | 66.7 | 96.6 | no |
| cand | close | 867 | 0.4 | 0.6 | 18.1 | 42 | no |
| cand | close-hold | 181 | 0.5 | 0.7 | 66.7 | 71.6 | no |
| cand | hero | 168 | 1 | 1.7 | - | - | no |
