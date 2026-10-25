# phone-end-counts handoff (round 3)

- Branch worktree-wf_67587a94-89a-1; worktree .claude/worktrees/wf_67587a94-89a-1; last commit: `git log -1`.
- CI: no new push in rounds 2 and 3. Round 1 push ci/phone-end-counts at ab773fe95: all 20 workflows skipped (lean-math
  40173828875, chromium-counts 40173828867, webkit-sim 40173828789). Runs in flight: none.
- Phone: 15 of 16 visits done (base x3 at visits 0, 7, 15; 12 arms once). Lost: morph.countdown:strip (visit 6). Raw files .local/phone/2026-10-25/
  (gitignored). No phone use in rounds 2 and 3.
- Strip, exact order (lead-resume.log): try 1 usbReset (proxy 1006 with USB re-enumeration), try 2 staleTab (found 0 of 1 tabs), lead hand reset,
  try 3 other (Runtime.evaluate timeout 15 s mid-scroll, no USB cycle). State.json now has attempts 3, faults [usbReset, staleTab, other];
  Lean `mayAttempt` false (`strip_visit_lost`), retryable false. Lost arm of THIS session. Its re-measure in phone-thermal-check is a new visit in
  a new session with the wip.mjs didCommitProvisionalTarget fix, not a fourth attempt.
- Verified: Lean lean/Fw/Device/PhoneArms.lean (arm plan, verdict rule, Fault/mayAttempt, recordFault/handReset/appendOnly, TabPlan with ownTab by host at
  any port, `visitMin` 7 so two visits per block); golden packages/contracts/golden/device/phone-arms.jsonl (regenerate: `cd lean && lake build
  Fw.Device.PhoneArms && lake env lean --run scripts/PhoneArmsGolden.lean > ../packages/contracts/golden/device/phone-arms.jsonl`), replayed by
  packages/measure-webkit/test/device-phone-arms.test.mjs and device-faults.test.mjs.
- Round 3 fixes: ownTab matches `http://host` at any port (device.mjs passes protocol and hostname of server.url); faults append-only across a hand reset
  (Lean theorems, golden `reset` and `append` lines, `saveState` refuses dropped faults, `markHandReset`, a done visit keeps its faults); visitMin 7;
  note wording (strip order, base layers per stop, "trade" not "worse"); ledger notes.
- Reduced: results/phone/2026-10-25-end-counts/{summary.json,tables.md}; note research/notes/2026/10-25-phone-end-counts.md; ledger: 12 notes.
- TS stand-ins: src/device-faults.mjs (twin of Fault/mayAttempt/tabPlan/recordFault/handReset/appendOnly, checked against the golden),
  device-phone-arms.mjs plumbing, device-phone-run.mjs and the withPhone glue (I/O).
- Writes outside the task graph: lean/scripts/PhoneArmsGolden.lean; packages/measure-webkit/{src/device-faults.mjs,test/device-faults.test.mjs}.
- Open: the strip re-measure and the wip.mjs fix belong to phone-thermal-check; hidden-pause, logo-3d, scene-pause and const-bounds trade on the
  phone (one visit each): repeat before any flag decision.
- Read first: lean/Fw/Device/PhoneArms.lean (end of the Fault and TabPlan sections), packages/measure-webkit/src/device-faults.mjs, device-phone-run.mjs.
