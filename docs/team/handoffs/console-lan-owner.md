# console-lan-owner handoff

State: branch `worktree-wf_b126b9de-9e2-1`, Lean + TS + tests done; check.sh green; console-api 296+ tests, console-web 7.

## What exists
- Lean `lean/Fw/Console/PreviewOwner.lean`: login limiter (`attempt`, `no_unbounded_tries`, `locked_refuses`, `ok_only_if`),
  gate (`allow`, `lan_requires_owner`, `preview_requires_owner`, `loopback_unchanged`), idle sweep (`idle_stops`, `ttl_stops`).
- Wire ops `console.ownerLogin`, `console.ownerGate`, `console.previewSweep` in `lean/Fw/Wire/Console.lean` (outside the task
  `writes` globs: `fw land` needs `--allow`); goldens in `packages/contracts/golden/console/`.
- TS glue in `apps/console-api/src/preview/`: `login.ts` (keychain read, constant-time compare, LoginGuard), `gate.ts`
  (middleware + /owner/login|logout, /api/owner), `proxy.ts` (/preview/<id>/{r,o,compare}, Referer routing for JS-built
  absolute paths), `rewrite.ts` (HTML/CSS), `lan.ts` (LAN address), `owner.ts` (sessions), `manager.ts` (idle sweep, prefix).
- Web: `TaskDetail.tsx` links go through the console port; vite dev proxy covers /preview and /owner.

## Conventions
- The passphrase exists only in memory (main.ts reads it once); tests inject a fake; `FW_CONSOLE_KEYCHAIN=off` skips the keychain.
- Previews need an owner session even from loopback. LAN mode (`FW_CONSOLE_LAN=1`) binds a second server on the private IPv4.

## Verified
One real build (`port-platform`, ports 47100/47101): HTML, CSS, images, ES modules and the compare page load under the proxy;
SvelteKit `/_app/...` and bundle-built `/selling/...` paths load through the Referer route. Child processes cleaned up.

## Open / limits
- Plain HTTP on the LAN: passphrase and cookie are sniffable on the Wi-Fi. Same-UID access (keychain, ptrace) is accepted.
- JS bodies are not rewritten; only same-origin Referer routing covers root-absolute strings (a page with no Referer policy change).
- IPv6 address rotation by an attacker is bounded only by the table cap (1024, fail closed).
- Read first: `PreviewOwner.lean` header, then `gate.ts`.
