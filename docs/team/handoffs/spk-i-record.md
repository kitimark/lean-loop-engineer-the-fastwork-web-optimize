# Handoff: spk-i-record

## State
- `research/notes/2026/10-17-spk-drafts/spk-i.md` is `status: decided`: byte-identical vectors not reached; V-i =
  per-type classes (Lean `measure.classify`, kMax 4, tMax 24, 3 runs). Index row updated in the same folder's README.
- Commit: see `git log -1` on branch `worktree-agent-ad9215bf3e253e472` (based on main 32c6336).

## Evidence used (all read-only, no local measurement)
- chromium-counts CI runs: 39029423874 (ee18c6b, 33/20/9), 39031884554 (da5d49e, 31/21/10), 39033771018 (12271fd,
  27/25/10); 62 types each. Read with `gh run view <id> --log`, job `classify`.
- Chromium lane code is the same across the three runs (git diff); image ids differ per workflow run.

## Conventions
- Claims tagged CONFIRMED / MEASURED / INFERRED with run id or file:line@commit.
- Contradictions with PLAN rev 6 and `class-policy.md` are listed in the record, not edited.

## Open items
1. Lead: choose whether stable types may be screened as totals (class-policy) or not (PLAN V-i "deterministic only").
2. Classes drift across CI workflow runs; freeze the worst class over >= 3 runs, pin the image (measure-engineer).
3. tMax 24 applies to pixel-area census types (quarantined by t alone); decide a separate tolerance.
4. `class-policy.md` §2 and PLAN §4.2 still show the Mac 28/14/8 of 50 types.
5. README count line ("8 partial (c, d, i, ...)") was not touched (task scope: the index row only).
6. `packages/measure-chromium/README.md:46` still lists `--deterministic-mode`.

## Read first
- `research/notes/2026/10-17-spk-drafts/spk-i.md`, then `class-policy.md`, then PLAN §1.2 V-i (l.152) and §4.2.
