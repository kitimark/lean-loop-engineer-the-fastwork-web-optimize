# Handoff: review-strips-console

State: branch `worktree-wf_69f980de-074-1`. The Reviews tab shows the frame strips of a look-change review inside the console.

Built
- Lean `lean/Fw/Console/ReviewStrips.lean` (imported by `Fw/Console/Review.lean`, not `Fw.lean`): `rows` (canonical: flag, engine, width,
  push, run, artifact, path, expires, note, diff), `stripsOf` (state ready/expired/missing per strip), `servable`, `serve` (allowlist), `redo`.
  Theorems: `strip_belongs`, `pending_no_strips`, `expired_not_served`, `serve_allowlist`, `serve_unknown`, `expired_refused`,
  `missing_only_without_rows`; `#guard` cases incl. the expiry day.
- `console.review` (`lean/Fw/Wire/Review.lean`): new optional request keys `today` (YYYY-MM-DD) and `serve` {flag, file}. With `today` each item
  has `strips` and the reply has `serve` ({ok, run, artifact, path} or {ok:false, reason}). Without `today` the reply is unchanged, so the
  existing golden `packages/contracts/golden/console/review.jsonl` still holds (I did not touch its generator).
- console-api `src/review/routes.ts`: `StripCache` (cache `<console dir>/review-cache/<run>/<artifact>/`, one download in flight per artifact,
  temp dir then rename, a failure is remembered 1 min, a 403 15 min, no retry before), `GET /api/reviews/:flag/strips/:file` (Lean `serve` decides, the
  path comes from the Lean row, never from the request). `createApp(..., reviewRoot, reviewOpts?: {download, today})` for tests.
- console-web `src/Reviews.tsx`: `StripCard`, `StripImage` (fetch with the owner token on approach, blob URL), external link kept as "Fallback".

Verified: check.sh, fwcore-build, console-api tests (`test/review-strips.test.ts`), console-web tests (`test/review.test.tsx`), console-web build.

Open items for the lead
1. WebKit strips show only once `lookDecisions` webkit material is `ready` in `lean/Fw/Preset/Gen.lean` (not mine to edit; run 39530106935, the 4
   screenshot strips). Until then the card shows the 4 Chromium strips. The rows for the 4 webkit screenshot strips exist and are tested via `looks`.
2. Notes of the webkit strips are empty ("no note yet"). The 4 screencast strips are not rows (they are not time-aligned), so no caveat is needed.
3. The redo text is `[ci:trajectory-probe] [frames:<flag>]` (the frames push), not a `[trajectory ...]` line: the strips come from the `frames` job.
4. Restart the live console after landing; run 39473950464 expires 2026-11-19, 39530106935 on 2026-11-20 (then the card says so).
5. TS stand-ins: none for decisions; the glue (cache, download, route) is I/O.
