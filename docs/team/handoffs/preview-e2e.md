# Handoff: preview-e2e (console-builder)

Branch `worktree-wf_191ab411-e94-1`; CI branch `ci/preview-e2e`. Read first: `docs/team/tools/preview-e2e.md`.

State
- `packages/e2e-preview`: rig (`src/rig.mjs`), checks (`src/suite.mjs`), CLI (`src/run.mjs`), fixture (`fixture/site`), tests (`test/rig.test.mjs`, `test/signature.test.mjs`).
- Read set: Trigger row uses `@fwcore`, console-api src, contracts src/package.json; `land.ts` PACKAGE_EXTRA_READS the same. Land lane: `LandTier.browserRuns`, `console.landTier` field `browser`, `checks.ts` prints `LANE browser=`, `land.yml` steps.
- Registration commit: `apps/runner/src/land.ts` (PACKAGE_EXTRA_READS), `LandTier.lean` (remoteIds 7, filterList 7), `lean/land-filter.txt`, land-tier golden.
- Lane commit: `Fw/Ci/Trigger.lean` row + cacheWriters, goldens `ci/triggers.jsonl` `ci/intent.jsonl`, `.github/workflows/preview-e2e.yml`.
- Selection tests: `apps/runner/test/preview-e2e-selection.test.ts`, last test of `scripts/ci-paths.test.mjs`.

CI results (ci/preview-e2e, preview-e2e.yml)
- Run 39335496085 (head 0301c0dd): chromium 83/83, playwright-webkit 87/87; controls `raw`, `tap-only`, `proxy-only` x3 each on both engines; `/o` `start()` counted once.
- Attribution (webkit): signature only in `proxy-only`; `raw` and `tap-only` clean. Earlier red runs that shaped the rule: 39333909578 (cancel count exact, 3 CSS cancels answered 200 not 302), 39334939255 (Playwright reported 0 cancels in some loads).
- Final head 2432fc11: preview-e2e run 39337456654 (chromium 83/83, webkit 87/87); land lane run 39337463978 (branch ci/land-preview-e2e) ran the browser suite on both engines behind `LANE browser=true` (artifact land-preview-e2e, 83/83 and 87/87). Lean check.sh green, runner 1241 tests, ci-paths 41, e2e-preview 12.

Local debug runs (not results)
- Sec-Fetch-Dest negative control (isScriptPath gated again): plain host goes red.
- macOS WebKit 27.2: no module cancellations; cancels fonts instead (so the strict failed-request rule is red there; CI decides).
- Double import: no. Modules evaluate once on both engines and hosts; proxy unchanged.

Open
- Confirm on the phone (iOS Safari is not in the suite).
- `PreviewManager` is a stub; add a real-manager case if the manager changes.

Conventions
- Never read the owner link/passphrase/keychain; rig uses `TEST_PASSPHRASE` and a tmp store.
- Regenerate goldens (`lake test -- --write-ci-trigger-golden`, `LandTierGolden.lean`, `ci-paths.mjs --write`), never hand-edit.
- Bash in a worktree refuses heredoc plus cd; use Write/Edit or a script file.
- Orphan `serve-child.ts --fw-preview=e2e-fixture` after a killed run: kill only your own PIDs.
