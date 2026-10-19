# port-font-gaps handoff
- Change: form-control base rule (color/font inherit) in apps/site/src/styles/reset.css (reset layer); MUI theme typography fontFamily set to the original body stack (was system-ui, the cause of countdown and morph.panel Typography text).
- Button parts keep their own size/weight rules; the reset only restores the family. Confirm on CI via check-5 fonts step.
- Merged worktree-wf_db541e00-01b-1 locally for the CI run; branch ci/port-font-gaps.
- Open: CI result (font-change pairs), people.deck/people.o limits.
- CI run 39254252262 (visual-diff, ci/port-font-gaps, all jobs green; check-5 steps advisory FAIL): no button or countdown font-change pair remains in either engine; svg/assets: 0 missing of 111, svg 0 missing 0 extra of 31/31.
- Remaining: people.o "o" -> people.card "o" (ownership, all probes); WebKit desk-1512 people.deck content mismatch; WebKit touch-601/401 lose morph.panel text and 5 morph.countdown leaves with nothing added (leaf missing in the port at those probes, not a family change; investigate next). Earlier run 39251365605 was lean only (lane not requested).
