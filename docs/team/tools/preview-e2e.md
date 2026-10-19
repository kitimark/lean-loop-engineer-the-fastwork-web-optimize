# preview-e2e: the preview in a real browser

Package `packages/e2e-preview` (`@fw/e2e-preview`). Playwright-core 1.64.1, Chromium and WebKit, iPhone user agent,
390x844 viewport. It starts its own console-api and preview on spare ports; it never touches the lead's console (8787/8788),
the keychain, the owner link or the owner passphrase.

## What it runs

- Rig (`src/rig.mjs`): the console-api server files imported by file URL (app, store, owner, grants, login, preview-app, arm
  app and listeners), a stub `PreviewManager`, and one real preview server process (`serve-child.ts`) with two arms: `o` = the
  unmodified `snapshot/site`, `r` = `fixture/site` (a small built rewrite: stylesheet, font, image, boot script that `import()`s
  root-absolute `/_app/...` modules, and a client-side route `about`). Each arm has its own origin (own port, Lean
  `Fw.Console.PreviewArm`): a root-absolute request is answered in place by the arm whose port received it. No redirect, no
  Referer. The preview port keeps the entry paths (`/preview/<id>/r/`, `/o/`: a page-level 302 to the arm origin, query kept)
  and `/compare`. A forward proxy maps `fw-phone.test` to loopback so the browser sees a plain-HTTP host that is not
  potentially trustworthy (the phone's case); the tap between an arm and the server counts module evaluations.
- Access: a grant link (`POST /api/preview/grant`, then `/__grant?t=`; cookies ignore ports, so one grant opens every arm
  origin), and LAN-mode passphrase login (test passphrase, no keychain) on the LAN address when the machine has one.
- Per target `r` and `o` (document on the arm origin) and `compare` (preview port), per host (loopback, plain host, LAN when
  present): document 200; every same-origin request 2xx/3xx (accepted: `/cdn-cgi/rum`); no page errors; fonts loaded; 0 broken
  images; each entry module evaluated exactly once; `Sec-Fetch-Dest` present on loopback and absent on the plain host.
  Strict: 0 unhandled rejections and 0 cancelled same-origin requests (any failed request matching `/cancel/i`; the text
  differs by engine). External hosts are aborted.
- `start()` once: the tap adds a counter to SvelteKit's client `start()` (`__fwStarts`); the check requires exactly 1.
- Client-side navigation (`client-nav-r`, `client-nav-o`): click the home link, then a dynamic `import()` of a route node;
  still 0 rejections, 0 cancels, no document reload. The snapshot has one route, so the original's check is its home link; the
  fixture arm carries a second route.
- Controls (3 loads each, original arm): `raw` (raw preview port), `tap-only` (raw server behind the tap), `arm-only` (the
  arm app in front of the raw server, no tap). `<engine>/control/attribution` fails if any control load shows a rejection or a
  cancel (no accepted noise).

## Run it (debug only; results are CI's)

    sh scripts/wt-prep.sh                                   # fresh worktree
    pnpm --filter ./packages/e2e-preview test               # browser-free: evalReport, attribution, rig over HTTP (land lane)
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
  picks decide as the whole selection does). Tests: `apps/runner/test/preview-e2e-selection.test.ts` (both directions),
  `lean/Fw/Console/LandTier.lean`.
- Development: `.github/workflows/preview-e2e.yml`, a ci/* push whose head commit says `[ci:preview-e2e]`, and only if the
  Lean row (`Fw.Ci.Trigger`: `@fwcore`, `apps/console-api/src/**`, `packages/contracts/src/**`, ...) matches a changed file
  (`scripts/ci-paths.test.mjs`). Never on every push.

## Why one origin per arm (replaces the 302 and the double-import question)

The snapshot boot script imports `/_app/immutable/entry/start.*.js` by a root-absolute string. The old proxy answered that
with a 302 to the prefixed URL; WebKit then cancelled duplicate loads and logged module-import rejections (CI evidence: the
`proxy-only` control showed 3 rejections and 13-16 cancels per load while `raw` and `tap-only` were clean). With an origin per
arm the root path is the arm's own path, so there is nothing to redirect. Lean (`PreviewArm.lean`) decides the mapping from the
local port to the arm and proves that no request reaches the other arm's files (no leak) and that the gate decision equals the
old per-origin one (`console.previewArm`, goldens in `packages/contracts/golden/console/`).

## Accepted limits

- Playwright WebKit stands in for iOS Safari; the user's phone check is the final confirmation. iOS Safari is not in the suite.
- WebKit on macOS may stall on the LAN-address page load (local network permission); use `--no-lan` there. CI has no such prompt.
  Local macOS WebKit also showed a rare lazy-image cancel on a compare-page frame while scrolling; CI (Linux) is the arbiter.
- `PreviewManager` is a stub; the preview server process is real.
- TS stand-ins: none new for decisions. The arm app and listeners (`arm-app.ts`, `arm-servers.ts`) are I/O glue over Lean's
  `console.previewArm`.
