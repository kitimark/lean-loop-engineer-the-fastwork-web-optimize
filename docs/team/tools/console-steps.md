# Your steps by topic, with questions the lead answers (step-threads)

The Your steps card groups the open steps for you by topic. Each group shows the topic's title, the lead's current summary
and when it was last updated. Every step and every topic has a Questions thread: you write a question in the console, the
lead sees a `step.question` alert in `fw watch`, answers with `fw step reply`, and the answer shows under your question.
Texts are plain text, never HTML. It works on a phone and on the plain-http LAN page (same box as the review cards).

## Who decides what

| Piece | Where | Decided by |
|---|---|---|
| Who may define a topic (lead, script), the title (1..120 characters, not blank) and summary (not blank, 2000) | `lean/Fw/Console.lean` (`check`), `lean/Fw/Console/Steps.lean` (`topicRefusal`) | Lean (the reducer) |
| Latest valid definition per topic, which open user steps group where, group order (open work or questions first, then the rest, then quiet topics; newer activity first) | `lean/Fw/Console/Steps.lean` (`define`, `view`, `order`; proved: cover, order is a sorted permutation, ranks) | Lean (`fwcore` op `console.stepTopics`, `lean/Fw/Wire/Steps.lean`), golden `packages/contracts/golden/console/steps-topics.jsonl` |
| Alert `step.question <step:id\|topic:id>`: one per subject with an open question, closed by the reply (`question_iff`, `question_post_opens`, `question_reply_closes`) | `lean/Fw/Obs/Health.lean`, `lean/Fw/Console/Steps.lean`; golden `packages/contracts/golden/obs/health.jsonl` | Lean (`fwcore obs.health`) |
| Threads | the review feedback machinery (`review.feedback`, `review.feedback.reply`) with the subject `step:<id>` or `topic:<id>` in `flag` | Lean (reducer, `console.reviewFeedback`) |
| Routes `GET /api/steps/topics`, `POST /api/steps/<step\|topic>/<id>/question {text, cid?}` | `apps/console-api/src/steps/threads.ts` | glue (hands the log and the board to Lean, submits the user's event) |
| CLI | `apps/runner/src/step-threads.ts`, `fw.ts` (`post --topic`) | glue (argument mapping, printing) |
| Card | `apps/console-web/src/StepThreads.tsx`, `App.tsx`, `ReviewFeedback.tsx` (`words`) | rendering only |

## Commands

- `pnpm fw step topic --id <topic> --title <text> --summary <text>`: the lead's current title and summary (`step.topic`; lead or script). Run it again to update the summary.
- `pnpm fw step post <step> --title <text> --topic <topic> ...`: a step grouped under a topic. A step with no topic, or a topic nobody defined, falls in the Other group.
- `pnpm fw step reply --id <step|topic> --to <comment id> --text <text> [--kind step|topic]`: answers one question and closes its alert. The subject (`step:<id>` or `topic:<id>`) is found from the thread that holds the comment; `--kind` only picks when a step and a topic share an id.
- `pnpm fw step questions [--all]`: the open questions on steps and topics (`--all` adds the answered ones).
- The user's question is `review.feedback {flag: "step:<id>"|"topic:<id>", id, text}` (actor `user` only), posted by the console route.
- Refusals are the reducer's, e.g. `actor user may not cause step.topic`, `title is empty`, `title is longer than 120 characters`, `no such feedback`, `feedback already answered`.

## Accepted limits

- One lead answers; plain text only; no edit or delete; no attachments.
- The alert reaches the lead through the existing `fw watch` stream (next check, every 5 min at most); no phone notification (follow-up).
- Threads exist on steps and topics only, not on other card kinds (follow-up).
- The reducer does not check that the step or topic named in a question exists (the subject is the `flag` text with a `step:` or `topic:` prefix); a question on an unknown subject shows in `fw step questions` and raises its alert, and the lead answers it as usual.
- A topic carries no state in the reducer: its definition is read from the log, the latest valid one per id wins.
- The `review.feedback` alert is for review flags only; a `step:`/`topic:` subject raises `step.question` instead (`kinds_disjoint`).
- No topics are seeded; the lead posts them.

## TS stand-ins

None for decisions. `threads.ts` reads the log and the board and mints an id; the CLI maps arguments; the card renders.
