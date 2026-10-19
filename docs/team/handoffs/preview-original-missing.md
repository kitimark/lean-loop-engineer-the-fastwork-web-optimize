# preview-original-missing handoff

State: branch worktree-wf_88c85d5a-2b0-1, see `git log` for the commit.
Changed: apps/console-api/src/preview/rewrite.ts (inline script bodies untouched; manifest link use-credentials),
proxy.ts (script-destination Referer-routed requests get a 302 below the arm), test/preview-rewrite.test.ts (new),
apps/runner/src/land.ts (console-api now declares the read of snapshot/site/index.html), research/notes/2026/10-19-preview-original.md.
Verified: console-api `pnpm test` (417 pass, tsc included); ci-paths test; runner land-inputs. Headless Chrome end to end on a
scratch preview app (stub manager, snapshot as both arms, own test session): no CSP error, no failed request, fonts loaded, hydrated.
Open: (1) TS stand-in: rewrite rules are not in Lean; a Lean spec "only bytes outside inline script bodies change" with a
golden would replace the table tests. (2) Not run through a real PreviewManager preview (needs a task build); the stub used the same
proxy and gate code. (3) Pain-notes count 0 in headless on both direct and proxied; not investigated (follow-up).
Conventions: scratch scripts lived in the session scratchpad, not committed.
Read first: research/notes/2026/10-19-preview-original.md.
