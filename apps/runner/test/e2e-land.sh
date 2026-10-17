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
# `fw` only gets through the capability door: play the PreToolUse hook (cap.mjs) before each call, as agent type $1
# (main = lead, a name with "review" = reviewer, anything else = owner). `script` is never available to an agent.
as() {
  AGENT=$1; shift
  node -e '
    const [a, ...argv] = process.argv.slice(1);
    const p = { tool_name: "Bash", tool_use_id: "t" + Date.now() + Math.random(), cwd: process.cwd(), tool_input: { command: "pnpm fw " + argv.join(" ") } };
    if (a !== "main") p.agent_type = a;
    process.stdout.write(JSON.stringify(p));' "$AGENT" "$@" | node "$HERE/apps/runner/hooks/cap.mjs"
  $FW "$@"
}
screen() { # the screen runner is not an agent: it uses the web/user door
  PORT=$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(".fw-console/api.json","utf8")).port))')
  curl -fsS -X POST "http://127.0.0.1:$PORT/api/commands" -H 'content-type: application/json' \
    -d "{\"type\":\"card.screen\",\"key\":\"screen:$1\",\"actor\":\"script\",\"card\":\"A\",\"sha\":\"$1\",\"pass\":true}" > /dev/null
}
as builder card open A --owner o
as main card approve A
echo hi > "$T/wt-A/a.txt"; (cd "$T/wt-A" && $G add -- a.txt && $G commit -q -m a)
SHA=$($G rev-parse card/A)
echo "--- land before evidence must refuse"
if as main land card/A --allow '**'; then echo "FAIL: landed without evidence"; exit 1; fi
screen "$SHA"
as reviewer card review A "$SHA" --by someone-else --accept true
$FW status
echo "--- land"
export FW_LAND_CHECKS='[["true"]]'
as main land card/A --allow '**'
unset FW_LAND_CHECKS
[ "$($G rev-parse main)" = "$SHA" ] || { echo "FAIL: main did not advance"; exit 1; }
$FW status
echo "e2e-land: ok"
