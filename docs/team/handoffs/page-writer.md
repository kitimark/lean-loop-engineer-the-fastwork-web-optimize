# Handoff: page-writer

State at 2c3e5e3f (branch worktree-wf_33987ed2-d9d-2, main a3196a4 merged): loop-plan.html is the page, math-view.html its supporting file.

- `docs/plan/loop-plan.html` is the published page; `docs/plan/math-view.html` (the generated math view, about 10.5 MB) is a
  supporting file published at the same relative path, so the page's `math-view.html` links resolve. The lead publishes both.
- Page contract: no doctype/html/head/body; `<title>` first; colors as tokens with both dark-mode blocks; the side
  gutter uses `max(16px, env(safe-area-inset-*))`; no horizontal scroll at 375 px; check light and dark.
- `<meta charset="utf-8">` is at the top, because pre-rendered MathML garbles over file:// without it.
- Math view: `node docs/plan/tools/build-math-view.mjs` runs `lake build`, `lake exe mathview --lint` and
  `lake exe mathview` in `lean/` (or takes `--json <export>`), then rewrites three generated blocks: `mathview` in math-view.html (the view,
  grouped by module, order list in the script; new `Fw/` modules append by name), `tokens` in math-view.html's style (a
  copy of loop-plan.html's style block) and `mathview-review` in loop-plan.html (the review panel's chip, tally, record
  link, axiom line). `--check` fails on drift or bad TeX. KaTeX 0.16.11 from the root
  devDependency (`FW_KATEX` overrides). Math is pre-rendered MathML, so the page loads no script.
- Review status per declaration comes from table rows in `research/notes/*/*-math-review-*.md`. Row format (new rows):
  `| \`Fw.Full.name\` | agree|disagree | <stmtHash> | <mathHash> | <note> |`, both hashes copied from
  `lake exe mathview` (`stmtHash`: Lean statement + reached `Fw.*` bodies; `mathHash`: the whole docstring, English +
  `$$` math + notes, whitespace-normalised). Older rows stay valid: `| name | verdict | <stmtHash> | <note> |` and
  `| name | verdict |`. Hash cells are recognised by being all digits (mathHash only after a stmtHash). A row is
  "review stale" when any hash it carries differs from the export, so stmt-only rows do not catch docstring edits; no
  row shows "review pending".
- Precedence: each record's frontmatter has `round: <n>` (fwcore = 2, r3-a65aaa7 = 3); the highest round wins, the
  last row within a record. A record with rows but no `round:` ranks below all rounds (by file name) and the generator
  warns; two records with the same round fail. The fw-spec record (sketch, 72 agree) has no rows and is only linked
  as history. A new review record: next round number, then re-run the generator; nothing else to edit.
- Backfill: every r3 row carries a mathHash (lean/Fw unchanged since a65aaa7); fwcore rows carry one only where the
  docstring is unchanged since 9367dea (176 of 224; 48 stay stmt-only with an empty mathHash cell).
- The generated blocks carry no git sha: the stamp is `export <12 hex>`, sha256 of the sorted
  `name\tstmtHash\tmathHash` lines, so a rebase that leaves lean/ unchanged keeps `--check` green.
- At 9367dea: 224 declarations, 12 modules, 93 theorems, all sorry-free with standard axioms, 224 review pending.
- 375 px check: Chrome headless needs CDP `Emulation.setDeviceMetricsOverride` with `mobile:false` (the window
  minimum is 500 px, and `mobile:true` gives a 980 px layout viewport because the page has no viewport meta).
- Roadmap: the dependency graph mirrors PLAN §10.1/§10.2. Landed boxes show their commit sha; nothing hand-written
  says "running".
- A link to `docs/plan/math-to-lean.html` sits near the Math view heading, outside the generated markers.
- Don't commit (the lead commits). Report ≤300 chars.
