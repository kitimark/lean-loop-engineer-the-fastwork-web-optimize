# part-stage handoff (round 1: stage glue, no App.tsx / entry-server)

State: branch worktree-wf_9847872a-d87-2, one commit. Premise on every stage result: `declared-rows-unverified`.

Built
- `lean/Fw/Site/Stage.lean`: `parse` of `?only=<id|g1..g5>&stage=y:N,vh:N,vw:N`; page-level parts refused
  (`resolve_refuses_pageLevel`), group stages drop page-level members (`g4` empty, `g2` loses morph.tween), `parse_ok_stageable`,
  `parseEnv_valid`. Defaults y=0 vw=1280 vh=800; ranges y<=1e6, vw/vh 1..1e4. Golden `packages/contracts/golden/parts/stage.jsonl`
  from `lean/scripts/StageGolden.lean` (`lake env lean --run scripts/StageGolden.lean [--check <file>]`).
- `apps/site/src/registry/only.ts` (`parseOnly`, port checked by `only.test.ts` against the golden).
- `apps/site/src/stage/`: `PartStage.tsx` (hosts the section of the staged parts, fixed-height stubs for the other sections in
  page order, one-time input writes), `fixedEnv.ts` (pins window scrollY/innerWidth/innerHeight, restores), `inputs.ts`
  (declared inputs from contracts.gen.json; rest values in `REST`; unknown ones listed in `unset`, never invented), `hosts.ts`.
  `window.__fwStage` and `data-fw-premise` carry the premise.

Verified (local): apps/site vitest + tsc, ci-paths test, runner land-inputs test, check-imports, Lean module builds with no sorry.
Not run: lean/scripts/check.sh, any CI, a browser.

Open
- Wiring (App.tsx, for morph-group-integrate to land first): in entry-client, `const o = parseOnly(location.search)`; `ok` ->
  `<PartStage stage={o.stage} config={resolved.config} />` instead of `<App>`; `err` -> ErrorPage with the code. entry-server /
  gen-shells prerender of `?only=` pages: not done.
- check.sh needs one line: `job "stage golden check" lake env lean --run scripts/StageGolden.lean --check ../packages/contracts/golden/parts/stage.jsonl`
  (not added: wave-1 branch 4 edits check.sh). Until then the golden is not CI-checked.
- Stub heights are vh multiples (`STUB_VH`), not boxes.gen.json; hosts mount the whole section of a sub-part; rest values of
  data-splash/data-scene style inputs are unknown (`unset`); the `stub` ablation variants are not built.
- Host props follow today's App.tsx; revisit `renderHost` after morph-group-integrate changes Nav/MorphPanel.
- Real viewport is not resized by the stage; a harness must set it to vw x vh (`viewportMismatch` reports).
