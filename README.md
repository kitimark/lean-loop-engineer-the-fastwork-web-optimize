# fastwork-com-web-optimize-lean

A personal, educational loop-engineering study of the scroll performance of the public fastwork.com homepage.
It is not affiliated with Fastwork. Fastwork approved publishing its compiled site, fonts included; that copy lives
in `snapshot/` unmodified (see `snapshot/README.md`).

Fastwork has approved publishing a copy of its compiled homepage, including fonts, in this repository.

## Repo map

| Path | What |
|---|---|
| `lean/` | Lean 4 core (`fwcore`): reducers, gates, breakpoints, verdicts, with proofs and golden vectors |
| `apps/` | `console-api`, `console-web` (the console), `runner` (the `fw` CLI), `site` (the rewrite) |
| `packages/` | `contracts`, `gate-breakpoints`, `measure-chromium`, `measure-webkit` |
| `docs/plan/` | the plan (`PLAN.md`) and its explainer page (`loop-plan.html`) |
| `docs/team/` | handoffs and improvement logs |
| `research/` | notes, kickoff research, measurements |
| `snapshot/` | Fastwork's compiled site, unmodified, with `snapshot.lock.json` at the root pinning it |

## Run

Needs Node, pnpm and Lean (`brew install elan-init`).

```sh
pnpm install
sh lean/scripts/check-fast.sh   # quick Lean check (about 1 s on an unchanged tree)
pnpm test                       # builds Lean, then runs every package's tests
```

Console: `pnpm --filter console-api start` for the API, `pnpm --filter console-web dev` for the web UI.

## Read first

- [`docs/plan/PLAN.md`](docs/plan/PLAN.md): the plan
- [`docs/team/improvements/2026-10-17.md`](docs/team/improvements/2026-10-17.md): what was improved and why

## License

MIT for this repository's own code and docs (see `LICENSE`). `snapshot/` remains under Fastwork's terms.
