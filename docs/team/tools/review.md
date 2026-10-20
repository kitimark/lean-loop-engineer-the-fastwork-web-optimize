# review: the user's review queue

A kept look change whose visual review is pending waits for the owner in the console, in a panel called **Your reviews**.

## Where the decision lives

- Lean `Fw.Console.Review` (`lean/Fw/Console/Review.lean`) derives the items from `Fw.Preset.Gen.lookDecisions`: a row whose
  words contain `pending user visual review` is pending. One item per pending flag (`one_item_per_pending`).
- An item is open until the board holds the flag's step with the answer `keep` or `reject` (`closed_only_on_decision`); a
  decided item never reopens when the log grows (`recorded_append`, `decided_stays`). The audience is the owner's
  (`audience_is_owner`, same rule as `Fw.Console.Alert.audienceOf`).
- Wire op `console.review` (`lean/Fw/Wire/Review.lean`); goldens `packages/contracts/golden/console/review.jsonl`.

## The event

The decision is recorded as the user's `step.answer` on step `review-<flag>` (kind `choice`, options keep and reject,
audience `user`), which console-api posts as a `step.post` of the script when Lean says it is missing. No new event type
exists: the reducer already refuses an answer to a closed step. Only the answer word is read.

## HTTP (console-api, `src/review/routes.ts`)

| route | meaning |
|---|---|
| `GET /api/reviews` | items from Lean with `changed` (the ledger row of the flag: candidate, look, per-engine result), `material` (Chromium strips ready from CI run 39473950464, artifact `frames-chromium`, expires 2026-11-19; WebKit pending, task `earn-look-review-webkit`), `link` |
| `POST /api/reviews/<flag>` `{decision}` | Lean accepts or refuses (unknown flag, already decided, word not keep or reject: 422); an accepted answer is appended through the store |

The review page link is private. It is read from `.local/reviews.json` at the main checkout (`{"<flag>": "<https url>"}`,
gitignored). A missing, malformed or non-https entry gives `link: null`; the page then shows the run id and artifact name.

## Web

Tab **Reviews** with a count badge while items are open (`?tab=reviews` lands on it). Keep and Reject ask in the page
first (Yes / Cancel); the decision shows after. Compose marks the variant `look change, review pending` while its item is open.

## After a decision

The lead applies it to `Gen.lookDecisions` by hand (change the words so they no longer say pending), regenerates the
goldens, and the item leaves the queue. Not automated yet.
