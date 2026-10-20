# Handoff: gh-budget-watch-expiry

State: branch worktree-wf_bc899052-656-2 (commit named in the report). Read first: `research/notes/2026/10-20-gh-budget-watch-expiry.md`.

Verified here: `sh lean/scripts/check.sh` (see report), `pnpm test` in packages/gh-budget (36 old + 5 new), ci-paths test, runner land-inputs test.
Not verified: any run against the real `.git/fw-gh-budget` (forbidden; tests use temp dirs). No CI push made (nothing here needs CI).

What changed
- Lean `lean/Fw/Ci/Budget.lean`: Limits `maxAge` 7200, `missMax` 3, `maxRun` 10^13; Watch.misses; State.incidents; events `expire`, `listed`, `ack`;
  `pageCap`/`pagesOf` (tickCost reads at most 10 pages); section "(i) Stale watches and the bounded tick" with the theorems.
- Wire `lean/Fw/Ci/Wire.lean`: codecs, `clocked` applies `expire` on every op, `register` of an invalid id is an error, `next` replies `pages`.
- Goldens regenerated, never by hand: `lake test -- --write-ci-budget-golden` (from lean/).
- TS: `poller.ts` (limit from reply pages, `listed` event, `drainIncidents` to `incidents.jsonl`), `state.ts` path, `cli.ts` prints undrained incidents.

Finding: the stray id was a branch sentinel (`wait.ts:37`), a valid watch id by design; the lead's rule (a) alone would not catch it.

Open items (follow-ups, below the pinned unit)
- A waiter whose watch was dropped is not told (it times out). Let `evaluate` read `incidents.jsonl`.
- A killed waiter's sentinel lives up to 7200 s; a reaper keyed on the marker pid would end it at once.
- TS stand-ins: none new (all decisions are fwcore ops). The `full` flag is `rows.length >= 100 * pages` in glue (a count, no decision).

Conventions: JSON keys of the wire are sorted; new Event keys must be added to `eventOf` and the golden cases; `#guard cases.length` counts them.
