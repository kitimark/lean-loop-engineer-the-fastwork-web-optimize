# port-fonts-check

State: branch `worktree-wf_db541e00-01b-1`; CI branch `ci/port-fonts-check` (workflow visual-diff, head commit carries `[ci:visual-diff]`).
- Lean: `lean/Fw/Port/Fonts.lean` (check 5: leaf units as multisets, loaded faces as sets; theorems `fail_of_missing_leaf`,
  `fail_of_extra_leaf`, `fail_of_missing_face`, `fail_of_extra_face`, `pass_iff`, `pass_self`, `units_blank`). `Check.fonts` added in
  `Sections.lean` (page-wide, like assets and svg). Exclusion: family `Fastwork` (declared, never applied, never loaded).
- Golden: `packages/contracts/golden/port/fonts.jsonl` from `lean/scripts/PortGolden.lean` (regenerate, then `--check`).
- Twin and page reader (TS stand-in, reports only): `scripts/port/fonts.mjs`. Browser run: `packages/visual-diff/src/fonts.mjs`,
  CLI `node src/cli.mjs fonts --engine <e> --out DIR`. Test: `apps/site/test/port-fonts.test.mjs` (golden always; the probe-page test
  runs with `FW_PORT_FONTS_ENGINE`). CI job `port-fonts` (matrix engine) in `visual-diff.yml`; the built-page step is advisory.
- Visual diff: default `--assets none` (port as built); `inject` is a named diagnostic (workflow input `assets`), forced font-family
  only there. `tolerances.json` unchanged (no evidence yet). Docs: `docs/team/tools/visual-diff.md`.
- Reads declared in `apps/runner/src/land.ts` (apps/site, packages/visual-diff). No write to work-graph.json.
Verified locally (not a result): golden replay; one probe-page run in Chrome: good pair passes, `pain.notes`-fallback pair fails.
Unit of decision: per text leaf (section, normalised text, family, weight, style) plus the loaded (family, weight, style) set.
Accepted limits: WebKit font rendering beyond family/weight/style; Fastwork excluded; overlay-only DOM that is absent at load is not read;
the page sweeps by scrolling once before reading.
Open: CI results (run ids in the report); which probes change verdict under `none`; then decide per failing probe whether it is a port
gap (fix in a gap lane) or a tolerance (only with evidence). Read first: `lean/Fw/Port/Fonts.lean`, then `scripts/port/fonts.mjs`.
