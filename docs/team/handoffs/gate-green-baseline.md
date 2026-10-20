# Handoff: gate-green-baseline

State: branch `worktree-wf_54534f79-487-2` (CI ref `ci/gate-green-baseline`), fix commit 8f9814ff, measured tree 22bab3bc.
Result: the full breakpoint gate passes both engines, three consecutive runs, no flags, workflow success
(39368032874, 39369683085, 39370632229). Chromium 7049 pass / 7 excused / 0 fail; WebKit 6765 pass / 291 excused / 0 fail.

Cause: Playwright's `page.setViewportSize` also sets the screen to the viewport (playwright-core 1.64.1 `lib/coreBundle.js:23896`),
so WebKit phone-rotation stops 1 and 3 (932x430, device width 430) read device-width 932, "not achieved", every Lean row there `na`.
Fix is in the harness, not an excuse: `packages/gate-breakpoints/src/engines.mjs` (WebKit `resize` sets viewport and screen together).

Verified: `sh lean/scripts/check.sh` green; gate-breakpoints 144/144; `scripts/ci-paths.test.mjs` 41/41; apps/runner 57/57.
Lean: `lean/Fw/Gate/WebkitScreen.lean` (`plain_resize_unmet`, `kept_resize_met`, `phone_rotation_never_excused`);
golden `packages/contracts/golden/gate/webkit-screen.jsonl`; the general "an excuse never hides a comparable failing reading"
already stands in `Fw.Gate.Exit` (allowlist unchanged, 5 entries).

Open items:
- No premise-registry entry for the Playwright behaviour (outside this task's writes); a source-pin test covers it for now.
- Not run on `main`; land through the queue to get a main run.
- The WebKit phone-rotation sweep is the slowest shard (199 s on j1 in run 1).

Conventions: a Playwright upgrade must keep `test/webkit-screen.test.mjs` green; if the internals vanish the resize falls back to
`setViewportSize` and the gate reports the cell not comparable (loud, never a pass).
Writes outside the graph list: `lean/Fw/Ci/Trigger.lean` (one golden added to the `lean.yml` row) and the regenerated
`packages/contracts/golden/ci/triggers.jsonl` (the ci-paths tests required both).

Read first: `research/notes/2026/10-20-gate-green-baseline.md`.
