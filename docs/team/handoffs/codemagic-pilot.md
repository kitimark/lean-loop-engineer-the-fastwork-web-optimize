# Handoff: codemagic-pilot (measure-engineer)

State: branch `worktree-wf_5ac2953f-445-1` (local `ci/codemagic-pilot` is pushed at the WIP commit 476da151, the yaml the three builds used).


Read first: `research/notes/2026/10-2x-codemagic-pilot.md` (results, recommendation), then `docs/team/tools/codemagic.md` (setup, commands, rules).

Verified
- Lean `Fw.Ci.Codemagic` (400-of-500 rule, three refusal theorems, `trigger_iff`, `ledger_invariant`, month key, exit mapping); `sh lean/scripts/check.sh` green; golden `packages/contracts/golden/ci/codemagic.jsonl` up to date.
- `node --test scripts/codemagic.test.mjs` (20 tests, golden replays, token host and redirect, 429, missing Keychain item, refusals), `scripts/ci-paths.test.mjs`, `apps/runner` `pnpm test` (apps/runner is unchanged, so the read scan has no new read).
- Three Codemagic builds (ids in the note): 2 finished, 1 failed (`simctl openurl` timeout); 46 of 500 minutes.

Open
- Wiring into `pool-fallback`: follow-up that needs the user's approval; the note recommends Codemagic ahead of CircleCI for sim cells (INFERRED, n = 3).
- `pnpm fw ci codemagic <sub>` is not shipped: its hook in `apps/runner/src/fw.ts` makes the `land-inputs` read scan demand `scripts/codemagic.mjs`, `scripts/codemagic.test.mjs` and `codemagic.yaml` in the apps/runner reads in `apps/runner/src/land.ts`, which is outside this task's writes. Use `node scripts/codemagic.mjs <sub>`. The lead may add both (the circleci lines in fw.ts and land.ts are the pattern).
- Class-count rule needs 3 finished runs per provider; Codemagic has 2. The harness lacks an `openurl` retry; the proxy is brewed each build; Node is not pinned in the yaml.
- The ledger `.local/codemagic-ledger.json` is per checkout (46 minutes used in 2026-10); copy it to any other checkout that triggers.
- TS stand-ins: `monthOf` in JS (Date; checked against the Lean golden), the class-table compare and digest (TS, not Lean), the ledger file I/O.

Conventions
- App id only from `FW_CODEMAGIC_APP_ID` or `.local/codemagic.json`; token only from the Keychain item `fw-codemagic-token`, sent only to `api.codemagic.io`; raw build responses are never committed (they hold commit author data).
- Trigger only through the adapter (it checks the Lean rule and writes a pending ledger row before the request); wait with `node scripts/codemagic.mjs wait` (poll at least 120 s).
- The workflow has no `triggering` block: a push starts nothing, only the API does.
