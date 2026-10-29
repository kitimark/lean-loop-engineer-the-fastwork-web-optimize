## trajectory playwright-webkit (WebKit 27.2 (playwright-core 1.64.1)) search=?fw=platform.glint:hold-freeze reads=full paths=hero+morph reps=5 RED

arms: 85, all with the config hash of their search and fwMode hydrate (rewrite) or no window.__fw (original)

units 14416: pass 9400, fail 174, skip 4842; coverage failures 168

| against the faithful arm | units |
|---|---|
| new (fails here, not in the faithful arm) | 43 (content 1, coverage 42) |
| both (fails in both: baseline red) | 129 |
| unmeasured (fails on content here, on coverage in the faithful arm: no verdict) | 0 |
| undecided (open@1 has no rewrite sample and the original's hit rate cannot tell late from missing, or the unit is new without one original pass and not new without another) | 6 (leave-one-out 6) |
| cleared (fails only in the faithful arm) | 126 |
| ok | 14112 |


| width | path | node.property | new units | steps |
|---|---|---|---|---|
| 641 | morph | nav.cls.is-hero-pill | 1/62 | open@2=coverage |
| 641 | morph | nav.cls.is-hero-chrome-ready | 1/62 | open@2=coverage |
| 641 | morph | nav.cls.is-morphing | 1/62 | open@2=coverage |
| 641 | morph | nav.cls.is-expanded | 1/62 | open@2=coverage |
| 641 | morph | nav.cls.is-on-dark | 1/62 | open@2=coverage |
| 641 | morph | nav.cls.is-scroll-hidden | 1/62 | open@2=coverage |
| 641 | morph | nav.visibility | 1/62 | open@2=coverage |
| 641 | morph | nav.rect | 1/62 | open@2=coverage |
| 641 | morph | nav.border-radius | 1/62 | open@2=coverage |
| 641 | morph | nav.background-color | 2/62 | open@2=coverage, close-hold@0=apart |
| 641 | morph | nav.opacity | 1/62 | open@2=coverage |
| 641 | morph | nav.backdrop-filter.fn | 1/62 | open@2=coverage |
| 641 | morph | nav.backdrop-filter.num | 1/62 | open@2=coverage |
| 641 | morph | nav.transform.lin | 1/62 | open@2=coverage |
| 641 | morph | nav.transform.shift | 1/62 | open@2=coverage |
| 641 | morph | logo.position | 1/62 | open@2=coverage |
| 641 | morph | logo.transform-origin | 1/62 | open@2=coverage |
| 641 | morph | logo.rect-in-nav | 1/62 | open@2=coverage |
| 641 | morph | logo.color | 1/62 | open@2=coverage |
| 641 | morph | logo.translate | 1/62 | open@2=coverage |
| 641 | morph | logo.scale | 1/62 | open@2=coverage |
| 641 | morph | logo.transform.lin | 1/62 | open@2=coverage |
| 641 | morph | logo.transform.shift | 1/62 | open@2=coverage |
| 641 | morph | actions.gap | 1/62 | open@2=coverage |
| 641 | morph | actions.opacity | 1/62 | open@2=coverage |
| 641 | morph | earn.tabindex | 1/62 | open@2=coverage |
| 641 | morph | earn.attr.aria-hidden | 1/62 | open@2=coverage |
| 641 | morph | earn.opacity | 1/62 | open@2=coverage |
| 641 | morph | earn.filter.fn | 1/62 | open@2=coverage |
| 641 | morph | earn.filter.num | 1/62 | open@2=coverage |
| 641 | morph | earn.max-width | 1/62 | open@2=coverage |
| 641 | morph | earn.transform.lin | 1/62 | open@2=coverage |
| 641 | morph | earn.transform.shift | 1/62 | open@2=coverage |
| 641 | morph | panel.attr.data-start-selling-scene | 1/62 | open@2=coverage |
| 641 | morph | panel.attr.aria-hidden | 1/62 | open@2=coverage |
| 641 | morph | panel.expanded | 1/62 | open@2=coverage |
| 641 | morph | panel.opacity | 1/62 | open@2=coverage |
| 641 | morph | panel.filter.fn | 1/62 | open@2=coverage |
| 641 | morph | panel.filter.num | 1/62 | open@2=coverage |
| 641 | morph | panel.transform.lin | 1/62 | open@2=coverage |
| 641 | morph | panel.transform.shift | 1/62 | open@2=coverage |
| 641 | morph | panel.cta.tabindex | 1/62 | open@2=coverage |

| arm | phase | samples | read p50 | read p90 | gap p50 | gap p90 | reads dominate |
|---|---|---|---|---|---|---|---|
| orig | open | 670 | 1 | 1 | 21 | 62 | no |
| orig | open-hold | 178 | 1 | 1 | 67 | 80 | no |
| orig | close | 693 | 1 | 1 | 23 | 58 | no |
| orig | close-hold | 173 | 1 | 1 | 67 | 88 | no |
| orig | hero | 168 | 2 | 4 | - | - | no |
| base | open | 755 | 1 | 1 | 19 | 52 | no |
| base | open-hold | 182 | 1 | 1 | 67 | 70 | no |
| base | close | 650 | 1 | 1 | 22 | 64 | no |
| base | close-hold | 178 | 1 | 1 | 67 | 84 | no |
| base | hero | 168 | 1 | 3 | - | - | no |
| cand | open | 1275 | 1 | 1 | 19 | 50 | no |
| cand | open-hold | 303 | 1 | 1 | 67 | 69 | no |
| cand | close | 1168 | 1 | 1 | 21 | 59 | no |
| cand | close-hold | 307 | 1 | 1 | 67 | 70 | no |
| cand | hero | 168 | 2 | 3 | - | - | no |
