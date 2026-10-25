Branch: worktree-wf_8a06f29a-d26-1 (CI branch ci/panel-rest-n11, pushed once at ab3b3248f)
Worktree: .claude/worktrees/wf_8a06f29a-d26-1 (under the main checkout)
Last commit: ab3b3248f (handoff commit follows); CI pushes used: 1 of 3.
CI runs on the push (push-triggered, none dispatched by me): lean 40174060322, trajectory-probe 40174060257, toolbar-throttle 40174060360, wktr 40174060278 (states in the report; updated below when read).

State: flag `morph.panel:rest` shipped. The platform section gets `data-fw-rest` while the written `--morph-fade` is 1 (CSS `.section[data-fw-rest] { filter: none }`, last rule in platform.module.css); morph.tween driver `updateFade` writes it via `rest.logic.ts setRest`; MorphTween reads the flag from `window.__fw.config.variants['morph.panel']`.
Lean: `lean/Fw/Parts/MorphPanelRest.lean` (kindOf, kindOf_rest/fade/off_iff, toggles*); golden `packages/contracts/golden/parts/morph.panel.rest.jsonl`, job in check.sh, trigger row regenerated (`lake --dir lean test -- --write-ci-trigger-golden`). Gen.lean curated exclusion (Chromium trade) -> v2-proved unchanged, decisions golden has the row.
Verified locally: lean/scripts/check.sh green; site tests 7753 pass, typecheck, ci-paths test, runner tests; dry land `VERDICT dry panel-rest-n11`.
RG10 settled (research note): 54 abs / 0 fixed descendants, all have a positioned/transformed ancestor below the section. Pixel check: only 721 px width differs beyond noise (one edge row at a fractional section bottom).
Open: lead dispatches gate (both engines), WebKit Simulator counts (3 VMs per arm, per finish zone, toggle frames), Chromium swipe-touch-v1 3 runs per arm; per-engine verdict. Follow-ups: fractional-edge premise in Lean; Chromium run-level mixed theorem; toggle-only-in-a-layout-frame decision if Chromium pays on the toggle.
Conventions: FootprintRows.lean and footprint-diff.gen.json come from `lake env lean --run scripts/ContractsGolden.lean --rows|--diff` (part-footprint.mjs --write does not write them); rebuild Fw.Parts.Contract first.
Read first: research/notes/2026/10-2x-panel-rest-n11.md, apps/site/src/parts/morph.panel/rest.logic.ts.
