# Handoff: review-strips-console (round 2)

State: branch `worktree-wf_69f980de-074-1`, main merged (webkit material ready, LAN click fix). The Reviews tab shows the 8 earn strips.

Built
- Lean `lean/Fw/Console/ReviewStrips.lean` (imported by `Fw/Console/Review.lean`): `rows` hold flag, engine, width, push, artifact, path, note, diff
  and NO run or expiry. `resolve` is the one place a row meets `Gen.lookDecisions` material: run and expiry come from the engine's material, and the
  row's artifact must be in the material's artifact string split on `, `; otherwise the strip is `missing` (never served). `stripsOf`, `servable`,
  `serve`, `redo` (one commit-message line).
  Theorems: `resolve_sound`, `resolve_unnamed`, `strip_material` (every listed strip's run/expiry = its material's), `unnamed_missing`,
  `serve_allowlist` (served strip: row of the flag, file asked for, unexpired, run/expiry/artifact from the material), `expired_not_served`,
  `serve_unknown`, `expired_refused`, `strip_belongs`, `pending_no_strips`, `missing_only_without_rows`; `#guard`s incl. expiry days 11-19 / 11-20.
- `console.review` (`lean/Fw/Wire/Review.lean`): optional `today` and `serve` {flag, file}; unchanged without `today` (golden holds).
- console-api `src/review/routes.ts`: `StripCache` and `GET /api/reviews/:flag/strips/:file` (Lean decides; core failure = 500 with the message).
- console-web `src/Reviews.tsx`: `StripCard` (legend now has the sample-time caveat; redo text = one commit-message line plus "update the material in Gen.lean").

Verified on the merged tree under Node 24.22.0: see the report (console-api, console-web, check.sh exit code, fwcore-build, web build).

Open / accepted limits
1. WebKit notes stay empty; screencast strips are not rows; no prefetch; task-detail preview link is a follow-up.
2. After a CI re-run the lead edits the material (run, artifact, expires) in Gen.lean; the rows need no edit unless artifact names change.
3. Restart the live console after landing. Chromium expires 2026-11-19, webkit 2026-11-20.
4. TS stand-ins: none for decisions (cache/download/route are I/O).
