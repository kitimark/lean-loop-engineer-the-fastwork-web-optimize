# console-builds-tab handoff

State: branch worktree-wf_a10164f7-fb5-1 (commits: Lean module + goldens, API + picker, web tab).

What exists
- Lean `lean/Fw/Console/Builds.lean`: port rows (landed port-*/fix-* from main's log, newest first, one per task), flag/preset rows with
  status (v2-proved, baseline, not in v2-proved, out of v2-proved (C3)), preview target and slot per row, `enumerate`, `picker`, `choose`.
  Ops `console.builds` and `console.buildsPicker` in `lean/Fw/Wire/Console.lean`; goldens in `packages/contracts/golden/console/`.
- API: `GET /api/builds` (read-only rows); `POST /api/previews {build: <row id>}` (row ids `port:<task>`, `flag:<part:variant>`,
  `preset:<name>`). The server recomputes rows in Lean; the body never carries a sha or a search. Facts gathering: `src/preview/builds.ts`.
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
- Preview slot of an optimize row is `opt-<kind>-<name>`; port rows use the task id (shared with the task detail Preview).

Open: a start from a build row of a task that already has a live preview in the same slot is refused by the manager (one per slot).
Read first: `lean/Fw/Console/Builds.lean`, `apps/console-api/test/builds.test.ts`.
