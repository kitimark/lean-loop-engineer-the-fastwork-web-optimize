# macos-telemetry (measure-engineer), branch worktree-wf_01c97be9-4eb-1

State: three fixes, Lean reducer with goldens, collector, committed 4.3-day dataset, note with Lean-rendered tables and
the ranked cuts. Implementing the cuts is a follow-up. Commit: `git log -1` on the branch (report names it).

Read first: `research/notes/2026/10-2x-macos-telemetry.md`, then `lean/Fw/Obs/MacTelemetry.lean` (module doc, `Ctx.cuts`),
`apps/runner/src/ci-telemetry-mac.ts`.

What is in
- Fix 1 `fw ci state`: grows the run list 100/400/1000, `--branch/--workflow` (`apps/runner/src/ci.ts`). Cause MEASURED: 100 runs spanned 51 min.
- Fix 2 `fw ci wait`: success folded to failure because 1 of 10 jobs had conclusion "" (GitHub lag). Lean
  `Fw.Ci.Attempt.jobsSettled` (300 s grace), re-read up to 6 x 5 s, never cache an unsettled view (`packages/gh-budget/src/wait.ts`).
- Fix 3 `fw ci telemetry`: a `(matched)` row per job from Lean `obs.macMatched`.
- Lean `Fw.Obs.MacTelemetry` + `MacTelemetryWire`: ops `obs.macSample` `obs.macReduce` `obs.macMatched` `obs.macIs`; golden
  `packages/contracts/golden/obs/mactelemetry.jsonl` (generator `lean/scripts/MacTelemetryGolden.lean`, `--check` in check.sh).
- Dataset `mactelemetry-window-input.jsonl` (193 sampled runs of 3,415; 3 Codemagic builds; 3 CircleCI jobs) and
  `mactelemetry-window-report.json` (`--report`). The note embeds the Lean tables verbatim; the vitest in
  `apps/runner/test/ci-telemetry-mac.test.ts` fails when they differ.

Verified: apps/runner and packages/gh-budget `pnpm test`, `node --test scripts/ci-paths.test.mjs`, land-inputs test,
`sh lean/scripts/check.sh`, `fw land --dry` (see the report). No CI class counts are claimed.

TS stand-ins (I/O glue, no decision): fix 1, fix 2 re-read loop, fix 3 call, the collector (`ci-telemetry-mac.ts`).
Writes outside the graph list: `lean/Fw/Ci/{Attempt,Wire,Golden}.lean`, `packages/contracts/golden/ci-budget/wire.jsonl`,
`packages/gh-budget/{src/wait.ts,test/wait.test.ts}`, `lean/Fw/Wire.lean`, `lean/Fw.lean`, `lean/scripts/check.sh`,
`apps/runner/src/land.ts` (one PACKAGE_EXTRA_READS line), `docs/team/tools/ci-telemetry.md`.

Open items
- Follow-up: per-step timeouts for the measure steps (rank 1/2), teardown trim for wktr, wktr-fixtures, engine-premises, gate-gaps (<= 11 min/day), more Codemagic builds before any shift.
- `.claude/workflows/build-review.js` still calls `fw ci state` (not edited).
- Window is 4.32 days, not 7: nothing older exists. Codemagic 3 builds and CircleCI 3 jobs are thin rows.
- Savings are INFERRED until a cut lands. Re-collect: `pnpm -s fw ci telemetry macos-window --cache <dir> --now <ms> --codemagic-builds <ids>` (about 20 min), then `--report`.

Conventions: Codemagic build ids are given with `--codemagic-builds` (no ledger file exists); the CircleCI slug is never printed or committed.
