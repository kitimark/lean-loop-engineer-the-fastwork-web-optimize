| set | arm | run | right / rows | accuracy | held-out right / rows | held-out accuracy | certify | missing | invalid (Lean validate) |
|---|---|---|---|---|---|---|---|---|---|
| d1 | jev | recorded | 65 / 116 | 56.0 % | 18 / 33 | 54.5 % | none | 0 | - |
| d1 | haiku | first | 69 / 116 | 59.5 % | 20 / 33 | 60.6 % | none | 0 | 15 probabilities: the sum is not 1 within eps |
| d1 | haiku | clean | 64 / 116 | 55.2 % | 17 / 33 | 51.5 % | none | 0 | 78 probabilities: the sum is not 1 within eps; 1 probabilities: the keys differ from the question's |
| d1 | sonnet | first | 78 / 116 | 67.2 % | 19 / 33 | 57.6 % | none | 0 | 1 choice: the pick is not the highest-probability option; 76 probabilities: the keys differ from the question's; 10 probabilities: the sum is not 1 within eps |
| d1 | sonnet | clean | 75 / 116 | 64.7 % | 20 / 33 | 60.6 % | none | 0 | 16 probabilities: the sum is not 1 within eps; 13 probabilities: the keys differ from the question's |
| d2 | jev | recorded | 40 / 83 | 48.2 % | 34 / 73 | 46.6 % | none | 7 | - |
| d2 | haiku | first | 38 / 90 | 42.2 % | 32 / 75 | 42.7 % | none | 0 | 0 |
| d2 | haiku | clean | 43 / 90 | 47.8 % | 36 / 75 | 48.0 % | none | 0 | 0 |
| d2 | sonnet | first | 39 / 90 | 43.3 % | 34 / 75 | 45.3 % | none | 0 | 0 |
| d2 | sonnet | clean | 44 / 89 | 49.4 % | 39 / 74 | 52.7 % | none | 1 | 0 |

| set | arm | rows | parses | calls (retried) | input tokens | output tokens | $ (Claude Code estimate) | model | ms median / max | wall s | choices changed vs first run |
|---|---|---|---|---|---|---|---|---|---|---|---|
| d1 | haiku | 116 | json 116 | 116 (0) | 218347 | 54406 | 0.0706 | claude-haiku-5-5 | 2823 / 6991 | 140 | 36 |
| d1 | sonnet | 116 | json 116 | 116 (0) | 215934 | 41942 | 1.2769 | claude-sonnet-5-5 | 3566 / 7631 | 157 | 31 |
| d2 | haiku | 90 | json 90 | 90 (0) | 160826 | 34087 | 0.0492 | claude-haiku-5-5 | 2570 / 4919 | 105 | 14 |
| d2 | sonnet | 90 | json 89, none 1 | 90 (0) | 158932 | 19196 | 0.8273 | claude-sonnet-5-5 | 2896 / 5283 | 108 | 18 |
