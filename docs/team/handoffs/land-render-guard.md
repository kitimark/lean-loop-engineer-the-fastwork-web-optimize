# land-render-guard handoff

State: branch `worktree-wf_4db820fb-32c-1`. Round 1: code 156b2d22/4016473e, docs 9b7523b4, merge of main e561ee97.
Round 2 (review of e561ee97): merge of main 5a5874af, code ceec06e9 (sha-pinned guard and merges, prefix theorem,
trimmed extension), this handoff in the commit after it.

What it does: `fw land` (real and `--dry`) pins the branch tip as `sha` and refuses, before scope and any check, when
`main..sha` stores a blob at a media path (image/font/video/audio by extension) outside `snapshot/` not on the Lean
allowlist; a later `git rm` does not clear it. Kind `scope`, exit 12, one `REFUSED: render guard:` line. Every merge
(pre-lock commit, locked fallback, card fast-forward) takes `sha`, never the branch name.

Verified:
- Lean `lean/Fw/Land/RenderGuard.lean`: decision, parser of the `git log -z` tokens, #guard examples, theorems
  `refusal_survives_later`, `removal_keeps_refusal`, `removal_keeps_refusal_prefix` (newest-first log order),
  `allowed_never_refuses`, `snapshot_never_refuses`, `media_refuses`, `nonmedia_hit_none`, `refuses_append`.
- Op `console.landRenderGuard` in `lean/Fw/Wire/Console.lean`; golden `packages/contracts/golden/land/render-guard.jsonl`
  (20 cases, from `lean/scripts/OpsGolden.lean` via `named` in `lean/Fw/Ops/Golden.lean`).
- `apps/runner/test/land-render-guard.test.ts`: golden replay, temp repo add-then-remove (dry and real, no check ran,
  main unchanged), snapshot pass, rename out of snapshot/, merge adding a render, unreadable branch, and a render
  committed on the branch during a check (pre-lock fallback, card fast-forward) never reaching main.
- `pnpm test` in apps/runner (1617) and packages/contracts, `node --test scripts/ci-paths.test.mjs`, `lean/scripts/check.sh`.

Design choices: TS passes the raw NUL-split tokens; Lean parses them (a path that reads like a header stays a path).
Every status but `D` refuses (M/T/unknown too: fail closed). Merges are read by their first-parent diff, renames as
delete + add (`--no-renames`), so a rename out of `snapshot/` is caught.

Open items (follow-ups): content sniffing (accepted limit: extension only); the allowlist is empty because main tracks
no media outside `snapshot/` (2026-10-21); origin/main's existing history is not scanned; the ci/* push path is task
ci-push-render-guard; the work-graph row writes are the lead's.

Read first: `docs/team/tools/land.md` (section "The render guard"), then `renderGuard` in `apps/runner/src/land.ts`.
