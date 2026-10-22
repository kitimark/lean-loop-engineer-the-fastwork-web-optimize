---
id: 2026-10-22-jev-file-context-ablation
kind: note
title: "D1 file-context ablation: the named code files lower every arm, adopt is false"
status: review
created: 2026-10-22
topics: [jev, oracle, leakage, negative-result, evaluation, lean]
---

# D1 file-context ablation

The run answers the design in `research/notes/2026/10-2x-jev-file-context.md`. Adding the leak-safe code files a D1
row names to its state lowers the score of every arm on the 27 rows that changed (MEASURED). The adopt rule says
false: every arm and mode has net below 4, and all six nets are negative. File context stays out of the Jev state.

| Arm | Mode | Base right | Arm right | Gains | Losses | Net | Sign p |
|---|---|---|---|---|---|---|---|
| jev | strict | 16 | 12 | 3 | 7 | -4 | 11/32 |
| jev | renorm | 17 | 14 | 2 | 5 | -3 | 29/64 |
| haiku | strict | 7 | 5 | 3 | 5 | -2 | 93/128 |
| haiku | renorm | 15 | 12 | 0 | 3 | -3 | 1/4 |
| sonnet | strict | 14 | 12 | 4 | 6 | -2 | 193/256 |
| sonnet | renorm | 17 | 15 | 2 | 4 | -2 | 11/16 |
| jev-naive | strict | 16 | 15 | 2 | 3 | -1 | 1 |
| jev-naive | renorm | 17 | 15 | 1 | 3 | -2 | 5/8 |

All counts are out of 27 paired rows (MEASURED, `results/jev-file-context-ablation/paired.json`). No single
difference is significant: the smallest two-sided sign-test p is 1/4. The finding is that the files did not help, and
the direction is down in all eight rows of the table. The jev-naive arm is a contrast and does not enter the adopt
rule.

## What was built (CONFIRMED, Lean)

- `lean/Fw/Oracle/Expand.lean` decides which files a row gets. The path scan `pathsOf` is a Lean port of `PATH_RE`
  in `scripts/jev-leak.mjs`. The `safe` config is an allowlist: prefixes `apps/ packages/ scripts/ lean/Fw/`, never
  `lean/Fw/Oracle/`, code extensions only. A file holding a mistake class, an exact severity word or the row id
  (case-insensitive) is dropped whole. A greedy fit in path order keeps whole files while the JSON-escaped state stays
  under `stateCap` 32768 bytes.
- Theorems: `expand_files` (every emitted file is allowed, whole and vocabulary-free), `expand_same`,
  `expand_refused` (refused only when no single file fits), `expand_uncut` (`capState` keeps the expanded state
  whole), `expand_local`, `expand_noop_state` (a row with no kept file keeps its state, so it replays with 0 sends).
- `lean/Fw/Oracle/ExpandPaired.lean` holds the paired flips, the exact two-sided sign test `signP` and the adopt rule
  `adopt` with `adopt_iff` and the `reject_*` theorems. `minNet` is 4.
- `lean/Fw/Oracle/ExpandWire.lean` adds the ops `oracle.expandPaths`, `oracle.expand`, `oracle.paired` and
  `oracle.adopt`. Their golden is `packages/contracts/golden/oracle/expand.jsonl`, and `scripts/jev-expand.test.mjs`
  replays it through fwcore.
- `scripts/jev-expand.mjs` is I/O glue. It reads git blobs and answer files, and Lean makes every decision.

## Inputs (MEASURED, `node scripts/jev-expand.mjs build`)

The safe config reads each file at the row's pin, the last commit of `ecdc0787` before the incident time
(`git rev-list -1 --before=<at>`). The naive config reads every named file under any top directory at `ecdc0787`,
with no vocabulary drop. That is what a reader who opens today's files would see.

| Count | Value |
|---|---|
| D1 rows, pinned | 116, 115 |
| Safe result: expanded, refused, same | 27, 9, 80 |
| Expanded rows with 1, 2, 3 files | 24, 2, 1 |
| Escaped state of expanded rows | 3425 to 28196 bytes |
| File verdicts: kept, notAllowed, overCap, vocab, noText | 31, 39, 16, 7, 2 |
| Vocab drops by word | blocker 3, c-orphan-wait 2, c-late-check 1, row id 1 |
| Naive on the 27 rows: expanded, refused | 25, 2 |

The record per row (paths, verdicts, byte counts, blob ids, no file text) is
`results/jev-file-context-ablation/inputs.json`. The datasets `d1-expand.jsonl` (set `d1x`) and `d1-naive.jsonl`
(set `d1n`) stay in `.cache/jev`, out of git.

The design scan counted 38 rows; the build expands 27. The scan kept a file that is allowlisted, present at the pin
and free of class ids, with no cap. That rule applied to `inputs.json` gives the same 38 rows (MEASURED; the scan
script is not in git). The other 11 rows keep no file under `Fw.Oracle.Expand` for one of two reasons:

| Reason | Rows |
|---|---|
| Every kept file alone exceeds the cap, so the row is refused rather than cut (9) | `inc-retention-hides-unlanded`, `inc-prompt-premise-align`, `inc-proof-of-dead-code`, `inc-mutants-red-no-task`, `inc-helper-spawn-named`, `inc-trajectory-pooled-window`, `inc-land-scope-stale-base`, `inc-main-checkout-busy-queue`, `inc-dispatch-push-runs` |
| Every allowlisted file holds `blocker` (a `Labels.exactWords` entry, matched as a case-insensitive substring, so `blockers` counts), which the scan did not check (2) | `inc-workflow-unbound`, `inc-upsert-keeps-evidence` |

The row-id drop removes `apps/runner/src/land.ts` from `inc-land-undeclared-reads`, which still expands with
another file, so it changes no count.

## Sends and costs (MEASURED, 2026-10-22)

| Arm | Command | Calls | Cost |
|---|---|---|---|
| jev d1x | `pnpm fw oracle send --set d1x` | 27 | input 245603 tokens over all 116 rows, about $0.0103 |
| jev d1n | `pnpm fw oracle send --set d1n` | 22 | input 264960 tokens over all 116 rows, about $0.0111 |
| haiku | `node scripts/jev-arms-clean.mjs run --model haiku --set d1x ...` | 27 | $0.052, 36 s wall |
| sonnet | `node scripts/jev-arms-clean.mjs run --model sonnet --set d1x ...` | 27 | $1.004, 49 s wall |

Jev used 49 of the daily cap of 200. Each set took two runs because the per-run estimated-token budget stopped the
first. The 89 unchanged rows of each set replayed from the answer log with 0 sends, as `expand_noop_state` predicts
(`node scripts/jev-expand.mjs status` shows 0 to send). Haiku and Sonnet answered 27 of 27 with a scorable answer.

Scores over all 116 rows (`pnpm -s fw oracle score --set d1x --arm jev --out ...`, lenient pick): Jev d1 65, d1x 62,
d1n 63. On the 27 rows: Haiku 13 and Sonnet 15. Files: `results/jev-file-context-ablation/d1x.json`, `d1n.json`.

## Paired rule (MEASURED, `node scripts/jev-expand.mjs paired`)

Each row counts as right when the answer validates and its pick is the label. Strict validates the answer as given.
Renorm first divides the probabilities by their sum, because oracle-eps has not landed, and an answer that sums to 1.1
fails strict. A failure or a missing answer counts as wrong. The baselines are the D1 replies in the answer log for
Jev and `results/jev-arms-clean/d1-{haiku,sonnet}.answers.jsonl` for the isolated arms.

`oracle.adopt` returns false with 20 reasons: `netLow` for all six arm-modes, plus 14 `untraced` gains. The hand trace
was not done. `reject_netLow` already fixes the verdict, so a trace could not change it.

## Mechanism (INFERRED from a hand read of the losses)

- `inc-watch-unlanded-after-land` (label `c-order-derived`) is lost in 6 of the 8 arm-modes. Sonnet moves from
  `c-order-derived` to `c-proxy-verdict`.
- `inc-worktree-role-as-teammate` (label `c-policy-prose`) is lost in all four Jev and naive arm-modes; the read
  answer moved to `c-env-assume`.
- Both rows gain 18 to 27 KB of the code they name. That code describes how the system works, not what went wrong.
  It dilutes the row's own text and pulls the answer toward the classes the code suggests.
- The labels are judgments over the row text, as the design note predicted. A fact from a file cannot move a judgment
  the row already supports, but bulk text can distract from it.

## Naive contrast (MEASURED)

The naive arm was meant to show the leak the allowlist closes. On D1 it shows almost none. The label text appears in 0
naive rows and the row id in 1. The large leak files, `docs/team/work-graph.json` and the incident ledger, exceed the
cap on their own and never enter. Most naive kept files are the same code as the safe arm at a later commit; only 2
are docs files. Under this cap, the code allowlist together with the cap closes the D1 leak. The vocabulary drop
removed 7 files, but only one of them sits on an expanded row (`inc-land-undeclared-reads`, row id), and no arm gains
on it.

## Lesson (negative result)

Before adding context to a judgment label, expect harm, not neutral noise. Text about the system the row names reads
as evidence for the classes that describe that system, and it outweighs the row's few sentences. Check this with a
paired run on the changed rows before any full re-measure. That run cost 49 Jev sends and $1.06 of isolated calls.

## Limits

- D1 only, 27 rows. The power is low: the sign test needs at least 6 gains and 0 losses for p below 0.05, and no
  p here is below 1/4.
- The instruction text is unchanged. The `files` field was added to the incident-class fields, and no instruction
  tells the model what it is.
- The fit measures escaped bytes before redaction. A redaction that lengthens a line could push a row past the cap;
  this was not checked.
- The path scan is a Lean port of `PATH_RE`; a broader scan would name more files.
- The hand trace of the 14 gains is not done.
- Both modes are reported because oracle-eps has not landed; the verdict is the same in each.
