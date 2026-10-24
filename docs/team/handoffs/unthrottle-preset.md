# unthrottle-preset handoff

Branch: worktree-wf_582d1cc2-be7-1 (CI branch ci/unthrottle-preset). Worktree: .claude/worktrees/wf_582d1cc2-be7-1 (under the repo root)
CI measured sha: c113d5eca (text final). Later commits: ledger, note, report, handoff only.

CI runs (ci/unthrottle-preset), all at c113d5eca:
- 40078755889 trajectory-probe push (fw=engine.scroll:unthrottle, both): success; Chromium hero+morph pass, Linux WebKit hero pass
- 40080296257 trajectory-probe dispatch 2 of 3 (adds Mac leg): Mac hero pass, Mac morph no verdict: coverage (widths 641 and 1280, where the element is inactive)
- 40078755847 toolbar-throttle push: success, pooled verdict lifted for unthrottle (0 band runs in 6330 exit frames vs 19 in 1600 rewrite, one usable rewrite pass)
- 40078781031 chromium-counts dispatch 1 of 3: absolute plus guard, +0 layers in 575/573/572 of 575 frames; decision absolute
- 40078755885 lean push: success
- 40083527306 breakpoint-gate dispatch 3 of 3 (fw=engine.scroll:unthrottle, both engines; v2-proved is empty so --fw): success, failing-items table empty on both engines

Verified: Lean EngineScrollUnthrottle.lean (position, guard theorems, relevantAnimations named); check.sh green at d8b937498; ledger row proved;
Gen.run: flag is not a member (WebKit morph cell pending; no flag has passed it).
Final: check.sh green at the final Lean commit (slot run), site tests (6567) and typecheck, measure-webkit tests, ci-paths test pass; main merged.
Dry land without --allow: `VERDICT scope unthrottle-preset` (four files outside the graph writes: toolbar-throttle.yml, measure-webkit throttle cli.mjs/report.mjs/test). The lead adds them to the task writes or lands with --allow.
Review ready: returnToBuilder only for the undelivered item (v2-proved membership) and the scope dry verdict, both named above.
Open: (1) WebKit morph trajectory cell: Mac morph gives no verdict for any flag, so v2-proved stays empty; a follow-up must decide that cell (vacuity of a flag proved inactive at the probe's fine-pointer widths is one option); (2) phone pass of the shipped text; (3) power cost of leaving the throttle. Power cost of leaving the throttle not measured.
Writes outside the task: .github/workflows/toolbar-throttle.yml, packages/measure-webkit/src/throttle/{cli,report}.mjs, packages/measure-webkit/test/throttle-report.test.mjs.
Read first: research/notes/2026/10-2x-throttle-lift-ship.md section 6.

Continue round (graph r423): main merged; v2-proved membership is followUp (task webkit-morph-cell); four lane files are now in the task writes.
Reran: apps/runner tests (3437 pass), lean check.sh green. No new CI dispatch.
