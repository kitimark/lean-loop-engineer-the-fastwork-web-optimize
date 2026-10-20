# Handoff: preview-e2e-entry

Branch `worktree-wf_b6f1e1ef-717-2`. Follows the reviews of preview-proxy-direct (rounds 1 and 2). CI: preview-e2e run 39354139723 (head b1540c25, chromium and playwright-webkit green), lean run 39354139768 green.
Run 39353226003 (head 2b51a40d) had WebKit red on arm-only control loads (a landing-page image cancelled mid-load); fixed by waiting for it.

## State
- Suite (`packages/e2e-preview/src/suite.mjs`): `<host>/<target>/landing/*` noise checks after the grant landing is idle; targets
  `entry-r` / `entry-o` open `/preview/<id>/r|o/?only=hero&flags=a` (the Builds.tsx shape), check the hop lands on the arm origin with
  the search kept, then all target checks incl. `entry-modules-evaluated-once`; LAN load runs the noise checks (`<engine>/lan/o/*`);
  `same-document-navigation-observed` in both client-nav checks (fails on an empty `log.navs`); control loads block external URLs.
  `noiseChecks(check, log, own, { requireResponses, documentHops })`: `documentHops` lets page-level (document) redirects through, never a
  redirected module or asset.
- Rig (`src/rig.mjs`): `backendOff` is read from the Lean reply of `console.previewAdmit` (`readBackendOff`), exposed as `rig.backendOff`
  (not in `rig.ports`). `runPorts` holds all ports inside a try, releases on failure, retries up to 8 times on EADDRINUSE;
  `startRig` closes what it opened when a start fails. Ports are released together just before the child starts (accepted window).
- Lean: `Preview.lean` owns `backendOff` and `portSpace`; `admit` refuses `portSpace < lo + portN + backendOff` as `noPorts`;
  theorems `admit_refuses_high_base` (the refusal branch) and `admit_backend_in_space` (stated against `admit`'s output).
  Reply field `backendOff` in `console.previewAdmit`; two golden cases (base 64600 refused, 64496 admitted), regenerated.
- `test/signature.test.mjs` renamed `test/attribution.test.mjs`.
- `cache-policy.ts`: nothing to delete. The proxy no longer imports it, but `serve-child.ts` (the real preview server) uses every export
  (`Variants`, `pickEncoding`, `etagOf`, `etagMatches`, `manifestNames`, `cachePolicy`) and `preview-speed.test.ts` covers them.

## Verified
e2e-preview unit tests (14), Lean `check.sh`, local debug runs (not results): Chromium 253/253, WebKit 242/242 (no LAN).
CI decides: preview-e2e workflow on both engines.

## Open
- CI results; user phone check. iOS Safari not in the suite.
- TS stand-ins: none new for decisions (rig and suite are test glue).

## Read first
`docs/team/tools/preview-e2e.md`, `packages/e2e-preview/src/rig.mjs` (`runPorts`), `lean/Fw/Console/Preview.lean` (`admit`).
