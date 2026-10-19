# part-stage handoff (round 3: final design round)

State: branch worktree-wf_9847872a-d87-2 (round-3 commit on top of 77da3028 + merge of main). Premise on every stage result: `declared-rows-unverified`.

Built
- `lean/Fw/Site/Stage.lean`: `parse` plus `plan : String -> Option Plan`: `hosts`, `mounted` (every part id under the rendered hosts),
  `stubs`, `writes`/`neighbours`/`unset` (from `effect`), `scrollEngine = "faithful"`. Theorems: `hostOf_total_on_stageable`,
  `plan_members_mounted`, `pageLevel_never_mounted`.
- Round 3: `effect` docstring now states what the code does (math reviewer's LaTeX): a non-`data-` className of an unmounted owner
  with a host is written as a class removal (absent at rest) without consulting `rest`; cssVar and `data-` attributes need a `rest`
  value, else unset. The code was kept (removal is the rest state of a class).
- Round 3: `vectors` gains `parts.map ("?only=" ++ ·.id)`; golden `packages/contracts/golden/parts/stage.jsonl` regenerated (72 lines).
- Round 3: `lean/scripts/check.sh` job "stage golden check"; `stage.jsonl` added to the lean.yml row in `Fw/Ci/Trigger.lean`, triggers.jsonl
  regenerated (`lake test -- --write-ci-trigger-golden`); `checkShReads` already covers `packages/contracts/golden/**`; workflow files unchanged.
- TS stand-ins checked against the golden (`registry/only.test.ts`): `registry/only.ts`, `stage/{hosts,inputs,plan}.ts`.
- `entry-client.tsx`: `?only=` ok -> `PartStage` client-rendered, env pinned before first render; err -> ErrorPage `stage: <code>`.

Verified (local): apps/site vitest 5117 + tsc, packages/contracts test, ci-paths 32/32, runner land-inputs 35/35, mathview lint 0 failing,
StageGolden --check, `lake test` all passed. Not run: full check.sh, CI, a browser.

Open
- Work-graph row part-stage `writes` (lead) must cover lean/Fw/Site/Stage.lean, lean/scripts/StageGolden.lean, lean/scripts/check.sh,
  lean/Fw/Ci/Trigger.lean, packages/contracts/golden/ci/triggers.jsonl, apps/site/src/registry/only.test.ts, apps/site/src/stage/**,
  apps/site/src/entry-client.tsx (else land with --allow).
- With the current contract every vector has `writes=[]` (no cssVar/className owner sits outside its consumer's host); the write branch is
  covered only by the hand tests. Follow-up: a Lean theorem that single-part plans have no writes.
- `stage/plan.ts` comment names `plan.test.ts`; the check is in `registry/only.test.ts` (low, not fixed in this round).
- Rerun the golden check if contract-rows-from-code lands first (stage.jsonl derives from Contract.lean).
- Prerender: a `?only=` page is client-rendered (the query is not part of a static file name).
- Accepted limits: STUB_VH heights; a sub-part mounts its whole section; engine.scroll variant fixed per stage; panel mount timing;
  premise declared-rows-unverified carried into every stage result.
