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
CI (workflow visual-diff, branch ci/port-fonts-check): assets=none runs 39245919162 (older reader), 39248286394 (head), 39248398577
(dispatch); assets=inject baseline 39245980604. Per-run jobs green; the probe-page test and golden replay pass on both engines. The
built-page `fonts` step fails at all 8 probes on both engines (advisory): same 40 missing, 40 extra leaves, faces equal. Real gaps:
buttons draw Arial (-webkit-standard in WebKit) not Google Sans (hero Join waitlist, hero.cue, morph.panel, people.deck items);
hero.countdown and morph.countdown digits and a morph.panel text draw system-ui; `people.o` text is owned by people.card in the port.
Port job report (built site, advisory): assets pass, svg fails (2 missing, 1 extra); the unit tests of checks 1-4 pass.
Verdicts under none vs inject, 3 none runs: 433 of 496 cells hold one verdict in all three (254 U, 79 P, 77 F); ~25 cells flip between
runs, so tolerances.json is unchanged. Inject was worse (0 P chromium) as its forced font-family hits every element.
Open: fix the button/countdown font inheritance in a gap lane, then rerun; decide the `people.o` owner. Read first:
`lean/Fw/Port/Fonts.lean`, then `scripts/port/fonts.mjs`.
