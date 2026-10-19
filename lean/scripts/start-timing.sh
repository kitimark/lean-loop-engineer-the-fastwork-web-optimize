#!/bin/sh
# start-timing.sh <fwcore> [n]: CPU and wall time of n spawned fwcore calls, each with one cheap wire request
# on stdin as apps/runner sends it (task fwcore-lazy-tables). One warm-up call first, then the n calls in a subshell
# whose `times` gives their user+sys CPU; the wall is from GNU `date +%s%N` (Linux).
set -eu
b=$1; n=${2:-50}
req='{"id":1,"op":"multiplicity","k":3,"m":4,"n":4}'
echo "$req" | "$b" > /dev/null
(
  t0=$(date +%s%N)
  i=0
  while [ "$i" -lt "$n" ]; do
    echo "$req" | "$b" > /dev/null
    i=$((i + 1))
  done
  t1=$(date +%s%N)
  echo "$((t1 - t0))"
  times
) | awk -v n="$n" '
  function sec(s, a) { split(s, a, "m"); sub(/s$/, "", a[2]); return a[1] * 60 + a[2] }
  NR == 1 { ns = $1 }
  NR == 3 { u = sec($1); s = sec($2) }
  END { printf "{\"calls\":%d,\"userS\":%.3f,\"sysS\":%.3f,\"wallS\":%.3f,\"cpuMsPerCall\":%.1f,\"wallMsPerCall\":%.1f}\n", n, u, s, ns / 1e9, (u + s) * 1000 / n, ns / 1e6 / n }'
