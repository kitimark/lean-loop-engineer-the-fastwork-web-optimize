# sup-route (lean-prover) handoff
State: branch worktree-wf_52c2ab8a-83c-1, main e49111ae merged; check.sh green, dry land `VERDICT dry sup-route`
(needs `--allow lean/scripts/check.sh`: the one added golden job line is outside the graph writes).
What exists
- `lean/Fw/Sup/Route.lean` (namespace `Fw.Sup.Route`, imports only Lean.Data.Json, not Core):
  `Stage` (s0 1a 1b 2 3 4, `rank`), `Service` (20 client paths from design.md section 5, each with `Service.stage`),
  `on st svc := svc.stage.rank ≤ st.rank`, `routeOf st svc present hashOk : Route` (daemon | today), `routeAll`.
- Theorems: routeOf_absent, routeOf_off, routeOf_hash (each fallback branch -> today), routeOf_daemon (all hold),
  routeOf_daemon_iff, routeOf_today_iff, routeOf_total, routeOf_s0 (stage 0 routes nothing), routeOf_mono (raising
  the stage never takes a service off the daemon), routeAll_lookup / routeAll_own (a batch decides each service
  alone), Stage.all_complete / Service.all_complete (the goldens cover the whole input domain), stage_moves.
- Goldens: `packages/contracts/golden/sup/route.jsonl`, 480 lines = 6 stages x 20 services x present x hashOk,
  `{name, request: {op: "sup.route", stage, service, present, hashOk}, response: {route, serviceStage}}`.
  Regenerate from lean/: `printf 'import Fw.Sup.Route\n#eval Fw.Sup.Route.gen []\n' | lake env lean --stdin`;
  check.sh job "sup-route golden check" runs it with --check (one added line, next to lake-slot).
- `lean/Fw.lean` imports Fw.Sup.Route.
Accepted limits
- Stage 0: no daemon binary; `hashOk` is an input, computing the binary hash is a follow-up.
- The stage flag is one level for all services; the design's per-service rollback in stage 2 ("flag off per
  service") is not modelled (follow-up, e.g. an off-list input checked before `on`).
- The `fw` bin without pnpm (stage 2) is packaging, not a routed path, so it has no `Service`.
Open items (follow-ups): wire routeOf into the fw CLI and clients (sup-client), fwcore `sup.route` wire op if TS
needs it at runtime, binary-hash source (identity file commit/toolchain or exe sha256).
Read first: Route.lean top to `routeAll`, then the theorem list.
