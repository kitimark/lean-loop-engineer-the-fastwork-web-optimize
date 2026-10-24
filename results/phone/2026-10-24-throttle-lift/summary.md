# Phone session 2026-10-24

Moving frames over 50 ms per 100 (lower is better), per pass; verdict against the original passes (an arm wins only beyond their spread).

| zone | original | spread | arm | passes | verdict |
| --- | --- | --- | --- | --- | --- |
| total | 8.76 / 14.09 | 5.33 | rewrite | 0.35 | beats |
| total | 8.76 / 14.09 | 5.33 | look | 0.17 | beats |
| hero | 14.03 / 11.14 | 2.89 | rewrite | 0.00 | beats |
| hero | 14.03 / 11.14 | 2.89 | look | 0.00 | beats |
| finish | 4.19 / 10.09 | 5.90 | rewrite | 2.46 | same |
| finish | 4.19 / 10.09 | 5.90 | look | 1.17 | same |
| rest | 5.39 / 18.15 | 12.76 | rewrite | 0.14 | same |
| rest | 5.39 / 18.15 | 12.76 | look | 0.11 | same |

| arm | pass | frames | taps | felt marks | longest ms |
| --- | --- | --- | --- | --- | --- |
| original | 1 | 4170 | 104 | 25 | 178.0 |
| rewrite | 1 | 5161 | 92 | 24 | 72.0 |
| look | 1 | 4816 | 26 | 5 | 59.0 |
| original | 2 | 3480 | 115 | 32 | 229.0 |

## Hero-exit still runs (Lean `Fw.Device.StillRuns` via its twin `packages/measure-webkit/src/throttle/stillruns.mjs`)

Arms: original (passes 1, 4), rewrite (faithful), look = rewrite + `?fw=engine.scroll:throttle-lift` (diagnostic flag).
Band runs = runs of 5-6 frames where the hero-exit value stood still while the page moved (the 100 ms visible-rect throttle);
exit frames = frames with the hero value strictly between 0 and 1000 per mille.

| pass | viewport h | band runs | short runs (1-9) | exit frames | felt marks in hero / finish / rest |
| --- | --- | --- | --- | --- | --- |
| original 1 | 775 | 29 | 73 | 717 | 16 / 8 / 1 |
| rewrite | 775 | 90 | 108 | 1200 | 12 / 12 / 0 |
| look (first try, toolbar already collapsed) | 815 | 6 | 27 | 1415 | 0 / 11 / 0 |
| look (repeat, toolbar shown) | 775 | 2 | 62 | 1318 | 0 / 5 / 0 |
| original 2 | 775 | 27 | 69 | 812 | 13 / 12 / 7 |

Verdict (same viewport height, rewrite vs look repeat): `lifted`. The first look pass had a different viewport height (815,
toolbar collapsed), so the Lean verdict for it is `confounded`; the table above uses the repeat. MEASURED on the real iPhone,
one person, one session; felt marks are the person's triple taps.
