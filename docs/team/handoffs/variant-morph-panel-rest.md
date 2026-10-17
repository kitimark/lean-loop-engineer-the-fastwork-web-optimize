# variant-morph-panel-rest (handoff)

State: TS variant `rest` in apps/site/src/parts/morph.panel/ (logic.ts panelFilterState/Value/OwnLayer, driver.ts opts.rest,
index.tsx passes `variant === 'rest'`, CSS `[data-fw-filter='rest'|'fade']`, part.json variant `rest`, tests in logic.test.ts).
Faithful path: driver writes `data-fw-filter` only when `rest`; CSS rules are attribute-gated, so flag off = unchanged.
Toggle: morph 0.8 (progress 1, blur radius 0; Lean rest_iff). rest: filter none, will-change auto; fade: will-change transform,opacity,filter.

BLOCKED: no CI run. `git merge worktree-agent-aa399880b0e73e3d8` conflicts (App.tsx, Census.tsx, registry/index.ts, Scope.lean,
Golden.lean, gate page.mjs/run.mjs/scope.gen.json: main has moved; two gate prepare mechanisms). That is integrate-ports' job.
I took only the port's morph.panel dir (checkout, not merge). The part is not registered/wired here, so the variant cannot run
until integrate-ports lands. Then: push ci/variant-morph-panel-rest, gate with `?fw=morph.panel:rest`, then engine-check on morph-panel.jsonl.
Golden fn vectors (morph.panel.jsonl) were not generated (Lean build busy), so logic.test.ts golden block not run locally; my 3 new tests pass.

RG10 (DOM check): panel keeps `transform: scale()` (never none) and is positioned with z-index 1, so containing block and stacking
context persist without the filter. Descendants: absolute backdrop/veil/center/footer (z 1, 2), no fixed descendants (grep morph.columns/countdown).
Holds in the port's DOM.
