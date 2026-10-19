---
id: 2026-10-20-lean-migration-inventory
kind: note
title: "Lean migration plan, appendix: inventory by area and older overlapping tasks"
status: draft
created: 2026-10-20
topics: [lean, fwcore, lean-first, migration, inventory]
---

# Lean migration inventory (appendix to 10-20-lean-migration.md)

Kind: S stand-in (Lean twin exists), D decision (no or partial Lean), G generator. Target: F run in fwcore, L Lean
generates, C TS checked against a Lean golden, X delete. Effort S, M or L (one value per row). Line counts are whole
files, glue included, at main 50a438ec; preview rows re-checked after preview-inspect's 55e571b. The tally is
a scratch tally script (not committed). D rows in the site and CI tables are INFERRED; the review did not re-check them.

### Runner and scripts (6.4k lines in files holding decisions; 2.8k glue, 0.3k rendering stay TS)
| module | kind | today | target | value | eff |
|---|---|---|---|---|---|
| land.ts selection, prelock, read tables | S | LandSpeed + PathCheck, golden, no LandSpeed op | F, L tables | 4 land incidents, selection soundness | M |
| land-verdict.ts | S | LandVerdict, LandDry, golden 187 rows, no op | F | inc-land-dry-no-verdict, retry-text-match, queue-unknown | S |
| land-queue.ts, premises.ts, coverage.ts | S | Lean + goldens, no op | F | task runner-standins-fwcore | M |
| workflow/salvage.ts | S | op not imported by Fw.Wire | F | inc-workflow-null-result | S |
| build-review.js stage plan | D | none | L | 4 workflow incidents | S |
| merge-ledger.mjs | S | LedgerMerge, golden, no op | F | conflict_iff covers the git driver | S |
| lint-wallclock.mjs | S | WallClock, golden | F | task wallclock-lint-lean | S |
| ci-paths.mjs checks | D | Trigger, Intent; checks in TS | F, L text | inc-ci-trigger-drift, dispatch-push-runs | L |
| next.ts, watch-collect.ts classifiers | S | Ops.Wait parser exists | F | 4 wait-loop incidents | M |
| hooks/emit.mjs record, unseenSpawn | D | none | C, F | inc-obs-silent-drop, workflow-unbound | S |
| hooks/cap.mjs lexer | S | ops.actor/ops.cap goldens | C | lexer cases unpinned | S |
| run.ts ghCost table | D | Budget proofs, hand cost table | L | inc-gh-rate-limit | S |
| port/digest.mjs, port/fonts.mjs | S | Port goldens | C | already pinned | M |
| wt-prep.sh build_pids, sim-lock.sh | D, S | none; Fw.Lease op | C, F | inc-wt-prep-lsp-as-build; lease FIFO | S |
| ci-push.mjs, math-pending.mjs | D | Intent data only; none | C | inc-dispatch-push-runs | S |
| scrub.mjs, small CLI policy | D | none | stays | low | - |

### console-api (2.6k lines in files holding decisions; 1.0k glue stays TS)
| module | kind | today | target | value | eff |
|---|---|---|---|---|---|
| spool/workflow.ts | S | Plan.Workflow, golden, no op | F + time rule | inc-workflow-unbound, multi-unbound | M |
| reconcile/reconciler.ts, naming.ts | D | syncFrom twin; steps 1, 2, 3b none | F | 4 plan-sync and done incidents | L |
| preview/owner.ts, lan.ts | D | gate takes TS booleans; grants.ts (55e571b) calls console.previewGrant with the same TS `lan` boolean | F over raw headers | LAN gate proofs over real inputs | M |
| preview/facts.ts | D | Lean consumes TS-derived facts | F | inc-proof-of-typed-expectation | L |
| cap/cap.ts | S | ops.actor, ops.door wired, unused | F + capConsume | identity heuristic class | M |
| core/build-base.ts | S | Stale.chooseBase, hand-copied table | F | stale-service incidents | S |
| preview/manager.ts isOurs | D | none (55e571b added only an audit method) | F | identity heuristic class | S |
| preview/builds.ts, cache-policy.ts, picker.ts | D, S | partial | F, L | cycle-safe extends | M |
| store.ts replay repair | D | none | C | silent log truncation | S |
| preview/login.ts capacity | D | ownerLogin | F | global_bound when table full | S |
| rewrite.ts, serve-child.ts safeFile | D | none | C | inc-preview-csp-rewrite; traversal | M |
| lean.ts backoff, coalesce.ts | S | goldens | C (keep) | hot path | - |

### console-web (0.3k lines in files holding decisions; 0.9k JSX and 0.3k glue stay React)
| module | kind | today | target | value | eff |
|---|---|---|---|---|---|
| App.tsx step buttons, PostForm | D | reducer only | F `offered` | PostForm is always refused today | M |
| Plan.tsx columns, DeviceLane | D | TState only | F `column` | Ready count and hidden device tasks | S |
| Plan.tsx layout | D | criticalPath only | F `layers` | dep_left, cycle hazard | M |
| Builds.tsx state, action | D | rows only | F `rowAction` | no refused Rebuild click | M |
| Health.tsx code rows | D | 24 codes; 7 mapped to rows (`Health.tsx:100-108@50a438ec`, CONFIRMED) | L | sys.loadHigh shown | S |
| TaskDetail.tsx tables | S | isPortFix, Refusal | L | inc-ui-steps-unchecked | S |
| labels, age | D | none | C | format drift | S |

### Site (6.1k lines in files holding decisions, 4.0k run in the browser; 13.1k TSX and CSS, 3.8k glue stay)
| module | kind | today | target | value | eff |
|---|---|---|---|---|---|
| parts/*/logic.ts (26 files; 28 with `*logic.ts`) | S | per-part Lean + 35 golden files, no freshness job | C + freshness | spec edit drift | S |
| missing golden rows (signup, morph.mount, hitTest ...) | S | theorems, no rows | C | dead-code proofs | M |
| hero.accent/steps.ts, pain.notes/armed.ts, engine.scene | S | hand-typed Lean values | C | typed-expectation, hidden-pause port | S |
| engine/clock.logic.ts | D | golden file missing, test skipped | C | false green | S |
| registry/resolve.ts, entry-server enumerate | D | toy 6-part enum | C + table, L | variant-gate-flags-off, stale counts | M |
| parts/*/media.ts ids | data | Scope.lean restates | L | part-scope-breakpoint-gap | S |
| stage/hosts.ts HOST_FRAME | S | no row | C | task stage-host-lean | S |
| scripts/media-check.mjs | D | none | F | scope_sound premise | S |
| part-footprint selector matcher | G | 3 TS matchers | C | dead-selectors finding | M |
| shells/model.ts | S | dead twin | X | one gap item closed | S |

### Packages (5.7k lines in files holding decisions; 7.4k glue, 2.5k in-page stay)
| module | kind | today | target | value | eff |
|---|---|---|---|---|---|
| gate cli.mjs exit | S | Gate.Exit golden, no op | F | inc-gate-pass-uncompared | S |
| gate summary.mjs mask | D | none | F | masked row never passes | M |
| gate align-equiv.mjs | S | AlignEquiv golden | F inside gate.state | inc-prompt-premise-align | M |
| gate declared.mjs, view.mjs | D | cited only | F | inc-gate-scan-page-state | S |
| gate spec.mjs sweeps, freezegen, settlegen | G | interpreted `lean --run` | L via `fwcore sweepsgen` | freeze.test 32-36 s | S |
| gate settle.mjs, freeze.mjs | S | goldens | C (per-frame) | - | - |
| gaps/* judges | D | W rule only | F batched | devicecells 12-15 s | M |
| measure-chromium premise-verdict.mjs | S | EnginePremise golden, no op | F | inc-premise-unmeasured-goldens | M |
| measure-chromium compare.mjs | tool | run-to-run self-check CLI (`compare`, `determinism` scripts, `package.json:11,13`; cited by `Classes.lean:6`) | stays | - | - |
| measure-webkit quietsteps.mjs | S | tested twin; op `measure.quietSteps` is wired (`lean/Fw/Measure/Wire.lean:845@50a438ec`) | F (tests call the op), then X | - | S |
| measure-webkit reduce.mjs, class tables | S, D | ops exist for part | F | inc-ci-rerun-partial-arms | M |
| measure-wktr reduce, variance, premise, runset | S, D | partial | F | premise lane, merge-drops-measured-change | M |
| engine-check wave2.mjs | D | none | F | 3 attribution incidents | M |
| visual-diff verdict, settle-adapter, run.mjs calm | S, D | Pixel golden | F, L | third settle copy drifted | S |
| gh-budget wait.ts, charged.ts | D | verdict only | F, C | inc-ci-skipped-false-pass | M |
| contracts plan-sync.ts | S | sync proofs in `Plan/Core.lean:1827-1881` | F | 3 plan-sync incidents | M |
| contracts zod schemas | glue | none | L JSON Schema | inc-obs-silent-drop | L |

### CI (2.9k lines in files holding decisions; 0.9k glue and summaries stay)
| module | kind | today | target | value | eff |
|---|---|---|---|---|---|
| chromium-counts.yml plan step | D | SimPlan not run here | F `measure.countsPlan` | variant-gate-flags-off | S |
| merge jobs of 5 lanes | D | none for the arm set | F | inc-ci-rerun-partial-arms | M |
| dispatch-input checks | D | partly golden | L | flags-off, merge-drops-measured-change | M |
| changed-inputs.mjs | S | Intent golden | C + glob vectors | glob premise checked | M |
| merge-gate.mjs, gate-jobs.mjs deal | S, D | Merge proved, no op | F | proof covers CI merge | S |
| setup-lean cache key globs | D | hand globs miss include_str goldens | L | rebuilds on 16 jobs | S |
| runs-on labels, max-parallel | D | none | L | inc-ci-run-cap-prompt | M |
| mutants.sh merge verdict | D | none | F | inc-mutants-red-no-task | S |
| gate-shards.mjs | S | dead twin; named in `lean/Fw/Ci/Trigger.lean:239` and `golden/ci/triggers.jsonl` | X | - | S |

## Older open tasks that also overlap

These M5 tasks have no evidence on main and claim broad paths. They overlap wave rows but are left out of the "blocked
by" column, because the lead decides whether they are still live. Count = wave rows hit (overlap script
scratch generator output (not committed), glob prefix match, `lean/Fw.lean` imports excluded).

console-stale-2 25, ci-shape-obs 24 (parked), lean-first-gate 22, ci-shared-failure 14, gate-wall-target 13, land-dry
13, lfg-pilot 13, model-golden-rows 8, lfg-kill-ci 7, premise-inherits-retarget 7, fix-proofs 6, gate-run-identity 6,
premise-ack-2 6, lfg-ts-lint 6, gate-speed-impl 5, task-spec-lint 5, resume-rule 5, lfg-land-wire 5,
theorem-reach-lint 3, land-cancel-runs 2, gate-webkit-red 2, entries-due-ticks 2, and 16 tasks with 1 row each
(check-map-lean-2, review-loop-alert, gate-expected-red, variant-morph-panel-rest, people-pain-deferral, panel-rest-n11,
waapi-threshold-attr, avif-picture, orbit-read-first, carousel-hidden-pause, nav-default-selectors, ci-wait-lag,
visual-diff-3, lfg-shadow, lfg-enforce-new, lfg-enforce-all). The umbrella tasks lfg-burn-ts and lean-ops-gap overlap
every row; this plan becomes their item list.
