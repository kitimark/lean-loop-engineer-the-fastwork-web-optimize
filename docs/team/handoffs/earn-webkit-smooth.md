# earn-webkit-smooth handoff
Branch: worktree-wf_bbd9b85f-6e4-1 (CI branch ci/earn-webkit-smooth). Worktree: .claude/worktrees/wf_bbd9b85f-6e4-1. Last sha: `git log -1`.
CI runs (3 of 3 pushes used): 40100235090 trajectory-probe FAILED (flag arm opened '/' without its search; fixed), 40100235131 lean failed (footprint-diff stale; fixed);
push 2: trajectory-probe 40100783726 success, breakpoint-gate 40100783656 success (default page), lean 40100783678 success;
push 3 (main merged): trajectory-probe 40102193302 success, lean 40102193331 success. Data: artifacts transitions-apple-<width> of the two trajectory-probe runs (30 days); the reduced table is in the note (results/ is outside the task's writes).

## Verified
Lean `Fw.Parts.NavEarnWebkit` (theorems in the note) and `lean/scripts/check.sh` green; golden nav.earn.webkit.jsonl replayed by
apps/site/src/parts/nav/earn.webkit.golden.test.ts; site tests, gate-breakpoints tests, ci-paths --check, part-footprint --check.
MEASURED on macOS CI (2 valid runs): WebKit and Safari with `nav:earn-logical` ease the padding (largest step 1.5-5.5 px, settles ~520 ms) where the faithful rule snaps 24 px (16 px narrow); Chromium unchanged.

## Open
- Breakpoint gate with the variant needs a dispatch with `fw` (lead): `gh workflow run breakpoint-gate.yml --ref ci/earn-webkit-smooth -f engines=chromium -f fw=nav:earn-logical`.
  A push cannot carry `fw`; the push run 40100783656 covers the default page only.
- The user's Safari and iPhone review (ledger row n=67 nav.earn.logicalPadding, look-change, pending). iPhone inferred from shared WebKit source.
- Two valid macOS runs, not three (one push lost to a harness bug).

## Conventions
Variant = class `is-earn-logical` set once at render; the two rules sit last in nav.module.css; the gate's transition table (lean/Fw/Gate/Trajectory.lean `rules`,
reduce.mjs RULES, golden gate/trajectory.jsonl) must list every transition rule of that file, with its line. After touching nav.module.css or parts: part-footprint --write,
then `lake env lean --run scripts/ContractsGolden.lean --diff` / `--rows` outputs into footprint-diff.gen.json / FootprintRows.lean, TrajectoryGolden after a lake build.
Transitions lane: commit message `[ci:trajectory-probe] [frames:<part:variant>] [transitions:earn]` + `[trajectory engines=playwright-webkit widths=390,1280]`; the flag arm is `flag`.
Read first: research/notes/2026/10-2x-earn-webkit-smooth.md.
