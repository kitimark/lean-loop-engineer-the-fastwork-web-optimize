# console-builds-tab handoff

State: branch worktree-wf_a10164f7-fb5-1, round 2 (review r1 findings 1-4 applied; commit named in the report).

What exists
- Lean `lean/Fw/Console/Builds.lean`: port rows (landed port-*/fix-* tasks, newest first, one per task: at its newest `Task:` trailer commit, else at its evidence land commit), flag/preset rows with
  status (v2-proved, baseline, not in v2-proved, out of v2-proved (C3)), preview target and slot per row, `enumerate`, `picker`, `choose`.
  Ops `console.builds` and `console.buildsPicker` in `lean/Fw/Wire/Console.lean`; goldens in `packages/contracts/golden/console/`.
- API: `GET /api/builds` (read-only rows); `POST /api/previews {build: <row id>}` (row ids `port:<task>`, `flag:<part:variant>`,
  `preset:<name>`). The server recomputes rows in Lean; the body never carries a sha or a search. Facts gathering: `src/preview/builds.ts` (`evidenceLands` resolves each task's first evidence commit to its land commit on main's first-parent line by binary search; `readPresets` resolves `extends`).
- Manager: `start(slot, proof, at?)` and `Entry.search`; the compare page (`serve-child.ts`) has a picker of exactly the build's
  prerendered searches (default, presets, flags) and opens at the row's search.
- Web: `apps/console-web/src/Builds.tsx` and the Builds tab in `App.tsx`.

Verified
- console-api and console-web tests, typecheck, vite build; Lean check.sh at the final commit.
- Scratch console on its own ports with an in-process owner session and headless Chrome: both lists render (6 ports, 50 optimize rows),
  one Preview from each list opens a compare page; the picker lists 51 searches, equal to the Lean `enumerate`; switching it changes
  the rewrite arm. Real `apps/site` aot build: `configs.json` has 51 keys, equal to the Lean list.

TS stand-ins: `src/preview/picker.ts` (twin of `picker`/`choose`, checked against `console.buildsPicker.jsonl`; serve-child has no fwcore).
Facts reading (`readFlags`, `readPresets`, `mainLog`) is I/O glue.

Decisions / limits
- Faithful variants are listed with status "baseline". hero.countdown:strip is forced "out of v2-proved (C3)" in Lean until
  c3-preset-update regenerates the preset (theorem `c3_never_proved`; then drop the override).
- Not offered: multi-flag combinations that are not prerendered. Old land commits may fail to build; shown as "failed".
- Preview slot of an optimize row is `opt-<kind>-<name>`; a port row's is `land-<task>` (Lean `landSlot`), apart from the task-detail Preview whose slot is the task id; Builds.tsx also matches the target sha.

Round 2 (verified headless: scratch console, own ports and owner session, real repo facts, stubbed build hook)
- Rows on the real repo: 28 port/fix rows (was 6), 50 optimize rows. port-hero and fix-nav at c4b57a2 (evidence landing; 17 rows share it).
- Preview from the port list (land-port-hero) and from the optimize list (opt-flag-engine-scroll-batched at ?fw=...) open compare pages;
  a task-detail Preview of fix-nav (slot fix-nav) leaves its Builds row (slot land-fix-nav) without a state.
- Lean theorems (Builds.lean): portRows_trailer_land and portRows_evidence_land (one per branch), portRows_land_commit, portRows_newest (row is the
  task's newest trailer landing), portRows_complete_trailer / _evidence, nodup, sorted, landSlot. Goldens: evidence-only, trailer wins, unresolvable, extends.
- TS stand-ins: `picker.ts`; `readPresets` extends resolution (mirrors site `presetEntries`; Lean takes the resolved fw); `evidenceLands` sha resolution is I/O glue.
- Tasks left without a land fact (no trailer, no evidence commit): port-parts (evidence names no commit), fix-proofs (no evidence). Not shown.

Follow-ups
- opt-main (finding 5): optimize rows still build per row (one build per row); share one build per main sha and switch the search in the compare picker.
- A start from a row whose slot already has a live preview is refused by the manager (one per slot); 2 previews at once is the manager's limit.
Read first: `lean/Fw/Console/Builds.lean`, `apps/console-api/test/builds.test.ts`.
