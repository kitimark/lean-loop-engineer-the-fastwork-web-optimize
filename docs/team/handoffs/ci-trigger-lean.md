# Handoff: ci-trigger-lean

State: branch worktree-agent-a6c1c91bf38def240 (commits "ci-trigger-lean: ..."), verified on CI branch ci/ci-trigger-lean.
Read first: `lean/Fw/Ci/Trigger.lean` (module docstring), then `docs/team/tools/fw-ci.md` last section.

What it does
- Lean decides: `starts_iff` (a workflow starts iff a push file that differs from main is in its declared inputs),
  `none_started` (soundness: nothing outside every input starts anything), `merge_starts_nothing`, `filter_passes` (the coarse
  GitHub paths filter never drops a needed start), `skipped_replays`. `table` holds every workflow's branches and inputs.
- `@fwcore` / `@breakgen` = build files + import cone of Main.lean / BreakgenMain.lean (not `lean/**`); the cone is read
  from the checkout by `scripts/ci-paths.mjs` (imports and include_str), so a new import moves the paths and the lint fails
  until `--write`.
- Golden: `packages/contracts/golden/ci/triggers.jsonl` (table + 14 replay cases). Regenerate:
  `cd lean && lake test -- --write-ci-trigger-golden`.
- `node scripts/ci-paths.mjs [--write]` writes/checks `on.push` (branches, paths), the `guard` job in EVERY workflow and
  `needs: [guard]` + `if` on every root job. Land check: `apps/runner/test/ci-triggers.test.ts` (+ `scripts/ci-paths.test.mjs`,
  `.github/scripts/changed-inputs.test.mjs`); `PACKAGE_EXTRA_READS["apps/runner"]` lists the files it reads.
- Guard (`.github/scripts/changed-inputs.mjs`) now asks about THIS push (before..HEAD, minus files equal to origin/main), not the
  whole branch; new branch / unknown `before` falls back to the whole branch. Fails open.
- Incident `inc-ci-trigger-drift` (docs/team/incidents/ledger.json): why ci-trigger-scope did not hold (merge diffs match the
  filter; 3 of 11 workflows; `lean/**` everywhere; whole-branch guard; no lint), Lean verdict provable.

Conventions: TS/JS glue holds no decision; the table is the single place to change a trigger. Globs are limited to what GitHub
and PathCheck read the same (`portableGlob`). Workflow `needs:` must be inline (`[a, b]`) for the reader.

Open items
- Math view: new theorems in Fw.Ci.Trigger are unsigned; run math-reviewer.
- The first push of any new ci/* branch has no `before`: the guard uses the whole branch, so a branch that changes a workflow
  file starts that workflow (by design). Dispatch is the way to run one lane (fw-ci.md).
- Cones are over-approximate only if Lake reads files besides `import`/`include_str`; add them to `fwcoreFiles` if found.
- Whole-branch fallback could use `before` from the event payload on new branches; not needed so far.
