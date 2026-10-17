# pub-prep handoff (W0 of docs/team/public-ci-brief.md)

State: branch worktree-agent-a68871c5f297d0d49, five commits (LICENSE, NOTICE, README, .gitignore, snapshot) plus this note.
Nothing pushed.

Done
- LICENSE: MIT, 2026, holder `kitimark` (the git author handle); NOTICE paragraph appended (snapshot/ stays under Fastwork's terms).
- README.md: purpose, repo map, run commands, links. Approval wording is a placeholder comment plus a draft line.
- .gitignore: `snapshot/site` tracked; `snapshot/site-pretty/` ignored (no harness reads it: gate-breakpoints, measure-chromium
  and measure-webkit use only snapshot/site; site-pretty is cited only in comments and anchors.json prose); volatile scratch
  (`.mirror/missing-local.txt`, `.mirror/chrome-profile/`, `.DS_Store`) ignored.
- snapshot/: 269 files, 30.1 MB, copied from the main checkout. Verified: `git write-tree --prefix=snapshot/site/` gives
  c15a27be... = v1Pin.trees.site in snapshot.lock.json. snapshot.lock.json holds only tree-level hashes, no per-file sha256.
  Its `files: 266` differs from 269 tracked (the lock counts differently; the tree id matches, so bytes are identical).
- snapshot/README.md: source, dates, hash method, approval placeholder.

Open items
- Owner confirms the approval wording (two APPROVAL placeholders: README.md, snapshot/README.md).
- site-pretty tree id could not be re-verified (not present in git); the site tree id is the check that matters.
- Snapshot index.html carries a third-party analytics client token (Fastwork's own page, unmodified); owner may accept or redact.
- Harness path lookup finds snapshot/site via the main checkout; after merge it also exists in every worktree.

Read first: LICENSE, README.md, snapshot/README.md.
