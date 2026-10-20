# Handoff: circleci-cache-accounting

State: branch worktree-wf_d9735227-281-1; code at 3a531f48 (pushed as ci/circleci-cache-accounting), then a docs commit (note, handoff).
Read first: `research/notes/2026/10-20-circleci-pilot.md` section "Cache accounting", then `lean/Fw/Ci/Provider.lean` (`CacheSave`,
`cacheSavedBytes`, `cachePipelineBytes`, `savesCacheJob`), `.circleci/job.sh` (`cache_probe`, `cache_gate`), `scripts/circleci.mjs` (`readCacheSave`).

Result (MEASURED, CircleCI pipelines 254, 255, 256 on arm.medium.gen2, one lockfile): the first stores 9.3 MiB once, the next two halt
before `save_cache` (no save step in the job steps). Ledger milli 10, 11, 11 (was 108 per pipeline); credits 11, 12, 11 (INFERRED).
Root cause: CircleCI already skipped the upload of an existing key (step output), the ledger counted `du` of the store at every job.

Verified: `sh lean/scripts/check.sh` green; `node --test scripts/circleci.test.mjs` (52) and `scripts/ci-paths.test.mjs` (47); `pnpm test` in apps/runner (1563).

Facts the next agent needs:
- The cache key is now `pnpm-store-v2-...` and the cached paths are the store and `~/.fw-cache` (marker `lock-sha256`). A lockfile change makes one pipeline store a new cache; the other job of that pipeline reports "skipped" (key locked).
- `fetch` needs API v1.1 (`urls.jobSteps`), slug form `gh/<org>/<repo>` works; a `circleci/<uuid>/<uuid>` slug is untested. A save step that failed, or an output that is neither skip nor size, is an error (bytes unknown), not a guess.
- Pure decisions are Lean + golden (`cacheSaved`, `cachePipeline`, `jobMap.savesCache`). TS stand-ins: none new; the text parse `parseCacheSave` and the marker shell are glue with tests on real recordings (fixtures premise-tests*.json now hold the v1.1 steps and the Saving cache outputs).
- `.local/circleci.json` did not exist in this worktree; I wrote it from the API (project slug and definition id), gitignored.
- `pnpm fw` fails in a fresh worktree until `pnpm install --frozen-lockfile`; I ran `node scripts/circleci.mjs` directly for trigger, wait, fetch.

Writes outside the graph writes (needed for "Lean first"): lean/Fw/Ci/Provider.lean, lean/scripts/ProviderGolden.lean, packages/contracts/golden/ci/provider.jsonl (regenerated). docs/team/tools/circleci.md NOT edited: lead should change "the ledger counts the pnpm cache at every save" (Rules/Open) to "the ledger counts what the Saving cache step uploaded", and the key to v2.

Open: workspace bytes are still `du` (24 KB per engine job); webkit-sim jobs have no cache; ci-route can now plan CircleCI Arm series without the storage stop.
