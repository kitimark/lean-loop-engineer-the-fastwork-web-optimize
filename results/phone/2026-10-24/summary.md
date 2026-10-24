# Phone session 2026-10-24

Moving frames over 50 ms per 100 (lower is better), per pass; verdict against the original passes (an arm wins only beyond their spread).

| zone | original | spread | arm | passes | verdict |
| --- | --- | --- | --- | --- | --- |
| total | 4.71 / 7.52 | 2.81 | rewrite | 0.63 | beats |
| total | 4.71 / 7.52 | 2.81 | look | 0.19 | beats |
| hero | 4.27 / 12.37 | 8.10 | rewrite | 0.17 | same |
| hero | 4.27 / 12.37 | 8.10 | look | 0.00 | same |
| finish | 0.00 / 1.39 | 1.39 | rewrite | 2.78 | same |
| finish | 0.00 / 1.39 | 1.39 | look | 1.21 | same |
| rest | 83.33 / 6.37 | 76.96 | rewrite | 0.57 | same |
| rest | 83.33 / 6.37 | 76.96 | look | 0.17 | same |

| arm | pass | frames | taps | felt marks | longest ms |
| --- | --- | --- | --- | --- | --- |
| original | 1 | 4781 | 47 | 12 | 174.0 |
| rewrite | 1 | 5165 | 55 | 13 | 73.0 |
| look | 1 | 5212 | 37 | 9 | 65.0 |
| original | 2 | 4224 | 85 | 20 | 133.0 |

Arms: original (passes 1, 4), rewrite (faithful), look = rewrite + `?fw=hero.accent:draw-nolayout-full` (the combined search with `morph.tween:scroll-lock` is not prerendered, so the scroll lock was not in this session). Original pass 2 had 122 zoom frames (a double tap zoomed). Original pass 1 never reached the end-of-page morph (fade stayed 0). MEASURED on the real iPhone, one person, one session.
