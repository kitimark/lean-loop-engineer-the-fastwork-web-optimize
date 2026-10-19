---
id: 2026-10-20-lean-migration
kind: note
title: "Lean migration plan: what moves into Lean, what stays TypeScript, and in which order"
status: draft
created: 2026-10-20
topics: [lean, fwcore, lean-first, migration, test-speed, runtime]
---

# Lean migration plan

## Answer

- Most non-rendering logic already has a Lean spec, but only part of it runs in Lean. The inventory has 106 files
  holding decisions, 23.9k lines (whole files, glue included). 15% of those lines run in Lean or are Lean-generated.
  53% are TS twins of a Lean spec. 31% have no Lean spec. (INFERRED: tally in a scratch tally script (not committed).)
  fwcore serves about 146 op names (INFERRED, grep of `| "<op>"` under `lean/Fw`) over 130k lines of `lean/Fw`
  (MEASURED, `wc -l`).
- **Can move:** 48 files with decisions can move to fwcore (10.0k lines). 16 files (3.1k) can become Lean-generated
  tables or text. 31 files (7.5k) stay TS but get checked against Lean goldens. Two dead twins (shells/model.ts,
  gate-shards.mjs; 289 lines) are deleted. quietsteps.mjs is a tested twin: its tests move to the wired
  `measure.quietSteps` op, then it goes. measure-chromium `compare.mjs` stays; it is a self-check CLI, not a twin.
- **Stays TS:** I/O (git, gh, HTTP, ps, files, Simulator, Docker, browsers), React and CSS rendering (14.4k lines),
  in-page instrumentation (2.5k), hot-path hooks, and code that runs in the browser or a container without fwcore.
- **Why not Lean for I/O:** Lean v4.35.0 has no HTTP client, TLS, sha256, file watching, regex, glob or YAML. It does
  ship an HTTP/1.1 server (`Std.Http`, sans-I/O) and libuv sockets (`Std.Internal.UV`). So console-api HTTP stays TS
  by choice (cost), not because Lean cannot do it. The wasm runtime is too heavy for the homepage (see Runtime).
- **Test speed:** moving logic into Lean saves seconds. Process start costs more. One spawned fwcore start takes about
  1 CPU-s. The runner suite spawns at least 165 times, so about 165 CPU-s go to start-up (INFERRED). console-api
  already uses `fwcore serve` and its tests still take 97 s p50 (review, from test spans), so start-up is not the only
  cost. Four eager test tables are 86% of closure-init samples and 53% of main-thread samples (one local `sample`
  run). Wave 0 makes them lazy; a CI re-measure decides whether it worked.
- **Proofs:** each wired stand-in makes its existing theorems cover the code that runs (inc-proof-of-dead-code class).

## Inventory

The six area tables are in `10-20-lean-migration-inventory.md` next to this note. Line counts are at main 50a438ec;
the preview rows were re-checked after preview-inspect's 55e571b. That commit added `console.previewGrant`
(`lean/Fw/Console/PreviewOwner.lean`), which grants.ts already calls; it takes the same TS `lan` boolean as the owner
gate, so the api-owner-raw row stands.

## Migration waves

Score = (incidents prevented, capped at 3, plus test speed 0-2, plus proofs enabled 0-2) / effort (S 1, M 2, L 3).
It is an ordering heuristic, not a measurement. Existing graph tasks keep their ids: runner-standins-fwcore,
workflow-salvage-wire, land-queue-verdict, land-order-overlap, wallclock-lint-lean (wave 1), stage-host-lean (wave 3),
measure-valid, ci-runner-lint (wave 4).

**Same-file rule.** Tasks in this plan that write one file are chained by deps, highest score first: Wire/Console.lean
(land-verdict-op, land-select-op, api-reconcile-op, web-step-offers), Wire/Plan.lean (build-review-stages,
web-plan-columns, api-workflow-op, web-detail-tables, web-plan-layers, plan-sync-op), Wire/Obs.lean, Ops/Wire.lean,
Wire/Gate.lean, Measure/Wire.lean, Ci/Wire.lean, Ci/Trigger.lean, Parts/Golden.lean, `scripts/ci-paths.mjs` and
`.github/workflows/*.yml`. Three writes were narrowed to one file each instead (api-isours-op, api-preview-facts-raw,
site-hand-expect-golden). `lean/Fw.lean` imports are append-only and not chained (accepted limit).

**Blocked by** names open graph tasks (main 50a438ec, no evidence, not cut) whose writes overlap the row. Short names:
LX = latex-strip-c (docstrings in most `lean/**/*.lean`); Wire7 = ci-route, ci-telemetry, countdown-one-chain,
exit-scoped-var, land-wait, morph-layers, runner-standins-fwcore (all claim `lean/Fw/Wire/**`); Gold4 = exit-scoped-var,
land-wait, morph-layers, runner-standins-fwcore (claim `packages/contracts/golden/**`). Older M5 tasks with broad
claims are listed in the appendix, not here. The check is a glob-prefix match, so it over-reports (INFERRED).
fwcore-lazy-tables is started by the lead; its overlaps decide land order, not start.

### Wave 0: runtime and freshness (multiplies every later wave)
| id | owner | stream | eff | deps | blocked by | title | writes | score |
|---|---|---|---|---|---|---|---|---|
| fwcore-lazy-tables (started) | lean-prover | lean | S | - | LX, Wire7, comment-sicko-spawn | Make the 4 eager test tables Unit -> _; lint new large top-level constants in fwcore imports; CI re-measure of spawn CPU-s is the acceptance | lean/Fw/Parts/PainNotesGolden.lean, lean/Fw/Parts/Contract.lean, lean/Fw/Wire/ShardGolden.lean, lean/Fw/Parts/Golden.lean, lean/scripts/ShardGolden.lean, lean/Fw/Lint/** | 3 |
| parts-golden-fresh | lean-prover | site | S | fwcore-lazy-tables | LX, circleci-pilot | fwcore partsgolden --check job in check.sh | lean/Fw/Parts/Golden.lean, lean/scripts/check.sh | 2 |
| gate-gen-compiled | measure-engineer | gate | S | - | LX | freezegen and settlegen as sweepsgen subcommands like sweepsgen scope | packages/gate-breakpoints/scripts/freezegen.mjs, packages/gate-breakpoints/scripts/settlegen.mjs, lean/SweepsgenMain.lean | 2 |
| fwcore-serve-runner | console-builder | tooling | M | fwcore-lazy-tables | comment-sicko-spawn, runner-standins-fwcore | Shared fwcore serve child for runner async paths and the vitest setup; only if the CI re-measure after fwcore-lazy-tables still shows spawn cost | apps/runner/src/run.ts, apps/runner/src/fwcore-serve.ts, apps/runner/test/setup*.ts | 1.5 |
| fwcore-client-shared | measure-engineer | measure | M | fwcore-lazy-tables | measure-valid | One fwcore client for gate, measure-chromium, measure-webkit, gh-budget, difftest; same condition | packages/difftest/src/fwcore.mjs, packages/gate-breakpoints/src/verdict.mjs, packages/measure-chromium/src/fwcore.mjs, packages/measure-webkit/src/handoff.mjs, packages/gh-budget/src/core.ts | 1 |
| dead-twins-delete | console-builder | tooling | S | - | LX, Gold4, ci-dispatch-no-push, ci-route, ci-telemetry, circleci-pilot | Delete shells/model.ts with gen-shells and check:shells, and gate-shards.mjs with its Trigger.lean entry and golden row | apps/site/src/shells/**, apps/site/scripts/gen-shells.mjs, apps/site/package.json, .github/scripts/gate-shards.mjs, .github/README.md, lean/Fw/Ci/Trigger.lean, packages/contracts/golden/ci/triggers.jsonl | 1 |

### Wave 1: wire Lean that exists
| id | owner | stream | eff | deps | blocked by | title | writes | score |
|---|---|---|---|---|---|---|---|---|
| land-verdict-op | lean-prover | tooling | S | land-queue-verdict | LX, Wire7, comment-sicko-spawn, console-daemon, land-no-api, land-queue-verdict, preview-script-move | Op over LandVerdict and LandDry; land-verdict.ts calls it; tests become wire replay | lean/Fw/Console/LandVerdict.lean, lean/Fw/Console/LandDry.lean, lean/Fw/Wire/Console.lean, apps/runner/src/land-verdict.ts, apps/runner/test/land-verdict.test.ts, apps/runner/test/land-dry.test.ts | 6 |
| build-review-stages | lean-prover | tooling | S | workflow-salvage-wire | LX, Wire7, build-review-lint, workflow-salvage-wire | Lean op from work-graph writes to workflow stages (isolation, math review, salvage) passed as args | lean/Fw/Plan/Workflow*.lean, lean/Fw/Wire/Plan.lean, .claude/workflows/build-review.js | 5 |
| gate-exit-op | measure-engineer | gate | S | - | LX, Wire7 | gate.exit op over Fw.Gate.Exit; delete the cli.mjs twin | lean/Fw/Wire/Gate.lean, packages/gate-breakpoints/src/cli.mjs, packages/gate-breakpoints/test/exit.test.mjs | 4 |
| ledger-merge-op | console-builder | tooling | S | manifest-merge | LX, build-review-lint, comment-sicko-spawn, land-order-overlap, manifest-merge, queue-idle-guard, runner-standins-fwcore, watch-liveness, workflow-salvage-wire | merge-ledger.mjs calls an ops.ledgerMerge op; missing fwcore leaves a normal conflict | lean/Fw/Ops/Wire.lean, scripts/merge-ledger.mjs, apps/runner/test/ledger-merge.test.ts | 4 |
| emit-record-golden | console-builder | tooling | S | - | LX, Gold4, comment-sicko-spawn | Lean ObsRecord cases pin emit.mjs record(); unseenSpawn as an fwcore op | lean/Fw/Ops/Obs*.lean, packages/contracts/golden/ops/obs-record.jsonl, apps/runner/hooks/emit.mjs | 4 |
| land-select-op | lean-prover | tooling | M | land-verdict-op, quietsteps-op | LX, Wire7, circleci-pilot, comment-sicko-spawn, console-daemon, land-lane-followups, land-no-api, overflow-on-land, preview-e2e, preview-script-move | Batched LandSpeed op (select, select2, prelock, checkDeps); Lean emits the read tables | lean/Fw/Console/LandSpeed.lean, lean/Fw/Wire/Console.lean, apps/runner/src/land.ts, apps/runner/test/land-prelock.test.ts, apps/runner/test/land-scope.test.ts | 3 |
| build-base-op | console-builder | console | S | - | LX, Wire7, circleci-status, console-daemon, preview-script-move, reconcile-sched-trace, watch-liveness | obs.chooseBase op; golden from the #guards replaces the hand table | lean/Fw/Obs/Stale.lean, lean/Fw/Wire/Obs.lean, apps/console-api/src/core/build-base.ts, apps/console-api/test/build-base.test.ts | 3 |
| next-classify-op | lean-prover | tooling | M | build-base-op | LX, Wire7, lane-admit-load | Raw command lines into obs.next and obs.signals; the Wait lexer classifies; delete the regexes | lean/Fw/Obs/Next.lean, lean/Fw/Obs/Signals.lean, lean/Fw/Wire/Obs.lean, apps/runner/src/next.ts, apps/runner/src/watch-collect.ts | 2.5 |
| quietsteps-op | measure-engineer | measure | S | - | circleci-pilot, land-lane-followups, land-no-api, land-wait, measure-valid, overflow-on-land, preview-e2e | Tests call the wired measure.quietSteps op; then delete the quietsteps.mjs twin | packages/measure-webkit/src/quietsteps.mjs, packages/measure-webkit/README.md, packages/difftest/test/measure-webkit.test.mjs, packages/measure-webkit/test/fwcore.test.mjs, apps/runner/src/land.ts | 2 |
| api-cap-ops | console-builder | console | S | - | circleci-status, console-daemon, preview-script-move, reconcile-sched-trace, watch-liveness | app.ts and cap.ts call ops.actor and ops.door | apps/console-api/src/cap/cap.ts, apps/console-api/src/app.ts, apps/console-api/test/cap.test.ts | 2 |
| engine-premise-op | measure-engineer | measure | M | ledger-merge-op | LX, build-review-lint, ci-dispatch-no-push, ci-runner-lint, ci-telemetry, land-order-overlap, measure-valid, queue-idle-guard, runner-standins-fwcore, watch-liveness, workflow-salvage-wire | ops.enginePremise; engine-premises.yml gets the fwcore artifact | lean/Fw/Ops/Wire.lean, packages/measure-chromium/src/premise-verdict.mjs, .github/workflows/engine-premises.yml | 2 |
| wktr-ops | measure-engineer | measure | S | - | LX | measure.wktrVariance op; wktr premise and summarize call fwcore; WKTR_EXPECTED generated | lean/Fw/Measure/Wire.lean, packages/measure-wktr/fixtures/variance.mjs, packages/measure-wktr/fixtures/premise.mjs, packages/measure-wktr/fixtures/summarize.mjs | 1.5 |

### Wave 2: console decisions out of React and TS predicates
| id | owner | stream | eff | deps | blocked by | title | writes | score |
|---|---|---|---|---|---|---|---|---|
| web-plan-columns | console-builder | console | S | build-review-stages | LX, Wire7, circleci-status | column : TState -> Lane -> Column with an exhaustiveness theorem; TS groups by it | lean/Fw/Plan/Core.lean, lean/Fw/Wire/Plan.lean, packages/contracts/src/index.ts, apps/console-web/src/Plan.tsx, apps/console-web/test/device-lane.test.tsx, apps/console-web/test/plan-cut.test.tsx | 4 |
| api-workflow-op | console-builder | console | M | web-plan-columns | LX, Wire7, circleci-status, console-daemon, preview-script-move, reconcile-sched-trace, watch-liveness | plan.workflow op plus the time rule spawn_at <= stop_at | lean/Fw/Plan/Workflow.lean, lean/Fw/Wire/Plan.lean, apps/console-api/src/spool/workflow.ts, apps/console-api/test/workflow-claim.test.ts | 3 |
| api-reconcile-op | console-builder | console | M | land-select-op | LX, Wire7, console-daemon, preview-script-move, reconcile-sched-trace, watch-liveness | console.reconcile over refs, ahead counts and trailers returns card.build and card.landed commands | lean/Fw/Console/Reconcile.lean, lean/Fw/Wire/Console.lean, apps/console-api/src/reconcile/reconciler.ts, apps/console-api/src/reconcile/naming.ts | 2.8 |
| api-done-infer | lean-prover | console | M | api-reconcile-op | LX, reconcile-sched-trace, watch-liveness | task.done inference (step 3b) in Lean: done only with evidence on main; idempotent keys | lean/Fw/Console/Reconcile.lean, apps/console-api/src/reconcile/reconciler.ts | 2.8 |
| web-step-offers | console-builder | console | S | api-reconcile-op, web-plan-columns | LX, Wire7, circleci-status, console-daemon, preview-script-move | offered(step, actor) with offered implies accepted; fix or remove PostForm | lean/Fw/Console.lean, lean/Fw/Wire/Console.lean, packages/contracts/src/index.ts, apps/console-web/src/App.tsx | 2 |
| web-detail-tables | console-builder | console | S | api-workflow-op | LX, Wire7, circleci-status | Lean emits refusal and target text plus hasDetail per task | lean/Fw/Console/Preview.lean, lean/Fw/Wire/Plan.lean, apps/console-web/src/TaskDetail.tsx | 2 |
| web-health-rows | console-builder | console | S | next-classify-op | LX, Wire7, circleci-status | Code.row with decide-proved coverage of the 24 codes, emitted by obs.health | lean/Fw/Obs/Health.lean, lean/Fw/Wire/Obs.lean, packages/contracts/golden/obs/health.jsonl, apps/console-web/src/Health.tsx | 2 |
| api-isours-op | console-builder | console | S | - | LX, preview-e2e, watch-liveness | Signal decision over ps facts; a pid whose start time changed is never signalled | lean/Fw/Console/PreviewSignal.lean, apps/console-api/src/preview/manager.ts | 2 |
| api-store-replay | console-builder | console | S | - | LX, reconcile-sched-trace, watch-liveness | Lean decides replay repair: only the last line may drop | lean/Fw/Console/StoreReplay.lean, apps/console-api/src/store.ts | 2 |
| api-owner-raw | lean-prover | console | M | - | LX, console-daemon, preview-e2e, preview-script-move, watch-liveness | ownerGate, ownerAction and the grant checks classify raw Host, Origin and remote address | lean/Fw/Console/PreviewOwner.lean, apps/console-api/src/preview/owner.ts, apps/console-api/src/preview/lan.ts | 1.5 |
| web-plan-layers | console-builder | console | M | web-detail-tables | LX, Wire7, circleci-status | layers in Plan.Graph with dep_left; plan view emits layer and row | lean/Fw/Plan/Graph.lean, lean/Fw/Wire/Plan.lean, apps/console-web/src/Plan.tsx | 1.5 |
| api-preview-facts-raw | lean-prover | console | L | - | LX, preview-e2e, reconcile-sched-trace, watch-liveness | Lean derives noCode, behind, ownWork and candidates from raw git facts | lean/Fw/Console/PreviewFacts.lean, apps/console-api/src/preview/facts.ts, apps/console-api/scripts/gen-preview-facts.ts | 1.3 |
| web-builds-action | console-builder | console | S | - | LX, circleci-status | rowAction in console.builds | lean/Fw/Console/Builds.lean, apps/console-web/src/Builds.tsx | 1 |

### Wave 3: site goldens and generated tables
| id | owner | stream | eff | deps | blocked by | title | writes | score |
|---|---|---|---|---|---|---|---|---|
| site-hand-expect-golden | lean-prover | site | S | fwcore-lazy-tables | LX, Gold4 | Golden rows for HeroAccentOpt bounds and chain, PainNotesOpt armed and resumeAt, HiddenPause constants; delete the hand copies | lean/Fw/Parts/HeroAccent*.lean, lean/Fw/Parts/PainNotes*.lean, lean/Fw/Parts/HiddenPause*.lean, apps/site/src/parts/hero.accent/*.test.ts, apps/site/src/parts/pain.notes/*.test.ts, apps/site/src/parts/engine.scene/*.test.ts, packages/contracts/golden/parts/hero.accent.jsonl, packages/contracts/golden/parts/pain.notes.jsonl, packages/contracts/golden/parts/engine.scene.jsonl | 3 |
| site-flags-lean | lean-prover | site | M | - | LX, Gold4 | Fw.Site.Flags over the real registry (presets, @impl, requires, conflicts); golden; prerender list generated | lean/Fw/Site/Flags.lean, packages/contracts/golden/site/flags.jsonl, apps/site/src/registry/resolve.test.ts, apps/site/src/entry-server.tsx | 2 |
| engine-clock-lean | lean-prover | site | S | - | LX, Gold4 | Fw.Parts.EngineClock and the missing engine.clock.jsonl | lean/Fw/Parts/EngineClock.lean, packages/contracts/golden/parts/engine.clock.jsonl | 2 |
| site-media-ids-gen | lean-prover | site | S | - | LX, countdown-one-chain, exit-scoped-var, morph-layers | Scope.lean emits per-part media id lists; media.ts imports them | lean/Fw/Gate/Scope.lean, apps/site/src/parts/*/media.ts, packages/gate-breakpoints/test/scope.test.mjs | 2 |
| site-test-speed | console-builder | site | S | - | - | svg-extract scan via git grep, footprint test only on parts changes, vitest isolate false | apps/site/vitest.config.ts, apps/site/src/svg-extract.test.ts, apps/site/src/footprint.test.ts | 2 |
| parts-golden-rows | lean-prover | site | M | parts-golden-fresh, site-hand-expect-golden, engine-clock-lean | LX, Gold4, countdown-hidden-arm, countdown-one-chain, stage-host-lean, waapi-touch-arm | Rows for every exported function with a theorem | lean/Fw/Parts/Golden.lean, packages/contracts/golden/parts/*.jsonl | 1 |

### Wave 4: CI, gate and measurement verdicts
| id | owner | stream | eff | deps | blocked by | title | writes | score |
|---|---|---|---|---|---|---|---|---|
| counts-plan-op | measure-engineer | ci | S | wktr-ops | LX, ci-dispatch-no-push, ci-runner-lint, ci-telemetry | measure.countsPlan like simPlan; the plan job needs fwcore | lean/Fw/Measure/SimPlan.lean, lean/Fw/Measure/Wire.lean, .github/workflows/chromium-counts.yml | 3 |
| gh-wait-op | measure-engineer | ci | M | - | LX, ci-telemetry | ci.wait.evaluate: run selection, grace, missing lanes | lean/Fw/Ci/Verdict.lean, lean/Fw/Ci/Wire.lean, packages/gh-budget/src/wait.ts | 2.5 |
| wave2-attribution-lean | measure-engineer | measure | M | - | LX, morph-layers, wave2-stageas-g2 | engine-check attribution rule in Lean (MEASURED iff the non-faithful set equals the pair) | lean/Fw/Engine/Attribution.lean, packages/engine-check/src/wave2.mjs | 2.5 |
| gate-summary-mask | measure-engineer | gate | M | gate-exit-op | LX, Wire7 | Mask and not-rendered demotion inside gate.state | lean/Fw/Gate/Settle.lean, lean/Fw/Wire/Gate.lean, packages/gate-breakpoints/src/summary.mjs | 2 |
| gate-jobs-op | measure-engineer | ci | S | gate-summary-mask | LX, Wire7 | gate.jobs (scope narrowing plus the probe deal, cover-once theorem) and gate.merge ops | lean/Fw/Gate/Shard.lean, lean/Fw/Gate/Merge.lean, lean/Fw/Wire/Gate.lean, .github/scripts/gate-jobs.mjs, .github/scripts/merge-gate.mjs | 2 |
| plan-sync-op | lean-prover | plan | M | web-plan-layers | LX, Wire7 | plan.sync op for topoSort and syncCommands | lean/Fw/Plan/Core.lean, lean/Fw/Wire/Plan.lean, packages/contracts/src/plan-sync.ts | 2 |
| ci-checks-op | lean-prover | ci | M | dead-twins-delete, gh-wait-op | LX, ci-dispatch-no-push, ci-telemetry, preview-e2e | ci-paths workflow checks (unguarded, dispatchOnly, status-if) as one op | lean/Fw/Ci/Trigger.lean, lean/Fw/Ci/Wire.lean, scripts/ci-paths.mjs, scripts/ci-paths.test.mjs | 2 |
| ci-text-gen | lean-prover | ci | M | ci-checks-op | LX, ci-dispatch-no-push, ci-telemetry, preview-e2e | Guard, tip, concurrency and push text emitted by Lean; ci-paths only splices | lean/Fw/Ci/Trigger.lean, scripts/ci-paths.mjs | 2 |
| vd-verdict-op | measure-engineer | measure | S | - | LX, fonts-followups | visual-diff verdict and calm in fwcore; reuse the gate settle rule; tolerances generated | lean/Fw/Gate/Pixel.lean, packages/visual-diff/src/verdict.mjs, packages/visual-diff/src/settle-adapter.mjs, packages/visual-diff/src/run.mjs, packages/visual-diff/tolerances.json | 2 |
| ci-arm-set-valid | measure-engineer | ci | M | counts-plan-op | LX, ci-dispatch-no-push, ci-runner-lint, ci-telemetry | Lean rule: all n arms present, all from one attempt; called before classify in 5 merge jobs | lean/Fw/Measure/ArmSet.lean, .github/workflows/webkit-sim.yml, .github/workflows/chromium-counts.yml, .github/workflows/wktr.yml, .github/workflows/wktr-fixtures.yml, .github/workflows/breakpoint-gate.yml | 1.5 |
| lane-inputs-gen | measure-engineer | ci | M | ci-text-gen, ci-arm-set-valid, engine-premise-op | LX, ci-dispatch-no-push, ci-runner-lint, ci-telemetry, land-wait, preview-e2e | Lean lane-input table as dispatch choices and defaults | lean/Fw/Ci/Inputs.lean, scripts/ci-paths.mjs, .github/workflows/*.yml | 1.5 |
| setup-lean-key-gen | measure-engineer | ci | S | lane-inputs-gen | ci-dispatch-no-push, ci-telemetry, preview-e2e | Lake key globs from Trigger.fwcoreFiles, checked by ci-paths | .github/actions/setup-lean/action.yml, scripts/ci-paths.mjs | 1 |
| ci-fwcore-once | measure-engineer | ci | M | lane-inputs-gen | ci-dispatch-no-push, ci-runner-lint, ci-telemetry, land-wait, preview-e2e | One fwcore build per commit reused by artifact in 8 workflows | .github/workflows/*.yml | 1 |

### Follow-up
| id | owner | stream | eff | deps | blocked by | title | writes | score |
|---|---|---|---|---|---|---|---|---|
| lfg-twin-freshness | lean-prover | lean | S | lfg-enforce-all | LX | Lean-first gate input: a TS twin without a freshness job counts as a violation | lean/Fw/Ops/LeanFirst*.lean | - |

Later (score below 1): mutants verdict op, mw-reduce ops, gaps batched op, align-equiv in gate.state, contracts JSON
Schema from Lean, changed-inputs glob matcher, snapshot Reference goldens, cap lexer golden, wt-prep rule, sim-lock
lease, ghCost table, math-pending, page.mjs predicate source, port digest batching.

## Runtime decision

Local timings below are debug runs on a loaded Mac, not results. CPU-seconds are the stable figure; wall time swings
4-6x with load. The CI re-measure is the acceptance test of fwcore-lazy-tables.

| path | cost | status |
|---|---|---|
| spawn fwcore per call | ≈1 CPU-s per start (0.87-1.05 CPU-s); wall 1.7-10 s, depending on load | local debug runs, load ~120 on 8 cores |
| `fwcore serve` kept running | 0.031 ms p50 per op; 5000 piped ops 35.6 ms; first reply 1.2 s | local debug run |
| fwcore start after lazy tables | ≈0.03 CPU-s | INFERRED from `breakgen` and a lazy-constant test; re-measure on CI |
| `fw land:fwcore build (phase 1)` span | p50 10.8 s, p90 34 s (n=17) | MEASURED, fw land spans |

- Fix start-up first. Lean evaluates every top-level constant at program start. `Fw.Parts.PainNotesGolden.lines`
  (`lean/Fw/Parts/PainNotesGolden.lean:80`), `Contract.rowsText` and `diffText` (`lean/Fw/Parts/Contract.lean:1046,
  1173`) and `Wire.Shard.Golden.cases` (`lean/Fw/Wire/ShardGolden.lean:81`) are such constants (CONFIRMED by source).
  They are 86% of closure-init samples and 53% of main-thread samples (one local `sample` run).
- Long-lived processes use `fwcore serve`. console-api already does (`apps/console-api/src/core/lean.ts:110`,
  CONFIRMED). The runner spawns per call (`apps/runner/src/run.ts:78`, CONFIRMED); `fw next` spawns 6 times and the
  runner suite at least 165 times (local count).
- One-shot CLI calls keep spawning after the lazy fix. Hooks that gate every `pnpm fw` call (cap.mjs) stay in-process
  JS with golden pins, because a stale or missing binary would block all calls.
- Browser: no Lean wasm. Lean's emscripten build needs `-fwasm-exceptions -pthread`
  (`src/CMakeLists.txt:175@eb6cafb`, CONFIRMED), so the page needs cross-origin isolation headers (INFERRED). Size:
  1.6 KB gzip for `morph.tween/logic.ts` source (6.2 KB with its drivers) against 460 KB of native arm64 text in
  libleanrt, plus GMP, libuv and libc++ (MEASURED). The wasm size is not measured; INFERRED larger. Browser logic stays
  TS checked against Lean goldens. Finite input spaces (flag resolution) become a Lean-generated JSON table.
- Containers and CI jobs without fwcore (serve-child, measure-chromium in Docker, the CI guard) keep golden-checked
  twins, or console-api computes the table with fwcore and writes JSON for them.

## What stays TypeScript for good

- I/O: git, gh and HTTP, ps and signals, files, Simulator, Docker, Playwright, SSE, timers, localStorage.
- Rendering: React, MUI, shadcn, Tailwind and CSS modules (14.4k lines), CLI tables, step summaries.
- Formats and services Lean v4.35.0 lacks: HTTP client, TLS, sha256, file watching, regex, glob, YAML, Vite and its
  AST parser. The console HTTP server stays TS by choice (Std.Http exists).
- In-page instrumentation and per-frame predicates (settle, freeze), where a process call per frame costs too much.

Rule that keeps it thin: a TS file holds no decision. Each branch on data is a call to an fwcore op, a lookup in a
Lean-generated table, or a twin replayed against a Lean golden in check.sh. The lean-first gate
(`lean/Fw/Ops/LeanFirst*.lean`) will enforce it. It runs in shadow today and refuses nothing; enforcement comes with
lfg-enforce-all. The follow-up lfg-twin-freshness adds one input after that: a twin without a freshness job counts as
a violation.

## What this changes in the plan

- `docs/team/work-graph.json`: add the wave tasks with the deps above. fwcore-lazy-tables is started; add
  parts-golden-fresh, fwcore-serve-runner and fwcore-client-shared with it as a dep. site-test-speed overlaps nothing and can
  start now; gate-gen-compiled starts once latex-strip-c lands. dead-twins-delete waits for its blockers.
- Narrow the broad claims of the Wire7 and Gold4 tasks (`lean/Fw/Wire/**`, `packages/contracts/golden/**`) to the
  files they edit. That unblocks most wave 1 and wave 2 rows.
- Cut or narrow the older M5 tasks listed in the appendix before wave 1 starts.
- lean-ops-gap and lfg-burn-ts: point their item lists at the wave tables here, so one list owns the TS-to-Lean work.
- land-test-speed: depends on fwcore-lazy-tables; its fwcore-spawn share should drop (CI re-measure).
- Add lfg-twin-freshness with dep lfg-enforce-all.
