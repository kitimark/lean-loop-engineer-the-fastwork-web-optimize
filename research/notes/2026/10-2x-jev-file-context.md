---
id: 2026-10-22-jev-file-context
kind: note
title: "Expanding the repo files a row names into the Jev state: not worth building, labels are judgments and post-fix files leak them"
status: review
created: 2026-10-22
topics: [jev, oracle, leakage, negative-result, evaluation, lean-design]
---

# Expanding named repo files into the Jev state

**Answer.** No. Do not build the expansion and do not re-measure with it.

- No row needs a file to reach its label. D1 labels are the ledger's own class and D2 labels are the reviewer's own
  grade: both are judgments about text the row already holds. Rows that name files score like rows that do not
  (MEASURED, gap at most 5.9 points in either direction, table below).
- The signal the files do carry is the label itself. 9 rows name a file that holds their label, a decoy label or the
  lead's later triage (MEASURED). The one row all five arm runs missed, `inc-precommit-stale-fwcore`, names
  `scripts/checkmap.mjs`, whose line 2 states its class `c-late-check` (CONFIRMED,
  `scripts/checkmap.mjs:2@ecdc0787`). A re-measure would score that leak as a gain.
- The files are too large for the state. The median D2 row names 95.5 KiB of files against `stateCap` 32768 bytes
  (MEASURED; `lean/Fw/Oracle/Redact.lean:195@7e676da5`).

Every count below comes from one run of the committed scan (MEASURED, 2026-10-22, script at 11d7ec4a):

```
node scripts/jev-leak.mjs --rows <dir with rows-d1.json, rows-d2.json> --clean results/jev-arms-clean
```

The rows are the trial rows joined for the review page (state, label, and the Jev, Haiku and Sonnet answers of the
first run). They stay out of git because they hold dataset text. `--clean` adds the isolated Haiku and Sonnet re-run
of `research/notes/2026/10-2x-jev-arms-clean.md` as two more arms. The scan reads each file from git, never from the
working tree: D1 at `ecdc0787` (the ledger commit D1 was built from), D2 at `c31e0848` (main when the trial counts
were written; D2 has no ledger commit).

**Path regex** (every count depends on it): a top-level repo dir (`research docs lean lean-math apps packages scripts
.github .claude .circleci refs results snapshot .cache .local`), a slash, then the characters `A-Za-z0-9_.@*{}<>,/+-`,
ending on a letter, digit, `_`, `*`, `}` or `>`, with no path character before it (`PATH_RE`,
`scripts/jev-leak.mjs:25`). It runs over every string of the row's state. Trailing `.` and `,` are stripped, `:N` line
suffixes are not captured, and bare file names with no directory are not counted. A path with `*{}<>` counts as a
pattern.

## What the named files would add (MEASURED)

| | D1 (116 rows) | D2 (90 rows) |
|---|---|---|
| Rows naming at least one path | 64 | 88 |
| Rows with at least one file (blob) at the source commit | 57 | 84 |
| Distinct paths | 72: 61 blobs, 3 dirs, 3 patterns, 5 missing | 244: 171 blobs, 14 dirs, 34 patterns, 25 missing |
| Fields that name a path (rows) | cause 51, symptom 21, title 11 | where 82, task 47, finding 30, limits 12, unit 1 |
| Files per row with a blob, raw bytes: median, p90, max | 26.0, 132.1, 722.7 KiB | 95.5, 851.5, 1111.7 KiB |
| Same, JSON-escaped (text blobs): median, max | 26.9, 772.7 KiB | 97.7, 1208.6 KiB |
| Rows over `stateCap` 32768 B (raw) | 23 | 57 |
| Rows over `bodyCap` 65536 B (escaped) | 17 | 50 |

Both sets together name 294 distinct paths. The caps are `stateCap` (`lean/Fw/Oracle/Redact.lean:195@7e676da5`) and
`bodyCap` (`lean/Fw/Oracle/Send.lean:24@7e676da5`), CONFIRMED. Whole files would break `stateCap` on 23 D1 and 57 D2
rows.

## Label leaks (MEASURED by the scan, refs CONFIRMED with `git show`)

| Row | Label | File (at source commit) | What it holds | Arms right (Jev, Haiku, Sonnet, Haiku clean, Sonnet clean) |
|---|---|---|---|---|
| inc-precommit-stale-fwcore | c-late-check | `scripts/checkmap.mjs:2@ecdc0787` | "mistake class c-late-check" | none of 5 |
| inc-until-grep-finished-output | c-orphan-wait | `apps/runner/hooks/wait-guard.mjs:2@ecdc0787` | "mistake class c-orphan-wait" | 5 of 5 |
| inc-parallel-write-overlap | c-shared-no-lock | `lean/Fw/Sched/Admit.lean:1455@ecdc0787` | "c-shared-no-lock" in an incident line | 5 of 5 |
| inc-wait-guard-while-read-fp | c-spec-gap | `apps/runner/hooks/wait-guard.mjs:2@ecdc0787` | decoy: "c-orphan-wait" | 5 of 5 |
| ci-push-render-guard#f1 | blocker | `docs/team/work-graph.json:12061@c31e0848` | "ci-push-render-guard review follow-up: ..." | Haiku clean only |
| graph-check-lean#f1 | blocker | `docs/team/work-graph.json:12347@c31e0848` | "graph-check-lean review follow-ups: ..." | 5 of 5 |
| graph-check-lean#f2 | follow-up | same line | same record | none of 4 (no Jev answer) |
| user-review-queue#f1 | fix-before-land | `docs/team/work-graph.json:12037@c31e0848` | "user-review-queue review follow-ups: ..." | none of 5 |
| orphan-guard#f3 | follow-up | `docs/team/work-graph.json:10971@c31e0848` | "orphan-guard review follow-ups: ..." | Sonnet clean only |

D2 rows are listed by task and finding number; their full ids carry the review workflow id. The D2 records are the
lead's triage after the review. Read against the findings, they show that the task got follow-up work, and the
graph-check-lean record's item (1) is near f1's topic (staged inputs) filed as a follow-up while the reviewer graded
f1 blocker (INFERRED, a decoy there). Their signal is weaker than the D1 class ids, which state the label verbatim.

Weaker signal the scan counts but does not add to the 9:

- 52 of the 57 D1 rows with a blob name a file that changed between the incident's `at` and `ecdc0787`, so most
  files describe the fix, not the state the incident saw.
- 14 D2 rows name a handoff whose first lines say "round N", which shows the review was refused.
- 4 D1 rows name a file that holds the row's own incident id (`next.ts`, `Next.lean`, `land.ts`,
  `work-graph.json`).

**Pinning the commit does not remove the leak.** At the per-row pin (the last ancestor of `ecdc0787` committed before
the incident's `at`), 2 rows still get their own class id: `inc-precommit-stale-fwcore` and
`inc-until-grep-finished-output`. `scripts/checkmap.mjs` was added at `aa02285e` (2026-10-18T13:49+07:00), 37 minutes
before its incident's `at` 14:26 (CONFIRMED, `git log`, ledger at `ecdc0787`), already naming `c-late-check`. The
class id is there because the file is hardening for that class, written for earlier incidents of it.

## Rows that name files score like rows that do not (MEASURED)

| Arm | D1 naming paths | D1 no path | Gap (points) |
|---|---|---|---|
| Jev | 36/64 (56.3 %) | 29/52 (55.8 %) | +0.5 |
| Haiku, first run | 37/64 (57.8 %) | 32/52 (61.5 %) | -3.7 |
| Sonnet, first run | 42/64 (65.6 %) | 36/52 (69.2 %) | -3.6 |
| Haiku, clean | 37/64 (57.8 %) | 27/52 (51.9 %) | +5.9 |
| Sonnet, clean | 41/64 (64.1 %) | 34/52 (65.4 %) | -1.3 |

The sign changes between runs of the same model, so the gap is noise at this size. D2 has no control: only 2 of 90
rows name no path.

## Mechanism and lesson (negative result)

- **Mechanism.** Hardening code names the mistake class it hardens in its header comment (`checkmap.mjs:2`,
  `wait-guard.mjs:2` at `ecdc0787`), and the work graph records the lead's triage of each review. The files a row
  names are therefore, more often than not, the record of the label, written by the same people who wrote the
  label. A model given them can copy the answer instead of judging the text.
- **Why it cannot help.** A label that is a judgment over the row's text depends only on that text and the criteria.
  Facts from files can only help when the label turns on a fact the row leaves out; the rows every arm missed are
  class-boundary and severity calls (INFERRED from the investigation's reading of the missed rows). The table above finds no effect.
- **General lesson.** Before adding context to an evaluation, ask whether the label is a fact or a judgment. For a
  judgment, extra context from the same organisation's later records is a leak channel, and a time pin only closes
  it when the leaking text was written after the event. Filter by label vocabulary, not by date.

## Lean design that would be needed (described, not written)

A module `Fw.Oracle.Expand`, pure, with git as I/O only:

- **Allowlist, not deny-list.** `ExpandCfg` holds path prefixes and extensions (code only; no `docs/`, `research/`,
  `.claude/`, `.cache/`, `lean/Fw/Oracle/`). Theorem `expand_allowed`: every emitted header path passes `allowed`, and
  `decide` shows `docs/team/incidents/ledger.json` and `docs/team/work-graph.json` are refused.
- **Vocab-free.** A file holding any label word of the set (`Labels.mistakeClasses`, `lean/Fw/Oracle/Labels.lean:57`;
  `Labels.exactWords`, `:94`) or the row id is dropped whole. Theorem `expand_vocabFree`: no output line holds a
  vocabulary word.
- **Escaped-byte cap against `capState`.** `capState` keeps the tail of each field and gives later fields what is
  left (`lean/Fw/Oracle/Redact.lean:303-307@7e676da5`, CONFIRMED), so an over-budget files field would lose its head
  with no notice. The expansion caps itself in JSON-escaped bytes (the body is escaped, `bodyText`,
  `lean/Fw/Oracle/Body.lean:38@7e676da5`), and a new `capState_of_le` (`stateBytes S ≤ b → capState b S = S`) shows
  nothing is cut.
- **No-op replay.** Theorem `expand_noop`: a row with no file kept gets a byte-identical body, so it replays from the
  answer log with 0 sends.
- **Determinism.** Theorem `expand_local`: two blob maps that agree on the row's planned paths give the same output;
  the TS glue records the commit and blob id per path.

## The D1-only ablation and its decision rule (designed, not run)

- Rows: D1 rows that keep at least one allowlisted, vocab-free file at the per-row pin: 38 (MEASURED by the scan,
  `optionA`, prefixes `apps/ packages/ scripts/ lean/Fw/` minus `lean/Fw/Oracle/`, extensions `.lean .ts .tsx .mjs
  .js .sh .yaml`).
- Arms: Jev plus isolated Haiku and Sonnet calls on the identical expanded state, against the clean baseline.
- Rule, paired per row: count flips into and out of correct. Adopt only if every arm gains at least 4 net rows, no
  gain is on a row where a dropped file held a vocabulary word, and a hand read traces each gain to a fact the row
  lacks rather than fix-describing text. Otherwise record it as a negative result.

**Sends.** `dailyCap` is 200 per UTC day (`lean/Fw/Oracle/Send.lean:9@7e676da5`, CONFIRMED). A pass that changes only
rows with a kept file needs 94 sends (38 D1, 49 D2 at `c31e0848`, 7 D2 rows Jev never answered); a pass that changes
every body needs 206 (MEASURED, scan). The investigation estimated 108 with a narrower allowlist; the count moves with
the allowlist.

## Corrections to the investigation

| Claim in the investigation | Scan |
|---|---|
| 108 sends for the changed-rows pass | 94 (allowlist above) |
| Gap within about 4 points | Within 5.9 points once the clean arms are added |
| D2 median row about 100 KB | 95.5 KiB raw, 97.7 KiB escaped |
| Pinning before the incident removes most leaks | It keeps 2 of the 3 own-class-id leaks |

## Limits

- The ablation is designed, not run; `Fw.Oracle.Expand` is described, not written (accepted limits).
- Every count depends on the path regex above. A broader regex (bare file names, `:N` suffixes) moves the row
  counts by a few rows.
- D2 files are read at `c31e0848`, not at each review's time; the reviewed branch may differ from main.
- The per-row pin uses committer dates (`git rev-list --before`), and the ledger's `at` is minute-precise.

## What this changes in the plan

- `research/notes/2026/10-2x-jev-replay.md`, section "Limits": add one line saying the Jev state holds only the row's
  own text by design, with this note as the reason; file context is closed as a negative result.
- Work graph (lead): add no `Fw.Oracle.Expand` task. Reopen it only if a new question has fact labels (for example
  "does this file still contain X"), and then start from the design and decision rule above.
