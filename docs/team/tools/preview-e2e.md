# preview-e2e: the preview proxy in a real browser

Package `packages/e2e-preview` (`@fw/e2e-preview`). Playwright-core 1.64.1, Chromium and WebKit, iPhone user agent,
390x844 viewport. It starts its own console-api and preview on spare ports; it never touches the lead's console (8787/8788),
the keychain, the owner link or the owner passphrase.

## What it runs

- Rig (`src/rig.mjs`): the console-api server files imported by file URL (app, store, owner, grants, login, preview-app), a
  stub `PreviewManager`, and one real preview server process (`serve-child.ts`) with two arms: `/o` = the unmodified
  `snapshot/site`, `/r` = `fixture/site` (a small built rewrite: stylesheet, font, image, boot script that `import()`s
  root-absolute `/_app/...` modules). A forward proxy maps `fw-phone.test` to loopback so the browser sees a plain-HTTP host
  that is not potentially trustworthy (the phone's case); the tap in front of `/_app/*.js` counts module evaluations.
- Access: a grant link (`POST /api/preview/grant`, then `/__grant?t=`), and LAN-mode passphrase login (test passphrase, no
  keychain) on the LAN address when the machine has one.
- Per target `/r/`, `/o/`, `/compare` and per host (loopback, plain host): document 200; every same-origin request 2xx/3xx
  (accepted: `/cdn-cgi/rum`); no page errors; fonts loaded; 0 broken images; each entry module evaluated exactly once
  (hydration once); `Sec-Fetch-Dest` present on loopback and absent on the plain host; root-absolute module requests
  answered 302 below the preview prefix. External hosts are aborted.
- `/o` hydration: the tap adds a counter to SvelteKit's client `start()` (`__fwStarts`); the check requires exactly 1 (the
  fixture arm counts its own `start()` the same way).
- Controls (3 loads each, original arm, no pass/fail on the page): `raw` (raw preview port), `tap-only` (raw server behind the
  tap, no proxy), `proxy-only` (the console proxy in front of the raw server, no tap; `rig.useTap(false)`). The check
  `<engine>/control/attribution` names the arm that shows the WebKit signature below.

## Run it (debug only; results are CI's)

    sh scripts/wt-prep.sh                                   # fresh worktree
    pnpm --filter ./packages/e2e-preview test               # browser-free: evalReport + rig over HTTP (land lane)
    cd packages/e2e-preview
    node src/run.mjs --engine chromium --out /tmp/e2e       # CHROME_PATH or E2E_CHROMIUM_CHANNEL=chrome if no Playwright build
    node src/run.mjs --engine playwright-webkit --out /tmp/e2e

Progress goes to stderr; `out/<engine>.json` holds every check. Exit 1 on any failed check.

## When it runs

- Land lane (`.github/workflows/land.yml`), remote tier: when land selects `packages/e2e-preview` (its package, or a file of
  `PACKAGE_EXTRA_READS["packages/e2e-preview"]`: `apps/console-api/src/**`, `packages/contracts/src/**` and `package.json`,
  console goldens, the snapshot; or the fwcore binary, which console-api decides through) it runs the browser-free tests and
  then the browser suite on both engines (`node src/run.mjs --engine chromium`, `--engine playwright-webkit`; artifact
  `land-preview-e2e`). The step condition is the line `LANE browser=true|false` of `fw checks --tier remote`, which is Lean
  `Fw.Console.LandTier.browserRuns` (theorems: runs iff the e2e check is selected; the check is in the remote tier; the remote
  picks decide as the whole selection does). So a land that touches the proxy checks real browsers. Tests:
  `apps/runner/test/preview-e2e-selection.test.ts` (both directions), `lean/Fw/Console/LandTier.lean`.
- Development: `.github/workflows/preview-e2e.yml`, a ci/* push whose head commit says `[ci:preview-e2e]`, and only if the
  Lean row (`Fw.Ci.Trigger`: `@fwcore`, `apps/console-api/src/**`, `packages/contracts/src/**`, ...) matches a changed file
  (`scripts/ci-paths.test.mjs`). Never on every push.

## Double import (decision from evidence)

The snapshot boot script imports `/_app/immutable/entry/start.*.js` by a root-absolute string; the proxy answers 302 to the
prefixed URL so relative imports stay inside the preview. Question: is the app evaluated twice (root URL and prefixed URL)?
Measured on both engines, loopback and plain host: each module is evaluated once (`/o`: 11 of 11 files, `/r`: 3 of 3).
Modulepreload links fetch but do not evaluate. Decision: no proxy change; the 302 stays and the suite asserts it.

Negative control: with `isScriptPath` gated on `Sec-Fetch-Dest` again (the original phone bug) the suite fails on the plain
host (its root-module and hydration checks go red) and passes on loopback. Local debug run, not a CI result.

## Accepted limits

- Playwright WebKit stands in for iOS Safari; the user's phone check is the final confirmation.
- Playwright WebKit on Linux cancels the preloads of other routes that the app builds with root-absolute `/_app/...` URLs:
  the proxy answers them 302 to the prefixed URL while the same file is imported by its prefixed URL, and WebKit cancels the
  duplicate ("Load request cancelled"). Per original-arm load the page logs exactly 3 unhandled rejections (two failed module
  imports and one CSS preload of an `/_app/` asset). Every server answer is 2xx/3xx, the entry modules still evaluate once,
  `start()` runs once, fonts and images are fine. Chromium shows none of it.
  Attribution (CI run 39335496085, head 0301c0dd; also 39334939255 and 39333909578): on WebKit the `raw` and `tap-only`
  controls show 0 rejections and 0 cancels in 3 of 3 loads each; `proxy-only` shows 3 rejections and 13-16 cancels in 3 of 3.
  So the console proxy path (the 302 of root-absolute duplicates) causes it; the engine alone and the tap (with its
  `cache-control: no-store`) do not, so the tap keeps its headers. Chromium: all three controls clean.
  The suite asserts the signature exactly (`cancelSignature`, `test/signature.test.mjs`): 3 rejections of the two named kinds,
  the CSS preload on an `/_app/` asset whose root request the preview port answered; when Playwright reports the cancelled
  requests, exactly 13, all `/_app/`, each with a root-URL 302 (script) or an answered root request (stylesheet) in `rig.seen`;
  any other failed same-origin request fails `page-errors`. Limit found on CI: Playwright WebKit on Linux reports those cancels
  in only some loads (13 or none for the same page: runs 39333909578 and 39334939255), so the restored "a cancelled request was
  reported" condition cannot be required; with none reported the exact rejection shape and the answered root requests carry
  the decision. A real WebKit-only module failure with another message or another asset still fails. Not fixed in the proxy:
  rewriting the app's JavaScript is out of the proxy's contract. `--no-route` drops the external-request blocking (diagnosis).
- WebKit on macOS may stall on the LAN-address page load (local network permission); use `--no-lan` there. CI has no such prompt.
- `PreviewManager` is a stub; the preview server process is real.
- TS stand-ins: none new. `isScriptPath` (suffix test) remains the existing stand-in in proxy.ts.
