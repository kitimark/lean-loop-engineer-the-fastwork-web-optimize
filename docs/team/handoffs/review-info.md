# review-info handoff

State (round 2): panel for `nav:earn-no-transition`, committed on branch `worktree-wf_dab73f82-af9-2`. Lean check.sh green, console-api (713) and console-web (75) tests green, web build ok.

## Parts
- Lean `lean/Fw/Console/ReviewInfo.lean`: gain table (model rows computed from `NavEarnOpt.countFor`; measured rows from the research note table), `shownOf noise before after` rule: gain on the cautious bound `gainLow` (lowest before - highest after), loss on `lossHigh` (highest before - lowest after), overlapping ranges show `overlap` (theorems `gain_beats_noise`, `worse_beats_noise`, `overlap_no_difference`, `in_noise_hidden`, `unknown_no_delta`), excerpt ranges with anchors, mechanism, engine sources, formulas. `lean/Fw/Wire/ReviewInfo.lean` is op `console.reviewInfo` {flag}.
- Shared-file edit (3 lines + 1 doc row): `lean/Fw/Wire/Console.lean` (import, ops list, dispatch).
- `apps/console-api/src/review/info.ts`: `mountReviewInfo(app, store, root)` -> `GET /api/reviews/:flag/info`; reads the named lines from `root`, refuses a range whose anchor moved. Not mounted yet.
- `apps/console-web/src/ReviewInfo.tsx`: `<ReviewInfo flag data/>`, hook `useReviewInfo(flag)`; KaTeX 0.16.11 (exact pin, `apps/console-web/package.json` + `pnpm-lock.yaml`; `src/katex.d.ts` declares its types).
- Tests: `apps/console-api/test/review-info.test.ts` (golden `nav-earn.jsonl`, note table, ledger, anchors, formula lines, owner gate), `apps/console-web/test/review-info.test.tsx` (renders every real formula).

## Integration (lead)
1. In `app.ts` after `mountReviews`: `mountReviewInfo(app, store, reviewRoot)`. 2. In the card's slot: `<ReviewInfo flag={item.flag} data={useReviewInfo(item.flag)}/>`.

## Open items
- WebKit gain stays UNKNOWN (no new CI). Noise is MEASURED from A/A runs 39464294630 and 39464322751 (note table "A/A value-change noise"): opacity 2, max-width 4, per metric (`aaNoise`). Shown: 390 close max-width and 1280 close max-width overlap, 390 close opacity 13 more, 1280 close opacity 3 more; 1280 open opacity 3 fewer. 640/641 open rows added (20 rows); their close rows are left out (not in the note table; panel says so).
- `earnSummary` and the excerpt/formula tables are earn-only; another flag needs its own `infoFor` arm. Formula `line` numbers are hard-coded; the api test fails when NavEarnOpt moves them.
- TS stand-ins: none for decisions (the noise rule is Lean). TS only reads files and renders.
- math-reviewer: check the formulas below in the panel.

## Formulas and Lean source (all `lean/Fw/Parts/NavEarnOpt.lean`; unchanged from round 1 except the three edited rows)
| id | formula | Lean | line |
|---|---|---|---|
| on | on(f,m)=not(f and m) | def transitionsOn | 16 |
| off | on_k=false => shown_k=g_k | theorem shown_off | 88 |
| lags | 0<=delta, 0<d, live(run^F_k)=false, g_{k+1}!=g_k => shown^F_{k+1}=g_k (F = faithfulOn; one frame; the long hold is #guard NavEarnOpt.lean:376, :391) | theorem faithful_lags | 107 |
| settled | t monotone, 0<d, g constant on (j,j+n], t_j+delta+d<=t_{j+n} => shown_{j+n}=g_{j+n} | theorem shown_settled | 145 |
| same | draw(shown^on)=draw(shown^on') on settled windows | theorem visSame_settled | 177 |
| work | work_on(n)=#{k<n | dirty_on(k)}, dirty(k+1)=[g_{k+1}!=g_k] or running | def work | 192 |
| worklE | work_on(n)<=work_faithful(n) | theorem work_le | 230 |
| saving | s=work_f-work_flag>=0: 43-3=40, 29-3=26, 65-65=0, 51-51=0 (numbers: golden nav-earn.jsonl fn=work; #guards 371-373 witness three of them) | #guard countFor | 371 |
| trace | trace k (run_k) m=[run_{k+i}] | theorem trace_eq | 255 |
| all3 | K in Settled3 => each of the 3 properties shows the same value in both arms | theorem settled3_same | 429 |
| window | 40*50/3=666.7<680=max(0+680,120+320)<=41*50/3=683.3 | #guard settled3B | 448 |
Source of numbers: golden `packages/contracts/golden/parts/nav-earn.jsonl`; `research/notes/2026/10-20-earn-transition-retarget.md` (runs 39463486725, 39464309993; A/A 39464294630, 39464322751); ledger `nav.earn.noTransition`.

Read first: `lean/Fw/Console/ReviewInfo.lean`, then `apps/console-api/src/review/info.ts`.
