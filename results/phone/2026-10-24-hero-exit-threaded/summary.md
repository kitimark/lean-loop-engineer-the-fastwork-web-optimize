# Phone session 2026-10-24

Moving frames over 50 ms per 100 (lower is better), per pass; verdict against the original passes (an arm wins only beyond their spread).

| zone | original | spread | arm | passes | verdict |
| --- | --- | --- | --- | --- | --- |
| total | 8.76 / 14.09 | 5.33 | rewrite | 0.35 | beats |
| total | 8.76 / 14.09 | 5.33 | look | 0.29 | beats |
| hero | 14.03 / 11.14 | 2.89 | rewrite | 0.00 | beats |
| hero | 14.03 / 11.14 | 2.89 | look | 0.00 | beats |
| finish | 4.19 / 10.09 | 5.90 | rewrite | 2.46 | same |
| finish | 4.19 / 10.09 | 5.90 | look | 1.46 | same |
| rest | 5.39 / 18.15 | 12.76 | rewrite | 0.14 | same |
| rest | 5.39 / 18.15 | 12.76 | look | 0.24 | same |

| arm | pass | frames | taps | felt marks | longest ms |
| --- | --- | --- | --- | --- | --- |
| original | 1 | 4170 | 104 | 25 | 178.0 |
| rewrite | 1 | 5161 | 92 | 24 | 72.0 |
| look | 1 | 4917 | 42 | 11 | 73.0 |
| original | 2 | 3480 | 115 | 32 | 229.0 |

Arms: original (passes 1, 4) and rewrite are the controls recorded minutes earlier in the throttle-lift session
(`results/phone/2026-10-24-throttle-lift/`); look = rewrite + `?fw=hero.exit:threaded`, recorded alone with the toolbar shown
(viewport h 775 in every pass). Felt marks hero / finish / rest: original 1 16/8/1, rewrite 12/12/0, threaded 0/8/3,
original 2 13/12/7. The hero still-run count (Lean `Fw.Device.StillRuns`) gives `no-data` for this arm: the threaded variant
clears the inline `--exit-opacity` the recorder reads (part.json limit), so the hero value is not visible to the recorder.
MEASURED on the real iPhone, one person.
