# review-preview-devices handoff (console-builder)

State: branch worktree-wf_dab73f82-af9-1, all work committed. Preview button on open look-change review cards.

Read first: `lean/Fw/Console/ReviewPreview.lean` (phoneMax = 600 = wLe600, Device/View/Plan/record, theorems), then
`lean/Fw/Wire/ReviewPreview.lean` (op `console.reviewPreview`), `apps/console-api/src/review/preview.ts`, `apps/console-web/src/ReviewPreview.tsx`.

Design:
- Reducer: `review.previewed {flag, device}`, user only, device desktop|phone, flag part:variant (`Fw.Console` check, mirrored in `Serve.lean`). State unchanged beyond `seen`; the log is the record.
- Lean op `console.reviewPreview` decides: open-ness of the review, arm (r | compare), search (`?fw=<key>` or none), device from the width, missing devices and ask lines.
- console-api: `POST /api/reviews/:flag/preview {view,width,done?}`: without `done` it returns the plan only; with `done` (page opened) it submits the event (key `review-previewed-<flag>-<device>`). `GET /api/reviews` items carry `preview`.
- Web: the page runs the existing `POST /api/builds/open` loop with the plan's search and arm; links use `previewBase` (page host).
- e2e-preview: target `entry-review-flag` (`?fw=nav:earn-no-transition` through the entry path on every host).

Verified locally: lean check.sh green, fwtest console-apply 49/49, console-api 709 tests, console-web 70 tests + tsc + build, e2e-preview 15 browser-free tests, ci-paths 54, land-inputs 55. Browser e2e: CI preview-e2e run 39557255514 (see Round 2).

Round 2:
- `review.previewed` is out of the public door: contracts `PublicCommand` (used by `POST /api/commands` and the agent door `stamp`) omits it; `Command`/`Event` (log, reducer) keep it. Only `mountReviewPreview` appends it from Lean's plan. Test: door returns 400.
- Blocked pop-up: `openAndRecord` records only when a window opened; otherwise the rendered link records on its click (test).
- `flag_search_exact` stays a `#guard` over `lookDecisions` (accepted limit): Lean core has no `String.splitOn` lemmas and `decide +kernel` does not reduce it.
- Previewed-on is not scoped to a review round (accepted limit: a re-review of the same flag counts old previews).
- CI: preview-e2e run 39557255514 (ci/review-preview-devices @257d0684) green on chromium and playwright-webkit; entry-review-flag 38 checks each all ok on loopback and plain-http (fw-phone.test); landed URL carries ?fw=nav:earn-no-transition.

Open:
- Original-snapshot arm is not offered (Compare is the existing original-vs-flag page).
- Open-ness is decided in the Lean op, not the reducer (a stray `review.previewed` for a decided flag is accepted but shown nowhere).
- The event is recorded after the page opened, not when the user looked.
- Slot `open-main` is shared with Builds; a flag preview and a Builds open reuse the same main build.
- The marker `{/* review-info panel */}` in ReviewCard is where the sibling review-info task renders its panel (the relayed request for CSS/JS/math explanation sections belongs to that task).
No TS stand-ins: every decision is in Lean.
