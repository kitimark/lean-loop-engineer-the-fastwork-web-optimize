# Handoff: preview-proxy-direct

Branch `worktree-wf_f702f7d5-89d-1`; CI branch `ci/preview-proxy-direct` (run ids: see below once filled by the lead).

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
Local mac WebKit flaked rarely (different check each run); Linux CI decides.

## Open
- CI results for chromium and playwright-webkit; user phone check.
- Follow-up: unused `cache-policy.ts` variants; iOS Safari not in the suite.

## Read first
`research/notes/2026/10-20-preview-proxy-direct.md`, `docs/team/tools/preview-e2e.md`, `lean/Fw/Console/PreviewArm.lean`.
