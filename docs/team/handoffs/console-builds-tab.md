# console-builds-tab handoff

State: branch worktree-wf_a10164f7-fb5-1 at e3502863 plus the lead's r2 fixes (evidence loop break, this file); review r2 accepted.

What exists
- Lean `lean/Fw/Console/Builds.lean`: port rows (landed port-*/fix-* tasks, newest first, one per task, at its newest `Task:` trailer
  commit, else at its evidence land commit), flag/preset rows with status (v2-proved, baseline, not in v2-proved, out of v2-proved (C3)),
  preview target and slot per row, `enumerate`, `picker`, `choose`. Ops `console.builds`, `console.buildsPicker` (Wire/Console.lean);
  goldens in `packages/contracts/golden/console/` (incl. evidence-only, trailer wins, unresolvable, extends).
- Theorems: portRows_trailer_land, portRows_evidence_land, portRows_land_commit, portRows_newest, portRows_complete_trailer/_evidence,
  nodup, sorted, landSlot, c3_never_proved.
- API: `GET /api/builds`; `POST /api/previews {build: <row id>}` (`port:<task>`, `flag:<part:variant>`, `preset:<name>`); the server
  recomputes rows in Lean, the body never carries a sha or search. Facts: `src/preview/builds.ts` (`evidenceLands`: first evidence
  token on main's first-parent line, by binary search; `readPresets` resolves `extends`; `mainLog`).
- Manager `start(slot, proof, at?)`, `Entry.search`; compare page (`serve-child.ts`) picker = the build's prerendered searches.
- Web: `apps/console-web/src/Builds.tsx`, Builds tab in `App.tsx`.

Verified (scratch console, own ports and owner session, headless Chrome)
- 28 port/fix rows, 50 optimize rows; port-hero and fix-nav at c4b57a2; picker lists 51 searches = Lean `enumerate` = aot configs.json.
- Preview from each list opens a compare page; a task-detail Preview (slot = task id) leaves the Builds row (slot land-<task>) unmarked.
- Lean check.sh green; console-api 432 tests, console-web 11 tests.

TS stand-ins: `picker.ts` (golden-checked), `readPresets` extends resolution (mirrors site `presetEntries`).
Not shown (no land fact): port-parts (evidence names no commit), fix-proofs (no evidence).

Follow-ups
- opt-main: optimize rows build once per row; share one build per main sha, switch the search in the picker.
- builds-log-window: a land commit older than mainLog's 2000 commits is dropped silently; put it in `missing` (latent, 652 today).
- builds-c3-override: c3-preset-update has landed; drop the hero.countdown:strip override and `c3_never_proved`.
- test for an evidence list with an off-main commit before an on-main one (loop now breaks only on a resolved land).
Read first: `lean/Fw/Console/Builds.lean`, `apps/console-api/test/builds.test.ts`.
