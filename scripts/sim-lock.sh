#!/bin/sh
# sim-lock.sh: exclusive lock for the iOS Simulator. SHELL STAND-IN for Fw.Lease. [parallel-plan Q3]
# usage: sim-lock.sh acquire <owner> [--wait N] | release | status
# Lock dir: <main checkout>/.local/locks/sim (shared by all worktrees); files: owner, pid, at (acquire ms), start (owner start, epoch s).
# pid is the parent process ($PPID) of this script, so the lock lives as long as the caller.
# Lock events (task sup-baseline): one JSON line per acquire, release and stale recovery in <main>/.fw-console/locks.jsonl
# (FW_LOCK_EVENTS_FILE overrides, FW_LOCK_EVENTS=off or CI disables). Fields: ts (ms; whole seconds where `date` has no %N), lock, ev, kind, pid, start (epoch s,
# 0 unknown), waitMs on acquire (whole seconds: the poll loop sleeps 1 s), holdMs on release. No owner name, no paths, no arguments.
# One Simulator for both locks (task sim-first-queue): after taking the directory, acquire asks `fw slot held --kind sim`
# under the slot's state lock and gives the directory back while a slot sim holder is live; the slot in turn counts this
# directory as a Simulator holder. A failing check refuses the lock. CI has no slot, so CI skips the check.
set -eu
here=$(cd "$(dirname "$0")" && pwd -P)
main=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
lock="$main/.local/locks/sim"
alive() { kill -0 "$1" 2>/dev/null; }
# slot_sim: exit 0 when a slot sim holder is live, 1 when none, anything else when the check failed.
slot_sim() {
  [ -z "${CI:-}" ] || return 1
  FW_LOCK_EVENTS=off node "$here/../apps/runner/src/fw.ts" slot held --kind sim >/dev/null 2>&1
}
now_ms() {
  ms=$(date +%s%N 2>/dev/null) || ms=
  case "$ms" in *N|"") ms=$(( $(date +%s) * 1000 )) ;; *) ms=$((ms / 1000000)) ;; esac
  echo "$ms"
}
start_of() {
  st=$(LC_ALL=C TZ=UTC ps -o lstart= -p "$1" 2>/dev/null) || st=
  if [ -n "$st" ]; then LC_ALL=C TZ=UTC date -j -f '%a %b %e %T %Y' "$st" +%s 2>/dev/null || echo 0; else echo 0; fi
}
evfile=${FW_LOCK_EVENTS_FILE:-}
if [ -z "$evfile" ] && [ -z "${CI:-}" ]; then evfile="$main/.fw-console/locks.jsonl"; fi
if [ "${FW_LOCK_EVENTS:-on}" = off ]; then evfile=; fi
# ev <ev> <pid> <start> <ms field> <ms value>
ev() {
  [ -n "$evfile" ] || return 0
  { mkdir -p "${evfile%/*}"
    printf '{"ts":%s,"lock":"sim","ev":"%s","kind":"sim","pid":%s,"start":%s,"%s":%s}\n' "$(now_ms)" "$1" "$2" "$3" "$4" "$5" >> "$evfile"
  } 2>/dev/null || :
}
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
      rc=0; slot_sim || rc=$?
      if [ "$rc" -ne 1 ]; then
        rm -rf "$lock"
        if [ "$rc" -ne 0 ]; then echo "sim-lock: fw slot held --kind sim failed (exit $rc); lock refused" >&2; exit 1; fi
        if [ "$t" -ge "$wait" ]; then echo "sim-lock: held by a Simulator slot of fw slot (see pnpm -s fw slot status)" >&2; exit 1; fi
        sleep 1; t=$((t+1)); continue
      fi
      if [ -n "$evfile" ]; then
        s=$(start_of "$PPID"); now_ms > "$lock/at"; echo "$s" > "$lock/start"
        ev acquire "$PPID" "$s" waitMs $((t * 1000))
      fi
      echo "sim-lock: acquired by $owner (pid $PPID)"; exit 0
    fi
    opid=$(cat "$lock/pid" 2>/dev/null || true)
    if [ -n "$opid" ] && ! alive "$opid"; then
      echo "sim-lock: stale lock (owner $(cat "$lock/owner" 2>/dev/null || echo ?), pid $opid dead) recovered" >&2
      if [ -n "$evfile" ]; then
        at=$(cat "$lock/at" 2>/dev/null || true)
        [ -z "$at" ] || ev release "$opid" "$(cat "$lock/start" 2>/dev/null || echo 0)" holdMs $(( $(now_ms) - at ))
      fi
      rm -rf "$lock"; continue
    fi
    if [ "$t" -ge "$wait" ]; then
      echo "sim-lock: held by $(cat "$lock/owner" 2>/dev/null || echo ?) (pid ${opid:-?})" >&2; exit 1
    fi
    sleep 1; t=$((t+1))
  done ;;
release)
  if [ -n "$evfile" ] && [ -d "$lock" ]; then
    at=$(cat "$lock/at" 2>/dev/null || true)
    [ -z "$at" ] || ev release "$(cat "$lock/pid" 2>/dev/null || echo 0)" "$(cat "$lock/start" 2>/dev/null || echo 0)" holdMs $(( $(now_ms) - at ))
  fi
  rm -rf "$lock"; echo "sim-lock: released" ;;
status)
  if [ -d "$lock" ]; then
    opid=$(cat "$lock/pid" 2>/dev/null || true)
    if [ -n "$opid" ] && alive "$opid"; then echo "held by $(cat "$lock/owner") (pid $opid)"
    else echo "stale (pid ${opid:-none} dead)"; fi
  else echo "free"; fi ;;
*) echo "usage: sim-lock.sh acquire <owner> [--wait N] | release | status" >&2; exit 2 ;;
esac
