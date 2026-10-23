#!/bin/sh
# Land check `workflow-lint` (task workflow-syntax-gate, incident inc-workflow-dup-key): actionlint on the workflow files.
# usage: sh scripts/check-workflows.sh [workflow-file ...]   (default: .github/workflows/*.yml and *.yaml)
# Verdict (Lean Fw.Ci.WorkflowLint, via apps/runner/src/land-checks-workflow.ts): syntax-check and expression findings fail (exit 1),
# every other kind (shellcheck, ...) is a warning, a missing actionlint refuses (exit 3, never a pass).
# Local tier: the check is not on the remote allowlist, so it runs where fw land runs; install with `brew install actionlint`.
set -u
here=$(cd "$(dirname "$0")" && pwd)
if ! command -v actionlint >/dev/null 2>&1; then
  echo "REFUSED workflow-lint: actionlint is not installed (brew install actionlint); the workflow files were not checked"
  exit 3
fi
if [ "$#" -eq 0 ]; then
  for f in .github/workflows/*.yml .github/workflows/*.yaml; do [ -e "$f" ] && set -- "$@" "$f"; done
fi
[ "$#" -gt 0 ] || { echo "workflow-lint: no workflow files"; exit 0; }
out=$(actionlint -format '{{json .}}' "$@"); rc=$?
if [ "$rc" -gt 1 ]; then
  echo "REFUSED workflow-lint: actionlint failed to run (exit $rc)"
  exit 3
fi
printf '%s\n' "$out" | node "$here/../apps/runner/src/land-checks-workflow.ts"
vrc=$?
# TAP summary: the land lane reads the skipped count from it (a check without a summary is "unknown" and fails); no file is skipped.
printf '# tests %s\n# skipped 0\n' "$#"
exit "$vrc"
