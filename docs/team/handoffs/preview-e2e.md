# Handoff: preview-e2e (console-builder)

Branch `worktree-wf_191ab411-e94-1`; CI branch `ci/preview-e2e`. Read first: `docs/team/tools/preview-e2e.md`.

State
- `packages/e2e-preview`: rig (`src/rig.mjs`), checks (`src/suite.mjs`), CLI (`src/run.mjs`), fixture (`fixture/site`), tests (`test/rig.test.mjs`).
- Registration commit: `apps/runner/src/land.ts` (PACKAGE_EXTRA_READS), `LandTier.lean` (remoteIds 7, filterList 7), `lean/land-filter.txt`, land-tier golden.
- Lane commit: `Fw/Ci/Trigger.lean` row + cacheWriters, goldens `ci/triggers.jsonl` `ci/intent.jsonl`, `.github/workflows/preview-e2e.yml`.
- Selection tests: `apps/runner/test/preview-e2e-selection.test.ts`, last test of `scripts/ci-paths.test.mjs`.

Verified (local debug runs, not results)
- CI run 39330324128 (head f05938d3, success): chromium 77/77, playwright-webkit green. Package, runner, ci-paths, Lean checks pass.
- Double import: no. Modules evaluate once on both engines and both hosts; proxy unchanged.
- Limit: WebKit on Linux cancels redirected duplicate `/_app/` preloads (3 rejections, 13 cancelled per page); direct-serve control and Chromium have 0. Named as check `webkit-linux-preload-cancel-noise-observed`.
- Local macOS WebKit may stall on the LAN page (permission): use `--no-lan`. `--no-route` is a diagnosis flag.

Open
- Confirm on the phone (iOS Safari is not in the suite).
- `PreviewManager` is a stub; add a real-manager case if the manager changes.

Conventions
- Never read the owner link/passphrase/keychain; rig uses `TEST_PASSPHRASE` and a tmp store.
- Regenerate goldens (`lake test -- --write-ci-trigger-golden`, `LandTierGolden.lean`, `ci-paths.mjs --write`), never hand-edit.
- Bash in a worktree refuses heredoc plus cd; use Write/Edit or a script file.
- Orphan `serve-child.ts --fw-preview=e2e-fixture` after a killed run: kill only your own PIDs.
