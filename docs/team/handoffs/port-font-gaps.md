# port-font-gaps handoff
- Change: form-control base rule (color/font inherit) in apps/site/src/styles/reset.css (reset layer); MUI theme typography fontFamily set to the original body stack (was system-ui, the cause of countdown and morph.panel Typography text).
- Button parts keep their own size/weight rules; the reset only restores the family. Confirm on CI via check-5 fonts step.
- Merged worktree-wf_db541e00-01b-1 locally for the CI run; branch ci/port-font-gaps.
- Open: CI result (font-change pairs), people.deck/people.o limits.
