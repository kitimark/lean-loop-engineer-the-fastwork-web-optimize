# scrub-session-paths handoff

State: scripts/scrub.mjs has three new rules; tests in scripts/scrub.test.mjs (node --test, 8 pass); old scripts/test-scrub.mjs still passes.
- `session-path`: `/private/tmp/claude-<digits>/-Users-<name>-` or `-home-<name>-` (also `/tmp/claude-...`).
- `encoded-home`: any `-Users-<name>-` / `-home-<name>-` not glued to a word or hyphen before it (so `nav-home-page-x` passes).
- `account-name`: `os.userInfo().username` read at run time, whole word, case-insensitive. Env `FW_SCRUB_ACCOUNT` overrides it (tests inject; empty = rule off). Names under 3 chars and generic ones (runner, root, user, admin, ubuntu, circleci, node, nobody, name, me, you) are ignored, so CI and `apps/runner` do not trip it.
- Allowlist unchanged: per rule and path with a reason. A session-path match also matches encoded-home; allow both rules for one file.

Verified: `node scripts/scrub.mjs --tree --where` on the tracked tree: 0 hits for every rule (branch based on main 9f660d9f).
Docs: docs/team/tools/land.md line 30.
Open: Lean spec of the path shapes (follow-up); git history not rewritten.
TS stand-in: all rule logic is TS, no Lean golden.
Read first: scripts/scrub.mjs top (account-name block) and scripts/scrub.test.mjs.
Incident part 2 (land-queue.ts:130 drops the exception message) is outside this task's pinned unit; not touched.
