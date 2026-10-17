# Handoff: spk-hooks (researcher, work-graph task spk-hooks)

## State (HEAD 30fbbd8, nothing committed by me)
- Rewrote `research/notes/2026/10-17-spk-drafts/spk-c.md` (ANSWERED) and `spk-p.md` (PARTIAL, 2 of 3) as decision
  records from a spool snapshot (2,328 records, 17:24 to 19:25 +0700, Claude Code 2.1.302). Status `review`, lead signs.
- spk-c.md also holds the full hook payload audit: per-event counts and fields, coverage vs transcripts, ordering,
  drain, hook latency, spawn-guard shadow log.

## Conventions followed
- Counts and field names only; no payload values, paths or teammate names in the notes (repo is public).
- Claude Code behaviour read from the 2.1.302 binary strings; cited by grep anchor (`hook_event_name:"SubagentStop"`),
  because minified names are not stable.
- Analysis scripts lived in the session scratchpad (not committed); rerun = copy `.fw-console/spool` and count.

## Open items
- SPK-p part 2 (background-task wake): needs `emit.mjs` to keep a `background_tasks` count, then a controlled test.
- emit.mjs keeps 9 fields; proposed additions: `source`, `trigger`, `notification_type`, `background_tasks` count.
- Spawn-guard: Workflow spawns bypass it (18 of 26 starts); reason drops want/got; board does not show decisions.
- cap.mjs / actorFor: lead = no `agent_id`; refuse empty `agent_type` with an `agent_id` (forked internal agents).
- The drafts index `README.md` rows for SPK-c and SPK-p are now stale (not in my task's file list).

## Read first
`research/notes/2026/10-17-spk-drafts/spk-c.md` (audit table), then `spk-p.md`.
