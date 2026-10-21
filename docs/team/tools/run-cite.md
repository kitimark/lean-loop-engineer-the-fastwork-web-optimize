# run-cite: does a cited CI run carry the flag it is cited for?

`node scripts/run-cite.mjs` reads the flags each arm of a cited run carried from that run's own artifacts and asks
Lean whether each citation (run id, flag) matches.
- Spec and proofs: `lean/Fw/Gate/RunCite.lean` (fwcore op `gate.runCite`).
- Glue (download, parse, cache): `scripts/run-cite.mjs`.
- Golden vectors: `packages/contracts/golden/gate/run-cite.jsonl` (`lean/scripts/RunCiteGolden.lean`, checked by
  `lean/scripts/check.sh`), replayed through the built fwcore by `node --test scripts/run-cite.test.mjs` (part of the
  root `pnpm test`); one request line in `lean/golden/wire-requests.txt` (`rc-1`).

## Use

| Command | Checks | Exit |
|---|---|---|
| `node scripts/run-cite.mjs` | every run id in the `evidence` of each `research/findings/ledger.json` row, in the role its marker gives; in a row with no `flag`, only marked run ids | 0 no mismatch, 1 a mismatch, 2 usage or failure |
| `--ledger <file>` | another findings ledger | |
| `--note <file>` (repeatable) | explicit `<run id> <part:variant>` citations in a note or handoff; replaces the default ledger unless `--ledger` is also given | |
| `--refresh <run id>` (repeatable) | drops that run from the cache and downloads it again | |
| `--json` | one JSON object: `verdicts` (citation plus Lean verdict) and `unflagged` | |

Each line prints `match`, `mismatch ... carried: <flags>` (`(no flag)` when the run carried none) or
`unknown ... <why>`. A line `unflagged <row>` names a row with no `flag` whose evidence has unmarked run ids; those
ids are not checked and do not change the exit code.

## Ledger rows and role markers

Fields read per row: `id` (else `n`), `flag` (a string, else the row has no flag) and `evidence` (a string, else the
row is skipped). No other field is read: run ids in `visual`, `mechanism`, `next` and the rest go unchecked, and the
`flags` array does not set the row's flag. Lean (`mentions`, `citesOf`, `rowCites`) reads the evidence:
- A run id is a word of 10 to 12 digits.
- The text right after it sets its role: ` (A/A)` (one space) marks a run that carried no flag (an A/A run or a
  default baseline run), ` (<part:variant>)` a run of that flag. Anything else (`(flag)`,
  `(hero.exit:faithful A/A)`, `A/A 3946...`, `3946...(A/A)`) leaves the row's flag.
- A run marked anywhere in the row gets one citation per marker and none for the row's flag. An unmarked run is cited
  for the row's flag.
- A row with no `flag` cites only its marked runs, with flag `""` (`row_no_flag`), which the A/A and sibling rules
  ignore (`aa_ignores_flag`, `sibling_ignores_flag`); each other run id is listed under `unflagged`
  (`row_no_flag_covers`). To check such a row, mark every run id in it, the row's
  own runs with ` (<part:variant>)`. A `flag` field is not the way: `Fw.Preset.Gen` reads `flag`, and a new one changes
  `packages/contracts/golden/preset/v2-proved.decisions.jsonl`.

A marker applies to the one run id it follows: in `a and b (A/A)` only `b` is marked.

## Where each artifact records an arm's flags

| Artifact | File | Field | Written at |
|---|---|---|---|
| `trajectory-{chromium,playwright-webkit,apple}` | `raw-<engine>.json` | `runs[].search` (original, base, candidate) | `packages/gate-breakpoints/src/trajectory/run.mjs:120` |
| `chromium-counts-<target>-<n>` | `counts.json` | `meta.search` | `packages/measure-chromium/src/run.mjs:331` |
| `gate-<engine>-j0` | `<engine>.json` | `header.flags.search` | `packages/gate-breakpoints/src/run.mjs:412` |
| `webkit-sim-<vm>` | `<vm>-session-N.json` | `site.search` (`site: null` is the original) | `packages/measure-webkit/src/cli.mjs:130` |

Only job `j0` of a gate run is downloaded: the gate artifacts are 27-57 MB per job, and every job gets the same
`FW_SEARCH` (`.github/workflows/breakpoint-gate.yml:258`, `:271`).

## Verdict (Lean)

- `unknown`: no artifact (expired, not finished, not a gate run), run not found, or no arm.
- `match`: some arm's `fw` entry is the flag, or the flag plus an `@impl` suffix.
- `mismatch`: no arm carries it and no arm uses a `preset`; the reply lists every `fw` entry the run carried.
- `unknown`: no arm carries it but an arm uses a `preset`, whose members the artifacts do not record.

These rules judge the row's flag, and a sibling marker's flag in its place (`judge_row`, `judge_sibling`). An A/A
marker has its own rule (`aaVerdict`, `aa_match_iff`, `aa_mismatch_iff`):
- `match`: there is an arm, and no arm has a `fw` entry or a `preset`.
- `mismatch`: some arm has one; the reply lists every `fw` entry and `preset=<name>`.
- `unknown`: no artifact or no arm, as above.

## Cache and GitHub

- Run facts are cached in `.cache/run-cite/runs.json` (gitignored; `FW_RUN_CITE_CACHE` overrides). A cached run costs
  no API call. The cache is saved after each download.
- Only `gh run download` is used, once per uncached run. Nothing polls. A failure other than "no valid artifacts" or
  "not found" (such as a 403) stops the run, is not retried and is not cached.
- An expired run stays `unknown` in the cache. A run read while still in progress may be cached with partial arms:
  `--refresh` it once it has finished.

## Limits

- Frame and leg artifacts are not read.
- An unmarked A/A or sibling run in a row's prose is cited for the row's flag and comes out as a mismatch: add its
  marker.
- Note citations (`--note`) are parsed in JS (`noteCites`, a TS stand-in) and carry no role.
- Run ids outside `evidence` (in `visual`, `mechanism`, `next`, ...) are not checked. On 2026-10-21, 28 of the 72
  rows had a 10 to 12 digit word outside `evidence`.
- `gh run download` runs with its working directory at the repo top, so `gh` resolves this repo from any caller cwd.
