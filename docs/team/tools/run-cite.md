# run-cite: does a cited CI run carry the flag it is cited for?

`node scripts/run-cite.mjs` reads the flags each arm of a cited run carried from that run's own artifacts and asks
Lean whether each citation (run id, flag) matches.
- Spec and proofs: `lean/Fw/Gate/RunCite.lean` (fwcore op `gate.runCite`).
- Glue (download, parse, cache): `scripts/run-cite.mjs`.
- Golden vectors: `packages/contracts/golden/gate/run-cite.jsonl` (`lean/scripts/RunCiteGolden.lean`, checked by
  `lean/scripts/check.sh`), replayed through the built fwcore by `node --test scripts/run-cite.test.mjs`.

## Use

| Command | Checks | Exit |
|---|---|---|
| `node scripts/run-cite.mjs` | every run id in the evidence of each `research/findings/ledger.json` row that names a `flag` | 0 no mismatch, 1 a mismatch, 2 usage or failure |
| `--ledger <file>` | another findings ledger | |
| `--note <file>` (repeatable) | explicit `<run id> <part:variant>` citations in a note or handoff; replaces the default ledger unless `--ledger` is also given | |
| `--refresh <run id>` (repeatable) | drops that run from the cache and downloads it again | |
| `--json` | one JSON array: citation plus Lean verdict | |

Each line prints `match`, `mismatch ... carried: <flags>` (or `(no flag)` for an A/A run) or `unknown ... <why>`.

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

## Cache and GitHub

- Run facts are cached in `.cache/run-cite/runs.json` (gitignored; `FW_RUN_CITE_CACHE` overrides). A cached run costs
  no API call. The cache is saved after each download.
- Only `gh run download` is used, once per uncached run. Nothing polls. A failure other than "no valid artifacts" or
  "not found" (such as a 403) stops the run, is not retried and is not cached.
- An expired run stays `unknown` in the cache. A run read while still in progress may be cached with partial arms:
  `--refresh` it once it has finished.

## Limits

- Frame and leg artifacts are not read.
- A ledger row cites each run in its evidence for the row's flag. A row's prose can also name an A/A run or a run of a
  sibling flag; those citations come out as mismatches.
