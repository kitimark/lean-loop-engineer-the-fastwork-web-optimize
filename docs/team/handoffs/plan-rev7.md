# Handoff: plan-rev7 (plan-editor)

## State
- PLAN.md revision 7 written (catch-up to d41aef0; rev 6 was a48aa54). Commit: see branch
  `worktree-agent-a8184e17f77478661` ("plan: revision 7 ...").
- loop-plan.html matches rev 7 outside the generated math view (new `#rev7` section, measure, findings,
  parts, lean, team, roadmap and decisions sections updated).
- class-policy.md: Chromium part DECIDED (SPK-i, 6b4237e), CI numbers 33/22/7, 31/23/8, 27/27/8; local 28/14/8
  marked superseded. WebKit part still DRAFT.
- lean/README.md: only the `measure.classify` row changed (`pxRel`, `unit`, `tBound`, `classifyAllU`).

## Conventions followed
- Status tags (CONFIRMED / INFERRED / MEASURED) with commit or note citations.
- No table cell over ~40 words (checked with a word-count script over every markdown table).
- Contradictions resolved in place and recorded in App A (A25-A28) and the App D rev-7 delta table.
- The generated blocks `mathview-review:begin/end` and `mathview:begin/end` in loop-plan.html are untouched.

## Open items
- PLAN.md is ~1,620 lines, above the ~1,300 target (words fell from ~28,500 to ~27,400; the table split
  added lines). Next cut: move §4.2 findings and §6.6 details to research notes (logged in App D).
- Open user questions: Q32 (A/B bench window), Q34 (MUI `cssVariables`, rec. off), Q35 (dead CSS as an
  inert sheet, rec. no).
- loop-plan.html roadmap rows M4-M6 are unchanged from rev 6.

## Read first
1. PLAN.md §0 "Since revision 6" and App D "Revision 7 delta".
2. docs/team/improvements/2026-10-17.md after the rev-7 entry, for the next catch-up.
