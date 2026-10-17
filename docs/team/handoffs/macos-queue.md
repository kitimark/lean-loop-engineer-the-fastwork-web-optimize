# macos-queue handoff

State: investigation done; note written, uncommitted (the lead commits). This file and the note are the only edits.
- Note: research/notes/2026/10-17-macos-queue.md (base: main c92c310; data snapshot 2026-10-17 ~14:13 UTC)

Method (re-run to refresh numbers):
- `gh run list --limit 100 --json databaseId,workflowName,headSha,headBranch,createdAt,status` and
  `gh run view <id> --json jobs`, run from the repo dir; the label comes from `git show <headSha>:.github/workflows/<wf>.yml`.
- Job creation = run createdAt, or completedAt of its `needs`. A job is "started" when it has steps and status != queued.
- Scripts (scratchpad, not committed): q.py (waits per label + timeline), sweep.py (concurrency levels),
  rel.py (match each delayed start to the slot release before it), vm.py (VM-min per lane).

Conventions: read-only on workflows and runs; statuses MEASURED/CONFIRMED/INFERRED; no workflow edits.

Open items:
- Workflow owners apply: max-parallel budgets, dispatch-only sim-speed, fold wktr archive, rebase ci/* on main.
- `strategy.max-parallel` doc section not re-read (marked INFERRED).
- Plan tier unknown (the observed cap of 5 fits Free, Pro or Team).
