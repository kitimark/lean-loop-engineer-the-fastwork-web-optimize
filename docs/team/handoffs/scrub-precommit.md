# scrub-precommit handoff

State: branch worktree-agent-ae92c71d7d3361685 (see git log for the commit). Work-graph task scrub-precommit, review item 8.

Files
- `scripts/scrub.mjs`: Node stdlib scanner. Default scans added lines of `git diff --cached`; `--tree` scans all tracked
  files and prints JSON counts by rule (`--where` adds file:line, never values).
- `scripts/hooks/pre-commit`: runs scrub.mjs. Enabled by `git config core.hooksPath scripts/hooks`, now set by
  `scripts/wt-prep.sh` (config is shared by all worktrees; the relative path resolves per worktree). The main checkout
  needs one `sh scripts/wt-prep.sh` or the config line once (the lead does this on landing).
- `scripts/scrub-allow.json`: allowlist, array of `{rule, path, reason}`; path is a file or a `dir/` prefix; empty
  reason is a config error (exit 2). Starts empty.
- `scripts/test-scrub.mjs`: fixtures for every rule and allow case in a temp git repo (`node scripts/test-scrub.mjs`).

Rules: email (allowed: example.com/.invalid/.org/.net, noreply@anthropic.com, `name@1.2.3`, `icon@2x.png`, `x@main.zip`),
home-path (/Users/<n>/, /home/<n>/; allowed names runner, user, you, name, me, username, Shared, example, x),
lan-ip (10/8, 172.16/12, 192.168/16), device-id (uppercase UUID, 8-16 hex UDID), secret (PRIVATE KEY block;
any path with `.fw-console/` and `secret`). snapshot/** and binary files are skipped. Output names file:line:col and rule only.

Measured: whole tracked tree 0.4 s user (0.8 s wall); staged diff scan is far less.
Whole-tree findings after two false-positive fixes: none.

Open items: hook is bypassable with `--no-verify` (no server-side check; CI could run `node scripts/scrub.mjs --tree`).
Lowercase UUIDs are not flagged on purpose (git/test ids); revisit if device ids appear in lowercase.
Read first: scripts/scrub.mjs header comment.
