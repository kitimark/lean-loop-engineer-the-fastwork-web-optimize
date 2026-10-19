# fw land: pre-lock protocol

`fw land <branch> --task <id>` (apps/runner/src/land.ts). Lean: `Fw.Console.LandSpeed` (`pre_eq_old_iff`, `preLand_commit_exact`,
`prelockAction_fallback`), `Fw.Console.Land` (`landTip`).

1. **Before the lock** (no lock, the main checkout is untouched and free for the lead):
   `main0 = HEAD`; `T = git -c attr.tree=main0 merge-tree --write-tree main0 tip`; `C = commit-tree` with parents `[main0, tip]` and the
   `Task:` trailer; C is checked out in a persistent land worktree `.claude/land-wt/<n>/` (gitignored, one slot per concurrent land,
   `.lake` and `node_modules` kept warm, everything else `git clean -fdx`-ed); the evidence edit is applied there and C re-made from the
   edited tree (the checked tree is the committed tree); conflict-marker grep; then `checksFor` (check-dag) run in the land worktree.
2. **Under the lock** (sub-second, span "lock held", 5 s ceiling): `prelockAction(HEAD, main0, verdict, attempt, retries)`:
   `ff` -> Lean `console.landCommit` (lock ours, HEAD = main0) -> `git merge --ff-only C`; `refuse` -> main untouched;
   `recheck` (main moved) -> release, redo against the new main, at most `retries` (3) times; `fallback` -> the old locked protocol
   (merge --no-commit in the main checkout, checks there, commit). A conflict also falls back (it then refuses as before).
3. **land-guard** only refuses commits during the ff instant (or during a fallback land's open merge).
4. `prelock: false` (option) = the old protocol only. The card fast-forward path (no `--task`) is unchanged.

TS stand-in, marked for Lean replacement: `prelockAction` (no fwcore op yet); checked against the `landSpeed.prelock` golden.
First-in-first-out landing: `land-queue.md`.

## `--dry` and verdict lines

Hand-back rule: before an agent hands a branch back it merges `main` into it and runs `pnpm fw land <branch> --task <id>
[--allow <glob>]... --dry`, and hands back only when the last line is `VERDICT dry <id>` (exit 0). Other kinds are fixed
first: `stale` = merge main again, `scope` = declare the write or pass `--allow`, `reads` = declare the read in the
premise, `conflict` = resolve. Lean `handback_pass_land_pass`: if the dry land passes and main has not moved, the real
land's scope, merge and reads stages pass.

`pnpm fw land <branch> --task <id> --dry` runs the real land's cheap stages on the same merge-tree commit: stale base (the branch must contain main), scope, merge and conflict markers, and the static reads test (`land-inputs.test.ts`) when the change selects the `reads-scan` check (its own cheap check, `vitest run test/land-inputs.test.ts`; selected by any change to a path any check declares as input, Lean `LandSpeed.scan_selected`). It takes no lock, writes no queue entry and never moves main; the checks run in a land worktree slot (a pid claim). Lean: `Fw.Console.LandDry` (`dry_pass_land_pass`, `dry_refusal_is_land_refusal`, `handback_pass_land_pass`).

Every `fw land` prints a last line `VERDICT <kind> <task>` and exits with a code per kind (Lean `Fw.Console.LandVerdict`):

| kind | exit | meaning |
|---|---|---|
| done, dry, queued, empty | 0 | landed, dry land passes, queued, the branch has no commit of its own (nothing to land) |
| busy 10, dirty 11 | 10, 11 | retryable: the lock or the main checkout is in the way |
| scope 12, reads 13, conflict 14, checks 15, stale 16, lint 17 | 12-17 | fix the branch (lint: a fast lint failed) |
| unknown | 2 | anything else |

Scripts read the word after `VERDICT` or the exit code, never prose. A dry run (also one that throws or is refused before any stage) prints
exactly one `VERDICT` line, last: `fw.ts` prints the lines Lean `dryRun` returns for the seven stage outcomes that `land.ts` computes
(Lean `dryRun_one_verdict`; a thrown exception is the outcome `threw`, kind `unknown`). Not proved: that `land.ts` computes the outcomes
truthfully (tests only). A non-dry land prints its VERDICT line in `fw.ts` as before (tests, not a theorem).

### The dry land's fast lints

After the reads stage the dry land runs, in the merge-tree worktree (never the main checkout), the fast lints that refused real lands:
`node scripts/ci-paths.mjs --check` (0.1 s) and, when the change touches `lean/`, the axiom check the way `lean/scripts/check.sh` runs it
(`lean/scripts/axiom-check.sh`: an incremental `lake build`, then no `sorryAx` and only the standard axioms; no `fwtest`, no tests). A failure is `VERDICT lint` (exit 17). Which lints run is Lean `lintPlan`. Order (Lean `Outcome.first`): exception, stale, empty (no own commits), scope, conflict, reads,
lint, dry (`kind_spec`: the kind is the first failing stage in that order); `dry_pass_all`: dry means every one of them passed. A real
land prints `lint` too when a failed check reports only the `check.sh` stages `lake build` / `axiom check` (Lean `checkFailKind`,
`dry_kind_is_real_kind`); the real land has no `ci-paths` check, so a `ci-paths` failure has no real counterpart. Glue: `dryLintArgv` in `apps/runner/src/land.ts`; tests inject `dryLints`.
Cost: see the handoff note `docs/team/handoffs/land-dry-full.md`. TS stand-in `apps/runner/src/land-verdict.ts`, checked against `packages/contracts/golden/console/land-dry.jsonl`.

