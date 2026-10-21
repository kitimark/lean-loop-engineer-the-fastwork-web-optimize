# Review feedback: comment on a review card, the lead answers

Each card of the console's Reviews tab has a Feedback section. You write a comment (what the next research should look at),
press Send, and the comment shows in a thread under the box with its time and a status chip: `open` until the lead
answers, then `answered` with the lead's reply under it. It works on a phone (390 px, over the LAN console), and on the
plain-http LAN page (the client id is built from the clock and `Math.random`, not `crypto.randomUUID`). Texts are shown as
plain text, never as HTML.

## Who decides what

| Piece | Where | Decided by |
|---|---|---|
| Who may write each event, repeated id, unknown or answered `to`, text cap (2000 characters, not blank) | `lean/Fw/Console.lean` (`check`), `lean/Fw/Console/ReviewFeedback.lean` | Lean (the reducer) |
| What the reducer guarantees (`feedback_only_user`, `reply_only_lead`, `accepted_reply_closes_one`, ...) | `lean/Fw/Console/ReviewFeedbackLaws.lean` | Lean (proved) |
| The thread of a flag, open count, status | op `console.reviewFeedback` (`lean/Fw/Wire/ReviewFeedback.lean`), golden `packages/contracts/golden/console/reviewFeedback.jsonl` | Lean (`fwcore`) |
| Watch alert `review.feedback <flag>`: one per flag with an open comment, closed by the reply, detail = open count + newest text's first 120 characters | `lean/Fw/Obs/FeedbackAlert.lean` (pairs, theorems), `lean/Fw/Obs/Health.lean` (turns them into alerts) | Lean |
| Routes `GET /api/reviews/feedback`, `GET /api/reviews/<flag>/feedback`, `POST /api/reviews/<flag>/feedback {text, cid?}`; `feedback` on each item of `GET /api/reviews` | `apps/console-api/src/review/feedback.ts`, `review/routes.ts` | glue (hands the log's events to Lean, submits as actor `user`) |
| The lead's reply: `pnpm fw review reply --flag <f> --to <id> --text <t>`; `pnpm fw review feedback [--flag f] [--all]` prints the threads | `apps/runner/src/review.ts`, `fw.ts` | glue (argument mapping; the capability door stamps the actor) |
| Feedback section | `apps/console-web/src/ReviewFeedback.tsx`, `Reviews.tsx` | rendering only |

## Commands

- `review.feedback {flag, id, text}`: actor `user` only (the console route posts it).
- `review.feedback.reply {flag, to, text}`: actor `lead` only. `to` must name an open comment of that flag.
- Refusals are the reducer's: `actor lead may not cause review.feedback`, `actor user may not cause review.feedback.reply`, `no such feedback`,
  `feedback already answered`, `feedback id exists`, `text is empty`, `text is longer than 2000 characters`.

## Accepted limits

No notification outside the console and `fw watch`; no edit or delete; no attachments; plain text only. `fb` is not in the
`stateJson` wire (like `plan`). The zod cap on the command counts UTF-16 units, Lean counts characters; Lean stays the authority.

## TS stand-ins

None for decisions. `feedback.ts` only reads events and mints an id. The CLI only maps arguments.
