# phone-end-counts handoff (round 4 build, final design round)

- Branch worktree-wf_67587a94-89a-1; worktree .claude/worktrees/wf_67587a94-89a-1; last commit: `git log -1` (main 92c905d81 merged).
- CI: no new push in rounds 2 to 4. Round 1 push ci/phone-end-counts at ab773fe95: all 20 workflows skipped (lean-math
  40173828875, chromium-counts 40173828867, webkit-sim 40173828789). Runs in flight: none.
- Phone: 15 of 16 visits done (base x3 at visits 0, 7, 15; 12 arms once). Lost: morph.countdown:strip (visit 6). Raw files .local/phone/2026-10-25/
  (gitignored). No phone use in rounds 2 to 4.
- Strip provenance: try 1 is in blocks3.log:77-81 with no error line on disk; its usbReset name rests on the lead's account (INFERRED), and
  lead-resume.log starts at attempt 2. Try 2's text "found 0 of 1 tabs" is `other` by Lean faultOf (golden phone-arms.jsonl:73); named staleTab by
  hand (INFERRED). Try 3 other (Runtime.evaluate timeout, no USB cycle). The lead marked it lost (lead-resume.log:31); Lean agrees for any three
  faults (mayAttempt_fourth, strip_visit_lost). Try 3 ran only because the counter restarted after the hand reset. state.json attempts 3 and its
  faults were set by hand to match the log (accepted limit). Retryable false; re-measure in phone-thermal-check is a new visit.
- Verified: Lean lean/Fw/Device/PhoneArms.lean (arm plan, verdict rule, Fault/mayAttempt, recordFault/handReset/appendOnly, TabPlan with ownTab by
  host at any port, `visitMin` 7); golden packages/contracts/golden/device/phone-arms.jsonl (regenerate: `cd lean && lake build
  Fw.Device.PhoneArms && lake env lean --run scripts/PhoneArmsGolden.lean > ../packages/contracts/golden/device/phone-arms.jsonl`), replayed by
  packages/measure-webkit/test/device-phone-arms.test.mjs and device-faults.test.mjs.
- Round 4 (prose only): note wording (strip provenance, hand-reset guarantee is the runner's, second attempts of visits 2 and 14, Simulator
  sentence restored, EventDispatch except const-bounds); ledger: only the strip note changed.
- Reduced: results/phone/2026-10-25-end-counts/{summary.json,tables.md}; note research/notes/2026/10-25-phone-end-counts.md; ledger: 12 notes.
- TS stand-ins: src/device-faults.mjs (twin of Fault/mayAttempt/tabPlan/recordFault/handReset/appendOnly, checked against the golden),
  device-phone-arms.mjs plumbing, device-phone-run.mjs and the withPhone glue (I/O).
- Writes outside the task graph: lean/scripts/PhoneArmsGolden.lean; packages/measure-webkit/{src/device-faults.mjs,test/device-faults.test.mjs}.
- Open: hand-reset CLI (arms-run --hand-reset <index> <reason> calling markHandReset) and refusing a state write that removes a visit with
  faults: phone-thermal-check, Lean-first in PhoneArms.lean with a golden line.
- Open: the strip re-measure and the wip.mjs fix belong to phone-thermal-check; hidden-pause, logo-3d, scene-pause and const-bounds trade on the
  phone (one visit each): repeat before any flag decision.
- Read first: lean/Fw/Device/PhoneArms.lean (end of the Fault and TabPlan sections), packages/measure-webkit/src/device-faults.mjs, device-phone-run.mjs.
