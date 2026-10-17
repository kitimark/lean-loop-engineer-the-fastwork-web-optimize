#!/bin/sh
# Appends "<epoch ms> <label>" to $RUNNER_TEMP/result/marks.txt (sim-speed probe; glue only, no decision).
#   sh .github/scripts/sim-speed-mark.sh <label...>
set -eu
dir=${RUNNER_TEMP:-/tmp}/result
mkdir -p "$dir"
ms=$(perl -MTime::HiRes=time -e 'printf "%d", time*1000')
printf '%s %s\n' "$ms" "$*" >> "$dir/marks.txt"
printf 'MARK %s %s\n' "$ms" "$*"
