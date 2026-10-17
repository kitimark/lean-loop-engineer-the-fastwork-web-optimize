# Handoff: gate-part-filter (`--parts` for the breakpoint gate)

Branch worktree-wf_eaf1cd1e-ed1-3 (commit in the report). Glue only; `verdict.mjs` is untouched (no TS stand-in added).

## What changed
- `cli.mjs run|summary --parts id,...` (ids as in `src/anchors.json`). `spec.mjs selectParts` validates (unknown or empty
  list throws) and returns covered/skipped in anchors order. `run.mjs` collects only the covered parts and writes
  `header.parts {covered, skipped}` ONLY when something is skipped; `summary.mjs` takes the covered set from the header
  (or `--parts`, which must be a subset of what the run collected), builds rows/failures from it and prints
  "Narrowed to parts: ... Skipped (no verdict for them): ..." in md and `parts` in json. matchMedia rows stay (not per part).
- CI: `breakpoint-gate.yml` has a new `parts` input (empty = all) -> plan output -> `--parts` on shard and sweep runs.
  `FILTERS` there is only setup-pnpm's package filter, so it was left alone. `gate-shards.mjs --parts` only validates ids
  (exit 2) and leaves its stdout JSON unchanged. `merge-gate.mjs` needed nothing (the header, parts included, must match).
- Test: `selectParts` in `test/spec.test.mjs` (15 pass).

## Measured (this Mac, Chrome 155 + Playwright WebKit, same dist, not phone time)
- Full run, code before the change: 535.6 s. Full run, new code: 517.5 s. Raw run files and summary.json/md are
  byte-identical between the two (sha256 equal), so default runs and verdicts are unchanged and deterministic.
- `--parts hero.exit` alone, both engines: 528.1 s. NO real saving: every probe applies to every part, so all 124 loads x 2
  arms + 4 sweeps still run. Its hero.exit row is identical to the full run's row (pass, 14/14 cells, both engines).
- `--parts hero.exit --probes height-probes,dark --sweeps none`, chromium: 37 s (loads are the cost; compose the flags).

## Open items
- To cut loads per part, each part needs a declared probe scope (blocks/sweeps it depends on, with a reason) in
  `anchors.json`, and a Lean statement that the scope suffices; that is a decision, not glue, so not invented here.
- The CI path (plan/shard/sweep/merge with `parts`) is validated for YAML and the shell expansion only; not dispatched.
- Read first: `packages/gate-breakpoints/src/run.mjs` (partFilter), `summary.mjs` (summarize).
