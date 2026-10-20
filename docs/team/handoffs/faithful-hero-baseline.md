# Handoff: faithful-hero-baseline (round 2)

State: branch worktree-wf_fe20256e-e16-2 (main merged), CI branches ci/faithful-hero-baseline (code 412d16a) and
ci/faithful-hero-baseline-nosmooth (same, reset.css `scroll-behavior` block removed; CI only, not merged). Result, tables,
row F: research/notes/2026/10-21-faithful-hero-baseline.md. Tool doc: docs/team/tools/trajectory-probe.md.

Port defects fixed (apps/site against the snapshot):
- `html{scroll-behavior:smooth}` (+ reduced-motion `auto`) missing: src/styles/reset.css, test src/scroll-behavior.test.ts.
- `is-on-dark` derived only on scroll; the original also derives it on every morph change: src/parts/nav.hitTest/index.tsx
  (MutationObserver, docblock says its write is outside the registerScroll order), test morph.component.test.ts.
  Footprint regenerated (`node apps/site/scripts/part-footprint.mjs --write`); `lake build Fw.Parts.Contract` holds.
- Harness scrolls that must jump say `behavior: 'instant'` (PartStage.tsx, census.mjs, e2e-preview suite.mjs); probe
  `heroPath` (kit.mjs) re-issues an instant scroll (max 2) when a rest stops short.

Verified (MEASURED, CI): Lean `outcome` (storedOf + outcome, no admission write) is pass for Chromium hero and morph and
macOS WebKit hero in runs 39453764374 and 39457063232 (both success); Linux WebKit morph "no verdict: coverage" (accepted).
Row F (earn max-width/opacity at close@0/close-hold@0): CSS values equal; in-flight sampling, fails in candidate and faithful
arm in all 3 runs incl. A/A 39409003529. Row C: no CSS rule ties earn to `.is-on-dark`; follow-up.
Two effects: run 39461484608 (success; kit retry, no port scroll-behavior): macOS WebKit 0 new / 0 both / 4000 ok, so A is cleared
by the instrument; the port fix is shown by scroll-behavior.test.ts only. Reverse variant (port fix, no retry) not run.

Outside-graph writes: none (graph widened at 2ff42b63; kit.mjs, FootprintData.lean, footprint.gen.json are listed there).
Not run locally: sim. Runs used: 3 of 4.

Open: (1) clock-aligned read for close@0 / close-hold@0 (reducer + Lean); (2) row C cause; (3) reverse variant if
the retry should be removed; (4) Linux WebKit push cells; (5) the recorder was not run (no stored admission line).
Dispatch: `pnpm -s fw run --trajectory --ref ci/<branch> --fw hero.exit:faithful --engines both`.
Read first: the research note, then kit.mjs `heroPath`.
