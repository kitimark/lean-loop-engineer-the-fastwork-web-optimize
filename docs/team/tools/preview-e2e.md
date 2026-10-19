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

## Run it (debug only; results are CI's)

    sh scripts/wt-prep.sh                                   # fresh worktree
    pnpm --filter ./packages/e2e-preview test               # browser-free: evalReport + rig over HTTP (land lane)
    cd packages/e2e-preview
    node src/run.mjs --engine chromium --out /tmp/e2e       # CHROME_PATH or E2E_CHROMIUM_CHANNEL=chrome if no Playwright build
    node src/run.mjs --engine playwright-webkit --out /tmp/e2e

Progress goes to stderr; `out/<engine>.json` holds every check. Exit 1 on any failed check.

## When it runs

- Land lane: only the browser-free tests (`pnpm --filter ./packages/e2e-preview test`), remote tier, selected when a file of
  `PACKAGE_EXTRA_READS["packages/e2e-preview"]` (apps/console-api/src/**, PreviewOwner.lean, console goldens, snapshot) or the
  package changes. Test: `apps/runner/test/preview-e2e-selection.test.ts`.
- Browsers: `.github/workflows/preview-e2e.yml`, a ci/* push whose head commit says `[ci:preview-e2e]`, and only if the
  Lean row (`Fw.Ci.Trigger`) matches a changed file (`scripts/ci-paths.test.mjs`). Never on every push.

## Double import (decision from evidence)

The snapshot boot script imports `/_app/immutable/entry/start.*.js` by a root-absolute string; the proxy answers 302 to the
prefixed URL so relative imports stay inside the preview. Question: is the app evaluated twice (root URL and prefixed URL)?
Measured on both engines, loopback and plain host: each module is evaluated once (`/o`: 11 of 11 files, `/r`: 3 of 3).
Modulepreload links fetch but do not evaluate. Decision: no proxy change; the 302 stays and the suite asserts it.

Negative control: with `isScriptPath` gated on `Sec-Fetch-Dest` again (the original phone bug) the suite fails on the plain
host (its root-module and hydration checks go red) and passes on loopback. Local debug run, not a CI result.

## Accepted limits

- Playwright WebKit stands in for iOS Safari; the user's phone check is the final confirmation.
- `PreviewManager` is a stub; the preview server process is real.
- TS stand-ins: none new. `isScriptPath` (suffix test) remains the existing stand-in in proxy.ts.
