# Labelled replay sets for the Jev trial (task jev-datasets)

Status: MEASURED 2026-10-22 (round 2 run: counts.json written 2026-10-22T00:57:38+07:00; ledger at commit ecdc0787) on the dev Mac from local history (this is a data extraction, not a performance result). No Jev call was made and no `gh api` call. The datasets stay local in `.cache/jev/<set>.jsonl` (gitignored); this note commits only counts.

The trial asks whether Jev can sort our own past work. Each set below is a list of items from our history with a label that was decided before Jev saw anything. A later task (calibration, jev-replay) sends the items to Jev and scores the answers against the labels.

## How a row gets its label

- CONFIRMED (lean/Fw/Oracle/Labels.lean, golden packages/contracts/golden/oracle/labels.jsonl, 189 lines): every label rule and the split are Lean, standalone and proved by case theorems. `scripts/jev-datasets.mjs` reads its constants and rule tables from the golden; `scripts/jev-datasets.test.mjs` replays every golden row (hash, d1, severity, fable, apply, phrase, all 64 CI fact combinations, all 30 alert combinations).
- Split: a row is held out when FNV-1a 32 of its id mod 4 is 0 (`heldOut`); the rest is calibration. Theorems `split_exclusive`, `split_disjoint`, `split_complete`. The split depends on the id only, and every id is stable: D1 by the ledger incident id, D2 by `<task>#<workflow id>#f<n>` (the workflow id is the journal's own, so pruning an old journal removes its rows and moves no other row; `round` is a field, not part of the id), D3 by `run-<run id>`, D4 by the step id. A row never moves between runs.
- Redaction: home paths, user names, emails, session ids, agent ids, LAN IPs, device ids and tokens become placeholders before a row is written; a row with a residual leak is withheld and counted. This is a TS stand-in (see the end).

## D1: incident mistake class

Source: `docs/team/incidents/ledger.json` at commit ecdc0787, 115 rows. Label = the ledger's `mistakeClass` (13 classes; `d1Label` returns none for an unknown class). Input to Jev: title, symptom, cause.

| label | rows |
| --- | ---: |
| c-env-assume | 15 |
| c-order-derived | 16 |
| c-handcopy | 2 |
| c-identity-heuristic | 8 |
| c-late-check | 14 |
| c-orphan-wait | 6 |
| c-policy-prose | 2 |
| c-proxy-verdict | 7 |
| c-quota | 7 |
| c-sample-validity | 5 |
| c-shared-no-lock | 10 |
| c-spec-gap | 14 |
| c-unearned-claim | 9 |
| total labelled | 115 |
| held out | 33 (all labelled) |

Limit: the labels are the lead's own classification at the time, the same people who wrote the symptom text. Two classes have 2 rows each (c-handcopy, c-policy-prose), so a per-class score on the held-out part is meaningless for them; score by class only over the pooled calibration plus held-out part, and report the held-out score for the whole set.

## D2: review-finding severity and unit membership

Source: the 393 `adv:` (build-review) results in the workflow journals, 2434 findings (15 more withheld by redaction). Input to Jev: the finding text and location, the task text, the pinned unit and the accepted limits parsed from the reviewer prompt. Label = the reviewer's grade (`severity`, Lean): an explicit "follow-up" tag wins; else the leading word (blocker, blocking, critical, high = blocker; fix-before-land, major = fix-before-land; follow-up, low, minor, nit = follow-up). In unit = blocker or fix-before-land. `medium`, `moderate`, `info`, `verified`, `note`, `process` and free text are unlabelled on purpose.

MEASURED why `medium` is unlabelled: of reviews with a medium finding, 44 were accepted and 208 refused; `high` and `major` sat in refused reviews 87 of 90 and 129 of 131 times. Medium does not predict the outcome, so it gets no grade rather than a guess.

| label | rows | exact words | legacy words |
| --- | ---: | ---: | ---: |
| blocker | 138 | 44 | 94 |
| fix-before-land | 171 | 42 | 129 |
| follow-up | 1200 | 112 | 1088 |
| unlabelled | 925 | | |
| total labelled | 1509 | | |

Exact words are the three grade names; legacy words are the older vocabulary mapped by the word table. Held out: 602 rows, 364 labelled (blocker 31, fix-before-land 43, follow-up 290). Unit membership: in unit 309 (blocker plus fix-before-land), out of unit 1200. 124 of the 393 reviewer prompts lack a "Pinned unit of decision" line, so the unit field is empty for those rows (flag `hasUnit`).

Regrades: a Fable advice (workflow `fable-refusals`) can lower a grade (a line saying "reviewer error" or "rule noise" dismisses the finding; "real, low value" makes it a follow-up). 46 Fable advices were found; a regrade applies only when the advice has exactly as many classification lines as the round has findings, and then by position. That held for 1 advice; 45 were skipped; 6 regrades exist, and the source (`fable:<workflow id>`) is in each affected row's `labelSource`. Not searched: the check agents of `fable-refusals` runs and lead regrades by task split; lead regrades by quoting a finding in a later prompt were tried and dropped because the text match was unreliable. Labels outside the 6 Fable regrades are the reviewer grades.

The journals are live, so the D2 counts are those of the last run (counts.json, 2026-10-22T00:57:38+07:00); a later review adds rows. Limits (accepted in the task): labels are reviewer grades, noisy by the reviewer's own variance; the legacy word mapping is a decision (the Lean table), not a fact; review rounds of tasks whose journals were already pruned are absent (jev-oracle's rounds are not in the journals).

## D3: CI failure cause

Source: `gh run list` (failures 2026-10-17 to 2026-10-21 and the latest 1000 successes, which reach back only to 2026-10-19) plus the tail of `gh run view --log-failed` for a sample of at most 150 failures (failures sorted by the FNV hash of the run id, first 150, so the sample is fixed). Label (Lean `ciCause`, decisive cases only): infra when the log has an infra phrase (SSL connect error, ECONNRESET, could not download and the like) and no code phrase; flake when the same sha passed in the same workflow; ours when the log has a code phrase (AssertionError, `premises: FAILED`, a TypeScript error and the like) and no infra phrase; everything else is unlabelled. A failure older than the success window (not `covered`) is labelled only when the log is infra-only: without the full success list neither flake nor ours can be decided (theorem `ciCause_uncovered`).

| label | rows | held out |
| --- | ---: | ---: |
| infra | 11 | 3 |
| ours | 9 | 2 |
| flake | 1 | 0 |
| unlabelled | 326 | 93 |
| total | 347 (labelled 21) | 98 (labelled 5) |

Why 326 are unlabelled (MEASURED, from the facts stored in each row): no log read for 200 failures (147 of the 150-log sample were read; the rest of the failures are outside the sample), of those 114 are also older than the success window; a log was read but shows no decisive phrase for 49 covered failures (mostly `Process completed with exit code 1.` with the cause earlier in the log) and for 77 failures older than the success window. The 1000-success list reaches back only to 2026-10-19, so `covered` is false for the failures of 10-17 and 10-18. Three `gh` log reads failed with "log not found" in the round-2 run; no 403 occurred, the run did not stop early (`stoppedBy` null). Failures read from the runs: 347 over 18 workflows (breakpoint-gate 124, lean 49, land 42 the largest).

This is a thin set: 21 labelled rows (5 held out) cannot support a per-cause score; it supports a "does Jev agree with decisive cases" check. A fuller D3 needs the failed-job log of every failure kept at the time (follow-up) or a longer success list.

## D4: fw watch alert triage

Source: the console event log. Label (Lean `alertTriage`): the alert's audience decides (user = ask user, lead = mitigate); with no audience, how the step ended decides (the user acted = ask user; the lead cancelled = ignore; resolved automatically = mitigate; cancelled by a script = mitigate only when the title says the lead restarts it).

| label | rows |
| --- | ---: |
| ask-user | 5 |
| ignore | 2 |
| mitigate | 3 |
| total | 10 (held out 0) |

GAP (named): only 10 alert steps exist in the console event log (19453 events read). `fw watch` alerts are not persisted and the lead's mitigations are in chat transcripts, which this task does not read. The set is too small to hold out any row (the split gives 0) or to score; it is a format check. A fuller D4 needs the watch to persist its alerts and the lead's action; follow-up.

## TS stand-ins and gaps

- Stand-in: the redaction (regexes plus the local user names read at run time), the journal and prompt parsing (unit, limits, task text), the Fable classification-line finder and the log tail reduction are TS, tested on synthetic fixtures only; they hold no label decision. A leak the regexes miss is possible: the files stay local.
- Gap: D3 is a bounded sample (150 logs) with the success list only back to 2026-10-19; D4 is tiny; D2 labels are noisy; calibration and Jev calls are other tasks.
- Rerun: `node scripts/jev-datasets.mjs --sets d1,d2,d3,d4 [--no-gh --logs-dir .cache/jev/d3-logs]` writes `.cache/jev/*.jsonl` and `counts.json`; without `--runs-dir` D3 reads the run lists itself with `gh run list`.
