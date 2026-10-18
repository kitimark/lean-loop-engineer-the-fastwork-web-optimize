# Handoff: math-final (review tooling)

State: `scripts/math-pending.mjs` + `scripts/test-math-pending.mjs` (9 tests) on the worktree branch; first run (r13) at
0cee322: 3546 entries, 2610 signed, 936 pending, batches A=234 B=236 C=233 D=233.

Use: `node scripts/math-pending.mjs [--batches 4] [--out <dir>] [--json <export>]`, tests:
`node scripts/test-math-pending.mjs`. Output: `batch-<A..>.tsv` (module, name, kind, stmtHash, mathHash; no header)
and `summary.json` (HEAD, dirty flag, export key, totals, per-module counts, batches, status of each pending entry).

Conventions followed:
- Export source order: `--json`, then `lean/.lake/mathview-cache/<key>.json`, then the main checkout's cache (a
  worktree without `lean/.lake`), then `lean/scripts/mathview-cached.sh --build`. `<key>` is recomputed in node exactly
  as mathview-cached.sh does, so a cache hit is the export of these exact sources (only lint-passing exports are cached).
- Record precedence copied from `docs/plan/tools/build-math-view.mjs` `reviews()` (highest `round:`, last row wins).
- Signed is strict: latest row agree AND both hashes present and equal. A row without hashes is `unhashed` (pending),
  unlike the page, which shows it as agree (2 rows: `Fw.Null.pNull`, `Fw.Null.winsAt_le_one`, fwcore record).
- Statuses: signed, new, stale (agree, hash changed), unhashed, disagree (hashes unchanged), disagree-changed.
- Script, not Lean: the decision is one map lookup + set difference + greedy (LPT) batching; the script asserts
  pending ∪ signed = all, pending ∩ signed = ∅ and that the batches partition pending on every run, and the tests cover
  each status, precedence and batching. Not proved in Lean (listed as a TS stand-in if the lead wants it in fwcore).
- Batching: per module; a module larger than ceil(pending/N) is cut in line order; largest chunk first to the
  smallest batch. Deterministic.

Open items:
- Modules still being written at 0cee322: PeopleCard, HeroAccent, Obs.Next, Plan.Incident have no entries yet;
  Console.Land has 18 new entries; Plan.Core/Graph have `Fw.Plan.mk`, `Fw.Plan.cpf` (disagree-changed). Delta round later.
- docs/plan/loop-plan.html math view tally is stale (says 2167 agree / 4 disagree / 0 pending); regenerate with
  `node docs/plan/tools/build-math-view.mjs` after the next record lands.
- Possible addition: `--skip-modules` to hold back modules in flux.

Read first: header of `scripts/math-pending.mjs`, then `research/notes/2026/10-18-math-review-r12-6504ec1.md`.
