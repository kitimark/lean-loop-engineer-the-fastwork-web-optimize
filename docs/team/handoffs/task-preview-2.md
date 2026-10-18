# task-preview-2 handoff

State: branch worktree-wf_9700d3e6-57a-1 (see `git log -1`). Read first: docs/team/handoffs/task-preview.md.

- Owner link secrecy. Lean: `Sink`, `linkSink`, `linkPlan`, `no_file_sink`, `no_nontty_sink`, `linkPlan_ok` (end of
  lean/Fw/Console/Preview.lean); wire op `console.previewLink` (no golden yet: adding one needs lean/Fw/Ops/Golden.lean, outside this task scope; land with --allow or a follow-up). TS: apps/console-api/src/preview/link.ts
  (`announceLink`: opens /dev/tty, asks Lean, writes the link to the tty only), main.ts (no token on stdout/stderr), owner.ts
  `reissue()`, src/owner-link.ts (`pnpm --filter @fw/console-api owner-link` sends SIGUSR2 to the pid in api.json; the
  console writes a fresh link to ITS own terminal; the command prints no link). No tty -> no link, message says how.
  Test: apps/console-api/test/owner-link.test.ts (child in its own session, stdout+stderr a file: no token; fake tty).
- Panel head. Lean `srcRank`/`ordered`/`pickHead` (rank: handoff, merge, named, handoffCommit, ci, originCi; first held
  wins), `Fact.land` + `landOf` (landed head previews its land commit on main, not main's tip). PreviewTable rows have
  `expectHead`; `table_matches` proves head and target for all 25. Glue: facts.ts `landCommit` (first-parent commit of
  main after the head, ancestry path). Tests in test/preview.test.ts ("panel head").
- Heads that changed vs round 2 (held by an integration ref, both candidates): port-morph-columns, port-nav, port-people,
  port-platform, fix-nav, fix-pain-notes, fix-commission-margin, fix-page-offset (+ landed rows now show land commits).
- Known limit (INFERRED): a handoffCommit that is on main only because main later edited the handoff reads as held; it
  ranks below handoff/merge/named, so only tasks with no better candidate are affected.
- Open: SIGUSR2 by an agent only re-prints a link to the user's terminal (nuisance, no leak); same-UID cookie theft remains.
