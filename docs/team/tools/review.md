# review: the user's review queue

A kept look change whose visual review is pending waits for the owner in the console, in a panel called **Your reviews**.

## Where the decision lives

- `Fw.Preset.Gen.lookDecisions` is the one canonical source. Each row is structured: `decision` (kept, rejected, accepted),
  `review` (pending, done) and `material` (CI run, artifact, expiry, per engine ready or pending). The ledger text of the
  flag (`userDecision`) is checked against it by `Gen.ledgerDisagreements` in every `Gen.run` (write and `--check`): same
  date, text starts with the verdict word, says `deferred` exactly while the review is pending, names the run, artifact and expiry.
- Lean `Fw.Console.Review` (`lean/Fw/Console/Review.lean`) derives the items: a row with `review = pending` is pending (no
  text is read). One item per pending flag (`one_item_per_pending`). The review material comes from the row, through the
  op output; console-api holds no material table.
- An item is open until a review step of the flag holds the answer `keep` or `reject` (`closed_only_on_decision`); a decided
  item never reopens when the log grows (`recorded_append`, `decided_stays`). The audience is the owner's (`audience_is_owner`).
- Every reachable step state leaves the item decidable. A `Rec` carries `isOpen` (waiting or started). An open step accepts keep
  and reject (`open_accepts`). A step closed without a verdict (started then done, cancelled, answered with a word that is no
  verdict) refuses an answer (`closed_refused`) and the item needs a new step (`closed_needs_post`): Lean picks the fresh id
  `review-<flag>#<k>` (`freshId`, the first unused), and once that step is posted open keep and reject are accepted
  (`repost_accepts`, `undecided_actionable`). The id `review-<flag>#<k>` belongs to the flag's family (`inFamily_stepIdN`).
- Wire op `console.review` (`lean/Fw/Wire/Review.lean`); goldens `packages/contracts/golden/console/review.jsonl`.

## The event (design)

The decision is the user's `step.answer` on the review step (kind `choice`, options keep and reject, audience `user`). This is
the design, not a deviation: board steps are the existing canonical record of a user decision, so no new event type exists and
the reducer keeps refusing an answer to a closed step. Only the answer word is read.

The review steps are posted by console-api, never by a GET: at startup and every minute (`ensureReviewSteps`), and by
`POST /api/reviews/<flag>` before it asks Lean. The `Your steps` list shows no Start, Done or answer button for a step whose id
starts with `review-`; it links to `?tab=reviews`, so the only decision path is the panel with its confirm step.

## HTTP (console-api, `src/review/routes.ts`)

| route | meaning |
|---|---|
| `GET /api/reviews` | items from Lean with `changed` (the ledger row of the flag: candidate, look, per-engine result), `material` (from Lean, per engine), `link`; read-only, appends no event |
| `POST /api/reviews/<flag>` `{decision}` | Lean accepts or refuses (unknown flag, already decided, word not keep or reject: 422); an accepted answer is appended through the store |

The review page link is private. It is read from `.local/reviews.json` at the main checkout (`{"<flag>": "<https url>"}`,
gitignored). A missing, malformed or non-https entry gives `link: null`; the page then shows the run id and artifact name.

## Web

Tab **Reviews** with a count badge while items are open (`?tab=reviews` lands on it). Keep and Reject ask in the page
first (Yes / Cancel); the decision shows after. Compose marks the variant `look change, review pending` while its item is open.

## After a decision

The lead applies it to `Gen.lookDecisions` by hand (set `review := .done`, the verdict, and the ledger text), regenerates the
goldens, and the item leaves the queue. Not automated yet.

## Reports (review-reports)

An experiment reports its result to the user as a report, shown in the Reports section below the look-change reviews.
- **Decision (Lean `Fw.Console.Report`, op `console.report`):** a report is shown only if every number is tagged MEASURED
  with a CI run id (digits) or INFERRED with its reason, values are decimals, 2 to 4 arms with distinct names, strips are
  https, the recommendation is adopt, hold or drop. A refusal names the place (lane, metric, arm). Answers: approve, hold,
  reject, with an optional comment; a comment becomes `review.feedback` on the topic `report:<id>` (the lead gets the
  existing `review.feedback` alert). Goldens: `packages/contracts/golden/console/report.jsonl` (30 cases).
- **Post:** `pnpm -s fw review report post --file <report.json>` (example: `results/review-reports/example.json`, used in
  tests only, never posted to the live log). It posts `step.post` `report-<id>` (choice, audience user).
- **HTTP (`apps/console-api/src/review/reports.ts`):** `GET /api/reports`, `POST /api/reports` {report},
  `POST /api/reports/:id/answer` {word, comment?, cid?}. A different report under a used id is 409.
- **Storage:** `<console dir>/reports/<id>.json`; a step body is capped at 2000 characters, so the report is a side file
  and the step body is Lean's short text.
- **Web (`Reports.tsx`):** arms side by side, a metric table per lane with a tag chip per cell, layer verdicts, the strips
  link, the thread, a comment box and Approve / Hold / Reject with an in-page confirm step. Works at 390 px.
- **TS stand-in:** none for decisions. Unchecked glue: the file store and the posting calls.
- **Limits:** strips link to CI artifacts, which expire; no image hosting; the Reviews tab badge counts look-change
  reviews only (reports show their own count in the section). Each experiment task posts its own report.
