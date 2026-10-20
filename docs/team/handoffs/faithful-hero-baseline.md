# Handoff: faithful-hero-baseline

State: branch worktree-wf_fe20256e-e16-2, CI branch ci/faithful-hero-baseline, measured code 412d16a1. Result and tables:
research/notes/2026/10-21-faithful-hero-baseline.md. Tool doc: docs/team/tools/trajectory-probe.md.

Port defects fixed (apps/site against the snapshot):
- `html{scroll-behavior:smooth}` (+ reduced-motion `auto`) was missing: src/styles/reset.css, test src/scroll-behavior.test.ts.
- `is-on-dark` was derived only on scroll; the original also derives it on every morph change (hit || morph > .2):
  src/parts/nav.hitTest/index.tsx, test morph.component.test.ts (red without the fix). Footprint regenerated with
  `node apps/site/scripts/part-footprint.mjs --write`; `lake build Fw.Parts.Contract` holds.
- Harness scrolls that must jump now say `behavior: 'instant'` (PartStage.tsx, scripts/census.mjs, e2e-preview suite.mjs);
  probe `heroPath` re-issues an instant scroll (max 2) when a rest stops short of its target.

Verified: macOS WebKit hero path, 2 runs (39453764374, 39457063232): 0 new, 0 both, 4000 ok (before: 54/54/114 both).
Chromium, same runs: no is-on-dark, logo.color or 390 earn.max-width unit left. Residual: coverage new (42, one width) in run
1, 2 content new (earn at 1280 close-hold@0) in run 2. They are A/A noise (cand = base config) from a transition sampled in
flight, so the literal "0 new on Chromium" is not met; stored-outcome rule passes (one width each, INFERRED).
Dispatch: `pnpm -s fw run --trajectory --ref ci/faithful-hero-baseline --fw hero.exit:faithful --engines both`.

Open: (1) a clock-aligned read for close@0 / close-hold@0 (reducer + Lean, not mine); (2) Linux WebKit push cells stay
"no verdict: coverage"; (3) the recorder (`Fw.Preset.Gen.record`) was not run, no stored admission line written.
Conventions: dispatch with the search in `--fw`, never a preset; download with an absolute `-D`; 2 of 4 runs used.
Read first: the research note, then kit.mjs `heroPath`.
