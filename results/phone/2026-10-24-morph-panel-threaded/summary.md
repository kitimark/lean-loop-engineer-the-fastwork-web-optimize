# Phone session 2026-10-24

Moving frames over 50 ms per 100 (lower is better), per pass; verdict against the original passes (an arm wins only beyond their spread).

| zone | original | spread | arm | passes | verdict |
| --- | --- | --- | --- | --- | --- |
| total | 8.76 / 14.09 | 5.33 | rewrite | 0.35 | beats |
| total | 8.76 / 14.09 | 5.33 | look | 2.26 | beats |
| hero | 14.03 / 11.14 | 2.89 | rewrite | 0.00 | beats |
| hero | 14.03 / 11.14 | 2.89 | look | 0.00 | beats |
| finish | 4.19 / 10.09 | 5.90 | rewrite | 2.46 | same |
| finish | 4.19 / 10.09 | 5.90 | look | 5.61 | same |
| rest | 5.39 / 18.15 | 12.76 | rewrite | 0.14 | same |
| rest | 5.39 / 18.15 | 12.76 | look | 0.50 | same |

| arm | pass | frames | taps | felt marks | longest ms |
| --- | --- | --- | --- | --- | --- |
| original | 1 | 4170 | 104 | 25 | 178.0 |
| rewrite | 1 | 5161 | 92 | 24 | 72.0 |
| look | 1 | 4124 | 47 | 13 | 65.0 |
| original | 2 | 3480 | 115 | 32 | 229.0 |

End-of-page (finish zone) only, all passes at viewport h 775; controls from the throttle-lift session plus a second rewrite pass:

| pass | finish frames > 50 ms per 100 | finish felt marks |
| --- | --- | --- |
| original 1 / 2 | 4.19 / 10.09 | 8 / 12 |
| rewrite 1 / 2 | 2.46 / 6.56 | 12 / 14 |
| rewrite + morph.panel:threaded | 5.61 | 12 |
| rewrite + engine.scroll:throttle-lift (repeat pass) | 1.17 | 5 |

morph.panel:threaded is inside the rewrite's own spread: no end-of-page gain (negative result). throttle-lift is the lowest on both
measures but is one pass, inside the originals' spread, so not yet a verdict. MEASURED on the real iPhone, one person.
