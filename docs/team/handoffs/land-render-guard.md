# land-render-guard handoff

State: branch `worktree-wf_4db820fb-32c-1`, last commit named in the lead report (docs + handoff on top of the code commits).

What it does: `fw land` (real and `--dry`) refuses, before scope and before any check, a branch whose `main..branch`
history stores a blob at a media path (image/font/video/audio by extension) outside `snapshot/` that is not on the
Lean allowlist. A later `git rm` does not clear it. Kind `scope`, exit 12, one `REFUSED: render guard:` line.

Verified:
- Lean `lean/Fw/Land/RenderGuard.lean`: decision, parser of the `git log -z` tokens, #guard examples, theorems
  `refusal_survives_later`, `removal_keeps_refusal`, `allowed_never_refuses`, `snapshot_never_refuses`, `media_refuses`,
  `nonmedia_hit_none`, `refuses_append`.
- Op `console.landRenderGuard` in `lean/Fw/Wire/Console.lean`; golden `packages/contracts/golden/land/render-guard.jsonl`
  (19 cases, written by `lean/scripts/OpsGolden.lean` via `named` in `lean/Fw/Ops/Golden.lean`).
- `apps/runner/test/land-render-guard.test.ts`: golden replay through fwcore, temp repo add-then-remove (dry and real,
  no check ran, main unchanged), snapshot pass, rename out of snapshot/, a merge adding a render, unreadable branch.
- `pnpm test` in apps/runner (1613 tests), packages/contracts, `node --test scripts/ci-paths.test.mjs`, `lean/scripts/check.sh`.

Design choices: TS passes the raw NUL-split tokens; Lean parses them (a path that reads like a header stays a path).
Every status but `D` refuses (M/T/unknown too: fail closed). Merges are read by their first-parent diff, renames as
delete + add (`--no-renames`), so a rename out of `snapshot/` is caught.

Open items (follow-ups): content sniffing (accepted limit: extension only); the allowlist is empty because main tracks
no media outside `snapshot/` (2026-10-21); a scan of origin/main's existing history is out of scope.

Read first: `docs/team/tools/land.md` (section "The render guard"), then `renderGuard` in `apps/runner/src/land.ts`.
