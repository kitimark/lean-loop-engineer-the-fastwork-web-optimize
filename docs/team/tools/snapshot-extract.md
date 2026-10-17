# snapshot-extract

`packages/snapshot-extract`: the original's computed styles, extracted by a browser, as the data Lean consumes. It exists
because values copied by hand from the snapshot drift or get transcribed wrong (the missing body colour and font rule of
the port were of that kind); an extractor writes them down, Lean then reads them.

## What it does

- Serves the unmodified `snapshot/site` (and our prerendered port, `apps/site/dist/aot`) with the breakpoint gate's own
  server, engines, page waits and probe definitions (`packages/gate-breakpoints`, imported read only), in Chromium and
  Playwright WebKit.
- Environments: the whole-pixel probes of the Lean matrix (`apps/site/src/breakpoints.gen.json`), one load per distinct
  (width, device width, hover, pointer, reduced motion, scheme): 116 per arm and engine.
- Elements: the first match of every (part, role) of `packages/gate-breakpoints/src/anchors.json` (the `orig` selector for the
  original, the `rewrite` selector for the port); the count of matches is recorded too.
- Properties: the base set (colour, font, line height, display, ...) plus every longhand declared by any rule that matches the
  original's element. The port is read on exactly the original's list.
- Per (part, role, property, environment): the computed value, and its declared source: `rule` (winning rule: sheet file,
  rule ordinal, `media`, `imp`), `inline`, `inherited` (nearest declaring ancestor tag and how many levels up) or `initial`.
  The winner uses an approximate cascade (specificity, order, `!important`; `@layer` ignored). A value changed by a running
  animation is written `@animated` (not data).

## Pipeline (`.github/workflows/snapshot-extract.yml`, free runners)

1. `site` builds the port once. 2. `extract` runs 3 independent jobs per engine (`extract-<engine>-<rep>` artifacts).
3. `report` merges the three runs of an engine: a row (a cell or a role count) is kept only when all three agree (empirical
premise `snapshot-extract.determinism`, Lean `Fw.Site.Reference.reference_deterministic`), the rest goes to
`*-unstable-<engine>.json`. It then compares the port with the reference and uploads the artifact `snapshot-reference`.

Files of the artifact: `reference-<engine>.jsonl` (the dataset, schema `fw.snapshot-extract.reference/1`),
`reference-full-<engine>.jsonl` (the same with selector text, for diagnosis), `port-*.jsonl`, `*-unstable-*.json`,
`fonts-<engine>.json`, `report.md`, `report.json`. Engines: `chromium` (Chrome Headless Shell 156.0.8078.4) and `webkit`
(Playwright WebKit on Linux, not Safari).

## Dataset format

One JSON object per line. Line 1: header (`engine`, `browser`, `snapshot`, `envs` with widths and media features, `runs`).
Then, per role, `{"t":"role","part","role","n":[{"x":count,"e":...}]}` and, per property,
`{"t":"cell","part","role","prop","v":[{"x":value,"e":...}],"s":[{"x":source,"e":...}]}`. `e` is `"all"` or the list of
environment indices (positions in the header's `envs`) that share `x`; `x` is `null` when the element is absent.

What is committed (`packages/contracts/golden/site/reference-*.jsonl`) holds numbers and keywords per property only: no
selectors, `url(...)` reduced to a file name or a hash, values over 300 characters reduced to length and hash. It is
observed values (the snapshot itself is published with Fastwork's approval), not Fastwork code.

## Commands

    pnpm --filter @fw/snapshot-extract test                         # unit tests of the data shaping and the report
    node src/cli.mjs extract --engine chromium|playwright-webkit --out out   # one run (CI; locally only a short debug run)
    node src/cli.mjs merge --engine E --in r1.json,r2.json,r3.json --out dataset
    node src/cli.mjs report --in dataset --out dataset              # report.md / report.json

`FW_EXTRACT_NO_PORT=1` skips the port arm (debug, no site build needed).

## Lean

`lean/Fw/Site/Reference.lean`: the data model, the parser of the JSONL (embedded with `include_str`), `inheritedFromBody`,
`Agree`, `classify`/`crossEngine_split` (five classes of a key across the engines), `split_partition`, `reference_deterministic`
(premise-backed), `stableCells_same`. TS stand-ins: the report's categories (`src/report.mjs`) and the cascade winner in
the page; both are checked only by their unit tests and by the run, not by golden vectors from Lean yet.

For fix-proofs and lean-coverage: the dataset is the `generated` source for the original's site CSS; read the cell of a
(part, role, property) with `Dataset.find?` on `referenceChromium` / `referenceWebkit`.
