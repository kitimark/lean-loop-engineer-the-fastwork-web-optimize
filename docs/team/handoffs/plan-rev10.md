# plan-rev10: PLAN revision 10 (the proof model)

## For you (the user), in short
- **What changed:** the evidence for every optimization is now a Lean theorem pair, not a phone run: (vis) same picture as the original for every time and every width band, (work) no more engine work per frame and less somewhere, under cited models of Chromium and WebKit (new §4.7). CI counts check the models (F0-F5); the phone is an optional spot check with nothing waiting on it.
- **Q37 is closed:** no cost model is needed; the (work) theorem is per stage, so "no frame costs more" holds for any unit costs.
- **New critical path (6 tasks, about 27 h, fits C3 with ~19 h slack):** `engine-core-lean` → `engine-chromium-lean` → `morph-tween-waapi` → `variant-morph-tween-waapi` → `experiments` → `write-up`.

| New tasks (23) | Size |
|---|---|
| `engine-core-lean`; `engine-chromium-lean`, `engine-webkit-lean`, `engine-ci-check`, `engine-gaps`, `webkit-sim-rewrite` (parallel after core) | M each |
| `morph-tween-curve` (S) → `morph-tween-waapi` (M) → `variant-morph-tween-waapi` (M) | S/M/M |
| 10 `proof-*` tasks (nav hit-test S, countdown strip S, pain notes S; hidden pause, morph mount, morph panel, people card, people deck, hero accent M; hero exit M-L, dropped first) | S-L |
| `variant-hidden-pause` (M), `variant-morph-mount-shift` (S), `variant-morph-panel-rest` (S), `pixel-spot` (S, optional) | S/M |

- **Decisions for you (defaults apply at C2, 2026-10-18 23:15):** **D1** keep `phone-session-2` as an optional spot check (recommended) or cut it; **D2** which look-changing proposals (CM, constant glass, FLIP, st6, typing chunks, PR-040/041) you want as Try-it pages (default: none in the 2 days).

## For the next agent
- State: PLAN.md rev 10 and work-graph.json committed on branch `worktree-agent-a277414b51db68c33` (see `git log -1`); not landed on `main`.
- Graph: 152 tasks, cut via `cut: true` + milestone MX + deps `[]`; sizes live in titles as "(S)/(M)/(L)" (unknown JSON fields are ignored by sync). A cut dep is not done in `Fw/Plan`, so cutting a task means removing its edges (done for `bands-freeze` → `experiments`).
- Sync: the first `pnpm fw plan sync docs/team/work-graph.json` applied 31 commands, 0 refused, to the live board. A second run from this worktree was refused ("no valid, unused capability"), so the lead should re-run sync after landing (the graph file is the truth).
- Open: PLAN is ~1,400 lines (soft target ~1,300); next candidates to tighten are §1.2, §11, §6.5 S1-S13, §8.2. `swipe-baseline` and `gap-light` stay done (session 1, 5ced4f6), not cut. `experiments`, `engine-core-lean`, `engine-ci-check`, `proof-hidden-pause` titles are 200-220 chars (sync clips the board title; the file keeps the text).
- Read first: PLAN §4.7, §10.6, §12.1; `research/notes/2026/10-18-engine-proof-design.md` §5.
