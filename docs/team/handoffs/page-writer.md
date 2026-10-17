# Handoff: page-writer

State at f2988c0 (explainer page at plan rev 5 with review fixes, published).

- `docs/plan/loop-plan.html` is the published artifact. The lead publishes it from this same file path.
- Page contract: no doctype/html/head/body; `<title>` first; colors as tokens with both dark-mode blocks; the side
  gutter uses `max(16px, env(safe-area-inset-*))`; no horizontal scroll at 375 px; check light and dark.
- `<meta charset="utf-8">` is at the top, because pre-rendered MathML garbles over file:// without it.
- Math view: `node docs/plan/tools/build-math-view.mjs` rewrites the block between the generated markers.
  `--check` fails on drift or bad TeX. It uses katex 0.16.11 from the root devDependency (`pnpm install`; `FW_KATEX`
  overrides). Math is pre-rendered MathML, so the page loads no script.
- The math source is `research/kickoff/05-lean-sketch/Fw/Spec/*.lean` docstrings. When `lean/` lands it moves there.
- The reviewed chip links `research/notes/2026/10-17-math-review-fw-spec.md`.
- Roadmap: the dependency graph mirrors PLAN §10.1/§10.2. Landed boxes show their commit sha; nothing hand-written
  says "running".
- A link to `docs/plan/math-to-lean.html` sits near the Math view heading, outside the generated markers.
- Don't commit (the lead commits). Report ≤300 chars.
