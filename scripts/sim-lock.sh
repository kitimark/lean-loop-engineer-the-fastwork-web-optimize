#!/bin/sh
# sim-lock.sh: exclusive lock for the iOS Simulator. SHELL STAND-IN for Fw.Lease. [parallel-plan Q3]
# usage: sim-lock.sh acquire <owner> [--wait N] | release | status
# Lock dir: <main checkout>/.local/locks/sim (shared by all worktrees); files: owner, pid.
# pid is the parent process ($PPID) of this script, so the lock lives as long as the caller.
set -eu
main=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
lock="$main/.local/locks/sim"
alive() { kill -0 "$1" 2>/dev/null; }
cmd=${1:-status}
case "$cmd" in
acquire)
  owner=${2:?owner required}; wait=0
  if [ "${3:-}" = "--wait" ]; then wait=${4:?N required}; fi
  mkdir -p "$main/.local/locks"
  t=0
  while :; do
    if mkdir "$lock" 2>/dev/null; then
      echo "$owner" > "$lock/owner"; echo "$PPID" > "$lock/pid"
      echo "sim-lock: acquired by $owner (pid $PPID)"; exit 0
    fi
    opid=$(cat "$lock/pid" 2>/dev/null || true)
    if [ -n "$opid" ] && ! alive "$opid"; then
      echo "sim-lock: stale lock (owner $(cat "$lock/owner" 2>/dev/null || echo ?), pid $opid dead) recovered" >&2
      rm -rf "$lock"; continue
    fi
    if [ "$t" -ge "$wait" ]; then
      echo "sim-lock: held by $(cat "$lock/owner" 2>/dev/null || echo ?) (pid ${opid:-?})" >&2; exit 1
    fi
    sleep 1; t=$((t+1))
  done ;;
release) rm -rf "$lock"; echo "sim-lock: released" ;;
status)
  if [ -d "$lock" ]; then
    opid=$(cat "$lock/pid" 2>/dev/null || true)
    if [ -n "$opid" ] && alive "$opid"; then echo "held by $(cat "$lock/owner") (pid $opid)"
    else echo "stale (pid ${opid:-none} dead)"; fi
  else echo "free"; fi ;;
*) echo "usage: sim-lock.sh acquire <owner> [--wait N] | release | status" >&2; exit 2 ;;
esac
