# counts-only handoff

State: branch worktree-wf_11ac09ad-a60-2 (also pushed as ci/counts-only). Task: let chromium-counts measure one part page.

Built
- `.github/workflows/chromium-counts.yml`: new optional dispatch input `only` (part or group id, charset `[A-Za-z0-9.]`, no leading or
  trailing dot). Plan job appends `&only=<id>` / `?only=<id>` to the rewrite search; `only` with target other than `rewrite` fails.
  The old fw charset check never saw `?only=` (it checks the `fw` input alone); the new input has its own check. Site build skips
  `--config` for an `?only=` search (a stage page is client-rendered, `pageFor` falls back to index.html). The classes job writes the
  frozen-classes premise (declared-rows-unverified, INFERRED) to run.txt and the step summary.
- `lean/Fw/Engine/Keys.lean`: `goldenRuns` gains `(rewrite, ?only=hero)`; theorem `answers_only_hero` (key branch and alias branch).
  `runKey_inj` and `answers_base_iff` already cover any query.
- `packages/engine-check/golden/keys.jsonl` regenerated from `Fw.Engine.Keys.goldenJsonl` (78 vectors, 6 added, none changed). It has no
  `--write` script; it was printed with `lake env lean --run` on a scratch file. `EngineGoldens.lean` check: 12 files equal (no engine golden
  uses goldenRuns). `packages/engine-check/test/keys.test.mjs` count 72 -> 78 (outside the row's writes, needed by the test).

Verified (local): `lake build Fw.Engine.Keys`, mathview lint 0 failing, engine-check tests 6/6, ci-paths 32/32, apps/runner vitest 1028.
actionlint shows only shellcheck style notes. CI: one pilot dispatch only=hero, see the report for the run id.

Open
- Whether the harness waits correctly on a client-rendered stage page (no hydration marker) is what the pilot shows.
- keys.jsonl has no registered writer or `--check` job in lean/scripts/check.sh (follow-up from model-checks still open).
- Premise on part pages: frozen classes are of the whole page; verdicts on a part page are INFERRED to be bounded by them.
