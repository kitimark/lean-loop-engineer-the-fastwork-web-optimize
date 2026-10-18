#!/bin/sh
# Static checks of the changed files (task check-map-lean, mistake class c-late-check): every file changed against the
# merge-base with main (committed, staged, unstaged or untracked) gets the check of its kind: `node --check` for
# .mjs/.js/.cjs, a TypeScript parse for .ts/.mts/.cts, tsc for .tsx and .d.ts, lake build for Lean, a JSON/JSONL/YAML/
# sh/Python/Swift parse. The mapping and the verdict are Lean (Fw.Ops.CheckMap via fwcore ops.checkMap, ops.checkVerdict);
# scripts/checkmap.mjs only runs the argv it gets. scripts/hooks/pre-commit runs the same on the staged files.
#   sh scripts/check.sh                  changed files (fast)
#   sh scripts/check.sh --base <ref>     changed against <ref>
#   sh scripts/check.sh --all            every tracked file (~35 s)
#   sh scripts/check.sh --tracked        every tracked file has a kind (no command runs; < 1 s)
#   add --strict to fail on a missing tool (exit 127) or a missing fwcore instead of skipping
exec node "$(dirname "$0")/checkmap.mjs" "$@"
