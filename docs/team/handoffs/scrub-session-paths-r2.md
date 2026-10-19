# scrub-session-paths-r2 handoff

Branch worktree-wf_06234e28-4d2-3. It merges the scrub-session-paths commit (1e966fc3, branch worktree-wf_c3476a53-402-1, not yet on main when this ran) and adds the r2 fixes. If main already has 1e966fc3 the merge is a no-op.
- encoded-home: `/(?:-Users-|(?<![A-Za-z0-9-])-home-)([A-Za-z0-9._]+)(?=[-\/]|$)/g`: trailing name, `/` after the name, glued `claude-501-Users-x-`, `%2F-Users-x`, `C--Users-x`. Only the lowercase `-home-` branch keeps the left-edge guard. session-path got the same lookahead.
- scanPath runs encoded-home and account-name on the file path (line 0), allowlist applies.
- FW_SCRUB_ACCOUNT counts only with FW_SCRUB_TEST=1; otherwise ignored, stderr note.
- `node scripts/scrub.mjs --self-check` prints `{"generic":[...],"account":bool}` (never the name); tests assert every GENERIC name turns the rule off. A case with FW_SCRUB_ACCOUNT unset and fake HOME/USER/LOGNAME: the name comes from the OS account (os.userInfo), the env is ignored.
- CI: apps/runner/test/scrub.test.ts spawns `node --test scripts/scrub.test.mjs` and `node scripts/test-scrub.mjs` (exit 0); the scrub files are in PACKAGE_EXTRA_READS["apps/runner"], so every land touching them runs the runner suite. The premise-tests step and its Trigger rows were dropped (one place: the land lane).
Verified: scrub.test.mjs 17 pass; test-scrub.mjs all pass; `scrub.mjs --tree --where` on the tracked tree: 0 hits for every rule; ci-paths --check and ci-paths.test.mjs (40) pass; lean/scripts/check.sh green; apps/runner pnpm test 1233 pass.
Open: Lean spec of allowed path shapes; git history not rewritten; follow-ups from review r1: right edge `(?![A-Za-z0-9._])` for quoted trailing form, glued Linux `claude-N-home-` branch. TS stand-in: all rule logic (no Lean golden).
Read first: scripts/scrub.mjs, scripts/scrub.test.mjs.

CI (round 2): run 39340537849 (land, branch ci/land-scrub-session-paths-r2, sha 1a60fc88): test/scrub.test.ts passed (2/2) in the apps/runner suite. The suite is red on one older test: scripts/circleci.test.mjs:253 asserts the fixtures do not contain the OS account name; on the CI runner that name is "runner", which the recorded logs contain. Proposed fix (blocked by the auto classifier as a security-test change, so not applied): skip the account check when the account is the generic "runner". Lead decides.
