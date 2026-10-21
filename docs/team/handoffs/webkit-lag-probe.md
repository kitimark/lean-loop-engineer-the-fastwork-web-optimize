# Handoff: webkit-lag-probe (measure-engineer), round 2

Branch `worktree-wf_4ab15aff-5d3-1`, CI branch `ci/webkit-lag-probe`. Read first:
`research/notes/2026/10-21-webkit-lag-probe.md` (findings, generated block, counter meanings, follow-ups).

## State
- State commit: `8b768018` (code, note, workflow). The CI sims of run 39511908073 ran commit `18893825`
  (the nearest-y join and later report code were applied offline to its artifacts).
- Lane `packages/measure-webkit/src/lag/`: `probe.mjs` (sampling), `report.mjs` (join, ratios, Markdown), `reduce.mjs`
  (TS twin), `note.mjs` (marker block filler), `cli.mjs` (`run`, `report --note`).
- Lean `lean/Fw/Measure/WebKitLag.lean`: regions through `Fw.Measure.WebKit` zones, unit-free ratio ranking with
  `rankWindows_scaleCol`, per-branch arm `verdict`, `topK`/`topPart`; golden `webkit-lag.jsonl` (50 lines).
## Verified (at 8b768018)
- measure-webkit tests 135/135, `scripts/ci-paths.test.mjs` 49/49, runner `land-inputs` 55/55, `lean/scripts/check.sh` green.
- Every table cell in the note block is `cli.mjs report` output over the six lag JSONs of run 39511908073 (sha256 in the note).
- Not verified: the `lag-report` job itself (skipped in both runs; gate now `!cancelled()` with guard/plan conjuncts).
## Open
1. One verifying dispatch (lead): `gh workflow run webkit-sim.yml --ref ci/webkit-lag-probe -f lag=true -f target=both -f vms=3`.
2. Forced exit (`PipeWrap open`) is the `ios_webkit_debug_proxy` child pipes in `sim.mjs startProxy`/`session.mjs`, not ours.
3. Counters needing new instrumentation are the note's Follow-ups 1-6 (DOM agent id, layers created, image decodes,
   wheel split, repaint split, tiled coverage), each with its WebKit path.
4. The two arms have different part tables (selector table vs data-fw); shares of people/pain and nav/morph move between them.
## Conventions
- Arm differences only by `verdict` on per-pass ranges; otherwise "no difference shown (ranges overlap)".
- Writes outside the graph: `.github/workflows/webkit-sim.yml` (lag-report gate), `lean/Fw.lean`, `lean/scripts/check.sh`,
  `lean/scripts/WebkitLagGolden.lean`, `lean/Fw/Store/Layout.lean`, `lean/Fw/Ci/Trigger.lean`, `packages/contracts/golden/ci/triggers.jsonl`.
- TS stand-ins: in-page JS, `clipRect`/`clipsPerStep`, nearest-y join, step duration sums, `partTable`/`leafTable`,
  Markdown, `note.mjs`, probe retries.
- Candidate fixes are judged by the note's smallest-effect rule (range wholly outside the baseline arm's range, 3 jobs).
