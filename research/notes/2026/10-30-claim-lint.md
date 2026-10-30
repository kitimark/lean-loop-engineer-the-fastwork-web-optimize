# Claim lint: status tags need their kind of source, numbers that name an artifact key equal it

## Answer

- `node packages/plan-lint/src/cli.ts [<note.md>...]` prints one `WARN path:line code detail` line per finding and a
  summary line, and always exits 0. With no files it reads every tracked `research/notes/**/*.md` and
  `docs/team/handoffs/*.md`.
- `fw land`, dry and real, runs it over the notes and handoffs changed in main...branch (`landLint` in
  `packages/plan-lint/src/land-lint.ts`, called from `apps/runner/src/land.ts`) and prints its lines. The land verdict and
  exit code do not change; a lint that cannot run prints `claims lint: not run (...)`.
- Every rule is Lean (`lean/Fw/Plan/Claims.lean`). The TypeScript in `packages/plan-lint/src/claims-lint.ts` reads the
  note, the artifacts it names and `git ls-files`, and asks `lean/scripts/ClaimsGolden.lean --serve` for the findings.
- At aed97053b the lint finds 1432 warnings in 354 of 1177 files (table below). No existing note fails: the lint is a
  warning.
- Refused fragments in the golden (`packages/contracts/golden/plan/claims.jsonl`, each row names the commit that holds
  the fragment verbatim). The lint catches 2 of the 7:
  - caught: end-floor-writes r2 "70 to 83" over the listed 83, 71, 81 (`rangeEnds`, 42c52ed52); watch-memory r2 "All
    numbers below are MEASURED local harness numbers", with no run id and no committed path (`measuredNoSource`,
    e64ac7211).
  - unchecked, no artifact key: nav-cta-webkit-match r2 "within 10 px of its settled floor at 1280", true for exit only
    (d547444e1); watch-memory r2 "1.7 x the after-arm peak", 512 / 289 with no operands written, and "sawtooth 150 to
    860 MB", KiB divided by 1000 (e64ac7211); end-floor-writes r2 "32 frames with one recalc, 16 with two, 0 with none"
    stated for the wrong rows, and the Lesson that generalized past j2 (42c52ed52, the Lesson in
    `research/findings/ledger.json`).
  - Rows named `variant` are built for the rule, not quoted: a wrong-row table cell, `512 / 289 = 1.7`, `152032/1000 =
    148`, a scratch sampler path, misquoted `verdict.txt` lines. The lint catches each of them.

## Rules

| Code | Rule | Lean |
|---|---|---|
| `confirmedNoSource` | a `CONFIRMED` tag needs a path, sha, URL, run id or `Fw.` name in its scope | `claimOk`, `claim_ok_iff`, `confirmed_ok_iff` |
| `measuredNoSource` | a `MEASURED` tag needs a run id (9 or more digits) or a path that `git ls-files` lists | `measured_ok_iff` |
| `measuredScratch` | a sentence tagged `MEASURED` never cites a scratch or local path | `measured_scratch_refused` |
| `boundNoTheorem` | a tagged sentence that says bound, bounds or bounded names a theorem | `claim_ok_iff`, `inferred_ok_iff` |
| `keyMismatch` | a number after `file.json key` equals the key's value rounded half away from zero to the written places | `numOk`, `numOk_iff`, `roundQ_half`, `roundQ_exact` |
| `keyMissing` | the named key exists in the file | `lookup` |
| `rangeEnds` | `a to b` followed by a key reference and its comma list: `a` is the least listed value and `b` the greatest | `rangeOk`, `rangeOk_iff`, `rangeOk_nil` |
| `arithMismatch` | a written `a op b = c` (op one of `/ * × + -`) equals `a op b` rounded to the places of `c`, times 100 for a percent | `numOk` |
| `quoteMissing` | a quote right after a `.txt` path occurs in one line of that file, its `...` parts in order and at word edges | `quoteFindings` |
| `refUnread` | the file a key, caption or quote names resolves to one repo path and the lint could read it | `resolve` |

Scope of a status tag:

- A sentence draws cites from its paragraph or list item and from its section heading.
- A heading draws cites from its whole section.
- A table row draws cites from the prose block right above the table.
- A tag inside a code span is a mention, not a claim.
- A unit that carries all three tags is a legend and is skipped.

Key references take three forms:

- In a sentence: a `.json` path token followed by a key token, such as `summary.json`
  `chromiumVsWebkit['1280/entry/logical'].settledChanged` followed by a number. A bare file name resolves to the one
  path in the same note that ends with it.
- In a table caption: `under <template> in <file>: Header = key, ...`. Each `<column>` slot in the template takes the
  row's cell, and each named header's cell must equal its key.
- After a `.txt` path: a quoted line, with `...` for the parts left out.

A key segment `[x]` on an array picks the one element whose `id`, `name`, `arm` or `key` field equals `x`.

## Current warnings at aed97053b

| Code | Count |
|---|---|
| `measuredNoSource` | 973 |
| `confirmedNoSource` | 376 |
| `boundNoTheorem` | 67 |
| `measuredScratch` | 9 |
| `refUnread` | 6 |
| `keyMissing` | 1 |
| `rangeEnds`, `arithMismatch`, `keyMismatch`, `quoteMissing` | 0 |

The full list: `node packages/plan-lint/src/cli.ts`. Findings outside the two status codes with the largest counts:

- `research/notes/2026/10-2x-earn-gpu.md:307` `keyMissing`: `summary.json` resolves to
  `results/smoothness-webkit/summary.json`, which has no `zones` key.
- `refUnread`: `research/notes/2026/10-17-ci-measurement-feasibility.md:71` and `:103` (upstream files, not in this
  repo); `research/notes/2026/10-18-sweeps-speed.md:106`, `research/notes/2026/10-20-mount-scroll-tap.md:104`,
  `research/notes/2026/10-2x-sim-touch-reliable.md:172` and `research/notes/2026/10-2x-window-own-end.md:17` (a bare
  file name with no full path in the note).
- `measuredScratch`: `research/notes/2026/10-17-parallel-work-measure.md:3`, `10-17-team-review-fable.md:65`,
  `10-20-cache-relations.md:46`, `10-20-resource-audit.md:313`, `10-22-lag-coverage.md:99`,
  `10-25-gate-flag-deltas.md:14`, `10-2x-cc-fallback-why.md:17` and `:41`, `10-2x-jev-retrieval.md:14` (all under
  `research/notes/2026/`).

Most status warnings sit in notes written before the rule, often headings such as `## Result (MEASURED)` over a
section with no run id. The notes with the most warnings are `10-17-token-usage-facts.md` (31),
`10-18-engine-gaps.md` (26) and `10-18-engine-webkit-pipeline.md` (25).

## Accepted limits

- Warning only: the CLI exits 0 and `fw land` prints its lines without changing the verdict; no CI step runs it.
- A number that names no key is unchecked, such as "within 10 px of its settled floor at 1280" (nav-cta-webkit-match
  r2) or "sawtooth 150 to 860 MB" without a key reference (watch-memory r2).
- Formats beyond JSON keys and `.txt` lines are follow-ups (CSV, markdown tables in results, YAML).
- Prose claims without numbers are unchecked, such as the end-floor-writes r2 Lesson "silence the six listed writer sets
  and the floor stays", which the j2 qwrite `verdict.txt` line (cut 40 of 154) contradicts.
- A chained sum such as `1250 + 900 + 900 = 3050` and any arithmetic inside a code span are unchecked.
- The bound rule reads the words bound, bounds and bounded, so a timeout or a gate threshold called a bound also asks for
  a theorem name (most of the 67 `boundNoTheorem`).

## Follow-ups

- `fw claims lint <files>` needs a dispatch line in `apps/runner/src/fw-main.ts` (outside this task's writes).
- A fwcore op `plan.claims` needs a registration in `lean/Fw/Wire/Plan.lean`; the CLI then calls fwcore instead of
  `lake env lean --run`.
- A `packages/plan-lint/package.json` with a `test` script adds the test to land checks; that needs a
  `pnpm-lock.yaml` importer line (outside the writes).

## Speed

One local run over the 1177 default files took 34 s on this Mac, through the Lean interpreter. The 49 node tests take
under 1 s.
