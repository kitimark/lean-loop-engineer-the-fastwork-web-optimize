# phone-end-counts handoff (round 2)

- Branch worktree-wf_67587a94-89a-1; worktree .claude/worktrees/wf_67587a94-89a-1; last commit: `git log -1`.
- CI: no new push in round 2 (no measurement CI needed). Round 1 push ci/phone-end-counts at ab773fe95: all 20 workflows skipped (lean-math 40173828875,
  chromium-counts 40173828867, webkit-sim 40173828789). Runs in flight: none.
- Phone: 15 of 16 visits done (base x3 at visits 0, 7, 15; 12 arms once). Lost: morph.countdown:strip (visit 6; usbReset then staleTab; lead facts).
  Raw files .local/phone/2026-10-25/ (gitignored). State.json visit 6 now carries faults [usbReset, staleTab] (lead's finding), so `arms-run` retries it once.
- Verified: Lean lean/Fw/Device/PhoneArms.lean (arm plan, verdict rule, new Fault/mayAttempt and TabPlan/tabPlan with one theorem per branch);
  golden packages/contracts/golden/device/phone-arms.jsonl (regenerate: `cd lean && lake build Fw.Device.PhoneArms && lake env lean --run
  scripts/PhoneArmsGolden.lean > ../packages/contracts/golden/device/phone-arms.jsonl`), replayed by test/device-phone-arms.test.mjs and
  test/device-faults.test.mjs. Merged main (r471); Trigger.lean row and triggers.jsonl regenerated (`lake test -- --write-ci-trigger-golden`).
- Reduced: results/phone/2026-10-25-end-counts/{summary.json,tables.md} (metrics now include paintArea; layer census and backing MB tables).
  Note research/notes/2026/10-25-phone-end-counts.md (answer first, per-arm table, CI comparison with run ids). Ledger: 12 notes (one per entry, task).
- Fixes: device.mjs resets one stale tab of our own origin to about:blank before the blank-tab check (Lean tabPlan); device-phone-run.mjs records a Fault per
  failed attempt and retries a harness-lost visit once more (Lean mayAttempt); doneIdx no longer skips a retryable lost visit.
- TS stand-ins: src/device-faults.mjs (twin of Fault/mayAttempt/tabPlan), device-phone-arms.mjs plumbing (pagesOf, countValues, censusValues, frameValues,
  reduceSession), device-phone-run.mjs and the withPhone glue (I/O).
- Writes outside the task graph: lean/scripts/PhoneArmsGolden.lean (golden script, r468 named it). New file packages/measure-webkit/{src/device-faults.mjs,test/device-faults.test.mjs} match device-*.
- Open: the strip retry belongs to phone-thermal-check; hidden-pause, logo-3d, scene-pause, const-bounds look worse on the phone (one visit each), repeat before a decision.
- Read first: lean/Fw/Device/PhoneArms.lean (end), packages/measure-webkit/src/device-faults.mjs, device-phone-run.mjs.
