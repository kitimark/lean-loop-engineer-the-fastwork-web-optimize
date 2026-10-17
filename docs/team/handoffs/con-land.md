# Handoff: con-land (git reconciler, fw land, fw card)

State: branch `worktree-agent-a084326c554189805`. console-api 59 tests, runner 18, typecheck green, e2e script green
(`FW_CORE_BIN=<fwcore> sh apps/runner/test/e2e-land.sh`: real console-api + fw CLI + temp repo).
Tests need the fwcore binary (`FW_CORE_BIN` when the worktree has no `lean/.lake`).

## Conventions
- Branch -> card rule: `card/<CARD>` (builder = card owner) or `card/<CARD>/<agent>`; other branches are ignored
  (`console-api/src/reconcile/naming.ts`).
- Reconciler (`reconcile/reconciler.ts`): polls 2 s (`main.ts` starts it), `POST /api/reconcile` runs a pass now.
  Facts: `card.build` key `build:<ref>:<sha>` per commit in `main..branch`; `card.landed` key `landed:main:<sha>` when a
  card's head is an ancestor of main. Reducer dedups by key; in-process memo avoids resubmitting (and re-logging refusals).
- `GET /api/land/:card`: readiness = Lean board `stage == land_ready` (no TS decision).
- `fw land card/X`: rebase if behind (new commits = new builds, so evidence goes stale and Lean refuses until re-screened),
  reconcile, readiness, fast checks (`sh lean/scripts/check.sh`, `pnpm test`; `FW_LAND_CHECKS` JSON overrides, dev only),
  path check, `card.land_request` (actor lead; `FW_ACTOR=user`), `git merge --ff-only` on main's worktree, reconcile.
- `fw card open|approve|screen|review|swipe|request` in `runner/src/card.ts`; default actor per Lean MAY table.

## Lean gaps / stand-ins
- `pathCheck` in `runner/src/land.ts` is a TS stand-in (deny list + optional allow list); replace with `ops.pathCheck`.
- No Lean op for "branch/commit -> card" mapping or for per-card allowed paths; no `check.sh --fast` yet.
- Land-readiness answer is only the board stage; a dedicated `console.landReadiness` (with the refusal reason) would
  avoid the runner composing messages from `stage` + `next`.
- Actor is self-declared (fw land uses `lead`); capability hook still open.

## Open
- Detection gap: commits that reach main before the reconciler ever saw them on the branch yield no `card.build`/`landed`.
- Main ref name is fixed `main`; worktree path of main found via `git worktree list`.
