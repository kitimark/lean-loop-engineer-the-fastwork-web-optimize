# phone-end-counts handoff

- Branch worktree-wf_67587a94-89a-1; worktree .claude/worktrees/wf_67587a94-89a-1; last commit: see `git log -1` (final commit after this file).
- CI: ci/phone-end-counts pushed at ab773fe95; all 20 workflows concluded skipped (lean-math 40173828875, chromium-counts 40173828867,
  webkit-sim 40173828789). No measurement CI is needed; the Simulator side comes from earlier runs named in the note.
- Verified: Lean lean/Fw/Device/PhoneArms.lean (no sorry), golden packages/contracts/golden/device/phone-arms.jsonl replayed by
  packages/measure-webkit/test/device-phone-arms.test.mjs; triggers.jsonl regenerated.
- Phone: 6 of 16 visits done (base, original, hero.exit:threaded, hero:scene-pause, morph.columns:idle-none, morph.countdown:hidden-pause).
  Visit 6 (morph.countdown:strip) failed once (proxy closed, code 1006), then the phone was "paired but not on USB" for 4+ min
  (scratchpad/pec/blocked.txt). One retry remains for visit 6. Raw data: .local/phone/2026-10-25/ (gitignored, state.json resumes).
- Resume (user reconnects and unlocks the phone): from packages/measure-webkit run `node src/device-cli.mjs arms-run --all --site
  ../../apps/site/dist/aot --dir ../../.local/phone/2026-10-25 --blocked ../../scratchpad/pec/blocked.txt` (about 2 h; waits the cool gap itself;
  nothing else device-cli on the Mac). Then `arms-reduce --dir ../../.local/phone/2026-10-25 --out ../../results/phone/2026-10-25-end-counts`
  and update research/notes/2026/10-25-phone-end-counts.md (tables, verdicts, comparison) and the 4 ledger notes.
- Results so far: results/phone/2026-10-25-end-counts/{summary.json,tables.md}; note research/notes/2026/10-25-phone-end-counts.md.
  Verdicts are provisional: the base has one visit, so its spread is within-visit only.
- Ledger: 4 notes (field lesson, task phone-end-counts) for hero.exit:threaded, hero:scene-pause, morph.columns:idle-none, hidden-pause.
- TS stand-ins: device-phone-arms.mjs plumbing (pagesOf, countValues, frameValues, reduceSession), device-phone-run.mjs (I/O).
- Write outside the task graph: lean/scripts/PhoneArmsGolden.lean (the golden script).
- Read first: lean/Fw/Device/PhoneArms.lean, packages/measure-webkit/src/device-phone-arms.mjs, device-phone-run.mjs.
