# land-dry-full handoff (builder)

State: branch worktree-wf_59731989-59c-2. check.sh green, runner tests 617 pass, tsc clean.

Done
- Lean `Fw.Console.LandVerdict`: kinds `empty` (success, exit 0) and `lint` (refusal, exit 17).
- Lean `Fw.Console.LandDry`: `Stages` gains `own` and `lints`; `dryKind` order stale, empty, scope, conflict, reads, lint, dry.
  Theorems: `dry_pass_all`, `dry_iff_land_pass` (updated), `empty_ok`, `dry_prints_one_verdict`, `dryKind_cases`. Goldens regenerated
  (land-dry 42 rows, land-queue 28 rows: the queue golden iterates `Kind.all`).
- TS: `land-verdict.ts` (kinds, `dryKind` with own, lints); `land.ts` `dryLintArgv` + `dryLints` option + empty early return;
  `fw.ts` turns an exception in `land` into `VERDICT unknown`.
- Lints run in the merge-tree land worktree slot: `node scripts/ci-paths.mjs --check` always; `lean/scripts/mathview-cached.sh --build`
  when the change touches `lean/` (cache hit builds nothing; a miss runs an incremental `lake build`, no fwtest).
- Measured (this Mac, the full dry on this branch, 6 Lean modules changed, warm slot): 11 s end to end (reads test + lints).

Scope note: the task writes lack `apps/runner/src/land-verdict.ts` and `apps/runner/src/fw.ts`; the dry here passed with
`--allow` for both. The lead should add them to the task writes (or land with --allow).

Open: the real land still reports a lint failure as `checks` (the lint stage is dry-only in the Lean model). The cause of the
earlier "no VERDICT" for fix-orbit was not reproduced; the try/catch in fw.ts guarantees one line for any exception.
