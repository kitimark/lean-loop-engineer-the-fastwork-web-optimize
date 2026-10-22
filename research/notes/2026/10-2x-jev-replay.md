# Jev on our own history: offline replay of D1 and D2 (task jev-replay)

Status: MEASURED 2026-10-22 local (2026-10-21 UTC, the answer log's day) with `jev-1.13.0`; rows from the local
datasets of task jev-datasets (`.cache/jev`, gitignored). Numbers come from `results/jev/d1.json` and `d2.json`
(`pnpm fw oracle score`, Lean's `oracle.score`). The Haiku and Sonnet arms are not run yet; the lead runs them with
the prompt below.

**Answer.** Jev is not yet useful as an advisor on either question. On D1 (incident class, 14 options) it is right
on 65 of 116 incidents (56.0 %; 61 of 116, 52.6 %, if the 9 replies rejected only for rounding count as
wrong). On D2 (finding severity, 3 grades) it is right on 40 of the 83 sampled findings
answered so far (48.2 %); one grade in three would be right by chance. Lean certifies no option on either set: no
option reaches precision 9/10 with 5 right on the choose part. The whole run cost under one cent: Jev bills only
input tokens. A Jev call took 0.3 s median.

## What was sent

| set | question | rows sent | how Lean picked them | held out |
|---|---|---|---|---|
| D1 | `incident-class` (13 classes + none) | 116 | every labeled row (`d1`, unknown label 0) | 33 |
| D2 | `finding-severity` (blocker, fix-before-land, follow-up + unclear) | 83 of 90 | stratified sample, `d2_pick_le` | 73 of 75 |

- The split is Lean's one canonical split (`Labels.heldOut`, FNV-1a 32 of the id is 0 mod 4; `heldOut_canonical`).
  A row's own `split` key is never read.
- Sample size from the certification math: at q = 9/10, k = 5, an option is certifiable only with at least 25
  held-out rows of its label (`certify_needs_holdout`, `minHoldout_least`; `minHoldout` = 25 by `#guard`). D2 takes
  25 held-out and 5 choose-part rows per grade, in a hash order other than the split's (`sampleHeld_mem`,
  `d2_pick_le`: at most 90 rows). Follow-up has 25 held-out rows in the sample, but only 23 are answered so far: 2
  of the 7 rows still to send are held out, so follow-up cannot certify before they are sent.
- D2 leak filter: 281 of 1534 labeled findings start with their own grade ("Blocker: ...") in `what` or `where`
  (`leaks`); they are never sampled.
- State: D1 sends title, symptom, cause; D2 sends finding, where, task, unit, limits (`rowState_declared`). Texts are
  cut into lines of at most 400 characters, and local run ids `wf_<hex>` become `wf_<id>` (`scrubWf_clean`), then
  Lean's redaction runs as for every request.
- Budget: per run at most 60 sends and 400 000 estimated input tokens (`preRun_send`; estimate = body bytes), and the
  daily cap of 200. Sends used: 116 (D1, 2 runs) + 83 (D2, 2 runs) + 1 earlier = 200, the cap. The other 7 D2 rows
  (all follow-up) wait for the next UTC day: `pnpm fw oracle send --set d2` sends only those, then
  `pnpm fw oracle score --set d2` rewrites the Jev arm.

## D1: incident class (MEASURED, 116 rows)

| part | rows | valid answers | right | accuracy |
|---|---|---|---|---|
| all | 116 | 106 | 65 | 56.0 % |
| holdout | 33 | 31 | 18 | 54.5 % |

| class | labeled | chosen | right | precision | recall |
|---|---|---|---|---|---|
| c-orphan-wait | 6 | 6 | 5 | 0.83 | 0.83 |
| c-order-derived | 16 | 8 | 4 | 0.50 | 0.25 |
| c-shared-no-lock | 10 | 10 | 9 | 0.90 | 0.90 |
| c-quota | 7 | 6 | 4 | 0.67 | 0.57 |
| c-proxy-verdict | 7 | 6 | 2 | 0.33 | 0.29 |
| c-identity-heuristic | 8 | 8 | 4 | 0.50 | 0.50 |
| c-late-check | 14 | 6 | 6 | 1.00 | 0.43 |
| c-unearned-claim | 9 | 5 | 3 | 0.60 | 0.33 |
| c-sample-validity | 5 | 11 | 4 | 0.36 | 0.80 |
| c-env-assume | 16 | 18 | 12 | 0.67 | 0.75 |
| c-spec-gap | 14 | 19 | 8 | 0.42 | 0.57 |
| c-handcopy | 2 | 6 | 2 | 0.33 | 1.00 |
| c-policy-prose | 2 | 3 | 2 | 0.67 | 1.00 |
| none | 0 | 4 | 0 | 0 | - |

- The confusion matrix is in `results/jev/d1.json` (`arms.jev.confusion`). The largest mix-ups: c-late-check
  answered as c-spec-gap (3), c-order-derived as c-env-assume (3).
- 10 replies fail validation and are scored by their choice, the rule for every arm (`pickOf`). 9 have 14
  probabilities that sum to 0.99: Jev rounds each to two decimals, and `Core.eps` = 1/1000 rejects that. 1 picks an
  option that is not the most probable (wrong either way). 4 of the 9 rejected replies pick the labeled class (1 held
  out); counted as wrong, D1 is 61 of 116 (52.6 %), holdout 17 of 33. That lower count is set by eps, not by Jev's
  choices. A rejected reply still cannot be certified (`certify` reads valid answers only). Finding: with
  n options rounded to 0.01 the sum can be off by up to n·0.005, so `eps` should depend on n, or Jev's sums should
  be renormalized before validation (follow-up; `Fw.Oracle.Core` is outside this task).
- Certification: none. A class has at most 5 held-out rows, under the 25 any certificate needs, so D1 measures
  accuracy only.

## D2: finding severity (MEASURED, 83 of 90 sampled rows)

| part | rows | right | accuracy |
|---|---|---|---|
| all | 83 | 40 | 48.2 % |
| holdout | 73 | 34 | 46.6 % |

| label \ answer | blocker | fix-before-land | follow-up | unclear |
|---|---|---|---|---|
| blocker (30) | 23 | 6 | 1 | 0 |
| fix-before-land (30) | 15 | 11 | 4 | 0 |
| follow-up (23) | 5 | 12 | 6 | 0 |

| grade | precision | recall | holdout precision |
|---|---|---|---|
| blocker | 0.53 | 0.77 | 0.53 (19 of 36) |
| fix-before-land | 0.38 | 0.37 | 0.35 (9 of 26) |
| follow-up | 0.55 | 0.26 | 0.55 (6 of 11) |

- Rescored with the one rule for every arm (`pickOf`): unchanged, since all 83 D2 replies pass validation.
- Jev leans towards the more severe grade: 43 of 83 answers are blocker, against 30 blocker labels.
- The labels are noisy (an accepted limit): a D2 label is the grade the review round gave, not a ruling on the text.
- Certification: none. The choose part has at most 5 answered rows per grade, so k = 5 would need every one advised
  and right; the holdout precision of every grade is far below 9/10.

## Cost and latency (MEASURED)

| set | input tokens | output tokens | $ at $0.042 / Mtok in | estimate (bytes) | ms median | ms mean | ms max |
|---|---|---|---|---|---|---|---|
| D1 | 125 470 | 19 549 | 0.0053 | 338 433 | 304 | 328 | 826 |
| D2 (83) | 78 620 | 4 623 | 0.0033 | 202 753 | 320 | 340 | 604 |

- Price CONFIRMED (docs.typesafe.ai/models.md, read 2026-10-22): $0.042 per million input tokens, output not billed.
  $ = usage × price (`armPrice`, `dollars`), not an invoice.
- The byte estimate is 2.6 to 2.7 times the billed tokens, so the run budget is conservative.
- Time per call is the client's wall time in the answer log (network included).

## The Haiku and Sonnet arms (for the lead)

Same rows, same state, same instructions and criteria as the Jev body. Prices CONFIRMED (docs.claude.com pricing,
read 2026-10-22): Haiku 5.5 $0.10 in / $0.50 out, Sonnet 5.5 $2 / $10 per Mtok.

1. `pnpm fw oracle arm-input --set d1 --out <scratch>/d1-prompts.jsonl` (and `--set d2`): one `{id, prompt}` per
   row. Keep the file out of git: the prompts hold dataset text.
2. Send each `prompt` as the whole user message, without tools or a system prompt. It starts with this preamble
   (`ARM_PREAMBLE` in `apps/runner/src/oracle-score.ts`):

   > You answer one classification question about the state below. The question, its options with their criteria,
   > and the state are given as JSON. Reply with one JSON object and nothing else: {"choice": "<one option name>",
   > "probabilities": {"<option name>": <number>, ...}}, with a probability for every option, summing to 1, and the
   > choice the option with the highest probability.

   followed by `{question, type, instructions, criteria, state}` from the Jev body (criteria in Jev's shuffled order).
3. Write one line per row: `{"id": ..., "choice": ..., "probabilities": {...}, "inputTokens": n, "outputTokens": n,
   "ms": n}`. A reply that is not valid JSON: keep `choice` only if it names an option, else omit the row.
4. `pnpm fw oracle score --set d1 --arm haiku --answers <file>` (and `sonnet`, and `d2`) adds the arm to
   `results/jev/<set>.json`. Lean validates each answer as it does Jev's; an answer that fails validation (no
   probabilities, or a sum off by more than `Core.eps`) is scored by its choice, as a Jev reply is, but cannot be
   certified.

## Limits

- D2 labels are noisy; D3 and D4 are not sent (gaps of jev-datasets).
- 7 D2 rows wait for the next UTC day (daily cap 200).
- One model version, one run per row: no repeat runs, so no variance across calls.
- The prompt text and the arm-input writer are TS (`oracle-score.ts`); the bodies they quote are Lean's.
- The first-run Claude arms read only their prompt chunks; their thinking is signature-only (see `10-2x-jev-retrieval.md`).
