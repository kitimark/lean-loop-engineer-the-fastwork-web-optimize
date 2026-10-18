# console-lan-owner handoff (round 2)

State: branch `worktree-wf_70b094c0-cb0-1` (round 1 + main merged); Lean, TS, tests done; see the final commit.

## What exists
- Lean `lean/Fw/Console/PreviewOwner.lean`: login limiter per address and global (`attempt`, `no_unbounded_tries`,
  `global_bound`, `locked_refuses`, `ok_only_if`), `lanStart` (`lan_start_requires_long`, passphrase >= 12 chars), console gate
  (`allow`, `lan_requires_owner`, `console_never_serves_preview`, `loopback_unchanged`), preview gate (`allowPreview`,
  `preview_requires_cookie`), origins (`preview_origin_ne_console`, `owner_action_requires_console_origin`,
  `preview_origin_refused`, `preview_cookie_no_owner`), idle sweep.
- Wire ops `console.ownerLogin|ownerGate|ownerAction|lanStart|previewSweep` (`lean/Fw/Wire/Console.lean`); goldens in
  `packages/contracts/golden/console/`. These files are outside the task `writes` globs: `fw land` needs `--allow`.
- TS in `apps/console-api/src/preview/`: `gate.ts` (console port, login body cap 1 KiB, Origin check), `preview-app.ts`
  (preview port: only `fw_preview` cookie, nothing else served), `owner.ts` (sessions with two cookies, `actionOk`),
  `login.ts` (global record), `proxy.ts` (forwards no cookie), `main.ts` (preview listener = console port + 1).
- Web: `TaskDetail.tsx` `previewBase(port)` builds links on the preview port.

## Conventions
- Passphrase only in memory; tests inject a fake; `FW_CONSOLE_KEYCHAIN=off` skips the keychain; never print its length.
- Cookies ignore ports, so the Origin check (Lean) is what refuses preview JS; `/api/commands` allows no Origin (CLI tools).

## Open / stated limits
- Plain HTTP on the LAN (sniffable); same-UID access; preview servers on loopback ports reachable by local processes.
- An attacker can lock the owner out for 10 min by 20 wrong tries (global limit); JS bodies are not rewritten.
- Flaky under load: `preview.test.ts` idle tick/reap (timing, real servers).
- Read first: `PreviewOwner.lean` header, then `preview-app.ts`, `gate.ts`.
