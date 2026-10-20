# latex-close (last step of lean-latex-removal)

- **State:** branch `worktree-wf_b89787a9-b17-1`, work in `5c48df67`, this handoff in the next commit, base `e51f47ac`.
- **Lean docs:** `Ci/Trigger` lost its 76 `$$` blocks (the stale 14-row table block included) and its inline `$C$`,
  `$m(x)$` now read `coneGlobs` and `differs x`. `Wire/Store` `parseFlag` and `Ci/Golden` `count` are plain text.
- **Premise statements:** no consumer renders them (only `apps/runner/src/premises.ts` types the field; no KaTeX in
  apps or packages), so all 33 registry and 5 untested statements are Unicode plain text. `golden/ops/premise.jsonl` regenerated.
- **Leftovers:** `MathView.lean:16` heading names the `autoTex` field; `CheckMap.trackedKeys` uses
  `docs/plan/tools/check-lean-lessons.mjs` for the retired `build-math-view.mjs`; `Fw/Site/README.md` cites
  `sh lean/scripts/axiom-check.sh`.
- **Retired:** `scripts/latex-strip.mjs` and its test. No package.json script, hook or CI step named them.
- **Verified:** comment scan of all 354 tracked `lean/**/*.lean` (doc and plain comments, code spans skipped, `$` and
  ~90 LaTeX commands): 0 hits. `latex-strip.mjs --check` on the same files before deletion: silent, exit 0.
  `git grep '$$'` in Lean leaves only shell PID cases in `Ops/Wait` and `Ops/Golden`. `sh lean/scripts/check.sh`
  green; ci-paths 41/41; runner 1478/1478 with tsc; contracts 7/7; premise-tests 3/3.
- **References outside the writes (lead):** `docs/team/work-graph.json` (latex-strip-c, latex-close writes),
  handoffs `latex-strip-c.md`, `latex-strip-c2.md`, `fwcore-lazy-tables.md`; research notes
  `2026/10-20-lean-migration.md`, `2026/10-21-findings-ledger-1020.md` (history, left).
- **Read first:** `docs/team/handoffs/lean-latex-removal.md`.
