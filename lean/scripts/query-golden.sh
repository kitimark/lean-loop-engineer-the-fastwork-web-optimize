#!/bin/sh
# Golden check for console.query (task fwcore-query-speed): two fwcore binaries answer the same query on each log, and the
# replies must be byte-identical. Prints the replay and query times of each (local debug timing, not a CI result).
# usage: sh lean/scripts/query-golden.sh <old fwcore> <new fwcore> <events.jsonl>...
# Logs: the real `.fw-console/events.jsonl` (never committed), its copies from `scale-log.mjs`, or `synth-log.mjs <n>`.
set -eu
old=$1
new=$2
shift 2
dir=$(mktemp -d)
status=0
for log in "$@"; do
  echo "log $log"
  echo "  old: $(node "$(dirname "$0")/query-time.mjs" "$old" "$log" "$dir/old.out")"
  echo "  new: $(node "$(dirname "$0")/query-time.mjs" "$new" "$log" "$dir/new.out")"
  if cmp -s "$dir/old.out" "$dir/new.out"; then echo "  identical"; else echo "  DIFFERENT"; status=1; fi
done
rm -rf "$dir"
exit $status
