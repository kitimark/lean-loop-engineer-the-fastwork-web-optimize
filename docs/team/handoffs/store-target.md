# Handoff: store-target

**State:** branch `worktree-agent-a6135e99ad87a9f07` on top of 24482c1; the commit with trailer `Task: store-target`.
Gate: `sh lean/scripts/check.sh` green; runner 104 tests, console-api 201 tests green; runner `tsc --noEmit` clean.

**Done**
- `Fw.Store.Target` = {original, rewrite} (`name`, `ofName`; `both` is not a target). The store key is now version 2:
  `keyPairs` = v=2, engine, **target**, preset, profile, sha, image, flags. `keyPairs_inj` covers the target;
  `keyPairs_target_ne` and `plan_key_target_ne` prove an original run and a rewrite run never share a key.
- `Request.target` and `Manifest.target` (strings, checked): problems `target: not original or rewrite` and
  `target: original takes no preset or flags` (`targetFits`, mirrors the check in chromium-counts.yml).
- `dispatchInputs .chromium` sends `target` (theorem `dispatch_target`); the workflow default `both` is never used.
- `needs` gains `target` when it is not `original`, so webkit (webkit-sim.yml, snapshot only) is BLOCKED on `target`.
- `Manifest.req` builds the key from a manifest (wire `store.manifest` uses it); `Manifest.valid_req`.
- Wire (`lean/Fw/Wire/Store.lean`, outside the task's paths but forced by the new fields): `target` is a required
  field of `store.plan` requests and of manifests ("missing field target" otherwise).
- TS: `fw run --target original|rewrite` is required; sent to fwcore, written to the manifest. Contracts
  (`packages/contracts/src/artifacts.ts`): `StoreTarget`, `RunManifest.target`, `PlanRequest.target`.
  run-golden.test.ts accepts a request outside the schema only when fwcore's reply is an error.
- Goldens regenerated (plan 14 cases, manifest 6). Six old Store mathview binder warnings fixed.

**Lean is ready for webkit-sim (ci-webkit owns the workflow; no input added here):** when webkit-sim.yml gains inputs,
add their names to `workflowInputs .webkit` and send them in `dispatchInputs .webkit` (mirror chromium: `target`,
`profile`, `preset`, `fw`). The key already holds target, preset, flags, profile and image for webkit; `blocked`
then clears by itself, and `needs_dispatched`/`blocked_chromium` show the pattern of the proofs to extend.

**Open items**
- Old v1 runs in a local `.fw-console/store/runs/` have no target; they are simply never hit (different key input).
- The workflow accepts preset names `[a-z0-9-]` only, while `isId` also allows `.` and `_`.
- Other handoffs (store-and-run.md, rewrite-ci-lane.md) still describe `fw run` without `--target`.

**Read first:** `Target`, `targetFits`, `keyPairs`, `needs`, `dispatchInputs`, `jobsFor` in lean/Fw/Store/Layout.lean.
