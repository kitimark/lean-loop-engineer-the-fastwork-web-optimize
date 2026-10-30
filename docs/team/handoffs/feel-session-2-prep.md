branch: worktree-wf_8092b7fe-92d-1
worktree: .claude/worktrees/wf_8092b7fe-92d-1 (under the main checkout)
last commit: 166d5943d (merge of main over e9fa80213 work + land.ts reads), this handoff after it
CI runs: none (the task needs no CI; nothing touches the phone)
verified locally: lake build, `FeelGolden --check`, measure-webkit feel tests (32) + device-feel-plan tests (13), 7 arms built
  from the generated build command and every `?fw=` resolved in dist/aot/configs.json.
also verified: check.sh green via slot, measure-webkit tests 1050 pass, ci-paths 56 pass, runner land-inputs 73 pass, plan lint 0 errors.
open: the task's writes lack `apps/runner/src/land.ts` (two reads added to the measure-webkit row) and
  `lean/Fw/Device/FeelGolden.lean` (the glob names lean/scripts/Feel*Golden.lean); the dry land without --allow ends
  `VERDICT scope`, with both allowed it ends `VERDICT dry feel-session-2-prep`. The lead adds both paths to the writes.

State
- Arm flags: `Fw.Device.Feel.sameArmsOf` reads the generated preset golden `packages/contracts/golden/preset/v2-proved.json`
  (via `Fw.Preset.Gen.presetKeys`); `feel.jsonl` has a `preset` row and `device-feel.mjs` throws when it disagrees with the file.
- Arms: base, v2-proved, v2-proved-2flag (blind, shown twice, never twice in a row) + L1..L4 labelled
  (`nav:earn-logical`, `platform.glint:compositor`, `morph.end.nobounce:on`, `morph.stage:on`). 10 visits, about 21 min (estimate).
- `scripts/feel-session.sh [--seed N] [--date D] [--build] [--plan]`: plan, read-only probe (exit 3 + ask), background
  `feel start` (pin Serious, capture, fresh dir `.local/phone/<date>-feel2`), never `feel next`. Tested against a stub CLI.
- New TS: `packages/measure-webkit/src/device-feel-plan.mjs` (TS stand-in of Lean probeOf/failOf/estimateS, golden-checked).
- Conflicts: none of the four look flags conflicts with the v2-proved flags; `platform:faded-pause` conflicts are in
  `apps/site/src/parts/platform/part.json:48`. The kit composes each look arm alone against base, not on v2-proved.

Conventions
- Regenerate the golden from Lean (`FeelGolden`), never hand-edit `feel.jsonl`. `FeelGolden.lean` is outside the task's writes glob.
- Web Inspector cannot be probed read-only before the proxy runs; the script classifies a failed start (`failOf`) and prints the ask.

Read first: research/notes/2026/10-30-feel-session-2-prep.md, then lean/Fw/Device/Feel.lean (session-start section).
