---
id: 2026-10-22-jev-retrieval-trace
kind: note
title: "Traced retrieval on D1: free to read, Haiku and Sonnet read nothing; forced to read, Haiku gains and Sonnet loses; Jev's file pick does not help; adopt is false for all six arms"
status: review
created: 2026-10-22
topics: [jev, oracle, claude-arms, retrieval, tracing, negative-result, lean]
---

# Traced retrieval on D1

The run follows the design in `research/notes/2026/10-2x-jev-retrieval.md`. Six arms ran on the 38 in-scope D1 rows:

- T-haiku and T-sonnet: `claude -p` with Read, Grep and Glob over a per-row tree, behind a hook.
- T-haiku-read and T-sonnet-read: the same, with a prompt and a hook that refuse the answer before one Read.
- J-hybrid: Jev with the lines T-sonnet read.
- J-pick: Jev picks a file, then answers with that file in its state.

**Answer.**

- **Thinking text is not exposed (MEASURED).** The probe row gave Haiku one thinking block with 0 characters (only
  the signature) and gave Sonnet no thinking block. Over the T-haiku run, 40 blocks held 0 characters, and over the T-sonnet run, 16 blocks held 0 characters. Thinking is
  therefore not recorded. The record is the read trace plus the `evidence` field.
- **Free to read, neither model read a file (MEASURED).** Across 76 traced calls (38 rows × 2 models):
  - 0 Read, Grep or Glob calls, 0 denied, 0 unhooked; every trace verdict is `ok`.
  - T-sonnet gave no evidence.
  - T-haiku gave 9 evidence items for lines it never read. `validEvidence` refuses all 9, by `validEvidence_read`:
    valid evidence lies inside a read range.
- **Why (INFERRED):**
  - The system prompt opens with the arm preamble "Reply with one JSON object and nothing else"
    (`apps/runner/src/oracle-score.ts:49-53`), and reading is optional ("You may read them",
    `scripts/jev-trace.mjs:140-145`).
  - The state already holds the row's own text, and both models answer from it in 2-4 turns.
- **J-hybrid is C (MEASURED, proved).** With no read ranges, `hybrid_noreads` keeps every row unchanged, so all 38
  sends replayed from the log at 0 new sends. The answers equal C row by row.
- **Forced to read, every row read exactly one file (MEASURED).** Over 76 calls (38 rows × 2 models), each row has one
  allowed Read, and every trace verdict is `ok`. The answer gate refused a first answer in 5 Haiku rows and 9 Sonnet
  rows, and each model then read and answered. 32 Haiku rows and 31 Sonnet rows read a file the row names.
- **Reading helps Haiku in renorm mode and hurts Sonnet (MEASURED, 38 rows).** T-haiku-read renorm gains 5 rows and
  loses 1 against C (net 4, sign p 7/32), and gains 5 rows with no loss against the unforced T-haiku (p 1/16).
  T-sonnet-read loses 7 rows and gains 2 against T-sonnet in both modes (net -5, p 23/128).
- **Adopt is false for every arm and mode (MEASURED).** The Lean rule (`adopt_iff`) needs net ≥ 4 against C, X not
  worse, no gain on a dropped row and every gain traced. 9 of the 12 verdicts fail on `netLowC`. T-haiku strict and
  T-haiku-read strict fail `gainOnDropped` (inc-upsert-keeps-evidence, plus inc-land-undeclared-reads for the forced
  arm). T-haiku-read renorm passes the first three conditions and fails only `untraced`: a hand read of its 5 gains
  found that each evidence range restates the row's own cause, and each row's cause names the file the model read
  (`results/jev-retrieval-trace/traced.json`).
- **Scoring is main's after oracle-eps.** Strict mode now accepts probabilities whose sum rounds to 1 at the reply's
  precision (`lean/Fw/Oracle/Core.lean`, `sumOk`). This changed only the strict rows of the tables below.

## Forced-read arms

T-haiku-read and T-sonnet-read against C, X and their unforced T arm (`results/jev-retrieval-trace/paired.json`,
`vsT`):

| Arm | Mode | C right | Arm right | vs C | vs X | vs T | Adopt (reasons) |
|---|---|---|---|---|---|---|---|
| t-haiku-read | strict | 9 | 14 | +10 -5, net 5, p 309/1024 | +12 -6, net 6 | +5 -4, net 1, p 1 | false (gainOnDropped, untraced) |
| t-haiku-read | renorm | 21 | 25 | +5 -1, net 4, p 7/32 | +7 -0, net 7 | +5 -0, net 5, p 1/16 | false (untraced) |
| t-sonnet-read | strict | 20 | 18 | +3 -5, net -2, p 93/128 | +3 -3, net 0 | +2 -7, net -5, p 23/128 | false (netLowC, untraced) |
| t-sonnet-read | renorm | 22 | 18 | +2 -6, net -4, p 37/128 | +2 -4, net -2 | +2 -7, net -5, p 23/128 | false (netLowC, netLowX, untraced) |

Read trace per arm (MEASURED, `t-{haiku,sonnet}-read.rows.jsonl`):

| Arm | Allowed Read, Grep, Glob | Denied calls | Answers refused before a Read | Bytes read | Rows with valid evidence | Invalid evidence |
|---|---|---|---|---|---|---|
| t-haiku-read | 38, 5, 12 | 13 outside, 5 overBytes | 5 | 239,499 | 36 | 2 (a file it did not read) |
| t-sonnet-read | 38, 15, 19 | 6 outside | 9 | 76,928 | 35 | 0 |

- **Why Haiku gains (INFERRED).** The 5 renorm gains rest on lines that repeat the row's cause, in the file that the
  cause names. Reading moved probability toward the class the row already implied. It added no fact the row lacked.
- **Why Sonnet loses (INFERRED).** This matches the ablation: file text in the state lowers Sonnet's scores. That note
  measured the effect with file text pasted into the state, and here Sonnet chose the file itself.
- **Evidence paths.** Haiku cited some lines by absolute path. `oracle.retrieveEvidence` now takes the row root and maps
  such paths through `rel`, so they are checked like relative ones.

## Paired tables (38 rows; dropped rows: inc-workflow-unbound, inc-land-undeclared-reads, inc-upsert-keeps-evidence)

Against C (the clean first run of the same base model; for J arms, Jev on `d1`):

| Arm | Mode | Base right | Arm right | Gains | Losses | Net | Sign p | Adopt |
|---|---|---|---|---|---|---|---|---|
| t-haiku | strict | 9 | 13 | 9 | 5 | 4 | 3473/8192 | false |
| t-haiku | renorm | 21 | 20 | 2 | 3 | -1 | 1 | false |
| t-sonnet | strict | 20 | 23 | 7 | 4 | 3 | 281/512 | false |
| t-sonnet | renorm | 22 | 23 | 5 | 4 | 1 | 1 | false |
| j-hybrid | strict | 20 | 20 | 0 | 0 | 0 | 1 | false |
| j-hybrid | renorm | 20 | 20 | 0 | 0 | 0 | 1 | false |
| j-pick | strict | 20 | 18 | 2 | 4 | -2 | 11/16 | false |
| j-pick | renorm | 20 | 18 | 2 | 4 | -2 | 11/16 | false |

Against X (the file-context ablation: the 27 expanded rows, plus C on the rest):

| Arm | Mode | Base right | Arm right | Gains | Losses | Net | Sign p |
|---|---|---|---|---|---|---|---|
| t-haiku | strict | 8 | 13 | 8 | 3 | 5 | 29/128 |
| t-haiku | renorm | 18 | 20 | 3 | 1 | 2 | 5/8 |
| t-sonnet | strict | 18 | 23 | 6 | 1 | 5 | 1/8 |
| t-sonnet | renorm | 20 | 23 | 5 | 2 | 3 | 29/64 |
| j-hybrid | strict | 17 | 20 | 5 | 2 | 3 | 29/64 |
| j-hybrid | renorm | 17 | 20 | 5 | 2 | 3 | 29/64 |
| j-pick | strict | 17 | 18 | 2 | 1 | 1 | 1 |
| j-pick | renorm | 17 | 18 | 2 | 1 | 1 | 1 |

What the tables show:

- **The C-to-T swings are noise.** The T arms read nothing, so their swings against C measure what changes with the
  new system prompt, the answer schema and resampling. In strict mode T-haiku moved 14 rows (+9 -5) and T-sonnet 11
  (+7 -4) without one read. No sign p against C is below 0.4.
- **The wins over X are not retrieval.** They repeat the ablation's finding that adding file text lowers scores. They
  are not a gain from reading, since J-hybrid equals C.
- **J-pick always picks a file.** Step 1 picked a file in all 36 rows with candidates, and never `none`. Step 2 lost
  to C (net -2 in both modes).
- **J-pick shows no first-slot bias (MEASURED, 10 rows).** The position share counts only rows with 2 or more
  candidates (`Multi`, theorems `share_few` and `share_multi`: a row with 0 or 1 candidate changes no share). fwcore
  (`oracle.retrievePickPos`, `results/jev-retrieval-trace/position.json`) counts 10 such rows of 38, with 26 single
  and 2 empty rows left out. Over the 10 it gives f1 4 (2/5), f2 5 (1/2), f3 1 (1/10) and `none` 0. A uniform pick over
  each row's candidates would give f1 a share of 29/60.
- **5 of the 36 J-pick prompts replayed.** Their picked excerpt equals the X row's file text, so the prompt equals the
  X prompt (`d1-expand.jsonl`, MEASURED).

## Spend (MEASURED)

| Arm | Calls | Jev sends | Claude cost |
|---|---|---|---|
| probe | 2 | 0 | $0.028 |
| t-haiku | 38 | 0 | $0.062 |
| t-sonnet | 38 | 0 | $1.109 |
| t-haiku-read | 38 | 0 | $0.089 |
| t-sonnet-read | 38 | 0 | $0.987 |
| j-hybrid | 38 | 0 (38 replays) | — |
| j-pick step 1 (`d1k`) | 36 | 36 | — |
| j-pick step 2 (`d1p`) | 38 | 31 (7 replays) | — |

Before the run, 49 Jev sends were logged for 2026-10-22. Lean planned 72 more with none deferred (`sendPlan_day`), and
67 were sent, so the day closes at 116 of 200. Estimated Jev input tokens: 57,522 (step 1) and 341,276 (step 2).

**Run split (MEASURED from the send log's timestamps; deviation).** The design asked for runs of 19 rows (≤ 38 sends,
about 200,000 tokens). Each step went out as one run instead. The log keeps no run id, so the split comes from
the send times. `d1k` sent 36 sends from 09:26:27 to 09:26:45 UTC with at most 0.55 s between sends. `d1p` sent 31
sends from 09:26:57 to 09:27:15 UTC with at most 0.75 s between sends. Both runs stay inside the Lean run caps that
`sendPlan_runs` proves (60 sends and 400,000 estimated tokens), and step 2 exceeded the design's 200,000-token figure.

## How it is built

- **Lean: `Fw.Oracle.Retrieve`**, served by fwcore as 14 `oracle.retrieve*` ops. It holds:
  - the per-row tree: an allowlist with no vocabulary words (`tree_refuses`, `tree_ledger`, `tree_research`);
  - the hook, with a budget of 8 calls and 32 KiB (`hookRun_bound`, `traceVerdict_hookRun`);
  - read ranges and evidence (`validEvidence_read`);
  - J-pick, with at most 4 candidates, an excerpt of at most 8 KiB, and none-is-no-op (`pick_none_noop`,
    `pickSends_le`);
  - J-hybrid (`hybrid_noreads`);
  - the pick-position share over rows with 2 or more candidates (`multi?_two`, `share_few`, `share_multi`);
  - the forced-read answer gate (`answerGate_allow`, `answerGate_readFirst`, `answerGate_free`);
  - the send plan (`sendPlan_runs`, `sendPlan_day`) and the adopt rule (`adopt_iff`).
  - Golden: `packages/contracts/golden/oracle/retrieve.jsonl` (43 cases).
- **Harness: `scripts/jev-trace.mjs`.**
  - The per-row trees sit at the row's pin. 252 sampled files checked against Lean's tree verdict, all equal.
  - The PreToolUse hook calls `oracle.retrieveHook`.
  - The trace re-judges every tool use in the stream, including uses the hook never saw.
  - An answer counts only with an `ok` trace.
- **Results** are in `results/jev-retrieval-trace/`:
  - `probe.json` and `trees.json`;
  - `t-{haiku,sonnet}.{rows,answers}.jsonl` and `runs.jsonl`;
  - `t-{haiku,sonnet}-read.{rows,answers}.jsonl` (the forced-read arms);
  - `hybrid.json`, `pick1.json`, `pick.json`, `position.json`, `traced.json` and `paired.json`.
  - The raw streams stay local.

## Limits

- D1 only, 38 rows and one run per row. With no repeats, the noise floor comes from the C-to-T swings above, not from
  a variance estimate.
- The T arms answer a different system prompt from C (the read permission and the evidence field). So T against C
  measures that prompt change as well as retrieval, and retrieval itself was 0.
- The forced-read arms change the prompt as well as the reads, so their swing against C mixes both. Against the
  unforced T arm only the read requirement differs (Haiku +5 -0, sign p 1/16, 38 rows).
- Grep output counts 0 bytes in the trace budget. Only Read spans count.
- J-pick's candidates are the files the row names that are in its tree. Files found by search are not offered.
- Only T-haiku-read renorm needed a hand trace (`traced.json`); none of its 5 gains was traced.
