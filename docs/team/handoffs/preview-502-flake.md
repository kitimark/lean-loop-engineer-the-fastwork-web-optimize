# preview-502-flake handoff

State: cause found and fixed; branch `worktree-wf_4f15f604-8c2-1`. CI branches `ci/preview-502-flake*` carried a temporary
workflow that the final commit removes (the Lean workflow table has no row for it).

Cause (MEASURED + CONFIRMED): the rig's tap (Node server, idle limit 5 s + 1 s) closed a pooled socket while the arm app's
`http.Agent` reused it, ECONNRESET on a reused socket idle 5995 to 5999 ms. The Agent ignores a server's `Keep-Alive` hint
without its own `timeout` (Node v24.22.0 lib/_http_agent.js:655), and the tap copied the preview server's `timeout=65`.
Same blind spot in `proxy.ts` (compare). Full evidence and run ids: `research/notes/2026/10-2x-preview-502-flake.md`.

Fix: `apps/console-api/src/preview/upstream.ts` (`previewAgent` with `timeout: 30_000`, `upstream`, `log502`) used by
`arm-app.ts` and `proxy.ts`; `packages/e2e-preview/src/rig.mjs` tap drops hop-by-hop headers; test
`apps/console-api/test/preview-upstream.test.ts`. No retry.
Also: `controlLoad` keeps `leavePage`'s result (`openFailure`); `frameFacts` waits up to 5 s for the wanted font families (a
third flake, `o-frame/fonts-loaded#1` on a cold first load, cause INFERRED); docs and the webkit-cancelled-flake note text fixes.

Verified on CI: 10 green 1000-load compare repeats (39627999647 ... 39637984172, listed in the note), 10 more green all-target
runs; console-api 752 tests, e2e-preview 23, runner 1897, ci-paths 54 pass.

Open:
- `pnpm fw ci wait` prints `success -> fail` for some successful runs of an unknown workflow (artifacts were clean).
- The font wait has no trace; if `fonts-loaded` reds again the cause is not timing.
- The 18 land runs of the webkit-cancelled-flake note are not recoverable by id.

Read first: the note, then `upstream.ts`.
