# fw premises

Some Lean theorems assume a fact about the browser (for example "a write in rAF is seen by the frame's own layout-time observers").
Lean cannot prove those. The registry `lean/Fw/Ops/Premise.lean` lists each as a `Premise` (id, LaTeX statement, the theorems that
assume it, the engines it must hold on, a test id `prem.<id>`). `packages/premise-tests` holds one tiny static page
(`pages/<id>.html`) and one Playwright test (`src/tests.mjs`) per premise, run on Chromium and WebKit.

- Test kinds: `page` (default; the Playwright page above) or `lane`, for a premise a page cannot observe (for example
  WebKit's `internals.styleRecalcCount`, only in WebKitTestRunner). A lane premise's test id is the workflow file that
  asserts it (`wktr_scroll_timeline_restyle` → `.github/workflows/wktr-fixtures.yml`).
- `premiseLint_sound` (Lean): the lint is clean iff every page premise has a test, every lane premise's workflow file
  exists (`fw premises` lists `.github/workflows/`), and every test names a registered page premise.
- `flagged` (Lean): a page premise that does not hold on a required engine, failed or missing, flags the theorems that
  assume it. `flagged_eq_nil_iff`, `flagged_of_fail`, `flagged_of_missing` prove the rule; lane premises are never
  flagged from page results (`not_flagged_of_lane`), their workflow asserts them.
- Golden: `packages/contracts/golden/ops/premise.jsonl` (rows `premise`, `lint`, `flag`), written by
  `cd lean && lake env lean --run scripts/PremiseGolden.lean` (`--check` compares without writing).
- TS stand-in: `apps/runner/src/premises.ts` ports lint and flag; `apps/runner/test/premises.test.ts` checks both against the golden rows.

## Use

- `pnpm fw premises` static lint: the declared tests against the registry, and every non-`planned:` theorem name against `lean/Fw`.
- `pnpm fw premises --results <dir|file>... [--json]` reads the per-engine JSON of `node packages/premise-tests/src/run.mjs --engine
  chromium|playwright-webkit --out out` (a directory is searched recursively, so a downloaded artifact directory works).
  Prints `FINDING premise <id> does not hold (<engine>: <first error line>)` and the theorems that assume it.
- Acknowledged findings (`acks` in `Premise.lean`, task premise-ack): a finding recorded in `research/findings/ledger.json`
  is acknowledged as (premise, engine, observed class = first non-blank error line, ledger id, intermittent). It prints
  under `acknowledged findings` as `ACK ...` and does not fail. A new premise or engine, or a changed class, prints
  `FINDING ... (changed; acknowledged: ...)` and fails; a non-intermittent ack not observed prints `STALE ack` and
  fails (remove it). Rule: `red_iff_unacked`; an ack citing an unknown premise or ledger id is a `LINT ack` error.
- Exit codes: 0 clean, 3 a lint error, an unacknowledged finding, a stale ack or an unknown theorem name, 64 usage.
- A theorem name `planned:<task>` stands for a theorem that task will state; the existence check skips it. Rename it to the real
  name when the theorem lands, and add the premise to the theorem's docstring.
- CI: `.github/workflows/premise-tests.yml` (`gh workflow run premise-tests.yml --ref ci/<task>`), jobs `engine` (both engines,
  artifacts `premises-chromium`, `premises-webkit`) and `verdict` (red on a finding).
- Local: `node packages/premise-tests/src/run.mjs --engine webkit --out /tmp/x` is a debug run only; never report it as a result.

## Add a premise

1. Add it to `registry` in `Premise.lean` (the build proves unique ids); regenerate the golden.
2. Page premise: add `pages/<id>.html` and an entry in `src/tests.mjs` with `id: 'prem.<id>'`. Lane premise: set
   `kind := .lane` and `testId := ".github/workflows/<lane>.yml"` (the workflow must exist and assert the premise).
3. `pnpm --filter @fw/runner test` and `node --test` in `packages/premise-tests`.

## Acknowledge a finding

1. Record it in `research/findings/ledger.json` with an `id` (e.g. `premise.<premise id>`), the CI runs and the mechanism.
2. Add one `Ack` per failing engine to `acks` (class exactly the first non-blank error line; `intermittent := true` only
   when CI runs show it both failing and passing), add the id to `ackFindingIds`, regenerate the golden.
