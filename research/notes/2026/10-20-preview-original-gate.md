# Why the original arm failed on the phone (preview-inspect)

Status: cause CONFIRMED by reproduction in Chromium; the fix verified in Chromium and Playwright WebKit. The user's own
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

Repro (Chromium, iPhone UA, 390x844, LAN host, valid session cookie, before the fix): 404 on `/_app/immutable/chunks/*.js`
with Referer `/_app/immutable/entry/start.*.js`.

## Fix
`apps/console-api/src/preview/proxy.ts`: a Referer-routed path ending `.js` or `.mjs` (`isScriptPath`) is always redirected, whatever
`Sec-Fetch-Dest` says. This is a TS stand-in (a path-suffix test, no Lean decision; the admission rules it sits behind are Lean).
Regression test: `apps/console-api/test/lan-owner.test.ts` (302 for `/x.js` with a preview Referer and no `Sec-Fetch-Dest`; the old
assertion expected 200 and encoded the bug).

## Runs after the fix
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
