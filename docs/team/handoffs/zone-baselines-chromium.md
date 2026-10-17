# Handoff: zone-baselines-chromium (measure-engineer), part 2

State: branch `worktree-agent-a640e2b5cfb5a1b15`, commit trailer `Task: zone-baselines-chromium`. Part 1 (swipe-v1 original) is on main.
Done: all four (profile, arm) baselines exist under `results/baselines/chromium/<profile>/<arm>.{zones,classes,baseline}.json`:
swipe-v1 original+rewrite (run 39048702153) and swipe-touch-v1 original+rewrite (run 39050423094, no new CI run). detDrift and
detDriftTotals empty in all four, 0 unlisted. Table and numbers: `results/baselines/chromium/README.md` (Part 2); note in
`research/notes/2026/10-17-zone-baselines-chromium.md`.
Code: `packages/measure-chromium/src/zone-baseline.mjs` got `--profile` (select among stored runs); `test/fwcore.test.mjs` checks all four
baselines (`--check`, empty drift, 0 unlisted).

Learned
- `pnpm fw ci` writes to the MAIN checkout's store; a worktree needs `pnpm install --offline --frozen-lockfile`; `fw ci` finds main's fwcore, but
  `zone-baseline.mjs` needs `FW_CORE_BIN=<main>/lean/.lake/build/bin/fwcore` when the worktree has no lake build.
- A copy of the fwcore binary in the scratchpad could not be executed (spawn failed); use the main path.
- A target=original dispatch skips classify; dispatch `target=both` (the refreeze runs did).

Open
- Re-run `zone-baseline.mjs baseline --profile p --target t` after any refreeze (the test fails while stale).
- The swipe-v1 rewrite is the early rewrite (sha cba3040); take a fresh `target=rewrite` run after ports land and re-pull it.
- Touch rewrite/original frame counts (409/531) differ from swipe-v1 (385/503) by design; only compare within a profile.
- No per-part dimension (Chromium counts have none).
Read first: `results/baselines/chromium/README.md` (Part 2 table).
