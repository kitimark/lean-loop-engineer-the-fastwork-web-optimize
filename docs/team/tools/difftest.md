# difftest: randomized differential tests of TS against fwcore

`packages/difftest` runs each TS function that mirrors a fwcore wire op on fast-check inputs next to the real
`fwcore` binary and asserts equal output. The golden vectors (`packages/contracts/golden/**`) sample a few points;
this samples thousands.

## How it works
- `src/fwcore.mjs`: one fwcore child per test file, `batch(requests)` sends all lines in one write.
- `src/diff.mjs` `differential(core, {op, arb, ts, project?, compareErrors?})`:
  1. sample N inputs with the seed, one batch to fwcore, compare with `ts(input)` (canonical JSON, sorted keys);
  2. on a mismatch, rerun the same seed as an async fast-check property (shrinks), append the minimal case as a golden
     row `{name, request, response}` to `$DIFFTEST_OUT/<op>.jsonl` (default `packages/difftest/candidates/`, gitignored)
     and fail with request, TS output and Lean output;
  3. Lean refusals (`{"error"}`) are skipped (Lean refuses inputs where JS would throw) unless `compareErrors`; at
     least `minAccepted` (0.5) of the runs must be accepted, so a drifting generator cannot pass vacuously.
- Env: `DIFFTEST_SEED` (default 20261018), `DIFFTEST_RUNS` (default 300), `FW_CORE_BIN`, `DIFFTEST_OUT`.
- `test/selftest.test.mjs` is a negative control: a deliberately wrong symDiff must be caught and shrunk to <= 3 items.
- Run: `FW_CORE_BIN=... pnpm --filter @fw/difftest test`.

## CI: `.github/workflows/difftest.yml`
`fwcore` job builds the binary (artifact); `fixed` (seed 20261018, 2000 runs per op, blocks); `rotating` (seed = run
id, 20000 runs, `continue-on-error`, seed in the job summary, candidates uploaded as an artifact). Also on dispatch; no schedule (a schedule runs on main).

## Covered (TS -> Lean op)
| TS | op |
|---|---|
| measure-webkit `tally`, `reduceSteps`, `zones`, `symDiff`, `summarize`, `classify` (cells), `quietReply` | `measure.webkit.tally`, `.reduceSteps`, `.zones`, `measure.symDiff`, `.summarize`, `.classify`, `.quietSteps` |
| measure-chromium `snapshotCounts`, `n0Windows`+`n0FrameCounts` (incl. the +-1/1000 edge) | `measure.snapshotCounts`, `measure.n0Windows` |
| runner `hooks/cap.mjs identity`, console-api `cap.ts actorFor` | `ops.actor` (incl. refusal messages) |

## Inventory: TS with a Lean op, not covered here
- `apps/site/src/registry/resolve.ts` vs `flags.resolve`: imports extensionless (`./hash`), so Node cannot load it, and
  the registry shapes differ; needs a resolve hook or a vitest-hosted run plus a request mapper. Follow-up.
- `measure-chromium trace.mjs` splits/`traceToFrameCounts` vs `measure.splits`: needs a trace-event arbitrary. Follow-up.
- `measure-webkit` `perstep.classifyModes`, `determinism.classifyPasses` (glue over classify).

## Lean-first violations: TS decision logic with no Lean op (reported, not fixed)
| TS | decision | Lean |
|---|---|---|
| `apps/site/src/parts/*/logic.ts` (platform, nav.hitTest, platform.sweep, morph.tween/waapi, hero.*, engine.scroll, platform.entries/glint/marquee) | part math | `Fw.Parts.*` exists but only through the `partsgolden` generator, no wire op: there is no oracle for random inputs. Follow-up: op `parts.eval {part, fn, in}`. |
| `console-api/src/spool/workflow.ts` | workflow-run binding (`wfEvents`) | `Fw.Plan.Workflow` has no wire op |
| `packages/contracts/src/plan-sync.ts` `syncFrom` | which commit a plan sync reads | `Fw.Plan.syncFrom`, no wire op |
| `site/src/shells/model.ts` | shell box model | no Lean spec |
| `measure-wktr/src/reduce.mjs` | WKTR count reduction | header says Lean spec needed; no op |
| `runner/src/watch-collect.ts parseMemLevel` | memory pressure 1/2/4 -> level | none |
| `gh-budget/src/wait.ts verdict` | `fw ci wait` exit: 0 only if every decisive run succeeded | none |
| `runner/src/next.ts classifyTree`, `watchedFileOf` | process tree -> ciWait/sleepLoop/build/other | none |
| `runner/hooks/spawn-guard.mjs verdict` | enforce-mode deny/ask mapping | `ops.spawn` decides, mapping is TS |
| `gate-breakpoints/src/gaps/devicejudge.mjs judgeDevice` | `pass = W and X and T and S and L`, X and S equality checks | only `gate.reach` (W) |
| `runner/hooks/emit.mjs` | spawn matching by role + recency | marked TS stand-in |

(From a grep sweep; `timing.ts`, `engine-check.ts`, `incidents.ts`, `drain.ts` retry rule, `poller.ts` not checked.)
Console reducers, `obs.next`, `obs.timing`, `obs.health`, gate verdicts, `ci.budget.*`, `store.*` have no TS
counterpart (TS calls fwcore), so there is nothing to diff.

## Findings
No mismatch in any covered op at the fixed seed (2000 runs) or at local seeds 1 and 7 (3000 and 20000 runs per op).
