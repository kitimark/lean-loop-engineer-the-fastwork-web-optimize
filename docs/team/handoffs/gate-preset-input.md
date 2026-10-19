# gate-preset-input handoff

Branch `worktree-wf_11ac09ad-a60-4`, CI branch `ci/gate-preset-input`.

## Cause (CONFIRMED, source read)
- `apps/site/src/entry-server.tsx` `enumerateSearches` prerenders `?preset=<name>` for every preset, so `?preset=v2-proved`
  was always a key of `configs.json`. The workflow `fw` input became `?fw=<input>`, so `preset:v2-proved` asked for
  `?fw=preset:v2-proved`, which no build has (`serve.mjs` `rewriteFor` threw "not prerendered" in the job, not in smoke).
- The smoke step never read `FW_SEARCH`.

## Change
- New `preset` input of `breakpoint-gate.yml`. The `site` job's plan step runs `.github/scripts/gate-search.mjs` (twin of
  `Fw.Gate.Search.pick`) and exposes `needs.site.outputs.search`; the smoke and run steps use it as `FW_SEARCH`.
  A refused pair (both inputs set, bad alphabet) fails in the plan step.
- `.github/scripts/gate-smoke.mjs` calls `rewriteFor(siteDist())` before launching an engine (a missing key fails
  there, with the known keys listed) and serves the rewrite arm with that page.
- Lean: `lean/Fw/Gate/Search.lean` (one theorem per branch of `pick`, `pick_v2_proved`), generator
  `lean/scripts/SearchGolden.lean`, golden `packages/contracts/golden/gate/search.jsonl`, job "search golden check" in
  `lean/scripts/check.sh`; `Fw.lean` import; `Fw/Ci/Trigger.lean` rows (gate row: script, test, golden; lean row: golden)
  and regenerated `golden/ci/triggers.jsonl`.
- No generated file was hand-edited; the preset JSON is untouched.

## Verified locally (not a measurement)
`lake build`, `lake test`, golden `--check`, mathview lint 0 failing, `node --test scripts/ci-paths.test.mjs` (32),
`.github/scripts/gate-search.test.mjs` (3), `gate-jobs.test.mjs` (10), `pnpm --filter @fw/gate-breakpoints test` (137),
`pnpm --filter @fw/runner test` (1028 plus tsc). Smoke with a fake dist and `?fw=preset:v2-proved` exits 1 listing the known keys.
`sh lean/scripts/check.sh` as a whole was not run (the worktree sandbox refuses it); its jobs were run one by one.

## Open
- work-graph `writes` of this task lists `apps/site/scripts/prerender*.mjs` etc.; the files actually written are above
  (lead to adjust).
- TS stand-in: none; `gate-search.mjs` is checked against the Lean golden.
- Gate run on the v2-proved arm (MEASURED, CI): run 39189945037, `workflow_dispatch` on `ci/gate-preset-input` at 8a6b34ba
  with `engines=chromium preset=v2-proved`. Smoke and all 3 gate jobs passed; the page loaded was `?preset=v2-proved`,
  config 6762d15c2b8b6d35. Verdict chromium: fail (7056 readings, 6533 pass, 516 fail, 7 excused; universe identical, not
  narrowed). Failing rows: hero.countdown (all 14 columns; strip: `face` count 64 vs 0) and nav (6 columns; `actions`
  1 vs 4, `bar` 1 vs 2 in the count lens), plus one platform style `--morph-fade` that differs. Every other row passes.
  Next: the lead decides whether the strip / nav variants are meant to change those counts (then the gate needs a
  Lean exemption) or the preset must drop them.
- Not run: WebKit (Chromium only was asked).
