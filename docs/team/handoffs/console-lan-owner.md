# console-lan-owner handoff (round 3, final design)

State: branch `worktree-wf_b4b76cde-a4b-1` (round 2 branch + main merged); Lean, TS, web, tests done; see the final commit.

## Design (closed)
- No ambient owner credential. Login (`POST /owner/login`, JSON only) returns an owner token; console-web keeps it in
  localStorage of the console origin (origin includes the port, so preview JS cannot read it) and sends `Authorization: Bearer`.
  Owner rights come from that header alone (Lean `owner_requires_bearer`, `cookie_never_owner`). No `fw_owner` cookie exists.
- `fw_preview` cookie stays: it opens the preview port only (viewing).
- Every console response sets `X-Frame-Options: DENY` and `CSP frame-ancestors 'none'`.
- All non-GET routes except `/owner/login` pass one Origin gate; the trusted origins come from Lean (`trustedOrigins`, in the
  `console.ownerAction` op, not `ownerGate`: small deviation), empty when the preview port is unset, never the preview port.
- New Lean class `shell` (static web, no data): a LAN browser loads it without a header; data lives under `/api`, `/owner`.
- One-time link `/owner?t=` redirects to `/#owner=<token>`; `auth.ts` stores it and clears the fragment. SSE is fetch-based.
- `Proof.cookie` in `routes.ts` is a legacy field name: it now means "valid bearer".

## User steps
- Log in at `/owner/login` (passphrase from the keychain), or open the tty one-time link; both end at the console with the token stored.

## Verified
- Reviewer probes (`probe.ts`, `probe2.ts`, Chrome): preview page sees only `fw_preview`; its cross-port POSTs get 403/415; stolen
  cookie plus forged console Origin replayed outside the browser: 403, `cookie:false`; 0 owner calls.
- Goldens `console.ownerGate|ownerAction.jsonl` are outside the task globs: `fw land` needs `--allow`.

## Stated limits
- Plain HTTP on the LAN; same-UID local processes; preview loopback ports reachable locally.
- 10-minute lockout DoS (20 wrong tries); preview-cookie leakage (grants preview viewing only; shadowing can only deny viewing).
- Unauthenticated LAN device can fetch the static web shell (no data). Lead-accepted (r3): trusted list computed in `ownerAction`; a
  `/#owner=<junk>` link can wipe the stored token (DoS, re-login); FW_CONSOLE_WEB_ORIGIN on a 47100-47139 port is not refused; Host case-sensitive.
- Read first: `PreviewOwner.lean` header, then `owner.ts`, `gate.ts`, `app.ts` middleware.
