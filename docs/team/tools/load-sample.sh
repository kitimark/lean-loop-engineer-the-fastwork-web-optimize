#!/bin/zsh
# load-sample.sh: machine-load sampler. One JSON line per sample to <main>/.local/load/<date>.jsonl.
# usage: load-sample.sh [interval_s=10] [duration_s=14400]
# Gauges: cpu idle %, mem free %, swap used MB, CPU % and count per process kind, and cpuProbeMs
# (time of a fixed busy loop; grows under contention). load1 is NOT a gauge (MEASURED: on macOS it
# does not track CPU demand).
interval=${1:-10}; dur=${2:-14400}
main=$(cd "$(git rev-parse --git-common-dir)/.." && pwd -P)
mkdir -p "$main/.local/load"
out="$main/.local/load/$(date -u +%Y-%m-%d).jsonl"
end=$(( $(date +%s) + dur ))
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time()*1000'; }
while [ $(date +%s) -lt $end ]; do
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  idle=$(top -l 2 -n 0 -s 1 | grep "CPU usage" | tail -1 | awk '{print $7}' | tr -d '%')
  free=$(memory_pressure -Q 2>/dev/null | awk -F': ' '/free percentage/{print $2}' | tr -d '%')
  swap=$(sysctl -n vm.swapusage | awk '{gsub("M","",$6); print $6}')
  t0=$(now_ms); i=0; while [ $i -lt 20000 ]; do i=$((i+1)); done; probe=$(( $(now_ms) - t0 ))
  ps -axo pcpu=,comm= | awk -v ts="$ts" -v idle="${idle:-null}" -v free="${free:-null}" -v swap="${swap:-null}" -v probe="$probe" '
    function kind(c) {
      if (c ~ /(^|\/)(lean|lake)$/) return "lean"
      if (c ~ /(^|\/)node$/) return "node"
      if (c ~ /docker|qemu|Virtualization|vz/) return "docker"
      if (c ~ /[Ss]imulator|launchd_sim/) return "sim"
      if (c ~ /(^|\/)claude$/) return "claude"
      return ""
    }
    { k = kind($2); if (k != "") { n[k]++; c[k] += $1 } }
    END {
      printf "{\"ts\":\"%s\",\"idle\":%s,\"memFree\":%s,\"swapMB\":%s,\"cpuProbeMs\":%s", ts, idle, free, swap, probe
      split("lean node docker sim claude", ks, " ")
      for (j = 1; j <= 5; j++) { k = ks[j]; printf ",\"%s\":{\"n\":%d,\"cpu\":%.1f}", k, n[k]+0, c[k]+0 }
      print "}"
    }' >> "$out"
  sleep $interval
done
