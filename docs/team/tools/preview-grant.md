# fw preview grant

`pnpm -s fw preview grant [<preview-id>] [--arm r|o]` prints one link, `http://127.0.0.1:<previewPort>/__grant?t=<token>`.
Open it in a headless browser on this Mac: it sets a preview-access cookie and redirects to the preview (default: the newest
serving one, arm `r`). No login.

- Asked over loopback only (`POST /api/preview/grant`, console Origin only); a LAN request is refused (Lean `issue_requires_loopback`).
- The token is random, single use, valid 10 minutes, redeemed from loopback only (Lean `redeem_*`).
- The cookie `fw_grant` (HttpOnly, SameSite=Strict) lasts at most 60 minutes. It opens preview paths and Referer-routed ones
  on the preview port, also through the LAN host, so a phone-user-agent probe can use the LAN address as Host. It never opens
  `/api` or `/owner` and is not the owner session (`allowGrant`, `serve_grant_only_preview`, `grant_never_other`).
- Decisions: `lean/Fw/Console/PreviewOwner.lean` (section 2b'), ops `console.previewGrant` and `console.ownerGate`
  (goldens in `packages/contracts/golden/console/`). TS (`apps/console-api/src/preview/grants.ts`) holds tables and randomness.
- Audit: lines `grant.issue`, `grant.redeem`, `grant.use`, `grant.refused` in `.fw-console/preview/log.jsonl`, with the grant
  id and never a token or cookie value. (Not `events.jsonl`: a new event type needs a reducer change.)
- Tokens live in console memory; a console restart voids all of them.
