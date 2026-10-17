# watch-slow handoff

State: branch `worktree-agent-a095bf4c828ba2285`, one commit on main e781f27 (see `git log -1`). Gates green:
`sh lean/scripts/check.sh` (mathview + ShadowLint 0 failing) and `pnpm --filter ./apps/runner test` (109 tests).

What it did (Lean first; `fw watch` only gathers inputs):
- `lean/Fw/Obs/Health.lean`: new Params `goneAfterMin 120, ciSlowMin 20, toolSlowMin 15, procMaxMin 20, loadMax 150`;
  State `gone` (silent > goneAfterMin, folded into `ended`: not live, not in nLive/overCap/orphan/child checks);
  codes `agent.gone` (once vs `Obs.prevAt`), `agent.toolSlow`, `ci.slow`, `ci.finished`, `proc.long`, `sys.loadHigh`;
  `Alert.crit` from `Obs.critical` (task ids; tied = equal or `-digits`; CI via branch `ci/<task>`), sorted first.
  System pieces are named functions `sOver … sPerm`; `sysAlerts = Code.all.flatMap sysPiece`.
- Proved again with the new pieces: `health_mono` (via `Looser`, 16 fields), `alerts_sorted`, `crit_first`,
  `health_perm`, `counts_total`, `nLive_gone`, `goneAlert_iff`, `state_gone`, `ciSlow_raised`, `loadHigh_iff`.
- `lean/Fw/Wire/Obs.lean`: codecs for the new fields (`procOf_procJson`, round trips extended), `critical` in alert JSON,
  `gone` count. `lean/Fw/Obs/Golden.lean`: 9 new typed + 2 literal cases; golden regenerated (68 cases).
- `apps/runner/src/watch-collect.ts`: `ps` trees (`sessionProcs`, `keepNames`), `loadFloor`, `services`, gh `updatedAt`
  as `endedAt`, `collectCritical` (GET /api/plan) + `carryCritical`, `prevAt`. `watch.ts`: gone hidden, `*` critical.

Conventions: new thresholds strict `>` (load `>=`); binder-name rule (ν in permissionWait); no `let` in pieces.

Open items:
- apps/console-web/src/Health.tsx (not mine): add `gone` to STATES/order and the counts line; show `critical`.
- apps/console-api/src/health.ts zod: counts add `gone`, alerts add `critical: z.boolean().optional()` (now stripped).
- proc.long flags long poll loops of every agent in the session (by design); tune `procMaxMin` if noisy.

Read first: docs/team/tools/watch.md, the module doc of lean/Fw/Wire/Obs.lean, `sysAlerts` in Health.lean.
