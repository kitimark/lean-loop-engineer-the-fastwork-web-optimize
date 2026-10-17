# Phone session 1b (2026-10-18): Light appearance and the first finger swipe

Same device, OS and harness as session 1 (`../2026-10-17-s1/README.md`); the phone was in **Light** appearance (checked with
`matchMedia('(prefers-color-scheme: dark)')` before every run; the first two attempts of the session still read dark and were
discarded). Battery 80 %, battery temperature 32 C at both readouts, not charging. No address or device id is stored.

- `gap-device/`: the 8 gap cells and checks W, X, T, S, L all pass; 8 agree, 0 disagree; the one session-1 difference (`dark`)
  is gone, so check S now passes (`device-verdict.json` `pass: true`). Simulator evidence = CI run 39044573514.
- `swipe-original-frames.json`: ORIGINAL page, **finger swipe** by a person, rAF timestamp intervals of every frame for 100 s
  (raw timestamps stay local). One recording, so the figures below carry no run-to-run spread.

| arm (original page, phone, 430 px) | moving frames | > 34 ms per 100 | > 50 ms per 100 | longest | median |
|---|---|---|---|---|---|
| scripted scrollTo 800 px/s (session 1, Dark) | 2003 | 28.7 | 22.9 | 164 ms | 17 ms |
| finger swipe (session 1b, Light) | 911 | 11.4 | 2.6 | 81 ms | 17 ms |

Finger swipe by zone (y0 px; frames over 50 ms per 100; median interval): 0: 2.8 (21 ms), 500: 7.3 (25), 1000: 3.4 (17),
1500: 20.0 (31; 25 frames only), 2000: 3.1, 2500: 1.2, 3000 to 4500: 0 to 0, 5000: 1.9. The page was scrolled to 5308 px
(bounce past the end) and to -35 px (bounce past the top). Not done: counts under a swipe (Timeline arm) and the rewrite
arm; the harness supports both (`device-cli.mjs swipe [--timeline]`).
