# trajectory-admission handoff

State: branch `worktree-wf_a2e03981-f12-1` (commit in the report). The trajectory probe is the admission gate of `v2-proved`.

Verified:
- Lean `Fw.Gate.Trajectory`: `Stored`, `outcome` (per run and path), recorder helpers `groupsOf`/`widthsOf` with
  `groupsOf_complete`, and `outcome_fail_iff`, `outcome_pass_iff`, `outcome_coverage_repeat`.
- Lean `Fw.Preset.V2Proved`: `tcell` (one theorem per branch), `trajWhy`, `ok` needs `trajWhy = pass`;
  `member_needs_trajectory`, `member_needs_mac_morph`, `trajectory_{falsified,pending}_not_mem`. Axioms: standard only.
- `Fw.Preset.Gen`: reads `packages/contracts/golden/preset/v2-proved.trajectory.jsonl`; decision rows carry `trajectory`
  (verdict `pass` / `pending: trajectory` / `falsified: trajectory`, cells, runs). `Gen.record` is the only writer.
- Run 39442517769 (`?preset=v2-proved` at df40923) recorded: Chromium hero and morph, Linux WebKit hero and morph.
- `v2-proved` is empty: all 8 former members are `pending: trajectory` (WebKit morph cell has no mac-webkit run).
- Tests: site (vitest + typecheck), console-api, runner land-inputs, `scripts/ci-paths.test.mjs`, `lean/scripts/check.sh`.

Open:
- `probe-apple` walks hero only and runs only for `hero.exit` searches, so no flag can get a WebKit morph cell. A
  workflow change (lead) must let it walk `--paths hero,morph` for any dispatched search; then dispatch
  `pnpm -s fw run --trajectory --ref ci/<branch> --fw engine.scene:hidden-pause,engine.scroll:batched,morph.columns:hidden-pause,morph.countdown:hidden-pause,morph.mount:shift,nav.hitTest:elements-skip,pain.notes:visible,people.card:mq --engines playwright-webkit`
  (pending candidates go as --fw: the empty preset walks the default config), record, regenerate.
- A pass of a shared run (a preset) passes each flag in it; a subset of that preset is not re-walked.

Conventions: record from `lean/` (command in `docs/team/tools/trajectory-probe.md`, Admission); a `?preset=` search needs
the preset file at the run's sha (`git show <sha>:apps/site/src/registry/presets/v2-proved.json`).

Read first: `docs/team/tools/trajectory-probe.md` (Admission), `lean/Fw/Preset/V2Proved.lean` (Trajectory admission).
