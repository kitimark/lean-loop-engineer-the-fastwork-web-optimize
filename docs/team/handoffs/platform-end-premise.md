# platform-end-premise (researcher) handoff

State: branch worktree-wf_74608e93-3d6-1; note `research/notes/2026/10-2x-platform-end-premise.md` written and committed.
Read-only on the site and the ledger; the lead updates ledger row n=42 from the note's last section.

Verified (CONFIRMED by source, no measurement)
- Answer 1: the original (snapshot/site @94928077) ends at the platform card at every width. Page template
  `nodes/2.DyWL8TcE.js` byte 364269: main = hero, people, pain, commission, platform (GM at 364831) with no width
  condition; after main only the closed `<dialog>` (display:none, position:fixed, `DialogHeader.Qcgwm6ST.css` 16223).
  Section padding 0 at all widths (`2.gBuqKVzi.css` 94996, 144953); the card is its only child (343776). No footer.
- Answer 2: WebKit@862f17d `Page.cpp:2298-2300` runs `evaluateMediaQueriesAndReportChanges` -> `Document.cpp:5861-5867`
  -> `MediaQueryMatcher.cpp:95-116` -> `MediaQueryList.cpp:108` dispatches `change` synchronously; this comes before rAF
  (2329) and layout (2337, 2399).

Open items
- Follow-up: rubber-band overscroll at the page end (iOS scrollY past the maximum, macOS bounce) is the only path where
  the original computes a nonzero shrink (INFERRED, unmeasured).
- Chromium's equivalent of P1 was not checked (not in the unit).

Conventions: the snapshot has no tracked pretty copy, so cite byte offsets (`grep -ob`) into the minified files.
Read first: the note, then `research/notes/2026/10-2x-platform-shrink-mq.md`.
