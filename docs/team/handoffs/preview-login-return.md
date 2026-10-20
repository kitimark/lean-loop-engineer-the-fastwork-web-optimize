# preview-login-return handoff

State: branch `worktree-wf_30371784-468-1` at 66c51e34 (round 2, accepted).

Built
- Lean `lean/Fw/Console/PreviewReturn.lean`: `accepts` (allowlist: live arm port, or live `/preview/<id>/` on the preview port, never the
  console port; `pathOk`, `hostOk`, `nonceOk`), `redirect`, `landing`; a theorem per branch, `landing_sound` and `landing_url_shape`
  (no open redirect). Wire op `console.loginReturn` (`Fw/Wire/Console.lean`), 31 golden cases in `Fw/Ops/Golden.lean`
  (`packages/contracts/golden/console/console.loginReturn.jsonl`, regenerate with `cd lean && lake env lean --run scripts/OpsGolden.lean`).
- console-api `src/preview/return.ts` (`ReturnStore`: nonce map, calls Lean), wired in `arm-app.ts`, `preview-app.ts`, `gate.ts`
  (login page `?r=`, login body `r`, reply `next`), `login.ts` (form `data-r`), `owner.ts` (`consolePort`), `main.ts`, `app.ts`.
- console-web `App.tsx` `landingOf` (`/?tab=builds&note=stopped`).
- Docs: `docs/team/tools/console.md` ("Login return link").

Verified: console-api `pnpm test` 507/507 (`test/login-return.test.ts` 11), console-web tests, Lean check.

Open items
- TS stand-ins: none for decisions. The nonce map, hostName split and the HTTP glue are I/O.
- A `//host/path` request target is read by the server as that path on this arm; the held link is that path (no foreign host).
- The console-port redirect (HTML request to a gated console path) still carries no return.
- Arm ports change on restart, so old links stay dead (accepted).

Read first: `lean/Fw/Console/PreviewReturn.lean`, then `apps/console-api/src/preview/return.ts`.

Round 2: `redirect`/`landing` take `hosts` (console host names from `OwnerAuth.hostNames`); `redirect` also takes `get` and `heldCount`
(HEAD/non-GET deny, full store `.login false`); theorems `redirect_not_get`, `redirect_foreign_host`, `redirect_full`,
`landing_foreign_host`; `landing_sound`/`landing_url_shape` conclude `host ∈ hosts`. TS uses `location` unchanged; its map eviction is housekeeping.
- Follow-up: `return.ts` TTL_MS copies Lean `ttl` as a literal and eviction runs before the Lean call; take it from Lean (generated constant or a golden-pinned test).
