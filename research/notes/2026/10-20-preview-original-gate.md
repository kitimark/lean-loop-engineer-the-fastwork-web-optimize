# Why the original arm failed on the phone (preview-inspect)

Status: cause CONFIRMED by engine source and by reproduction in Chromium; the fix verified in Chromium and Playwright WebKit. The user's own
phone check is the final confirmation (lead relays it).

## Symptom
The rewrite arm `/preview/<id>/r/` worked on the phone, the original arm `/preview/<id>/o/` did not, even after
preview-original-missing (55a42117). The lead's loopback harness, without the gate, rendered both.

## Cause (CONFIRMED)
`mountPreviewProxy` moves a root-absolute script request under the preview prefix with a 302, so a module's relative imports
stay inside the preview. It decided this from `Sec-Fetch-Dest: script`. Browsers send `Sec-Fetch-*` only to secure origins
(HTTPS or loopback). The phone reaches `http://<lan-address>:<previewPort>`, which is neither, so the header never came.
The proxy then served `/_app/immutable/entry/start.*.js` in place (200, read below the preview by its Referer). The module's base URL became
`/_app/...`, its relative chunk imports resolved outside the preview and returned 404, and the page failed with
"Failed to fetch dynamically imported module": no hydration. Over `127.0.0.1` (a secure context) the header was sent, which is
why every loopback check passed.

Engine source (CONFIRMED): Chromium `services/network/sec_header_helpers.cc:292`@f842f52 returns before setting fetch metadata
when `!IsUrlPotentiallyTrustworthy(target_url)`. WebKit `Source/WebCore/loader/cache/CachedResourceLoader.cpp:702-708`@862f17d
(`updateRequestFetchMetadataHeaders`) returns when `!requestOrigin->isPotentiallyTrustworthy()`, before it sets Sec-Fetch-Dest
(line 717). Shas are the pins in `refs/upstream/sources.lock.yaml`; I read both files at those shas.

Repro (Chromium, iPhone UA, 390x844, LAN host, valid session cookie, before the fix): 404 on `/_app/immutable/chunks/*.js`
with Referer `/_app/immutable/entry/start.*.js`.

## Fix
`apps/console-api/src/preview/proxy.ts`: a Referer-routed path ending `.js` or `.mjs` (`isScriptPath`) is always redirected, whatever
`Sec-Fetch-Dest` says. This is a TS stand-in (a path-suffix test, no Lean decision; the admission rules it sits behind are Lean).
Limit: the suffix rule also redirects a Referer-routed `navigator.serviceWorker.register('/sw.js')` fetch, and browsers reject a
redirected service-worker script. The fastwork snapshot only calls `getRegistration`, so nothing breaks today. The fix is a Lean
`scriptMove(path, secFetchDest)` that serves `Sec-Fetch-Dest: serviceworker`/`worker` in place (follow-up, see the handoff).
Regression test: `apps/console-api/test/lan-owner.test.ts` (302 for `/x.js` with a preview Referer and no `Sec-Fetch-Dest`; the old
assertion expected 200 and encoded the bug).

## Runs after the fix
Ran against the branch worktree at commit af75c332 (console-api on this branch), using the builder's own preview server on a free
port, not 8788. The console serving 8788 at the time (main 84d779cf, started before the grant routes) has no `/__grant`, so a grant
probe through 8788 is impossible until the console is restarted on this branch (the lead's post-land step).
Probe: iPhone UA, 390x844, external hosts blocked, original arm `/preview/pvi/o/` from the preview server over the snapshot,
admitted by an inspect grant (redeemed on loopback, cookie carried to the LAN host).

| engine | host | hydrated | fonts | images | failed same-origin |
|---|---|---|---|---|---|
| Chromium | loopback | yes | Google Sans, Playpen Sans Start Selling | 148, 0 broken | none (11 expected script 302s) |
| Chromium | LAN | yes | same | 148, 0 broken | none |
| WebKit | loopback | yes | same | 148, 0 broken | none |
| WebKit | LAN | yes | same | 148, 0 broken | none |

The only error is the aborted external `cloudflareinsights` request (my own route block; the accepted `/cdn-cgi/rum` class).
WebKit prints unused-preload warnings for root-path preload links; harmless.

## The grant (part A)
See `docs/team/tools/preview-grant.md`. Admission is Lean (`PreviewOwner.lean` 2b', theorems `issue_requires_loopback`,
`redeem_ok_iff`, `grant_expires`, `grant_never_other`, `serve_grant_only_preview`, goldens `console.previewGrant`, `console.ownerGate`).
Deviation: audit lines go to `.fw-console/preview/log.jsonl`, not `events.jsonl`, because a new event type needs a reducer change.

## Accepted limits
The grant never opens `/api` or `/owner` and is never the owner session. Tokens are in memory only. The browser probe is a
scratch script, not committed; the unit tests cover the redirect and the grant glue.
