# Preview without the root-path 302: one origin per arm

Status: design CONFIRMED by Lean proofs (`lean/Fw/Console/PreviewArm.lean`); browser result MEASURED on CI (run ids in the
handoff). The user's phone check stays the final confirmation.

## Problem
The preview proxy answered a root-absolute module request (`/_app/immutable/...`) with a 302 to a URL below the preview
prefix, so relative imports stay inside the arm. In WebKit this made duplicate loads: cancelled requests and "Importing a
module script failed" rejections (CI controls: `proxy-only` 3 rejections and 13-16 cancels per load, `raw` and `tap-only` clean).
Choosing the arm from the Referer is inference and fails on plain-http hosts that send no fetch metadata.

## Design (identity, not inference)
Each preview arm has its own public port, so a root-absolute path means the same thing as in the built site: no redirect.
- The preview server runs on a private loopback port (public + 1000, Lean `Arm.backendOf`); the arm app reads the local port
  of the socket and asks Lean `console.previewArm` (route + gate) once per request.
- Theorems: no request on one arm's port reaches the other arm's files (no leak); the gate decision per origin equals the
  old one (`console.ownerGate` goldens, `via` removed); root-absolute paths on the preview port are a shell path and are never
  granted (`grant_never_shell`).
- The preview port keeps `/preview/<id>/r|o/` as a page-level 302 to the arm origin (query kept), so console links and grant
  redirects are unchanged, and `/compare`.
- Cookies ignore ports, so the session cookie and `fw_grant` work on every arm origin.

## Gotchas
- fwcore matches replies by a top-level `id`; a reply field `id` crashed it ("reply id mismatch"). The field is `preview`.
- WebKit's cancel text differs: macOS "cancelled", Linux "Load request cancelled". The suite matches `/cancel/i`.
- The control loads must ignore the `POST /cdn-cgi/rum` beacon (a snapshot artefact, cancelled on unload).

## Checks
e2e asserts, per engine, host and target: 0 rejections, 0 cancelled same-origin requests, start() once, client-side
navigation, strict control attribution. Local macOS WebKit showed rare flakes (a lazy image cancel in a compare frame while
scrolling; once a module import) that differ per run; the Linux CI run is the arbiter (limit noted in the tool doc).

## Follow-up
- `cache-policy.ts` variants may be unused by the proxy now; check and delete.
- iOS Safari is not in the suite.
