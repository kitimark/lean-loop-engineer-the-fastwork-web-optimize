# incidents-1019 handoff

State: branch worktree-wf_07cbabb8-80d-1, base 3ff0dbdc; the commit adding this file holds the work.
- docs/team/incidents/ledger.json: 40 new incidents (inc-workflow-null-result ... inc-preset-change-stale-counts), 104 in total.
- research/mistakes/ledger.json: retro rows m176-m215, one per incident (linked by the incident's `mistake` field), and 1 dropped entry (lfg-mathview-facts follow-up: not a mistake).
- Diff is append-only (0 deleted lines). Serializers: incidents indent 1, mistakes indent 2, trailing newline.

Verified: `pnpm -s fw incidents lint` reports 104 incidents, 26 errors, 12 warnings (the 12 are the old baseline). All 26 errors are
missingFixTask / unknownHardening for the 11 proposed task ids below. Every cited commit is on main and every cited file exists.
Evidence that is only in the lead's list or transcripts is cited as "local-only" inside the cause (INFERRED).

Proposed tasks (the lead adds them to the graph; then lint is clean):
| id | owner | stream | title | writes |
|---|---|---|---|---|
| workflow-salvage-wire | lean-prover | tooling | salvage stage in build-review on a null build, from Fw.Ops.Salvage via fwcore | .claude/workflows/build-review.js, lean/Fw/Wire*.lean, apps/runner/src/workflow/salvage.ts, apps/runner/test/workflow-salvage.test.ts, docs/team/tools/prompt-rules.md, handoff |
| build-review-lint | lean-prover | tooling | Lean rule over build-review task args: Lean stages iff writes touch lean/, fix round needs findings, per-item report, preamble lines present | lean/Fw/Ops/BuildReview.lean, golden jsonl, .claude/workflows/build-review.js, handoff |
| fw-task-add | console-builder | tooling | `fw task add`: contract shape check (stream, writes incl. handoff), 1-space serializer, zero deleted lines | apps/runner/src/task-add.ts, its test, docs/team/tools/task-add.md, handoff |
| queue-idle-guard | lean-prover | tooling | Lean queueIdle gates `fw console restart` and main-checkout edits | lean/Fw/Ops/QueueIdle.lean, golden, apps/runner/src/console.ts, handoff |
| land-rows | console-builder | tooling | `fw land --queue --rows <file>`; branch from each worktree HEAD; no env vars | apps/runner/src/land-queue.ts, its test, docs/team/tools/land-queue.md, handoff |
| land-no-api | console-builder | tooling | fw land --dry without console-api (plan from the graph file) | apps/runner/src/lib.ts, apps/runner/src/fw.ts, apps/runner/test/lib.test.ts, handoff |
| land-queue-verdict | console-builder | tooling | queue maps a thrown refusal to its Kind and logs it; unknown only with a reason | apps/runner/src/land-queue.ts, apps/runner/src/land-verdict.ts, tests, handoff |
| land-order-overlap | lean-prover | tooling | queue order by declared-write overlap on shared generated files | lean/Fw/Ops/LandOrder.lean, golden, apps/runner/src/land-queue.ts, handoff |
| manifest-merge | console-builder | tooling | url-keyed union merge driver for apps/site/assets.manifest.json (LedgerMerge pattern) | scripts/merge-manifest.mjs, .gitattributes, test, handoff |
| lane-admit-load | lean-prover | tooling | admit local-heavy lanes by load1 < 2 x cores and a running check.sh cap | lean/Fw/Sched/Admit.lean, golden, apps/runner/src/watch.ts, handoff |
| gate-narrowed-out | lean-prover | gate | narrowed gate readings excluded from the C3/flag decision domain (theorem + golden) | lean/Fw/Gate/*.lean, golden, handoff |

Open: the "fixed" status the lint derives comes from the fix task being done. For recurrences (inc-plan-sync-manual repeats
inc-plan-sync-on-land-only) that status is only as good as that task. No research note was written: the task names only the ledgers and this file.
Conventions: leanReason is plain text (no LaTeX); `no` verdicts carry empiricalCheck and no hardening; the cause starts with CONFIRMED or INFERRED.
Read first: docs/team/incidents/README.md, then the new tail of docs/team/incidents/ledger.json.
