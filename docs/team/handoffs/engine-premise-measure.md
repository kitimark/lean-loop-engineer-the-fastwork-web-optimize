# Handoff: engine-premise-measure

State: branch `worktree-agent-abf229eb4ee70943d`. Measured run 39088367495 (commit 485b013, workflow `engine-premises`).

Result: 17 untested engine premises -> 5 measured and held (moved into `registry` as lane premises: cr.script, cr.style,
cr.commit, wk.style, wk.commit), 7 measured and refuted (cr.layout, cr.props, cr.paint, cr.raster, cr.hits, wk.layout,
wk.props; counterexample cells in `refutedPremises`), 5 not measurable (wk.script, wk.paint, cr.comp, cr.signature,
cr.mode). 12 untested remain; 153 of 253 golden rows still cite one of them, 100 rest on measured premises only.

Read first: `research/notes/2026/10-18-engine-premises.md` (ranking, method, results, findings table).

Where things are
- Lean: `lean/Fw/Ops/EnginePremise.lean` (cases, observers, steps, verdict theorems, golden writer);
  `lean/Fw/Ops/Premise.lean` (`laneRule`, `registry`, `untestedPremises`, `refutedPremises`, `engineCites_valid`).
- Golden: `packages/contracts/golden/ops/engine-premises.jsonl` (251 rows), `premise.jsonl` (23 premises).
- Lane: `.github/workflows/engine-premises.yml` (3 Chromium + 3 WebKit x 2 passes, verdict job), trigger row in
  `lean/Fw/Ci/Trigger.lean`.
- TS: `packages/measure-chromium/src/premise-fixture.mjs`, `premise-verdict.mjs`, `profiles/engine-premise-cr.json`,
  `packages/measure-wktr/fixtures/premises.sh`, `harness.mjs` cases mode.

Conventions: verdict logic lives in Lean and is ported to `premise-verdict.mjs`; expected values come from the model;
Chromium drops 6 warm frames after Tracing.start; a presence test cannot see `units`, forced passes or base-arm order
(stated in each registry statement).

Open items
- Fix the engine model where refuted (split levels layoutPos/layoutFull/paint per placement; WebKit filter layout and
  compositing table); then re-run the lane: the refuted ones become holds without code changes to the harness.
- cr.props refutation is one cell (step 126, rAF after padding@own); a second fixture order would confirm it.
- wk.script / wk.paint need counters (none in WKTR); cr.comp needs a compositor-animation observable; cr.mode needs real Chrome.
- The math-reviewer was not run on the new `laneRule`/`refutedPremises` docstrings.
