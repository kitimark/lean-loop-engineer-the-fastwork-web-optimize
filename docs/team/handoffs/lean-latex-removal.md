# lean-latex-removal (closed by latex-close)

- **State:** all child steps done; the last, latex-close, is commit `5c48df67` on `worktree-wf_b89787a9-b17-1`.
- **Removed, by step:**
  - latex-lint-relax: the mathview docstring rules (`$$` required, English before math).
  - latex-generators: `$$` output of the six Lean generators.
  - latex-mathview-b2: the mathview-differential CI job, `mathview-cached.sh`, `build-math-view.mjs`, the english/math
    export fields and their lints.
  - latex-strip-c, latex-strip-c2, latex-close: every `$$` and inline LaTeX in Lean doc comments; premise statements
    became Unicode plain text.
  - latex-teardown, latex-plan-text: LaTeX rules in agents, tools docs and PLAN.md. skills-reframe moved the Lean
    comment rules into `comment-sicko`.
  - latex-close: the one-off `scripts/latex-strip.mjs` and its test.
- **Verified:** 0 LaTeX hits in comments of all 354 tracked `lean/**/*.lean` (latex-close handoff has the scan);
  `sh lean/scripts/check.sh` green.
- **Rules from here on (positive):**
  - Lean source holds specs, proofs and code. Docstrings are plain sentences per `.claude/agents/comment-sicko.md`;
    a formula there uses Lean or Unicode notation (`≤`, `∀`, `↔`) inside code spans.
  - Math a reader sees is written on demand into an artifact from the Lean statement, per
    `docs/team/tools/math-artifact.md`; `lake exe mathview --decl <name>` gives the signature, `autoTex` and hash.
  - Data strings emitted to goldens (premise statements) are Unicode plain text, since no consumer renders TeX.
- **Kept on purpose:** the MathView renderer (`autoTex`, LaTeX for artifact writers), `math-reviewer` and KaTeX in
  `docs/plan/tools/check-lean-lessons.mjs`; research notes that quote LaTeX are history.
- **Open (lead):** `docs/team/work-graph.json` still names `scripts/latex-strip*.mjs` in task writes; the
  `mathview-cache` row in `docs/team/tools/disk-cleanup.md` can go once no checkout holds that directory.
- **Read first:** `docs/team/tools/math-artifact.md`, `.claude/agents/comment-sicko.md`.
