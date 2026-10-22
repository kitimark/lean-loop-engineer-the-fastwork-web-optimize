---
id: 2026-10-22-jev-retrieval-trace
kind: note
title: "Traced retrieval on D1: Haiku and Sonnet read nothing, Jev's file pick does not help, adopt is false for all four arms"
status: review
created: 2026-10-22
topics: [jev, oracle, claude-arms, retrieval, tracing, negative-result, lean]
---

# Traced retrieval on D1 (task jev-retrieval-trace)

The run follows the design in `research/notes/2026/10-2x-jev-retrieval.md`. Four arms ran on the 38 in-scope D1 rows:

- T-haiku and T-sonnet: `claude -p` with Read, Grep and Glob over a per-row tree, behind a hook.
- J-hybrid: Jev with the lines T-sonnet read.
- J-pick: Jev picks a file, then answers with that file in its state.

**Answer.**

- **Thinking text is not exposed (MEASURED).** The probe row gave Haiku one thinking block with 0 characters (only
  the signature) and gave Sonnet no thinking block. Over the T-haiku run, 40 blocks held 0 characters. Thinking is
  therefore not recorded. The record is the read trace plus the `evidence` field.
- **Neither model read a file (MEASURED).** Across 76 traced calls (38 rows × 2 models):
  - 0 Read, Grep or Glob calls, 0 denied, 0 unhooked; every trace verdict is `ok`.
  - T-sonnet gave no evidence.
  - T-haiku gave 9 evidence items for lines it never read. `validEvidence` refuses all 9, by `validEvidence_read`:
    valid evidence lies inside a read range.
- **Why (INFERRED):**
  - The system prompt opens with the arm preamble "Reply with one JSON object and nothing else"
    (`apps/runner/src/oracle-score.ts:49-53`), and reading is optional ("You may read them",
    `scripts/jev-trace.mjs:140-145`).
  - The state already holds the row's own text, and both models answer from it in 2-4 turns.
  - Making the models read would need a forced-read prompt. That is a new arm, not run here.
- **J-hybrid is C (MEASURED, proved).** With no read ranges, `hybrid_noreads` keeps every row unchanged, so all 38
  sends replayed from the log at 0 new sends. The answers equal C row by row.
- **Adopt is false for every arm and mode (MEASURED).** The Lean rule (`adopt_iff`) needs net ≥ 4 against C, X not
  worse, no gain on a dropped row and every gain traced. All 8 verdicts fail on `netLowC` already, so no hand trace of
  gains could flip them.

## Paired tables (38 rows; dropped rows: inc-workflow-unbound, inc-land-undeclared-reads, inc-upsert-keeps-evidence)

Against C (the clean first run of the same base model; for J arms, Jev on `d1`):

| Arm | Mode | Base right | Arm right | Gains | Losses | Net | Sign p | Adopt |
|---|---|---|---|---|---|---|---|---|
| t-haiku | strict | 7 | 7 | 5 | 5 | 0 | 1 | false |
| t-haiku | renorm | 21 | 20 | 2 | 3 | -1 | 1 | false |
| t-sonnet | strict | 19 | 21 | 7 | 5 | 2 | 793/1024 | false |
| t-sonnet | renorm | 22 | 23 | 5 | 4 | 1 | 1 | false |
| j-hybrid | strict | 18 | 18 | 0 | 0 | 0 | 1 | false |
| j-hybrid | renorm | 20 | 20 | 0 | 0 | 0 | 1 | false |
| j-pick | strict | 18 | 17 | 4 | 5 | -1 | 1 | false |
| j-pick | renorm | 20 | 18 | 2 | 4 | -2 | 11/16 | false |

Against X (the file-context ablation: the 27 expanded rows, plus C on the rest):

| Arm | Mode | Base right | Arm right | Gains | Losses | Net | Sign p |
|---|---|---|---|---|---|---|---|
| t-haiku | strict | 5 | 7 | 4 | 2 | 2 | 11/16 |
| t-haiku | renorm | 18 | 20 | 3 | 1 | 2 | 5/8 |
| t-sonnet | strict | 17 | 21 | 7 | 3 | 4 | 11/32 |
| t-sonnet | renorm | 20 | 23 | 5 | 2 | 3 | 29/64 |
| j-hybrid | strict | 14 | 18 | 7 | 3 | 4 | 11/32 |
| j-hybrid | renorm | 17 | 20 | 5 | 2 | 3 | 29/64 |
| j-pick | strict | 14 | 17 | 4 | 1 | 3 | 3/8 |
| j-pick | renorm | 17 | 18 | 2 | 1 | 1 | 1 |

What the tables show:

- **The C-to-T swings are noise.** The T arms read nothing, so their swings against C measure what changes with the
  new system prompt, the answer schema and resampling. T-sonnet still moved 12 rows (+7 -5). A net below 4 on 38
  rows is inside this noise (no sign p is below 0.3).
- **The wins over X are not retrieval.** They repeat the ablation's finding that adding file text lowers scores. They
  are not a gain from reading, since J-hybrid equals C.
- **J-pick picks f1.** Step 1 picked a file in all 36 rows with candidates, and never `none`. It chose f1 (the first
  path in sorted order) in 30 rows, f2 in 5 and f3 in 1. This suggests a position bias (INFERRED). Step 2 lost to C
  (net -1 strict, -2 renorm).
- **5 of the 36 J-pick prompts replayed.** Their picked excerpt equals the X row's file text, so the prompt equals the
  X prompt (`d1-expand.jsonl`, MEASURED).

## Spend (MEASURED)

| Arm | Calls | Jev sends | Claude cost |
|---|---|---|---|
| probe | 2 | 0 | $0.028 |
| t-haiku | 38 | 0 | $0.062 |
| t-sonnet | 38 | 0 | $1.109 |
| j-hybrid | 38 | 0 (38 replays) | — |
| j-pick step 1 (`d1k`) | 36 | 36 | — |
| j-pick step 2 (`d1p`) | 38 | 31 (7 replays) | — |

Before the run, 49 Jev sends were logged for 2026-10-22. Lean planned 72 more with none deferred (`sendPlan_day`), and
67 were sent, so the day closes at 116 of 200. Estimated Jev input tokens: 57,522 (step 1) and 341,276 (step 2).

## How it is built

- **Lean: `Fw.Oracle.Retrieve`**, served by fwcore as 12 `oracle.retrieve*` ops. It holds:
  - the per-row tree: an allowlist with no vocabulary words (`tree_refuses`, `tree_ledger`, `tree_research`);
  - the hook, with a budget of 8 calls and 32 KiB (`hookRun_bound`, `traceVerdict_hookRun`);
  - read ranges and evidence (`validEvidence_read`);
  - J-pick, with at most 4 candidates, an excerpt of at most 8 KiB, and none-is-no-op (`pick_none_noop`,
    `pickSends_le`);
  - J-hybrid (`hybrid_noreads`);
  - the send plan (`sendPlan_runs`, `sendPlan_day`) and the adopt rule (`adopt_iff`).
  - Golden: `packages/contracts/golden/oracle/retrieve.jsonl` (36 cases).
- **Harness: `scripts/jev-trace.mjs`.**
  - The per-row trees sit at the row's pin. 252 sampled files checked against Lean's tree verdict, all equal.
  - The PreToolUse hook calls `oracle.retrieveHook`.
  - The trace re-judges every tool use in the stream, including uses the hook never saw.
  - An answer counts only with an `ok` trace.
- **Results** are in `results/jev-retrieval-trace/`:
  - `probe.json` and `trees.json`;
  - `t-{haiku,sonnet}.{rows,answers}.jsonl` and `runs.jsonl`;
  - `hybrid.json`, `pick1.json`, `pick.json` and `paired.json`.
  - The raw streams stay local.

## Limits

- D1 only, 38 rows and one run per row. With no repeats, the noise floor comes from the C-to-T swings above, not from
  a variance estimate.
- The T arms answer a different system prompt from C (the read permission and the evidence field). So T against C
  measures that prompt change as well as retrieval, and retrieval itself was 0.
- A forced-read variant (a prompt that requires at least one read) was not run, so "would reading help" stays open.
- J-pick's candidates are the files the row names that are in its tree. Files found by search are not offered.
- No gain was traced by hand. None was needed, because every verdict fails `netLowC` first.
