# port-font-gaps handoff
- Change: form-control base rule (color/font inherit) in apps/site/src/styles/reset.css (reset layer); MUI theme typography fontFamily set to the original body stack (was system-ui, the cause of countdown and morph.panel Typography text).
- Button parts keep their own size/weight rules; the reset only restores the family. Confirm on CI via check-5 fonts step.
- Merged worktree-wf_db541e00-01b-1 locally for the CI run; branch ci/port-font-gaps.
- Open: CI result (font-change pairs), people.deck/people.o limits.
- CI run 39254252262 (visual-diff, ci/port-font-gaps, all jobs green; check-5 steps advisory FAIL): no button or countdown font-change pair remains in either engine; svg/assets: 0 missing of 111, svg 0 missing 0 extra of 31/31.
- Remaining: people.o "o" -> people.card "o" (ownership, all probes); WebKit desk-1512 people.deck content mismatch; morph loss at WebKit touch-601/401 was reader timing; see Round 1. Earlier run 39251365605 was lean only (lane not requested).

## Round 1 (deterministic check-5 reader)
- Merged worktree-wf_db541e00-01b-1 (not pushed). CI run 39262636419 (visual-diff, ci/port-font-gaps, all jobs green, commit with [ci:visual-diff]). Branch head: 0256a28b.
- Font changes (family/weight/style differs on a paired leaf): 0 in every probe, both engines (8 probes each). Gaps 0, missingFaces/extraFaces 0, settled true both sides, deck tab equal.
- WebKit touch-601: leaves 462/461 (orig/port), touch-401: 461/462; morph.panel and morph.countdown leaves are present on both sides and paired (not in lost/added). Only unpaired: commission.typing (time-driven).
- Remaining per engine: 1 move (people.o "o" -> people.card, ownership) in every probe; unpaired time-driven leaves (platform.entries, commission.typing, pain.notes) are reader limits.
- Morph-loss cause: reader timing. MEASURED: settled run 39262636419 has every WebKit touch-601/401 morph leaf in both arms with the same font (missing/extra hold only commission.typing and people.o). INFERRED mechanism: the older unsettled reader read whichever arm was early at 363 leaves (orig in 39248286394: 363/377 and 363/363; port in 39254252262: 461/363 and 461/363). Settled counts: touch-601 462/461, touch-401 461/462.
- Follow-ups: overlay buttons (overlays.signup, overlays.drawer, nav.langMenu) are outside what CI verified; people.o ownership move; generate the body font stack from one source (theme.ts and reset.css) instead of the equality test apps/site/src/font-stack.test.ts.
