# lean-console-gaps (lean-prover) handoff

State: branch `worktree-agent-aebd2746926f8e8bf` (base 342a9fb), one commit "lean: console gaps ...". Gates green:
`sh lean/scripts/check.sh`, `pnpm --filter ./apps/console-api test` (181), `pnpm --filter ./apps/runner test` (81), console-api typecheck.

Moved from TS stand-ins into Lean (fwcore ops, all stateless, goldens from `lean/scripts/OpsGolden.lean`):
- `ops.obs` (`Fw/Ops/Obs.lean`, wire in `Fw/Ops/Wire.lean`): obs key `agent|event|tool_use_id-or-ts` and the per
  (agent type, tool) summary. drain.ts `obsKey`/`summarize` call it (`Drain.summary()` is now async; routes.ts awaits).
- `plan.trailers` (`Fw/Plan/Trailer.lean`, wire in `Fw/Wire/Console.lean`): which `Task:` trailer on which first-parent
  commit marks which task done (oldest wins; done/unknown/repeated ids give no fact; verdicts for all). git.ts keeps
  only I/O (`firstParentLog`) + `trailerFacts`; reconciler step 3a uses it.
- `ops.spawn` reply gained `wantKind` (`SpawnGuard.wantKind`, theorem `kindMismatch_fields`); spawn-guard.mjs
  `kinds(req, reply)` reads want/got from the same reply (no extra call; null when fwcore is unavailable).
- `console.landReadiness` (`Fw/Console/Land.lean`: `landNeeds c = [] <-> ready c`, refusal = reducer's) and
  `console.actor` (`Fw/Console/Self.lean`: console-api's own sources -> actor/type, all allowed by MAY). No TS caller
  yet: test/console-self.test.ts checks every new golden against fwcore and pins alertFor's actor/type.

Conventions: wire modules have no math (MathView skips `Fw.Wire.*`); Golden.lean `extra` writes golden/plan and
golden/console files in the ops format `{name, request, response}`; regenerate with
`cd lean && lake env lean --run scripts/OpsGolden.lean` (lake test checks staleness).

Open items:
- contracts `ObsRecord` is `.strict()` but spawn-guard records carry role/want_kind/got_kind/has_name/isolation/
  depth/seen_by, so the drain counts them invalid (SpawnGuard claims never reach `claimFor`). Not in this task's files.
- `console.landReadiness` is stateless (card JSON in); a stateful variant via `Fw/Serve.lean` and a console-web
  consumer are follow-ups. reconciler.ts/drain.ts still write actor literals (pinned by the golden test).
- docs/team/handoffs/fw-land-log.md still names the removed `taskTrailers`.

Read first: `lean/Fw/Wire/Console.lean` (op table), `lean/Fw/Ops/Golden.lean` (`extra`), the test above.
