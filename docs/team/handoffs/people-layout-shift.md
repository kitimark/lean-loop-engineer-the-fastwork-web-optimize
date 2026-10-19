# people-layout-shift handoff

State: branch worktree-wf_f69637af-21b-1, CI branch ci/people-layout-shift (fix commit 2b37d60a; the later commit adds the note, handoff and a comment fix).
Read first: `research/notes/2026/10-19-people-layout-shift.md` (answer at top, tables, run ids).

Verified (CI, 3 runs after the fix: 39288152363, 39288315945, 39288339116; before: 39279857839):
- Section top, height and document height equal (0 px) at 1920, 1440, 1280, 861, 401, both engines, all frames; layout-shift sums equal.
- One deterministic difference found and fixed: the original's empty `<source>` is a flex item, so the cover-block gap (12 CSS px, 14.64 on screen) sits above the cover at widths above 1030. Port fix: `.coverBlock::before { content: '' }` in `apps/site/src/parts/people.deck/deck.module.css`. After: zero non-motion origins in every load dump, both engines.
- Local tests green: visual-diff (32), apps/site (`pnpm test`, typecheck), `node --test scripts/ci-paths.test.mjs`, apps/runner `land-inputs`, `sh lean/scripts/check.sh` exit 0.

Writes outside the task's graph writes: `lean/Fw/Parts/FootprintData.lean` and `packages/contracts/golden/parts/footprint.gen.json` (regenerated, `node scripts/part-footprint.mjs --write`); `lean/Fw/Ci/Trigger.lean` `cacheWriters` (3 rows for job `people-layout`) and `packages/contracts/golden/ci/triggers.jsonl` (`cd lean && lake test -- --write-ci-trigger-golden`); `deck.module.css`. `apps/runner/src/fw.ts` shows modified in the worktree from before the task; it is not mine and not committed.

Open items:
- WebKit: the port's 'o' collapse starts about one sample after the original's in most repetitions (INFERRED, React commit against Svelte class toggle). Needs a frame-counting probe from the click, then a Lean-proved trigger rule in `people.o/driver.ts`.
- The earlier "1 to 12 px taller" note was not reproduced; cause unknown.
- Port-only `.future { width: max(100%, 320px) }` and a stale Google Sans comment in `people.card/card.module.css`; widths other than the five untested.
- Chromium/WebKit scroll-driven transforms are frame-count driven; CI frames are slow, so cold-pass transform differences are noise (orig-vs-orig as large).

Conventions: dispatch with `gh workflow run visual-diff.yml --ref ci/people-layout-shift -f peoplelayout=true` (artifacts `people-layout-chromium`, `people-layout-playwright-webkit`; `gh run download` needs the worktree as cwd). Analyzer: `node packages/visual-diff/src/cli.mjs people-layout-report --in <dir>`. The probe and analyzer are TS stand-ins (no Lean golden).
