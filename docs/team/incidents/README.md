# Tooling incidents

`ledger.json` holds one record per root cause of a team tooling incident. `pnpm fw incidents lint` checks it with
fwcore `plan.incidentLint` (`lean/Fw/Plan/Incident.lean`); it must pass (exit 0, 0 errors) before you commit a change.

## Add an incident
Append one object to `incidents` with these fields:
- `id` (`inc-<slug>`, unique), `at` (ISO time with offset), `title`, `symptom`.
- `cause`: starts with a status prefix `CONFIRMED`, `INFERRED` or `MEASURED`, then the source (code read, ps, headers).
- `evidence`: at least one `{kind, ref, note}`. Kinds:
  - `commit`: a short or full sha that is on main (`git merge-base --is-ancestor`).
  - `ci`: a GitHub Actions run id (digits).
  - `file`: a repo-relative path that exists in the checkout (not a file that lives only on an unlanded branch).
  - `event`: a seq in `.fw-console/events.jsonl` (warning: local-only, not reproducible from the public repo).
  - `proc`: a process shape (warning: not reproducible). Prefer commit, ci and file.
- `repro`: how to make it happen again. `regression`: the test or golden that keeps it fixed.
- `fix`: `{task, also?}`: work-graph task ids. Each must exist in `docs/team/work-graph.json`.
- The mistake-retro link (`research/mistakes/ledger.json`, task incident-lean-fields):
  - `leanVerdict`: `provable`, `partly` or `no` (exact, lowercase). `leanReason`: why Lean can or cannot prove it.
  - `hardening`: the work-graph task id of the Lean-backed hardening. Required for `provable` and `partly`;
    optional for `no`, but when present it must exist.
  - `empiricalCheck`: the test or CI check that covers it. Required for `no`; optional otherwise.
  - `mistakeClass` (optional): a class id of `research/mistakes/ledger.json` (`classes[].id`).
  - `mistake` (optional, not linted): the retro row id (`m…`) the incident matches.
  - Copy verdict and reason from the retro's mistake row; do not invent new ones.
- Never write a `status` field. The lint derives the status: fixed when `fix.task` and every `also` task are done,
  fixing when one of them is claimed, open otherwise.

## Rules
- The repo is public. No personal data: no emails, names, LAN IPs, device ids, and no home paths. Write
  `<scratchpad>` or `<tasks>` instead of a local directory. The pre-commit scrub refuses home paths.
- Facts come from git, the file system and the board, never from the ledger. If the console-api is down, task
  states come from the work graph file (no claims, so nothing shows as fixing).
- Errors: no evidence, an unknown kind, a malformed ref, a commit not on main, a missing file, an unknown or
  missing fix task, a blank repro or regression, a cause without a prefix, a `status` field, a duplicate id, or a
  missing or wrong Lean field (`missingLeanVerdict`, `badLeanVerdict`, `missingLeanReason`, `missingHardening`,
  `unknownHardening`, `missingEmpiricalCheck`, `unknownMistakeClass`; the detail names the field).
