# Handoff: plan-page-readability

State: branch worktree-wf_33987ed2-d9d-2, one commit.

- Math view moved to its own page `docs/plan/math-view.html` (head and tokens copied from loop-plan; generated block
  between `mathview:begin/end`). `loop-plan.html` keeps only the `mathview-review` panel (chip by priority
  disagree > stale > pending > reviewed, links to disagreements, link to the math page).
- `docs/plan/tools/build-math-view.mjs` writes both files; `--check` compares both. KaTeX needs `FW_KATEX` in a
  worktree without node_modules. `tex()` flattens `<mo>` that wrap other elements (`++`, `::`, `<|>`, monus, `\bmod`) and
  throws if any `<mo>` still has a child element.
- Math page: module table, "Needs attention" (disagreements only; stale shown as counts per module), one closed
  `<details>` per module, status chip only when not agree. Verified: 0 non-MathML nodes inside `<math>`, no
  horizontal scroll at 390 with every details open.
- loop-plan: new "Now" section first (static text from PLAN rev 10, not generated: TODO generate from work-graph),
  rev 9 log folded into a details, sections reordered (Now, Roadmap, Decisions, Why ... Team, Math), nav 7 wrapping
  links, hero ruler moved into Measuring, rev 7 dependency SVG folded under a details (superseded; not redrawn).
- Open: Now panel statuses are as of PLAN rev 10; Measuring/Findings/Parts text still rev 7-9; the Why/Chat merge
  and the "Review stale 517" list were not done.
