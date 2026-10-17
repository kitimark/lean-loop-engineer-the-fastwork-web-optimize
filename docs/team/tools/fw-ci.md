# fw ci

`fw ci [<run id>] [--workflow chromium-counts] [--branch main] [--store <dir>]` pulls a finished CI run into the artifact store.
No run id: the latest run of the workflow on the branch. The store is `$FW_CONSOLE_DIR/store` (default `.fw-console/store`) unless `--store`.

- Downloads only `chromium-counts-*` and `chromium-classes` (not the image or fwcore artifacts) with `gh run download`.
- One store key per target in the run (a `both` run files two keys). fwcore `store.manifest` validates and keys it: target, preset, profile,
  git sha, image. Profile and image come from the shards (`counts.json`, `image-id.txt`); preset and flags from the rewrite query.
- Entries per key: `r<n>/*` (the shards of that target), `classes/*` (chromium-classes/<target>), `ci.json` (run id, head sha, conclusion).
- Refuses (exit 2, nothing stored): other workflow, run not completed or not success, a shard job that failed, a missing shard artifact
  or classes dir, shards that disagree on profile, query, target or image.
- Idempotent: the same run again prints `unchanged` and writes nothing. A different run with an already-stored key is refused, not overwritten.
- TS stand-in (Lean op `store.ciRun` wanted): `selectCiRun`, `searchConfig` in `apps/runner/src/ci.ts`; table tests in `apps/runner/test/ci.test.ts`.
- Chromium only; WebKit waits for webkit-green.
