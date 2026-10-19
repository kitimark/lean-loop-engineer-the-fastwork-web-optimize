# report-draft-3 handoff

State: draft 3 of `docs/report/v2-report.md` (builder 372e3942, lead review fixes on top; text only, no build).

Verified (review r1 accepted)
- Every new number cites a run id, commit or note; Lean names grepped at dcd3e13d (40 names declared).
- The 9-flag preset is `apps/site/src/registry/presets/v2-proved.json`; `grep PENDING` returns 0.
- Lead fixes: the WebKit phone-rotation limit is 1 cell with 2 readings (stops 1 and 3), not 2 cells; both C3 gate runs
  conclude "failure" on GitHub only because the merge job exits non-zero on WebKit "incomplete"; incident window
  22:49-23:56 +0700 (resolved 16:56Z); CI demand cited from `research/notes/2026/10-20-ci-demand.md`; gh-status slot filled.

Open slots (the lead fills them before the 11:15 freeze; an unfilled slot becomes one not-done line in §7)
- `SLOT compose-check` (§4.5): F6 verdict per part, stage and zone, with run ids.
- `SLOT people-layout-shift` (§7): boxes and shifts per width and engine, each with its cause.
- §4.6 counts: the 1832 -> 821 / 1864 -> 856 numbers include the strip (10-flag preset). 9-flag counts runs
  39292304129 / 39292310716 (swipe-v1 base / v2-proved) and 39292317241 / 39292323514 (swipe-touch-v1) were
  dispatched 2026-10-20 00:13 +0700 on ci/c3-gate (639f9475); replace or add the 9-flag row when they finish.

Conventions
- §2-§3, §4.4, §4.7 and §6.1-§6.3 are kept from draft 2. Sections moved: cost §6, not-done §7, lessons §8.
- §6.4 token totals come from a one-off script over local transcripts (no `fw usage` CLI); dollars INFERRED from list prices.
- The incident ledger has no 2026-10-19 rows; the lead's pending mistakes list goes in after C4.

Read first: §1 "Answer at C3", §4.2, §7, then `research/notes/2026/10-19-c3-decision.md`.
