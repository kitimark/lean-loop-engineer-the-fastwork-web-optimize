# Handoff: preview-inspect

State: branch worktree-wf_472752b6-0dc-1, see the last commit. Parts A and B done.

- A: `fw preview grant [<id>] [--arm r|o]` (apps/runner/src/preview.ts) -> `POST /api/preview/grant` (loopback only) ->
  `/__grant?t=` on the preview port sets cookie `fw_grant`. Lean: `lean/Fw/Console/PreviewOwner.lean` 2b', ops
  `console.previewGrant` + extended `console.ownerGate` (`lean/Fw/Wire/Console.lean`), goldens regenerated.
  TS glue: `apps/console-api/src/preview/grants.ts`, `preview-app.ts`, `routes.ts`.
- B: cause = the script redirect keyed on `Sec-Fetch-Dest`, which plain-HTTP LAN origins never receive. Fix `isScriptPath` in
  `proxy.ts` (TS stand-in, path suffix). Note: `research/notes/2026/10-20-preview-original-gate.md`.

Verified: console-api, runner tests (with typecheck); Chromium and WebKit, phone UA, loopback and LAN host, original arm.
Open:
- The user's phone check of `/preview/<id>/o/` is the final confirmation.
- Audit lines go to `.fw-console/preview/log.jsonl`, not `events.jsonl` (new event type = reducer change); decide if wanted.
- The browser probe is scratch, not committed; add one under scripts/ if a standing check is wanted.
- The console must be restarted to serve the new routes.
Read first: docs/team/tools/preview-grant.md, then the note.
