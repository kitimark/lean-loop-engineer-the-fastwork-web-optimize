# webkit-cancelled-flake handoff

State: root cause found and fixed in `packages/e2e-preview`; branch `worktree-wf_ad651a2b-c27-2`, CI branch
`ci/webkit-cancelled-flake` (tip carries a temporary workflow that the final commit removes).

Cause (MEASURED + CONFIRMED): the suite leaves the grant landing page with a plain `page.goto(next)`; a lazy image
request of the landing page (`service-strawberry.jpg`) is started or in flight, WebKit cancels it at navigation start
(`DocumentLoader::stopLoadingSubresources`), and the log reset before the `goto` charges it to the next load.
Full evidence: `research/notes/2026/10-21-webkit-cancelled-flake.md`.

Fix: `src/suite.mjs` `leavePage` (goto `about:blank`, then `trackOpen(...).idle()`), check `landing-page-requests-ended`.
Tests: `test/leave.test.mjs` (browser-free). Debug flags in `src/run.mjs`: `--only a,b`, `--repeat n`, `--trace`
(`src/trace.mjs`), `--provoke n` (n uncached image requests before leaving the landing page).

Verified on CI: provoke pair 39599085320 (old code, 180 of 180 loads fail) and 39599115237 (fixed, 0 of 180);
natural 10 green jobs 39599136251 (1200 loads, 0 failures).

Open:
- Second flake: HTTP 502 "preview server not reachable" from `apps/console-api/src/preview/arm-app.ts:88` (3 to 5 of
  1000 loads, old and new code alike); it also reddens this test. Needs a new task (log the upstream error code first).
- `docs/team/tools/preview-e2e.md` lines 79-80 and the new flags are not documented (outside this task's writes).
- Repeat workflow for more evidence: recreate it from git history (commit 87a75cf5) if needed; it has no Lean table row.

Read first: the note, then `packages/e2e-preview/src/suite.mjs` (`trackOpen`, `leavePage`, `runTarget`).
