# lean-coverage handoff

**State.** The work is on the worktree branch, in the commit after main `2a3bc0d`.
- `lean/Fw/Gate/Coverage.lean`: spec, proofs and the repo `claims`; the golden writer sits under `Fw.Wire.Coverage.Golden`.
- `apps/runner/src/coverage.ts`: `pnpm fw coverage`.
- Golden: `packages/contracts/golden/gate/coverage.jsonl`. Docs: `docs/team/tools/coverage.md`.
- Proved:
  - `coverage_lint_sound`
  - `lint_monotone`
  - `lint_nil_judged_sourced` (an empty lint means every judged gate item is sourced)
  - `lint_allProbes`
  - `tally_total`
  - `sourceOf_sound`
  - `covered_part_local`
- check.sh is green. The runner tests pass (19 files, 296 tests).

**First run** (integrate-ports tree, run 39067170911, chromium + playwright-webkit, 14 classes):
- 52346 probes: 126 golden, 42 exempt, 52178 uncovered.
- Per part (probes/covered):
  - engine.scroll 56/28; nav.hitTest 812/0; morph.mount 14/0; hero.countdown 1288/0; morph.countdown 1274/0; hero.exit 588/14
  - morph.columns 490/0; morph.tween 28/14; morph.panel 4004/0; nav 2996/0; nav.langMenu 1162/0; commission 5852/42
  - commission.typing 3038/28; overlays.drawer 3570/0; overlays.signup 3948/0; hero 3668/0; hero.orbit 1932/0; hero.deck 1092/0
  - hero.accent 168/0; hero.cue 770/0; people.card 1666/14; people.o 1596/0; people.carousel 2268/0; people.deck 3766/14
  - pain 2002/0; pain.notes 798/0; platform 1708/14; platform.stageBg 1064/0; platform.sweep 210/0; platform.glint 238/0
  - platform.entries 238/0; platform.marquee 42/0
- Failing: 152 items, 292 (item, class) cells. 280 cells (145 items) were uncovered: all of the nav, nav.hitTest, nav.langMenu, overlays.signup, platform.stageBg, people.o, hero.orbit and pain.notes failures, and most of commission and commission.typing.
- 12 cells (7 items) had a golden source and still failed:
  - commission runway height (both engines)
  - commission.typing --visual-scale (both engines)
  - commission.typing progress width (chromium)
  - people.card --future-shrink (webkit)
  - people.deck --profile-scale (webkit)

  The cause is wiring or inputs, not the formula.

**Conventions.**
- Claims live in Lean only, and the TS reads them from the golden's "claims" line.
- A claim with a file counts only with repo evidence: a generated file named from `apps/site/src`, or a golden file named by a test or by `goldenConformance('<id>'`.
- No blanket exemptions.
- The TS lint is a stand-in mirror, checked against the golden.

**Open items.**
- 12 of the 24 seeded claims hit no probe, because the driver-written inline props (e.g. pain.notes left/top, hero.orbit --orbit-enter-*) are not in the run header's `restated` list.
- fix-proofs adds claims part by part.

**To make it a land blocker:**
1. Commit the run header props per engine as a gate artifact (style probes need them).
2. Have `fw land` run `fw coverage --run <artifact>` after the gate.
3. Add the golden `--check` to `lake test` or check.sh.
4. Agree an allowlist ratchet (lint may only shrink; `lint_monotone` backs that claims never add failures).

**Read first:** docs/team/tools/coverage.md, then the module doc of Coverage.lean.
