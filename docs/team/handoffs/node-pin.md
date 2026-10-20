# node-pin handoff

State: branch worktree-wf_1c3edcd5-171-1, commit b9ae4fc9 (+ lead merge of main); one canonical Node pin `.node-version` = 24.22.0.
- 24.22.0 released 2026-10-14 (https://nodejs.org/en/blog/release/v24.22.0, dist index), so 6 days old; it is the only 24.x >= 24.22.0 and the
  version that throws on a recursive fs.watch of a missing path, so the >= 24.22.0 rule beat the two-week age wish.
- Every actions/setup-node step (setup-pnpm action + 11 workflows) uses `node-version-file: .node-version`; no `node-version:` is left.
- Check: `nodePinProblems` in scripts/ci-paths.mjs (run by `node scripts/ci-paths.mjs --check`): file is exact x.y.z >= 24.22.0, no
  `node-version:` key, every setup-node reads `.node-version`, every workflow using Node lists `.node-version` in its Lean row.
  Tests: scripts/ci-paths.test.mjs (2 new). TS stand-in: this rule has no Lean golden (the rows are Lean).
- Lean: `.node-version` added to the input list of all 16 Node lanes in lean/Fw/Ci/Trigger.lean; a `#guard` pins the lanes a
  pin change starts; triggers.jsonl regenerated (`lake test -- --write-ci-trigger-golden`).
- Local use: `nvm install && nvm use` reads .node-version (or `fnm use`). The Mac's nvm 24.14.0 is not changed (accepted limit).
- Verified: ci-paths --check green, ci-paths.test.mjs 43/43, lean/scripts/check.sh green, apps/runner pnpm test 1508 pass.
- Writes outside graph writes: 11 workflow files (setup-node steps), lean/Fw/Ops/CheckMap.lean (text kind for ext node-version, else the commit checkmap refuses .node-version),
  nothing else.
- CI proof: land run 39450225890 (ci/land-node-pin @ b9ae4fc9), all 4 legs log `Resolved .node-version as 24.22.0` / `node: v24.22.0`.
