# proof-hero-exit (handoff)

- **State:** `lean/Fw/Parts/HeroExitOpt.lean` builds green, no sorry, standard axioms only; mathview 0 failing.
  Golden rows: `packages/contracts/golden/engine/hero-exit.jsonl` (20 rows, scenario `swipe-v1`, variant `hero-exit-threaded`, base `original`).
- **E-s:** `consumer_eq_s` (under `RG11`, every consumer's animated value equals the JS `calc()` value at every offset);
  core step `progress_eq_js`. Pointer-events: `sentinel_iff_pointerOff`.
- **Chromium:** exact tables `cr_orig_exact` / `cr_var_exact`; blur on main (`blur_main`, bit 12; merged → `merged_main`).
  Verdicts: `cr_real_trade` (main strictly lower, comp +1 pass), `cr_lane_mixed` (script gone, props units +1, style equal, comp +1).
- **WebKit:** `wk_all_comp` (needs threadedScrollDriven; `wk_legacy_main` shows the converse), `wk_var_exact`, `wk_trade`
  (main strictly lower for any original change list; comp gains N+3 ticks).
- **Regenerate goldens:** from `lean/`, `lake env lean <file>` with
  `import Fw.Parts.HeroExitOpt` + `#eval IO.FS.writeFile "../packages/contracts/golden/engine/hero-exit.jsonl" Fw.Parts.HeroExitOpt.goldenJsonl`.
- **Conventions:** Chromium code in `section Cr` (`open Fw.Engine.Chromium`), WebKit in `section Wk`; golden code uses qualified names.
  Predictions never `=0`/`=o` (whole-page counts); `framePred` over a scroll frame + an idle frame.
- **Open:** opacity crossing 1 (WebKit `opacityCross1` layout) not tabled; resident layers not modelled; R2 undercount;
  C3 (which offset the compositor shows). WebKit scenario id `swipe-v1` assumed for the sim/WKTR lanes: confirm against
  the WebKit classes file before engine-check runs. Golden band is the phone band (430 px); no rows for > 600 px.
- **Read first:** module doc at the top of `HeroExitOpt.lean`, then `cr_lane_mixed` and `wk_trade`.
