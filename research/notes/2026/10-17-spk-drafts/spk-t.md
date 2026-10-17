---
id: 2026-10-17-spk-t
kind: note
title: "SPK-t: strict sandbox, socket, path resolution, violation detection and capability"
status: draft
created: 2026-10-17
topics: [spike, decision-record, sandbox, capability, worktree, hooks]
---

# SPK-t (DRAFT decision record)

**Question (PLAN Appendix B).** With the sandbox on (`allowUnsandboxedCommands: false`, `allowUnixSockets` = the CLI
socket, `denyWrite` = `.fw-console`), from a teammate in the main checkout and from a named worktree subagent:
(a) `pnpm fw gate`, tests and `git commit` with zero refusals (with SPK-o); (b) `node -e "fs.appendFileSync(<state>/events.jsonl,'x')"`
fails; (c) Edit/Write there are denied; (d) `pnpm fw screen` reaches the socket; (e) deny paths resolve to the main
checkout's `.fw-console/` from a worktree, and a commit on `main` outside `fw land` shows as a violation within one
reconcile pass; (f) the capability hook adds `--cap` (implemented as a spooled capability, see below) and console-api refuses a missing, wrong or reused capability;
(g) `emit.mjs` finishes in < 100 ms and prints nothing.

**Status: PARTIAL.** Items (f) and (g) have unit-test evidence; (a) to (e) cannot be tested because the sandbox is not
configured. M0 requires "SPK-t passed, or the separate-user fallback set up": **neither holds yet.**

| Item | State | Evidence | Status |
|---|---|---|---|
| (a) fw gate, tests, commit, zero refusals | open; `fw gate` missing, 8.4 % refusal baseline | `spk-o.md` | MEASURED (baseline) |
| (b) append to `events.jsonl` fails | open: no `sandbox` key; `.fw-console/` does not exist in the checkout | `.claude/settings.json` @a0b9053 (0 matches for `sandbox`) | CONFIRMED |
| (c) Edit/Write denied | open (needs `filesystem.denyWrite` plus the Edit/Write deny rule) | same | CONFIRMED |
| (d) `pnpm fw screen` reaches the socket | open (needs `allowUnixSockets`) | same | CONFIRMED |
| (e) paths resolve to the main checkout from a worktree; violation shown within one reconcile pass | partial: the reconciler detects commits and landing (`card.build`, `card.landed`), but a commit that reaches `main` before the reconciler saw it on a branch yields no fact | `docs/team/handoffs/con-land.md` "Open" @840f7d6 | CONFIRMED (gap) |
| (f) capability: missing, wrong, reused refused | unit-tested: 403 without a valid unused capability; HMAC check; single-use consume (`caps.used.jsonl`); `cap.mjs` writes `{agent_type, tool_use_id, cmd_hash, mac}` | `apps/console-api/test/cap.test.ts`, `apps/runner/hooks/cap.mjs`, `con-hooks.md` @97bd8a2 | MEASURED (tests) |
| (f) deviation and caveat | the implemented hook does not add `--cap` to the command: it appends a single-use capability to `.fw-console/caps.jsonl` keyed by `tool_use_id` and the command hash (`cap.mjs:1-5`). It is anti-accident, not anti-malice (the secret file is readable by the same OS user), and only counts if `fw` posts to `/api/agent/commands`, which is not wired (`fw` still posts to `/api/commands`) | `con-hooks.md` "Open" | CONFIRMED |
| (g) `emit.mjs` < 100 ms and silent | test asserts the floor < 100 ms; median about 47 ms vs 37 ms for bare node; spool-only, silent, exit 0 | `apps/runner/test/hooks.test.ts:81-89`, `con-hooks.md` @97bd8a2 | MEASURED |
| Doc facts: sandbox scope, child processes, hooks outside the sandbox, `updatedInput` | CONFIRMED by docs (via PLAN Appendix B) ; project-relative path resolution from worktrees is INFERRED | PLAN Appendix B | as stated |

**Dependency found while reading (INFERRED from code):** the capability maps `agent_type` to an actor and defaults a
missing `agent_type` to `main`, i.e. the lead (`cap.mjs:47`, `cap.ts:71`). SPK-c decides whether teammates carry
`agent_type`. See `spk-c.md`.

**Evidence commit:** `97bd8a2`, `3fe1876` (hooks, capability), `840f7d6` (land); HEAD `30e3264`.

## Missing
- The `sandbox` block, the hooks block and the `.fw-console/` state dir: none are applied. `.claude/**` edits prompt the
  user (an `ask` rule), so they come as one planned sitting.
- `fw` wired to `/api/agent/commands` with `argv`; `/api/commands` restricted to the user door (con-hooks "Open").
- An end-to-end run of items (a)-(e) from a teammate and from a named worktree subagent.
- Fallback if the sandbox breaks builds: a separate OS user owning `.fw-console/` (R25).

## Next step
1. Lead: apply the sandbox and hooks blocks in one `.claude/settings.json` sitting; ask the user once.
2. console-builder (agent-ops): wire `fw` to `/api/agent/commands`; script items (a)-(g) as one checklist run, from the
   main checkout and from a fresh named worktree subagent (also settles SPK-o); log refusals.
3. If a build or test needs a write the sandbox forbids (for example a toolchain cache under the home dir), record the
   fix as an absolute-path setting in `settings.local.json`, not a home path in a committed file.
4. If items (b), (c) or (e) fail, set up the separate-user fallback and mark SPK-t "passed via fallback".

## What this changes in the plan
- §10.2 M0: SPK-t is not met; it blocks the gate until item 1-2 run. R25 and R27 stay open; R27's mitigation depends on
  SPK-c. Appendix B: SPK-t "partial (f, g by unit tests)".
