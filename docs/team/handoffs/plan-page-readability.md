# Handoff: plan-page-readability

State at 2c3e5e3f plus the lead fix commit after it (branch worktree-wf_33987ed2-d9d-2, main a3196a4 merged).

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
- Round 2: Now table stacks below 600 px (data-label per cell), nav static below 600 px, hero meta carries the deadline
  and C2, `min-width:0` on details and section children; no page scroll at 390/375, light/dark, all details open.
  Now panel is hand-written with an "as of main a3196a4, 2026-10-18 20:16 +0700" stamp; refresh it from
  work-graph.json when it matters. Rev-10-reversed sentences (cost model, calibration, 5 of 5 swipes, phone as a
  condition) rewritten, including the outer-loop SVG labels. Deadline and critical path only in Now (Roadmap links).
- math-view.html is 10.5 MB (limit 12 MB): generator drops KaTeX annotation/semantics, span, xmlns, separator, merges
  upright single-letter `<mi>` runs; `.mv-entry` has content-visibility:auto. Its style token block is a generator copy
  of loop-plan's style between `tokens:begin/end`. Generator maps U+2238 to `\dot-` (new on main in Fw.Gate.Shard).
- Open: generating the Now panel from the work graph; Measuring/Findings/Parts prose beyond F5 is rev 7-9 wording;
  Why/Chat not merged; no viewport meta (host skeleton). Publish loop-plan.html plus math-view.html at the same path.
