# part-stage handoff (round 2: Lean stage plan, wiring)

State: branch worktree-wf_9847872a-d87-2. Premise on every stage result: `declared-rows-unverified`.

Built (round 2)
- `lean/Fw/Site/Stage.lean`: `parse` plus `plan : String -> Option Plan` (`Stage.plan`): `hosts`, `mounted` (every part id under the
  rendered hosts), `stubs` (section px from `stubX100`), `writes`/`neighbours`/`unset` (from `effect` over the inputs of mounted
  parts; morphPhase, scenePaused, page-level owners and inputs without a `rest` value are `unset`), `scrollEngine = "faithful"`.
  Theorems: `hostOf_total_on_stageable`, `plan_members_mounted`, `pageLevel_never_mounted`. LaTeX of resolve, parseEnv, pairs, parse
  fixed as the math reviewer wrote. Golden `packages/contracts/golden/parts/stage.jsonl` regenerated (38 vectors).
- TS ports checked against the golden (`registry/only.test.ts`): `registry/only.ts`, `stage/hosts.ts`, `stage/inputs.ts`,
  `stage/plan.ts`. These are the TS stand-ins: no decision logic beyond the Lean plan.
- `entry-client.tsx`: `?only=` parsed; ok -> `PartStage` client-rendered (never hydrated), env pinned by `pinEnv` BEFORE first render;
  err -> ErrorPage `stage: <code>`. `PartStage` reports `mounted` and `scrollEngine` (also `data-fw-scroll-engine`).

Verified (local): apps/site vitest (5083) + tsc, ci-paths test, mathview lint 0 failing, Lean module builds with no sorry, golden --check.
Pre-existing, not ours: runner land-inputs readsOnly fails on apps/site/src/parts/people/assets.ts (snapshot/ read, from main).
Not run: check.sh, CI, a browser.

Open
- check.sh needs `job "stage golden check" lake env lean --run scripts/StageGolden.lean --check ../packages/contracts/golden/parts/stage.jsonl`
  and the work-graph row part-stage `writes` needs lean/Fw/Site/Stage.lean, lean/scripts/StageGolden.lean, apps/site/src/registry/only.test.ts,
  apps/site/src/stage/** , apps/site/src/entry-client.tsx, lean/scripts/check.sh (else land with --allow). Not added: faithful-checks-rerun holds check.sh.
- Prerender: a `?only=` page cannot be a static file (the query is not part of the file name); pages.mjs serves index.html and the
  client renders (`mode: client-render`). No entry-server/gen-shells change.
- Accepted limits: STUB_X100 heights; a sub-part mounts its whole host; engine.scroll variant fixed per stage; panel mounts at once
  (page: after MorphMount onMount); the real viewport is not resized (`viewportMismatch`); host props follow today's App.tsx; `stub` ablation variants not built.
