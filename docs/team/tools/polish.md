# fw polish: comment and prose polish in the build flow

Every build-review run that the reviewer accepts gets a Polish stage: `comment-sicko` on the code and shell files of the
diff, `slop-checker` cuts on its prose. Lean decides which file is in which scope, which cut applies and which edit is
kept (`Fw.Plan.Polish`, fwcore ops `plan.polishPlan`, `plan.polishCuts` and `plan.polishHunks`); `apps/runner/src/polish.ts` reads git and
files, calls fwcore and writes what it returns.

## Use

```
pnpm -s fw polish plan --branch <b> --task <id>
pnpm -s fw polish cuts --branch <b> --task <id> --cuts <file|-> [--apply yes]
pnpm -s fw polish commit --branch <b> --task <id> [--message <m>]
pnpm -s fw polish --staged [--cuts <file|-> [--apply yes]]
```

- `plan`: classes of `git diff --name-only main...<b>`, read in the branch's worktree. Prints `class <class> <mark> <path>`,
  then `comments <mark> <repo-relative path> lines <lo-hi,lo-hi|none>` (the branch's changed lines of that file plus the
  margin: the only lines `comment-sicko` may edit) and `prose <repo-relative path>`, then `VERDICT polish-plan <id> <stages>`
  (`comments`, `prose`, `comments,prose` or `none`).
- `cuts`: cuts are `{cuts:[{path, old, new}]}` or a bare array; paths relative to the worktree or absolute. Prints one
  `cut <verdict> <path> "<old…>"` line per cut (`missing <tokens>` for `dropsFacts`), then
  `VERDICT polish-cuts <id> applied|judged <n>/<m>`. Only files in the prose scope are read; a cut on another file is `notProse` or `notFound`.
- `commit`: edits in the worktree (`git diff --name-only HEAD`) that Lean keeps are added and committed; the rest are
  restored from HEAD. Each edit hunk of a code or shell file is judged alone: a hunk not wholly inside a branch hunk plus
  the margin is reverted whole (even one that starts inside the margin and runs past it) and named
  (`restored <path>:<lo>-<hi> (outside the branch's hunks)`); a kept file with no edit record is restored. If the main
  checkout has uncommitted edits in the plan's files, nothing is restored or committed:
  `VERDICT polish-commit <id> refused` (exit 1). `VERDICT polish-commit <id> committed|nothing`.
- `--staged`: the lead's own commit. Scopes come from the index of this checkout; spawn `comment-sicko` on the
  `comments` lines and `slop-checker` on the `prose` lines, then judge its cuts with `--cuts`. `--apply yes` re-stages
  the changed files.

Errors print `VERDICT <kind> <id> error` and exit 1; a usage error exits 64.

## Decisions (Lean `lean/Fw/Plan/Polish.lean`)

- Classes: `skip` (generator outputs, a `GENERATED` first line, `.gen.` names, lock files, `snapshot/`, golden and
  fixture trees, `.lake`, `.cache`, `.local`), else `shell` (`.sh`, `.bash`), `code` (TS, JS, Lean, YAML), `prose`
  (Markdown, the ledger and the work graph); any other file is `skip`. Generator outputs are the workflow files `scripts/ci-paths.mjs --write`
  reconciles and `lean/Fw/Ops/LakeJobsGen.lean`. Theorems: `skipped_skip`, `gen_skip`, `stamped_skip`, `snapshot_skip`.
- A shell file is never Lean: its mark is `#` (`shell_mark`, `shell_not_lean`).
- A skip file is never in a scope and its edits are restored (`admits_not_skip`, `skip_never_edited`, `gen_never_edited`,
  `kept_not_skip`, `kept_in_diff`).
- A stage runs only when its class is in the diff (`comments_runs_iff`, `prose_runs_iff`, `stages_nil`).
- Cuts (`judge`, in order on the text the earlier cuts left): `notProse`, `notFound`, `notUnique` (old must occur once),
  `dropsFacts` (a number, commit, `path:line`, status word or identifier of old is missing from new; `cutSafe_iff`),
  `breaksPunct` (a new space before `;` `,` `.` `)` `:`), `breaksJson` (a quote, backslash or newline in a JSON cut), else
  `apply`. One theorem per verdict: `judge_apply_iff`, `judge_notFound`, `judge_notUnique`, `judge_dropsFacts`,
  `judge_breaksPunct`, `judge_breaksJson`, `judge_skip`.

- Hunk rule (`admitted`, op `plan.polishHunks`): an edit hunk is kept iff some branch hunk `h` has
  `h.start - 3 <= e.start` and `e.hi <= h.hi + 3`, that is, the edit lies inside the hunk plus the 3-line margin
  (containment, not overlap: `admitted_iff`, `admitted_inside`, `restored_far_above`, `restored_far_below`). Path rule
  (`relOk`, `editKept`): the path is non-empty, does not start with `/`, and no `..` climbs above the worktree root (`a/../b` passes, `../a` and `a/../../b` do not); `blocked_mem` names the dirty main-checkout files.
  Prose files are kept whole (their cuts are judged by `cutSafe`).

- Restore rule (op `plan.polishWalk`, `walk`): the commit step never reverse-applies a single zero-context hunk (git
  places it by the new-side line, which an earlier kept hunk has shifted; this reinserted a deleted docstring 7 lines too
  low in Trajectory.lean and Timing.lean, which then did not build). For a file with kept and restored hunks it walks the
  `-U0` hunks in ascending order over the HEAD blob: kept hunks emit their new lines, restored hunks the HEAD lines
  (`walk_restored`, `walk_keep`, `walk_restore`, `walk_skip_restored`: the result is HEAD with exactly the kept hunks
  applied). The walk is TS (`walkHunks`, a stand-in) replayed against the Lean goldens; a hunk with a
  no-newline marker restores the whole file.
- Invariant (round 3): the polish commit's tree differs from HEAD only in the `keep` paths (`git commit -- <keep>` builds
  a temporary index, so the pre-commit hook also sees only `keep`; other staged entries stay staged). `keep`, `restore`
  and both stage scopes are disjoint from the paths dirty at plan time (`plan.polishPlan` takes `dirtyBefore`, drops those
  paths from `paths` and `edited`, and names the dropped edited ones in `left`; theorem `dirty_never_scoped`). Settle
  touches only paths outside the plan-time baseline. Without a baseline `fw polish commit` acts on nothing.
- The stage ends clean (`plan.polishSettle`, `settle`): after every commit outcome the dirty tracked paths that were clean
  at plan time are restored from HEAD (the index is reset only for those paths), untracked files not present at plan time
  are deleted, and one line `cleanup: restored N (...), removed M (...), worktree clean` is printed (`settle_clean`,
  `settle_dirty_before`, `settle_keeps_dirty_before`, `settle_restores_clean_only`, `settle_removes_created`,
  `settle_keeps_before`, `settle_committed`, `settle_idempotent`).
- Baseline lifetime: `fw polish plan` writes `fw-polish-untracked` and `fw-polish-dirty` in the git dir (the same dirty
  list it passed as `dirtyBefore`) and prints `skip <path> (dirty before plan)` for each planned path that was dirty;
  `--staged` passes no dirty paths (every staged path differs from HEAD). The commit step prints `left <path> (dirty
  before fw polish plan, not the polish stage's)` from Lean `left`. Settle deletes both baseline files, so a second
  commit needs a fresh plan.
- No baseline (either file missing): `fw polish commit` prints `no baseline from fw polish plan` and
  `VERDICT polish-commit <task> refused` and touches nothing; settle without a dirty baseline restores nothing, without an
  untracked baseline deletes nothing. With fwcore down the stand-in restores only non-baseline dirty paths and deletes nothing.

## Goldens

`packages/contracts/golden/plan/polish.jsonl` (test `apps/runner/test/polish.test.ts`; regenerate with
`FW_WRITE_POLISH_GOLDEN=1`). The three over-cuts of the 10-22 slop pass are cases: all three are `dropsFacts` (polarity words `not`, `no`, `never`,
`without`, `unless` are facts).

## Limits

- A cut that keeps every token and polarity word but drops other meaning applies; `slop-checker`'s judgement stays an
  agent's, and so does `comment-sicko`'s.
- Each polish run costs one comment and one prose agent per accepted build.
- `relOk` checks the path text, not symlink resolution.
- A cut applies only where its old text occurs once in the file and `cutSafe` holds.
