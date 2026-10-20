# console-preview-search handoff

State: branch `worktree-wf_8bcf6c8c-093-1`; see the report for the final commit.

Built
- Lean `lean/Fw/Console/BuildsOpen.lean`: `validate` (charset, length, then resolve.ts rules), `decide` (reuse/wait/rebuild/start),
  `fullUrl` (LAN or loopback), `openSearch`/`openRow`, a theorem per branch.
- Wire ops `console.buildsSearch`, `console.buildsOpen` in `lean/Fw/Wire/Console.lean`; golden cases in `lean/Fw/Ops/Golden.lean`
  (regenerate: `cd lean && lake env lean --run scripts/OpsGolden.lean`, check with `--check`).
- console-api `POST /api/builds/open` (`src/preview/routes.ts`), `readRegistry` (`builds.ts`), `OwnerAuth.lanPreviewAddr`.
- console-web `Builds.tsx` (Open, Open compare, search box, recent, Copy link) and `buildsOpen.ts` (localStorage, clipboard).
- Docs: `docs/team/tools/console.md`, section "Builds tab".

Verified: console-api tests (`test/builds.test.ts`, `test/builds-search.test.ts`), console-web tests and build, Lean golden agreement
with `apps/site/src/registry/resolve.ts`. After merging, rebuild fwcore (`sh scripts/fwcore-build.sh`) so the new ops exist.

Open items (follow-ups)
- resolve.ts prototype-key quirk (`in`, `presets[name]`): `constructor` passes there, Lean refuses it.
- Lean charset/length cap is stricter than resolve.ts; unknown parameters are dropped from the canonical search.
- No browser test of the click flow (pop-up, polling); the route and Lean pieces are tested.

Read first: `lean/Fw/Console/BuildsOpen.lean`, then `apps/console-api/src/preview/routes.ts` (`/api/builds/open`).
