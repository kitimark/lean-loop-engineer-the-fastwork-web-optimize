# @fw/gate-breakpoints

Breakpoint parity gate (PLAN 6.6, M2): the original (read-only `snapshot/site`, served locally) against the rewrite
(`apps/site/dist/aot`, default prerendered config), per probe of the Lean matrix (`apps/site/src/breakpoints.gen.json`,
124 loads per engine), in Chromium (Mac Chrome through puppeteer-core) and Playwright WebKit. Handoff and results:
`docs/team/handoffs/gate-breakpoints.md`.

```sh
pnpm --filter @fw/site build                         # the rewrite, once (needs lake for the byte check)
cd packages/gate-breakpoints
node src/cli.mjs run --engine both --out out/run-a   # raw JSON per engine: out/run-a/<engine>.json (about 10 min each)
node src/cli.mjs summary --out out/run-a             # summary.json + summary.md from the raw files
node --test "test/*.test.mjs"                        # the pure rule and the data checks, no browser
```

Options of `run`: `--engine chromium|playwright-webkit|both`, `--concurrency N` (default 4), `--probes id-or-block,...`,
`--sweeps id,...|none`, `--parts id,...` (pilot part ids of `src/anchors.json`: engine.scroll, nav.hitTest,
hero.countdown, hero.exit; default all). `--parts` collects and judges only those parts; the run header and the summary
then name the parts covered and skipped (a default run is byte-identical to before the flag). It does not cut loads:
every probe applies to every part, so combine it with `--probes`/`--sweeps` to shorten a run. `summary --parts` narrows
the verdict further, to parts the run collected. In CI: the `parts` input of `breakpoint-gate` (empty = all). Env: `CHROME_PATH`, `FW_SNAPSHOT_SITE`, `FW_SITE_DIST`.

| File | Role |
|---|---|
| `src/verdict.mjs` | **all decisions**, pure (the list for the Lean spec) |
| `src/anchors.json` | per part: elements compared (original selector, rewrite selector), box dimensions, skipped properties, each with the reason |
| `src/page.mjs` | code that runs in the page (pin clock, wait, collect raw facts) |
| `src/engines.mjs` | env emulation per engine (the header comment says how, and what is not reachable) |
| `src/run.mjs`, `src/spec.mjs`, `src/serve.mjs` | runner, probes and sweeps from the gen file, read-only static servers |
| `src/summary.mjs` | groups the raw files with `verdict.mjs` into the table |
| `src/gaps/` | the `gaps` lane (`node src/cli.mjs gaps collect|summary|run|device-serve|device-judge`): the 8 cells the default run cannot reach, collected and judged on CI (`.github/workflows/gate-gaps.yml`); see `src/gaps/README.md`, phone session `src/gaps/DEVICE.md`; results in `results/gaps/` (from CI artifacts only) |

The run files hold only raw facts and are byte-deterministic (no timestamps or durations).
