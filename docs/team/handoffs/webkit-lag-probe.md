# Handoff: webkit-lag-probe (measure-engineer), round 3 (final design round)

Branch `worktree-wf_4ab15aff-5d3-1`, CI branch `ci/webkit-lag-probe` (last push `06eee565`; round 3 pushed nothing).
Read first: `research/notes/2026/10-21-webkit-lag-probe.md` (Findings with anchors, generated block, follow-ups).

## State
- State commit: 189cb3b0 (code and block), 47ae3fb2 (Findings, handoff). Run 39511908073 ran `18893825`; the report code was applied offline to its six artifacts.
- Lean `lean/Fw/Measure/WebKitLag.lean`: `rareMin` 10, `countColumns` allowlist, `rareBase`, `flagged`, `ratioVerdict`
  (one theorem per branch), `Verdict.rareBaseline`; golden `webkit-lag.jsonl` 61 lines; `reduce.mjs` reads the constants from it.
- The flag drives every table and the idle lines; the footnote is generated from `rareMin`. Findings 1-9 carry anchors;
  `test/lag-findings.test.mjs` checks each anchored block cell; INFERRED sums and round-1 quotes are a per-token allowlist.
## Verified
- measure-webkit tests 146/146, `scripts/ci-paths.test.mjs` 52/52, runner `land-inputs` 55/55, `lean/scripts/check.sh` green.
- The block regenerates byte-identical from the six sha256-pinned JSONs (`cli.mjs report --note`).
## Accepted limits (final design, verbatim)
Footnote and theorem-scope wording beyond the generated footnote; follow-up reasons; the PipeWrap forced-exit wording (handle not
closed); the lag-report job gating (never ran green; open item for the lead); counters needing new instrumentation; Simulator not
phone; 3 jobs x 2 passes per arm; durations are host us; Findings remain hand-written prose (anchored, not generated); TS stand-ins
partTable/leafTable/Markdown/note.mjs (no Lean golden).
## Open
1. Lead: verifying dispatch of the lag-report job: `gh workflow run webkit-sim.yml --ref ci/webkit-lag-probe -f lag=true -f target=both -f vms=3`.
2. PipeWrap forced exit: ours (proxy child pipes of `startProxy`); harmless, watchdog exits 0 after 20 s; not fixed here (note follow-up 10).
3. Counters needing new instrumentation: note follow-ups 1-6, each with its reason.
## Conventions
- Arm differences only by `verdict` on per-pass ranges; a flagged (*) cell gets no ratio verdict (`ratioVerdict`).
- Writes outside the graph: `.github/workflows/webkit-sim.yml`, `lean/Fw.lean`, `lean/scripts/check.sh`, `lean/scripts/WebkitLagGolden.lean`,
  `lean/Fw/Store/Layout.lean`, `lean/Fw/Ci/Trigger.lean`, `packages/contracts/golden/ci/triggers.jsonl`,
  `packages/measure-webkit/test/lag-findings.test.mjs` (new), `apps/runner/src/land.ts` (declared read of the note).
