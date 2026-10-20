# lego-composer handoff

State: branch `worktree-wf_f9068550-3cc-1`, commit b68a3a9a plus review follow-ups. Not landed; the lead lands it.

Built: Lean `Fw.Console.Compose` (classes, page order, decide, canonical search, theorems, `#guard` fixtures), wire
`Fw.Wire.Compose`, op `console.compose` in `Wire/Console.lean`, goldens `console.compose.jsonl` (via `Fw/Ops/Golden.lean`),
console-api `GET /api/compose` and `/api/compose/decision` (`src/preview/compose.ts`), console-web tab Compose
(`Compose.tsx`, `composeOpen.ts`, `App.tsx`: also `?tab=compose` and a wrapping nav for 390 px).
Round 2 fixes: stale decision (`Compose.tsx` tags replies with their query, `newestWins` drops older, `answersNow` marks stale; bar says "updating…", Open, Open compare, Copy link off); Copy link is its own step (`copyKnown`), failure shows "Copy failed: long-press the link below", link is `select-all`; new class `ledger-proved` (`classOf_ledgerProved`), `measured` says "not in v2-proved yet (the gate has not admitted it)".
`explicitKeys` extras for morph.columns:hidden-pause (rows 19, 41), morph.countdown:hidden-pause (row 43); explicit rule needs no part name; only unrated variant was morph.columns:hidden-pause; `matchRow` rules in compose.md.
`implReasons`: a preset entry with a non-default impl (default `mui`) is refused in the preset list; goldens `cmp2` cases.

Verified: `sh lean/scripts/check.sh` green (axiom check 0 failing); console-api `pnpm test` 609 pass incl. typecheck;
console-web `vitest` 38 pass + tsc; `node --test scripts/ci-paths.test.mjs` 49 pass; runner `land-inputs` 55 pass.
No new reads were needed for those tests. The web test is static render plus pure helpers (no DOM library in the repo).

Not verified: a real iPhone Safari run (layout is by classes and a render test only); a live click-through on the lead's console.

Open items:
- Writes outside the listed ones: `lean/Fw/Ops/Golden.lean` (the `cmp` fixtures and cases), `apps/console-api/src/preview/routes.ts`
  (one mount line), `apps/console-web/src/App.tsx` (tab, nav wrap).
- TS stand-ins: ledger text attached by index, run-id regex, the open polling loop (copy of Builds' loop in `composeOpen.ts`).
- Rebuild `lake build fwcore` after Lean edits or the api golden tests fail on a stale binary.
- The look-change list is read from `provenance.limit` text starting `look change`.
- Class of a variant depends on text matching of ledger candidates (flag first); rows that match nothing show as "other findings".
- `v2-proved.json` has an empty `fw` on this branch, so no variant is classed `proved` on the real registry yet.

Read first: `docs/team/tools/compose.md`, then `lean/Fw/Console/Compose.lean`, `apps/console-api/test/compose.test.ts`.
Conventions: never hand-edit the golden; regenerate with `cd lean && lake build Fw.Ops.Golden && lake env lean --run scripts/OpsGolden.lean`.
