#!/bin/sh
# Host sampler for the sim-speed probe: every INTERVAL seconds (default 15) one block with uptime, vm_stat, swap,
# memory pressure, the Simulator device states and the top CPU processes (second `top` sample = instantaneous).
# Runs in the background from before `simctl create` until the job ends; the PID goes to <out>.pid and only that PID is
# ever killed (by the probe's last step). Glue only.
#   sh .github/scripts/sim-speed-sampler.sh <out.txt> [interval]
out=${1:?usage: sim-speed-sampler.sh <out.txt> [interval]}
every=${2:-15}
while :; do
  {
    echo "=== $(perl -MTime::HiRes=time -e 'printf "%d", time*1000') $(date -u +%H:%M:%S)"
    uptime
    vm_stat | head -12
    sysctl -n vm.swapusage
    memory_pressure 2>/dev/null | grep -i 'free percentage'
    xcrun simctl list devices 2>/dev/null | grep -E '\((Booted|Booting|Shutting Down)\)'
    top -l 2 -s 1 -n 10 -o cpu -stats pid,cpu,mem,command 2>/dev/null | awk '/^Processes:/{n++} n==2' | head -22
  } >> "$out" 2>&1
  sleep "$every"
done
