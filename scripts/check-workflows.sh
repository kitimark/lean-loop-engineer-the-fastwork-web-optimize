#!/bin/sh
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
[ "$rc" -eq 1 ] && [ -z "$out" ] && { echo "REFUSED workflow-lint: actionlint exit 1 without findings"; exit 3; }
printf '%s\n' "$out" | node "$here/../apps/runner/src/land-checks-workflow.ts"
vrc=$?
printf '# tests %s\n# skipped 0\n' "$#"
exit "$vrc"
