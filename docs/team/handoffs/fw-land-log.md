# fw-land-log handoff

State: branch worktree-agent-abeaf5b1b6fb9dfa7. Tests green (console-api test/reconcile*, runner test/land*) with FW_CORE_BIN pointing at the main checkout's fwcore.

What exists
- `fw land <card/branch> --task <id>` (apps/runner/src/land.ts, flag parsed in fw.ts): checks the task is defined and undone, merges `--no-ff`
  with a `Task: <id>` trailer, then submits task.done (key `taskdone:<id>`, evidence = merge commit) and prints the commit link.
  Without --task: ff-only as before. Still card branches only (`card/<CARD>[/<agent>]`): worktree-* branches are refused by branchCard.
- Reconciler pass 3a (reconcile/reconciler.ts, git.ts `taskTrailers`): whole-line `Task: <id>` trailers on first-parent history of main
  (last 300) -> task.done(actor git, evidence = that commit). Same key as land and as the old card-id pass 3b, so first writer wins.
- `GET /api/repo` -> {url, commit} from `git remote get-url origin` (ssh/https normalised; null without origin). Never hard-coded.
- TS STAND-INS (no Lean rule exists in lean/Fw/Plan for "which merge maps to which task"; Lean only decides done/evidence once the command
  arrives): trailer parsing, repoUrl normalisation. Candidates for Lean golden vectors later.

Open items
- console-web Plan.tsx `Evidence` still shows `git show <sha>`; it should fetch /api/repo and link `${commit}${sha}` (file outside my writes).
- Lead's real merges of worktree-* branches via plain git need `-m "Task: <id>"`; making `fw land` accept non-card branches is a policy call.
- con-plan handoff claims "no public remote": wrong, origin exists.
- Console must have a Reconciler (createApp third arg) for /api/repo.

Read first: apps/runner/src/land.ts, apps/console-api/test/reconcile-task.test.ts.
