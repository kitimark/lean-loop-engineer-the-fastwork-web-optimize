# counts-only handoff

State: branch worktree-wf_11ac09ad-a60-2 (also pushed as ci/counts-only). Task: let chromium-counts measure one part page. CLOSED AS A FINDING: the harness cannot (research/notes/2026/10-19-counts-only-finding.md).

Built (kept)
- chromium-counts.yml: `only` input (charset check) now fails the plan job; the `?only=` handling further down (site build skip, classes summary) is unreachable.
- lean/Fw/Engine/Keys.lean: `goldenRuns` row `(rewrite, ?only=hero)` + theorem `answers_only_hero` (stay true). keys.jsonl regenerated (78 vectors),
  keys.test.mjs count 72 -> 78. Verified locally: lake build Fw.Engine.Keys, engine-check 6/6, ci-paths, apps/runner vitest.

Open
- keys.jsonl has no registered writer or `--check` job in lean/scripts/check.sh (follow-up from model-checks still open).
- Premise on part pages: frozen classes are of the whole page; verdicts on a part page are INFERRED to be bounded by them.

Pilot (1 dispatch, only=hero, rewrite, 3 runs, swipe-v1, ci/counts-only @ 63034e1e): run 39189237058 FAILED, no counts. plan/site/fwcore/image passed; the 3
counts jobs died at packages/measure-chromium/src/run.mjs:151 (`viewport not faithful: 1280x800 vs profile 430x932`).

Causes (CONFIRMED by reading, not by a second dispatch)
1. pinEnv (apps/site/src/stage/fixedEnv.ts:24-29, called at apps/site/src/entry-client.tsx:36) pins innerWidth/innerHeight/scrollY to the stage env; with no
   `&stage=` that is Env.default y 0, vw 1280, vh 800 (apps/site/src/registry/only.ts:85, lean/Fw/Site/Stage.lean:30-31). viewportFaithful at run.mjs:149-151 sees 1280x800.
2. entry-client installs mode 'client-render' for `?only=` (entry-client.tsx:26-33); run.mjs:161-163 requires mode 'hydrate'.
3. The pinned scrollY is constant, so the swipe plan's scrollTo (run.mjs:167 on) does not move the part (INFERRED).

Next: task driver-stage-mode (driver passes &stage= from the profile, accepts client-render for a stage page, drives the stage y). Not an apps/site patch.
Then lift the `only` refusal in chromium-counts.yml plan job. Before any dispatch, statically check every driver gate against the page.
