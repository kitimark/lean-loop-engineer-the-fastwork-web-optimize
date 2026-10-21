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
- The real entry path: after the grant link is redeemed and the landing page is idle, `<host>/<target>/landing/*` runs the same
  noise checks (0 rejections, 0 cancelled or failed same-origin requests; the page-level hops of the entry are allowed, a
  redirected module or asset is not). Targets `entry-r` and `entry-o` open `<preview port>/preview/<id>/r|o/?only=hero&flags=a`
  (the Builds.tsx link shape), require the hop to land on the arm origin with the search kept, and run all target checks
  including `entry-modules-evaluated-once`. Target `entry-review-flag` opens the flag arm of a review card's Preview button
  (`/preview/<id>/r/?fw=nav:earn-no-transition`, review-preview-devices) the same way, on every host including the plain-HTTP
  phone host, and requires the flag query on the arm origin.
- LAN lane: the one load on the LAN address (`<engine>/lan/o/*`) also runs the noise checks.
- `start()` once: the tap adds a counter to SvelteKit's client `start()` (`__fwStarts`); the check requires exactly 1.
- Client-side navigation (`client-nav-r`, `client-nav-o`): click the home link, then a dynamic `import()` of a route node;
  still 0 rejections, 0 cancels, no document reload, and `same-document-navigation-observed` (the browser reported a navigation
  of the main frame; an empty list fails). The snapshot has one route, so the original's navigation is its home link
  (`navs: main /`); the fixture arm carries a second route (`main /about`).
- Controls (3 loads each, original arm): `raw` (raw preview port), `tap-only` (raw server behind the tap), `arm-only` (the
  arm app in front of the raw server, no tap). `<engine>/control/attribution` fails if any control load shows a rejection or a
  cancel (no accepted noise). Control loads block external URLs like the targets.

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
  then the browser suite, one engine per leg (legs `chromium` and `playwright-webkit`, `node src/run.mjs --engine <leg>`; artifacts
  `land-preview-e2e-chromium` and `land-preview-e2e-playwright-webkit`). The step condition is the line
  `LANE leg=<leg> engine=true|false checks=<n>` of `fw checks --tier remote --leg <leg>`, which is Lean
  `Fw.Console.LandLegs.engineRuns` over `Fw.Console.LandTier.browserRuns` (theorems: an engine leg runs iff the e2e check is selected;
  the check is in the remote tier; the remote picks decide as the whole selection does; a suites leg never runs it). Tests: `apps/runner/test/preview-e2e-selection.test.ts` (both directions),
  `lean/Fw/Console/LandTier.lean`.
- Development: `.github/workflows/preview-e2e.yml`, a ci/* push whose head commit says `[ci:preview-e2e]`, and only if the
  Lean row (`Fw.Ci.Trigger`: `@fwcore`, `apps/console-api/src/**`, `packages/contracts/src/**`, ...) matches a changed file
  (`scripts/ci-paths.test.mjs`). Never on every push.

## Debug flags of `src/run.mjs`

Debug runs repeat targets on loopback on one engine; they are for CI branches (a temporary `ci/<task>` workflow), not for the land lane.

| flag | meaning |
|---|---|
| `--only a,b` | run just these target ids (`r`, `o`, `compare`, `entry-r`, `entry-o`, `entry-review-flag`) on the loopback host |
| `--repeat n` | with `--only` (or alone): n loads of each selected target; the check ids carry `#<load>` |
| `--trace` | also write `out/trace-<engine>.json`: the timeline of each failed load and 2 passing ones (`src/trace.mjs`) |
| `--provoke n` | start n uncached image requests on the landing page just before it is left (makes the landing-page cancel deterministic) |

An error of the arm app's upstream request is logged on stderr as `preview-502 {"code","syscall","msg","reused","idleMs","path"}`
(`arm-app.ts`); a run with `2>err.txt` keeps it.

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
- The suite waits for the grant landing page to finish hydrating, then leaves it through `about:blank` (`leavePage`) and waits
  until every request the page asked for has ended (check `landing-page-requests-ended`); only then is the log reset and the next
  load observed. A plain `goto` from a page with a lazy image in flight makes the browser cancel that request (WebKit
  `DocumentLoader::stopLoadingSubresources`) and the cancel lands in the next load's checks: not a server fault, see
  `research/notes/2026/10-21-webkit-cancelled-flake.md`. The control loads leave their landing page the same way; a request still
  open is counted as a cancelled one for that control (`openFailure`).
- The tap between an arm app and the preview server is a Node server with the default 5 s keep-alive; it passes no hop-by-hop
  header (`Connection`, `Keep-Alive`) of the preview server's reply on, so the arm app's Agent reads the tap's true hint. A
  copied `Keep-Alive: timeout=65` once made the Agent reuse a socket the tap had just closed: HTTP 502 in about 3 of 1000 loads
  (`research/notes/2026/10-2x-preview-502-flake.md`).
- Ports: `startRig` holds every port of a run together (up to 8 attempts) and releases them together just before the preview child
  starts; a port another process takes in that window fails its bind loudly (accepted). A start that fails half way closes
  what it opened. The private-port offset is Lean's `Fw.Console.Preview.backendOff`, read from the `console.previewAdmit`
  reply (`rig.backendOff`); `admit` refuses a `portBase` with `portBase + portN + backendOff > 65536` as `noPorts`
  (`admit_refuses_high_base`, `admit_backend_in_space`).
- `PreviewManager` is a stub; the preview server process is real.
- TS stand-ins: none new for decisions. The arm app and listeners (`arm-app.ts`, `arm-servers.ts`) are I/O glue over Lean's
  `console.previewArm`.
