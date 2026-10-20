# Handoff: preview-proxy-direct

Branch `worktree-wf_f702f7d5-89d-1`; CI branch `ci/preview-proxy-direct`: preview-e2e run 39344950785 (head a2f5b592) green, chromium and playwright-webkit jobs both.
Earlier red runs were test artifacts, fixed in the suite: leaving the grant landing page mid-hydration cancelled its imports.

## State
- Lean: `lean/Fw/Console/PreviewArm.lean` (route, armServe, no-leak, same-gate), `PreviewOwner.lean` (`via` removed),
  op `console.previewArm` (reply field `preview`, not `id`). Goldens in `packages/contracts/golden/console/`, generated.
- console-api: `preview/arm-app.ts`, `arm-servers.ts` (listeners per arm), `proxy.ts` (entry 302 to arm origin, `/compare`),
  `manager.ts` (private ports `+1000`), `serve-child.ts`. `rewrite.ts` and its test deleted.
- e2e: `packages/e2e-preview` runs on arm origins; strict 0 rejections / 0 cancels, start() once, client-nav, strict controls.
- console-web unchanged: links `/preview/<id>/r/` hop to the arm origin.

## TS stand-ins
- arm-app / ArmServers glue: I/O only, decisions come from Lean `console.previewArm`.
- e2e rig (tap, host proxy, hop-by-hop strip) is test glue; the `/cancel/i` match is a suite detail.

## Verified
console-api tests, e2e-preview unit tests, Lean check; local Chromium and mac WebKit debug runs (not results).
The local mac WebKit flakes had the same cause (fixed); CI decides.

## Open
- CI results for chromium and playwright-webkit; user phone check.
- Follow-up: unused `cache-policy.ts` variants; iOS Safari not in the suite.

## Read first
`research/notes/2026/10-20-preview-proxy-direct.md`, `docs/team/tools/preview-e2e.md`, `lean/Fw/Console/PreviewArm.lean`.

## Round 2 (land refusal EADDRINUSE 127.0.0.1:35787)
- Cause (INFERRED, not reproduced): the rig drew its ports with a probe that closed at once (`freePort`), so two draws in one start
  could return the same port (e.g. an arm port reused as console/preview port), and `close()` did not await the server or child exits.
- Fix: `packages/e2e-preview/src/rig.mjs` holds all ports of a run open together (`holdPorts`/`runPorts`), arm ports <= 64535 so
  +1000 stays <= 65535, releases just before binding; every server and the preview child are awaited on close; `ArmServers.close` is async.
- Test: `rig.test.mjs` last describe (rig, close, rig, plus an overlapping rig; ports disjoint and free after close).
- CI: land lane run 39347735107 (branch ci/land-preview-proxy-direct-r2, sha 543d7dbb) green; browser suite chromium and webkit ran.
