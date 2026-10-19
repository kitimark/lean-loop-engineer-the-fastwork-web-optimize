# Preview original arm: scripts blocked by the rewrite (2026-10-19)

Status: MEASURED (headless Chrome on a scratch preview app, snapshot as both arms).

- Cause (CONFIRMED by the user's DevTools capture, reproduced by the new test): `rewriteBody` changed root-absolute paths inside the inline SvelteKit boot script, so its sha256 no longer matched the page's CSP meta (hash-only `script-src`). The script was blocked, hydration never ran.
- Fix 1: bodies of inline `<script>` (no `src`) are never changed; attributes and CSS are rewritten as before (`apps/console-api/src/preview/rewrite.ts`).
- Fix 2 (found by the end-to-end run): with the boot script running, `import("/_app/...start.js")` reached the proxy through `viaReferer`, but the module's own relative imports (`../chunks/x.js`) then resolved at the console root with Referer = the module, and 404ed. A request with `sec-fetch-dest: script` that `viaReferer` maps is now answered with a 302 to the prefixed URL, so the module lives below `/preview/<id>/o/`. Other destinations are served in place (unchanged).
- Fix 3: `<link rel=manifest>` gets `crossorigin="use-credentials"` so the fetch carries `fw_preview`. The gate is untouched, so no new data is exposed and no Lean rule changes.
- Test on the real `snapshot/site/index.html`: inline bodies equal after rewrite; every CSP sha256 matches an inline script.
- End to end (scratch preview app, port 47931, test session, loopback): no CSP error, no failed request, `document.fonts` holds Playpen Sans loaded, pain canvas filled (hydrated). Left: `404 /cdn-cgi/rum` (Cloudflare beacon, accepted). Direct snapshot server shows the same pain-notes count (0 in headless at that scroll), so that is not a regression.
- Lean: `rewrite.ts` is not Lean-specified today, so no theorem was added. It is a TS stand-in (table tests + the snapshot test) for a future Lean span spec: "only bytes outside inline script bodies may change".
