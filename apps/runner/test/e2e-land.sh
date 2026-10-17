#!/bin/sh
# Scripted end-to-end run on a throwaway repo: real console-api process, real `fw` CLI, real git.
# usage: FW_CORE_BIN=<fwcore> sh apps/runner/test/e2e-land.sh
set -eu
HERE=$(cd "$(dirname "$0")/../../.." && pwd)
FW="node $HERE/apps/runner/src/fw.ts"
T=$(mktemp -d)
G="git -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false"
trap 'kill $API 2>/dev/null || true; rm -rf "$T"' EXIT
mkdir "$T/main" && cd "$T/main"
$G init -q -b main && echo x > README && $G add -- README && $G commit -q -m init
$G worktree add -q -b card/A "$T/wt-A" main
cd "$T/main" && node "$HERE/apps/console-api/src/main.ts" > "$T/api.log" 2>&1 &
API=$!
for i in 1 2 3 4 5 6 7 8 9 10; do [ -f "$T/main/.fw-console/api.json" ] && break; sleep 0.5; done
cd "$T/main"
$FW card open A --owner o
$FW card approve A
echo hi > "$T/wt-A/a.txt"; (cd "$T/wt-A" && $G add -- a.txt && $G commit -q -m a)
SHA=$($G rev-parse card/A)
echo "--- land before evidence must refuse"
if $FW land card/A; then echo "FAIL: landed without evidence"; exit 1; fi
$FW card screen A "$SHA" --pass true
$FW card review A "$SHA" --by someone-else --accept true
$FW status
echo "--- land"
FW_LAND_CHECKS='[["true"]]' $FW land card/A
[ "$($G rev-parse main)" = "$SHA" ] || { echo "FAIL: main did not advance"; exit 1; }
$FW status
echo "e2e-land: ok"
