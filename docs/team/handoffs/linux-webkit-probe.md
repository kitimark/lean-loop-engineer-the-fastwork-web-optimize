# Handoff: linux-webkit-probe (measure-engineer)

State: branch `worktree-wf_73b9728f-b7a-1`; CI branch `ci/linux-webkit-probe`. One CI run used of 3: run 39629051205
(workflow `linux-webkit-probe`, 2 VMs x 20 arms x 2 rounds), success, 80 arm runs, 0 errors, 800 of 800 steps delimited, 773 of 800 settled (27 hit the 4 s cap, 24 of them in orig-w390-d3-lp1).

Read first: `research/notes/2026/10-2x-linux-webkit.md` (four findings, what the lane can and cannot stand in for; the
tables inside the markers are generated, never edit them by hand).

Verified (local, after the run): `pnpm --filter @fw/measure-webkit test` (207 tests, 1 skipped before the note existed,
now 0 in my files), `node scripts/ci-paths.mjs --check`, `node --test scripts/ci-paths.test.mjs`, apps/runner
`ci-triggers` and `land-inputs` tests, `sh lean/scripts/check.sh`.

How to rerun: push `ci/linux-webkit-probe` with `pnpm -s fw ci push --branch ci/linux-webkit-probe --lanes linux-webkit-probe`
(or dispatch with `arms=<ids>`; `node packages/measure-webkit/src/linux/cli.mjs arms` lists them). Download with
`gh run download <id> -n linux-webkit-vm<N>`; copy `vm<N>.json` (not `-raw.json`, 52 MB) to
`results/linux-webkit/run<id>-vm<N>.json`; regenerate with `cli.mjs table --runs results/linux-webkit --note <note>`.

Writes outside the graph list (all needed by the new workflow): `lean/Fw/Ci/Trigger.lean` (row for
linux-webkit-probe.yml), `lean/Fw/Ci/Overflow.lean` (width 2), goldens `packages/contracts/golden/ci/{intent,triggers}.jsonl`
(regenerated with `lake test -- --write-ci-trigger-golden`), `results/linux-webkit/*.json`.

TS stand-ins (all descriptive, no verdict, no gate): `reduce.mjs` (percentiles, interval and Timeline-step reduction),
`table.mjs` (table layout), `arms.mjs` (arm matrix). Lean specs for them are not written; a later task can prove the
percentile and the step-window reduction.

Open: (1) the `fps` arm is 16 % faster than the base arm, unexplained; (2) main thread versus tile raster split of the
229 ms is not measured; (3) only 2 VMs, so no 3-VM class counts; (4) GTK build under xvfb not run; (5) no Mac-vs-Linux
count comparison. Conventions: Node `$HOME/.nvm/versions/node/v24.22.0/bin`; playwright-core resolves from
`packages/gate-breakpoints`; this package has none of its own.

Round 2 (no new CI run): applied review round 1 (FPS claims, Composite = count not time, whole-recording heading, steps-settled
column, Finding 1 heading and width sentence, package URLs); main merged; tables regenerated with cli.mjs table.
Still open: fw ci state does not know this workflow; percentile and step-window reduction have no Lean spec.
