# fw oracle

Typed answers from an outside model (TypeSafe's Jev) for decisions we cannot script, used **only as advice**.

- **What Lean proves:** what we DO with any answer and any failure (lean/Fw/Oracle). Every failure escalates,
  an answer is advised only at its own option's threshold (`decideOpt`): an option with no threshold escalates
  (`uncalibrated`; the no-match option never has one), a threshold outside (0, 1] escalates, a gate value below the
  option's threshold escalates, a Choice reply whose pick is not its most probable option is a schema failure, and the
  only effects are "print advice" or "ask a person": nothing lands, pushes, deletes, cancels or kills
  (`never_irreversible`).
- **What Lean does not prove:** that an answer is right. Accuracy is **MEASURED** on a labeled replay set by
  `fw oracle calibrate` (each threshold chosen on the choose part and certified on the holdout part) and reported on
  the holdout part by `fw oracle eval`. It holds only for questions like the ones in that set.

## Commands

| command | does |
|---|---|
| `pnpm fw oracle ask <question> --state <state.json> [--thresholds <table.json>] [--json]` | One state (an object of field to string or lines): `advise <option> (gate g)` or `escalate: <reason>`, exit 0 either way. No table, or no entry for the question, means uncalibrated: every answer escalates. |
| `pnpm fw oracle calibrate <question> --replay <rows.jsonl> [--limit n] [--resume] [--out <table.json>]` | Asks about every labeled row (at most 60 sends per run; logged replies replay for free). Ids come from Lean (`oracle.plan`: `id`, else `run-<runId>`; a null label is skipped; a `split` field is an error). Lean splits the rows by id (`heldOut`), chooses each option's least acceptable gate value on the choose part and keeps it only when the holdout part certifies it (`certify`). The entry (`thresholds`, `choose`, `holdout`, `used`, `dropped`, `rows`, `model`, `measuredOn`, `status: MEASURED`) is written to `--out` only when every labeled id has an answer (`mayWrite_sound`); a refused row, the run cap or `--limit` prints it and exits 2. `--resume` first checks (`oracle.plan`) that the rows missing from the answer log fit the run cap, else exits 2 and sends nothing. |
| `pnpm fw oracle eval <question> --replay <rows.jsonl> --thresholds <table.json>` | Asks about the holdout rows only and prints accuracy (hits / covered) and coverage (covered / rows) at the stored thresholds, MEASURED. Writes nothing. |
| `pnpm fw oracle send --set <d1\|d2> [--part calibrate\|holdout] [--limit n] [--dir <datasets dir>]` | The offline replay of a dataset of task jev-datasets (default dir: `.cache/jev` of the main checkout). Lean picks the rows and builds each state (`oracle.replay`); each send passes `oracle.preRun`: the daily cap, and per run at most 60 sends and 400 000 estimated input tokens (one token per body byte). It stops at the first refusal or a missing key and exits 2 until every picked row has an answer; run it again and logged answers replay. |
| `pnpm fw oracle score --set <d1\|d2> [--arm jev\|haiku\|sonnet] [--answers <arm.jsonl>] [--dir] [--out <file>]` | The numbers of one arm on the picked rows (`oracle.score`), written as `arms.<arm>` of `results/jev/<set>.json` (other arms kept). The Jev arm reads the answer log (the entry of each row's exact body); another arm reads `--answers`, one `{id, choice, probabilities?, inputTokens?, outputTokens?, ms?}` per line. Exit 2 while rows are missing. |
| `pnpm fw oracle arm-input --set <d1\|d2> --out <prompts.jsonl> [--dir]` | One `{id, prompt}` per picked row for another arm: a fixed preamble with the answer format, then the question, criteria and redacted state of the Jev body. |

Replay rows are `{id?, runId?, state, label}`, one per line. The replay sets and the per-question thresholds come
from the tasks jev-datasets and jev-replay; nothing is calibrated on landing, so every answer escalates.

## Questions (Fw.Oracle.Questions)

| question | options | fields | calibration constants (Lean, not overridable) |
|---|---|---|---|
| `ci-triage` | flake, infra, real; no-match unknown | job, step, log | q = 9/10, k = 5 |
| `incident-class` | the 13 mistake classes of the incident ledger; no-match none | title, symptom, cause | q = 9/10, k = 5 |
| `finding-severity` | blocker, fix-before-land, follow-up; no-match unclear | finding, where, task, unit, limits | q = 9/10, k = 5 |

- Calibration is per option, never pooled (`per_option_sound`): option o gets the least observed gate value t such
  that, among the choose-part rows advised as o at gate ≥ t, at least max(1, k) are labeled o and the precision is at
  least q. An option with fewer rows gets none (`calibrate_none_of_sparse`), and so does one the model never answers
  (`never_answered_none`).
- Held-out certification (`holdout_certified`, `wilsonOk_sound`): t is kept only when the holdout rows advised as o at
  gate ≥ t have at least max(1, k) hits h out of n advised and the one-sided Wilson score lower bound of h/n at
  z = 1.645 (95 %) is at least q. In exact arithmetic: q·n ≤ h and z²·n·q·(1 − q) ≤ (h − q·n)². At q = 9/10, 25 right
  of 25 passes and 24 of 24 does not; 100 of 104 passes; 15 of 16 (point precision 0.94) is refused. The bound assumes the
  holdout rows are independent draws of the questions we will ask. Holdout rows can remove a threshold but never move
  one (`choose_independent_of_holdout`).
- The split is by id, fixed in Lean and shared with the datasets (`Labels.heldOut`, `heldOut_canonical`): a row is
  held out when FNV-1a 32 of its id is 0 mod 4. A row's own `split` key is never read.
- At q = 9/10 and k = 5 an option can only be certified with at least 25 held-out rows of that label
  (`certify_needs_holdout`, `minHoldout_least`); the D2 sample takes 25 held-out and 5 choose-part rows per grade.
- The reviewer's round-5 probe on the holdout part (flake advised 16 times, 5 right; 5 infra; 25 real) certifies
  real only: a `#guard` in `Fw.Oracle.Calibrate`, a golden in `wire.jsonl` and a vitest case.
- Option order: Jev leans towards the first listed option, so a Choice's options are listed in an order shuffled by
  a seed (FNV-1a of the redacted state text): the same state gives the same bytes and the order is a permutation
  (`shuffle_perm`).

## Flow (all decisions are fwcore ops, `oracle.*`)

1. `oracle.request`: Lean redacts the state and builds the exact body (`bodyText`); the client hashes it (sha256) as
   the answer-log key.
2. `oracle.pre`, on the raw state:
   - a logged reply is replayed (no call);
   - a field the question does not declare is refused (`undeclared`);
   - an unredacted state or a body over 64 KiB is refused;
   - the daily cap of 200 sends (counted from the log) or the run cap of 60 sends refuses with `overBudget`;
     a replay run (`fw oracle send`) asks `oracle.preRun` instead, which also refuses past 400 000 estimated input
     tokens per run (`preRun_send`);
   - otherwise `send` with the body, and the client sends exactly that string (`body_from_lean`; it throws if the
     string differs from `oracle.request`'s).
3. Send: the key is read from the keychain only now, after `send`. No key is failure `noKey`, which escalates. Timeout
   30 s; a non-200 status is failure `http` (429 and 529 are not retried).
4. `oracle.decide`: Lean parses the reply (decimals read exactly), validates it, recomputes the gate value from the
   probabilities (the reported `confidence` is ignored) and applies the policy.
5. Answer log: one line per send in `.fw-console/oracle.jsonl` of the main checkout (gitignored; `FW_ORACLE_LOG`
   overrides). It holds the key hash, the day, the time taken and the reply (as `oracle.store` caps it, 64 KiB) or
   the failure; never the API key or the request body. Each call records a timing span (`tool: oracle`).

Which texts are public enough to send is the caller's choice for now; a provenance check per field is a follow-up.

## Replay ops (Fw.Wire.OracleReplay)

| op | request | reply |
|---|---|---|
| `oracle.replay` | `set` (`d1`, `d2`), `rows` [Dataset row], `part`? (`holdout` or `calibrate`), `limit`? | `set`, `question`, `file`, `sampled`, `labeled`, `unknownLabel`, `leaking`, `selected`, `rows` [{`id`, `label`, `part`, `state`}] |
| `oracle.preRun` | `name`, `names`?, `state`, `logged`?, `today`, `days` [string], `sent`, `spent` | `pre` replay/refuse/send, `failure`?, `bodyText` and `tokens` (on send) |
| `oracle.score` | `name`, `arm` (`jev`, `haiku`, `sonnet`), `replay` [{`id`, `label`}], `answers` [Arm answer] | `arm`, `question`, `labeled`, `missing`, `all` and `holdout` (rows, answered, right, accuracy, per option labeled, chosen, right, precision, recall), `confusion` {`columns`, `rows`}, `thresholds`, `choose`, `holdoutCert`, `minHoldout`, `inputTokens`, `outputTokens`, `dollars`, `msMean`, `msMedian`, `msMax` |

Dataset row: an object with `id`, `label` (an option name, or null) and the text keys of the set (`ReplaySet.fields`);
other keys are ignored, and the row's own `split` is never read (Lean splits by id). Arm answer: `{id, reply}` (the
Jev response text), `{id, failure}`, or `{id, choice, probabilities?}` (another arm), each with `inputTokens`?,
`outputTokens`? (for a Jev reply, read from its `usage` when absent) and `ms`?.

## Redaction (Fw.Oracle.Redact)

- Home paths in four forms (`/Users/`, `/home/`, `\Users\`, `-Users-`) become `~` (`no_home_forms`); the git user
  name and its words, the git e-mail and the login name become `<user>` in any letter case, bounded by
  non-alphanumerics; e-mail addresses, IPv4 addresses and key-shaped tokens are replaced.
- `redact_idem` and `no_home_path` hold for every input. Caps (`redacted_caps`, `send_caps`): 500 characters per state
  line, 32 KiB per state, 64 KiB per stored reply.
- Errors and logged replies are scrubbed of the key as well (`packages/oracle/src/scrub.ts`).

## The key (user step)

- In your own terminal: `security add-generic-password -s typesafe-api -a typesafe -w` (it prompts, so the key never
  enters shell history).
- Agents never read, print, export or store the key, and tests use a fake reader. The client reads it with
  `security find-generic-password -s typesafe-api -w` only after `oracle.pre` answers `send`.

## API facts

- CONFIRMED (https://docs.typesafe.ai/api.md, read 2026-10-18): `POST https://api.typesafe.ai/v1/systemone`,
  `Authorization: Bearer <key>`, body `{state, model, questions}`. Response `{model, answers, usage}`. Errors 400,
  401, 413, 415, 422, 429, 529.
- MEASURED 2026-10-22: Choice criteria as a list gives 422; as an object of option to description it gives 200 on
  `jev-1.13.0` (`answers.<name>.choice`, `confidence`, `probabilities`). A noul answer is a number.
- CONFIRMED (https://docs.typesafe.ai/models.md): pin a version (`jev-1.13.0`); aliases move.

## Files

- `lean/Fw/Oracle/*.lean`: the math; `lean/Fw/Oracle/Wire.lean`: the ops.
- `packages/oracle`: the client (`@fw/oracle`), with offline tests (`pnpm --filter ./packages/oracle test`).
- `apps/runner/src/oracle.ts`: the CLI; `apps/runner/src/oracle-score.ts`: the scorer and the arm prompts; tests
  `apps/runner/test/oracle.test.ts` (real fwcore, fake fetch, fake keychain).
- `lean/Fw/Oracle/Replay.lean` and `ReplayWire.lean`: the replay sets, the sample, the score; `results/jev/`: scores.
- `packages/contracts/golden/oracle/`: `wire.jsonl` and `fixtures.jsonl`, generated by Lean
  (`cd lean && lake env lean --run scripts/OracleGolden.lean`; `--check` runs in `lean/scripts/check.sh`).
